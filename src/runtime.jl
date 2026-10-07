# --- Runtime tracking: requests and long-running operations -----------------
#
# Two process-local ledgers behind the `RuntimeRoutes` dev dashboard:
#
# - requests: every request that passes through `track_requests` — in flight
#   (with a ticking age) and a bounded history of finished ones with their
#   handling time, status, matched route and execution mode;
# - jobs: every `@queued` (heavy) execution that outlives the `:auto` grace
#   period — polled, deferred direct-page loads and blocking/inline ones
#   alike — plus
#   work reported through `track_job!` (hand-rolled Treebars pollers, app
#   tasks): queued/running, and a bounded history of finished ones with wall
#   time, outcome and the frozen progress tree.
#
# Neither ledger depends on the server. `track_requests` is a plain HTTP.jl
# middleware (`handler -> req -> response`), so any server that composes
# HTTP.jl handlers can install it; `serve` puts it in its own request pipeline.
# Jobs are recorded by HTMXObjects' own operation layer (`_execute_operation`
# registers every `@queued` execution at start, `_retain_operation!` hands
# polled ones to a watcher), not by the server. Ordinary operations are only
# requests.
#
# Known limits: the ledgers are process-local and in memory — empty after a
# restart, and per process in a multi-process deployment. An operation that
# finishes within the grace period is a request, not a job. A job has no
# progress tree when DynamicObjects produced no substatus for it (an uncached
# `@fresh` route) or Treebars is not loaded.
#
# The ledgers are bounded and hold no request headers, cookies or bodies, and
# request targets are redacted before storage: HTMXObjects' operation and
# page-load tokens are bearer capabilities (see `_operation_polls`), so their
# values — and any parameter whose name looks like a credential — never reach a
# record.

"""
    RuntimeRequest

One tracked HTTP request. `duration` is `NaN` and `status` is `0` while the
request is in flight. `kind` is `:page`, `:htmx`, `:poll` (a follow-up
operation poll), `:websocket` or `:sse`; the last two stay in flight for the
life of the connection. `route` is the matched route pattern (`"GET /foo/{1}"`),
`mode` the operation transport HTMXObjects chose (`:blocking`, `:polling`,
`:page_load`, `:poll` for a follow-up poll, `:preload` for a speculative
request to a `@preload` route, `:none` for non-operation requests), and `job` the id of the [`RuntimeJob`](@ref) the request started or
polled (`0` for none). `target` is the redacted path and query.
"""
mutable struct RuntimeRequest
    id::Int
    method::String
    target::String
    path::String
    kind::Symbol
    route::String
    mode::Symbol
    job::Int
    threadpool::Symbol
    started_at::Float64
    started_ns::UInt64
    duration::Float64
    status::Int
    error::String
    hidden::Bool
end

"""
    RuntimeJob

One job: a `@queued` route execution that outlived the `:auto` grace period
(whether it continued in the background while clients polled it or answered
inline), or work reported through [`track_job!`](@ref). `state` is `:queued`, `:running`,
`:done` or `:failed`; `duration` is `NaN` until it finishes. `requests` counts
the requests that started or joined the same computation, `polls` the
follow-up requests it answered. `result_url` is the externally visible target
of an originating GET whose query needed no token/credential redaction (empty
otherwise). `progress` is the job's progress node (a Treebars tree when
Treebars is loaded), kept after completion so history shows per-phase timings.
`scope` is the root-provider scope of the operation that started it
(`:request`, `:session`, `:job`, or `:none` outside any operation); the provider
key itself is only kept as a salted in-process digest, used to match
[`jobs_board`](@ref)'s `mine` filter. `position` is the queue position of a
`:queued` job (`0` otherwise); a job whose computation waits in the job queue
([`configure_job_queue!`](@ref)) is listed as `:queued` with its current
position.
"""
mutable struct RuntimeJob
    id::Int
    label::String
    route::String
    target::String
    result_url::String
    state::Symbol
    started_at::Float64
    started_ns::UInt64
    duration::Float64
    error::String
    requests::Int
    polls::Int
    last_seen_ns::UInt64
    handle::Any
    progress::Any
    scope::Symbol
    session::UInt
    position::Int
    hidden::Bool
    watched::Bool
    source::Any
end

"""
    RuntimeTracker(; history_limit=1000, job_history_limit=100, record_polls=false)

Process-local ledger of tracked requests and long-running jobs. The package
keeps one global instance ([`runtime_tracker`](@ref)); separate instances are
useful for tests or for tracking a second server independently.

- `history_limit` — finished requests kept (oldest dropped first).
- `job_history_limit` — finished jobs kept.
- `record_polls` — keep follow-up operation polls in the request history.
  Off by default: a live poller issues a request every `poll_interval`, which
  would otherwise crowd everything else out. Polls are still counted on their
  job either way.
- `enabled` — mutable switch; a disabled tracker passes requests straight
  through.
"""
mutable struct RuntimeTracker
    lock::ReentrantLock
    enabled::Bool
    history_limit::Int
    job_history_limit::Int
    record_polls::Bool
    next_request::Int
    next_job::Int
    inflight::Dict{Int,RuntimeRequest}
    history::Vector{RuntimeRequest}
    running::Dict{Int,RuntimeJob}
    finished::Vector{RuntimeJob}
    by_handle::Dict{Any,Int}
    started_at::Float64
    total_requests::Int
    total_jobs::Int
end

function RuntimeTracker(; history_limit::Integer=1000,
        job_history_limit::Integer=100, record_polls::Bool=false,
        enabled::Bool=true)
    history_limit >= 0 || throw(ArgumentError("history_limit must be non-negative"))
    job_history_limit >= 0 || throw(ArgumentError("job_history_limit must be non-negative"))
    RuntimeTracker(ReentrantLock(), enabled, history_limit, job_history_limit,
        record_polls, 0, 0, Dict{Int,RuntimeRequest}(), RuntimeRequest[],
        Dict{Int,RuntimeJob}(), RuntimeJob[], Dict{Any,Int}(), time(), 0, 0)
end

const _RUNTIME_TRACKER = RuntimeTracker()

"""
    runtime_tracker() -> RuntimeTracker

The process-global [`RuntimeTracker`](@ref) that [`serve`](@ref)'s default
middleware and HTMXObjects' operation layer record into, and that
[`RuntimeRoutes`](@ref) displays by default.
"""
runtime_tracker() = _RUNTIME_TRACKER

