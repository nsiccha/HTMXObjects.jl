module HTMXObjectsTreebarsExt

# Treebars-aware recording. Sets HTMXObjects's recording shim Refs at
# `__init__` time so the canonical `RecordingState` / `RecordingRoutes`
# (in HTMXObjects core) get live progress instead of the synchronous
# fallback. Refs (vs same-signature method overwriting) keep us inside
# Julia's precompile rules.

import HTMXObjects
import Treebars

function _grace_fetch(render_result, started, grace_period)
    rv = started
    if rv isa HTMXObjects.DynamicObjects.Pending
        grace_period > 0 || return (ready=false, value=nothing)
        outcome = timedwait(() -> isready(rv), grace_period;
                            pollint=min(0.005, grace_period))
        outcome === :ok || return (ready=false, value=nothing)
        rv = fetch(rv)
    end
    (ready=true, value=render_result(rv))
end

function __init__()
    HTMXObjects._recording_progress_init_impl[] =
        () -> Treebars.initialize_progress!(:state; description="Recording")

    HTMXObjects._recording_progress_phase_impl[] =
        (parent, description) -> Treebars.prepare_progress!(parent; description)

    HTMXObjects._recording_run_phase_impl[] =
        (f, phase) -> Treebars.with_prepared_progress(f, phase)

    HTMXObjects._recording_polling_impl[] =
        (args...; kwargs...) -> Treebars.polling_fetchindex(args...; kwargs...)

    HTMXObjects._operation_polling_impl[] =
        (render_result, started, ip, keys, call_kwargs, transport) -> begin
            fast = _grace_fetch(render_result, started, transport.grace_period)
            fast.ready && return fast.value
            # Only retain operations that actually cross the grace boundary and
            # emit a poller. Fast values and test seams that replace this
            # extension never occupy the bounded operation registry.
            transport.retain()
            treebars_transport = (
                poll_url=transport.poll_url,
                label=transport.label,
                poll_interval=transport.poll_interval,
                keep_progress=transport.keep_progress,
                error_obj=transport.error_obj,
                req=transport.req,
            )
            kwargs = merge(call_kwargs, treebars_transport)
            try
                Treebars.polling_fetchindex(render_result, ip, keys...; kwargs...)
            catch
                # keep_progress=true renders failures internally; propagated
                # failures (including keep_progress=false) have no future poll.
                transport.cleanup()
                rethrow()
            end
        end
end

end # module
