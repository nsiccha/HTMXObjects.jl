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

@testitem "request feedback marks only requests the reader started in a browser" tags=[:browser, :unit] begin
    # Snag lazy-load-succes-a0c68d63: a lazy fragment (`hx-trigger="load"`,
    # outerHTML) flashed a success outline around the whole content it loaded.
    # htmx reports the end of a request whose own swap removed its element on
    # the closest remaining ancestor, and the script marked that ancestor.
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        # Runs while the page parses, before htmx sends the page's own `load`
        # requests: every feedback class any element ever receives is recorded,
        # with the in-flight opacity of each requesting element.
        driver = h.script(Raw(raw"""
        var marks = {}, dim = {};
        function probe(el) { return el.getAttribute && el.getAttribute('data-probe'); }
        new MutationObserver(function(records) {
          records.forEach(function(r) {
            var p = probe(r.target);
            if (!p || !r.target.isConnected) return;
            r.target.classList.forEach(function(c) {
              var m = /^htmx-request-(\w+)$/.exec(c);
              if (!m) return;
              marks[p] = marks[p] || [];
              if (marks[p].indexOf(m[1]) < 0) marks[p].push(m[1]);
            });
          });
        }).observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ['class']});
        // htmx adds `htmx-request` (the CSS dim) just before beforeSend.
        document.addEventListener('htmx:beforeSend', function(e) {
          var p = probe(e.detail.elt);
          if (p) dim[p] = getComputedStyle(e.detail.elt).opacity;
        });
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent(event.message));
        });
        window.addEventListener('load', async function() {
          var sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          var el = p => document.querySelector('[data-probe="' + p + '"]');
          async function until(p) {
            for (var i = 0; i < 600 && !el(p); i++) await sleep(25);
            if (!el(p)) throw new Error('timeout: ' + p);
          }
          try {
            await until('lazy-content');
            await until('panel-content');
            await until('poll-content');
            el('nest').click();
            await until('nested-content');
            el('self').click();
            await until('self-content');
            await sleep(100);
            var want = {
              // The page's own requests: a lazy fragment, a tab panel shown
              // on screen, a poller's final answer, and a lazy fragment that
              // arrived with a clicked answer.
              'lazy': '', 'lazy-wrap': '', 'lazy-content': '', 'panel': '', 'panel-content': '',
              'poll': '', 'poll-wrap': '', 'poll-content': '', 'nested': '', 'nested-content': '',
              // Clicked: the button and its target pulse, then flash.
              'nest': 'active success', 'nest-out': 'active success',
              // Clicked and replaced by its own answer: what replaced it
              // flashes, not the element around it.
              'self': 'active', 'self-content': 'success', 'self-wrap': ''
            };
            var wrong = Object.keys(want).filter(function(p) {
              return (marks[p] || []).sort().join(' ') !== want[p];
            }).map(function(p) { return p + '=' + (marks[p] || []).join('+'); });
            // Only the clicked button dims while its request runs.
            var dims = {lazy: '1', panel: '1', poll: '1', nested: '1', nest: '0.7'};
            Object.keys(dims).forEach(function(p) {
              if (dim[p] !== dims[p]) wrong.push('dim ' + p + '=' + dim[p]);
            });
            await fetch('/complete?status=' + (wrong.length ? encodeURIComponent('wrong ' + wrong.join(',')) : 'passed'));
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        body = h.main(driver,
            h.div(h.div(h.p("loading"); data_probe="lazy", hx_get="/frag?n=lazy",
                        hx_trigger="load", hx_swap="outerHTML"); data_probe="lazy-wrap"),
            h.div(; data_probe="panel", hx_get="/frag?n=panel", hx_trigger="intersect once",
                  hx_swap="innerHTML"),
            h.div(h.div("polling"; data_probe="poll", hx_get="/poll", hx_trigger="every 100ms",
                        hx_swap="outerHTML"); data_probe="poll-wrap"),
            h.button("nest"; data_probe="nest", hx_get="/nest", hx_target="#nest-out"),
            h.div(; id="nest-out", data_probe="nest-out"),
            h.div(h.button("self"; data_probe="self", hx_get="/frag?n=self", hx_swap="outerHTML");
                  data_probe="self-wrap"))
        page = repr("text/html", htmx(body;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, pico_version=nothing,
            compose=false, overlay=false))
        polls = Threads.Atomic{Int}(0)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            html(s) = HTTP.Response(200, ["Content-Type" => "text/html"], s)
            path == "/" && return html(page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/frag"
                n = get(HTTP.queryparams(uri), "n", "")
                return html("<p data-probe=\"$n-content\">$n</p>")
            end
            path == "/nest" && return html("<div data-probe=\"nested\" hx-get=\"/frag?n=nested\" " *
                "hx-trigger=\"load\" hx-swap=\"outerHTML\">loading</div>")
            if path == "/poll"
                Threads.atomic_add!(polls, 1) < 2 || return html("<p data-probe=\"poll-content\">done</p>")
                return html("<div data-probe=\"poll\" hx-get=\"/poll\" hx-trigger=\"every 100ms\" " *
                    "hx-swap=\"outerHTML\">polling</div>")
            end
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

@testitem "request feedback marks each out-of-band swap once in a browser" tags=[:browser, :unit] begin
    # Snag answer-an-htmx-r-63b2f727: htmx 2.0.8 announces an answer's k-th
    # out-of-band swap again on every element swapped in so far, and the
    # script re-marked the swap's target on every announcement, so an answer
    # of 40 out-of-band cells applied 860 success marks.
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        cells = 40
        driver = h.script(Raw(raw"""
        // Every success mark the page applies, and every out-of-band
        // announcement htmx makes.
        var marks = 0, announced = 0;
        var add = DOMTokenList.prototype.add;
        DOMTokenList.prototype.add = function() {
          for (var i = 0; i < arguments.length; i++) if (arguments[i] === 'htmx-request-success') marks++;
          return add.apply(this, arguments);
        };
        document.addEventListener('htmx:oobAfterSwap', function() { announced++; });
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent(event.message));
        });
        window.addEventListener('load', async function() {
          try {
            var go = document.getElementById('go');
            var settled = new Promise(resolve => go.addEventListener('htmx:afterSettle', resolve, {once: true}));
            go.click();
            await settled;
            var wrong = [];
            // The answer: one innerHTML swap into #box, then 40 outerHTML
            // cells. htmx's own count: 1 for the box, then k + 1 for the k-th
            // cell (the request's target and the k cells swapped in so far).
            if (announced !== 861) wrong.push('announced=' + announced);
            // One mark per out-of-band swap, plus the clicked button's own.
            if (marks !== 42) wrong.push('marks=' + marks);
            // An innerHTML target stays in the page, so its mark shows.
            if (!document.getElementById('box').classList.contains('htmx-request-success')) wrong.push('box unmarked');
            if (document.getElementById('c39').textContent !== 'new') wrong.push('cells not swapped');
            await fetch('/complete?status=' + (wrong.length ? encodeURIComponent('wrong ' + wrong.join(',')) : 'passed'));
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        body = h.main(
            h.button("go"; id="go", hx_get="/oob", hx_swap="none"),
            h.div("box"; id="box"),
            h.table(h.tbody(h.tr((h.td(string(i); id="c$i") for i in 0:cells-1)...))))
        page = repr("text/html", htmx(body, driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, pico_version=nothing,
            compose=false, overlay=false))
        answer = "<div id=\"box\" hx-swap-oob=\"innerHTML\">boxed</div>" *
            join("<template><td id=\"c$i\" hx-swap-oob=\"true\">new</td></template>" for i in 0:cells-1)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/oob" && return HTTP.Response(200, ["Content-Type" => "text/html"], answer)
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
