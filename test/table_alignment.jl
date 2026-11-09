using TestItemRunner

# A sortable column header can take its column's alignment (snag
# `sortable-table-h-6312a3b4`): the KB writes every Markdown pipe table as a
# `sortable_table` and right-aligns a `---:` column's cells, but a sortable
# header could carry no alignment, so the heading sat at the left edge of its
# column and the numbers at the right.

@testitem "a column's alignment rides on its header and every cell, still sorting" tags=[:unit] begin
    using HTMXObjects
    ths(html) = [m.match for m in eachmatch(r"<th[ >][^>]*>", html)]
    tds(html) = [m.match for m in eachmatch(r"<td[^>]*>", html)]
    rows = [h.tr(h.td("RK"), h.td("38.1"; data_sort_value="38.1")),
            h.tr(h.td("Stan"), h.td("12"; data_sort_value="12"))]
    html = repr("text/html", sortable_table(["Model", ColumnSpec("Time (s)"; align=:right)], rows))
    @test ths(html) == ["<th onclick=\"sortTable(0, this)\" class=\"u-pointer\">",
                        "<th onclick=\"sortTable(1, this)\" class=\"u-pointer\" data-htmxo-align=\"right\">"]
    # The header still sorts with its button.
    @test count("htmxo-sort-control", html) == 2
    @test tds(html) == ["<td>", "<td data-sort-value=\"38.1\" data-htmxo-align=\"right\">",
                        "<td>", "<td data-sort-value=\"12\" data-htmxo-align=\"right\">"]
    # The caller's rows are copied, never changed.
    @test !haskey(HTMXObjects.HTMX.attrs(first(HTMXObjects.HTMX.children(rows[1])[2:end])), Symbol("data-htmxo-align"))
    # Each value; a String works too; anything else throws.
    for align in (:left, :center, :right)
        @test ColumnSpec("x"; align).align === align
    end
    @test ColumnSpec("x"; align="center").align === :center
    @test ColumnSpec("x").align === nothing
    @test_throws ArgumentError ColumnSpec("x"; align=:middle)
    @test_throws ArgumentError ColumnSpec("x"; align=1)
    # The help ⓘ and the ▾ sort-key menu stay in the aligned header.
    keyed = [h.tr(h.td("a"), h.td("22 (13–34)"; sort_values(22, 13, 34)...))]
    spec = ColumnSpec("Employees"; help="Estimate with interval.", sort_keys=["Estimate", "Lower", "Upper"], align=:right)
    html = repr("text/html", sortable_table(["Zone", spec], keyed))
    th = match(r"<th onclick=\"sortTable\(1, this\)\"[^>]*>.*?</th>"s, html).match
    @test contains(th, "data-htmxo-align=\"right\"") && contains(th, "htmxo-column-help") &&
          contains(th, "htmxo-sort-menu-toggle")
    @test contains(html, "<td data-htmxo-sort-keys=\"[22,13,34]\" data-htmxo-align=\"right\">")
    # Without sorting the header is aligned as well; so is a grouped header's leaf.
    @test contains(repr("text/html", sortable_table(["Model", ColumnSpec("T"; align=:center)], rows; sortable=false)),
        "<th data-htmxo-align=\"center\">T</th>")
    grouped = repr("text/html", sortable_table(["Model", ColumnSpec("Primal"; align=:right), ColumnSpec("Gradient"; align=:right)],
        [h.tr(h.td("a"), h.td("1"), h.td("2"))]; header_groups=["Time" => 2:3]))
    @test count(r"<th[^>]*data-htmxo-sort-col=\"[23]\"[^>]*data-htmxo-align=\"right\"", grouped) +
          count(r"<th[^>]*data-htmxo-align=\"right\"[^>]*data-htmxo-sort-col=\"[23]\"", grouped) == 2
    # A cell that says how it is aligned keeps it; a cell spanning columns and a
    # detail row are no cell of one column.
    own = [h.tr(h.td("a"), h.td("1"; data_htmxo_align="left")),
           h.tr(h.td("b"), h.td("2"; style="text-align: center")),
           h.tr(h.td("c"), h.td("3"; class="u-text-center")),
           h.tr(h.td("d e"; colspan="2")),
           h.tr(; id="detail-x")(h.td("detail"; colspan="2"))]
    cells = tds(repr("text/html", sortable_table(["K", ColumnSpec("V"; align=:right)], own)))
    @test !any(c -> contains(c, "data-htmxo-align=\"right\""), cells)
    # Markdown and the plain `String` header are as they were.
    md(t) = HTMXObjects.to_markdown_string(t)
    @test md(sortable_table(["Model", ColumnSpec("Time (s)"; align=:right)], rows)) ==
          md(sortable_table(["Model", "Time (s)"], rows))
    @test repr("text/html", sortable_table([ColumnSpec("Model"), "Time"], rows)) ==
          repr("text/html", sortable_table(["Model", "Time"], rows))
