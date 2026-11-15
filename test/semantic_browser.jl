using TestItemRunner

@testmodule BrowserFixtures begin
    using HTMXObjects
    export Lines, StaleCaption, ServerTwin, OpaqueHelp, TOY_JS, browser_region, bound_texts

    # A module in the contract `ReactiveKernels.js_source` emits: positional
    # arguments in `INPUTS` order, a named tuple returned as an object, and a
    # `JuliaError` named by the Julia exception.
    const TOY_JS = """
    export class JuliaError extends Error {
      constructor(type, message) { super(message); this.name = type; }
    }
    export function toy(grid, a, b, lim, z) {
      if (b < 0) throw new JuliaError("DomainError", "toy was called with b = " + b + "; it must be nonnegative");
      const n = grid.length, x = new Array(n), y = new Array(n);
      for (let i = 0; i < n; i++) { x[i] = grid[i]; y[i] = a * grid[i] + b; }
      // `lim` and `z` echo embedded data that JSON alone cannot carry: Inf and -0.0.
      return { x, y, total: a + b, at: [a + b, 2 * a + b], lim, z,
               ok: [lim === Infinity ? 1 : 0, Object.is(z, -0) ? 1 : 0] };
    }
    export const INPUTS = [{ name: "grid", type: "Vector{Float64}" }, { name: "a", type: "Float64" },
      { name: "b", type: "Float64" }, { name: "lim", type: "Float64" }, { name: "z", type: "Float64" }];
    export const OUTPUTS = [{ name: "x" }, { name: "y" }, { name: "total" }, { name: "at" }, { name: "lim" },
      { name: "z" }, { name: "ok" }];
    """

    @htmx struct Lines
        "Slope"
        @param a::Float64 = 2.0
        # A range (a slider with a number field): continuous, never a view per value.
        @options(a) = number_domain(0.0, 10.0)
        "Intercept"
        @param b::Float64 = 1.0
        "Show"
        @param show::Symbol = :line
        @options(show) = [:line, :total]
        "Extra"
        @param extra::Float64 = 0.5
        # Arithmetic of inputs: evaluated in the browser.
        @relevant(extra) = a * b > 10
        grid = [0.0, 1.0, 2.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        __page__(content) = HTMXObjects.htmx(content; title = "Lines", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = show == :line ?
            h.div(h.p("total ", bound(line.total); class = "total"),
                  h.p("second ", bound(line.at[2]); class = "second"),
                  h.p("slope ", bound(a), " extra ", bound(extra; digits = 2)),
                  h.div(; id = "plot1", bound_columns_attrs(bound(line; columns = (:x, :y)))...),
                  h.p(bound(line.lim), " ", bound(line.z), " ", bound(line.ok[1]), bound(line.ok[2]);
                      class = "echo")) :
            h.p("total only ", bound(line.total; digits = 1); class = "total")
    end

    # A caption that shows an input outside `bound`: stale on a static page.
    @htmx struct StaleCaption
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total), " for slope ", string(a))
    end

    # A second result that reads the inputs and computes nothing in the browser.
    @htmx struct ServerTwin
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
        "Twice"
        @get twice() = h.p("twice ", string(2 * (a + b)))
    end

    # A control whose help text the server draws again when another input changes.
    @htmx struct OpaqueHelp
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        @help(b) = string("now ", a)
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total), " ", bound(b))
    end

    browser_region(html) = match(r"<div id=\"[^\"]*-result\"[^>]*data-htmxo-browser=[^>]*>", html)
    bound_texts(html) = [m.captures[1] for m in eachmatch(r"<span data-htmxo-bound=\"[^\"]*\"[^>]*>([^<]*)</span>", html)]
end

@testitem "@browser declares a property the browser computes, bound marks where it shows" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    @test HTMXObjects._browser_properties(Lines) == (:line,)
    @test HTMXObjects._browser_properties(Int) == ()
    m = getproperty(Lines(), HTMXObjects._browser_property(:line))
    @test m isa BrowserModule
    @test m.entry == "toy"
    @test m.inputs == [("grid", "Vector{Float64}"), ("a", "Float64"), ("b", "Float64"),
                       ("lim", "Float64"), ("z", "Float64")]
    # The operation reads its browser property and the inputs it is computed from.
    reads = HTMXObjects._operation_reads(Lines, :result)
    @test reads.complete
    @test issubset([:a, :b, :show, :extra, :line], reads.names)
    @test HTMXObjects._browser_reads(Lines(), :result) == [:line]

    # A @param comes from its control; `bound` names a path.
    # The macro runs where `@htmx` is defined: `using` first, then the struct.
    function err(ex)
        m = Module()
        Core.eval(m, :(using HTMXObjects))
        try
            Core.eval(m, ex)
            nothing
        catch e
            e isa LoadError ? e.error : e
        end
    end
    e1 = err(:(@htmx struct B1
        @param a::Float64 = 1.0
        @browser(a) = browser_module(; source = "", entry = :f)
    end))
    @test e1 isa ArgumentError && occursin("names a `@param`", e1.msg)
    e2 = err(:(@htmx struct B2
        @param a::Float64 = 1.0
        @get r() = h.p(bound(a + 1))
    end))
    @test e2 isa ArgumentError && occursin("`bound` takes a property or `@param` name", e2.msg)
    @test_throws ArgumentError HTMXObjects.bound(1.0)
