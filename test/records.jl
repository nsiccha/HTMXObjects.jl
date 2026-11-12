using TestItemRunner


@testmodule RecordsFixtures begin
    using HTMXObjects, HTTP, Sockets
    using HTMXObjects.DynamicObjects: option_domain
    export ScenarioApp, sidebar_of, attrs_of, body_of, browser_outcome

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

    # The routed app's page at `path`, with the script `driver` (which ends by
    # fetching `/complete?<key>=<value>&…`), opened in headless Chrome: the
    # values the driver reported, or an empty Dict when it reported nothing
    # within 60 s.
    function browser_outcome(driver::AbstractString; path="/")
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        receipt = Channel{String}(1)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        page = repr("text/html", htmx(Raw(body_of(dispatch(:GET, path; headers=["HX-Request" => "true"]))),
            h.script(Raw(driver)); assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, pico_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            target = HTTP.URI(req.target).path
            target == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            haskey(assets, target) &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[target])
            target == "/favicon.ico" && return HTTP.Response(204)
            if target == "/complete"
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
                    timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05)
                    isready(receipt) ? Dict(HTTP.URIs.queryparams(HTTP.URI(take!(receipt)))) :
                                       Dict{String,String}()
                finally
                    process_exited(process) || kill(process)
                end
            end
        finally
            close(server)
        end
    end
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
    # The fold control comes first in the head and names the card's fields;
    # the summary a folded card shows is (empty) after the label.
    @test contains(sidebar, "<div class=\"htmxo-record-head\"><button type=\"button\" class=\"htmxo-record-fold\" aria-expanded=\"true\" aria-controls=\"htmxo-record-fields--scenarios-1\" aria-label=\"Fields\" title=\"Fields\" data-htmxo-record-action=\"fold\"></button><input type=\"hidden\" name=\"scenarios.1.on\"")
    @test contains(sidebar, "class=\"htmxo-record-label\"><span class=\"htmxo-record-summary\"></span><button type=\"button\" class=\"outline secondary\" data-htmxo-record-action=\"duplicate\">")
    @test contains(sidebar, "</div><div id=\"htmxo-record-fields--scenarios-1\" class=\"htmxo-input-section-fields\">")
    @test contains(sidebar, "data-htmxo-record-action=\"add\">Add Scenario</button>")
    # Its fields as their own controls are, `@relevant` included, renamed for
    # the record, ids suffixed for the card.
    @test contains(sidebar, r"data-htmxo-relevant=\"scenarios\.1\.age\" data-show-when=\"[^\"]*basis")
    # A docstring's help text is shown once, under the cards, after the
    # field's label; the card's field names it, unsuffixed.
    help = match(r"name=\"scenarios\.1\.regimen\"[^>]*aria-describedby=\"(htmxo-help-\d+)\"", sidebar)
    @test help !== nothing
    @test contains(sidebar, "data-htmxo-record-action=\"add\">Add Scenario</button><div class=\"htmxo-record-help\"><small id=\"$(help.captures[1])\" class=\"htmxo-help\"><strong>Regimen</strong>: Doses as <code>percent% q hours x count</code>.</small></div>")
    # Age and weight are short fields, sharing a row.
    @test contains(sidebar, r"<div class=\"htmxo-input-field\" data-htmxo-width=\"short\"><div class=\"htmxo-relevant\" data-htmxo-relevant=\"scenarios\.1\.age\""s)
    # The page shows the records its address names.
    two = sidebar_of(page("/?scenarios.1.label=Low&scenarios.2.label=High&scenarios.2.on=false&scenarios.2.age=30"))
    @test count("class=\"htmxo-record\"", two) == 2
    # Both cards name the one help text.
    @test count("Doses as", two) == 1
    described = [m.captures[1] for m in eachmatch(r"name=\"scenarios\.\d\.regimen\"[^>]*aria-describedby=\"(htmxo-help-\d+)\"", two)]
    @test length(described) == 2 && allequal(described) && contains(two, "<small id=\"$(described[1])\" class=\"htmxo-help\">")
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
          contains(german, "data-htmxo-record-copy=\"{label} (Kopie)\"") &&
          contains(german, "aria-label=\"Felder\" title=\"Felder\" data-htmxo-record-action=\"fold\"")
