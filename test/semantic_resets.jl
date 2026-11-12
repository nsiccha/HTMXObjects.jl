using TestItemRunner

@testmodule ResetInputFixtures begin
    using HTMXObjects
    export ResetPage

    @htmx struct ResetPage
        placed::Bool = false
        @param output::String = "pk"
        @options(output) = ["pk", "pbmc"]
        @param offset::Int = 0
        @param note::String = "a"
        criterion = output == "pk" ? 10.0 : -50.0
        @param threshold::Float64 = criterion + offset
        @resets(threshold) = (output, offset)
        @param direction::String = output == "pk" ? "above" : "below"
        @options(direction) = ["above", "below"]
        @resets(direction) = (output, choices)
        @param choices::Vector{String} = ["a"]
        @options(choices) = ["a", "true"]
        @resets(choices) = output
        @param constant::Int = 4
        @resets(constant) = output
        @param legacy::Float64 = criterion
        @get profile() = h.p("profile:", output, ":", offset, ":", threshold)
        @get responding() = h.p("responding:", output, ":", offset, ":", threshold,
            ":", direction, ":", constant, ":", legacy, ":", note)
        @get form() = h.div(
            operation_form(__self__, :responding; id="primary", target_id="#answer"),
            operation_form(__self__, :responding; id="independent", target_id="#other-answer"),
            h.div(; id="answer"), h.div(; id="other-answer"))
        @get index() = semantic_app(__self__; presentation=:tabs,
            place=placed ? (threshold=:responding,) : nothing,
            select=entry -> !(entry.name in (:index, :form)))
    end
end

