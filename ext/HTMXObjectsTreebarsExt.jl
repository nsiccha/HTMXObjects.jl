module HTMXObjectsTreebarsExt

# Treebars-aware recording. Sets HTMXObjects's recording shim Refs at
# `__init__` time so the canonical `RecordingState` / `RecordingRoutes`
# (in HTMXObjects core) get live progress instead of the synchronous
# fallback. Refs (vs same-signature method overwriting) keep us inside
# Julia's precompile rules.

import HTMXObjects
import HTTP
import Treebars

function _operation_ready_terminal(render_result, started)
    value = started
    while value isa HTMXObjects._OperationHandle
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
    # An operation answered with a finalized response (`HTTP.Response`,
    # `MIMEResponse`) its route did not declare — `hx_response`, a
    # `dispatch`ed sub-request — keeps its headers on the poll response,
    # with its body inside the same terminal node.
    finalized = HTMXObjects._finalized_response(terminal)
    finalized === nothing ||
        return (ready=true, value=HTMXObjects._operation_finalized_terminal(finalized))
    # The dual-class, marked terminal node the shell unwraps to the bare
    # route fragment, in an element that can parent it (core
    # `_auto_terminal_node`).
    (ready=true, value=HTMXObjects._auto_terminal_node(terminal))
end

# `track_job` (the job-ledger hook `polling_fetchindex` reports through)
# and `htmx_render_board` (keyed boards) arrived in the SAME Treebars
# commit (`8bde866`), and the board binding is a core stub — present as
# soon as Treebars loads. So the board binding doubles as the hook
# probe: only a Treebars that declares the kwarg gets it. Older
# Treebars forwards unknown kwargs into `fetchindex`, where the
# route's strict `iscached` rejects `track_job` with a MethodError —
# recorded under a poisoned cache key, so every later poll of the
# operation renders the failure article instead (snag
# track-job-forwar-44464e91). Probe the core binding, never the
# extension method's kwargs: at `__init__` time Treebars' own
# extension may not be loaded yet, and its `kwargs...` slurp would
# accept the probe syntactically anyway.
_treebars_tracks_jobs() = isdefined(Treebars, :htmx_render_board)

function _operation_treebars_kwargs(call_kwargs, transport,
        treebars_tracks_jobs::Bool)
    treebars_transport = (
        poll_url=transport.poll_url,
        label=transport.label,
        poll_interval=transport.poll_interval,
        keep_progress=transport.keep_progress,
        error_obj=transport.error_obj,
        req=transport.req,
    )
    kwargs = merge(call_kwargs, treebars_transport)
    # The operation layer records this job itself (`retain`), so a
    # hook-capable Treebars must not track it again — but only such a
    # Treebars understands `track_job` (see `_treebars_tracks_jobs`).
    treebars_tracks_jobs ? merge(kwargs, (; track_job=false)) : kwargs
end

# The framework-generated auto poll URL already holds the operation's captured
# arguments. Keep htmx from adding ancestor hx-vals, hx-include, or form fields
# to that URL on each poll. Hand-shaped Treebars pollers retain their normal
# inheritance, including their current-arguments recovery behavior.
_isolate_auto_poll_params(response) =
    HTMXObjects._operation_running_answer(response) ?
        response(; hx_params="none") : response