end

@testitem "a card field's docstring help is shown once under the cards, its @help in each card" setup=[RecordsFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain

    @htmx struct HelpedCardsApp
        "Basis"
        @param basis::String = "a"
        @options(basis) = option_domain(["a" => "A", "b" => "B"])
        """
        Dose

        In mg.
        """
        @param dose::Float64 = 1.0
        "Note"
        @param note::String = ""
        @help(note) = string("For dose ", dose)
        """
        Age

        In years.
        """
        @param age::Float64 = 50.0
        @relevant(age) = basis == "a"
        "Cards"
        @param cards::Records = Records(:dose, :note, :age; label="Card")
        "One"
        @get one() = h.p(length(cards), basis)
        "Two"
        @get two() = h.p(length(cards), basis)
        @get index() = semantic_app(__self__; presentation=:tabs, select=entry -> entry.name !== :index)
    end

    route!(HelpedCardsApp(); operation_policy=:blocking)
    page(url) = sidebar_of(body_of(dispatch(:GET, url; headers=["HX-Request" => "true"])))
    two = page("/?cards.1.dose=2&cards.2.dose=3")
    # The docstrings' help texts once each, in field order, after Add; each
    # card's field names its text.
    dose = match(r"<div class=\"htmxo-record-help\"><small id=\"(htmxo-help-\d+)\" class=\"htmxo-help\"><strong>Dose</strong>: In mg\.</small></div>", two)
    age = match(r"<div class=\"htmxo-record-help\" data-show-when=\"[^\"]*basis[^\"]*\"><small id=\"(htmxo-help-\d+)\" class=\"htmxo-help\"><strong>Age</strong>: In years\.</small></div>", two)
    @test dose !== nothing && age !== nothing && dose.offset < age.offset
    @test count("In mg.", two) == 1 && count("In years.", two) == 1
    for i in 1:2
        @test contains(two, Regex("name=\"cards\\.$i\\.dose\"[^>]*aria-describedby=\"$(dose.captures[1])\""))
        @test contains(two, Regex("name=\"cards\\.$i\\.age\"[^>]*aria-describedby=\"$(age.captures[1])\""))
    end
    # A `@help` text is computed for each record, and stays in its card.
    @test count("For dose 2.0", two) == 1 && count("For dose 3.0", two) == 1
    @test findfirst("For dose 3.0", two).start < findfirst("data-htmxo-record-action=\"add\"", two).start
    # An Age that applies to no card hides its help text too.
    @test contains(page("/?basis=b"), r"<div class=\"htmxo-record-help\" hidden(=\"[^\"]*\")? data-show-when=\"[^\"]*\"><small id=\"htmxo-help-\d+\" class=\"htmxo-help\"><strong>Age</strong>")
end

@testitem "cards are added, duplicated, switched off and removed in a browser" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
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
            // The regimen's help text stays once, under the cards, and every
            // card's regimen still names it.
            const helps = document.querySelectorAll('.htmxo-record-help small');
            out.help = helps.length === 1 && [1, 2, 3].every(i => field(i, 'regimen').getAttribute('aria-describedby') === helps[0].id);
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
        """)
        @test get(outcome, "error", "") == ""
        for key in ("add", "duplicate", "help", "own", "off", "remove", "last")
            @test (key => get(outcome, key, "missing")) == (key => "true")
        end
    end
end

@testitem "a card folds to a line of its values and still sends them, in a browser" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
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
          const address = () => new URLSearchParams(location.search);
          const toggle = c => c.querySelector('.htmxo-record-fold');
          const line = c => c.querySelector('.htmxo-record-summary');
          // The summary's text, its separators' no-break spaces as spaces.
          const text = c => line(c).textContent.replace(/\u00a0/g, ' ');
          const fieldsOf = c => c.querySelector('.htmxo-input-section-fields');
          const shown = el => getComputedStyle(el).display !== 'none';
          const actions = c => Array.from(c.querySelectorAll('[data-htmxo-record-action="duplicate"], [data-htmxo-record-action="remove"]'));
          const isOpen = c => !c.hasAttribute('data-htmxo-folded') && toggle(c).getAttribute('aria-expanded') === 'true' &&
            shown(fieldsOf(c)) && !shown(line(c)) && actions(c).every(shown) &&
            toggle(c).getAttribute('aria-controls') === fieldsOf(c).id;
          // Folded: the fold control, on/off box, label and summary; the
          // fields, Duplicate and Remove give way.
          const isFolded = c => c.hasAttribute('data-htmxo-folded') && toggle(c).getAttribute('aria-expanded') === 'false' &&
            !shown(fieldsOf(c)) && shown(line(c)) && !actions(c).some(shown) &&
            shown(c.querySelector('.htmxo-record-on')) && shown(c.querySelector('.htmxo-record-label')) &&
            toggle(c).getAttribute('aria-controls') === fieldsOf(c).id;
          const out = {};
          try {
            await until(() => result() === 'Scenario 1=100% q 24 x 14/false/50.0/70.0', 'first result');
            field(1, 'age').value = '33'; change(field(1, 'age'));
            await until(() => result() === 'Scenario 1=100% q 24 x 14/false/33.0/70.0', 'age set');
            // Every card starts open; folding it leaves its head and one line
            // of its values, a choice by its label and a number after its own.
            out.open = isOpen(cards()[0]) && fieldsOf(cards()[0]).id === 'htmxo-record-fields--scenarios-1';
            const openHeight = cards()[0].getBoundingClientRect().height, search = location.search;
            toggle(cards()[0]).click();
            await sleep(400);
            out.folded = isFolded(cards()[0]);
            out.line = text(cards()[0]);
            // Each value with the separator after it is a span, so the line
            // breaks between values.
            out.parts = Array.from(line(cards()[0]).children).map(s => s.textContent).join('|') ===
              '100% q 24 x 14\u00a0·|Female\u00a0·|Age (years): 33\u00a0·|Weight (kg): 70';
            out.heights = Math.round(openHeight) + '>' + Math.round(cards()[0].getBoundingClientRect().height);
            // The fold changes no input, result or address.
            out.unchanged = location.search === search && result() === 'Scenario 1=100% q 24 x 14/false/33.0/70.0';
            // Its line drops and regains the fields that stop and start to
            // apply (Sex and Age apply to the typical subject only).
            document.querySelector('[name="basis"][value="cohort"]').click();
            await until(() => text(cards()[0]) === '100% q 24 x 14 · Weight (kg): 70', 'cohort');
            document.querySelector('[name="basis"][value="typical"]').click();
            await until(() => text(cards()[0]) === '100% q 24 x 14 · Female · Age (years): 33 · Weight (kg): 70', 'typical');
            // While folded, the card's values are still sent: switched off and
            // on again from its head, it is computed with its age.
            cards()[0].querySelector('.htmxo-record-on input').click();
            await until(() => result() === '', 'switched off');
            cards()[0].querySelector('.htmxo-record-on input').click();
            await until(() => result() === 'Scenario 1=100% q 24 x 14/false/33.0/70.0', 'switched on');
            out.sent = isFolded(cards()[0]) && address().get('scenarios.1.age') === '33';
            // Added cards open, copying the last card (folded) as it is
            // in the page; the folded one stays folded.
            document.querySelector('[data-htmxo-record-action="add"]').click();
            await sleep(20);
            out.added = cards().length === 2 && isFolded(cards()[0]) && isOpen(cards()[1]) &&
              fieldsOf(cards()[1]).id === 'htmxo-record-fields--scenarios-2' && field(2, 'age').value === '33';
            // A duplicated card opens; folding its source leaves it open.
            cards()[1].querySelector('[data-htmxo-record-action="duplicate"]').click();
            await sleep(20);
            toggle(cards()[1]).click();
            out.copies = cards().length === 3 && isFolded(cards()[0]) && isFolded(cards()[1]) && isOpen(cards()[2]) &&
              cards()[2].querySelector('.htmxo-record-label').value === 'Scenario 2 (copy)';
            await until(() => result().split('|').length === 3, 'three results');
            // A fold follows its card when the cards are numbered again
            // (Remove shows once the first card is unfolded).
            toggle(cards()[0]).click();
            cards()[0].querySelector('[data-htmxo-record-action="remove"]').click();
            await until(() => result().split('|').length === 2, 'removed');
            out.renumbered = isFolded(cards()[0]) && isOpen(cards()[1]) &&
              fieldsOf(cards()[0]).id === 'htmxo-record-fields--scenarios-1' &&
              fieldsOf(cards()[1]).id === 'htmxo-record-fields--scenarios-2' &&
              text(cards()[0]) === '100% q 24 x 14 · Female · Age (years): 33 · Weight (kg): 70';
            // Unfolding shows the fields again.
            toggle(cards()[0]).click();
            out.unfolded = isOpen(cards()[0]) && text(cards()[0]) === '';
          } catch (e) { out.error = String(e) + ' | result=' + result() + ' | line=' + (cards()[0] ? text(cards()[0]) : ''); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """)
        @test get(outcome, "error", "") == ""
        for key in ("open", "folded", "parts", "unchanged", "sent", "added", "copies", "renumbered", "unfolded")
            @test (key => get(outcome, key, "missing")) == (key => "true")
        end
        @test get(outcome, "line", "missing") == "100% q 24 x 14 · Female · Age (years): 33 · Weight (kg): 70"
        @info "Records card height, open > folded (px)" heights = get(outcome, "heights", "missing")
    end
