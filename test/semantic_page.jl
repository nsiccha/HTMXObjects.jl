using TestItemRunner

@testmodule SemanticPageFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export SimPage, FitsPage, UPLOADS, sidebar_of, tab_of, tag_attrs, result_text

    const UPLOADS = String[]

    # A simulator in the shape of Bruno's web-sim: a scenario every view reads,
    # settings of single views, inputs that apply only to some scenarios, and
    # one mutation.
    @htmx struct SimPage
        "Fit"
        @param fit::String = "one"
        @options(fit) = option_domain(["one" => "One output", "two" => "Two outputs"])
        "Prediction basis"
        @param basis::String = "typical"
        @options(basis) = option_domain(["typical" => "Typical subject", "cohort" => "New subjects"])
        "Subjects"
        @param subjects::Int = 100
        @relevant(subjects) = basis != "typical"
        "Male"
        @param male::Bool = false
        @relevant(male) = basis == "typical"
        "Dose (mg)"
        @param dose::Float64 = 60.0
        "Scale"
        @param scale::String = "value"
        @options(scale) = option_domain(["value" => "Value", "change" => "Change"])
        "Doses (mg)"
        @param doses::String = "5, 10"
        "Output"
        @param output::String = "a"
        outputs = fit == "two" ? ["a", "b"] : ["a"]
        # Not a comparison of inputs: the page asks the server.
        @relevant(output) = length(outputs) > 1
        "Read by no operation"
        @param unused::Int = 0
        scenario = string(fit, "/", basis, "/", subjects, "/", male)
        "Time course"
        @get timecourse() = h.p("timecourse:", scenario, ":", dose, ":", scale; class="result")
        "Dose–response"
        @get dose_response() = h.p("dose_response:", scenario, ":", doses, ":", output; class="result")
        "Fraction responding"
        @get fraction(; threshold::Float64 = -50.0) =
            h.p("fraction:", scenario, ":", doses, ":", output, ":", threshold; class="result")
        "Add a fit"
        @post upload(; name::String) = (push!(UPLOADS, name); h.p("added:", name; class="result"))
        @get index() = semantic_app(__self__; presentation=:tabs,
            title="Simulator", select=entry -> entry.name !== :index)
    end

    # Defaults computed from other properties, as Bruno's web-sim's are.
    @htmx struct FitsPage
        fits = ["x", "y"]
        "Fit"
        @param fit::String = isempty(fits) ? "" : first(fits)
        @options(fit) = option_domain(fits)
        "Subjects"
        @param n::Int = length(fits) + 1
        "Profile"
        @get profile() = h.p("profile:", fit, ":", n)
        "Summary"
        @get summary() = h.p("summary:", fit, ":", n)
    end

    # The sidebar form, and one tab's content, of a rendered page.
    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\" class=\"htmxo-semantic-context htmxo-semantic-sidebar\".*?</form>"s, html).match
    tab_of(html, name) = match(Regex("<div class=\"htmxo-semantic-tab\" data-operation=\"$(name)\".*?(?=<div id=\"[^\"]*-tabs-tab-|</main>|\$)", "s"), html).match
    # The attributes of the first `<tag …>` whose opening tag matches `pattern`.
    function tag_attrs(html, pattern)
        m = match(pattern, html)
        m === nothing && return nothing
        Dict(a.captures[1] => replace(a.captures[2], "&amp;" => "&", "&quot;" => "\"")
             for a in eachmatch(r" ([\w-]+)=\"([^\"]*)\"", m.match))
    end
    result_text(response) = replace(String(response.body), r"<[^>]*>" => "")
end

