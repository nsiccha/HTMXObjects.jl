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

@testitem "flat master detail rows carry a native disclosure control" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    # The first cell is a link, which a `detail_toggle=:label` button cannot wrap.
    link = h.td(h.a("0001"; href="/invoice/1"), h.small(" (credit)"); data_sort_value="1")
    before = repr("text/html", link)
    items = [(; id="1", cell=link), (; id="2", cell=h.td(h.a("0002"; href="/invoice/2")))]
    table(; kw...) = master_detail_table(["Invoice", "Amount"], items;
        key=x -> "invoice-$(x.id)", master=x -> (x.cell, h.td("10")),
        detail=x -> h.p("Detail $(x.id)"), kw...)
    html = repr("text/html", table(; initially_open=x -> x.id == "1"))
    @test repr("text/html", link) == before
    controls = [m.match for m in eachmatch(r"<button[^>]*data-htmxo-detail-toggle[^>]*>[^<]*</button>", html)]
    @test length(controls) == 2
    for (id, open, glyph) in (("1", "true", "▾"), ("2", "false", "▸"))
        control = only(c for c in controls if contains(c, "aria-controls=\"detail-invoice-$id\""))
        @test contains(control, "type=\"button\"")
        @test contains(control, "data-htmxo-disclosure=\"\"")
        @test contains(control, "aria-label=\"Details\"")
        @test contains(control, "aria-expanded=\"$open\"")
        @test endswith(control, ">$glyph</button>")
    end
    # The control sits beside the cell's own content, never around the link,
    # and the cell keeps its attributes; the row click stays.
    @test contains(html, "<td data-sort-value=\"1\"><button")
    @test contains(html, "</button><span data-htmxo-row-label=\"\"><a href=\"/invoice/1\">0001</a><small> (credit)</small></span></td>")
    masters = [m.match for m in eachmatch(r"<tr[^>]*id=\"row-[^\"]*\"[^>]*>", html)]
    @test length(masters) == 2 && all(contains(t, "onclick=") for t in masters)
    @test contains(html, "button[data-htmxo-disclosure]")
    # Markdown keeps the cell content and drops the control.
    md = to_markdown_string(table())
    @test contains(md, "0001") && contains(md, "0002")
    @test !contains(md, "▸") && !contains(md, "Details")
    # Lazy rows and searchable tables carry the same control.
    lazy = repr("text/html", table(; detail=nothing, detail_url=x -> "/detail/$(x.id)", searchable=true))
    @test count("data-htmxo-disclosure=\"\"", lazy) == 2
    @test contains(lazy, "hx-get=\"/detail/1\"")
    # In a hierarchy the triangle means child rows, so details keep "Details".
    leaf = (; key="leaf", name="Leaf", children=())
    tree = repr("text/html", master_detail_table(["Name"], [(; key="g", name="G", children=(leaf,))];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail=x -> isempty(x.children) ? h.p("d") : nothing))
    @test contains(tree, ">Details</button>")
    @test !contains(tree, "data-htmxo-disclosure=\"\"")
    # Refused: the first cell hosts the row's detail control, so it must be an
    # element; bare text would otherwise surface as a MethodError (dev §1).
    @test_throws "the first master cell must be a <td> node" master_detail_table(["A"], [1];
        key=identity, master=_ -> ("text",), detail=_ -> "d")
end

@testitem "sort header controls are plain headings on every page shell" tags=[:unit] begin
    using HTMXObjects
    # The reporting measurement, inverted. The header label is a native
    # `<button>` (keyboard sort), but its reset lived only in the opt-in
    # `sortable_table_styles()`. A page that left that block out — most
    # consuming apps — rendered every column header as a Pico primary button.
    rule = ".htmxo-sortable-table thead th > .htmxo-sort-control {"
    @test contains(repr("text/html", htmxo_utility_styles()), rule)
    @test contains(repr("text/html", htmxo_utility_styles()), "$(rule[1:end-2]):focus-visible {")
    # One source: the opt-in block no longer carries a copy.
    @test !contains(repr("text/html", sortable_table_styles()), "htmxo-sort-control")
    table = sortable_table(["Name"], [h.tr(h.td("a"))])
    @test contains(repr("text/html", htmx(table; pico_version="2")), rule)
    @test contains(repr("text/html", HTMXObjects.pico_page(table)), rule)
end

@testitem "sort header controls render as heading text under Pico" tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = e => getComputedStyle(e);
                const control = document.querySelector('thead th > .htmxo-sort-control');
                const th = control.closest('th'), plain = document.getElementById('plain');
                // Positive control: Pico is loaded and fills an ordinary button.
                out.picoFillsButtons = String(css(plain).backgroundColor !== 'rgba(0, 0, 0, 0)');
                out.transparent = String(css(control).backgroundColor === 'rgba(0, 0, 0, 0)');
                out.headingColor = String(css(control).color === css(th).color);
                out.headingFont = String(css(control).fontWeight === css(th).fontWeight &&
                    css(control).fontSize === css(th).fontSize);
                out.noPadding = String(css(control).paddingLeft === '0px' && css(control).paddingTop === '0px');
                out.noBorder = String(css(control).borderTopWidth === '0px');
                out.done = '1';
            });
            """))
        content = h.main(; class="container")(
            sortable_table(["Name", "Score"], [h.tr(h.td("a"), h.td("1"))]),
            h.button("Plain"; type="button", id="plain"), driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            # The page shell exactly as an app builds it: Pico from the vendor
            # copy, and no `sortable_table_styles()` in `extra_head`.
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing,
                extra_head=(sortable_table_js(),))))
            profile = joinpath(directory, "profile")
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`
            read(pipeline(cmd; stderr=devnull), String)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("pico-fills-buttons", "transparent", "heading-color", "heading-font",
                       "no-padding", "no-border")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
