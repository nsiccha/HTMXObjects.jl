@testmodule ToastFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h
    export ToastApp, toast_gate, hx_post, hx_get, poll_url, settle_response, body_text, running

    const toast_gate = Ref(Base.Event())

    @htmx struct ToastApp
        "Save the invoice"
        @post save_fast() = hx_response(h.p("saved"); toast="Invoice saved")
        "Save slowly"
        @post save_slow() = (wait(toast_gate[]); hx_response(h.p("slow saved"); toast="Gespeichert ✓ 100%"))
    end

    const hx = ["HX-Request" => "true"]
    hx_post(target) = dispatch(:POST, target; headers=[hx; "HTMXO-Swap" => "innerHTML"], body="")
    hx_get(target) = dispatch(:GET, target; headers=hx)
    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")
    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
    function settle_response(target)
        for _ in 1:200
            response = hx_get(target)
            running(body_text(response)) || return response
            sleep(0.025)
        end
        error("operation never settled: $target")
    end
end

@testitem "route-named toasts: header, shell runtime and compose reuse" tags=[:unit] begin
    using HTMXObjects, HTTP
    resp = hx_response(h.p("ok"); toast="Gespeichert ✓ 100%")
    @test HTTP.header(resp, "X-HTMXO-Toast") == HTTP.escapeuri("Gespeichert ✓ 100%")
    # Header values are ASCII: the text arrives percent-encoded.
    @test isascii(HTTP.header(resp, "X-HTMXO-Toast"))
    @test !HTTP.hasheader(hx_response(h.p("ok")), "X-HTMXO-Toast")
    page = repr("text/html", htmx(h.p("x")))
    @test count("window.htmxoToast = toast", page) == 1
    @test count(".htmxo-toasts {", page) == 1
    # Without the compose box the toast runtime still ships.
    @test contains(repr("text/html", htmx(h.p("x"); compose=false)), "window.htmxoToast = toast")
    # One implementation: the compose box raises its toasts through it.
    compose = repr("text/html", compose_box_script())
    @test !contains(compose, "window.htmxoToast = ")
    @test contains(compose, "window.htmxoToast(text, status)")
    @test !contains(repr("text/html", compose_box_styles()), ".htmxo-toast")
    assets = join(repr.("text/html", compose_box_assets()))
    @test contains(assets, "window.htmxoToast = toast") && contains(assets, ".htmxo-toasts {")
end

@testitem "a polled mutation's toast arrives on its terminal response only" setup=[ToastFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!
    _clear_operation_polls!()
    route!(ToastApp())
    fast = hx_post("/save_fast")
    @test HTTP.header(fast, "X-HTMXO-Toast") == "Invoice%20saved"
    toast_gate[] = Base.Event()
    slow = hx_post("/save_slow")
    body = body_text(slow)
    @test running(body)
    @test !HTTP.hasheader(slow, "X-HTMXO-Toast")
    target = poll_url(body)
    pending = hx_get(target)
    @test running(body_text(pending)) && !HTTP.hasheader(pending, "X-HTMXO-Toast")
    notify(toast_gate[])
    terminal = settle_response(target)
    @test contains(body_text(terminal), "slow saved")
    @test HTTP.header(terminal, "X-HTMXO-Toast") == HTTP.escapeuri("Gespeichert ✓ 100%")
end

@testitem "toasts in a real browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        controls = h.div(
            h.button("Save"; id="save", hx_post="/save", hx_target="#out"),
            h.button("Fail"; id="fail", hx_post="/fail", hx_target="#out"),
            h.button("Stop"; id="act", hx_post="/act", hx_swap="none", data_htmxo_toast="body"),
            h.button("Stop again"; id="act-fail", hx_post="/act-fail", hx_swap="none", data_htmxo_toast="body"),
            h.button("Copy"; id="copy", hx_post="/plain-ok", hx_swap="none", data_htmxo_toast="Copied"),
            h.button("Both"; id="both", hx_post="/save", hx_swap="none", data_htmxo_toast="body"),
            h.div(; id="out"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const region = () => document.getElementById('htmxo-toasts');
            const toasts = () => Array.from(region().querySelectorAll('.htmxo-toast'));
            const texts = () => toasts().map(t => t.querySelector('span').textContent);
            const settle = async id => {
                let done = false;
                const on = e => { if (e.detail.elt.id === id) done = true; };
                document.addEventListener('htmx:afterRequest', on);
                document.getElementById(id).click();
                await wait(() => done);
                document.removeEventListener('htmx:afterRequest', on);
                await new Promise(r => setTimeout(r, 0));
            };
            check('region-ready', region() && region().getAttribute('role') === 'status' && region().getAttribute('aria-live') === 'polite' && toasts().length === 0);
            await settle('save');
            check('route-named', texts().join('|') === 'Invoice saved ✓ 100%' && toasts()[0].classList.contains('htmxo-toast-success'));
            check('swapped', document.getElementById('out').textContent === 'saved');
            const close = toasts()[0].querySelector('.htmxo-toast-close');
            check('dismiss-button', close.tagName === 'BUTTON' && close.getAttribute('aria-label') === 'Dismiss');
            close.click();
            await wait(() => toasts().length === 0);
            check('dismissed', toasts().length === 0);
            await settle('fail');
            check('no-success-toast-on-error', toasts().length === 0);
            await settle('act');
            check('swap-none-body', texts().join('|') === 'interrupt sent');
            await settle('act-fail');
            const error = toasts().find(t => t.classList.contains('htmxo-toast-error'));
            check('error-toast', error && error.querySelector('span').textContent === 'already stopped' && error.getAttribute('role') === 'alert');
            await settle('copy');
            check('static-text', texts().includes('Copied'));
            await settle('both');
            check('route-header-wins', texts().filter(t => t === 'Invoice saved ✓ 100%').length === 1);
            window.htmxoToast('From script', 'info');
            check('api-stacks', texts().includes('From script') && toasts().length === 5 && toasts().every(t => t.parentElement === region()));
            check('fixed-region', getComputedStyle(region()).position === 'fixed');
            // Success/info toasts leave after 4 s, errors after 8 s.
            await new Promise(r => setTimeout(r, 4500));
            check('auto-dismiss', toasts().length === 1 && toasts()[0].classList.contains('htmxo-toast-error'));
            await new Promise(r => setTimeout(r, 4000));
            check('error-stays-longer', toasts().length === 0);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(controls, driver;
            hyperscript_version=nothing, feedback=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            text(status, body) = HTTP.Response(status, ["Content-Type" => "text/plain"], body)
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif path == "/save"
                hx_response("saved"; toast="Invoice saved ✓ 100%")
            elseif path == "/fail"
                HTTP.Response(500, ["Content-Type" => "text/html"], "<article aria-invalid=\"true\">boom</article>")
            elseif path == "/act"
                text(200, "interrupt sent\n")
            elseif path == "/act-fail"
                text(409, "already stopped")
            elseif path == "/plain-ok"
                HTTP.Response(200, ["Content-Type" => "text/html"], "<p>ignored</p>")
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 14
            end
        finally
            close(server)
        end
    end
end
