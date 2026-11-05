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
            from: markdown+autolink_bare_uris+tex_math_single_backslash-raw_tex
            pdf-standard: [ua-1]
            syntax-highlighting: idiomatic
            include-in-header: [$(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_TABLES_TYPST)), $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_CODE_TYPST))]
        filters:
          - path: $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_QUOTES_FILTER))
            at: post-render
          - path: $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_FIGURES_FILTER))
            at: post-render
          - path: $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_LABELS_FILTER))
            at: post-render
          - $(HTMXObjects._yaml_string(filter))
          - $(HTMXObjects._yaml_string(images))
          - $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_DATE_FILTER))
          - $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_LINKS_FILTER))
          - $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_BREAKS_FILTER))
        ---

        # Ergebnisse
        """
    @test isfile(HTMXObjects._PDF_REPORT_QUOTES_FILTER) && isfile(HTMXObjects._PDF_REPORT_TABLES_TYPST) &&
          isfile(HTMXObjects._PDF_REPORT_CODE_TYPST) && isfile(HTMXObjects._PDF_REPORT_LABELS_FILTER) &&
          isfile(HTMXObjects._PDF_REPORT_DATE_FILTER) && isfile(HTMXObjects._PDF_REPORT_LINKS_FILTER) &&
          isfile(HTMXObjects._PDF_REPORT_FIGURES_FILTER) && isfile(HTMXObjects._PDF_REPORT_BREAKS_FILTER)
end

@testitem "pdf_report hands base_url to the link filter" tags=[:unit] begin
    using HTMXObjects

    key = HTMXObjects._PDF_REPORT_BASE_URL_KEY
    frontmatter(; kw...) =
        split(HTMXObjects._pdf_report_qmd("# R\n"; title="R", lang="de-DE", kw...), "\n---\n")[1]
    @test !occursin(key, frontmatter())
    # The address the Markdown's `/` stands for, without its trailing `/`,
    # escaped so that Pandoc keeps it as text.
    for base in ("https://example.org/p/App", "https://example.org/p/App/")
        @test occursin("\nlang: \"de-DE\"\n$key: " *
                       HTMXObjects._yaml_string("https\\:\\/\\/example\\.org\\/p\\/App") * "\n",
                       frontmatter(; base_url=base))
    end
    @test occursin("\n$key: ", frontmatter(; base_url="http://localhost:8080"))

    refusal(; kw...) = try
        pdf_report("# R\n", joinpath(tempdir(), "never.pdf"); title="R", lang="de-DE",
                   quarto="htmxo-no-such-quarto", kw...)
    catch e
        e
    end
    # refused: a `/` path joins onto an absolute address; without a scheme and
    # host, or with a query or fragment, the joined link would open nothing
    for base in ("example.org/app", "/p/App", "https://", "https://example.org/a b",
                 "https://example.org/app?x=1", "https://example.org/app#top")
        err = refusal(; base_url=base)
        @test err isa ArgumentError && occursin("base_url", err.msg)
    end
    # refused: the key is pdf_report's own; the address goes in as `base_url=`
    err = refusal(; metadata=Dict(key => "https://example.org"))
    @test err isa ArgumentError && occursin("base_url=", err.msg)
    passed = refusal(; base_url="https://example.org/app")
    @test passed isa ErrorException && occursin("Quarto not found", passed.msg)
end

@testitem "pdf_report hands url_map's answers to the link filter" tags=[:unit] begin
    using HTMXObjects

    key = HTMXObjects._PDF_REPORT_URL_MAP_KEY
    frontmatter(; kw...) =
        split(HTMXObjects._pdf_report_qmd("# R\n"; title="R", lang="de-DE", kw...), "\n---\n")[1]
    @test !occursin(key, frontmatter())
    # A target is written as given (Pandoc reads a metadata key as text), its URL
    # escaped so that Pandoc keeps it as text, and "" leaves the link to the
    # filter's own rules.
    @test occursin("\nlang: \"de-DE\"\n$key:\n" *
                   "  \"/api/v1/x?p=0.9\": " * HTMXObjects._yaml_string("https\\:\\/\\/example\\.org\\/x\\.json") * "\n" *
                   "  \"#oben\": \"\"\n",
                   frontmatter(; urls=["/api/v1/x?p=0.9" => "https://example.org/x.json", "#oben" => ""]))
    # A report without links still says that a url_map was given.
    @test occursin("\n$key: {}\n", frontmatter(; urls=Pair{String,String}[]))

    answer(url) = HTMXObjects._pdf_report_mapped_url(url, "/api/x")
    @test answer(nothing) == ""
    @test answer("https://example.org/odl/api-x.json") == "https://example.org/odl/api-x.json"
    @test answer(SubString("mailto:info@example.org", 1)) == "mailto:info@example.org"
    # refused: a PDF opens only an absolute URL; a relative target (StaticExport's
    # bundle file, say) would point at a file next to the PDF
    for url in ("api-x.json", "/odl/api-x.json", "C:x", "https://example.org/a b", "")
        err = try answer(url) catch e e end
        @test err isa ArgumentError && occursin("absolute URL", err.msg) && occursin("/api/x", err.msg)
    end
    # refused: an answer is a URL or nothing, as StaticExport's url_map
    err = try answer(:x) catch e e end
    @test err isa ArgumentError && occursin("String or nothing", err.msg)

    # refused: the key is pdf_report's own; the function goes in as `url_map=`
    err = try
        pdf_report("# R\n", joinpath(tempdir(), "never.pdf"); title="R", lang="de-DE",
                   quarto="htmxo-no-such-quarto", metadata=Dict(key => "x"))
    catch e
        e
    end
    @test err isa ArgumentError && occursin("url_map=", err.msg)
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

@testitem "pdf_report keeps a date Quarto reads and prints any other date text as written" tags=[:unit] begin
    using HTMXObjects, Dates

    frontmatter(metadata) =
        split(HTMXObjects._pdf_report_qmd("# R\n"; title="R", lang="de-DE", metadata), "\n---\n")[1]
    text = HTMXObjects._PDF_REPORT_DATE_TEXT_KEY

    # A date Quarto reads correctly stays `date`, for `date_format` to format.
    for date in (Date(2026, 10, 22), DateTime(2026, 10, 22, 10, 30), "2026-10-22", "2026-10-22 10:30",
                 "2026-10-22T10:30:00.5+02:00", "today", :now, "last-modified")
        fm = frontmatter((date=date, date_format="long"))
        @test occursin("\ndate: \"$date\"\n", fm) && occursin("\ndate-format: \"long\"\n", fm)
        @test !occursin(text, fm)
    end
    # Quarto would misread any other text ("22.10.2026" as Invalid Date,
    # "05.10.2026" as 10 May), so it goes under the key the date filter prints
    # as written, its Markdown punctuation escaped so Pandoc keeps the text.
    @test occursin("\n$text: $(HTMXObjects._yaml_string("05\\.10\\.2026"))\n", frontmatter((date="05.10.2026",)))
    fm = frontmatter(Dict("date" => "1. Oktober *2026*", "subtitle" => "S"))
    @test occursin("\n$text: $(HTMXObjects._yaml_string("1\\. Oktober \\*2026\\*"))\n", fm)
    @test !occursin("\ndate:", fm) && occursin("\nsubtitle: \"S\"\n", fm)
    for date in ("22.10.2026", "Oktober 2026", "2026-10", "2026-1-5", "10/22/2026", :heute)
        @test occursin("\n$text: ", frontmatter((date=date,)))
    end
    # A date given as Quarto's object form is Quarto's to read.
    @test occursin("\ndate: {\"value\": \"2026-10-22\", \"format\": \"long\"}\n",
                   frontmatter((date=(value="2026-10-22", format="long"),)))

    # refused: `date_format` cannot format text, which prints as written
    # (snag pdf-report-metad-89ac6032, user design decision 1dnvswg)
    err = try frontmatter((date="22.10.2026", date_format="DD.MM.YYYY")) catch e e end
    @test err isa ArgumentError && occursin("date_format", err.msg) && occursin("\"22.10.2026\"", err.msg)
    # refused: the date text key is pdf_report's own; text goes in as `date=`
    err = try frontmatter(Dict(text => "x")) catch e e end
    @test err isa ArgumentError && occursin("date=", err.msg)
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
    # (snag pdf-report-docum-5afe7187), and PAC its reader that links addresses (snag
    # ran-pac-2026-26-7da3df82)
    for (metadata, says) in [(title="X",) => "title=", (lang="en-US",) => "lang=",
                             (pdf_standard=String[],) => "ua-1", Dict("format" => "html") => "ua-1",
                             (filters=["mine.lua"],) => "alt text", (from="markdown",) => "PAC",
                             # a Quarto theme tags each token of a code block as its own Code
                             # element (snag review-the-brm-m-68c151e1)
                             (syntax_highlighting="github",) => "Code element",
                             Dict("highlight-style" => "arrow") => "Code element"]
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
        using HTMXObjects, Dates

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

            # The date filter hands Typst the date as a string: written as
            # markup, `[22. Oktober 2026]` is a numbered list in Typst.
            template = joinpath(dir, "date.template")
            write(template, "\$date\$\n")
            typst_date(key, value) = (write(joinpath(dir, "date.md"), "---\n$key: $(HTMXObjects._yaml_string(value))\n---\n");
                strip(read(`$(Sys.which("quarto")) pandoc -s -f markdown -t typst --template=$template
                            --lua-filter=$(HTMXObjects._PDF_REPORT_DATE_FILTER) $(joinpath(dir, "date.md"))`, String)))
            @test typst_date("date", "22. Oktober 2026") == "#\"22. Oktober 2026\""
            @test typst_date(HTMXObjects._PDF_REPORT_DATE_TEXT_KEY,
                             HTMXObjects._markdown_literal("1. Oktober \"*2026*\" \\ #a")) ==
                  "#\"1. Oktober \\\"*2026*\\\" \\\\ #a\""
            rm(template); rm(joinpath(dir, "date.md"))
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                # Quarto alone printed "Invalid Date" for 22.10.2026 and 2026-05-10
                # for 05.10.2026 (snag pdf-report-metad-89ac6032).
                @test occursin("22.10.2026", read(`pdftotext -enc UTF-8 $opts -`, String))
                for (date, shown) in [(date="05.10.2026",) => "05.10.2026",
                                      (date="1. Oktober 2026",) => "1. Oktober 2026",
                                      (date=Date(2026, 10, 5), date_format="long") => "5. Oktober 2026",
                                      (date="2026-10-05", date_format="DD.MM.YYYY") => "05.10.2026"]
                    dated = joinpath(dir, "out", "datum.pdf")
                    @test pdf_report("# R\n", dated; title="R", lang="de-DE", metadata=date) == dated
                    @test pdfua(dated) && occursin(shown, read(`pdftotext -enc UTF-8 $dated -`, String))
                    rm(dated)
                end
            end
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
                # pdftotext's default encoding is Latin-1 on Windows, which
                # writes „ as ,, and “ as ".
                text = read(`pdftotext -enc UTF-8 $de -`, String)
                @test occursin("Bericht „Q“", text)
                @test occursin("„Lieferflächen für Berlin“", text)
                @test occursin("„gerades“", text) && occursin("‚einfache‘", text)
            end
            rm(de); rm(joinpath(dir, "de.md"))

            # Table cells are set ragged-right and hyphenate only a word wider
            # than its column; the body stays justified and hyphenated. Quarto's
            # template justified the cells too, so Typst split words that fit
            # on the next line: Me-dian, Verhält-nis.
            tables = """
                Der Fließtext bleibt im Blocksatz und wird wie bisher getrennt, damit die Zeilen gleichmäßig lang sind und der Bericht ordentlich aussieht. Hier steht ein langer Satz mit Verhältniswahrscheinlichkeiten und Messstellenvergleichen.

                | Studienarm | Methode | Bayes: Verhältnis zur Referenz [95 %] | Klassisch: Median Verhältnis | Klassisch: Bland–Altman-Mittel |
                |---|---|---|---|---|
                | Kreatinin | Bland–Altman nach Grubbs-Ausschluss | 0,986 [0,946; 1,02] | 0,991 | 0,987 |

                | Methode | n | Median Verhältnis | Bland–Altman (95-%-Grenzen) | Passing–Bablok Steigung | Anteil Ausreißer bzw. kontaminiert | Prädiktive 95-%-Grenzen |
                |---|---|---|---|---|---|---|
                | Kontaminationswahrscheinlichkeit | 48 | 0,986 | 0,987 (0,912 bis 1,07) | Messstellenvergleich | 4 % [1 %; 9 %] | `verylongidentifiername` |
                """
            tab = joinpath(dir, "tabellen.pdf")
            @test pdf_report(tables, tab; title="Methodenvergleich", lang="de-DE") == tab
            @test pdfua(tab)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                # Typst's hyphenation shows as a soft hyphen in the text layer.
                # -layout keeps one at a line end: xpdf's pdftotext (the one on
                # the Windows runner) otherwise joins the word it split.
                text = read(`pdftotext -enc UTF-8 -layout $tab -`, String)
                @test occursin("Verhältniswahr\u00ad", text)
                cells = text[findfirst("Studienarm", text).start:end]
                pieces = [m[1] for m in eachmatch(r"(\p{L}+)\u00ad", cells)]
                @test "Kontami" in pieces && "kon" in pieces
                too_wide = "Kontaminationswahrscheinlichkeit kontaminiert Messstellenvergleich"
                @test all(p -> occursin(p, too_wide), pieces)
                @test occursin("verylongidentifiername", cells)
            end
            rm(tab)

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

@testitem "pdf_report links addresses and tags a lone image as a figure of its own" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        # PAC (PDF Accessibility Checker) fails an address shown as text without a
        # link and warns about a Figure inside a P, where veraPDF passes both: the
        # data-source URLs and the maps of a veraPDF-clean report (snag
        # ran-pac-2026-26-7da3df82). Typst writes the structure tree and the link
        # annotations uncompressed, `N 0 obj <</Type/StructElem/S/<type>…`.
        figure_parents(bytes) = sort([match(Regex("(?m)^$(m[1]) 0 obj\\s*<</Type/StructElem/S/(\\w+)"), bytes).captures[1]
                                      for m in eachmatch(r"/Type/StructElem/S/Figure/P (\d+) 0 R", bytes)])
        uris(bytes) = sort(unique(m[1] for m in eachmatch(r"/URI\(([^)]*)\)", bytes)))

        mktempdir() do dir
            write(joinpath(dir, "bars.svg"),
                  """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10"/></svg>""")
            md = """
                # Quellen

                Daten: https://www.regionalstatistik.de/genesis/online. Kontakt info@example.de oder www.example.de, auch (www.example.org/karte).

                Kein Link: awww.example.de und `curl https://example.org/api`. Ein Link: `https://example.org/code`.

                | Quelle | Lizenz |
                |---|---|
                | BKG | dl-de/by-2-0 (© BKG, Datenquellen: https://sg.geodatenzentrum.de/web_public/gdz/datenquellen/Datenquellen_vg_nuts.pdf) |

                ![](bars.svg){alt="Zwei gleich hohe Balken."}

                Ein Symbol ![](bars.svg){alt="Balken" width="0.5cm"} im Text.

                ![Balken je Land](bars.svg){alt="Zwei Balken je Land."}

                """ * HTMXObjects.to_markdown_string(with_caption(CaptionSpec(; title="Balken je Kreis"),
                                                                 h.img(; src="bars.svg", alt="Zwei Balken.")))
            out = joinpath(dir, "quellen.pdf")
            @test pdf_report(md, out; title="Quellen", lang="de-DE") == out
            bytes = read(out, String)
            @test occursin("<pdfuaid:part>1</pdfuaid:part>", bytes) && occursin("/StructTreeRoot", bytes)
            # Every address is a link to itself, `www.` with `https://`, without the
            # punctuation after it; a code span with more than an address stays text.
            @test uris(bytes) == sort(["https://www.regionalstatistik.de/genesis/online", "mailto:info@example.de",
                                       "https://www.example.de", "https://www.example.org/karte",
                                       "https://example.org/code",
                                       "https://sg.geodatenzentrum.de/web_public/gdz/datenquellen/Datenquellen_vg_nuts.pdf"])
            # The lone image, the one `with_caption` writes and Quarto's captioned
            # figure are figures of their own; the image within the line of text
            # stays in its paragraph, as before.
            @test figure_parents(bytes) == ["Div", "Document", "Document", "P"]

            # Quarto reads the front matter without the reader's autolinks, so an
            # address in a subtitle stayed text, and PAC failed it (snag
            # offer-pac-qualit-7471af7a). A one-letter "scheme" is a drive, not an address.
            titled = joinpath(dir, "titel.pdf")
            pdf_report("# Quellen\n", titled; title="Quellen", lang="de-DE",
                       metadata=(subtitle="Stand: https://example.org/odl/, (www.example.org/karte). info@example.de C://x",
                                 author="Autorin https://example.org/autorin/"))
            @test uris(read(titled, String)) == sort(["https://example.org/odl/", "https://www.example.org/karte",
                                                      "mailto:info@example.de", "https://example.org/autorin/"])
        end
    end
