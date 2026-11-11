using TestItemRunner


@testmodule InstanceScopeFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw
    export scope_page, station_view, nested_answer, detail_answer, day_view, InstanceScopeApp, SCOPE_CHECKS

    # 21 checks for each of the page's three places, 5 for the page, 4 for
    # the table whose rows load one fragment (`detail_instance=true`).
    const SCOPE_CHECKS = 21 * 3 + 5 + 4

    # What an AoV plot's scripts and caption controls do with a plot id: draw
    # into the element, download it, and find its remap controls by building
    # their ids and names around it.
    const FAKE_AOV = h.script(Raw(raw"""
    window.FakeAoV = {
      embed: function (id) {
        var el = document.getElementById(id);
        el.dataset.drawn = String(Number(el.dataset.drawn || 0) + 1);
      },
      download: function (id, format, name) { document.getElementById(id).dataset.downloaded = format + ':' + name; },
      remap: function (ch, id) {
        var select = document.getElementById('aov-remap-' + ch + '-' + id);
        var same = document.querySelectorAll('select[id^="aov-remap-"][id$="-' + id + '"]');
        var pins = document.querySelectorAll('input[name="aov-pin-' + id + '"]');
        if (select) select.dataset.remapped = same.length + ':' + pins.length;
      }
    };
    """))

    const DRIVER = h.script(Raw(raw"""
    window.addEventListener('load', async function () {
      const checks = [];
      const check = (name, ok) => checks.push(name + ':' + (ok === true ? 'true' : 'false ' + String(ok)));
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const wait = async (cond, n = 250) => { for (let i = 0; i < n && !cond(); i++) await sleep(20); return cond(); };
      const byId = id => document.getElementById(id);
      const dupes = () => {
        const seen = new Set(), twice = [];
        document.querySelectorAll('[id]').forEach(e => { if (seen.has(e.id)) twice.push(e.id); seen.add(e.id); });
        return twice;
      };
      const scoped = Boolean(document.querySelector('[data-htmxo-instance]'));
      const slots = Array.from(document.querySelectorAll('.slot'));
      try {
        if (!scoped) {
          await wait(() => slots.every(s => s.querySelector('.plot')));
          check('bare-loaded', slots.every(s => s.querySelector('.plot')));
          check('bare-duplicates', dupes().length > 0);
          const drawn = slots.map(s => s.querySelector('.plot').dataset.drawn || '0').join(',');
          check('bare-draws-collide', drawn !== '1,1,1' || drawn);
        } else {
          await wait(() => slots.every(s => s.querySelector('.plot') && s.querySelector('.inner')));
          const want = {'slot-karte': '--karte', 'slot-liste': '--liste', 'slot-inner': '--outer--inner'};
          for (const s of slots) {
            const sfx = want[s.id], c = (name, ok) => check(s.id + '-' + name, ok);
            const inside = el => Boolean(el) && s.contains(el);
            c('suffix', htmxoInstanceSuffix(s) === sfx || htmxoInstanceSuffix(s));
            const plot = s.querySelector('.plot');
            c('plot-id', plot.id === 'plot-1' + sfx || plot.id);
            c('plot-drawn-once', plot.dataset.drawn === '1' || plot.dataset.drawn);
            c('plot-data-id', plot.dataset.plotId === plot.id || plot.dataset.plotId);
            c('popover', inside(byId(s.querySelector('[popovertarget]').getAttribute('popovertarget'))));
            c('labelledby', inside(byId(s.querySelector('figure').getAttribute('aria-labelledby'))));
            const fill = s.querySelector('rect[fill]').getAttribute('fill');
            c('svg-fill', (fill === 'url(#hatch-1' + sfx + ')' && inside(byId('hatch-1' + sfx))) || fill);
            c('link', s.querySelector('a.to-title').getAttribute('href') === '#title-1' + sfx);
            c('style', getComputedStyle(plot).minHeight === '7px' || getComputedStyle(plot).minHeight);
            s.querySelector('button.download').click();
            c('download', plot.dataset.downloaded === 'png:plot-1' + sfx || plot.dataset.downloaded);
            const remap = s.querySelector('select.remap');
            c('remap', (remap.id === 'aov-remap-a-plot-1' + sfx && remap.dataset.remapped === '1:2') || remap.id + ' ' + remap.dataset.remapped);
            c('names', Array.from(s.querySelectorAll('input.pin')).every(r => r.name === 'aov-pin-plot-1' + sfx));
            const inner = s.querySelector('.inner');
            c('nested', (inner.id === 'inner-1' + sfx && inside(byId(inner.getAttribute('aria-describedby')))) || inner.id);
            c('nested-target', s.querySelector('button.more').getAttribute('hx-target') === '#nest-1' + sfx);
            // A master/detail table in the place: its rows, their details,
            // a lazy detail and a browser regroup stay in the place.
            const leaf = k => s.querySelector('tr[data-htmxo-leaf="' + k + '"]');
            const detailOf = r => byId('detail-' + r.id.slice(4));
            let row = leaf('kiel');
            c('row-id', row.id.endsWith('kiel' + sfx) || row.id);
            row.click();
            c('detail-open', inside(detailOf(row)) && !detailOf(row).hidden);
            c('detail-loaded', await wait(() => inside(byId('note-kiel' + sfx))));
            htmxoRegroup(s.querySelector('[data-htmxo-regroup]'), []);
            row = leaf('kiel');
            c('regroup-row-id', row.id === 'row-kiel' + sfx || row.id);
            c('regroup-kept-open', inside(detailOf(row)) && !detailOf(row).hidden);
            row.click();
            c('regroup-toggle', inside(detailOf(row)) && detailOf(row).hidden === true);
            leaf('luebeck').click();
            c('regroup-lazy', await wait(() => inside(byId('note-luebeck' + sfx))));
          }
          check('unique', dupes().length === 0 || dupes().join(' '));
          check('page-oob', byId('status').textContent === 'loaded' && !document.querySelector('[id^="status--"]'));
          // A place that loads again gets the same ids, drawn into the new element.
          const s = slots[0], old = s.querySelector('.plot');
          htmx.ajax('GET', s.getAttribute('hx-get'), {target: s, swap: 'innerHTML'});
          check('reload', await wait(() => Boolean(s.querySelector('.plot') && s.querySelector('.plot') !== old && s.querySelector('.inner'))));
          const fresh = s.querySelector('.plot');
          check('reload-ids', (fresh.id === 'plot-1--karte' && fresh.dataset.drawn === '1') || fresh.id + ' ' + fresh.dataset.drawn);
          check('reload-unique', dupes().length === 0 || dupes().join(' '));
          // One table, two rows loading the same address: each row's detail
          // is a place of its own, inside the place around the table.
          const days = ['d1-kiel', 'd2-kiel'];
          days.forEach(k => byId('row-' + k).click());
          const slotOf = k => byId('detail-slot-' + k);
          await wait(() => days.every(k => slotOf(k).querySelector('.mini-plot')));
          check('rows-ids', days.every(k => slotOf(k).querySelector('.mini-plot').id === 'mini-plot--pruefliste--' + k) ||
            days.map(k => slotOf(k).querySelector('.mini-plot') && slotOf(k).querySelector('.mini-plot').id).join(' '));
          check('rows-drawn', days.every(k => slotOf(k).querySelector('.mini-plot').dataset.drawn === '1'));
          check('rows-popover', days.every(k => slotOf(k).contains(byId(slotOf(k).querySelector('[popovertarget]').getAttribute('popovertarget')))));
          check('rows-unique', dupes().length === 0 || dupes().join(' '));
        }
      } catch (err) {
        check('error ' + String(err && err.stack || err).replace(/\s+/g, ' '), false);
      }
      const out = document.createElement('pre');
      out.id = 'checks';
      out.textContent = checks.join('\n');
      document.body.appendChild(out);
    });
    """))

    const PROBES = [(id="kiel", name="Kiel", ort="Nord"), (id="luebeck", name="Lübeck", ort="Süd")]

    # The station view: an AoV-shaped plot with its caption controls, an SVG
    # pattern, a nested request, a page-level out-of-band status, a table.
    station_view() = h.section(; id="probe-1", class="probe")(
        h.h3(; id="title-1")("Probe"),
        h.a(; class="to-title", href="#title-1")("Title"),
        h.style(Raw("#plot-1 { min-height: 7px; }")),
        h.figure(; aria_labelledby="title-1")(
            h.div(; id="plot-1", class="plot", data_plot_id="plot-1"),
            h.script(Raw("FakeAoV.embed('plot-1');")),
            h.button(; type="button", popovertarget="plot-1-download-menu")("⬇"),
            h.div(; id="plot-1-download-menu", popover="")(
                h.button(; type="button", class="download", onclick="FakeAoV.download('plot-1', 'png', 'plot-1')")("PNG")),
            h.select(; id="aov-remap-a-plot-1", class="remap")(h.option("a")),
            h.input(; type="radio", class="pin", name="aov-pin-plot-1", value="x"),
            h.input(; type="radio", class="pin", name="aov-pin-plot-1", value="y"),
            h.script(Raw("FakeAoV.remap('a', 'plot-1');"))),
        h.svg(; width="20", height="20")(
            h.defs(h.pattern(; id="hatch-1", patternUnits="userSpaceOnUse", width="4", height="4")(
                h.rect(; width="4", height="4"))),
            h.rect(; width="20", height="20", fill="url(#hatch-1)")),
        h.div(; id="nest-1"),
        h.button(; type="button", class="more", hx_get="/scope_nested", hx_target="#nest-1", hx_trigger="load")("more"),
        master_detail_table(["Name", "Ort"], PROBES; key=p -> p.id,
            master=p -> (h.td(p.name), h.td(p.ort)),
            detail_url=p -> "/scope_detail?k=" * p.id,
            groupings=["Ort" => p -> p.ort], group_by=["Ort"], id="probes"),
        h.span(; id="status", hx_swap_oob="true")("loaded"))

    nested_answer() = h.p(; id="inner-1", class="inner", aria_describedby="title-1")("inner")
    detail_answer(k) = h.p(; id="note-$k")(k)
    # What each day row of the table loads: one address for every row.
    day_view() = h.div(; class="mini")(
        h.div(; id="mini-plot", class="mini-plot"),
        h.script(Raw("FakeAoV.embed('mini-plot');")),
        h.button(; type="button", popovertarget="mini-menu")("⬇"),
        h.div(; id="mini-menu", popover="")("menu"))

    slot(id) = h.div(; id, class="slot", hx_get="/scope_teil", hx_trigger="load")
    # The page: three places, two side by side and one inside another, or the
    # same three slots without places (the control).
    function scope_page(scoped::Bool)
        place(keys, inner) = foldr((k, x) -> h.section(; data_htmxo_instance=k)(x), keys; init=inner)
        slots = [scoped ? place(keys, slot(id)) : h.section(slot(id)) for (id, keys) in
                 (("slot-karte", ("karte",)), ("slot-liste", ("liste",)), ("slot-inner", ("outer", "inner")))]
        days = master_detail_table(["Tag"], [(id="d1-kiel",), (id="d2-kiel",)]; key=d -> d.id,
            master=d -> (h.td(d.id),), detail_url=_ -> "/scope_tag", detail_instance=scoped, id="days")
        h.main(h.p(; id="status")("waiting"), slots...,
            scoped ? h.section(; data_htmxo_instance="pruefliste")(days) : h.section(days), FAKE_AOV, DRIVER)
    end

    @htmx struct InstanceScopeApp
        __page__(content) = htmx(content; assets=:vendor, runtime=:linked, pico_version=nothing,
            sse_version=nothing, ws_version=nothing, preload_version=nothing, hyperscript_version=nothing)
        @get index() = scope_page(true)
        @get scope_teil() = station_view()
        @get scope_nested() = nested_answer()
        @get scope_detail(; k::String="") = detail_answer(k)
        @get scope_tag() = day_view()
    end
