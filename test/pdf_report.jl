using TestItemRunner

@testitem "pdf_report front matter asks Quarto's Typst for PDF/UA-1" tags=[:unit] begin
    using HTMXObjects

    filter = HTMXObjects._PDFUA_MATH_ALT_FILTER
    images = HTMXObjects._PDF_REPORT_IMAGES_FILTER
    @test isfile(filter) && isfile(images)
    @test HTMXObjects._pdf_report_qmd("# Ergebnisse\n"; title="Bericht \"A\" \\ 2026", lang="de-DE") == """
        ---
        title: "Bericht \\"A\\" \\\\ 2026"
        lang: "de-DE"
        papersize: "a4"
        format:
          typst:
            pdf-standard: [ua-1]
        filters:
          - path: $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_QUOTES_FILTER))
            at: post-render
          - $(HTMXObjects._yaml_string(filter))
          - $(HTMXObjects._yaml_string(images))
        ---

        # Ergebnisse
        """
    @test isfile(HTMXObjects._PDF_REPORT_QUOTES_FILTER)
end

@testitem "pdf_report writes metadata into the front matter and picks the region's paper" tags=[:unit] begin
    using HTMXObjects, Dates

    qmd(lang; metadata=(;)) = HTMXObjects._pdf_report_qmd("# R\n"; title="R", lang, metadata)
    frontmatter(lang; metadata=(;)) = split(qmd(lang; metadata), "\n---\n")[1]

    @test occursin("""
        lang: "de-DE"
        papersize: "a4"
        subtitle: "Mietspiegel \\"2026\\""
        date: "2026-10-22"
        toc: true
        toc-depth: 2
        margin: {"x": "2cm", "y": "2cm"}
        fontsize: "10pt"
        author: ["A", "B"]
        columns: 1
        format:
        """, qmd("de-DE"; metadata=(subtitle="Mietspiegel \"2026\"", date=Date(2026, 10, 22), toc=true,
                                    toc_depth=2, margin=(x="2cm", y="2cm"), fontsize="10pt",
                                    author=["A", "B"], columns=1)))
    # Dictionary keys are written as given.
    @test occursin("\ntoc-title: \"Inhalt\"\n", qmd("de-DE"; metadata=Dict("toc-title" => "Inhalt")))

    # US Letter for the regions Unicode CLDR lists for it, A4 everywhere else.
    @test occursin("papersize: \"a4\"", frontmatter("en-GB"))
    @test occursin("papersize: \"a4\"", frontmatter("es-419"))
    @test occursin("papersize: \"us-letter\"", frontmatter("en-US"))
    @test occursin("papersize: \"us-letter\"", frontmatter("es-mx"))
    @test occursin("papersize: \"us-letter\"", frontmatter("fr-CA"))
    # An explicit papersize wins, written once.
    fm = frontmatter("de-DE"; metadata=(papersize="a5",))
    @test occursin("papersize: \"a5\"", fm) && count("papersize", fm) == 1
end

@testitem "pdf_report refuses metadata and Markdown that would override its own front matter" tags=[:unit] begin
    using HTMXObjects

    refusal(md="# R\n"; metadata=(;)) = try
        pdf_report(md, joinpath(tempdir(), "never.pdf"); title="R", lang="de-DE", metadata,
                   quarto="htmxo-no-such-quarto")
    catch e
        e
    end
    # refused: PDF/UA-1 needs pdf_report's title, language, ua-1 standard and equation alt text
    # (snag pdf-report-docum-5afe7187)
    for (metadata, says) in [(title="X",) => "title=", (lang="en-US",) => "lang=",
                             (pdf_standard=String[],) => "ua-1", Dict("format" => "html") => "ua-1",
                             (filters=["mine.lua"],) => "alt text"]
        err = refusal(; metadata)
        @test err isa ArgumentError && occursin(says, err.msg)
    end
    @test refusal(; metadata=Dict("not a key" => 1)) isa ArgumentError
    @test refusal(; metadata=Dict(:toc => true, "toc" => false)) isa ArgumentError
    @test refusal(; metadata=(fontsize=Inf,)) isa ArgumentError
    @test refusal(; metadata=(toc=1im,)) isa ArgumentError
    @test refusal(; metadata=["toc" => true]) isa ArgumentError

    # refused: Quarto merges a YAML block in the Markdown over the generated front
    # matter, so it would silently replace title and lang (snag pdf-report-docum-5afe7187)
    err = refusal("---\nlang: en-US\n---\n\n# R\n")
    @test err isa ArgumentError && occursin("YAML metadata block (line 1)", err.msg)
    @test refusal("# R\n\n---\nsubtitle: x\n...\n") isa ArgumentError
    # A thematic break, a table and a fenced example are not metadata blocks: these
    # get past the checks to the missing Quarto.
    for md in ["# R\n\n---\n\nText.\n", "| a | b |\n|---|---|\n| 1 | 2 |\n",
               "# R\n\n```yaml\n---\ntitle: x\n---\n```\n", "# R\n\n~~~~\n---\ntitle: x\n---\n~~~~\n"]
        passed = refusal(md)
        @test passed isa ErrorException && occursin("Quarto not found", passed.msg)
    end