end

@testitem "a column of number cells right-aligns its header" tags=[:unit] begin
    using HTMXObjects
    header(html, i) = match(Regex("<th onclick=\"sortTable\\($(i - 1), this\\)\"[^>]*>"), html).match
    aligned(html, i) = contains(header(html, i), "data-htmxo-align=\"right\"")
    # Floats are number cells; text is not.
    html = repr("text/html", render_table((model=["RK", "Stan"], time=[38.1, 12.0])))
    @test !aligned(html, 1) && aligned(html, 2)
    # `missing` and a blank cell keep a column of numbers; a text cell among them does not.
    rows = [h.tr(number_cell(1.5), number_cell(2.5), h.td("x")),
            h.tr(number_cell(missing), h.td("n/a"), h.td("")),
            h.tr(h.td(""), number_cell(3.0), number_cell(4.0))]
    html = repr("text/html", sortable_table(["A", "B", "C"], rows))
    @test aligned(html, 1) && !aligned(html, 2) && !aligned(html, 3)
    # An interval and a group sum are number cells too.
    zones = [(; id="a", m=22.0, lo=13.0, hi=34.0)]
    html = repr("text/html", master_detail_table(["Zone", "Employees"], zones; key=z -> z.id,
        master=z -> (h.td(z.id), IntervalEstimate(z.m, z.lo, z.hi)), detail=z -> h.p("d")))
    @test !aligned(html, 1) && aligned(html, 2)
    # `align = :left` keeps a number column at the left, header and cells.
    html = repr("text/html", render_table((model=["RK"], time=[38.1]); columns=["time" => ColumnSpec("Time"; align=:left)]))
    @test contains(header(html, 2), "data-htmxo-align=\"left\"")
    @test contains(html, "data-htmxo-number=\"38.1\" data-htmxo-align=\"left\"")
    # A pre-built header is the caller's own.
    html = repr("text/html", sortable_table([h.th("A")], [h.tr(number_cell(1.5))]))
    @test contains(html, "<th>A</th>")
end

@testitem "group rows, row updates and the browser's group template carry a column's alignment" tags=[:unit] begin
    using HTMXObjects
    items = [(; id="a", party="Acme", amt=1.5), (; id="b", party="Acme", amt=2.0), (; id="c", party="Zed", amt=3.25)]
    table(; kw...) = master_detail_table(["Name", ColumnSpec("Party"; align=:center), "Amount"], items;
        key=t -> t.id, master=t -> (h.td(t.id), h.td(t.party), t.amt), detail=t -> h.p("memo"),
        groupings=["None" => nothing, "Party" => t -> t.party], group_by=["Party"],
        group_summary=["Amount" => ColumnSummary(:sum, t -> t.amt; digits=2)], id="tx", kw...)
    html = repr("text/html", table())
    # Header: the declared column and the column of numbers.
    @test count(r"<th onclick=\"sortTable\([12], this\)\" class=\"u-pointer\" data-htmxo-align=\"(center|right)\">", html) == 2
    # Every row's Party cell, leaves and groups, and the template the browser
    # builds its group rows from when it regroups.
    for m in eachmatch(r"<tr[^>]*id=\"row-[^\"]*\"[^>]*>(.*?)</tr>"s, html)
        cells = [c.match for c in eachmatch(r"<td[^>]*>", m[1])]
        @test cells[2] == "<td data-htmxo-align=\"center\">"
    end
    template = match(r"<template data-htmxo-group-template[^>]*>(.*?)</template>"s, html)[1]
    @test contains(template, "<td data-htmxo-align=\"center\">")
    # A row update renders its rows the same way.
    update = repr("text/html", table(update_rows="b"))
    @test count("<td data-htmxo-align=\"center\">", update) == 2
    @test contains(update, "<td colspan=\"3\">")   # the detail row is no column's cell
end

