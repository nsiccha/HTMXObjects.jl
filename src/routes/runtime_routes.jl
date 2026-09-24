# --- RuntimeRoutes ------------------------------------------------------------
#
# Opt-in dev dashboard over the runtime ledgers in `runtime.jl`:
#
#   @include runtime = RuntimeRoutes()        # → /runtime
#
#   GET  /runtime            process summary, running jobs, recent jobs,
#                            in-flight requests, per-route timings, recent requests
#   GET  /runtime/panel      the same view as a fragment (the refresh target)
#   GET  /runtime/jobs       one job board as a fragment (it polls itself)
#   GET  /runtime/snapshot   `runtime_snapshot()` as JSON
#   POST /runtime/clear      forget finished requests and jobs
#
# Every route is `@fresh`: it renders inline on the request's own task. Under
# `:auto`, an ordinary GET would spawn its render onto the `:default` pool and
# poll after the grace period — so on a server whose compute threads are
# saturated, the dashboard would queue behind the very jobs it is meant to
# show. The dashboard also hides its own requests from the history.
#
# Like `TestRoutes` and `SharedOpsRoutes`, this is a development surface: mount
# it where only developers can reach it. It never shows headers, cookies or
# bodies, and request targets are stored redacted (see `runtime.jl`).

_runtime_clock(t::Real) = Libc.strftime("%H:%M:%S", t)

_runtime_duration(t::Real) = isfinite(t) ? fmt_time(t) : "—"

function _runtime_state_badge(state::Symbol)
    state === :running && return status_badge(:running)
    state === :done && return status_badge(:done)
    state === :failed && return status_badge(:failed)
    status_badge(state)
end

function _runtime_status_cell(row)
    row.running && return h.span("…"; class="u-text-muted")
    failed = row.status >= 500 || !isempty(row.error)
    cls = failed ? "u-text-error" : row.status >= 400 ? "u-text-warning" : ""
    h.span(string(row.status), failed && row.status < 500 ? " error" : "";
           class=cls, title=row.error)
end

_runtime_code(x) = h.code(string(x))

# Jobs render on boards, whose items carry their id as a "job" meta item.
_runtime_job_link(id::Int) = id == 0 ? "—" : h.span("#$(id)"; title="job id")

# The transport HTMXObjects chose, as it played out: a polling-capable
# operation that answered within the grace period never became a job.
function _runtime_mode(row)
    row.mode === :none && return "—"
    row.mode in (:polling, :page_load) && row.job == 0 && !row.running &&
        return "inline"
    string(row.mode)
end

function _runtime_table(caption, header, rows; empty="None.")
    isempty(rows) && return h.section(h.h2(caption), h.p(empty; class="u-text-muted"))
    h.section(
        h.h2(caption),
        h.div(h.table(
            h.thead(h.tr((h.th(label; scope="col") for label in header)...)),
            h.tbody(rows...);
            class="striped");
            class="htmxo-runtime-scroll"),
    )
end

# Idle long enough that no client is plausibly still polling: the default
# poll interval is 200ms, so ten seconds of silence means the page is gone.
const _RUNTIME_UNWATCHED_AFTER = 10.0

# --- job boards ---------------------------------------------------------------

# Extension seam: the Treebars extension renders boards with
# `Treebars.htmx_render_board` (keyed, reconciled in place, trees and all).
# Without Treebars, `jobs_board` falls back to a plain list.
const _jobs_board_render_impl = Ref{Any}(nothing)

_jobs_board_ms(seconds::Real) = isfinite(seconds) ? max(0, round(Int, seconds * 1000)) : 0

# Small label/value pairs under an item's header. Targets are stored redacted.
function _jobs_board_meta(row; show_id::Bool=false)
    meta = Pair{String,Any}[]
    show_id && push!(meta, "job" => "#$(row.id)")
    row.state === :queued && row.position > 0 && push!(meta, "position" => row.position)
    isempty(row.route) || push!(meta, "route" => row.route)
    isempty(row.target) || push!(meta, "target" => h.code(row.target))
    row.state in (:done, :failed) && push!(meta, "started" => _runtime_clock(row.started_at))
    row.requests > 1 && push!(meta, "requests" => string(row.requests))
    row.polls > 0 && push!(meta, "polls" => string(row.polls))
    row.state === :running && row.idle >= _RUNTIME_UNWATCHED_AFTER &&
        push!(meta, "unwatched" => fmt_time(row.idle))
    isempty(row.error) || push!(meta, "error" => row.error)
    meta
