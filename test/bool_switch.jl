using TestItemRunner

@testmodule BoolSwitchFixtures begin
    using HTMXObjects
    export SwitchPage, WrongControl

    # `ploughed` and `boxed` are read by two results, so they sit in the
    # sidebar; `above` is `trend`'s own input and follows `level`; `archive`
    # and `forced` belong to the mutation `save`, which a button sends.
    @htmx struct SwitchPage
        "Show the ploughed-soil difference"
        @param ploughed::Bool = true
        @param level::Float64 = 1.0
        "Only above one"
        @param above::Bool = level > 1.0
        @param boxed::Bool = false
        @control(boxed) = :checkbox
        @param archive::Bool = false
        @param forced::Bool = false
        @control forced = :switch
        @get trend() = h.p("trend:", ploughed, ":", level, ":", above, ":", boxed)
        @get table() = h.p("table:", ploughed, ":", level, ":", boxed)
        @post save(; confirm::Bool = false) =
            h.p("saved:", confirm, ":", archive, ":", forced, ":", ploughed)
        @get index() = semantic_app(__self__; presentation=:tabs,
            select=entry -> entry.name in (:trend, :table, :save))
        @get stacked() = semantic_app(__self__; select=entry -> entry.name in (:trend, :save))
    end

    @htmx struct WrongControl
        @param rate::Float64 = 1.0
        @control(rate) = :switch
        @get first() = h.p(rate)
        @get second() = h.p(rate)
        @get index() = semantic_app(__self__; presentation=:tabs,
            select=entry -> entry.name in (:first, :second))
    end
end

