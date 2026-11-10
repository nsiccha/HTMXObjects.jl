using TestItemRunner

# A single choice drawn as a table of its options (option records with
# `columns`), a sidebar input placed in an operation's tab (`place`), and a
# mutation's answer that sets an input (`set_inputs`): web-sim's Fits table
# (todo `0we4wfo`, decision `04rngh7`).

@testmodule ChoiceTableFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain, TrackedDirectory
    export FitsPage, FITS_DIR, FIT_INFO, reset_fits!, tab_of, sidebar_of, attrs_of

    const FITS_DIR = mktempdir()
    const FIT_INFO = Dict{String,Any}()
    function reset_fits!()
        foreach(path -> rm(path; force=true), readdir(FITS_DIR; join=true))
        empty!(FIT_INFO)
        for (name, info) in ("pkpd-2024" => (label="PK/PD 2024", model="two-cpt", subjects=212, draws=1000),
                             "synthetic" => (label="Synthetic", model="emax", subjects=40, draws=400))
            FIT_INFO[name] = info
            write(joinpath(FITS_DIR, name), "fit")
        end
    end
    reset_fits!()

    @htmx struct FitsPage
        listing = TrackedDirectory(FITS_DIR; key = basename)
        fits = sort!(collect(keys(listing)))
        "Fit"
        @param fit::String = first(fits)
        @options(fit) = option_domain([(value=name, label=FIT_INFO[name].label,
            columns=(Model=FIT_INFO[name].model, Subjects=FIT_INFO[name].subjects,
                     Draws=FIT_INFO[name].draws)) for name in fits])
        "Dose (mg)"
        @param dose::Float64 = 60.0
        "Time course"
        @get timecourse() = h.p("timecourse:", fit, ":", dose; class="result")
        "Summary"
        @get summary() = h.p("summary:", fit, ":", dose; class="result")
        "Fits"
        @post upload(; name::String) = begin
            FIT_INFO[name] = (label=uppercase(name), model="new", subjects=1, draws=10)
            write(joinpath(FITS_DIR, name), "fit")
            h.div(h.p("added:", name), set_inputs(fit=name))
        end
        @get index() = semantic_app(__self__; presentation=:tabs, title="Simulator",
            select=entry -> entry.name !== :index, place=(fit=:upload,))
    end

    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\"[^>]*>.*?</form>"s, html).match
    tab_of(html, name) = match(Regex("<div class=\"htmxo-semantic-tab\" data-operation=\"$(name)\".*?(?=<div id=\"[^\"]*-tabs-tab-|\$)", "s"), html).match
    function attrs_of(html, pattern)
        m = match(pattern, html)
        m === nothing && return nothing
        Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&", "&quot;" => "\"")
             for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.match))
    end
end