"""
    configure_runtime!(tracker=runtime_tracker(); enabled, history_limit,
                       job_history_limit, record_polls) -> tracker

Adjust a tracker in place. Omitted settings are unchanged. Shrinking a limit
trims the corresponding history immediately.
"""
function configure_runtime!(tracker::RuntimeTracker=runtime_tracker();
        enabled=nothing, history_limit=nothing, job_history_limit=nothing,
        record_polls=nothing)
    lock(tracker.lock) do
        enabled === nothing || (tracker.enabled = enabled)
        record_polls === nothing || (tracker.record_polls = record_polls)
        if history_limit !== nothing
            history_limit >= 0 || throw(ArgumentError("history_limit must be non-negative"))
            tracker.history_limit = history_limit
        end
        if job_history_limit !== nothing
            job_history_limit >= 0 || throw(ArgumentError("job_history_limit must be non-negative"))
            tracker.job_history_limit = job_history_limit
        end
        _runtime_trim!(tracker.history, tracker.history_limit)
        _runtime_trim!(tracker.finished, tracker.job_history_limit)
    end
    tracker
end

"""
    clear_runtime_history!(tracker=runtime_tracker()) -> tracker

Forget finished requests and jobs. In-flight requests and running jobs are
kept — they are still happening.
"""
function clear_runtime_history!(tracker::RuntimeTracker=runtime_tracker())
    lock(tracker.lock) do
        empty!(tracker.history)
        empty!(tracker.finished)
    end
    tracker
end

function _runtime_trim!(entries::Vector, limit::Int)
    excess = length(entries) - limit
    excess > 0 && deleteat!(entries, 1:excess)
    entries
end

_runtime_elapsed(started_ns::UInt64, now_ns::UInt64=time_ns()) =
    now_ns >= started_ns ? (now_ns - started_ns) / 1.0e9 : 0.0

# --- target redaction ------------------------------------------------------

# Query parameters whose VALUES are bearer capabilities or credentials. The
# HTMXObjects markers are exact; everything else matches by name.
const _RUNTIME_REDACTED_PARAMS = ("__htmxo_operation", "__htmxo_page_load")
const _RUNTIME_SENSITIVE_PARAM =
    r"token|secret|passw|api_?key|auth|session|cookie|csrf|signature"i

function _runtime_redacted_param(name::AbstractString)
    name in _RUNTIME_REDACTED_PARAMS && return true
    decoded = try HTTP.URIs.unescapeuri(name) catch; name end
    decoded in _RUNTIME_REDACTED_PARAMS || occursin(_RUNTIME_SENSITIVE_PARAM, decoded)
end

"""
    _runtime_redact_target(target) -> String

Request target with the values of bearer/credential query parameters replaced
by `…`. Everything else — path, parameter names, ordinary values — is kept, so
the dev view still shows which arguments a request carried.
"""
function _runtime_redact_target(target::AbstractString)
    q = findfirst('?', target)
    q === nothing && return String(target)
    path = target[1:prevind(target, q)]
    query = target[nextind(target, q):end]
    isempty(query) && return String(target)
    parts = map(split(query, '&')) do part
        eq = findfirst('=', part)
        eq === nothing && return part
        name = part[1:prevind(part, eq)]
        _runtime_redacted_param(name) ? string(name, "=…") : part
    end
    string(path, '?', join(parts, '&'))
end

_runtime_path(target::AbstractString) = let q = findfirst('?', target)
    q === nothing ? String(target) : String(target[1:prevind(target, q)])
end

function _runtime_request_kind(req::HTTP.Request)
    HTTP.WebSockets.isupgrade(req) && return :websocket
    occursin("text/event-stream", HTTP.header(req, "Accept", "")) && return :sse
    occursin("__htmxo_poll=1", req.target) && return :poll
    is_htmx(req) && return :htmx
    :page
end

function _runtime_error_summary(err)
    err = unwrap_error(err)
    text = try sprint(showerror, err) catch; string(typeof(err)) end
    line = strip(first(split(text, '\n')))
    length(line) > 300 ? first(line, 299) * "…" : String(line)
end

# Bookkeeping must never take a request down with it: a failure in the ledger
# is logged (once per process) and serving carries on untracked.
function _runtime_guarded(f, what::AbstractString)
    try
        f()
    catch err
        @warn "HTMXObjects runtime tracking failed; continuing untracked" what exception=(err, catch_backtrace()) maxlog=1
        nothing
    end
end

# --- request middleware ----------------------------------------------------

const _RUNTIME_REQUEST_KEY = :htmxo_runtime_request
const _RUNTIME_TRACKER_KEY = :htmxo_runtime_tracker

"""
    track_requests(handler; tracker=runtime_tracker()) -> handler

HTTP.jl middleware that records every request in `tracker`: registered as in
flight on entry, moved to the bounded history with its status and handling time
on exit (including when `handler` throws, recorded as status 500).

It is a plain `HTTP.Request -> HTTP.Response` wrapper with no server-specific
API, so it composes with any HTTP.jl handler stack:

```julia
HTTP.serve(track_requests(router), host, port)   # any HTTP.jl request handler
```

[`serve`](@ref) already installs it as its outermost middleware
(`runtime_tracking=false` opts out), so do not add it there a second time.
Downstream HTMXObjects code annotates the live record — matched route,
operation mode, job id — through `req.context`.
"""
function track_requests(handler; tracker::RuntimeTracker=runtime_tracker())
    function (req::HTTP.Request)
        tracker.enabled || return handler(req)
        record = _runtime_guarded("request start") do
            _runtime_request_start!(tracker, req)
        end
        record isa RuntimeRequest || return handler(req)
        req.context[_RUNTIME_REQUEST_KEY] = record
        req.context[_RUNTIME_TRACKER_KEY] = tracker
        status = 500
        failure = ""
        try
            response = handler(req)
            status = response isa HTTP.Response ? Int(response.status) :
                     record.kind === :websocket ? 101 : 200
            return response
        catch err
            # A `@ws` route unwinds with `_WebSocketClosed` once its session
            # ends: the upgrade succeeded, it did not fail.
            if err isa _WebSocketClosed
                status = 101
            else
                failure = something(_runtime_guarded(
                    () -> _runtime_error_summary(err), "error summary"), "")
            end
            rethrow()
        finally
            _runtime_guarded("request finish") do
                _runtime_request_finish!(tracker, record, status, failure)
            end
        end
    end
end

function _runtime_request_start!(tracker::RuntimeTracker, req::HTTP.Request)
    target = _runtime_redact_target(req.target)
    kind = _runtime_request_kind(req)
    pool = try Threads.threadpool() catch; :default end
    lock(tracker.lock) do
        tracker.next_request += 1
        tracker.total_requests += 1
        record = RuntimeRequest(tracker.next_request, String(req.method),
            target, _runtime_path(target), kind, "", :none, 0, pool,
            time(), time_ns(), NaN, 0, "",
            kind === :poll && !tracker.record_polls)
        tracker.inflight[record.id] = record
        record
    end
