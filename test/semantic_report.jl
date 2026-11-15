using TestItemRunner

# A `semantic_app(…; presentation=:tabs)` page's Markdown and report: each tab
# writes its result as the result's address answers it, after a line naming
# the inputs it is shown at, and a report writes it again at each declared
# state (snag semantic-app-tab-91e9c1d6).
@testmodule ReportFixtures begin
    using HTMXObjects
    export Picture, PictureDe, Cohorts, TWICE_CALLS, markdown, html

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

    markdown(url; kwargs...) = String(HTMXObjects._response_bytes(
        dispatch(:GET, url; headers = ["Accept" => "text/markdown"], kwargs...)))
    html(url) = String(HTMXObjects._response_bytes(dispatch(:GET, url; headers = ["HX-Request" => "true"])))
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
        @test occursin(own, md)
        @test !occursin("<div", md) && !occursin("<button", md) && !occursin("data-htmxo", md)
        @test !occursin("Copy link", md)
        # The result the server computes, which the page loads into its tab.
        @test occursin("twice 160.4 in mode line", md)
        # Each tab: its label, then its result.
        @test findfirst("**Result**", md)[1] < findfirst("Total", md)[1] < findfirst("**Twice**", md)[1] <
              findfirst("twice 160.4", md)[1]
        # A result takes no number in a numbered document, as on the page.
        @test occursin("Figure 1: A figure before", md)
        @test occursin("**In the tab**", md) && !occursin("Figure 2", md)
    end
    # The HTML page does not ask for the tab it does not show, and holds none of it.
    before = TWICE_CALLS[]
    page = html("/")
    @test TWICE_CALLS[] == before
    @test !occursin("Shown at", page) && !occursin("twice ", page)
    markdown("/")
    @test TWICE_CALLS[] == before + 1
end

@testitem "the Shown at line names the inputs a tab's result reads, as its controls show them" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Picture(); operation_policy = :blocking)
    md = markdown("/")
    # Digits and unit of a number range, an option's label, a checkbox's value;
    # only the inputs the result reads (the result reads neither `mode` nor `doubled`).
    @test occursin("Shown at: Slope (per day) 0.20; Intercept 80 units\n\nTotal", md)
    @test occursin("Shown at: Slope (per day) 0.20; Intercept 80 units; Mode A line; Doubled no\n\ntwice 160.4", md)
    # The page's address sets the inputs, and the line follows them.
    md = markdown("/?a=0.5&mode=total&doubled=true")
    @test occursin("Shown at: Slope (per day) 0.50; Intercept 80 units\n\nTotal\n\n80.50", md)
    @test occursin("Shown at: Slope (per day) 0.50; Intercept 80 units; Mode The total; Doubled yes\n\ntwice 322.0 in mode total", md)
    # A German page's words.
    route!(PictureDe(); operation_policy = :blocking)
    md = markdown("/")
    @test occursin("Dargestellt bei: Steigung 0.20; Verdoppelt ja\n\nWert 0.4", md)
    @test error_texts().shown_at == "Shown at" && error_texts(:de).shown_at == "Dargestellt bei"
    @test (error_texts().shown_yes, error_texts().shown_no) == ("yes", "no")
    @test (error_texts(:de).shown_yes, error_texts(:de).shown_no) == ("ja", "nein")
    # A list of records: each switched-on record with its fields' values.
    route!(Cohorts(); operation_policy = :blocking)
    md = markdown("/")
    @test occursin("doses 5.0", md)
    @test occursin(r"Shown at: Scenarios Scenario[^\n]*\(Dose \(mg\) 5\)", md)
end

@testitem "report_states writes a tab's result again at each declared state, in a report only" setup=[ReportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Picture(); operation_policy = :blocking)
    report = markdown("/"; report = true)
    # The page's inputs first, then each state with its caption and its own line.
    steep = findfirst("**Steep**\n\nShown at: Slope (per day) 0.50; Intercept 80 units\n\nTotal\n\n80.50", report)
    @test steep !== nothing
    @test findfirst("Shown at: Slope (per day) 0.20; Intercept 80 units\n\nTotal\n\n80.20", report)[1] < steep[1]
    @test occursin("Shown at: Slope (per day) 0.20; Intercept 20 units\n\nTotal\n\n20.20", report)
    # Each tab whose inputs a state names writes it, with the state's values only for what it names.
    @test occursin("**Steep**\n\nShown at: Slope (per day) 0.50; Intercept 80 units; Mode A line; Doubled no\n\ntwice 161.0", report)
    @test occursin("Shown at: Slope (per day) 0.20; Intercept 20 units; Mode A line; Doubled yes\n\ntwice 80.8", report)
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
