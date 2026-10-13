using TestItemRunner

@testmodule NumberControlFixtures begin
    using HTMXObjects
    export MeasureHost, number_input

    @htmx struct MeasureOperations
        """
        Measure

        # Arguments
        - `seconds`: Seconds per measurement
        """
        @post measure(; seconds::Float64=1.0, points::Int=4, ratio::Float32=0.5f0) =
            string("measure:", seconds, ":", points, ":", ratio)
        "Scale"
        @post scale(; factor::Float64) = string("scale:", factor)
    end
    @htmx struct ToleranceOperations
        tolerance::Float64
        "Check"
        @get check() = string("check:", tolerance)
    end
    @htmx struct MeasureHost
        @include runs = MeasureOperations()
        @include checks = ToleranceOperations(0.25)
    end

    # The `<input>` tag a generated form renders for the argument `name`.
    number_input(html, name) = match(Regex("<input[^>]*\\bname=\"$(name)\"[^>]*>"), html).match
end

@testitem "number arguments accept the values of their declared type" setup=[NumberControlFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    app = MeasureHost()
    html = repr("text/html", semantic_app(app))
    # A float argument, a float without a default, and a float fixed field all
    # accept any value; without a step the browser only accepts whole steps.
    for name in ("seconds", "ratio", "factor", "tolerance")
        input = number_input(html, name)
        @test contains(input, "type=\"number\"")
        @test contains(input, "step=\"any\"")
    end
    @test contains(number_input(html, "seconds"), "value=\"1.0\"")
    @test contains(number_input(html, "factor"), "required=\"true\"")
    # An integer keeps the browser's whole-number step.
    @test contains(number_input(html, "points"), "type=\"number\"")
    @test !contains(number_input(html, "points"), "step=")
    @test HTMXObjects._number_step(Int) === nothing
    @test HTMXObjects._number_step(UInt8) === nothing
    @test HTMXObjects._number_step(Rational{Int}) == "any"

    route!(app; operation_policy=:blocking)
    form = ["Content-Type" => "application/x-www-form-urlencoded"]
    measured = dispatch(:POST, "/runs/measure?plain=1"; headers=form,
        body="seconds=0.2&points=3&ratio=0.125")
    @test measured.status == 200
    @test String(measured.body) == "measure:0.2:3:0.125"
    checked = dispatch(:GET, "/checks/check?plain=1&tolerance=0.125")
    @test checked.status == 200
    @test String(checked.body) == "check:0.125"
end

@testitem "a browser submits a fractional value for a float argument" setup=[NumberControlFixtures, ChromeDump] tags=[:browser, :semantic] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        app = MeasureHost()
        route!(app; operation_policy=:blocking)
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const valid = (input, value) => { input.value = value; return input.checkValidity(); };
            const form = document.querySelector('form[hx-post="/runs/measure"]');
            const field = name => form.querySelector('input[name="' + name + '"]');
            // Positive control: an unstepped number input rejects 0.2.
            check('control-rejects-fraction', !valid(document.getElementById('control'), '0.2'));
            check('seconds-accepts-fraction', valid(field('seconds'), '0.2'));
            check('ratio-accepts-fraction', valid(field('ratio'), '0.125'));
            check('points-rejects-fraction', !valid(field('points'), '2.5'));
            check('points-accepts-integer', valid(field('points'), '3'));
            form.requestSubmit();
            const result = document.getElementById('result');
            const end = Date.now() + 10000;
            while (!result.textContent.includes('measure:') && Date.now() < end)
                await new Promise(r => setTimeout(r, 25));
            check('submitted', result.textContent.trim() === 'measure:0.2:3:0.125');
            const out = document.createElement('pre'); out.id = 'checks';
            out.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(out);
        });
        """))
        page = repr("text/html", htmx(
            operation_form(app.runs, :measure; verb=:POST, target_id="#result"),
            h.div(; id="result"),
            h.input(; id="control", type="number", value="1.0"),
            driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, pico_version=nothing,
            feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            dispatch(req.method, req.target; headers=collect(req.headers),
                body=HTMXObjects._request_body_bytes(req))
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 6
            end
        finally
            close(server)
        end
    end
end