@testitem "@relevant reads a @param's default where it does not apply" setup=[SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(SimPage(); operation_policy=:blocking)
    get(url) = result_text(dispatch(:GET, url; headers=["HX-Request" => "true"]))
    # Submitted, but the typical subject has no subjects to count.
    @test get("/timecourse?basis=typical&subjects=7") == "timecourse:one/typical/100/false:60.0:value"
    @test get("/timecourse?basis=cohort&subjects=7") == "timecourse:one/cohort/7/false:60.0:value"
    # A checked box submits "true"; it applies only to the typical subject.
    @test get("/timecourse?basis=typical&male=true") == "timecourse:one/typical/100/true:60.0:value"
    @test get("/timecourse?basis=cohort&male=true") == "timecourse:one/cohort/100/false:60.0:value"
    # A condition on a computed property.
    @test get("/dose_response?fit=one&output=b") == "dose_response:one/typical/100/false:5, 10:a"
    @test get("/dose_response?fit=two&output=b") == "dose_response:two/typical/100/false:5, 10:b"

    # The condition is a property, and the parameter reads it.
    @test HTMXObjects._param_relevance(SimPage) ==
          (subjects=:(basis != "typical"), male=:(basis == "typical"), output=:(length(outputs) > 1))
    @test :__relevant_subjects__ in property_descriptor(SimPage, :subjects).dependencies
    # Reflection still reads the parameter's type, default and doc.
    @test HTMXObjects._reflect_local_param(SimPage, :subjects) ==
          (type=Int, required=false, default=100, doc="Subjects")
    @test HTMXObjects._reflect_local_param(SimPage, :output) ==
          (type=String, required=false, default="a", doc="Output")

    # refused: the value a @relevant parameter takes where it does not apply is its default.
    no_default = :(@htmx struct RelevantNoDefault
        @param basis::String = "typical"
        @param subjects::Int
        @relevant(subjects) = basis != "typical"
    end)
    @test_throws "no default" macroexpand(@__MODULE__, no_default)
    # refused: a @relevant condition belongs to a @param of the same struct.
    unknown = :(@htmx struct RelevantUnknown
        @param basis::String = "typical"
        @relevant(subjects) = basis != "typical"
    end)
    @test_throws "names no `@param`" macroexpand(@__MODULE__, unknown)
    # refused: a delegated parameter is extracted, and so gated, by the struct it delegates to.
    delegated = :(@htmx struct RelevantDelegated
        @param (; basis) = __parent__
        @relevant(basis) = true
    end)
    @test_throws "delegates" macroexpand(@__MODULE__, delegated)
end

@testitem "a @relevant condition of inputs is evaluated in the browser" tags=[:unit, :semantic] begin
    using HTMXObjects

    names = Set([:basis, :subjects, :male, :kind])
    client(ex) = HTMXObjects._client_relevance(ex, names)
    @test client(:(basis != "typical")) ==
          Dict("field" => "basis", "op" => "neq", "value" => "typical", "numeric" => false)
    @test client(:(subjects > 1)) ==
          Dict("field" => "subjects", "op" => "gt", "value" => "1", "numeric" => true)
    # The input on the right is compared from the left.
    @test client(:(1 < subjects)) ==
          Dict("field" => "subjects", "op" => "gt", "value" => "1", "numeric" => true)
    @test client(:male) == Dict("field" => "male", "op" => "eq", "value" => "true")
    @test client(:(kind == :a)) ==
          Dict("field" => "kind", "op" => "eq", "value" => "a", "numeric" => false)
    @test client(:(basis in ("cohort", "covariates"))) == Dict("field" => "basis", "op" => "in",
        "values" => ["cohort", "covariates"], "numeric" => false)
    @test client(:(basis ∉ ["cohort"]))["not"]["op"] == "in"
    both = client(:(basis != "typical" && !male))
    @test both["all"][1]["field"] == "basis"
    @test both["all"][2] == Dict("not" => Dict("field" => "male", "op" => "eq", "value" => "true"))
    @test haskey(client(:(male || subjects >= 2)), "any")
    # Anything else is evaluated on the server.
    @test client(:(length(outputs) > 1)) === nothing
    @test client(:(basis == other)) === nothing
    @test client(:(outputs == "a")) === nothing
    @test client(:(basis != "typical" && length(outputs) > 1)) === nothing
end

@testitem "presentation=:tabs puts shared inputs in a sidebar and each operation in a tab" setup=[SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(SimPage(); operation_policy=:blocking)
    page(url="/") = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    html = page()
    sidebar = sidebar_of(html)
    names_in(s) = Set(m.captures[1] for m in eachmatch(r" name=\"(\w+)\"", s))
    # What several operations read is in the sidebar; what none reads is no
    # control (a mutation's form carries its value, as a stacked one does).
    @test names_in(sidebar) == Set(["fit", "basis", "subjects", "male", "doses", "output"])
    @test count("name=\"unused\"", html) == 1
    @test contains(tab_of(html, "upload"), "<input type=\"hidden\" name=\"unused\" value=\"0\">")
    # What one operation reads is in its tab, with its own arguments.
    @test names_in(tab_of(html, "timecourse")) == Set(["dose", "scale"])
    @test names_in(tab_of(html, "fraction")) == Set(["threshold"])
    @test !contains(tab_of(html, "dose_response"), "<form")
    # A mutation keeps its form and button, sent with the sidebar.
    upload = tab_of(html, "upload")
    @test contains(upload, "<form hx-post=\"/upload\"")
    @test contains(upload, "hx-include=\"#htmxo-semantic-context-")
    @test contains(upload, "<button")
    @test names_in(upload) ⊇ Set(["name"])
    @test !any(name -> contains(upload, "name=\"$(name)\""), ("fit", "basis", "subjects"))
    # Labels come from the parameters' docstrings; few options are radios.
    @test contains(sidebar, "<legend>Prediction basis</legend>")
    @test contains(sidebar, "<input type=\"radio\" name=\"basis\" value=\"typical\" checked=\"true\">")
    @test contains(sidebar, "<input type=\"checkbox\" name=\"male\" value=\"true\">")

    # An input that does not apply starts hidden; its condition rides along
    # for the browser, or, when the browser cannot evaluate it, the control
    # re-renders when the input it reads changes.
    subjects = tag_attrs(sidebar, r"<div class=\"htmxo-relevant\" data-htmxo-relevant=\"subjects\"[^>]*>")
    @test haskey(subjects, "hidden")
    @test subjects["data-show-when"] == "{\"field\":\"basis\",\"numeric\":false,\"op\":\"neq\",\"value\":\"typical\"}"
    male = tag_attrs(sidebar, r"<div class=\"htmxo-relevant\" data-htmxo-relevant=\"male\"[^>]*>")
    @test !haskey(male, "hidden")
    output = tag_attrs(sidebar, r"<div class=\"htmxo-relevant\" data-htmxo-relevant=\"output\"[^>]*>")
    @test haskey(output, "hidden") && !haskey(output, "data-show-when")
    region = tag_attrs(sidebar, r"<div class=\"htmxo-semantic-context-control\"[^>]*>")
    @test region["data-htmxo-depends"] == "fit"
    @test contains(page("/?basis=cohort"), r"data-htmxo-relevant=\"subjects\" data-show-when")

    # Each read's result follows its inputs: its address, the forms it is
    # sent, and the inputs it reads.
    result(name) = tag_attrs(html, Regex("<div id=\"[^\"]*-get-$(replace(name, "_" => "-"))-result\"[^>]*>"))
    timecourse = result("timecourse")
    @test timecourse["data-htmxo-follow"] == "/timecourse"
    @test split(timecourse["data-htmxo-inputs"]) ==
          ["#" * tag_attrs(sidebar, r"<form[^>]*>")["id"], "#" * timecourse["id"] * "-inputs"]
    @test timecourse["data-htmxo-reads"] == "basis dose fit male scale subjects"
    @test result("dose_response")["data-htmxo-reads"] == "basis doses fit male output subjects"
    @test result("fraction")["data-htmxo-reads"] == "basis doses fit male output subjects threshold"
    @test haskey(timecourse, "data-htmxo-live") && timecourse["hx-sync"] == "this:replace"
    # The open tab's result starts with the page, asked for with the values
    # the page shows, but not an input that does not apply.
    first_load = tag_attrs(html, r"<div hx-get=\"/timecourse[^\"]*\" hx-trigger=\"load\"[^>]*>")
    @test HTTP.URI(first_load["hx-get"]).path == "/timecourse"
    @test Dict(HTTP.URIs.queryparams(HTTP.URI(first_load["hx-get"]))) == Dict("fit" => "one",
        "basis" => "typical", "male" => "false", "doses" => "5, 10", "dose" => "60.0",
        "scale" => "value")
    @test count("hx-trigger=\"load\"", html) == 1

    # The page address names the open tab; `active` names it otherwise.
    @test count("hx-trigger=\"load\"", page("/?tab=fraction")) == 1
    @test contains(page("/?tab=fraction"), r"<div hx-get=\"/fraction\?")
    @test contains(page("/?tab=fraction"), r"class=\"contrast\" data-panel=\"tab-3\" data-tab-name=\"fraction\"")
    app = SimPage()
    @test contains(repr("text/html", semantic_app(app; presentation=:tabs, active=:dose_response,
        select=entry -> entry.name !== :index)), r"<div hx-get=\"/dose_response\?")

    # `shared` chooses the sidebar; each tab then shows what it reads of the rest.
    chosen = repr("text/html", semantic_app(app; presentation=:tabs, shared=[:fit, :basis],
        select=entry -> entry.name !== :index))
    @test names_in(sidebar_of(chosen)) == Set(["fit", "basis"])
    @test names_in(tab_of(chosen, "timecourse")) == Set(["subjects", "male", "dose", "scale"])
    @test names_in(tab_of(chosen, "dose_response")) == Set(["subjects", "male", "doses", "output"])

    # refused: a sidebar of inputs no operation takes would offer nothing to change.
    @test_throws "no operation of the surface takes" semantic_app(app; presentation=:tabs,
        shared=[:nope], select=entry -> entry.name !== :index)
    # refused: compact actions and a shared result are the stacked surface's.
    @test_throws "presentation must be :stacked or :tabs" semantic_app(app; presentation=:cards)
    @test_throws "compact=true is a :stacked option" semantic_app(app; presentation=:tabs, compact=true)
    @test_throws "shared= chooses the sidebar" semantic_app(app; shared=[:fit])
end

@testitem "a tabs page re-renders a control the way the page showed it" setup=[SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(SimPage(); operation_policy=:blocking)
    html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
    region = tag_attrs(sidebar_of(html), r"<div class=\"htmxo-semantic-context-control\"[^>]*>")
    refresh(values) = String(dispatch(:GET, region["hx-get"] * "&" *
        join(["$k=$v" for (k, v) in values], "&"); headers=["HX-Request" => "true"]).body)
    # The output applies once the fit predicts two; the refresh renders the
    # sidebar's text control, not a hidden input.
    one = refresh(["fit" => "one", "output" => "a"])
    @test contains(one, "data-htmxo-relevant=\"output\" hidden=\"true\"")
    two = refresh(["fit" => "two", "output" => "b"])
    @test contains(two, "<div class=\"htmxo-relevant\" data-htmxo-relevant=\"output\">")
    @test contains(two, "<label>Output<input name=\"output\"")
    @test contains(two, "value=\"b\"")
    @test tag_attrs(two, r"<div class=\"htmxo-semantic-context-control\"[^>]*>") == region
end

@testitem "semantic_control renders one input of an app its own way" setup=[SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    HTMXObjects.semantic_control(::SimPage, ::Val{:dose}, c) =
        ninput((; dose=c.value); label=c.label * " per day", min=0, step="any")
    HTMXObjects.semantic_control(::SimPage, ::Val{:subjects}, c) =
        ninput((; subjects=c.value); label=c.label, min=1, step=1)
    HTMXObjects.semantic_control(::SimPage, ::Val{:threshold}, c) =
        ninput((; threshold=c.value); label="Threshold (%)", max=0, step="any")
    try
        route!(SimPage(); operation_policy=:blocking)
        html = String(dispatch(:GET, "/"; headers=["HX-Request" => "true"]).body)
        @test contains(tab_of(html, "timecourse"), "<label>Dose (mg) per day<input")
        @test contains(tab_of(html, "timecourse"), "min=\"0\"")
        @test contains(tab_of(html, "fraction"), "<label>Threshold (%)<input")
        # A @relevant input keeps its condition around the app's control.
        @test contains(sidebar_of(html), r"data-htmxo-relevant=\"subjects\" hidden=\"true\"[^>]*><label>Subjects<input[^>]*min=\"1\""s)
        # The stacked surface and a plain operation form use it too.
        stacked = repr("text/html", semantic_app(SimPage(); select=entry -> entry.name === :fraction))
        @test contains(stacked, "<label>Threshold (%)<input")
        @test contains(repr("text/html", operation_form(SimPage(), :fraction)), "<label>Threshold (%)<input")
    finally
        for name in (:dose, :subjects, :threshold)
            Base.delete_method(which(HTMXObjects.semantic_control, (SimPage, Val{name}, Any)))
        end
    end
end

@testitem "a tabs page's results follow their inputs in a browser" setup=[SemanticPageFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        empty!(UPLOADS)
        route!(SimPage(); operation_policy=:blocking)
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
          const shown = name => document.querySelector('[id$="-get-' + name.replace('_', '-') + '-result"]').textContent;
          const relevant = name => !document.querySelector('[data-htmxo-relevant="' + name + '"]').hidden;
          const tab = name => document.querySelector('a[data-tab-name="' + name + '"]').click();
          function choose(name, value) {
            const input = document.querySelector('input[name="' + name + '"][value="' + value + '"]');
            input.click();
          }
          function type(name, value) {
            const input = document.querySelector('input[name="' + name + '"]');
            input.value = value;
            input.dispatchEvent(new Event('change', {bubbles: true}));
          }
          async function expect(route, n, label) {
            const c = await counts();
            if ((c[route] || 0) !== n) throw new Error(label + ': ' + route + ' asked ' + (c[route] || 0) + ' times, expected ' + n);
          }
          try {
            // The open tab's result came with the page.
            await until(() => shown('timecourse') === 'timecourse:one/typical/100/false:60.0:value', 'first');
            await expect('/timecourse', 1, 'first');
            if (relevant('subjects') || !relevant('male') || relevant('output')) throw new Error('first relevance');
            // A sidebar input it reads: asked again, and the inputs that
            // apply now show.
            choose('basis', 'cohort');
            await until(() => shown('timecourse') === 'timecourse:one/cohort/100/false:60.0:value', 'cohort');
            if (!relevant('subjects') || relevant('male')) throw new Error('cohort relevance');
            type('subjects', '7');
            await until(() => shown('timecourse') === 'timecourse:one/cohort/7/false:60.0:value', 'subjects');
            await expect('/timecourse', 3, 'subjects');
            // A tab opened for the first time asks for its result.
            tab('dose_response');
            await until(() => shown('dose_response') === 'dose_response:one/cohort/7/false:5, 10:a', 'dose_response');
            await expect('/dose_response', 1, 'dose_response');
            // Back to a tab whose inputs did not change: nothing is asked.
            tab('timecourse');
            await sleep(700);
            await expect('/timecourse', 3, 'unchanged tab');
            // An input that stops applying is not sent, and changing it then asks nothing.
            choose('basis', 'typical');
            await until(() => shown('timecourse') === 'timecourse:one/typical/100/false:60.0:value', 'typical');
            if (relevant('subjects')) throw new Error('typical relevance');
            type('subjects', '9');
            await sleep(700);
            await expect('/timecourse', 4, 'hidden input');
            // The tab's own input.
            choose('scale', 'change');
            await until(() => shown('timecourse') === 'timecourse:one/typical/100/false:60.0:change', 'scale');
            await expect('/timecourse', 5, 'scale');
            // dose_response reads basis, which changed while it was hidden,
            // and not scale.
            tab('dose_response');
            await until(() => shown('dose_response') === 'dose_response:one/typical/100/false:5, 10:a', 'dose_response again');
            await expect('/dose_response', 2, 'dose_response again');
            tab('timecourse'); await sleep(500); tab('dose_response'); await sleep(700);
            await expect('/dose_response', 2, 'dose_response unchanged');
            await expect('/timecourse', 5, 'timecourse unchanged');
            // A condition the server evaluates: the output applies once the
            // fit predicts two.
            choose('fit', 'two');
            await until(() => relevant('output'), 'output');
            type('output', 'b');
            await until(() => shown('dose_response') === 'dose_response:two/typical/100/false:5, 10:b', 'output b');
            // A mutation: every other result is asked for again when shown.
            tab('upload');
            const form = document.querySelector('form[hx-post="/upload"]');
            form.querySelector('input[name="name"]').value = 'third';
            form.requestSubmit();
            await until(() => document.querySelector('[id$="-post-upload-result"]').textContent === 'added:third', 'upload');
            const before = (await counts())['/dose_response'];
            tab('dose_response');
            await sleep(800);
            await fetch('/complete?status=passed&before=' + before);
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
                    @test startswith(outcome, "/complete?status=passed")
                    before = parse(Int, match(r"before=(\d+)", outcome)[1])
                    # The upload cleared what the results were asked for, so
                    # showing dose_response asked again.
                    @test counts["/dose_response"] == before + 1
                    @test UPLOADS == ["third"]
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

@testitem "a tabs page keeps its inputs in the page address" setup=[SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(SimPage(); operation_policy=:blocking)
    page(url="/") = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    form_attrs(html) = tag_attrs(html, r"<form[^>]*>")
    html = page()
    # Each form of inputs names those the address keeps and what each shows
    # when the address names nothing, as its control sends it.
    @test form_attrs(sidebar_of(html))["data-htmxo-address"] ==
          """{"basis":["typical"],"doses":["5, 10"],"fit":["one"],"male":["false"],"output":["a"],"subjects":["100"]}"""
    @test form_attrs(tab_of(html, "timecourse"))["data-htmxo-address"] ==
          """{"dose":["60.0"],"scale":["value"]}"""
    @test form_attrs(tab_of(html, "fraction"))["data-htmxo-address"] == """{"threshold":["-50.0"]}"""
    # A mutation's own inputs are not page state.
    @test !haskey(form_attrs(tab_of(html, "upload")), "data-htmxo-address")

    # The page shows the values its address names: the sidebar's, a tab's own
    # `@param`s and its arguments; the open tab's result starts with them.
    opened = page("/?basis=cohort&subjects=7&dose=30&scale=change&threshold=-30&tab=fraction")
    sidebar = sidebar_of(opened)
    @test contains(sidebar, "<input type=\"radio\" name=\"basis\" value=\"cohort\" checked=\"true\">")
    @test contains(sidebar, r"<input[^>]* name=\"subjects\"[^>]* value=\"7\"")
    @test contains(tab_of(opened, "timecourse"), r"<input[^>]* name=\"dose\"[^>]* value=\"30.0\"")
    @test contains(tab_of(opened, "timecourse"),
                   "<input type=\"radio\" name=\"scale\" value=\"change\" checked=\"true\">")
    @test contains(tab_of(opened, "fraction"), r"<input[^>]* name=\"threshold\"[^>]* value=\"-30.0\"")
    first_load = tag_attrs(opened, r"<div hx-get=\"/fraction[^\"]*\" hx-trigger=\"load\"[^>]*>")
    query = Dict(HTTP.URIs.queryparams(HTTP.URI(first_load["hx-get"])))
    @test query["basis"] == "cohort" && query["subjects"] == "7" && query["threshold"] == "-30.0"
    @test result_text(dispatch(:GET, first_load["hx-get"]; headers=["HX-Request" => "true"])) ==
          "fraction:one/cohort/7/false:5, 10:a:-30.0"
    # A value the address does not name keeps the page's default.
    @test contains(tab_of(page("/?tab=fraction"), "fraction"),
                   r"<input[^>]* name=\"threshold\"[^>]* value=\"-50.0\"")

    # `values=` gives an input the value it shows without the address; the
    # address still wins over it.
    app = SimPage()
    valued = repr("text/html", semantic_app(app; presentation=:tabs,
        values=(; threshold=-40.0), select=entry -> entry.name !== :index))
    @test form_attrs(tab_of(valued, "fraction"))["data-htmxo-address"] == """{"threshold":["-40.0"]}"""

    # A default computed from other properties is the value it computes.
    computed = repr("text/html", semantic_app(FitsPage(); presentation=:tabs))
    @test form_attrs(sidebar_of(computed))["data-htmxo-address"] == """{"fit":["x"],"n":["3"]}"""

    # `url_state=false` leaves the address to the tab.
    off = repr("text/html", semantic_app(app; presentation=:tabs, url_state=false,
        select=entry -> entry.name !== :index))
    @test !contains(off, "data-htmxo-address")
    # refused: the stacked surface has no page address to keep.
    @test_throws "url_state= keeps the inputs of presentation=:tabs" semantic_app(app; url_state=true)
    @test_throws "url_state must be true or false" semantic_app(app; presentation=:tabs, url_state=1,
        select=entry -> entry.name !== :index)
end

@testitem "a tabs page writes its inputs into the page address in a browser" setup=[SemanticPageFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(SimPage(); operation_policy=:blocking)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label + ' at ' + location.search);
              await sleep(25);
            }
          }
          const shown = name => document.querySelector('[id$="-get-' + name.replace('_', '-') + '-result"]').textContent;
          const relevant = name => !document.querySelector('[data-htmxo-relevant="' + name + '"]').hidden;
          const tab = name => document.querySelector('a[data-tab-name="' + name + '"]').click();
          const param = name => new URLSearchParams(location.search).get(name);
          const control = name => document.querySelector('input[name="' + name + '"]');
          const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
          function type(name, value) {
            const input = control(name);
            input.value = value;
            input.dispatchEvent(new Event('change', {bubbles: true}));
          }
          try {
            const before = sessionStorage.getItem('htmxo-test-address');
            if (before !== null) {
              // Reloaded: the page shows what its address names.
              if (location.search !== before) throw new Error('reload changed the address: ' + location.search);
              await until(() => shown('fraction') === 'fraction:one/cohort/7/false:5, 10:a:-30.0', 'reloaded result');
              if (!document.querySelector('input[name="basis"][value="cohort"]').checked) throw new Error('reloaded basis');
              if (control('subjects').value !== '7' || !relevant('subjects')) throw new Error('reloaded subjects');
              if (control('threshold').value !== '-30.0') throw new Error('reloaded threshold: ' + control('threshold').value);
              await fetch('/complete?status=passed&search=' + encodeURIComponent(location.search));
              return;
            }
            await until(() => shown('timecourse') === 'timecourse:one/typical/100/false:60.0:value', 'first');
            await sleep(300);
            if (location.search !== '') throw new Error('the first load wrote the address: ' + location.search);
            // A sidebar input, and one that applies once it is set.
            choose('basis', 'cohort');
            await until(() => param('basis') === 'cohort', 'basis');
            type('subjects', '7');
            await until(() => param('subjects') === '7', 'subjects');
            // The open tab stays in the address beside them; a tab's own input.
            tab('fraction');
            await until(() => param('tab') === 'fraction', 'tab');
            type('threshold', '-30');
            await until(() => param('threshold') === '-30', 'threshold');
            if (param('basis') !== 'cohort' || param('tab') !== 'fraction') throw new Error('kept: ' + location.search);
            // Back at its default, an input is left out.
            type('threshold', '-50.0');
            await until(() => param('threshold') === null, 'threshold default');
            // An input that stops applying is left out, a checkbox is written.
            choose('basis', 'typical');
            await until(() => param('basis') === null && param('subjects') === null, 'typical');
            control('male').click();
            await until(() => param('male') === 'true', 'male');
            control('male').click();
            await until(() => param('male') === null, 'male default');
            // A condition the server evaluates: the output leaves the address
            // once its re-rendered control is hidden.
            choose('fit', 'two');
            await until(() => relevant('output'), 'output applies');
            type('output', 'b');
            await until(() => param('output') === 'b' && param('fit') === 'two', 'output');
            choose('fit', 'one');
            await until(() => !relevant('output'), 'output hidden');
            await until(() => param('output') === null && param('fit') === null, 'output left out');
            // A value the reader set before comes back with its input.
            choose('basis', 'cohort');
            await until(() => param('subjects') === '7', 'subjects back');
            type('threshold', '-30');
            await until(() => param('threshold') === '-30', 'threshold again');
            if (location.search !== '?tab=fraction&basis=cohort&subjects=7&threshold=-30')
              throw new Error('address: ' + location.search);
            sessionStorage.setItem('htmxo-test-address', location.search);
            location.reload();
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
                    @test startswith(outcome, "/complete?status=passed")
                    @test HTTP.URIs.unescapeuri(outcome) ==
                          "/complete?status=passed&search=?tab=fraction&basis=cohort&subjects=7&threshold=-30"
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
