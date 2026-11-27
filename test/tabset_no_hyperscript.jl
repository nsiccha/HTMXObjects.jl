# A tabset opens its tabs by itself: `tabset_script` shows the clicked tab's
# panel, and a page without that script falls back to the call each tabset
# carries. Neither needs hyperscript or htmx, so a page that leaves one out
# (`htmx(...; hyperscript_version=nothing)`, a static export of one) has working
# tabs (snag `tabset-dead-with-de026b7f`: such a page recorded the click in its
# address and showed the first panel forever).

@testitem "a tabset's markup carries no hyperscript" setup=[HTMXOTestImports] tags=[:unit] begin
    html(x) = repr("text/html", x)
    for kwargs in ((;), (; url_param=nothing), (; url_param="model", label="Quellen", names=["a", "b"]))
        s = html(tabset("A" => h.p("a"), "B" => "/b"; id="ts", kwargs...))
        # No `_` attribute anywhere: the tab links carried their switch in one.
        @test !contains(s, " _=")
        @test !contains(s, "halt the event")
        # What says which panel a tab opens, for the script and the fallback.
        @test contains(s, "data-panel=\"tab-2\" ") && contains(s, "role=\"tab\"")
    end
    # The script and the fallback run one text, so they cannot drift apart.
    show = HTMXObjects._TABSET_SHOW
    @test contains(html(tabset_script()), "const show = $show;")
    @test contains(HTMXObjects._TABSET_INSERTED, "($show)(ts, a);")
    @test contains(html(tabset("A" => h.p("a"); id="t1")), HTMXObjects._TABSET_INSERTED)
    # A page that leaves out hyperscript, or htmx too, still carries the script.
    for shell in (htmx(tabset("A" => h.p("a"), "B" => h.p("b")); hyperscript_version=nothing),
                  htmx(tabset("A" => h.p("a"), "B" => h.p("b")); htmx_version=nothing, hyperscript_version=nothing))
        page = html(shell)
        @test !contains(page, "hyperscript.org@")
        @test contains(page, "window.htmxoTabset = ")
    end
end

