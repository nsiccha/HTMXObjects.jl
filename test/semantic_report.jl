using TestItemRunner

# A `semantic_app(…; presentation=:tabs)` page's Markdown and report: each tab
# writes its result as the result's address answers it, after a statement naming
# the inputs it is shown at, and a report writes it again at each declared
# state (snag semantic-app-tab-91e9c1d6).
@testmodule ReportFixtures begin
    using HTMXObjects
    export Picture, PictureDe, Cohorts, Snow, NumberedPicture, TWICE_CALLS, markdown, html, shown_at
    export MountedPicture, MountedArticle, mounted_view, mounted_document

    const TOY_JS = """
    export class JuliaError extends Error {
      constructor(type, message) { super(message); this.name = type; }
    }
    export function toy(grid, a, b) {
      const n = grid.length, x = new Array(n), y = new Array(n);
      for (let i = 0; i < n; i++) { x[i] = grid[i]; y[i] = a * grid[i] + b; }
      return { x, y, total: a + b };
    }
    export const INPUTS = [{ name: "grid", type: "Vector{Float64}" }, { name: "a", type: "Float64" },
      { name: "b", type: "Float64" }];
    export const OUTPUTS = [{ name: "x" }, { name: "y" }, { name: "total" }];
    """

    # How often the server-computed tab was asked for.
    const TWICE_CALLS = Ref(0)

    @htmx struct Picture
        "Slope (per day)"
        @param a::Float64 = 0.2
        @options(a) = number_domain(0.05, 0.8; log = true, digits = 2)
        "Intercept"
        @param b::Float64 = 80.0
        @options(b) = number_domain(10, 100; step = 1, unit = "units")
        "Mode"
        @param mode::Symbol = :line
        @options(mode) = [:line => "A line", :total => "The total"]
        "Doubled"
        @param doubled::Bool = false
        grid = [0.0, 1.0, 2.0]
        line = (; x = grid, y = a .* grid .+ b, total = a + b)
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(numbered(h.h1("Picture"),
            with_caption("A figure before", h.p("before")),
            semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index,
                         report_states = ["Steep" => (a = 0.5,), (b = 20.0, doubled = true)])))
        "Result"
        @get result() = h.div(
            h.button("Copy link"; type = "button"),
            h.dl(h.dt("Total"), h.dd(bound(line.total; digits = 2))),
            with_caption("In the tab", h.p("drawn")),
            render_table(bound(line; columns = (:x, :y))))
        "Twice"
        @get twice() = (TWICE_CALLS[] += 1;
            h.p("twice ", string((doubled ? 4 : 2) * (a + b)), " in mode ", string(mode)))
    end

    @htmx struct PictureDe
        __error_texts__ = error_texts(:de)
        "Steigung"
        @param a::Float64 = 0.2
        @options(a) = number_domain(0.05, 0.8; digits = 2)
        "Verdoppelt"
        @param doubled::Bool = true
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Ergebnis"
        @get result() = h.p("Wert ", string((doubled ? 2 : 1) * a))
    end

    @htmx struct Cohorts
        "Dose (mg)"
        @param dose::Float64 = 5.0
        "Scenarios"
        @param scenarios::Records = Records(:dose; label = "Scenario")
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Doses"
        @get doses() = h.p("doses ", join([string(s.dose) for s in scenarios], ", "))
    end

    # Labels that are phrases with a comma, and one that ends in its own colon
    # (snag shown-at-line-ru-25ece17f).
    @htmx struct Snow
        "Attenuation per mm of snow water, for radiation crossing straight up"
        @param k::Float64 = 0.003
        @options(k) = number_domain(0.001, 0.01; digits = 4)
        "Density of the snow, to read water as depth"
        @param rho::Float64 = 250.0
        @options(rho) = number_domain(50, 500; step = 10, unit = "kg/m³")
        "Depth:"
        @param depth::Float64 = 0.5
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Shielding"
        @get shielding() = h.p("shielded by ", string(round(Int, log(2) / k * rho / 250)), " mm at ", string(depth))
    end

    # A numbered report around a tab the browser computes: a cited figure and
    # table in the tab, a finite input the browser switches views for, a
    # declared state, and a figure after the app (snag semantic-app-tab-c64170a6).
    const CURVE_JS = """
    export const INPUTS = [{ name: "grid", type: "Vector{Float64}" }, { name: "a", type: "Float64" }];
    export const OUTPUTS = [{ name: "x" }, { name: "y" }];
    export function curve(grid, a) {
      return { x: grid.slice(), y: grid.map(g => a * g) };
    }
    """

    @htmx struct NumberedPicture
        "Slope"
        @param a::Float64 = 0.2
        @options(a) = number_domain(0.05, 0.8; digits = 2)
        "Wide"
        @param wide::Bool = false
        grid = [0.0, 1.0]
        line = (; x = grid, y = a .* grid)
        @browser(line) = browser_module(; source = CURVE_JS, entry = :curve)
        @get index() = h.main(numbered(h.h1("Report"),
            h.p("See ", ref("fig-curve"), " and ", ref("tbl-values"), "."),
            semantic_app(__self__; presentation = :tabs, select = e -> e.name == :picture,
                         report_states = ["Steep" => (a = 0.5,)]),
            with_caption("After", h.p("after"))))
        "Picture"
        @get picture() = h.div(
            with_caption("Curve", h.p(wide ? "drawn wide" : "drawn"); id = "fig-curve"),
            render_table(bound(line; columns = (:x, :y)); caption = "Values", id = "values"))
    end

    # Two mounts of one picture in an article routed under a prefix, each shown
    # by a custom tabs layout, as a report builds the article outside any
    # request (snag render-the-mount-9fb42ee3).
    @htmx struct MountedPicture
        "Slope (per day)"
        @param a::Float64 = 0.2
        @options(a) = number_domain(0.05, 0.8; log = true, digits = 2)
        "Intercept"
        @param b::Float64 = 80.0
        @options(b) = number_domain(10, 100; step = 1, unit = "units")
        grid = [0.0, 1.0, 2.0]
        line = (; x = grid, y = a .* grid .+ b, total = a + b)
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        "Picture"
        @get mounted_figure() = h.div(h.dl(h.dt("Total"), h.dd(bound(line.total; digits = 2))))
        "Table"
        @get mounted_numbers() = h.div(render_table(bound(line; columns = (:x, :y))))
        "Note"
        @get mounted_note() = h.p("note ", string(a))
    end

    function mounted_layout(parts)
        tabs = tabset(parts.tabs...; id = parts.id * "-tabs", names = parts.tab_names,
            active = parts.active, url_scope = get(parts, :url_scope, nothing))
        h.section(app_layout(h.aside(parts.sidebar, h.div(parts.reset)), tabs;
            content_id = parts.id * "-content"); id = parts.id, class = "htmxo-semantic-app")
    end
    mounted_view(picture) = semantic_app(picture; presentation = :tabs, layout = mounted_layout,
        select = e -> e.name in (:mounted_figure, :mounted_numbers), shared = [:a, :b])
    mounted_document(app) = numbered(SemanticSection("Pictures",
        SemanticSection("Gentle", h.p("Before."), h.section(mounted_view(app.gentle))),
        SemanticSection("Steep", h.p("Between."), h.section(mounted_view(app.steep)))))

    @htmx struct MountedArticle
        @include gentle = MountedPicture()
        @include steep = MountedPicture(; a = 0.4)
        @get index() = h.main(mounted_document(__self__))
    end

    markdown(url; kwargs...) = String(HTMXObjects._response_bytes(
        dispatch(:GET, url; headers = ["Accept" => "text/markdown"], kwargs...)))
    html(url) = String(HTMXObjects._response_bytes(dispatch(:GET, url; headers = ["HX-Request" => "true"])))
    # The Markdown of a "Shown at" statement: its heading word, then one
    # `Label: value` line for each input, each line ending in Markdown's line break.
    shown_at(lines...; head = "Shown at") = string(head, ":", join(("\\\n" * l for l in lines)))
