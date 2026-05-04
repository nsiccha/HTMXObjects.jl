# Minimal "Hello World" HTMXObjects app.
#
# Run with:  julia --project examples/hello.jl
# Then open: http://localhost:8080

using HTMXObjects

@htmx struct HelloApp
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index = h.div(
        h.h1("Hello, World!"),
        h.p("Built with ", h.a(href="https://github.com/nsiccha/HTMXObjects.jl")("HTMXObjects.jl")),
    )
end

record      = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""

function __init__()
    record ? route!(HelloApp(); record_dir, record_base) : route!(HelloApp())
end

__init__()
serve(; port)
