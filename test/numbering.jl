using TestItemRunner

# `numbered`, `contents` and `ref`: a page's sections, captioned figures and
# captioned tables carry the same numbers in its HTML, its Markdown and the
# `pdf_report` PDF made from that Markdown (snag page-toc-and-num-8d65e41f,
# reporter BayesianRegressionReports:pdf).

@testmodule NumberedFixture begin
    using HTMXObjects
    md(x; kw...) = HTMXObjects.to_markdown_string(x; kw...)
    html(x) = sprint(show, MIME"text/html"(), x)
    plain(x) = sprint(show, MIME"text/plain"(), x)
    # A small report: a contents list, nested sections, a figure, a table and refs.
    report() = numbered(
        contents(),
        SemanticSection("Results",
            h.p("See ", ref("fig-post"), ", ", ref("model"), " and ", ref("tbl-doses"), "."),
            with_caption(CaptionSpec(; title="Posterior", short="draws"), h.p("PLOT"); id="fig-post"),
            SemanticSection("Detail", h.p("x")),
            render_table((A=[1, 2], B=[3, 4]); caption="Doses", id="doses")),
        SemanticSection("Model", h.p("y"),
            SemanticSection("Priors", with_caption("Second", h.p("P2"))); anchor="model"))
    # The numbers a rendering shows, in reading order.
    headings(text) = [m.match for m in eachmatch(r"(?m)^#+ [0-9.]+ \w+", text)]
    html_headings(text) = [replace(m.match, r"<[^>]*>" => "") for m in eachmatch(
        r"<h[1-6]><span class=\"htmxo-section-number\">[0-9.]+</span> \w+", text)]
    captions(text) = [m.match for m in eachmatch(r"(Figure|Table|Abbildung|Tabelle) \d+:", text)]
end

@testitem "a numbered document numbers its sections the same in HTML, Markdown and plain text" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, html, plain, report, headings, html_headings

    m, x, p = md(report()), html(report()), plain(report())
    @test startswith(m, "<!-- htmxo:numbered -->\n\n")
    @test headings(m) == ["## 1 Results", "### 1.1 Detail", "## 2 Model", "### 2.1 Priors"]
    @test html_headings(x) == ["1 Results", "1.1 Detail", "2 Model", "2.1 Priors"]
    for line in ("1 Results", "1.1 Detail", "2 Model", "2.1 Priors")
        @test occursin("\n" * line * "\n", p)
    end

    # An anchored section keeps its id; any other gets one from its number,
    # in every form, so a contents list and a ref can link it.
    @test occursin("## 2 Model {#model}", m) && occursin("### 1.1 Detail {#section-1-1}", m)
    @test occursin("""<section class="htmxo-semantic-section" id="model"><h2><span class="htmxo-section-number">2</span> Model</h2>""", x)
    @test occursin("""id="section-1-1"><h3><span class="htmxo-section-number">1.1</span> Detail</h3>""", x)

    # A `level=1` section is the document's title: unnumbered, its sections count from 1.
    t = md(numbered(SemanticSection("Report", SemanticSection("A", "a"),
        SemanticSection("B", SemanticSection("B1", "b")); level=1)))
    @test occursin("# Report\n", t) && !occursin("# 1 Report", t)
    @test headings(t) == ["## 1 A", "## 2 B", "### 2.1 B1"]
    # `sections=false` leaves sections unnumbered and without generated ids.
    @test md(numbered(SemanticSection("A", "a"); sections=false)) == "<!-- htmxo:numbered -->\n\n## A\n\na"

    # Inside a node (as `pdf_report(h.article(…))` renders a report), the
    # Markdown is the same, and a link in one child still writes its target's
    # id in another.
    linked = numbered(SemanticSection("A", h.p(h.a("there"; href="#t"))), h.div(h.p("target"); id="t"))
    @test occursin(md(report()), md(h.article(report())))
    @test occursin("{#t}", md(linked)) && occursin("{#t}", md(h.article(linked)))
end

