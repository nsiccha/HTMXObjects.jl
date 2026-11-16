using TestItemRunner

@testitem "table density and header alignment are independent and preserve cell alignment" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    heads(x) = [m.match for m in eachmatch(r"<th[ >][^>]*>", html(x))]
    cells(x) = [m.match for m in eachmatch(r"<td[^>]*>", html(x))]
    data = (name=["A", "B"], value=[2.0, 1.0])
    normal = render_table(data)
    @test html(normal) == html(render_table(data; density=:normal, header_align=nothing))
    compact = render_table(data; density=:compact)
    @test heads(compact) == heads(normal)
    @test cells(compact) == cells(normal)
    @test contains(html(compact), "class=\"striped htmxo-sortable-table\"")
    @test contains(html(compact), "data-htmxo-density=\"compact\"")
    left = render_table(data; header_align=:left)
    @test all(contains("data-htmxo-align=\"left\""), heads(left))
    @test cells(left) == cells(normal)
    @test !contains(html(left), "data-htmxo-density")
    @test html(render_table(data; density="compact", header_align="left")) ==
          html(render_table(data; density=:compact, header_align=:left))
    for align in (:left, :center, :right)
        table = render_table(data; header_align=align,
            columns=[:value => ColumnSpec("Value"; align=:center)])
        @test all(contains("data-htmxo-align=\"$align\""), heads(table))
        @test all(c -> contains(c, "data-htmxo-align=\"center\""), cells(table)[2:2:end])
    end
    for density in (:dense, nothing, 1)
        @test_throws ArgumentError render_table(data; density)
    end
    for header_align in (:middle, 1)
        @test_throws ArgumentError render_table(data; header_align)
    end
    rows = [h.tr(number_cell(1.5), number_cell(2.5), number_cell(3.5))]
    own = h.th("Own"; data_htmxo_align="right")
    grouped = sortable_table([own, ColumnSpec("A"; align=:right), "B"], rows;
        density=:compact, header_align=:left, header_groups=["Group" => 2:3])
    @test contains(first(heads(grouped)), "data-htmxo-align=\"right\"")
    @test count(contains("data-htmxo-align=\"left\""), heads(grouped)) == 2
    @test !contains(html(own), "left")
    @test !contains(html(rows[1]), "data-htmxo-align")
    plain = sortable_table(["A"], [h.tr(number_cell(1.5))]; sortable=false,
        density=:compact, header_align=:left, class="")
    @test contains(html(plain), "<th data-htmxo-align=\"left\">A</th>")
    @test !contains(html(plain), "htmxo-sort-control")
    items = [(id="a", value=1.5)]
    detail(; kw...) = master_detail_table(["Name", "Value"], items; key=x -> x.id,
        master=x -> (h.td(x.id), number_cell(x.value)), detail=x -> h.p("Detail"), kw...)
    styled = detail(; density=:compact, header_align=:left, class="")
    @test contains(html(styled), "data-htmxo-density=\"compact\"")
    @test all(contains("data-htmxo-align=\"left\""), heads(styled))
    @test cells(styled) == cells(detail())
    @test HTMXObjects.to_markdown_string(styled) == HTMXObjects.to_markdown_string(detail())
end

@testitem "compact tables fit fourteen rows with CSV in a 512px frame in both themes" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        data = (name=["Region $i" for i in 1:24], value=Float64.(24:-1:1))
        compact = render_table(data; id="compact", density=:compact, header_align=:left, class="")
        normal = render_table(data; id="normal")
        nested = sortable_table(["Outer"], [h.tr(; id="row-a")(h.td("Master")),
            h.tr(; id="detail-a")(h.td(render_table(data; id="nested"); colspan=1))]; density=:compact)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const out = {};
          const frame = document.querySelector('#frame'), t = document.querySelector('#compact').closest('table');
          const next = () => new Promise(r => setTimeout(r, 100));
          const px = (e, name) => parseFloat(getComputedStyle(e)[name]);
          try {
            for (const theme of ['light', 'dark']) {
              document.documentElement.dataset.theme = theme;
              frame.scrollTop = 0;
              await next();
              const box = frame.getBoundingClientRect(), rows = Array.from(t.tBodies[0].rows);
              const th = t.tHead.rows[0].cells[1], td = rows[0].cells[1];
              out[theme] = {
                root: px(document.documentElement, 'fontSize'), height: box.height,
                complete: rows.filter(r => { const b = r.getBoundingClientRect(); return b.top >= box.top && b.bottom <= box.bottom; }).length,
                font: px(td, 'fontSize'), padding: px(td, 'paddingTop'), row: rows[0].getBoundingClientRect().height,
                head: getComputedStyle(th).textAlign, cell: getComputedStyle(td).textAlign,
                stripe: t.classList.contains('striped'),
                normalFont: px(document.querySelector('#normal td'), 'fontSize'),
                normalPadding: px(document.querySelector('#normal td'), 'paddingTop'),
                nestedFont: px(document.querySelector('#nested td'), 'fontSize'),
                nestedPadding: px(document.querySelector('#nested td'), 'paddingTop')
              };
              frame.scrollTop = 160;
              await next();
              out[theme].stickyGap = Math.abs(th.getBoundingClientRect().top - box.top);
            }
            frame.scrollTop = 0;
            t.tHead.rows[0].cells[1].querySelector('button').click();
            out.first = t.tBodies[0].rows[0].cells[1].getAttribute('data-htmxo-number');
            out.sort = t.tHead.rows[0].cells[1].getAttribute('aria-sort');
            let blob;
            const create = URL.createObjectURL;
            URL.createObjectURL = b => { blob = b; return create(b); };
            document.addEventListener('click', e => { if (e.target.closest('a[download]')) e.preventDefault(); }, true);
            frame.querySelector('.caption-action').click();
            out.csv = await blob.text();
            URL.createObjectURL = create;
          } catch (error) { out.error = String(error); }
          const pre = document.createElement('pre'); pre.id = 'out'; pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
        }, {once: true});
        """))
        content = h.main(h.div(compact; id="frame"), normal, nested, driver)
        dom = mktempdir() do dir
            copy_vendorfiles(joinpath(dir, "vendor"); packages=(:pico,))
            fixture = joinpath(dir, "page.html")
            # Fixture-only geometry: the production result frame supplies this
            # scrolling height through semantic_app(result_height="32rem").
            page = htmx(content; assets="vendor", pico_version=HTMXObjects._PICO_VERSION,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing)
            write(fixture, replace(repr("text/html", page), "</head>" =>
                "<style>#frame { height:32rem; overflow:auto; width:880px }</style></head>"))
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,1000 --virtual-time-budget=5000 --dump-dom --user-data-dir=$(joinpath(dir, "profile")) file://$fixture`)
        end
        m = match(r"<pre id=\"out\">([^<]*)</pre>", dom)
        @test !isnothing(m)
        out = HTMXObjects.JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
        @test !haskey(out, "error")
        for theme in ("light", "dark")
            v = out[theme]
            @test v["root"] == 16 && v["height"] == 512
            @test v["complete"] >= 14
            @test v["font"] ≈ 14.4 && v["padding"] == 4
            @test v["head"] == "left" && v["cell"] == "right" && !v["stripe"]
            @test v["normalFont"] == v["nestedFont"] == 16
            @test v["normalPadding"] == v["nestedPadding"] == 8
            @test v["stickyGap"] <= 2
        end
        @test out["first"] == "1.0" && out["sort"] == "ascending"
        @test startswith(out["csv"], "name,value\nRegion 24,1.0")
        @test length(split(strip(out["csv"]), '\n')) == 25
    end
end