@testitem "column alignment is unlayered so it beats Pico's" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", sortable_table_styles())
    # Pico aligns `td, th` to the start outside any layer; a rule inside
    # `@layer htmxo` would lose to it.
    unlayered = css[findfirst("INTENTIONALLY UNLAYERED", css).stop:end]
    for rule in ("td[data-htmxo-number] { text-align: right; }",
                 ":is(th, td)[data-htmxo-align=\"left\"] { text-align: left; }",
                 ":is(th, td)[data-htmxo-align=\"center\"] { text-align: center; }",
                 ":is(th, td)[data-htmxo-align=\"right\"] { text-align: right; }")
        @test contains(unlayered, rule)
    end
    # A column's own alignment comes after the number rule, so `align = :left` wins.
    @test findfirst("td[data-htmxo-number]", unlayered).start <
          findfirst(":is(th, td)[data-htmxo-align=\"left\"]", unlayered).start
    # Every table page carries it.
    @test contains(repr("text/html", HTMXObjects.pico_page(h.p("x"))), ":is(th, td)[data-htmxo-align=\"right\"]")
end

@testitem "an aligned sortable header lines up with its cells under Pico" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        # The reported table: a text column and three right-aligned number
        # columns, in a wide page, as the KB writes `|---|---:|---:|---:|`.
        rows = [h.tr(; id="row-$k")(h.td(m), (h.td(string(v); data_sort_value=string(v)) for v in vs)...)
                for (k, m, vs) in (("rk", "RK native", (38.1, 2.0, 7.0)), ("stan", "Stan", (12.0, 3.5, 1.0)),
                                   ("wren", "Wren", (25.4, 1.25, 4.0)))]
        headers = ["Model", ColumnSpec("RK native + hoisting"; align=:right),
                   ColumnSpec("Stan"; align=:right, help="Seconds per gradient."), "Wren"]
        floats = [h.tr(h.td("a"), number_cell(1.5)), h.tr(h.td("b"), number_cell(22.25))]
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = {};
                const right = el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el);
                    return r.right - parseFloat(s.paddingRight) - parseFloat(s.borderRightWidth); };
                const left = el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el);
                    return r.left + parseFloat(s.paddingLeft) + parseFloat(s.borderLeftWidth); };
                const t = document.querySelector('#kb table'), ths = t.tHead.rows[0].cells;
                out.pico = getComputedStyle(ths[0]).textAlign;           // Pico's start
                out.th1 = getComputedStyle(ths[1]).textAlign;
                out.td1 = getComputedStyle(t.tBodies[0].rows[0].cells[1]).textAlign;
                // The label's right edge at the column's right edge, as the numbers'.
                const button = ths[1].querySelector('.htmxo-sort-control');
                out.labelGap = Math.round(right(ths[1]) - button.getBoundingClientRect().right);
                // With help: the ⓘ closes the header at the right edge.
                out.helpGap = Math.round(right(ths[2]) - ths[2].querySelector('.htmxo-column-help').getBoundingClientRect().right);
                // The unaligned column keeps its label at the left.
                out.plainGap = Math.round(ths[3].querySelector('.htmxo-sort-control').getBoundingClientRect().left - left(ths[3]));
                out.columnWidth = Math.round(ths[1].getBoundingClientRect().width);
                // Sorting still works on the aligned header.
                button.click();
                out.order = Array.from(t.tBodies[0].rows).map(r => r.id).join(',');
                out.sorted = ths[1].dataset.sortDir || '';
                out.after = getComputedStyle(ths[1]).textAlign;
                // A float column: header and numbers at the right by default.
                const f = document.querySelector('#floats table');
                out.fth = getComputedStyle(f.tHead.rows[0].cells[1]).textAlign;
                out.ftd = getComputedStyle(f.tBodies[0].rows[0].cells[1]).textAlign;
                const pre = document.createElement('pre'); pre.id = 'out';
                pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
            });
            """))
        content = h.main(; class="container")(h.div(; id="kb")(sortable_table(headers, rows)),
            h.div(; id="floats")(sortable_table(["Name", "Value"], floats)), driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing)))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        m = match(r"<pre id=\"out\">([^<]*)</pre>", dom)
        @test !isnothing(m)
        out = HTMXObjects.JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
        field(name) = out[name]
        num(name) = Float64(out[name])
        # Positive control: Pico is on the page and aligns a plain header to the start.
        @test field("pico") == "start"
        @test field("th1") == "right" && field("td1") == "right"
        # The column is wide, so a left-aligned label would sit far from the edge.
        @test num("columnWidth") > 150
        @test abs(num("labelGap")) <= 2
        @test abs(num("helpGap")) <= 2
        @test abs(num("plainGap")) <= 2
        @test field("order") == "row-stan,row-wren,row-rk" && field("sorted") == "asc"
        @test field("after") == "right"
        @test field("fth") == "right" && field("ftd") == "right"
    end
end
