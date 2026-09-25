# --- Runtime tracking: requests and long-running operations -----------------
#
# Two process-local ledgers behind the `RuntimeRoutes` dev dashboard:
#
# - requests: every request that passes through `track_requests` — in flight
#   (with a ticking age) and a bounded history of finished ones with their
#   handling time, status, matched route and execution mode;
# - jobs: every operation execution that outlives the `:auto` grace period —
#   polled, deferred direct-page loads and blocking/inline ones alike — plus
#   work reported through `track_job!` (hand-rolled Treebars pollers, app
#   tasks): queued/running, and a bounded history of finished ones with wall
#   time, outcome and the frozen progress tree.
#
# Neither ledger depends on the server. `track_requests` is a plain HTTP.jl
# middleware (`handler -> req -> response`), so any server that composes
# HTTP.jl handlers can install it; `serve` puts it in its own request pipeline.
# Jobs are recorded by HTMXObjects' own operation layer (`_execute_operation`
# registers every execution at start, `_retain_operation!` hands polled ones
# to a watcher), not by the server.
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

One job: a route execution that outlived the `:auto` grace period (whether it
continued in the background while clients polled it or answered inline), or
work reported through [`track_job!`](@ref). `state` is `:queued`, `:running`,
`:done` or `:failed`; `duration` is `NaN` until it finishes. `requests` counts
the requests that started or joined the same computation, `polls` the
follow-up requests it answered. `progress` is the job's progress node (a
Treebars tree when Treebars is loaded), kept after completion so history shows
per-phase timings. `scope` is the root-provider scope of the operation that
started it (`:request`, `:session`, `:job`, or `:none` outside any operation);
the provider key itself is only kept as a salted in-process digest, used to
match [`jobs_board`](@ref)'s `mine` filter. `position` is the queue position of
a `:queued` job (`0` otherwise); a job whose computation waits in the job queue
([`configure_job_queue!`](@ref)) is listed as `:queued` with its current
position.
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

# An operation is a job once it outlives the `:auto` grace period (see
# `_operation_grace_period`): every execution is registered at start, shown once
# it is older than this, and forgotten if it finishes sooner.
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
    route = record isa RuntimeRequest ? record.route : ""
    hidden = record isa RuntimeRequest && record.hidden
    job = RuntimeJob(tracker.next_job, string(label), route, target, :running,
        started_at, started_ns, NaN, "", 1, 0, now_ns, handle, progress,
        scope, session, 0, hidden, false, source)
    tracker.running[job.id] = job
    _runtime_link_request!(tracker, record, job)
    job
end

"""
    _runtime_operation_started!(req, descriptor, name, context, prop, keys, call_kwargs)

Register one operation execution as a job at its start — every transport
(`:blocking`, `:polling`, `:page_load`), so inline work is visible too. The job
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
        call_kwargs; leaf=nothing)
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
    own = entry.job
    job, fresh = lock(tracker.lock) do
        mine = own isa RuntimeJob && !own.watched &&
               get(tracker.running, own.id, nothing) === own ? own : nothing
        existing = get(tracker.running, get(tracker.by_handle, key, 0), nothing)
        if existing isa RuntimeJob && existing !== mine
            # This execution joined a computation that is already a job.
            existing.requests += 1
            existing.last_seen_ns = now_ns
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
    value = handle isa Union{DynamicObjects.Pending,Task} ? handle : fetch(handle)
    while value isa Union{DynamicObjects.Pending,Task}
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
# Opt-in bounded execution for background operations
# (`configure_job_queue!`). Without it, every operation that goes to the
# background — the polling transport, a deferred direct-page load, a healed
# poll, a `@preload` — starts its compute with `Threads.@spawn`, so N heavy
# computes all run
# at once on the `:default` pool. With it, the operation layer hands them to
# DynamicObjects through `Deferred(executor)` instead: at most `max_running` run
# at a time and the rest wait in FIFO order, listed as `:queued` jobs with their
# position. A queued compute nobody has started, joined or polled for
# `abandon_after` seconds is abandoned (`DynamicObjects.abandon!`): its job
# fails with reason "abandoned", and the next request for it starts afresh.

mutable struct _QueuedCompute
    compute::Any             # DynamicObjects.DeferredCompute
    key::Any                 # `_runtime_handle_key` of the compute's Pending
    tracker::RuntimeTracker
    enqueued_ns::UInt64
end

mutable struct _JobQueue
    lock::ReentrantLock
    ready::Threads.Condition
    waiting::Vector{_QueuedCompute}
    max_running::Int
    abandon_after::Float64
    workers::Int
    reaping::Bool
end

function _JobQueue()
    lk = ReentrantLock()
    _JobQueue(lk, Threads.Condition(lk), _QueuedCompute[], 0, 60.0, 0, false)
end

const _JOB_QUEUE = _JobQueue()

"""
    configure_job_queue!(; max_running=nothing, abandon_after=nothing) -> NamedTuple

