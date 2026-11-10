using TestItemRunner

@testmodule InputSectionFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export SectionPage, SECTIONS, section_page, sidebar_of, tab_of, sections_of, fields_of

    # A simulator in the shape of Bruno's web-sim: a scenario every view reads,
    # settings of the simulation and of the views, inputs that apply only to
    # some scenarios, and a view with arguments of its own.
    @htmx struct SectionPage
        "Fit"
        @param fit::String = "one"
        @options(fit) = option_domain(["one" => "One output", "two" => "Two outputs"])
        "Prediction basis"
        @param basis::String = "typical"
        @options(basis) = option_domain(["typical" => "Typical subject", "cohort" => "New subjects"])
        "Subjects"
        @param subjects::Int = 100
        @relevant(subjects) = basis != "typical"
        "Sex"
        @param male::Bool = false
        @options(male) = option_domain([false => "Female", true => "Male"])
        @relevant(male) = basis == "typical"
        "Age (years)"
        @param age::Float64 = 50.0
        @relevant(age) = basis == "typical"
        "Weight (kg)"
        @param weight::Float64 = 70.0
        @relevant(weight) = basis == "typical"
        "Regimen"
        @param regimen::String = "100% q 24 x 14"
        "Draws"
        @param draws::Int = 100
        "Seed"
        @param seed::Int = 1
        "Doses (mg)"
        @param doses::String = "5, 10"
        "Output"
        @param output::String = "a"
        outputs = fit == "two" ? ["a", "b"] : ["a"]
        # Not a comparison of inputs: the page asks the server.
        @relevant(output) = length(outputs) > 1
        "Not in any section"
        @param note::String = ""
        scenario = string(fit, "/", basis, "/", subjects, "/", male, "/", age, "/", weight, "/",
                          regimen, "/", draws, "/", seed, "/", note)
        "Time course"
        @get timecourse() = h.p("timecourse:", scenario, ":", doses; class="result")
        "Dose–response"
        @get dose_response() = h.p("dose_response:", scenario, ":", doses, ":", output; class="result")
        "Fraction responding"
        @get fraction(; threshold::Float64 = -50.0, direction::String = "below") =
            h.p("fraction:", scenario, ":", output, ":", threshold, ":", direction; class="result")
    end

    # Main sections, two settings sections given between them (drawn last),
    # and a section of one view's own arguments.
    const SECTIONS = [
        "Fit" => [:fit],
        "Subjects" => [:basis, :subjects],
        InputSection("Simulation settings", [:draws, :seed]; settings=true),
        "Typical subject" => [:male, :age, :weight],
        "Dosing" => (:regimen,),
        InputSection("View settings", [:doses, :output]; settings=true),
        "Responder" => [:threshold, :direction],
    ]

    section_page(app=SectionPage(); kwargs...) = repr("text/html", semantic_app(app;
        presentation=:tabs, title="Simulator", kwargs...))
    sidebar_of(html) = match(r"<form id=\"htmxo-semantic-context-[^\"]*\" class=\"htmxo-semantic-context htmxo-semantic-sidebar\".*?</form>"s, html).match
    tab_of(html, name) = match(Regex("<div class=\"htmxo-semantic-tab\" data-operation=\"$(name)\".*?(?=<div id=\"[^\"]*-tabs-tab-|\$)", "s"), html).match
    # The headings of the sections in `html`, in order, each with its settings mark.
    sections_of(html) = [(m.captures[2], m.captures[1] !== nothing) for m in
        eachmatch(r"<fieldset class=\"htmxo-input-section\"( data-htmxo-settings=\"\")?><legend>([^<]*)</legend>", html)]
    # The inputs of one section, in order, each with whether it is short.
    function fields_of(html, heading)
        section = match(Regex("<legend>$(heading)</legend><div class=\"htmxo-input-section-fields\">(.*?)</div></fieldset>", "s"), html)
        section === nothing && return nothing
        [(m.captures[2], m.captures[1] !== nothing) for m in eachmatch(
            r"<div class=\"htmxo-input-field\"( data-htmxo-width=\"short\")?>.*?name=\"(\w+)\""s, section.captures[1])]
    end
end

