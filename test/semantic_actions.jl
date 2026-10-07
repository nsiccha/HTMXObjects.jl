using TestItemRunner

@testmodule SemanticActionFixtures begin
    using HTMXObjects
    export ActionHost, ActionRow, ActionGraph, ActionGates, action_surface, OrderHost,
           shared_surface, row_cells, present, SelectHost, SelectStages

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

    # A table row layout: pipeline buttons in the first cell, the other two in
    # the second, the form operation in the third, and one shared result host
    # spanning a second row below all three columns.
    button_of(parts, name) = only(action.button for action in parts.actions
                                  if action.name === name)
    present(nodes...) = Any[node for node in nodes if !isnothing(node)]
    row_cells(parts) = (
        h.tr(h.td(present(parts.context)..., parts.inputs...,
                  button_of(parts, :compile), button_of(parts, :source)),
             h.td(button_of(parts, :reset), button_of(parts, :slow)),
             h.td(parts.operations...)),
        h.tr(h.td(parts.result; colspan="3")))
    shared_surface(row; kwargs...) = action_surface(row; results=:shared,
        layout=row_cells, kwargs...)

    # Two surfaces of one row on one page: the table cells show two of its
    # operations, and the complementary selection renders below the table.
    in_cells(entry) = entry.name in (:compile, :slow)
    split_cells(parts) = (
        h.tr(h.td(present(parts.context)..., parts.inputs...,
                  (action.button for action in parts.actions)...)),
        h.tr(h.td(parts.result; colspan="3")))
    split_surfaces(row) = h.div(
        h.table(h.tbody(action_surface(row; results=:shared, layout=split_cells,
                                       select=in_cells)...)),
        action_surface(row; results=:shared, select=!in_cells))

    @htmx struct ActionHost
        @param session_key::String = "demo"
        @include rows(row::Int) = ActionRow(string(row))
        @get detail(; row::Int) = action_surface(rows(row))
        @get shared_detail(; row::Int) = h.table(h.tbody(shared_surface(rows(row))...))
        @get split_detail(; row::Int) = split_surfaces(rows(row))
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

    # A row and its mounted stage child carry the same request context, but the
    # child delegates its params in a different order than the row declares.
    @htmx struct OrderStages
        @param (; session_key, failed_only) = __parent__
        @post lower() = h.p("lower:$(session_key):$(failed_only)")
    end

    @htmx struct OrderRow
        label::String = ""
        @param (; session_key, view, failed_only) = __parent__
        @include stages = OrderStages()
        @get source() = h.p("source:$(label):$(view)")
        @post benchmark() = h.p("benchmark:$(label):$(failed_only)")
    end

    @htmx struct OrderHost
        @param session_key::String = "demo"
        @param view::String = "compact"
        @param failed_only::Bool = false
        @include rows(key::String) = OrderRow(; label=key)
    end

    # A row whose table cells show the mounted stage buttons and some of the
    # row's own operations; the rest of the graph is used on other surfaces.
    @htmx struct SelectStages
        @param (; session_key) = __parent__
        @param tier::String = "full"
        "Lower the model."
        @post lower() = h.p("lower:$(session_key):$(tier)")
        "Emit the program."
        @post emit() = h.p("emit:$(session_key):$(tier)")
    end

    @htmx struct SelectRow
        label::String
        @param (; session_key) = __parent__
        @include steps = SelectStages()
        "Check the model."
        @post check() = h.p("check:$(label):$(session_key)")
        "Measure the model."
        @post measure() = h.p("measure:$(label)")
        "Flag the model."
        @post flag(; note::String) = h.p("flag:$(label):$(note)")
        "Follow the model."
        @ws follow() = h.p("follow:$(label)")
    end

    @htmx struct SelectHost
        @param session_key::String = "demo"
        @include rows(key::String) = SelectRow(key)
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

    # A child whose hidden context differs (an extra `@param`) gets its own
    # holder instead of falling back to a form (snag compact-repeated-222f51ff,
    # user decision 0brkhpx).
    graph = repr("text/html", semantic_app(ActionGraph(; __prefix__="/graph",
        __req__=HTTP.Request("GET", "/?session_key=token")); compact=true))
    @test contains(graph, "<button type=\"button\" hx-post=\"/graph/root_action\"")
    @test count("<form ", graph) == 0
    graph_holders = [m.captures[1] for m in eachmatch(
        r"<div id=\"([^\"]+)\" class=\"htmxo-semantic-action-inputs\">", graph)]
    @test graph_holders == ["htmxo-semantic-actions-_2fgraph", "htmxo-semantic-actions-_2fgraph-2"]
    @test contains(graph, "<div id=\"htmxo-semantic-actions-_2fgraph-2\" class=\"htmxo-semantic-action-inputs\">" *
                          "<input type=\"hidden\" name=\"session_key\" value=\"token\">" *
                          "<input type=\"hidden\" name=\"flavor\" value=\"plain\"></div>")
    child_button = only(m.match for m in eachmatch(r"<button[^>]*hx-post=\"/graph/child/child_action\"[^>]*>", graph))
    @test contains(child_button, "hx-include=\"#htmxo-semantic-actions-_2fgraph-2\"")
    root_button = only(m.match for m in eachmatch(r"<button[^>]*hx-post=\"/graph/root_action\"[^>]*>", graph))
    @test contains(root_button, "hx-include=\"#htmxo-semantic-actions-_2fgraph\"")

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
          // Act only after htmx has settled (processed) the swapped-in row; a
          // click on an inserted button before that sends no request.
          document.body.addEventListener('htmx:afterSettle', function(event) {
            var target = event.detail.target;
            if (target && /^row[12]$/.test(target.id)) document.body.dataset['settled' + target.id] = 'yes';
          });
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
            await until(() => document.body.dataset.settledrow1 === 'yes', 'row 1 settled');
            document.getElementById('expand2').click();
            await until(() => document.body.dataset.settledrow2 === 'yes', 'row 2 settled');
            require(button(1, 'get', 'source') && button(2, 'get', 'source'), 'row actions');
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

