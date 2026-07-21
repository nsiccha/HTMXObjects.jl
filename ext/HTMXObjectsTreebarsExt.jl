module HTMXObjectsTreebarsExt

# Treebars-aware recording. Sets HTMXObjects's recording shim Refs at
# `__init__` time so the canonical `RecordingState` / `RecordingRoutes`
# (in HTMXObjects core) get live progress instead of the synchronous
# fallback. Refs (vs same-signature method overwriting) keep us inside
# Julia's precompile rules.

import HTMXObjects
import Treebars

function _grace_fetch(render_result, ip, keys, call_kwargs, grace_period)
    grace_period > 0 || return (ready=false, value=nothing)
    HTMXObjects.DynamicObjects.fetchindex(ip, keys...; call_kwargs...) do rv, _status
        if rv isa HTMXObjects.DynamicObjects.Pending
            outcome = timedwait(() -> isready(rv), grace_period;
                                pollint=min(0.005, grace_period))
            outcome === :ok || return (ready=false, value=nothing)
            rv = fetch(rv)
        end
        (ready=true, value=render_result(rv))
    end
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
        (render_result, ip, keys, call_kwargs, transport) -> begin
            fast = _grace_fetch(render_result, ip, keys, call_kwargs,
                                transport.grace_period)
            fast.ready && return fast.value
            treebars_transport = (
                poll_url=transport.poll_url,
                label=transport.label,
                poll_interval=transport.poll_interval,
                keep_progress=transport.keep_progress,
                error_obj=transport.error_obj,
                req=transport.req,
            )
            kwargs = merge(call_kwargs, treebars_transport)
            Treebars.polling_fetchindex(render_result, ip, keys...; kwargs...)
        end
end

end # module
