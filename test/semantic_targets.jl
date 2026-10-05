using TestItemRunner

@testmodule SemanticTargetFixtures begin
    using HTMXObjects
    export TargetHost, TargetLeaf, TargetSlugRoot, TargetGates

    const TargetGates = Dict{String,Channel{Nothing}}()

    @htmx struct TargetLeaf
        label::String
        @options mode = (:short, :long)
        mode::Symbol
        @options choice = mode === :short ? (:a, :b) : (:c, :d)
        @get read(; choice::Symbol=:a) = h.p("read:$(label):$(mode):$(choice)")
        @post write(; note::String="hello") = h.p("write:$(label):$(note)")
        @get slow() = begin
            take!(TargetGates[label])
            h.p("slow:$(label)")
        end
    end

    @htmx struct TargetHost
        @include rows(row::Int) = TargetLeaf(string(row), :short)
        @include items(item::String) = TargetLeaf(item, :short)
        @get detail(; row::Int) = semantic_app(rows(row);
            submit=entry -> h.span("Run ", h.strong(entry.title)),
            submit_attrs=entry -> (; title="Run $(entry.name)", aria_label="Run $(entry.name)"),
            render_operation=entry -> h.div(entry.form, entry.result))
    end

    @htmx struct TargetSlugRoot
        @get read_mount_2f726f77732f31() = h.p("unmounted")
    end
end

