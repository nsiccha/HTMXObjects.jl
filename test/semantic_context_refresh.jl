using TestItemRunner

@testmodule ContextRefreshFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: TrackedDirectory, option_domain
    export DrawOps, DrawPage, StaticOps, StaticHost, DRAW_ROOT, reset_draws!, region_attrs,
           refresh_url, multipart_body

    const DRAW_ROOT = mktempdir()

    @htmx struct DrawOps
        run_root::String = DRAW_ROOT
        @param model::String = "a"
        @options(model) = option_domain(["a" => "A", "b" => "B"])
        draw_files(key::String) = TrackedDirectory(mkpath(joinpath(run_root, key));
            match = path -> endswith(path, ".json"), key = basename)
        @param draws_source::String = "synthetic"
        @options(draws_source) = option_domain(["synthetic" => "Synthetic";
            ["$name" => "Imported: $name" for name in sort!(collect(keys(draw_files(model))))]])
        doses(key::String) = key == "a" ? [1 => "One", 2 => "Two"] : [3 => "Three"]
        @options(dose) = option_domain(doses(model))
        "Import draws"
        @post import_draws(; file::Upload) = begin
            startswith(file.filename, "slow") && sleep(0.6)
            write(joinpath(run_root, model, basename(file.filename)), file.data)
            h.p("imported:$(file.filename)")
        end
        "Simulate"
        @get simulate(; dose::Int = 1) = h.p("simulate:$(model):$(draws_source):$(dose)")
    end

    @htmx struct DrawPage
        @include ops = DrawOps()
        @get index() = semantic_app(ops)
    end

    @htmx struct StaticOps
        @param model::String = "a"
        @options(model) = option_domain(["a" => "A", "b" => "B"])
        "Simulate"
        @get simulate() = h.p("simulate:$(model)")
    end

    @htmx struct StaticHost
        @include ops = StaticOps()
    end

    # Empty, not remove: a retained root keeps tracking the same directories.
    reset_draws!() = for key in ("a", "b")
        dir = mkpath(joinpath(DRAW_ROOT, key))
        foreach(path -> rm(path; force=true), readdir(dir; join=true))
    end

    # The attributes of the first element opening with `<div class="$class"`.
    function region_attrs(html, class)
        m = match(Regex("<div class=\"$(class)\"([^>]*)>"), html)
        m === nothing && return nothing
        Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&")
             for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.captures[1]))
    end

    refresh_url(attrs, values) = attrs["hx-get"] * "&" * join(["$k=$v" for (k, v) in values], "&")

    # `parts` are `name => text` fields and `name => (filename, content)` files.
    function multipart_body(parts; boundary="htmxoContextBoundary")
        io = IOBuffer()
        for (name, value) in parts
            print(io, "--", boundary, "\r\n")
            if value isa Tuple
                print(io, "Content-Disposition: form-data; name=\"", name,
                      "\"; filename=\"", value[1], "\"\r\nContent-Type: application/json\r\n\r\n",
                      value[2], "\r\n")
            else
                print(io, "Content-Disposition: form-data; name=\"", name, "\"\r\n\r\n",
                      value, "\r\n")
            end
        end
        print(io, "--", boundary, "--\r\n")
        ["Content-Type" => "multipart/form-data; boundary=$(boundary)"], take!(io)
    end
end

