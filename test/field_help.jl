using TestItemRunner


@testmodule FieldHelpFixtures begin
    using HTMXObjects, HTTP, Sockets
    export HelpPage, GlossedPage, schedule_of, sidebar_of, tab_of, attrs_of, browser_outcome

    function schedule_of(regimen)
        m = match(r"^(\d+)% q (\d+) x (\d+)$", strip(regimen))
        m === nothing && throw(CallerFault(400,
            "the regimen $(repr(regimen)) does not parse: write it as 100% q 24 x 14"; param=:regimen))
        (percent=parse(Int, m[1]), every=parse(Int, m[2]), doses=parse(Int, m[3]))
    end

    @htmx struct HelpPage
        """
        Regimen

        Doses as `percent% q hours x count`:
        `100% q 24 x 14` is 14 doses, one every 24 h.
        """
        @param regimen::String = "100% q 24 x 14"
        "Dose (mg)"
        @param dose_mg::Float64 = 60.0
        @help(dose_mg) = let s = schedule_of(regimen)
            "$(s.doses) doses of $(dose_mg * s.percent / 100) mg every $(s.every) h"
        end
        "Days"
        @param days::Int = 7
        "Seed"
        @param seed::Int = 1
        @help(seed) = nothing
        plan = schedule_of(regimen)
        "Time course"
        @get timecourse() = h.p("timecourse:", plan.doses, ":", dose_mg, ":", seed; class="result")
        "Summary"
        @get summary() = h.p("summary:", plan.doses, ":", days, ":", seed; class="result")
        @get index() = semantic_app(__self__; presentation=:tabs, title="Simulator",
            select=entry -> entry.name !== :index)
    end

    # The same inputs under a root with a glossary whose term the fault's
    # message uses (snag `on-web-sim-s-gen-fa2a5324`: web-sim's "regimen").
    const DOSING = Glossary([GlossaryTerm("regimen",
        "The dosing schedule: 100% q 24 x 14 is the dose once a day for 14 days.";
        forms=["Regimen", "regimens"])])

    @htmx struct GlossedPage
        __glossary__ = DOSING
        """
        Regimen

        Doses as `percent% q hours x count`.
        """
        @param regimen::String = "100% q 24 x 14"
        plan = schedule_of(regimen)
        "Course"
        @get course() = h.p("course:", plan.doses; class="result")
        "Totals"
        @get totals() = h.p("totals:", plan.doses; class="result")
        @get index() = semantic_app(__self__; presentation=:tabs, title="Simulator",
            select=entry -> entry.name !== :index)
    end

    # The app page at "/" with `driver` appended, served with the vendored htmx
    # to headless Chrome; the page's requests go to the routes registered last.
    # What the driver reported to `/complete`, or `nothing` if it never did.
    function browser_outcome(driver)
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        receipt = Channel{String}(1)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        page = repr("text/html", htmx(Raw(String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)), driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing, preload_version=nothing, pico_version=nothing,
            feedback=false, compose=false, overlay=false))
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
                    timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05)
                    isready(receipt) ? Dict(HTTP.URIs.queryparams(HTTP.URI(take!(receipt)))) : nothing
                finally
                    process_exited(process) || kill(process)
                end
            end
        finally
            close(server)
        end
    end

    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\" class=\"htmxo-semantic-context htmxo-semantic-sidebar\".*?</form>"s, html).match
    tab_of(html, name) = match(Regex("<div class=\"htmxo-semantic-tab\" data-operation=\"$(name)\".*?(?=<div id=\"[^\"]*-tabs-tab-|\$)", "s"), html).match
    function attrs_of(html, pattern)
        m = match(pattern, html)
        m === nothing && return nothing
        Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&", "&quot;" => "\"")
             for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.match))
    end
end

