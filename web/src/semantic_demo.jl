@dynamicstruct struct SemanticDemoData end

const _SEM_DEMO_BODY = """Load `data_path`, then call `load_data(x_y_z)`."""

@htmx struct SemanticDemoRoutes
    @get index() = begin
        h.div(
            h.h1("Semantic Links and Alternatives Demo"),
            h.p("Append ", h.code("?plain"), " to see what each element ",
                "projects: the external glyph survives, and only an ",
                "alternatives block's default view appears."),
            h.section(
                h.h2("Internal vs external links"),
                h.p("Internal: ", SemanticLink("home", "/"), "."),
                h.p("External: ",
                    SemanticLink("HTMXObjects.jl", "https://github.com/nsiccha/HTMXObjects.jl";
                        external=true), "."),
            ),
            h.section(
                h.h2("Alternatives: verbatim source plus a second view"),
                SemanticAlternatives(
                    h.pre(h.code(_SEM_DEMO_BODY)),
                    "rendered preview" => render_markdown(_SEM_DEMO_BODY),
                ),
            ),
        )
    end
end