end

_jobs_board_entry(row; show_id::Bool=false) = (; key=row.id, label=row.label,
    state=row.state, elapsed_ms=_jobs_board_ms(row.duration), node=row.progress,
    meta=_jobs_board_meta(row; show_id))

function _jobs_board_state_text(entry)
    d = fmt_time(entry.elapsed_ms / 1000)
    entry.state === :queued ? "queued" :
    entry.state === :running ? "running for $d" :
    entry.state === :done ? "done in $d" : "failed after $d"
end

# Without Treebars: the same entries as a plain list, replaced wholesale on
# each poll (no trees, no in-place updates).
function _jobs_board_fallback(entries; id, empty, poll_url, poll_interval, kwargs...)
    items = map(entries) do e
        meta = [h.span(" · ", k, " ", v isa Union{AbstractString,Node} ? v : string(v))
                for (k, v) in e.meta]
        h.li(h.strong(e.label), " — ", _jobs_board_state_text(e), meta...;
             data_htmxo_job=string(e.key))
    end
    body = isempty(items) ? h.p(empty; class="u-text-muted") : h.ul(items...)
    isnothing(poll_url) && return h.section(body; id, class="htmxo-jobs")
    h.section(body; id, class="htmxo-jobs", hx_get=string(poll_url),
              hx_trigger="every $(poll_interval)", hx_swap="outerHTML")
end

"""
    jobs_board(; mine=nothing, all=false, tracker=nothing,
               states=(:queued, :running), filter=nothing, recent=3.0,
               poll_url=nothing, poll_interval="1s", id="htmxo-jobs",
               empty="No running jobs.", expanded=false, linger_ms=1500,
               newest_first=false, limit=nothing)

A live board of jobs from the runtime ledger ([`runtime_jobs`](@ref)): each job
with its label, state, elapsed time and — with Treebars loaded — its progress
tree, rendered by `Treebars.htmx_render_board`. With `poll_url` the board polls
that URL every `poll_interval` and updates in place: new jobs appear, running
ones tick and update without resetting an expanded tree, finished ones show
their outcome and leave. Serve it from an `@fresh` route that returns the same
call, so the board never queues behind the work it shows:

```julia
@fresh @get my_jobs() = jobs_board(; mine=__req__, poll_url=query_url(__self__ / "my_jobs"))
```

Whose jobs: `mine=req` shows the jobs started under the requesting session —
operations served by the same `:session`/`:job` root-provider scope and key
(and `track_job!` work reported with such a request). Other sessions' jobs are
never shown unless the caller opts into the global view with `all=true`, as the
developer dashboard does; one of the two is required. With the default
`:request`-scoped provider every request is its own session, so a `mine` board
stays empty: give the app a session-scoped [`RootProvider`](@ref).

`states` selects the jobs (`:queued`, `:running`, `:done`, `:failed`); a board
of queued/running jobs also lists jobs that finished within the last `recent`
seconds, so their outcome shows before they leave. `filter(row) -> Bool`
narrows further (rows as [`runtime_jobs`](@ref) returns them). `newest_first`
and `limit` order and cap the list — for a history board of finished jobs.
`id` must be unique on the page and stable across polls.

Without Treebars the board is a plain list, replaced on each poll.
"""
function jobs_board(; mine=nothing, all::Bool=false, tracker=nothing,
        states=(:queued, :running), filter=nothing, recent::Real=3.0,
        poll_url=nothing, poll_interval="1s", id::AbstractString="htmxo-jobs",
        empty::AbstractString="No running jobs.", expanded::Bool=false,
        linger_ms::Integer=1500, newest_first::Bool=false, limit=nothing,
        _show_ids::Bool=false)
    isnothing(mine) && !all && throw(ArgumentError(
        "jobs_board shows one session's jobs or, explicitly, everyone's: " *
        "pass `mine=req` (the requesting session) or `all=true` (the developer view)"))
    t = tracker isa RuntimeTracker ? tracker : _runtime_tracker_of(mine)
    wanted = states isa Symbol ? (states,) : Tuple(Symbol.(states))
    scope = all ? nothing : mine
    rows = runtime_jobs(t; states=wanted, filter, mine=scope)
    just_finished = Tuple(setdiff((:done, :failed), wanted))
    if recent > 0 && !isempty(just_finished) && any(in((:queued, :running)), wanted)
        append!(rows, runtime_jobs(t; states=just_finished, filter, mine=scope, recent))
    end
    sort!(rows; by=r -> r.id, rev=newest_first)
    isnothing(limit) || (rows = first(rows, max(0, Int(limit))))
    entries = [_jobs_board_entry(row; show_id=_show_ids) for row in rows]
    impl = something(_jobs_board_render_impl[], _jobs_board_fallback)
    impl(entries; id, empty, poll_url, poll_interval, expanded, linger_ms)