end

@testitem "a tabs page's Markdown writes each tab's result as its address answers it" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Picture(); operation_policy = :blocking)
    for report in (false, true)
        md = markdown("/"; report)
        # The result computed in the browser: what its own address answers, never its HTML.
        own = strip(String(HTMXObjects._response_bytes(dispatch(:GET, "/result"; report,
            headers = ["HX-Request" => "true", "Accept" => "text/markdown"]))))
        @test occursin("Total\n\n80.20", own) && occursin("| 1 | 80.2 |", own)
        # In the numbered page its caption continues the page's count.
        @test occursin(replace(own, "**In the tab**" => "**Figure 2: In the tab**"), md)
        @test !occursin("<div", md) && !occursin("<button", md) && !occursin("data-htmxo", md)
        @test !occursin("Copy link", md)
        # The result the server computes, which the page loads into its tab.
        @test occursin("twice 160.4 in mode line", md)
        # Each tab: its label, then its result.
        @test findfirst("**Result**", md)[1] < findfirst("Total", md)[1] < findfirst("**Twice**", md)[1] <
              findfirst("twice 160.4", md)[1]
        # A result the page draws takes the document's next number, as on the
        # page; a declared state's copy (a report's) takes none.
        @test occursin("Figure 1: A figure before", md)
        @test count("**Figure 2: In the tab**", md) == 1 && !occursin("Figure 3", md)
        @test count("**In the tab**", md) == (report ? 2 : 0)
        @test !occursin("htmxo:caption-number", md)
    end
    # The HTML page does not ask for the tab it does not show, and holds none of it.
    before = TWICE_CALLS[]
    page = html("/")
    @test TWICE_CALLS[] == before
    @test !occursin("Shown at", page) && !occursin("twice ", page)
    markdown("/")
    @test TWICE_CALLS[] == before + 1
