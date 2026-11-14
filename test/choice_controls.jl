using TestItemRunner

@testmodule ChoiceFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export ChoicePage, pills_of, lists_of, selects_of, sidebar_of

    # Web-sim's shape: a vessel among 5, a summary quantity among 8 and a
    # compound among 12, read by two operations (the sidebar) or one (a tab).
    @htmx struct ChoicePage
        "Vessel"
        @param vessel::String = "s50"
        @options(vessel) = option_domain(["s50" => "Syringe-50", "b50" => "Bottle-50",
            "b20" => "Bottle-20", "t20" => "Tablet-20", "t60" => "Tablet-60"])
        "Prediction basis"
        @param basis::String = "typical"
        @options(basis) = option_domain(["typical" => "Typical subject", "cohort" => "New subjects"])
        "Summary quantity"
        @param quantity::String = "q1"
        @options(quantity) = option_domain(["q$i" => "Quantity $i" for i in 1:8])
        "Compound"
        @param compound::String = "c3"
        @options(compound) = option_domain(["c$i" => "Compound $i" for i in 1:12])
        "Time course"
        @get timecourse() = h.p("timecourse:", vessel, ":", basis, ":", compound; class="result")
        "Summary"
        @get summary() = h.p("summary:", vessel, ":", basis, ":", quantity, ":", compound; class="result")
        @get index() = semantic_app(__self__; presentation=:tabs, title="Simulator",
                                    select=entry -> entry.name !== :index)
    end

    pills_of(html) = Set(m.captures[1] for m in
        eachmatch(r"<fieldset><legend>[^<]*</legend><label><input type=\"radio\" name=\"(\w+)\"", html))
    lists_of(html) = Set(m.captures[1] for m in
        eachmatch(r"class=\"htmxo-choice-option\"><input type=\"radio\" name=\"(\w+)\"", html))
    selects_of(html) = Set(m.captures[1] for m in eachmatch(r"<select[^>]* name=\"(\w+)\"", html))
    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\" class=\"htmxo-semantic-context htmxo-semantic-sidebar\".*?</form>"s, html).match
end

