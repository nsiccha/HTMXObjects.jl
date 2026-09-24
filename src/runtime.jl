# --- Runtime tracking: requests and long-running operations -----------------
#
# Two process-local ledgers behind the `RuntimeRoutes` dev dashboard:
#
# - requests: every request that passes through `track_requests` — in flight
#   (with a ticking age) and a bounded history of finished ones with their
#   handling time, status, matched route and execution mode;
# - jobs: every operation that crossed the `:auto` grace boundary and became a
#   poller (or a deferred direct-page load) — running, and a bounded history of
#   finished ones with wall time, outcome and the frozen progress tree.
#
# Neither ledger depends on Oxygen. `track_requests` is a plain HTTP.jl
# middleware (`handler -> req -> response`), so any server that composes
# HTTP.jl handlers can install it; `serve` currently hands it to Oxygen's
# middleware chain only because Oxygen is today's server. Jobs are recorded by
# HTMXObjects' own operation layer (`_retain_operation!`), not by the server.
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

One long-running operation: a route execution that outlived the `:auto` grace
period and continued in the background while clients polled it. `state` is
`:running`, `:done` or `:failed`; `duration` is `NaN` while running. `requests`
counts the requests that started or joined the same computation, `polls` the
follow-up polls it answered. `progress` is the operation's progress node
(a Treebars tree when Treebars is loaded), kept after completion so history
shows per-phase timings.
"""
mutable struct RuntimeJob
    id::Int
    label::String
    route::String
    target::String
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
            failure = something(_runtime_guarded(
                () -> _runtime_error_summary(err), "error summary"), "")
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
watching the server does not bury what it is watching.
"""
_runtime_hide_request!(req) =
    _runtime_annotate!(record -> (record.hidden = true), req)

_runtime_note_mode!(req, mode::Symbol) =
    _runtime_annotate!(record -> (record.mode = mode), req)

# HTMX requests receive route errors as 200 fragments (so the error article
# swaps in), which would make a failed request look healthy in the ledger.
# `_route_error_response` notes the failure and its recorded error id instead.
_runtime_note_error!(req, err, uid) = _runtime_annotate!(req) do record
    record.error = string(_runtime_error_summary(err), " [error ", uid, "]")
end

# --- jobs ------------------------------------------------------------------

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

"""
    _retain_operation!(entry, descriptor, name)

Retain a polling operation (see `_retain_operation_poll!`) and record it as a
long-running job. Every path where an operation crosses the grace boundary —
the polling transport, a deferred direct-page load, a healed poll — retains
through here.
"""
function _retain_operation!(entry::_OperationPollEntry, descriptor, name::Symbol)
    _retain_operation_poll!(entry)
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
    handle isa DynamicObjects.Pending || return nothing
    req = entry.request
    record = _runtime_record(req)
    key = _runtime_handle_key(handle)
    now_ns = time_ns()
    progress = try
        DynamicObjects.getstatus(entry.prop, entry.keys...; entry.call_kwargs...)
    catch
        nothing
    end
    job, fresh = lock(tracker.lock) do
        existing = get(tracker.by_handle, key, 0)
        job = get(tracker.running, existing, nothing)
        if job isa RuntimeJob
            job.requests += 1
            job.last_seen_ns = now_ns
            job.progress === nothing && (job.progress = progress)
            fresh = false
        else
            tracker.next_job += 1
            tracker.total_jobs += 1
            started_at, started_ns = record isa RuntimeRequest ?
                (record.started_at, record.started_ns) : (time(), now_ns)
            target = record isa RuntimeRequest ? record.target :
                     _runtime_redact_target(req.target)
            route = record isa RuntimeRequest ? record.route : ""
            job = RuntimeJob(tracker.next_job, string(label),
                route, target, :running, started_at, started_ns, NaN, "", 1, 0,
                now_ns, handle, progress)
            tracker.running[job.id] = job
            tracker.by_handle[key] = job.id
            fresh = true
        end
        if record isa RuntimeRequest && haskey(tracker.inflight, record.id)
            record.job = job.id
        end
        job, fresh
    end
    fresh && _runtime_watch_job!(tracker, job, key, handle)
    nothing
end