end

@testitem "the Shown at statement names the inputs a tab's result reads, one per line, as its controls show them" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Picture(); operation_policy = :blocking)
    md = markdown("/")
    # Digits and unit of a number range, an option's label, a checkbox's value;
    # only the inputs the result reads (the result reads neither `mode` nor `doubled`).
    @test occursin(shown_at("Slope (per day): 0.20", "Intercept: 80 units") * "\n\nTotal", md)
    @test occursin(shown_at("Slope (per day): 0.20", "Intercept: 80 units", "Mode: A line", "Doubled: no") * "\n\ntwice 160.4", md)
    # The page's address sets the inputs, and the line follows them.
    md = markdown("/?a=0.5&mode=total&doubled=true")
    @test occursin(shown_at("Slope (per day): 0.50", "Intercept: 80 units") * "\n\nTotal\n\n80.50", md)
    @test occursin(shown_at("Slope (per day): 0.50", "Intercept: 80 units", "Mode: The total", "Doubled: yes") * "\n\ntwice 322.0 in mode total", md)
    # A German page's words.
    route!(PictureDe(); operation_policy = :blocking)
    md = markdown("/")
    @test occursin(shown_at("Steigung: 0.20", "Verdoppelt: ja"; head = "Dargestellt bei") * "\n\nWert 0.4", md)
    @test error_texts().shown_at == "Shown at" && error_texts(:de).shown_at == "Dargestellt bei"
    @test (error_texts().shown_yes, error_texts().shown_no) == ("yes", "no")
    @test (error_texts(:de).shown_yes, error_texts(:de).shown_no) == ("ja", "nein")
    # A list of records: each switched-on record with its fields' values.
    route!(Cohorts(); operation_policy = :blocking)
    md = markdown("/")
    @test occursin("doses 5.0", md)
    @test occursin(r"Shown at:\\\nScenarios: Scenario[^\n]*\(Dose \(mg\): 5\)", md)
    # A label that holds a comma stays apart from its value, each on its own
    # line; a label that ends in a colon keeps its own.
    route!(Snow(); operation_policy = :blocking)
    md = markdown("/")
    @test occursin(shown_at("Attenuation per mm of snow water, for radiation crossing straight up: 0.0030",
                            "Density of the snow, to read water as depth: 250 kg/m³",
                            "Depth: 0.5") * "\n\nshielded by 231 mm at 0.5", md)
    @test !occursin("Depth::", md)
end

