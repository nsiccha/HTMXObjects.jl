# A tabset reads as tabs to assistive technology and works from the keyboard,
# and neither changes what opens a lazy tab or what the URL says.

# Real key presses and mouse clicks, through the DevTools protocol: a script's
# KeyboardEvent moves no focus and clicks no link, so only these reach the page's
# Tab order and a link's Enter.
@testmodule TabsetBrowser begin
    using HTTP
    export Browser, evaluate, press, mouse_click, wait_for, open_page, focused

    struct Browser
        ws::Any
        next::Ref{Int}
    end
    function call(b::Browser, method, params="{}")
        id = b.next[] += 1
        HTTP.WebSockets.send(b.ws, "{\"id\":$id,\"method\":\"$method\",\"params\":$params}")
        while true
            reply = String(HTTP.WebSockets.receive(b.ws))
            startswith(reply, "{\"id\":$id,") || continue
            contains(reply, "\"error\":") && error("$method: $reply")
            return reply
        end
    end
    # The scripts in the item answer with plain text: no quotes, no backslashes.
    function evaluate(b::Browser, js)
        source = replace(js, "\\" => "\\\\", "\"" => "\\\"", "\n" => " ")
        reply = call(b, "Runtime.evaluate", "{\"expression\":\"$source\",\"returnByValue\":true,\"awaitPromise\":true}")
        contains(reply, "\"exceptionDetails\"") && error("$js: $reply")
        m = match(r"\"value\":\"([^\"]*)\"", reply)
        isnothing(m) ? "" : String(m[1])
    end
    const KEYS = Dict("Tab" => (9, "Tab", "\\t"), "Enter" => (13, "Enter", "\\r"), " " => (32, "Space", " "),
        "ArrowLeft" => (37, "ArrowLeft", ""), "ArrowRight" => (39, "ArrowRight", ""),
        "Home" => (36, "Home", ""), "End" => (35, "End", ""))
    # `modifiers`: 1 Alt, 2 Ctrl, 4 Meta, 8 Shift.
    function press(b::Browser, key; modifiers=0)
        code, name, text = KEYS[key]
        common = "\"key\":\"$key\",\"code\":\"$name\",\"windowsVirtualKeyCode\":$code,\"modifiers\":$modifiers"
        call(b, "Input.dispatchKeyEvent", "{\"type\":\"$(isempty(text) ? "rawKeyDown" : "keyDown")\",$common" *
            (isempty(text) ? "" : ",\"text\":\"$text\"") * "}")
        call(b, "Input.dispatchKeyEvent", "{\"type\":\"keyUp\",$common}")
        nothing
    end
    function mouse_click(b::Browser, x, y)
        for type in ("mousePressed", "mouseReleased")
            call(b, "Input.dispatchMouseEvent", "{\"type\":\"$type\",\"x\":$x,\"y\":$y,\"button\":\"left\",\"clickCount\":1}")
        end
        nothing
    end
    wait_for(b, js) = timedwait(() -> evaluate(b, "String(Boolean($js))") == "true", 15; pollint=0.05) === :ok
    function open_page(b::Browser, url)
        call(b, "Page.navigate", "{\"url\":\"$url\"}")
        # The new document, loaded: hyperscript processes the page when it is ready.
        sleep(0.1)
        wait_for(b, "document.readyState === 'complete' && window._hyperscript")
    end
    focused(b) = evaluate(b, "document.activeElement.id")
end

