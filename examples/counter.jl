# Counter app demonstrating HTMX partial updates.
#
# Run with:  julia --project examples/counter.jl
# Then open: http://localhost:8080
#
# Run with recording (for VitePress / static deploy):
#     julia --project examples/counter.jl record /tmp/counter 8080 /examples/counter

module Counter

using HTMXObjects

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    counter_ui(n::Int) = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(
            hx_get="/increment/$n",
            hx_target="#counter",
            hx_swap="outerHTML",
        )("+"),
    )

    @get index() = h.div(h.h1("HTMX Counter"), counter_ui(0))
    @get increment(n::Int) = counter_ui(n + 1)
end

# URL list — used by `record_examples.jl` to drive `record!`.
gallery_paths() = ["/", "/increment/0", "/increment/1", "/increment/2"]

function main(; record=false, record_dir="site", port=8080, record_base="")
    record ? route!(App(); record_dir, record_base) : route!(App())
    serve(; port)
end

end # module Counter

if abspath(PROGRAM_FILE) == @__FILE__
    record      = length(ARGS) >= 1 && ARGS[1] == "record"
    record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
    port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
    record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""
    Counter.main(; record, record_dir, port, record_base)
end
