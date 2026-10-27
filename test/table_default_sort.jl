@testmodule DefaultSortFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export row_ids, value_row, pinned_pairs, TREE, tree_table, ITEMS, grouped_table, keyed_rows, keyed_table

    # The ids of a rendered table's rows, in document order.
    row_ids(html) = [m[1] for m in eachmatch(r"<tr[^>]* id=\"([^\"]+)\"", html)]
    # A section row as the snag reported it: a label and its estimate.
    value_row(label, v) = h.tr(id="row-$label")(h.td(label), h.td(string(v); data_sort_value=string(v)))

    # Master/detail pairs, "c" pinned, and a full-width row with no cell in
    # the sorted column.
    function pinned_pairs()
        rows = Any[h.tr(h.td("Abschnitte"; colspan="2"))]
        for (k, v, pin) in (("a", 1, false), ("b", 3, false), ("c", 2, true), ("d", 4, false))
            attrs = pin ? (; data_htmxo_pinned="") : k == "d" ? (; data_htmxo_pinned="false") : (;)
            append!(rows, master_detail_pair(k, (h.td(k), h.td(string(v); data_sort_value=string(v))),
                h.p("detail $k"), 2; master_attrs=attrs))
        end
        rows
    end

    # A tree whose siblings come in the wrong order on both levels.
    const TREE = [
        (; key="small", name="Small", n=29.0, children=[(; key="s1", name="S1", n=9.0, children=()),
                                                       (; key="s2", name="S2", n=20.0, children=())]),
        (; key="big", name="Big", n=1234.5, children=[(; key="b1", name="B1", n=34.5, children=()),
                                                     (; key="b2", name="B2", n=1200.0, children=())]),
    ]
    tree_table(; kw...) = master_detail_table(["Gebiet", "Beschäftigte"], TREE;
        key=x -> x.key, master=x -> (h.td(x.name), number_cell(x.n)), children=x -> x.children,
        detail=x -> isempty(x.children) ? h.p("Detail ", x.name) : nothing, kw...)

    # Big (sum 1234.5) is listed first and Small (sum 29) second; the leaves of
    # each in the wrong order.
    const ITEMS = [(; id="b", bez="Big", n=34.5), (; id="a", bez="Small", n=9.0),
                   (; id="d", bez="Big", n=1200.0), (; id="c", bez="Small", n=20.0)]
    grouped_table(; id="g", texts=table_texts(:de), kw...) = master_detail_table(["Gebiet", "Beschäftigte"], ITEMS;
        id, key=t -> id * t.id, master=t -> (h.td(t.id), number_cell(t.n; texts)),
        groupings=["Keine" => nothing, "Bezirk" => t -> t.bez], group_by=["Bezirk"],
        group_summary=["Beschäftigte" => ColumnSummary(:sum, t -> t.n; digits=1)],
        detail=t -> h.p("Detail ", t.id), texts, kw...)

    # Hand-built cells with two sort keys; "z" has no lower bound.
    keyed_rows() = [h.tr(id="row-$k")(h.td(k), h.td("$est ($lo–$hi)"; sort_values(est, lo, hi)...))
                    for (k, est, lo, hi) in (("x", 5, 4, 6), ("y", 3, 1, 9), ("z", 4, missing, 5))]
    keyed_table(; kw...) = sortable_table(["Zone", ColumnSpec("Estimate"; sort_keys=["Estimate", "Lower", "Upper"])],
        keyed_rows(); kw...)
end