@testitem "compact semantic actions share one holder for equal context in any order" setup=[SemanticActionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    root = OrderHost(; __prefix__="/app",
        __req__=HTTP.Request("GET", "/?session_key=token&failed_only=true"),
        __cache_base__=mktempdir())
    html = repr("text/html", semantic_app(root.rows("r7"); compact=true))
    # Every operation is control-free, so none keeps a form, although the stage
    # child declares the same request context in a different order.
    @test count("<form ", html) == 0
    @test count("<button", html) == 3
    @test count("class=\"htmxo-semantic-action-inputs\"", html) == 1
    for input in ("name=\"session_key\" value=\"token\"", "name=\"failed_only\" value=\"true\"",
                  "name=\"view\" value=\"compact\"")
        @test count(input, html) == 1
    end
    @test count("hx-include=\"#htmxo-semantic-actions-_2fapp_2frows_2fr7\"", html) == 3
    route!(root; operation_policy=:blocking)
    headers = ["HX-Request" => "true", "Content-Type" => "application/x-www-form-urlencoded"]
    lowered = dispatch(:POST, "/rows/r7/stages/lower"; headers,
                       body="session_key=token&failed_only=true&view=compact")
    @test String(lowered.body) == "<p>lower:token:true</p>"
    measured = dispatch(:POST, "/rows/r7/benchmark"; headers,
                        body="session_key=token&failed_only=true&view=compact")
    @test String(measured.body) == "<p>benchmark:r7:true</p>"
end

@testitem "compact semantic actions place parts through a layout around one shared result" setup=[SemanticActionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    root = ActionHost(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    holder = "htmxo-semantic-actions-_2fproxy_2fdemo_2frows_2f1"
    host = "htmxo-semantic-result-_2fproxy_2fdemo_2frows_2f1"

    # results=:shared in the default layout: one host, last in the section;
    # every button and the remaining form target it by id; nothing else is a
    # result.
    entries = Any[]
    shared = repr("text/html", action_surface(root.rows(1); results=:shared,
        render_operation=entry -> (push!(entries, entry);
                                   HTMXObjects._default_semantic_operation(entry))))
    @test count("class=\"htmxo-semantic-operation-result\"", shared) == 1
    @test endswith(shared, "<div id=\"$(host)\" class=\"htmxo-semantic-operation-result\" " *
                           "aria-live=\"polite\"></div></section>")
    @test count("hx-target=\"#$(host)\"", shared) == 5
    @test !contains(shared, "next .htmxo-semantic-operation-result")
    @test only(entries).target_id == host
    @test only(entries).result === nothing
    @test !contains(shared, "nothing")

    # A table layout places each button in its own cell and the host in a
    # row-spanning cell below them.
    cells = repr("text/html", h.tbody(shared_surface(root.rows(1))...))
    rows = [m.captures[1] for m in eachmatch(r"<tr>(.*?)</tr>", cells)]
    @test length(rows) == 2
    tds = [m.captures[1] for m in eachmatch(r"<td>(.*?)</td>", rows[1])]
    @test length(tds) == 3
    @test contains(tds[1], "id=\"$(holder)\"")
    @test contains(tds[1], "hx-post=\"/proxy/demo/rows/1/compile\"")
    @test contains(tds[1], "hx-get=\"/proxy/demo/rows/1/source\"")
    @test contains(tds[2], "hx-delete=\"/proxy/demo/rows/1/reset\"")
    @test contains(tds[2], "hx-post=\"/proxy/demo/rows/1/slow\"")
    @test contains(tds[3], "<form ") && contains(tds[3], "hx-target=\"#$(host)\"")
    @test rows[2] == "<td colspan=\"3\"><div id=\"$(host)\" " *
                     "class=\"htmxo-semantic-operation-result\" aria-live=\"polite\"></div></td>"
    for m in eachmatch(r"<button[^>]*type=\"button\"[^>]*>", cells)
        @test contains(m.match, "hx-target=\"#$(host)\"")
        @test contains(m.match, "hx-include=\"#$(holder), #")
    end

    # Two rows in one table: unique ids, and each row's buttons address only
    # their own holder and host.
    two = repr("text/html", h.table(h.tbody(shared_surface(root.rows(1))...,
                                            shared_surface(root.rows(2))...)))
    ids = [m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", two)]
    @test length(unique(ids)) == length(ids)
    for m in eachmatch(r"<button[^>]*hx-(?:get|post|delete)=\"/proxy/demo/rows/(\d)/[^>]*>", two)
        n = m.captures[1]
        @test contains(m.match, "hx-target=\"#htmxo-semantic-result-_2fproxy_2fdemo_2frows_2f$(n)\"")
        @test contains(m.match, "hx-include=\"#htmxo-semantic-actions-_2fproxy_2fdemo_2frows_2f$(n),")
    end

    # The default layout, passed explicitly through the validated seam, is the
    # default output.
    @test repr("text/html", action_surface(root.rows(1);
              layout=parts -> HTMXObjects._default_semantic_layout(parts))) ==
          repr("text/html", action_surface(root.rows(1)))
    @test repr("text/html", action_surface(root.rows(1); results=:shared,
              layout=parts -> HTMXObjects._default_semantic_layout(parts))) == shared

    # Compiler-owned wiring is placed exactly once, as given.
    without(parts, name) = (h.tr(h.td(present(parts.context)..., parts.inputs...,
        (action.button for action in parts.actions if action.name !== name)...)),
        h.tr(h.td(parts.result)))
    error_text(f) = try f(); "" catch err; err isa ArgumentError ? err.msg : rethrow() end
    message = error_text(() -> shared_surface(root.rows(1); layout=parts -> without(parts, :reset)))
    @test contains(message, "button is placed 0 times")
    @test contains(message, "reset")
    @test contains(error_text(() -> shared_surface(root.rows(1); layout=parts ->
        (row_cells(parts)..., h.tr(h.td(parts.inputs...))))), "hidden-context holder 1 is placed 2 times")
    @test contains(error_text(() -> shared_surface(root.rows(1); layout=parts ->
        (without(parts, nothing)[1], h.tr(h.td(h.div(; class="mine")))))),
        "the shared result host is placed 0 times")
    # A rebuilt button is a different node, even with the same attributes.
    rebuilt(parts) = (h.tr(h.td(present(parts.context)..., parts.inputs...,
        (action.button(; class="mine") for action in parts.actions)...)), h.tr(h.td(parts.result)))
    @test contains(error_text(() -> shared_surface(root.rows(1); layout=rebuilt)), "placed 0 times")
    # results=:each keeps each result directly after its button.
    apart(parts) = h.div(present(parts.context)..., parts.inputs...,
        (action.button for action in parts.actions)...,
        (action.result for action in parts.actions)...)
    @test contains(error_text(() -> action_surface(root.rows(1); layout=apart)),
                   "result does not directly follow its button")
    together(parts) = h.div(present(parts.context)..., parts.inputs...,
        (node for action in parts.actions for node in (action.button, action.result))...)
    @test count("</button><div class=\"htmxo-semantic-operation-result\"",
                repr("text/html", action_surface(root.rows(1); layout=together))) == 4
    @test_throws ArgumentError action_surface(root.rows(1); results=:row)

    # Forms keep the shared host when compact is off.
    plain_shared = repr("text/html", semantic_app(root.rows(1); results=:shared))
    @test count("<form ", plain_shared) == 5
    @test count("hx-target=\"#$(host)\"", plain_shared) == 5
    @test count("class=\"htmxo-semantic-operation-result\"", plain_shared) == 1
end

@testitem "select compiles only the chosen operations of a surface" setup=[SemanticActionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    root = SelectHost(; __prefix__="/app",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    row = root.rows("r1")
    html(value) = repr("text/html", value)
    buttons(surface) = Dict(m.captures[1] => m.match for m in eachmatch(
        r"<button[^>]*hx-(?:get|post|delete)=\"([^\"]+)\"[^>]*>", surface))
    error_text(f) = try f(); "" catch err; err isa ArgumentError ? err.msg : rethrow() end
    holder = "htmxo-semantic-actions-_2fapp_2frows_2fr1"
    host = "htmxo-semantic-result-_2fapp_2frows_2fr1"
    # The table cells show the mounted stage buttons and the row's check; the
    # row's measure and flag operations and its stream belong to other surfaces.
    inline(entry) = entry.object isa SelectStages || entry.name === :check
    http_only(entry) = entry.verb !== :WEBSOCKET
    cells(parts) = (h.tr(h.td(present(parts.context)..., parts.inputs...,
                             (action.button for action in parts.actions)...,
                             parts.operations...)),
                    h.tr(h.td(parts.result)))

    # Selecting everything is the default, byte for byte, in every shape.
    action_row = ActionHost(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"),
        __cache_base__=mktempdir()).rows(1)
    everything = entry -> true
    @test html(semantic_app(action_row)) == html(semantic_app(action_row; select=everything))
    @test html(action_surface(action_row)) == html(action_surface(action_row; select=everything))
    @test html(h.tbody(shared_surface(action_row)...)) ==
          html(h.tbody(shared_surface(action_row; select=everything)...))

    # The default renderer refuses the row's stream; leaving it out compiles.
    @test contains(error_text(() -> semantic_app(row; compact=true)),
                   "no default control for WebSocket")
    full = html(h.tbody(semantic_app(row; compact=true, results=:shared,
                                     layout=cells, select=http_only)...))
    @test sort(collect(keys(buttons(full)))) == ["/app/rows/r1/check", "/app/rows/r1/measure",
        "/app/rows/r1/steps/emit", "/app/rows/r1/steps/lower"]
    @test count("<form ", full) == 1

    # Only the selected operations are compiled: no other callback sees the
    # rest, and the layout need not (and cannot) place them.
    seen = Symbol[]
    selected = semantic_app(row; compact=true, results=:shared, layout=cells, select=inline,
        submit_attrs=entry -> (push!(seen, entry.name); (; title=entry.title)),
        render_operation=entry -> error("no selected operation keeps a form"))
    surface = html(h.tbody(selected...))
    @test sort(seen) == [:check, :emit, :lower]
    @test sort(collect(keys(buttons(surface)))) ==
          ["/app/rows/r1/check", "/app/rows/r1/steps/emit", "/app/rows/r1/steps/lower"]
    @test !contains(surface, "measure") && !contains(surface, "flag") &&
          !contains(surface, "follow") && !contains(surface, "<form")
    @test count("class=\"htmxo-semantic-operation-result\"", surface) == 1
    # A surface that leaves operations out has ids of its own for the parts it
    # shares across operations; the suffix names the selected graph positions.
    suffix = only(m.captures[1] for m in eachmatch(
        Regex("<div id=\"$(host)(-only-[0-9a-f]+)\" class=\"htmxo-semantic-operation-result\""), surface))
    @test contains(surface, "id=\"$(holder)$(suffix)\"")
    @test contains(surface, "-context-selectrow-app-rows-r1$(suffix)\" class=\"htmxo-semantic-context\"")
    unsuffixed(markup) = replace(markup, r"-only-[0-9a-f]+" => "")

    # Apart from those ids, a selected button is the full surface's button: same
    # URL, verb, included holder and context, and target — so submission and
    # polling are unchanged.
    full_buttons = buttons(html(h.tbody(semantic_app(row; compact=true, results=:shared,
        layout=cells, select=http_only, submit_attrs=entry -> (; title=entry.title))...)))
    for (url, button) in buttons(surface)
        @test unsuffixed(button) == unsuffixed(full_buttons[url])
        @test contains(button, "hx-target=\"#$(host)$(suffix)\"")
    end
    each = html(semantic_app(row; compact=true, select=inline))
    each_full = html(semantic_app(row; compact=true, select=http_only))
    for (url, button) in buttons(each)
        @test unsuffixed(button) == unsuffixed(buttons(each_full)[url])
    end

    # Holders and the context group carry only what the selection needs. The
    # stages declare an extra `@param`, so they keep their own holder; they
    # read no fixed field, so a stages-only surface has no context group.
    @test count("class=\"htmxo-semantic-action-inputs\"", surface) == 2
    @test contains(surface, "class=\"htmxo-semantic-context\"")
    stages = html(semantic_app(row; compact=true, select=entry -> entry.object isa SelectStages))
    @test !contains(stages, "htmxo-semantic-context")
    stage_holders = [m.captures[1] for m in eachmatch(
        r"<div id=\"([^\"]+)\" class=\"htmxo-semantic-action-inputs\">", stages)]
    @test length(stage_holders) == 1 && startswith(only(stage_holders), holder * "-only-")
    @test contains(stages, "name=\"tier\" value=\"full\"") &&
          contains(stages, "name=\"session_key\" value=\"token\"")
    for button in values(buttons(stages))
        @test contains(button, "hx-include=\"#$(only(stage_holders))\"")
    end

    # The cells and the complementary surface share one page: every id is
    # unique, every include resolves, and each surface's buttons swap into its
    # own result host.
    rest = semantic_app(row; compact=true, results=:shared,
                        select=entry -> !inline(entry) && http_only(entry))
    page = html(h.div(h.table(h.tbody(selected...)), rest))
    ids = [m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", page)]
    @test length(unique(ids)) == length(ids)
    for m in eachmatch(r"hx-include=\"([^\"]+)\"", page), selector in split(m.captures[1], ", ")
        @test startswith(selector, "#") && selector[2:end] in ids
    end
    rest_html = html(rest)
    rest_host = only(m.captures[1] for m in eachmatch(
        r"<div id=\"([^\"]+)\" class=\"htmxo-semantic-operation-result\"", rest_html))
    @test rest_host != host * suffix && startswith(rest_host, host * "-only-")
    @test sort(collect(keys(buttons(rest_html)))) == ["/app/rows/r1/measure"]
    @test count("hx-target=\"#$(rest_host)\"", rest_html) == 2   # measure's button, flag's form
    @test !contains(rest_html, "hx-target=\"#$(host)$(suffix)\"")

    # A form operation keeps its graph-derived result target when selected.
    target(surface) = only(match(r"hx-target=\"([^\"]+)\"", m.match).captures[1]
        for m in eachmatch(r"<form[^>]*>", surface) if contains(m.match, "/app/rows/r1/flag\""))
    forms = Any[]
    flag_only = html(semantic_app(row; select=entry -> entry.name === :flag,
        render_operation=entry -> (push!(forms, entry);
                                   HTMXObjects._default_semantic_operation(entry))))
    @test length(forms) == 1 && only(forms).name === :flag
    @test target(flag_only) == target(html(semantic_app(row; select=http_only)))
    @test contains(flag_only, "id=\"$(only(forms).target_id)\"")

    # Placement is still checked for every selected part.
    missing_emit(parts) = (h.tr(h.td(present(parts.context)..., parts.inputs...,
        (action.button for action in parts.actions if action.name !== :emit)...)),
        h.tr(h.td(parts.result)))
    message = error_text(() -> semantic_app(row; compact=true, results=:shared,
                                            layout=missing_emit, select=inline))
    @test contains(message, "/steps/emit button is placed 0 times")

    # The predicate answers true or false; its own failures propagate; and the
    # whole graph is still discovered and checked.
    @test contains(error_text(() -> semantic_app(row; select=entry -> nothing)),
                   "select must return true or false")
    @test_throws ErrorException semantic_app(row; select=entry -> error("boom"))
    @test contains(error_text(() -> semantic_app(root; select=entry -> false)), "rows")
    @test !contains(html(semantic_app(row; compact=true, select=entry -> false)), "<button")

    # Selected buttons submit what their forms would have.
    route!(root; operation_policy=:blocking)
    headers = ["HX-Request" => "true", "Content-Type" => "application/x-www-form-urlencoded"]
    lowered = dispatch(:POST, "/rows/r1/steps/lower"; headers, body="session_key=token&tier=full")
    @test String(lowered.body) == "<p>lower:token:full</p>"
    checked = dispatch(:POST, "/rows/r1/check"; headers, body="session_key=token&label=r1")
    @test String(checked.body) == "<p>check:r1:token</p>"
end

@testitem "shared compact results land in their own row's host in a browser" setup=[SemanticActionFixtures] tags=[:browser, :semantic] begin
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
          function host(n) {
            return document.getElementById('htmxo-semantic-result-_2fproxy_2fdemo_2frows_2f' + n);
          }
          function button(n, verb, name) {
            return row(n).querySelector('button[hx-' + verb + '$="/' + name + '"]');
          }
          function text(n) { return host(n).textContent; }
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function require(value, label) { if (!value) throw new Error(label); }
          document.body.addEventListener('htmx:afterSettle', function(event) {
            var target = event.detail.target;
            if (target && /^row[12]$/.test(target.id)) document.body.dataset['settled' + target.id] = 'yes';
          });
          document.body.addEventListener('htmx:afterSwap', function() {
            [1, 2].forEach(function(n) {
              var h = host(n);
              if (h && h.querySelector('.treebar-poller')) document.body.dataset['polled' + n] = 'yes';
            });
          });
          try {
            document.getElementById('expand1').click();
            await until(() => document.body.dataset.settledrow1 === 'yes', 'row 1 settled');
            document.getElementById('expand2').click();
            await until(() => document.body.dataset.settledrow2 === 'yes', 'row 2 settled');
            var all = Array.from(document.querySelectorAll('[id]')).map(el => el.id);
            require(new Set(all).size === all.length, 'duplicate DOM ids');
            // Placement: buttons in their cells, one host in a row-spanning
            // cell of its own table row, and no other result element.
            [1, 2].forEach(function(n) {
              require(button(n, 'post', 'compile').closest('td') === button(n, 'get', 'source').closest('td'),
                      'pipeline cell ' + n);
              require(button(n, 'delete', 'reset').closest('td') !== button(n, 'post', 'compile').closest('td'),
                      'second cell ' + n);
              require(host(n).closest('td').getAttribute('colspan') === '3', 'spanning host ' + n);
              require(host(n).closest('tr') !== button(n, 'post', 'compile').closest('tr'), 'host row ' + n);
            });
            require(document.querySelectorAll('.htmxo-semantic-operation-result').length === 2,
                    'only the two hosts are results');

            button(2, 'get', 'source').click();
            await until(() => text(2).includes('source:2:token'), 'row 2 GET');
            require(text(1) === '', 'GET filled row 1');
            button(1, 'post', 'compile').click();
            await until(() => text(1).includes('compile:1:token'), 'row 1 POST');
            require(text(2).includes('source:2:token'), 'POST changed row 2');
            button(1, 'get', 'source').click();
            await until(() => text(1).includes('source:1:token'), 'row 1 replaced');
            require(!text(1).includes('compile'), 'shared host kept the earlier result');
            button(2, 'delete', 'reset').click();
            await until(() => text(2).includes('reset:2'), 'row 2 DELETE');
            require(!text(2).includes('source'), 'DELETE kept the earlier result');
            row(1).querySelector('form').requestSubmit();
            await until(() => text(1).includes('seeded:1:1'), 'row 1 form into the host');

            button(1, 'post', 'slow').click();
            button(2, 'post', 'slow').click();
            await until(() => document.body.dataset.polled1 === 'yes' &&
                              document.body.dataset.polled2 === 'yes', 'both mutation pollers');
            await fetch('/release');
            await until(() => text(1).includes('slow:1') && text(2).includes('slow:2'), 'both slow results');
            require(!text(1).includes('slow:2') && !text(2).includes('slow:1'), 'mutation polls crossed rows');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        rows = [h.div(
            h.button("Expand"; id="expand$(n)",
                     hx_get="/proxy/demo/shared_detail?row=$(n)&session_key=token",
                     hx_target="#row$(n)", hx_swap="innerHTML"),
            h.div(; id="row$(n)")) for n in 1:2]
        page = repr("text/html", htmx(rows..., diagnostics, driver;
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
            for n in 1:2
                warm = HTTP.get("http://127.0.0.1:$port/proxy/demo/shared_detail?row=$(n)&session_key=token";
                                retry=false, status_exception=false)
                @test warm.status == 200
                warm.status == 200 || error(String(warm.body))
                @test contains(String(warm.body),
                    "hx-target=\"#htmxo-semantic-result-_2fproxy_2fdemo_2frows_2f$(n)\"")
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
            polls = filter(r -> contains(r, "__htmxo_poll=1"), requests)
            @test any(r -> startswith(r, "GET /proxy/demo/rows/1/slow?"), polls)
            @test any(r -> startswith(r, "GET /proxy/demo/rows/2/slow?"), polls)
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/slow"), requests) == 1
            @test count(r -> startswith(r, "POST /proxy/demo/rows/2/slow"), requests) == 1
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/seeded"), requests) == 1
            @test isempty(filter(r -> !contains(r, " /proxy/demo/"), requests))
        finally
            foreach(gate -> isready(gate) || put!(gate, nothing), values(ActionGates))
            close(server)
        end
    end
end

@testitem "selected surfaces of one row share a page in a browser" setup=[SemanticActionFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        ActionGates["1"] = Channel{Nothing}(1)
        route!(ActionHost(; __cache_base__=mktempdir());
            operation_policy=OperationPolicy(:auto; keep_progress=false))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          var prefix = 'htmxo-semantic-result-_2fproxy_2fdemo_2frows_2f1-only-';
          function hosts() { return Array.from(document.querySelectorAll('[id^="' + prefix + '"]')); }
          function cells() { return hosts().find(el => el.closest('table')); }
          function rest() { return hosts().find(el => !el.closest('table')); }
          function button(verb, name) {
            return document.querySelector('button[hx-' + verb + '$="/rows/1/' + name + '"]');
          }
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function require(value, label) { if (!value) throw new Error(label); }
          document.body.addEventListener('htmx:afterSettle', function(event) {
            if (event.detail.target && event.detail.target.id === 'row1') document.body.dataset.settled = 'yes';
          });
          document.body.addEventListener('htmx:afterSwap', function() {
            var host = cells();
            if (host && host.querySelector('.treebar-poller')) document.body.dataset.polled = 'yes';
          });
          try {
            document.getElementById('expand').click();
            await until(() => document.body.dataset.settled === 'yes', 'row settled');
            var all = Array.from(document.querySelectorAll('[id]')).map(el => el.id);
            require(new Set(all).size === all.length, 'duplicate DOM ids');
            require(hosts().length === 2 && cells() && rest() && cells() !== rest(), 'one host per surface');
            require(button('post', 'compile').closest('table') && button('post', 'slow').closest('table'),
                    'selected buttons in the cells');
            require(!button('get', 'source').closest('table') && !button('delete', 'reset').closest('table'),
                    'complementary buttons below the table');

            button('post', 'compile').click();
            await until(() => cells().textContent.includes('compile:1:token'), 'cells POST');
            require(rest().textContent === '', 'cells POST reached the other surface');
            button('get', 'source').click();
            await until(() => rest().textContent.includes('source:1:token'), 'rest GET');
            require(cells().textContent.includes('compile:1:token'), 'rest GET reached the cells');
            rest().closest('section').querySelector('form').requestSubmit();
            await until(() => rest().textContent.includes('seeded:1:1'), 'rest form');
            button('post', 'slow').click();
            await until(() => document.body.dataset.polled === 'yes', 'cells mutation poller');
            await fetch('/release');
            await until(() => cells().textContent.includes('slow:1'), 'cells slow result');
            require(rest().textContent.includes('seeded:1:1'), 'poll reached the other surface');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        page = repr("text/html", htmx(
            h.button("Expand"; id="expand",
                     hx_get="/proxy/demo/split_detail?row=1&session_key=token",
                     hx_target="#row1", hx_swap="innerHTML"),
            h.div(; id="row1"), driver;
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
                isready(ActionGates["1"]) || put!(ActionGates["1"], nothing)
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
            warm = HTTP.get("http://127.0.0.1:$port/proxy/demo/split_detail?row=1&session_key=token";
                            retry=false, status_exception=false)
            @test warm.status == 200
            warm.status == 200 || error(String(warm.body))
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
            polls = filter(r -> contains(r, "__htmxo_poll=1"), requests)
            @test any(r -> startswith(r, "GET /proxy/demo/rows/1/slow?"), polls)
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/slow"), requests) == 1
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/compile"), requests) == 1
            @test count(r -> startswith(r, "POST /proxy/demo/rows/1/seeded"), requests) == 1
            @test isempty(filter(r -> !contains(r, " /proxy/demo/"), requests))
        finally
            isready(ActionGates["1"]) || put!(ActionGates["1"], nothing)
            close(server)
        end
    end
end
