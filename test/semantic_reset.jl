using TestItemRunner

@testmodule SemanticResetFixtures begin
    using HTMXObjects
    export OneTab, GermanTabs, ConstantPage, reset_button, form_ids

    # Inputs read by one operation only: no sidebar, so its tab draws the Reset.
    @htmx struct OneTab
        "Attenuation"
        @param attenuation::Float64 = 0.004
        @options(attenuation) = number_domain(0.001, 0.015; log=true, digits=4)
        "Density"
        @param density::Float64 = 300.0
        "Reading"
        @get reading() = h.p("reading:", attenuation, ":", density; class="result")
        @get index() = semantic_app(__self__; presentation=:tabs,
            select=entry -> entry.name !== :index)
    end

    # A default named by a constant follows it, with no control to draw again:
    # only the page keeps it following after a Reset.
    const RESET_LEVEL = 3
    @htmx struct ConstantPage
        "Level"
        @param level::Int = RESET_LEVEL
        "Mode"
        @param mode::String = "a"
        @options(mode) = ["a", "b"]
        "View"
        @get view() = h.p("view:", level, ":", mode; class="result")
        @get index() = semantic_app(__self__; presentation=:tabs,
            select=entry -> entry.name !== :index)
    end

    @htmx struct GermanTabs
        __error_texts__ = error_texts(:de)
        "Dosis"
        @param dose::Float64 = 1.0
        "Verlauf"
        @get course() = h.p("course:", dose)
        "Zusammenfassung"
        @get summary() = h.p("summary:", dose)
    end

    # The attributes of the page's Reset button, its text, and where it starts.
    function reset_button(html)
        m = match(r"<button([^>]*data-htmxo-reset=[^>]*)>([^<]*)</button>", html)
        m === nothing && return nothing
        attrs = Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&", "&quot;" => "\"")
                     for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.captures[1]))
        (; attrs, text=m.captures[2], offset=m.offset)
    end
    # The ids of the page's forms that carry the attribute `attr`.
    form_ids(html, attr="data-htmxo-address") =
        Set(m.captures[1] for m in eachmatch(Regex("<form id=\"([^\"]*)\"[^>]*$attr="), html))
end