end

function _runtime_request_finish!(tracker::RuntimeTracker,
        record::RuntimeRequest, status::Integer, failure::AbstractString)
    finished_ns = time_ns()
    lock(tracker.lock) do
        record.duration = _runtime_elapsed(record.started_ns, finished_ns)
        record.status = status
        isempty(failure) || (record.error = failure)
        delete!(tracker.inflight, record.id)
        if !record.hidden && tracker.history_limit > 0
            push!(tracker.history, record)
            _runtime_trim!(tracker.history, tracker.history_limit)
        end
    end
    nothing
end

_runtime_record(req::HTTP.Request) =
    get(req.context, _RUNTIME_REQUEST_KEY, nothing)
_runtime_record(_) = nothing

# The tracker whose middleware saw a request travels with it, so the operation
# layer annotates and records jobs into the same ledger. An untracked request
# (in-process `dispatch`, recording, tests driving the router directly) falls
# back to the global tracker for jobs and annotates nothing.
_runtime_tracker_of(req::HTTP.Request) =
    get(req.context, _RUNTIME_TRACKER_KEY, runtime_tracker())::RuntimeTracker
_runtime_tracker_of(_) = runtime_tracker()

# Records are plain data handed out in snapshots; every mutation happens under
# the owning tracker's lock.
function _runtime_annotate!(f, req)
    record = _runtime_record(req)
    record isa RuntimeRequest || return nothing
    tracker = _runtime_tracker_of(req)
    _runtime_guarded("request annotation") do
        lock(tracker.lock) do
            f(record)
        end
    end
    nothing
end

"""
    _runtime_note_route!(req, method, path)

Record the route pattern a request matched. Called from `_register_handler`,
HTMXObjects' single route-registration chokepoint.
"""
_runtime_note_route!(req, method, path) =
    _runtime_annotate!(record -> (record.route = string(method, ' ', path)), req)

"""
    _runtime_hide_request!(req)

Exclude a request from the history — used by the dashboard's own routes so
watching the server does not bury what it is watching. The job the request
started, if any, is hidden with it.
"""
_runtime_hide_request!(req) = _runtime_annotate!(req) do record
    record.hidden = true
    job = get(_runtime_tracker_of(req).running, record.job, nothing)
    job isa RuntimeJob && (job.hidden = true)
end

_runtime_note_mode!(req, mode::Symbol) =
    _runtime_annotate!(record -> (record.mode = mode), req)

# HTMX requests receive route errors as 200 fragments (so the error article
# swaps in), which would make a failed request look healthy in the ledger.
# `_route_error_response` notes the failure and its recorded error id instead.
_runtime_note_error!(req, err, uid) = _runtime_annotate!(req) do record
    record.error = string(_runtime_error_summary(err), " [error ", uid, "]")
end

# --- sessions --------------------------------------------------------------

# Which session a job belongs to, for `jobs_board(; mine=req)`: the scope of
# the root provider that served the operation, and a digest of its key. The
# key itself (often a session cookie value) is never stored; the digest is
# salted per process and never leaves it — it is not part of any row.
const _RUNTIME_SESSION_KEY = :htmxo_runtime_session
const _RUNTIME_SESSION_SALT = Ref{UInt}(0)
const _RUNTIME_NO_SESSION = (:none, UInt(0))

function _runtime_session_salt()
    salt = _RUNTIME_SESSION_SALT[]
    salt == 0 || return salt
    _RUNTIME_SESSION_SALT[] = rand(Random.RandomDevice(), UInt)
end

# A `:request`-scoped operation has no session beyond its own request, so it
# never matches `mine`.
function _runtime_session(context)
    context isa OperationContext || return _RUNTIME_NO_SESSION
    context.scope === :request && return (:request, UInt(0))
    (context.scope, hash((context.scope, context.key), _runtime_session_salt()))
end

# Called where the operation layer builds a request's `OperationContext`,
# before any route code runs: the request then carries its session identity
# to `track_job!` and `jobs_board(; mine=req)`.
_runtime_note_session!(req::HTTP.Request, context) = _runtime_guarded("session") do
    req.context[_RUNTIME_SESSION_KEY] = _runtime_session(context)
end
_runtime_note_session!(_, _) = nothing

_runtime_session_of(req::HTTP.Request) =
    get(req.context, _RUNTIME_SESSION_KEY, _RUNTIME_NO_SESSION)::Tuple{Symbol,UInt}
_runtime_session_of(context::OperationContext) = _runtime_session(context)
_runtime_session_of(_) = _RUNTIME_NO_SESSION

_runtime_same_session(j::RuntimeJob, (scope, session)) =
    session != 0 && j.scope === scope && j.session == session

# --- jobs ------------------------------------------------------------------

# A `@queued` operation is a job once it outlives the `:auto` grace period (see
# `_operation_grace_period`): every such execution is registered at start, shown
# once it is older than this, and forgotten if it finishes sooner.
const _RUNTIME_JOB_GRACE = 0.1

# Identity of the computation behind a handle. Two requests that join the same
# in-flight DynamicObjects compute (a retained root, or a second poll-heal of a
# still-running key) receive distinct `Pending` values over the same
# `(cache, key, slot)`, and must count as one job.
function _runtime_handle_key(handle)
    try
        cache = getfield(handle, :cache)
        slot = getfield(handle, :slot)
        (objectid(cache), getfield(handle, :key),
         slot === nothing ? UInt(0) : objectid(slot))
    catch
        objectid(handle)
    end
end

_runtime_link_request!(tracker::RuntimeTracker, record, job::RuntimeJob) =
    record isa RuntimeRequest && haskey(tracker.inflight, record.id) &&
        (record.job = job.id)

# A retained operation result is safe to link only when its originating GET
# target needed no credential/token redaction. Preserve the externally visible
# prefix so the link stays inside a path-stripping reverse proxy.
function _runtime_result_url(record, req)
    req isa HTTP.Request || return ""
    method = record isa RuntimeRequest ? record.method : String(req.method)
    method == "GET" || return ""
    target = _operation_request_url(req, _request_prefix(req, ""))
    _runtime_redact_target(target) == target ? target : ""
end

