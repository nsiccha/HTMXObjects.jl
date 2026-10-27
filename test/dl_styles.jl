@testitem "every page shell carries the definition-list layout" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", htmxo_utility_styles())
    @test occursin(r"dl:not\(\[hidden\]\) \{\s*display: grid;\s*grid-template-columns: fit-content\(min\(var\(--htmxo-dl-label-width, 16rem\), 40%\)\) minmax\(0, 1fr\);"s, css)
    @test occursin("grid-template-columns: subgrid;", css)
    # A one-word term wraps, so the 40% cap holds; a list in a narrow
    # `SemanticGroup` item stacks.
    @test occursin(r":is\(dl, dl > div\) > dt \{[^}]*hyphens: auto; overflow-wrap: anywhere;"s, css)
    @test occursin(r"\.htmxo-semantic-group > \* \{[^}]*container-type: inline-size;\s*contain-intrinsic-inline-size: var\(--htmxo-semantic-group-min, 20rem\);"s, css)
    @test occursin(r"@container \(width < 24rem\) \{\s*dl:not\(\[hidden\]\), dl > div:not\(\[hidden\]\) \{ display: block; \}"s, css)
    # Layered, so an app's own unlayered `dl` rule always wins.
    layer = findfirst("@layer htmxo {", css)
    rule = findfirst("dl:not([hidden]) {", css)
    @test !isnothing(layer) && !isnothing(rule) && first(layer) < first(rule)
    for page in (htmx(h.dl(h.dt("a"), h.dd("1"))), htmx(h.dl(h.dt("a"), h.dd("1")); pico_version="2"))
        @test occursin("dl:not([hidden]) {", repr("text/html", page))
    end
end

