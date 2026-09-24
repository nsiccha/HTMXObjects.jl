# --- RuntimeRoutes ------------------------------------------------------------
#
# Opt-in dev dashboard over the runtime ledgers in `runtime.jl`:
#
#   @include runtime = RuntimeRoutes()        # → /runtime
#
#   GET  /runtime            process summary, running jobs, in-flight requests,
#                            per-route timings, recent jobs, recent requests
#   GET  /runtime/panel      the same view as a fragment (the refresh target)
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

_runtime_job_link(id::Int) =
    id == 0 ? "—" : h.a("#$(id)"; href="#runtime-job-$(id)")

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

# A job's progress tree (Treebars) inside a <details>. The id lets the refresh
# script keep an opened tree open across swaps.
function _runtime_progress_details(tracker::RuntimeTracker, job)
    tree = try
        _runtime_progress_render(_runtime_job_progress(tracker, job.id))
    catch
        nothing
    end
    tree === nothing && return "—"
    h.details(h.summary("progress"), tree;
              data_runtime_details="job-$(job.id)")
end

# Idle long enough that no client is plausibly still polling: the default
# poll interval is 200ms, so ten seconds of silence means the page is gone.
const _RUNTIME_UNWATCHED_AFTER = 10.0

function _runtime_running_jobs(tracker, snapshot)
    rows = map(snapshot.running) do job
        idle = job.idle >= _RUNTIME_UNWATCHED_AFTER ?
            h.span("unwatched $(fmt_time(job.idle))"; class="u-text-warning",
                   title="No request has started, joined or polled this job recently; it keeps computing anyway.") :
            fmt_time(job.idle)
        h.tr(
            h.td(h.strong(job.label), h.div(_runtime_code(job.target); class="u-text-xs");
                 id="runtime-job-$(job.id)"),
            h.td(_runtime_duration(job.duration)),
            h.td(string(job.requests)),
            h.td(string(job.polls)),
            h.td(idle),
            h.td(_runtime_progress_details(tracker, job)),
        )
    end
    _runtime_table("Running jobs",
        ("Job", "Running for", "Requests", "Polls", "Last seen", "Progress"),
        rows; empty="No long-running jobs.")
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

function _runtime_finished_jobs(tracker, snapshot; limit::Int)
    rows = map(Iterators.take(snapshot.finished, limit)) do job
        h.tr(
            h.td(h.strong(job.label), h.div(_runtime_code(job.target); class="u-text-xs");
                 id="runtime-job-$(job.id)"),
            h.td(_runtime_clock(job.started_at)),
            h.td(_runtime_state_badge(job.state),
                 isempty(job.error) ? "" : h.div(job.error; class="u-text-xs u-text-error")),
            h.td(_runtime_duration(job.duration)),
            h.td(string(job.requests)),
            h.td(string(job.polls)),
            h.td(_runtime_progress_details(tracker, job)),
        )
    end
    _runtime_table("Recent jobs",
        ("Job", "Started", "Outcome", "Took", "Requests", "Polls", "Progress"),
        collect(rows); empty="No finished jobs recorded yet.")
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

# Keeps an opened progress <details> open across the periodic outerHTML swap.
const _RUNTIME_DETAILS_SCRIPT = """
(function () {
  if (window.__htmxoRuntimeDetails) return;
  window.__htmxoRuntimeDetails = new Set();
  document.addEventListener("toggle", function (event) {
    var el = event.target;
    if (!el.dataset || !el.dataset.runtimeDetails) return;
    if (el.open) window.__htmxoRuntimeDetails.add(el.dataset.runtimeDetails);
    else window.__htmxoRuntimeDetails.delete(el.dataset.runtimeDetails);
  }, true);
  document.addEventListener("htmx:afterSettle", function () {
    document.querySelectorAll("details[data-runtime-details]").forEach(function (el) {
      if (window.__htmxoRuntimeDetails.has(el.dataset.runtimeDetails)) el.open = true;
    });
  });
})();
"""

const _RUNTIME_STYLES = """
.htmxo-runtime-scroll { overflow-x: auto; }
.htmxo-runtime td code { white-space: nowrap; }
.htmxo-runtime details > summary { cursor: pointer; }
"""

"""
    runtime_dashboard(tracker=runtime_tracker(); prefix="/runtime", live=true,
                      refresh="2s", limit=100)

Render the runtime dashboard for `tracker`: a process summary, running jobs,
in-flight requests, per-route timings, and the latest `limit` finished jobs and
requests. With `live=true` the view re-fetches `\$prefix/panel` every `refresh`.
Used by [`RuntimeRoutes`](@ref); callable directly to embed the view elsewhere.
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
    attrs = live ?
        (; id="htmxo-runtime", class="htmxo-runtime",
           hx_get=query_url("$(prefix)/panel"; limit),
           hx_trigger="every $(refresh)", hx_swap="outerHTML") :
        (; id="htmxo-runtime", class="htmxo-runtime")
    h.section(
        h.style(_RUNTIME_STYLES),
        h.script(Raw(_RUNTIME_DETAILS_SCRIPT)),
        h.h1("Runtime"),
        _runtime_process_summary(snapshot.process),
        controls,
        _runtime_running_jobs(tracker, snapshot),
        _runtime_inflight(snapshot),
        _runtime_routes(snapshot),
        _runtime_finished_jobs(tracker, snapshot; limit),
        _runtime_history(snapshot; limit);
        attrs...,
    )
end

"""
    RuntimeRoutes(; tracker=nothing, refresh="2s")

Mountable dev dashboard for current and past requests and long-running jobs.
Mount it opt-in on any `@htmx struct`:

```julia
@include runtime = RuntimeRoutes()        # → GET /runtime
```

Provides:

- `@get index(; live=true, limit=100)` — the dashboard: process summary
  (thread pools, running-job count against `:default` threads, heap, GC),
  running jobs with their progress trees and how long since a client last
  polled them, in-flight requests with their age, per-route p50/p95/max
  timings, and the most recent finished jobs and requests. Refreshes itself
  every `refresh` while `live`.
- `@get panel(; live=true, limit=100)` — the same view as a fragment (the refresh target).
- `@get snapshot()` — [`runtime_snapshot`](@ref) as JSON.
- `@post clear()` — [`clear_runtime_history!`](@ref).

Requests are recorded by [`track_requests`](@ref), which [`serve`](@ref)
installs by default; jobs are recorded by HTMXObjects' operation layer whenever
an operation outlives the `:auto` grace period. `tracker=nothing` shows the
global [`runtime_tracker`](@ref).

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