# One lightweight watcher per job: wait for the computation (following nested
# `Pending`s — a route may finish by returning another one), then stamp the
# outcome. It runs on the interactive pool when there is one, so a saturated
# `:default` pool — the situation the dashboard exists to diagnose — does not
# delay the finish timestamp. The watcher never renders or retains the value.
function _runtime_watch_job!(tracker::RuntimeTracker, job::RuntimeJob, key, handle)
    watch = function ()
        state = :done
        failure = ""
        try
            value = handle
            while value isa DynamicObjects.Pending
                value = fetch(value)
            end
        catch err
            state = :failed
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
        job.duration = _runtime_elapsed(job.started_ns, finished_ns)
        job.handle = nothing
        delete!(tracker.running, job.id)
        get(tracker.by_handle, key, 0) == job.id && delete!(tracker.by_handle, key)
        if tracker.job_history_limit > 0
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
    handle isa DynamicObjects.Pending || return nothing
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

# --- snapshots -------------------------------------------------------------

_runtime_request_row(r::RuntimeRequest, now_ns::UInt64) = (;
    id=r.id, method=r.method, target=r.target, path=r.path, kind=r.kind,
    route=r.route, mode=r.mode, job=r.job, threadpool=r.threadpool,
    started_at=r.started_at,
    duration=isnan(r.duration) ? _runtime_elapsed(r.started_ns, now_ns) : r.duration,
    running=isnan(r.duration), status=r.status, error=r.error)

_runtime_job_row(j::RuntimeJob, now_ns::UInt64) = (;
    id=j.id, label=j.label, route=j.route, target=j.target, state=j.state,
    started_at=j.started_at,
    duration=isnan(j.duration) ? _runtime_elapsed(j.started_ns, now_ns) : j.duration,
    requests=j.requests, polls=j.polls,
    idle=j.state === :running ? _runtime_elapsed(j.last_seen_ns, now_ns) : 0.0,
    error=j.error)

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
- `running` / `finished` — long-running jobs (finished newest first); a running
  job's `idle` is the time since a request last started, joined or polled it,
  so a large `idle` means nobody is watching it any more;
- `routes` — per-route count, error count (5xx, or a route error rendered as
  an HTMX fragment), p50/p95/max and total handling time over the request
  history, busiest first;
- `process` — uptime, thread-pool sizes, running-job count, GC and memory.

Requests hidden from the history (the dashboard's own, and polls unless
`record_polls`) are omitted from `inflight` too.
"""
function runtime_snapshot(tracker::RuntimeTracker=runtime_tracker())
    now_ns = time_ns()
    inflight, history, running, finished = lock(tracker.lock) do
        (sort!([_runtime_request_row(r, now_ns) for r in values(tracker.inflight) if !r.hidden];
               by=r -> r.started_at),
         [_runtime_request_row(r, now_ns) for r in Iterators.reverse(tracker.history)],
         sort!([_runtime_job_row(j, now_ns) for j in values(tracker.running)];
               by=j -> j.started_at),
         [_runtime_job_row(j, now_ns) for j in Iterators.reverse(tracker.finished)])
    end
    (; inflight, history, running, finished,
       routes=_runtime_route_stats(history),
       process=_runtime_process_row(tracker, length(running)))
end

# Progress trees for the dashboard, looked up by job id under the lock and
# rendered outside it.
function _runtime_job_progress(tracker::RuntimeTracker, id::Int)
    lock(tracker.lock) do
        job = get(tracker.running, id, nothing)
        job isa RuntimeJob && return job.progress
        idx = findfirst(j -> j.id == id, tracker.finished)
        idx === nothing ? nothing : tracker.finished[idx].progress
    end
end

# Extension seam: the Treebars extension renders a progress node as its HTML
# tree. Without Treebars there is no tree to show.
const _runtime_progress_render_impl = Ref{Any}(node -> nothing)

_runtime_progress_render(node) = node === nothing ? nothing :
    _runtime_progress_render_impl[](node)

"""
    _with_runtime_tracking(kwargs, tracker=runtime_tracker())

Prepend [`track_requests`](@ref) to `serve`'s middleware list, outermost, so it
sees every request the router and serializer produce a response for.
"""
function _with_runtime_tracking(kwargs, tracker::RuntimeTracker=runtime_tracker())
    kw = Dict{Symbol,Any}(kwargs)
    middleware = handler -> track_requests(handler; tracker)
    kw[:middleware] = Any[middleware, Base.get(kw, :middleware, [])...]
    kw
end
