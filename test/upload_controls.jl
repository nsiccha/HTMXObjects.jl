using TestItemRunner

@testmodule UploadControlFixtures begin
    using HTMXObjects
    export UploadHost, UploadLeaf, UploadQuery, multipart_body

    @htmx struct UploadLeaf
        @options cohort = (:north, :south)
        cohort::Symbol
        choices(key::Symbol) = key === :north ? (:n1, :n2) : (:s1, :s2)
        @options dataset = choices(cohort)
        """
        Import draws

        # Arguments
        - `file`: Draws file
        """
        @post import_draws(; dataset::Symbol, file::Upload) =
            h.p("import:$(cohort):$(dataset):$(file.filename):$(String(copy(file.data)))")
        "Import many"
        @post import_many(; files::Vector{Upload}) = h.p("many:" * join(
            ["$(f.filename)=$(String(copy(f.data)))" for f in files], ","))
        "Pick"
        @post pick(; dataset::Symbol) = h.p("pick:$(cohort):$(dataset)")
        "Rename"
        @post rename(; title::String) = h.p("rename:$(title)")
    end
    @htmx struct UploadHost
        @include imports = UploadLeaf(:north)
    end

    @htmx struct UploadQuery
        @get inspect(; file::Upload) = file.filename
    end

    # `parts` are `name => text` fields and `name => (filename, content)` files.
    function multipart_body(parts; boundary="htmxoUploadBoundary")
        io = IOBuffer()
        for (name, value) in parts
            print(io, "--", boundary, "\r\n")
            if value isa Tuple
                print(io, "Content-Disposition: form-data; name=\"", name,
                      "\"; filename=\"", value[1], "\"\r\nContent-Type: text/plain\r\n\r\n",
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

@testitem "Upload arguments render file inputs on multipart forms" setup=[UploadControlFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    app = UploadHost()
    html = repr("text/html", semantic_app(app))
    forms = Dict(m.captures[1] => m.match for m in
                 eachmatch(r"<form hx-post=\"/imports/(\w+)\".*?</form>"s, html))
    @test Set(keys(forms)) == Set(["import_draws", "import_many", "pick", "rename"])
    # A single file is a required, labelled file input; several are `multiple`.
    @test contains(forms["import_draws"],
                   "<label>Draws file<input type=\"file\" name=\"file\" required=\"true\"></label>")
    @test occursin(r"<input type=\"file\" name=\"files\" multiple=\"true\" required=\"true\">",
                   forms["import_many"])
    @test !occursin(r"<input (?![^>]*type=\"file\")[^>]*name=\"files?\"", html)
    # Only a form carrying a file submits multipart.
    @test occursin(r"<form [^>]*hx-encoding=\"multipart/form-data\"", forms["import_draws"])
    @test occursin(r"<form [^>]*hx-encoding=\"multipart/form-data\"", forms["import_many"])
    @test !contains(forms["pick"], "hx-encoding")
    @test !contains(forms["rename"], "hx-encoding")
    @test occursin(r"<input [^>]*name=\"title\"", forms["rename"])

    # A caller attribute still wins over the compiler's encoding.
    @test contains(repr("text/html", operation_form(app.imports, :import_many; verb=:POST,
                                                    hx_encoding="custom")),
                   "hx-encoding=\"custom\"")

    # Refused: a GET or DELETE request carries arguments in its URL, so no browser
    # submission can bind a file there (HTTP semantics, snag semantic-app-ove-607afac1).
    @test_throws ArgumentError operation_form(UploadQuery(), :inspect; verb=:GET)

    route!(app; operation_policy=:blocking)
    headers, body = multipart_body(["dataset" => "n2", "file" => ("draws.csv", "a,b\n1,2")])
    posted = dispatch(:POST, "/imports/import_draws"; headers, body)
    @test posted.status == 200
    @test contains(String(posted.body), "import:north:n2:draws.csv:a,b\n1,2")
    headers, body = multipart_body(["files" => ("one.txt", "1"), "files" => ("two.txt", "2")])
    many = dispatch(:POST, "/imports/import_many"; headers, body)
    @test many.status == 200
    @test contains(String(many.body), "many:one.txt=1,two.txt=2")
    headers, body = multipart_body(["files" => ("only.txt", "x")])
    single = dispatch(:POST, "/imports/import_many"; headers, body)
    @test single.status == 200
    @test contains(String(single.body), "many:only.txt=x")
    # A browser sends an empty file input as a part with a blank file name and
    # no bytes: a missing required argument.
    headers, body = multipart_body(["dataset" => "n1", "file" => ("", "")])
    @test dispatch(:POST, "/imports/import_draws"; headers, body).status == 400
end

@testitem "dependent refresh keeps file inputs outside the swapped controls" setup=[UploadControlFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    app = UploadHost()
    html = repr("text/html", operation_form(app.imports, :import_draws; verb=:POST))
    controls = match(r"<div class=\"htmxo-semantic-controls\">.*?</fieldset></div>"s, html)
    @test controls !== nothing
    # The refreshed region holds the dependent controls; the file input follows
    # it, so a refresh cannot clear a chosen file.
    @test !contains(controls.match, "type=\"file\"")
    @test occursin(r"</fieldset></div><label>Draws file<input type=\"file\" name=\"file\" required=\"true\"></label><button",
                   html)
    # The refresh request leaves the file out instead of re-uploading it.
    refresh = match(r"<div [^>]*hx-trigger=\"change\"[^>]*>", html)
    @test refresh !== nothing
    @test contains(refresh.match, "hx-params=\"not file\"")
    @test occursin(r"<form [^>]*hx-encoding=\"multipart/form-data\"", html)
    # A dependent form without a file keeps its refresh unfiltered and urlencoded.
    pick = repr("text/html", operation_form(app.imports, :pick; verb=:POST))
    @test contains(pick, "hx-trigger=\"change\"")
    @test !contains(pick, "hx-params")
    @test !contains(pick, "hx-encoding")

    route!(app; operation_policy=:blocking)
    headers, body = multipart_body(["cohort" => "south", "dataset" => "n1"])
    response = dispatch(:POST, "/imports/import_draws?__htmxo_form=1&__htmxo_controls=1";
        headers=[headers; "HX-Request" => "true"], body)
    @test response.status == 200
    refreshed = String(response.body)
    @test startswith(refreshed, "<div class=\"htmxo-semantic-controls\">")
    @test contains(refreshed, "value=\"s1\"")
    @test !contains(refreshed, "value=\"n1\"")
    @test !contains(refreshed, "type=\"file\"")
    @test !contains(refreshed, "<form")
end

@testitem "a browser submits a chosen file through a generated form and a dependent refresh" setup=[UploadControlFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        app = UploadHost()
        route!(app; operation_policy=:blocking)
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        refresh_bodies = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          async function until(check, label) {
            var end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await new Promise(resolve => setTimeout(resolve, 25));
            }
          }
          function require(value, label) { if (!value) throw new Error(label); }
          function choose(input, files) {
            var transfer = new DataTransfer();
            files.forEach(function(file) { transfer.items.add(file); });
            input.files = transfer.files;
          }
          try {
            var draws = document.querySelector('form[hx-post="/imports/import_draws"]');
            var file = draws.querySelector('input[type="file"][name="file"]');
            choose(file, [new File(['a,b\n1,2'], 'draws.csv', {type: 'text/csv'})]);
            var settled = false;
            draws.addEventListener('htmx:afterSettle', function(event) {
              if (event.target.classList.contains('htmxo-semantic-controls')) settled = true;
            });
            var south = draws.querySelector('[name="cohort"][value="south"]');
            south.checked = true;
            south.dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => settled, 'dependent refresh');
            require(draws.querySelector('[name="dataset"][value="s2"]'), 'refresh did not update choices');
            require(draws.querySelector('input[type="file"][name="file"]') === file, 'refresh replaced the file input');
            require(file.files.length === 1 && file.files[0].name === 'draws.csv', 'refresh cleared the chosen file');
            draws.querySelector('[name="dataset"][value="s2"]').checked = true;
            draws.requestSubmit();
            await until(() => document.getElementById('draws-result').textContent.includes('import:'), 'single upload');
            require(document.getElementById('draws-result').textContent.trim() === 'import:south:s2:draws.csv:a,b\n1,2',
                    'single upload result: ' + document.getElementById('draws-result').textContent);
            var many = document.querySelector('form[hx-post="/imports/import_many"]');
            choose(many.querySelector('input[type="file"][name="files"]'), [
              new File(['1'], 'one.txt', {type: 'text/plain'}),
              new File(['2'], 'two.txt', {type: 'text/plain'})]);
            many.requestSubmit();
            await until(() => document.getElementById('many-result').textContent.includes('many:'), 'multiple upload');
            require(document.getElementById('many-result').textContent.trim() === 'many:one.txt=1,two.txt=2',
                    'multiple upload result: ' + document.getElementById('many-result').textContent);
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        page = repr("text/html", htmx(
            operation_form(app.imports, :import_draws; verb=:POST, target_id="#draws-result"),
            h.div(; id="draws-result"),
            operation_form(app.imports, :import_many; verb=:POST, target_id="#many-result"),
            h.div(; id="many-result"),
            driver;
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
            body = HTMXObjects._request_body_bytes(req)
            contains(req.target, "__htmxo_controls=1") && push!(refresh_bodies, String(copy(body)))
            dispatch(req.method, req.target; headers=collect(req.headers), body)
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    @test isready(receipt)
                    outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                    @test outcome == "/complete?status=passed"
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            # The dependent refresh submitted multipart context without the file.
            @test length(refresh_bodies) == 1
            @test contains(only(refresh_bodies), "name=\"cohort\"")
            @test !contains(only(refresh_bodies), "draws.csv")
        finally
            close(server)
        end
    end
end