@testitem "captions in a numbered document start with their number" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, html, plain, report, captions

    m, x = md(report()), html(report())
    # Figures and tables count separately, straight through the document.
    @test captions(m) == captions(x) == ["Figure 1:", "Table 1:", "Figure 2:"]
    @test occursin("**Figure 1: Posterior** — draws", m) && occursin("**Table 1: Doses**", m)
    @test occursin("""<strong><span><span class="htmxo-caption-number">Figure 1:</span> </span>Posterior</strong>""", x)
    @test occursin("Figure 1: Posterior — draws", plain(report()))

    # A captioned figure inside another: HTML writes the outer caption first and
    # Markdown last, and both give the outer one the first number.
    inner = with_caption("Inner", h.div("i"); id="fig-inner")
    nested = numbered(with_caption("Outer", h.div(inner); id="fig-outer"), h.p(ref("fig-inner")))
    @test captions(md(nested)) == ["Figure 2:", "Figure 1:"]
    @test captions(html(nested)) == ["Figure 1:", "Figure 2:"]
    @test occursin("[Figure 2](#fig-inner)", md(nested))

    # A caption without a title shows its number in bold by itself before the summary.
    untitled = numbered(with_caption(CaptionSpec(; title="", short="Only a summary"), "c"),
                        with_caption(CaptionSpec(; title="  ", short="", long="Long text."), "d"))
    @test occursin("**Figure 1:** Only a summary", md(untitled))
    @test occursin("**Figure 2:** Long text.", md(untitled))
    @test occursin("""<strong><span class="htmxo-caption-number">Figure 1:</span></strong> </span>Only a summary""", html(untitled))

    # `kind` and the document's switches.
    @test captions(md(numbered(with_caption("T", "c"; kind=:table), with_caption("N", "c"; kind=nothing)))) == ["Table 1:"]
    unreferenced = (with_caption("F1", "a"), render_table((A=[1],); caption="T1"), with_caption("F2", "b"))
    @test captions(md(numbered(unreferenced...; figures=false))) == ["Table 1:"]
    @test captions(md(numbered(unreferenced...; tables=false))) == ["Figure 1:", "Figure 2:"]
    # A ref to an element whose kind is not numbered has nothing to cite.
    @test_throws ArgumentError md(numbered(report().children...; figures=false))
    @test_throws ArgumentError with_caption("T", "c"; kind=:listing)

    # Content built anew for each render (a function's private content) is
    # numbered by its place in the HTML.
    built = numbered(with_caption("A", "a"), private(() -> with_caption("B", "b")), with_caption("C", "c"))
    @test HTMXObjects._with_audience(() -> captions(html(built)), :private) == ["Figure 1:", "Figure 2:", "Figure 3:"]
end

@testitem "contents lists the numbered sections and ref cites them" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, html, plain, report

    m, x = md(report()), html(report())
    @test occursin("""
        ::: {.htmxo-contents title="Contents" depth="3"}
        **Contents**

        - [1 Results](#section-1)
            - [1.1 Detail](#section-1-1)
        - [2 Model](#model)
            - [2.1 Priors](#section-2-1)

        :::""", m)
    @test occursin("""<nav class="htmxo-contents" aria-label="Contents"><p class="htmxo-contents-title">Contents</p><ol><li><a href="#section-1"><span class="htmxo-section-number">1</span> <span>Results</span></a><ol><li><a href="#section-1-1">""", x)
    @test occursin("Contents\n1 Results\n  1.1 Detail\n2 Model\n  2.1 Priors", plain(report()))
    # `depth` keeps the list to the top levels; the PDF's outline depth follows.
    shallow = md(numbered(contents(; depth=1), report().children[2:end]...))
    @test occursin("depth=\"2\"", shallow) && occursin("- [2 Model](#model)\n\n:::", shallow) &&
        !occursin("1.1 Detail](", shallow)
    @test_throws ArgumentError contents(; depth=0)

    # ref reads as the element's number, linking it, in every form.
    @test occursin("See [Figure 1](#fig-post), [Section 2](#model) and [Table 1](#tbl-doses).", m)
    @test occursin("""See <a href="#fig-post" class="htmxo-ref">Figure 1</a>, <a href="#model" class="htmxo-ref">Section 2</a>""", x)
    @test occursin("See Figure 1, Section 2 and Table 1.", plain(report()))
    # A ref may come before what it cites (the numbers are given first).
    @test occursin("[Section 2](#later)", md(numbered(h.p(ref("later")), SemanticSection("A", "a"), SemanticSection("B", "b"; anchor="later"))))
    # A ref to nothing numbered, and a ref or contents list outside a numbered document, throw.
    err = try md(numbered(SemanticSection("A", "a"), h.p(ref("nope")))); nothing catch e; e end
    @test err isa ArgumentError && occursin("\"nope\"", err.msg) && occursin("section-1", err.msg)
    @test_throws ArgumentError md(h.p(ref("x")))
    @test_throws ArgumentError md(contents())
    @test_throws ArgumentError ref("")
