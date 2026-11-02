using TestItemRunner

@testitem "status tones have one source and reach cells through the Pico bridge" tags=[:unit] begin
    using HTMXObjects
    css(x) = repr("text/html", x)
    theme, bridge = css(htmxo_theme()), css(pico_bridge())
    for sheet in (theme, bridge)
        @test contains(sheet, "--htmxo-success: light-dark(#217d72, #2a9d8f);")
        @test contains(sheet, "--htmxo-warning: light-dark(#9c6311, #e9a23b);")
        @test contains(sheet, "--htmxo-error:   light-dark(#ca3f1c, #e76f51);")
    end
    # Pico's page stylesheet defines none of these, so they only ever fell back.
    @test !contains(bridge, "--pico-color-")
    # Unlayered, because Pico's `td, th` rule is, and as weak as that rule, so an
    # app's rule still wins. `:is(td, th)` names only the cell: `tr[data-status]`
    # stays out.
    @test !contains(split(bridge, ":is(td, th):where([data-status])")[1], "@layer")
    @test contains(bridge, ":is(td, th):where([data-status]) { font-weight: bold; }")
    for status in ("success", "error", "warning", "muted")
        @test contains(bridge, ":is(td, th):where([data-status=\"$status\"]) { color: var(--htmxo-$status); }")
    end
    # They move with a tinted row's other tones (test/table_linking.jl measures it).
    for token in ("--htmxo-success", "--htmxo-warning", "--htmxo-error")
        @test token in first.(HTMXObjects._TINTED_ROW_TONES)
    end
    # Every page gets the tones; only a Pico page has a cell rule to outweigh.
    @test contains(css(htmx(h.p("x"))), "light-dark(#217d72, #2a9d8f)")
    @test !contains(css(htmx(h.p("x"))), ":is(td, th):where([data-status")
    @test contains(css(htmx(h.p("x"); pico_version="2")), ":is(td, th):where([data-status")
end