@testitem "a @param's help text is drawn under its control" setup=[FieldHelpFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(HelpPage(); operation_policy=:blocking)
    page(url="/") = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    html = page()
    sidebar = sidebar_of(html)
    # A docstring's first paragraph is the label, the rest its help text (one
    # line; a span between backticks is code), which the field names.
    m = match(r"<label>Regimen<input name=\"regimen\"[^>]* aria-describedby=\"(htmxo-help-\d+)\"><small id=\"(htmxo-help-\d+)\" class=\"htmxo-help\">(.*?)</small></label>"s, sidebar)
    @test m !== nothing
    @test m.captures[1] == m.captures[2]
    @test m.captures[3] == "Doses as <code>percent% q hours x count</code>: <code>100% q 24 x 14</code> is 14 doses, one every 24 h."
    # `@help` computes its text for the request, from any input.
    help(s, name) = something(match(Regex("name=\"$(name)\"[^>]*><small id=\"htmxo-help-\\d+\" class=\"htmxo-help\">(.*?)</small>", "s"), s),
                              (; captures=[nothing])).captures[1]
    @test help(tab_of(html, "timecourse"), "dose_mg") == "14 doses of 60.0 mg every 24 h"
    @test help(tab_of(page("/?regimen=50%25%20q%2012%20x%203&dose_mg=40"), "timecourse"), "dose_mg") ==
          "3 doses of 20.0 mg every 12 h"
    # It is drawn again when what it reads changes: its control refreshes with
    # the regimen (in the sidebar) and with its own value.
    region = attrs_of(tab_of(html, "timecourse"), r"<div class=\"htmxo-semantic-controls\"[^>]*>")
    @test region["data-htmxo-depends"] == "regimen"
    refreshed = String(dispatch(:GET, region["hx-get"] * "&regimen=100%25%20q%208%20x%2021&dose_mg=10";
        headers=["HX-Request" => "true"]).body)
    @test help(refreshed, "dose_mg") == "21 doses of 10.0 mg every 8 h"
    # Where the text cannot be computed because an input is at fault, the
    # control has no help text; the faulty input's field says why.
    @test help(tab_of(page("/?regimen=nope"), "timecourse"), "dose_mg") === nothing
    # A `@help` that gives `nothing`, and a one-paragraph docstring: no help text.
    @test !contains(sidebar, "name=\"seed\"") || help(sidebar, "seed") === nothing
    @test contains(tab_of(html, "summary"), "<label>Days<input name=\"days\" type=\"number\" value=\"7\"></label>")
    # semantic_control receives it.
    HTMXObjects.semantic_control(::HelpPage, ::Val{:regimen}, c) =
        h.label(c.label, h.input(; name="regimen", value=c.value), h.p(c.help; class="own-help"))
    try
        @test contains(page(), "<p class=\"own-help\">Doses as `percent% q hours x count`")
    finally
        Base.delete_method(which(HTMXObjects.semantic_control, (HelpPage, Val{:regimen}, Any)))
    end
end

@testitem "@help is refused for an input the struct does not declare, and twice for one" tags=[:unit, :semantic] begin
    using HTMXObjects

    @test_throws "`@help(nope)` names no `@param` of this struct" @eval @htmx struct BadHelp
        @param n::Int = 1
        @help(nope) = "x"
        @get f() = h.p(n)
    end
    @test_throws "a `@param` has two `@help` declarations: n" @eval @htmx struct TwiceHelp
        @param n::Int = 1
        @help(n) = "x"
        @help(n) = "y"
        @get f() = h.p(n)
    end
end

@testitem "a caller fault that names its input says so to the page" setup=[FieldHelpFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    import HTMXObjects: _clear_operation_polls!

    @test CallerFault(400, "x").param === nothing
    @test CallerFault(400, "x"; param="regimen").param === :regimen
    @test_throws "CallerFault param must name an input" CallerFault(400, "x"; param=1)

    _clear_operation_polls!()
    route!(HelpPage(); operation_policy=:blocking)
    hx(url) = dispatch(:GET, url; headers=["HX-Request" => "true"])
    body(r) = String(HTMXObjects._message_body_bytes(r))
    # An htmx answer names the input in a header and on its article.
    bad = hx("/timecourse?regimen=nope")
    @test bad.status == 200
    @test HTTP.header(bad, "X-HTMXO-Error-Param") == "regimen"
    @test contains(body(bad), "<article aria-invalid=\"true\" data-htmxo-param=\"regimen\"><header>Bad Request</header><p>the regimen &quot;nope&quot; does not parse")
    # A submitted value its type refuses names its parameter too.
    typed = hx("/summary?days=soon")
    @test HTTP.header(typed, "X-HTMXO-Error-Param") == "days"
    # A fault about no input, and a good answer, name none.
    @test !HTTP.hasheader(hx("/timecourse"), "X-HTMXO-Error-Param")
    # The Markdown answer is unchanged: the 400 and its message.
    plain = dispatch(:GET, "/timecourse?regimen=nope"; headers=["Accept" => "text/markdown"])
    @test plain.status == 400
    @test contains(body(plain), "the regimen \"nope\" does not parse")
    @test !HTTP.hasheader(plain, "X-HTMXO-Error-Param")

    # A polled operation's failing answer names it as well.
    gate = Base.Event()
    @htmx struct PolledParamApp
        "Slow"
        @get slow(; n::Int=1) = (wait(gate); throw(CallerFault(422, "n is refused"; param=:n)))
    end
    route!(PolledParamApp())
    started = hx("/slow?n=2")
    url = replace(only(match(r"hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\"", body(started)).captures), "&amp;" => "&")
    notify(gate)
    # The poll that ends the operation (a function, so the loop sets `answer`).
    function settled(url)
        for _ in 1:400
            answer = hx(url)
            contains(body(answer), "hx-trigger=\"every ") || return answer
            sleep(0.025)
        end
        error("the operation did not end: $url")
    end
    failed = settled(url)
    @test HTTP.header(failed, "X-HTMXO-Error-Param") == "n"
    @test contains(body(failed), "data-htmxo-param=\"n\"")
end

@testitem "a page shows a fault at its input's field and keeps the result it shows in a browser" setup=[FieldHelpFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        route!(HelpPage(); operation_policy=:blocking)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const result = () => document.querySelector('[data-htmxo-follow="/timecourse"]');
          const regimen = () => document.querySelector('input[name="regimen"]');
          const error = () => document.querySelector('.htmxo-field-error');
          function set(value) {
            regimen().value = value;
            regimen().dispatchEvent(new Event('change', {bubbles: true}));
          }
          const out = {};
          try {
            await until(() => result().textContent.includes('timecourse:14'), 'first result');
            const shown = result().textContent;
            // A regimen that does not parse: the field says so, the result stays, faded.
            set('nope');
            await until(() => error(), 'field error');
            out.field = regimen().getAttribute('aria-invalid') === 'true' &&
              error().textContent.includes('does not parse') &&
              regimen().getAttribute('aria-describedby').split(' ').includes(error().id) &&
              regimen().nextElementSibling === error();
            out.kept = result().textContent === shown && result().hasAttribute('data-htmxo-stale') &&
              getComputedStyle(result()).opacity < 1;
            // The page address keeps what the reader typed.
            out.address = new URLSearchParams(location.search).get('regimen') === 'nope';
            // A good regimen clears both and shows its result.
            set('100% q 12 x 3');
            await until(() => result().textContent.includes('timecourse:3'), 'corrected result');
            await sleep(50);
            out.cleared = !error() && !regimen().hasAttribute('aria-invalid') &&
              !result().hasAttribute('data-htmxo-stale') &&
              !(regimen().getAttribute('aria-describedby') || '').includes('field-error');
            // The help text is still there.
            out.help = !!document.querySelector('label small.htmxo-help');
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """))
        outcome = browser_outcome(driver)
        @test outcome !== nothing
        outcome = something(outcome, Dict{String,String}())
        @test !haskey(outcome, "error") || outcome["error"] == ""
        for key in ("field", "kept", "address", "cleared", "help")
            @test get(outcome, key, "missing") == "true"
        end
    end
end

@testitem "a fault's message under a glossary links its terms" setup=[FieldHelpFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    import HTMXObjects: _clear_operation_polls!

    _clear_operation_polls!()
    route!(GlossedPage())
    answer = dispatch(:GET, "/course?regimen=nope"; headers=["HX-Request" => "true"])
    text = String(HTMXObjects._message_body_bytes(answer))
    # The paragraph the page copies under the field: the term is a link that
    # names its definition, which sits beside it in a box the page hides.
    @test HTTP.header(answer, "X-HTMXO-Error-Param") == "regimen"
    m = match(r"<article aria-invalid=\"true\" data-htmxo-param=\"regimen\"><header>Bad Request</header><p>the <span class=\"htmxo-term\"><a href=\"#term-regimen\" aria-describedby=\"([^\"]+)\">regimen</a><span class=\"htmxo-term-def\"><span id=\"([^\"]+)\" role=\"tooltip\">The dosing schedule: [^<]*</span>", text)
    @test m !== nothing
    @test m !== nothing && m.captures[1] == m.captures[2]
    @test contains(text, "</span></span> &quot;nope&quot; does not parse: write it as 100% q 24 x 14</p>")
end

@testitem "a fault's message under its field reads as a sentence, its terms linked, in a browser" setup=[FieldHelpFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        import HTMXObjects: _clear_operation_polls!

        _clear_operation_polls!()
        route!(GlossedPage())
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const region = name => document.querySelector('[data-htmxo-follow="/' + name + '"]');
          const regimen = () => document.querySelector('input[name="regimen"]');
          const note = () => document.querySelector('.htmxo-field-error');
          const shown = el => getComputedStyle(el).display !== 'none';
          const unique = () => {
            const ids = Array.from(document.querySelectorAll('[id]'), el => el.id);
            return new Set(ids).size === ids.length;
          };
          // A term's link in `within`, the definition it names, and that definition's box.
          function term(within) {
            const a = within.querySelector('.htmxo-term > a');
            const tip = a && document.getElementById(a.getAttribute('aria-describedby'));
            return {a, tip, box: tip && tip.closest('.htmxo-term-def')};
          }
          function set(value) {
            regimen().value = value;
            regimen().dispatchEvent(new Event('change', {bubbles: true}));
          }
          const out = {};
          try {
            await until(() => region('course').textContent.includes('course:14'), 'first result');
            set('nope');
            await until(() => note(), 'field error');
            const t = term(note());
            // The message reads as the sentence; its term is a link whose
            // definition, in the note itself, stays hidden.
            out.sentence = note().innerText.trim() ===
              'the regimen "nope" does not parse: write it as 100% q 24 x 14';
            out.linked = !!t.a && t.a.textContent === 'regimen' && t.a.getAttribute('href') === '#term-regimen' &&
              !!t.tip && note().contains(t.tip) && t.tip.textContent.startsWith('The dosing schedule');
            out.hidden = !!t.box && !shown(t.box);
            // Focus opens the definition, in the page's text colour, not the fault's.
            t.a.focus();
            await until(() => shown(t.box), 'definition opens');
            out.opens = getComputedStyle(t.box).color !== getComputedStyle(note()).color;
            t.a.blur();
            await until(() => !shown(t.box), 'definition closes');
            // A region with nothing to keep shows the fault's article too: each
            // copy's link names its own definition, and no id is repeated.
            document.querySelector('[role="tab"][data-tab-name="totals"]').click();
            await until(() => region('totals').querySelector('article[data-htmxo-param]'), 'article in totals');
            await until(() => note(), 'field error again');
            const article = region('totals').querySelector('article[data-htmxo-param]');
            const inArticle = term(article), inNote = term(note());
            out.both = !!inArticle.tip && article.contains(inArticle.tip) &&
              !!inNote.tip && note().contains(inNote.tip) && unique();
            // A good regimen clears the note and shows its result.
            set('100% q 12 x 3');
            await until(() => region('totals').textContent.includes('totals:3'), 'corrected result');
            await sleep(50);
            out.cleared = !note() && !(regimen().getAttribute('aria-describedby') || '').includes('field-error') && unique();
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """))
        outcome = browser_outcome(driver)
        @test outcome !== nothing
        outcome = something(outcome, Dict{String,String}())
        @test !haskey(outcome, "error") || outcome["error"] == ""
        for key in ("sentence", "linked", "hidden", "opens", "both", "cleared")
            @test get(outcome, key, "missing") == "true"
        end
    end
end

@testitem "a page opened with an input at fault shows the fault in its result and at its field in a browser" setup=[FieldHelpFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(HelpPage(); operation_policy=:blocking)
        receipt = Channel{String}(1)
        # The page's first answer for the open tab is a fault about the regimen:
        # its load placeholder is no result to keep, so the article replaces it.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const region = () => document.querySelector('[data-htmxo-follow="/timecourse"]');
          const out = {};
          try {
            await until(() => region().querySelector('article[aria-invalid]'), 'the fault in the result');
            out.article = region().textContent.includes('does not parse') &&
              !region().querySelector('progress, [hx-trigger="load"]') &&
              !region().hasAttribute('data-htmxo-stale');
            const note = document.querySelector('.htmxo-field-error');
            out.field = !!note && note.textContent.includes('does not parse') &&
              document.querySelector('input[name="regimen"]').getAttribute('aria-invalid') === 'true';
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """))
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        page = repr("text/html", htmx(Raw(String(dispatch(:GET, "/?regimen=nope"; headers=["HX-Request" => "true"]).body)), driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing, preload_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false))
        @test contains(page, r"<div hx-get=\"/timecourse\?[^\"]*regimen=nope[^\"]*\" hx-trigger=\"load\"")
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
                    for key in ("article", "field")
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
