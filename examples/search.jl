# Search app demonstrating:
#   - live search using query parameters and queryparams(req)
#   - mixing route!() with a custom Oxygen route for query-string handling
#   - is_htmx to return a fragment for HTMX requests and the full page otherwise
#
# Run with:  julia examples/search.jl
# Then open: http://localhost:8080

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
using HTMXObjects

const FRUITS = [
    "Apple", "Apricot", "Avocado", "Banana", "Blueberry",
    "Cherry", "Coconut", "Date", "Fig", "Grape",
    "Kiwi", "Lemon", "Lime", "Mango", "Orange",
    "Papaya", "Peach", "Pear", "Pineapple", "Plum",
    "Raspberry", "Strawberry", "Tangerine", "Watermelon",
]

# The input triggers a live GET /results?q=... on every keystroke (debounced).
# HTMX serialises the input's value as a query parameter automatically.
search_input(query="") = h.input(
    id="query",
    name="q",
    type="search",
    value=query,
    placeholder="Search fruits…",
    autofocus=true,
    hx_get="/results",
    hx_target="#results",
    hx_trigger="input delay:200ms",
)

function results_list(matches, query)
    h.div(id="results")(
        isempty(query)   ? h.p("Start typing to search.") :
        isempty(matches) ? h.p("No results for \"$query\".") :
                           h.ul([h.li(m) for m in matches])
    )
end

@htmx struct SearchApp
    @get index = htmx(
        h.main(class="container")(
            h.h1("Fruit Search"),
            search_input(),
            results_list([], ""),
        )
    )
end

app = SearchApp()
route!(app)

# Custom route for /results — uses query params rather than path params, so it
# cannot be expressed as a @get property and is registered manually instead.
Oxygen.get("/results") do req
    q = queryparam(req, "q")
    matches = filter(f -> occursin(lowercase(q), lowercase(f)), FRUITS)
    fragment = results_list(matches, q)
    # When navigated to directly (not via HTMX) return the full page so the
    # search box and previous query are still visible.
    htmx_or(req, fragment) do
        htmx(h.main(class="container")(
            h.h1("Fruit Search"),
            search_input(q),
            fragment,
        ))
    end
end

serve()
