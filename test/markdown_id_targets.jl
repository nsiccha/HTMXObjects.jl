@testitem "render_markdown makes empty span and a id targets real elements" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: to_markdown_string
    html(src) = repr("text/html", render_markdown(src; rules=MarkdownRule[]))

    # BRM's prior-table shape: a target, the label, and a link to it.
    src = "<span id=\"brm-prior-0123456789abcdef\"></span>P1, see [P1](#brm-prior-0123456789abcdef)."
    out = html(src)
    @test contains(out, "<p><span id=\"brm-prior-0123456789abcdef\"></span>P1, see ")
    @test contains(out, "<a href=\"#brm-prior-0123456789abcdef\">P1</a>")
    @test !contains(out, "&lt;")
    # The Markdown projection writes the tags back as written.
    @test rstrip(to_markdown_string(render_markdown(src; rules=MarkdownRule[]))) == src

    # An older BRM's `<a id>` form, and ids with digits, `_` and `-`.
    @test contains(html("x <a id=\"old_target-1\"></a>P2 y"),
        "<p>x <a id=\"old_target-1\"></a>P2 y</p>")

    # Inside a GFM table cell.
    table = "| Prior | Term |\n|---|---|\n| <span id=\"t-1\"></span>P1 | x |\n"
    cell = html(table)
    @test contains(cell, "<span id=\"t-1\"></span>P1</td>")
    @test !contains(cell, "&lt;")
    @test contains(to_markdown_string(render_markdown(table; rules=MarkdownRule[])),
        "| <span id=\"t-1\"></span>P1 | x |")

    # In a heading and a list item.
    @test contains(html("## <span id=\"h\"></span>Priors"), "<h2><span id=\"h\"></span>Priors</h2>")
    @test contains(html("- <span id=\"li\"></span>P1\n- P2\n"), "<li><span id=\"li\"></span>P1</li>")

    # SemanticProse renders through the same walk.
    @test contains(repr("text/html", SemanticProse("<span id=\"p\"></span>P1")),
        "<span id=\"p\"></span>P1")
end

@testitem "render_markdown keeps other raw HTML tags escaped" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: to_markdown_string
    html(src) = repr("text/html", render_markdown(src; rules=MarkdownRule[]))
    escaped(src) = (out = html(src); contains(out, "&lt;") && !contains(out, " id=\""))

    @test escaped("<span id=\"x\" class=\"c\"></span>P1")   # another attribute
    @test escaped("<span class=\"c\" id=\"x\"></span>P1")
    @test escaped("<span id=\"x\">P1</span>")                # content between the tags
    @test escaped("<span id=\"x\"> </span>")
    @test escaped("<span id=\"1x\"></span>P1")               # id must start with a letter
    @test escaped("<span id=\"a b\"></span>P1")
    @test escaped("<span id=\"a.b\"></span>P1")
    @test escaped("<span id=\"\"></span>P1")
    @test escaped("<span id='x'></span>P1")                  # only the double-quoted form
    @test escaped("<span id=\"x\">P1")                       # unpaired opening tag
    @test escaped("P1</span>")                               # unpaired closing tag
    @test escaped("<span id=\"x\"></a>")                     # mismatched closing tag
    @test escaped("<div id=\"x\"></div>P1")                  # other elements
    @test escaped("<b id=\"x\"></b>P1")
    # An `<a>` inside a link would be invalid HTML; a `<span>` is fine there.
    @test escaped("[label <a id=\"x\"></a>](#y)")
    @test contains(html("[label <span id=\"x\"></span>](#y)"),
        "<a href=\"#y\">label <span id=\"x\"></span></a>")

    # Escaped tags still project back as written.
    src = "<span id=\"x\" class=\"c\"></span>P1"
    @test rstrip(to_markdown_string(render_markdown(src; rules=MarkdownRule[]))) == src
end
