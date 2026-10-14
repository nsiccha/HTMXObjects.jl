@testitem "Markdown shows the state a control shows the reader" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    md(x) = to_markdown_string(x)

    # A row's toggle: the label names the state and `aria-pressed` carries it.
    toggle(on) = h.button(on ? "ineligible" : "eligible"; type="button",
        aria_pressed=on ? "true" : "false", hx_post="/toggle", hx_target="closest tr")
    table = h.table(h.thead(h.tr(h.th("Row"), h.th("Eligibility"))),
        h.tbody(h.tr(h.td("1"), h.td(toggle(true))), h.tr(h.td("2"), h.td(toggle(false)))))
    @test md(table) == "| Row | Eligibility |\n| --- | --- |\n" *
        "| 1 | ineligible (pressed) |\n| 2 | eligible (not pressed) |\n\n"
    # The HTML is untouched.
    @test repr("text/html", toggle(true)) == "<button type=\"button\" aria-pressed=\"true\" " *
        "hx-post=\"/toggle\" hx-target=\"closest tr\">ineligible</button>"

    # Every toggle state, on a button and on any other element.
    @test md(h.p(h.button("Mute"; aria_pressed="mixed"))) == " Mute (mixed)\n\n"
    @test md(h.p(h.button("Mute"; aria_pressed=true))) == " Mute (pressed)\n\n"
    @test md(h.p(h.button("Autosave"; role="switch", aria_checked="true"))) ==
        " Autosave (checked)\n\n"
    @test md(h.ul(h.li("Bold"; role="menuitemcheckbox", aria_checked="false"))) ==
        "- Bold (not checked)\n"
    # The label keeps its markup, minus any chrome inside it.
    @test md(h.p(h.button(h.strong("Mute"), h.input(type="hidden", value="x"); aria_pressed="false"))) ==
        " **Mute** (not pressed)\n\n"
    # A state attribute outside the ARIA values is no toggle: the button is dropped.
    @test md(h.p("keep", h.button("X"; aria_pressed="undefined"))) == "keep\n\n"
    # A toggle that is also a labelled control states its state.
    @test md(h.p(h.button("On"; aria_pressed="true", data_htmxo_label=""))) == " On (pressed)\n\n"

    # A select shows its chosen option, not every option in a row.
    options = (h.option("Food"; value="f"), h.option("Travel"; value="t", selected=true),
        h.option("Office"; value="o"))
    @test md(h.p("Category:", h.select(name="c")(options...))) == "Category: Travel\n\n"
    @test md(h.p("Category:", h.select(name="c")(h.option("Food"; disabled=true), h.option("Rent")))) ==
        "Category: Rent\n\n"
    @test md(h.p("Pick:", h.select(h.optgroup(label="G")(h.option("y"),
        h.option("z"; selected=true, label="Zed"))))) == "Pick: Zed\n\n"
    @test md(h.p("Tags:", h.select(multiple=true)(h.option("a"; selected=true), h.option("b"),
        h.option("c"; selected=true)))) == "Tags: a, c\n\n"
    @test md(h.p("Tags:", h.select(multiple=true)(h.option("a"), h.option("b")))) == "Tags:\n\n"

    # Checkbox and radio marks, and value fields.
    @test md(h.p(h.input(type="checkbox", checked=true), "archived ",
        h.input(type="checkbox"), "draft")) == "☑ archived ☐ draft\n\n"
    @test md(h.p(h.input(type="radio", checked=true), "A ", h.input(type="radio"), "B")) ==
        "◉ A ○ B\n\n"
    @test md(h.p("Name:", h.input(type="text", value="Ada"), " N:", h.input(type="number", value="3"),
        " Q:", h.input(value="untyped"))) == "Name: Ada N: 3 Q: untyped\n\n"
    # Fields that show nothing, secrets, uploads and actions are dropped.
    @test md(h.p("E:", h.input(type="text"), " P:", h.input(type="password", value="secret"),
        " H:", h.input(type="hidden", value="h"), " S:", h.input(type="submit", value="Go"),
        " F:", h.input(type="file"))) == "E: P: H: S: F:\n\n"
    @test md(h.p("Body:", h.textarea("long text"))) == "Body:\n\n"
    # A form still goes whole, state and all.
    @test md(h.div(h.p("before"), h.form(h.button("ineligible"; aria_pressed="true"),
        h.select(h.option("x"; selected=true)), h.input(type="checkbox", checked=true)),
        h.p("after"))) == "before\n\nafter\n\n"
    # An action button stays dropped.
    @test md(h.p("keep ", h.button("Run"))) == "keep \n\n"
end