end

@testitem "browser_module reads its module's entry and arguments" tags=[:unit, :semantic] begin
    using HTMXObjects
    m = browser_module(; source = "export function f(x, y) { return x; }\nexport const INPUTS = [{ name: \"x\", type: \"Float64\" }, { \"name\": \"y\", \"type\": \"Vector{Int64}\" }];", entry = :f)
    @test m.inputs == [("x", "Float64"), ("y", "Vector{Int64}")]
    @test_throws ArgumentError browser_module(; source = "export const INPUTS = [];", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {}", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {} export const INPUTS = []; // </script>", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {}", entry = "not a name")
    mktemp() do path, io
        write(io, "export function g(a) { return a; }\nexport const INPUTS = [{ name: \"a\", type: \"Float64\" }];")
        close(io)
        @test browser_module(path, :g).inputs == [("a", "Float64")]
        @test browser_module(path, :g) === browser_module(path, :g)
    end
    @test_throws ArgumentError browser_module("/no/such/module.mjs", :g)
end

@testitem "a browser result carries its views, bindings, module and bound values" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON
    route!(Lines(); operation_policy = :blocking)
    html = String(HTMXObjects._response_bytes(dispatch(:GET, "/"; headers = ["HX-Request" => "true"])))
    region = browser_region(html)
    @test region !== nothing
    @test occursin("data-htmxo-follow=\"/result\"", region.match)
    # The view at the current values, and one template per value of the finite input.
    @test count("<div class=\"htmxo-browser-view\"", html) == 1
    @test count("<template data-htmxo-variant=", html) == 2
    @test occursin("data-htmxo-number=", html)  # `a`'s range control
    @test bound_texts(html)[1:4] == ["3.0", "5.0", "2.0", "0.5"]
    # The binding: the module's arguments in its order, data embedded once.
    binding = JSON.parse(match(r"<script type=\"application/json\" id=\"[^\"]*\" data-htmxo-browser-binding=\"\">([^<]*)</script>", html).captures[1])
    @test binding["entry"] == "toy"
    @test [i["name"] for i in binding["inputs"]] == ["grid", "a", "b", "lim", "z"]
    # Non-finite data travels tagged (JSON has no Inf); -0.0 keeps its sign.
    @test binding["inputs"][4]["value"] == Dict("\$f" => "Inf")
    @test binding["inputs"][5]["value"] == 0.0 && signbit(binding["inputs"][5]["value"])
    @test binding["inputs"][1]["value"] == [0.0, 1.0, 2.0]
    @test binding["inputs"][2]["param"] == "a" && binding["inputs"][2]["default"] == ["2.0"]
    @test count("data-htmxo-browser-module=\"\"", html) == 1
    @test count("window.__htmxoSemanticBrowser = true", html) == 1
    # Arithmetic relevance is a browser predicate, not a server refresh.
    @test occursin("&quot;cmp&quot;:&quot;gt&quot;", html)
    @test !occursin("data-htmxo-depends", html)
    # The bound columns name the element that shows them.
    @test occursin("data-htmxo-bound-columns=", html)
    # Text peers show the values.
    plain = String(HTMXObjects._response_bytes(dispatch(:GET, "/result?a=3&b=4&plain=1")))
    @test occursin("total 7.0", plain) && occursin("second 10.0", plain) && occursin("slope 3.0", plain)
    @test HTMXObjects._browser_skeleton("<p><span data-htmxo-bound=\"[&quot;a&quot;]\" data-htmxo-kind=\"float\">2.0</span> <div id=\"p\" data-htmxo-bound-columns=\"x\"><div><script>var s = '</div>';</script>1</div></div></p>") ==
          "<p><span data-htmxo-bound=\"[&quot;a&quot;]\" data-htmxo-kind=\"float\"></span> <div id=\"p\" data-htmxo-bound-columns=\"x\"></div></p>"
end

@testitem "bound(…; columns) stays bound inside a plot's data: it is its own Tables.columns" tags=[:unit, :semantic] begin
    using HTMXObjects, Tables
    # Made by the macro's lowering of `bound`, as a view writes it.
    m = Module()
    Core.eval(m, :(using HTMXObjects))
    Core.eval(m, :(@htmx struct Plotted
        grid = [0.0, 1.0, 2.0]
        line = (; x = grid, y = 2 .* grid .+ 1, total = 9.0)
        table = bound(line; columns = (:x, :y))
    end))
    b = Core.eval(m, :(Plotted().table))
    @test b isa HTMXObjects.BoundColumns
    # AlgebraOfGraphics' `data(b)` keeps `Columns(Tables.columns(b))`: that is `b`,
    # so a plotting package reading the layer's data back can mark its element.
    cols = Tables.columns(b)
    @test cols === b
    @test bound_columns_attrs(cols; dataset = "d") == bound_columns_attrs(b; dataset = "d")
    @test occursin("\"path\":[\"line\"]", bound_columns_attrs(cols).data_htmxo_bound_columns)
    # The Tables.jl column interface AlgebraOfGraphics (`getcolumn`,
    # `columnnames`, `rows`) and AlgebraOfVega (`rowtable`) read it through.
    @test Tables.istable(b) && Tables.columnaccess(b)
    @test Tables.columnnames(cols) == (:x, :y)
    @test Tables.getcolumn(cols, :y) == [1.0, 3.0, 5.0]
    @test Tables.getcolumn(cols, 1) == [0.0, 1.0, 2.0]
    @test Tables.schema(b) == Tables.Schema((:x, :y), (Float64, Float64))
    @test Tables.columntable(b) == (x = [0.0, 1.0, 2.0], y = [1.0, 3.0, 5.0])
    @test Tables.rowtable(b) == [(x = 0.0, y = 1.0), (x = 1.0, y = 3.0), (x = 2.0, y = 5.0)]
    @test length(Tables.rows(cols)) == 3
    # Its columns are the chosen outputs only, and an error names the property.
    e = try; Tables.getcolumn(b, :total); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("the table of line has the columns x, y, not `total`", e.msg)
    # The path the lowering passes holds symbols: errors name it too.
    e2 = try; HTMXObjects._bound((:line, :fit), (; x = [1.0]); columns = (:x, :nope)); nothing; catch err; err; end
    @test e2 isa ArgumentError && occursin("line.fit has no output `nope`", e2.msg)
end

@testitem "export_site writes a browser page and names what a static page would show stale" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Lines(); operation_policy = :blocking)
    HTMXObjects.vendorfiles("assets/vendor")
    mktempdir() do dir
        out = export_site(joinpath(dir, "site"); pages = ["/"])
        @test out.files > 0
        index = read(joinpath(dir, "site", "index.html"), String)
        @test occursin("data-htmxo-browser=", index)
        # The result is in the page; no fragment file is written for it.
        fragments = joinpath(dir, "site", "hx")
        @test !any(f -> startswith(f, "result"), isdir(fragments) ? readdir(fragments) : String[])
    end
    for (T, phrase) in ((StaleCaption, "shows `a` outside `bound`"),
                        (ServerTwin, "the result `twice` reads `a`, `b` but computes nothing in the browser"),
                        (OpaqueHelp, "the server draws the control of `b` again when other inputs change (its `@help` text reads other inputs)"))
        route!(T(); operation_policy = :blocking)
        mktempdir() do dir
            e = try
                export_site(joinpath(dir, "site"); pages = ["/"])
                nothing
            catch err
                err
            end
            @test e isa HTMXObjects.StaticSiteIncomplete
            @test e !== nothing && any(((a, why),) -> a == "/" && occursin(phrase, why), e.failed)
        end
    end
