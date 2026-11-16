using TestItemRunner

@testmodule BrowserFixtures begin
    using HTMXObjects
    export Lines, StaleCaption, ServerTwin, OpaqueHelp, ToggledDefault, FollowingDefault, ChosenDefault, ChosenStale,
           FixedRanges, RangesPage, InputRange, Shield, Grid, TermSite, Window, WINDOW_START, Doses, DOSE_TEXTS, TOY_JS,
           Halving, browser_region, bound_texts

    # A module in the contract `ReactiveKernels.js_source` emits: positional
    # arguments in `INPUTS` order, a named tuple returned as an object, and a
    # `JuliaError` named by the Julia exception.
    const TOY_JS = """
    export class JuliaError extends Error {
      constructor(type, message) { super(message); this.name = type; }
    }
    export function toy(grid, a, b, lim, z) {
      if (b < 0) throw new JuliaError("DomainError", "toy was called with b = " + b + "; it must be nonnegative");
      const n = grid.length, x = new Array(n), y = new Array(n);
      for (let i = 0; i < n; i++) { x[i] = grid[i]; y[i] = a * grid[i] + b; }
      // `lim` and `z` echo embedded data that JSON alone cannot carry: Inf and -0.0.
      return { x, y, total: a + b, at: [a + b, 2 * a + b], lim, z,
               ok: [lim === Infinity ? 1 : 0, Object.is(z, -0) ? 1 : 0] };
    }
    export const INPUTS = [{ name: "grid", type: "Vector{Float64}" }, { name: "a", type: "Float64" },
      { name: "b", type: "Float64" }, { name: "lim", type: "Float64" }, { name: "z", type: "Float64" }];
    export const OUTPUTS = [{ name: "x" }, { name: "y" }, { name: "total" }, { name: "at" }, { name: "lim" },
      { name: "z" }, { name: "ok" }];
    """

    @htmx struct Lines
        "Slope"
        @param a::Float64 = 2.0
        # A range (a slider with a number field): continuous, never a view per value.
        # Its `step` is the slider's grid; a typed number need only lie in the range.
        @options(a) = number_domain(0.0, 10.0; step = 0.5)
        "Intercept"
        @param b::Float64 = 1.0
        "Show"
        @param show::Symbol = :line
        @options(show) = [:line, :total]
        "Extra"
        @param extra::Float64 = 0.5
        # Arithmetic of inputs: evaluated in the browser.
        @relevant(extra) = a * b > 10
        grid = [0.0, 1.0, 2.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        __page__(content) = HTMXObjects.htmx(content; title = "Lines", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = show == :line ?
            h.div(h.p("total ", bound(line.total); class = "total"),
                  h.p("second ", bound(line.at[2]); class = "second"),
                  h.p("slope ", bound(a), " extra ", bound(extra; digits = 2)),
                  h.div(; id = "plot1", bound_columns_attrs(bound(line; columns = (:x, :y)))...),
                  # A single value: a table of one row, such as a rule's.
                  h.div(; id = "rule1", bound_columns_attrs(bound(line; columns = (:total,)))...),
                  h.p(bound(line.lim), " ", bound(line.z), " ", bound(line.ok[1]), bound(line.ok[2]);
                      class = "echo")) :
            h.p("total only ", bound(line.total; digits = 1); class = "total")
    end

    # A caption that shows an input outside `bound`: stale on a static page.
    @htmx struct StaleCaption
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total), " for slope ", string(a))
    end

    # A second result that reads the inputs and computes nothing in the browser.
    @htmx struct ServerTwin
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
        "Twice"
        @get twice() = h.p("twice ", string(2 * (a + b)))
    end

    # A control whose help text the server draws again when another input changes.
    @htmx struct OpaqueHelp
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        @help(b) = string("now ", a)
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total), " ", bound(b))
    end

    const OFFSET_JS = """
    export function offset(a, on, b) { return { total: a + (on ? b : 0) }; }
    export const INPUTS = [{ name: "a", type: "Float64" }, { name: "on", type: "Bool" },
      { name: "b", type: "Float64" }];
    """

    # An input a toggle hides, whose default is computed from a fixed field and
    # so reads no input: only its `@relevant` condition reads `on`, which the
    # browser evaluates (snag `export-site-rele-5a6fd953`).
    @htmx struct ToggledDefault
        settings::Any = (; start = 1.5)
        "Slope"
        @param a::Float64 = 2.0
        "Add an intercept"
        @param on::Bool = true
        "Intercept"
        @param b::Float64 = Float64(settings.start)
        @options(b) = number_domain(0.0, 10.0)
        @relevant(b) = on == true
        line = (; total = a + (on ? b : 0.0))
        @browser(line) = browser_module(; source = OFFSET_JS, entry = :offset)
        __page__(content) = HTMXObjects.htmx(content; title = "Toggled", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
    end

    # The same input with a default the server computes from another input.
    @htmx struct FollowingDefault
        "Slope"
        @param a::Float64 = 2.0
        "Add an intercept"
        @param on::Bool = true
        "Intercept"
        @param b::Float64 = a / 2
        @options(b) = number_domain(0.0, 10.0)
        @relevant(b) = on == true
        line = (; total = a + (on ? b : 0.0))
        @browser(line) = browser_module(; source = OFFSET_JS, entry = :offset)
        __page__(content) = HTMXObjects.htmx(content; title = "Following", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
    end

    const SUM_JS = """
    export function sum(a, b) { return { total: a + b }; }
    export const INPUTS = [{ name: "a", type: "Float64" }, { name: "b", type: "Float64" }];
    """

    # Ranges an application supplies: `@options` that read a fixed field with
    # a default (`a`) or a property computed from one (`b`) read no input
    # (snag `export-site-opti-97b7d7a9`).
    @htmx struct FixedRanges
        limits::Any = (; a = (0.0, 2.0))
        scale::Float64 = 3.0
        upper = 2scale
        "A"
        @param a::Float64 = 1.0
        @options(a) = number_domain(limits.a...; digits = 3)
        "B"
        @param b::Float64 = 0.5
        @options(b) = number_domain(0.0, upper; digits = 3)
        line = (; total = a + b)
        @browser(line) = browser_module(; source = SUM_JS, entry = :sum)
        __page__(content) = HTMXObjects.htmx(content; title = "Ranges", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
    end

    # One view drawn with the ranges its page hands it.
    @htmx struct RangesView
        limits::Any = nothing
        "A"
        @param a::Float64 = 1.0
        @options(a) = number_domain(limits.a...; digits = 3)
        "B"
        @param b::Float64 = 0.5
        @options(b) = number_domain(limits.b...; digits = 3)
        line = (; total = a + b)
        @browser(line) = browser_module(; source = SUM_JS, entry = :sum)
        "Result"
        @get result() = h.p("total ", bound(line.total))
    end
    @htmx struct RangesPage
        limits::Any = (; a = (0.0, 4.0), b = (0.0, 5.0))
        @include view = RangesView(; limits)
        __page__(content) = HTMXObjects.htmx(content; title = "Mounted ranges", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(view; presentation = :tabs))
    end

    # A range that reads an input through a property: the server draws `a`
    # again when `b` changes.
    @htmx struct InputRange
        "A"
        @param a::Float64 = 1.0
        upper = 2b
        @options(a) = number_domain(0.0, upper; digits = 3)
        "B"
        @param b::Float64 = 0.5
        @options(b) = number_domain(0.0, 1.0; digits = 3)
        line = (; total = a + b)
        @browser(line) = browser_module(; source = SUM_JS, entry = :sum)
        __page__(content) = HTMXObjects.htmx(content; title = "Input range", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p("total ", bound(line.total))
    end

    const CHOSEN_JS = """
    export function scaled(family, scale) { return { y: family === 0 ? scale : 2 * scale }; }
    export const INPUTS = [{ name: "family", type: "Int64" }, { name: "scale", type: "Float64" }];
    """

    # A finite input and a continuous one whose defaults are computed from a
    # fixed field, so both follow their defaults until the reader sets them
    # (snag `static-export-fi-2f405405`, Portfolio's prior-families picture).
    @htmx struct ChosenDefault
        settings::Any = (; family = 0, scale = 0.3)
        "Family"
        @param family::Int = Int(settings.family)
        @options(family) = [0 => "Exponential", 1 => "Log-normal"]
        "Scale"
        @param scale::Float64 = Float64(settings.scale)
        @options(scale) = number_domain(0.1, 2; step = 0.1, digits = 2)
        out = (; y = family == 0 ? scale : 2 * scale)
        @browser(out) = browser_module(; source = CHOSEN_JS, entry = :scaled)
        __page__(content) = HTMXObjects.htmx(content; title = "Chosen", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.div(h.p(family == 0 ? "exponential sentence" : "log-normal sentence"; class = "fact"),
                              h.p(bound(out.y; digits = 2)))
    end

    # The same inputs, with the continuous one shown outside `bound`: stale on
    # a static page.
    @htmx struct ChosenStale
        settings::Any = (; family = 0, scale = 0.3)
        "Family"
        @param family::Int = Int(settings.family)
        @options(family) = [0 => "Exponential", 1 => "Log-normal"]
        "Scale"
        @param scale::Float64 = Float64(settings.scale)
        @options(scale) = number_domain(0.1, 2; step = 0.1, digits = 2)
        out = (; y = family == 0 ? scale : 2 * scale)
        @browser(out) = browser_module(; source = CHOSEN_JS, entry = :scaled)
        __page__(content) = HTMXObjects.htmx(content; title = "Stale", assets = "assets/vendor",
                                             runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p(bound(out.y; digits = 2), " at scale ", string(scale))
    end

    # The snow-shielding picture's facts and table (Portfolio's client
    # visualizer): rational functions only, so the browser computes the same
    # Float64 as the server and the two write identical cells.
    const SHIELD_JS = """
    export function shield(water, attenuation) {
      return { water, depth: water.map(w => w / 2.5), share: water.map(w => 1 / (1 + attenuation * w)),
               half: 1 / attenuation, at: [1 / (1 + attenuation * 20), 1 / (1 + attenuation * 100)] };
    }
    export const INPUTS = [{ name: "water", type: "Vector{Float64}" }, { name: "attenuation", type: "Float64" }];
    """

    @htmx struct Shield
        "Attenuation per mm of snow water"
        @param attenuation::Float64 = 0.01
        @options(attenuation) = number_domain(0.005, 0.02)
        water = [0.0, 20.0, 50.0, 100.0]
        shield = (; water, depth = water ./ 2.5, share = 1 ./ (1 .+ attenuation .* water), half = 1 / attenuation,
                  at = [1 / (1 + attenuation * 20), 1 / (1 + attenuation * 100)])
        @browser(shield) = browser_module(; source = SHIELD_JS, entry = :shield)
        __page__(content) = HTMXObjects.htmx(content; title = "Shield", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "What the snow lets through"
        @get picture() = h.div(h.p(bound(shield.half; digits = 0), " mm of water"; class = "half"),
            h.p(bound(shield.at[1]; percent = true, digits = 0), " and ",
                bound(shield.at[2]; percent = true, digits = 0); class = "at"),
            h.p(bound(shield.at[1]; digits = 3, texts = table_texts(:de)); class = "de"),
            render_table(bound(shield; columns = (:water, :depth, :share));
                columns = [:water => ColumnSpec("Snow water (mm)"; digits = 0), :depth => ColumnSpec("Depth (cm)"; digits = 0),
                           :share => ColumnSpec("Share passing"; digits = 3)],
                link = "shield", link_key = :water),
            # A single-value output is a table of one row, redrawn the same way.
            render_table(bound(shield; columns = (:half,)); columns = [:half => ColumnSpec("Half (mm)"; digits = 0)]))
    end

    # A year's window of a daily series (Portfolio's snow article, snag
    # show-a-year-s-wi-b018d869): the module returns numbers only, so a day is
    # its milliseconds since 1970 (UTC) and a day without a reading is NaN.
    const WINDOW_START = 1_569_888_000_000.0  # 1 October 2019, 00:00 UTC
    const WINDOW_JS = """
    export function yearWindow(start, reading, shift) {
      const t = reading.map((r, i) => start + (i + shift) * 86400000);
      return { t, read: reading, peak: t[2], none: NaN };
    }
    export const INPUTS = [{ name: "start", type: "Float64" }, { name: "reading", type: "Vector{Float64}" },
      { name: "shift", type: "Float64" }];
    """
    function year_window(start, reading, shift)
        t = [start + (i - 1 + shift) * 86400000.0 for i in eachindex(reading)]
        (; t, read = reading, peak = t[3], none = NaN)
    end

    @htmx struct Window
        "Days after 1 October 2019"
        @param shift::Float64 = 0.0
        @options(shift) = number_domain(0, 400)
        start = WINDOW_START
        reading = [1.5, NaN, 3.25, 2.0]
        window = year_window(start, reading, shift)
        @browser(window) = browser_module(; source = WINDOW_JS, entry = :yearWindow)
        __page__(content) = HTMXObjects.htmx(content; title = "Window", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "The year's readings"
        @get days() = h.div(h.p("on ", bound(window.peak; date = :long); class = "peak"),
            h.p(bound(window.peak; date = :short, texts = table_texts(:de)), " ", bound(window.peak; date = :month); class = "peak-de"),
            h.p(bound(window.none), " ", bound(window.none; date = :short); class = "none"),
            render_table(bound(window; columns = (:t, :read)); id = "days",
                columns = [:t => ColumnSpec("Day"; date = :short), :read => ColumnSpec("Reading"; digits = 1)]),
            render_table(bound(window; columns = (:t,)); id = "tage", texts = table_texts(:de),
                columns = [:t => ColumnSpec("Tag"; date = :long)]))
    end

    # The dose levels two rules recommend (Portfolio's dose report, snag
    # bound-cannot-sho-5a0dbf64): the module returns whole numbers, 0 for no
    # dose, and the page writes each as the text the original picture shows.
    # A risk above 1.2 gives level 6, which the labels do not name.
    const DOSE_TEXTS = [0 => "No dose", 1 => "50 mg (level 1)", 2 => "100 mg (level 2)",
                        3 => "200 mg (level 3)", 4 => "300 mg (level 4)", 5 => "400 mg (level 5)"]
    const DOSES_JS = """
    export function doseRules(risk) {
      const paper = Math.floor(risk * 5), mtd = paper > 0 ? paper - 1 : 0;
      return { paper, mtd, dosed: paper > 0, rule: [1, 2], level: [paper, mtd] };
    }
    export const INPUTS = [{ name: "risk", type: "Float64" }];
    """
    function dose_rules(risk)
        paper = floor(Int, risk * 5)
        mtd = paper > 0 ? paper - 1 : 0
        (; paper, mtd, dosed = paper > 0, rule = [1, 2], level = [paper, mtd])
    end

    @htmx struct Doses
        "Risk"
        @param risk::Float64 = 0.5
        @options(risk) = number_domain(0, 1.4)
        rules = dose_rules(risk)
        @browser(rules) = browser_module(; source = DOSES_JS, entry = :doseRules)
        __page__(content) = HTMXObjects.htmx(content; title = "Doses", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "The rules' doses"
        @get facts() = h.div(h.p(bound(rules.paper; labels = DOSE_TEXTS); class = "paper"),
            h.p(bound(rules.mtd; labels = Dict(DOSE_TEXTS)); class = "mtd"),
            h.p(bound(rules.dosed; labels = [true => "Dosed", false => "Not dosed"]); class = "dosed"),
            render_table(bound(rules; columns = (:rule, :level)); id = "rules",
                columns = [:rule => ColumnSpec("Rule"; labels = [1 => "Paper's rule", 2 => "MTD rule"]),
                           :level => ColumnSpec("Dose"; labels = DOSE_TEXTS)]))
    end

    const HALVING_JS = """
    export function halving(slope) {
      const half = slope === 2 ? NaN : slope === -2 ? -Infinity : 1 / slope;
      return {half, values: [half, 2.125, 0]};
    }
    export const INPUTS = [{name: "slope", type: "Float64"}];
    """
    const HALF_LABELS = [Inf => "No finite halving time", -Inf => "Negative infinity", 0.0 => "None"]
    @htmx struct Halving
        "Slope"
        @param slope::Float64 = 0.5
        @options(slope) = number_domain(-2, 2)
        prediction = (; half = slope == 2 ? NaN : slope == -2 ? -Inf : 1 / slope,
                        values = [slope == 2 ? NaN : slope == -2 ? -Inf : 1 / slope, 2.125, 0.0])
        @browser(prediction) = browser_module(; source = HALVING_JS, entry = :halving)
        __page__(content) = HTMXObjects.htmx(content; title = "Halving", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Halving time"
        @get facts() = h.div(h.p(bound(prediction.half; digits = 1, labels = HALF_LABELS, unit = "years"); class = "half"),
            h.p(bound(prediction.half; sigdigits = 2, labels = HALF_LABELS, unit = "Jahre", texts = table_texts(:de)); class = "half-de"),
            render_table(bound(prediction; columns = (:values,)); id = "halving", searchable = true,
                columns = [:values => ColumnSpec("Years"; digits = 1, labels = HALF_LABELS)]))
    end

    # Matrix data in the shape `ReactiveKernels.js_source` modules take
    # (RK 0.1.264, decision `1r7ufgm`): the array of its rows, rows of one
    # length (arrays or typed arrays), and a matrix without rows as an empty
    # array whose `cols` is its column count. The module checks its inputs as
    # RK's `_rk_matrix` does, so a page that passed columns, a flat run or a
    # bare `[]` for `zeros(0, 3)` would read other numbers or raise.
    const GRID_JS = """
    export class JuliaError extends Error {
      constructor(type, message) { super(message); this.name = type; }
    }
    function cols(name, x, element) {
      if (!Array.isArray(x)) throw new JuliaError("ArgumentError", "the input `" + name + "` must be an array of rows; got " + x);
      for (let i = 0; i < x.length; i++) {
        const r = x[i];
        if (!(Array.isArray(r) || ArrayBuffer.isView(r)) || r.length !== x[0].length)
          throw new JuliaError("ArgumentError", "the input `" + name + "` must have rows of one length");
        for (let j = 0; j < r.length; j++)
          if (typeof r[j] !== element) throw new JuliaError("ArgumentError", "the input `" + name + "` must hold " + element + "s");
      }
      if (x.length === 0 && x.cols !== undefined && !Number.isInteger(x.cols))
        throw new JuliaError("ArgumentError", "the input `" + name + "` has no rows and a column count of " + x.cols);
      return x.length > 0 ? x[0].length : Number.isInteger(x.cols) ? x.cols : 0;
    }
    export function grid(m, none, wide, flags, scale) {
      const n = cols("m", m, "number"), nn = cols("none", none, "number"), nw = cols("wide", wide, "number");
      cols("flags", flags, "boolean");
      return { corner: m[0][1] * scale, last: m[m.length - 1][n - 1] * scale, size: [m.length, n],
               none: [none.length, nn], wide: [wide.length, nw],
               inf: m[1][0] === Infinity ? 1 : 0, flag: flags[1][0] ? 1 : 0 };
    }
    export const INPUTS = [{ name: "m", type: "Matrix{Float64}" }, { name: "none", type: "Matrix{Float64}" },
      { name: "wide", type: "Matrix{Float64}" }, { name: "flags", type: "Matrix{Bool}" }, { name: "scale", type: "Float64" }];
    """

    @htmx struct Grid
        "Scale"
        @param scale::Float64 = 1.0
        # Read by rows `m[1, 2]` is 2; a column-major page would hand the
        # module 5 there, and `flags[2, 1]` would read false.
        m = [1.0 2.0 3.0; Inf 5.0 6.0]
        none = zeros(0, 3)
        wide = zeros(2, 0)
        flags = [false false; true false]
        grid = (; corner = m[1, 2] * scale, last = m[end, end] * scale, size = [size(m)...],
                none = [size(none)...], wide = [size(wide)...],
                inf = m[2, 1] == Inf ? 1 : 0, flag = flags[2, 1] ? 1 : 0)
        @browser(grid) = browser_module(; source = GRID_JS, entry = :grid)
        __page__(content) = HTMXObjects.htmx(content; title = "Grid", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.p(bound(grid.corner), " ", bound(grid.last), " ", bound(grid.size[1]), "x",
                            bound(grid.size[2]), " ", bound(grid.none[1]), "x", bound(grid.none[2]), " ",
                            bound(grid.wide[1]), "x", bound(grid.wide[2]), " ", bound(grid.inf), bound(grid.flag);
                            class = "grid")
    end

    # Results whose markup differs between two answers of the same inputs
    # (snag browser-result-u-88fa1fae). `result` uses a term of the site's
    # glossary, whose link carries an id that is new in every answer; `shown`
    # also shows an input outside `bound`; `own` writes an id of its own; and
    # `growing` holds one more element every time it is rendered.
    const RENDERS = Ref(0)
    @htmx struct TermLine
        "Slope"
        @param a::Float64 = 2.0
        "Intercept"
        @param b::Float64 = 1.0
        grid = [0.0, 1.0]
        lim = Inf    # an unbounded limit: data, not a missing value
        z = -0.0
        line = (; x = grid, y = a .* grid .+ b, total = a + b, at = [a + b, 2a + b], lim, z,
                ok = [lim == Inf ? 1 : 0, signbit(z) ? 1 : 0])
        @browser(line) = browser_module(; source = TOY_JS, entry = :toy)
        "Result"
        @get result() = h.p("The widget total is ", bound(line.total), ".")
        "Slope shown"
        @get shown() = h.p("The widget total is ", bound(line.total), " for slope ", string(a), ".")
        "Own id"
        @get own() = h.p("total ", bound(line.total); id = string("own-", rand(UInt64)))
        "Growing"
        @get growing() = h.p("total ", bound(line.total), (h.b("+") for _ in 1:(RENDERS[] += 1))...)
    end

    # The shape of Portfolio's dose article: a site that declares a glossary
    # and mounts the picture.
    @htmx struct TermSite
        __glossary__ = Glossary([GlossaryTerm("Widget", "A thing."; forms = ["widget"])]; href = "", title = "Glossary")
        @include line = TermLine()
        __page__(content) = HTMXObjects.htmx(content; title = "Terms", assets = "assets/vendor", runtime = :linked)
        @get index() = h.main(semantic_app(line; presentation = :tabs, select = e -> e.name == :result))
        @get shown() = h.main(semantic_app(line; presentation = :tabs, select = e -> e.name == :shown))
        @get own() = h.main(semantic_app(line; presentation = :tabs, select = e -> e.name == :own))
        @get growing() = h.main(semantic_app(line; presentation = :tabs, select = e -> e.name == :growing))
    end

    browser_region(html) = match(r"<div id=\"[^\"]*-result\"[^>]*data-htmxo-browser=[^>]*>", html)
    bound_texts(html) = [m.captures[1] for m in eachmatch(r"<span data-htmxo-bound=\"[^\"]*\"[^>]*>([^<]*)</span>", html)]
end

@testitem "@browser declares a property the browser computes, bound marks where it shows" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    @test HTMXObjects._browser_properties(Lines) == (:line,)
    @test HTMXObjects._browser_properties(Int) == ()
    m = getproperty(Lines(), HTMXObjects._browser_property(:line))
    @test m isa BrowserModule
    @test m.entry == "toy"
    @test m.inputs == [("grid", "Vector{Float64}"), ("a", "Float64"), ("b", "Float64"),
                       ("lim", "Float64"), ("z", "Float64")]
    # The operation reads its browser property and the inputs it is computed from.
    reads = HTMXObjects._operation_reads(Lines, :result)
    @test reads.complete
    @test issubset([:a, :b, :show, :extra, :line], reads.names)
    @test HTMXObjects._browser_reads(Lines(), :result) == [:line]

    # A @param comes from its control; `bound` names a path.
    # The macro runs where `@htmx` is defined: `using` first, then the struct.
    function err(ex)
        m = Module()
        Core.eval(m, :(using HTMXObjects))
        try
            Core.eval(m, ex)
            nothing
        catch e
            e isa LoadError ? e.error : e
        end
    end
    e1 = err(:(@htmx struct B1
        @param a::Float64 = 1.0
        @browser(a) = browser_module(; source = "", entry = :f)
    end))
    @test e1 isa ArgumentError && occursin("names a `@param`", e1.msg)
    e2 = err(:(@htmx struct B2
        @param a::Float64 = 1.0
        @get r() = h.p(bound(a + 1))
    end))
    @test e2 isa ArgumentError && occursin("`bound` takes a property or `@param` name", e2.msg)
    @test_throws ArgumentError HTMXObjects.bound(1.0)
end

@testitem "browser_module reads its module's entry and arguments" tags=[:unit, :semantic] begin
    using HTMXObjects
    m = browser_module(; source = "export function f(x, y) { return x; }\nexport const INPUTS = [{ name: \"x\", type: \"Float64\" }, { \"name\": \"y\", \"type\": \"Vector{Int64}\" }];", entry = :f)
    @test m.inputs == [("x", "Float64"), ("y", "Vector{Int64}")]
    @test_throws ArgumentError browser_module(; source = "export const INPUTS = [];", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {}", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {} export const INPUTS = []; // </script>", entry = :f)
    @test_throws ArgumentError browser_module(; source = "export function f() {}", entry = "not a name")
    mktemp() do path, io
        write(io, "export function g(a) { return a; }\nexport const INPUTS = [{ name: \"a\", type: \"Float64\" }];")
        close(io)
        @test browser_module(path, :g).inputs == [("a", "Float64")]
        @test browser_module(path, :g) === browser_module(path, :g)
    end
    @test_throws ArgumentError browser_module("/no/such/module.mjs", :g)
end

@testitem "a browser result carries its views, bindings, module and bound values" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON
    route!(Lines(); operation_policy = :blocking)
    html = String(HTMXObjects._response_bytes(dispatch(:GET, "/"; headers = ["HX-Request" => "true"])))
    region = browser_region(html)
    @test region !== nothing
    @test occursin("data-htmxo-follow=\"/result\"", region.match)
    # The view at the current values, and one template per value of the finite input.
    @test count("<div class=\"htmxo-browser-view\"", html) == 1
    @test count("<template data-htmxo-variant=", html) == 2
    @test occursin("data-htmxo-number=", html)  # `a`'s range control
    # Numbers as `format_number` writes them: `extra` with exactly two decimals.
    @test bound_texts(html)[1:4] == ["3", "5", "2", "0.50"]
    # The binding: the module's arguments in its order, data embedded once.
    binding = JSON.parse(match(r"<script type=\"application/json\" id=\"[^\"]*\" data-htmxo-browser-binding=\"\">([^<]*)</script>", html).captures[1])
    @test binding["entry"] == "toy"
    @test [i["name"] for i in binding["inputs"]] == ["grid", "a", "b", "lim", "z"]
    # Non-finite data travels tagged (JSON has no Inf); -0.0 keeps its sign.
    @test binding["inputs"][4]["value"] == Dict("\$f" => "Inf")
    @test binding["inputs"][5]["value"] == 0.0 && signbit(binding["inputs"][5]["value"])
    @test binding["inputs"][1]["value"] == [0.0, 1.0, 2.0]
    @test binding["inputs"][2]["param"] == "a" && binding["inputs"][2]["default"] == ["2.0"]
    @test count("data-htmxo-browser-module=\"\"", html) == 1
    @test count("window.__htmxoSemanticBrowser = true", html) == 1
    # Arithmetic relevance is a browser predicate, not a server refresh.
    @test occursin("&quot;cmp&quot;:&quot;gt&quot;", html)
    @test !occursin("data-htmxo-depends", html)
    # The bound columns name the element that shows them.
    @test occursin("data-htmxo-bound-columns=", html)
    # Text peers show the values.
    plain = String(HTMXObjects._response_bytes(dispatch(:GET, "/result?a=3&b=4&plain=1")))
    @test occursin(r"total 7(?![.\d])", plain) && occursin(r"second 10(?![.\d])", plain) && occursin(r"slope 3(?![.\d])", plain)
    @test HTMXObjects._browser_skeleton("<p><span data-htmxo-bound=\"[&quot;a&quot;]\" data-htmxo-kind=\"float\">2.0</span> <div id=\"p\" data-htmxo-bound-columns=\"x\"><div><script>var s = '</div>';</script>1</div></div></p>") ==
          "<p><span data-htmxo-bound=\"[&quot;a&quot;]\" data-htmxo-kind=\"float\"></span> <div id=\"p\" data-htmxo-bound-columns=\"x\"></div></p>"
end

@testitem "a browser module takes matrix data as the array of its rows" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON
    # Snag browser-module-m-1d4c9b53: a Matrix argument was refused with a 500.
    route!(Grid(); operation_policy = :blocking)
    response = dispatch(:GET, "/"; headers = ["HX-Request" => "true"])
    @test response.status == 200
    html = String(HTMXObjects._response_bytes(response))
    binding = JSON.parse(match(r"<script type=\"application/json\" id=\"[^\"]*\" data-htmxo-browser-binding=\"\">([^<]*)</script>", html).captures[1])
    values = Dict(i["name"] => get(i, "value", nothing) for i in binding["inputs"])
    # Rows in order, `m[i][j]` Julia's `m[i+1, j+1]`; Inf tagged inside a row.
    @test values["m"] == Any[Any[1.0, 2.0, 3.0], Any[Dict("\$f" => "Inf"), 5.0, 6.0]]
    # No rows: the column count, which `[]` cannot carry; no columns: empty rows.
    @test values["none"] == Dict("\$cols" => 3)
    @test values["wide"] == Any[Any[], Any[]]
    @test values["flags"] == Any[Any[false, false], Any[true, false]]
    @test binding["inputs"][end]["param"] == "scale"
    @test bound_texts(html) == ["2", "6", "2", "3", "0", "3", "2", "0", "1", "1"]
    # Any AbstractMatrix, by its axes; 0×0 is `[]`.
    @test HTMXObjects._browser_data([1 2; 3 4]', "x") == Any[Any[1, 3], Any[2, 4]]
    @test HTMXObjects._browser_data(zeros(0, 0), "x") == Any[]
    @test HTMXObjects._browser_data(BitMatrix([1 0]), "x") == Any[Any[true, false]]
    # Higher dimensions stay refused, naming what the page passes.
    err = try HTMXObjects._browser_data(zeros(2, 2, 2), "cube"); nothing catch e; e end
    @test err isa ArgumentError && occursin("`cube` is a Array{Float64, 3}", err.msg) &&
          occursin("vectors and matrices of them", err.msg)
end

@testitem "bound(…; columns) stays bound inside a plot's data: it is its own Tables.columns" tags=[:unit, :semantic] begin
    using HTMXObjects, Tables
    # Made by the macro's lowering of `bound`, as a view writes it.
    m = Module()
    Core.eval(m, :(using HTMXObjects))
    Core.eval(m, :(@htmx struct Plotted
        grid = [0.0, 1.0, 2.0]
        line = (; x = grid, y = 2 .* grid .+ 1, total = 9.0)
        table = bound(line; columns = (:x, :y))
    end))
    b = Core.eval(m, :(Plotted().table))
    @test b isa HTMXObjects.BoundColumns
    # AlgebraOfGraphics' `data(b)` keeps `Columns(Tables.columns(b))`: that is `b`,
    # so a plotting package reading the layer's data back can mark its element.
    cols = Tables.columns(b)
    @test cols === b
    @test bound_columns_attrs(cols; dataset = "d") == bound_columns_attrs(b; dataset = "d")
    @test occursin("\"path\":[\"line\"]", bound_columns_attrs(cols).data_htmxo_bound_columns)
    # The Tables.jl column interface AlgebraOfGraphics (`getcolumn`,
    # `columnnames`, `rows`) and AlgebraOfVega (`rowtable`) read it through.
    @test Tables.istable(b) && Tables.columnaccess(b)
    @test Tables.columnnames(cols) == (:x, :y)
    @test Tables.getcolumn(cols, :y) == [1.0, 3.0, 5.0]
    @test Tables.getcolumn(cols, 1) == [0.0, 1.0, 2.0]
    @test Tables.schema(b) == Tables.Schema((:x, :y), (Float64, Float64))
    @test Tables.columntable(b) == (x = [0.0, 1.0, 2.0], y = [1.0, 3.0, 5.0])
    @test Tables.rowtable(b) == [(x = 0.0, y = 1.0), (x = 1.0, y = 3.0), (x = 2.0, y = 5.0)]
    @test length(Tables.rows(cols)) == 3
    # Its columns are the chosen outputs only, and an error names the property.
    e = try; Tables.getcolumn(b, :total); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("the table of line has the columns x, y, not `total`", e.msg)
    # The path the lowering passes holds symbols: errors name it too.
    e2 = try; HTMXObjects._bound((:line, :fit), (; x = [1.0]); columns = (:x, :nope)); nothing; catch err; err; end
    @test e2 isa ArgumentError && occursin("line.fit has no output `nope`", e2.msg)
end

@testitem "bound(…; columns) of single-value outputs is a table of one row" tags=[:unit, :semantic] begin
    using HTMXObjects, Tables
    m = Module()
    Core.eval(m, :(using HTMXObjects))
    Core.eval(m, :(@htmx struct Ruled
        grid = [0.0, 1.0, 2.0]
        prediction = (; water = grid, share = 2 .* grid, half = 1.5, n = 3, label = "half")
        curves = bound(prediction; columns = (:water, :share))
        rule = bound(prediction; columns = (:half,))
        marks = bound(prediction; columns = (:half, :n, :label))
    end))
    rule = Core.eval(m, :(Ruled().rule))
    @test rule isa HTMXObjects.BoundColumns
    @test Tables.columns(rule) === rule
    @test Tables.columnnames(rule) == (:half,)
    @test Tables.getcolumn(rule, :half) == [1.5]
    @test Tables.getcolumn(rule, 1) == [1.5]
    @test Tables.schema(rule) == Tables.Schema((:half,), (Float64,))
    @test Tables.rowtable(rule) == [(half = 1.5,)]
    # The same table as a length-1 vector output gives, which a plot already draws.
    @test Tables.columntable(rule) ==
          Tables.columntable(HTMXObjects._bound((:prediction,), (; half = [1.5]); columns = (:half,)))
    @test occursin("\"columns\":[\"half\"]", bound_columns_attrs(rule).data_htmxo_bound_columns)
    marks = Core.eval(m, :(Ruled().marks))
    @test Tables.schema(marks) == Tables.Schema((:half, :n, :label), (Float64, Int, String))
    @test Tables.rowtable(marks) == [(half = 1.5, n = 3, label = "half")]
    # Vector outputs are unchanged beside it.
    @test Tables.rowtable(Core.eval(m, :(Ruled().curves)))[3] == (water = 2.0, share = 4.0)
    # A table does not mix single values and vectors: the error names both and
    # the table the single values can have.
    value = (; water = [1.0, 2.0], share = [0.5, 0.25], half = 1.5, n = 3, grid = [1 2; 3 4])
    e = try; HTMXObjects._bound((:prediction,), value; columns = (:water, :half, :share, :n)); nothing; catch err; err; end
    @test e isa ArgumentError
    @test e !== nothing && occursin("the outputs `half`, `n` (single values) and `water`, `share` (vectors) of prediction cannot share a table", e.msg)
    @test e !== nothing && occursin("bound(prediction; columns = (:half, :n))", e.msg)
    e1 = try; HTMXObjects._bound((:prediction,), value; columns = (:half, :water)); nothing; catch err; err; end
    @test e1 !== nothing && occursin("bound(prediction; columns = (:half,))", e1.msg)
    # An output that is neither a vector nor a single number or text is refused.
    e2 = try; HTMXObjects._bound((:prediction,), value; columns = (:grid,)); nothing; catch err; err; end
    @test e2 isa ArgumentError && occursin("prediction.grid is a Matrix{Int64}, neither a vector nor a single number or text", e2.msg)
end

@testitem "export_site writes a browser page and names what a static page would show stale" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(Lines(); operation_policy = :blocking)
    HTMXObjects.vendorfiles("assets/vendor")
    mktempdir() do dir
        out = export_site(joinpath(dir, "site"); pages = ["/"])
        @test out.files > 0
        index = read(joinpath(dir, "site", "index.html"), String)
        @test occursin("data-htmxo-browser=", index)
        # The result is in the page; no fragment file is written for it.
        fragments = joinpath(dir, "site", "hx")
        @test !any(f -> startswith(f, "result"), isdir(fragments) ? readdir(fragments) : String[])
    end
    for (T, phrase) in ((StaleCaption, "shows `a` outside `bound`"),
                        (ServerTwin, "the result `twice` reads `a`, `b` but computes nothing in the browser"),
                        (OpaqueHelp, "the server draws the control of `b` again when other inputs change (its `@help` text reads other inputs)"))
        route!(T(); operation_policy = :blocking)
        mktempdir() do dir
            e = try
                export_site(joinpath(dir, "site"); pages = ["/"])
                nothing
            catch err
                err
            end
            @test e isa HTMXObjects.StaticSiteIncomplete
            @test e !== nothing && any(((a, why),) -> a == "/" && occursin(phrase, why), e.failed)
        end
    end
end

@testitem "export_site writes a toggled input whose default reads no input, and names the inputs a default reads" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    HTMXObjects.vendorfiles("assets/vendor")
    # The default of `b` reads a fixed field. What its `@relevant` condition
    # reads (`on`) is no input of the default, so no server draws `b` again.
    route!(ToggledDefault(); operation_policy = :blocking)
    mktempdir() do dir
        out = export_site(joinpath(dir, "site"); pages = ["/"])
        @test out.files > 0
        index = read(joinpath(dir, "site", "index.html"), String)
        @test occursin("data-htmxo-browser=", index)
        @test occursin("data-htmxo-relevant=\"b\"", index)
    end
    # A default that does read an input is still refused, and the refusal
    # names that input and not the one the condition reads.
    route!(FollowingDefault(); operation_policy = :blocking)
    mktempdir() do dir
        e = try
            export_site(joinpath(dir, "site"); pages = ["/"])
            nothing
        catch err
            err
        end
        @test e isa HTMXObjects.StaticSiteIncomplete
        @test e !== nothing && any(((a, why),) -> a == "/" && occursin(
            "the server draws the control of `b` again when other inputs change (its default reads `a`)", why), e.failed)
    end
end

@testitem "export_site writes controls whose @options read fixed fields, and names the inputs @options read" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    HTMXObjects.vendorfiles("assets/vendor")
    # Ranges from a fixed field with a default, from a property computed from
    # one, and handed to a mounted view by its page: no control of the page
    # changes them, so the export writes the page with those ranges.
    for (T, uppers) in ((FixedRanges, ("2.0", "6.0")), (RangesPage, ("4.0", "5.0")))
        route!(T(); operation_policy = :blocking)
        mktempdir() do dir
            out = export_site(joinpath(dir, "site"); pages = ["/"])
            @test out.files > 0
            index = read(joinpath(dir, "site", "index.html"), String)
            @test occursin("data-htmxo-browser=", index)
            @test all(upper -> occursin("upper&quot;:" * upper, index), uppers)
        end
    end
    # A range that reads an input through a property is still refused, and
    # the refusal names the input, not the property.
    route!(InputRange(); operation_policy = :blocking)
    mktempdir() do dir
        e = try
            export_site(joinpath(dir, "site"); pages = ["/"])
            nothing
        catch err
            err
        end
        @test e isa HTMXObjects.StaticSiteIncomplete
        @test e !== nothing && any(((a, why),) -> a == "/" && occursin(
            "the server draws the control of `a` again when other inputs change (its `@options` read `b`)", why), e.failed)
    end
end

@testitem "a live page draws a control again when an input its @options read through a property changes" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(InputRange(); operation_policy = :blocking)
    page = String(HTMXObjects.dispatch(:GET, "/").body)
    # The control of `b` asks the server for the controls when it changes.
    m = match(r"<div[^>]*hx-get=\"([^\"]*)\"[^>]*hx-trigger=\"change\"[^>]*>.{0,600}?name=\"(\w+)\""s, page)
    @test m !== nothing && m.captures[2] == "b"
    url = replace(m.captures[1], "&amp;" => "&")
    controls = String(HTMXObjects.dispatch(:GET, url * "&a=1.0&b=0.9"; headers = ["HX-Request" => "true"]).body)
    # The range of `a` it draws is the one `upper = 2b` gives.
    label = match(r"<label[^>]*data-htmxo-number=\"([^\"]*)\"(?:(?!</label>).)*?name=\"a\""s, controls)
    @test label !== nothing && occursin("upper&quot;:1.8", label.captures[1])
end

@testitem "a finite input whose default reads a fixed field has a view per value, and the export check changes a continuous one" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    HTMXObjects.vendorfiles("assets/vendor")
    # Snag static-export-fi-2f405405: every view of `family` held the result
    # for its default, because an input that follows its computed default was
    # left out of each view's address.
    route!(ChosenDefault(); operation_policy = :blocking)
    fact(body) = (m = match(r"class=\"fact\"[^>]*>([^<]*)<", body); m === nothing ? nothing : m.captures[1])
    for (family, sentence) in ((0, "exponential sentence"), (1, "log-normal sentence"))
        r = dispatch(:GET, "/result?family=$family"; headers = ["HX-Request" => "true"])
        @test fact(String(HTMXObjects._response_bytes(r))) == sentence
    end
    function views(body)
        map(eachmatch(r"<(div|template)[^>]*data-htmxo-variant=\"([^\"]*)\"[^>]*>", body)) do m
            (m.captures[1], replace(m.captures[2], "&quot;" => "\""),
             fact(SubString(body, m.offset + ncodeunits(m.match))))
        end
    end
    expected = [("div", "{\"family\":\"0\"}", "exponential sentence"),
                ("template", "{\"family\":\"0\"}", "exponential sentence"),
                ("template", "{\"family\":\"1\"}", "log-normal sentence")]
    live = dispatch(:GET, "/"; headers = ["HX-Request" => "true"])
    @test views(String(HTMXObjects._response_bytes(live))) == expected
    static = dispatch(:GET, "/"; static = StaticExport(; controls = :disable, runtime = :linked, audience = :public))
    @test static.status == 200
    @test views(String(HTMXObjects._response_bytes(static))) == expected
    mktempdir() do dir
        @test export_site(joinpath(dir, "site"); pages = ["/"]).files > 0
    end
    # The export's check changes a continuous input that follows its computed
    # default too, so a view showing it outside `bound` is named.
    route!(ChosenStale(); operation_policy = :blocking)
    mktempdir() do dir
        e = try
            export_site(joinpath(dir, "site"); pages = ["/"])
            nothing
        catch err
            err
        end
        @test e isa HTMXObjects.StaticSiteIncomplete
        @test e !== nothing && any(((a, why),) -> a == "/" && occursin(
            "the result `result` shows `scale` outside `bound`: its view changes when `scale` does", why), e.failed)
    end
end

@testitem "a static export compares a browser result with what two renders of the same inputs differ in" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    # Snag browser-result-u-88fa1fae: under a root with a glossary, a result
    # whose text uses a term was refused, one line per continuous input.
    route!(TermSite(); operation_policy = :blocking)
    HTMXObjects.vendorfiles("assets/vendor")
    fragment() = String(HTMXObjects._response_bytes(dispatch(:GET, "/line/result"; headers = ["HX-Request" => "true"])))
    one, other = fragment(), fragment()
    # The linked term's definition id is new in every answer, and nothing else is.
    @test occursin("aria-describedby=\"htmxo-term-widget-", one)
    @test one != other
    @test replace(one, r"htmxo-term-widget-[0-9a-z]+-1" => "") == replace(other, r"htmxo-term-widget-[0-9a-z]+-1" => "")
    static = dispatch(:GET, "/"; static = StaticExport(; controls = :disable, runtime = :linked, audience = :public))
    @test static.status == 200
    page = String(HTMXObjects._response_bytes(static))
    @test occursin("data-htmxo-browser=", page) && occursin("class=\"htmxo-term\"", page)
    function failure(address)
        mktempdir() do dir
            try
                export_site(joinpath(dir, "site"); pages = [address])
                nothing
            catch err
                err
            end
        end
    end
    @test failure("/") === nothing
    # An id of the view's own, new in every answer, is no input either.
    @test failure("/own") === nothing
    # An input shown outside `bound` is still named, with what changed, and
    # the input that only `bound` shows is not.
    e = failure("/shown")
    @test e isa HTMXObjects.StaticSiteIncomplete
    why = e === nothing ? "" : join((why for (_, why) in e.failed), "\n")
    @test occursin("the result `shown` shows `a` outside `bound`: its view changes when `a` does", why)
    @test occursin(r"for slope 2\.0\.</p>` becomes `[^`]*for slope 2\.2[0-9]*\.</p>` with `a` = 2\.2", why)
    @test !occursin("shows `b` outside", why)
    # Renders of the same inputs that do not line up cannot be compared with a
    # changed input's: said once for the result, not once per input.
    e = failure("/growing")
    @test e isa HTMXObjects.StaticSiteIncomplete
    why = e === nothing ? "" : join((why for (_, why) in e.failed), "\n")
    @test count("the export could not check the result `growing`: with the same inputs", why) == 1
    @test occursin("which do not line up", why) && !occursin("outside `bound`:", why)

    # The comparison itself, on skeletons: `again()` hands out one more
    # rendering of the unchanged inputs.
    control() = Ref{Union{Nothing,HTMXObjects._BrowserControl}}(nothing)
    compare!(ref, base, changed, renders) =
        HTMXObjects._browser_compare!(ref, base, changed, () -> popfirst!(renders))
    base = "<p id=\"t-1\">00 min 58 s</p>"
    @test join(HTMXObjects._browser_pieces(base)) == base
    @test HTMXObjects._browser_pieces("<a id=\"x-1\">b c</a>") == ["<", "a", " ", "id", "=", "\"", "x-1", "\"", ">", "b", " ", "c", "<", "/a", ">"]
    ref = control()
    # The id and the seconds differ between two renderings of the same inputs.
    @test compare!(ref, base, "<p id=\"t-2\">00 min 59 s</p>", ["<p id=\"t-3\">00 min 59 s</p>"]) === :same
    # The minutes did not, until now: one more rendering shows that they do too.
    @test compare!(ref, base, "<p id=\"t-4\">01 min 00 s</p>", ["<p id=\"t-5\">01 min 00 s</p>"]) === :same
    # What no rendering of the same inputs differs in is the input's doing.
    @test compare!(ref, base, "<p id=\"t-6\">01 min 00 s!</p>", ["<p id=\"t-7\">01 min 01 s</p>"]) === :changed
    @test compare!(control(), base, "<p id=\"t-1\">00 min 58 s</p><b></b>", [base]) === :changed
    # A rendering of the same inputs that did not render teaches nothing.
    @test compare!(control(), base, "<p id=\"t-2\">00 min 58 s</p>", [nothing]) === :changed
    # Renderings of the same inputs with different numbers of pieces do not line up.
    ref = control()
    @test compare!(ref, base, "<p id=\"t-2\">00 min 59 s</p>", ["<p id=\"t-3\">59 s</p>"]) === :unlike
    # What a message quotes: where they part (past the id, which differs first),
    # and of a long view only what surrounds the difference.
    @test HTMXObjects._browser_difference(ref[].pieces, ref[].unlike, nothing) ==
          ("<p id=\"t-1\">00 min 58 s</p>", "<p id=\"t-3\">59 s</p>")
    far = string("<p id=\"t-1\">", "x"^60, " a b</p>")
    @test HTMXObjects._browser_difference(HTMXObjects._browser_pieces(far),
              HTMXObjects._browser_pieces(string("<p id=\"t-2\">", "x"^60, " a</p>")), nothing) ==
          (string("…", "x"^38, " a b</p>"), string("…", "x"^38, " a</p>"))
    long = string("<p>", "x"^60, " 2.0 ", "y"^60, "</p>")
    @test HTMXObjects._browser_difference(HTMXObjects._browser_pieces(long),
              HTMXObjects._browser_pieces(replace(long, "2.0" => "2.5")), falses(11)) ==
          (string("…", "x"^37, " 2.0 ", "y"^39, "…"), string("…", "x"^37, " 2.5 ", "y"^39, "…"))
end

@testitem "a static browser page follows its inputs offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Lines(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        floats = [1e-5, 1e-4, 0.00012, 1e5, 1e6, 123456.0, 999999.5, 0.1 + 0.2, -0.0, 1.5e17, 5e-324, 2.5e-5, 1.0e15]
        expected_floats = string.(floats)
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label); await sleep(25); }
          }
          const region = () => document.querySelector('[data-htmxo-browser]');
          const shown = () => Array.from(region().querySelectorAll(':scope > .htmxo-browser-view [data-htmxo-bound]:not(.echo *)')).map(e => e.textContent).join('|');
          const echo = () => Array.from(region().querySelectorAll(':scope > .htmxo-browser-view .echo [data-htmxo-bound]')).map(e => e.textContent).join('|');
          const control = name => document.querySelector('input[name="' + name + '"]');
          const relevant = name => !document.querySelector('[data-htmxo-relevant="' + name + '"]').hidden;
          function type(name, value) { const c = control(name); c.value = value; c.dispatchEvent(new Event('change', {bubbles: true})); }
          const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
          try {
            if (sessionStorage.getItem('htmxo-test-browser') !== null) {
              // A shared link: the page applies its address, computing the result.
              await until(() => shown() === '7.0', 'shared link result');
              if (control('a').value !== '3' || !document.querySelector('input[name="show"][value="total"]').checked)
                throw new Error('shared link controls');
              await fetch('/complete?status=passed&search=' + encodeURIComponent(location.search));
              return;
            }
            await until(() => shown() === '3|5|2|0.50', 'first: ' + shown());
            const floats = ($(repr(floats))).map(window.__htmxoJuliaFloat).join(' ');
            if (floats !== $(repr(join(expected_floats, " "))))
              throw new Error('julia floats: ' + floats);
            let columns = null, rule = null;
            document.addEventListener('htmxo:bound-columns', e => {
              if (e.target.id === 'rule1') rule = e.detail; else columns = e.detail;
            });
            await fetch('/mark?phase=start');
            type('a', '3'); type('b', '4');
            await until(() => shown() === '7|10|3|0.50', 'a=3 b=4: ' + shown());
            // Computed in the browser from embedded Inf and -0.0, both intact
            // (the `ok` outputs say so; -0.0 is written `0`, as format_number does).
            if (echo() !== '∞|0|1|1') throw new Error('non-finite data: ' + echo());
            if (!columns || columns.columns.y.join(',') !== '4,7,10') throw new Error('columns: ' + JSON.stringify(columns));
            // A single value's table keeps its one row: the new value, not none.
            if (!rule || rule.n !== 1 || JSON.stringify(rule.columns) !== '{"total":[7]}')
              throw new Error('one-row columns: ' + JSON.stringify(rule));
            await until(() => relevant('extra'), 'extra applies (a*b > 10)');
            type('extra', '0.125');
            // Exactly two decimals, halves away from zero, as on the server.
            await until(() => shown() === '7|10|3|0.13', 'extra digits: ' + shown());
            choose('show', 'total');
            await until(() => shown() === '7.0', 'total view: ' + shown());
            choose('show', 'line');
            await until(() => shown() === '7|10|3|0.13', 'line view again: ' + shown());
            type('b', '-1');
            await until(() => { const n = region().querySelector('.htmxo-browser-fault'); return n && n.textContent.startsWith('DomainError: toy was called with b = -1'); }, 'fault');
            if (!region().querySelector('.htmxo-browser-view').hasAttribute('data-htmxo-stale')) throw new Error('not stale');
            type('b', '2');
            // a*b = 6: `extra` no longer applies and reads its default, as on the server.
            await until(() => shown() === '5|8|3|0.50' && !region().querySelector('.htmxo-browser-fault'), 'recovered: ' + shown());
            // A slider held down sends `input` events only, which its field
            // relays: the result follows each, the address waits for the release.
            const slider = document.querySelector('label[data-htmxo-number]:has(input[name="a"]) input[data-htmxo-number-slider]');
            slider.value = '100';
            slider.dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => shown() === '4|6|2|0.50', 'held slider: ' + shown());
            if (control('a').value !== '2' || new URLSearchParams(location.search).get('a') !== '3')
              throw new Error('held slider field or address: ' + control('a').value + ' ' + location.search);
            // A number being typed: `input` events of the field alone.
            control('a').value = '4';
            control('a').dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => shown() === '6|10|4|0.50', 'typed: ' + shown());
            slider.dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => new URLSearchParams(location.search).get('a') === '4', 'address on release: ' + location.search);
            // A number between the slider's grid values (`step = 0.5`) is
            // computed as typed (snag use-number-domai-f74b4f09: the grid as
            // the field's own step made it invalid, and the result stayed).
            type('a', '4.3');
            await until(() => shown() === '6.3|10.6|4.3|0.50', 'between grid values: ' + shown());
            await until(() => new URLSearchParams(location.search).get('a') === '4.3', 'address between grid values: ' + location.search);
            await fetch('/mark?phase=end');
            if (new URLSearchParams(location.search).get('b') !== '2') throw new Error('address: ' + location.search);
            sessionStorage.setItem('htmxo-test-browser', '1');
            location.href = location.pathname + '?a=3&b=4&show=total';
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
                        @test HTTP.URIs.unescapeuri(outcome) == "/complete?status=passed&search=?a=3&b=4&show=total"
                    finally
                        process_exited(process) || kill(process)
                        wait(process)
                    end
                end
            finally
                close(server)
            end
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end

@testitem "a static page hands its browser module matrix data as rows, offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Grid(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          const region = () => document.querySelector('[data-htmxo-browser]');
          const shown = () => region().querySelector(':scope > .htmxo-browser-view .grid').textContent;
          const fault = () => { const n = region().querySelector('.htmxo-browser-fault'); return n ? n.textContent : ''; };
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label + ' [' + shown() + '] ' + fault()); await sleep(25); }
          }
          try {
            await until(() => shown() === '2 6 2x3 0x3 2x0 11', 'server view');
            const c = document.querySelector('input[name="scale"]');
            c.value = '3';
            c.dispatchEvent(new Event('change', {bubbles: true}));
            // Computed in the browser from the rows: m[1, 2] * 3, m[2, 3] * 3,
            // both shapes kept (0×3 through its `cols`), Inf and the Bool intact.
            await until(() => shown() === '6 18 2x3 0x3 2x0 11' && fault() === '', 'scale=3');
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
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2])
            close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose = false) do req
                path = HTTP.URI(req.target).path
                if path == "/complete"
                    isready(receipt) || put!(receipt, String(req.target))
                    return HTTP.Response(204)
                end
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
        end
    end
end

@testitem "bound writes a number as format_number does, with its digits, percent and language" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    b(x; kw...) = HTMXObjects._bound((:x,), x; kw...)
    html(v) = repr("text/html", v)
    # Exactly `digits` decimals, a share as a percent, the language's marks.
    @test repr("text/plain", b(0.12; digits = 3)) == "0.120" && repr("text/plain", b(45.0; digits = 0)) == "45"
    @test repr("text/plain", b(0.4517; percent = true, digits = 0)) == "45%"
    @test repr("text/plain", b(0.12; digits = 3, texts = table_texts(:de))) == "0,120"
    @test repr("text/plain", b(0.4517; percent = true, sigdigits = 2, texts = table_texts(:de))) == "45 %"
    # Without keywords as format_number writes it: no `.0`, a power of ten, grouped integers.
    @test repr("text/plain", b(2.0)) == "2" && repr("text/plain", b(3.81e-5)) == "3.81·10⁻⁵"
    @test repr("text/plain", b(1234)) == "1,234" && repr("text/plain", b(Inf)) == "∞"
    @test repr("text/plain", b(true)) == "true" && repr("text/plain", b("on")) == "on"
    # The page writes it again with the same rounding, percent and language.
    @test occursin("data-htmxo-format=\"{&quot;digits&quot;:3}\"", html(b(0.12; digits = 3)))
    @test occursin("&quot;percent&quot;:true", html(b(0.45; percent = true)))
    de = html(b(0.12; digits = 3, texts = table_texts(:de)))
    @test occursin("&quot;decimal&quot;:&quot;,&quot;", de) && occursin("&quot;percent&quot;:&quot;{number} %&quot;", de)
    @test !occursin("data-htmxo-format", html(b(2.0))) && occursin("data-htmxo-kind=\"int\"", html(b(1234)))
    # The facts of the shielding picture, as its page shows them first.
    route!(Shield(); operation_policy = :blocking)
    facts = String(HTMXObjects._response_bytes(dispatch(:GET, "/picture"; headers = ["HX-Request" => "true"])))
    @test bound_texts(facts) == ["100", "83%", "50%", "0,833"]
    # Refused: a rounding that is no integer, both roundings, and rounding a table.
    @test_throws ArgumentError b(1.0; digits = 1.5)
    @test_throws ArgumentError b(1.0; digits = 1, sigdigits = 2)
    e = try; HTMXObjects._bound((:x,), (; a = [1.0]); columns = (:a,), digits = 1); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("ColumnSpec(label; digits, sigdigits, percent)", e.msg)
end

@testitem "render_table of browser outputs describes its rows for the page, and a static page keeps it" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON
    route!(Shield(); operation_policy = :blocking)
    html = String(HTMXObjects._response_bytes(dispatch(:GET, "/picture"; headers = ["HX-Request" => "true"])))
    # The first rows, as any render_table writes them, each column with its rounding.
    @test [m[1] for m in eachmatch(r"<td[^>]*>([^<]*)</td>", html)] ==
          ["0", "0", "1.000", "20", "8", "0.833", "50", "20", "0.667", "100", "40", "0.500", "100"]
    @test occursin("data-sort-value=\"0.8333333333333334\" data-htmxo-number=\"0.8333333333333334\">0.833<", html)
    # Keyed for hover linking as AlgebraOfVega keys a plot's marks: `20`, not `20.0`.
    @test [m[1] for m in eachmatch(r"data-htmxo-link-key=\"([^\"]*)\"", html)] == ["0", "20", "50", "100"]
    spec = JSON.parse(replace(match(r"data-htmxo-bound-table=\"([^\"]*)\"", html)[1], "&quot;" => "\""))
    @test spec["path"] == ["shield"] && spec["link_key"] == "water"
    @test [c["name"] for c in spec["columns"]] == ["water", "depth", "share"]
    @test all(c -> c["kind"] == "float", spec["columns"]) && [c["digits"] for c in spec["columns"]] == [0, 0, 3]
    one = JSON.parse(replace(collect(eachmatch(r"data-htmxo-bound-table=\"([^\"]*)\"", html))[2][1], "&quot;" => "\""))
    @test [c["name"] for c in one["columns"]] == ["half"] && one["columns"][1]["kind"] == "float"
    # The text peer shows the rows the server computes.
    plain = String(HTMXObjects._response_bytes(dispatch(:GET, "/picture?attenuation=0.02&plain=1")))
    @test occursin("0.714", plain) && occursin("0.333", plain)
    # The page writes the rows again, so the static export takes the page.
    HTMXObjects.vendorfiles("assets/vendor")
    mktempdir() do dir
        export_site(joinpath(dir, "site"); pages = ["/"])
        @test occursin("data-htmxo-bound-table=", read(joinpath(dir, "site", "index.html"), String))
    end
    @test HTMXObjects._browser_skeleton("<table data-htmxo-bound-table=\"x\"><tbody><tr><td>1</td></tr></tbody></table><small data-htmxo-table-count=\"\" role=\"status\">4 of 4 rows shown</small>") ==
          "<table data-htmxo-bound-table=\"x\"></table><small data-htmxo-table-count=\"\" role=\"status\"></small>"
    # The browser runs no Julia: a function of the table is refused, naming it.
    t = HTMXObjects._bound((:shield,), (; water = [1.0, 2.0], share = [0.5, 0.25]); columns = (:water, :share))
    refused(; kw...) = try; render_table(t; kw...); nothing; catch err; err; end
    for (kw, phrase) in (((; cell = (v, c, i) -> v), "`cell` function"), ((; search_text = r -> "x"), "`search_text` function"),
                         ((; link = "g", link_key = r -> r.water), "`link_key` function"), ((; selectable = "s"), "`selectable`"),
                         ((; columns = [:share => ColumnSpec("S"; sort_keys = ["a" => r -> 1, "b" => r -> 2])]), "sort keys computed"))
        e = refused(; kw...)
        @test e isa ArgumentError && occursin(phrase, e.msg) && occursin("the table of shield", e.msg)
    end
    @test occursin("data-htmxo-link-key=\"2\"", repr("text/html", render_table(t; link = "g", link_key = :water)))
end

@testitem "bound and ColumnSpec write a day as format_date does, and a NaN as no value" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON
    import Dates
    b(x; kw...) = HTMXObjects._bound((:x,), x; kw...)
    plain(v) = repr("text/plain", v)
    day = 1_573_862_400_000.0  # 16 November 2019, the reporter's peak day
    @test plain(b(day; date = :long)) == "16 November 2019"
    @test plain(b(day; date = :short)) == "16 Nov 2019" && plain(b(day; date = :month)) == "Nov 2019"
    @test plain(b(day; date = :long, texts = table_texts(:de))) == "16. November 2019"
    @test plain(b(day; date = :short, texts = table_texts(:de))) == "16. Nov. 2019"
    # The same day as an integer and as a Date; the UTC day of a later instant
    # of it; a fraction before 1970 dropped toward zero, as JavaScript does.
    @test plain(b(Int(day); date = :long)) == plain(b(Dates.Date(2019, 11, 16); date = :long)) == "16 November 2019"
    @test plain(b(day + 86_399_999; date = :short)) == "16 Nov 2019" && plain(b(day + 86_400_000; date = :short)) == "17 Nov 2019"
    @test plain(b(-0.5; date = :short)) == "1 Jan 1970" && plain(b(-1.0; date = :short)) == "31 Dec 1969"
    # No day: no number, NaN, ±Inf and beyond the range of JavaScript's dates.
    for x in (NaN, Inf, -Inf, missing, nothing, 8.64e15 + 1)
        @test plain(b(x; date = :long)) == "–"
    end
    @test plain(b(8.64e15; date = :short)) == "13 Sep 275760"
    # A NaN number is no value, as missing is; format_number itself keeps NaN.
    @test plain(b(NaN)) == plain(b(NaN; digits = 1)) == plain(b(NaN; percent = true)) == plain(b(missing)) == "–"
    @test plain(b(Inf)) == "∞" && format_number(NaN) == "NaN"
    # The page writes the day again from the words of its style alone.
    fmt(v) = JSON.parse(replace(match(r"data-htmxo-format=\"([^\"]*)\"", repr("text/html", v))[1], "&quot;" => "\""))
    @test fmt(b(day; date = :long)) == Dict("date" => Dict("layout" => "{day} {month} {year}",
        "months" => collect(table_texts().months)))
    de = fmt(b(day; date = :short, texts = table_texts(:de)))["date"]
    @test de["layout"] == table_texts(:de).date_short && de["months_short"][11] == "Nov." && !haskey(de, "months")
    @test fmt(b(day; date = :month))["date"] == Dict("layout" => "{month_short} {year}",
        "months_short" => collect(table_texts().months_short))
    # Refused: an unknown style, a day written with digits, a DateTime, text, days in a table.
    refused(x; kw...) = try; b(x; kw...); nothing; catch err; err; end
    for (kw, phrase) in (((; date = :weekday), "`date` is :long, :short or :month"), ((; date = "long"), "`date` is :long"),
                         ((; date = :long, digits = 1), "takes no `digits`"), ((; date = :long, percent = true), "takes no `digits`"))
        e = refused(day; kw...)
        @test e isa ArgumentError && occursin(phrase, e.msg)
    end
    e = refused(Dates.DateTime(2019, 11, 16); date = :long)
    @test e isa ArgumentError && occursin("Date(x)", e.msg)
    @test refused("2019-11-16"; date = :long) isa ArgumentError && refused(true; date = :long) isa ArgumentError
    e = try; HTMXObjects._bound((:x,), (; t = [day]); columns = (:t,), date = :short); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("ColumnSpec(label; date)", e.msg)

    # The year window as its page shows it first: facts, a table of days with
    # an empty cell for the missing reading, and a German table.
    route!(Window(); operation_policy = :blocking)
    page = String(HTMXObjects._response_bytes(dispatch(:GET, "/days"; headers = ["HX-Request" => "true"])))
    @test bound_texts(page) == ["3 October 2019", "3. Okt. 2019", "Oct 2019", "–", "–"]
    @test [m[1] for m in eachmatch(r"<td[^>]*>([^<]*)</td>", page)] ==
          ["1 Oct 2019", "1.5", "2 Oct 2019", "–", "3 Oct 2019", "3.3", "4 Oct 2019", "2.0",
           "1. Oktober 2019", "2. Oktober 2019", "3. Oktober 2019", "4. Oktober 2019"]
    # A day sorts by its number and exports its ISO day; the missing reading is
    # an empty number cell, no sort value and an empty ⬇ CSV field.
    @test occursin("<td data-sort-value=\"1.569888e12\" data-htmxo-number=\"2019-10-01\">1 Oct 2019</td>", page)
    @test occursin("<td data-htmxo-number=\"\">–</td>", page) && !occursin("NaN<", page)
    # The day column is right-aligned like a number column, header included.
    @test occursin(r"<th[^>]*data-htmxo-align=\"right\"[^>]*>(?:(?!</th>).)*Day"s, page)
    specs = [JSON.parse(replace(m[1], "&quot;" => "\"")) for m in eachmatch(r"data-htmxo-bound-table=\"([^\"]*)\"", page)]
    @test specs[1]["columns"][1]["date"] == Dict("layout" => "{day} {month_short} {year}", "months_short" => collect(table_texts().months_short))
    @test specs[1]["columns"][2]["digits"] == 1 && !haskey(specs[1]["columns"][2], "date")
    @test specs[2]["columns"][1]["date"]["months"][10] == "Oktober"
    # The text peer writes the days and the empty reading too.
    plaintext = String(HTMXObjects._response_bytes(dispatch(:GET, "/days?shift=100&plain=1")))
    @test occursin("11 January 2020", plaintext) && occursin("9 Jan 2020", plaintext) && !occursin("NaN", plaintext)
end

@testitem "bound numeric exceptions and units agree with table and Markdown text" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON, Dates
    labels = [Inf => "No finite halving time", -Inf => "Not finite", 0.0 => "None"]
    b(x; kw...) = HTMXObjects._bound((:x,), x; kw...)
    for (value, expected) in ((12.34, "12.3 years"), (1.25, "1.3 years"), (Inf, "No finite halving time"),
                              (-Inf, "Not finite"), (0, "None"), (NaN, "–"), (missing, "–"), (nothing, "–"))
        value = b(value; digits = 1, labels, unit = "years")
        @test repr("text/plain", value) == repr("text/markdown", value) == expected
        @test occursin(">" * expected * "</span>", repr("text/html", value))
    end
    @test repr("text/plain", b(12.34; sigdigits = 3, labels, unit = "Jahre", texts = table_texts(:de))) == "12,3 Jahre"
    @test repr("text/plain", b(0.125; percent = true, labels, unit = "per year")) == "12.5% per year"
    @test repr("text/plain", b(-Inf; digits = 1, labels = [Inf => "Positive"], unit = "years")) == "-∞ years"
    @test repr("text/plain", b(Inf; labels = Dict(Inf => "Infinite"))) == "Infinite"
    @test repr("text/plain", b("Inf"; labels = [Inf => "Number", "Inf" => "Text"])) == "Text"
    @test repr("text/plain", b(2.0; unit = "")) == "2"
    for x in (true, "hello", Date(2020, 1, 1))
        kw = x isa Date ? (; date = :long) : (;)
        @test repr("text/plain", b(x; unit = "years", kw...)) == repr("text/plain", b(x; kw...))
    end
    for x in (false, "unlabelled")
        @test_throws ArgumentError b(x; digits = 1, labels)
    end
    @test_throws ArgumentError b(12.34; labels, unit = "years")
    @test_throws ArgumentError b(NaN; labels = [NaN => "None"])
    @test_throws ArgumentError b(Inf; labels = [Inf => "a", Float32(Inf) => "b"])
    @test_throws ArgumentError HTMXObjects._bound((:x,), (; values = [1]); columns = (:values,), unit = "years")
    @test occursin("&lt;years&gt;", repr("text/html", b(1; unit = "<years>")))
    @test occursin("&lt;none&gt;", repr("text/html", b(Inf; digits = 1, labels = [Inf => "<none>"])))
    # A valid JSON key carries each infinity without colliding with text keys.
    wire = HTMXObjects._labels_wire(b(Inf; digits = 1, labels).labels)
    @test JSON.parse(JSON.json(wire))["pairs"][1:2] == [[Dict("infinite" => 1), "No finite halving time"],
        [Dict("infinite" => -1), "Not finite"]]
    table = render_table((; years = [12.34, Inf, -Inf, 0.0, missing]);
        columns = [:years => ColumnSpec("Years"; digits = 1, labels)])
    html = repr("text/html", table)
    @test occursin("data-htmxo-number=\"12.34\"", html) && occursin(">12.3</td>", html)
    @test occursin("data-sort-value=\"Infinity\">No finite halving time", html)
    @test occursin("data-sort-value=\"-Infinity\">Not finite", html)
    @test occursin("data-sort-value=\"0.0\">None", html)
    @test occursin("No finite halving time", HTMXObjects.to_markdown_string(table))
    route!(Halving(); operation_policy = :blocking)
    page = String(HTMXObjects._response_bytes(dispatch(:GET, "/facts?slope=0&plain=1")))
    @test occursin("No finite halving time", page) && !occursin("years", page) && !occursin("Jahre", page)
end

@testitem "bound and ColumnSpec write a value as the text its labels name" setup=[BrowserFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, JSON, HTTP
    b(x; kw...) = HTMXObjects._bound((:x,), x; kw...)
    plain(v) = repr("text/plain", v)
    refused(f) = try; f(); nothing; catch err; err; end
    @test plain(b(3; labels = DOSE_TEXTS)) == "200 mg (level 3)" && plain(b(0; labels = DOSE_TEXTS)) == "No dose"
    # A number key names the same number, as a module returns it; a Dict reads the same.
    @test plain(b(3.0; labels = DOSE_TEXTS)) == plain(b(Int32(3); labels = Dict(DOSE_TEXTS))) == "200 mg (level 3)"
    @test plain(b(0.5; labels = [0.5 => "half"])) == "half"
    # Booleans and text name only Booleans and text.
    yes = [true => "Yes", false => "No"]
    @test plain(b(true; labels = yes)) == "Yes" && plain(b(false; labels = yes)) == "No"
    @test plain(b("a"; labels = ["a" => "Alpha", :b => "Beta"])) == "Alpha" && plain(b(:b; labels = ["a" => "Alpha", :b => "Beta"])) == "Beta"
    # No value is `–`, as for every bound value.
    for x in (NaN, missing, nothing)
        @test plain(b(x; labels = DOSE_TEXTS)) == "–"
    end
    # The Markdown and the HTML say the label; the page carries the table to write it again.
    @test repr("text/markdown", b(0; labels = DOSE_TEXTS)) == "No dose"
    html = repr("text/html", b(3; labels = DOSE_TEXTS))
    @test occursin(">200 mg (level 3)</span>", html) && occursin("data-htmxo-kind=\"int\"", html)
    fmt(v) = JSON.parse(replace(match(r"data-htmxo-format=\"([^\"]*)\"", repr("text/html", v))[1], "&quot;" => "\"", "&#39;" => "'"))
    @test fmt(b(3; labels = DOSE_TEXTS)) == Dict("labels" => Dict("pairs" => [[k, t] for (k, t) in DOSE_TEXTS],
        "named" => "0, 1, 2, 3, 4, 5", "what" => "bound(x; labels)"))
    @test fmt(b(true; labels = yes))["labels"]["pairs"] == [[true, "Yes"], [false, "No"]]
    # A Dict's keys in order: Booleans, numbers, text.
    @test fmt(b(1; labels = Dict("z" => "Z", 2 => "two", 1 => "one", false => "no")))["labels"]["named"] == "false, 1, 2, \"z\""
    # A value the labels do not name is an error naming it and the keys,
    # never a silent fallback: a number missing, a Bool for a number key, a
    # number for a Bool key, text for a number key.
    e = refused(() -> b(7; labels = DOSE_TEXTS))
    @test e isa ArgumentError && e.msg == "bound(x; labels): 7 is not a value its labels name (0, 1, 2, 3, 4, 5)"
    e = refused(() -> HTMXObjects._bound((:rules, :paper), 6.0; labels = DOSE_TEXTS))
    @test e isa ArgumentError && e.msg == "bound(rules.paper; labels): 6.0 is not a value its labels name (0, 1, 2, 3, 4, 5)"
    @test refused(() -> b(true; labels = [1 => "one"])) isa ArgumentError
    @test refused(() -> b(1; labels = yes)) isa ArgumentError
    @test refused(() -> b("1"; labels = [1 => "one"])) isa ArgumentError
    # Refused as the page is built: with day keywords, an empty
    # or repeated table, a key that is no value or no key, a label that is no text.
    for (kw, phrase) in (((; date = :long), "takes no `date`"),)
        e = refused(() -> b(3; labels = DOSE_TEXTS, kw...))
        @test e isa ArgumentError && occursin(phrase, e.msg)
    end
    for (table, phrase) in (([], "names no value"), (Dict{Int,String}(), "names no value"),
                            ([3 => "a", 3.0 => "b"], "names 3.0 twice"), ([NaN => "none"], "cannot name NaN"),
                            ([nothing => "none"], "a key of `labels` is a number, a Bool or text"),
                            ([1 => 2], "the label of 1 is a $(Int); a label is text"), ([1, 2], "is a `value => text` pair"),
                            ("No dose", "a list of `value => text` pairs or a Dict"))
        e = refused(() -> b(1; labels = table))
        @test e isa ArgumentError && occursin(phrase, e.msg) && startswith(e.msg, "bound(x; labels)")
    end
    e = refused(() -> HTMXObjects._bound((:x,), (; t = [1]); columns = (:t,), labels = DOSE_TEXTS))
    @test e isa ArgumentError && occursin("ColumnSpec(label; labels)", e.msg)

    # A column of labels in any render_table: each cell its label, sorted by
    # its value, text at the left; no value is the empty cell; a value the
    # labels do not name is an error naming the column.
    dose = ColumnSpec("Dose"; labels = DOSE_TEXTS)
    t = repr("text/html", render_table((; rule = ["paper", "mtd", "none"], level = [3, 0, missing]); columns = [:level => dose]))
    @test occursin("<td data-sort-value=\"3\">200 mg (level 3)</td>", t) && occursin("<td data-sort-value=\"0\">No dose</td>", t)
    @test occursin(r"<td[^>]*data-htmxo-number=\"\"[^>]*>–</td>", t)
    @test !occursin(r"<th[^>]*data-htmxo-align=\"right\"[^>]*>(?:(?!</th>).)*Dose"s, t)
    @test occursin("data-sort-value=\"1\">Yes", repr("text/html", render_table((; ok = [true]); columns = [:ok => ColumnSpec("OK"; labels = yes)])))
    e = refused(() -> render_table((; level = [7]); columns = [:level => dose]))
    @test e isa ArgumentError && e.msg == "ColumnSpec(\"Dose\"; labels): 7 is not a value its labels name (0, 1, 2, 3, 4, 5)"
    for kw in ((; date = :short),)
        e = refused(() -> ColumnSpec("Dose"; labels = DOSE_TEXTS, kw...))
        @test e isa ArgumentError && startswith(e.msg, "ColumnSpec(\"Dose\"; labels)") && occursin("takes no `date`", e.msg)
    end
    e = refused(() -> sortable_table([dose], []))
    @test e isa ArgumentError && occursin("numbers, days or labels", e.msg)

    # The dose rules as their page shows them first, in HTML, as text and in the bound table's description.
    route!(Doses(); operation_policy = :blocking)
    HTMXObjects.vendorfiles("assets/vendor")
    page = String(HTMXObjects._response_bytes(dispatch(:GET, "/facts"; headers = ["HX-Request" => "true"])))
    @test bound_texts(page) == ["100 mg (level 2)", "50 mg (level 1)", "Dosed"]
    unescaped(x) = replace(x, "&#39;" => "'", "&apos;" => "'", "&quot;" => "\"", "&amp;" => "&")
    @test [unescaped(m[1]) for m in eachmatch(r"<td[^>]*>([^<]*)</td>", page)] == ["Paper's rule", "100 mg (level 2)", "MTD rule", "50 mg (level 1)"]
    spec = JSON.parse(unescaped(match(r"data-htmxo-bound-table=\"([^\"]*)\"", page)[1]))
    @test spec["columns"][1]["labels"]["pairs"] == [[1, "Paper's rule"], [2, "MTD rule"]] && spec["columns"][2]["kind"] == "int"
    @test spec["columns"][2]["labels"]["what"] == "ColumnSpec(\"Dose\"; labels)"
    zero = String(HTMXObjects._response_bytes(dispatch(:GET, "/facts?risk=0.1&plain=1")))
    @test occursin("No dose", zero) && occursin("Not dosed", zero) && !occursin("level", zero)
    # A risk whose level the labels do not name fails on the server, naming it:
    # the answer is a recorded error, whose log entry holds the cause.
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            answer = dispatch(:GET, "/facts?risk=1.3"; headers = ["HX-Request" => "true"])
            uid = HTTP.header(answer, "X-HTMXO-Error-Id", "")
            @test !isempty(uid)
            logged = read(joinpath(dir, "$uid.log"), String)
            @test contains(logged, "status:    500") &&
                  contains(logged, "ArgumentError: bound(rules.paper; labels): 6 is not a value its labels name (0, 1, 2, 3, 4, 5)")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # A static export of the page has nothing it would show stale.
    mktempdir() do dir
        export_site(joinpath(dir, "site"); pages = ["/"])
        @test isfile(joinpath(dir, "site", "index.html"))
    end
end

@testitem "a static page writes bound days and missing values again offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, JSON
        import Dates
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Window(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        # What format_date and the ISO day write, which `htmxoDateText` and
        # `htmxoDateKey` must write too: every month in each style and
        # language, an American override, and the edges of JavaScript's dates.
        js(x::Real) = HTMXObjects._js_number_text(Float64(x))
        ms(d) = Dates.value(Dates.DateTime(d)) - Dates.UNIXEPOCH
        american = table_texts(; date_long = "{month} {day}, {year}", date_month = "{month} {year}")
        cases = String[]
        case(x, style, texts) = let day = HTMXObjects._date_day(x)
            push!(cases, string("[", js(x), ",", JSON.json(HTMXObjects._date_words(texts, style)), ",",
                JSON.json(format_date(day; texts, style)), ",", JSON.json(isnothing(day) ? nothing : string(day)), "]"))
        end
        for m in 1:12, d in (1, 28), style in (:long, :short, :month), texts in (table_texts(), table_texts(:de), american)
            case(ms(Dates.Date(2021, m, d)) + 43_200_000, style, texts)
        end
        for x in (-0.5, -1.0, -1.5, 86_399_999.9, 8.64e15, -8.64e15, 8.64e15 + 1, NaN, Inf, -Inf, ms(Dates.Date(9, 3, 1)))
            case(x, :short, table_texts())
        end
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + (typeof label === 'function' ? label() : label)); await sleep(25); }
          }
          // The page's two bound tables, in order (`id` names their ⬇ CSV files).
          const table = id => document.querySelectorAll('table[data-htmxo-bound-table]')[id === 'days' ? 0 : 1];
          const rows = id => Array.from(table(id).tBodies[0].rows);
          const cell = c => [c.textContent, c.getAttribute('data-sort-value'), c.getAttribute('data-htmxo-number'), c.getAttribute('data-htmxo-align')].join('~');
          const snapshot = () => ['days', 'tage'].map(id => rows(id).map(r => Array.from(r.cells).map(cell).join('|')).join(' ')).join(' / ');
          const column = (id, j) => rows(id).map(r => r.cells[j].textContent).join(',');
          const fact = name => Array.from(document.querySelectorAll('.' + name + ' [data-htmxo-bound]')).map(e => e.textContent).join('|');
          const facts = () => [fact('peak'), fact('peak-de'), fact('none')].join(' ');
          const field = () => document.querySelector('input[name="shift"]');
          function typed(v) { const c = field(); c.value = v; c.dispatchEvent(new Event('input', {bubbles: true})); }
          try {
            const cases = [$(join(cases, ",\n"))];
            const wrong = cases.filter(c => htmxoDateText(c[0], c[1]) !== c[2] || htmxoDateKey(c[0]) !== c[3])
              .map(c => [c[0], c[1].layout, htmxoDateText(c[0], c[1]), c[2], htmxoDateKey(c[0]), c[3]]);
            if (wrong.length) throw new Error(wrong.length + ' days differ: ' + JSON.stringify(wrong.slice(0, 4)));
            await until(() => table('days') && rows('days').length === 4, 'table');
            const server = snapshot();
            if (facts() !== '3 October 2019 3. Okt. 2019|Oct 2019 –|–') throw new Error('first facts: ' + facts());
            await fetch('/mark?phase=start');
            typed('100');
            await until(() => facts() === '11 January 2020 11. Jan. 2020|Jan 2020 –|–', () => 'typed facts: ' + facts());
            await until(() => column('days', 0) === '9 Jan 2020,10 Jan 2020,11 Jan 2020,12 Jan 2020', () => 'typed days: ' + column('days', 0));
            await until(() => column('tage', 0) === '9. Januar 2020,10. Januar 2020,11. Januar 2020,12. Januar 2020', () => 'typed Tage: ' + column('tage', 0));
            // The missing reading stays an empty cell; a day sorts by its number
            // and exports its ISO day.
            if (column('days', 1) !== '1.5,–,3.3,2.0') throw new Error('readings: ' + column('days', 1));
            const first = rows('days')[0].cells[0], empty = rows('days')[1].cells[1];
            if (first.getAttribute('data-sort-value') !== $(repr(string(WINDOW_START + 100 * 86400000.0))) || first.getAttribute('data-htmxo-number') !== '2020-01-09')
              throw new Error('day cell: ' + cell(first));
            if (empty.hasAttribute('data-sort-value') || empty.getAttribute('data-htmxo-number') !== '') throw new Error('empty cell: ' + cell(empty));
            // The reader sorts the days, latest first, and the sort holds for new rows.
            const th = table('days').tHead.rows[0].cells[0];
            sortTable(th); sortTable(th);
            if (column('days', 0) !== '12 Jan 2020,11 Jan 2020,10 Jan 2020,9 Jan 2020') throw new Error('sorted: ' + column('days', 0));
            // Half a day later is still the same UTC day.
            typed('100.5');
            await until(() => fact('peak') === '11 January 2020' && rows('days')[0].cells[0].getAttribute('data-sort-value') !== first.getAttribute('data-sort-value'),
              () => 'half a day: ' + facts());
            if (column('days', 0) !== '12 Jan 2020,11 Jan 2020,10 Jan 2020,9 Jan 2020') throw new Error('half a day, sorted: ' + column('days', 0));
            // Back at the first value, the browser's rows are the server's, cell by cell.
            sortTable(th);
            typed('0');
            await until(() => facts() === '3 October 2019 3. Okt. 2019|Oct 2019 –|–', () => 'back: ' + facts());
            await until(() => snapshot() === server, () => 'parity: ' + snapshot() + ' / ' + server);
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
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end

@testitem "a static page writes bound values and a table column as their labels again offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Doses(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + (typeof label === 'function' ? label() : label)); await sleep(25); }
          }
          const fact = name => document.querySelector('.' + name + ' [data-htmxo-bound]').textContent;
          const facts = () => [fact('paper'), fact('mtd'), fact('dosed')].join('|');
          const table = () => document.querySelector('table[data-htmxo-bound-table]');
          const rows = () => Array.from(table().tBodies[0].rows);
          const cell = c => [c.textContent, c.getAttribute('data-sort-value'), c.getAttribute('data-htmxo-number')].join('~');
          const snapshot = () => rows().map(r => Array.from(r.cells).map(cell).join('|')).join(' ');
          const column = j => rows().map(r => r.cells[j].textContent).join(',');
          const fault = () => { const f = document.querySelector('.htmxo-browser-fault'); return f ? f.textContent : ''; };
          const stale = () => !!document.querySelector('.htmxo-browser-view[data-htmxo-stale]');
          const field = () => document.querySelector('input[name="risk"]');
          function typed(v) { const c = field(); c.value = v; c.dispatchEvent(new Event('input', {bubbles: true})); }
          try {
            await until(() => table() && rows().length === 2, 'table');
            const server = snapshot();
            if (facts() !== '100 mg (level 2)|50 mg (level 1)|Dosed') throw new Error('first facts: ' + facts());
            await fetch('/mark?phase=start');
            // No dose for either rule: the labels of 0 and of false.
            typed('0.1');
            await until(() => facts() === 'No dose|No dose|Not dosed', () => 'no dose: ' + facts());
            await until(() => column(1) === 'No dose,No dose', () => 'no dose column: ' + column(1));
            if (column(0) !== "Paper's rule,MTD rule") throw new Error('rules: ' + column(0));
            const none = rows()[0].cells[1];
            if (none.getAttribute('data-sort-value') !== '0' || none.hasAttribute('data-htmxo-number')) throw new Error('label cell: ' + cell(none));
            // Level 1 and 0: sorted by the value, "No dose" comes first, which its text would not.
            typed('0.25');
            await until(() => facts() === '50 mg (level 1)|No dose|Dosed', () => 'levels 1 and 0: ' + facts());
            await until(() => column(1) === '50 mg (level 1),No dose', () => 'levels 1 and 0 column: ' + column(1));
            const th = table().tHead.rows[0].cells[1];
            sortTable(th);
            if (column(1) !== 'No dose,50 mg (level 1)') throw new Error('sorted by level: ' + column(1));
            // Level 6, which the labels do not name: the result shows the
            // server's error and fades, the value keeps its last text and the
            // table its rows, and what the labels do name is written.
            typed('1.3');
            await until(() => fault() !== '', () => 'fault: ' + facts());
            if (fault() !== 'ArgumentError: bound(rules.paper; labels): 6 is not a value its labels name (0, 1, 2, 3, 4, 5)')
              throw new Error('fault text: ' + fault());
            if (!stale()) throw new Error('not faded');
            if (facts() !== '50 mg (level 1)|400 mg (level 5)|Dosed') throw new Error('fault facts: ' + facts());
            if (column(1) !== 'No dose,50 mg (level 1)') throw new Error('fault rows: ' + column(1));
            // Back at the first value: no fault, and the browser's rows are the
            // server's, cell by cell. A second click sorts by level, highest
            // first, which is the server's order of these two rows (2, then 1).
            sortTable(th);
            if (column(1) !== '50 mg (level 1),No dose') throw new Error('sorted by level, highest first: ' + column(1));
            typed('0.5');
            await until(() => fault() === '' && !stale() && facts() === '100 mg (level 2)|50 mg (level 1)|Dosed', () => 'back: ' + facts() + ' ' + fault());
            await until(() => snapshot() === server, () => 'parity: ' + snapshot() + ' / ' + server);
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
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end

@testitem "numeric exceptions and units redraw offline through finite infinite and missing values" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Halving(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + label()); await sleep(25); }
          }
          const fact = name => document.querySelector('.' + name + ' [data-htmxo-bound]').textContent;
          const facts = () => [fact('half'), fact('half-de')].join('|');
          const table = () => document.querySelector('table[data-htmxo-bound-table]');
          const rows = () => Array.from(table().tBodies[0].rows);
          const cell = c => [c.textContent, c.getAttribute('data-sort-value'), c.getAttribute('data-htmxo-number')].join('~');
          const snapshot = () => rows().map(r => cell(r.cells[0])).join('|');
          function typed(v) { const c = document.querySelector('input[name="slope"]'); c.value = v; c.dispatchEvent(new Event('input', {bubbles: true})); }
          try {
            await until(() => table() && rows().length === 3, () => 'table');
            const server = snapshot();
            if (facts() !== '2.0 years|2 Jahre') throw new Error('first facts: ' + facts());
            await fetch('/mark?phase=start');
            for (const [slope, en, de, expectedCell] of [
              ['0', 'No finite halving time', 'No finite halving time', 'No finite halving time~Infinity~'],
              ['-2', 'Negative infinity', 'Negative infinity', 'Negative infinity~-Infinity~'],
              ['2', '–', '–', '–~~'],
              ['0.8', '1.3 years', '1,3 Jahre', '1.3~1.25~1.25'],
              ['0', 'No finite halving time', 'No finite halving time', 'No finite halving time~Infinity~']
            ]) {
              typed(slope);
              await until(() => facts() === en + '|' + de && cell(rows()[0].cells[0]) === expectedCell,
                () => facts() + ' / ' + snapshot());
              const words = document.createRange();
              words.selectNodeContents(rows()[0].cells[0]);
              if (words.getClientRects().length !== 1) throw new Error('label broken across lines: ' + en);
              if (rows()[1].cells[0].getAttribute('data-htmxo-number') !== '2.125') throw new Error('numeric CSV');
              if (cell(rows()[2].cells[0]) !== 'None~0.0~') throw new Error('zero label: ' + snapshot());
            }
            const search = document.querySelector('.sortable-table-search input, input[type="search"]');
            if (!search) throw new Error('search control missing');
            search.value = 'finite'; search.dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => rows().filter(r => !r.hidden && r.style.display !== 'none').length === 1, () => 'search labels');
            search.value = ''; search.dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => rows().every(r => !r.hidden && r.style.display !== 'none'), () => 'clear search');
            sortTable(table().tHead.rows[0].cells[0]);
            if (rows().map(r => r.cells[0].textContent).join('|') !== 'None|2.1|No finite halving time') throw new Error('numeric sort: ' + snapshot());
            // Clear the sort by returning to source order before testing exact parity.
            typed('0.5');
            await until(() => facts() === '2.0 years|2 Jahre', () => 'back: ' + facts());
            const cells = rows().map(r => cell(r.cells[0])).sort().join('|');
            if (cells !== server.split('|').sort().join('|')) throw new Error('server parity: ' + cells + ' / ' + server);
            if (document.querySelector('.htmxo-browser-fault')) throw new Error('browser fault');
            await fetch('/mark?phase=end');
            await fetch('/complete?status=passed');
          } catch (error) { await fetch('/complete?status=' + encodeURIComponent(String(error))); }
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
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end

