using TestItemRunner

@testmodule SubmitPresentationFixtures begin
    using HTMXObjects
    export SubmitHost, SubmitLeaf, rich_submit, button_attrs

    rich_submit() = h.span(h.span(; class="icon", aria_hidden="true"), h.span("Run"))
    button_attrs = (; title="Run operation", aria_label="Run operation", class="compact")

    @htmx struct SubmitLeaf
        @param (; session_key) = __parent__
        @options mode = (:short, :long)
        mode::Symbol
        @options choice = mode === :short ? (:a, :b) : (:c, :d)
        @get read(; choice::Symbol=:a) = h.p("$(session_key):$(mode):$(choice)")
        @post write(; choice::Symbol=:a) = h.p("$(session_key):$(mode):$(choice)")
    end
    @htmx struct SubmitHost
        @param session_key::String="demo"
        @include rows(row::Int) = SubmitLeaf(:short)
    end
end

@testitem "rich submit decoration and controls-only refresh preserve request context" setup=[SubmitPresentationFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    root = SubmitHost(; __req__=HTTP.Request("GET", "/?session_key=token"))
    leaf = root.rows(7)
    node = rich_submit()
    original = repr("text/html", node)
    for verb in (:GET, :POST)
        name = verb === :GET ? :read : :write
        html = repr("text/html", operation_form(leaf, name; verb, submit=node,
            submit_attrs=button_attrs, target_id="#result", form_class="kept", radio_max=1))
        @test contains(html, "<button title=\"Run operation\" aria-label=\"Run operation\" class=\"compact\" type=\"submit\">")
        @test contains(html, original)
        @test !contains(html, "Node(")
        @test !contains(html, "name=\"__htmxo_")
        @test contains(html, "name=\"session_key\" value=\"token\"")
        @test contains(html, "hx-target=\"#result\"")
        @test contains(html, "__htmxo_controls=1")
        @test contains(html, "__htmxo_radio_max=1")
        @test !contains(html, "__htmxo_submit")
    end
    @test repr("text/html", node) == original
    # Refused: decoration must retain the compiler-owned submission and target
    # (snag semantic-generat-f5f60713 expected contract), including HTML aliases.
    for key in (:type, :TYPE, :hx_target, :data_hx_get, :formaction)
        attrs = NamedTuple{(key,)}(("override",))
        @test_throws ArgumentError operation_form(leaf, :read; submit_attrs=attrs)
    end

    entries = Any[]
    semantic_app(leaf; submit=entry -> node,
        submit_attrs=entry -> (; title="Run $(entry.name)", aria_label="Run $(entry.name)"),
        render_operation=entry -> (push!(entries, entry); h.div(entry.form, entry.result)))
    @test length(entries) == 2
    for entry in entries
        html = repr("text/html", entry.form)
        @test contains(html, "title=\"Run $(entry.name)\"")
        @test contains(html, "aria-label=\"Run $(entry.name)\"")
        @test contains(html, "hx-target=\"#$(entry.target_id)\"")
        @test !contains(html, "name=\"__htmxo_")
    end

    route!(root; operation_policy=:blocking)
    for verb in (:GET, :POST)
        name = verb === :GET ? :read : :write
        url = query_url("/rows/7/$(name)"; __htmxo_form=1, __htmxo_controls=1,
                        __htmxo_radio_max=1, mode=:long, session_key="token")
        response = dispatch(verb, url; headers=["HX-Request" => "true"])
        @test response.status == 200
        html = String(response.body)
        @test startswith(html, "<div class=\"htmxo-semantic-controls\">")
        @test contains(html, "value=\"c\"")
        @test !contains(html, "value=\"a\"")
        @test contains(html, "<select")
        @test !contains(html, "<form")
        @test !contains(html, "<button")
        @test !contains(html, "token:long:")
    end
    response = dispatch(:GET, "/rows/7/read?mode=long&choice=c&session_key=token")
    @test response.status == 200
    @test contains(String(response.body), "token:long:c")
end

@testitem "native rich submit survives automatic dependent refresh in a browser" setup=[SubmitPresentationFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        root = SubmitHost(; __prefix__="/proxy/demo", __req__=HTTP.Request("GET", "/?session_key=token"))
        route!(root; operation_policy=:blocking)
        form = operation_form(root.rows(7), :read; navigate=true, submit=rich_submit(),
            submit_attrs=button_attrs, form_class="kept", data_marker="kept")
        driver = h.script(HTMXObjects.Raw(raw"""
        window.addEventListener('load', async function() {
          function require(value, label) { if (!value) throw new Error(label); }
          async function until(check) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('refresh timed out');
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          try {
            var form = document.querySelector('form');
            var button = form.querySelector('button[type="submit"]');
            var markup = button.innerHTML;
            var mode = form.querySelector('[name="mode"][value="long"]');
            mode.checked = true;
            mode.dispatchEvent(new Event('change', {bubbles:true}));
            await until(() => form.querySelector('[name="choice"][value="c"]'));
            require(form === document.querySelector('form'), 'form replaced');
            require(button === form.querySelector('button[type="submit"]'), 'button replaced');
            require(button.innerHTML === markup, 'rich label changed');
            require(button.title === 'Run operation' && button.getAttribute('aria-label') === 'Run operation', 'decoration lost');
            require(form.method === 'get' && form.getAttribute('action') === '/proxy/demo/rows/7/read', 'native action changed');
            require(form.className === 'kept' && form.dataset.marker === 'kept', 'form attributes lost');
            require(!form.querySelector('[name^="__htmxo_"]'), 'internal fields submitted');
            form.querySelector('[name="choice"][value="c"]').checked = true;
            form.requestSubmit();
          } catch (error) {
            await fetch('/complete?error=' + encodeURIComponent(String(error)));
          }
        }, {once:true});
        """))
        page = repr("text/html", htmx(form, driver; assets="/test-assets",
            sse_version=nothing, ws_version=nothing, preload_version=nothing,
            hyperscript_version=nothing, pico_version=nothing,
            feedback=false, compose=false, overlay=false))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{Any}(1)
        refreshes = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" && return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, (; error=String(req.target)))
                return HTTP.Response(204)
            end
            internal = replace(String(req.target), r"^/proxy/demo" => "")
            response = dispatch(req.method, internal;
                headers=[collect(req.headers); "X-Forwarded-Prefix" => "/proxy/demo"],
                body=HTMXObjects._request_body_bytes(req))
            if HTTP.header(req, "HX-Request", "") == "true"
                push!(refreshes, String(req.target))
            else
                isready(receipt) || put!(receipt, (; target=String(req.target),
                    status=response.status, body=String(response.body)))
            end
            response
        end
        try
            # Warm route compilation before the browser begins its timed wait.
            warm = HTTP.get("http://127.0.0.1:$port/proxy/demo/rows/7/read?__htmxo_form=1&__htmxo_controls=1&mode=long&session_key=token";
                headers=["HX-Request" => "true"], retry=false, status_exception=false)
            @test warm.status == 200
            empty!(refreshes)
            mktempdir() do profile
                process = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=joinpath(profile, "browser.log")); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    if isready(receipt)
                        outcome = take!(receipt)
                        @test !haskey(outcome, :error)
                        if haskey(outcome, :target)
                            @test outcome.status == 200
                            @test contains(outcome.body, "token:long:c")
                            @test !contains(outcome.target, "__htmxo_")
                            @test startswith(outcome.target, "/proxy/demo/rows/7/read?")
                        end
                        haskey(outcome, :error) && @info "Native form browser error" outcome
                    end
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            @test length(refreshes) == 1
            @test contains(only(refreshes), "__htmxo_controls=1")
        finally
            close(server)
        end
    end
end