end

# The dashboard's boards, one per `state` of the `jobs` route. They sit outside
# the periodically refreshed panels and poll themselves, so an expanded tree
# survives while the rest of the dashboard refreshes.
function _runtime_jobs_board(tracker::RuntimeTracker; prefix::AbstractString,
        state::AbstractString="running", live::Bool=true, limit::Integer=100,
        poll_interval::AbstractString="1s")
    poll_url = live ? query_url("$(prefix)/jobs"; state, limit) : nothing
    if state == "running"
        jobs_board(; all=true, _show_ids=true, tracker, states=(:queued, :running), poll_url,
                   poll_interval, id="htmxo-runtime-jobs", empty="No running jobs.")
    elseif state == "finished"
        jobs_board(; all=true, _show_ids=true, tracker, states=(:done, :failed), poll_url,
                   poll_interval, id="htmxo-runtime-finished", newest_first=true,
                   limit, empty="No finished jobs recorded yet.")
    elseif state == "all"
        jobs_board(; all=true, _show_ids=true, tracker, states=(:queued, :running, :done, :failed),
                   poll_url, poll_interval, id="htmxo-runtime-all", newest_first=true,
                   limit, empty="No jobs recorded yet.")
    else
        throw(ArgumentError("state must be \"running\", \"finished\" or \"all\" (got $(repr(state)))"))
    end
end

function _runtime_inflight(snapshot)
    rows = map(snapshot.inflight) do r
        h.tr(
            h.td(r.method),
            h.td(_runtime_code(r.target)),
            h.td(_runtime_duration(r.duration)),
            h.td(string(r.kind)),
            h.td(_runtime_mode(r)),
            h.td(isempty(r.route) ? "—" : _runtime_code(r.route)),
            h.td(string(r.threadpool)),
            h.td(_runtime_job_link(r.job)),
        )
    end
    _runtime_table("In-flight requests",
        ("Method", "Target", "Age", "Kind", "Mode", "Route", "Pool", "Job"),
        rows; empty="No requests in flight.")
end

function _runtime_routes(snapshot)
    rows = map(snapshot.routes) do s
        h.tr(
            h.td(_runtime_code(s.route)),
            h.td(string(s.count)),
            h.td(s.errors == 0 ? "0" : h.span(string(s.errors); class="u-text-error")),
            h.td(_runtime_duration(s.p50)),
            h.td(_runtime_duration(s.p95)),
            h.td(_runtime_duration(s.max)),
            h.td(_runtime_duration(s.total)),
        )
    end
    _runtime_table("Route timings",
        ("Route", "Requests", "Errors", "p50", "p95", "Max", "Total"),
        rows; empty="No finished requests recorded yet.")
end

function _runtime_history(snapshot; limit::Int)
    rows = map(Iterators.take(snapshot.history, limit)) do r
        h.tr(
            h.td(_runtime_clock(r.started_at)),
            h.td(r.method),
            h.td(_runtime_code(r.target)),
            h.td(_runtime_status_cell(r)),
            h.td(_runtime_duration(r.duration)),
            h.td(string(r.kind)),
            h.td(_runtime_mode(r)),
            h.td(string(r.threadpool)),
            h.td(_runtime_job_link(r.job)),
        )
    end
    shown = min(limit, length(snapshot.history))
    caption = shown < length(snapshot.history) ?
        "Recent requests (latest $(shown) of $(length(snapshot.history)))" :
        "Recent requests"
    _runtime_table(caption,
        ("At", "Method", "Target", "Status", "Took", "Kind", "Mode", "Pool", "Job"),
        collect(rows); empty="No finished requests recorded yet.")