end

@testitem "a folded card stays folded when its form's controls are drawn again, in a browser" setup=[RecordsFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        using HTMXObjects.DynamicObjects: option_domain

        # One view reads the cards, so they are in its own form, beside a
        # choice whose options read another input: changing that input draws
        # the form's controls, the cards among them, again.
        @htmx struct RedrawnCardsApp
            "Basis"
            @param basis::String = "a"
            @options(basis) = option_domain(["a" => "A", "b" => "B"])
            "Kind"
            @param kind::String = "x"
            @options(kind) = option_domain(basis == "a" ? ["x" => "X", "y" => "Y"] : ["x" => "X", "z" => "Z"])
            "Dose (mg)"
            @param dose::Float64 = 1.0
            "Cards"
            @param cards::Records = Records(:dose; label="Card")
            "One"
            @get one() = h.p(string(basis, kind, ":", join((c.dose for c in cards), ",")); class="result")
            "Two"
            @get two() = h.p("two")
            @get index() = semantic_app(__self__; presentation=:tabs, select=entry -> entry.name !== :index)
        end
        route!(RedrawnCardsApp(); operation_policy=:blocking)
        outcome = browser_outcome(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const result = () => (document.querySelector('[data-htmxo-follow="/one"] .result') || {}).textContent || '';
          const cards = () => Array.from(document.querySelectorAll('.htmxo-record'));
          const line = c => c.querySelector('.htmxo-record-summary').textContent.replace(/ /g, ' ');
          const out = {};
          try {
            await until(() => result() === 'ax:1.0', 'first result');
            document.querySelector('[data-htmxo-record-action="add"]').click();
            await until(() => result() === 'ax:1.0,1.0', 'added');
            const first = cards()[0];
            first.querySelector('.htmxo-record-fold').click();
            out.folded = first.hasAttribute('data-htmxo-folded') && line(first) === 'Dose (mg): 1';
            // The controls are drawn again: Kind offers Z.
            document.querySelector('[name="basis"][value="b"]').click();
            await until(() => document.querySelector('[name="kind"][value="z"]') && result() === 'bx:1.0,1.0', 'redrawn');
            await sleep(100);
            out.redrawn = !first.isConnected && cards().length === 2;
            out.kept = cards()[0].hasAttribute('data-htmxo-folded') &&
              cards()[0].querySelector('.htmxo-record-fold').getAttribute('aria-expanded') === 'false' &&
              line(cards()[0]) === 'Dose (mg): 1' && !cards()[1].hasAttribute('data-htmxo-folded');
          } catch (e) { out.error = String(e) + ' | result=' + result(); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """)
        @test get(outcome, "error", "") == ""
        for key in ("folded", "redrawn", "kept")
            @test (key => get(outcome, key, "missing")) == (key => "true")
        end
    end
end