@testitem "definition lists put each term beside its value in Chrome" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # One line per list: whether every term sits on its value's row and
        # left of it, the value's x offset in the list, the widest term, the
        # term's weight, the list's height, whether the values all start at
        # one x, and the list's width. A list without an id is named by the
        # `data-probe` wrapper around it.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const out = [];
            for (const dl of document.querySelectorAll('dl[id], [data-probe] dl')) {
                const box = dl.getBoundingClientRect();
                const dts = [...dl.querySelectorAll('dt')], dds = [...dl.querySelectorAll('dd')];
                let side = dts.length > 0;
                for (const dt of dts) {
                    let dd = dt.nextElementSibling;
                    while (dd && dd.tagName !== 'DD') dd = dd.nextElementSibling;
                    const a = dt.getBoundingClientRect(), b = dd.getBoundingClientRect();
                    side = side && Math.abs(a.top - b.top) < 3 && a.right <= b.left;
                }
                const xs = dds.map(d => Math.round(d.getBoundingClientRect().left - box.left));
                out.push((dl.id || dl.closest('[data-probe]').dataset.probe) + ': ' + [side, xs.length ? xs[0] : -1,
                    Math.round(Math.max(0, ...dts.map(d => d.getBoundingClientRect().width))),
                    dts.length ? getComputedStyle(dts[0]).fontWeight : '-',
                    dl.offsetHeight, xs.every(x => x === xs[0]), Math.round(box.width)].join(' '));
            }
            const group = document.querySelector('#inlinegroup .htmxo-semantic-group');
            if (group) out.push('inlinegroup: ' + Math.round(group.getBoundingClientRect().width));
            const multi = document.querySelectorAll('#multi dd');
            if (multi.length) {
                const a = multi[0].getBoundingClientRect(), b = multi[1].getBoundingClientRect();
                out.push('multi second: ' + (a.left === b.left && b.top >= a.bottom));
            }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = out.join('\n');
            document.body.appendChild(result);
        });
        """))
        long = "Geschossfläche Handel, Gastgewerbe und sonstige Dienstleistungen"
        # The reporter's card (snag dl-default-squee-b12a3a56): its 222 px list
        # had a 16 px value column.
        cards = SemanticGroup(SemanticCard("Bericht",
            SemanticFields(; Inhalt="Daten, Methode, Ergebnisse, Prüfungen, Grenzen", Leistungsbeschreibung="LB 2.2.3")))
        content = h.main(; class="container")(
            h.dl(; id="plain")(h.dt("Fläche"), h.dd("38,2 ha"), h.dt("Einwohner (2025)"), h.dd("4.812"),
                h.dt("Teilverkehrszelle"), h.dd(h.p("Die kleinste räumliche Einheit des Verkehrsmodells."))),
            # `div`-wrapped pairs (valid HTML) share the list's columns.
            h.dl(; id="grouped")(h.div(h.dt("Miete"), h.dd("1.240 €")),
                h.div(h.dt("Verfügbar ab"), h.dd("1. Dezember 2026"))),
            h.dl(; id="multi")(h.dt("Abschnitt"), h.dd("Wirtschaftsabschnitt"), h.dd("Kapitel")),
            # In a narrow column the term column stays within 40% of the list
            # (a long term wraps).
            h.div(; class="narrow")(h.dl(; id="narrow")(h.dt(long), h.dd("12,7"))),
            # A one-word term too: a German compound has no space to wrap at,
            # and it used to keep its full width and squeeze its value.
            h.div(; class="narrow")(h.dl(; id="oneword")(h.dt("Leistungsbeschreibung"), h.dd("LB 2.2.1 bis 2.2.3"))),
            # In a narrow `SemanticGroup` card each term sits above its value;
            # in a wide one they stay side by side.
            h.div(; class="cards-narrow", data_probe="cardnarrow")(Raw(repr("text/html", cards))),
            h.div(; class="cards-wide", data_probe="cardwide")(Raw(repr("text/html", cards))),
            # The cards' containers leave other layouts alone: a list as a
            # flex item keeps its content width, and a group in a parent that
            # sizes to its content keeps at least one card's width.
            h.div(; class="flexrow")(h.dl(; id="flexitem")(h.dt("Quelle"), h.dd("Amt für Statistik Berlin-Brandenburg")), h.p("Nachbar")),
            h.div(; id="inlinegroup", class="inline-holder")(Raw(repr("text/html", cards))),
            # An app's own stylesheet still stacks a list, `div` pairs included.
            h.dl(; id="stacked", class="app-stacked")(h.dt("Quelle"), h.dd("Amt für Statistik")),
            h.dl(; id="stackedgroups", class="app-stacked")(h.div(h.dt("Quelle"), h.dd("Amt für Statistik"))),
            h.dl(; id="hidden", hidden=true)(h.dt("x"), h.dd("y")))
        app_css = h.style(Raw(".narrow { width: 400px; } " *
            ".app-stacked, .app-stacked > div { display: block; } " *
            ".cards-narrow { width: 300px; } .cards-wide { width: 800px; } " *
            ".flexrow { display: flex; gap: 1rem; } .inline-holder { display: inline-block; }"))
        shell(pico) = repr("text/html", htmx(content, driver; assets=:vendor, lang="de",
            pico_version=pico ? HTMXObjects._PICO_VERSION : nothing, htmx_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false, extra_head=(app_css,)))
        page = shell(true)
        # The control is the same page without the definition-list rules: it
        # must show the old layout, or the probe cannot tell the two apart.
        control = replace(page, r"dl:not\(\[hidden\]\) \{.*?:is\(dl, dl > div\) > dd > :last-child \{ margin-bottom: 0; \}"s => "")
        @test control != page
        # One control per new rule, each the page with only that rule removed.
        nowrap = replace(page, " hyphens: auto; overflow-wrap: anywhere;" => "")
        nostack = replace(page, r"@container \(width < 24rem\) \{.*?\n\}"s => "")
        nobasis = replace(page, r"\n\s*contain-intrinsic-inline-size: var\(--htmxo-semantic-group-min, 20rem\);" => "")
        for c in (nowrap, nostack, nobasis)
            @test c != page
        end
        pages = Dict(
            "/" => page, "/nopico" => shell(false), "/control" => control,
            "/nowrap" => nowrap, "/nostack" => nostack, "/nobasis" => nobasis,
            "/vendor/pico.min.css" => read(HTMXObjects._vendor_file(:pico), String),
        )
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => endswith(path, ".css") ? "text/css" : "text/html"], pages[path])
        end
        measure(path) = mktempdir() do profile
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1000,900 --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? Dict{String,Vector{String}}() :
                Dict(String(k) => split(v) for (k, v) in (split(l, ": "; limit=2) for l in split(checks[1], '\n')))
        end
        try
            for path in ("/", "/nopico")
                m = measure(path)
                # "<side> <value x> <widest term> <term weight> <height> <values aligned> <width>"
                for id in ("plain", "grouped", "multi", "narrow", "oneword", "cardwide", "flexitem")
                    @test m[id][1] == "true"
                    @test m[id][4] == "600"
                    @test m[id][6] == "true"
                end
                # The value column starts after the widest term (and the gap).
                @test parse(Int, m["plain"][2]) > parse(Int, m["plain"][3])
                @test parse(Int, m["narrow"][3]) <= 160
                # A one-word term keeps to 40% of its 400 px list, and its value
                # keeps at least half of it.
                @test parse(Int, m["oneword"][3]) <= 160
                @test parse(Int, m["oneword"][2]) <= 200
                @test m["multi second"] == ["true"]
                for id in ("stacked", "stackedgroups", "cardnarrow")
                    @test m[id][1] == "false"
                    @test m[id][2] == "0"
                end
                @test m["cardnarrow"][4] == "600"
                # A flex item is no container, so it keeps its content width; a
                # group in an inline-block keeps at least one 20rem card.
                @test parse(Int, m["flexitem"][7]) > 200
                @test parse(Int, only(m["inlinegroup"])) >= 320
                @test m["hidden"][5] == "0"
            end
            # Without the rules: Pico's own look, terms above values indented 40 px.
            c = measure("/control")
            @test c["plain"][1] == "false"
            @test c["plain"][2] == "40"
            @test c["plain"][4] == "400"
            @test c["hidden"][5] == "0"
            # Each new rule removed on its own brings its failure back: the
            # one-word term takes its full width, the narrow card keeps its
            # columns, and the inline-block group collapses.
            @test parse(Int, measure("/nowrap")["oneword"][3]) > 160
            @test measure("/nostack")["cardnarrow"][1] == "true"
            @test parse(Int, only(measure("/nobasis")["inlinegroup"])) < 100
        finally
            close(server)
        end
    end
end