end

@testitem "a static browser page follows its inputs offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Lines(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        floats = [1e-5, 1e-4, 0.00012, 1e5, 1e6, 123456.0, 999999.5, 0.1 + 0.2, -0.0, 1.5e17, 5e-324, 2.5e-5, 1.0e15]
        expected_floats = string.(floats)
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const region = () => document.querySelector('[data-htmxo-browser]');
          const shown = () => Array.from(region().querySelectorAll(':scope > .htmxo-browser-view [data-htmxo-bound]:not(.echo *)')).map(e => e.textContent).join('|');
          const echo = () => Array.from(region().querySelectorAll(':scope > .htmxo-browser-view .echo [data-htmxo-bound]')).map(e => e.textContent).join('|');
          const control = name => document.querySelector('input[name="' + name + '"]');
          const relevant = name => !document.querySelector('[data-htmxo-relevant="' + name + '"]').hidden;
          function type(name, value) { const c = control(name); c.value = value; c.dispatchEvent(new Event('change', {bubbles: true})); }
          const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
          try {
            if (sessionStorage.getItem('htmxo-test-browser') !== null) {
              // A shared link: the page applies its address, computing the result.
              await until(() => shown() === '7.0', 'shared link result');
              if (control('a').value !== '3' || !document.querySelector('input[name="show"][value="total"]').checked)
                throw new Error('shared link controls');
              await fetch('/complete?status=passed&search=' + encodeURIComponent(location.search));
              return;
            }
            await until(() => shown() === '3.0|5.0|2.0|0.5', 'first: ' + shown());
            const floats = ($(repr(floats))).map(window.__htmxoJuliaFloat).join(' ');
            if (floats !== $(repr(join(expected_floats, " "))))
              throw new Error('julia floats: ' + floats);
            let columns = null;
            document.addEventListener('htmxo:bound-columns', e => { columns = e.detail; });
            await fetch('/mark?phase=start');
            type('a', '3'); type('b', '4');
            await until(() => shown() === '7.0|10.0|3.0|0.5', 'a=3 b=4: ' + shown());
            // Computed in the browser from embedded Inf and -0.0, both intact.
            if (echo() !== 'Inf|-0.0|1|1') throw new Error('non-finite data: ' + echo());
            if (!columns || columns.columns.y.join(',') !== '4,7,10') throw new Error('columns: ' + JSON.stringify(columns));
            await until(() => relevant('extra'), 'extra applies (a*b > 10)');
            type('extra', '0.125');
            await until(() => shown() === '7.0|10.0|3.0|0.12', 'extra digits: ' + shown());
            choose('show', 'total');
            await until(() => shown() === '7.0', 'total view: ' + shown());
            choose('show', 'line');
            await until(() => shown() === '7.0|10.0|3.0|0.12', 'line view again: ' + shown());
            type('b', '-1');
            await until(() => { const n = region().querySelector('.htmxo-browser-fault'); return n && n.textContent.startsWith('DomainError: toy was called with b = -1'); }, 'fault');
            if (!region().querySelector('.htmxo-browser-view').hasAttribute('data-htmxo-stale')) throw new Error('not stale');
            type('b', '2');
            // a*b = 6: `extra` no longer applies and reads its default, as on the server.
            await until(() => shown() === '5.0|8.0|3.0|0.5' && !region().querySelector('.htmxo-browser-fault'), 'recovered: ' + shown());
            // A slider held down sends `input` events only, which its field
            // relays: the result follows each, the address waits for the release.
            const slider = document.querySelector('label[data-htmxo-number]:has(input[name="a"]) input[data-htmxo-number-slider]');
            slider.value = '100';
            slider.dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => shown() === '4.0|6.0|2.0|0.5', 'held slider: ' + shown());
            if (control('a').value !== '2' || new URLSearchParams(location.search).get('a') !== '3')
              throw new Error('held slider field or address: ' + control('a').value + ' ' + location.search);
            // A number being typed: `input` events of the field alone.
            control('a').value = '4';
            control('a').dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => shown() === '6.0|10.0|4.0|0.5', 'typed: ' + shown());
            slider.dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => new URLSearchParams(location.search).get('a') === '4', 'address on release: ' + location.search);
            await fetch('/mark?phase=end');
            if (new URLSearchParams(location.search).get('b') !== '2') throw new Error('address: ' + location.search);
            sessionStorage.setItem('htmxo-test-browser', '1');
            location.href = location.pathname + '?a=3&b=4&show=total';
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        </script>
        """
        mktempdir() do dir
            site = joinpath(dir, "site")
            export_site(site; pages = ["/"])
            receipt = Channel{String}(1)
            requests = String[]
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2])
            close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose = false) do req
                uri = HTTP.URI(req.target)
                path = uri.path
                push!(requests, req.target)
                if path == "/complete"
                    isready(receipt) || put!(receipt, String(req.target))
                    return HTTP.Response(204)
                end
                path == "/mark" && return HTTP.Response(204)
                file = joinpath(site, lstrip(path == "/" ? "/index.html" : HTTP.URIs.unescapeuri(path), '/'))
                isfile(file) || return HTTP.Response(404)
                body = read(file, String)
                endswith(file, "index.html") && (body = replace(body, "</body>" => driver * "</body>"))
                type = endswith(file, ".js") ? "application/javascript" : endswith(file, ".css") ? "text/css" : "text/html"
                HTTP.Response(200, ["Content-Type" => type], body)
            end
            try
                mktempdir() do profile
                    cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/index.html`
                    browser_log = joinpath(profile, "browser.log")
                    process = run(pipeline(cmd; stdout = devnull, stderr = browser_log); wait = false)
                    try
                        @test timedwait(() -> isready(receipt) || process_exited(process), 90; pollint = 0.05) === :ok
                        outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                        @test HTTP.URIs.unescapeuri(outcome) == "/complete?status=passed&search=?a=3&b=4&show=total"
                    finally
                        process_exited(process) || kill(process)
                        wait(process)
                    end
                end
            finally
                close(server)
            end
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end