@testitem "a mounted app's tabs write their results when the page is built outside a request" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    app = MountedArticle()
    # A slash around the prefix names the same mount as without one.
    @test route!(app; prefix = "/article/", operation_policy = :blocking) === app
    # The object `route!` registered, and its children, are mounted where its routes are.
    @test app.__prefix__ == "/article" && app.steep.__prefix__ == "/article/steep"
    @test string(app) == "/article" && app.gentle / "mounted_figure" == "/article/gentle/mounted_figure"
    # The article's page, then the article built outside a request, as a
    # report builds it. The page's Markdown is the app's first request: a
    # later one shows the steep mount at a = 0.2 (snag retained-semanti-865defc0).
    page_md = markdown("/article/"; report = true)
    page = html("/article/")
    outside = mounted_document(app)
    for text in (repr(MIME"text/html"(), outside), page)
        @test occursin("data-htmxo-follow=\"/article/gentle/mounted_figure\"", text)
        @test occursin("data-htmxo-follow=\"/article/steep/mounted_numbers\"", text)
        @test !occursin("//article", text)
    end
    for md in (HTMXObjects.to_markdown_string(outside; report = true), page_md)
        # Each tab: its label block, the inputs it is shown at, then its result.
        @test occursin("::: {.htmxo-label}\n**Picture**\n:::\n\n" *
            shown_at("Slope (per day): 0.20", "Intercept: 80 units") * "\n\nTotal\n\n80.20", md)
        @test occursin(shown_at("Slope (per day): 0.40", "Intercept: 80 units") * "\n\nTotal\n\n80.40", md)
        @test occursin("| 2 | 80.4 |", md) && occursin("| 2 | 80.8 |", md)
        @test count("Shown at:", md) == 4 && count("Total", md) == 2
    end
    # A picture no `route!` mounted has no address answering its results: the
    # page and its Markdown say so rather than show the tab empty.
    @test_throws "semantic_app: the result address /mounted_figure" mounted_view(MountedPicture())
    @test_throws "of MountedPicture (mounted at __prefix__ \"\") answers 404 and no route serves it" mounted_view(MountedPicture())
    note = semantic_app(MountedPicture(); presentation = :tabs, select = e -> e.name == :mounted_note)
    @test_throws "no route serves it" HTMXObjects.to_markdown_string(note)
end

@testitem "report_states writes a tab's result again at each declared state, in a report only" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Picture(); operation_policy = :blocking)
    report = markdown("/"; report = true)
    # The page's inputs first, then each state with its caption and its own statement.
    steep = findfirst("**Steep**\n\n" * shown_at("Slope (per day): 0.50", "Intercept: 80 units") * "\n\nTotal\n\n80.50", report)
    @test steep !== nothing
    @test findfirst(shown_at("Slope (per day): 0.20", "Intercept: 80 units") * "\n\nTotal\n\n80.20", report)[1] < steep[1]
    @test occursin(shown_at("Slope (per day): 0.20", "Intercept: 20 units") * "\n\nTotal\n\n20.20", report)
    # Each tab whose inputs a state names writes it, with the state's values only for what it names.
    @test occursin("**Steep**\n\n" * shown_at("Slope (per day): 0.50", "Intercept: 80 units", "Mode: A line", "Doubled: no") * "\n\ntwice 161.0", report)
    @test occursin(shown_at("Slope (per day): 0.20", "Intercept: 20 units", "Mode: A line", "Doubled: yes") * "\n\ntwice 80.8", report)
    @test count("Shown at:", report) == 6
    # An ordinary read and the page show the page's inputs only.
    plain = markdown("/")
    @test !occursin("Steep", plain) && count("Shown at:", plain) == 2
    @test !occursin("Steep", html("/"))
    # A state names inputs of the page, and its values are ones they take.
    @test_throws "names :slope, which no operation of the surface takes; its inputs are" semantic_app(
        Picture(); presentation = :tabs, select = e -> e.name != :index, report_states = [(slope = 0.5,)])
    @test_throws "report_states must be a vector of states" semantic_app(
        Picture(); presentation = :tabs, select = e -> e.name != :index, report_states = (a = 0.5,))
    @test_throws "a state must name at least one input" semantic_app(
        Picture(); presentation = :tabs, select = e -> e.name != :index, report_states = [(;)])
    @test_throws "a state's caption must not be empty" semantic_app(
        Picture(); presentation = :tabs, select = e -> e.name != :index, report_states = [" " => (a = 0.5,)])
    @test_throws "report_states= shows the results of presentation=:tabs" semantic_app(
        Picture(); select = e -> e.name != :index, report_states = [(a = 0.5,)])
    page = semantic_app(Picture(); presentation = :tabs, select = e -> e.name != :index,
                        report_states = ["Too steep" => (a = 5.0,)])
    @test_throws "the state \"Too steep\" is refused at /result?a=5.0" HTMXObjects.to_markdown_string(page; report = true)
    @test !occursin("Too steep", HTMXObjects.to_markdown_string(page))
end