@testitem "a generated Bool is a switch where a change applies at once and a checkbox where a button sends it" setup=[BoolSwitchFixtures, SemanticPageFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    @test HTMXObjects._param_controls(SwitchPage) == (boxed=:checkbox, forced=:switch)
    route!(SwitchPage(); operation_policy=:blocking)
    page(url) = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    field(html, name) = tag_attrs(html, Regex("<input[^>]*name=\"$name\"[^>]*>"))
    html = page("/")

    # The sidebar applies a change at once: a switch, the same box with
    # `role="switch"`, submitting "true", its label after it.
    sidebar = sidebar_of(html)
    @test contains(sidebar, "<label><input type=\"checkbox\" name=\"ploughed\" checked=\"true\" role=\"switch\" value=\"true\">Show the ploughed-soil difference</label>")
    # `@control(boxed) = :checkbox` keeps a box there.
    @test field(sidebar, "boxed")["type"] == "checkbox"
    @test !haskey(field(sidebar, "boxed"), "role")
    @test field(sidebar, "boxed")["value"] == "true"

    # A following tab's own input applies at once too, and keeps following its
    # computed default; its refresh says so, and draws the switch again.
    trend = tab_of(html, "trend")
    above = field(trend, "above")
    @test above["role"] == "switch" && above["value"] == "true"
    @test haskey(above, "data-htmxo-follows") && !haskey(above, "checked")
    region = tag_attrs(trend, r"<div class=\"htmxo-semantic-controls\"[^>]*>")
    @test contains(region["hx-get"], "__htmxo_live=1")
    refreshed = page(region["hx-get"] * "&ploughed=true&level=2.0&boxed=false")
    @test field(refreshed, "above")["role"] == "switch"
    @test haskey(field(refreshed, "above"), "checked")
    @test haskey(field(refreshed, "above"), "data-htmxo-follows")

    # A mutation's form waits for its button: its `Bool` input is a checkbox,
    # and `@control(forced) = :switch` draws a switch there. A `Bool`
    # argument's two values stay pills.
    save = tab_of(html, "save")
    @test contains(save, "<button")
    @test field(save, "archive")["type"] == "checkbox" && !haskey(field(save, "archive"), "role")
    @test field(save, "archive")["value"] == "true"
    @test field(save, "forced")["role"] == "switch"
    @test field(save, "confirm")["type"] == "radio"
    @test !contains(save, "__htmxo_live")

    # An operation card of the stacked presentation is sent with its button.
    stacked = page("/stacked")
    @test field(stacked, "confirm")["type"] == "radio"
    @test !contains(stacked, "role=\"switch\"")

    # What a switch submits is what a checkbox submits.
    hx = ["HX-Request" => "true"]
    @test result_text(dispatch(:GET, "/trend?ploughed=false&level=2.0&above=true&boxed=true"; headers=hx)) ==
        "trend:false:2.0:true:true"
    @test result_text(dispatch(:GET, "/trend?level=0.5"; headers=hx)) == "trend:true:0.5:false:false"
    @test result_text(dispatch(:POST, "/save?forced=true&archive=true&confirm=true&ploughed=false";
        headers=hx)) == "saved:true:true:true:false"
    # The Markdown reads a switch as the box it is.
    @test HTMXObjects.to_markdown_string(cinput("x"; label="On", checked=true, switch=true)) == "☑ On"

    # The page's shell draws a switch's "on" track in the text colour, after
    # the unlayered pills, on pages with and without Pico.
    css = repr("text/html", htmxo_utility_styles())
    rule = "input[type=\"checkbox\"][role=\"switch\"] {\n    --pico-switch-checked-background-color: var(--pico-contrast-background, CanvasText);"
    @test contains(css, rule)
    @test contains(css, "input[type=\"checkbox\"][role=\"switch\"]:checked {\n    --pico-switch-color: var(--pico-contrast-inverse, Canvas);")
    @test findfirst(rule, css).start > findfirst("/* Unlayered so it beats", css).start
    @test contains(repr("text/html", htmx(h.p("x"))), rule)

    # `@control` names a `Bool` `@param` of the struct and one of the two
    # controls, once.
    for body in (:(begin @param x::Bool = false; @control(x) = switch end),
                 :(begin @param x::Bool = false; @control(x) = :toggle end),
                 :(begin @param x::Bool = false; @control(missing_input) = :switch end),
                 :(begin @param x::Bool = false; @control(x) = :switch; @control(x) = :checkbox end))
        ex = Expr(:struct, false, gensym(:BadControl), body)
        @test_throws ArgumentError HTMXObjects._convert_params!(ex)
    end
    # On any other input it would be ignored, so the page refuses it, naming it.
    route!(WrongControl(); operation_policy=:blocking)
    @test dispatch(:GET, "/"; headers=["Accept" => "text/html"]).status == 500
    route = HTMXObjects._semantic_runtime_route(WrongControl(),
        HTMXObjects._operation_route(WrongControl, :first, :GET))
    param = only(p for p in route.params if p.name === :rate)
    @test param.control === :switch
    err = try
        HTMXObjects._semantic_default_control(WrongControl(), WrongControl, param, "Rate", 1.0, (;))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test contains(err.msg, "@control(rate) = :switch") && contains(err.msg, "declared as `Float64`")
end

@testitem "a switch's on track reads in the text colour in light and dark, never Pico's azure" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = e => getComputedStyle(e), box = e => e.getBoundingClientRect();
                const pico = document.documentElement.dataset.pico === '1';
                const probe = value => { const p = document.getElementById('probe'); p.style.backgroundColor = value; return css(p).backgroundColor; };
                const on = document.querySelector('#on input'), off = document.querySelector('#off input'),
                      generated = document.querySelector('#generated input'), plain = document.querySelector('#plain input');
                const knob = e => getComputedStyle(e, '::before').backgroundColor;
                if (pico) {
                    // Positive control: Pico draws a box with role=switch as a switch, wider than tall,
                    // and a plain checkbox, ticked, in its azure.
                    out.control = String(css(on).appearance === 'none' && box(on).width > box(on).height * 1.5 &&
                        css(plain).backgroundColor === probe('var(--pico-primary-background)'));
                    // On: the track is the text colour with a knob in the page colour; never azure.
                    const filled = e => css(e).backgroundColor === probe('var(--pico-contrast-background)') &&
                        knob(e) === probe('var(--pico-contrast-inverse)') &&
                        css(e).backgroundColor !== probe('var(--pico-primary-background)');
                    out.on = String(filled(on) && filled(generated));
                    // Off: Pico's own grey track and white knob.
                    out.off = String(css(off).backgroundColor === probe('var(--pico-switch-background-color)') &&
                        knob(off) === probe('var(--pico-switch-color)'));
                    // A click turns it on, drawn as on, and the form sends "true".
                    off.click();
                    out.toggle = String(off.checked && filled(off) &&
                        new FormData(document.getElementById('form')).get('off') === 'true');
                    const light = css(on).backgroundColor;
                    document.documentElement.dataset.theme = 'dark';
                    out.dark = String(filled(on) && css(on).backgroundColor !== light);
                } else {
                    // Without Pico it is a box that still submits "true".
                    out.control = String(box(on).width > 5 && on.checked);
                    out.on = String(!new FormData(document.getElementById('form')).has('off'));
                    off.click();
                    out.toggle = String(new FormData(document.getElementById('form')).get('off') === 'true');
                    out.off = 'true'; out.dark = 'true';
                }
                out.done = '1';
            });
            """))
        content = h.main(; class="container")(
            h.form(; id="form")(
                h.div(; id="on")(cinput("on"; label="On", checked=true, switch=true, value="true")),
                h.div(; id="off")(cinput("off"; label="Off", switch=true, value="true")),
                h.div(; id="generated")(HTMXObjects._typed_control(Bool, "ploughed", "Ploughed", true, (;); switch=true)),
                h.div(; id="plain")(cinput("plain"; label="Plain", checked=true, value="true"))),
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
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1000,800 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
            end
            @test contains(dom, "data-done=\"1\"")
            for marker in ("control", "on", "off", "toggle", "dark")
                @test contains(dom, "data-$marker=\"true\"")
            end
        end
    end
end
