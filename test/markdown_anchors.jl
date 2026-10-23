using TestItemRunner

@testitem "semantic anchors are Pandoc identifiers in markdown" tags=[:unit, :semantic] begin
    using HTMXObjects
    md(x) = HTMXObjects.to_markdown_string(x)

    # A section or card carries its anchor on its title heading.
    @test md(SemanticSection("Eins", SemanticProse("Text"); anchor="a1")) == "## Eins {#a1}\n\nText"
    @test md(SemanticCard("Karte", "Inhalt"; anchor="c1")) == "### Karte {#c1}\n\nInhalt"
    @test md(SemanticSection("Leer"; anchor="a1")) == "## Leer {#a1}"
    # A code block has no heading, so a fenced div carries it.
    @test md(SemanticCode(:julia, "x = 1"; anchor="k1")) == "::: {#k1}\n```julia\nx = 1\n```\n:::"
    # Outside the `#id` shorthand's characters, the key-value form.
    @test md(SemanticSection("S", "y"; anchor="abschnitt-ä.1:x_y")) == "## S {#abschnitt-ä.1:x_y}\n\ny"
    @test md(SemanticSection("S", "y"; anchor="a/b")) == "## S {id=\"a/b\"}\n\ny"
    @test md(SemanticSection("S", "y"; anchor="a\"b\\c")) == "## S {id=\"a\\\"b\\\\c\"}\n\ny"
    # A nested section or card keeps its anchor at its own heading level.
    @test md(SemanticSection("A", SemanticSection("B", SemanticCard("C", "x"; anchor="c1");
        anchor="b1"); anchor="a1")) == "## A {#a1}\n\n### B {#b1}\n\n#### C {#c1}\n\nx"

    # Unaddressed elements are unchanged.
    @test md(SemanticSection("Eins", "Text")) == "## Eins\n\nText"
    @test md(SemanticCard("Karte", "Inhalt")) == "### Karte\n\nInhalt"
    @test md(SemanticCode(:julia, "x = 1")) == "```julia\nx = 1\n```"

    # Among siblings, a wrapped code block stays its own block.
    @test md(h.div("Siehe", SemanticCode(:julia, "x = 1"; anchor="k1"), "oben.")) ==
        "Siehe\n\n::: {#k1}\n```julia\nx = 1\n```\n:::\n\noben."
end

@testitem "pdf_report resolves links to semantic anchors" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        link_annotations(path) = count(r"/Subtype\s*/Link", read(path, String))

        mktempdir() do dir
            report = h.article(
                h.p(SemanticLink("Abschnitt", "#a1"), ", ", SemanticLink("Karte", "#c1"), ", ",
                    SemanticLink("Code", "#k1"), ", ", SemanticLink("Pfad", "#t/0")),
                sortable_table(["Abschnitt"], [h.tr(h.td(h.a("Eins"; href="#a1")))]),
                SemanticSection("Eins", SemanticProse("Text"),
                    SemanticCard("Karte", "Inhalt"; anchor="c1"),
                    SemanticCode(:julia, "x = 1"; anchor="k1"); anchor="a1"),
                SemanticSection("Pfad", "y"; anchor="t/0"))
            out = joinpath(dir, "bericht.pdf")
            @test pdf_report(report, out; title="Bericht", lang="de-DE") == out
            @test pdfua(out)
            @test link_annotations(out) == 5
            @test readdir(dir) == ["bericht.pdf"]
        end
    end
end
