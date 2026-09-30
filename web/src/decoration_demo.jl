@dynamicstruct struct DecorationDemoData end

# Canned item states behind a batch cache: the builder stands in for one
# batched query (a GraphQL call, a DB round-trip). First paint reads misses
# and kicks one drain; the next render finds entries.
const _DECORATION_DEMO_CACHE = BackgroundCache{String,Any}(
    keys -> Dict(k => (; state="open", title="Demo item $k") for k in keys);
    batch=50, ttl=600.0, unbuilt=nothing)

const _DECORATION_DEMO_RULE = MarkdownRule(r"(\w+)#(\d+)", (m, ctx) -> begin
    key = "$(m.captures[1])#$(m.captures[2])"
    decorated_link(m.match, "/items/$(m.captures[2])", _DECORATION_DEMO_CACHE[key];
        class="decoration-demo-ref",
        attrs=e -> (; data_state=e.state, title=e.title))
end)

const _DECORATION_DEMO_SRC = "Tracking demo#12 and demo#34."

@htmx struct DecorationDemoRoutes
    @get index() = begin
        h.div(
            h.h1("Deferred Decoration Demo"),
            h.p("First paint shows plain links; the batch lands in the ",
                "background and the next render decorates them. Reload to ",
                "see the decorated form. Append ", h.code("?plain"),
                " for the stable projection."),
            h.pre(h.code(_DECORATION_DEMO_SRC)),
            render_markdown(_DECORATION_DEMO_SRC;
                rules=[_DECORATION_DEMO_RULE]),
        )
    end
end
