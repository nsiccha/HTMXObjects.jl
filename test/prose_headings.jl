using TestItemRunner

@testmodule ProseHeadingsFixture begin
    using HTMXObjects, Markdown
    # A Julia docstring's level-1 headings, shown inside nested sections as
    # BayesianRegressionModels' model view does (snag semanticprose-em-202acc7a).
    const DOC = Markdown.parse("""
        f(x)

    Lead paragraph of a docstring.

    # Usage

    ```julia
    f(1)
    ```

    # Implementation

    Implementation notes.
    """)
    view(prose) = SemanticSection("Model and workflow",
        SemanticSection("Model specification",
            SemanticSection("Callable documentation",
                SemanticDisclosure("Mod.f", prose))),
        SemanticSection("Next section", SemanticProse("After the docstring.")))
    md(x) = HTMXObjects.to_markdown_string(x)
    html(x) = repr("text/html", x)
    # The heading levels of Markdown outside code fences, and of HTML, in order.
    function md_levels(text)
        levels, fence = Pair{Int,String}[], false
        for line in split(text, '\n')
            startswith(line, "```") && (fence = !fence; continue)
            fence && continue
            m = match(r"^[> -]*(#{1,6}) (.*)$", line)
            isnothing(m) || push!(levels, length(m[1]) => String(m[2]))
        end
        levels
    end
    html_levels(text) = [parse(Int, m[1]) => replace(m[2], r"<[^>]*>" => "")
                         for m in eachmatch(r"<h([1-6])[^>]*>(.*?)</h\1>"s, text)]
end

@testitem "a prose's headings follow the section nesting in Markdown and HTML" setup=[ProseHeadingsFixture] tags=[:unit, :semantic] begin
    using HTMXObjects
    (; DOC, view, md, html, md_levels, html_levels) = ProseHeadingsFixture

    node = view(SemanticProse(DOC))
    expected = [2 => "Model and workflow", 3 => "Model specification", 4 => "Callable documentation",
                5 => "Usage", 5 => "Implementation", 3 => "Next section"]
    @test md_levels(md(node)) == expected
    @test html_levels(html(node)) == expected
    @test occursin("Lead paragraph of a docstring.\n\n##### Usage\n\n```julia\nf(1)\n```\n\n##### Implementation\n\nImplementation notes.",
                   md(node))
    # The plain-text peer keeps the source.
    @test occursin("\n# Usage\n", repr("text/plain", node))

    # At the top of a page a prose opens where a section would, below the title;
    # inside a `level=1` section, below it.
    top = SemanticProse("# Appendix\n\nText.\n\n## Detail\n\nMore.")
    @test md(top) == "## Appendix\n\nText.\n\n### Detail\n\nMore."
    @test html_levels(html(top)) == [2 => "Appendix", 3 => "Detail"]
    @test md_levels(md(SemanticGroup(SemanticSection("Intro", "Opening."), top))) ==
        [2 => "Intro", 2 => "Appendix", 3 => "Detail"]
    @test html_levels(html(SemanticSection("Page", top; level=1))) ==
        [1 => "Page", 2 => "Appendix", 3 => "Detail"]
end

@testitem "a prose's outline is closed up, and none deeper than the sixth level" setup=[ProseHeadingsFixture] tags=[:unit, :semantic] begin
    using HTMXObjects, Markdown
    (; md, html, md_levels, html_levels) = ProseHeadingsFixture
    in_api(prose) = SemanticSection("API", SemanticSection("f", prose))
    both(x) = (md_levels(md(x)), html_levels(html(x)))

    # A heading written deeper than one before it is closed up to one level
    # below it; headings written at one level stay siblings.
    starts_deeper = in_api(SemanticProse(Markdown.parse("Lead.\n\n## Notes\n\nA.\n\n# Examples\n\nB.\n")))
    @test all(==([2 => "API", 3 => "f", 4 => "Notes", 4 => "Examples"]), both(starts_deeper))
    skips = in_api(SemanticProse("# A\n\n### B\n\n### C\n\n#### D\n\n## E"))
    @test all(==([2 => "API", 3 => "f", 4 => "A", 5 => "B", 5 => "C", 6 => "D", 5 => "E"]), both(skips))
    # A prose without gaps keeps its outline exactly, moved under its section.
    nested = in_api(SemanticProse("# A\n\n## B\n\n# C\n\n## D"))
    @test all(==([2 => "API", 3 => "f", 4 => "A", 5 => "B", 4 => "C", 5 => "D"]), both(nested))

    # Inside sections six deep, every heading of the prose is at the sixth.
    deep = foldr((t, inner) -> SemanticSection(t, inner), ["L2", "L3", "L4", "L5", "L6"];
                 init=SemanticProse("# Top\n\nA.\n\n## Below\n\nB.\n\n### Further\n\nC."))
    sixth = [2 => "L2", 3 => "L3", 4 => "L4", 5 => "L5", 6 => "L6", 6 => "Top", 6 => "Below", 6 => "Further"]
    @test all(==(sixth), both(deep))
