# Minimal "Hello World" HTMXObjects app.

module Hello

using HTMXObjects

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index = h.div(
        h.h1("Hello, World!"),
        h.p("Built with ", h.a(href="https://github.com/nsiccha/HTMXObjects.jl")("HTMXObjects.jl")),
    )
end

gallery_paths() = ["/"]

function main(; record=false, record_dir="site", port=8080, record_base="")
    record ? route!(App(); record_dir, record_base) : route!(App())
    serve(; port)
end

end # module Hello

if abspath(PROGRAM_FILE) == @__FILE__
    record      = length(ARGS) >= 1 && ARGS[1] == "record"
    record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
    port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
    record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""
    Hello.main(; record, record_dir, port, record_base)
end