@testitem "a generated single choice is pills up to radio_max options and a searchable list past it" setup=[ChoiceFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(ChoicePage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    @test pills_of(html) == Set(["vessel", "basis", "quantity"])
    @test lists_of(html) == Set(["compound"])
    @test isempty(selects_of(html))
    # The compound is read by both operations: the sidebar.
    @test lists_of(sidebar_of(html)) == Set(["compound"])
    @test contains(sidebar_of(html), "<span class=\"htmxo-choice-current\">Compound 3</span>")

    app = ChoicePage()
    surface(; kw...) = repr("text/html", semantic_app(app; select=entry -> entry.name !== :index, kw...))
    # The stacked surface picks the same controls.
    @test pills_of(surface()) == Set(["vessel", "basis", "quantity"]) && lists_of(surface()) == Set(["compound"])
    # `radio_max` sets the cutoff for every control of the surface, the
    # sidebar's included, on both presentations.
    for presentation in (:stacked, :tabs)
        few = surface(; presentation, radio_max=3)
        @test pills_of(few) == Set(["basis"])
        @test lists_of(few) == Set(["vessel", "quantity", "compound"])
        many = surface(; presentation, radio_max=12)
        @test pills_of(many) == Set(["vessel", "basis", "quantity", "compound"]) && isempty(lists_of(many))
    end
    @test lists_of(sidebar_of(surface(; presentation=:tabs, radio_max=3))) == Set(["vessel", "compound"])
    # A low-level form takes it too, and its refresh keeps it.
    form = repr("text/html", operation_form(app, :summary; radio_max=3))
    @test lists_of(form) == Set(["vessel", "quantity", "compound"])
    @test !contains(repr("text/html", operation_form(app, :summary)), "__htmxo_radio_max")
end

@testitem "a refreshed control keeps the cutoff the page used" tags=[:unit, :semantic] begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain

    @htmx struct RefreshedChoice
        "Kind"
        @param kind::String = "a"
        @options(kind) = option_domain(["a" => "A", "b" => "B"])
        "Item"
        @param item::String = "x1"
        # Five items of the chosen kind: the refresh resolves them anew.
        @options(item) = option_domain(["$(kind)$(i)" => "$(uppercase(kind)) $i" for i in 1:5])
        "One"
        @get one() = h.p("one:", kind, ":", item)
        "Two"
        @get two() = h.p("two:", kind, ":", item)
        @get index() = semantic_app(__self__; presentation=:tabs, radio_max=3,
                                    select=entry -> entry.name !== :index)
    end
    route!(RefreshedChoice(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    region = match(r"<div class=\"htmxo-semantic-context-control\"[^>]* hx-get=\"([^\"]+)\"", html)
    @test !isnothing(region)
    url = replace(region.captures[1], "&amp;" => "&")
    @test contains(url, "__htmxo_radio_max=3")
    refreshed = String(dispatch(:GET, url * "&kind=b&item=b2"; headers=["HX-Request" => "true"]).body)
    @test contains(refreshed, "class=\"htmxo-choice-list\"")
    @test contains(refreshed, "<span class=\"htmxo-choice-current\">B 2</span>")
    @test contains(refreshed, "name=\"item\" value=\"b2\" checked=\"true\"")
end

@testitem "choice_list: a field, a search and one radio per option" tags=[:unit] begin
    using HTMXObjects

    node = choice_list((; fruit="b"), ["a" => "Äpfel", "b" => "Birnen", "c" => "Kirschen"]; label="Obst")
    html = repr("text/html", node)
    @test startswith(html, "<fieldset class=\"htmxo-choice-list\" data-htmxo-choice-list=\"\"><legend>Obst</legend>")
    field = match(r"<button type=\"button\" class=\"htmxo-choice-field\" popovertarget=\"([\w-]+)\" aria-haspopup=\"dialog\" aria-expanded=\"false\" title=\"Birnen\">", html)
    @test !isnothing(field)
    @test contains(html, "<div id=\"$(field.captures[1])\" class=\"htmxo-choice-panel\" popover=\"auto\" role=\"dialog\" aria-label=\"Obst\">")
    @test contains(html, "<span class=\"htmxo-choice-current\">Birnen</span>")
    @test contains(html, "<label class=\"htmxo-choice-option\"><input type=\"radio\" name=\"fruit\" value=\"b\" checked=\"true\"><span class=\"htmxo-choice-label\">Birnen</span></label>")
    @test count("type=\"radio\"", html) == 3
    # The search field has no name, so no form sends it, and its own events
    # stop at it.
    search = match(r"<input type=\"search\"[^>]*>", html).match
    @test !contains(search, "name=") && contains(search, "placeholder=\"Search…\"")
    @test contains(search, "oninput=\"htmxoChoiceFilter(this);event.stopPropagation()\"")
    @test contains(search, "onchange=\"event.stopPropagation()\"")
    @test contains(html, "<p class=\"htmxo-choice-empty\" hidden=\"true\">No matching option</p>")
    # Each list has its own popover.
    other = repr("text/html", choice_list("fruit", ["a", "b"]))
    @test match(r"popovertarget=\"([\w-]+)\"", other).captures[1] != field.captures[1]
    @test contains(other, "<span class=\"htmxo-choice-current\"></span>")
    # Another language's words, and `show_when`.
    german = repr("text/html", choice_list("fruit", ["a", "b"]; texts=error_texts(:de),
                                           show_when=(:kind, ==, "fruit"), required=true))
    @test contains(german, "placeholder=\"Suchen…\"") && contains(german, ">Keine passende Auswahl</p>")
    @test contains(german, "data-show-when-field=\"kind\"")
    @test count("required=\"true\"", german) == 2
    @test error_texts(:de; choice_search="Finden…").choice_search == "Finden…"

    # A generated list keeps option groups, help and disabled options.
    domain = (; options=[(value="x", label="X", group="Group 1"), (value="y", label="Y", help="Why"),
                         (value="z", label="Z", group="Group 1", disabled=true)])
    generated = repr("text/html", HTMXObjects._semantic_choice_list(:pick, "Pick", domain, "x"))
    @test contains(generated, "<div class=\"htmxo-choice-group\"><div class=\"htmxo-choice-heading\">Group 1</div><label class=\"htmxo-choice-option\"><input type=\"radio\" name=\"pick\" value=\"x\" checked=\"true\">")
    @test contains(generated, "<span class=\"htmxo-choice-label\">Y</span><small>Why</small>")
    @test contains(generated, "value=\"z\" disabled=\"true\"")
end

@testitem "a choice list reads as its label and the chosen option in Markdown" tags=[:unit] begin
    using HTMXObjects

    md(x) = HTMXObjects.to_markdown_string(x)
    list = choice_list((; fruit="b"), ["a" => "Äpfel", "b" => "Birnen", "c" => "Kirschen"]; label="Obst")
    @test md(h.div(h.p("Before"), list)) == "Before\n\nObst Birnen\n\n"
    @test md(choice_list("fruit", ["a", "b"]; label="Obst")) == "Obst\n\n"
    # Other fieldsets keep their marks.
    @test contains(md(radio_group((; x="1"), ["1" => "One", "2" => "Two"])), "◉")
end

@testitem "choice_list(nv, url): the chosen rows, a loader for the rest, and choice_options' rows" tags=[:unit] begin
    using HTMXObjects

    html = repr("text/html", choice_list((; agent="Claude:ux"), "/agent_options"; label="Agent"))
    @test startswith(html, "<fieldset class=\"htmxo-choice-list\" data-htmxo-choice-list=\"\" " *
        "data-htmxo-choice-loads=\"\" data-htmxo-choice-name=\"agent\" data-htmxo-required=\"false\"><legend>Agent</legend>")
    # The chosen option is a row of the list: the closed field shows it and
    # the form sends it before any request.
    @test contains(html, "<span class=\"htmxo-choice-current\">Claude:ux</span>")
    @test contains(html, "<div class=\"htmxo-choice-options\"><label class=\"htmxo-choice-option\"><input type=\"radio\" " *
        "name=\"agent\" value=\"Claude:ux\" checked=\"true\"><span class=\"htmxo-choice-label\">Claude:ux</span></label></div>")
    @test count("type=\"radio\"", html) == 1
    # The rest loads through an htmx GET the script triggers, which inherits
    # no values, so every list naming the address asks the same one.
    loader = match(r"<div class=\"htmxo-choice-loading\"[^>]*>", html).match
    for attr in ("role=\"status\"", "hx-get=\"/agent_options\"", "hx-trigger=\"htmxo-choice-load\"", "hx-swap=\"none\"",
                 "hx-include=\"unset\"", "hx-vals=\"unset\"", "data-htmxo-failed=\"Request failed\"")
        @test contains(loader, attr)
    end
    @test contains(html, "\">Loading…</div><p class=\"htmxo-choice-empty\" hidden=\"true\">")
    @test !contains(html, "htmxo-choice-placeholder")
    # A pair or a record gives the chosen option's label (and group);
    # `nothing` and "" choose nothing.
    paired = repr("text/html", choice_list((; agent="a1"), "/o"; value="a1" => "Agent one"))
    @test contains(paired, "<span class=\"htmxo-choice-current\">Agent one</span>") &&
          contains(paired, "value=\"a1\" checked=\"true\"><span class=\"htmxo-choice-label\">Agent one</span>")
    grouped = repr("text/html", choice_list("agent", "/o"; value=(; value="a2", label="Two", group="G", help="Second")))
    @test contains(grouped, "<div class=\"htmxo-choice-group\"><div class=\"htmxo-choice-heading\">G</div><label class=\"htmxo-choice-option\">" *
        "<input type=\"radio\" name=\"agent\" value=\"a2\" checked=\"true\"><span class=\"htmxo-choice-label\">Two</span><small>Second</small>")
    for none in (nothing, "")
        empty = repr("text/html", choice_list("agent", "/o"; value=none))
        @test !contains(empty, "type=\"radio\"") && contains(empty, "<span class=\"htmxo-choice-current\"></span>")
    end
    # Required with nothing chosen: one hidden required input refuses an empty
    # submit until the rows arrive; a chosen row is required itself.
    required = repr("text/html", choice_list("agent", "/o"; required=true))
    @test contains(required, "<div class=\"htmxo-choice-options\"><input type=\"radio\" name=\"agent\" value=\"\" required=\"true\" " *
        "hidden=\"true\" tabindex=\"-1\" aria-hidden=\"true\" class=\"htmxo-choice-placeholder\"></div>")
    @test contains(required, "data-htmxo-required=\"true\"")
    chosen = repr("text/html", choice_list((; agent="x"), "/o"; required=true))
    @test contains(chosen, "value=\"x\" checked=\"true\" required=\"true\"") && !contains(chosen, "htmxo-choice-placeholder")
    # Several choices: checkboxes, the count and labels, the explicit empty.
    many = repr("text/html", choice_list((; agents=["a", "b" => "Bee"]), "/o"; multiple=true, required=true))
    @test contains(many, "data-htmxo-multiple=\"\" data-htmxo-required=\"true\" data-htmxo-selected=\"{count} selected\"")
    @test count("type=\"checkbox\"", many) == 2 && contains(many, "<span class=\"htmxo-choice-current\">2 selected: a, Bee</span>")
    @test contains(many, "data-htmxo-choice-empty=\"\" disabled=\"true\"")
    none = repr("text/html", choice_list((; agents=String[]), "/o"; multiple=true, required=true))
    @test contains(none, "<input type=\"checkbox\" name=\"agents\" value=\"\" required=\"true\" hidden=\"true\"")
    # Another language's words, and the chosen label in Markdown.
    german = repr("text/html", choice_list("agent", "/o"; texts=error_texts(:de)))
    @test contains(german, "data-htmxo-failed=\"Anfrage fehlgeschlagen\"") && contains(german, "\">Wird geladen…</div>")
    @test HTMXObjects.to_markdown_string(choice_list((; agent="a1"), "/o"; label="Agent", value="a1" => "Agent one")) ==
          "Agent Agent one\n\n"

    # The answer: the rows an inline list draws, without name or chosen state.
    options = [(value="x", label="X", group="Group 1"), (value="y", label="Y", help="Why"),
               (value="z", label="Z", group="Group 1", disabled=true)]
    rows = repr("text/html", choice_options(options))
    @test startswith(rows, "<div class=\"htmxo-choice-options\" data-htmxo-choice-options=\"\"><label class=\"htmxo-choice-option\">" *
        "<input type=\"radio\" value=\"y\"><span class=\"htmxo-choice-label\">Y</span><small>Why</small></label>" *
        "<div class=\"htmxo-choice-group\"><div class=\"htmxo-choice-heading\">Group 1</div>")
    @test contains(rows, "<input type=\"radio\" value=\"z\" disabled=\"true\">")
    @test !contains(rows, "name=") && !contains(rows, "checked") && !contains(rows, "required")
    inline = repr("text/html", choice_list("pick", options; value=nothing))
    drawn = match(r"<div class=\"htmxo-choice-options\">(.*)</div><p class=\"htmxo-choice-empty\""s, inline)[1]
    @test replace(drawn, " name=\"pick\"" => "") == match(r"^<div[^>]*>(.*)</div>$"s, rows)[1]
    @test repr("text/html", choice_options(["a" => "A"])) == repr("text/html", choice_options([(value="a", label="A")]))
end

@testitem "a static export maps where a choice list loads its options" tags=[:unit] begin
    using HTMXObjects

    loader(x) = match(r"<div class=\"htmxo-choice-loading\"[^>]*>", repr("text/html", x)).match
    # Inside a form whose own request sends values: the loader inherits none.
    form = h.form(; hx_get="/result", hx_include="#context", hx_vals="{\"k\": 1}")(
        choice_list((; agent="a"), "/agent_options"))
    @test contains(loader(static_transform(form; record_base="/r")), "hx-get=\"/r/hx/agent_options.html\"")
    exported = loader(static_transform(form, StaticExport(; record_base="/r")))
    @test contains(exported, "hx-get=\"/r/hx/agent_options\"") && !contains(exported, "data-static-disabled")
    mapped = static_transform(form, StaticExport(; url_map=u -> u == "/agent_options" ? "agents.html" : nothing))
    @test contains(loader(mapped), "hx-get=\"agents.html\"")
    # An address the export cannot answer leaves the list its chosen row.
    query = repr("text/html", static_transform(choice_list((; agent="a"), "/agent_options?kind=x"),
                                               StaticExport(; controls=:remove)))
    @test !contains(query, "htmxo-choice-loading") && contains(query, "value=\"a\" checked=\"true\"")
end

@testitem "a choice list loads its options once per address in a browser" tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        options = [(value="a", label="Äpfel"), (value="b", label="Birnen"), (value="c", label="Kirschen", group="Steinobst"),
                   (value="d", label="Datteln", help="getrocknet"), (value="e", label="Eicheln", disabled=true),
                   (value="f", label="Feigen")]
        receipt = Channel{String}(1)
        asked = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await sleep(25);
            }
          }
          const fail = message => { throw new Error(message); };
          const requests = async () => (await fetch('/asked')).json();
          const css = e => getComputedStyle(e);
          const list = id => document.getElementById(id).querySelector('.htmxo-choice-list');
          const parts = l => ({field: l.querySelector('.htmxo-choice-field'), panel: l.querySelector('.htmxo-choice-panel'),
                               search: l.querySelector('.htmxo-choice-search'), loader: l.querySelector('.htmxo-choice-loading'),
                               empty: l.querySelector('.htmxo-choice-empty')});
          const inputs = l => Array.from(l.querySelectorAll('.htmxo-choice-option input'));
          const values = l => inputs(l).map(c => c.value).join();
          const shown = l => Array.from(l.querySelectorAll('.htmxo-choice-option'))
            .filter(o => css(o).display !== 'none').map(o => o.querySelector('input').value).join();
          const open = l => parts(l).panel.matches(':popover-open');
          const key = (el, k) => el.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true}));
          const type = (l, text) => { const s = parts(l).search; s.value = text; s.dispatchEvent(new Event('input', {bubbles: true})); };
          const form = document.getElementById('form');
          const submitted = [];
          form.addEventListener('submit', e => { e.preventDefault(); submitted.push(new FormData(form)); });
          try {
            const a = list('a'), b = list('b'), c = list('c'), d = list('d');
            await sleep(300);
            // A page view asks nothing; the closed fields show and send their choices.
            if ((await requests()).length) fail('asked on the page view');
            const before = new FormData(form);
            if (before.get('agent') !== 'b' || before.getAll('many').join() !== 'a' ||
                parts(a).field.querySelector('.htmxo-choice-current').textContent !== 'b') fail('closed');
            // A required list with nothing chosen refuses the submit and opens,
            // saying its options load, then shows them.
            form.requestSubmit();
            await sleep(50);
            if (submitted.length || !open(b)) fail('the empty required list did not open');
            if (parts(b).loader.hidden || parts(b).loader.textContent !== 'Loading…' || !parts(b).empty.hidden) fail('loading');
            await until(() => inputs(b).length === 6, 'the rows of b');
            if (JSON.stringify(await requests()) !== '["/opts"]') fail('asked: ' + JSON.stringify(await requests()));
            if (!inputs(b).every(x => x.type === 'radio' && x.name === 'other' && x.required) ||
                b.querySelector('.htmxo-choice-placeholder') || !parts(b).loader.hidden || values(b) !== 'a,b,d,e,f,c') fail('b rows');
            parts(b).panel.hidePopover();
            await sleep(50);
            // Pointing at another list naming the address asks nothing more; it
            // copies the rows when it opens, its chosen one checked once and
            // labelled as the answer labels it.
            parts(a).field.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
            await sleep(100);
            parts(a).field.click();
            await sleep(50);
            if (values(a) !== 'a,b,d,e,f,c' || !a.querySelector('input[value="b"]').checked ||
                !parts(a).field.textContent.includes('Birnen') || !open(a)) fail('a rows: ' + values(a));
            if (JSON.stringify(await requests()) !== '["/opts"]') fail('asked again');
            // The search ignores case and accents; Enter chooses and closes.
            type(a, 'APF');
            if (shown(a) !== 'a') fail('search: ' + shown(a));
            key(parts(a).search, 'Enter');
            await sleep(50);
            if (open(a) || new FormData(form).get('agent') !== 'a' || !parts(a).field.textContent.includes('Äpfel')) fail('chosen');
            // Several choices: checkboxes that keep the chosen one and toggle more.
            parts(c).field.click();
            await sleep(50);
            if (!inputs(c).every(x => x.type === 'checkbox' && x.name === 'many') || !c.querySelector('input[value="a"]').checked) fail('c rows');
            c.querySelector('input[value="c"]').closest('.htmxo-choice-option').click();
            await sleep(50);
            if (new FormData(form).getAll('many').join() !== 'a,c' || !open(c) ||
                !parts(c).field.textContent.includes('2 selected: Äpfel, Kirschen')) fail('c toggled: ' + parts(c).field.textContent);
            parts(c).panel.hidePopover();
            await sleep(50);
            // Chosen, the required list lets the form submit.
            parts(b).field.click();
            await sleep(50);
            type(b, 'feig');
            key(parts(b).search, 'Enter');
            await sleep(50);
            form.requestSubmit();
            await sleep(50);
            if (submitted.length !== 1 || submitted[0].get('other') !== 'f' || submitted[0].get('agent') !== 'a') fail('submit');
            // An address that fails: the open list says so where the rows would
            // be, keeps its chosen row, and asks again when it opens again.
            parts(d).field.click();
            await until(() => parts(d).loader.classList.contains('htmxo-choice-failed'), 'the failure of d');
            if (!parts(d).loader.textContent.startsWith('Request failed') || !parts(d).empty.hidden || values(d) !== 'x')
              fail('d failure: ' + parts(d).loader.textContent);
            parts(d).panel.hidePopover();
            await sleep(50);
            parts(d).field.click();
            await sleep(500);
            const all = await requests();
            if (all.filter(x => x === '/broken').length !== 2 || all.filter(x => x === '/opts').length !== 1)
              fail('asked: ' + JSON.stringify(all));
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        content = h.main(; class="container")(
            h.form(; id="form")(
                # Values every request inside it would inherit: the loaders take none.
                h.div(; hx_include="#form", hx_vals="{\"k\": 1}")(
                    h.div(; id="a")(choice_list((; agent="b"), "/opts"; label="A")),
                    h.div(; id="b")(choice_list("other", "/opts"; label="B", required=true)),
                    h.div(; id="c")(choice_list((; many=["a"]), "/opts"; label="C", multiple=true)),
                    h.div(; id="d")(choice_list((; broken="x"), "/broken"; label="D"))),
                h.button("Send"; type="submit")),
            driver)
        page = repr("text/html", htmx(content; assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, pico_version=nothing, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            haskey(assets, path) &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/asked" && return HTTP.Response(200, ["Content-Type" => "application/json"],
                "[" * join(("\"" * t * "\"" for t in asked), ",") * "]")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            push!(asked, String(req.target))
            if path == "/opts"
                sleep(0.3)  # long enough for the open list to show that it loads
                return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", choice_options(options)))
            end
            HTTP.Response(500, ["Content-Type" => "text/plain"], "the options are gone")
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                browser_log = joinpath(profile, "browser.log")
                process = run(pipeline(cmd; stdout=devnull, stderr=browser_log); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 90; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                    @test outcome == "/complete?status=passed"
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

@testitem "every htmx page carries the choice list's script and styles" tags=[:unit] begin
    using HTMXObjects

    css = repr("text/html", htmxo_utility_styles())
    @test contains(css, ".htmxo-choice-list > .htmxo-choice-field {")
    @test contains(css, ".htmxo-choice-panel:popover-open { display: flex; flex-direction: column; }")
    @test contains(css, ".htmxo-choice-panel .htmxo-choice-option:has(> input:checked) {")
    # Unlayered: Pico styles buttons, labels and radios unlayered.
    @test findfirst(".htmxo-choice-list > .htmxo-choice-field {", css).start >
          findfirst("/* Unlayered so it beats", css).start
    # A filtered-out option is hidden by a class, never the `hidden`
    # attribute, which the page runtimes read as "does not apply".
    script = repr("text/html", choice_list_script())
    @test contains(script, "classList.toggle('htmxo-choice-out', out)")
    @test !contains(script, "o.hidden")
    for page in (htmx(h.p("x")), htmx(h.p("x"); pico_version="2"))
        html = repr("text/html", page)
        @test contains(html, "window.__htmxoChoiceList")
        @test contains(html, ".htmxo-choice-list > .htmxo-choice-field {")
    end
end

@testitem "a choice list opens, searches and chooses in a browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const out = document.body.dataset, css = e => getComputedStyle(e), box = e => e.getBoundingClientRect();
                const sleep = ms => new Promise(r => setTimeout(r, ms));
                const pico = document.documentElement.dataset.pico === '1';
                const list = document.querySelector('#fruits .htmxo-choice-list');
                const field = list.querySelector('.htmxo-choice-field'), panel = list.querySelector('.htmxo-choice-panel');
                const search = list.querySelector('.htmxo-choice-search');
                const option = v => list.querySelector('input[value="' + v + '"]').closest('.htmxo-choice-option');
                const shown = () => Array.from(list.querySelectorAll('.htmxo-choice-option'))
                    .filter(o => css(o).display !== 'none').map(o => o.querySelector('input').value);
                const open = () => panel.matches(':popover-open');
                const key = (el, k) => el.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true}));
                const type = text => { search.value = text; search.dispatchEvent(new Event('input', {bubbles: true})); };
                const form = document.getElementById('form');
                const heard = [];
                ['input', 'change'].forEach(t => form.addEventListener(t, e => heard.push(t + ':' + (e.target.name || e.target.className))));
                const probe = value => { const p = document.getElementById('probe'); p.style.backgroundColor = value; return css(p).backgroundColor; };
                try {
                    // Closed: one field showing the chosen option, the radios out of sight.
                    out.closed = String(!open() && field.textContent.includes('Birnen') && box(panel).height === 0 &&
                        new FormData(form).get('fruit') === 'b');
                    // The field reads as an input, not a Pico button.
                    out.field = String(css(field).textAlign === 'start' && css(field).borderTopStyle === 'solid' &&
                        (!pico || css(field).backgroundColor === probe('var(--pico-form-element-background-color)')));
                    // A click opens the list under the field, outside the box that clips
                    // everything else, with the focus in the search field.
                    field.click();
                    await sleep(50);
                    const f = box(field), p = box(panel), clip = box(document.getElementById('fruits'));
                    out.opened = String(open() && field.getAttribute('aria-expanded') === 'true' &&
                        Math.abs(p.top - f.bottom) <= 4 && Math.abs(p.left - f.left) <= 1 && p.width >= f.width - 1 &&
                        p.bottom > clip.bottom && document.elementFromPoint(p.left + 10, p.bottom - 10) !== null &&
                        panel.contains(document.elementFromPoint(p.left + 10, p.bottom - 10)) &&
                        document.activeElement === search);
                    // The chosen option is highlighted and filled like a pill.
                    out.chosen = String(option('b').classList.contains('htmxo-choice-active') &&
                        css(option('b')).backgroundColor === (pico ? probe('var(--pico-contrast-background)') : probe('CanvasText')) &&
                        css(option('a')).backgroundColor !== css(option('b')).backgroundColor);
                    // Typing filters, ignoring case and accents; the search never reaches the form.
                    type('apf');
                    out.filter = String(JSON.stringify(shown()) === '["a"]' && heard.length === 0 &&
                        option('a').classList.contains('htmxo-choice-active'));
                    // No match: the list says so, and an emptied group hides its heading.
                    type('zzz');
                    out.nomatch = String(shown().length === 0 && !list.querySelector('.htmxo-choice-empty').hidden &&
                        css(list.querySelector('.htmxo-choice-group')).display === 'none');
                    type('');
                    out.cleared = String(shown().length === 6 && list.querySelector('.htmxo-choice-empty').hidden);
                    // The arrow keys move from the chosen option and skip the disabled
                    // one (rows: a b d e f, then the group's c); Enter chooses, closes
                    // and returns the focus to the field, which shows the choice.
                    const at = () => list.querySelector('.htmxo-choice-active input').value;
                    key(search, 'ArrowDown');
                    const first = at();
                    key(search, 'ArrowDown');
                    const second = at();
                    key(search, 'ArrowUp');
                    key(search, 'Enter');
                    await sleep(50);
                    out.enter = String(first === 'd' && second === 'f' && !open() && document.activeElement === field &&
                        field.textContent.includes('Datteln') && field.title === 'Datteln' &&
                        new FormData(form).get('fruit') === 'd' &&
                        JSON.stringify(heard) === '["input:fruit","change:fruit"]' &&
                        field.getAttribute('aria-expanded') === 'false');
                    // A letter typed on the closed field opens it, searched; the search
                    // reads an option's help too ("getrocknet").
                    key(field, 'k');
                    await sleep(50);
                    out.typed = String(open() && search.value === 'k' && JSON.stringify(shown()) === '["d","c"]' &&
                        document.activeElement === search);
                    // A click on an option chooses it and closes the list.
                    option('c').click();
                    await sleep(50);
                    out.click = String(!open() && new FormData(form).get('fruit') === 'c' && field.textContent.includes('Kirschen'));
                    // A disabled option cannot be chosen.
                    field.click(); await sleep(50);
                    option('e').click(); await sleep(50);
                    out.disabled = String(new FormData(form).get('fruit') === 'c' && css(option('e')).opacity === '0.5');
                    panel.hidePopover(); await sleep(50);
                    // The search hides the chosen option by a class, so the form still sends it.
                    field.click(); await sleep(50); type('apf');
                    out.sent = String(new FormData(form).get('fruit') === 'c' && !option('c').closest('[hidden]'));
                    panel.hidePopover(); await sleep(50);
                    if (pico) {
                        const light = css(field).backgroundColor;
                        document.documentElement.dataset.theme = 'dark';
                        out.dark = String(css(field).backgroundColor !== light &&
                            css(field).backgroundColor === probe('var(--pico-form-element-background-color)'));
                    } else {
                        out.dark = 'true';
                    }
                } catch (error) {
                    out.error = String(error);
                }
                out.done = '1';
            });
            """))
        options = [(value="a", label="Äpfel"), (value="b", label="Birnen"), (value="c", label="Kirschen", group="Steinobst"),
                   (value="d", label="Datteln", help="getrocknet"), (value="e", label="Eicheln", disabled=true),
                   (value="f", label="Feigen")]
        content = h.main(; class="container")(
            h.form(; id="form")(
                # A small box that clips its content: the open list is not clipped.
                h.div(; id="fruits", style="height: 7rem; overflow: hidden; width: 18rem;")(
                    # The hand-placed list takes the records a generated list reads.
                    choice_list((; fruit="b"), options; label="Fruit"))),
            h.div(; id="probe")("probe"),
            driver)
        app = h.style(Raw("*, *::before, *::after { transition: none !important; }"))
        for pico in (true, false)
            marked = h.script(Raw(pico ? "document.documentElement.dataset.pico = '1';" : ""))
            dom = mktempdir() do directory
                copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
                fixture = joinpath(directory, "page.html")
                write(fixture, repr("text/html", htmx(content; assets="vendor",
                    pico_version=pico ? HTMXObjects._PICO_VERSION : nothing, htmx_version=nothing,
                    hyperscript_version=nothing, preload_version=nothing, extra_head=(app, marked))))
                profile = joinpath(directory, "profile")
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1200,900 --virtual-time-budget=4000 --dump-dom --user-data-dir=$profile file://$fixture`)
            end
            @test contains(dom, "data-done=\"1\"")
            @test !contains(dom, "data-error=")
            for marker in ("closed", "field", "opened", "chosen", "filter", "nomatch", "cleared", "enter",
                           "typed", "click", "disabled", "sent", "dark")
                @test contains(dom, "data-$marker=\"true\"")
            end
        end
    end
end

@testitem "a choice in a tabs page's sidebar asks its results once, its search never" setup=[ChoiceFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(ChoicePage(); operation_policy=:blocking)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        receipt = Channel{String}(1)
        counts = Dict{String,Int}()
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await sleep(25);
            }
          }
          const counts = async () => (await fetch('/counts')).json();
          const shown = name => document.querySelector('[id$="-get-' + name + '-result"]').textContent;
          async function expect(route, n, label) {
            const c = await counts();
            if ((c[route] || 0) !== n) throw new Error(label + ': ' + route + ' asked ' + (c[route] || 0) + ' times, expected ' + n);
          }
          try {
            await until(() => shown('timecourse') === 'timecourse:s50:typical:c3', 'first');
            await expect('/timecourse', 1, 'first');
            const list = document.querySelector('.htmxo-semantic-sidebar .htmxo-choice-list');
            const field = list.querySelector('.htmxo-choice-field'), search = list.querySelector('.htmxo-choice-search');
            field.click();
            await sleep(50);
            // Searching asks nothing.
            for (const text of ['c', 'co', 'compound 1']) {
              search.value = text;
              search.dispatchEvent(new Event('input', {bubbles: true}));
              await sleep(100);
            }
            search.dispatchEvent(new Event('change', {bubbles: true}));
            await sleep(700);
            await expect('/timecourse', 1, 'search');
            // Choosing asks the open tab once: the search left Compound 1, 10,
            // 11 and 12, the first highlighted.
            search.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowDown', bubbles: true}));
            search.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', bubbles: true, cancelable: true}));
            await until(() => shown('timecourse') === 'timecourse:s50:typical:c10', 'chosen');
            await sleep(700);
            await expect('/timecourse', 2, 'chosen');
            if (!field.textContent.includes('Compound 10')) throw new Error('field label');
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once: true});
        """))
        page = repr("text/html", htmx(Raw(String(dispatch(:GET, "/";
                headers=["HX-Request" => "true"]).body)), driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, pico_version=nothing,
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
            path == "/counts" && return HTTP.Response(200, ["Content-Type" => "application/json"],
                "{" * join(["\"$k\":$v" for (k, v) in counts], ",") * "}")
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            contains(req.target, "__htmxo_form") || (counts[path] = get(counts, path, 0) + 1)
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
                    outcome = isready(receipt) ? take!(receipt) : read(browser_log, String)
                    @test outcome == "/complete?status=passed"
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