@testitem "a tabset's markup says what is selected and which panel each tab controls" setup=[HTMXOTestImports] tags=[:unit] begin
    html(x) = repr("text/html", x)
    tag(s, id) = match(Regex("<[a-z]+ [^>]*\\bid=\"$id\"[^>]*>"), s).match
    s = html(tabset("Eins" => h.p("1"), "Zwei" => "/zwei", "Drei" => h.p("3"); id="ts", label="Auswertungen", active=2))
    @test contains(s, "<nav role=\"none\">")
    @test contains(s, "<ul role=\"tablist\" aria-label=\"Auswertungen\">")
    @test length(collect(eachmatch(r"<li role=\"presentation\">", s))) == 3
    for (i, selected) in ((1, false), (2, true), (3, false))
        link = tag(s, "ts-tablink-$i")
        @test startswith(link, "<a ")
        @test contains(link, "role=\"tab\"")
        @test contains(link, "aria-selected=\"$selected\"")
        @test contains(link, "aria-controls=\"ts-tab-$i\"")
        @test contains(link, "tabindex=\"$(selected ? 0 : -1)\"")
        panel = tag(s, "ts-tab-$i")
        @test startswith(panel, "<div ")
        @test contains(panel, "role=\"tabpanel\"")
        @test contains(panel, "aria-labelledby=\"ts-tablink-$i\"")
        @test contains(panel, "tabindex=\"0\"")
    end
    # The tab bar has no name of its own until it is given one.
    plain = html(tabset("A" => h.p("a"), "B" => h.p("b"); id="t2"))
    @test contains(plain, "<ul role=\"tablist\">") && !contains(plain, "aria-label=")
    # Refused: `aria-label` is text; a node would render as nonsense.
    @test_throws TypeError tabset("A" => h.p("a"); label=h.span("x"))
    # A tabset kept out of the URL is the same to assistive technology, and
    # names nothing.
    off = html(tabset("A" => h.p("a"), "B" => h.p("b"); id="t3", url_param=nothing))
    @test contains(off, "role=\"tablist\"") && contains(off, "aria-controls=\"t3-tab-2\"")
    @test !contains(off, "data-tab-")
    @test endswith(off, "(document.currentScript.parentElement)</script></div>")
    # Markdown still writes only the labels and contents.
    md = repr("text/markdown", tabset("A" => h.p("a"), "B" => h.p("b"); label="L"))
    @test !contains(md, "role") && !contains(md, "aria") && !contains(md, "L\n")
    # A static export keeps all of it.
    for controls in (:disable, :remove)
        exported = html(static_transform(htmx(tabset("A" => h.p("a"), "B" => h.p("b"); id="t4")), StaticExport(; controls)))
        @test contains(exported, "aria-controls=\"t4-tab-2\"") && contains(exported, "aria-labelledby=\"t4-tablink-2\"")
    end
end

