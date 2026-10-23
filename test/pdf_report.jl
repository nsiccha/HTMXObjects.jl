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
        format:
          typst:
            pdf-standard: [ua-1]
        filters:
          - $(HTMXObjects._yaml_string(filter))
          - $(HTMXObjects._yaml_string(images))
        ---

        # Ergebnisse
        """
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

            # An `h.img` with alt text alone in its block: HTMX.jl writes it as
            # `![alt](src)`, which Pandoc reads as a figure whose caption is the
            # alt text and whose image has none, so Typst refuses the PDF. Flip
            # to `@test` once HTMX.jl writes the alt as an attribute.
            @test_broken try
                pdf_report(with_caption(CaptionSpec(; title="Balken"),
                        h.img(; src="bars.svg", alt="Two bars of equal height."); id="fig-bars"),
                    joinpath(dir, "img.pdf"); title="R", lang="en-GB")
                pdfua(joinpath(dir, "img.pdf"))
            catch
                false
            end

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
