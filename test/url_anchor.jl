# The address's `#id` reaches an element an htmx swap inserts after the page
# loaded (`url_anchor_script`): the browser's own scroll runs too early for it.

@testitem "htmx() pages carry the url_anchor runtime, inline, linked and exported" setup=[HTMXOTestImports] tags=[:unit] begin
    html(x) = repr("text/html", x)
    script = html(url_anchor_script())
    @test contains(script, "window.htmxoUrlAnchor = true")
    page = htmx(h.p("x"))
    @test count("window.htmxoUrlAnchor = true", html(page)) == 1
    linked = html(htmx(h.p("x"); assets=:vendor, runtime=:linked))
    @test contains(linked, "src=\"/vendor/htmxo/url_anchor.js?v=")
    @test !contains(linked, "window.htmxoUrlAnchor")
    @test contains(html(static_transform(page, StaticExport())), "window.htmxoUrlAnchor = true")
end

@testitem "a link's #id lands on a tabset that arrives in a fragment, in a real browser" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # The tabset `ts` sits below the fold, as the last part of a fragment
        # the page loads after it has loaded, so the page only grows long
        # enough to bring it to the top once its tab has loaded. Step 0 opens
        # the page without the runtime: the browser alone stays at the top.
        # Step 1 opens the page: it lands on the tabset, whose tab the URL
        # names loads, and keeps it at the top. Step 2 scrolls before the
        # fragment arrives, step 3 after the page reached the tabset and before
        # its tab has loaded: the page stays where the reader took it.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const step = new URLSearchParams(location.search).get('step');
            const checks = [];
            const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
            const sleep = ms => new Promise(r => setTimeout(r, ms));
            const wait = async cond => { for (let n = 0; n < 250 && !cond(); n++) await sleep(20); return cond(); };
            const top = () => document.getElementById('ts').getBoundingClientRect().top;
            const loaded = () => document.getElementById('lazy-zwei');
            const report = async () => {
                await fetch('/report?step=' + step + '&checks=' + encodeURIComponent(checks.join('|')));
            };
            if (step === '2') window.scrollTo(0, 40);
            check('arrived', await wait(() => document.getElementById('ts')));
            check('tab-open', document.querySelector('#ts > nav a.contrast').dataset.tabName === 'zwei');
            if (step === '0') {
                await sleep(500);
                check('browser-stays-at-top', window.scrollY === 0 && top() > innerHeight);
                check('tab-waits', !loaded());
                await report();
                location.href = '/?step=1&tab=zwei#ts';
            } else if (step === '1') {
                check('tab-loads', await wait(loaded));
                await sleep(300);
                check('lands-on-tabset', window.scrollY > 0 && Math.abs(top()) < 2);
                await report();
                location.href = '/?step=2&tab=zwei#ts';
            } else if (step === '2') {
                await sleep(500);
                check('reader-scroll-kept', window.scrollY === 40 && top() > innerHeight);
                check('tab-waits', !loaded());
                await report();
                location.href = '/?step=3&tab=zwei#ts';
            } else {
                check('reached', await wait(() => window.scrollY > 0) && !loaded());
                window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100 }));
                window.scrollTo(0, 100);
                check('tab-loads', await wait(loaded));
                await sleep(300);
                check('reader-takeover-kept', window.scrollY === 100);
                await report();
            }
        });
        """))
        body = h.main(
            h.div(; style="height: 3000px")("above the fold"),
            h.div(; hx_get="/late", hx_trigger="load")("loading"))
        page = repr("text/html", htmx(body; assets=:vendor, extra_head=(driver,),
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing))
        runtime = repr("text/html", url_anchor_script())
        @test contains(page, runtime)
        bare = replace(page, runtime => "")
        late = repr("text/html", h.section(tabset("Eins" => h.p("eins"), "Zwei" => "/lazy/zwei"; id="ts")))
        vendorfiles()
        reports = Channel{Tuple{String,String}}(4)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/bare" && return HTTP.Response(200, ["Content-Type" => "text/html"], bare)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/late"
                # Step 2's fragment arrives after the reader has scrolled.
                contains(HTTP.header(req, "HX-Current-URL", ""), "step=2") && sleep(1.0)
                return HTTP.Response(200, ["Content-Type" => "text/html"], late)
            end
            if path == "/lazy/zwei"
                # The tab's content arrives after the page reached the tabset.
                sleep(contains(HTTP.header(req, "HX-Current-URL", ""), "step=3") ? 1.0 : 0.3)
                return HTTP.Response(200, ["Content-Type" => "text/html"],
                    "<p id=\"lazy-zwei\" style=\"height: 3000px\">zwei</p>")
            end
            if path == "/report"
                q = HTTP.queryparams(uri)
                put!(reports, (q["step"], q["checks"]))
                return HTTP.Response(204)
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        try
            url = "http://127.0.0.1:$port/bare?step=0&tab=zwei#ts"
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --password-store=basic --window-size=1200,800 --user-data-dir=$profile $url`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> Base.n_avail(reports) == 4 || process_exited(process), 90; pollint=0.05) === :ok
                    for (step, n) in (("0", 4), ("1", 4), ("2", 4), ("3", 5))
                        isready(reports) || break
                        got, checks = take!(reports)
                        @test got == step
                        lines = split(checks, '|')
                        @test length(lines) == n
                        for line in lines
                            @test endswith(line, ":true")
                        end
                    end
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        finally
            close(server)
        end
    end
end

@testitem "a link's #id stays on a tabset the page carries while lazy parts load after it, in a real browser" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # The tabset `ts` is part of the page, below a 1,000 px spacer and a
        # part `above` that loads with the page, and the page is too short to
        # bring it to the top until the URL's tab has loaded. The browser
        # keeps the tabset in view only until the page's `load` event, so a
        # part that arrives later moves the page on without it. Steps 0 and 1
        # load the tab's panel after the page (the page grows below the
        # tabset): without the runtime the tabset stays short of the top, with
        # it the page lands on it. Steps 2 and 3 load `above` after the page
        # (the tabset is pushed down): without the runtime it leaves the
        # window, with it the page scrolls as far towards it as it can. In
        # step 4 the reader scrolls before `above` arrives, and the page stays
        # where the reader took it.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const step = new URLSearchParams(location.search).get('step');
            const checks = [];
            const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
            const sleep = ms => new Promise(r => setTimeout(r, ms));
            const wait = async cond => { for (let n = 0; n < 250 && !cond(); n++) await sleep(20); return cond(); };
            const top = () => document.getElementById('ts').getBoundingClientRect().top;
            const bottom = () => document.documentElement.scrollHeight - innerHeight;
            const report = async () => {
                await fetch('/report?step=' + step + '&checks=' + encodeURIComponent(checks.join('|')));
            };
            // In step 4 the tabset is out of view, so its lazy tab waits.
            const parts = step === '4' ? ['above-done'] : ['above-done', 'lazy-zwei'];
            if (step === '4') {
                window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100 }));
                window.scrollTo(0, 60);
            }
            check('loaded', await wait(() => parts.every(id => document.getElementById(id))));
            await sleep(300);
            if (step === '0') {
                check('browser-stops-short', top() > 2 && top() < innerHeight);
                await report();
                location.href = '/?step=1&tab=zwei#ts';
            } else if (step === '1') {
                check('lands-on-tabset', Math.abs(top()) < 2);
                await report();
                location.href = '/bare?step=2&tab=zwei#ts';
            } else if (step === '2') {
                check('browser-loses-tabset', top() > innerHeight);
                await report();
                location.href = '/?step=3&tab=zwei#ts';
            } else if (step === '3') {
                check('keeps-tabset-in-view', top() > 0 && top() < innerHeight && Math.abs(scrollY - bottom()) < 2);
                await report();
                location.href = '/?step=4&tab=zwei#ts';
            } else {
                check('reader-scroll-kept', window.scrollY === 60 && top() > innerHeight);
                await report();
            }
        });
        """))
        body = h.main(
            h.div(; style="height: 1000px")("above the fold"),
            h.div(; id="above", hx_get="/above", hx_trigger="load")("loading"),
            h.section(tabset("Eins" => h.p("eins"), "Zwei" => "/lazy/zwei"; id="ts")))
        page = repr("text/html", htmx(body; assets=:vendor, extra_head=(driver,),
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing))
        runtime = repr("text/html", url_anchor_script())
        @test contains(page, runtime)
        bare = replace(page, runtime => "")
        function step(req)
            m = match(r"step=(\d)", HTTP.header(req, "HX-Current-URL", ""))
            m === nothing ? "" : m.captures[1]
        end
        vendorfiles()
        reports = Channel{Tuple{String,String}}(5)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/bare" && return HTTP.Response(200, ["Content-Type" => "text/html"], bare)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/above"
                # Steps 2–4: the part above the tabset arrives after the page,
                # and pushes the tabset down.
                late = step(req) in ("2", "3", "4")
                late && sleep(1.0)
                return HTTP.Response(200, ["Content-Type" => "text/html"],
                    "<div id=\"above-done\" style=\"height: $(late ? 2000 : 20)px\">above</div>")
            end
            if path == "/lazy/zwei"
                # Steps 0 and 1: the tab's panel arrives after the page, and
                # makes it long enough to bring the tabset to the top.
                late = step(req) in ("0", "1")
                late && sleep(1.0)
                return HTTP.Response(200, ["Content-Type" => "text/html"],
                    "<p id=\"lazy-zwei\" style=\"height: $(late ? 3000 : 50)px\">zwei</p>")
            end
            if path == "/report"
                q = HTTP.queryparams(uri)
                put!(reports, (q["step"], q["checks"]))
                return HTTP.Response(204)
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        try
            url = "http://127.0.0.1:$port/bare?step=0&tab=zwei#ts"
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --password-store=basic --window-size=1200,800 --user-data-dir=$profile $url`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> Base.n_avail(reports) == 5 || process_exited(process), 90; pollint=0.05) === :ok
                    for want in ("0", "1", "2", "3", "4")
                        isready(reports) || break
                        got, checks = take!(reports)
                        @test got == want
                        lines = split(checks, '|')
                        @test length(lines) == 2
                        for line in lines
                            @test endswith(line, ":true")
                        end
                    end
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        finally
            close(server)
        end
    end
end
