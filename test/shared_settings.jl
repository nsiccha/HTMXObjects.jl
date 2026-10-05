using TestItemRunner

@testmodule SharedSettingsFixtures begin
    using HTMXObjects
    include(joinpath(@__DIR__, "..", "examples", "shared_settings.jl"))
    using .SharedSettings
    export SharedSettings, repeated_settings

    # Same generated table and behavior, with common attributes repeated on
    # each row instead of inherited from its ancestor. Measure serialized bytes.
    function repeated_settings(html)
        attrs = match(r"^<div(.*)></div>$", repr("text/html",
            h.div(; SharedSettings.TABLE_SETTINGS...))).captures[1]
        outer = match(r"<div class=\"shared-settings-table\"[^>]*>", html).match
        body = replace(html, outer => "<div class=\"shared-settings-table\">"; count=1)
        replace(body, "<tr data-row=" => "<tr$(attrs) data-row=")
    end
end

@testitem "shared table settings reduce raw bytes without losing generated markup" setup=[SharedSettingsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    root = SharedSettings.App(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    shared = repr("text/html", SharedSettings.table_surface(root; load_operations=true))
    repeated = repeated_settings(shared)
    for html in (shared, repeated)
        @test count("<form ", html) == 800
        @test count("name=\"session_key\" value=\"token\"", html) == 800
        @test !contains(html, "name=\"__htmxo_")
        @test !contains(html, "Node(")
        ids = [m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", html)]
        @test length(ids) == 1200
        @test length(unique(ids)) == length(ids)
        targets = [m.captures[1][2:end] for m in eachmatch(r"hx-target=\"(#[^\"]+)\"", html)]
        @test length(targets) == 800
        @test all(target -> target in ids, targets)
        @test count("aria-label=\"Run read\"", html) == 400
        @test count("aria-label=\"Run write\"", html) == 400
        @test contains(html, "hx-get=\"/proxy/demo/rows/400/read\"")
        @test contains(html, "hx-post=\"/proxy/demo/rows/400/write\"")
    end
    for attribute in ("hx-vals=", "hx-on--before-request=", "hx-on--after-request=", "hx-on-click=")
        @test count(attribute, shared) == 1
        @test count(attribute, repeated) == 400
    end
    strip_common(html) = replace(html,
        r" hx-(?:vals|swap|on--before-request|on--after-request|on-click)=\"[^\"]*\"" => "")
    @test strip_common(shared) == strip_common(repeated)
    @test ncodeunits(shared) < 0.75 * ncodeunits(repeated)
    route!(root; operation_policy=:blocking)
    response = dispatch(:GET, "/eager?session_key=token";
        headers=["HX-Request" => "true", "X-Forwarded-Prefix" => "/proxy/demo"])
    @test response.status == 200
    @test String(response.body) == shared
    @info "Shared table raw HTML bytes (400 rows / 800 forms)" repeated=ncodeunits(repeated) shared=ncodeunits(shared) saved=ncodeunits(repeated)-ncodeunits(shared)
end

@testitem "deferred row controls reduce initial table bytes" setup=[SharedSettingsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    root = SharedSettings.App(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    deferred = repr("text/html", SharedSettings.table_surface(root))
    eager = repr("text/html", SharedSettings.table_surface(root; load_operations=true))
    @test count("<tr data-row=", deferred) == 400
    @test count("<form ", deferred) == 0
    @test count("Load operations", deferred) == 400
    @test count("hx-vals=", deferred) == 1
    has_last_row_url = occursin(r"hx-get=\"/proxy/demo/detail\?[^\"]*\brow=400(?:&amp;[^\"]*)?\"", deferred)
    @test has_last_row_url
    @test count("session_key=token", deferred) == 400
    @test !contains(deferred, ">nothing</div>")
    @test ncodeunits(deferred) < 0.2 * ncodeunits(eager)
    route!(root; operation_policy=:blocking)
    response = dispatch(:GET, "/?session_key=token";
        headers=["HX-Request" => "true", "X-Forwarded-Prefix" => "/proxy/demo"])
    @test response.status == 200
    @test String(response.body) == deferred
    detail = dispatch(:GET, "/detail?row=400&session_key=token";
        headers=["HX-Request" => "true", "X-Forwarded-Prefix" => "/proxy/demo"])
    @test detail.status == 200
    @test count("<form ", String(detail.body)) == 2
    @test contains(String(detail.body), "hx-post=\"/proxy/demo/rows/400/write\"")
    @info "Deferred table raw HTML bytes (400 rows; forms loaded when requested)" eager=ncodeunits(eager) deferred=ncodeunits(deferred) detail=ncodeunits(detail.body) saved=ncodeunits(eager)-ncodeunits(deferred)
end

@testitem "shared table ancestor behavior survives mounted swaps and form refresh" setup=[SharedSettingsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        root = SharedSettings.App(; __prefix__="/proxy/demo",
            __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
        route!(root; operation_policy=:blocking)
        receipt = Channel{String}(1)
        requests = Any[]
        page_loads = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          function require(value, label) { if (!value) throw new Error(label); }
          async function until(check, label) {
            const end = Date.now() + 20000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function row(n) { return document.querySelector('tr[data-row="' + n + '"]'); }
          function form(n, verb) { return row(n).querySelector('form[hx-' + verb + ']'); }
          function result(n, verb) { return document.querySelector(form(n, verb).getAttribute('hx-target')); }
          async function loadRow(n) {
            const settled = new Promise(resolve => row(n).querySelector('.row-operations')
              .addEventListener('htmx:afterSettle', resolve, {once:true}));
            row(n).querySelector('button').click();
            await settled;
          }
          try {
            const table = document.querySelector('.shared-settings-table');
            const original = form(2, 'get');
            if (location.pathname !== '/deferred') require(original && form(1, 'get'), 'eager initial forms');
            await loadRow(2);
            await until(() => form(2, 'get') !== original, 'relative target reload');
            await until(() => table.querySelector('output').textContent === 'Ready', 'ancestor after-request');
            require(table.dataset.lastRow === '2', 'ancestor click handler');
            if (!form(1, 'get')) {
              await loadRow(1);
              await until(() => form(1, 'get'), 'deferred first row');
            }
            const read = form(2, 'get');
            const target = read.getAttribute('hx-target');
            const button = read.querySelector('button');
            const label = button.innerHTML;
            const context = document.querySelector(read.getAttribute('hx-include'));
            const sharedNames = Array.from(new Set(Array.from(context.querySelectorAll('[name]')).map(el => el.name))).join(',');
            const mode = context.querySelector('[name="mode"][value="long"]');
            mode.checked = true;
            const controls = read.querySelector('.htmxo-semantic-controls');
            const refreshed = new Promise(resolve => read.addEventListener('htmx:afterSettle', resolve, {once:true}));
            await htmx.ajax('GET', read.getAttribute('hx-get') + '?__htmxo_form=1&__htmxo_controls=1', {
              source: read, target: controls, swap: 'outerHTML', values: {
                mode: 'long', session_key: 'token', __htmxo_shared_context: sharedNames,
                __htmxo_context_selector: read.getAttribute('hx-include')
              }
            });
            await refreshed;
            await until(() => read.querySelector('[name="choice"][value="c"]'), 'dependent choices');
            require(form(2, 'get') === read && read.getAttribute('hx-target') === target, 'form and target identity');
            require(read.querySelector('button') === button && button.innerHTML === label, 'rich submit identity');
            require(button.title === 'Run read' && button.getAttribute('aria-label') === 'Run read', 'button metadata');
            read.querySelector('[name="choice"][value="c"]').checked = true;
            read.requestSubmit();
            await until(() => result(2, 'get').textContent.includes('read:2:token:compact:long:c'), 'GET values');
            require(result(1, 'get').textContent === '', 'GET isolation');
            const write = form(1, 'post');
            write.querySelector('[name="note"]').value = 'changed';
            write.requestSubmit();
            await until(() => result(1, 'post').textContent.includes('write:1:token:compact:changed'), 'POST values');
            require(result(2, 'post').textContent === '', 'POST isolation');
            await until(() => table.querySelector('output').textContent === 'Ready', 'shared handler after swap');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once:true});
        """))
        table = repr("text/html", SharedSettings.table_surface(root; indices=1:2, load_operations=true))
        deferred = repr("text/html", SharedSettings.table_surface(root; indices=1:2))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path in ("/shared", "/repeated", "/deferred")
                push!(page_loads, String(req.target))
                content = path == "/deferred" ? deferred :
                    path == "/shared" ? table : repeated_settings(table)
                page = htmx(Raw(content), driver; assets="/test-assets",
                    sse_version=nothing, ws_version=nothing, preload_version=nothing,
                    hyperscript_version=nothing, pico_version=nothing,
                    feedback=false, compose=false, overlay=false)
                return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", page))
            end
            if path in ("/native-get", "/native-post")
                leaf = root.rows(3)
                form = path == "/native-get" ? operation_form(leaf, :read; navigate=true) :
                    operation_form(leaf, :write; verb=:POST, method="post", action=leaf / "write")
                native_driver = h.script(Raw(raw"""
                  window.addEventListener('load', function() {
                    const form = document.querySelector('form');
                    const choice = form.querySelector('[name="choice"][value="b"]');
                    if (choice) choice.checked = true;
                    const note = form.querySelector('[name="note"]');
                    if (note) note.value = 'native';
                    form.requestSubmit();
                  }, {once:true});
                """))
                # No htmx script: the browser itself serializes these controls.
                page = h.html(h.body(h.div(form; SharedSettings.TABLE_SETTINGS...), native_driver))
                return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", page))
            end
            path == "/test-assets/htmx.min.js" && return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            push!(requests, (; method=req.method, target=String(req.target), body=String(HTMXObjects._request_body_bytes(req))))
            response = dispatch(req.method, replace(String(req.target), r"^/proxy/demo" => "");
                headers=[collect(req.headers); "X-Forwarded-Prefix" => "/proxy/demo"],
                body=HTMXObjects._request_body_bytes(req))
            if startswith(path, "/proxy/demo/rows/3/") && HTTP.header(req, "HX-Request", "") != "true"
                isready(receipt) || put!(receipt, "native:$(req.method):$(response.status)")
            end
            response
        end
        try
            # Warm only pure render/control routes before the browser deadline.
            for url in ("/proxy/demo/detail?row=2&session_key=token",
                        "/proxy/demo/rows/2/read?__htmxo_form=1&__htmxo_controls=1&mode=long&session_key=token&__htmxo_shared_context=mode")
                warm = HTTP.get("http://127.0.0.1:$port" * url; retry=false, status_exception=false)
                @test warm.status == 200
                warm.status == 200 || error(String(warm.body))
            end
            for path in ("/shared", "/repeated", "/deferred", "/native-get", "/native-post")
                empty!(requests)
                empty!(page_loads)
                mktempdir() do profile
                    process = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port$path`;
                        stdout=devnull, stderr=joinpath(profile, "browser.log")); wait=false)
                    try
                        @test timedwait(() -> isready(receipt) || process_exited(process), 90; pollint=0.05) === :ok
                        @test isready(receipt)
                        if isready(receipt)
                            outcome = take!(receipt)
                            expected = path == "/native-get" ? "native:GET:200" :
                                path == "/native-post" ? "native:POST:200" : "/complete?status=passed"
                            @test outcome == expected
                            outcome == expected || @info "Shared settings browser failure" outcome
                        end
                    finally
                        process_exited(process) || kill(process)
                        wait(process)
                    end
                end
                if startswith(path, "/native-")
                    @test length(requests) == 1
                    values = only(requests).target * "&" * only(requests).body
                    @test contains(values, "session_key=token")
                    @test contains(values, "view=compact")
                    @test !contains(values, "columns=")
                    @test !contains(values, "__htmxo_")
                    @test contains(values, path == "/native-get" ? "choice=b" : "note=native")
                else
                    @test page_loads == [path]
                    @test length(requests) == (path == "/deferred" ? 5 : 4)
                    @test count(req -> HTTP.URI(req.target).path == "/proxy/demo/detail", requests) ==
                        (path == "/deferred" ? 2 : 1)
                    @test count(req -> HTTP.URI(req.target).path == "/proxy/demo/rows/2/read" &&
                        !contains(req.target, "__htmxo_form=1"), requests) == 1
                    @test any(req -> contains(req.target, "__htmxo_controls=1"), requests)
                    @test all(req -> contains(req.target * "&" * req.body, "columns=column1"), requests)
                    @test count(req -> req.method == "POST", requests) == 1
                end
            end
        finally
            close(server)
        end
    end
end

@testitem "shared settings keep native GET and POST form controls" setup=[SharedSettingsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    root = SharedSettings.App(; __prefix__="/proxy/demo",
        __req__=HTTP.Request("GET", "/?session_key=token"), __cache_base__=mktempdir())
    route!(root; operation_policy=:blocking)
    leaf = root.rows(3)
    get_html = repr("text/html", operation_form(leaf, :read; navigate=true))
    post_html = repr("text/html", operation_form(leaf, :write; verb=:POST,
        method="post", action=leaf / "write"))
    @test contains(get_html, "method=\"get\" action=\"/proxy/demo/rows/3/read\"")
    @test contains(post_html, "method=\"post\" action=\"/proxy/demo/rows/3/write\"")
    for html in (get_html, post_html)
        @test contains(html, "name=\"session_key\" value=\"token\"")
        @test contains(html, "name=\"view\" value=\"compact\"")
        @test !contains(html, "name=\"__htmxo_")
    end
    get_response = dispatch(:GET, "/rows/3/read?session_key=token&view=compact&mode=short&choice=b")
    @test get_response.status == 200
    @test contains(String(get_response.body), "read:3:token:compact:short:b")
    post_response = dispatch(:POST, "/rows/3/write";
        headers=["Content-Type" => "application/x-www-form-urlencoded"],
        body="session_key=token&view=compact&note=native")
    @test post_response.status == 200
    @test contains(String(post_response.body), "write:3:token:compact:native")
end