# Snag data-status-colo-eae6eb27 (reporter HTMXObjects:snag.focused-master-d-b37a1471):
# `td[data-status]` rendered as body text under Pico, and all three tones sat
# under 4.5:1 on a white page, down to 2.17:1 for warning.
@testitem "status text reaches cells and keeps 4.5:1 in light and dark" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    import HTMXObjects: Raw
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        tones = ("success", "warning", "error")
        table = h.table(; id="plain")(
            h.thead(h.tr(h.th("Plain"; id="th-plain"), [h.th(s; data_probe="th-$s", data_status=s) for s in tones]...)),
            h.tbody(
                h.tr(h.td("Plain"; id="td-plain"), [h.td(s; data_probe="td-$s", data_status=s) for s in tones]...),
                # A status row keeps Pico's cells: the KB's agent roster relies on it.
                h.tr(; data_status="error")(h.td("Row"; id="td-in-status-row")),
                h.tr(h.td("Muted"; id="td-muted", data_status="muted")),
                # The weakest rule an app can write, after the bridge, beats it.
                h.tr(h.td("App"; class="app-cell", id="td-app", data_status="error"))))
        striped = h.table(; class="striped")(h.tbody(
            h.tr([h.td(s; data_probe="striped-$s", data_status=s) for s in tones]...),
            h.tr(h.td("even"))))
        semantic = (:ok => "semantic-success", :warn => "semantic-warning", :fail => "semantic-error")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const cv = document.createElement('canvas'); cv.width = cv.height = 1;
            const c = cv.getContext('2d', {willReadFrequently: true});
            const rgba = s => { c.clearRect(0, 0, 1, 1); c.fillStyle = 'rgba(0,0,0,0)'; c.fillStyle = s; c.fillRect(0, 0, 1, 1);
                const d = c.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2], d[3] / 255]; };
            const over = (t, b) => [0, 1, 2].map(i => t[i] * t[3] + b[i] * (1 - t[3]));
            const lin = v => (v /= 255) <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4;
            const lum = p => .2126 * lin(p[0]) + .7152 * lin(p[1]) + .0722 * lin(p[2]);
            const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + .05) / (y + .05); };
            const backdrop = el => { const path = []; for (let e = el; e; e = e.parentElement) path.unshift(e);
                let bg = [255, 255, 255];
                for (const e of path) bg = over(rgba(getComputedStyle(e).backgroundColor), bg);
                return bg; };
            const css = id => getComputedStyle(document.getElementById(id));
            const out = [];
            for (const theme of ['light', 'dark']) {
                document.documentElement.dataset.theme = theme;
                // The tones only mean something if Pico is really painting this theme.
                out.push(`${theme} scheme: ` + (getComputedStyle(document.documentElement).colorScheme === theme));
                out.push(`${theme} plain cell: ` + (css('td-plain').fontWeight));
                for (const probe of document.querySelectorAll('[data-probe]')) {
                    // A `SemanticStatus` colours its own element, inside the probe's.
                    const e = probe.querySelector('.htmxo-semantic-status') || probe;
                    const s = getComputedStyle(e), bg = backdrop(e), name = probe.dataset.probe;
                    out.push(`${theme} ratio ${name}: ` + ratio(over(rgba(s.color), bg), bg).toFixed(2));
                    out.push(`${theme} weight ${name}: ` + s.fontWeight);
                    out.push(`${theme} differs ${name}: ` + (s.color !== css('td-plain').color));
                }
                const plain = css('td-plain'), inRow = css('td-in-status-row'), app = css('td-app'), muted = css('td-muted');
                out.push(`${theme} status row keeps cells: ` + (inRow.color === plain.color && inRow.fontWeight === plain.fontWeight));
                out.push(`${theme} app colour wins: ` + (app.color === 'rgb(1, 2, 3)'));
                out.push(`${theme} app weight wins: ` + (app.fontWeight === '300'));
                out.push(`${theme} muted cell: ` + (muted.color === getComputedStyle(document.getElementById('small-muted')).color && Number(muted.fontWeight) >= 700));
            }
            // `light-dark()` follows the scheme where the tone is used, not the root's.
            document.documentElement.dataset.theme = 'light';
            out.push('nested dark: ' + (css('nested-dark').color !== css('nested-light').color));
            const result = document.createElement('pre'); result.id = 'checks'; result.textContent = out.join('\n');
            document.body.appendChild(result);
        });
        """))
        app = h.style(Raw("td:where(.app-cell) { color: rgb(1, 2, 3); font-weight: 300; } " *
                          "*, *::before, *::after { transition: none !important; }"))
        content = h.main(; class="container")(table, striped,
            h.p([h.span(s; data_probe="span-$s", data_status=s) for s in tones]...),
            h.p([h.small(s; data_probe="small-$s", data_status=s) for s in tones]...),
            h.p(h.small("muted"; id="small-muted", data_status="muted")),
            h.p([h.span(; data_probe=name)(SemanticStatus(kind)) for (kind, name) in semantic]...),
            h.p([h.span(s; class="u-text-$s", data_probe="utility-$s") for s in tones]...),
            # Pico's darkest surface in light, and its lightest in dark.
            h.article(h.header([h.span(s; data_probe="card-$s", data_status=s) for s in tones]...), h.p("Body")),
            h.p(h.span("light"; id="nested-light", data_status="success")),
            h.div(; data_theme="dark")(h.span("dark"; id="nested-dark", data_status="success")),
            driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor", pico_version=HTMXObjects._PICO_VERSION,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing, extra_head=(app,))))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1200,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        checks = Dict(Pair(split(line, ": "; limit=2)...) for line in
            eachsplit(something(match(r"<pre id=\"checks\">(.*?)</pre>"s, dom), (; captures=[""])).captures[1], '\n')
            if contains(line, ": "))
        @test !isempty(checks)
        for theme in ("light", "dark")
            @test checks["$theme scheme"] == "true"
            # Positive control: a cell without the attribute keeps Pico's weight.
            @test parse(Int, checks["$theme plain cell"]) < 700
            for prefix in ("td", "th", "striped", "span", "small", "semantic", "utility", "card"), tone in tones
                @test parse(Float64, checks["$theme ratio $prefix-$tone"]) >= 4.5
                @test checks["$theme differs $prefix-$tone"] == "true"
            end
            for prefix in ("td", "th", "striped"), tone in tones
                @test parse(Int, checks["$theme weight $prefix-$tone"]) >= 700
            end
            @test checks["$theme status row keeps cells"] == "true"
            @test checks["$theme app colour wins"] == "true"
            @test checks["$theme app weight wins"] == "true"
            @test checks["$theme muted cell"] == "true"
        end
        @test checks["nested dark"] == "true"
    end
end