@testitem "options that carry columns are a table to choose from" setup=[ChoiceTableFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain

    reset_fits!()
    @htmx struct TableForm
        "Fit"
        @param fit::String = "b"
        @options(fit) = option_domain([(value="a", label="Fit A", columns=(Model="emax", Draws=400)),
                                       (value="b", label="Fit B", columns=["Model" => "two-cpt", "Subjects" => 12]),
                                       (value="c", label="Fit C")])
        "Run"
        @get run() = h.p(fit)
    end
    html = repr("text/html", operation_form(TableForm(), :run))
    @test contains(html, "<fieldset class=\"htmxo-choice-table\" data-htmxo-choice-table=\"\"><legend>Fit</legend>")
    # The label column, then each column in the order the options first name it.
    headers = [m.captures[1] for m in eachmatch(r"class=\"htmxo-sort-control\"[^>]*>([^<]*)</button>", html)]
    @test headers == ["Fit", "Model", "Draws", "Subjects"]
    rows = [m.match for m in eachmatch(r"<tr data-htmxo-choice-row=\"\" tabindex=\"-1\">.*?</tr>"s, html)]
    @test length(rows) == 3
    @test contains(rows[1], "<input type=\"radio\" name=\"fit\" value=\"a\">Fit A")
    @test contains(rows[2], "value=\"b\" checked=\"true\">Fit B")
    # Numbers are number cells (they sort by value and align right); a missing column is empty.
    @test contains(rows[1], "data-htmxo-number")
    @test contains(rows[3], "<td></td>")
    # Few options: no search; more than radio_max: the table's search field.
    @test !contains(html, "type=\"search\"")
    many = repr("text/html", operation_form(TableForm(), :run; radio_max=2))
    @test contains(many, "type=\"search\"")
    # A choice table is not a short field: in a section it takes the whole width.
    @test !contains(repr("text/html", semantic_app(TableForm(); presentation=:tabs,
        sections=["Fit" => [:fit]])), "data-htmxo-width=\"short\"><fieldset class=\"htmxo-choice-table\"")
end

@testitem "place= draws a sidebar input in an operation's tab, still the sidebar form's" setup=[ChoiceTableFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    reset_fits!()
    route!(FitsPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    sidebar = sidebar_of(html)
    form_id = attrs_of(sidebar, r"<form[^>]*>")["id"]
    # The sidebar keeps the dose; the fit is in the Fits tab, above its form.
    @test !contains(sidebar, "name=\"fit\"")
    @test contains(sidebar, "name=\"dose\"")
    upload = tab_of(html, "upload")
    @test findfirst("htmxo-choice-table", upload)[1] < findfirst("<form hx-post=\"/upload\"", upload)[1]
    # Its radio buttons belong to the sidebar's form.
    radios = collect(eachmatch(r"<input type=\"radio\" name=\"fit\"[^>]*>", upload))
    @test length(radios) == 2
    @test all(m -> contains(m.match, "form=\"$(form_id)\""), radios)
    # The address keeps it, and every result that reads it is sent the sidebar.
    @test contains(attrs_of(sidebar, r"<form[^>]*>")["data-htmxo-address"], "\"fit\"")
    @test contains(attrs_of(html, r"<div id=\"[^\"]*-get-timecourse-result\"[^>]*>")["data-htmxo-inputs"], "#" * form_id)
    # Its control refreshes through the sidebar, and draws itself placed again.
    region = attrs_of(upload, r"<div class=\"htmxo-semantic-context-control\"[^>]*>")
    @test region["hx-include"] == "#" * form_id
    @test region["data-htmxo-context"] == form_id
    @test contains(region["hx-get"], "__htmxo_placed=" * HTTP.URIs.escapeuri(form_id))
    refreshed = String(dispatch(:GET, region["hx-get"] * "&fit=synthetic&dose=60";
        headers=["HX-Request" => "true"]).body)
    @test contains(refreshed, "value=\"synthetic\" checked=\"true\" form=\"$(form_id)\"")
    @test attrs_of(refreshed, r"<div class=\"htmxo-semantic-context-control\"[^>]*>")["hx-include"] == "#" * form_id

    # refused: an input that is not the sidebar's, a tab the page lacks, a stacked page.
    app = FitsPage()
    @test_throws "place= moves a sidebar input into a tab; :name is not one" semantic_app(app;
        presentation=:tabs, select=entry -> entry.name !== :index, place=(name=:upload,))
    @test_throws "place= names :nope, which is no tab of the page" semantic_app(app;
        presentation=:tabs, select=entry -> entry.name !== :index, place=(fit=:nope,))
    @test_throws "place= puts inputs of presentation=:tabs into its tabs" semantic_app(app; place=(fit=:upload,))
end

@testitem "set_inputs is an empty template naming the inputs and their values" tags=[:unit, :semantic] begin
    using HTMXObjects

    html = repr("text/html", set_inputs(fit="new-fit", doses=[5, 10], on=true))
    @test startswith(html, "<template data-htmxo-set-inputs=\"")
    json = replace(match(r"data-htmxo-set-inputs=\"([^\"]*)\"", html).captures[1], "&quot;" => "\"")
    @test HTMXObjects.JSON.parse(json) == Dict("fit" => ["new-fit"], "doses" => ["5", "10"], "on" => ["true"])
    @test strip(HTMXObjects.to_markdown_string(h.div(h.p("added"), set_inputs(fit="x")))) == "added"
end

@testitem "a table choice follows a click, and an added fit becomes the choice, in a browser" setup=[ChoiceTableFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        reset_fits!()
        route!(FitsPage(); operation_policy=:blocking)
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const result = () => document.querySelector('[data-htmxo-follow="/timecourse"]').textContent;
          const chosen = () => document.querySelector('input[name="fit"]:checked').value;
          const row = text => Array.from(document.querySelectorAll('[data-htmxo-choice-row]')).find(r => r.textContent.includes(text));
          const out = {};
          try {
            await until(() => result().includes('timecourse:pkpd-2024'), 'first result');
            document.querySelector('a[data-tab-name="upload"]').click();
            await sleep(100);
            // A click on a row's cell chooses it; the chosen row is marked.
            row('emax').querySelector('td:nth-child(3)').click();
            await sleep(50);
            out.click = chosen() === 'synthetic' &&
              getComputedStyle(row('emax').querySelector('td:nth-child(2)')).fontWeight >= 600 &&
              new URLSearchParams(location.search).get('fit') === 'synthetic';
            // Enter on a focused row chooses it.
            const pkpd = row('two-cpt');
            pkpd.focus();
            pkpd.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', bubbles: true, cancelable: true}));
            await sleep(50);
            out.enter = chosen() === 'pkpd-2024';
            // The result that reads it follows, from its own tab.
            document.querySelector('a[data-tab-name="timecourse"]').click();
            await until(() => result().includes('timecourse:pkpd-2024'), 'followed');
            out.follow = true;
            // An upload adds a fit, which becomes the choice once its row arrives.
            document.querySelector('a[data-tab-name="upload"]').click();
            await sleep(100);
            const form = document.querySelector('form[hx-post="/upload"]');
            form.querySelector('input[name="name"]').value = 'fresh';
            form.requestSubmit();
            await until(() => row('FRESH') && chosen() === 'fresh', 'added fit chosen');
            out.added = document.querySelectorAll('[data-htmxo-choice-row]').length === 3 &&
              new URLSearchParams(location.search).get('fit') === 'fresh' &&
              !document.querySelector('template[data-htmxo-set-inputs]');
            document.querySelector('a[data-tab-name="timecourse"]').click();
            await until(() => result().includes('timecourse:fresh'), 'result of the added fit');
            out.addedFollow = true;
          } catch (e) { out.error = String(e); }
          fetch('/complete?' + new URLSearchParams(Object.entries(out).map(([k, v]) => [k, String(v)])));
        });
        """))
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        page = repr("text/html", htmx(Raw(String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)), driver;
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
                    for key in ("click", "enter", "follow", "added", "addedFollow")
                        @test get(outcome, key, "missing") == "true"
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