@testitem "a static page writes its bound table and facts again offline in a browser" setup=[BrowserFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, JSON
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(Shield(); operation_policy = :blocking)
        HTMXObjects.vendorfiles("assets/vendor")
        # What format_number writes, which the page's `htmxoNumberText` must write too.
        js(x::Integer) = string(x)
        js(x::AbstractFloat) = HTMXObjects._js_number_text(Float64(x))
        numbers = (0.15623, 2.0, -0.0, 3.81e-5, -1234.5, 1e15, 1.5e15, 0.125, 0.145, 0.07, 2850.0, 9.96, 1234567.25,
                   5e-324, 0.4517, Inf, -Inf, NaN, 0, 42, -1234, 1234567)
        formats = ((;), (; digits = 0), (; digits = 3), (; sigdigits = 2), (; percent = true),
                   (; percent = true, digits = 1), (; percent = true, sigdigits = 2))
        cases = String[]
        for x in numbers, f in formats, texts in (table_texts(), table_texts(:de))
            t = Dict(string(n) => getfield(texts, n) for n in (:decimal, :thousands, :minus, :percent))
            fjs = JSON.json(merge(Dict{String,Any}(string(k) => v for (k, v) in pairs(f)), Dict{String,Any}("texts" => t)))
            push!(cases, string("[", js(x), ",", fjs, ",", x isa Integer, ",", JSON.json(format_number(x; texts, f...)), "]"))
        end
        driver = """
        <script>
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          async function until(check, label) {
            const end = Date.now() + 10000;
            while (!check()) { if (Date.now() > end) throw new Error('timeout: ' + (typeof label === 'function' ? label() : label)); await sleep(25); }
          }
          const table = () => document.querySelector('table[data-htmxo-bound-table]');
          const rows = () => Array.from(table().tBodies[0].rows);
          const cell = c => [c.textContent, c.getAttribute('data-sort-value'), c.getAttribute('data-htmxo-number'), c.getAttribute('data-htmxo-align')].join('~');
          const snapshot = () => rows().map(r => r.getAttribute('data-htmxo-link-key') + '=' + Array.from(r.cells).map(cell).join('|')).sort().join(' ');
          const column = j => rows().map(r => r.cells[j].textContent).join(',');
          const fact = name => Array.from(document.querySelectorAll('.' + name + ' [data-htmxo-bound]')).map(e => e.textContent).join('|');
          const facts = () => [fact('half'), fact('at'), fact('de')].join(' ');
          // The one-row table of the single value `half`.
          const halfRow = () => Array.from(document.querySelectorAll('table[data-htmxo-bound-table]')[1].tBodies[0].rows).map(r => r.textContent).join(',');
          const field = () => document.querySelector('input[name="attenuation"]');
          function typed(v) { const c = field(); c.value = v; c.dispatchEvent(new Event('input', {bubbles: true})); }
          try {
            const cases = [$(join(cases, ",\n"))];
            const wrong = cases.filter(c => htmxoNumberText(c[0], c[1], c[2]) !== c[3])
              .map(c => [c[0], c[1], htmxoNumberText(c[0], c[1], c[2]), c[3]]);
            if (wrong.length) throw new Error(wrong.length + ' numbers differ: ' + JSON.stringify(wrong.slice(0, 4)));
            await until(() => table() && rows().length === 4, 'table');
            const server = snapshot();
            if (facts() !== '100 83%|50% 0,833') throw new Error('first facts: ' + facts());
            if (halfRow() !== '100') throw new Error('first one-row table: ' + halfRow());
            // The reader sorts by the share, ascending.
            const th = table().tHead.rows[0].cells[2];
            sortTable(th);
            if (column(0) !== '100,50,20,0') throw new Error('sorted: ' + column(0));
            await fetch('/mark?phase=start');
            typed('0.02');
            await until(() => facts() === '50 71%|33% 0,714', () => 'typed facts: ' + facts());
            await until(() => column(2) === '0.333,0.500,0.714,1.000', () => 'typed table: ' + column(2));
            await until(() => halfRow() === '50', () => 'typed one-row table: ' + halfRow());
            // The reader's sort holds for the new rows.
            if (column(0) !== '100,50,20,0' || th.getAttribute('aria-sort') !== 'ascending')
              throw new Error('sort kept: ' + column(0) + ' ' + th.getAttribute('aria-sort'));
            // The ⬇ CSV and the sort read the unrounded share.
            const r20 = table().querySelector('tr[data-htmxo-link-key="20"]');
            if (r20.cells[2].getAttribute('data-htmxo-number') !== $(repr(string(1 / 1.4))))
              throw new Error('csv value: ' + r20.cells[2].getAttribute('data-htmxo-number'));
            // Hover linking lights the new rows.
            htmxoLink('shield', '50');
            await until(() => table().querySelector('tr[data-htmxo-link-key="50"]').hasAttribute('data-htmxo-linked'), 'linked row');
            htmxoLink('shield', null);
            // A slider held down: its `input` events alone redraw facts and table.
            const slider = document.querySelector('input[data-htmxo-number-slider]');
            slider.value = slider.min;
            slider.dispatchEvent(new Event('input', {bubbles: true}));
            await until(() => fact('half') === '200', () => 'held slider: ' + facts());
            await until(() => column(2) === '0.667,0.800,0.909,1.000', () => 'held slider table: ' + column(2));
            await until(() => halfRow() === '200', () => 'held slider one-row table: ' + halfRow());
            // Back at the first value, the browser's rows are the server's, cell by cell.
            typed('0.01');
            await until(() => facts() === '100 83%|50% 0,833', () => 'back: ' + facts());
            await until(() => snapshot() === server, () => 'parity: ' + snapshot() + ' / ' + server);
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
            # Between the marks the page computed and redrew without a single request.
            start = findfirst(==("/mark?phase=start"), requests)
            stop = findfirst(==("/mark?phase=end"), requests)
            @test start !== nothing && stop !== nothing && stop == start + 1
        end
    end
end
