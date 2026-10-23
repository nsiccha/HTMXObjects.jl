# `tabset_styles` draws a tabset as an underline tab bar: a thin rule under the
# tabs, the open tab in the text color with an accent underline on that rule,
# and an unframed panel.

@testitem "tabset_styles draws an underline tab bar and beats Pico's nav spacing" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", tabset_styles())
    # Unlayered: Pico spaces `nav li` and `nav a` unlayered, and a layered
    # rule loses to those whatever its specificity, which left the open tab
    # floating above its rule.
    @test !occursin("@layer", css)
    @test occursin(r"\.tabset > nav \{[^}]*box-shadow: inset 0 -1px 0 var\(--htmxo-tab-rule,"s, css)
    @test occursin(r"\.tabset > nav > ul > li > a\.contrast \{[^}]*border-bottom-color: var\(--htmxo-accent\);"s, css)
    @test occursin(r"\.tabset > \.tab-panel \{\s*padding: 1rem 0 0;\s*\}"s, css)
    @test !occursin("--htmxo-border", css)
    # Pico's nav rules match these with equal specificity in places, so the
    # tabset rules follow Pico's stylesheet in the shell.
    page = repr("text/html", htmx(tabset("A" => h.p("a"), "B" => h.p("b")); pico_version="2"))
    pico = findfirst("pico.min.css", page)
    tabs = findfirst(".tabset > nav > ul > li > a.contrast", page)
    @test !isnothing(pico) && !isnothing(tabs) && first(pico) < first(tabs)
end

@testitem "a tabset's open tab underlines the rule in Chrome, with and without Pico" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # One line of `name=value` checks: the open tab's underline reaches the
        # nav's bottom edge (where the rule is drawn), Pico's nav spacing is
        # gone, the open and the other tab carry the accent and no underline,
        # the open tab reads in the text color, and the panel has no frame.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const nav = document.querySelector('#ts > nav');
            const open = nav.querySelector('a.contrast'), other = nav.querySelector('a.secondary');
            const css = e => getComputedStyle(e);
            const probe = document.createElement('span');
            probe.style.color = 'var(--htmxo-accent)'; document.body.appendChild(probe);
            const accent = css(probe).color;
            const panel = document.querySelector('#ts > .tab-panel');
            const out = [
                'flush=' + (Math.abs(open.getBoundingClientRect().bottom - nav.getBoundingClientRect().bottom) < 0.5),
                'li-padding=' + css(open.parentElement).paddingTop + '/' + css(open.parentElement).paddingLeft,
                'ul-margin=' + css(nav.querySelector('ul')).marginLeft,
                'row=' + (other.getBoundingClientRect().top === open.getBoundingClientRect().top),
                'bullets=' + css(nav.querySelector('ul')).listStyleType,
                'underline=' + css(open).borderBottomWidth + ':' + (css(open).borderBottomColor === accent),
                'other=' + css(other).borderBottomColor,
                'text=' + (css(open).color === css(document.querySelector('#body')).color),
                'muted=' + (css(other).color !== css(open).color),
                'panel=' + css(panel).borderTopWidth + '/' + css(panel).borderLeftWidth,
                'decoration=' + css(open).textDecorationLine,
            ];
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = out.join(' ');
            document.body.appendChild(result);
        });
        """))
        content = h.main(; class="container")(h.p("Body text."; id="body"),
            tabset("Übersicht" => h.p("one"), "Messwerte" => h.p("two"), "Güte (K-40)" => h.p("three"); id="ts"))
        shell(pico) = repr("text/html", htmx(content, driver; assets=:vendor, pico_version=pico,
            htmx_version=nothing, hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        pico = shell(HTMXObjects._PICO_VERSION)
        pages = Dict(
            "/light" => pico,
            "/dark" => replace(pico, "<html" => "<html data-theme=\"dark\""; count=1),
            "/plain" => shell(nothing),
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
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1400,900 --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? nothing : checks[1]
        end
        try
            expected = "flush=true li-padding=0px/0px ul-margin=0px row=true bullets=none " *
                "underline=2px:true other=rgba(0, 0, 0, 0) text=true muted=true panel=0px/0px decoration=none"
            @test measure("/light") == expected
            @test measure("/dark") == expected
            @test measure("/plain") == expected
        finally
            close(server)
        end
    end
end