end

@testitem "pdf_report keeps semantic labels with their body across pages" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        marker(name) = "`#context [#metadata(here().page()) <$name>]`{=typst}"
        label(text, name) = "::: {.htmxo-label}\n**$text** $(marker(name))\n:::\n\n"
        body = "### Definition $(marker("heading"))\n\nFirst paragraph $(marker("body"))\n"
        function placement(md, lead; filtered=true, paragraph_spacing="1.2em")
            mktempdir() do dir
                filters = filtered ? ["--lua-filter", HTMXObjects._PDF_REPORT_LABELS_FILTER] : String[]
                typst = read(pipeline(`$quarto pandoc --from markdown --to typst $filters`;
                                     stdin=IOBuffer(md)), String)
                doc = joinpath(dir, "labels.typ")
                write(doc, "#set page(width: 300pt, height: 200pt, margin: 20pt)\n",
                      "#set par(spacing: $paragraph_spacing)\n#v($(lead)pt)\n", typst)
                out = IOBuffer()
                run(pipeline(`$quarto typst eval "query(metadata).map(it => it.value)" --in $doc`;
                             stdout=out, stderr=out))
                parse.(Float64, split(match(r"\[([\d.,\s]*)\]", String(take!(out))).captures[1], ','))
            end
        end
        short = label("Short label", "label") * body
        @test placement(short, 95) == [1, 1, 1]
        # Room for the label alone: without the rule it is stranded; with the
        # rule the label, heading and first paragraph move together.
        @test placement(short, 120; filtered=false) == [1, 2, 2]
        @test placement(short, 120) == [2, 2, 2]
        # Bold-only prose is not a semantic label and keeps its own pagination.
        prose = "**Short label** $(marker("label"))\n\n" * body
        @test placement(prose, 120) == placement(prose, 120; filtered=false)
        wrapped = label("A longer label that wraps across several lines with enough words to fill the line", "label") * body
        @test placement(wrapped, 105) == [2, 2, 2]
        nested = label("Outer label", "outer") * short
        @test placement(nested, 120) == [2, 2, 2, 2]
        long = short * join("\nParagraph $i $(marker("row"))\n" for i in 1:40)
        pages = placement(long, 120)
        @test pages[1:3] == [2, 2, 2]
        @test issorted(pages) && last(pages) > 3

        # Keep the label's paragraph spacing, including a document's smaller
        # spacing. The block default otherwise adds gaps and even extra pages.
        pos = "`#context [#metadata(here().position().y / 1pt)]`{=typst}"
        plain_label = "**Label** $pos\n\n"
        marked_label = "::: {.htmxo-label}\n**Label** $pos\n:::\n\n"
        @test last(placement("Before\n\n" * marked_label * "After $pos", 0; paragraph_spacing="0.55em")) ≈
              last(placement("Before\n\n" * plain_label * "After $pos", 0; paragraph_spacing="0.55em"))

        # Exercise the actual Markdown producer and Quarto's post-render
        # filter stage, including the PDF structure and all of a long body.
        mktempdir() do dir
            content = tabset("Outer tab" => SemanticDisclosure("Nested label",
                SemanticSection("Definition", (SemanticProse("Paragraph $i.") for i in 1:70)...)))
            out = joinpath(dir, "labels.pdf")
            @test pdf_report(content, out; title="Labels", lang="en-GB") == out
            bytes = read(out, String)
            @test occursin("<pdfuaid:part>1</pdfuaid:part>", bytes) && occursin("/StructTreeRoot", bytes)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text of each page"
            else
                texts = split(read(`pdftotext -enc UTF-8 -layout $out -`, String), '\f'; keepempty=false)
                onpage(pattern) = findall(t -> occursin(pattern, t), texts)
                @test onpage("Outer tab") == onpage("Nested label") == onpage("Definition") == onpage("Paragraph 1.")
                @test all(i -> length(onpage("Paragraph $i.")) == 1, 1:70)
                @test only(onpage("Paragraph 70.")) > only(onpage("Paragraph 1."))
                @test !occursin("htmxo-label", join(texts))
            end
        end
    end
