using TestItemRunner

@testmodule SemanticActionFixtures begin
    using HTMXObjects
    export ActionHost, ActionRow, ActionGraph, ActionGates, action_surface

    const ActionGates = Dict{String,Channel{Nothing}}()

    @htmx struct ActionRow
        label::String
        @param (; session_key) = __parent__
        "Compile the model."
        @post compile() = h.p("compile:$(label):$(session_key)")
        "Show the source."
        @get source() = h.p("source:$(label):$(session_key)")
        "Reset the results."
        @delete reset() = h.p("reset:$(label)")
        "Run slowly."
        @post slow() = begin
            take!(ActionGates[label])
            h.p("slow:$(label)")
        end
        "Run with a seed."
        @post seeded(; seed::Int=1) = h.p("seeded:$(label):$(seed)")
    end

    action_surface(row; kwargs...) = semantic_app(row; compact=true,
        submit_attrs=entry -> (; title=entry.title, aria_label=entry.title), kwargs...)

    @htmx struct ActionHost
        @param session_key::String = "demo"
        @include rows(row::Int) = ActionRow(string(row))
        @get detail(; row::Int) = action_surface(rows(row))
    end

    @htmx struct ActionChild
        @param (; session_key) = __parent__
        @param flavor::String = "plain"
        @post child_action() = h.p("child:$(flavor)")
    end

    @htmx struct ActionGraph
        @param session_key::String = "demo"
        @post root_action() = h.p("root")
        @include child = ActionChild()
    end
end