end

function _runtime_process_summary(p)
    oversubscribed = p.running_jobs > p.threads_default
    items = Any[
        "up " * fmt_time(p.uptime),
        "threads $(p.threads_default) default · $(p.threads_interactive) interactive",
        oversubscribed ?
            h.span("$(p.running_jobs) running jobs > $(p.threads_default) compute threads";
                   class="u-text-warning",
                   title="More long-running jobs than :default threads: they are time-sharing the pool and will all finish later.") :
            "$(p.running_jobs) running jobs",
        "heap " * fmt_bytes(p.live_bytes),
        "GC " * fmt_time(p.gc_time),
        "free " * fmt_bytes(p.free_memory) * " / " * fmt_bytes(p.total_memory),
        "$(p.total_requests) requests · $(p.total_jobs) jobs since start",
    ]
    children = Any[]
    for (i, item) in enumerate(items)
        i == 1 || push!(children, " · ")
        push!(children, item)
    end
    h.p(children...; class="u-text-muted")
end

const _RUNTIME_STYLES = """
.htmxo-runtime-scroll { overflow-x: auto; }
.htmxo-runtime td code { white-space: nowrap; }
.htmxo-runtime .treebar-board-meta code { font-size: 0.95em; padding: 0 0.25em; }
"""

# A region of the dashboard that refreshes itself: it re-fetches the panel and
# selects its own part of the response, so the job boards between the regions
# — which poll and reconcile on their own — are never replaced.
function _runtime_region(id::AbstractString, children...; prefix, live::Bool,
        refresh::AbstractString, limit::Int)
    live || return h.div(children...; id)
    h.div(children...; id, hx_get=query_url("$(prefix)/panel"; limit),
          hx_trigger="every $(refresh)", hx_select="#$(id)", hx_target="this",
          hx_swap="outerHTML")
end

"""
    runtime_dashboard(tracker=runtime_tracker(); prefix="/runtime", live=true,
                      refresh="2s", limit=100)

Render the runtime dashboard for `tracker`: a process summary, the running and
the latest `limit` finished jobs as live job boards (see [`jobs_board`](@ref);
with Treebars, each with its progress tree), in-flight requests, per-route
timings, and the latest `limit` finished requests. With `live=true` the boards
poll `\$prefix/jobs` and the other sections re-fetch `\$prefix/panel` every
`refresh`; `live=false` renders a still snapshot. Used by
[`RuntimeRoutes`](@ref); callable directly to embed the view elsewhere.
"""
function runtime_dashboard(tracker::RuntimeTracker=runtime_tracker();
        prefix::AbstractString="/runtime", live::Bool=true,
        refresh::AbstractString="2s", limit::Integer=100)
    snapshot = runtime_snapshot(tracker)
    limit = max(0, Int(limit))
    toggle = live ?
        h.a("Pause"; href=query_url(prefix; live=false, limit),
            hx_get=query_url("$(prefix)/panel"; live=false, limit),
            hx_target="#htmxo-runtime", hx_swap="outerHTML") :
        h.a("Resume"; href=query_url(prefix; limit),
            hx_get=query_url("$(prefix)/panel"; limit),
            hx_target="#htmxo-runtime", hx_swap="outerHTML")
    controls = h.p(
        toggle, " · ",
        h.a("JSON"; href="$(prefix)/snapshot"), " · ",
        h.button("Clear history"; type="button", class="secondary",
                 hx_post=query_url("$(prefix)/clear"; live, limit),
                 hx_target="#htmxo-runtime", hx_swap="outerHTML"),
    )
    region(id, children...) = _runtime_region(id, children...; prefix, live, refresh, limit)
    h.section(
        h.style(_RUNTIME_STYLES),
        h.h1("Runtime"),
        region("htmxo-runtime-summary", _runtime_process_summary(snapshot.process)),
        controls,
        h.section(h.h2("Running jobs"),
                  _runtime_jobs_board(tracker; prefix, state="running", live, limit)),
        h.section(h.h2("Recent jobs"),
                  _runtime_jobs_board(tracker; prefix, state="finished", live, limit,
                                      poll_interval=refresh)),
        region("htmxo-runtime-panel",
            _runtime_inflight(snapshot),
            _runtime_routes(snapshot),
            _runtime_history(snapshot; limit));
        id="htmxo-runtime", class="htmxo-runtime",
    )