# Create and register a job. The caller holds `tracker.lock`.
function _runtime_new_job!(tracker::RuntimeTracker, label, record, req;
        scope::Symbol, session::UInt, handle=nothing, progress=nothing,
        source=nothing, now_ns::UInt64=time_ns())
    tracker.next_job += 1
    tracker.total_jobs += 1
    started_at, started_ns = record isa RuntimeRequest ?
        (record.started_at, record.started_ns) : (time(), now_ns)
    target = record isa RuntimeRequest ? record.target :
             req isa HTTP.Request ? _runtime_redact_target(req.target) : ""
    result_url = _runtime_result_url(record, req)
    route = record isa RuntimeRequest ? record.route : ""
    hidden = record isa RuntimeRequest && record.hidden
    job = RuntimeJob(tracker.next_job, string(label), route, target, result_url, :running,
        started_at, started_ns, NaN, "", 1, 0, now_ns, handle, progress,
        scope, session, 0, hidden, false, source)
    tracker.running[job.id] = job
    _runtime_link_request!(tracker, record, job)
    job
end

"""
    _runtime_operation_started!(req, descriptor, name, context, prop, keys, call_kwargs)

Register one `@queued` operation execution as a job at its start — every
transport (`:blocking`, `:polling`, `:page_load`), so inline work is visible too. The job
shows once it outlives the grace period; `_runtime_operation_finished!` ends it
when the execution returns, unless the execution was retained as a poller, in
which case `_retain_operation!` hands it to a watcher. `source` lets the
dashboard read an inline execution's progress node lazily while it runs.
WebSocket and SSE routes are skipped: their body runs after the operation, for
the life of the connection.
"""
function _runtime_operation_started!(req, descriptor, name::Symbol, context,
        prop, keys, call_kwargs; leaf=nothing)
    req isa HTTP.Request || return nothing
    context isa OperationContext && context.transport !== :http && return nothing
    _runtime_untracked(leaf) && return nothing
    tracker = _runtime_tracker_of(req)
    tracker.enabled || return nothing
    label = _runtime_operation_label(descriptor, name)
    scope, session = _runtime_session(context)
    record = _runtime_record(req)
    lock(tracker.lock) do
        _runtime_new_job!(tracker, label, record, req; scope, session,
                          source=(prop, keys, call_kwargs))
    end
end

"""
    _runtime_operation_finished!(req, job, err)

End a job registered by `_runtime_operation_started!` when its execution
returns (`err === nothing`) or throws. A job retained as a poller belongs to
its watcher and one merged into an already-tracked computation is gone; both
are left alone. An execution that finished within the grace period was a
request, not a job, and is forgotten.
"""
function _runtime_operation_finished!(req, job, err)
    job isa RuntimeJob || return nothing
    tracker = _runtime_tracker_of(req)
    finished_ns = time_ns()
    # Take the tree into the history while DynamicObjects can still resolve it
    # (not for a quick execution: it is about to be forgotten).
    quick = _runtime_elapsed(job.started_ns, finished_ns) < _RUNTIME_JOB_GRACE
    node = job.watched || quick ? nothing : _runtime_lazy_progress(job.source)
    record = _runtime_record(req)
    lock(tracker.lock) do
        (job.watched || get(tracker.running, job.id, nothing) !== job) && return nothing
        delete!(tracker.running, job.id)
        job.duration = _runtime_elapsed(job.started_ns, finished_ns)
        job.state = err === nothing ? :done : :failed
        err === nothing || (job.error = _runtime_error_summary(err))
        job.source = nothing
        job.progress === nothing && (job.progress = node)
        hidden = job.hidden || (record isa RuntimeRequest && record.hidden)
        if hidden || job.duration < _RUNTIME_JOB_GRACE
            tracker.total_jobs -= 1
            record isa RuntimeRequest && record.job == job.id && (record.job = 0)
            return nothing
        end
        if tracker.job_history_limit > 0
            push!(tracker.finished, job)
            _runtime_trim!(tracker.finished, tracker.job_history_limit)
        end
    end
    nothing
end

# Routes whose executions are never jobs: the runtime dashboard's own, which
# must not show up in what they display (its first, compile-bound requests
# would otherwise outlive the grace period before the body can hide itself).
_runtime_untracked(_) = false

# Run `f` as an operation execution: registered at start, ended on return or
# throw. Tracking is guarded: a ledger failure never affects the operation.
function _with_runtime_job(f, req, descriptor, name, context, prop, keys,
        call_kwargs; leaf=nothing, track::Bool=true)
    # Only `@queued` (heavy) computations are jobs; an ordinary operation is
    # recorded as the request it is.
    track || return f(nothing)
    job = _runtime_guarded("job start") do
        _runtime_operation_started!(req, descriptor, name, context, prop, keys,
                                    call_kwargs; leaf)
    end
    value = try
        f(job)
    catch err
        _runtime_guarded(() -> _runtime_operation_finished!(req, job, err), "job finish")
        rethrow()
    end
    _runtime_guarded(() -> _runtime_operation_finished!(req, job, nothing), "job finish")
    value
end

"""
    _retain_operation!(entry, descriptor, name)

Retain a polling operation (see `_retain_operation_poll!`) and record it as a
long-running job. Every path where an operation crosses the grace boundary —
the polling transport, a deferred direct-page load, a healed poll — retains
through here. The job registered when the execution started (`entry.job`) is
handed to a watcher, or merged into the job already tracking the same
computation.
"""
function _retain_operation!(entry::_OperationPollEntry, descriptor, name::Symbol;
        track::Bool=true)
    _retain_operation_poll!(entry)
    track || return nothing
    _runtime_guarded("job start") do
        _runtime_job_started!(_runtime_tracker_of(entry.request), entry,
                              _runtime_operation_label(descriptor, name))
    end
    nothing
end

# The operation's human name: its docstring summary, else the humanized
# property name — the same rule the poller header follows.
function _runtime_operation_label(descriptor, name::Symbol)
    description = descriptor === nothing ? "" : get(descriptor, :description, "")
    something(_docstring_summary(description), Long(name))
end

