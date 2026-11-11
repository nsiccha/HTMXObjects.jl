using TestItemRunner

@testitem "a cell spanning columns sorts under its first and keeps later cells in theirs" setup=[HTMXOTestImports, ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        cell(x, v) = h.td(x; data_sort_value=string(v))
        rows = [h.tr(; id="c")(cell("c", 3), cell("c1", 30), cell("c2", 10)),
                # Spans the last two columns.
                h.tr(; id="s")(cell("s", 2), h.td("WEIT"; colspan="2", data_sort_value="20")),
                h.tr(; id="b")(cell("b", 4), cell("b1", 10), cell("b2", 30)),
                # Spans the first two: its own last cell is in the third column.
                h.tr(; id="l")(h.td("LINKS"; colspan="2", data_sort_value="1"), cell("l2", 20))]
        driver = h.script(HTMXObjects.Raw(raw"""
        window.addEventListener('load', async () => {
          const out = {};
          const table = document.querySelector('table');
          const order = () => Array.from(table.tBodies[0].rows).map(r => r.id).join(',');
          const sort = c => { table.tHead.rows[0].cells[c].querySelector('.htmxo-sort-control').click(); return order(); };
          out.col0 = sort(0);
          out.col1 = sort(1);
          out.col2 = sort(2);
          const createURL = URL.createObjectURL, click = HTMLAnchorElement.prototype.click;
          let blob = null;
          URL.createObjectURL = b => { blob = b; return 'blob:test'; };
          HTMLAnchorElement.prototype.click = function () {};
          try { downloadTableCsv(table, 't.csv'); } finally { URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = click; }
          out.csv = (await blob.text()).split('\n').sort().join('|');
          const pre = document.createElement('pre');
          pre.id = 'out';
          pre.textContent = JSON.stringify(out);
          document.body.appendChild(pre);
        });
        """))
        page = repr("text/html", htmx(h.main(sortable_table(["A", "B", "C"], rows; id="t"), driver);
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing))
        result = mktempdir() do dir
            file = joinpath(dir, "t.html")
            write(file, page)
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$(joinpath(dir, "p")) file://$file`; timeout=60)
            m = match(r"<pre id=\"out\">([^<]*)</pre>", dom)
            isnothing(m) ? "" : replace(m[1], "&quot;" => "\"", "&amp;" => "&")
        end
        @test !isempty(result)
        field(name) = (m = match(Regex("\"$name\":\"([^\"]*)\""), result); isnothing(m) ? nothing : m[1])
        # Column A: three rows by value; the row spanning from it starts there.
        @test field("col0") == "l,s,c,b"
        # Column B: `s`'s wide cell starts there and counts; `l`'s covers it, so `l`
        # is not ordered by it.
        @test field("col1") == "l,b,s,c"
        # Column C: `l`'s own cell is in it, one cell further left than its column;
        # `s`'s wide cell only covers it.
        @test field("col2") == "s,c,l,b"
        # CSV: every row has its three columns, and what a span covers is blank.
        @test field("csv") == "A,B,C|LINKS,,l2|b,b1,b2|c,c1,c2|s,WEIT,"
    end
end