# A stalled operation's poll answers `OperationStalled` through the route error
# pipeline (error log, hooks, `X-HTMXO-Error-Id`), inside the terminal shape
# Treebars gives a failed operation, so the live poller selects it, stops and
# terminalizes: the failure, the open progress tree of what was still running,
# and — for a read — a Run again button that replaces this terminal content with
# a fresh request of the operation (it targets the content node it sits in, so
# it works whether or not the page runs Treebars' client finalizer). The
# registry entry goes: nothing polls it again.
function _operation_stalled_response(stall, ip, keys, call_kwargs, transport)
    transport.cleanup()
    status = try
        HTMXObjects.getstatus(ip, keys...; call_kwargs...)
    catch err
        @debug "HTMXObjects: no progress status for a stalled operation" exception=(err, catch_backtrace())
        nothing
    end
    tree = isnothing(status) ? "" :
        HTMXObjects.h.details(class="treebar-frozen", open=true)(
            HTMXObjects.h.summary("Progress"),
            Treebars.htmx_render(status; scoped=true))
    rerun = stall.error.rerun_url === nothing ? "" :
        HTMXObjects.h.p(HTMXObjects.h.button("Run again"; type="button",
            class="htmxo-operation-rerun", hx_get=stall.error.rerun_url,
            hx_target="closest .treebar-terminal-content",
            hx_swap="outerHTML",
            hx_params="none"))
    HTMXObjects._route_error_response(stall.req, stall.error, backtrace();
        error_obj=transport.error_obj,
        wrap=failure -> HTMXObjects.h.div(class="treebar-terminal")(
            HTMXObjects.h.div(class="treebar-terminal-content")(failure, tree,
                                                                rerun)))
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

    # A background fresh operation's own progress root: a detached, bare
    # node (empty description, so it renders no header row of its own). The
    # invocation runs through DynamicObjects' `maybeprogress!`, which opens
    # the route's documented substatus beneath it — the same labelled node a
    # memoized operation's poller renders.
    HTMXObjects._fresh_operation_root_impl[] =
        () -> Treebars.initialize_progress!(:state; description="")

    # Ambient dispatch-parent protocol (companion of Treebars `b4c2182`):
    # route bodies nesting a bare `polling_fetchindex` resolve the caller
    # node through `parent=:auto`. Guarded so the extension still loads
    # against Treebars generations that predate the protocol — the base
    # seam's passthrough stays installed and nothing binds.
    isdefined(Treebars, :with_dispatch_parent) &&
        (HTMXObjects._with_dispatch_parent_impl[] = Treebars.with_dispatch_parent)

    HTMXObjects._operation_polling_impl[] =
        (render_result, started, ip, keys, call_kwargs, transport) -> begin
            fast = HTMXObjects._operation_grace_fetch(
                value -> _operation_render_result(render_result, value, transport),
                started, transport.grace_period)
            fast.ready && return fast.value
            finalized_terminal = Ref{Union{Nothing,HTTP.Response}}(nothing)
            render_operation_result = value -> begin
                rendered = _operation_render_result(render_result, value, transport)
                transport.keep_terminal_tree || return rendered
                finalized = HTMXObjects._finalized_response(rendered)
                finalized === nothing && return rendered
                # Treebars renders a kept terminal as HTML. Give it the
                # finalized body, then attach the response headers to the
                # whole terminal after Treebars has built its frozen tree.
                finalized_terminal[] = finalized
                HTMXObjects.Raw(HTMXObjects._operation_terminal_body(finalized))
            end
            # Only retain operations that actually cross the grace boundary and
            # emit a poller. Fast values and test seams that replace this
            # extension never occupy the bounded operation registry.
            transport.retain()
            kwargs = _operation_treebars_kwargs(
                call_kwargs, transport, _treebars_tracks_jobs())
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
            if finalized_terminal[] !== nothing
                # An answer its headers send elsewhere (`HX-Retarget`, …)
                # retires the poller instead of replacing it, so there is no
                # place for a kept tree: answer the bare terminal.
                HTMXObjects._operation_redirects_swap(finalized_terminal[]) &&
                    return HTMXObjects._operation_finalized_terminal(
                        finalized_terminal[])
                html = HTMXObjects.to_response(responded)
                return HTTP.Response(200,
                    HTMXObjects._operation_terminal_headers(finalized_terminal[]);
                    body=HTMXObjects._message_body_bytes(html))
            end
            # Past its stall bound, an operation that would still answer the
            # running poller answers `OperationStalled` instead.
            stall = get(transport, :stalled, nothing)
            stall !== nothing && HTMXObjects._operation_running_answer(responded) &&
                return _operation_stalled_response(stall, ip, keys,
                                                   call_kwargs, transport)
            _isolate_auto_poll_params(responded)
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
