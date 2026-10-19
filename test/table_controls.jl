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
    # In a hierarchy the plain leaf label opens its detail without a filled button.
    leaf = (; key="leaf", name="Leaf", children=())
    tree = repr("text/html", master_detail_table(["Name"], [(; key="g", name="G", children=(leaf,))];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail=x -> isempty(x.children) ? h.p("d") : nothing))
    @test contains(tree, "data-htmxo-detail-toggle=\"\" data-htmxo-label=\"\"")
    @test contains(tree, ">Leaf</button>")
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

@testitem "sort header controls render as heading text under Pico" setup=[ChromeDump] tags=[:browser] begin
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
            dump_dom(cmd)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("pico-fills-buttons", "transparent", "heading-color", "heading-font",
                       "no-padding", "no-border")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end

@testitem "explained column headers stay sortable" tags=[:unit] begin
    using HTMXObjects
    rows = [h.tr(h.td("2"), h.td("b")), h.tr(h.td("1"), h.td("a"))]
    help = "RK / Stan log-density time; below 1× RK is faster."
    # The reported shape: a pre-built header node is the caller's own header,
    # used as-is, so it carries no sort wiring.
    node = repr("text/html", sortable_table([h.th(h.span("Primal")), "Name"], rows))
    @test count("htmxo-sort-control", node) == 1
    table = sortable_table([ColumnSpec("Primal"; help), "Name"], rows; id="t", default_sort="Primal")
    html = repr("text/html", table)
    @test count("htmxo-sort-control", html) == 2
    th = match(r"<th[^>]*>.*?</th>"s, html).match
    @test contains(th, "onclick=\"sortTable(0, this)\"")
    @test contains(th, "data-sort-dir=\"asc\"") && contains(th, "aria-sort=\"ascending\"")
    @test contains(th, "title=\"$help\"")
    @test contains(th, ">Primal<span class=\"htmxo-column-help\" aria-hidden=\"true\"> ⓘ</span></button>")
    # Markdown keeps the column name only.
    md = HTMXObjects.to_markdown_string(table)
    @test contains(md, "Primal") && contains(md, "Name")
    @test !contains(md, "ⓘ") && !contains(md, "log-density")
    # Without an explanation it is the String header, byte for byte.
    for spec in (ColumnSpec("Primal"), ColumnSpec("Primal"; help=" "))
        @test repr("text/html", sortable_table([spec, "Name"], rows)) ==
              repr("text/html", sortable_table(["Primal", "Name"], rows))
    end
    plain = repr("text/html", sortable_table([ColumnSpec("Primal"; help), "Name"], rows; sortable=false))
    @test contains(plain, "<th title=\"$help\">Primal<span class=\"htmxo-column-help\" aria-hidden=\"true\"> ⓘ</span></th>")
    @test !contains(plain, "htmxo-sort-control")
    # master_detail_table forwards its headers.
    tree = repr("text/html", master_detail_table([ColumnSpec("Model"; help="Pick one."), "Score"], [(; id="a")];
        key=x -> x.id, master=x -> (h.td("A"), h.td("1")), detail=x -> h.p("Detail")))
    @test contains(tree, "title=\"Pick one.\"") && count("htmxo-sort-control", tree) == 2
    @test_throws ErrorException sortable_table([h.th("Primal"), "Name"], rows; default_sort="Primal")
end

