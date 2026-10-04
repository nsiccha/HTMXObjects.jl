using TestItemRunner

@testmodule LazyDetailRequestFixtures begin
    using HTMXObjects
    export LazyDetailActions

    @htmx struct LazyDetailActions
        @get run() = SemanticCode(:julia, "answer = 42")
        @post reject() = nothing
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
