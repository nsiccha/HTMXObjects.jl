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
            include-in-header: [$(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_TABLES_TYPST))]
        filters:
          - path: $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_QUOTES_FILTER))
            at: post-render
          - $(HTMXObjects._yaml_string(filter))
          - $(HTMXObjects._yaml_string(images))
          - $(HTMXObjects._yaml_string(HTMXObjects._PDF_REPORT_DATE_FILTER))
        ---

        # Ergebnisse
        """
    @test isfile(HTMXObjects._PDF_REPORT_QUOTES_FILTER) && isfile(HTMXObjects._PDF_REPORT_TABLES_TYPST) &&
          isfile(HTMXObjects._PDF_REPORT_DATE_FILTER)
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