end

@testitem "the shell carries the instance-scope runtime, inline or linked" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    page = repr("text/html", htmx(h.p("x")))
    @test count("if (window.htmxoInstanceScope) return;", page) == 1
    @test contains(page, repr("text/html", instance_scope_script()))
    linked = repr("text/html", htmx(h.p("x"); assets=:vendor, runtime=:linked))
    @test contains(linked, "src=\"/vendor/htmxo/instance_scope.js?v=")
    @test !contains(linked, "window.htmxoInstanceScope")

    # `detail_instance=true`: each lazy detail slot is a place named by its row key.
    rows = [(id="d1 kiel",), (id="d2-kiel",)]
    table(; kw...) = repr("text/html", master_detail_table(["Tag"], rows; key=d -> d.id,
        master=d -> (h.td(d.id),), kw...))
    scoped = table(; detail_url=_ -> "/tag", detail_instance=true)
    @test contains(scoped, "id=\"detail-slot-d1--kiel\"")
    @test count("data-htmxo-instance=\"d1--kiel\"", scoped) == 1
    @test count("data-htmxo-instance=\"d2-kiel\"", scoped) == 1
    @test !contains(table(; detail_url=_ -> "/tag"), "data-htmxo-instance")
    @test_throws ArgumentError table(; detail=d -> h.p(d.id), detail_instance=true)
    pair = repr("text/html", master_detail_pair("k1", (h.td("x"),), nothing, 1; detail_url="/tag", detail_instance=true)[2])
    @test contains(pair, "data-htmxo-instance=\"k1\"")