end

@testitem "pdf_report breaks a captioned table across pages" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        # The page of the caption and of each row of a 30-row captioned table on
        # short pages, set below `lead` of space by Quarto's Typst with `rules`
        # in front, as `pdf_report` includes them.
        function placement(rules, lead)
            mktempdir() do dir
                doc = joinpath(dir, "t.typ")
                write(doc, rules, """
                    #set page(width: 300pt, height: 200pt, margin: 20pt)
                    #v($lead)
                    #figure(kind: "quarto-float-tbl", supplement: "Tabelle",
                      caption: figure.caption(position: top, [Cap #context [#metadata(here().page()) <cap>]]),
                      table(columns: 2, table.header[A][B],
                        ..range(30).map(i => ([#i], [#context [#metadata(here().page()) <row>]])).flatten()))
                    """)
                pages(label) = let out = IOBuffer()
                    run(pipeline(`$quarto typst eval "query(<$label>).map(it => it.value)" --in $doc`;
                                 stdout=out, stderr=out))
                    parse.(Int, split(match(r"\[([\d,\s]*)\]", String(take!(out))).captures[1], ','))
                end
                (; caption=only(pages("cap")), rows=pages("row"))
            end
        end
        rules = read(HTMXObjects._PDF_REPORT_TABLES_TYPST, String)

        # The control: without the rules the figure does not break, so all 30
        # rows land on the one page it moved to, running over its bottom.
        @test unique(placement("", "20pt").rows) == [2]
        # With them the table starts below the lead and continues page by page.
        flowed = placement(rules, "20pt")
        @test flowed.caption == first(flowed.rows) == 1
        @test issorted(flowed.rows) && last(flowed.rows) > 2
        # Room for the caption but not for the header and a row: the caption
        # moves to the next page with them instead of staying alone, as it does
        # when the table may break but the caption is not kept with it.
        moved = placement(rules, "135pt")
        @test moved.caption == first(moved.rows) == 2
        break_only = replace(rules, r"^#show figure\.caption.*$"m => "")
        @test break_only != rules && placement(break_only, "135pt").caption == 1

        # A whole report: a captioned 60-row table after a few lines.
        mktempdir() do dir
            n = 60
            page = h.article((h.p("Zeile $i.") for i in 1:3)...,
                render_table((Land=["Land $i" for i in 1:n], Wert=collect(1:n));
                    caption=CaptionSpec(; title="Werte je Land"), id="laender"),
                h.p("Nach der Tabelle."))
            out = joinpath(dir, "lang.pdf")
            @test pdf_report(page, out; title="Bericht", lang="de-DE") == out
            bytes = read(out, String)
            @test occursin("<pdfuaid:part>1</pdfuaid:part>", bytes) && occursin("/StructTreeRoot", bytes)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text of each page"
            else
                texts = split(read(`pdftotext -enc UTF-8 -layout $out -`, String), '\f'; keepempty=false)
                onpage(pattern) = findall(t -> occursin(pattern, t), texts)
                row(i) = onpage(Regex("Land $i\\s+$i\\s*\\n"))
                # Every row once; the table starts on page 1 below the lines,
                # where it has room, rather than moving to page 2.
                @test all(i -> length(row(i)) == 1, 1:n)
                @test onpage("Werte je Land") == row(1) == onpage("Zeile 3.") == [1]
                # It continues on the next pages, its header row on each one.
                table_pages = unique(vcat(row.(1:n)...))
                @test length(table_pages) >= 2
                @test onpage(r"Land\s+Wert") == table_pages
            end
        end
    end
