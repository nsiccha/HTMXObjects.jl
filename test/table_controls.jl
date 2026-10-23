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
    # The control stays on its label's line; the browser item "row controls
    # stay on their label's line in a narrow first column" measures it.
    @test contains(html, "td:has(> [data-htmxo-row-label]) { text-wrap-mode: nowrap; }")
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

@testitem "row controls stay on their label's line in a narrow first column" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        # The reported shape: short first labels (three-digit sample numbers)
        # beside seven wide text columns, which squeeze the first column to its
        # minimum width. Before the fix the ▸ sat above `124`, every row two
        # lines tall. A long label widens its column, so it gets tables of its
        # own, which check that labels still wrap.
        long = "Messstelle 7 am Uferfiltrat Ost"
        wide = h.td("Grundwassermessstelle Pflanzenschutzmittel Untersuchungsbericht Trinkwasseraufbereitung")
        headers = ["Nr.", ("Spalte $j" for j in 1:7)...]
        leaf(key, label) = (; key, label, children=())
        flat(id, items) = master_detail_table(headers, items; key=x -> id * x.key,
            master=x -> (h.td(x.label), ntuple(_ -> wide, 7)...), detail=x -> h.p("d"), id)
        tree(id, items) = master_detail_table(headers, items; key=x -> id * x.key,
            master=x -> (h.td(x.label), ntuple(_ -> wide, 7)...), children=x -> x.children,
            detail=x -> h.p("d"), initially_open=true, id)
        short_flat = [leaf("n$i", string(100 + i)) for i in 1:12]
        short_tree = [
            # A plain branch: its label is the branch button, ⓘ follows it.
            (; key="b1", label="201", children=[leaf("l1", "202"), leaf("l2", h.a("203"; href="#"))]),
            # A linked branch: a separate ▸ button precedes the link.
            (; key="b2", label=h.a("205"; href="#"), children=[leaf("l4", "206")])]
        tables(prefix) = (flat(prefix * "flat", short_flat), tree(prefix * "tree", short_tree))
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset;
                const char = (node, i) => { const r = document.createRange();
                    r.setStart(node, i); r.setEnd(node, i + 1); return r.getBoundingClientRect(); };
                const sameLine = (a, b) => a.top < b.bottom - 2 && b.top < a.bottom - 2;
                // Per shown master row: does a control before or after the label,
                // or the glyph inside a label button, leave the label's line?
                const measure = id => {
                    let rows = 0, split = 0, multiline = 0;
                    for (const row of document.getElementById(id).querySelectorAll(':scope > tr[id^="row-"]')) {
                        if (row.hidden) continue;
                        rows++;
                        const label = row.cells[0].querySelector(':scope > [data-htmxo-row-label]');
                        const text = document.createTreeWalker(label, NodeFilter.SHOW_TEXT).nextNode();
                        const first = char(text, 0), last = char(text, text.length - 1);
                        if (last.top >= first.bottom - 2) multiline++;
                        const before = label.previousElementSibling, after = label.nextElementSibling;
                        if (before && before.matches('button') && !sameLine(before.getBoundingClientRect(), first)) split++;
                        if (after && after.matches('button') && !sameLine(after.getBoundingClientRect(), last)) split++;
                        const own = label.querySelector(':scope > button');
                        if (own && getComputedStyle(own, '::before').content !== 'none' &&
                            first.top >= own.getBoundingClientRect().top + first.height / 2) split++;
                    }
                    return [rows, split, multiline];
                };
                [out.flatRows, out.flatSplit] = measure('flat');
                [out.treeRows, out.treeSplit] = measure('tree');
                [, out.flatLongSplit, out.flatLongMultiline] = measure('flatlong');
                [, out.treeLongSplit, out.treeLongMultiline] = measure('treelong');
                // Positive control: the same tables with wrapping restored at every
                // boundary split their controls, so the column is narrow enough.
                out.controlFlatSplit = measure('c-flat')[1];
                out.controlTreeSplit = measure('c-tree')[1];
                out.done = '1';
            });
            """))
        content = h.main(; class="container")(tables("")...,
            flat("flatlong", [leaf("n1", "101"), leaf("n2", long)]),
            tree("treelong", [(; key="b1", label="201", children=[leaf("l1", long)])]),
            h.style(Raw(".unglued td, .unglued td * { text-wrap-mode: wrap !important; }")),
            h.div(; class="unglued")(tables("c-")...), driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing,
                extra_head=(sortable_table_js(), sortable_table_styles()))))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        attr(name) = parse(Int, match(Regex("data-$name=\"(\\d+)\""), dom)[1])
        @test contains(dom, "data-done=\"1\"")
        @test attr("flat-rows") == 12 && attr("tree-rows") == 5
        @test attr("flat-split") == 0
        @test attr("tree-split") == 0
        @test attr("flat-long-split") == 0 && attr("tree-long-split") == 0
        @test attr("flat-long-multiline") == 1 && attr("tree-long-multiline") == 1
        @test attr("control-flat-split") > 0 && attr("control-tree-split") > 0
    end
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

@testitem "page shells carry the table runtime and leave out extra_head copies" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _runtime_text
    # The reported page: a stock pico_page defined `htmxoMdToggle` but none of
    # the functions the table controls call, so they were dead.
    functions = ("function sortTable(", "function htmxoTreeToggle(", "function htmxoTreeAll(",
        "function htmxoFilterTable(", "function downloadTableCsv(")
    stock = repr("text/html", HTMXObjects.pico_page(h.p("x")))
    @test all(f -> count(f, stock) == 1, functions)
    @test count("function htmxoMdToggle(", stock) == 1
    @test contains(stock, _runtime_text(:sortable_table_styles)) && contains(stock, _runtime_text(:caption_style))
    @test all(f -> contains(repr("text/html", htmx(h.p("x"))), f), functions)
    # The shell's block is sortable_table_js() without the master/detail half
    # that its comparison block already holds.
    @test _runtime_text(:sortable_table) == _runtime_text(:table_runtime) * _runtime_text(:master_detail)
    @test startswith(_runtime_text(:comparison), _runtime_text(:master_detail))
    # tables=false leaves the table runtime out; the master/detail runtime stays.
    without = repr("text/html", HTMXObjects.pico_page(h.p("x"); tables=false))
    @test !any(f -> contains(without, f), functions)
    @test !contains(without, _runtime_text(:caption_style))
    @test count("function htmxoMdToggle(", without) == 1

    # An app's own copies of what the shell carries are left out rather than
    # shipped twice; its other elements keep their place.
    own = h.style(Raw(".mine{color:red}"))
    helpers = (sortable_table_js(), sortable_table_styles(), caption_style(), download_table_js(), master_detail_js())
    @test repr("text/html", HTMXObjects.pico_page(h.p("x"); extra_head=(h.title("T"), helpers..., own))) ==
        repr("text/html", HTMXObjects.pico_page(h.p("x"); extra_head=(h.title("T"), own)))
    # Without the table runtime the table helpers are the app's own again;
    # only the master/detail copy, which the shell still carries, is left out.
    kept = repr("text/html", HTMXObjects.pico_page(h.p("x"); tables=false, extra_head=helpers))
    @test all(f -> count(f, kept) == 1, functions)
    @test kept == repr("text/html", HTMXObjects.pico_page(h.p("x"); tables=false, extra_head=helpers[1:4]))
    # A changed or attributed copy is not the helper, so it stays.
    tweaked = h.script(Raw(_runtime_text(:sortable_table) * "\n// app tweak"))
    attributed = h.style(Raw(_runtime_text(:caption_style)); media="print")
    changed = repr("text/html", HTMXObjects.pico_page(h.p("x"); extra_head=(tweaked, attributed)))
    @test contains(changed, "// app tweak") && contains(changed, "media=\"print\"")

    # A linked shell links its table blocks once and still leaves the copies out.
    kw = (; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION, runtime=:linked)
    linked = repr("text/html", HTMXObjects.pico_page(h.p("x"); kw..., extra_head=(helpers..., htmxo_gallery_styles())))
    for file in ("table_runtime.js", "sortable_table_styles.css", "caption_style.css", "download_table.js",
                 "gallery_styles.css")
        @test count("/vendor/htmxo/$file?v=", linked) == 1
    end
    @test !contains(linked, "htmxo/sortable_table.js") && !contains(linked, "htmxo/master_detail.js")
    @test !contains(repr("text/html", HTMXObjects.pico_page(h.p("x"); kw..., tables=false)), "table_runtime")
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

@testitem "master/detail rows read as one table, eager details after it" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string, filter_errors
    # Snag master-detail-ma-e63263bb (reporter TenderViews), user pick 1mu8842:
    # every `detail-<key>` companion used to be a one-cell row of the pipe
    # table (`|  |`, `| Loading… |`, a whole section folded into a cell), in
    # `?plain`, a consumer's own `show` and `pdf_report` alike.
    struct ConsumerTable
        inner
    end
    Base.show(io::IO, m::MIME"text/markdown", t::ConsumerTable) = show(io, m, t.inner)
    items = [(id="lb-3-2", lb="LB § 3.2", ap="AP 2", grp=["A", "B"]),
             (id="lb-5-1", lb="LB § 5.1", ap="", grp=["A"])]
    master = r -> (h.td(r.lb), h.td(r.ap))
    md_table(; kw...) = master_detail_table(["LB", "Abschnitt"], items; key=r -> r.id, master, kw...)
    rows = "| LB | Abschnitt |\n| --- | --- |\n| LB § 3.2 | AP 2 |\n| LB § 5.1 |  |\n"
    # One Markdown whichever serializer writes it.
    function markdown(t)
        md = to_markdown_string(t)
        @test repr("text/markdown", t) == md
        @test repr("text/markdown", ConsumerTable(t)) == md
        md
    end

    # Details with nothing to read write nothing: html_only, nothing, a form,
    # and lazy ones, which are not on the page.
    for kw in ((; detail=r -> html_only(SemanticProse("hidden $(r.id)"))),
               (; detail=r -> nothing),
               (; detail=r -> h.form(h.input(; name="x", value="v"), h.button("Save"))),
               (; detail_url=r -> "/sec/$(r.id)"))
        @test markdown(md_table(; kw...)) == rows * "\n"
    end
    # Eager details follow the table, each under its row's label, as a
    # `SemanticDisclosure` writes its summary and body.
    eager = md_table(; detail=r -> SemanticProse("detail for $(r.id)"))
    @test markdown(eager) == rows *
        "\n**LB § 3.2**\n\ndetail for lb-3-2\n\n**LB § 5.1**\n\ndetail for lb-5-1"
    section = markdown(md_table(; detail=r -> SemanticSection("AP 2: Modell",
        Any[SemanticProse("**LB § 3.2**"), SemanticProse("> quote")])))
    @test startswith(section, rows * "\n**LB § 3.2**\n\n## AP 2: Modell\n\n**LB § 3.2**\n\n> quote\n\n**LB § 5.1**\n\n")
    # The HTML keeps every companion row; the details are not repeated.
    html = repr("text/html", eager)
    @test count("<tr id=\"detail-", html) == 2
    @test count("detail for lb-3-2", html) == 1
    @test !contains(html, "**")
    # What follows the table starts its own paragraph.
    @test markdown(h.div(eager, h.p("after"))) ==
        rows * "\n**LB § 3.2**\n\ndetail for lb-3-2\n\n**LB § 5.1**\n\ndetail for lb-5-1\n\nafter\n\n"
    # A label is its words: no link target or emphasis, html_only left out.
    linked = md_table(; master=r -> (h.td(h.a(h.strong(r.lb); href="/x/$(r.id)"), h.small(" (1)"),
                                          html_only(h.span(" badge"))), h.td(r.ap)),
                      detail=r -> h.p("linked $(r.id)"))
    @test contains(markdown(linked), "\n\n**LB § 3.2 (1)**\n\nlinked lb-3-2\n\n**LB § 5.1 (1)**\n\nlinked lb-5-1")
    # A captioned table's details follow its figure.
    captioned = markdown(md_table(; detail=r -> h.p("cap $(r.id)"), caption=CaptionSpec(; title="Completeness"), id="req"))
    @test endswith(captioned, "**Completeness**\n:::\n\n**LB § 3.2**\n\ncap lb-3-2\n\n**LB § 5.1**\n\ncap lb-5-1")
    @test !contains(captioned, "| cap ")
    # Grouped header columns, the label button, search and selection.
    for kw in ((; header_groups=["Both" => 1:2]), (; detail_toggle=:label),
               (; searchable=true, selectable="sel", id="ss"))
        md = markdown(md_table(; detail=r -> h.p("d $(r.id)"), kw...))
        @test endswith(md, "\n\n**LB § 3.2**\n\nd lb-3-2\n\n**LB § 5.1**\n\nd lb-5-1")
        @test count("\n|", md) == 3
    end
    # A hierarchy: every row's detail, branches included, in row order.
    tree = [(id="root", lb="Root", ap="", kids=[(id="leaf1", lb="Leaf 1", ap="x", kids=[]),
                                                 (id="leaf2", lb="Leaf 2", ap="y", kids=[])])]
    @test markdown(master_detail_table(["Name", "Val"], tree; key=r -> r.id, master,
            children=r -> r.kids, detail=r -> h.p("tree $(r.id)"))) ==
        "| Name | Val |\n| --- | --- |\n| Root |  |\n| Leaf 1 | x |\n| Leaf 2 | y |\n\n" *
        "**Root**\n\ntree root\n\n**Leaf 1**\n\ntree leaf1\n\n**Leaf 2**\n\ntree leaf2"
    @test markdown(master_detail_table(["Name", "Val"], tree; key=r -> r.id, master,
            children=r -> r.kids, detail_url=r -> isempty(r.kids) ? "/t/$(r.id)" : nothing)) ==
        "| Name | Val |\n| --- | --- |\n| Root |  |\n| Leaf 1 | x |\n| Leaf 2 | y |\n\n"
    # A leaf listed under two groups is one item: its detail is written once.
    @test markdown(md_table(; detail=r -> h.p("grp $(r.id)"),
            groupings=["Group" => r -> r.grp, "None" => nothing])) ==
        "| LB | Abschnitt |\n| --- | --- |\n| **A** (2) |  |\n| LB § 3.2 | AP 2 |\n| LB § 5.1 |  |\n" *
        "| **B** (1) |  |\n| LB § 3.2 | AP 2 |\n\n**LB § 3.2**\n\ngrp lb-3-2\n\n**LB § 5.1**\n\ngrp lb-5-1"
    # Hand-built pairs in a `sortable_table`: no one-cell rows either.
    pairs = Any[]
    for r in items
        append!(pairs, master_detail_pair(r.id, master(r), h.p("pair $(r.id)"), 2))
    end
    @test markdown(sortable_table(["LB", "Abschnitt"], pairs; id="hb")) == rows * "\n"
    @test count("<tr id=\"detail-", repr("text/html", sortable_table(["LB", "Abschnitt"], pairs))) == 2
    # `?error` still reaches an error inside a detail row.
    errors = filter_errors(md_table(; detail=r -> h.div(h.p("ok"), h.span("boom $(r.id)"; data_error="true"))))
    @test count("boom lb-", repr("text/html", errors)) == 2
    @test contains(repr("text/html", errors), "<tr id=\"detail-lb-3-2\"")
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

@testitem "CSV download keeps the lines a cell shows" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
                let blob = null;
                URL.createObjectURL = b => { blob = b; return 'blob:test'; };
                HTMLAnchorElement.prototype.click = function() {};
                try { downloadTableCsv(document.getElementById('lines'), 'lines.csv'); } finally {
                    URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
                }
                document.body.dataset.csv = blob ? await blob.text() : '';
                document.body.dataset.done = '1';
            });
            """))
        # A mean over its range (MietspiegelBayes' table cell), block children,
        # source line breaks inside a text, a unit and a quote.
        rows = [h.tr(h.td("gut"), h.td(h.strong("6,28"), h.br(), h.small("6,01–6,55")),
                     h.td(h.div("a"), h.div("b, \"c\"")), h.td("\n   x\n   y  "), h.td("6,28 €/m²"))]
        table = sortable_table(["Wohnlage", h.th("Baujahr", h.br(), "bis 1918"), "Liste", "Text", "Miete"], rows;
            id="lines", download=false)
        page = string("<!doctype html><html><head><meta charset=\"utf-8\">", repr("text/html", sortable_table_js()),
            repr("text/html", download_table_js()), "</head><body>", repr("text/html", table),
            repr("text/html", driver), "</body></html>")
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, page)
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        csv = match(r"data-csv=\"([^\"]*)\"", dom)
        @test !isnothing(csv)
        expected = "Wohnlage,Baujahr bis 1918,Liste,Text,Miete\ngut,\"6,28\n6,01–6,55\",\"a\nb, \"\"c\"\"\",x y,\"6,28 €/m²\""
        unescape(s) = replace(s, "&quot;" => "\"", "&#10;" => "\n", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">")
        @test unescape(csv.captures[1]) == expected
    end
end