@testitem "a tabs page's Reset names every form of inputs and ends the sidebar" setup=[SemanticPageFixtures, SemanticResetFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(SimPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    button = reset_button(html)
    @test button !== nothing
    @test button.text == "Reset"
    @test button.attrs["type"] == "button"
    @test button.attrs["class"] == "outline secondary htmxo-semantic-reset"
    # The sidebar and each tab whose inputs the address keeps; a mutation's
    # own inputs are not page state.
    named = Set(lstrip.(split(button.attrs["data-htmxo-reset"]), '#'))
    @test named == form_ids(html)
    @test length(named) == 3
    @test !any(id -> occursin("upload", id), named)
    # No input follows a computed default here.
    @test !haskey(button.attrs, "data-htmxo-reset-follows")
    # It ends the sidebar, after its form, once.
    @test count("data-htmxo-reset=", html) == 1
    @test occursin(r"<aside>\s*<form id=\"htmxo-semantic-context-[^\"]*\" class=\"htmxo-semantic-context htmxo-semantic-sidebar\".*?</form>\s*<button[^>]*data-htmxo-reset="s, html)
    @test !occursin("data-htmxo-reset", tab_of(html, "timecourse"))

    # `reset=false` draws none; the address still keeps the inputs.
    app = SimPage()
    off = repr("text/html", semantic_app(app; presentation=:tabs, reset=false,
        select=entry -> entry.name !== :index))
    @test reset_button(off) === nothing
    @test !occursin("data-htmxo-reset", off)
    @test form_ids(off) == form_ids(html)

    # A page whose address keeps no input still names the defaults for its Reset.
    stateless = repr("text/html", semantic_app(app; presentation=:tabs, url_state=false,
        select=entry -> entry.name !== :index))
    @test !occursin("data-htmxo-address", stateless)
    @test form_ids(stateless, "data-htmxo-defaults") == form_ids(html)
    @test tag_attrs(sidebar_of(stateless), r"<form[^>]*>")["data-htmxo-defaults"] ==
          tag_attrs(sidebar_of(html), r"<form[^>]*>")["data-htmxo-address"]
    @test Set(lstrip.(split(reset_button(stateless).attrs["data-htmxo-reset"]), '#')) == form_ids(html)
    # Without either, a page carries neither.
    bare = repr("text/html", semantic_app(app; presentation=:tabs, url_state=false, reset=false,
        select=entry -> entry.name !== :index))
    @test !occursin("data-htmxo-defaults", bare) && !occursin("data-htmxo-reset", bare)

    # `values=` is what the Reset returns to, as the address leaves it out.
    valued = repr("text/html", semantic_app(app; presentation=:tabs,
        values=(; threshold=-40.0), select=entry -> entry.name !== :index))
    @test tag_attrs(tab_of(valued, "fraction"), r"<form[^>]*>")["data-htmxo-address"] == """{"threshold":["-40.0"]}"""
    @test reset_button(valued) !== nothing

    # refused: the stacked surface has no page of inputs to reset.
    @test_throws "reset= draws the Reset button of presentation=:tabs" semantic_app(app; reset=true)
    @test_throws "reset must be true or false" semantic_app(app; presentation=:tabs, reset=1,
        select=entry -> entry.name !== :index)
end

@testitem "the Reset names the inputs that follow their defaults again" setup=[SemanticPageFixtures, SemanticResetFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(CriterionPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/?tab=responding"; headers=["HX-Request" => "true"]).body)
    button = reset_button(html)
    @test button.attrs["data-htmxo-reset-follows"] == "direction response_quantity threshold"
    # Opened on a value the reader set, the page still resets it to following.
    opened = String(dispatch(:GET, "/?tab=responding&output=pbmc&threshold=-10";
        headers=["HX-Request" => "true"]).body)
    @test reset_button(opened).attrs == button.attrs

    # A computed default that `values=` replaces has a value to return to.
    valued = repr("text/html", semantic_app(CriterionPage(); presentation=:tabs,
        values=(; threshold=-20.0), select=entry -> entry.name !== :index))
    @test reset_button(valued).attrs["data-htmxo-reset-follows"] == "direction response_quantity"
end

@testitem "a page without a sidebar draws its Reset under each tab's inputs" setup=[SemanticPageFixtures, SemanticResetFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(OneTab(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    @test !occursin("htmxo-semantic-sidebar", html)
    tab = tab_of(html, "reading")
    button = reset_button(tab)
    @test button !== nothing
    @test Set(lstrip.(split(button.attrs["data-htmxo-reset"]), '#')) == form_ids(html)
    # Under the tab's inputs, before its result.
    @test occursin(r"<form id=\"[^\"]*-inputs\"[^>]*>.*?</form>\s*<button[^>]*data-htmxo-reset=[^>]*>Reset</button>\s*<div id=\"[^\"]*-result\""s, tab)

    # A custom layout and tab renderer get the button to place.
    seen = Ref{Any}(nothing)
    entries = Any[]
    obj = OneTab()
    semantic_app(obj; presentation=:tabs, select=entry -> entry.name !== :index,
        render_operation=entry -> (push!(entries, entry); h.div(entry.form, entry.result)),
        layout=parts -> (seen[] = parts; h.div(parts.tabs...)))
    @test seen[].reset isa HTMXObjects.Node
    @test occursin("data-htmxo-reset", repr("text/html", seen[].reset))
    @test length(entries) == 1 && entries[1].reset === seen[].reset
    # With a sidebar the tabs draw none: the sidebar holds it.
    sim = Any[]
    semantic_app(SimPage(); presentation=:tabs, select=entry -> entry.name !== :index,
        render_operation=entry -> (push!(sim, entry); h.div(entry.result)))
    @test all(entry -> entry.reset === nothing, sim)

    # Its words are the page's `__error_texts__`.
    @test error_texts().reset_inputs == "Reset"
    @test error_texts(:de).reset_inputs == "Zurücksetzen"
    @test error_texts(:de; reset_inputs="Alles zurücksetzen").reset_inputs == "Alles zurücksetzen"
    german = repr("text/html", semantic_app(GermanTabs(); presentation=:tabs))
    @test reset_button(german).text == "Zurücksetzen"
end

@testitem "a static page's Reset returns every input to its default offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Lines(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        driver = raw"""
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const region = () => document.querySelector('[data-htmxo-browser]');
          const shown = () => Array.from(region().querySelectorAll(':scope > .htmxo-browser-view [data-htmxo-bound]:not(.echo *)')).map(e => e.textContent).join('|');
          const control = name => document.querySelector('input[name="' + name + '"]');
          const relevant = name => !document.querySelector('[data-htmxo-relevant="' + name + '"]').hidden;
          function type(name, value) { const c = control(name); c.value = value; c.dispatchEvent(new Event('change', {bubbles: true})); }
          const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
          const kept = () => ['a', 'b', 'show', 'extra'].filter(n => new URLSearchParams(location.search).has(n)).join(',');
          try {
            await until(() => shown() === '3|5|2|0.50', 'first: ' + shown());
            const slider = document.querySelector('input[data-htmxo-number-slider]');
            const start = slider.value;
            await fetch('/mark?phase=start');
            type('a', '3'); type('b', '4');
            await until(() => shown() === '7|10|3|0.50', 'a=3 b=4: ' + shown());
            await until(() => relevant('extra'), 'extra applies (a*b > 10)');
            type('extra', '0.125');
            // `bound(extra; digits = 2)`: exactly two decimals, halves away from zero.
            await until(() => shown() === '7|10|3|0.13', 'extra: ' + shown());
            choose('show', 'total');
            await until(() => shown() === '7.0', 'total view: ' + shown());
            await until(() => kept() === 'a,b,show,extra', 'address before: ' + location.search);
            if (slider.value === start) throw new Error('slider did not move');
            const reset = document.querySelector('button[data-htmxo-reset]');
            if (!reset || reset.textContent !== 'Reset' || !reset.closest('.htmxo-semantic-tab'))
              throw new Error('no Reset under the tab: ' + (reset && reset.outerHTML));
            reset.click();
            await until(() => shown() === '3|5|2|0.50', 'reset result: ' + shown());
            if (Number(control('a').value) !== 2 || Number(control('b').value) !== 1 || Number(control('extra').value) !== 0.5)
              throw new Error('reset values: ' + ['a', 'b', 'extra'].map(n => control(n).value).join(','));
            if (!document.querySelector('input[name="show"][value="line"]').checked) throw new Error('show not reset');
            if (slider.value !== start) throw new Error('slider ' + slider.value + ' != ' + start);
            await until(() => !relevant('extra'), 'extra no longer applies');
            await until(() => kept() === '', 'address after: ' + location.search);
            // A second Reset with nothing to reset changes nothing.
            reset.click();
            await sleep(400);
            if (shown() !== '3|5|2|0.50' || kept() !== '') throw new Error('second reset: ' + shown());
            await fetch('/mark?phase=end');
            await fetch('/complete?status=passed');
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
                        @test HTTP.URIs.unescapeuri(outcome) == "/complete?status=passed"
                    finally
                        process_exited(process) || kill(process)
                        wait(process)
                    end
                end
            finally
                close(server)
            end
            # Between the marks the page reset and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end

@testitem "the Reset returns computed defaults to following their inputs in a browser" setup=[SemanticPageFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(CriterionPage(); operation_policy=:blocking)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label + ' at ' + location.search +
                ' showing ' + shown());
              await sleep(25);
            }
          }
          const shown = () => document.querySelector('[id$="-get-responding-result"]').textContent;
          const address = () => Array.from(new URLSearchParams(location.search))
            .map(p => p.join('=')).sort().join('&');
          const checked = name => document.querySelector('input[name="' + name + '"]:checked').value;
          const field = name => document.querySelector('input[name="' + name + '"]');
          const follows = name => field(name).hasAttribute('data-htmxo-follows');
          const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
          const reset = () => document.querySelector('button[data-htmxo-reset]').click();
          function type(name, value) {
            const input = field(name);
            input.value = value;
            input.dispatchEvent(new Event('input', {bubbles: true}));
            input.dispatchEvent(new Event('change', {bubbles: true}));
          }
          try {
            await until(() => shown() === 'responding:pk:cmin:above:-50.0', 'first');
            // Only a computed default was set: the server draws it again.
            type('threshold', '-10');
            await until(() => shown() === 'responding:pk:cmin:above:-10.0', 'typed');
            await until(() => address() === 'tab=responding&threshold=-10', 'typed address');
            reset();
            await until(() => shown() === 'responding:pk:cmin:above:-50.0', 'reset threshold');
            await until(() => field('threshold').value === '-50' && follows('threshold'), 'threshold follows');
            await until(() => address() === 'tab=responding', 'reset address');
            // Its source and explicit choices change as well.
            choose('output', 'pbmc');
            await until(() => shown() === 'responding:pbmc:min_change:below:-30.0', 'pbmc');
            type('threshold', '-10');
            choose('direction', 'above');
            await until(() => shown() === 'responding:pbmc:min_change:above:-10.0', 'pbmc set');
            await until(() => address() === 'direction=above&output=pbmc&tab=responding&threshold=-10', 'pbmc address');
            reset();
            await until(() => shown() === 'responding:pk:cmin:above:-50.0', 'reset all');
            await until(() => checked('output') === 'pk' && checked('direction') === 'above' &&
                              checked('response_quantity') === 'cmin' && field('threshold').value === '-50',
                        'reset controls');
            await until(() => follows('threshold') && follows('direction') && follows('response_quantity'), 'all follow');
            await until(() => address() === 'tab=responding', 'reset all address');
            // Following again: the next output change carries them along.
            choose('output', 'pbmc');
            await until(() => shown() === 'responding:pbmc:min_change:below:-30.0', 'follows after reset');
            await fetch('/complete?status=passed&search=' + encodeURIComponent(address()));
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        render(target) = repr("text/html", htmx(Raw(String(dispatch(:GET, target;
                headers=["HX-Request" => "true"]).body)), driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, pico_version=nothing,
            feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], render(req.target))
            haskey(assets, path) &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            # A slow controls refresh: results must wait for it.
            occursin("__htmxo_form=", req.target) && sleep(0.3)
            dispatch(req.method, req.target; headers=collect(req.headers),
                     body=HTMXObjects._request_body_bytes(req))
        end
        try
            mktempdir() do profile
                url = "http://127.0.0.1:$port/?tab=responding"
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $url`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 90; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                    @test HTTP.URIs.unescapeuri(outcome) ==
                          "/complete?status=passed&search=output=pbmc&tab=responding"
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

@testitem "the Reset returns a list of records to its one default card in a browser" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        route!(ScenarioApp(); operation_policy=:blocking)
        outcome = browser_outcome(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const result = () => Array.from(document.querySelectorAll('[data-htmxo-follow="/timecourse"] li')).map(li => li.textContent).join('|');
          const cards = () => Array.from(document.querySelectorAll('.htmxo-record'));
          const field = (i, f) => document.querySelector('[name="scenarios.' + i + '.' + f + '"]');
          const change = el => el.dispatchEvent(new Event('change', {bubbles: true}));
          const scenarioKeys = () => Array.from(new URLSearchParams(location.search).keys()).filter(k => k.startsWith('scenarios.')).join(',');
          const first = 'Scenario 1=100% q 24 x 14/false/50.0/70.0';
          const out = {};
          try {
            await until(() => result() === first, 'first result');
            document.querySelector('[data-htmxo-record-action="add"]').click();
            await sleep(20);
            field(2, 'age').value = '30'; change(field(2, 'age'));
            field(1, 'weight').value = '80'; change(field(1, 'weight'));
            const label = field(1, 'label'); label.value = 'Baseline'; change(label);
            cards()[0].querySelector('.htmxo-record-on input').click();
            await until(() => result() === 'Scenario 2=100% q 24 x 14/false/30.0/70.0', 'changed');
            await until(() => scenarioKeys() !== '', 'kept');
            cards()[1].querySelector('[data-htmxo-record-action="fold"]').click();
            document.querySelector('button[data-htmxo-reset]').click();
            await until(() => result() === first, 'reset result: ' + result());
            await until(() => scenarioKeys() === '', 'reset address: ' + location.search);
            out.cards = cards().length === 1;
            out.label = field(1, 'label').value === 'Scenario 1';
            out.on = cards()[0].querySelector('.htmxo-record-on input').checked;
            out.fields = field(1, 'weight').value === '70.0' && field(1, 'age').value === '50.0';
            out.open = !cards()[0].hasAttribute('data-htmxo-folded');
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """)
        @test get(outcome, "error", "") == ""
        for key in ("cards", "label", "on", "fields", "open")
            @test (key => get(outcome, key, "missing")) == (key => "true")
        end
    end
end

@testitem "preset cards keep automatic names and Reset restores the declared series" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        route!(PresetApp(); operation_policy=:blocking)
        outcome = browser_outcome(raw"""
        window.addEventListener('load', async function() {
          const cards = () => Array.from(document.querySelectorAll('.htmxo-record'));
          const input = (i, selector) => cards()[i].querySelector(selector);
          const names = () => cards().map(c => {
            const label = c.querySelector('.htmxo-record-label');
            return label.value || label.placeholder;
          }).join('|');
          const result = () => document.querySelector('[data-htmxo-follow="/series"]').textContent.trim();
          async function until(f, expected) {
            const end = Date.now() + 10000;
            while (f() !== expected) {
              if (Date.now() > end) throw Error('expected ' + expected + ', saw ' + f());
              await new Promise(r => setTimeout(r, 25));
            }
          }
          function rename(i, value) {
            const label = input(i, '.htmxo-record-label');
            label.value = value;
            label.dispatchEvent(new Event('change', {bubbles:true}));
          }
          try {
            await until(names, 'Shared');
            await until(result, 'Shared=70.0');
            document.querySelector('[data-htmxo-reset]').click();
            await until(names, 'Baseline|Twice daily|Daily');
            await until(result, 'Baseline=100.0|Daily=100.0');
            const colours = () => Array.from(document.querySelectorAll('.htmxo-record-on input:checked'),
              box => getComputedStyle(box).accentColor).join('|');
            document.documentElement.style.setProperty('--aov-category', 'rgb(20, 40, 60), #884422, #753');
            await until(colours, 'rgb(20, 40, 60)|rgb(136, 68, 34)');
            input(1, '.htmxo-record-on input').click();
            await until(colours, 'rgb(20, 40, 60)|rgb(136, 68, 34)|rgb(119, 85, 51)');
            input(1, '[data-htmxo-record-action="duplicate"]').click();
            await until(result, 'Baseline=100.0|Twice daily=50.0|Twice daily (2)=50.0|Daily=100.0');
            rename(2, 'Manual');
            input(2, 'input[type=radio][value=daily]').click();
            await until(result, 'Baseline=100.0|Twice daily=50.0|Manual=50.0|Daily=100.0');
            rename(2, '');
            await until(names, 'Baseline|Twice daily|Daily|Daily (2)');
            await until(result, 'Baseline=100.0|Twice daily=50.0|Daily=50.0|Daily (2)=100.0');
            const shared = new URLSearchParams(location.search);
            if (shared.get('scenarios.3.label') !== '' || shared.get('scenarios.3.regimen') !== 'daily')
              throw Error('automatic name was pinned in ' + location.search);
            input(0, '[data-htmxo-record-action="remove"]').click();
            document.querySelector('[data-htmxo-record-action="add"]').click();
            document.querySelector('[data-htmxo-reset]').click();
            await until(names, 'Baseline|Twice daily|Daily');
            await until(result, 'Baseline=100.0|Daily=100.0');
            await until(() => new URLSearchParams(location.search).has('scenarios.1.label'), false);
            fetch('/complete?passed=true');
          } catch (e) { fetch('/complete?' + new URLSearchParams({error:String(e)})); }
        });
        """; path="/?scenarios.1.label=Shared&scenarios.1.dose=70")
        @test outcome == Dict("passed" => "true")
    end
end

@testitem "a static Records form opens a partial shared link and resets to its presets" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        route!(PresetApp(); operation_policy=:blocking)
        # Serve the default HTML at a different address, as a static host does.
        outcome = browser_outcome(raw"""
        window.addEventListener('load', function() {
          const read = () => Array.from(document.querySelectorAll('.htmxo-record'), c => {
            const label = c.querySelector('.htmxo-record-label');
            return [label.value || label.placeholder, c.querySelector('[type=number]').valueAsNumber,
              c.querySelector('.htmxo-record-on input').checked].join('/');
          }).join('|');
          const link = read();
          document.querySelector('button[data-htmxo-reset]').click();
          fetch('/complete?' + new URLSearchParams({link, reset:read()}));
        });
        """; address="/?scenarios.1.regimen=bid&scenarios.2.label=Older&scenarios.2.on=false")
        @test outcome == Dict("link"=>"Twice daily/100/true|Older/100/false",
                              "reset"=>"Baseline/100/true|Twice daily/50/false|Daily/100/true")
    end
end

@testitem "the Reset keeps a constant default following in a browser" setup=[SemanticPageFixtures, RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        # `target` and `direction` follow defaults named by constants, so the
        # Reset gives them a value and announces it; `threshold` follows `base`.
        route!(IdentifierPage(); operation_policy=:blocking)
        outcome = browser_outcome(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label + ' showing ' + shown()); await sleep(25); }
          }
          const shown = () => document.querySelector('[id$="-get-responding-result"]').textContent;
          const field = name => document.querySelector('input[name="' + name + '"]');
          const follows = name => Array.from(document.querySelectorAll('input[name="' + name + '"]')).every(c => c.hasAttribute('data-htmxo-follows'));
          const checked = name => document.querySelector('input[name="' + name + '"]:checked').value;
          const kept = () => Array.from(new URLSearchParams(location.search).keys()).filter(k => k !== 'tab').sort().join(',');
          function type(name, value) {
            const input = field(name);
            input.value = value;
            input.dispatchEvent(new Event('input', {bubbles: true}));
            input.dispatchEvent(new Event('change', {bubbles: true}));
          }
          const out = {};
          try {
            await until(() => shown() === 'responding:-50.0:below:-25.0:above', 'first');
            type('target', '-10');
            document.querySelector('input[name="direction"][value="above"]').click();
            type('threshold', '-5');
            await until(() => shown() === 'responding:-10.0:above:-5.0:above', 'set');
            await until(() => kept() === 'direction,target,threshold', 'set address');
            document.querySelector('button[data-htmxo-reset]').click();
            await until(() => shown() === 'responding:-50.0:below:-25.0:above', 'reset');
            await until(() => field('threshold').value === '-25', 'threshold drawn again');
            out.values = Number(field('target').value) === -50 && checked('direction') === 'below';
            out.follow = follows('target') && follows('direction') && follows('threshold');
            out.literal = !follows('literal');
            await until(() => kept() === '', 'reset address');
            out.address = true;
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """; path="/?tab=responding")
        @test get(outcome, "error", "") == ""
        for key in ("values", "follow", "literal", "address")
            @test (key => get(outcome, key, "missing")) == (key => "true")
        end
    end
end

@testitem "the Reset keeps a default named by a constant following, with nothing drawn again, in a browser" setup=[SemanticResetFixtures, RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        route!(ConstantPage(); operation_policy=:blocking)
        html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
        @test reset_button(html).attrs["data-htmxo-reset-follows"] == "level"
        outcome = browser_outcome(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label + ' showing ' + shown()); await sleep(25); }
          }
          const shown = () => document.querySelector('[id$="-get-view-result"]').textContent;
          const level = () => document.querySelector('input[name="level"]');
          const kept = () => Array.from(new URLSearchParams(location.search).keys()).sort().join(',');
          const out = {};
          try {
            await until(() => shown() === 'view:3:a', 'first');
            out.before = level().hasAttribute('data-htmxo-follows');
            level().value = '7';
            level().dispatchEvent(new Event('change', {bubbles: true}));
            document.querySelector('input[name="mode"][value="b"]').click();
            await until(() => shown() === 'view:7:b', 'set');
            await until(() => kept() === 'level,mode', 'set address');
            const asked = [];
            document.addEventListener('htmx:configRequest', e => asked.push(e.detail.path));
            document.querySelector('button[data-htmxo-reset]').click();
            await until(() => shown() === 'view:3:a', 'reset');
            await until(() => kept() === '', 'reset address');
            await sleep(400);
            out.value = level().value === '3';
            out.follows = level().hasAttribute('data-htmxo-follows');
            // Nothing drew the control again: the page kept it following.
            out.redrawn = asked.some(p => p.indexOf('__htmxo_form=') >= 0);
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """)
        @test get(outcome, "error", "") == ""
        @test get(outcome, "before", "missing") == "true"
        @test get(outcome, "value", "missing") == "true"
        @test get(outcome, "follows", "missing") == "true"
        @test get(outcome, "redrawn", "missing") == "false"
    end
end