function _runtime_job_started!(tracker::RuntimeTracker, entry, label)
    tracker.enabled || return nothing
    handle = entry.started
    handle isa _OperationHandle || return nothing
    req = entry.request
    record = _runtime_record(req)
    key = _runtime_handle_key(handle)
    now_ns = time_ns()
    progress = try
        DynamicObjects.getstatus(entry.prop, entry.keys...; entry.call_kwargs...)
    catch
        nothing
    end
    own = entry.job
    job, fresh = lock(tracker.lock) do
        mine = own isa RuntimeJob && !own.watched &&
               get(tracker.running, own.id, nothing) === own ? own : nothing
        existing = get(tracker.running, get(tracker.by_handle, key, 0), nothing)
        if existing isa RuntimeJob && existing !== mine
            # This execution joined a computation that is already a job.
            existing.requests += 1
            existing.last_seen_ns = now_ns
            isempty(existing.result_url) &&
                (existing.result_url = _runtime_result_url(record, req))
            existing.progress === nothing && (existing.progress = progress)
            if mine !== nothing
                delete!(tracker.running, mine.id)
                tracker.total_jobs -= 1
            end
            _runtime_link_request!(tracker, record, existing)
            return existing, false
        end
        scope, session = _runtime_session_of(req)
        job = mine === nothing ?
            _runtime_new_job!(tracker, label, record, req; scope, session, now_ns) : mine
        job.handle = handle
        job.watched = true
        job.last_seen_ns = now_ns
        progress === nothing || (job.progress = progress)
        tracker.by_handle[key] = job.id
        _runtime_link_request!(tracker, record, job)
        job, true
    end
    fresh && _runtime_watch_job!(tracker, job, key, handle)
    nothing
end

"""
    track_job!(handle; label=nothing, progress=nothing, req=nothing, tracker=nothing) -> Int

Record work that HTMXObjects' operation layer did not start as a job, so it
shows on the runtime dashboard and on [`jobs_board`](@ref)s: a compute behind a
hand-rolled `Treebars.polling_fetchindex` poller (which calls this itself), an
app's `Threads.@spawn`, a warm-up task. `handle` is the in-flight work — a
DynamicObjects `Pending`, a `Task`, or anything `fetch` waits on — and a watcher
stamps its outcome (`:done`, or `:failed` with the error's summary) when it
resolves. `progress` is its progress node (a Treebars tree), `label` its name
(default `"Job"`).

Pass the request the work belongs to as `req`: the job then records that
request's route and redacted target, joins its session for
`jobs_board(; mine=req)`, and lands in the tracker that recorded the request
(else `tracker`, else [`runtime_tracker`](@ref)). Calling `track_job!` again for
the same in-flight computation — a follow-up poll — counts a poll on the
existing job instead of adding one. Returns the job id (`0` when not tracked).
Tracking never throws: a ledger failure is logged once and ignored.
"""
function track_job!(handle; label=nothing, progress=nothing, req=nothing,
        tracker=nothing)
    t = tracker isa RuntimeTracker ? tracker : _runtime_tracker_of(req)
    id = _runtime_guarded("track_job!") do
        _runtime_track_job!(t, handle, label, progress, req)
    end
    something(id, 0)
end

function _runtime_track_job!(tracker::RuntimeTracker, handle, label, progress, req)
    tracker.enabled || return 0
    handle === nothing && return 0
    key = _runtime_handle_key(handle)
    record = _runtime_record(req)
    scope, session = _runtime_session_of(req)
    now_ns = time_ns()
    job, fresh = lock(tracker.lock) do
        existing = get(tracker.running, get(tracker.by_handle, key, 0), nothing)
        if existing isa RuntimeJob
            existing.polls += 1
            existing.last_seen_ns = now_ns
            isempty(existing.result_url) &&
                (existing.result_url = _runtime_result_url(record, req))
            existing.progress === nothing && (existing.progress = progress)
            _runtime_link_request!(tracker, record, existing)
            return existing, false
        end
        job = _runtime_new_job!(tracker, something(label, "Job"), record, req;
                                scope, session, handle, progress, now_ns)
        job.watched = true
        tracker.by_handle[key] = job.id
        job, true
    end
    fresh && _runtime_watch_job!(tracker, job, key, handle)
    job.id
end

# Wait for a job's work, following nested `Pending`s (a route may finish by
# returning another one) and tasks. Anything else is waited on once.
function _runtime_await(handle)
    value = handle isa Union{_OperationHandle,Task} ? handle : fetch(handle)
    while value isa Union{_OperationHandle,Task}
        value = fetch(value)
    end
    nothing
end

# One lightweight watcher per job: wait for the computation, then stamp the
# outcome. It runs on the interactive pool when there is one, so a saturated
# `:default` pool — the situation the dashboard exists to diagnose — does not
# delay the finish timestamp. The watcher never renders or retains the value.
function _runtime_watch_job!(tracker::RuntimeTracker, job::RuntimeJob, key, handle)
    watch = function ()
        state = :done
        failure = ""
        try
            _runtime_await(handle)
        catch err
            state = :failed
            err isa TaskFailedException && (err = err.task.exception)
            failure = _runtime_error_summary(err)
        end
        _runtime_job_finish!(tracker, job, key, state, failure)
    end
    # Literal pool symbols: `@spawn` only accepts a computed pool on newer Julia.
    watcher = Threads.nthreads(:interactive) > 0 ?
        Threads.@spawn(:interactive, watch()) : Threads.@spawn(watch())
    errormonitor(watcher)
    nothing
end

function _runtime_job_finish!(tracker::RuntimeTracker, job::RuntimeJob, key,
        state::Symbol, failure::AbstractString)
    finished_ns = time_ns()
    lock(tracker.lock) do
        job.state = state
        job.error = failure
        job.position = 0
        job.duration = _runtime_elapsed(job.started_ns, finished_ns)
        job.handle = nothing
        job.source = nothing
        delete!(tracker.running, job.id)
        get(tracker.by_handle, key, 0) == job.id && delete!(tracker.by_handle, key)
        if !job.hidden && tracker.job_history_limit > 0
            push!(tracker.finished, job)
            _runtime_trim!(tracker.finished, tracker.job_history_limit)
        end
    end
    nothing
end

"""
    _runtime_job_polled!(req, handle)

Count a follow-up poll against the running job behind `handle`, and link the
poll request to it.
"""
_runtime_job_polled!(req, handle) =
    _runtime_guarded(() -> _runtime_count_poll!(req, handle), "job poll")

function _runtime_count_poll!(req, handle)
    tracker = _runtime_tracker_of(req)
    tracker.enabled || return nothing
    handle isa _OperationHandle || return nothing
    key = _runtime_handle_key(handle)
    record = _runtime_record(req)
    lock(tracker.lock) do
        job = get(tracker.running, get(tracker.by_handle, key, 0), nothing)
        job isa RuntimeJob || return nothing
        job.polls += 1
        job.last_seen_ns = time_ns()
        if record isa RuntimeRequest && haskey(tracker.inflight, record.id)
            record.job = job.id
            record.mode = :poll
        end
    end
    nothing
end