@testitem "default_sort writes the rows in the order its header shows" setup=[DefaultSortFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    # The reported table: sections in letter order, sorted by their estimate.
    rows = [value_row(l, v) for (l, v) in (("B", 0.0), ("C", 0.0), ("D", 0.047), ("E", 0.0), ("F", 46.5))]
    headers = ["Abschnitt", "Beschäftigte"]
    desc = sortable_table(headers, rows; default_sort=2 => :desc)
    # Equal estimates keep the order the rows came in, in either direction.
    @test row_ids(repr("text/html", desc)) == ["row-F", "row-D", "row-B", "row-C", "row-E"]
    @test row_ids(repr("text/html", sortable_table(headers, rows; default_sort="Beschäftigte"))) ==
        ["row-B", "row-C", "row-E", "row-D", "row-F"]
    # Without default_sort the rows stay as given.
    @test row_ids(repr("text/html", sortable_table(headers, rows))) == ["row-B", "row-C", "row-D", "row-E", "row-F"]
    # ?plain and PDF read the same order.
    md = to_markdown_string(desc)
    at(s) = first(findfirst(s, md))
    @test at("| F |") < at("| D |") < at("| B |") < at("| C |") < at("| E |")
    # render_table forwards it.
    rt = repr("text/html", render_table((name=["a", "b", "c"], score=[2, 3, 1]); default_sort=2 => :desc, download=false))
    @test first(findfirst(">b<", rt)) < first(findfirst(">a<", rt)) < first(findfirst(">c<", rt))
    # The caller's rows are left as they were.
    @test [HTMXObjects._row_id(r) for r in rows] == ["row-B", "row-C", "row-D", "row-E", "row-F"]

    # A cell without a sort value sorts by its text: numbers by the number
    # they start with, other text alphabetically, case and accents aside
    # (lower case first), punctuation before digits before letters.
    texts = [h.tr(id="row-$i")(h.td(t)) for (i, t) in enumerate(["beta", "Alpha", "10 Tsd.", "Äpfel", "–", "alpha", "9 Tsd."])]
    @test row_ids(repr("text/html", sortable_table(["Name"], texts; default_sort=1))) ==
        ["row-5", "row-7", "row-3", "row-6", "row-2", "row-4", "row-1"]
    # A number cell sorts by its exact number, not by its German text.
    de = [h.tr(id="row-$i")(number_cell(x; texts=table_texts(:de))) for (i, x) in enumerate([29.0, 1234.5, 1.5])]
    @test row_ids(repr("text/html", sortable_table(["n"], de; default_sort=1 => :desc))) == ["row-2", "row-1", "row-3"]
    # The JavaScript `parseFloat` the browser applies.
    @test HTMXObjects._js_parse_float("12 Tsd.") == 12 && HTMXObjects._js_parse_float(".5x") == 0.5 &&
        HTMXObjects._js_parse_float("1e400") == Inf && isnan(HTMXObjects._js_parse_float("–3")) &&
        HTMXObjects._js_parse_float("-Infinity") == -Inf
end

@testitem "default_sort keeps detail rows, pins and rows without the cell" setup=[DefaultSortFixtures] tags=[:unit] begin
    using HTMXObjects
    html = repr("text/html", sortable_table(["Name", "Value"], pinned_pairs(); default_sort=2 => :desc))
    # The full-width row has no cell in the column and stays first, where the
    # browser's sort leaves it; the pinned row leads the sorted ones; every
    # detail row stays under its master; `data-htmxo-pinned="false"` pins nothing.
    @test row_ids(html) == ["row-c", "detail-c", "row-d", "detail-d", "row-b", "detail-b", "row-a", "detail-a"]
    @test first(findfirst("Abschnitte", html)) < first(findfirst("id=\"row-c\"", html))
    # Pinned first in either direction.
    asc = row_ids(repr("text/html", sortable_table(["Name", "Value"], pinned_pairs(); default_sort=2)))
    @test asc == ["row-c", "detail-c", "row-a", "detail-a", "row-b", "detail-b", "row-d", "detail-d"]
end

@testitem "default_sort sorts by a named sort key, missing values last" setup=[DefaultSortFixtures] tags=[:unit] begin
    using HTMXObjects
    order(ds) = row_ids(repr("text/html", keyed_table(; default_sort=ds)))
    @test order("Estimate") == ["row-y", "row-z", "row-x"]
    @test order((col="Estimate", key="Lower", dir=:asc)) == ["row-y", "row-x", "row-z"]
    @test order((col="Estimate", key="Lower", dir=:desc)) == ["row-x", "row-y", "row-z"]
    @test order((col=2, key="Upper", dir=:desc)) == ["row-y", "row-x", "row-z"]
    @test HTMXObjects._sort_values_parse("[1, \"a\\\"b\\u00e9\", null, -2.5e3]") == Any[1.0, "a\"bé", nothing, -2500.0]
    # refused: a cell whose sort values are not a flat JSON array cannot be ordered.
    @test_throws ArgumentError HTMXObjects._sort_values_parse("[1, [2]]")
end

@testitem "default_sort orders a tree's siblings and a grouped table's groups" setup=[DefaultSortFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    tree = tree_table(; default_sort=2 => :desc)
    # Each set of siblings sorted, each subtree written whole.
    @test row_ids(repr("text/html", tree)) == ["row-big", "row-b2", "detail-b2", "row-b1", "detail-b1",
                                              "row-small", "row-s2", "detail-s2", "row-s1", "detail-s1"]
    # The details written after the table follow the rows.
    md = to_markdown_string(tree)
    at(s) = first(findfirst(s, md))
    @test at("**B2**") < at("**B1**") < at("**S2**") < at("**S1**")
    # Unsorted, the details keep the items' order.
    plain = to_markdown_string(tree_table())
    @test first(findfirst("**S1**", plain)) < first(findfirst("**B1**", plain))

    # Grouped: the groups by their sums (German text, exact number), the leaves by theirs.
    html = repr("text/html", grouped_table(; default_sort=2 => :desc))
    @test filter(id -> startswith(id, "row-"), row_ids(html)) ==
        ["row-group--Big", "row-group--Big--gd", "row-group--Big--gb", "row-group--Small", "row-group--Small--gc", "row-group--Small--ga"]
    @test first(findfirst("1.234,5", html)) < first(findfirst("29,0", html))
    # Without default_sort, groups and leaves come as listed.
    @test filter(id -> startswith(id, "row-"), row_ids(repr("text/html", grouped_table()))) ==
        ["row-group--Big", "row-group--Big--gb", "row-group--Big--gd", "row-group--Small", "row-group--Small--ga", "row-group--Small--gc"]
end

@testitem "default_sort writes the order the browser's sort gives browser" setup=[DefaultSortFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        texts = [h.tr(id="t-$i")(h.td(t)) for (i, t) in enumerate(["beta", "Alpha", "10 Tsd.", "Äpfel", "–", "alpha", "9 Tsd."])]
        tables = h.div(
            sortable_table(["Abschnitt", "Beschäftigte"],
                [value_row(l, v) for (l, v) in (("B", 0.0), ("C", 0.0), ("D", 0.047), ("E", 0.0), ("F", 46.5))];
                id="flat", default_sort=2 => :desc),
            sortable_table(["Name"], texts; id="text", default_sort=1),
            sortable_table(["Name", "Value"], pinned_pairs(); id="pins", default_sort=2 => :desc),
            keyed_table(; id="keyed", default_sort=(col="Estimate", key="Lower", dir=:asc)),
            tree_table(; id="tree", default_sort=2 => :desc),
            grouped_table(; id="g", default_sort=2 => :desc),
            grouped_table(; id="e", texts=table_texts(:en), default_sort=2 => :desc))
        # The browser applies each table's stamped sort itself (`htmxoResort`,
        # what a regroup or a row update runs): the rows must not move. Then
        # the grouped tables regroup to the flat view and back.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const checks = [];
            const rows = id => Array.from(document.getElementById(id).rows).map(r => r.id || r.textContent.trim()).join(',');
            for (const id of ['flat', 'text', 'pins', 'keyed', 'tree', 'g', 'e']) {
                const before = rows(id);
                htmxoResort(document.getElementById(id).closest('table'));
                const after = rows(id);
                checks.push(id + ':' + (before === after ? 'true' : 'false ' + before + ' VS ' + after));
            }
            for (const id of ['g', 'e']) {
                const before = rows(id);
                const pills = () => document.getElementById(id).closest('[data-htmxo-grouped]').querySelector('.htmxo-group-pills');
                htmxoGroupRequest(pills(), [], null);
                htmxoGroupRequest(pills(), ['Bezirk'], null);
                const after = rows(id);
                checks.push(id + '-regroup:' + (before === after ? 'true' : 'false ' + before + ' VS ' + after));
            }
            const pre = document.createElement('pre'); pre.id = 'checks'; pre.textContent = checks.join('\n');
            document.body.appendChild(pre);
        });
        """))
        page = repr("text/html", htmx(tables, driver; hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.Response(200, ["Content-Type" => "text/html"], page)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == 9
            end
        finally
            close(server)
        end
    end
end