end

"""
    RuntimeRoutes(; tracker=nothing, refresh="2s")

Mountable dev dashboard for current and past requests and jobs. Mount it opt-in
on any `@htmx struct`:

```julia
@include runtime = RuntimeRoutes()        # → GET /runtime
```

Provides:

- `@get index(; live=true, limit=100)` — the dashboard: process summary
  (thread pools, running-job count against `:default` threads, heap, GC), the
  running jobs and the most recent finished ones as live job boards — each job
  with its progress tree, how long it has run and how long since a client last
  polled it — in-flight requests with their age, per-route p50/p95/max
  timings, and the most recent finished requests. The boards poll `jobs`; the
  other sections refresh every `refresh` while `live`.
- `@get panel(; live=true, limit=100)` — the same view as a fragment (the refresh target).
- `@get jobs(; state="running", limit=100)` — one job board as a fragment that
  polls itself: `"running"` (queued and running jobs, plus those that just
  finished), `"finished"` (the latest `limit`, newest first) or `"all"`. It
  shows every session's jobs: this is the developer view (see
  [`jobs_board`](@ref) for per-session boards on app pages).
- `@get snapshot()` — [`runtime_snapshot`](@ref) as JSON.
- `@post clear()` — [`clear_runtime_history!`](@ref).

Requests are recorded by [`track_requests`](@ref), which [`serve`](@ref)
installs by default; jobs are recorded by HTMXObjects' operation layer for every
execution that outlives the `:auto` grace period, and by [`track_job!`](@ref)
for work it did not start (hand-rolled Treebars pollers report themselves).
`tracker=nothing` shows the global [`runtime_tracker`](@ref).

Every route is `@fresh`: it renders inline on the request's own task, so the
dashboard never queues behind a saturated compute pool — the situation it
exists to diagnose.

This is a development surface in the same sense as [`TestRoutes`](@ref): mount
it only where developers can reach it. It shows request paths and query
arguments (bearer tokens and credential-like parameters redacted), never
headers, cookies or bodies.
"""
@htmx struct RuntimeRoutes
    tracker::Any = nothing
    refresh::String = "2s"

    @fresh @get index(; live::Bool=true, limit::Int=100) = begin
        _runtime_hide_request!(__req__)
        runtime_dashboard(something(tracker, runtime_tracker());
                          prefix=string(__self__), live, refresh, limit)
    end
    @fresh @get panel(; live::Bool=true, limit::Int=100) = begin
        _runtime_hide_request!(__req__)
        runtime_dashboard(something(tracker, runtime_tracker());
                          prefix=string(__self__), live, refresh, limit)
    end
    @fresh @get jobs(; state::String="running", limit::Int=100) = begin
        _runtime_hide_request!(__req__)
        _runtime_jobs_board(something(tracker, runtime_tracker());
                            prefix=string(__self__), state, limit=max(0, limit),
                            poll_interval=state == "running" ? "1s" : refresh)
    end
    @fresh @get snapshot() = begin
        _runtime_hide_request!(__req__)
        MIMEResponse("application/json",
            _schema_json_encode(runtime_snapshot(something(tracker, runtime_tracker()))))
    end
    @post clear(; live::Bool=true, limit::Int=100) = begin
        _runtime_hide_request!(__req__)
        t = something(tracker, runtime_tracker())
        clear_runtime_history!(t)
        runtime_dashboard(t; prefix=string(__self__), live, refresh, limit)
    end
end

# The dashboard never lists its own work (see `_runtime_untracked`).
_runtime_untracked(::RuntimeRoutes) = true
