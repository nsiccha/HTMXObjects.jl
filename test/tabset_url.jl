# `tabset` keeps its open tab in the page URL: a tab click records the tab's
# name under the tabset's parameter, and a page opened with it shows that tab.

@testitem "tabset names its tabs and its URL parameter" setup=[HTMXOTestImports] tags=[:unit] begin
    html(x) = repr("text/html", x)
    names(s) = [m.captures[1] for m in eachmatch(r"data-tab-name=\"([^\"]*)\"", s)]
    s = html(tabset("Voralarme" => h.p("a"), "Störungen" => "/stoerungen",
        "Güte der Messungen (K-40)" => "/guete", "Cs-137" => h.p("c"); id="ts"))
    @test contains(s, "<div id=\"ts\" class=\"tabset\" data-tab-param=\"tab\">")
    @test names(s) == ["voralarme", "stoerungen", "guete-der-messungen-k-40", "cs-137"]
    # The call that shows the URL's tab is the tabset's last child, so it runs
    # once the tabset is in the document and before htmx processes it.
    @test endswith(s, "(document.currentScript.parentElement)</script></div>")
    # Markdown has no tab bar and no script: each tab is its label in bold
    # over its content (`test/tabset_markdown.jl`), never a link to `#`.
    md = repr("text/markdown", tabset("A" => h.p("a"), "B" => h.p("b")))
    @test startswith(md, "**A**\n\na\n") && !contains(md, "](") && !contains(md, "htmxoTabset")

    # A label that is not text, or keeps no letter or digit, is named by position.
    @test names(html(tabset(h.span("x") => h.p("a"), "∑" => h.p("b"), "Ärger ẞtraße" => h.p("c"), "Café" => h.p("d")))) ==
        ["1", "2", "aerger-sstrasse", "cafe"]

    # The app's own names; `active` by name.
    s2 = html(tabset("A" => h.p("a"), "B" => h.p("b"); names=["eins", "zwei"], active="zwei", id="t2"))
    @test names(s2) == ["eins", "zwei"]
    @test match(r"<a[^>]*class=\"contrast\"[^>]*data-tab-name=\"zwei\"", s2) !== nothing
    @test contains(s2, "<div id=\"t2-tab-2\" class=\"tab-panel u-w-full\"")
    @test contains(s2, "<div id=\"t2-tab-1\" class=\"tab-panel u-w-full u-hidden\"")

    # Its own parameter; the preload trigger a lazy tab regains when the URL
    # opens another tab rides on the tabset.
    s3 = html(tabset("A" => "/a", "B" => "/b"; url_param="insitu", preload=true, id="t3"))
    @test contains(s3, "data-tab-param=\"insitu\" data-tab-preload=\"mouseover\"")
    @test !contains(html(tabset("A" => "/a", "B" => "/b")), "data-tab-preload")

    # `url_param=nothing` renders the tabset as before: no names, no script.
    off = html(tabset("A" => h.p("a"), "A" => h.p("b"); url_param=nothing))
    @test !contains(off, "data-tab") && !contains(off, "<script")
    @test contains(html(tabset("A" => h.p("a"), "B" => h.p("b"); url_param=nothing, active="b", id="t5")),
        "<div id=\"t5-tab-2\" class=\"tab-panel u-w-full\"")

    # refused: the URL picks a tab by its name, so two tabs with one name could
    # not be told apart (design decision 1c8b88d, `names` prong).
    @test_throws ArgumentError tabset("Ä" => h.p("a"), "ae" => h.p("b"))
    @test_throws ArgumentError tabset("A" => h.p("a"), "B" => h.p("b"); names=["x", "x"])
    # refused: a tab needs a name to be addressed at all.
    @test_throws ArgumentError tabset("A" => h.p("a"), "B" => h.p("b"); names=["x", ""])
    @test_throws ArgumentError tabset("A" => h.p("a"); names=["a", "b"])
    @test_throws ArgumentError tabset("A" => h.p("a"); url_param="")
    # refused: `active` naming no tab is a programming error, not a fallback.
    @test_throws ArgumentError tabset("A" => h.p("a"); active="nope")

    # Every `htmx()` page carries the runtime, and a static export keeps it
    # with the tabset's names and call, so a bundle opens the URL's tab too.
    page = htmx(tabset("A" => h.p("a"), "B" => h.p("b"); id="t6"))
    @test contains(html(page), "window.htmxoTabset = ")
    for controls in (:disable, :remove)
        exported = html(static_transform(page, StaticExport(; controls)))
        @test contains(exported, "window.htmxoTabset = ")
        @test contains(exported, "data-tab-param=\"tab\"") && contains(exported, "data-tab-name=\"b\"")
        @test contains(exported, "(document.currentScript.parentElement)</script></div>")
    end