@testitem "a tabset works from the keyboard, in a real browser" setup=[HTMXOTestImports, TabsetBrowser] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # Every tab of the tabset agrees with what the page shows: exactly one
        # selected, the selected one's panel the only one visible, each tab and
        # panel pointing at each other. Answers "ok" or what is wrong.
        CONSISTENT = raw"""
        (id => {
            const ts = document.getElementById(id);
            const tabs = Array.from(ts.querySelectorAll(':scope > nav [role=tab]'));
            const wrong = [];
            for (const tab of tabs) {
                const panel = document.getElementById(tab.getAttribute('aria-controls'));
                const selected = tab.getAttribute('aria-selected') === 'true';
                const seen = getComputedStyle(panel).display !== 'none';
                if (panel.getAttribute('aria-labelledby') !== tab.id) wrong.push('link:' + tab.id);
                if (panel.parentElement !== ts) wrong.push('parent:' + tab.id);
                if (selected !== seen) wrong.push('shown:' + tab.id + ':' + selected + ':' + seen);
                if (selected !== tab.classList.contains('contrast')) wrong.push('class:' + tab.id);
            }
            if (tabs.filter(t => t.getAttribute('aria-selected') === 'true').length !== 1) wrong.push('count');
            return wrong.join(',') || 'ok';
        })
        """
        consistent(b, id) = evaluate(b, "$CONSISTENT('$id')")
        selected(b, id) = evaluate(b, "document.querySelector('#$id > nav [aria-selected=true]').id")
        stops(b, id) = evaluate(b, "Array.from(document.querySelectorAll('#$id > nav [role=tab]')).map(t => t.getAttribute('tabindex')).join(',')")

        body = h.main(; id="main")(
            h.button("before"; id="before"),
            tabset("Eins" => h.p("eins"; id="eins-text"), "Zwei" => "/lazy/zwei", "Drei" => h.button("in drei"; id="in-drei");
                id="ts", label="Auswertungen"),
            h.button("after"; id="after"),
            tabset("Außen" => tabset("Innen 1" => h.p("i1"), "Innen 2" => h.p("i2"), "Innen 3" => h.p("i3"); id="inner", url_param=nothing),
                   "Anders" => h.p("o2"), "Noch" => h.p("o3"); id="outer", url_param=nothing),
            h.div(; id="late", hx_get="/fragment", hx_trigger="load", hx_swap="innerHTML"),
            h.div(; style="height: 3000px"))
        fragment = repr("text/html", tabset("F1" => h.p("f1"), "F2" => h.p("f2"); id="frag", url_param="frag"))
        shell(; kw...) = htmx(body; assets=:vendor, feedback=false, compose=false, thread=false,
            treebars_assets=false, preload_version=nothing, kw...)
        page = repr("text/html", shell(; pico_version=HTMXObjects._PICO_VERSION))
        plain = repr("text/html", shell())
        exported = repr("text/html", static_transform(shell(; runtime=:linked), StaticExport()))
        # A page with its own head, which has not added `tabset_script`.
        script = repr("text/html", tabset_script())
        scriptless_page = replace(plain, script => ""; count=1)
        @test scriptless_page != plain
        vendorfiles()
        lazy_loads = Threads.Atomic{Int}(0)
        pages = Dict("/" => page, "/plain" => plain, "/export" => exported, "/scriptless" => scriptless_page)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"], pages[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/fragment" && return HTTP.Response(200, ["Content-Type" => "text/html"], fragment)
            if path == "/lazy/zwei"
                Threads.atomic_add!(lazy_loads, 1)
                return HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"lazy-zwei\">zwei</p>")
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        base = "http://127.0.0.1:$port"
        mktempdir() do profile
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1200,900 --remote-debugging-port=0 '--remote-allow-origins=*' --user-data-dir=$profile about:blank`
            process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
            try
                active = joinpath(profile, "DevToolsActivePort")
                @test timedwait(() -> isfile(active) && countlines(active) >= 2, 30; pollint=0.05) === :ok
                debug_port = strip(first(readlines(active)))
                targets = String(HTTP.get("http://127.0.0.1:$debug_port/json/list").body)
                target = match(r"\"webSocketDebuggerUrl\"\s*:\s*\"(ws://[^\"]*/page/[^\"]*)\"", targets)[1]
                HTTP.WebSockets.open(target; suppress_close_error=true) do ws
                    b = Browser(ws, Ref(0))
                    @test open_page(b, "$base/")

                    # Tab reaches the open tab, not the first or every tab.
                    @test stops(b, "ts") == "0,-1,-1"
                    evaluate(b, "document.getElementById('before').focus(); ''")
                    press(b, "Tab")
                    @test focused(b) == "ts-tablink-1"

                    # The arrows move the focus and open nothing: no fetch, no URL.
                    press(b, "ArrowRight")
                    @test focused(b) == "ts-tablink-2"
                    @test selected(b, "ts") == "ts-tablink-1"
                    sleep(0.3)
                    @test lazy_loads[] == 0
                    @test evaluate(b, "location.search") == ""
                    @test consistent(b, "ts") == "ok"

                    # Enter opens a lazy tab: its one fetch, its name in the URL.
                    press(b, "Enter")
                    @test wait_for(b, "document.getElementById('lazy-zwei')")
                    @test selected(b, "ts") == "ts-tablink-2"
                    @test stops(b, "ts") == "-1,0,-1"
                    @test lazy_loads[] == 1
                    @test evaluate(b, "location.search") == "?tab=zwei"
                    @test focused(b) == "ts-tablink-2"
                    @test consistent(b, "ts") == "ok"

                    # Space opens too, and does not scroll the page.
                    press(b, "ArrowRight")
                    @test focused(b) == "ts-tablink-3"
                    press(b, " ")
                    @test selected(b, "ts") == "ts-tablink-3"
                    @test evaluate(b, "String(scrollY)") == "0"
                    @test evaluate(b, "location.search") == "?tab=drei"
                    @test consistent(b, "ts") == "ok"

                    # They wrap, and Home and End go to the ends.
                    press(b, "ArrowRight")
                    @test focused(b) == "ts-tablink-1"
                    press(b, "ArrowLeft")
                    @test focused(b) == "ts-tablink-3"
                    press(b, "Home")
                    @test focused(b) == "ts-tablink-1"
                    press(b, "End")
                    @test focused(b) == "ts-tablink-3"
                    @test selected(b, "ts") == "ts-tablink-3"

                    # A key held with a modifier is the browser's: Alt+Left is
                    # Back, Alt+Right Forward (with nowhere to go here).
                    evaluate(b, "window.addEventListener('keydown', e => { window.lastKey = e.key + ':' + e.defaultPrevented; }); ''")
                    press(b, "ArrowRight"; modifiers=1)
                    @test evaluate(b, "window.lastKey") == "ArrowRight:false"
                    @test focused(b) == "ts-tablink-3"
                    @test open_page(b, "$base/")

                    # Tab leaves the tab bar for the open panel and what is in
                    # it, and Shift+Tab comes back to the open tab.
                    evaluate(b, "document.getElementById('ts-tablink-3').click(); document.getElementById('ts-tablink-3').focus(); ''")
                    @test stops(b, "ts") == "-1,-1,0"
                    press(b, "Tab")
                    @test focused(b) == "ts-tab-3"
                    press(b, "Tab")
                    @test focused(b) == "in-drei"
                    press(b, "Tab"; modifiers=8)
                    press(b, "Tab"; modifiers=8)
                    @test focused(b) == "ts-tablink-3"

                    # A focus ring shows where the keyboard is, on a tab and on
                    # a panel; a mouse click on a panel's text shows none.
                    for path in ("/", "/plain")
                        @test open_page(b, base * path)
                        for id in ("ts-tablink-1", "ts-tab-1")
                            evaluate(b, "document.getElementById('before').focus(); ''")
                            press(b, "Tab")
                            id == "ts-tab-1" && press(b, "Tab")
                            @test focused(b) == id
                            @test evaluate(b, "(a => { const s = getComputedStyle(a); " *
                                "return String(a.matches(':focus-visible') && (s.outlineStyle !== 'none' || s.boxShadow !== 'none')); })(document.activeElement)") == "true"
                        end
                        box = evaluate(b, "(r => r.left + 2 + ',' + (r.top + r.height / 2))(document.getElementById('eins-text').getBoundingClientRect())")
                        x, y = split(box, ',')
                        # From elsewhere: a click on what the keyboard already
                        # focused leaves its ring, as any browser does.
                        evaluate(b, "document.activeElement.blur(); ''")
                        mouse_click(b, x, y)
                        @test evaluate(b, "document.activeElement.id") == "ts-tab-1"
                        @test evaluate(b, "String(document.activeElement.matches(':focus-visible'))") == "false"
                    end

                    # The URL's tab says so from the start, and a click keeps it so.
                    @test open_page(b, "$base/?tab=drei")
                    @test selected(b, "ts") == "ts-tablink-3"
                    @test stops(b, "ts") == "-1,-1,0"
                    @test consistent(b, "ts") == "ok"
                    evaluate(b, "document.getElementById('ts-tablink-1').click(); ''")
                    @test selected(b, "ts") == "ts-tablink-1"
                    @test stops(b, "ts") == "0,-1,-1"
                    @test consistent(b, "ts") == "ok"

                    # A tabset's panels are its own: opening a tab of the outer
                    # one leaves the inner one's open tab and panel as they were.
                    evaluate(b, "document.getElementById('inner-tablink-2').click(); ''")
                    @test consistent(b, "inner") == "ok"
                    evaluate(b, "document.getElementById('outer-tablink-2').click(); ''")
                    @test consistent(b, "outer") == "ok"
                    evaluate(b, "document.getElementById('outer-tablink-1').click(); ''")
                    @test consistent(b, "outer") == "ok"
                    @test selected(b, "inner") == "inner-tablink-2"
                    @test consistent(b, "inner") == "ok"

                    # A tabset that arrives in a fragment works the same.
                    @test wait_for(b, "document.getElementById('frag-tablink-1')")
                    sleep(0.3)  # htmx settles it, and hyperscript processes it on htmx:load.
                    evaluate(b, "document.getElementById('frag-tablink-1').focus(); ''")
                    press(b, "ArrowRight")
                    @test focused(b) == "frag-tablink-2"
                    press(b, "Enter")
                    @test selected(b, "frag") == "frag-tablink-2"
                    @test consistent(b, "frag") == "ok"

                    # So does a static export.
                    @test open_page(b, "$base/export")
                    evaluate(b, "document.getElementById('ts-tablink-1').focus(); ''")
                    press(b, "End")
                    @test focused(b) == "ts-tablink-3"
                    press(b, "Enter")
                    @test selected(b, "ts") == "ts-tablink-3"
                    @test stops(b, "ts") == "-1,-1,0"
                    @test consistent(b, "ts") == "ok"

                    # Without the script nothing moves the focus along the tabs,
                    # so every tab is a stop in the page's Tab order and opens
                    # with Enter; the state still follows.
                    @test open_page(b, "$base/scriptless")
                    @test evaluate(b, "typeof window.htmxoTabset") == "undefined"
                    @test stops(b, "ts") == ",,"
                    @test stops(b, "outer") == ",,"
                    evaluate(b, "document.getElementById('before').focus(); ''")
                    press(b, "Tab")
                    @test focused(b) == "ts-tablink-1"
                    press(b, "Tab")
                    @test focused(b) == "ts-tablink-2"
                    press(b, "Tab")
                    @test focused(b) == "ts-tablink-3"
                    press(b, "Enter")
                    @test selected(b, "ts") == "ts-tablink-3"
                    @test stops(b, "ts") == ",,"
                    @test consistent(b, "ts") == "ok"
                    # Space is the page's here, which is what the runtime stops above.
                    press(b, " ")
                    @test wait_for(b, "scrollY > 0")
                end
            finally
                kill(process)
                timedwait(() -> process_exited(process), 5; pollint=0.05) === :ok || kill(process, Base.SIGKILL)
            end
        end
        close(server)
    end
end