@testitem "a shared context control whose options can change refreshes as a region" setup=[ContextRefreshFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    reset_draws!()
    html = repr("text/html", semantic_app(DrawPage().ops))
    group_id = match(r"<fieldset id=\"([^\"]+)\" class=\"htmxo-semantic-context\">", html).captures[1]

    # Only the control whose declared domain reads node state is a region; the
    # fixed `model` domain needs no refresh.
    @test count("class=\"htmxo-semantic-context-control\"", html) == 1
    region = match(r"<div class=\"htmxo-semantic-context-control\".*?</div>"s, html).match
    @test contains(region, "name=\"draws_source\"")
    @test !contains(region, "name=\"model\"")
    attrs = region_attrs(html, "htmxo-semantic-context-control")
    @test attrs["data-htmxo-depends"] == "model"
    # It re-resolves through the GET carrying it, not the import mutation.
    @test startswith(attrs["hx-get"], "/ops/simulate?__htmxo_form=1&")
    @test contains(attrs["hx-get"], "__htmxo_context_control=draws_source")
    @test contains(attrs["hx-get"], "__htmxo_shared_context=draws_source%2Cmodel")
    @test attrs["hx-trigger"] == "htmxo-refresh"
    @test attrs["hx-include"] == "closest .htmxo-semantic-context"
    @test attrs["hx-target"] == "this"
    @test attrs["hx-swap"] == "outerHTML"

    # Every result of the surface names the group a finished mutation refreshes.
    @test count("data-htmxo-refreshes=\"$(group_id)\"", html) == 2

    # A form control reading the lifted `model` refreshes when the group's
    # `model` changes; the import form reads nothing lifted.
    forms = Dict(m.captures[1] => m.match for m in
                 eachmatch(r"<form hx-(?:get|post)=\"/ops/(\w+)\".*?</form>"s, html))
    simulate = region_attrs(forms["simulate"], "htmxo-semantic-controls")
    @test simulate["data-htmxo-context"] == group_id
    @test simulate["data-htmxo-depends"] == "model"
    @test simulate["hx-trigger"] == "htmxo-refresh"
    @test simulate["hx-target"] == "this"
    @test contains(simulate["hx-get"], "__htmxo_controls=1")
    @test simulate["hx-include"] == "closest form, #$(group_id)"
    import_region = region_attrs(forms["import_draws"], "htmxo-semantic-controls")
    @test !haskey(import_region, "data-htmxo-context")
    @test !haskey(import_region, "hx-trigger")

    # A group whose domains are fixed keeps its markup: no region, no marker.
    static_html = repr("text/html", semantic_app(StaticHost().ops))
    @test contains(static_html, "class=\"htmxo-semantic-context\"")
    @test !contains(static_html, "htmxo-semantic-context-control")
    @test !contains(static_html, "data-htmxo-refreshes")
    @test !contains(static_html, "data-htmxo-context")
end

@testitem "a context refresh re-resolves one control against the submitted group" setup=[ContextRefreshFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    reset_draws!()
    route!(DrawPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/").body)
    attrs = region_attrs(html, "htmxo-semantic-context-control")
    refresh(values) = String(dispatch(:GET, refresh_url(attrs, values);
                                      headers=["HX-Request" => "true"]).body)

    before = refresh(["model" => "a", "draws_source" => "synthetic"])
    @test startswith(before, "<div class=\"htmxo-semantic-context-control\"")
    @test region_attrs(before, "htmxo-semantic-context-control") == attrs
    @test !contains(before, "fresh.json")

    # A file written since the page rendered is offered; the choice is kept.
    write(joinpath(DRAW_ROOT, "a", "fresh.json"), "{}")
    after = refresh(["model" => "a", "draws_source" => "synthetic"])
    @test contains(after, "value=\"fresh.json\"")
    @test contains(after, "Imported: fresh.json")
    @test contains(after, "value=\"synthetic\" checked=\"true\"")
    @test contains(refresh(["model" => "a", "draws_source" => "fresh.json"]),
                   "value=\"fresh.json\" checked=\"true\"")
    # The group's submitted `model` decides whose files are offered.
    @test !contains(refresh(["model" => "b", "draws_source" => "synthetic"]), "fresh.json")
    # The operation never ran: a refresh only renders the control.
    @test !contains(after, "simulate:")
end

@testitem "an import through the generated surface is offered by the next context refresh" setup=[ContextRefreshFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    reset_draws!()
    route!(DrawPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/").body)
    attrs = region_attrs(html, "htmxo-semantic-context-control")
    headers, body = multipart_body(["model" => "a", "draws_source" => "synthetic",
                                    "file" => ("posted.json", "{}")])
    response = dispatch(:POST, "/ops/import_draws";
                        headers=[headers; "HX-Request" => "true"], body)
    @test contains(String(response.body), "imported:posted.json")
    refreshed = String(dispatch(:GET,
        refresh_url(attrs, ["model" => "a", "draws_source" => "synthetic"]);
        headers=["HX-Request" => "true"]).body)
    @test contains(refreshed, "Imported: posted.json")

    # The lifted form region rebuilds its dose choices for the group's model.
    forms = Dict(m.captures[1] => m.match for m in
                 eachmatch(r"<form hx-(?:get|post)=\"/ops/(\w+)\".*?</form>"s, html))
    simulate = region_attrs(forms["simulate"], "htmxo-semantic-controls")
    rebuilt = String(dispatch(:GET,
        refresh_url(simulate, ["model" => "b", "draws_source" => "synthetic", "dose" => "1"]);
        headers=["HX-Request" => "true"]).body)
    @test region_attrs(rebuilt, "htmxo-semantic-controls") == simulate
    @test contains(rebuilt, "name=\"dose\" value=\"3\"")
    @test !contains(rebuilt, "name=\"dose\" value=\"1\"")
end

@testitem "a browser offers a just-imported value and follows a changed dependency" setup=[ContextRefreshFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        reset_draws!()
        app = DrawPage()
        # The default `:auto` policy: the slow import answers through polls.
        route!(app)
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          async function until(check, label) {
            var end = Date.now() + 20000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function values(name) {
            return Array.from(document.querySelectorAll('input[name="' + name + '"]'))
              .map(input => input.value);
          }
          function choose(name, value) {
            var input = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
            input.checked = true;
            input.dispatchEvent(new Event('change', {bubbles: true}));
          }
          async function upload(filename) {
            var form = document.querySelector('form[hx-post="/ops/import_draws"]');
            var transfer = new DataTransfer();
            transfer.items.add(new File(['{}'], filename, {type: 'application/json'}));
            form.querySelector('input[type="file"]').files = transfer.files;
            form.requestSubmit();
            var result = document.querySelector('[id$="post-import-draws-result"]');
            await until(() => result.textContent.includes('imported:' + filename), filename + ' result');
            await until(() => values('draws_source').includes(filename), filename + ' offered');
          }
          try {
            if (values('draws_source').join() !== 'synthetic') throw new Error('initial: ' + values('draws_source'));
            await upload('fast.json');
            await upload('slow.json');
            choose('model', 'b');
            await until(() => values('draws_source').join() === 'synthetic', 'b draws');
            await until(() => values('dose').join() === '3', 'b doses');
            choose('model', 'a');
            await until(() => values('draws_source').join() === 'synthetic,fast.json,slow.json', 'a draws');
            await until(() => values('dose').join() === '1,2', 'a doses');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        page = repr("text/html", htmx(semantic_app(app.ops), driver;
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
            push!(requests, String(req.target))
            dispatch(req.method, req.target; headers=collect(req.headers),
                     body=HTMXObjects._request_body_bytes(req))
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 90; pollint=0.05) === :ok
                    @test isready(receipt)
                    outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                    @test outcome == "/complete?status=passed"
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            # The slow import answered through polls, yet the group refreshed
            # once per import, and once per `model` change.
            @test any(target -> contains(target, "__htmxo_verb=POST"), requests)
            @test count(target -> contains(target, "__htmxo_context_control="), requests) == 4
            @test count(target -> startswith(target, "/ops/simulate?__htmxo_form=1&") &&
                                  contains(target, "__htmxo_controls=1"), requests) == 2
        finally
            close(server)
        end
    end
end
