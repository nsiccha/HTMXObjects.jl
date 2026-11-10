using TestItemRunner

# A list of records (`@param name::Records`): typed records for routes, a card
# per record on an app page (todo `1w1bnkx`, for Bruno's web-sim; decision
# `1a5bx6n`).

@testmodule RecordsFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export ScenarioApp, sidebar_of, attrs_of, body_of

    @htmx struct ScenarioApp
        "Prediction basis"
        @param basis::String = "typical"
        @options(basis) = option_domain(["typical" => "Typical subject", "cohort" => "New subjects"])
        """
        Regimen

        Doses as `percent% q hours x count`.
        """
        @param regimen::String = "100% q 24 x 14"
        "Sex"
        @param male::Bool = false
        @options(male) = option_domain([false => "Female", true => "Male"])
        @relevant(male) = basis == "typical"
        "Age (years)"
        @param age::Float64 = 50.0
        @relevant(age) = basis == "typical"
        "Weight (kg)"
        @param weight::Float64 = 70.0
        "Scenarios"
        @param scenarios::Records = Records(:regimen, :male, :age, :weight; label="Scenario")
        spec = string(regimen, "/", male, "/", age, "/", weight)
        "Time course"
        @get timecourse() = h.ul((h.li(s.label, "=", record_view(__self__, s).spec; class="result")
                                  for s in scenarios)...)
        "Summary"
        @get summary() = h.p("summary:", length(scenarios), ":", basis; class="result")
        "Every record"
        @get every() = h.p(join((string(r.label, ":", r.on) for r in all_records(scenarios)), ","))
        @get index() = semantic_app(__self__; presentation=:tabs, title="Simulator",
            select=entry -> !(entry.name in (:index, :every)))
    end

    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\"[^>]*>.*?</form>"s, html).match
    function attrs_of(html, pattern)
        m = match(pattern, html)
        m === nothing && return nothing
        Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&", "&quot;" => "\"")
             for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.match))
    end
    body_of(r) = String(HTMXObjects._message_body_bytes(r))
end

