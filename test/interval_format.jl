@testitem "format_interval writes the digits its interval supports" tags=[:unit] begin
    using HTMXObjects
    de = table_texts(:de)
    f(args...; kw...) = format_interval(args...; kw...)
    # Every number rounded at the second significant digit of the width, with
    # every decimal of that place (`3.20`), halves away from zero (450 at
    # hundreds is 500).
    @test f(22.3, 13.1, 34.2) == "22 (13–34)" && f(52, 31, 78) == "52 (31–78)"
    @test f(3.214, 2.951, 3.482) == "3.21 (2.95–3.48)" && f(3.2, 2.95, 3.48) == "3.20 (2.95–3.48)"
    @test f(0.523, 0.361, 0.712) == "0.52 (0.36–0.71)" && f(450, 120, 1800) == "500 (100–1,800)"
    @test f(22_430, 21_510, 23_320) == "22,400 (21,500–23,300)"
    # An estimate outside its interval is rounded at the same place.
    @test f(9.96, 9.1, 9.6) == "9.96 (9.10–9.60)"
    # In the table's language.
    @test f(22_430, 21_510, 23_320; texts=de) == "22.400 (21.500–23.300)" && f(3.2, 2.95, 3.48; texts=de) == "3,20 (2,95–3,48)"
    # A power of ten where format_number writes one, its digits kept.
    @test f(1.23e-5, 1.05e-5, 1.41e-5) == "1.23·10⁻⁵ (1.05·10⁻⁵–1.41·10⁻⁵)"
    @test f(2.2e16, 1.0e16, 3.0e16; texts=de) == "2,2·10¹⁶ (1,0·10¹⁶–3,0·10¹⁶)"
    # A negative bound: a word, since the dash would read as a minus.
    @test f(-5.2, -8.1, -2.3) == "-5.2 (-8.1 to -2.3)" && f(-5.2, -8.1, -2.3; texts=de) == "-5,2 (-8,1 bis -2,3)"
    @test f(0.004, -0.01, 0.02) == "0.004 (-0.010 to 0.020)"
    # The other rules.
    @test f(52, 31, 78; width_digits=1) == "50 (30–80)"
    @test f(0.5, 0.02, 3.1) == "0.5 (0.0–3.1)" && f(0.5, 0.02, 3.1; log=true) == "0.5 (0.02–3)"
    @test f(22.3, 13.1, 34.2; log=true) == "22 (13–34)"
    @test f(52, 31, 78; digits=1) == "52.0 (31.0–78.0)" && f(0.523, 0.361, 0.712; sigdigits=1) == "0.5 (0.4–0.7)"
    # No width, no digits from it; no bounds, the estimate alone.
    @test f(5, 5, 5) == "5 (5–5)" && f(22.3, missing, 34.2) == "22.3" && f(22.3, nothing, nothing) == "22.3"
    @test f(missing, 13.1, 34.2) == "– (13–34)" && f(missing, missing, missing) == "–"
    @test f(1.5, 1.0, Inf) == "1.5 (1–∞)"
    # The value and its fields; the texts can be replaced.
    x = IntervalEstimate(22.3, 13.1, 34.2)
    @test format_interval(x) == "22 (13–34)" && (x.estimate, x.lower, x.upper) == (22.3, 13.1, 34.2)
    @test IntervalEstimate(1 // 2, missing, 1).lower === missing
    @test format_interval(x; texts=table_texts(; interval="{estimate} [{lower}, {upper}]")) == "22 [13, 34]"
    # refused: an interval ending before it starts sets no digits; two rules
    # for one interval's digits; log digits of a quantity that is not
    # positive; values that are no numbers (dev §1).
    @test_throws ArgumentError IntervalEstimate(1, 3, 2)
    @test_throws ArgumentError IntervalEstimate(true, 1, 2)
    @test_throws ArgumentError IntervalEstimate("1", 1, 2)
    @test_throws ArgumentError f(1, 0, 2; log=true)
    @test_throws ArgumentError f(1, 0.5, 2; log=true, digits=1)
    @test_throws ArgumentError f(1, 0, 2; digits=1, sigdigits=1)
    @test_throws ArgumentError f(1, 0, 2; width_digits=0)
    @test_throws ArgumentError f(1, 0, 2; width_digits=16)
    @test_throws ArgumentError table_texts(; interval="{estimate} ({low}–{upper})")
end

@testitem "interval_cell keeps the exact numbers for sorting and the CSV" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    attr(cell, name) = let m = match(Regex("$name=\"([^\"]*)\""), cell); isnothing(m) ? nothing : replace(m[1], "&quot;" => "\"") end
    text(cell) = match(r">([^<]*)</td>", cell)[1]
    c = html(interval_cell(22.3, 13.1, 34.2; texts=table_texts(:de)))
    @test text(c) == "22 (13–34)" && attr(c, "data-sort-value") == "22.3" && attr(c, "data-htmxo-number") == "22.3"
    @test attr(c, "data-htmxo-sort-keys") == "[22.3,13.1,34.2,21.1,0.946188340807175]"
    @test attr(c, "data-htmxo-interval") == "[\"22.3\",\"13.1\",\"34.2\"]"
    @test html(interval_cell(IntervalEstimate(22.3, 13.1, 34.2); texts=table_texts(:de))) == c
    gap = html(interval_cell(missing, 13.1, 34.2))
    @test text(gap) == "– (13–34)" && isnothing(attr(gap, "data-sort-value")) && attr(gap, "data-htmxo-number") == ""
    @test attr(gap, "data-htmxo-interval") == "[\"\",\"13.1\",\"34.2\"]"
    # Further attributes reach the cell; the digits keywords are format_interval's.
    styled = html(interval_cell(52, 31, 78; width_digits=1, class="num"))
    @test text(styled) == "50 (30–80)" && attr(styled, "class") == "num" && attr(styled, "data-htmxo-interval") == "[\"52\",\"31\",\"78\"]"
end

@testitem "tables write an IntervalEstimate as one cell sorted by its five keys" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    html(x) = repr("text/html", x)
    de = table_texts(:de)
    keys_de = "data-htmxo-sort-keys=\"[&quot;Schätzwert&quot;,&quot;Untergrenze&quot;,&quot;Obergrenze&quot;,&quot;Intervallbreite&quot;,&quot;Relative Breite&quot;]\""
    csv_de = "data-htmxo-interval-csv=\"[&quot;Untergrenze&quot;,&quot;Obergrenze&quot;]\""
    est = [IntervalEstimate(3.214, 2.951, 3.482), IntervalEstimate(52.0, 31.0, 78.0)]
    table = (quantity=["CL", "V"], median=est)
    # render_table: the cell in the table's language, the header with the five
    # keys and the CSV's bound names; a SemanticTable renders through it.
    r = html(render_table(table; texts=de))
    @test contains(r, ">3,21 (2,95–3,48)</td>") && contains(r, ">52 (31–78)</td>") && contains(r, keys_de) && contains(r, csv_de)
    @test count("data-htmxo-interval-csv", r) == 1 && count("data-htmxo-sort-keys=\"[&quot;", r) == 1
    @test contains(to_markdown_string(render_table(table; texts=de)), "| CL | 3,21 (2,95–3,48) |")
    st = SemanticTable(table)
    @test contains(html(st), ">3.21 (2.95–3.48)</td>")
    @test contains(repr("text/markdown", st), "| CL | 3.21 (2.95–3.48) |")
    # The tab-separated text keeps the exact numbers, as the CSV does.
    @test repr("text/plain", st) == "quantity\tmedian\tmedian / Lower bound\tmedian / Upper bound\nCL\t3.214\t2.951\t3.482\nV\t52.0\t31.0\t78.0\n"
    # master_detail_table: a bare IntervalEstimate among the master cells, a
    # String header, and default_sort on one of the five keys.
    items = [(id="a", name="Alpha", e=IntervalEstimate(22.3, 13.1, 34.2)), (id="b", name="Beta", e=IntervalEstimate(3.2, 2.95, 3.48)),
             (id="c", name="Gamma", e=IntervalEstimate(40.0, 39.0, 41.0))]
    md(; kw...) = html(master_detail_table(["Name", "Schätzung"], items; key=it -> it.id,
        master=it -> (h.td(it.name), it.e), detail=it -> h.p("d"), texts=de, kw...))
    m = md()
    @test contains(m, ">22 (13–34)</td>") && contains(m, ">3,20 (2,95–3,48)</td>") && contains(m, keys_de) && contains(m, csv_de)
    order(s) = [x[1] for x in eachmatch(r"id=\"row-(\w)\"", s)]
    @test order(md(default_sort=(col="Schätzung", key="Obergrenze", dir=:desc))) == ["c", "a", "b"]
    @test order(md(default_sort=(col="Schätzung", key="Intervallbreite", dir=:asc))) == ["b", "c", "a"]
    # A header that names its keys keeps them; the cells carry the values.
    named = html(master_detail_table([ColumnSpec("Name"), ColumnSpec("E"; help="95 %", sort_keys=interval_sort_keys(; texts=de))],
        items; key=it -> it.id, master=it -> (h.td(it.name), it.e), detail=it -> h.p("d"), texts=de))
    @test contains(named, keys_de) && contains(named, "title=\"95 %\"")
    # sortable_table: hand-built interval cells give a String header the keys.
    rows = [h.tr(h.td(it.name), interval_cell(it.e; texts=de)) for it in items]
    s = html(sortable_table(["Name", "Schätzung"], rows; texts=de))
    @test contains(s, keys_de) && contains(s, csv_de)
    # A pre-built <th> stays as it is, but still names the CSV's bounds.
    pre = html(sortable_table(["Name", h.th("Schätzung")], rows; texts=de))
    @test !contains(pre, keys_de) && contains(pre, "<th $csv_de>Schätzung</th>")
    # A regroupable table: the leaves' column gets the keys, group rows no values.
    g = html(master_detail_table(["Name", "Schätzung"], items; key=it -> it.id, master=it -> (h.td(it.name), it.e),
        detail=it -> h.p("d"), texts=de, groupings=["Keine" => nothing, "Gruppe" => it -> it.id == "b" ? "B" : "A"], group_by=["Gruppe"]))
    @test contains(g, keys_de) && count("data-htmxo-interval=", g) >= 3
    # refused: a column whose sort keys the table computes, and a cell that
    # carries its own (dev §1: never overwrite silently).
    err = try
        master_detail_table([ColumnSpec("Name"), ColumnSpec("E"; sort_keys=interval_sort_keys(it -> 1, it -> 0, it -> 2))], items;
            key=it -> it.id, master=it -> (h.td(it.name), it.e), detail=it -> h.p("d"))
        nothing
    catch e
        sprint(showerror, e)
    end
    @test !isnothing(err) && contains(err, "drop `sort_keys`")
end

@testitem "an interval column sorts by its bounds and exports three CSV columns browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        de = table_texts(:de)
        table = (Name=["a", "b", "c", "d"],
                 Median=[IntervalEstimate(22.3, 13.1, 34.2), IntervalEstimate(3.2, 2.95, 3.48),
                         IntervalEstimate(40.0, 39.0, 41.0), IntervalEstimate(missing, 1.0, 2.0)])
        t = render_table(table; texts=de, id="iv", download=false)
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const body = document.getElementById('iv');
                const th = body.closest('table').querySelectorAll('thead th')[1];
                const names = () => Array.from(body.rows).map(r => r.cells[0].textContent).join(',');
                th.querySelector('[data-htmxo-sort-pick="2:desc"]').click();     // upper bound, descending
                document.body.dataset.upper = names();
                th.querySelector('[data-htmxo-sort-pick="3:asc"]').click();      // width, ascending
                document.body.dataset.width = names();
                const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
                let blob = null;
                URL.createObjectURL = b => { blob = b; return 'blob:test'; };
                HTMLAnchorElement.prototype.click = function() {};
                try { downloadTableCsv(body, 'iv.csv'); } finally {
                    URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
                }
                document.body.dataset.csv = blob ? await blob.text() : '';
                document.body.dataset.done = '1';
            });
            """))
        page = string("<!doctype html><html><head><meta charset=\"utf-8\">", repr("text/html", sortable_table_js()),
            repr("text/html", download_table_js()), "</head><body>", repr("text/html", t),
            repr("text/html", driver), "</body></html>")
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, page)
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        attr(name) = let m = match(Regex("data-$name=\"([^\"]*)\""), dom); isnothing(m) ? nothing : m[1] end
        # By the upper bound: 41 > 34,2 > 3,48 > 2; by the width: 0,53 < 1 < 2 < 21,1.
        @test attr("upper") == "c,a,b,d"
        @test attr("width") == "b,d,c,a"
        unescape(s) = replace(s, "&quot;" => "\"", "&#10;" => "\n", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">")
        csv = split(unescape(something(attr("csv"), "")), '\n')
        @test csv[1] == "Name,Median,Median / Untergrenze,Median / Obergrenze"
        @test csv[2:end] == ["b,3.2,2.95,3.48", "d,,1.0,2.0", "c,40.0,39.0,41.0", "a,22.3,13.1,34.2"]
    end
end
