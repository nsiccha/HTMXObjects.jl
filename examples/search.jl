# Search app demonstrating:
#   - derived properties for data and reusable UI fragments
#   - live search using kwargs for query-parameter extraction
#   - is_htmx to return a fragment for HTMX requests and the full page otherwise
#
# Run with:  julia --project examples/search.jl
# Then open: http://localhost:8080

using HTMXObjects

@htmx struct SearchApp
    req = nothing

    fruits = [
        "Apple", "Apricot", "Avocado", "Banana", "Blueberry",
        "Cherry", "Coconut", "Date", "Fig", "Grape",
        "Kiwi", "Lemon", "Lime", "Mango", "Orange",
        "Papaya", "Peach", "Pear", "Pineapple", "Plum",
        "Raspberry", "Strawberry", "Tangerine", "Watermelon",
    ]

    # The input triggers a live GET /results?q=... on every keystroke (debounced).
    # HTMX serialises the input's value as a query parameter automatically.
    search_input(query) = h.input(
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

    results_list(matches, query) = h.div(id="results")(
        isempty(query)   ? h.p("Start typing to search.") :
        isempty(matches) ? h.p("No results for \"$query\".") :
                           h.ul([h.li(m) for m in matches])
    )

    # Full page wrapper.
    page[content] = htmx(
        h.main(class="container")(
            h.h1("Fruit Search"),
            content,
        );
        pico_version="2",
    )

    @get index = page[(search_input(""), results_list([], ""))]

    # Kwargs auto-extract `q` from the query string for GET requests.
    @get results(; q="") = let
        matches = filter(f -> occursin(lowercase(q), lowercase(f)), fruits)
        fragment = (search_input(q), results_list(matches, q))
        if is_htmx(req)
            results_list(matches, q)
        else
            page[fragment]
        end
    end
end

record     = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port       = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080

function __init__()
    route!(SearchApp(); record_dir=record ? record_dir : nothing)
end

__init__()
serve(; port)