# When a client last started, joined or polled the job tracking `key` (`default`
# when none does yet). Used by the job queue's reaper.
function _runtime_last_seen(tracker::RuntimeTracker, key, default::UInt64)
    lock(tracker.lock) do
        job = get(tracker.running, get(tracker.by_handle, key, 0), nothing)
        job isa RuntimeJob ? job.last_seen_ns : default
    end
end

# A job's progress node when only its source is known: an inline execution
# still running on its request task, read lazily from DynamicObjects. Called
# outside the tracker lock.
function _runtime_lazy_progress(source)
    source === nothing && return nothing
    prop, keys, call_kwargs = source
    try
        DynamicObjects.getstatus(prop, keys...; call_kwargs...)
    catch
        nothing
    end
end

# --- job queue ---------------------------------------------------------------
#
# `@queued` (heavy) computations wait their turn in DynamicObjects' process-wide
# job queue: DynamicObjects' `@queued` marker declares the executor of every
# property it marks, route properties included, so each memoized or fresh
# computation of one is admitted there, on `:default`, whoever starts it.
# `configure_job_queue!` forwards `max_running` to it. Ordinary (unmarked)
# operations never queue; they start on their request's pool.
#
# What HTMXObjects adds is request-aware:
#
# - a route operation's job is recorded by the operation layer; an observer on
#   the queue records every other queued computation — a `@queued` property's —
#   as a job named after the property;
# - a route's queued computation nobody has started, joined or polled for
#   `abandon_after` seconds is abandoned (its page is gone): its job fails with
#   reason "abandoned", and the next request for it starts afresh. A property's
#   is never abandoned: its callers block on it;
# - the ledger shows each queued job's position.
#
# The observer runs on the enqueuing task. The operation layer marks the tasks
# that start a route's computation (`_route_queue_scope`), so the observer can
# tell a route's item from a property's.

# Seconds a route's queued computation may go unwatched before it is abandoned.
const _QUEUE_ABANDON_AFTER = Ref(60.0)

# Waiting items HTMXObjects knows: item => (tracker, ledger key, reapable). The
# key is a thunk for a fresh route invocation, whose operation exists only
# once its task is spawned. Only a polled route's item is reapable.
const _QUEUE_ITEMS = WeakKeyDict{Any,Tuple{RuntimeTracker,Any,Bool}}()
const _QUEUE_REAPING = Threads.Atomic{Bool}(false)

const _ROUTE_QUEUE_SCOPE = :htmxo_route_queue_scope

_has_job_queue() = isdefined(DynamicObjects, :job_queue)
_dynamicobjects_queue(name::Symbol) = getproperty(DynamicObjects, name)

"""
    configure_job_queue!(; max_running=nothing, abandon_after=nothing) -> NamedTuple

Bound how many `@queued` (heavy) computations run at once. Off by default
(`max_running=0`): a `@queued` computation starts on `:default` immediately. With
`max_running=n`, at most `n` such computations run at a time and the rest wait in
FIFO order; the runtime dashboard and [`jobs_board`](@ref)s list them as
`:queued` with their queue position ("queued · #3"), and they start as earlier
ones finish. Concurrent requests for the same computation still share it, queued
or running.

Every `@queued` computation is admitted, whoever starts it. On a route that is all
of them: memoized or fresh (`@fresh` routes and mutation verbs, which are never
coalesced), polled or answered inline — an inline (`@direct`, non-HTMX,
`:blocking`) request waits for its turn and its result. On an indexed property
it is every computation, from any caller — a route, another property's body, a
`Threads.@threads` iteration — and the caller blocks until it is done (see
*Queued properties* in the API docs). A queued computation that blocks on
another queued computation — itself, or any task it spawned — gives its slot
back for the rest of its run, so the cap counts heavy work rather than the jobs
waiting on it. Ordinary operations start at once on their request's pool.

A route's queued computation nobody has started, joined or polled for
`abandon_after` seconds (default 60) is abandoned instead of run — its page is
gone. Its job is recorded as `:failed` with reason "abandoned", and the next
request for it starts a fresh compute. `abandon_after=Inf` never abandons.
Running computes are never interrupted, and a property's computation is never
abandoned: its callers are waiting for it.

The queue is DynamicObjects' (`DynamicObjects.configure_queue!`, which this
forwards `max_running` to); `@queued` needs a DynamicObjects with it
(`pre-inference` ≥ `64aba0c`). Returns the current settings; omitted settings
are unchanged. Setting `max_running=0` starts everything still queued.
"""
function configure_job_queue!(; max_running=nothing, abandon_after=nothing)
    if max_running !== nothing
        max_running >= 0 || throw(ArgumentError("max_running must be non-negative"))
        max_running > 0 && !_has_job_queue() && throw(ArgumentError(
            "configure_job_queue! needs a DynamicObjects with its job queue " *
            "(pre-inference ≥ 64aba0c)"))
    end
    if abandon_after !== nothing
        abandon_after > 0 || throw(ArgumentError("abandon_after must be positive"))
        _QUEUE_ABANDON_AFTER[] = Float64(abandon_after)
    end
    max_running === nothing || !_has_job_queue() ||
        _dynamicobjects_queue(:configure_queue!)(; max_running=Int(max_running))
    job_queue_settings()
end

function job_queue_settings()
    queue = _has_job_queue() ? _dynamicobjects_queue(:queue_settings)() :
        (; max_running=0, queued=0, running=0)
    (; queue.max_running, abandon_after=_QUEUE_ABANDON_AFTER[], queue.queued,
       queue.running)
end

# Run `f` as the start of a route's queued computation for `tracker`'s ledger:
# what it enqueues is that route's, whose job the operation layer records.
# `key` is the job's ledger key, or `nothing` when the queued item carries it
# (a memoized computation's cache cell); `reapable` is whether nobody but a
# poller waits for it. Task-local, so a property the route's body computes
# later — on the queue's own task — stays a property's.
_route_queue_scope(f, tracker::RuntimeTracker, key, reapable::Bool) =
    task_local_storage(f, _ROUTE_QUEUE_SCOPE, (tracker, key, reapable))

# The queue observer (installed in `__init__`).
function _observe_queued!(item)
    route = get(task_local_storage(), _ROUTE_QUEUE_SCOPE, nothing)
    if route !== nothing
        tracker, key, reapable = route
        _remember_queued!(item, tracker, something(key, _queued_work_key(item.work)),
                          reapable)
        reapable && _start_queue_reaper!()
    elseif item.property !== nothing
        tracker = runtime_tracker()
        handle = _queued_watch_handle(item.work)
        id = track_job!(handle; label=String(item.property),
                        progress=_queued_status(item.work), tracker)
        id == 0 || _remember_queued!(item, tracker, _runtime_handle_key(handle), false)
    end
    nothing
