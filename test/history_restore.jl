using TestItemRunner

# Back to an address htmx pushed, when htmx holds no `sessionStorage` snapshot
# of it (a large page does not fit, or the cache was cleared): htmx 2.0.8
# reloads the address from the server (`HX-History-Restore-Request`, plus
# `HX-Request` by default) and swaps the answer into `<body>`. The page must
# come back whole, its `__page__` chrome included (snag history-restore-e9d56a74:
# it came back as the bare route fragment, its header and navigation gone).
@testitem "Back after a history-cache miss restores the whole page in a browser" setup=[ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        # On `/`: follow two pushed links, drop htmx's snapshots, go Back one
        # step and read the restored page.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          if (location.pathname !== '/') return;
          const checks = [];
          const check = (name, ok) => checks.push([name, Boolean(ok)]);
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await sleep(20); return cond(); };
          const level = () => (document.getElementById('level') || {}).textContent;
          // Click only once htmx has settled the previous swap: a link it has
          // not processed yet is followed as an ordinary page load.
          let settles = 0;
          document.addEventListener('htmx:afterSettle', () => { settles++; });
          const follow = async id => {
            const before = settles;
            document.getElementById(id).click();
            return await wait(() => settles > before);
          };
          try {
            check('pushed-2', await follow('to2') && level() === 'level 2' && location.search === '?n=2');
            check('pushed-3', await follow('next') && level() === 'level 3' && location.search === '?n=3');
            sessionStorage.removeItem('htmx-history-cache');
            let restored = null;
            document.addEventListener('htmx:historyRestore', e => { restored = e.detail; });
            history.back();
            check('restored', await wait(() => restored !== null));
            check('cache-miss', restored && restored.cacheMiss === true);
            check('address', location.pathname === '/level' && location.search === '?n=2');
            check('content', level() === 'level 2');
            check('chrome', document.querySelectorAll('#shell-nav').length === 1);
            check('one-main', document.querySelectorAll('#main').length === 1);
          } catch (err) {
            check('error: ' + String(err), false);
          }
          const result = document.createElement('pre'); result.id = 'checks';
          result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
          document.body.appendChild(result);
        });
        """))

        @htmx struct HistoryRestoreApp
            __page__(content) = htmx(
                h.div(h.nav("SHELL-NAV"; id="shell-nav"), h.main(content; id="main"));
                extra_head=(driver,), assets="/test-assets", sse_version=nothing,
                ws_version=nothing, preload_version=nothing, hyperscript_version=nothing,
                pico_version=nothing, feedback=false, compose=false, overlay=false)
            @get index() = h.a("to level 2"; id="to2", href="/level?n=2", hx_get="/level?n=2",
                               hx_target="#main", hx_push_url="true")
            @get level(; n::Int=1) = h.div(h.p("level $n"; id="level"),
                h.a("next"; id="next", href="/level?n=$(n + 1)", hx_get="/level?n=$(n + 1)",
                    hx_target="#main", hx_push_url="true"))
        end
        route!(HistoryRestoreApp())

        restores = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            HTTP.header(req, "HX-History-Restore-Request", "") == "true" &&
                push!(restores, string(req.target, " hx=", HTTP.header(req, "HX-Request", "")))
            first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == 8
                all(endswith(":true"), lines) && length(lines) == 8 ||
                    @info "history-restore browser run" checks=join(lines, "\n") restores=join(restores, "\n")
            end
            # The Back went to the server, as htmx's default restore request.
            @test restores == ["/level?n=2 hx=true"]
        finally
            close(server)
        end
    end
end
