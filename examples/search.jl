# Search app demonstrating:
#   - derived properties for data and reusable UI fragments
#   - live search using kwargs for query-parameter extraction
#   - is_htmx to return a fragment for HTMX requests and the full page otherwise
#
# Run with:  julia --project examples/search.jl
# Then open: http://localhost:8080

using HTMXObjects

@htmx struct SearchApp
    # Cross-route param: `q` is auto-extracted from the request's query
    # string on every request, so all properties — `search_input`,
    # `results_list`, the page wrapper — see the same value without each
    # route declaring it as a kwarg.
    @param q::String = ""

    fruits = [
        "Apple", "Apricot", "Avocado", "Banana", "Blueberry",
        "Cherry", "Coconut", "Date", "Fig", "Grape",
        "Kiwi", "Lemon", "Lime", "Mango", "Orange",
        "Papaya", "Peach", "Pear", "Pineapple", "Plum",
        "Raspberry", "Strawberry", "Tangerine", "Watermelon",
    ]

    matches = filter(f -> occursin(lowercase(q), lowercase(f)), fruits)

    # The input triggers a live GET /results?q=... on every keystroke (debounced).
    # HTMX serialises the input's value as a query parameter automatically.
    search_input = h.input(
        id="query",
        name="q",
        type="search",
        value=q,
        placeholder="Search fruits…",
        autofocus=true,
        hx_get="/results",
        hx_target="#results",
        hx_trigger="input delay:200ms",
    )

    results_list = h.div(id="results")(
        isempty(q)         ? h.p("Start typing to search.") :
        isempty(matches)   ? h.p("No results for \"$q\".") :
                             h.ul([h.li(m) for m in matches])
    )

    # Page wrapper bakes in the search input + h1, so any route's body lands
    # below as the results region. HTMX requests bypass this and get just
    # the route's `val` (the results_list fragment).
    __page__(content) = htmx(
        h.main(class="container")(
            h.h1("Fruit Search"),
            search_input,
            content,
        );
        pico_version="2",
    )

    @get index = results_list

    # Same fragment as index — `q` is `@param`-extracted from the URL
    # automatically. HTMX requests get the bare fragment (swap target
    # `#results` matches by id); browser navigation gets the full page
    # wrapped by `__page__` with the input pre-populated.
    @get results = results_list
end

record      = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""

function __init__()
    record ? route!(SearchApp(); record_dir, record_base) : route!(SearchApp())
end

__init__()
serve(; port)