end

_remember_queued!(item, tracker, key, reapable::Bool) =
    lock(() -> (_QUEUE_ITEMS[item] = (tracker, key, reapable)), _QUEUE_ITEMS)

# The ledger key of a queued memoized computation: its cache cell's, the same
# as a `Pending` for it (`_runtime_handle_key`).
_queued_work_key(work) = hasfield(typeof(work), :cache) ?
    (objectid(getfield(work, :cache)), getfield(work, :key), UInt(0)) : objectid(work)

_queued_status(work) = hasfield(typeof(work), :status) ? getfield(work, :status) : nothing

# What the ledger's watcher waits on for a property's queued computation. It
# must not count as a queued job waiting (which would give back the slot of
# the queued computation the observer ran under): for a memoized one, a
# `Pending` without the queue's executor; for a fresh one, its `QueuedCall`,
# fetched only once ready.
_queued_watch_handle(work) = hasfield(typeof(work), :cache) ?
    DynamicObjects.Pending(getfield(work, :cache), getfield(work, :key), nothing) :
    _QueuedCallWatch(work)

struct _QueuedCallWatch
    call::Any
end

function Base.fetch(w::_QueuedCallWatch)
    while !isready(w.call)
        sleep(0.05)
    end
    fetch(w.call)
end

_queued_key(key) = key
_queued_key(key::Function) = key()

# Queue positions by ledger key, 1-based, from DynamicObjects' waiting list.
function _job_queue_positions()
    _has_job_queue() || return Dict{Any,Int}()
    waiting = _dynamicobjects_queue(:queued_items)()
    positions = Dict{Any,Int}()
    lock(_QUEUE_ITEMS) do
        for (position, item) in enumerate(waiting)
            known = get(_QUEUE_ITEMS, item, nothing)
            known === nothing && continue
            positions[_queued_key(known[2])] = position
        end
    end
    positions
end

# Abandon routes' queued computations nobody watches. Runs while any waits.
function _start_queue_reaper!()
    Threads.atomic_cas!(_QUEUE_REAPING, false, true) && return nothing
    errormonitor(Threads.@spawn _job_queue_reaper())
    nothing
end

# It stops after two idle passes: the observer remembers an item just before
# DynamicObjects queues it, and one pass could fall in between.
function _job_queue_reaper()
    try
        idle = 0
        while idle < 2
            sleep(clamp(_QUEUE_ABANDON_AFTER[] / 4, 0.05, 1.0))
            idle = _job_queue_reap!() == :idle ? idle + 1 : 0
        end
    finally
        _QUEUE_REAPING[] = false
    end
end

function _job_queue_reap!(now_ns::UInt64=time_ns())
    waiting = _dynamicobjects_queue(:queued_items)()
    routes = lock(_QUEUE_ITEMS) do
        [(item, _QUEUE_ITEMS[item]) for item in waiting
         if haskey(_QUEUE_ITEMS, item) && _QUEUE_ITEMS[item][3]]
    end
    isempty(routes) && return :idle
    limit = _QUEUE_ABANDON_AFTER[]
    isfinite(limit) || return :watching
    stale = [item for (item, (tracker, key, _)) in routes
             if _runtime_elapsed(_runtime_last_seen(tracker, _queued_key(key),
                                                    item.enqueued_ns), now_ns) >= limit]
    isempty(stale) || _dynamicobjects_queue(:abandon_queued!)(
        _dynamicobjects_queue(:job_queue)(), stale,
        "abandoned: unwatched for $(fmt_time(limit))")
    :watching
end

# --- snapshots -------------------------------------------------------------

_runtime_request_row(r::RuntimeRequest, now_ns::UInt64) = (;
    id=r.id, method=r.method, target=r.target, path=r.path, kind=r.kind,
    route=r.route, mode=r.mode, job=r.job, threadpool=r.threadpool,
    started_at=r.started_at,
    duration=isnan(r.duration) ? _runtime_elapsed(r.started_ns, now_ns) : r.duration,
    running=isnan(r.duration), status=r.status, error=r.error)

_runtime_job_active(j::RuntimeJob) = j.state === :queued || j.state === :running

function _runtime_job_updated_at(j::RuntimeJob)
    _runtime_job_active(j) || return j.started_at + j.duration
    elapsed = j.last_seen_ns >= j.started_ns ?
        (j.last_seen_ns - j.started_ns) / 1.0e9 : 0.0
    j.started_at + elapsed
end

# A running job whose computation waits in the job queue reads as `:queued`
# with its position (`queued` maps job ids to positions, see
# `_runtime_queued_jobs`).
function _runtime_job_row(j::RuntimeJob, now_ns::UInt64, queued=nothing)
    position = queued === nothing ? j.position : get(queued, j.id, j.position)
    state = position > 0 && _runtime_job_active(j) ? :queued : j.state
    (; id=j.id, label=j.label, route=j.route, target=j.target,
       result_url=j.result_url, state, started_at=j.started_at,
       updated_at=_runtime_job_updated_at(j),
       duration=isnan(j.duration) ? _runtime_elapsed(j.started_ns, now_ns) : j.duration,
       requests=j.requests, polls=j.polls,
       idle=_runtime_job_active(j) ? _runtime_elapsed(j.last_seen_ns, now_ns) : 0.0,
       error=j.error, scope=j.scope, position)
end

# Job ids => queue positions for the tracker's jobs whose computation is
# queued. `positions` is read from the queue first (queue lock alone); this
# runs under the tracker lock, so the two locks are never nested.
function _runtime_queued_jobs(tracker::RuntimeTracker, positions)
    isempty(positions) && return nothing
    queued = Dict{Int,Int}()
    for (key, id) in tracker.by_handle
        position = get(positions, key, 0)
        position > 0 && (queued[id] = position)
    end
    queued
end

# A queued or running job shows once it is older than the grace period (it was
# registered at the start of an execution that may still answer inline); the
# dashboard's own work never shows.
_runtime_job_visible(j::RuntimeJob, now_ns::UInt64) = !j.hidden &&
    (!_runtime_job_active(j) || _runtime_elapsed(j.started_ns, now_ns) >= _RUNTIME_JOB_GRACE)

function _runtime_quantile(sorted::AbstractVector{Float64}, p::Real)
    isempty(sorted) && return NaN
    sorted[clamp(ceil(Int, p * length(sorted)), 1, length(sorted))]
end

