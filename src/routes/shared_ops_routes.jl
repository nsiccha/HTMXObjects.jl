# --- SharedOpsRoutes ------------------------------------------------------
#
# Reusable reset + revise routes bundle, factored out of the per-Bruno-app
# `OpsRoutes` definitions in `bruno/web-pkpd/src/ops.jl` and
# `bruno/web-explore/src/app.jl`. Apps mount it with:
#
#     @include ops = SharedOpsRoutes()
#
# This exposes (relative to the include mount point):
#   /reset            — clears in-memory DO caches on `__appdata__`
#   /revise/errors    — renders `Revise.errors(io)` as `<pre>`
#   /revise/now       — touches a file + triggers `Revise.revise()`
#
# Dependency note: the `/revise/*` routes call `Main.Revise` via `@eval`,
# assuming the host app has `using Revise` in its `Main` (which is the
# case for every HTMXObjects-based web app under `start-web.sh`). The
# `/reset` route assumes the host has wired an `__appdata__` property
# on the root context — the standard `_inject_dunder_props!` pattern
# threads it through.

"""
    SharedOpsRoutes()

Reusable ops sub-bundle providing the three standard endpoints every web
app needs: `/reset` (clear in-memory caches), `/revise/errors` (display
queued Revise errors), `/revise/now` (force-trigger Revise).

Mount as

    @include ops = SharedOpsRoutes()

inside the root `@htmx struct`. The bundle assumes the host app has
`__appdata__` wired on the root (for `clear_mem_caches!`) and `Revise`
loaded in `Main` (for the `/revise/*` routes).
"""
@htmx struct SharedOpsRoutes
    @get reset() = begin
        DynamicObjects.clear_mem_caches!(__appdata__)
        h.p("In-memory caches cleared.")
    end

    @include revise = begin
        @get errors() = h.div(
            h.h3("Revise Errors"),
            h.pre(sprint(io -> Main.Revise.errors(io))),
        )

        @get now() = begin
            src = @__FILE__
            touch(src)
            @eval Main Revise.revise()
            h.p("Revise triggered on $src.")
        end
    end
end