end

@testitem "numbers count what the reader and both forms show" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, html, headings, html_headings

    # A public reader's numbers leave the private section out, without a gap.
    doc = numbered(SemanticSection("A", "a"), private(SemanticSection("Secret", "s")), SemanticSection("C", "c"))
    @test headings(md(doc; audience=:public)) == ["## 1 A", "## 2 C"]
    @test HTMXObjects._with_audience(() -> html_headings(html(doc)), :public) == ["1 A", "2 C"]
    @test HTMXObjects._with_audience(() -> html_headings(html(doc)), :private) == ["1 A", "2 Secret", "3 C"]

    # What only HTML shows (`html_only`, an alternative's later views) takes no number.
    both = numbered(SemanticSection("A", "a"), html_only(SemanticSection("Web", "w")),
        SemanticAlternatives(SemanticSection("Main", "m"), "Other" => SemanticSection("Alt", "o")),
        SemanticSection("Z", "z"))
    @test headings(md(both)) == ["## 1 A", "## 2 Main", "## 3 Z"]
    @test html_headings(html(both)) == ["1 A", "2 Main", "3 Z"]
    @test occursin("<h2>Web</h2>", html(both)) && occursin("<h2>Alt</h2>", html(both))

    # An eager tabset's sections take the same numbers in the page and its Markdown.
    tabs = numbered(tabset("One" => SemanticSection("In one", with_caption("C1", "x")),
                           "Two" => SemanticSection("In two", "y")), SemanticSection("After", "z"))
    @test headings(md(tabs)) == ["## 1 In", "## 2 In", "## 3 After"]
    @test html_headings(html(tabs)) == ["1 In", "2 In", "3 After"]
    @test occursin("**Figure 1: C1**", md(tabs)) && occursin(">Figure 1:</span>", html(tabs))

    # A static export carries the numbers.
    exported = sprint(show, MIME"text/html"(), static_transform(NumberedFixture.report()))
    @test html_headings(exported) == ["1 Results", "1.1 Detail", "2 Model", "2.1 Priors"]
    @test occursin("""<a href="#fig-post" class="htmxo-ref">Figure 1</a>""", exported) &&
        occursin("""<nav class="htmxo-contents" aria-label="Contents">""", exported)
end