@testitem "compact semantic actions render control-free operations as buttons" setup=[SemanticActionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    root = ActionHost(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    html = repr("text/html", action_surface(root.rows(1)))
    holder = "htmxo-semantic-actions-_2fproxy_2fdemo_2frows_2f1"
    context = only(m.captures[1] for m in
                   eachmatch(r"<fieldset id=\"([^\"]+)\" class=\"htmxo-semantic-context\"", html))

    # Control-free operations become one button plus one result each; the
    # operation with a visible input keeps its generated form and target.
    @test count("<form ", html) == 1
    @test contains(html, "hx-post=\"/proxy/demo/rows/1/seeded\"")
    @test count("<button", html) == 5
    actions = [m.match for m in eachmatch(r"<button[^>]*type=\"button\"[^>]*>", html)]
    @test length(actions) == 4
    for (verb, name) in (("post", "compile"), ("get", "source"), ("delete", "reset"), ("post", "slow"))
        button = only(filter(b -> contains(b, "hx-$(verb)=\"/proxy/demo/rows/1/$(name)\""), actions))
        @test contains(button, "hx-include=\"#$(holder), #$(context)\"")
        @test contains(button, "hx-target=\"next .htmxo-semantic-operation-result\"")
        @test contains(button, "hx-swap=\"innerHTML\"")
    end
    # Each action's result directly follows its button, so the relative target
    # resolves to that operation's own result.
    @test count(r"</button><div class=\"htmxo-semantic-operation-result\" aria-live=\"polite\"></div>", html) == 4

    # Hidden request context is carried once by the shared holder; the seeded
    # form keeps its own copy.
    @test contains(html, "<div id=\"$(holder)\" class=\"htmxo-semantic-action-inputs\">" *
                         "<input type=\"hidden\" name=\"session_key\" value=\"token\"></div>")
    @test count("name=\"session_key\" value=\"token\"", html) == 2

    # Accessible labels: the default action content is the operation title;
    # `submit_attrs` decorates every button; forms keep the "Run" default.
    @test contains(html, ">Compile the model.</button>")
    @test contains(html, "aria-label=\"Compile the model.\"")
    @test contains(html, "type=\"submit\">Run</button>")
    custom = repr("text/html", action_surface(root.rows(1);
        submit=entry -> h.span(string(entry.name); class="op")))
    @test contains(custom, "<span class=\"op\">compile</span></button>")
    @test_throws ArgumentError action_surface(root.rows(1); submit_attrs=(; hx_target="#elsewhere"))

    # Every include points at a rendered element; ids stay unique across rows.
    two = repr("text/html", h.div(action_surface(root.rows(1)), action_surface(root.rows(2))))
    ids = [m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", two)]
    @test length(unique(ids)) == length(ids)
    for m in eachmatch(r"hx-include=\"([^\"]+)\"", two), selector in split(m.captures[1], ", ")
        @test startswith(selector, "#") && selector[2:end] in ids
    end

    # The default layout is unchanged by the new keyword.
    plain = semantic_app(root.rows(1))
    @test repr("text/html", plain) == repr("text/html", semantic_app(root.rows(1); compact=false))
    @test count("<form ", repr("text/html", plain)) == 5
    @test !contains(repr("text/html", plain), "htmxo-semantic-actions")

    # Operations whose hidden context differs from the shared holder keep forms.
    graph = repr("text/html", semantic_app(ActionGraph(; __prefix__="/graph",
        __req__=HTTP.Request("GET", "/?session_key=token")); compact=true))
    @test contains(graph, "<button type=\"button\" hx-post=\"/graph/root_action\"")
    @test contains(graph, "<form hx-post=\"/graph/child/child_action\"")
    @test count("<form ", graph) == 1

    # A button's included values are exactly what its form would have submitted.
    route!(root; operation_policy=:blocking)
    form_headers = ["HX-Request" => "true",
                    "Content-Type" => "application/x-www-form-urlencoded"]
    posted = dispatch(:POST, "/rows/1/compile"; headers=form_headers,
                      body="session_key=token&label=1")
    @test posted.status == 200
    @test contains(String(posted.body), "compile:1:token")
    fetched = dispatch(:GET, "/rows/1/source?session_key=token&label=1";
                       headers=["HX-Request" => "true"])
    @test fetched.status == 200
    @test contains(String(fetched.body), "source:1:token")
    deleted = dispatch(:DELETE, "/rows/1/reset"; headers=form_headers,
                       body="session_key=token&label=1")
    @test deleted.status == 200
    @test contains(String(deleted.body), "reset:1")
end

@testitem "compact semantic actions target their own results in a browser" setup=[SemanticActionFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        for n in 1:2
            ActionGates[string(n)] = Channel{Nothing}(1)
        end
        route!(ActionHost(; __cache_base__=mktempdir());
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
          function button(n, verb, name) {
            return row(n).querySelector('button[hx-' + verb + '$="/' + name + '"]');
          }
          function result(n, verb, name) {
            var b = button(n, verb, name);
            return b && b.nextElementSibling;
          }
          function results() {
            return Array.from(document.querySelectorAll('.htmxo-semantic-operation-result'));
          }
          function filled() { return results().filter(r => r.textContent.trim() !== '').length; }
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function require(value, label) { if (!value) throw new Error(label); }
          var settled = 0;
          document.body.addEventListener('htmx:afterSettle', function() { settled += 1; });
          document.body.addEventListener('htmx:afterSwap', function() {
            [1, 2].forEach(function(n) {
              var slow = result(n, 'post', 'slow');
              if (slow && slow.querySelector('.treebar-poller')) {
                document.body.dataset['polled' + n] = 'yes';
              }
            });
          });
          try {
            document.getElementById('expand1').click();
            await until(() => button(1, 'get', 'source'), 'row 1 actions');
            document.getElementById('expand2').click();
            await until(() => button(2, 'get', 'source'), 'row 2 actions');
            var mark = settled;
            await until(() => settled > mark || button(2, 'post', 'compile'), 'row 2 settled');
            var all = Array.from(document.querySelectorAll('[id]')).map(el => el.id);
            require(new Set(all).size === all.length, 'duplicate DOM ids');
            require(row(1).querySelectorAll('form').length === 1, 'row 1 forms');
            require(button(1, 'post', 'compile').getAttribute('aria-label') === 'Compile the model.',
                    'accessible label');

            button(2, 'get', 'source').click();
            await until(() => result(2, 'get', 'source').textContent.includes('source:2:token'), 'right GET');
            require(filled() === 1, 'GET filled another result');
            button(1, 'post', 'compile').click();
            await until(() => result(1, 'post', 'compile').textContent.includes('compile:1:token'), 'left POST');
            require(filled() === 2, 'POST filled another result');
            button(2, 'delete', 'reset').click();
            await until(() => result(2, 'delete', 'reset').textContent.includes('reset:2'), 'right DELETE');
            require(filled() === 3, 'DELETE filled another result');

            button(1, 'post', 'slow').click();
            button(2, 'post', 'slow').click();
            await until(() => document.body.dataset.polled1 === 'yes' &&
                              document.body.dataset.polled2 === 'yes', 'both mutation pollers');
            await fetch('/release');
            await until(() => result(1, 'post', 'slow').textContent.includes('slow:1') &&
                              result(2, 'post', 'slow').textContent.includes('slow:2'), 'both slow results');
            require(!result(1, 'post', 'slow').textContent.includes('slow:2') &&
                    !result(2, 'post', 'slow').textContent.includes('slow:1'), 'mutation polls crossed rows');
            require(filled() === 5, 'slow results filled another result');
            require(result(1, 'get', 'source').textContent === '', 'left source changed');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        rows = [h.tr(
            h.td(h.button("Expand"; id="expand$(n)",
                          hx_get="/proxy/demo/detail?row=$(n)&session_key=token",
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
                foreach(gate -> isready(gate) || put!(gate, nothing), values(ActionGates))
                return HTTP.Response(204)
            end
            HTTP.header(req, "HX-Request", "") == "true" &&
                push!(requests, string(req.method, " ", req.target))
            internal = replace(String(req.target), r"^/proxy/demo" => "")
            dispatch(req.method, internal;
                headers=[collect(req.headers); "X-Forwarded-Prefix" => "/proxy/demo"],
                body=HTMXObjects._request_body_bytes(req))
        end
        try
            # Compile the detail handler before starting the browser's clock.
            for n in 1:2
                warm = HTTP.get("http://127.0.0.1:$port/proxy/demo/detail?row=$(n)&session_key=token";
                                retry=false, status_exception=false)
                @test warm.status == 200
                warm.status == 200 || error(String(warm.body))
                @test contains(String(warm.body), "hx-post=\"/proxy/demo/rows/$(n)/compile\"")
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
                        outcome == "/complete?status=passed" ||
                            @info "Browser requests" requests=join(requests, "\n")
                    else
                        @info "Browser diagnostics" requests=join(requests, "\n") log=read(browser_log, String)
                    end
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            # Mutations resumed by GET polls on their own paths; nothing escaped the mount.
            polls = filter(r -> contains(r, "__htmxo_poll=1"), requests)
            @test any(r -> startswith(r, "GET /proxy/demo/rows/1/slow?"), polls)
            @test any(r -> startswith(r, "GET /proxy/demo/rows/2/slow?"), polls)
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/slow"), requests) == 1
            @test count(r -> startswith(r, "POST /proxy/demo/rows/2/slow"), requests) == 1
            @test isempty(filter(r -> !contains(r, " /proxy/demo/"), requests))
        finally
            foreach(gate -> isready(gate) || put!(gate, nothing), values(ActionGates))
            close(server)
        end
    end
end