@testitem "selected semantic mounts swap and poll independently in a browser" setup=[SemanticTargetFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        for n in 1:2
            TargetGates[string(n)] = Channel{Nothing}(1)
        end
        route!(TargetHost(; __cache_base__=mktempdir());
            operation_policy=OperationPolicy(:auto; keep_progress=false))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        diagnostics = h.script(Raw(raw"""
          window.addEventListener('error', function(event) {
            fetch('/complete?status=' + encodeURIComponent(event.message));
          });
        """))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          function row(n) { return document.getElementById('row' + n); }
          function form(n, verb, name) {
            return row(n).querySelector('form[hx-' + verb + '$="/' + name + '"]');
          }
          function result(n, verb, name) {
            return document.querySelector(form(n, verb, name).getAttribute('hx-target'));
          }
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function require(value, label) { if (!value) throw new Error(label); }
          document.body.addEventListener('htmx:afterSwap', function() {
            [1, 2].forEach(function(n) {
              if (row(n).querySelector('.treebar-poller')) {
                document.body.dataset['polled' + n] = 'yes';
              }
            });
          });
          document.body.addEventListener('htmx:invalidPath', function(event) {
            fetch('/complete?status=' + encodeURIComponent('invalid path: ' + event.detail.path));
          });
          try {
            document.getElementById('expand1').click();
            document.getElementById('expand2').click();
            await until(() => form(1, 'get', 'read') && form(2, 'get', 'read'), 'both details');
            var all = Array.from(document.querySelectorAll('[id]')).map(el => el.id);
            require(new Set(all).size === all.length, 'duplicate DOM ids');
            var read2 = form(2, 'get', 'read');
            var button2 = read2.querySelector('button[type="submit"]');
            var buttonMarkup = button2.innerHTML;
            var target2 = read2.getAttribute('hx-target');
            var otherRead = result(1, 'get', 'read');
            var otherWrite = result(2, 'post', 'write');
            var refreshedSettled = false;
            row(2).addEventListener('htmx:afterSettle', function(event) {
              if (event.target.classList.contains('htmxo-semantic-controls')) refreshedSettled = true;
            });
            var controls2 = read2.querySelector('.htmxo-semantic-controls');
            var context2 = document.querySelector(read2.getAttribute('hx-include'));
            var sharedNames = Array.from(new Set(Array.from(context2.querySelectorAll('[name]')).map(el => el.name))).join(',');
            await htmx.ajax('GET', read2.getAttribute('hx-get') + '?__htmxo_form=1&__htmxo_controls=1', {
              source: read2, target: controls2, swap: 'outerHTML', values: {
                mode: 'long', __htmxo_shared_context: sharedNames,
                __htmxo_context_selector: read2.getAttribute('hx-include')
              }
            });
            await until(() => refreshedSettled, 'refreshed controls initialized');
            require(read2 === form(2, 'get', 'read'), 'refresh replaced form');
            require(read2.getAttribute('hx-target') === target2, 'refresh changed target');
            require(read2.querySelector('button[type="submit"]') === button2, 'refresh replaced button');
            require(button2.innerHTML === buttonMarkup, 'refresh changed rich submit content');
            require(button2.title === 'Run read' && button2.getAttribute('aria-label') === 'Run read',
                    'refresh lost button decoration');
            require(!read2.querySelector('[name^="__htmxo_"]'), 'internal settings are successful inputs');
            var choice = read2.querySelector('[name="choice"][value="c"]');
            require(!!choice, 'dependent refresh did not update choices');
            // The shared field remains the source of context at submission.
            row(2).querySelector('[name="mode"][value="long"]').checked = true;
            choice.checked = true;
            read2.requestSubmit();
            await until(() => result(2, 'get', 'read').textContent.includes('read:2:long:c'), 'right GET');
            require(otherRead.textContent === '', 'right GET changed left result');
            var write1 = form(1, 'post', 'write');
            write1.querySelector('[name="note"]').value = 'left';
            write1.requestSubmit();
            await until(() => result(1, 'post', 'write').textContent.includes('write:1:left'), 'left POST');
            require(otherWrite.textContent === '', 'left POST changed right result');
            form(1, 'get', 'slow').requestSubmit();
            form(2, 'get', 'slow').requestSubmit();
            await until(() => document.body.dataset.polled1 === 'yes' &&
                              document.body.dataset.polled2 === 'yes', 'both interim pollers');
            await fetch('/release');
            await until(() => result(1, 'get', 'slow').textContent.includes('slow:1') &&
                              result(2, 'get', 'slow').textContent.includes('slow:2'), 'both polls');
            require(!result(1, 'get', 'slow').textContent.includes('slow:2') &&
                    !result(2, 'get', 'slow').textContent.includes('slow:1'), 'poll crossed rows');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        rows = [h.tr(
            h.td(h.button("Expand"; id="expand$(n)", hx_get="/proxy/demo/detail?row=$(n)",
                          hx_target="#row$(n)", hx_swap="innerHTML")),
            h.td(; id="row$(n)")) for n in 1:2]
        page = repr("text/html", htmx(h.table(h.tbody(rows...)), diagnostics, driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, pico_version=nothing,
            feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" && return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            if path == "/release"
                foreach(gate -> isready(gate) || put!(gate, nothing), values(TargetGates))
                return HTTP.Response(204)
            end
            HTTP.header(req, "HX-Request", "") == "true" && push!(requests, String(req.target))
            internal = replace(String(req.target), r"^/proxy/demo" => "")
            dispatch(req.method, internal;
                headers=[collect(req.headers); "X-Forwarded-Prefix" => "/proxy/demo"],
                body=HTMXObjects._request_body_bytes(req))
        end
        try
            # Compile the detail/refresh handlers before starting the browser's clock.
            for n in 1:2
                warm = HTTP.get("http://127.0.0.1:$port/proxy/demo/detail?row=$(n)"; retry=false, status_exception=false)
                @test warm.status == 200
                warm.status == 200 || error(String(warm.body))
                @test contains(String(warm.body), "hx-get=\"/proxy/demo/rows/$(n)/read\"")
            end
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    if isready(receipt)
                        outcome = take!(receipt)
                        @test outcome == "/complete?status=passed"
                        if outcome != "/complete?status=passed"
                            @info "Browser requests" requests=join(requests, "\n")
                        end
                    else
                        counts = Dict(url => count(==(url), requests) for url in unique(requests))
                        @info "Browser diagnostics" counts log=read(browser_log, String)
                    end
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            polls = filter(url -> contains(url, "__htmxo_poll=1"), requests)
            @test any(url -> startswith(url, "/proxy/demo/rows/1/slow?"), polls)
            @test any(url -> startswith(url, "/proxy/demo/rows/2/slow?"), polls)
            unprefixed = filter(url -> !startswith(url, "/proxy/demo/"), requests)
            @test isempty(unprefixed)
        finally
            foreach(gate -> isready(gate) || put!(gate, nothing), values(TargetGates))
            close(server)
        end
    end
end

@testitem "semantic result targets are stable and distinct across selected mounts" setup=[SemanticTargetFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    entries(obj) = begin
        result = Any[]
        semantic_app(obj; render_operation=entry -> begin
            push!(result, entry)
            h.div(entry.form, entry.result)
        end)
        result
    end
    ids(obj) = getproperty.(entries(obj), :target_id)
    root = TargetHost(; __cache_base__=mktempdir())
    left, right = entries(root.rows(1)), entries(root.rows(2))
    @test isempty(intersect(getproperty.(left, :target_id), getproperty.(right, :target_id)))
    @test ids(root.rows(1)) == getproperty.(left, :target_id)
    @test ids(TargetHost(; __cache_base__=mktempdir()).rows(1)) == ids(root.rows(1))
    for entry in [left; right]
        @test contains(repr("text/html", entry.form), "hx-target=\"#$(entry.target_id)\"")
        @test !contains(repr("text/html", entry.form), "name=\"__htmxo_")
        @test contains(repr("text/html", entry.result), "id=\"$(entry.target_id)\"")
        @test occursin(r"^[A-Za-z][A-Za-z0-9_-]*$", entry.target_id)
    end

    # A lossy lowercase/path slug would merge these distinct mounted identities.
    keys = ["A", "a", "a_b", "a-b", "a/b", "a b", "λ"]
    selected = [only(filter(e -> e.name === :read, entries(root.items(key)))).target_id for key in keys]
    @test length(unique(selected)) == length(keys)
    prefixed = TargetHost(; __prefix__="/proxy/demo", __cache_base__=mktempdir())
    @test isempty(intersect(ids(prefixed.rows(1)), ids(root.rows(1))))
    @test ids(prefixed.rows(1)) == ids(TargetLeaf("1", :short; __prefix__="/proxy/demo/rows/1/"))
    @test only(ids(TargetSlugRoot())) ∉ ids(root.rows(1))
    @test only(ids(TargetSlugRoot())) == "htmxo-operation-1-get-read-mount-2f726f77732f31-result"

    route!(root; prefix="demo", operation_policy=:blocking)
    for row in 1:2
        page = dispatch(:GET, "/demo/detail?row=$(row)")
        @test page.status == 200
        html = String(page.body)
        @test contains(html, "hx-get=\"/demo/rows/$(row)/read\"")
        @test contains(html, "id=\"$(first(ids(TargetLeaf(string(row), :short; __prefix__="/demo/rows/$(row)"))))\"")
    end

    # The existing refresh protocol must retain the exact generated selector.
    route!(root; operation_policy=:blocking)
    for (row, group) in [(1, left), (2, right)]
        entry = only(filter(e -> e.name === :read, group))
        query = query_url("/rows/$(row)/read"; __htmxo_form=1,
            __htmxo_target_id="#$(entry.target_id)", mode=:long)
        refreshed = dispatch(:GET, query; headers=["HX-Request" => "true"])
        @test refreshed.status == 200
        html = String(refreshed.body)
        @test contains(html, "hx-target=\"#$(entry.target_id)\"")
        @test contains(html, "value=\"c\"")
        @test !contains(html, "value=\"a\"")
    end

    # Refresh uses the externally visible route for either prefix mechanism.
    for forwarded in (false, true)
        route!(root; prefix=forwarded ? "" : "demo", operation_policy=:blocking)
        headers = forwarded ? ["X-Forwarded-Prefix" => "/proxy/demo/"] : Pair{String,String}[]
        external = forwarded ? "/proxy/demo" : "/demo"
        internal = forwarded ? "" : "/demo"
        for row in 1:2, name in (:read, :write)
            entry = only(filter(e -> e.name === name,
                entries(TargetLeaf(string(row), :short; __prefix__="$(external)/rows/$(row)"))))
            query = query_url("$(internal)/rows/$(row)/$(name)";
                __htmxo_form=1, __htmxo_target_id="#$(entry.target_id)", mode=:long)
            refreshed = dispatch(entry.route.verb, query; headers)
            @test refreshed.status == 200
            html = String(refreshed.body)
            verb = lowercase(string(entry.route.verb))
            @test contains(html, "hx-$(verb)=\"$(external)/rows/$(row)/$(name)\"")
            @test contains(html, "hx-target=\"#$(entry.target_id)\"")
        end
    end
end
