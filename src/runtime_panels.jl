"""
    poll_trigger(interval) -> String

An htmx timed trigger that pauses while the document is hidden. A returning tab
refreshes on the next interval. Use `"load, " * poll_trigger("2s")` for an initial
load as well. This pauses browser refreshes, not server-side work already running.
"""
poll_trigger(interval::AbstractString) = "every $interval [!document.hidden]"

"""
    process_rss_bytes() -> Int

Current resident memory of this process, measured by libuv. Unlike
`Sys.maxrss()`, this is not a historical peak. It includes the Julia heap,
resident mapped files, native libraries and compiled code.
"""
function process_rss_bytes()
    rss = Ref{Csize_t}(0)
    result = ccall(:uv_resident_set_memory, Cint, (Ref{Csize_t},), rss)
    result == 0 || error("uv_resident_set_memory failed with libuv error $result")
    Int(rss[])
end

_runtime_memory() = (; rss_bytes=process_rss_bytes(), live_bytes=Base.gc_live_bytes(),
    free_memory=Float64(Sys.free_memory()), total_memory=Float64(Sys.total_memory()),
    load_average=Tuple(Sys.loadavg()))

"""
    system_load_panel(load_url; interval="2s", attrs...)

A self-refreshing fragment showing load average, current process RSS, live Julia
heap and system memory. Serve it from `load_url`. It uses the same measurements
as `runtime_snapshot().process` and pauses polling in hidden tabs. Extra attributes
belong to its outer element. No garbage collection runs while rendering it.
"""
function system_load_panel(load_url; interval="2s", attrs...)
    p = _runtime_memory()
    h.div(
        h.dl(h.dt("Load (1 min)"), h.dd(string(round(first(p.load_average); digits=2))),
            h.dt("Process RSS"), h.dd(fmt_bytes(p.rss_bytes)),
            h.dt("Julia heap"), h.dd(fmt_bytes(p.live_bytes)),
            h.dt("System memory"), h.dd(fmt_bytes(p.total_memory - p.free_memory),
                " / ", fmt_bytes(p.total_memory)),
            _worker_dl_items()...);
        class="htmxo-system-load", hx_get=load_url, hx_trigger=poll_trigger(interval),
        hx_swap="outerHTML", attrs...)
end

# The job queue's worker process (`configure_job_queue!(; workers=1)`), when
# one is configured: its pid, what it has in flight and how fresh its last
# message is, so a stall shows here before the watchdog acts.
function _worker_dl_items()
    status = _worker_status()
    (status === nothing || status.workers == 0) && return ()
    text = if status.running
        age = status.last_message_at isa Real ?
            string(", last message ", round(Int, time() - status.last_message_at), " s ago") : ""
        string("pid ", status.pid, ", ", status.in_flight, " in flight", age)
    else
        "configured, not running"
    end
    (h.dt("Worker"), h.dd(text))
end

const _MEMORY_COLLECTION_LOCK = ReentrantLock()
const _LAST_MEMORY_COLLECTION = Ref{Any}(nothing)

"""
    collect_and_measure!() -> NamedTuple

Run one full `GC.gc(true)` and return `(; at, seconds, rss_before, heap_before,
rss_after, heap_after)`, with byte counts and a Unix completion timestamp.
Collections through this API are serialized; only the latest result is retained.
Call from an explicit POST action, never a polling GET: a full collection pauses
all Julia threads. RSS also includes mapped files, native allocations and code;
the post-collection heap is the live Julia data.
"""
function collect_and_measure!()
    lock(_MEMORY_COLLECTION_LOCK) do
        rss_before = process_rss_bytes()
        heap_before = Int(Base.gc_live_bytes())
        seconds = @elapsed GC.gc(true)
        result = (; at=time(), seconds, rss_before, heap_before,
            rss_after=process_rss_bytes(), heap_after=Int(Base.gc_live_bytes()))
        _LAST_MEMORY_COLLECTION[] = result
        result
    end
end

"""
    last_memory_collection()

The latest `collect_and_measure!()` result in this process, or `nothing` before
the first collection. Reading it never runs a collection.
"""
last_memory_collection() = lock(() -> _LAST_MEMORY_COLLECTION[], _MEMORY_COLLECTION_LOCK)

"""
    memory_collect_panel(collect_url; measurement=nothing)

An explicit "Collect & measure" POST action and optional before/after memory
measurement. The POST route calls `collect_and_measure!()` and returns this
panel with that result. Keep it beside, not inside, a self-refreshing load panel
so a poll does not replace the result. No collection runs while rendering it.
"""
function memory_collect_panel(collect_url; measurement=nothing)
    result = if isnothing(measurement)
        nothing
    else
        m = measurement
        h.dl(h.dt("Retained Julia heap"), h.dd(fmt_bytes(m.heap_after)),
            h.dt("Process RSS after collection"), h.dd(fmt_bytes(m.rss_after)),
            h.dt("Before collection"), h.dd("heap ", fmt_bytes(m.heap_before),
                " · RSS ", fmt_bytes(m.rss_before)),
            h.dt("Collection"), h.dd(fmt_time(m.seconds), " at ",
                Libc.strftime("%H:%M:%S", m.at)))
    end
    h.div(result,
        h.button("Collect & measure"; hx_post=collect_url,
            hx_target="closest .htmxo-memory-collect", hx_swap="outerHTML",
            title="Run a full garbage collection and measure memory. All Julia threads pause until it finishes.");
        class="htmxo-memory-collect")
end