end

@testitem "tabset keeps its open tab in the URL in a real browser" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # Step 1 clicks tabs and opens step 2 with the URL they wrote; step 2
        # checks that the page shows those tabs, then leaves through an htmx
        # link and comes back; step 3 names a tab nobody has; step 4 opens the
        # page's static export with tabs in its URL.
        driver = h.script(Raw(raw"""
        window.htmxoWarnings = [];
        const htmxoWarn = console.warn;
        console.warn = (...a) => { window.htmxoWarnings.push(a.join(' ')); htmxoWarn.apply(console, a); };
        window.addEventListener('load', async function() {
            const step = new URLSearchParams(location.search).get('step');
            const checks = [];
            const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
            const wait = async cond => { for (let n = 0; n < 250 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const tab = (ts, name) => document.querySelector('#' + ts + ' > nav a[data-tab-name="' + name + '"]');
            const open = ts => document.querySelector('#' + ts + ' > nav a.contrast').dataset.tabName;
            const shown = ts => Array.from(document.querySelectorAll('#' + ts + ' > .tab-panel'))
                .filter(p => !p.classList.contains('u-hidden')).map(p => p.id).join(',');
            const report = async () => {
                await fetch('/report?step=' + step + '&checks=' + encodeURIComponent(checks.join('|')));
            };
            if (step === '1') {
                check('default-open', open('ts') === 'voralarme' && shown('ts') === 'ts-tab-1');
                tab('ts', 'stoerungen').click();
                check('click-records', location.search === '?step=1&tab=stoerungen');
                check('click-shows', open('ts') === 'stoerungen' && shown('ts') === 'ts-tab-2');
                check('lazy-click-loads', await wait(() => document.getElementById('lazy-stoerungen')));
                check('htmx-path-follows', sessionStorage.getItem('htmx-current-path-for-history') === '/?step=1&tab=stoerungen');
                // A tabset in a docs embed leaves the host page's URL alone.
                tab('emb', 'zwei').click();
                check('embed-untouched', location.search === '?step=1&tab=stoerungen' && open('emb') === 'zwei');
                await report();
                location.href = '/?step=2&tab=stoerungen&view=zwei&emb=zwei';
            } else if (step === '2') {
                // Shown from the start, the lazy panels included.
                check('restored', open('ts') === 'stoerungen' && shown('ts') === 'ts-tab-2');
                check('restored-lazy-default', open('view') === 'zwei' && shown('view') === 'view-tab-2');
                check('restored-lazy-loads', await wait(() => document.getElementById('lazy-zwei')));
                check('hidden-default-not-loaded', !document.getElementById('lazy-eins'));
                check('embed-not-restored', open('emb') === 'eins');
                // The default tab, now hidden, loads on its first click.
                tab('view', 'eins').click();
                check('moved-default-loads', await wait(() => document.getElementById('lazy-eins')));
                check('second-tabset-records', location.search === '?step=2&tab=stoerungen&view=eins&emb=zwei');
                // Leave through an htmx link and come back: htmx restores its
                // snapshot (no refetch), and the entry keeps htmx's state.
                document.getElementById('away').click();
                await wait(() => document.getElementById('other'));
                check('left', location.pathname === '/other');
                history.back();
                await wait(() => document.getElementById('ts'));
                check('back-shows', open('ts') === 'stoerungen' && open('view') === 'eins');
                check('back-url', location.search === '?step=2&tab=stoerungen&view=eins&emb=zwei');
                tab('ts', 'voralarme').click();
                check('state-kept', history.state && history.state.htmx === true && location.search === '?step=2&tab=voralarme&view=eins&emb=zwei');
                await report();
                location.href = '/?step=3&tab=nope';
            } else if (step === '3') {
                await wait(() => window.htmxoWarnings.length);
                check('unknown-default', open('ts') === 'voralarme' && shown('ts') === 'ts-tab-1');
                check('unknown-warns', window.htmxoWarnings.length === 1 && window.htmxoWarnings[0].includes('no tab is named "nope"'));
                await report();
                location.href = '/export?step=4&tab=stoerungen&view=zwei';
            } else {
                // A static file ignores its query string: the browser alone opens the tabs.
                check('export-restored', open('ts') === 'stoerungen' && shown('ts') === 'ts-tab-2');
                check('export-restored-lazy', open('view') === 'zwei' && await wait(() => document.getElementById('lazy-zwei')));
                check('export-hidden-default-not-loaded', !document.getElementById('lazy-eins'));
                tab('ts', 'voralarme').click();
                check('export-click-records', location.search === '?step=4&tab=voralarme&view=zwei');
                await report();
            }
        });
        """))
        body = h.main(; id="main")(
            tabset("Voralarme" => h.p("eager"), "Störungen" => "/lazy/stoerungen"; id="ts"),
            tabset("Eins" => "/lazy/eins", "Zwei" => "/lazy/zwei"; id="view", url_param="view"),
            h.div(; class="htmxo-embed")(tabset("Eins" => h.p("1"), "Zwei" => h.p("2"); id="emb", url_param="emb")),
            h.a("away"; id="away", href="#", hx_get="/other", hx_target="#main", hx_push_url="true"))
        page = repr("text/html", htmx(body; assets=:vendor, extra_head=(driver,),
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing))
        exported = repr("text/html", static_transform(htmx(body; assets=:vendor, extra_head=(driver,),
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing,
            runtime=:linked), StaticExport()))
        @test contains(exported, "window.htmxoTabset = ") && !contains(exported, "tabset_script.js")
        vendorfiles()
        # Lazy loads per (page step, tab), the step read from htmx's
        # HX-Current-URL: a load a navigation cuts short counts for its own step.
        lazy = Dict{Tuple{String,String},Int}()
        lazy_lock = ReentrantLock()
        history_misses = Threads.Atomic{Int}(0)
        reports = Channel{Tuple{String,String,Dict{String,Int}}}(4)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            if path == "/"
                HTTP.hasheader(req, "HX-History-Restore-Request") && Threads.atomic_add!(history_misses, 1)
                return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            end
            path == "/export" && return HTTP.Response(200, ["Content-Type" => "text/html"], exported)
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/other" && return HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"other\">other</p>")
            if startswith(path, "/lazy/")
                name = path[7:end]
                m = match(r"[?&]step=(\d)", HTTP.header(req, "HX-Current-URL", ""))
                step = isnothing(m) ? "?" : m[1]
                lock(() -> lazy[(step, name)] = get(lazy, (step, name), 0) + 1, lazy_lock)
                return HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"lazy-$name\">$name</p>")
            end
            if path == "/report"
                q = HTTP.queryparams(uri)
                counts = lock(lazy_lock) do
                    Dict(name => get(lazy, (q["step"], name), 0) for name in ("stoerungen", "eins", "zwei"))
                end
                put!(reports, (q["step"], q["checks"], counts))
                return HTTP.Response(204)
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        try
            url = "http://127.0.0.1:$port/?step=1"
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --password-store=basic --user-data-dir=$profile $url`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> Base.n_avail(reports) == 4 || process_exited(process), 90; pollint=0.05) === :ok
                    for (step, n) in (("1", 6), ("2", 11), ("3", 2), ("4", 4))
                        isready(reports) || break
                        got, checks, counts = take!(reports)
                        @test got == step
                        lines = split(checks, '|')
                        @test length(lines) == n
                        for line in lines
                            @test endswith(line, ":true")
                        end
                        if step == "1"
                            @test counts["stoerungen"] == 1
                            @test counts["zwei"] == 0
                        elseif step == "2"
                            # The URL's `zwei` loaded once; the hidden default
                            # `eins` once, on its click.
                            @test counts["zwei"] == 1
                            @test counts["eins"] == 1
                        elseif step == "4"
                            @test counts["zwei"] == 1
                            @test counts["eins"] == 0
                        end
                    end
                    @test history_misses[] == 0
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