@testitem "a section keeps its number however often HTMX writes it" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, html, headings, html_headings

    # A ref to a captioned figure inside a section is a link HTMX finds only in
    # the section's own output, so HTMX writes the document's Markdown a second
    # time (snag numbered-semanti-14da03de). Each section keeps its number, and
    # an unanchored one its generated id, which a ref can cite.
    doc = numbered(contents(),
        SemanticSection("Results", h.p("See ", ref("model"), ", ", ref("section-2-1"), " and ", ref("fig-x"), "."),
            with_caption(CaptionSpec(; title="A picture", short="Short."), h.p("FIGBODY"); id="fig-x")),
        SemanticSection("Model", SemanticSection("Priors", h.p("pri")); anchor="model"))
    m = md(doc; lang="en-GB")
    @test occursin("\n## 1 Results {#section-1}\n", m) && occursin("\n## 2 Model {#model}\n", m) &&
        occursin("\n### 2.1 Priors {#section-2-1}\n", m)
    @test occursin("See [Section 2](#model), [Section 2.1](#section-2-1) and [Figure 1](#fig-x).", m)
    @test md(doc; lang="en-GB", report=true) == m

    # One section placed twice takes its next number each time, in both forms.
    again = SemanticSection("Again", "x")
    twice = numbered(again, SemanticSection("Mid", h.p(ref("fig")), with_caption("F", "f"; id="fig")), again)
    @test headings(md(twice)) == ["## 1 Again", "## 2 Mid", "## 3 Again"]
    @test html_headings(html(twice)) == ["1 Again", "2 Mid", "3 Again"]

    # A section in a <header>, whose layout HTMX probes before writing it.
    top = md(numbered(h.header(SemanticSection("Top", "t")), SemanticSection("Next", "n")))
    @test occursin("1 Top {#section-1}", top) && occursin("\n## 2 Next {#section-2}\n", top)

    # Content built anew for each render (a function's private content), first
    # in a document HTMX writes twice.
    built = numbered(private(() -> SemanticSection("Built", h.p(ref("fig-b")))),
                     SemanticSection("Next", with_caption("F", "f"; id="fig-b")))
    @test headings(md(built; audience=:private)) == ["## 1 Built", "## 2 Next"]
    @test headings(md(built; audience=:public)) == ["## 1 Next"]
end

@testitem "outside a numbered document sections and captions render as before" tags=[:unit, :semantic] begin
    using HTMXObjects
    md(x) = HTMXObjects.to_markdown_string(x)
    html(x) = sprint(show, MIME"text/html"(), x)
    @test md(SemanticSection("Eins", "Text")) == "## Eins\n\nText"
    @test html(SemanticSection("Eins", "Text")) == """<section class="htmxo-semantic-section"><h2>Eins</h2>Text</section>"""
    @test html(with_caption("T", "c")) == """<figure class="captioned"><figcaption class="caption"><div class="caption-header"><span><strong>T</strong></span></div></figcaption>c</figure>"""
    @test md(with_caption("T", "c")) == md(h.figure(h.figcaption(h.strong("T")), "c"))
    @test HTMXObjects._plain_string(with_caption("T", "c")) == HTMXObjects._plain_string(with_caption("T", "c"; kind=nothing))
    # `html_only` content renders as an element's child does: plain text is
    # escaped, also as an alternative's later view (which is HTML's alone).
    @test html(h.div(html_only("a<b"))) == "<div>a&lt;b</div>"
    @test occursin("<summary>preview</summary>rendered &amp; out</details>",
        html(SemanticAlternatives("src", "preview" => "rendered & out")))
    # Outside a numbered document an untitled caption renders as without a number slot.
    for spec in (CaptionSpec(; title="", short="S"), CaptionSpec(; title="", short="", long="L"))
        @test html(with_caption(spec, "c")) == html(with_caption(spec, "c"; kind=nothing))
        @test md(with_caption(spec, "c")) == md(with_caption(spec, "c"; kind=nothing))
        @test HTMXObjects._tabset_default_id(["A" => with_caption(spec, "c")]) ==
            HTMXObjects._tabset_default_id(["A" => with_caption(spec, "c"; kind=nothing)])
    end
    # A caption's number slot changes no tabset's default id: the id is the
    # one a caption without a slot gives, as before numbers existed.
    @test HTMXObjects._tabset_default_id(["A" => with_caption("T", "c")]) ==
        HTMXObjects._tabset_default_id(["A" => with_caption("T", "c"; kind=nothing)]) ==
        HTMXObjects._tabset_default_id(["A" => h.figure(h.figcaption(h.div(h.span(h.strong("T"), "", ""); class="caption-header"); class="caption"), "c"; class="captioned")])
end

