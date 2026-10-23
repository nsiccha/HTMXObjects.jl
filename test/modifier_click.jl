@testitem "the shell carries the modifier-click runtime; breadcrumb links get their recorded address" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    page = repr("text/html", htmx(h.p("x")))
    @test count("window.htmxoModifierClick = true", page) == 1
    @test contains(page, repr("text/html", modifier_click_script()))
    linked = repr("text/html", htmx(h.p("x"); assets=:vendor, runtime=:linked))
    @test contains(linked, "src=\"/vendor/htmxo/modifier_click.js?v=")
    @test !contains(linked, "window.htmxoModifierClick")

    crumbs = htmxo_breadcrumb([("Home", "/", "/"), ("Report", "/report?frag=1", "true"),
                               ("Quiet", "/quiet", nothing), ("Off", "/off", "false"),
                               ("Here", nothing, nothing)])
    html = repr("text/html", crumbs)
    @test contains(html, "<a href=\"/\" hx-get=\"/\"")
    @test contains(html, "<a href=\"/report?frag=1\" hx-get=\"/report?frag=1\"")
    # A segment that records no address has none to open.
    @test contains(html, "<a hx-get=\"/quiet\"")
    @test contains(html, "<a hx-get=\"/off\"")
    @test count("href=", html) == 2
end

@testitem "modifier clicks on htmx links open their href in a browser" setup=[ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        # Each case clicks one link once and reads back whether its default was
        # prevented (the browser then does not follow the href), how many
        # requests htmx issued, and whether the link's own click listener ran.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          const checks = [];
          const check = (name, ok) => checks.push([name, Boolean(ok)]);
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await sleep(20); return cond(); };
          const requests = {}, heard = {};
          document.addEventListener('htmx:beforeRequest', e => {
            requests[e.target.id] = (requests[e.target.id] || 0) + 1;
          });
          document.querySelectorAll('a').forEach(a => a.addEventListener('click', () => {
            heard[a.id] = (heard[a.id] || 0) + 1;
          }));
          const click = async (id, mods) => {
            const before = requests[id] || 0, heardBefore = heard[id] || 0;
            const ev = new MouseEvent('click', Object.assign(
              {bubbles: true, cancelable: true, view: window, button: 0}, mods));
            document.getElementById(id).dispatchEvent(ev);
            await sleep(100);
            return {prevented: ev.defaultPrevented, requests: (requests[id] || 0) - before,
                    heard: (heard[id] || 0) - heardBefore};
          };
          const swapped = () => document.getElementById('t').textContent;
          const shell = document.documentElement.dataset.page === 'shell';
          try {
            let r = await click('nav', {});
            check('plain-prevented', r.prevented);
            check('plain-requests', r.requests === 1);
            check('plain-heard', r.heard === 1);
            check('plain-swapped', await wait(() => swapped() === 'fragment'));
            document.getElementById('t').textContent = '';
            for (const [name, mods] of [['ctrl', {ctrlKey: true}], ['meta', {metaKey: true}],
                                        ['shift', {shiftKey: true}], ['ctrl-shift', {ctrlKey: true, shiftKey: true}]]) {
              r = await click('nav', mods);
              // Without the runtime htmx swaps in place, as the snag measured.
              check(name + '-prevented', r.prevented === !shell);
              check(name + '-requests', r.requests === (shell ? 0 : 1));
              check(name + '-heard', r.heard === (shell ? 0 : 1));
              check(name + '-swapped', await wait(() => swapped() === (shell ? '' : 'fragment')));
              document.getElementById('t').textContent = '';
            }
            // A bare `#` link has no address to open: htmx keeps it.
            r = await click('hash', {ctrlKey: true});
            check('hash-kept', r.prevented && r.requests === 1);
            // A link htmx does not take on click: its listeners still run.
            r = await click('hover', {ctrlKey: true});
            check('hover-heard', !r.prevented && r.requests === 0 && r.heard === 1);
            // A link without htmx is the browser's alone either way.
            r = await click('plain-link', {ctrlKey: true});
            check('plain-link', !r.prevented && r.requests === 0 && r.heard === 1);
            // Alt is not a new-tab modifier.
            r = await click('nav', {altKey: true});
            check('alt-kept', r.prevented && r.requests === 1);
            // A programmatic htmx trigger carries no mouse state.
            document.getElementById('t').textContent = '';
            const before = requests.nav || 0;
            htmx.trigger(document.getElementById('nav'), 'click');
            await sleep(100);
            check('trigger-requests', (requests.nav || 0) - before === 1);
          } catch (err) {
            check('error: ' + String(err), false);
          }
          const result = document.createElement('pre'); result.id = 'checks';
          result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
          document.body.appendChild(result);
        });
        """))
        # The links target a frame so a followed href leaves this page in place.
        links = (
            h.a("Nav"; id="nav", href="/page?region=01", target="sink", hx_get="/frag",
                hx_target="#t"),
            h.a("Hash"; id="hash", href="#", hx_get="/frag", hx_target="#t"),
            h.a("Hover"; id="hover", href="/page?region=02", target="sink", hx_get="/frag",
                hx_target="#t", hx_trigger="mouseenter"),
            h.a("Plain"; id="plain-link", href="/page?region=03", target="sink"),
            h.div(; id="t"),
            h.iframe(; name="sink", title="sink"),
        )
        shell = repr("text/html", htmx(h.main(links..., driver);
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false))
        shell = replace(shell, "<html>" => "<html data-page=\"shell\">"; count=1)
        # The control: htmx alone, without the shell's runtime.
        bare = "<!DOCTYPE html>" * repr("text/html", h.html(
            h.head(h.meta(; charset="utf-8"), h.script(""; src="/test-assets/htmx.min.js")),
            h.body(h.main(links..., driver))))
        @test contains(shell, "window.htmxoModifierClick") && !contains(bare, "window.htmxoModifierClick")
        requests = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            html(body) = HTTP.Response(200, ["Content-Type" => "text/html"], body)
            path == "/" && return html(shell)
            path == "/bare" && return html(bare)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            push!(requests, string(req.target, " hx=", HTTP.header(req, "HX-Request", "")))
            path == "/frag" && return html("fragment")
            html("<p>page</p>")
        end
        try
            for (url, n) in (("/", 25), ("/bare", 25))
                empty!(requests)
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$url`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                isnothing(checks) && continue
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == n
                # The browser followed the href of each modifier click the
                # shell let through (Ctrl, Cmd, Shift, Ctrl+Shift), as a plain
                # page request; without the runtime htmx swapped instead.
                opened = count(==("/page?region=01 hx="), requests)
                @test opened == (url == "/" ? 4 : 0)
                all(endswith(":true"), lines) && length(lines) == n && opened == (url == "/" ? 4 : 0) ||
                    @info "modifier-click browser run" url checks=join(lines, "\n") requests=join(requests, "\n")
            end
        finally
            close(server)
        end
    end
end
