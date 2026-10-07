@testmodule SnapshotFixtures begin
    using HTMXObjects
    export BUILDS, leaf, catalogue

    const BUILDS = Ref(0)
    leaf(name) = (; key=lowercase(name), name, children=())
    const ITEMS = [(; key="family", name="Family",
        children=(leaf("Model_A"), leaf("Model_B")))]

    # A sortable, searchable hierarchy whose row names are label toggles, one
    # error-tagged status, and one control a static server cannot answer.
    function catalogue()
        BUILDS[] += 1
        h.div(h.h2("Catalogue"),
            master_detail_table(["Model", "Status"], ITEMS;
                key=x -> x.key, children=x -> x.children,
                branches_collapsible=false, detail_toggle=:label, searchable=true,
                master=x -> (h.td(x.name),
                    h.td(x.key == "model_b" ? e.span("failed: Model_B") : "ok")),
                detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing),
            h.button("Rerun"; hx_post="/rerun"))
    end
end

@testitem "Markdown keeps the labels of labelled table controls" setup=[SnapshotFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    table(toggle) = master_detail_table(["Model", "Status"], SnapshotFixtures.ITEMS;
        key=x -> x.key, children=x -> x.children, branches_collapsible=false,
        searchable=true, detail_toggle=toggle,
        master=x -> (h.td(x.name), h.td("ok")),
        detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing)
    for toggle in (:button, :label)
        md = to_markdown_string(table(toggle))
        # Sortable header names and row names are document content.
        @test startswith(md, "| Model | Status |\n| --- | --- |\n")
        @test contains(md, "| Model_A | ok |")
        @test contains(md, "| Model_B | ok |")
        # The search field, its empty state and the Details control are not.
        @test !contains(md, "Search")
        @test !contains(md, "No matching rows")
        @test !contains(md, "Details")
    end
    @test contains(to_markdown_string(render_table((a=[1], b=[2]); download=false)),
        "| a | b |\n| --- | --- |\n| 1 | 2 |")
    # The affordances stay in the HTML, and only the label control is marked.
    html = repr("text/html", table(:label))
    @test contains(html, "type=\"search\"")
    @test contains(html, "No matching rows")
    @test count("data-htmxo-label=\"\"", html) == 2 + 2   # two headers, two rows
    @test count("data-htmxo-label=\"\"", repr("text/html", table(:button))) == 2
    # An unmarked control is still dropped whole.
    @test to_markdown_string(h.p("keep ", h.button("Run"))) == "keep \n\n"
    @test to_markdown_string(h.p("keep ", h.button("Run"; data_htmxo_label=""))) ==
        "keep Run\n\n"
end

@testitem "HTMLSnapshot projects its retained value" setup=[SnapshotFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    value = catalogue()
    snapshot = HTMLSnapshot(value)
    @test repr("text/html", snapshot) == repr("text/html", value)
    @test repr("text/markdown", snapshot) == to_markdown_string(value)
    @test sprint(show, snapshot) == "HTMLSnapshot($(ncodeunits(repr("text/html", value))) bytes)"
    for outer in (v -> v, v -> h.section(h.h1("Models"), v))
        @test to_markdown_string(outer(snapshot)) == to_markdown_string(outer(value))
        @test repr("text/html", filter_errors(outer(snapshot))) ==
            repr("text/html", filter_errors(outer(value)))
        exported = static_transform(outer(snapshot), StaticExport(; controls=:remove))
        @test repr("text/html", exported) ==
            repr("text/html", static_transform(outer(value), StaticExport(; controls=:remove)))
        @test !contains(repr("text/html", exported), "hx-post")
    end
    # Non-Node values keep their own projections.
    fields = HTMLSnapshot(SemanticFields(status="ok"))
    @test repr("text/markdown", fields) == repr("text/markdown", SemanticFields(status="ok"))
    @test repr("text/html", fields) == repr("text/html", SemanticFields(status="ok"))
end

@testitem "HTMLSnapshot serves every negotiated response from one build" setup=[SnapshotFixtures] tags=[:unit] begin
    using HTMXObjects
    @htmx struct SnapshotRoutesProbe
        # Retained with the root; reads no request context.
        surface = HTMLSnapshot(catalogue())
        "Catalogue returned directly"
        @fresh @get direct() = surface
        "Catalogue nested in a page-level node"
        @fresh @get nested() = h.section(h.h1("Models"), surface)
        "Catalogue inside a discovering live region"
        @fresh @get live() = live_region("/events", surface; discover=true)
    end
    BUILDS[] = 0
    expected = repr("text/html", catalogue())
    route!(SnapshotRoutesProbe(); root_provider=RootProvider(;
        scope=:job, key=_ -> :catalogue, retention=RootRetention()))
    BUILDS[] = 0
    body(path; headers=Pair{String,String}[]) = let r = dispatch(:GET, path; headers)
        @test r.status == 200
        String(r.body)
    end
    for round in 1:2, path in ("/direct", "/nested", "/live")
        @test contains(body(path), expected)
        @test contains(body(path; headers=["HX-Request" => "true"]), expected)
        for md in (body(path * "?plain"), body(path * "?markdown"),
                   body(path; headers=["Accept" => "text/markdown"]))
            @test contains(md, "| Model | Status |")
            @test contains(md, "| Model_A | ok |")
            @test contains(md, "| Model_B | failed: Model_B |")
            @test !contains(md, "Search")
            @test !contains(md, "<")
        end
        errors = body(path * "?error"; headers=["HX-Request" => "true"])
        @test contains(errors, "<span data-error=\"true\">failed: Model_B</span>")
        @test !contains(errors, "Model_A")
        plain_errors = body(path * "?plain&error")
        @test contains(plain_errors, "failed: Model_B")
        @test !contains(plain_errors, "Model_A")
        exported = String(dispatch(:GET, path; headers=["HX-Request" => "true"],
            static=StaticExport(; controls=:remove)).body)
        @test contains(exported, "Model_A")
        @test !contains(exported, "hx-post")
    end
    @test BUILDS[] == 1
end
