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
    grace_started = time_ns()
    # A route may finish by returning another Pending. Follow that chain only
    # inside the original grace budget; rendering an unresolved inner handle
    # would synchronously fetch it and hold the request open.
    while rv isa HTMXObjects.DynamicObjects.Pending
        elapsed = (time_ns() - grace_started) / 1.0e9
        remaining = grace_period - elapsed
        remaining > 0 || return (ready=false, value=nothing)
        outcome = timedwait(() -> isready(rv), remaining;
                            pollint=min(0.005, remaining))
        outcome === :ok || return (ready=false, value=nothing)
        rv = fetch(rv)
    end
    (ready=true, value=render_result(rv))
end

function _operation_ready_terminal(render_result, started)
    value = started
    while value isa HTMXObjects.DynamicObjects.Pending
        isready(value) || return (ready=false, value=nothing)
        try
            value = fetch(value)
        catch
            # A failed operation is not a value-terminal: answer unresolved
            # so the normal path renders it (`safely` + failure article +
            # open tree).
            return (ready=false, value=nothing)
        end
    end
    terminal = render_result(value)
    # Dual-class terminal: the trigger-less `.treebar-poller-inner` is the
    # shape every deployed poller hx-select matches — the live select has no
    # `.treebar-terminal-content` branch, so the bare marker swapped an EMPTY
    # fragment — while `.treebar-terminal-content` keys the client finalizer
    # that terminalizes the wrapper once Treebars ships it. One node, not
    # nested: the top-level-only select excludes a nested match, and the
    # finalizer reads the class off the swapped node itself.
    # `data-htmxo-auto-terminal` marks this node as an `:auto` terminal for
    # `auto_terminal_script` (core): on `htmx:afterSwap` the shell replaces
    # the live poller wrapper with the node's bare content, so the caller's
    # target ends with exactly the route fragment — a wrapper div cannot be
    # a direct child of a structural element (`details`/`summary`,
    # `table`/`tr`, `select`/`option`, …). The response shape is unchanged,
    # so shells without the script keep the wrapper (status quo) and every
    # select generation still matches.
    (ready=true, value=HTMXObjects.h.div(terminal;
        class="treebar-poller-inner treebar-terminal-content",
        data_htmxo_auto_terminal=""))
end

function _operation_render_result(render_result, value, transport)
    rendered = render_result(value)
    transport.replace_page_load || return rendered

    terminal = HTMXObjects.h.div(
        rendered;
        id=transport.page_load_id,
        class="htmxo-operation-terminal",
        data_htmxo_operation_terminal="",
        hx_swap_oob="outerHTML",
    )
    # Treebars' running fragment selects its own inner region from every poll
    # response. Keep that selector satisfied while the nested OOB fragment
    # replaces HTMXObjects' stable direct-page wrapper as a whole, removing the
    # now-terminal poller and its Pause control.
    HTMXObjects.h.div(terminal; class="treebar-poller-inner")
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

    HTMXObjects._progress_attach_impl[] =
        (parent, node) -> Treebars.add_child!(parent, node)

    # Ambient dispatch-parent protocol (companion of Treebars `b4c2182`):
    # route bodies nesting a bare `polling_fetchindex` resolve the caller
    # node through `parent=:auto`. Guarded so the extension still loads
    # against Treebars generations that predate the protocol — the base
    # seam's passthrough stays installed and nothing binds.
    isdefined(Treebars, :with_dispatch_parent) &&
        (HTMXObjects._with_dispatch_parent_impl[] = Treebars.with_dispatch_parent)

    HTMXObjects._operation_polling_impl[] =
        (render_result, started, ip, keys, call_kwargs, transport) -> begin
            render_operation_result = value ->
                _operation_render_result(render_result, value, transport)
            fast = HTMXObjects._operation_grace_fetch(
                render_operation_result, started, transport.grace_period)
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
                # The operation layer records this job itself (`retain`).
                track_job=false,
            )
            kwargs = merge(call_kwargs, treebars_transport)
            responded = try
                Treebars.polling_fetchindex(
                    render_operation_result, ip, keys...; kwargs...)
            catch
                # keep_progress=true renders failures internally; propagated
                # failures (including keep_progress=false) have no future poll.
                transport.cleanup()
                rethrow()
            end
            # Completion-boundary settle: the operation may have resolved
            # inside the Treebars call above — its fetch re-reads the cache
            # after this closure's grace check. Without this re-probe that
            # poll renders Treebars' done terminal, kept tree and all,
            # instead of `:auto`'s bare terminal, so "resolved polls answer
            # bare" would hold only outside a microsecond race. Re-probing is
            # race-free in the other direction: a still-running operation
            # keeps its running poller and settles on a later poll, and a
            # failed one never probes ready, so Treebars' failure rendering
            # (recorded error + open tree) passes through untouched. Skipped
            # for direct-page OOB replacement (which renders its own terminal
            # shape) and for `keep_terminal_tree` (whose resolutions render
            # Treebars' done terminal by design). An initial request has no
            # live poller, so it settles to the bare value — the same answer
            # the grace fast path would have given — while resume/heal settle
            # to the marked terminal their live poller selects.
            if !transport.replace_page_load && !transport.keep_terminal_tree
                settled = transport.settle_bare ?
                    HTMXObjects._operation_ready_terminal_fallback(
                        render_operation_result, started) :
                    HTMXObjects._operation_ready_terminal(
                        render_operation_result, started)
                settled.ready && return settled.value
            end
            responded
        end

    # Job boards (`jobs_board`, the runtime dashboard): a keyed Treebars board,
    # reconciled in place on the client. Guarded like the dispatch-parent
    # protocol: an older Treebars keeps `jobs_board`'s plain-list fallback.
    isdefined(Treebars, :htmx_render_board) &&
        (HTMXObjects._jobs_board_render_impl[] =
            (entries; kwargs...) -> Treebars.htmx_render_board(entries; kwargs...))

    HTMXObjects._operation_ready_terminal_impl[] = _operation_ready_terminal
    HTMXObjects._polling_page_assets_impl[] =
        () -> (Treebars.htmx_treebar_styles(), Treebars.htmx_treebar_script())
end

end # module