Bound how many background operations compute at once. Off by default
(`max_running=0`): every operation that outlives the grace period starts its
compute immediately. With `max_running=n`, at most `n` such computes run at a
time and the rest wait in FIFO order; the runtime dashboard and
[`jobs_board`](@ref)s list them as `:queued` with their queue position ("queued
· #3"), and they start as earlier ones finish. Concurrent requests for the same
computation still share it, queued or running.

A queued compute whose job nobody has started, joined or polled for
`abandon_after` seconds (default 60) is abandoned instead of run — its page is
gone. Its job is recorded as `:failed` with reason "abandoned", and the next
request for it starts a fresh compute. `abandon_after=Inf` never abandons.
Running computes are never interrupted.

Only background computes queue: blocking executions (POST and other mutation
verbs, `:blocking` policies, `@fresh` routes, …) answer inline as before.
Needs a DynamicObjects with `Deferred`. Returns the current settings; omitted
settings are unchanged. Setting `max_running=0` starts everything still queued.
"""
function configure_job_queue!(; max_running=nothing, abandon_after=nothing)
    q = _JOB_QUEUE
    if max_running !== nothing
        max_running >= 0 || throw(ArgumentError("max_running must be non-negative"))
        max_running > 0 && !isdefined(DynamicObjects, :Deferred) && throw(ArgumentError(
            "configure_job_queue! needs a DynamicObjects with `Deferred`"))
    end
    if abandon_after !== nothing
        abandon_after > 0 || throw(ArgumentError("abandon_after must be positive"))
    end
    released = lock(q.lock) do
        abandon_after === nothing || (q.abandon_after = Float64(abandon_after))
        max_running === nothing && return _QueuedCompute[]
        q.max_running = Int(max_running)
        _job_queue_staff!(q)
        notify(q.ready)             # surplus workers retire
        q.max_running == 0 || return _QueuedCompute[]
        waiting = copy(q.waiting)
        empty!(q.waiting)
        waiting
    end
    # Queue switched off: nothing may be left waiting for a worker.
    for item in released
        errormonitor(Threads.@spawn _job_queue_run(item))
    end
    job_queue_settings()
end

job_queue_settings(q::_JobQueue=_JOB_QUEUE) = lock(q.lock) do
    (; max_running=q.max_running, abandon_after=q.abandon_after,
       queued=length(q.waiting))
end

# The `fetch` selector for a background compute: `identity` spawns it at once,
# a `Deferred` hands it to the queue.
function _operation_background_fetch(req)
    _JOB_QUEUE.max_running > 0 || return identity
    tracker = _runtime_tracker_of(req)
    getproperty(DynamicObjects, :Deferred)(d -> _job_queue_enqueue!(_JOB_QUEUE, d, tracker))
end

_job_queue_key(d) = (objectid(getfield(d, :cache)), getfield(d, :key), UInt(0))

function _job_queue_enqueue!(q::_JobQueue, d, tracker::RuntimeTracker)
    item = _QueuedCompute(d, _job_queue_key(d), tracker, time_ns())
    reap = lock(q.lock) do
        if q.max_running == 0
            # Switched off since this operation chose its selector.
            return nothing
        end
        push!(q.waiting, item)
        _job_queue_staff!(q)
        notify(q.ready; all=false)
        start_reaper = !q.reaping
        q.reaping = true
        start_reaper
    end
    reap === nothing && return errormonitor(Threads.@spawn _job_queue_run(item))
    reap && errormonitor(Threads.@spawn _job_queue_reaper(q))
    nothing
end

# Keep `max_running` workers. The caller holds `q.lock`.
function _job_queue_staff!(q::_JobQueue)
    while q.workers < q.max_running
        q.workers += 1
        # Literal pool symbol: `@spawn` only accepts a computed pool on newer Julia.
        errormonitor(Threads.@spawn :default _job_queue_worker(q))
    end
end

_job_queue_run(item::_QueuedCompute) =
    getproperty(DynamicObjects, :run!)(item.compute)

function _job_queue_worker(q::_JobQueue)
    while true
        item = lock(q.lock) do
            while q.workers <= q.max_running && isempty(q.waiting)
                wait(q.ready)
            end
            if q.workers > q.max_running
                q.workers -= 1          # the queue shrank: retire
                return nothing
            end
            popfirst!(q.waiting)
        end
        item === nothing && return nothing
        # `run!` records a compute's failure for its waiters; never rethrows.
        _job_queue_run(item)
    end
end

# Abandon queued computes nobody watches. Runs while anything is queued. The
# ledger is read without the queue lock held (the ledger never takes it
# either), so the two locks are never nested.
function _job_queue_reaper(q::_JobQueue)
    while true
        interval = lock(q.lock) do
            isempty(q.waiting) && (q.reaping = false; return nothing)
            clamp(q.abandon_after / 4, 0.05, 1.0)
        end
        interval === nothing && return nothing
        sleep(interval)
        _job_queue_reap!(q)
    end
end

function _job_queue_reap!(q::_JobQueue, now_ns::UInt64=time_ns())
    waiting, limit = lock(q.lock) do
        copy(q.waiting), q.abandon_after
    end
    isfinite(limit) || return 0
    stale = filter(waiting) do item
        _runtime_elapsed(_runtime_last_seen(item.tracker, item.key, item.enqueued_ns),
                         now_ns) >= limit
    end
    isempty(stale) && return 0
    lock(q.lock) do
        filter!(item -> !any(s -> s === item, stale), q.waiting)
    end
    reason = "abandoned: unwatched for $(fmt_time(limit))"
    for item in stale
        getproperty(DynamicObjects, :abandon!)(item.compute, reason)
    end
    length(stale)
end

# Queue positions by handle key, 1-based, read under the queue lock alone.
function _job_queue_positions(q::_JobQueue=_JOB_QUEUE)
    lock(q.lock) do
        Dict(item.key => i for (i, item) in enumerate(q.waiting))
    end
end

# --- snapshots -------------------------------------------------------------

_runtime_request_row(r::RuntimeRequest, now_ns::UInt64) = (;
    id=r.id, method=r.method, target=r.target, path=r.path, kind=r.kind,
    route=r.route, mode=r.mode, job=r.job, threadpool=r.threadpool,
    started_at=r.started_at,
    duration=isnan(r.duration) ? _runtime_elapsed(r.started_ns, now_ns) : r.duration,
    running=isnan(r.duration), status=r.status, error=r.error)

_runtime_job_active(j::RuntimeJob) = j.state === :queued || j.state === :running

# A running job whose computation waits in the job queue reads as `:queued`
# with its position (`queued` maps job ids to positions, see
# `_runtime_queued_jobs`).
function _runtime_job_row(j::RuntimeJob, now_ns::UInt64, queued=nothing)
    position = queued === nothing ? j.position : get(queued, j.id, j.position)
    state = position > 0 && _runtime_job_active(j) ? :queued : j.state
    (; id=j.id, label=j.label, route=j.route, target=j.target, state,
       started_at=j.started_at,
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

`(; id, label, route, target, state, started_at, duration, requests, polls,
idle, error, scope, position, progress)`

— `duration` is the time so far for a queued/running job and the wall time of
a finished one, `idle` the time since a request last started, joined or polled
a running job, `position` a queued job's queue position, and `progress` its
progress node (a Treebars tree, or `nothing`). The jobs are selected under the
tracker lock; progress nodes are handed out as they are, for rendering outside
it. A running inline execution's node is read from DynamicObjects on demand.

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