end

@testitem "pdf_report checks its arguments before running Quarto" tags=[:unit] begin
    using HTMXObjects

    mktempdir() do dir
        out = joinpath(dir, "report.pdf")
        # refused: PDF/UA-1 requires a document title (ISO 14289-1 7.1)
        @test_throws ArgumentError pdf_report("# R", out; title=" ", lang="de-DE")
        # refused: Quarto's Typst template would label a region-less tag `de-US`
        err = try pdf_report("# R", out; title="R", lang="de") catch e e end
        @test err isa ArgumentError && occursin("region", err.msg)
        @test_throws ArgumentError pdf_report("# R", out; title="R", lang="de-DE",
                                              resources=joinpath(dir, "missing"))
        err = try
            pdf_report("# R", out; title="R", lang="de-DE", quarto="htmxo-no-such-quarto")
        catch e
            e
        end
        @test err isa ErrorException && occursin("Quarto not found", err.msg)
        @test readdir(dir) == []
    end
end

@testitem "pdf_report writes a PDF/UA-1 report through Quarto" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes) &&
                occursin("/StructTreeRoot", bytes)
        end
        mediabox(path) = match(r"/MediaBox\s*\[([^\]]*)\]", read(path, String)).captures[1]
        a4, letter = "0 0 595.2756 841.8898", "0 0 612 792"
        svg = """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10"/></svg>"""

        mktempdir() do dir
            write(joinpath(dir, "bars.svg"), svg)
            page = h.article(
                h.h1("Ergebnisse"),
                h.p("Details auf der ", h.a("Projektseite"; href="https://example.org"), "."),
                render_table((Kreis=["Aachen", "Köln"], Wert=[1.5, 2.25]);
                    caption=CaptionSpec(; title="Werte", short="Je Kreis."), id="werte"),
                h.p("Modell: \$y = a + b x\$."),
            )
            out = joinpath(dir, "out", "bericht.pdf")
            @test pdf_report(page, out; title="Bericht", lang="de-DE", resources=dir) == out
            @test pdfua(out)
            @test mediabox(out) == a4

            # Document options, and the paper each region uses unless one is given.
            opts = joinpath(dir, "out", "optionen.pdf")
            @test pdf_report("# A\n\nText.\n\n# B\n\nText.\n", opts; title="Bericht", lang="de-DE",
                             metadata=(subtitle="Entwurf", date="22.10.2026", toc=true,
                                       margin=(x="2cm", y="2cm"), fontsize="10pt")) == opts
            @test pdfua(opts) && mediabox(opts) == a4
            us = joinpath(dir, "out", "us.pdf")
            @test pdf_report("# R\n", us; title="R", lang="en-US") == us
            @test mediabox(us) == letter
            @test pdf_report("# R\n", us; title="R", lang="en-US", metadata=(papersize="a4",)) == us
            @test mediabox(us) == a4

            # An image with alt text, a German part and display math.
            md = """
                # Results

                ![](bars.svg){alt="Two bars of equal height."}

                ::: {lang="de"}
                Die Zusammenfassung auf Deutsch.
                :::

                \$\$\\sum_{i=1}^n x_i\$\$
                """
            @test pdf_report(md, joinpath(dir, "md.pdf"); title="Report", lang="en-GB") == joinpath(dir, "md.pdf")
            @test pdfua(joinpath(dir, "md.pdf"))
            # Only the inputs and the two reports remain: no .qmd, no .quarto cache.
            @test sort(readdir(dir)) == ["bars.svg", "md.pdf", "out"]

            # refused: PDF/UA-1 requires alt text on every image (ISO 14289-1 7.3);
            # Typst rejects the document, and pdf_report says why.
            err = try
                pdf_report("# R\n\n![](bars.svg)\n", joinpath(dir, "noalt.pdf"); title="R", lang="en-GB")
            catch e
                e
            end
            @test err isa ErrorException && occursin("missing alt text", err.msg)
            @test sort(readdir(dir)) == ["bars.svg", "md.pdf", "out"]

            # Typographic quotes read as written, in the text and the title;
            # straight ones become the quotes of `lang`. Pandoc's Typst writer
            # alone turned “ and ‘ into straight quotes, which Typst opened
            # anew: „Lieferflächen für Berlin„ and ‚einfache’.
            german = "Der Leitfaden „Lieferflächen für Berlin“ gilt. Ein \"gerades\" Paar und ‚einfache‘ Zeichen."
            write(joinpath(dir, "de.md"), german)
            typst = read(`$(Sys.which("quarto")) pandoc -f markdown -t typst
                          --lua-filter=$(HTMXObjects._PDF_REPORT_QUOTES_FILTER) $(joinpath(dir, "de.md"))`, String)
            @test occursin("„Lieferflächen für Berlin“", typst) && occursin("‚einfache‘", typst)
            @test occursin("\"gerades\"", typst)  # left to Typst's quotes for `lang`
            de = joinpath(dir, "de.pdf")
            @test pdf_report(h.article(h.p(german)), de; title="Bericht „Q“", lang="de-DE") == de
            @test pdfua(de)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                text = read(`pdftotext $de -`, String)
                @test occursin("Bericht „Q“", text)
                @test occursin("„Lieferflächen für Berlin“", text)
                @test occursin("„gerades“", text) && occursin("‚einfache‘", text)
            end
            rm(de); rm(joinpath(dir, "de.md"))

            # An `h.img` with alt text alone in its block: HTMX.jl writes the alt
            # as an attribute, `![](bars.svg){alt="…"}`, so Pandoc keeps it on the
            # image rather than reading `![alt](src)` as an implicit figure whose
            # image has none, and Typst accepts the PDF.
            img = with_caption(CaptionSpec(; title="Balken"),
                h.img(; src="bars.svg", alt="Two bars of equal height."); id="fig-bars")
            @test pdf_report(img, joinpath(dir, "img.pdf"); title="R", lang="en-GB") == joinpath(dir, "img.pdf")
            @test pdfua(joinpath(dir, "img.pdf"))

            # Images Typst cannot read from `resources` as written: an absolute
            # path (outside or inside it), a `file:` URL and a relative path that
            # leaves it. A site-root path names the file under `resources`.
            report = joinpath(dir, "bericht")
            mkpath(joinpath(report, "assets"))
            cp(joinpath(dir, "bars.svg"), joinpath(report, "assets", "bars.svg"))
            slash(path) = replace(path, '\\' => '/')  # Markdown reads `\` as an escape
            bars = slash(joinpath(dir, "bars.svg"))
            @testset "image $src" for src in (bars, "file://" * (startswith(bars, "/") ? "" : "/") * bars,
                    "../bars.svg", slash(joinpath(report, "assets", "bars.svg")), "/assets/bars.svg")
                out = joinpath(report, "bericht.pdf")
                @test pdf_report("# Bericht\n\n![]($src){alt=\"Zwei gleich hohe Balken.\"}\n", out;
                                 title="Bericht", lang="de-DE") == out
                @test pdfua(out)
                rm(out)
            end
            err = try
                pdf_report("# R\n\n![]($(slash(joinpath(dir, "fehlt.svg")))){alt=\"Balken.\"}\n",
                           joinpath(report, "r.pdf"); title="R", lang="de-DE")
            catch e
                e
            end
            @test err isa ErrorException && occursin("fehlt.svg", err.msg)
            @test readdir(report) == ["assets"]
        end
    end
end