@testitem "a tabset opens its tabs without hyperscript, in a real browser" setup=[HTMXOTestImports, TabsetBrowser] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # As `test/tabset_a11y.jl`: every tab agrees with what the page shows.
        CONSISTENT = raw"""
        (id => {
            const ts = document.getElementById(id);
            const tabs = Array.from(ts.querySelectorAll(':scope > nav [role=tab]'));
            const wrong = [];
            for (const tab of tabs) {
                const panel = document.getElementById(tab.getAttribute('aria-controls'));
                const selected = tab.getAttribute('aria-selected') === 'true';
                const seen = getComputedStyle(panel).display !== 'none';
                if (selected !== seen) wrong.push('shown:' + tab.id + ':' + selected + ':' + seen);
                if (selected !== tab.classList.contains('contrast')) wrong.push('class:' + tab.id);
                if (selected === tab.classList.contains('secondary')) wrong.push('other:' + tab.id);
            }
            if (tabs.filter(t => t.getAttribute('aria-selected') === 'true').length !== 1) wrong.push('count');
            return wrong.join(',') || 'ok';
        })
        """
        consistent(b, id) = evaluate(b, "$CONSISTENT('$id')")
        selected(b, id) = evaluate(b, "document.querySelector('#$id > nav [aria-selected=true]').id")
        # A real click in the middle of the element, as a reader's.
        function click(b, id)
            box = evaluate(b, "(r => (r.left + r.width / 2) + ',' + (r.top + r.height / 2))(document.getElementById('$id').getBoundingClientRect())")
            x, y = split(box, ',')
            mouse_click(b, x, y)
        end

        # What sees a tab click that travels up the page: a click handler
        # around a tabset, and one on the document.
        probe = h.script(Raw("""
        window.seen = {wrapper: 0, document: 0};
        document.addEventListener('click', e => {
            if (e.target.closest && e.target.closest('[role=tab]')) window.seen.document++;
        });
        """))
        eager = (
            h.div(; id="wrapper", onclick="window.seen.wrapper++")(
                tabset("Eins" => h.p("eins"; id="eins-text"), "Zwei" => h.p("zwei"; id="zwei-text");
                    id="ts", url_param="model", label="Quellen")),
            tabset("Außen" => tabset("Innen 1" => h.p("i1"), "Innen 2" => h.p("i2"); id="inner", url_param=nothing),
                   "Anders" => h.p("o2"); id="outer", url_param=nothing))
        lazy = tabset("A" => h.p("a"), "B" => "/lazy/b"; id="lz", url_param="lz")
        shell(body...; kw...) = htmx(h.main(body...); assets=:vendor, extra_head=(probe,), feedback=false,
            compose=false, thread=false, treebars_assets=false, preload_version=nothing,
            hyperscript_version=nothing, kw...)
        nohs = repr("text/html", shell(eager..., lazy))
        # The reported page: a linked runtime, exported with its controls disabled.
        exported = repr("text/html", static_transform(shell(eager...; runtime=:linked),
            StaticExport(; controls=:disable, runtime=:linked)))
        bare = repr("text/html", shell(eager...; htmx_version=nothing))
        # A page with its own head, which has not added `tabset_script`.
        scriptless = replace(repr("text/html", shell(eager...)), repr("text/html", tabset_script()) => ""; count=1)
        for page in (nohs, exported, bare, scriptless)
            @test !contains(page, "_hyperscript.min.js")
        end
        @test contains(nohs, "window.htmxoTabset = ") && contains(nohs, "htmx.min.js")
        @test contains(exported, "htmxo/tabset_script.js") && !contains(exported, "window.htmxoTabset = ")
        @test contains(bare, "window.htmxoTabset = ") && !contains(bare, "htmx.min.js")
        @test !contains(scriptless, "window.htmxoTabset = ")
        vendorfiles()
        lazy_loads = Threads.Atomic{Int}(0)
        pages = Dict("/" => nohs, "/export" => exported, "/bare" => bare, "/scriptless" => scriptless)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"], pages[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/lazy/b"
                Threads.atomic_add!(lazy_loads, 1)
                return HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"lazy-b\">b</p>")
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        base = "http://127.0.0.1:$port"
        try
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
                        # (page, whether `tabset_script` is on it)
                        for (path, scripted) in (("/", true), ("/export", true), ("/bare", true), ("/scriptless", false))
                            @test open_page(b, base * path; ready="true")
                            @test evaluate(b, "typeof window._hyperscript") == "undefined"
                            @test evaluate(b, "typeof window.htmxoTabset") == (scripted ? "function" : "undefined")
                            @test selected(b, "ts") == "ts-tablink-1"
                            @test consistent(b, "ts") == "ok"

                            # The click opens the tab: its panel shows, the
                            # other hides, and the tabs say which is selected.
                            click(b, "ts-tablink-2")
                            @test selected(b, "ts") == "ts-tablink-2"
                            @test consistent(b, "ts") == "ok"
                            @test evaluate(b, "getComputedStyle(document.getElementById('zwei-text')).display") == "block"
                            @test evaluate(b, "String(document.getElementById('eins-text').offsetParent === null)") == "true"
                            # A tab is a link to `#`, which is not followed, and
                            # the script records the tab's name.
                            @test evaluate(b, "location.hash + '|' + String(location.href.endsWith('#'))") == "|false"
                            @test evaluate(b, "location.search") == (scripted ? "?model=zwei" : "")
                            # Back to the first tab.
                            click(b, "ts-tablink-1")
                            @test selected(b, "ts") == "ts-tablink-1"
                            @test consistent(b, "ts") == "ok"
                            @test evaluate(b, "location.search") == (scripted ? "?model=eins" : "")

                            # A tabset's panels are its own.
                            click(b, "inner-tablink-2")
                            @test selected(b, "inner") == "inner-tablink-2"
                            @test selected(b, "outer") == "outer-tablink-1"
                            @test consistent(b, "inner") == "ok" && consistent(b, "outer") == "ok"
                            click(b, "outer-tablink-2")
                            @test selected(b, "outer") == "outer-tablink-2"
                            @test consistent(b, "outer") == "ok"
                            click(b, "outer-tablink-1")
                            @test selected(b, "inner") == "inner-tablink-2"
                            @test consistent(b, "inner") == "ok" && consistent(b, "outer") == "ok"

                            # Nothing around a tabset takes a tab click for its own.
                            @test evaluate(b, "window.seen.wrapper + ',' + window.seen.document") == "0,0"
                            # A click beside the tabs does travel up: the probes work.
                            click(b, "eins-text")
                            @test evaluate(b, "String(window.seen.wrapper)") == "1"
                        end

                        # A page opened with the tab in its address shows it,
                        # exported or not.
                        for path in ("/", "/export", "/bare")
                            @test open_page(b, "$base$path?model=zwei"; ready="true")
                            @test selected(b, "ts") == "ts-tablink-2"
                            @test consistent(b, "ts") == "ok"
                        end

                        # htmx alone fetches a lazy tab, once, on its first click.
                        @test open_page(b, base * "/"; ready="window.htmx")
                        @test lazy_loads[] == 0
                        click(b, "lz-tablink-2")
                        @test wait_for(b, "document.getElementById('lazy-b')")
                        @test selected(b, "lz") == "lz-tablink-2"
                        @test consistent(b, "lz") == "ok"
                        click(b, "lz-tablink-1")
                        click(b, "lz-tablink-2")
                        @test selected(b, "lz") == "lz-tablink-2"
                        sleep(0.3)
                        @test lazy_loads[] == 1
                        # Space opens the focused tab, through the same click.
                        evaluate(b, "document.getElementById('lz-tablink-2').focus(); ''")
                        press(b, "ArrowLeft")
                        @test focused(b) == "lz-tablink-1"
                        press(b, " ")
                        @test selected(b, "lz") == "lz-tablink-1"
                        @test consistent(b, "lz") == "ok"
                    end
                finally
                    kill(process)
                    timedwait(() -> process_exited(process), 5; pollint=0.05) === :ok || kill(process, Base.SIGKILL)
                end
            end
        finally
            close(server)
        end
    end
end