@testitem "table labels survive a consumer's own Markdown show" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    # The reported shape: an app wraps the table in its own type whose Markdown
    # `show` delegates to the table node. That reaches HTMX.jl's serializer, not
    # `to_markdown_string`, and HTMX.jl drops a `<button>` whole, so every
    # sortable header (and every label button) came out empty: `|  |  |`.
    struct ConsumerTable
        inner
    end
    Base.show(io::IO, ::MIME"text/html", t::ConsumerTable) = show(io, MIME"text/html"(), t.inner)
    Base.show(io::IO, m::MIME"text/markdown", t::ConsumerTable) = show(io, m, t.inner)

    data = (Vessel=["Syringe-50", "Bottle-50"], Diet=["1.0", "0.81"])
    caption = CaptionSpec(; title="Bioavailability", short="Posterior median")
    items = [(id="a", name="Alpha", kind="K1"), (id="b", name="Beta", kind="K2")]
    tree = [(id="g", name="Group", kids=[(id="c", name="Child", kids=[])])]
    cells(x) = (h.td(h.strong(x.name)), h.td(x.kind))
    tables = (
        render_table(data; caption),
        sortable_table([ColumnSpec("Vessel"; help="The vessel."), "Diet"], [h.tr(h.td("a"), h.td("b"))]),
        master_detail_table(["Name", "Kind"], items; key=x -> x.id, master=cells,
            detail=x -> h.p("About ", x.name), detail_toggle=:label),
        master_detail_table(["Name"], tree; key=x -> x.id, master=x -> (h.td(x.name),),
            children=x -> x.kids, detail=x -> isempty(x.kids) ? h.p("Leaf") : nothing),
        master_detail_table(["Name", "Kind"], items; key=x -> x.id, master=cells,
            detail=x -> h.p("About"), groupings=["None" => nothing, "Kind" => x -> x.kind],
            group_by="Kind"))
    for table in tables
        @test repr("text/markdown", table) == to_markdown_string(table)
        @test repr("text/markdown", ConsumerTable(table)) == to_markdown_string(table)
        # The HTML is the same control, label inside.
        @test repr("text/html", ConsumerTable(table)) == repr("text/html", table)
    end
    @test contains(repr("text/markdown", ConsumerTable(first(tables))), "| Vessel | Diet |")
    @test contains(repr("text/markdown", ConsumerTable(tables[3])), "| **Alpha** | K1 |")
    @test contains(repr("text/markdown", ConsumerTable(tables[4])), "| Group |")
    @test contains(repr("text/markdown", ConsumerTable(tables[5])), "| **K1** (1) |")
    # A route returning the wrapper answers `Accept: text/markdown` with the labels.
    @htmx struct ConsumerTableApp
        @get table() = ConsumerTable(render_table(data; caption))
    end
    route!(ConsumerTableApp())
    response = dispatch(:GET, "/table"; headers=["Accept" => "text/markdown"])
    @test response.status == 200
    @test contains(String(response.body), "| Vessel | Diet |\n| --- | --- |\n| Syringe-50 | 1.0 |")
end

@testitem "explained column headers sort and export their label" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const out = document.body.dataset;
                const body = document.getElementById('explained'), table = body.closest('table');
                const control = table.tHead.rows[0].cells[0].querySelector('.htmxo-sort-control');
                const order = () => Array.from(body.rows).map(r => r.cells[1].textContent).join(',');
                out.title = String(control.title === 'Log-density time.');
                out.initial = String(order() === 'b,a,c');
                control.click();
                out.ascending = String(order() === 'a,b,c');
                control.click();
                out.descending = String(order() === 'c,b,a' &&
                    table.tHead.rows[0].cells[0].getAttribute('aria-sort') === 'descending');
                const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
                let blob = null;
                URL.createObjectURL = b => { blob = b; return 'blob:test'; };
                HTMLAnchorElement.prototype.click = function() {};
                try { downloadTableCsv(body, 'explained.csv'); } finally {
                    URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
                }
                const csv = blob ? await blob.text() : '';
                out.csvHeader = String(csv.split('\n')[0] === 'Primal,Name');
                out.done = '1';
            });
            """))
        table = sortable_table([ColumnSpec("Primal"; help="Log-density time."), "Name"],
            [h.tr(h.td("2"), h.td("b")), h.tr(h.td("1"), h.td("a")), h.tr(h.td("3"), h.td("c"))];
            id="explained")
        page = string("<!doctype html><html><head>", repr("text/html", sortable_table_js()),
            repr("text/html", download_table_js()), "</head><body>", repr("text/html", table),
            repr("text/html", driver), "</body></html>")
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, page)
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("title", "initial", "ascending", "descending", "csv-header")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