function _runtime_route_stats(history)
    groups = Dict{String,Vector{Any}}()
    for r in history
        key = isempty(r.route) ? string(r.method, ' ', r.path) : r.route
        push!(get!(() -> Any[], groups, key), r)
    end
    stats = map(collect(groups)) do (route, rs)
        durations = sort!(Float64[r.duration for r in rs])
        (; route, count=length(rs),
           errors=count(r -> r.status >= 500 || !isempty(r.error), rs),
           p50=_runtime_quantile(durations, 0.5),
           p95=_runtime_quantile(durations, 0.95),
           max=last(durations),
           total=sum(durations))
    end
    sort!(stats; by=s -> s.total, rev=true)
end

function _runtime_process_row(tracker::RuntimeTracker, running_jobs::Int)
    gc = Base.gc_num()
    (; uptime=time() - tracker.started_at,
       threads_default=Threads.nthreads(:default),
       threads_interactive=Threads.nthreads(:interactive),
       running_jobs,
       live_bytes=Base.gc_live_bytes(),
       gc_time=gc.total_time / 1.0e9,
       free_memory=Float64(Sys.free_memory()),
       total_memory=Float64(Sys.total_memory()),
       total_requests=tracker.total_requests,
       total_jobs=tracker.total_jobs)
end

"""
    runtime_snapshot(tracker=runtime_tracker()) -> NamedTuple

A consistent copy of the tracker's state as plain data:

- `inflight` — requests still being handled, oldest first, with their
  current age as `duration`;
- `history` — finished requests, newest first;
- `running` / `finished` — jobs, oldest running first, newest finished first
  (queued jobs are listed with the running ones); a running job's `idle` is the
  time since a request last started, joined or polled it, so a large `idle`
  means nobody is watching it any more. Progress nodes are not included — see
  [`runtime_jobs`](@ref);
- `routes` — per-route count, error count (5xx, or a route error rendered as
  an HTMX fragment), p50/p95/max and total handling time over the request
  history, busiest first;
- `process` — uptime, thread-pool sizes, running-job count, GC and memory.

Requests hidden from the history (the dashboard's own, and polls unless
`record_polls`) are omitted from `inflight` too.
"""
function runtime_snapshot(tracker::RuntimeTracker=runtime_tracker())
    positions = _job_queue_positions()
    now_ns = time_ns()
    inflight, history, running, finished = lock(tracker.lock) do
        queued = _runtime_queued_jobs(tracker, positions)
        (sort!([_runtime_request_row(r, now_ns) for r in values(tracker.inflight) if !r.hidden];
               by=r -> r.started_at),
         [_runtime_request_row(r, now_ns) for r in Iterators.reverse(tracker.history)],
         sort!([_runtime_job_row(j, now_ns, queued) for j in values(tracker.running)
                if _runtime_job_visible(j, now_ns)]; by=j -> j.started_at),
         [_runtime_job_row(j, now_ns) for j in Iterators.reverse(tracker.finished)])
    end
    (; inflight, history, running, finished,
       routes=_runtime_route_stats(history),
       process=_runtime_process_row(tracker, length(running)))
end

const _RUNTIME_JOB_STATES = (:queued, :running, :done, :failed)

"""
    runtime_jobs(tracker=runtime_tracker(); states=(:queued, :running),
                 filter=nothing, mine=nothing, recent=Inf) -> Vector{NamedTuple}

The tracker's jobs in `states` (any of `:queued`, `:running`, `:done`,
`:failed`) as plain rows, oldest first, each with its progress node:

`(; id, label, route, target, result_url, state, started_at, updated_at,
duration, requests, polls, idle, error, scope, position, progress)`

— `duration` is the time so far for a queued/running job and the wall time of
a finished one, `updated_at` the latest recorded start/join/poll or completion,
`result_url` the safe original GET target for a retained result (empty when the
target was not a GET or required redaction), `idle` the time since a request
last started, joined or polled a running job, `position` a queued job's queue
position, and `progress` its progress node (a Treebars tree, or `nothing`). The
jobs are selected under the tracker lock; progress nodes are handed out as they
are, for rendering outside it. A running inline execution's node is read from
DynamicObjects on demand.

- `filter(row) -> Bool` keeps only matching rows.
- `mine` — a request (or `OperationContext`): only jobs started under the same
  root-provider session, i.e. by an operation whose `:session`/`:job` scope and
  key match. With the default `:request`-scoped provider every request is its
  own session, so nothing matches. `nothing` (the default) is the global view.
- `recent` — finished jobs are included only if they finished within the last
  `recent` seconds.

Running jobs are listed once they outlive the `:auto` grace period (100 ms);
shorter executions are requests, not jobs. The ledger is process-local and in
memory: empty after a restart, and per process in a multi-process deployment.
"""
function runtime_jobs(tracker::RuntimeTracker=runtime_tracker();
        states=(:queued, :running), filter=nothing, mine=nothing, recent::Real=Inf)
    wanted = states isa Symbol ? (states,) : Tuple(Symbol.(states))
    for state in wanted
        state in _RUNTIME_JOB_STATES || throw(ArgumentError(
            "job states must be among $(_RUNTIME_JOB_STATES) (got $(repr(state)))"))
    end
    session = mine === nothing ? nothing : _runtime_session_of(mine)
    positions = _job_queue_positions()
    now_ns = time_ns()
    now = time()
    picked = lock(tracker.lock) do
        queued = _runtime_queued_jobs(tracker, positions)
        jobs = RuntimeJob[]
        for j in values(tracker.running)
            state = queued !== nothing && haskey(queued, j.id) ? :queued : j.state
            state in wanted && _runtime_job_visible(j, now_ns) || continue
            push!(jobs, j)
        end
        for j in tracker.finished
            j.state in wanted && !j.hidden || continue
            now - (j.started_at + j.duration) <= recent || continue
            push!(jobs, j)
        end
        session === nothing || filter!(j -> _runtime_same_session(j, session), jobs)
        sort!(jobs; by=j -> j.id)
        [(j, _runtime_job_row(j, now_ns, queued), j.progress, j.source) for j in jobs]
    end
    rows = NamedTuple[]
    for (j, row, progress, source) in picked
        node = progress === nothing ? _runtime_lazy_progress(source) : progress
        push!(rows, merge(row, (; progress=node)))
    end
    # Keep a lazily read node: DynamicObjects keeps it after the compute, but
    # the job drops its source when it finishes.
    lock(tracker.lock) do
        for ((j, _, progress, _), row) in zip(picked, rows)
            progress === nothing && j.progress === nothing && (j.progress = row.progress)
        end
    end
    filter === nothing ? rows : Base.filter(filter, rows)
end
