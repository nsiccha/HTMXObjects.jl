# Minimal "Hello World" HTMXObjects app.
#
# Run with:  julia examples/hello.jl
# Then open: http://localhost:8080

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
using HTMXObjects

@htmx struct HelloApp
    @get index = htmx(
        h.main(class="container")(
            h.h1("Hello, World!"),
            h.p("Built with ", h.a(href="https://github.com/nsiccha/HTMXObjects.jl")("HTMXObjects.jl")),
        )
    )
end

app = HelloApp()
route!(app)
serve()