end

@testitem "pdf_report tags a code block as one Code element with a paragraph per line" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        # Quarto's Skylighting tagged each token of a code block as a Code element of
        # its own: an empty one per line end and a whitespace-only one per space
        # between two tokens. PAC's Quality tab warned "Tagged text consists of only
        # whitespace" for each, 103 times in BRM's model view (snag
        # review-the-brm-m-68c151e1). Typst writes the structure tree uncompressed,
        # `N 0 obj <</Type/StructElem/S/<type>/P <parent> 0 R…/K[…]…>> endobj`.
        elements(bytes) = [(; n=parse(Int, m[1]), type=m[2], parent=parse(Int, m[3]), body=m[4])
                           for m in eachmatch(r"(?s)(\d+) 0 obj\s*<</Type/StructElem/S/(\w+)/P (\d+) 0 R(.*?)endobj", bytes)]
        empty_tags(bytes) = count(e -> occursin("/K[]", e.body), elements(bytes))
        # the paragraphs of each Code element, one per line it tags
        code_lines(bytes) = let es = elements(bytes)
            sort([count(p -> p.type == "P" && p.parent == c.n, es) for c in es if c.type == "Code"])
        end

        # a code span, a Julia block with an indented line, a line of spaces and a
        # blank line, and a block without a language
        md = "# Code\n\nCall `f(x)` once.\n\n" *
             "```julia\n\"Docstring.\"\nfunction f(x)\n    y = x + 1\n    \n\n    return y\nend\n```\n\n" *
             "```\nplain text\n```\n"
        mktempdir() do dir
            out = joinpath(dir, "code.pdf")
            @test pdf_report(md, out; title="Code", lang="en-GB") == out
            bytes = read(out, String)
            @test occursin("<pdfuaid:part>1</pdfuaid:part>", bytes) && occursin("/StructTreeRoot", bytes)
            # One Code element per code span and block, and one paragraph per line
            # with text: no empty element, and none for the line of spaces.
            @test empty_tags(bytes) == 0
            @test code_lines(bytes) == [0, 1, 5]
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the code's text"
            else
                text = read(`pdftotext -enc UTF-8 -layout $out -`, String)
                @test all(l -> occursin(l, text), ["f(x)", "\"Docstring.\"", "y = x + 1", "return y", "plain text"])
                # the indented lines start where they did, right of `function` and `end`
                # (where each word starts: `-layout` columns are not exact for code)
                boxes = [(; word=m[2], x=parse(Float64, m[1])) for m in
                         eachmatch(r"<word xMin=\"([\d.]+)\"[^>]*>([^<]*)</word>", read(`pdftotext -bbox $out -`, String))]
                x(word) = first(b.x for b in boxes if b.word == word)
                @test x("y") == x("return") > x("function") == x("end")
            end

            # The control: Quarto's default highlighting on the same Markdown tags
            # the tokens one by one, with empty elements, as before.
            mkdir(joinpath(dir, "skylighting"))
            qmd = joinpath(dir, "skylighting", "code.qmd")
            write(qmd, replace(HTMXObjects._pdf_report_qmd(md; title="Code", lang="en-GB"),
                               "    syntax-highlighting: idiomatic\n" => ""))
            run(pipeline(Cmd(`$quarto render code.qmd --to typst`; dir=dirname(qmd)); stdout=devnull, stderr=devnull))
            old = read(joinpath(dir, "skylighting", "code.pdf"), String)
            @test empty_tags(old) > 0 && length(code_lines(old)) > 10
        end

        # A blank line, or a line of spaces, is left out of the tags and kept on the
        # page: without the rule each is a paragraph of its own, and with it every
        # word stays where it was.
        rules = read(HTMXObjects._PDF_REPORT_CODE_TYPST, String)
        without = replace(rules, r"(?s)#show raw\.where\(block: true\): it => \{.*?\n\}\n" => "")
        @test without != rules
        compiled(rules) = mktempdir() do dir
            doc = joinpath(dir, "c.typ")
            write(doc, "#set document(title: \"C\")\n#set text(lang: \"en\", region: \"GB\")\n", rules,
                  "\n```julia\nf(x)\n\n    \n  y\n```\n")
            run(pipeline(`$quarto typst compile --pdf-standard ua-1 $doc`; stdout=devnull, stderr=devnull))
            pdf = joinpath(dir, "c.pdf")
            words = isnothing(Sys.which("pdftotext")) ? nothing :
                [m.match for m in eachmatch(r"<word [^>]*>[^<]*</word>", read(`pdftotext -bbox $pdf -`, String))]
            (; bytes=read(pdf, String), words)
        end
        with_rule, without_rule = compiled(rules), compiled(without)
        @test code_lines(with_rule.bytes) == [2] && empty_tags(with_rule.bytes) == 0
        @test code_lines(without_rule.bytes) == [4] && empty_tags(without_rule.bytes) > 0
        if isnothing(with_rule.words)
            @test_skip "pdftotext (poppler-utils) reads where each word is"
        else
            @test !isempty(with_rule.words) && with_rule.words == without_rule.words
        end
    end
end

