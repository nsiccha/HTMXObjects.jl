@testitem "a raw disclosure keeps its summary in Markdown reads" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string

    md(x) = to_markdown_string(x)
    @test md(h.details(h.summary("S"), h.p("B"))) == "**S**\n\nB\n\n"
    @test md(h.details(h.summary(h.h2("Heading")), h.p("B"))) == "## Heading\n\nB\n\n"
    @test md(h.details(h.summary("S"), h.p("B"), h.summary("Later"))) ==
        "**S**\n\nB\n\nLater"
    @test md(h.details(h.summary("Outer"), h.details(h.summary("Inner"), h.p("B")))) ==
        "**Outer**\n\n**Inner**\n\nB\n\n"
    # Stripping controls leaves nothing to open: its summary goes with the body.
    for body in (nothing, h.button("Save"), h.form(h.input(value="x"), h.button("Save")))
        @test md(h.div(h.p("before"), h.details(h.summary("Edit"), body), h.p("after"))) ==
            "before\n\nafter\n\n"
    end

    # The reporter's shape goes through the real ?plain response pipeline too.
    @htmx struct DisclosureTextApp
        @get index() = h.details(; class="group")(
            h.summary("Claude resets: 1 held"),
            h.div(; class="overflow-auto")(
                h.table(h.thead(h.tr(h.th("Login"), h.th("Left"))),
                    h.tbody(h.tr(h.td("test-login"), h.td("1 of 1"))))),
            h.small("Times are local."))
    end
    prefix = "/disclosure-text-summary"
    route!(DisclosureTextApp(); prefix)
    response = dispatch(:GET, prefix * "/?plain=1")
    @test response.status == 200
    text = String(HTMXObjects._message_body_bytes(response))
    @test occursin("**Claude resets: 1 held**", text)
    @test occursin("| test-login | 1 of 1 |", text)
    @test occursin("Times are local.", text)
    @test first(findfirst("Claude resets:", text)) < first(findfirst("| Login |", text))
end
