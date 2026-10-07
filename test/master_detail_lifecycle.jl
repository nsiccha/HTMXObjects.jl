using TestItemRunner

@testmodule LazyDetailRequestFixtures begin
    using HTMXObjects
    export LazyDetailActions, LazyDetailReadyActions

    @htmx struct LazyDetailActions
        @get run() = SemanticCode(:julia, "answer = 42")
        @post reject() = nothing
    end

    @htmx struct LazyDetailReadyActions
        @get first() = SemanticCode(:julia, "first = 1")
        @get second() = SemanticCode(:julia, "second = 2")
    end
end

@testitem "lazy detail forms accept immediate swap clicks" setup=[LazyDetailRequestFixtures] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        actions = LazyDetailReadyActions(; __prefix__="/proxy/demo/actions")
        controls = semantic_app(actions; render_operation=entry -> h.div(entry.form, entry.result))
        nested = master_detail_table(["Nested"], ["ready-child"];
            key=identity, master=x -> (h.td(x),),
            detail_url="/proxy/demo/child", initially_open=true)
        detail_html = repr("text/html", h.div(controls, nested; id="ready-controls"))
        table = master_detail_table(["Name"], ["ready"];
            key=identity, master=x -> (h.td(x),), detail_url="/proxy/demo/detail")
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        requests = Tuple{String,Bool}[]
        receipt = Channel{String}(1)
        action_gate = Channel{Nothing}(2)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
          const phase = new URLSearchParams(location.search).get('phase');
          const slot = document.getElementById('detail-slot-ready');
          const checks = [];
          let clicked = false, settled = false, completed = false;
          const forms = () => Array.from(slot.querySelectorAll('form[hx-get]'));
          const require = (ok, label) => { if (!ok) throw new Error(label); checks.push(label); };
          async function finish(status) {
            if (completed) return;
            completed = true;
            await fetch('/complete?status=' + encodeURIComponent(status));
          }
          window.addEventListener('error', event => finish(event.message));
          // This observer runs after each form's own HTMX submit listener.
          document.body.addEventListener('submit', function(event) {
            if (!slot.contains(event.target)) return;
            try { require(event.defaultPrevented, 'HTMX owns submit'); }
            catch (error) { finish(String(error)); }
            // Only a failing negative control needs protection from native
            // navigation, so it can send its diagnostic before unloading.
            if (!event.defaultPrevented) event.preventDefault();
          });
          function clickForms() {
            try {
              require(forms().length === 2, 'both forms inserted');
              require(phase === 'settle' || !settled, 'swap clicks precede settle');
              require(phase === 'settle' || document.getElementById('ready-controls').classList.contains(htmx.config.addedClass),
                      'visual settling still pending at swap');
              clicked = true;
              forms().forEach(form => form.querySelector('button[type=submit]').click());
            } catch (error) { finish(String(error)); }
          }
          function checkResults() {
            if (!clicked || !settled || completed) return;
            const results = forms().map(form => document.querySelector(form.getAttribute('hx-target')));
            if (results.length !== 2 || results.some(result => !result.textContent.trim())) return;
            try {
              require(results[0] !== results[1], 'independent result targets');
              require(results.some(result => result.textContent.includes('first = 1')) &&
                      results.some(result => result.textContent.includes('second = 2')), 'both results');
              require(document.getElementById('ready-controls') && document.getElementById('row-ready'), 'detail and table survive');
              require(location.pathname === '/proxy/demo/', 'table URL survives');
              require(!document.getElementById('ready-controls').classList.contains(htmx.config.addedClass),
                      'visual settling completes');
              require(slot.dataset.loaded === '1' && !slot.dataset.loading && !slot.dataset.failed, 'loaded latches');
              const child = document.getElementById('detail-slot-ready-child');
              if (child.dataset.loaded !== '1') return;
              require(child.textContent === 'child ready', 'nested load completes');
              // Collapse/reopen must preserve those exact nodes and avoid a new fetch.
              const controls = document.getElementById('ready-controls');
              document.getElementById('row-ready').click();
              document.getElementById('row-ready').click();
              require(document.getElementById('ready-controls') === controls, 'loaded DOM reused');
              finish('passed:' + checks.length);
            } catch (error) { finish(String(error)); }
          }
          document.body.addEventListener('htmx:afterSwap', function(event) {
            if (event.target === slot && phase === 'swap' && !clicked) clickForms();
            checkResults();
          });
          document.body.addEventListener('htmx:afterSettle', function(event) {
            if (event.target === slot) {
              settled = true;
              if (phase === 'settle' && !clicked) clickForms();
              // Keep both operations in flight across the ordinary settle
              // pass, using a server gate instead of a timing-based pause.
              fetch('/release');
            }
            checkResults();
          });
          document.getElementById('row-ready').click();
        }, {once: true});
        """))
        page = "<!DOCTYPE html>" * repr("text/html", h.html(
            h.head(h.meta(charset="UTF-8"), h.script(src="/htmx.js"), master_detail_js()), h.body(table, driver)))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/proxy/demo/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/htmx.js" && return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            if path == "/release"
                put!(action_gate, nothing)
                put!(action_gate, nothing)
                return HTTP.Response(204)
            end
            push!(requests, (path, HTTP.header(req, "HX-Request", "") == "true"))
            path == "/proxy/demo/detail" && return HTTP.Response(200, ["Content-Type" => "text/html"], detail_html)
            path == "/proxy/demo/child" && return HTTP.Response(200, ["Content-Type" => "text/html"], "child ready")
            for name in ("first", "second")
                if path == "/proxy/demo/actions/" * name
                    take!(action_gate)
                    return HTTP.Response(200, ["Content-Type" => "text/html"],
                        repr("text/html", SemanticCode(:julia, "$name = $(name == "first" ? 1 : 2)")))
                end
            end
            HTTP.Response(404)
        end
        try
            # The settle-only control proves the fixture and generated targets
            # work before the immediate-click case tests the readiness boundary.
            for phase in ("settle", "swap")
                empty!(requests)
                mktempdir() do profile
                    browser_log = joinpath(profile, "browser.log")
                    url = "http://127.0.0.1:$port/proxy/demo/?phase=$phase"
                    browser = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $url`;
                        stdout=devnull, stderr=browser_log); wait=false)
                    try
                        @test timedwait(() -> isready(receipt) || process_exited(browser), 30; pollint=0.05) === :ok
                        @test isready(receipt)
                        if isready(receipt)
                            outcome = take!(receipt)
                            @info "Lazy detail readiness" phase outcome requests
                            @test startswith(outcome, "/complete?status=passed%3A")
                        else
                            @info "Lazy detail readiness timeout" phase requests log=read(browser_log, String)
                        end
                    finally
                        process_exited(browser) || kill(browser)
                        wait(browser)
                    end
                end
                for path in ("/proxy/demo/detail", "/proxy/demo/child", "/proxy/demo/actions/first", "/proxy/demo/actions/second")
                    @test count(==((path, true)), requests) == 1
                end
                @test all(last, requests)
            end
        finally
            close(action_gate)
            close(server)
        end
    end
end

@testitem "lazy detail lifecycle ignores descendant requests" setup=[LazyDetailRequestFixtures] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        actions = LazyDetailActions(; __prefix__="/actions")
        controls = semantic_app(actions; render_operation=entry -> h.div(entry.form, entry.result))
        inner = master_detail_table(["Inner"], ["inner"];
            key=identity, master=x -> (h.td(x),), detail_url="/inner")
        outer = master_detail_table(["Outer"], ["outer"];
            key=identity, master=x -> (h.td(x),), detail_url="/outer", initially_open=true)
        outer_nodes = (
            h.div(SemanticStatus(:recorded); id="outer-status"), controls, inner,
            h.button("Replace"; id="replace-self", hx_get="/replace", hx_target="this", hx_swap="outerHTML",
                hx_on__before_swap="event.detail.shouldSwap=true"))
        outer_html = join(repr("text/html", node) for node in outer_nodes)
        inner_html = repr("text/html", h.div(
            h.div(SemanticStatus(:recorded); id="inner-status"),
            h.button("Run inner"; id="inner-run", hx_get="/inner-operation", hx_target="#inner-result"),
            h.div(; id="inner-result")))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const ownLoads = [];
          const descendantEvents = [];
          function slot(key) { return document.getElementById('detail-slot-' + key); }
          function state(key) {
            const s = slot(key);
            return JSON.stringify([s.dataset.loaded, s.dataset.loading || '', s.dataset.failed || '',
              Array.from(s.querySelectorAll('[data-status]')).map(p => [p.dataset.status, p.textContent])]);
          }
          function require(ok, label) { if (!ok) throw new Error(label); }
          async function until(check, label) {
            const end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 20));
            }
          }
          const pause = () => new Promise(resolve => setTimeout(resolve, 100));
          document.body.addEventListener('htmx:before-request', function(event) {
            if (event.detail.elt === slot('inner')) {
              ownLoads.push(slot('inner').dataset.loading === '1' &&
                            slot('inner').querySelector('[data-status]').textContent === 'Loading…');
            }
          });
          try {
            await until(() => slot('outer').dataset.loaded === '1', 'outer detail');
            await pause(); // Inserted forms must finish htmx initialization before submission.
            require(document.querySelector('#outer-status [data-status]').textContent === '• recorded', 'initial status');
            const outerState = state('outer');
            document.body.addEventListener('htmx:before-request', function(event) {
              if (event.detail.elt !== slot('outer')) descendantEvents.push(state('outer') === outerState);
            });
            const run = slot('outer').querySelector('form[hx-get$="/run"]');
            run.requestSubmit();
            await until(() => document.querySelector(run.getAttribute('hx-target')).textContent.includes('answer = 42'), 'generated GET');
            require(state('outer') === outerState, 'generated GET changed parent');

            let rejected = false;
            document.body.addEventListener('htmx:afterRequest', function(event) {
              if (event.detail.elt.matches('form[hx-post$="/reject"]')) rejected = true;
            });
            slot('outer').querySelector('form[hx-post$="/reject"]').requestSubmit();
            await until(() => rejected, 'generated POST failure');
            require(state('outer') === outerState, 'failed POST changed parent');

            // Freeze the parent snapshot before the nested slot itself starts changing.
            // Only the recorded status and parent latches belong to this ancestor.
            function parentIntact() {
              return slot('outer').dataset.loaded === '1' && !slot('outer').dataset.loading &&
                !slot('outer').dataset.failed &&
                document.querySelector('#outer-status [data-status]').textContent === '• recorded';
            }
            const nestedEvents = [];
            document.body.addEventListener('htmx:before-request', function(event) {
              if (event.detail.elt !== slot('outer')) nestedEvents.push(parentIntact());
            });
            document.getElementById('row-inner').click();
            await until(() => slot('inner').dataset.failed === '1', 'nested load failure');
            require(parentIntact(), 'nested failure changed parent');
            require(slot('inner').querySelector('[data-status]').textContent === 'Failed to load — click to retry', 'own failure label');
            slot('inner').click();
            await until(() => slot('inner').dataset.loaded === '1', 'nested retry');
            await pause();
            require(parentIntact(), 'nested retry changed parent');
            require(!slot('inner').dataset.failed && !slot('inner').dataset.loading, 'own retry latches');
            const innerState = state('inner');
            document.getElementById('inner-run').click();
            await until(() => document.getElementById('inner-result').textContent === 'inner complete', 'inner operation');
            require(state('inner') === innerState && parentIntact(), 'inner operation changed a lazy slot');

            // htmx forwards afterRequest to a surviving ancestor when the original
            // requester was swapped out. requestConfig.elt keeps its identity even
            // though detail.elt and event.target are now the lazy slot itself.
            let forwarded = false;
            slot('outer').addEventListener('htmx:afterRequest', function(event) {
              if (event.detail.requestConfig.elt.id === 'replace-self') {
                forwarded = event.target === slot('outer') && event.detail.failed;
              }
            });
            document.getElementById('replace-self').click();
            await until(() => document.getElementById('replacement') && forwarded, 'forwarded afterRequest');
            require(parentIntact(), 'forwarded afterRequest changed parent');
            require(ownLoads.length === 2 && ownLoads.every(Boolean), 'own beforeRequest lifecycle');
            require(descendantEvents.length >= 2 && descendantEvents.slice(0, 2).every(Boolean), 'descendant beforeRequest lifecycle');
            require(nestedEvents.length >= 4 && nestedEvents.every(Boolean), 'nested beforeRequest lifecycle');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        page = "<!DOCTYPE html>" * repr("text/html", h.html(
            h.head(h.meta(charset="UTF-8"), h.script(src="/htmx.js"), master_detail_js()), h.body(outer, driver)))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        inner_requests = Ref(0)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/htmx.js" && return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            push!(requests, path)
            path == "/outer" && return HTTP.Response(200, ["Content-Type" => "text/html"], outer_html)
            if path == "/inner"
                inner_requests[] += 1
                return inner_requests[] == 1 ? HTTP.Response(500, "load failed") :
                    HTTP.Response(200, ["Content-Type" => "text/html"], inner_html)
            end
            path == "/actions/run" && return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", SemanticCode(:julia, "answer = 42")))
            path == "/actions/reject" && return HTTP.Response(500, "operation failed")
            path == "/inner-operation" && return HTTP.Response(200, "inner complete")
            # The control explicitly swaps an error response, exercising the
            # forwarded failure event after its original requester is removed.
            path == "/replace" && return HTTP.Response(500, "<p id=\"replacement\">failed</p>")
            HTTP.Response(404)
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
                        outcome = take!(receipt)
                        @test outcome == "/complete?status=passed"
                        outcome == "/complete?status=passed" || @info "Lazy detail browser outcome" outcome requests
                    else
                        @info "Lazy detail browser timeout" requests log=read(browser_log, String)
                    end
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
            @test count(==("/outer"), requests) == 1
            @test count(==("/inner"), requests) == 2
            for path in ("/actions/run", "/actions/reject", "/inner-operation", "/replace")
                @test count(==(path), requests) == 1
            end
        finally
            close(server)
        end
    end
end

@testitem "lazy detail retries transient transport failures by itself" tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        names = ["drop", "gateway", "app", "aborted", "down"]
        table = master_detail_table(["Name"], names;
            key=identity, master=k -> (h.td(k),), detail_url=k -> "/detail/$k")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
          const names = ['drop', 'gateway', 'app', 'aborted', 'down'];
          const slot = k => document.getElementById('detail-slot-' + k);
          const data = k => slot(k).dataset;
          const status = k => { const p = slot(k).querySelector('[data-status]'); return p ? p.textContent : ''; };
          const failedLabel = 'Failed to load — click to retry';
          const sent = {}, sawRetrying = {}, failedAt = {};
          names.forEach(k => sent[k] = 0);
          document.addEventListener('htmx:beforeRequest', function(event) {
            const elt = event.detail.requestConfig && event.detail.requestConfig.elt;
            names.forEach(k => { if (elt === slot(k)) sent[k]++; });
          }, true);
          const start = performance.now();
          let appSentBeforeClick = null, done = false;
          const checks = [];
          const require = (ok, label) => { if (!ok) throw new Error(label + ' ' + JSON.stringify({sent, sawRetrying, appSentBeforeClick,
            state: names.map(k => [k, data(k).loaded, data(k).failed, data(k).loading, status(k)])})); checks.push(label); };
          async function finish(outcome) {
            if (done) return;
            done = true;
            await fetch('/complete?status=' + encodeURIComponent(outcome));
          }
          function tick() {
            const now = performance.now();
            names.forEach(k => {
              if (status(k).indexOf('retrying') >= 0) sawRetrying[k] = true;
              if (data(k).failed === '1' && failedAt[k] === undefined) failedAt[k] = now;
            });
            // An application error must stay failed: click only after the
            // retry window has passed, then the manual retry must still load.
            if (appSentBeforeClick === null && failedAt.app !== undefined && now - failedAt.app > 1500) {
              appSentBeforeClick = sent.app;
              slot('app').click();
            }
            const settled = data('drop').loaded === '1' && data('gateway').loaded === '1' &&
              appSentBeforeClick !== null && data('app').loaded === '1' && data('down').failed === '1' &&
              failedAt.aborted !== undefined && now - failedAt.aborted > 1500;
            if (settled) {
              try {
                require(sent.drop === 2 && slot('drop').querySelector('[data-detail="drop"]'), 'dropped connection retried once and loaded');
                require(sawRetrying.drop, 'retry status shown while waiting');
                require(sent.gateway === 2 && slot('gateway').querySelector('[data-detail="gateway"]'), 'unavailable gateway retried once and loaded');
                require(appSentBeforeClick === 1, 'application error does not retry by itself');
                require(sent.app === 2 && slot('app').querySelector('[data-detail="app"]'), 'click-to-retry loads after an application error');
                require(sent.aborted === 1 && data('aborted').failed === '1' && status('aborted') === failedLabel, 'explicit abort does not retry');
                require(sent.down === 3 && !data('down').loading && status('down') === failedLabel, 'two retries, then click-to-retry');
                finish('passed:' + checks.length);
              } catch (error) { finish(String(error)); }
            } else if (now - start > 20000) {
              try { require(false, 'timed out'); } catch (error) { finish(String(error)); }
            } else setTimeout(tick, 50);
          }
          names.forEach(k => document.getElementById('row-' + k).click());
          setTimeout(() => htmx.trigger(slot('aborted'), 'htmx:abort'), 300);
          tick();
        }, {once: true});
        """))
        page = "<!DOCTYPE html>" * repr("text/html", h.html(
            h.head(h.meta(charset="UTF-8"), h.script(src="/htmx.js"), master_detail_js()), h.body(table, driver)))

        # A raw socket server, so a request can be answered by closing the
        # connection without any response (what a dropped mobile link or a
        # proxy teardown looks like to the browser), on either HTTP.jl major.
        served = Dict(k => 0 for k in names)
        receipt = Channel{String}(1)
        listener = listen(Sockets.localhost, 0)
        port = Int(getsockname(listener)[2])
        reasons = Dict(200 => "OK", 204 => "No Content", 404 => "Not Found",
            500 => "Internal Server Error", 503 => "Service Unavailable")
        respond(io, code, body=""; type="text/html") = write(io,
            "HTTP/1.1 $code $(reasons[code])\r\nContent-Type: $type; charset=utf-8\r\n" *
            "Content-Length: $(sizeof(body))\r\nConnection: close\r\n\r\n", body)
        loaded(k) = repr("text/html", h.div("loaded $k"; data_detail=k))
        function handle(io)
            request_line = readline(io)
            while !isempty(strip(readline(io))) end
            target = split(request_line)[2]
            path = first(split(target, '?'))
            path == "/" && return respond(io, 200, page)
            path == "/htmx.js" && return respond(io, 200, htmx_js; type="application/javascript")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(target))
                return respond(io, 204)
            end
            startswith(path, "/detail/") || return respond(io, 404)
            k = path[length("/detail/")+1:end]
            n = (served[k] += 1)
            k == "drop" && return n == 1 ? nothing : respond(io, 200, loaded(k))
            k == "gateway" && return respond(io, n == 1 ? 503 : 200, n == 1 ? "unavailable" : loaded(k))
            k == "app" && return respond(io, n == 1 ? 500 : 200, n == 1 ? "failed" : loaded(k))
            # Held past the client's abort; the late write may hit a closed socket.
            k == "aborted" && (sleep(2); return respond(io, 200, loaded(k)))
            k == "down" && return nothing
            respond(io, 404)
        end
        acceptor = @async while isopen(listener)
            io = try accept(listener) catch; break end
            @async try
                handle(io)
            catch err
                # Only the aborted request's late write may fail.
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
                        outcome = take!(receipt)
                        @test startswith(outcome, "/complete?status=passed%3A7")
                        startswith(outcome, "/complete?status=passed") || @info "Lazy detail retry outcome" outcome served
                    else
                        @info "Lazy detail retry timeout" served log=read(browser_log, String)
                    end
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
            # The browser itself resent nothing: every request is the runtime's.
            @test served == Dict("drop" => 2, "gateway" => 2, "app" => 2, "aborted" => 1, "down" => 3)
        finally
            close(listener)
        end
    end
end