@testitem "pdf_report writes a link a PDF cannot open as its text" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        md = """
            # Links {#oben}

            Länder: [Bayern]() · [Hessen](#) · [Berlin](/region/11) · [Bremen](region/04) · [Sortiert](?sort=name)
            · [Quelle](https://example.org/daten) · [Post](mailto:info@example.org) · [Nach oben](#oben)
            """
        # Typst, as Pandoc writes it after the filter. Without it Typst got
        # `#link("")[Bayern]` (`URL must not be empty`), `#link()[Hessen]`
        # (`expected string, … found content`) and `#link("./region/11")[Berlin]`,
        # a link relative to the PDF file (snag pdf-report-of-a-bc600825).
        typst(md; base=nothing) = mktempdir() do dir
            write(joinpath(dir, "links.md"), md)
            meta = isnothing(base) ? `` : `-M $(HTMXObjects._PDF_REPORT_BASE_URL_KEY)=$base`
            read(`$quarto pandoc -f markdown -t typst --wrap=none $meta --lua-filter=$(HTMXObjects._PDF_REPORT_LINKS_FILTER)
                  $(joinpath(dir, "links.md"))`, String)
        end
        kept = ["#link(\"https://example.org/daten\")[Quelle]", "#link(\"mailto:info@example.org\")[Post]",
                "#link(<oben>)[Nach oben]"]
        plain = typst(md)
        @test all(k -> occursin(k, plain), kept)
        @test count("#link(", plain) == length(kept)
        @test occursin("Länder: Bayern · Hessen · Berlin · Bremen · Sortiert", plain)
        based = typst(md; base="https://example.org/p/App")
        @test all(k -> occursin(k, based), kept)
        @test occursin("#link(\"https://example.org/p/App/region/11\")[Berlin]", based)
        @test count("#link(", based) == length(kept) + 1
        @test occursin("Bayern · Hessen · #link(", based) && occursin("· Bremen · Sortiert", based)
        # A link written as its text that shows an address is then linked like
        # any other address in the text.
        @test occursin("Seite: #link(\"https://www.example.org\")[www.example.org]",
                       typst("Seite: [www.example.org](www.example.org)\n"))
        @test occursin("Seite: #link(\"https://example.org/t\")",
                       typst("Seite: [https://example.org/t](?r=1)\n"))

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        # The URI links of a PDF, by poppler's `pdfinfo -url`; `nothing` without it.
        function uris(path)
            isnothing(Sys.which("pdfinfo")) && return nothing
            out = IOBuffer()
            success(run(pipeline(ignorestatus(`pdfinfo -url $path`); stdout=out, stderr=devnull))) || return nothing
            sort!([last(split(l)) for l in split(String(take!(out)), '\n') if occursin("Annotation", l)])
        end
        mktempdir() do dir
            # A page whose links are an htmx-only `<a>` without `href`, the
            # `href="#"` of a script-driven one and a site path.
            page = h.article(h.h1("Regionen"), h.p("Länder: ",
                h.a("Bayern"; hx_get="/region/09", hx_target="#karte"), " · ",
                h.a("Hessen"; href="#", hx_get="/region/06", onclick="event.preventDefault()"), " · ",
                h.a("Berlin"; href="/region/11"), " · ", h.a("Quelle"; href="https://example.org/daten")))
            for (base, links) in [nothing => ["https://example.org/daten"],
                                  "https://example.org/p/App/" =>
                                      ["https://example.org/daten", "https://example.org/p/App/region/11"]]
                out = joinpath(dir, "regionen.pdf")
                @test pdf_report(page, out; title="Regionen", lang="de-DE", base_url=base) == out
                @test pdfua(out)
                found = uris(out)
                if isnothing(found)
                    @test_skip "pdfinfo -url (poppler ≥ 22) lists the links"
                else
                    @test found == links
                end
                if isnothing(Sys.which("pdftotext"))
                    @test_skip "pdftotext (poppler-utils) reads the text layer"
                else
                    text = replace(read(`pdftotext -enc UTF-8 $out -`, String), r"\s+" => " ")
                    @test occursin("Länder: Bayern · Hessen · Berlin · Quelle", text)
                end
            end
            out = joinpath(dir, "links.pdf")
            @test pdf_report(md, out; title="Links", lang="de-DE") == out
            @test pdfua(out)
            found = uris(out)
            if !isnothing(found)
                @test found == ["https://example.org/daten", "mailto:info@example.org"]
            end
        end
    end
end

@testitem "pdf_report links a target where url_map says" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        snapshot = "https://example.org/odl"
        # A static snapshot that stores `/api/v1/ap3/anomalien?p_min=0.9` as
        # `api-v1-ap3-anomalien-p_min-0.9.json` (snag pdf-report-markd-23652624).
        snapshot_file(a) = replace(lstrip(a, '/'), r"[/?=&]" => "-") * ".json"
        asked = String[]
        url_map(a) = (push!(asked, a);
                      startswith(a, "/api/") ? "$snapshot/$(snapshot_file(a))" :
                      a == "region/04" ? "$snapshot/region.html?r=04" : nothing)
        md = """
            # Schnittstelle {#oben}

            Anomalien: [JSON](/api/v1/ap3/anomalien?p_min=0.9) · [Seite](/schnittstelle) · [Bremen](region/04)
            · [Bayern]() · [Quelle](https://example.org/daten) · [Nach oben](#oben) · [noch einmal](/api/v1/ap3/anomalien?p_min=0.9)

            | Antwort | Adresse |
            |---|---|
            | Stationen | [Liste](/api/v1/stationen) |
            """
        targets = ["/api/v1/ap3/anomalien?p_min=0.9", "/schnittstelle", "region/04",
                   "https://example.org/daten", "#oben", "/api/v1/stationen"]
        document = HTMXObjects._pdf_report_qmd(md; title="Konzept [Start](/start)", lang="de-DE", base_url=snapshot)
        # The title's link is read with the document's, each target once.
        @test HTMXObjects._pdf_report_link_targets(quarto, document) == ["/start"; targets]

        # Typst, as Pandoc writes it after the filter, with url_map's answers.
        typst(urls) = mktempdir() do dir
            path = joinpath(dir, "links.qmd")
            write(path, HTMXObjects._pdf_report_qmd(md; title="Konzept", lang="de-DE", base_url=snapshot, urls))
            out, err = IOBuffer(), IOBuffer()
            proc = run(pipeline(ignorestatus(`$quarto pandoc -f markdown -t typst --wrap=none
                                              --lua-filter=$(HTMXObjects._PDF_REPORT_LINKS_FILTER) $path`);
                                stdout=out, stderr=err))
            success(proc) ? String(take!(out)) : String(take!(err))
        end
        answers = [t => HTMXObjects._pdf_report_mapped_url(url_map(t), t) for t in targets]
        mapped = typst(answers)
        json = "$snapshot/api-v1-ap3-anomalien-p_min-0.9.json"
        @test count("#link(\"$json\")", mapped) == 2
        @test occursin("#link(\"$snapshot/api-v1-stationen.json\")[Liste]", mapped)
        # nothing leaves a link to base_url, its text, or itself
        @test occursin("#link(\"$snapshot/schnittstelle\")[Seite]", mapped)
        @test occursin("#link(\"$snapshot/region.html?r=04\")[Bremen]", mapped)
        @test occursin("· Bayern · #link(\"https://example.org/daten\")[Quelle]", mapped)
        @test occursin("#link(<oben>)[Nach oben]", mapped)
        @test !occursin("htmxobjects-url-map", mapped)
        # A target the render reads but nobody asked url_map about stops the
        # filter rather than taking a rule url_map was never consulted on.
        stopped = typst(answers[2:end])
        @test occursin("url_map was not asked about the link target /api/v1/ap3/anomalien?p_min=0.9", stopped)

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        mktempdir() do dir
            out = joinpath(dir, "konzept.pdf")
            empty!(asked)
            @test pdf_report(md, out; title="Konzept", lang="de-DE", base_url=snapshot, url_map) == out
            @test pdfua(out)
            # once per target, in the order they appear
            @test asked == targets
            if isnothing(Sys.which("pdfinfo"))
                @test_skip "pdfinfo -url (poppler ≥ 22) lists the links"
            else
                io = IOBuffer()
                if success(run(pipeline(ignorestatus(`pdfinfo -url $out`); stdout=io, stderr=devnull)))
                    found = sort!([last(split(l)) for l in split(String(take!(io)), '\n') if occursin("Annotation", l)])
                    @test found == sort!([json, json, "$snapshot/schnittstelle", "$snapshot/region.html?r=04",
                                          "https://example.org/daten", "$snapshot/api-v1-stationen.json"])
                else
                    @test_skip "pdfinfo -url (poppler ≥ 22) lists the links"
                end
            end
            # refused: a PDF cannot open a relative answer; nothing is rendered
            rm(out)
            err = try
                pdf_report(md, out; title="Konzept", lang="de-DE", url_map = a -> "api.json")
            catch e
                e
            end
            @test err isa ArgumentError && occursin("absolute URL", err.msg)
            @test readdir(dir) == []
            # An error in url_map itself reaches the caller.
            err = try
                pdf_report(md, out; title="Konzept", lang="de-DE", url_map = a -> error("no map for $a"))
            catch e
                e
            end
            @test err isa ErrorException && occursin("no map for /api/v1/ap3/anomalien?p_min=0.9", err.msg)
            @test readdir(dir) == []
        end
    end
end

