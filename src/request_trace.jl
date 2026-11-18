# --- Per-request compute traces: `serve(; compute_trace)` --------------------
#
# The DynamicObjects compute trace (`with_compute_trace`, DynamicObjects ≥
# 0.5.0) of one HTTP request: which properties it read, which reads were served
# from memory, which computed or ran `@fresh`, how long each took, and which
# invalidations dropped values (user decision `1wbhyfs`, todo `09gck4a`).
#
# - `serve(; compute_trace=:requested)` traces a request that carries the
#   `?__trace` flag or `X-HTMXO-Trace: 1`; `:all` traces every request; `false`
#   (the default) traces nothing and ignores both. A full page traced on request
#   carries a script that adds the header to every same-origin htmx request it
#   makes, so its fragments, lazy loads and polls are traced too.
# - `_trace_requests` runs the request inside a `with_compute_trace` scope, just
#   inside the runtime tracker. The trace stays open until the request and every
#   operation it started (`_spawn_operation` → `_traced_operation`) have ended:
#   an `:auto` route answers with a poller before its slow part runs, and
#   DynamicObjects records only while a scope of the trace is active.
# - Each traced response carries `X-HTMXO-Trace-Id` and a `Server-Timing`
#   header (the slowest properties so far). A closed trace goes to the runtime
#   tracker's bounded ring (`trace_limit`) that `RuntimeRoutes` lists, and
#   writes one log line (`Info`, `_group=:trace`).
# - Only the per-property table and the invalidation log are kept (`events=0`),
#   never read arguments: like the request ledger, a trace holds no request
#   data beyond the redacted target.
# - Not kept: the dashboard's own requests, a follow-up operation poll that
#   computed nothing (it only waited, or read memory: its operation's work is in
#   the trace of the request that started it), and under `:all` a request that
#   read no property at all (static files).

# The traced request whose scope the current task runs in, with the tracker its
# trace is recorded on.
const _REQUEST_TRACE =
    ScopedValues.ScopedValue{Union{Nothing,Tuple{RequestTrace,RuntimeTracker}}}(nothing)

const _COMPUTE_TRACE_MODES = (false, :requested, :all)

function _check_compute_trace(mode)
    mode in _COMPUTE_TRACE_MODES || throw(ArgumentError(
        "`compute_trace` must be false, :requested or :all, got $(repr(mode))"))
    mode
end

const _TRACE_HEADER = "X-HTMXO-Trace"
const _TRACE_FLAG = "__trace"

_trace_header_on(value::AbstractString) =
    !(lowercase(strip(value)) in ("", "0", "false", "no", "off"))

# Whether `req` asked for its trace under `serve(; compute_trace=:requested)`.
function _trace_asked(req::HTTP.Request)
    _trace_header_on(HTTP.header(req, _TRACE_HEADER, "")) && return true
    occursin(_TRACE_FLAG, req.target) || return false
    haskey(something(_runtime_guarded(() -> queryparams(req), "trace flag"),
                     Dict{String,String}()), _TRACE_FLAG)
end

_trace_wanted(req::HTTP.Request, mode::Symbol) = mode === :all || _trace_asked(req)

"""
    _trace_requests(handler, mode, tracker) -> handler

`serve(; compute_trace=mode)`'s middleware: runs a traced request inside a
DynamicObjects compute trace recorded on `tracker`, and stamps its response
with `X-HTMXO-Trace-Id` and `Server-Timing`.
"""
function _trace_requests(handler, mode::Symbol, tracker::RuntimeTracker)
    function (req::HTTP.Request)
        _trace_wanted(req, mode) || return handler(req)
        rt = _runtime_guarded(() -> _trace_open!(tracker, req, mode), "trace start")
        rt isa RequestTrace || return handler(req)
        req.context[:htmxo_trace] = rt
        status = 500
        try
            response = ScopedValues.with(_REQUEST_TRACE => (rt, tracker)) do
                with_compute_trace(() -> handler(req), rt.trace)
            end
            status = response isa HTTP.Response ? Int(response.status) : 200
            response isa HTTP.Response || return response
            stamped = _runtime_guarded("trace headers") do
                _trace_response(req, response, rt, mode)
            end
            return something(stamped, response)
        catch err
            err isa _WebSocketClosed && (status = 101)
            rethrow()
        finally
            _runtime_guarded("trace finish") do
                _trace_responded!(tracker, rt, status)
                _trace_close!(tracker, rt)
            end
        end
    end
end

function _trace_open!(tracker::RuntimeTracker, req::HTTP.Request, mode::Symbol)
    target = _runtime_redact_target(req.target)
    poll = occursin("__htmxo_poll=1", req.target)
    lock(tracker.lock) do
        tracker.next_trace += 1
        rt = RequestTrace(tracker.next_trace, String(req.method), target, poll, 0,
            time(), time_ns(), NaN, NaN, ComputeTrace(), 1, false, mode !== :all)
        tracker.open_traces[rt.id] = rt
        rt
    end