@testitem "a Records param is the records switched on, each typed by its fields" setup=[RecordsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(ScenarioApp(); operation_policy=:blocking)
    get(url) = dispatch(:GET, url; headers=["HX-Request" => "true"])
    items(url) = [m.captures[1] for m in eachmatch(r"<li class=\"result\">(.*?)</li>", body_of(get(url)))]
    # Without records in the request: one record, "Scenario 1", of the fields' own values.
    @test items("/timecourse") == ["Scenario 1=100% q 24 x 14/false/50.0/70.0"]
    @test items("/timecourse?age=33") == ["Scenario 1=100% q 24 x 14/false/33.0/70.0"]
    # Records in order, typed; one switched off is left out; a missing label is numbered.
    @test items("/timecourse?scenarios.1.label=A&scenarios.1.age=40&scenarios.2.label=B&scenarios.2.on=false" *
                "&scenarios.3.male=true&scenarios.3.weight=80.5") ==
          ["A=100% q 24 x 14/false/40.0/70.0", "Scenario 3=100% q 24 x 14/true/50.0/80.5"]
    @test body_of(get("/every?scenarios.1.label=A&scenarios.2.label=B&scenarios.2.on=false")) ==
          "<p>A:true,B:false</p>"
    # The page's hidden "false" before its checked box: the last value wins.
    @test items("/timecourse?scenarios.1.on=false&scenarios.1.on=true&scenarios.1.label=A") ==
          ["A=100% q 24 x 14/false/50.0/70.0"]
    # Each record is read under the fields' `@relevant` conditions.
    @test items("/timecourse?basis=cohort&scenarios.1.label=A&scenarios.1.age=40&scenarios.1.male=true") ==
          ["A=100% q 24 x 14/false/50.0/70.0"]
    # A value a field refuses names the field as the page sends it.
    bad = get("/timecourse?scenarios.1.label=A&scenarios.2.age=abc")
    @test HTTP.header(bad, "X-HTMXO-Error-Param") == "scenarios.2.age"
    @test contains(body_of(bad), "Invalid value for parameter scenarios.2.age")
    # A route reads it as a vector of NamedTuples.
    app = ScenarioApp()
    @test collect(app.scenarios) == [(label="Scenario 1", regimen="100% q 24 x 14", male=false, age=50.0, weight=70.0)]
    @test record_view(app, (label="X", regimen="50% q 12 x 3", male=true, age=20.0, weight=60.0)).spec ==
          "50% q 12 x 3/true/20.0/60.0"

    # refused: a list without its fields, one with `@options` or `@relevant`, a field named label.
    @test_throws "needs its fields as its default" @eval @htmx struct NoFields
        @param a::Int = 1
        @param list::Records
        @get f() = h.p(a)
    end
    @test_throws "declare `@options`" @eval @htmx struct OptionList
        @param a::Int = 1
        @param list::Records = Records(:a)
        @relevant(list) = a > 0
        @get f() = h.p(a)
    end
    @test_throws "cannot be named `label` or `on`" Records(:label)
    @test_throws "names a field twice" Records(:a, :a)
end

@testitem "an app page draws a card per record, and keeps the list in its address" setup=[RecordsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(ScenarioApp(); operation_policy=:blocking)
    page(url="/") = body_of(dispatch(:GET, url; headers=["HX-Request" => "true"]))
    html = page()
    sidebar = sidebar_of(html)
    # The list is the sidebar's input (both views read it); its fields are not
    # inputs of the page, but of its cards.
    @test contains(sidebar, "<fieldset class=\"htmxo-records\" data-htmxo-records=\"scenarios\" data-htmxo-record-label=\"Scenario\" data-htmxo-record-copy=\"{label} (copy)\"><legend>Scenarios</legend>")
    names = Set(m.captures[1] for m in eachmatch(r" name=\"([^\"]+)\"", html))
    @test isempty(intersect(names, Set(["regimen", "male", "age", "weight"])))
    @test ["scenarios.1.on", "scenarios.1.label", "scenarios.1.regimen", "scenarios.1.male",
           "scenarios.1.age", "scenarios.1.weight"] ⊆ collect(names)
    # A card: the hidden off value and the Include box, the label, Duplicate, Remove.
    @test contains(sidebar, "<input type=\"hidden\" name=\"scenarios.1.on\" value=\"false\"><label class=\"htmxo-record-on\"><input type=\"checkbox\" name=\"scenarios.1.on\" value=\"true\" checked=\"true\">Include</label><input name=\"scenarios.1.label\" value=\"Scenario 1\" aria-label=\"Label\" class=\"htmxo-record-label\">")
    @test contains(sidebar, "data-htmxo-record-action=\"duplicate\">Duplicate</button>")
    @test contains(sidebar, "data-htmxo-record-action=\"add\">Add Scenario</button>")
    # Its fields as their own controls are, help text and `@relevant` included,
    # renamed for the record, ids suffixed for the card.
    @test contains(sidebar, r"data-htmxo-relevant=\"scenarios\.1\.age\" data-show-when=\"[^\"]*basis")
    help = match(r"name=\"scenarios\.1\.regimen\"[^>]*aria-describedby=\"(htmxo-help-\d+--scenarios-1)\"><small id=\"(htmxo-help-\d+--scenarios-1)\"", sidebar)
    @test help !== nothing && help.captures[1] == help.captures[2]
    # Age and weight are short fields, sharing a row.
    @test contains(sidebar, r"<div class=\"htmxo-input-field\" data-htmxo-width=\"short\"><div class=\"htmxo-relevant\" data-htmxo-relevant=\"scenarios\.1\.age\""s)
    # The page shows the records its address names.
    two = sidebar_of(page("/?scenarios.1.label=Low&scenarios.2.label=High&scenarios.2.on=false&scenarios.2.age=30"))
    @test count("class=\"htmxo-record\"", two) == 2
    @test contains(two, "name=\"scenarios.2.label\" value=\"High\"")
    @test contains(two, "<input type=\"checkbox\" name=\"scenarios.2.on\" value=\"true\">Include")
    @test contains(two, r"name=\"scenarios\.2\.age\" type=\"number\" value=\"30\"")
    # What the address leaves out: the one record a request naming none has.
    address = HTMXObjects.JSON.parse(attrs_of(sidebar, r"<form[^>]*>")["data-htmxo-address"])
    @test address["scenarios"]["records"]["label"] == "Scenario"
    @test address["scenarios"]["records"]["fields"]["age"] == ["50.0"]
    # The open tab's first address carries the records.
    first_load = attrs_of(html, r"<div hx-get=\"/timecourse[^\"]*\" hx-trigger=\"load\"[^>]*>")
    query = Dict(HTTP.URIs.queryparams(HTTP.URI(first_load["hx-get"])))
    @test query["scenarios.1.label"] == "Scenario 1" && query["scenarios.1.age"] == "50.0"
    # The cards are one section of the page (`sections`).
    @test contains(repr("text/html", semantic_app(ScenarioApp(); presentation=:tabs,
        select=entry -> !(entry.name in (:index, :every)), sections=["Scenarios" => [:scenarios]])),
        "<fieldset class=\"htmxo-input-section\"><legend>Scenarios</legend><div class=\"htmxo-input-section-fields\"><div class=\"htmxo-input-field\"><fieldset class=\"htmxo-records\"")
    # In German.
    @htmx struct GermanScenarioApp
        __error_texts__ = error_texts(:de)
        "Alter"
        @param age::Float64 = 50.0
        "Szenarien"
        @param scenarios::Records = Records(:age; label="Szenario")
        "Verlauf"
        @get verlauf() = h.p(length(scenarios))
        "Übersicht"
        @get uebersicht() = h.p(length(scenarios))
    end
    german = repr("text/html", semantic_app(GermanScenarioApp(); presentation=:tabs))
    @test contains(german, ">Szenario hinzufügen</button>") && contains(german, ">Duplizieren</button>") &&
          contains(german, "data-htmxo-record-copy=\"{label} (Kopie)\"")
end

@testitem "cards are added, duplicated, switched off and removed in a browser" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(ScenarioApp(); operation_policy=:blocking)
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
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
          const address = () => new URLSearchParams(location.search);
          const out = {};
          try {
            await until(() => result() === 'Scenario 1=100% q 24 x 14/false/50.0/70.0', 'first result');
            // Add copies the last card as "Scenario 2"; its age changed reaches the result.
            document.querySelector('[data-htmxo-record-action="add"]').click();
            await sleep(20);
            field(2, 'age').value = '30'; change(field(2, 'age'));
            await until(() => result() === 'Scenario 1=100% q 24 x 14/false/50.0/70.0|Scenario 2=100% q 24 x 14/false/30.0/70.0', 'added');
            out.add = cards().length === 2 && field(2, 'label').value === 'Scenario 2' &&
              address().get('scenarios.2.age') === '30' && address().get('scenarios.2.label') === 'Scenario 2';
            // Duplicate copies the first card after it; the cards are numbered again,
            // and a choice made in a copy stays its own.
            cards()[0].querySelector('[data-htmxo-record-action="duplicate"]').click();
            await sleep(20);
            out.duplicate = cards().map(c => c.querySelector('.htmxo-record-label').value).join('|') ===
              'Scenario 1|Scenario 1 (copy)|Scenario 2' && field(3, 'age').value === '30';
            document.querySelector('[name="scenarios.2.male"][value="true"]').click();
            await until(() => result().includes('Scenario 1 (copy)=100% q 24 x 14/true/50.0/70.0'), 'duplicate followed');
            out.own = document.querySelector('[name="scenarios.1.male"][value="false"]').checked;
            // Switching a card off takes it out of the result and into the address as on=false.
            cards()[0].querySelector('.htmxo-record-on input').click();
            await until(() => !result().startsWith('Scenario 1='), 'switched off');
            out.off = address().get('scenarios.1.on') === 'false';
            // Remove drops a card and numbers the rest again.
            // (The removed card was off, so the result does not change: wait for the address.)
            cards()[0].querySelector('[data-htmxo-record-action="remove"]').click();
            await until(() => !address().has('scenarios.3.label'), 'removed');
            out.remove = cards().length === 2 && field(1, 'label').value === 'Scenario 1 (copy)' &&
              address().get('scenarios.1.male') === 'true' && address().get('scenarios.2.age') === '30' &&
              result() === 'Scenario 1 (copy)=100% q 24 x 14/true/50.0/70.0|Scenario 2=100% q 24 x 14/false/30.0/70.0';
            // The last card cannot be removed.
            cards()[1].querySelector('[data-htmxo-record-action="remove"]').click();
            await sleep(20);
            cards()[0].querySelector('[data-htmxo-record-action="remove"]').click();
            await sleep(20);
            out.last = cards().length === 1;
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """))
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        page = repr("text/html", htmx(Raw(body_of(dispatch(:GET, "/"; headers=["HX-Request" => "true"]))), driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing, preload_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            haskey(assets, path) &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            dispatch(req.method, req.target; headers=collect(req.headers),
                     body=HTMXObjects._request_body_bytes(req))
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    outcome = isready(receipt) ? Dict(HTTP.URIs.queryparams(HTTP.URI(take!(receipt)))) : Dict{String,String}()
                    @test get(outcome, "error", "") == ""
                    for key in ("add", "duplicate", "own", "off", "remove", "last")
                        @test (key => get(outcome, key, "missing")) == (key => "true")
                    end
                finally
                    process_exited(process) || kill(process)
                end
            end
        finally
            close(server)
        end
    end
end