@testitem "pdf_report keeps a line break in a table cell" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        # A pipe table row is one line, so a cell's line break is an inline
        # `<br>`. Pandoc's Typst writer drops raw HTML: without the filter Typst
        # got `[27.26825.501--28.966]` (snag pdf-report-on-ma-981f47e0).
        md = """
            | Region | Arbeitsplätze |
            |---|---|
            | Goslar | 27.268<br>25.501–28.966 |
            | Harz | 1<br/>2 |
            | Brocken | 3<BR />4 |

            Eins<br>zwei.
            """
        typst = mktempdir() do dir
            write(joinpath(dir, "breaks.md"), md)
            read(`$quarto pandoc -f markdown -t typst --wrap=none --lua-filter=$(HTMXObjects._PDF_REPORT_BREAKS_FILTER)
                  $(joinpath(dir, "breaks.md"))`, String)
        end
        @test occursin("[27.268 \\ 25.501--28.966]", typst)
        @test occursin("[1 \\ 2]", typst) && occursin("[3 \\ 4]", typst)
        @test occursin("Eins \\ zwei.", typst)

        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        mktempdir() do dir
            # The cell of a page: a median, a line break and its interval.
            page = h.article(h.h1("Regionen"), h.table(
                h.thead(h.tr(h.th("Region"), h.th("Arbeitsplätze"))),
                h.tbody(h.tr(h.td("Goslar"), h.td("27.268", h.br(), h.small("25.501–28.966"))))))
            @test occursin("27.268<br>25.501–28.966", HTMXObjects.to_markdown_string(page))
            out = joinpath(dir, "regionen.pdf")
            @test pdf_report(page, out; title="Regionen", lang="de-DE") == out
            @test pdfua(out)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                text = read(`pdftotext -enc UTF-8 -layout $out -`, String)
                @test !occursin("27.26825.501", text)
                lines = strip.(split(text, '\n'))
                @test any(l -> endswith(l, "27.268"), lines) && any(==("25.501–28.966"), lines)
            end
        end
    end
end

@testitem "pdf_report writes metadata text so that it opens no math" tags=[:unit] begin
    using HTMXObjects

    # `\(` and `\[` open math in the report's reader.
    @test HTMXObjects._markdown_literal("(a) [b] 1.") == raw"&#40;a\) &#91;b\] 1\."
end

@testitem "pdf_report sets math wherever the browser does" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects

        quarto = Sys.which("quarto")
        reader = HTMXObjects._PDF_REPORT_READER
        typst(md, filters...) = mktempdir() do dir
            file = joinpath(dir, "m.md")
            write(file, md)
            read(`$quarto pandoc -f $reader -t typst --wrap=none $(["--lua-filter=$f" for f in filters]) $file`, String)
        end
        equations(md) = typst(md, HTMXObjects._PDFUA_MATH_ALT_FILTER)
        browser(md) = count("data-htmxo-math=", repr("text/html", render_markdown(md)))

        # Pandoc reads `\[` as an escaped bracket by default and each TeX command as
        # raw TeX, which its Typst writer drops: `\[ q_{\mathrm{cut}}(\phi,\theta) \]`
        # printed `[ q_{}(,) ]` and veraPDF passed it (snag pdf-report-brack-a0716710).
        @testset "$(repr(md))" for (md, formulas) in [
                raw"\[q\]" => 1, raw"Im \(x_1\) und \[y\] Text." => 2, "\\[\nx\n\\]" => 1,
                raw"$x$ und $$y$$" => 2, "\$\$\nx\n\$\$" => 1, "```math\nx\n```" => 1,
                raw"\( x \)" => 1, raw"Offen \[ bleibt Text." => 0, "Über \\[ einen\n\nAbsatz \\] nicht." => 0,
                raw"Code `\[x\]` und `\(y\)`." => 0, "```\n\\[x\\]\n```" => 0,
                raw"costs $5 and $10" => 0, raw"Preis \$5." => 0]
            @test browser(md) == formulas
            @test count("math.equation(alt:", equations(md)) == formulas
        end

        cut = equations("\\[\nq_{\\mathrm{cut}}(\\phi,\\theta)\n= p(\\phi\\mid D_A)\\,p(\\theta\\mid\\phi,D_B).\n\\]")
        @test occursin("phi.alt", cut) && occursin("theta", cut) && occursin("divides", cut)
        @test occursin(raw"q_{\\mathrm{cut}}(\\phi,\\theta)", cut)    # the alt text is the TeX source
        @test !occursin("q\\_{}", cut)

        # A TeX command outside any delimiters stays the text the browser shows.
        text = typst(raw"Pfad C:\Users\foo und \alpha hier.")
        @test occursin(raw"C:\\Users\\foo", text) && occursin(raw"\\alpha", text)
        @test occursin(raw"C:\Users\foo und \alpha hier", repr("text/html", render_markdown(raw"Pfad C:\Users\foo und \alpha hier.")))

        # The writer rounds `\!` to `#h(-1em)`, which overprinted a bracket on the
        # subscript before it, and `\;` to nothing. When this control fails, Pandoc has
        # fixed that and the filter's marks can go.
        @test occursin("#h(-1em)", typst(raw"$a\!b$")) && occursin("#h(0em)", typst(raw"$a\;b$"))
        spaces = equations(raw"$\mathbb E_q\!\left[x\right]\;y$")
        @test occursin("#h(-1em/6)", spaces) && occursin("thick", spaces) && !occursin("HTMXOPDF", spaces)
        @test occursin(raw"\\!", spaces)    # the alt text keeps the source
        # A pair of backslashes is a line break, not the command.
        @test occursin(raw"\\\\!", equations(raw"$\begin{aligned}a\\!b\end{aligned}$"))
        # A formula the writer cannot convert prints its source, without the marks.
        unconverted = equations(raw"$a\!\negthinspace b$")
        @test occursin(raw"\\negthinspace", unconverted) && !occursin("HTMXOPDF", unconverted)

        # Metadata text with brackets stays text, also where it is an address.
        mktempdir() do dir
            template = joinpath(dir, "date.template")
            write(template, "\$date\$\n")
            date = joinpath(dir, "date.md")
            write(date, "---\n$(HTMXObjects._PDF_REPORT_DATE_TEXT_KEY): " *
                        "$(HTMXObjects._yaml_string(HTMXObjects._markdown_literal("(Entwurf) [1] 23.10.")))\n---\n")
            @test strip(read(`$quarto pandoc -s -f $reader -t typst --template=$template
                               --lua-filter=$(HTMXObjects._PDF_REPORT_DATE_FILTER) $date`, String)) ==
                  "#\"(Entwurf) [1] 23.10.\""
        end
        linked = typst("---\n$(HTMXObjects._PDF_REPORT_BASE_URL_KEY): " *
                       "$(HTMXObjects._yaml_string(HTMXObjects._markdown_literal("https://example.org/a_(b)")))\n---\n\n[x](/p)\n",
                       HTMXObjects._PDF_REPORT_LINKS_FILTER)
        @test occursin("https://example.org/a_(b)/p", linked)

        # The whole way, from a `SemanticProse`, whose Markdown is its source.
        pdfua(path) = let bytes = read(path, String)
            startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
        end
        mktempdir() do dir
            out = joinpath(dir, "formeln.pdf")
            prose = SemanticProse("""
                Inline \\(x_1\\) und \$y\$.

                \\[
                q_{\\mathrm{cut}}(\\phi,\\theta) = \\mathbb E_q\\!\\left[\\log p(\\theta\\mid\\phi)\\right]
                \\]

                ```math
                \\sum_f z_f
                ```
                """)
            @test pdf_report(prose, out; title="Formeln", lang="de-DE") == out
            @test pdfua(out)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                pages = read(`pdftotext -enc UTF-8 -layout $out -`, String)
                @test occursin("𝜙", pages) && occursin("𝜃", pages) && occursin("cut", pages) && occursin("∑", pages)
                @test !occursin("q_{", pages) && !occursin("\\", pages)
            end
        end
    end
end

