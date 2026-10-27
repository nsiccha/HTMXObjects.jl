# A tabset in Markdown (`?plain`, `to_markdown_string`, `pdf_report`): no tab
# bar, every tab its label in bold followed by its content, as a
# `SemanticDisclosure` writes a label and its body (user design
# `HTMXObjects:snag.tabset-markdown-11f30b75/decisions/2026-10-26T18-00-39-920-02mzx5o`,
# no preference: bold labels, a lazy tab as a link to its address).

@testmodule TabsetMarkdown begin
    using HTMXObjects
    import HTMXObjects: HTMX, Node
    export plain_tabset

    # The tabset as a tree of plain nodes: what `tabset` built before its parts
    # carried a Markdown projection of their own.
    plain_tabset(x) = x
    plain_tabset(p::HTMXObjects._TabsetPart) = plain_tabset(p.node)
    plain_tabset(node::Node) =
        Node(HTMX.tag(node), copy(HTMX.attrs(node)), Any[plain_tabset(c) for c in HTMX.children(node)])
end

@testitem "a tabset's Markdown writes each tab under its label" setup=[TabsetMarkdown] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string

    ts = tabset("A" => h.p("a"), "B" => h.p("b"))
    md = to_markdown_string(ts)
    @test md == "**A**\n\na\n\n**B**\n\nb\n\n"
    # No tab bar: neither a list of the labels nor the restore script.
    @test !contains(md, "- A") && !contains(md, "htmxoTabset")
    # A direct `repr` (a consumer's own `show`) reads the same.
    @test repr("text/markdown", ts) == md

    # A lazy tab has no content on the page: its label links its address.
    lazy_md = to_markdown_string(tabset("Eager" => h.p("here"), "Lazy" => "/api/lazy"; id="ts"))
    @test lazy_md == "**Eager**\n\nhere\n\n**[Lazy](/api/lazy)**"

    # A label that is not text reads as its words; one with none leaves its
    # content without a label.
    @test startswith(to_markdown_string(tabset(h.span(h.strong("Güte"), " (K-40)") => h.p("g"))),
        "**Güte (K-40)**\n\ng")
    @test to_markdown_string(tabset(h.span() => h.p("bare"), "B" => h.p("b"))) ==
        "bare\n\n**B**\n\nb\n\n"

    # Several values in one tab are its content, in order.
    @test to_markdown_string(tabset("V" => [h.p("one"), h.p("two")])) == "**V**\n\none\n\ntwo\n\n"

    # A tab whose content strips to nothing (only a form) goes with its label.
    form_md = to_markdown_string(tabset("Edit" => h.form(h.textarea("raw source")), "View" => h.p("v")))
    @test form_md == "**View**\n\nv\n\n"
end

@testitem "a tabset's Markdown follows its reader's audience" setup=[TabsetMarkdown] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string

    ts = tabset("Überblick" => SemanticProse("Bayes-Regression der Nettokaltmiete."),
                "Modelldefinition" => private(SemanticCode(:julia, "mu ~ 1 + wohnflaeche")),
                "Kurz" => private(h.p("lang"); public=h.p("kurz")))
    public = to_markdown_string(ts; audience=:public)
    @test !contains(public, "Modelldefinition") && !contains(public, "wohnflaeche")
    @test public == "**Überblick**\n\nBayes-Regression der Nettokaltmiete.\n\n**Kurz**\n\nkurz\n\n"
    own = to_markdown_string(ts; audience=:private)
    @test contains(own, "**Modelldefinition**\n\n")
    @test contains(own, "```julia\nmu ~ 1 + wohnflaeche\n```")
    @test contains(own, "**Kurz**\n\n") && contains(own, "lang")
end

@testitem "a tabset's labels sit inside its section's level" setup=[TabsetMarkdown] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string

    # The reporter's shape: a model entry whose parts are tabs inside a section.
    entry = SemanticSection("Mietspiegelmodell",
        tabset("Überblick" => SemanticGroup(SemanticProse("Bayes-Regression."),
                                            SemanticFields(Konvergenz="R̂ 1,004")),
               "Verwendet in" => SemanticTable((LB=["1"], Anforderung=["Mietspiegel"])),
               "Details" => SemanticSection("Priors", SemanticProse("Normal(0, 1)"));
               id="tender-model-mietmodell-tabs", url_param="tender-model-mietmodell");
        anchor="tender-model-mietmodell")
    md = to_markdown_string(entry)
    @test md == """
        ## Mietspiegelmodell {#tender-model-mietmodell}

        **Überblick**

        Bayes-Regression.

        - **Konvergenz:** R̂ 1,004

        **Verwendet in**

        | LB | Anforderung |
        | --- | --- |
        | 1 | Mietspiegel |

        **Details**

        ### Priors

        Normal(0, 1)"""
end

@testitem "a tabset's HTML, HXML, ?error and static export are its nodes'" setup=[TabsetMarkdown] tags=[:unit] begin
    using HTMXObjects

    shapes = [
        tabset("A" => h.p("a"), "B" => h.p("b")),
        tabset("Eager" => h.p("here"), "Lazy" => "/api/lazy"; id="ts", preload=true),
        tabset("A" => "/a", "B" => "/b"; id="ts2", url_param="insitu", active="b"),
        tabset("A" => h.p("a"), "A" => h.p("b"); url_param=nothing),
        tabset("Fehler" => h.div(e.span("failed: Kiel"), h.p("ok")), "Gut" => h.p("gut")),
        tabset("Ü" => SemanticFields(status="ok"), "P" => private(h.p("P"); public=h.p("p"))),
    ]
    for ts in shapes
        plain = plain_tabset(ts)
        @test repr("text/html", ts) == repr("text/html", plain)
        @test repr("application/vnd.hyperview+xml", ts) == repr("application/vnd.hyperview+xml", plain)
        filtered = filter_errors(ts)
        @test isnothing(filtered) == isnothing(filter_errors(plain))
        isnothing(filtered) || @test repr("text/html", filtered) == repr("text/html", filter_errors(plain))
        for spec in (StaticExport(), StaticExport(; controls=:remove, record_base="/site"))
            @test repr("text/html", static_transform(ts, spec)) ==
                  repr("text/html", static_transform(plain, spec))
        end
    end
    # `?error` finds an error inside a tab.
    @test contains(repr("text/html", filter_errors(shapes[5])), "failed: Kiel")
    # The URL-restore script is still the tabset's last child.
    @test endswith(repr("text/html", shapes[1]), "(document.currentScript.parentElement)</script></div>")
end
