# Minimal "Hello World" HTMXObjects app.
#
# Run with:  julia --project examples/hello.jl
# Then open: http://localhost:8080

using HTMXObjects

@htmx struct HelloApp
    @get index = htmx(
        h.main(class="container")(
            h.h1("Hello, World!"),
            h.p("Built with ", h.a(href="https://github.com/nsiccha/HTMXObjects.jl")("HTMXObjects.jl")),
        );
        pico_version="2",
    )
end

record     = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port       = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080

function __init__()
    route!(HelloApp(); record_dir=record ? record_dir : nothing)
end

__init__()
serve(; port)
