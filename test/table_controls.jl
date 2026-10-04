@testitem "table labels toggle details with fixed expanded branches" tags=[:unit] begin
    using HTMXObjects
    leaf = (; key="leaf", name="A complete model label", children=())
    group = (; key="group", name="Group", children=(leaf,))
    cell = h.td(h.strong(leaf.name); data_sort_value="kept")
    before = repr("text/html", cell)
    html = repr("text/html", master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> (x.key == "leaf" ? cell : h.td(x.name),),
        children=x -> x.children, branches_collapsible=false,
        detail_toggle=:label, searchable=true,
        detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing))
    @test repr("text/html", cell) == before
    @test !contains(html, "data-htmxo-tree-toggle=")
    @test !contains(html, "data-htmxo-tree-open=")
    @test !contains(html, ">Details</button>")
    @test !contains(html, "id=\"detail-group\"")
    @test contains(html, "data-sort-value=\"kept\"")
    @test contains(html, "<strong>A complete model label</strong></button>")
    @test contains(html, "aria-controls=\"detail-leaf\"")
    @test contains(html, "aria-expanded=\"false\"")
    @test contains(html, "data-htmxo-detail-open=\"false\"")
    @test !contains(match(r"<tr[^>]*id=\"row-leaf\"[^>]*>", html).match, " hidden")
    @test contains(html, "hx-get=\"/detail/leaf\"")
    @test !contains(html, "htmxo-md-load consume, load")
    flat = repr("text/html", master_detail_table(["Name"], [leaf];
        key=x -> x.key, master=x -> (cell,), detail=x -> h.p("Detail"),
        detail_toggle=:label))
    @test contains(flat, "<strong>A complete model label</strong></button>")
    @test contains(flat, "aria-controls=\"detail-leaf\"")
    branch_detail = repr("text/html", master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        branches_collapsible=false, detail_toggle=:label, detail=x -> h.p("Detail")))
    @test !contains(branch_detail, "data-htmxo-tree-open=")
    @test count("data-htmxo-detail-toggle=", branch_detail) == 2
end

@testitem "semantic entry mounted URL recipe" tags=[:unit, :semantic] begin
    using HTMXObjects
    @htmx struct TableURLLeaf
        label::String
        @include sources = begin
            @get alpha() = h.p("alpha:$(label)")
            @get beta() = h.p("beta:$(label)")
        end
    end
    @htmx struct TableURLRoot
        @include rows(row::Int) = TableURLLeaf(string(row))
    end
    root = TableURLRoot(; __prefix__="/proxy/demo", __cache_base__=mktempdir())
    entries = Any[]
    semantic_app(root.rows(7); render_operation=entry -> begin
        push!(entries, entry)
        h.div()
    end)
    @test length(entries) == 2
    urls = [entry.object / entry.route.path for entry in entries]
    @test urls == ["/proxy/demo/rows/7/sources/alpha", "/proxy/demo/rows/7/sources/beta"]
    @test [entry.path for entry in entries] == ["/sources/alpha", "/sources/beta"]
    @test all(entry.verb === :GET for entry in entries)
    @test all(contains(repr("text/html", entry.form), "hx-get=\"$(url)\"") for (entry,url) in zip(entries,urls))
    html = repr("text/html", comparison_view((entry.title => url for (entry,url) in zip(entries,urls))...; id="mounted"))
    @test all(contains(html, "hx-get=\"$(url)\"") for url in urls)
end
