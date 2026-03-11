# Counter app demonstrating HTMX partial updates.
#
# The index page renders a full page containing the counter fragment.
# Clicking "+" sends a GET request to /increment/{n}, which returns only
# the updated counter fragment — HTMX swaps it in without a full page reload.
#
# Run with:  julia examples/counter.jl
# Then open: http://localhost:8080

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
using HTMXObjects

# Reusable fragment — returned by both the initial page and the HTMX update.
# The `id="counter"` is the swap target; hx-swap="outerHTML" replaces the whole div.
counter_ui(n::Int) = h.div(id="counter")(
    h.p("Count: $n"),
    h.button(
        hx_get="/increment/$n",
        hx_target="#counter",
        hx_swap="outerHTML",
    )("+"),
)

@htmx struct CounterApp
    # Full page — wraps the fragment for the initial browser load.
    @get index = htmx(
        h.main(class="container")(
            h.h1("HTMX Counter"),
            counter_ui(0),
        )
    )

    # Fragment only — returned for HTMX requests; swapped into the existing page.
    @get increment[n] = counter_ui(parse(Int, n) + 1)
end

app = CounterApp()
route!(app)
serve()