@testitem "in a numbered document a tab's result the browser computes takes the document's numbers, the same in page and Markdown" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(NumberedPicture(); operation_policy = :blocking)
    cap(words, title) = string("<strong><span><span class=\"htmxo-caption-number\">", words,
                               ":</span> </span>", title, "</strong>")
    page = html("/")
    # The tab's figure and table continue the document's count, and the figure
    # after the app takes the next number; `ref` cites the tab's.
    @test occursin(cap("Figure 1", "Curve"), page) && occursin(cap("Table 1", "Values"), page)
    @test occursin(cap("Figure 2", "After"), page)
    @test occursin("""<a href="#fig-curve" class="htmxo-ref">Figure 1</a>""", page)
    @test occursin("""<a href="#tbl-values" class="htmxo-ref">Table 1</a>""", page)
    # The view the browser shows for the other value of `wide` reads the same numbers.
    @test occursin("drawn wide", page)
    @test count("Curve</strong>", page) == count(cap("Figure 1", "Curve"), page) > 1
    @test !occursin("Figure 3", page) && !occursin("Table 2", page)
    @test !occursin("htmxo:caption-number", page)
    for report in (false, true)
        md = markdown("/"; report)
        @test occursin("See [Figure 1](#fig-curve) and [Table 1](#tbl-values).", md)
        @test count("**Figure 1: Curve**", md) == 1 && count("**Table 1: Values**", md) == 1
        @test occursin("**Figure 2: After**", md)
        @test !occursin("Figure 3", md) && !occursin("Table 2", md)
        @test !occursin("htmxo:caption-number", md)
        # A report's further state is only in the report, and takes no number.
        @test occursin("**Steep**", md) == report
        @test count("**Curve**", md) == (report ? 1 : 0) && count("**Values**", md) == (report ? 1 : 0)
        report && @test findfirst("**Figure 1: Curve**", md)[1] < findfirst("**Steep**", md)[1] <
                         findfirst("**Curve**", md)[1] < findfirst("**Figure 2: After**", md)[1]
        # The state's copy renames its ids, so each id a `ref` cites is in the report once.
        @test count(r"\{#fig-curve[\s}]", md) == 1 && count(r"\{#tbl-values[\s}]", md) == 1
        @test occursin("{#fig-curve-state-1", md) == report && occursin("{#tbl-values-state-1", md) == report
    end
    # The result's own address, and a page outside a numbered document, number nothing.
    for text in (html("/picture"), markdown("/picture"))
        @test occursin("Curve", text) && !occursin("Figure", text) && !occursin("htmxo:caption-number", text)
    end
    app = semantic_app(NumberedPicture(); presentation = :tabs, select = e -> e.name == :picture)
    for text in (repr(MIME"text/html"(), app), HTMXObjects.to_markdown_string(app))
        @test occursin("Curve", text) && !occursin("Figure", text) && !occursin("htmxo:caption-number", text)
    end
    # A static export numbers the page as the server does.
    HTMXObjects.vendorfiles("assets/vendor")
    mktempdir() do dir
        export_site(joinpath(dir, "site"); pages = ["/"])
        index = read(joinpath(dir, "site", "index.html"), String)
        @test occursin(cap("Figure 1", "Curve"), index) && occursin(cap("Table 1", "Values"), index)
        @test occursin(cap("Figure 2", "After"), index)
        @test !occursin("htmxo:caption-number", index)
    end
end

@testitem "a numbered report's PDF numbers a tab's result as the page does" tags=[:quarto] setup=[ReportFixtures] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1" || isnothing(Sys.which("pdftotext"))
        @test_skip true
    else
        using HTMXObjects
        route!(NumberedPicture(); operation_policy = :blocking)
        mktempdir() do dir
            out = joinpath(dir, "report.pdf")
            @test pdf_report(markdown("/"; report = true), out; title = "Report", lang = "en-GB") == out
            t = read(`pdftotext -enc UTF-8 -layout $out -`, String)
            # The tab's figure and table, the figure after the app, and the
            # citations read as on the page; the state's copy has no number.
            @test count("Figure 1: Curve", t) == 1 && count("Table 1: Values", t) == 1
            @test count("Figure 2: After", t) == 1
            @test !occursin("Figure 3", t) && !occursin("Table 2", t)
            @test occursin("See Figure 1 and Table 1.", t)
            @test occursin("Steep", t) && count("Curve", t) == 2
        end
    end
end