@testitem "pdf_report's repair makes a letter with a combining mark read once" tags=[:unit] begin
    using HTMXObjects
    using HTMXObjects: _pdf_text_layer_repaired, _pdf_file, _pdf_stream_data, _pdf_to_unicode,
        _pdf_scan_content, _pdf_utf16be_hex
    zlib = HTMXObjects.CodecZlib

    # A PDF laid out as Typst lays it out: the page's content is object 5, the
    # font's ToUnicode table object 7.
    function tiny_pdf(entries, content)
        cmap = "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n$(length(entries)) beginbfchar\n" *
               join(("<$(uppercase(string(code; base=16, pad=4)))> <$(_pdf_utf16be_hex(text))>"
                     for (code, text) in entries), "\n") * "\nendbfchar\n"
        stream(s) = let z = transcode(zlib.ZlibCompressor, Vector{UInt8}(codeunits(s)))
            vcat(Vector{UInt8}(codeunits("<</Filter/FlateDecode/Length $(length(z))>>\nstream\n")), z,
                 Vector{UInt8}(codeunits("\nendstream\n")))
        end
        plain(s) = Vector{UInt8}(codeunits(s * "\n"))
        objects = [plain("<</Type/Catalog/Pages 2 0 R>>"), plain("<</Type/Pages/Kids[3 0 R]/Count 1>>"),
                   plain("<</Type/Page/Resources 4 0 R/Contents 5 0 R/Parent 2 0 R>>"),
                   plain("<</Font<</f0 6 0 R>>>>"), stream(content),
                   plain("<</Type/Font/Subtype/Type0/BaseFont/X/Encoding/Identity-H/DescendantFonts[8 0 R]/ToUnicode 7 0 R>>"),
                   stream(cmap), plain("<</Type/Font/Subtype/CIDFontType0/BaseFont/X/DW 500/W[1[600] 2[0] 8 9 0]>>")]
        out = IOBuffer()
        write(out, "%PDF-1.7\n")
        offsets = Int[]
        for (n, object) in enumerate(objects)
            push!(offsets, position(out))
            write(out, "$n 0 obj\n", object, "endobj\n")
        end
        xref = position(out)
        write(out, "xref\n0 $(length(objects) + 1)\n0000000000 65535 f \n")
        foreach(offset -> write(out, lpad(offset, 10, '0'), " 00000 n \n"), offsets)
        write(out, "trailer\n<</Size $(length(objects) + 1)/Root 1 0 R>>\nstartxref\n$xref\n%%EOF")
        return take!(out)
    end

    table(pdf) = _pdf_to_unicode(String(_pdf_stream_data(_pdf_file(pdf), 7)))
    content(pdf) = _pdf_stream_data(_pdf_file(pdf), 5)
    scan(pdf) = _pdf_scan_content(content(pdf), Dict("f0" => 6))
    # What a reader that honours ActualText gets, and one that ignores it.
    function honouring(pdf)
        s, t = scan(pdf), table(pdf)
        out = IOBuffer()
        seen = 0
        for g in s.glyphs
            if g.span == 0
                write(out, t[g.code])
            elseif g.span != seen
                write(out, s.spans[g.span].text)
            end
            seen = g.span
        end
        return String(take!(out))
    end
    ignoring(pdf) = let t = table(pdf)
        join(t[g.code] for g in scan(pdf).glyphs)
    end
    # Every glyph and pen movement, in order: what a page draws from these streams.
    drawn(pdf) = let c = content(pdf)
        [e isa UnitRange ? String(c[e]) : e for show in scan(pdf).shows for e in show.elements for e in
         (e isa UnitRange ? [e] : [e[k:k+1] for k in 1:2:length(e)-1])]
    end
    objects_where_the_table_says(pdf) = let file = _pdf_file(pdf)
        all(startswith(String(pdf[range]), "$number 0 obj") for (number, range) in file.ranges)
    end

    rhat, xhat, qhat = "R̂", "x̂", "q̂"
    text(codes...; adjust="") = "BT 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[$adjust" *
        join("(\\000\\$(string(c; base=8, pad=3)))" for c in codes) * "]TJ\nET\n"
    tagged(n, body) = "/Span<</MCID $n>>BDC\nq 1 0 0 -1 20 $(30 + n) cm\n$(body)Q\nEMC"

    # The letter ends a longer run and the mark is a run of its own, each tagged,
    # both mapped to the whole cluster: what Typst writes for "aR̂b".
    typst = tiny_pdf([1 => rhat, 2 => rhat, 3 => "a", 4 => "b"],
                     tagged(0, text(3, 1)) * tagged(1, text(2; adjust="185")) * tagged(2, text(4)))
    @test honouring(typst) == ignoring(typst) == "a$(rhat)$(rhat)b"
    fixed = _pdf_text_layer_repaired(typst)
    @test honouring(fixed) == "a$(rhat)b"
    @test ignoring(fixed) == "a$(rhat)b"
    @test table(fixed)[1] == "R" && table(fixed)[2] == "̂" && table(fixed)[3] == "a"
    @test drawn(fixed) == drawn(typst)
    @test objects_where_the_table_says(fixed)
    @test occursin("<</MCID 1>>BDC", String(content(fixed)))
    @test startswith(String(copy(fixed)), "%PDF-1.7\n") && endswith(String(copy(fixed)), "%%EOF\n")
    @test _pdf_text_layer_repaired(fixed) === nothing  # nothing is left to repair
    # One span holds both glyphs: PDFium and xpdf ignore an empty span, so a span
    # per glyph would read the mark's code point too (`R̂̂`). The mark moves into the
    # letter's text object at the place it was, and its pen ends at the next glyph,
    # or readers see a word gap there.
    spans_of(pdf) = [s.text for s in scan(pdf).spans if !isnothing(s.text)]
    @test spans_of(fixed) == [rhat]
    @test occursin("1 0 0 -1 0 -1 Tm 2.035 Tc [185 <0002>]TJ 0 Tc", String(content(fixed)))
    mark_place(pdf, code) = let s = only(s for s in scan(pdf).shows if any(e -> e isa Vector{UInt8} && e == [0x00, code], s.elements))
        (s.matrix[5] + s.text_matrix[5], s.matrix[6] - s.text_matrix[6])
    end
    @test mark_place(fixed, 0x02) == mark_place(typst, 0x02) == (20.0, 31.0)

    # The same cluster twice in a row is two clusters.
    twice = tiny_pdf([1 => rhat, 2 => rhat], tagged(0, text(1)) * tagged(1, text(2)) * tagged(2, text(1)) * tagged(3, text(2)))
    @test honouring(_pdf_text_layer_repaired(twice)) == ignoring(_pdf_text_layer_repaired(twice)) == rhat * rhat

    # The table already says "R" for the letter, so the letter carries a span.
    plain_first = tiny_pdf([1 => "R", 2 => rhat],
        tagged(0, text(1)) * tagged(1, "BT/Span<</ActualText<FEFF00520302>>>BDC 0 Tr/f0 11 Tf 1 0 0 -1 7.5 0 Tm[(\\000\\001)]TJ\nEMC\nET\n") *
        tagged(2, text(2)))
    fixed = _pdf_text_layer_repaired(plain_first)
    @test honouring(plain_first) == "R$(rhat)$(rhat)"
    @test honouring(fixed) == ignoring(fixed) == "R$(rhat)"
    @test table(fixed)[1] == "R"
    @test spans_of(fixed) == [rhat]
    @test drawn(fixed) == drawn(plain_first)

    # One mark's glyph serves two letters, and the table holds the first letter.
    shared = tiny_pdf([8 => xhat, 9 => xhat, 20 => qhat],
        tagged(0, text(8)) * tagged(1, text(9)) * tagged(2, text(20)) *
        tagged(3, "BT/Span<</ActualText<FEFF00710302>>>BDC 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[(\\000\\011)]TJ\nEMC\nET\n"))
    fixed = _pdf_text_layer_repaired(shared)
    @test honouring(shared) == "$(xhat)$(xhat)$(qhat)$(qhat)"
    @test honouring(fixed) == ignoring(fixed) == "$(xhat)$(qhat)"
    @test !occursin("/ActualText()", String(content(fixed)))
    @test spans_of(fixed) == [xhat, qhat]
    @test drawn(fixed) == drawn(shared)

    # Two marks, and a code that needs escaping in a literal string.
    two_marks = "R̂̄"
    marks = tiny_pdf([0x28 => two_marks, 0x29 => two_marks, 0x5c => two_marks],
        tagged(0, "BT 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[(\\000\\()]TJ\nET\n") * tagged(1, "BT 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[(\\000\\))]TJ\nET\n") *
        tagged(2, "BT 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm(\\000\\\\)Tj\nET\n"))
    fixed = _pdf_text_layer_repaired(marks)
    @test honouring(fixed) == ignoring(fixed) == two_marks
    @test table(fixed)[0x28] == "R" && table(fixed)[0x29] == "̂" && table(fixed)[0x5c] == "̄"
    @test spans_of(fixed) == [two_marks]

    # Marks that share a run with the letter stay in its span; the rest join it.
    thai = "สิ่"
    split_run = tiny_pdf([1 => thai, 2 => thai, 3 => thai],
        tagged(0, "BT/Span<</ActualText<FEFF0E2A0E340E48>>>BDC 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[(\\000\\001\\000\\002)]TJ\nEMC\nET\n") *
        tagged(1, text(3)))
    fixed = _pdf_text_layer_repaired(split_run)
    @test honouring(fixed) == ignoring(fixed) == thai
    @test spans_of(fixed) == [thai]
    @test drawn(fixed) == drawn(split_run)

    # Runs that differ in more than their place cannot share a text object: the
    # letter's span reads the cluster, the mark's reads nothing, and it stays put.
    other_colour = tiny_pdf([1 => rhat, 2 => rhat],
        tagged(0, "/c0 cs 0 scn\n" * text(1)) * tagged(1, "/c1 cs 0 scn\n" * text(2)))
    fixed = _pdf_text_layer_repaired(other_colour)
    @test honouring(fixed) == ignoring(fixed) == rhat
    @test spans_of(fixed) == [rhat, ""]
    @test mark_place(fixed, 0x02) == mark_place(other_colour, 0x02)
    # So does a run whose place this repair cannot follow.
    no_matrix = tiny_pdf([1 => rhat, 2 => rhat],
        tagged(0, "BT 0 Tr/f0 11 Tf[(\\000\\001)]TJ\nET\n") * tagged(1, "BT 0 Tr/f0 11 Tf[(\\000\\002)]TJ\nET\n"))
    @test spans_of(_pdf_text_layer_repaired(no_matrix)) == [rhat, ""]

    # Both forms of a font's width array, and the default width.
    widths = HTMXObjects._pdf_font_widths(_pdf_file(typst), String(typst[_pdf_file(typst).ranges[6]]))
    @test widths.table[0x0001] == 600.0 && widths.table[0x0002] == 0.0 && widths.table[0x0009] == 0.0
    @test widths.default == 500.0
    @test HTMXObjects._pdf_number(1.045) == "1.045" && HTMXObjects._pdf_number(-0.5) == "-0.5"
    @test HTMXObjects._pdf_number(0.0000001) == "0" && HTMXObjects._pdf_number(3.0) == "3"

    # The letter's glyph reads something else elsewhere: its cluster still reads
    # once where ActualText counts, and the table keeps what it says.
    dotted = "i̇"
    other = tiny_pdf([5 => "ı", 6 => dotted],
        tagged(0, text(5)) * tagged(1, "BT/Span<</ActualText<FEFF00690307>>>BDC 0 Tr/f0 11 Tf 1 0 0 -1 0 0 Tm[(\\000\\005)]TJ\nEMC\nET\n") *
        tagged(2, text(6)))
    fixed = _pdf_text_layer_repaired(other)
    @test honouring(fixed) == "ı$(dotted)"
    @test table(fixed)[5] == "ı"

    # Right to left the glyphs do not follow the code points: spans only.
    hebrew = "שָ"
    rtl = tiny_pdf([1 => hebrew, 2 => hebrew], tagged(0, text(1)) * tagged(1, text(2)))
    fixed = _pdf_text_layer_repaired(rtl)
    @test honouring(fixed) == hebrew
    @test table(fixed)[1] == hebrew && table(fixed)[2] == hebrew

    # Nothing to repair leaves the file as it is: `nothing` means no rewrite.
    @test _pdf_text_layer_repaired(tiny_pdf([1 => "a", 2 => "b"], tagged(0, text(1, 2)))) === nothing
    # A glyph that draws the whole cluster reads once already.
    @test _pdf_text_layer_repaired(tiny_pdf([1 => "ê"], tagged(0, text(1)) * tagged(1, text(1)))) === nothing
    # A ligature is not a letter with a mark: "ffff" is two ligatures.
    @test _pdf_text_layer_repaired(tiny_pdf([1 => "ff", 2 => "ff"], tagged(0, text(1, 2)))) === nothing
    # One span around both glyphs reads once already (krilla's own way).
    @test _pdf_text_layer_repaired(tiny_pdf([1 => rhat, 2 => rhat],
        "BT/Span<</ActualText<FEFF00520302>>>BDC 0 Tr/f0 11 Tf[(\\000\\001\\000\\002)]TJ\nEMC\nET\n")) === nothing

    # What it cannot tell apart or read, it leaves and says so.
    three = tiny_pdf([1 => rhat, 2 => rhat, 3 => rhat], tagged(0, text(1)) * tagged(1, text(2)) * tagged(2, text(3)))
    @test (@test_logs (:warn, r"still read twice.*R̂") _pdf_text_layer_repaired(three)) === nothing
    inline_image = tiny_pdf([1 => rhat], "BI /W 1 /H 1 ID x EI\n" * tagged(0, text(1)))
    @test (@test_logs (:warn, r"could not read") _pdf_text_layer_repaired(inline_image)) === nothing
    @test (@test_logs (:warn, r"could not read") _pdf_text_layer_repaired(Vector{UInt8}(codeunits("not a pdf")))) === nothing
