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
    resp = to_response(hx_response(h.p("ok"); toast="Gespeichert ✓ 100%"))
    @test HTTP.header(resp, "X-HTMXO-Toast") == HTTP.escapeuri("Gespeichert ✓ 100%")
    # Header values are ASCII: the text arrives percent-encoded.
    @test isascii(HTTP.header(resp, "X-HTMXO-Toast"))
    @test !HTTP.hasheader(to_response(hx_response(h.p("ok"))), "X-HTMXO-Toast")
    page = repr("text/html", htmx(h.p("x")))
    @test count("window.htmxoToast = toast", page) == 1
    @test count(".htmxo-toasts {", page) == 1
    # One outcome reading, shared by the failure toast, request feedback and
    # the compose box.
    @test count("window.htmxoRequestOutcome = outcome", page) == 1
    @test contains(page, "window.htmxoRequestOutcome(e).state")
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

@testitem "toasts in a real browser" setup=[ChromeDump] tags=[:unit, :browser] begin
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
            check('error-gets-failure-toast-not-success', texts().join('|') === 'Request failed (HTTP 500 Internal Server Error)' && toasts()[0].classList.contains('htmxo-toast-error'));
            toasts()[0].querySelector('.htmxo-toast-close').click();
            await wait(() => toasts().length === 0);
            await settle('act');
            check('swap-none-body', texts().join('|') === 'interrupt sent');
            await settle('act-fail');
            const error = toasts().find(t => t.classList.contains('htmxo-toast-error'));
            check('error-toast', error && error.querySelector('span').textContent === 'Request failed (HTTP 409 Conflict): already stopped' && error.getAttribute('role') === 'alert');
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
                to_response(hx_response("saved"; toast="Invoice saved ✓ 100%"))
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
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
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

