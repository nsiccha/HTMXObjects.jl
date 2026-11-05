# The plain-text peer of semantic content that holds HTML nodes (snag
# `semantic-tabset-2bf661bc`, reporter BayesianRegressionModels:model-view:review):
# a `tabset` or a layout `h.div` inside a `SemanticSection` read as Julia's
# `Node(:div, OrderedDict(…))` dump in `repr("text/plain", section)`, because a
# node has no plain-text `show` of its own. It now reads as its text, in the
# blocks its Markdown peer lays out, with no markup.

@testitem "a tabset inside a section reads as its tabs in plain text" tags=[:unit] begin
    using HTMXObjects

    # The reporter's shape: a section whose details are tabs, one of which holds
    # a layout `div` with prose and a nested tabset of sections.
    definition = SemanticSection("Definition · Main.Probe.defaults",
        SemanticFields(; defining_module="Main.Probe"),
        SemanticCode(:julia, "@brm function defaults(x, shift=2; scale=3)\nend"),
        SemanticSection("Call instances", SemanticProse("Root definition")))
    source = h.div(SemanticProse("Each component definition is shown once."),
        tabset("Main.Probe.defaults" => definition; url_param=nothing, label="Model and component source"))
    view = SemanticSection("Model component", SemanticProse("Reusable component definition."),
        tabset("Source" => source,
               "Inputs" => SemanticTable((; input=["x", "shift"], default=["", "2"])),
               "Lazy" => "/api/lazy";
               url_param=nothing, label="Model component details"))
    plain = repr("text/plain", view)
    @test plain == """
        Model component

        Reusable component definition.

        Source

        Each component definition is shown once.

        Main.Probe.defaults

        Definition · Main.Probe.defaults

        defining_module: Main.Probe


        @brm function defaults(x, shift=2; scale=3)
        end

        Call instances

        Root definition

        Inputs

        input\tdefault
        x\t
        shift\t2

        Lazy (/api/lazy)"""
    # Control: none of the struct dump the snag reported, nor the tab bar's
    # script or attributes.
    for leaked in ("Node(", "OrderedDict", "_TabsetPart", "SemanticDisclosure", "htmxoTabset", "tablist")
        @test !contains(plain, leaked)
    end
    # The Markdown peer keeps its own markup: bold labels, a lazy tab as a link.
    md = repr("text/markdown", view)
    @test contains(md, "**Source**") && contains(md, "Each component definition is shown once.")
    @test contains(md, "**[Lazy](/api/lazy)**")
end

@testitem "a tabset's plain text follows its reader's audience" tags=[:unit] begin
    using HTMXObjects

    # Outside a request the reader is public: a private tab with no stand-in
    # goes with its label, one with a stand-in shows the stand-in.
    view = SemanticSection("Modell",
        tabset("Überblick" => SemanticProse("Bayes-Regression."),
               "Modelldefinition" => private(SemanticCode(:julia, "mu ~ 1 + wohnflaeche")),
               "Kurz" => private(h.p("lang"); public=h.p("kurz"));
               url_param=nothing))
    @test repr("text/plain", view) == "Modell\n\nÜberblick\n\nBayes-Regression.\n\nKurz\n\nkurz"
end

@testitem "HTML nodes among semantic content read as their text in plain text" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: HTMX

    plain(x) = repr("text/plain", SemanticGroup(x))
    # A link writes `label (target)`, as `SemanticLink` does; one that names no
    # target is its text; one whose text is its address writes it once.
    @test plain(h.p("See ", h.a("the docs"; href="/docs"), ", ", h.a("this"; href="#"), " and ",
                    h.a("/x"; href="/x"), ".")) == "See the docs (/docs), this and /x."
    # Blocks are paragraphs; inline elements stay in their line; a line break
    # breaks the line.
    @test plain(h.div(h.p("one ", h.strong("bold"), " ", h.code("code")), h.p("a", h.br(), "b"))) ==
        "one bold code\n\na\nb"
    # Lists: one item per line, an `<ol>` numbered from its `start`, a nested list
    # indented under its item.
    @test plain(h.ul(h.li("one"), h.li("two", h.ul(h.li("nested"))))) == "- one\n- two\n  - nested"
    @test plain(h.ol(; start=3)(h.li("c"), h.li("d"))) == "3. c\n4. d"
    # A table: one tab-separated line per row, as `SemanticTable` writes; a cell
    # spanning columns takes their places; a cell's line breaks fold.
    @test plain(h.table(h.thead(h.tr(h.th("a"), h.th("b"), h.th("c"))),
                        h.tbody(h.tr(h.td("1"; colspan=2), h.td("2")), h.tr(h.td("x"), h.td("y\nz"), h.td(""))))) ==
        "a\tb\tc\n1\t\t2\nx\ty z\t"
    # What Markdown leaves out, plain text leaves out: scripts, styles, buttons
    # and a details' toggle label. An image is its `alt`.
    @test plain(h.div(h.script(HTMX.Raw("alert(1)")), h.style("p{}"), h.button("Click"),
                      h.details(h.summary("More"), h.p("body")), h.img(; src="/x.png", alt="A plot"))) ==
        "body\n\nA plot"
    # Semantic elements inside nodes write their own plain peers.
    @test plain(h.div(SemanticMetric("draws", 4000), h.p(SemanticLink("docs", "/docs")))) ==
        "draws: 4000\n\ndocs (/docs)"
    # Wrappers that sit in node trees: a snapshot reads as its value, a
    # `markdown_only` as its text, an `html_only` as nothing.
    @test plain(h.div(HTMLSnapshot(h.p("kept")), markdown_only("for readers"), html_only(h.p("browser")))) ==
        "kept\n\nfor readers"
end

@testitem "a master/detail table's eager details follow it in plain text" tags=[:unit] begin
    using HTMXObjects

    table = master_detail_table(["Thing"], [1, 2];
        key=identity,
        master=r -> (h.td("row $r"),),
        detail=r -> r == 1 ? SemanticProse("detail of one") : nothing,
        id="things")
    plain = repr("text/plain", SemanticSection("Things", table))
    @test startswith(plain, "Things\n\n")
    @test contains(plain, "Thing\nrow 1\nrow 2")
    @test contains(plain, "row 1\n\ndetail of one")
    @test !contains(plain, "Node(") && !contains(plain, "_MD")
end