end

@testitem "pdf_report reads a letter with a combining mark once in the text layer" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1" || isnothing(Sys.which("pdftotext"))
        @test_skip "Quarto and pdftotext (poppler-utils) write and read the text layer"
    else
        using HTMXObjects

        rhat, xhat, qhat = "R̂", "x̂", "q̂"
        extract(path, mode...) = read(`pdftotext -enc UTF-8 $mode $path -`, String)
        mktempdir() do dir
            # Typst alone repeats the letter (typst/typst#8767). If this control
            # fails, Typst has fixed that and `src/pdf_text_layer.jl` can go.
            typ = joinpath(dir, "plain.typ")
            write(typ, "#set document(title: [T])\n$rhat ≤ 1,011\n")
            run(`$(Sys.which("quarto")) typst compile --pdf-standard ua-1 $typ`)
            @test occursin(rhat * rhat, extract(joinpath(dir, "plain.pdf"), "-raw"))

            md = """
                # Konvergenz $rhat

                Ein R, dann $rhat ≤ 1,011 und $xhat und $qhat, zweimal $rhat$rhat, im Wort a$(xhat)b,
                **fett $rhat** und `code $rhat`. Mit eigenem Glyph: ê und ê.

                | Größe | Wert |
                |---|---|
                | $rhat | 1,011 |
                """
            out = joinpath(dir, "bericht.pdf")
            @test pdf_report(md, out; title="Bericht", lang="de-DE") == out
            bytes = read(out, String)
            @test startswith(bytes, "%PDF") && occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
            for mode in (("-raw",), (), ("-layout",))
                text = extract(out, mode...)
                @test occursin("Konvergenz $rhat", text)
                @test occursin("$rhat ≤ 1,011", text)
                @test occursin("$xhat und $qhat", text)
                @test occursin("zweimal $rhat$rhat,", text)
                @test occursin("a$(xhat)b", text)
                @test occursin("fett $rhat", text)
                @test occursin("code $rhat", text)
                @test count(rhat, text) == 7
            end
        end
    end
end