# A request that fails before it reaches HTMXObjects (a gateway's 413, a
# dropped connection) used to show only request feedback's two-second red
# outline (snag `request-feedback-02dea6aa`: an upload over a gateway's size
# limit). It now raises one error toast that names the status and reason. A
# raw-socket server answers with an empty reason phrase, as an HTTP/2 gateway
# does, and closes a connection without any answer.
@testitem "failed requests raise one error toast in a real browser" tags=[:unit, :browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_file = "/vendor/" * HTMXObjects._VENDOR_ASSETS[:htmx].file
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        controls = h.div(
            h.form(h.input(; type="file", name="image"), h.button("Transcribe"; id="upload");
                id="upload-form", hx_post="/gateway", hx_encoding="multipart/form-data", hx_target="#upload-out"),
            h.div("previous result"; id="upload-out"),
            h.button("Stop"; id="plain", hx_post="/plain", hx_swap="none"),
            h.button("Drop"; id="drop", hx_post="/drop", hx_target="#drop-out"), h.div(; id="drop-out"),
            h.button("Away"; id="away", hx_post="/location", hx_target="#away-out"), h.div(; id="away-out"),
            h.button("Slow"; id="slow", hx_post="/slow", hx_target="#slow-out"), h.div(; id="slow-out"),
            h.form(compose_box("text"); id="compose", class="htmxo-compose-form", hx_post="/gateway", hx_swap="none"),
            h.button("Shown"; id="shown", hx_post="/gateway", hx_target="#shown-out"), h.div(; id="shown-out"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const require = (ok, label) => { if (!ok) throw new Error(label + ' ' + JSON.stringify(state())); checks.push(label); };
            const el = id => document.getElementById(id);
            const shown = () => Array.from(document.querySelectorAll('.htmxo-toast.htmxo-toast-show'));
            const texts = () => shown().map(t => t.querySelector('span').textContent);
            const state = () => ({ texts: texts(), classes: ['upload-form', 'drop', 'away', 'slow'].map(id => id + ':' + el(id).className) });
            const wait = async cond => { for (let n = 0; n < 400 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            // Resolves a macrotask after the request from `id` ended: its
            // answer, or the sendError/sendAbort that follows an
            // afterRequest without a status. The shell's toast has run by then.
            const ended = (id, fire) => new Promise(resolve => {
                const names = ['htmx:afterRequest', 'htmx:sendError', 'htmx:sendAbort'];
                const on = e => {
                    const elt = e.detail.requestConfig && e.detail.requestConfig.elt || e.detail.elt;
                    if (elt !== el(id) || (e.type === 'htmx:afterRequest' && !(e.detail.xhr && e.detail.xhr.status))) return;
                    names.forEach(n => document.removeEventListener(n, on));
                    setTimeout(resolve, 0);
                };
                names.forEach(n => document.addEventListener(n, on));
                fire();
            });
            const dismissAll = async () => { shown().forEach(t => t.querySelector('.htmxo-toast-close').click()); await wait(() => shown().length === 0); };
            try {
                await ended('upload-form', () => el('upload').click());
                require(texts().join('|') === 'Request failed (HTTP 413 Request Entity Too Large)' && shown()[0].getAttribute('role') === 'alert',
                    'gateway 413 names status and reason from the title');
                require(el('upload-form').classList.contains('htmx-request-error') && !el('upload-form').classList.contains('htmx-request-active'),
                    'failed requester flashes red without the in-flight class');
                require(el('upload-out').textContent === 'previous result', 'nothing swapped into the target');
                await ended('upload-form', () => el('upload').click());
                require(texts().join('|') === 'Request failed (HTTP 413 Request Entity Too Large) (×2)', 'a repeat counts instead of stacking');
                await dismissAll();
                await ended('plain', () => el('plain').click());
                require(texts().join('|') === 'Request failed (HTTP 409 Conflict): already stopped', 'short text/plain refusal follows the status');
                await dismissAll();
                await ended('drop', () => el('drop').click());
                require(texts().join('|') === 'Request failed: no response (network error or server unreachable)', 'dropped connection');
                require(el('drop').classList.contains('htmx-request-error') && !el('drop').classList.contains('htmx-request-active'),
                    'dropped connection flashes red');
                await dismissAll();
                await ended('away', () => el('away').click());
                require(texts().length === 0 && !el('away').classList.contains('htmx-request-error'), 'HX-Location answer is no failure');
                require(await wait(() => el('away-out').textContent === 'landed'), 'HX-Location followed');
                await ended('slow', () => { el('slow').click(); setTimeout(() => htmx.trigger(el('slow'), 'htmx:abort'), 100); });
                require(texts().length === 0 && !el('slow').classList.contains('htmx-request-error'), 'aborted request is no failure');
                const poll = document.createElement('div');
                poll.id = 'poll'; poll.setAttribute('hx-get', '/missing'); poll.setAttribute('hx-trigger', 'load, every 60s');
                document.body.appendChild(poll);
                await ended('poll', () => htmx.process(poll));
                require(texts().length === 0, 'a poller fails silently');
                poll.remove();
                await ended('compose', () => htmx.trigger(el('compose'), 'submit'));
                require(texts().join('|') === 'send failed — your text is preserved, retry when ready', 'compose box keeps its own single toast');
                await dismissAll();
                const timeout = window.htmxoRequestOutcome({ type: 'htmx:timeout', detail: {} });
                require(timeout.state === 'failure' && timeout.text === 'Request timed out', 'timeout outcome');
                require(window.htmxoRequestOutcome({ type: 'htmx:sendAbort', detail: {} }).state === 'neutral', 'abort outcome');
                const defaults = htmx.config.responseHandling;
                htmx.config.responseHandling = [{ code: '413', swap: true, error: true }].concat(defaults);
                await ended('shown', () => el('shown').click());
                htmx.config.responseHandling = defaults;
                require(texts().length === 0 && el('shown-out').textContent.indexOf('413 Request Entity Too Large') >= 0,
                    'an error answer the app swaps in raises no toast');
                await fetch('/complete?status=' + encodeURIComponent('passed:' + checks.length));
            } catch (error) {
                await fetch('/complete?status=' + encodeURIComponent(String(error)));
            }
        }, { once: true });
        """))
        page = repr("text/html", htmx(controls, driver; assets=:vendor, sse_version=nothing,
            ws_version=nothing, preload_version=nothing, hyperscript_version=nothing, overlay=false))
        nginx = "<html>\r\n<head><title>413 Request Entity Too Large</title></head>\r\n<body>\r\n" *
            "<center><h1>413 Request Entity Too Large</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"

        receipt = Channel{String}(1)
        listener = listen(Sockets.localhost, 0)
        port = Int(getsockname(listener)[2])
        respond(io, status_line, body=""; type="text/html", headers="") = write(io,
            "HTTP/1.1 $status_line\r\nContent-Type: $type; charset=utf-8\r\n$headers" *
            "Content-Length: $(sizeof(body))\r\nConnection: close\r\n\r\n", body)
        function handle(io)
            request_line = readline(io)
            body_bytes = 0
            while true
                line = readline(io)
                isempty(strip(line)) && break
                name, value = strip.(split(line, ':'; limit=2))
                lowercase(name) == "content-length" && (body_bytes = parse(Int, value))
            end
            body_bytes > 0 && read(io, body_bytes)
            target = split(request_line)[2]
            path = first(split(target, '?'))
            path == "/" && return respond(io, "200 OK", page)
            path == htmx_file && return respond(io, "200 OK", htmx_js; type="application/javascript")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(target))
                return respond(io, "204 No Content")
            end
            # An empty reason phrase: what the browser sees from an HTTP/2 gateway.
            path == "/gateway" && return respond(io, "413 ", nginx)
            path == "/plain" && return respond(io, "409 Conflict", "already stopped"; type="text/plain")
            path == "/drop" && return nothing
            path == "/location" && return respond(io, "200 OK";
                headers="HX-Location: {\"path\":\"/landed\",\"target\":\"#away-out\"}\r\n")
            path == "/landed" && return respond(io, "200 OK", "landed")
            # Held past the client's abort; the late write may hit a closed socket.
            path == "/slow" && (sleep(2); return respond(io, "200 OK", "late"))
            respond(io, "404 Not Found", "missing")
        end
        acceptor = @async while isopen(listener)
            io = try accept(listener) catch; break end
            @async try
                handle(io)
            catch err
                err isa Base.IOError || @error "test server handler failed" exception=(err, catch_backtrace())
            finally
                close(io)
            end
        end
        try
            mktempdir() do profile
                browser_log = joinpath(profile, "browser.log")
                browser = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(browser), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    if isready(receipt)
                        outcome = HTTP.unescapeuri(take!(receipt))
                        @test outcome == "/complete?status=passed:15"
                        outcome == "/complete?status=passed:15" || @info "Failure toast outcome" outcome
                    else
                        @info "Failure toast timeout" log=read(browser_log, String)
                    end
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
        finally
            close(listener)
        end
    end
end

# The failed-request toasts speak the page's error texts: `htmx(...;
# error_texts)` puts them on `<html>`, where the shell's toast runtime reads
# them, and an English page stays byte-identical (snag
# error-articles-i-c4c9b7f6, design pick `16ro3ue`).
@testitem "the page shell carries non-English toast texts" tags=[:unit] begin
    using HTMXObjects
    de = error_texts(:de)
    html_tag(page) = match(r"<html[^>]*>", repr("text/html", page)).match
    tag = html_tag(htmx(h.p("x"); error_texts=de))
    @test contains(tag, "data-htmxo-error-texts=")
    @test contains(tag, "Anfrage fehlgeschlagen") && contains(tag, "Fehlerhaftes Gateway") &&
        contains(tag, "Schließen")
    @test contains(tag, "hx-ext=\"preload\"")
    @test !contains(html_tag(htmx(h.p("x"); preload_version=nothing, error_texts=de)), "hx-ext")
    @test contains(html_tag(HTMXObjects.pico_page(h.p("x"); error_texts=de)), "data-htmxo-error-texts=")
    english = repr("text/html", htmx(h.p("x")))
    @test english == repr("text/html", htmx(h.p("x"); error_texts=error_texts(:en)))
    @test html_tag(htmx(h.p("x"))) == "<html hx-ext=\"preload\">"
    # The runtime's English default is written from the same texts.
    @test contains(english, "var ENGLISH = {\"request_failed\":\"Request failed\"")
    @test contains(english, "\"404\":\"Not Found\"")
    # refused: a locale symbol is not a set of texts, and would silently stay English
    @test_throws ArgumentError htmx(h.p("x"); error_texts=:de)
end

@testitem "failure toasts speak the page's error_texts in a real browser" tags=[:unit, :browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_file = "/vendor/" * HTMXObjects._VENDOR_ASSETS[:htmx].file
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        controls = h.div(
            h.button("Bad"; id="bad", hx_post="/bad", hx_target="#out"),
            h.button("Big"; id="big", hx_post="/big", hx_target="#out"),
            h.button("Drop"; id="drop", hx_post="/drop", hx_target="#out"), h.div(; id="out"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const require = (ok, label) => { if (!ok) throw new Error(label + ' ' + JSON.stringify(texts())); checks.push(label); };
            const el = id => document.getElementById(id);
            const shown = () => Array.from(document.querySelectorAll('.htmxo-toast.htmxo-toast-show'));
            const texts = () => shown().map(t => t.querySelector('span').textContent);
            const wait = async cond => { for (let n = 0; n < 400 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const ended = (id, fire) => new Promise(resolve => {
                const names = ['htmx:afterRequest', 'htmx:sendError'];
                const on = e => {
                    const elt = e.detail.requestConfig && e.detail.requestConfig.elt || e.detail.elt;
                    if (elt !== el(id) || (e.type === 'htmx:afterRequest' && !(e.detail.xhr && e.detail.xhr.status))) return;
                    names.forEach(n => document.removeEventListener(n, on));
                    setTimeout(resolve, 0);
                };
                names.forEach(n => document.addEventListener(n, on));
                fire();
            });
            const dismissAll = async () => { shown().forEach(t => t.querySelector('.htmxo-toast-close').click()); await wait(() => shown().length === 0); };
            try {
                await ended('bad', () => el('bad').click());
                // HTTP/1.1 brings the English reason "Bad Gateway"; the page's table names it.
                require(texts().join('|') === 'Anfrage fehlgeschlagen (HTTP 502 Fehlerhaftes Gateway)', 'reason phrase from the page texts');
                require(shown()[0].querySelector('.htmxo-toast-close').getAttribute('aria-label') === 'Schließen', 'dismiss label');
                await dismissAll();
                await ended('big', () => el('big').click());
                require(texts().join('|') === 'Anfrage fehlgeschlagen (HTTP 413 Inhalt zu groß)', 'empty reason phrase');
                await dismissAll();
                await ended('drop', () => el('drop').click());
                require(texts().join('|') === 'Anfrage fehlgeschlagen: keine Antwort (Netzwerkfehler oder Server nicht erreichbar)', 'dropped connection');
                const timeout = window.htmxoRequestOutcome({ type: 'htmx:timeout', detail: {} });
                require(timeout.text === 'Zeitüberschreitung der Anfrage', 'timeout outcome');
                await fetch('/complete?status=' + encodeURIComponent('passed:' + checks.length));
            } catch (error) {
                await fetch('/complete?status=' + encodeURIComponent(String(error)));
            }
        }, { once: true });
        """))
        page = repr("text/html", htmx(controls, driver; assets=:vendor, sse_version=nothing,
            ws_version=nothing, preload_version=nothing, hyperscript_version=nothing, overlay=false,
            error_texts=error_texts(:de)))
        gateway(title) = "<html>\r\n<head><title>$title</title></head>\r\n<body>\r\n" *
            "<center><h1>$title</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"

        receipt = Channel{String}(1)
        listener = listen(Sockets.localhost, 0)
        port = Int(getsockname(listener)[2])
        respond(io, status_line, body=""; type="text/html") = write(io,
            "HTTP/1.1 $status_line\r\nContent-Type: $type; charset=utf-8\r\n" *
            "Content-Length: $(sizeof(body))\r\nConnection: close\r\n\r\n", body)
        function handle(io)
            request_line = readline(io)
            body_bytes = 0
            while true
                line = readline(io)
                isempty(strip(line)) && break
                name, value = strip.(split(line, ':'; limit=2))
                lowercase(name) == "content-length" && (body_bytes = parse(Int, value))
            end
            body_bytes > 0 && read(io, body_bytes)
            target = split(request_line)[2]
            path = first(split(target, '?'))
            path == "/" && return respond(io, "200 OK", page)
            path == htmx_file && return respond(io, "200 OK", htmx_js; type="application/javascript")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(target))
                return respond(io, "204 No Content")
            end
            path == "/bad" && return respond(io, "502 Bad Gateway", gateway("502 Bad Gateway"))
            # An empty reason phrase: what the browser sees from an HTTP/2 gateway.
            path == "/big" && return respond(io, "413 ", gateway("413 Request Entity Too Large"))
            path == "/drop" && return nothing
            respond(io, "404 Not Found", "missing")
        end
        acceptor = @async while isopen(listener)
            io = try accept(listener) catch; break end
            @async try
                handle(io)
            catch err
                err isa Base.IOError || @error "test server handler failed" exception=(err, catch_backtrace())
            finally
                close(io)
            end
        end
        try
            mktempdir() do profile
                browser_log = joinpath(profile, "browser.log")
                browser = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(browser), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    if isready(receipt)
                        outcome = HTTP.unescapeuri(take!(receipt))
                        @test outcome == "/complete?status=passed:5"
                        outcome == "/complete?status=passed:5" || @info "German failure toast outcome" outcome
                    else
                        @info "German failure toast timeout" log=read(browser_log, String)
                    end
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
        finally
            close(listener)
        end
    end
end
