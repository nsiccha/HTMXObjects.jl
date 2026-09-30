@dynamicstruct struct MarkdownDemoData end

# A `#123` ticket rule for the custom-registry case: the pattern finds the
# ref, the builder links it. Render-scoped `context` counts what fired.
const _MD_DEMO_TICKET_RULE = MarkdownRule(r"#(\d+)",
    (m, ctx) -> begin
        ctx["tickets"] = get(ctx, "tickets", 0) + 1
        h.a("#$(m.captures[1])"; href="/tickets/$(m.captures[1])")
    end)

const _MD_DEMO_CASES = [
    ("Identifiers keep their underscores",
        "Load `data_path`, then call `load_data(x_y_z)`. No emphasis, nothing deleted.",
        nothing),
    ("Bare URLs link, punctuation stays outside",
        "See https://docs.example/a_b?c=1&d=2. (Parenthesized: https://x.example/a_(b)).",
        nothing),
    ("Author links, code and fences are never re-linked",
        "[ours](https://ours.example/a_b) and `https://code.example/x` stay as written.",
        nothing),
    ("A custom rule links ticket refs",
        "Fixed #12 and #34 in this release.",
        _MD_DEMO_TICKET_RULE),
]

const _MD_DEMO_BLOCKS = """
## Blocks

- [x] joined text runs
- [ ] per-item decoration (next demo)

| feature | status |
|:--------|-------:|
| tables  | yes |
| tasks   | yes |

```julia
render_markdown(src; rules=[MY_RULE, MARKDOWN_URL_RULE])
```
"""

_md_demo_case(title, source, rule) = h.section(
    h.h2(title),
    h.pre(h.code(source)),
    render_markdown(source; rules=isnothing(rule) ? nothing : rule),
)

@htmx struct MarkdownDemoRoutes
    @get index() = begin
        ctx = Dict{String,Any}()
        ticketed = render_markdown(_MD_DEMO_CASES[4][2];
            rules=_MD_DEMO_TICKET_RULE, context=ctx)
        h.div(
            h.h1("Markdown Renderer Demo"),
            h.p("Each case shows its source, then what ",
                h.code("render_markdown"), " makes of it. ",
                "Append ", h.code("?plain"), " for the markdown projection."),
            _md_demo_case(_MD_DEMO_CASES[1]...),
            _md_demo_case(_MD_DEMO_CASES[2]...),
            _md_demo_case(_MD_DEMO_CASES[3]...),
            h.section(
                h.h2(_MD_DEMO_CASES[4][1]),
                h.pre(h.code(_MD_DEMO_CASES[4][2])),
                ticketed,
                h.p(h.em("Render context saw $(get(ctx, "tickets", 0)) ticket refs.")),
            ),
            h.section(
                h.h2("Blocks: lists, tables, tasks, fences"),
                h.pre(h.code(_MD_DEMO_BLOCKS)),
                render_markdown(_MD_DEMO_BLOCKS; rules=MarkdownRule[]),
            ),
            h.section(
                h.h2("As a semantic element"),
                SemanticProse("Prose with data_path and https://docs.example keeps both."),
            ),
        )
    end
end
