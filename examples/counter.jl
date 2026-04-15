# Counter app demonstrating HTMX partial updates.
#
# The index page renders a full page containing the counter fragment.
# Clicking "+" sends a GET request to /increment/{n}, which returns only
# the updated counter fragment — HTMX swaps it in without a full page reload.
#
# Run with:  julia --project examples/counter.jl
# Then open: http://localhost:8080

using HTMXObjects

@htmx struct CounterApp
    # Reusable fragment — returned by both the initial page and the HTMX update.
    # The `id="counter"` is the swap target; hx-swap="outerHTML" replaces the whole div.
    counter_ui[n::Int] = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(
            hx_get="/increment/$n",
            hx_target="#counter",
            hx_swap="outerHTML",
        )("+"),
    )

    # Full page — wraps the fragment for the initial browser load.
    @get index = htmx(
        h.main(class="container")(
            h.h1("HTMX Counter"),
            counter_ui[0],
        );
        pico_version="2",
    )

    # Fragment only — returned for HTMX requests; swapped into the existing page.
    @get increment[n::Int] = counter_ui[n + 1]
end

record     = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port       = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080

function __init__()
    route!(CounterApp(); record_dir=record ? record_dir : nothing)
end

__init__()
serve(; port)