end

function _trace_responded!(tracker::RuntimeTracker, rt::RequestTrace, status::Integer)
    elapsed = _runtime_elapsed(rt.started_ns)
    lock(tracker.lock) do
        rt.status = status
        rt.response_s = elapsed
    end
    nothing
end

# One scope of `rt` ended (the request's, or an operation's). The last one
# closes the trace: it moves to the ring, or is dropped (see the file header).
function _trace_close!(tracker::RuntimeTracker, rt::RequestTrace)
    finished_ns = time_ns()
    closed = lock(tracker.lock) do
        rt.open -= 1
        rt.open > 0 && return false
        rt.duration = _runtime_elapsed(rt.started_ns, finished_ns)
        delete!(tracker.open_traces, rt.id)
        _trace_kept(rt) || return false
        if tracker.trace_limit > 0
            push!(tracker.traces, rt)
            _runtime_trim!(tracker.traces, tracker.trace_limit)
        end
        true
    end
    closed && _trace_log(rt)
    nothing
end

function _trace_kept(rt::RequestTrace)
    rt.hidden && return false
    rows = compute_trace_rows(rt.trace)
    rt.poll && return any(r -> r.computed + r.fresh + r.disk + r.errors > 0, rows)
    rt.keep_empty || !isempty(rows)
end

# `_runtime_hide_request!`: the dashboard's own requests are not kept.
function _trace_hide!(req)
    req isa HTTP.Request || return nothing
    rt = get(req.context, :htmxo_trace, nothing)
    rt isa RequestTrace && (rt.hidden = true)
    nothing
end

"""
    _traced_operation(f) -> f′

Every background start (`_spawn_operation`) made while a request is traced
keeps that request's trace open until it ends, and records into it.
"""
function _traced_operation(f)
    scope = _REQUEST_TRACE[]
    scope === nothing && return f
    rt, tracker = scope
    # A task that outlived every scope of the trace (it inherited the scoped
    # value) must not reopen a trace that has already closed.
    lock(() -> rt.open > 0 && (rt.open += 1; true), tracker.lock) || return f
    return function ()
        try
            with_compute_trace(f, rt.trace)
        finally
            _runtime_guarded(() -> _trace_close!(tracker, rt), "trace finish")
        end
    end
end

# --- the response: headers, and the page script ------------------------------

# A NEW response: a route may return a response it keeps (see
# `_compress_buffered`), which must not carry one request's trace id into the
# next.
function _trace_response(req::HTTP.Request, response::HTTP.Response,
        rt::RequestTrace, mode::Symbol)
    rt.hidden && return response
    _runtime_request_kind(req) in (:websocket, :sse) && return response
    headers = Pair{String,String}[String(k) => String(v) for (k, v) in response.headers]
    push!(headers, "X-HTMXO-Trace-Id" => string(rt.id))
    timing = _server_timing(compute_trace_rows(rt.trace))
    isempty(timing) || push!(headers, "Server-Timing" => timing)
    body = response.body
    if mode === :requested && _full_page_response(req, response)
        page = _inject_after_body(body, _TRACE_PAGE_SCRIPT)
        if page !== nothing
            body = page
            filter!(p -> lowercase(first(p)) != "content-length", headers)
        end
    end
    HTTP.Response(response.status, headers, body; request=response.request)
end

const _SERVER_TIMING_ROWS = 10

# `Server-Timing` (W3C Server Timing): the slowest properties so far, one
# metric each, with their own time (`self_s + hit_s`) in milliseconds and their
# label and counts as the description; browser developer tools show it in the
# request's timing view.
function _server_timing(rows)
    metrics = String[]
    for (i, r) in enumerate(rows)
        i > _SERVER_TIMING_ROWS && break
        label = _trace_label(r)
        push!(metrics, string(_server_timing_token(label), ";dur=",
            round(1000 * (r.self_s + r.hit_s); digits=3), ";desc=",
            _http_quoted(string(label, " (", _trace_counts(r), ")"))))
    end
    join(metrics, ", ")
end

# A metric name is an HTTP token: other characters (a type parameter's braces,
# a symbol's colon) become `_`.
_server_timing_token(label::AbstractString) =
    replace(label, r"[^A-Za-z0-9!#$%&'*+.^_`|~-]" => "_")

_http_quoted(text::AbstractString) =
    string('"', replace(text, '\\' => "\\\\", '"' => "\\\"", r"[\r\n]" => " "), '"')