@testitem "numbering words follow the page's language or texts=" tags=[:unit, :semantic] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, report, captions

    de = md(report(); lang="de-DE")
    @test captions(de) == ["Abbildung 1:", "Tabelle 1:", "Abbildung 2:"]
    @test occursin("See [Abbildung 1](#fig-post), [Abschnitt 2](#model) and [Tabelle 1](#tbl-doses).", de)
    @test occursin("title=\"Inhalt\"", de) && occursin("**Inhalt**", de)
    own = md(numbered(report().children...; texts=numbering_texts(:de; figure="Abb. {number}")))
    @test captions(own) == ["Tabelle 1:"] && occursin("**Abb. 1: Posterior**", own)
    @test numbering_texts(:en).figure == "Figure {number}"
    @test_throws ArgumentError numbering_texts(:fr)
    @test_throws ArgumentError numbering_texts(:en; figure="Fig. {n}")
    @test_throws ArgumentError numbering_texts(:en; legend="x")
end

@testitem "pdf_report switches Quarto's numbers off for a numbered document" tags=[:unit] setup=[NumberedFixture] begin
    using HTMXObjects
    using .NumberedFixture: md, report

    qmd(markdown; kw...) = HTMXObjects._pdf_report_qmd(markdown; title="T", lang="en-GB", kw...)
    y(path) = HTMXObjects._yaml_string(path)
    numbered_typst, contents_filter = HTMXObjects._PDF_REPORT_NUMBERED_TYPST, HTMXObjects._PDF_REPORT_CONTENTS_FILTER
    @test isfile(numbered_typst) && isfile(contents_filter)
    doc = qmd(md(report()))
    @test occursin("include-in-header: [$(y(HTMXObjects._PDF_REPORT_TABLES_TYPST)), $(y(HTMXObjects._PDF_REPORT_CODE_TYPST)), $(y(numbered_typst))]", doc)
    @test occursin("  - $(y(contents_filter))\n---\n", doc)
    # Without numbers or a contents list, nothing changes.
    plain_doc = qmd("# A\n\nText.\n")
    @test !occursin(y(numbered_typst), plain_doc) && !occursin(y(contents_filter), plain_doc)
    # The marker inside fenced code is text, not a numbered document.
    @test !occursin(y(numbered_typst), qmd("```\n<!-- htmxo:numbered -->\n```\n"))
    # Quarto's own numbering or contents list would print everything twice.
    @test_throws ArgumentError qmd(md(report()); metadata=(number_sections=true,))
    @test_throws ArgumentError qmd(md(report()); metadata=(toc=true,))
    @test occursin("toc: false", qmd(md(report()); metadata=(toc=false, number_sections=false)))
    # A numbered document without contents() keeps Quarto's toc available.
    @test occursin("toc: true", qmd(md(numbered(SemanticSection("A", "a"))); metadata=(toc=true,)))
end

@testitem "pdf_report prints each number once, with a contents list" tags=[:quarto] setup=[NumberedFixture] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1" || isnothing(Sys.which("pdftotext"))
        @test_skip true
    else
        using HTMXObjects
        using .NumberedFixture: report

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        text(path) = read(`pdftotext -enc UTF-8 -layout $path -`, String)
        mktempdir() do dir
            out = joinpath(dir, "report.pdf")
            @test pdf_report(h.article(report()), out; title="Numbered", lang="en-GB") == out
            @test pdfua(out)
            t = text(out)
            # Each number once: Quarto's and Typst's own are off.
            @test count("Figure 1:", t) == 1 && count("Table 1:", t) == 1 && count("Figure 2:", t) == 1
            @test !occursin(r"Figure 1: *Figure", t) && !occursin(r"\b1 1 Results", t)
            # The contents list is Typst's outline: the numbered headings with page numbers.
            @test occursin("Contents", t)
            @test occursin(r"1 Results[ .]+\S*1\n", t) && occursin(r"2\.1 Priors[ .]+\S*1\n", t)
            # The refs are links inside the document.
            @test occursin("See Figure 1, Section 2 and Table 1.", t)
            @test count(r"/Subtype\s*/Link", read(out, String)) >= 3

            de = joinpath(dir, "bericht.pdf")
            pdf_report(h.article(report()), de; title="Bericht", lang="de-DE")
            td = text(de)
            @test occursin("Inhalt", td) && count("Abbildung 1:", td) == 1 && count("Tabelle 1:", td) == 1
        end
    end
end