@testitem "reset declarations retain explicit requests and describe refresh dependencies" setup=[ResetInputFixtures, SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    @test HTMXObjects._param_resets(ResetPage) ==
        (threshold=(:output, :offset), direction=(:output, :choices),
         choices=(:output,), constant=(:output,))
    route!(ResetPage(); operation_policy=:blocking)
    page(url) = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    html = page("/?tab=responding&threshold=0.5&direction=below&constant=9&legacy=77")
    field(name) = tag_attrs(html, Regex("<input[^>]*name=\"$name\"[^>]*>"))
    @test field("threshold")["value"] == "0.5"
    @test field("threshold")["data-htmxo-resets"] == "offset output"
    @test !haskey(field("threshold"), "data-htmxo-follows")
    @test field("constant")["data-htmxo-resets"] == "output"
    @test !haskey(field("legacy"), "data-htmxo-resets")
    @test result_text(dispatch(:GET, "/responding?output=pbmc&threshold=0.5&direction=above";
        headers=["HX-Request" => "true"])) == "responding:pbmc:0:0.5:above:4:-50.0:a"
    # Dropping the override, as the browser does, restores following even for
    # a literal default. A subsequent explicit edit is intentional again.
    fresh = page("/?tab=responding&output=pbmc&offset=2&legacy=77")
    threshold = tag_attrs(fresh, r"<input[^>]*name=\"threshold\"[^>]*>")
    @test threshold["value"] == "-48"
    @test haskey(threshold, "data-htmxo-follows")
    @test haskey(tag_attrs(fresh, r"<input[^>]*name=\"constant\"[^>]*>"), "data-htmxo-follows")
    @test contains(page("/form?output=pk&direction=below"), "data-htmxo-resets=\"output\"")
    @test result_text(dispatch(:GET, "/responding?output=pbmc&threshold=12";
        headers=["HX-Request" => "true"])) == "responding:pbmc:0:12.0:below:4:-50.0:a"

    # The declaration names inputs, not arbitrary computed expressions, and
    # resetting a required parameter would have no default to restore.
    for body in (:(begin @param x::Int; @param source=1; @resets(x)=source end),
                 :(begin @param x=1; @resets(x)=missing_input end),
                 :(begin @param x=1; @param source=1; @resets(x)=source+1 end),
                 :(begin @param source=1; @resets(missing_input)=source end))
        ex = Expr(:struct, false, gensym(:BadReset), body)
        @test_throws ArgumentError HTMXObjects._convert_params!(ex)
    end

    # Inline mounted children can reset on a parent input.
    @htmx struct NestedReset
        @param source::Int = 1
        @include child = begin
            @param value::Int = source + 1
            @resets(value) = source
            @get result() = h.p(value)
        end
    end
    @test HTMXObjects._param_resets(typeof(NestedReset().child)) == (value=(:source,),)
end

@testitem "reader overrides reset on changed sources in generated forms" setup=[ResetInputFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires Chrome")
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const field = name => document.querySelector('[name="' + name + '"]:not([type="hidden"])');
          const checked = name => document.querySelector('[name="' + name + '"]:checked').value;
          const shown = () => document.querySelector('[id$="-get-responding-result"]').textContent;
          const address = () => new URLSearchParams(location.search);
          const choose = (name, value) => document.querySelector('[name="' + name + '"][value="' + value + '"]').click();
          const change = c => c.dispatchEvent(new Event('change', {bubbles: true}));
          function type(name, value) {
            const c = field(name); c.value = value;
            c.dispatchEvent(new Event('input', {bubbles: true})); change(c);
          }
          async function until(check, label) {
            const end = Date.now() + 12000;
            while (!check()) {
              if (Date.now() > end) throw new Error(label + ': ' + shown() + ' ' + location.search);
              await sleep(25);
            }
          }
          const result = text => until(() => shown() === text, text);
          try {
            if (sessionStorage.getItem('reset-reload')) {
              await result('responding:pbmc:2:-48.0:below:4:77.0:b');
              if (field('threshold').value !== '-48' || checked('direction') !== 'below')
                throw new Error('reload controls');
              await fetch('/complete?status=passed'); return;
            }
            await result('responding:pk:0:0.5:below:9:77.0:a');
            if (field('threshold').hasAttribute('data-htmxo-follows')) throw new Error('initial override lost');
            // Re-emitting the same source value does not reset anything.
            const before = field('direction');
            change(document.querySelector('[name="output"]:checked'));
            await until(() => field('direction') !== before, 'unchanged source refresh');
            await sleep(50);
            if (field('threshold').value !== '0.5' || checked('direction') !== 'below')
              throw new Error('unchanged source reset');
            type('note', 'b');
            await result('responding:pk:0:0.5:below:9:77.0:b');
            // A new reader edit made while the reset refresh is in flight
            // must survive that response, then reset on the next change.
            choose('output', 'pbmc');
            await sleep(100);
            type('threshold', '11');
            await result('responding:pbmc:0:11.0:below:4:77.0:b');
            await until(() => address().get('threshold') === '11', 'pending edit address');
            choose('output', 'pk');
            await result('responding:pk:0:10.0:above:4:77.0:b');
            choose('output', 'pbmc');
            await result('responding:pbmc:0:-50.0:below:4:77.0:b');
            await until(() => field('threshold').value === '-50' && field('constant').value === '4', 'reset controls');
            await until(() => !address().has('threshold') && !address().has('direction') && !address().has('constant'), 'reset address');
            type('threshold', '12');
            choose('direction', 'above');
            await result('responding:pbmc:0:12.0:above:4:77.0:b');
            // Only threshold names offset; the direction edit must survive.
            type('offset', '2');
            await result('responding:pbmc:2:-48.0:above:4:77.0:b');
            type('threshold', '15');
            await result('responding:pbmc:2:15.0:above:4:77.0:b');
            const beforeEqual = field('threshold');
            type('offset', '02');
            await until(() => field('threshold') !== beforeEqual, 'equal numeric source refresh');
            if (field('threshold').value !== '15') throw new Error('equal numeric source reset');
            choose('output', 'pk');
            await sleep(100);
            choose('output', 'pbmc');
            await result('responding:pbmc:2:-48.0:below:4:77.0:b');
            choose('output', 'pk');
            await result('responding:pk:2:12.0:above:4:77.0:b');
            choose('output', 'pbmc');
            await result('responding:pbmc:2:-48.0:below:4:77.0:b');
            await until(() => !address().has('threshold') && !address().has('direction') &&
              address().get('output') === 'pbmc', 'reload address');
            sessionStorage.setItem('reset-reload', '1'); location.reload();
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        form_driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const form = document.getElementById('primary');
          const other = document.getElementById('independent');
          let settledControls = form.querySelector('.htmxo-semantic-controls');
          form.addEventListener('htmx:afterSettle', function(e) {
            if (e.target.classList.contains('htmxo-semantic-controls')) settledControls = e.target;
          });
          const choose = (name, value) => form.querySelector('[name="' + name + '"][value="' + value + '"]').click();
          const checked = (f, name) => f.querySelector('[name="' + name + '"]:checked').value;
          async function until(check, label) {
            const end = Date.now() + 12000;
            while (!check() || form.querySelector('.htmxo-semantic-controls') !== settledControls) {
              if (Date.now() > end) throw new Error(label + ': ' +
                JSON.stringify(Array.from(new FormData(form))) + ' result=' + document.getElementById('answer').textContent);
              await sleep(25);
            }
          }
          try {
            choose('output', 'pbmc');
            await until(() => checked(form, 'direction') === 'below', 'first reset');
            if (checked(other, 'direction') !== 'above') throw new Error('unrelated form reset');
            choose('direction', 'above');
            choose('choices', 'true');
            await until(() => checked(form, 'direction') === 'below', 'vector changed');
            choose('direction', 'above');
            const unchanged = form.querySelector('[name="direction"]');
            form.querySelector('[name="choices"][value="true"]').dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => form.querySelector('[name="direction"]') !== unchanged, 'vector equal');
            if (checked(form, 'direction') !== 'above') throw new Error('equal vector source reset');
            choose('choices', 'a');
            await until(() => checked(form, 'direction') === 'below', 'vector removed a');
            const emptied = form.querySelector('[name="direction"]');
            choose('choices', 'true');
            await until(() => form.querySelector('[name="direction"]') !== emptied, 'vector emptied');
            if (form.querySelector('[name="choices"]:checked')) throw new Error('empty vector lost');
            const before = form.querySelector('[name="direction"]');
            choose('output', 'pk');
            await until(() => form.querySelector('[name="direction"]') !== before, 'output pk');
            if (checked(form, 'choices') !== 'a') throw new Error('vector default not restored');
            choose('output', 'pbmc');
            await until(() => checked(form, 'direction') === 'below', 'last reset');
            form.querySelector('button[type="submit"]').click();
            await until(() => document.getElementById('answer').textContent ===
              'responding:pbmc:0:-50.0:below:4:77.0:a', 'submitted result');
            if (checked(other, 'direction') !== 'above') throw new Error('unrelated form changed');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        for mode in (:shared, :placed, :standalone)
            placed = mode === :placed
            route!(ResetPage(; placed); operation_policy=:blocking)
            receipt = Channel{String}(1)
            asked = String[]
            render(target) = repr("text/html", htmx(Raw(String(dispatch(:GET, target;
                headers=["HX-Request" => "true"]).body)), mode === :standalone ? form_driver : driver;
                assets="/test-assets", sse_version=nothing, ws_version=nothing,
                preload_version=nothing, pico_version=nothing,
                feedback=false, compose=false, overlay=false))
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2]); close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
                path = HTTP.URI(req.target).path
                path in ("/", "/form") && return HTTP.Response(200, ["Content-Type" => "text/html"], render(req.target))
                haskey(assets, path) && return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
                path == "/favicon.ico" && return HTTP.Response(204)
                if path == "/complete"
                    isready(receipt) || put!(receipt, String(req.target))
                    return HTTP.Response(204)
                end
                push!(asked, String(req.target))
                # Outlast the results debounce: neither requests nor the URL
                # may retain a discarded override while controls are pending.
                occursin("__htmxo_form=", req.target) && sleep(0.65)
                dispatch(req.method, req.target; headers=collect(req.headers),
                    body=HTMXObjects._request_body_bytes(req))
            end
            try
                mktempdir() do profile
                    target = mode === :standalone ? "/form?threshold=0.5&direction=above&constant=9&legacy=77" :
                        "/?tab=responding&threshold=0.5&direction=below&constant=9&legacy=77"
                    url = "http://127.0.0.1:$port$target"
                    cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $url`
                    log = joinpath(profile, "browser.log")
                    process = run(pipeline(cmd; stdout=devnull, stderr=log); wait=false)
                    try
                        @test timedwait(() -> isready(receipt) || process_exited(process), 100; pollint=0.05) === :ok
                        outcome = isready(receipt) ? take!(receipt) : read(log, String)
                        @test outcome == "/complete?status=passed"
                        @test !any(url -> contains(url, "output=pbmc") &&
                            contains(url, "threshold=0.5"), asked)
                        mode === :standalone || @test any(contains("threshold=12"), asked)
                        @test !any(url -> contains(url, "output=pk") &&
                            contains(url, "threshold=15"), asked)
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
end