# A full page — a navigation's HTML answer, not a fragment swap — which can
# carry a page script (a traced page's, development mode's).
_full_page_response(req::HTTP.Request, response::HTTP.Response) =
    !_hx_partial_swap(req) && response.status == 200 &&
    occursin("text/html", lowercase(HTTP.header(response, "Content-Type", "")))

# The script a traced page carries: every same-origin htmx request it makes
# asks for its trace (`htmx:configRequest` bubbles to the document; the
# listener does not need htmx loaded yet).
const _TRACE_PAGE_SCRIPT = """<script data-htmxo-trace>document.addEventListener("htmx:configRequest",function(e){try{if(new URL(e.detail.path,location.href).origin===location.origin){e.detail.headers["$(_TRACE_HEADER)"]="1"}}catch(_){}});</script>"""

# `body` with `snippet` after its `<body …>` tag, or `nothing` when the body
# is not held in memory (a stream) or has no `<body>` tag.
function _inject_after_body(body, snippet::AbstractString)
    bytes = _buffered_bytes(body)
    bytes === nothing && return nothing
    text = String(copy(bytes))
    m = match(r"<body(?:\s[^>]*)?>"i, text)
    m === nothing && return nothing
    stop = m.offset + ncodeunits(m.match) - 1
    string(SubString(text, 1, stop), snippet,
           SubString(text, nextind(text, stop)))
end

# --- labels and the log line --------------------------------------------------

_trace_type_label(T::DataType) = isempty(T.parameters) ? string(nameof(T)) :
    string(nameof(T), "{", join(map(repr, T.parameters), ", "), "}")
_trace_type_label(T) = string(T)
_trace_label(r) = string(_trace_type_label(r.type), ".", r.property)

const _TRACE_COUNT_COLUMNS = (:computed, :fresh, :disk, :hits, :waits, :pending, :errors)

# What a row's reads did, e.g. "28 fresh" or "1 computed, 12 hits".
function _trace_counts(r)
    parts = [string(getfield(r, c), " ", c) for c in _TRACE_COUNT_COLUMNS
             if getfield(r, c) != 0]
    isempty(parts) ? string(r.calls, " reads") : join(parts, ", ")
end

# Seconds with three decimals, as DynamicObjects' own trace table prints them.
function _trace_seconds(x::Real)
    isfinite(x) || return "–"
    ms = round(Int, 1000 * x)
    string(div(ms, 1000), ".", lpad(rem(ms, 1000), 3, '0'))
end

const _TRACE_LOG_ROWS = 3

"""
    _trace_log_line(rt) -> String

`trace 17 GET /review?x=1 200 1.842s: AppData.load_transaction_state 1.512s (28 fresh), …`
— the three properties with the most own time.
"""
function _trace_log_line(rt::RequestTrace)
    rows = compute_trace_rows(rt.trace)
    slowest = isempty(rows) ? "no property reads" : join((string(_trace_label(r), " ",
        _trace_seconds(r.self_s + r.hit_s), "s (", _trace_counts(r), ")")
        for r in Iterators.take(rows, _TRACE_LOG_ROWS)), ", ")
    string(_access_log_timestamp(), " - trace ", rt.id, " ", rt.method, " ", rt.target,
           " ", rt.status, " ", _trace_seconds(rt.duration), "s: ", slowest,
           length(rows) > _TRACE_LOG_ROWS ? ", …" : "")
end

function _trace_log(rt::RequestTrace)
    try
        @info _trace_log_line(rt) _group=:trace
    catch err
        @warn "Writing a request trace's log line failed" exception=(err, catch_backtrace()) maxlog=1
    end
    nothing
end

# --- reading the ledger ---------------------------------------------------------

"""
    request_traces(tracker=runtime_tracker()) -> Vector{RequestTrace}

The tracker's request traces (see [`serve`](@ref)'s `compute_trace`), newest
first: those still open (the request, or an operation it started, still runs),
then the latest closed ones the tracker keeps (`trace_limit`).
"""
function request_traces(tracker::RuntimeTracker=runtime_tracker())
    lock(tracker.lock) do
        open = sort!([rt for rt in values(tracker.open_traces) if !rt.hidden];
                     by=rt -> -rt.id)
        vcat(open, reverse(tracker.traces))
    end
end

"""
    request_trace(id, tracker=runtime_tracker()) -> Union{RequestTrace,Nothing}

The request trace numbered `id` (its response's `X-HTMXO-Trace-Id`), or
`nothing` when the tracker no longer keeps it.
"""
function request_trace(id::Integer, tracker::RuntimeTracker=runtime_tracker())
    lock(tracker.lock) do
        rt = get(tracker.open_traces, id, nothing)
        rt isa RequestTrace && !rt.hidden && return rt
        i = findlast(t -> t.id == id, tracker.traces)
        i === nothing ? nothing : tracker.traces[i]
    end
end
