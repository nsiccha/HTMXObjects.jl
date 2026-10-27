@testitem "format_number writes a number in the table's language" tags=[:unit] begin
    using HTMXObjects
    de, en = table_texts(:de), table_texts()
    f(x; kw...) = format_number(x; texts=de, kw...)
    # Every digit Julia prints, in German; a float's trailing `.0` is no digit.
    @test f(0.15623) == "0,15623" && f(2.0) == "2" && f(-0.0) == "0" && f(0.0) == "0"
    @test f(1234567.25) == "1.234.567,25" && f(1234567.0) == "1.234.567" && f(123456.0) == "123.456"
    @test f(100000.0) == "100.000" && f(-1234.5) == "-1.234,5" && f(0.001) == "0,001"
    # A power of ten below 10⁻⁴ and from 10¹⁵ up, with superscript digits.
    @test f(3.81e-5) == "3,81·10⁻⁵" && f(-3.81e-5) == "-3,81·10⁻⁵" && f(1e-5) == "1·10⁻⁵"
    @test f(1e-4) == "0,0001" && f(9.99e-5) == "9,99·10⁻⁵"
    @test f(1e15) == "1·10¹⁵" && f(1.5e15) == "1,5·10¹⁵" && f(999999999999999.0) == "999.999.999.999.999"
    @test f(5e-324) == "5·10⁻³²⁴" && f(floatmax()) == "1,7976931348623157·10³⁰⁸"
    # English writes the same numbers with its own marks.
    @test format_number(0.15623) == "0.15623" && format_number(3.81e-5) == "3.81·10⁻⁵"
    @test format_number(1234567) == "1,234,567" && format_number(1234567.25; texts=en) == "1,234,567.25"
    # Integers keep every digit, grouped, and never switch to a power of ten.
    @test f(1234567) == "1.234.567" && f(-1234) == "-1.234" && f(42) == "42" && f(0) == "0"
    @test f(10^18) == "1.000.000.000.000.000.000" && f(typemin(Int)) == "-9.223.372.036.854.775.808"
    @test f(big(10)^20) == "100.000.000.000.000.000.000"
    # Significant digits round first, halves away from zero like fixed
    # decimals (`round(x; sigdigits=2)` gives 2800 and 0.12), carrying into a
    # new digit; then the rounded number is written as above.
    @test f(0.15623; sigdigits=3) == "0,156" && f(3.81234e-5; sigdigits=3) == "3,81·10⁻⁵"
    @test f(1234567; sigdigits=3) == "1.230.000" && f(1234567.25; sigdigits=2) == "1.200.000"
    @test f(9.9996e-5; sigdigits=3) == "0,0001"
    @test f(2850; sigdigits=2) == "2.900" && f(2850.0; sigdigits=2) == "2.900" && f(-2850.0; sigdigits=2) == "-2.900"
    @test f(0.125; sigdigits=2) == "0,13" && f(2.5; sigdigits=1) == "3" && f(29210.0; sigdigits=2) == "29.000"
    @test f(9.96; sigdigits=2) == "10" && f(99.96; sigdigits=3) == "100" && f(-0.0; sigdigits=2) == "0"
    @test f(1.5e15; sigdigits=1) == "2·10¹⁵" && f(999999999999999.0; sigdigits=15) == "999.999.999.999.999"
    @test f(5e-324; sigdigits=2) == "4,9·10⁻³²⁴" && f(floatmax(); sigdigits=3) == "1,8·10³⁰⁸"
    # An integer rounded to significant digits stays an integer: every digit.
    @test f(10^16 + 5 * 10^14; sigdigits=2) == "11.000.000.000.000.000" && f(10^16; sigdigits=2) == "10.000.000.000.000.000"
    # Fixed decimals are the group sums' own: halves away from zero.
    @test f(0.15623; digits=2) == "0,16" && f(3.81e-5; digits=2) == "0,00" && f(1234.0; digits=2) == "1.234,00"
    @test f(1234; digits=2) == "1.234,00" && f(1234; digits=0) == "1.234" && f(1e15; digits=0) == "1.000.000.000.000.000"
    @test [format_number(x; texts=en, digits=d) for (x, d) in ((1234567.891, 2), (0.125, 2), (-0.004, 2), (999.5, 0), (1e15, 0))] ==
        ["1,234,567.89", "0.13", "0.00", "1,000", "1,000,000,000,000,000"]
    @test format_number(-1234.5; texts=de, digits=1) == "-1.234,5"
    @test format_number(1234.5; texts=table_texts(:de; thousands=" "), digits=1) == "1 234,5"
    # No value, infinities and NaN; other reals as their float.
    @test f(missing) == "–" && f(nothing) == "–" && f(missing; digits=2) == "–"
    @test f(Inf) == "∞" && f(-Inf) == "-∞" && f(NaN) == "NaN" && f(Inf; digits=2) == "∞"
    @test f(1 // 4) == "0,25" && f(Float32(0.1)) == "0,1" && f(Float16(0.5)) == "0,5" && f(π; sigdigits=3) == "3,14"
    # Refused: digits outside the group sums' range, sigdigits outside 1 to
    # 15 (the digits the browser's group sums round exactly), both at once,
    # a Bool and a value that is not a number.
    @test_throws ArgumentError f(1.0; digits=11)
    @test_throws ArgumentError f(1.0; digits=-1)
    @test_throws ArgumentError f(1.0; sigdigits=0)
    @test_throws ArgumentError f(1.0; sigdigits=16)
    @test_throws ArgumentError f(1.0; digits=2, sigdigits=3)
    @test_throws ArgumentError f(true)
    @test_throws ArgumentError f("1.5")
end

@testitem "number_cell keeps the exact value for sorting and the CSV" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    html(x) = repr("text/html", x)
    de = table_texts(:de)
    attr(cell, name) = let m = match(Regex("$name=\"([^\"]*)\""), cell); isnothing(m) ? nothing : m[1] end
    text(cell) = match(r">([^<]*)</td>", cell)[1]
    c = html(number_cell(0.15623; texts=de, sigdigits=3))
    @test startswith(c, "<td ") && text(c) == "0,156"
    @test attr(c, "data-sort-value") == "0.15623" && attr(c, "data-htmxo-number") == "0.15623"
    tiny = html(number_cell(3.81e-5; texts=de))
    @test text(tiny) == "3,81·10⁻⁵" && attr(tiny, "data-sort-value") == "3.81e-5" && attr(tiny, "data-htmxo-number") == "3.81e-5"
    large = html(number_cell(1234567.25; texts=de, digits=1))
    @test text(large) == "1.234.567,3" && attr(large, "data-sort-value") == "1.23456725e6"
    @test attr(html(number_cell(1234567)), "data-sort-value") == "1234567" && text(html(number_cell(1234567))) == "1,234,567"
    # `parseFloat` does not know `Inf`.
    @test attr(html(number_cell(-Inf)), "data-sort-value") == "-Infinity" && text(html(number_cell(-Inf))) == "-∞"
    # No value: a dash, no sort key, an empty CSV field.
    gap = html(number_cell(missing; texts=de))
    @test text(gap) == "–" && isnothing(attr(gap, "data-sort-value")) && attr(gap, "data-htmxo-number") == ""
    # Further attributes reach the cell, and a given sort key wins.
    styled = html(number_cell(0.5; class="num", data_sort_value="b"))
    @test attr(styled, "class") == "num" && attr(styled, "data-sort-value") == "b" && attr(styled, "data-htmxo-number") == "0.5"
    @test_throws ArgumentError number_cell(1.0; digits=2, sigdigits=2)
end

@testitem "render_table writes floats in the table's language" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    html(x) = repr("text/html", x)
    table = (name=["a", "b"], share=[0.15623, 3.81e-5], year=[2024, 10115], ok=[true, false])
    de = html(render_table(table; texts=table_texts(:de)))
    @test contains(de, ">0,15623</td>") && contains(de, ">3,81·10⁻⁵</td>") && contains(de, "data-sort-value=\"3.81e-5\"")
    @test contains(de, "data-htmxo-number=\"0.15623\"")
    # Integers, Bools and text stay as written: a year is not 2.024.
    @test contains(de, "<td>2024</td>") && contains(de, "<td>10115</td>") && contains(de, "<td>true</td>") && contains(de, "<td>a</td>")
    # English keeps its digits; a custom cell renderer still writes the content.
    en = html(render_table((x=[1234.5, 2.0],)))
    @test contains(en, ">1,234.5</td>") && contains(en, ">2</td>") && contains(en, "data-sort-value=\"1234.5\"")
    custom = html(render_table(table; texts=table_texts(:de), cell=(v, c, i) -> string(v)))
    @test contains(custom, "<td>0.15623</td>") && !contains(custom, "data-sort-value")
    # Markdown carries the shown text.
    md = to_markdown_string(render_table(table; texts=table_texts(:de)))
    @test contains(md, "0,15623") && contains(md, "3,81·10⁻⁵")
    # A SemanticTable's peers: HTML and Markdown show the number as the table
    # writes it; the tab-separated plain text keeps the value, as the CSV does.
    st = SemanticTable((name=["a"], x=[1234.5], tiny=[3.81e-5], n=[2024]))
    @test contains(repr("text/html", st), ">1,234.5</td>") && contains(repr("text/html", st), ">3.81·10⁻⁵</td>")
    @test contains(repr("text/markdown", st), "| a | 1,234.5 | 3.81·10⁻⁵ | 2024 |")
    @test contains(repr("text/plain", st), "a\t1234.5\t3.81e-5\t2024")
end

@testitem "a bare float among master cells is a number cell" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    html(x) = repr("text/html", x)
    de = table_texts(:de)
    items = [(id="a", name="Alpha", x=0.15623), (id="b", name="Beta", x=1234567.25)]
    flat = html(master_detail_table(["Name", "x"], items; key=it -> it.id,
        master=it -> (h.td(it.name), it.x), detail=it -> h.p("d"), texts=de))
    @test contains(flat, ">0,15623</td>") && contains(flat, ">1.234.567,25</td>") && contains(flat, "data-sort-value=\"1.23456725e6\"")
    # The row form, and a float in the first cell, which holds the row's controls.
    row = html(master_detail_table(["x", "Name"], items; key=it -> it.id,
        master=it -> h.tr(it.x, h.td(it.name); data_kind="k"), detail=it -> h.p("d"), texts=de))
    @test contains(row, "data-kind=\"k\"") && contains(row, "data-htmxo-number=\"0.15623\"") &&
        contains(row, "<span data-htmxo-row-label=\"\">0,15623</span>")
    pair = html(h.tbody(master_detail_pair("a", Any[h.td("Alpha"), 0.15623], h.p("d"), 2; texts=de)...))
    @test contains(pair, ">0,15623</td>")
    # The text a lazy group's search reaches is the text its rows show.
    tx = [(; id="p$i", party=isodd(i) ? "Acme" : "Bakery", amount=-1000.5 * i) for i in 1:4]
    lazy = html(master_detail_table(["Party", "Amount"], tx; key=t -> t.id,
        master=t -> (h.td(t.party), t.amount), detail=t -> h.p("d"), texts=de,
        groupings=["party" => t -> t.party], group_by=["party"], group_rows_url=(k, ms) -> "/rows?key=$k"))
    @test contains(lazy, "[&quot;p1&quot;,&quot;Acme -1.000,5&quot;]")
end

@testitem "German number cells sort by value and export their number browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        de = table_texts(:de)
        xs = [0.156, 3.81e-5, 1234567.25, missing, 12.0]
        names = ["a", "b", "c", "d", "e"]
        cells = sortable_table(["Name", "x"], [h.tr(h.td(n), number_cell(x; texts=de)) for (n, x) in zip(names, xs)];
            id="cells", download=false, texts=de)
        # Control: the same German text without the cell's sort key.
        texts_only = sortable_table(["Name", "x"], [h.tr(h.td(n), h.td(format_number(x; texts=de))) for (n, x) in zip(names, xs)];
            id="texts", download=false, texts=de)
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const order = id => {
                    const body = document.getElementById(id);
                    body.closest('table').querySelectorAll('thead th')[1].click();
                    return Array.from(body.rows).map(r => r.cells[0].textContent).filter(n => n !== 'd').join(',');
                };
                document.body.dataset.cells = order('cells');
                document.body.dataset.texts = order('texts');
                const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
                let blob = null;
                URL.createObjectURL = b => { blob = b; return 'blob:test'; };
                HTMLAnchorElement.prototype.click = function() {};
                try { downloadTableCsv(document.getElementById('cells'), 'cells.csv'); } finally {
                    URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
                }
                document.body.dataset.csv = blob ? await blob.text() : '';
                document.body.dataset.done = '1';
            });
            """))
        page = string("<!doctype html><html><head><meta charset=\"utf-8\">", repr("text/html", sortable_table_js()),
            repr("text/html", download_table_js()), "</head><body>", repr("text/html", cells),
            repr("text/html", texts_only), repr("text/html", driver), "</body></html>")
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, page)
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        attr(name) = let m = match(Regex("data-$name=\"([^\"]*)\""), dom); isnothing(m) ? nothing : m[1] end
        # By value: 3,81·10⁻⁵ < 0,156 < 12 < 1.234.567,25. The text alone sorts
        # 0,156 as 0, 1.234.567,25 as 1.234 and 3,81·10⁻⁵ as 3.
        @test attr("cells") == "b,a,e,c"
        @test attr("texts") == "a,c,b,e"
        unescape(s) = replace(s, "&quot;" => "\"", "&#10;" => "\n", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">")
        # The CSV holds the numbers, in the sorted order, and an empty field for no value.
        csv = unescape(something(attr("csv"), ""))
        @test split(csv, '\n')[1] == "Name,x"
        @test Set(split(csv, '\n')[2:end]) == Set(["b,3.81e-5", "a,0.156", "e,12.0", "c,1.23456725e6", "d,"])
    end
end
