# Counter app demonstrating HTMX partial updates.
#
# The index page renders a full page containing the counter fragment.
# Clicking "+" sends a GET request to /increment/{n}, which returns only
# the updated counter fragment — HTMX swaps it in without a full page reload.
#
# Run with:  julia --project examples/counter.jl
# Then open: http://localhost:8080
#
# Run with recording (for VitePress / static deploy):
#     julia --project examples/counter.jl record /tmp/counter 8080 /examples/counter
# The fourth arg is the URL prefix where the recording will be served — used
# by `static_transform` to rewrite `hx-get` URLs into the `hx/` subtree.

using HTMXObjects

@htmx struct CounterApp
    # Page wrapper — applied to the root route's val for non-HTMX requests.
    # Routes return bare body content so they're equally usable as HTMX
    # fragments (HX-Request → val) and full pages (no header → __page__(val)).
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    # Reusable fragment — returned by both the initial page and the HTMX update.
    counter_ui(n::Int) = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(
            hx_get="/increment/$n",
            hx_target="#counter",
            hx_swap="outerHTML",
        )("+"),
    )

    # Body fragment — wrapped by `__page__` for full-page requests, returned
    # bare for HTMX requests (and for fragment recordings).
    @get index = h.div(h.h1("HTMX Counter"), counter_ui(0))

    # Fragment only — returned for HTMX requests and recorded as a fragment.
    @get increment(n::Int) = counter_ui(n + 1)
end

record      = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""

function __init__()
    if record
        route!(CounterApp(); record_dir, record_base)
    else
        route!(CounterApp())
    end
end

__init__()
serve(; port)