end

@testitem "only a prose's heading lines change in its Markdown" setup=[ProseHeadingsFixture] tags=[:unit, :semantic] begin
    using HTMXObjects
    (; md, html, html_levels) = ProseHeadingsFixture

    # Setext headings become one ATX line; headings in a quote or a list item
    # keep their container; a `#` in a code fence or indented code is text.
    source = """
    Title
    =====

    Para with a [link](https://example.org) and \$x_1\$.

    Sub title
    on two lines\\
    ------------

    > # Quoted
    > text

    - item

      # In list

    ```
    # not a heading
    ```

        # indented code
    """
    mixed = SemanticSection("Mixed", SemanticProse(source))
    @test md(mixed) == """
    ## Mixed

    ### Title

    Para with a [link](https://example.org) and \$x_1\$.

    #### Sub title on two lines\\

    > ### Quoted
    > text

    - item

      ### In list

    ```
    # not a heading
    ```

        # indented code
    """
    @test html_levels(html(mixed)) ==
        [2 => "Mixed", 3 => "Title", 4 => "Sub title on two lines\\", 3 => "Quoted", 3 => "In list"]
    # A `\\` ending an earlier line is a hard break, which one heading line cannot hold.
    @test md(SemanticSection("S", SemanticProse("Two\\\nlines\n---"))) == "## S\n\n### Two lines"
    @test repr("text/plain", SemanticProse(source)) == source

    # Prose with no heading, or with its headings already in place, is unchanged.
    for text in ("No *headings* here, only #hashtags and `#code`.\n\n- a\n- b",
                 "A rule, not a heading:\n\n---\n\nAfter.", "### Already\n\nText.")
        @test md(SemanticSection("S", SemanticProse(text))) == "## S\n\n" * text
    end
    @test md(SemanticProse("## Top\n\nText.")) == "## Top\n\nText."
    @test md(SemanticProse("# Money \$5\n\nCosts \$5 and \$10."; math=false)) == "## Money \$5\n\nCosts \$5 and \$10."
end

@testitem "a prose's headings are placed in a card, a static export and glossary-linked prose" setup=[ProseHeadingsFixture] tags=[:unit, :semantic] begin
    using HTMXObjects
    import HTMXObjects: h
    (; md, html, md_levels, html_levels) = ProseHeadingsFixture
    prose = SemanticProse("# Usage\n\nThe Registerzelle.\n\n## Detail\n\nMore.")

    # A card's Markdown title is a heading, its HTML title is not.
    card = SemanticSection("S", SemanticCard("Card", prose))
    @test md_levels(md(card)) == [2 => "S", 3 => "Card", 4 => "Usage", 5 => "Detail"]
    @test html_levels(html(card)) == [2 => "S", 3 => "Usage", 4 => "Detail"]

    # A static export builds the prose's peer where it renders.
    page = h.article(SemanticSection("A", SemanticSection("B", prose)))
    @test html_levels(repr("text/html", static_transform(page, StaticExport()))) ==
        [2 => "A", 3 => "B", 4 => "Usage", 5 => "Detail"]

    # Glossary linking renders the prose before it is placed; its peers place it.
    g = Glossary(["Registerzelle" => "Ein Bezirk × Abschnitt."]; href="/glossar", title="Glossar")
    linked = link_terms(SemanticSection("A", SemanticSection("B", prose)), g)
    @test occursin("class=\"htmxo-term\"", html(linked))
    @test html_levels(html(linked)) == [2 => "A", 3 => "B", 4 => "Usage", 5 => "Detail"]
    @test md_levels(md(linked)) == [2 => "A", 3 => "B", 4 => "Usage", 5 => "Detail"]
    @test occursin("The [Registerzelle](/glossar#term-registerzelle).", md(linked))
    @test occursin("\n# Usage\n", repr("text/plain", linked))
end

@testitem "pdf_report of a docstring's headings inside nested sections passes PDF/UA-1" setup=[ProseHeadingsFixture] tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        (; DOC, view) = ProseHeadingsFixture
        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        mktempdir() do dir
            out = joinpath(dir, "docstring.pdf")
            @test pdf_report(view(SemanticProse(DOC)), out; title="Prose headings", lang="en-GB") == out
            @test pdfua(out)
            # Top-level prose after a section, and a docstring that starts deeper.
            after = joinpath(dir, "after.pdf")
            @test pdf_report(SemanticGroup(SemanticSection("Intro", "Opening."),
                                           SemanticProse("## Notes\n\nA.\n\n# Appendix\n\nB.")),
                             after; title="After a section", lang="en-GB") == after
            @test pdfua(after)
        end
    end
end