end

@testitem "a fragment open in several places keeps its ids apart in a browser" setup=[ChromeDump, InstanceScopeFixture, HTMXOTestPorts] tags=[:browser, :integration] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP
        import HTMXObjects: h
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        shell(scoped) = repr("text/html", htmx(scope_page(scoped); assets="/test-assets", pico_version=nothing,
            sse_version=nothing, ws_version=nothing, preload_version=nothing, hyperscript_version=nothing,
            feedback=false, compose=false, overlay=false))
        html(body) = HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body)
        port = free_port()
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            path == "/" && return html(shell(true))
            path == "/bare" && return html(shell(false))
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/scope_teil" && return html(repr("text/html", station_view()))
            path == "/scope_nested" && return html(repr("text/html", nested_answer()))
            path == "/scope_detail" && return html(repr("text/html", detail_answer(HTTP.queryparams(uri)["k"])))
            path == "/scope_tag" && return html(repr("text/html", day_view()))
            HTTP.Response(404)
        end
        try
            for (url, n) in (("/", SCOPE_CHECKS), ("/bare", 3))
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$url`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                isnothing(checks) && continue
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == n
                all(endswith(":true"), lines) && length(lines) == n ||
                    @info "instance-scope browser run" url checks=join(lines, "\n")
            end
        finally
            close(server)
        end
    end
end

@testitem "export_site writes a fragment open in several places once, and its places keep their ids apart" setup=[ChromeDump, InstanceScopeFixture, HTMXOTestPorts] tags=[:browser, :integration] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP
        route!(InstanceScopeApp())
        vendorfiles()
        dir = joinpath(mktempdir(), "site")
        export_site(dir; pages=["/"])
        files = [relpath(joinpath(root, f), dir) for (root, _, fs) in walkdir(dir) for f in fs]
        # Three places load one address: one file.
        @test count(f -> startswith(f, "hx/scope_teil"), files) == 1
        @test "hx/scope_teil.html" in files
        @test "vendor/htmxo/instance_scope.js" in files
        @test count(f -> startswith(f, "hx/scope_detail"), files) == 2
        # Two table rows load one address: one file.
        @test count(f -> startswith(f, "hx/scope_tag"), files) == 1

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        types = Dict(".html" => "text/html; charset=utf-8", ".js" => "application/javascript", ".css" => "text/css")
        port = free_port()
        # The bundle from the site root and from a subdirectory.
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URIs.unescapeuri(HTTP.URI(req.target).path)
            rel = startswith(path, "/sub/") ? path[6:end] : lstrip(path, '/')
            file = joinpath(dir, isempty(rel) ? "index.html" : rel)
            isfile(file) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => get(types, last(splitext(file)), "application/octet-stream")], read(file))
        end
        try
            for url in ("/index.html", "/sub/index.html")
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$url`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                isnothing(checks) && continue
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == SCOPE_CHECKS
                all(endswith(":true"), lines) && length(lines) == SCOPE_CHECKS ||
                    @info "instance-scope export browser run" url checks=join(lines, "\n")
            end
        finally
            close(server)
        end
    end
end
