using TestItemRunner

@testitem "request feedback marks the target htmx resolved in a browser" tags=[:browser, :unit] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent(event.message));
        });
        window.addEventListener('load', async function() {
          // Where each request's response lands, as htmx resolves it; the
          // feedback classes must be on exactly that element.
          var expected = {
            rel: () => document.getElementById('rel-out'),
            inh: () => document.getElementById('inh-out'),
            find: () => document.getElementById('find-out'),
            outer: () => document.getElementById('swapme'),
          };
          var seen = {};
          // Registered after the feedback script's DOMContentLoaded listeners,
          // so these run after it has applied its classes for the same event.
          document.body.addEventListener('htmx:beforeRequest', function(e) {
            var id = e.detail.elt.id;
            if (expected[id]) seen[id + ':active'] = expected[id]().classList.contains('htmx-request-active');
          });
          document.body.addEventListener('htmx:afterRequest', function(e) {
            var id = e.detail.elt.id;
            if (!expected[id]) return;
            seen[id + ':success'] = expected[id]().classList.contains('htmx-request-success');
            seen[id + ':done'] = true;
          });
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          try {
            for (var id of ['rel', 'inh', 'find', 'outer']) {
              document.getElementById(id).click();
              await until(() => seen[id + ':done'], id);
            }
            var failed = Object.keys(seen).filter(k => seen[k] !== true);
            require(document.getElementById('swapme').textContent === 'new', 'outerHTML swap');
            await fetch('/complete?status=' + (failed.length ? encodeURIComponent('missing ' + failed.join(',')) : 'passed'));
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
          function require(value, label) { if (!value) throw new Error(label); }
        }, {once: true});
        """))
        body = h.main(
            # Extended relative selector, resolved from the requesting button.
            h.div(h.button("rel"; id="rel", hx_get="/frag?n=rel", hx_target="next .result"),
                  h.div(; id="rel-out", class="result")),
            # Target inherited from an ancestor; the button declares none.
            h.div(h.button("inh"; id="inh", hx_get="/frag?n=inh"); hx_target="#inh-out"),
            h.div(; id="inh-out"),
            # `find` resolves inside the requesting element.
            h.button(h.span("find"; id="find-out"); id="find", hx_get="/frag?n=find",
                     hx_target="find span"),
            # outerHTML replaces the target before afterRequest; its same-id
            # replacement carries the success mark.
            h.button("outer"; id="outer", hx_get="/swap", hx_target="#swapme", hx_swap="outerHTML"),
            h.div("old"; id="swapme"))
        page = repr("text/html", htmx(body, driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, pico_version=nothing,
            compose=false, overlay=false))
        # The feedback script itself (not another shell asset) reads htmx's
        # resolved target.
        @test contains(repr("text/html", request_feedback_script()), "evt.detail.target")
        @test contains(page, repr("text/html", request_feedback_script()))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/frag" && return HTTP.Response(200, ["Content-Type" => "text/html"],
                "done-" * get(HTTP.queryparams(uri), "n", ""))
            path == "/swap" && return HTTP.Response(200, ["Content-Type" => "text/html"],
                "<div id=\"swapme\">new</div>")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            HTTP.Response(404)
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    if isready(receipt)
                        @test take!(receipt) == "/complete?status=passed"
                    else
                        @info "Browser diagnostics" log=read(browser_log, String)
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
