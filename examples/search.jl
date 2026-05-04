# Search app demonstrating:
#   - cross-route `@param` for query-string extraction
#   - live search via debounced HTMX input
#   - canonical __page__ shape so HX requests get just the swap target

module Search

using HTMXObjects

@htmx struct App
    @param q::String = ""

    fruits = [
        "Apple", "Apricot", "Avocado", "Banana", "Blueberry",
        "Cherry", "Coconut", "Date", "Fig", "Grape",
        "Kiwi", "Lemon", "Lime", "Mango", "Orange",
        "Papaya", "Peach", "Pear", "Pineapple", "Plum",
        "Raspberry", "Strawberry", "Tangerine", "Watermelon",
    ]

    matches = filter(f -> occursin(lowercase(q), lowercase(f)), fruits)

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

    __page__(content) = htmx(
        h.main(class="container")(
            h.h1("Fruit Search"),
            search_input,
            content,
        );
        pico_version="2",
    )

    @get index = results_list
    @get results = results_list
end

gallery_paths() = ["/", "/results"]

function main(; record=false, record_dir="site", port=8080, record_base="")
    record ? route!(App(); record_dir, record_base) : route!(App())
    serve(; port)
end

end # module Search

if abspath(PROGRAM_FILE) == @__FILE__
    record      = length(ARGS) >= 1 && ARGS[1] == "record"
    record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
    port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
    record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""
    Search.main(; record, record_dir, port, record_base)
end