@testitem "a tabs page draws its declared input sections in the sidebar and a tab" setup=[InputSectionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    html = section_page(; sections=SECTIONS)
    sidebar = sidebar_of(html)
    # Inputs no section names come first, as they were; then the sections in
    # the order given, the settings after the rest.
    @test sections_of(sidebar) == [("Fit", false), ("Subjects", false), ("Typical subject", false),
        ("Dosing", false), ("Simulation settings", true), ("View settings", true)]
    @test findfirst("name=\"note\"", sidebar)[1] < findfirst("htmxo-input-section", sidebar)[1]
    @test !contains(sidebar, r"<div class=\"htmxo-input-field\"[^>]*>(<div[^>]*>)*<label>Not in any section")
    # A section's inputs follow the order it names them. A number, a checkbox
    # and a choice between two pills are short fields, which share a row.
    @test fields_of(sidebar, "Subjects") == [("basis", true), ("subjects", true)]
    @test fields_of(sidebar, "Typical subject") == [("male", true), ("age", true), ("weight", true)]
    @test fields_of(sidebar, "Dosing") == [("regimen", false)]
    @test fields_of(sidebar, "View settings") == [("doses", false), ("output", false)]
    # A tab's own inputs are sectioned the same way; a section holding none of
    # a form's inputs is not drawn there.
    fraction = tab_of(html, "fraction")
    @test sections_of(fraction) == [("Responder", false)]
    @test fields_of(fraction, "Responder") == [("threshold", true), ("direction", false)]
    @test isempty(sections_of(tab_of(html, "timecourse")))
    # `@relevant` still hides a field: its wrapper sits in the field, as before.
    @test contains(sidebar, r"<div class=\"htmxo-input-field\" data-htmxo-width=\"short\"><div class=\"htmxo-relevant\" data-htmxo-relevant=\"subjects\" hidden=\"true\""s)
    # The page address keeps the same inputs, and the page's results read the same.
    plain = section_page()
    address(s) = match(r"data-htmxo-address=\"([^\"]*)\"", sidebar_of(s)).captures[1]
    @test address(html) == address(plain)
    reads(s) = [m.captures[1] for m in eachmatch(r"data-htmxo-reads=\"([^\"]*)\"", s)]
    @test reads(html) == reads(plain)
    names_in(s) = Set(m.captures[1] for m in eachmatch(r" name=\"(\w+)\"", s))
    @test names_in(html) == names_in(plain)
    # A form is Markdown chrome: the page's Markdown does not change.
    @test HTMXObjects.to_markdown_string(semantic_app(SectionPage(); presentation=:tabs,
        title="Simulator", sections=SECTIONS)) ==
        HTMXObjects.to_markdown_string(semantic_app(SectionPage(); presentation=:tabs, title="Simulator"))

    # `heading => names` is `InputSection(heading, names)`.
    @test InputSection("A", [:x]).settings === false
    @test InputSection("A", :x).names == [:x]
    # refused: an input in two sections, an unknown input, a stray value, a
    # stacked surface (which has no sidebar), an empty section.
    @test_throws "puts :age in both \"A\" and \"B\"" section_page(; sections=["A" => [:age], "B" => [:age]])
    @test_throws "names :nope, which no operation of the surface takes" section_page(; sections=["A" => [:nope]])
    @test_throws "sections= takes InputSection(heading, names) or heading => names" section_page(; sections=[:age])
    @test_throws "sections= groups the inputs of presentation=:tabs" semantic_app(SectionPage(); sections=SECTIONS)
    @test_throws "names no input" InputSection("A", Symbol[])
    @test_throws "needs a heading" InputSection(" ", [:x])
end

@testitem "a tabs page's refreshed controls keep their sections" setup=[InputSectionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    route!(SectionPage(); operation_policy=:blocking)
    # The output's relevance reads the fit, which the sidebar shows: the
    # dose–response tab's controls refresh from the server when it changes.
    html = section_page(; sections=SECTIONS, shared=[:fit, :basis])
    tab = tab_of(html, "dose_response")
    @test sections_of(tab) == [("Subjects", false), ("Typical subject", false), ("Dosing", false),
        ("Simulation settings", true), ("View settings", true)]
    region = match(r"<div class=\"htmxo-semantic-controls\" hx-get=\"([^\"]*)\""s, tab)
    @test region !== nothing
    url = replace(region.captures[1], "&amp;" => "&")
    @test contains(url, "__htmxo_sections=")
    refreshed = String(dispatch(:GET, url * "&fit=two&basis=typical&output=b";
        headers=["HX-Request" => "true"]).body)
    @test sections_of(refreshed) == sections_of(tab)
    @test fields_of(refreshed, "View settings") == [("doses", false), ("output", false)]
    @test contains(refreshed, "<div class=\"htmxo-relevant\" data-htmxo-relevant=\"output\"><label>Output")
    @test contains(refreshed, "value=\"b\"")
end

@testitem "input sections share rows and hide with their inputs in a browser" setup=[InputSectionFixtures, ChromeDump] tags=[:browser, :semantic] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const out = document.body.dataset, sleep = ms => new Promise(r => setTimeout(r, ms));
                const pico = document.documentElement.dataset.pico === '1';
                const section = heading => Array.from(document.querySelectorAll('.htmxo-input-section'))
                    .find(s => s.querySelector('legend').textContent === heading);
                const shown = el => el.getBoundingClientRect().height > 0;
                const field = name => document.querySelector('[name="' + name + '"]').closest('.htmxo-input-field');
                const top = name => Math.round(field(name).getBoundingClientRect().top);
                try {
                    // A section's heading reads as one, under Pico too.
                    out.heading = String(parseInt(getComputedStyle(section('Dosing').querySelector('legend')).fontWeight) >= 600);
                    // Short fields share a row; a long one takes the whole width.
                    out.row = String(top('age') === top('weight') && top('draws') === top('seed') &&
                        field('regimen').getBoundingClientRect().width >= field('age').getBoundingClientRect().width * 1.8);
                    // New subjects: the typical subject's fields do not apply, so its
                    // section is gone, and the subjects field shows.
                    out.hidden = String(!shown(section('Typical subject')) && shown(field('subjects')) && shown(section('Subjects')));
                    // Choosing the typical subject brings the section back, and hides the subjects field.
                    document.querySelector('input[name="basis"][value="typical"]').click();
                    await sleep(100);
                    out.back = String(shown(section('Typical subject')) && shown(field('age')) && !shown(field('subjects')));
                    // A server-evaluated condition (the output) hides its field, not its section.
                    out.server = String(!shown(field('output')) && shown(section('View settings')));
                } catch (error) {
                    out.error = String(error);
                }
                out.done = '1';
            });
            """))
        app = SectionPage()
        # The page as a reader asked for new subjects.
        content = h.main(; class="container")(
            semantic_app(app; presentation=:tabs, sections=SECTIONS, url_state=false), driver)
        for pico in (true, false)
            marked = h.script(Raw(pico ? "document.documentElement.dataset.pico = '1';" : ""))
            style = h.style(Raw("*, *::before, *::after { transition: none !important; } " *
                ".htmxo-app-layout { --htmxo-sidebar-width: 19rem; }"))
            dom = mktempdir() do directory
                copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
                fixture = joinpath(directory, "page.html")
                html = repr("text/html", htmx(content; assets="vendor",
                    pico_version=pico ? HTMXObjects._PICO_VERSION : nothing, htmx_version=nothing,
                    hyperscript_version=nothing, preload_version=nothing, extra_head=(style, marked)))
                # New subjects chosen: the server hides what does not apply, as a
                # request with `basis=cohort` would.
                html = replace(html, "value=\"typical\" checked=\"true\"" => "value=\"typical\"",
                    "value=\"cohort\">" => "value=\"cohort\" checked=\"true\">")
                for name in ("male", "age", "weight")
                    html = replace(html, "data-htmxo-relevant=\"$name\" " => "data-htmxo-relevant=\"$name\" hidden=\"true\" ")
                end
                html = replace(html, "data-htmxo-relevant=\"subjects\" hidden=\"true\" " => "data-htmxo-relevant=\"subjects\" ")
                write(fixture, html)
                profile = joinpath(directory, "profile")
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1200 --virtual-time-budget=4000 --dump-dom --user-data-dir=$profile file://$fixture`)
            end
            @test contains(dom, "data-done=\"1\"")
            @test !contains(dom, "data-error=")
            for marker in ("heading", "row", "hidden", "back", "server")
                @test contains(dom, "data-$marker=\"true\"")
            end
        end
    end
end
