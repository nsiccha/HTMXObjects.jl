@testmodule PdfFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export tiny_pdf, PDF_PAGES, html, PDF3, PdfExportApp

    # A PDF of text lines in Helvetica, one page per entry, each line its own
    # text run: enough for PDF.js to draw the pages and read their words.
    function tiny_pdf(pages::Vector{Vector{String}})
        esc(s) = replace(s, '\\' => "\\\\", '(' => "\\(", ')' => "\\)")
        n = length(pages)
        kids = [4 + 2(i - 1) for i in 1:n]
        objs = String["<< /Type /Catalog /Pages 2 0 R >>",
                      "<< /Type /Pages /Kids [$(join(("$k 0 R" for k in kids), " "))] /Count $n >>",
                      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
        for (i, lines) in enumerate(pages)
            content = "BT /F1 14 Tf 72 720 Td 20 TL " * join(("(" * esc(l) * ") Tj T*" for l in lines), " ") * " ET"
            push!(objs, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " *
                        "/Resources << /Font << /F1 3 0 R >> >> /Contents $(kids[i] + 1) 0 R >>")
            push!(objs, "<< /Length $(sizeof(content)) >>\nstream\n$content\nendstream")
        end
        io = IOBuffer()
        write(io, "%PDF-1.4\n")
        offsets = Int[]
        for (i, o) in enumerate(objs)
            push!(offsets, position(io))
            write(io, "$i 0 obj\n$o\nendobj\n")
        end
        xref = position(io)
        write(io, "xref\n0 $(length(objs) + 1)\n0000000000 65535 f \n")
        for off in offsets
            write(io, lpad(off, 10, '0'), " 00000 n \n")
        end
        write(io, "trailer\n<< /Size $(length(objs) + 1) /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
        take!(io)
    end

    const PDF_PAGES = [
        ["Section 1: Child protection",
         "Child protection is the task of every provider and of",
         "everyone who works with children in the provider's care.",
         "Other text on the first page."],
        ["Section 2: Reporting",
         "A suspected case is reported to the youth office within one day.",
         "The report names the facts observed and the steps taken."]]
    const PDF3 = tiny_pdf([PDF_PAGES; [["Section 3: Records",
                                        "Every report is kept for ten years in the provider's records."]]])

    html(x) = repr("text/html", x)

    # A panel in an app, for its static export (snag pdf-panel-static-81f73b0d):
    # its files come from routes without an extension, as a tender app's do. A
    # page with one document, with references to it and to a file it does not
    # list, one with pills and one with a searchable list.
    @htmx struct PdfExportApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = pdf_beside(
            h.article(
                h.p("Records ", pdf_ref("(LB, p. 3)", "/pdfx_datei/lb"; page=3, panel="orig", id="r3",
                                        quoted="kept for ten years in the provider's records"), "."),
                h.p("Reports ", pdf_ref("(annex, p. 2)", "/pdfx_datei/anlage"; page=2, panel="orig", id="r2",
                                        quoted="reported to the youth office"), "."),
                pdf_toggle("orig", "Originale"; id="toggle"),
                h.p("Trips ", pdf_ref("(Methodik)", "/pdfx_text#methodik"; kind=:html, panel="orig", id="rh",
                                      quoted="follow a Poisson distribution"), "."),
                h.p(h.a("Pills"; href="/pdfx_pills"), " ", h.a("List"; href="/pdfx_list"))),
            pdf_panel(["Leistungsbeschreibung" => "/pdfx_datei/lb"]; id="orig"))
        @get pdfx_pills() = pdf_panel(["LB" => "/pdfx_datei/lb", "Anlage" => "/pdfx_datei/anlage",
                                       (title="Text", url="/pdfx_text", kind=:html)]; id="pills")
        @get pdfx_list() = pdf_panel(["Teil $i" => "/pdfx_datei/teil$i" for i in 1:9]; id="list")
        @direct @get pdfx_datei(name::String) = MIMEResponse("application/pdf", PDF3)
        # an HTML document the panel loads as a fragment (snag pdf-panel-shows-b0bebb33)
        @get pdfx_text() = h.article(h.h2("Methodik"; id="methodik"),
                                     h.p("Trips per zone follow a Poisson distribution."))
    end
end

@testitem "pdf_ref is a link to the page that names its passage" setup=[PdfFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    r = pdf_ref("(S. 12)", "/files/k.pdf#zoom=50"; page=12, panel="orig", quoted="Kinderschutz ist Aufgabe aller Träger")
    s = html(r)
    @test occursin("href=\"/files/k.pdf#page=12\"", s)              # the file at its page, its own fragment dropped
    @test occursin("data-htmxo-pdf-url=\"/files/k.pdf\"", s)
    @test occursin("data-htmxo-pdf-page=\"12\"", s)
    @test occursin("data-htmxo-pdf-panel=\"orig\"", s) && occursin("aria-controls=\"orig\"", s)
    @test occursin("data-htmxo-pdf-quote=\"Kinderschutz ist Aufgabe aller Träger\"", s)
    key = match(r"data-htmxo-pdf-key=\"([^\"]+)\"", s)[1]
    hue = parse(Int, match(r"data-htmxo-pdf-hue=\"(\d)\"", s)[1])
    @test 1 <= hue <= 8
    # one passage, one key and one colour, wherever it is quoted; another passage, another key
    again = html(pdf_ref("ebd.", "/files/k.pdf"; page=12, panel="orig", quoted="Kinderschutz ist Aufgabe aller Träger"))
    @test occursin("data-htmxo-pdf-key=\"$key\"", again) && occursin("data-htmxo-pdf-hue=\"$hue\"", again)
    @test !occursin(key, html(pdf_ref("x", "/files/k.pdf"; page=13, panel="orig", quoted="Kinderschutz ist Aufgabe aller Träger")))
    # a key and a colour of one's own
    own = html(pdf_ref("LB 3.2", "/doc.pdf"; page=2, panel="p", quoted="words here", key="lb-3-2", hue=3,
                       document="Leistungsbeschreibung", class="ref"))
    @test occursin("data-htmxo-pdf-key=\"lb-3-2\"", own) && occursin("data-htmxo-pdf-hue=\"3\"", own)
    @test occursin("data-htmxo-pdf-document=\"Leistungsbeschreibung\"", own) && occursin("class=\"ref\"", own)
    # without quoted words: the page's top, no passage, no key
    plain = html(pdf_ref("Leistungsbeschreibung", "/doc.pdf"; panel="p"))
    @test occursin("href=\"/doc.pdf#page=1\"", plain)
    @test !occursin("data-htmxo-pdf-key", plain) && !occursin("data-htmxo-pdf-quote", plain) && !occursin("data-htmxo-pdf-hue", plain)
    @test !occursin("data-htmxo-pdf-quote", html(pdf_ref("x", "/doc.pdf"; panel="p", quoted="  ")))
    # its Markdown is the link
    @test strip(to_markdown_string(h.p("Siehe ", r, "."))) == "Siehe [(S. 12)](/files/k.pdf#page=12)."
    # refused
    @test_throws ArgumentError pdf_ref("x", "/doc.pdf"; panel="p", page=0)
    @test_throws ArgumentError pdf_ref("x", "/doc.pdf"; panel="p", hue=9)
    @test_throws ArgumentError pdf_ref("x", "/doc.pdf"; panel="p", hue=0)
    @test_throws ArgumentError pdf_ref("x", ""; panel="p")
    @test_throws ArgumentError pdf_ref("x", "/doc.pdf"; panel="")
    @test_throws ArgumentError pdf_ref("x", "/doc.pdf"; panel="p", quoted=12)
end

@testitem "pdf_panel: a closed panel in the page's language, HTML only" setup=[PdfFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    p = pdf_panel(["Konzept" => "/files/k.pdf#page=3", "/code/raw?path=docs/a%20b/plan.pdf"]; id="orig", assets=false)
    s = html(p)
    @test occursin(r"<aside id=\"orig\" class=\"htmxo-pdf-panel\" hidden", s)
    @test occursin("data-htmxo-pdf-viewer=\"\"", s) && occursin("data-htmxo-pdf-link=\"orig\"", s)   # its group is its id
    @test occursin("<label><input type=\"radio\" name=\"htmxo-pdf-document-orig\" value=\"/files/k.pdf\" checked=\"true\">Konzept</label>", s)
    @test occursin("value=\"/code/raw?path=docs/a%20b/plan.pdf\">plan.pdf</label>", s)               # named by its file
    @test occursin("href=\"/files/k.pdf\"", s)                                                       # "open file", the first
    @test occursin("aria-label=\"Document\"", s) && occursin("data-text-page=\"page {page} of {pages}\"", s)
    @test occursin("data-htmxo-pdfjs=\"https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/\"", s)
    @test !occursin("window.htmxoPdf", s)                                                            # assets=false
    @test occursin("window.htmxoPdf", html(pdf_panel(; id="x")))                                     # carried by default
    @test occursin("data-htmxo-pdf-link=\"crosswalk\"", html(pdf_panel(; id="x", link="crosswalk", pdfjs="/vendor/pdfjs")))
    @test occursin("data-htmxo-pdfjs=\"/vendor/pdfjs/\"", html(pdf_panel(; id="x", pdfjs="/vendor/pdfjs", assets=false)))
    @test occursin("<span class=\"htmxo-pdf-title\" data-htmxo-pdf-url=\"/one.pdf\">one.pdf</span>", html(pdf_panel("/one.pdf"; id="x", assets=false)))
    # Markdown leaves it out
    @test strip(to_markdown_string(h.div(h.p("Text"), p))) == "Text"
    # the page's language, or texts of one's own
    de = HTMXObjects._with_page_lang(() -> html(pdf_panel(; id="x", assets=false)), "de-DE")
    @test occursin("aria-label=\"Dokument\"", de) && occursin("data-text-page=\"Seite {page} von {pages}\"", de)
    @test occursin("aria-label=\"Document\"", HTMXObjects._with_page_lang(() -> html(pdf_panel(; id="x", assets=false)), "fr"))
    own = html(pdf_panel(; id="x", assets=false, texts=pdf_panel_texts(:de; label="Originale")))
    @test occursin("aria-label=\"Originale\"", own) && occursin(">Farben</button>", own)
    @test pdf_panel_texts(:de).not_found == "Die zitierten Worte stehen nicht auf dieser Seite"
    @test pdf_panel_texts(:de).search == "Suchen…" && pdf_panel_texts(:de).no_match == "Kein passendes Dokument"
    @test_throws ArgumentError pdf_panel_texts(:fr)
    @test_throws ArgumentError pdf_panel_texts(; page="Seite {seite}")
    @test_throws ArgumentError pdf_panel_texts(; label_typo="x")
    @test_throws ArgumentError pdf_panel(; id="x", texts=table_texts())
    @test_throws ArgumentError pdf_panel(["/a.pdf", "A" => "/a.pdf#page=2"]; id="x")                # listed twice
    @test_throws ArgumentError pdf_panel([42]; id="x")
    @test_throws ArgumentError pdf_panel(; id="")
end

@testitem "pdf_panel: the document chooser is never a native select box" setup=[PdfFixtures] tags=[:unit] begin
    # User rule (VerkehrsStrukturdaten:ux/decisions/2026-10-26T14-07-45-293-19mny0l, snag
    # pdf-panel-docume-fcc431e2): one document is its title, a few a row of pills, a long
    # list a searchable list; never a <select>.
    using HTMXObjects
    docs(n) = ["Document $i" => "/d$i.pdf" for i in 1:n]
    panel(n; kw...) = html(pdf_panel(docs(n); id="p", assets=false, kw...))
    chooser(s) = match(r"<div class=\"htmxo-pdf-documents\" data-htmxo-pdf-document=\"\" data-htmxo-pdf-pills=\"8\">(.*?)</div><div class=\"htmxo-pdf-controls\">"s, s)[1]
    @test all(n -> !occursin("<select", panel(n)) && !occursin("<option", panel(n)), 0:12)
    # none yet: an empty chooser, which a reference fills
    @test chooser(panel(0)) == ""
    # one: its title as text, carrying its address; no control
    one = html(pdf_panel(["Leistungsbeschreibung, Stand März 2026" => "/unterlagen/lb"]; id="p", link="g", assets=false))
    @test chooser(one) == "<span class=\"htmxo-pdf-title\" data-htmxo-pdf-url=\"/unterlagen/lb\">Leistungsbeschreibung, Stand März 2026</span>"
    @test !occursin("type=\"radio\"", one)
    # two to eight: radio_group's pills, named for the panel, the first chosen
    for n in (2, 8)
        c = chooser(panel(n))
        @test startswith(c, "<fieldset><legend>Documents</legend><label><input type=\"radio\" name=\"htmxo-pdf-document-p\" value=\"/d1.pdf\" checked=\"true\">Document 1</label>")
        @test count("type=\"radio\"", c) == n && count("checked", c) == 1 && !occursin("htmxo-choice", c)
    end
    # more: the searchable list, its field showing the first, its words the panel's
    many = chooser(panel(9))
    @test occursin("<fieldset class=\"htmxo-choice-list\" data-htmxo-choice-list=\"\"><legend>Documents</legend>", many)
    @test occursin("<span class=\"htmxo-choice-current\">Document 1</span>", many)
    @test occursin("placeholder=\"Search…\"", many) && occursin(">No matching document</p>", many)
    @test count("<input type=\"radio\" name=\"htmxo-pdf-document-p\"", many) == 9 && count("checked", many) == 1
    de = HTMXObjects._with_page_lang(() -> chooser(panel(9)), "de")
    @test occursin("<legend>Dokumente</legend>", de) && occursin("placeholder=\"Suchen…\"", de) && occursin(">Kein passendes Dokument</p>", de)
    own = chooser(panel(9; texts=pdf_panel_texts(; search="Find a file", no_match="None")))
    @test occursin("placeholder=\"Find a file\"", own) && occursin(">None</p>", own)
    # the words a reference's added document is drawn with
    s = panel(2)
    @test occursin("data-text-documents=\"Documents\"", s) && occursin("data-text-search=\"Search…\"", s) &&
          occursin("data-text-no-match=\"No matching document\"", s)
    # the controls stay together, the page line between its buttons
    @test occursin(r"<div class=\"htmxo-pdf-controls\"><span class=\"htmxo-pdf-pager\"><button type=\"button\" data-htmxo-pdf-step=\"-1\"[^>]*>‹</button><span class=\"htmxo-pdf-page-info\" data-htmxo-pdf-page-info=\"\"></span><button type=\"button\" data-htmxo-pdf-step=\"1\"[^>]*>›</button></span>", s)
end

@testitem "pdf_toggle and pdf_beside" setup=[PdfFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    t = html(pdf_toggle("orig"))
    @test occursin("data-htmxo-pdf-toggle=\"orig\"", t) && occursin("aria-controls=\"orig\"", t)
    @test occursin("aria-pressed=\"false\"", t) && occursin(">Document</button>", t)
    @test occursin(">Dokument</button>", HTMXObjects._with_page_lang(() -> html(pdf_toggle("orig")), "de"))
    @test occursin(">Originale</button>", html(pdf_toggle("orig", "Originale"; class="secondary")))
    @test strip(to_markdown_string(h.div(h.p("a"), pdf_toggle("orig")))) == "a"
    b = html(pdf_beside(h.p("content"), pdf_panel(; id="orig", assets=false)))
    @test occursin(r"^<div class=\"htmxo-pdf-beside\" data-htmxo-pdf-beside=\"\"><div class=\"htmxo-pdf-beside-content\"><p>content</p></div><aside id=\"orig\"", b)
end

@testitem "pdf_ref and pdf_panel take HTML documents: an anchor, no pages" setup=[PdfFixtures] tags=[:unit] begin
    # Snag pdf-panel-shows-b0bebb33: a cited brief section or code range is an
    # HTML fragment, shown in the same panel as the PDFs.
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    r = html(pdf_ref("(Methodik)", "/agents/a/briefs/b#annahmen"; kind=:html, panel="orig",
                     quoted="Fahrten je Zone folgen einer Poisson-Verteilung"))
    @test occursin("href=\"/agents/a/briefs/b#annahmen\"", r)             # the address as given, its anchor kept
    @test occursin("data-htmxo-pdf-url=\"/agents/a/briefs/b\"", r)         # the document: the address without it
    @test occursin("data-htmxo-pdf-kind=\"html\"", r) && occursin("data-htmxo-pdf-anchor=\"annahmen\"", r)
    @test !occursin("data-htmxo-pdf-page", r) && !occursin("#page=", r)
    key = match(r"data-htmxo-pdf-key=\"([^\"]+)\"", r)[1]
    # the anchor is part of the passage's key, as a PDF's page is
    @test !occursin(key, html(pdf_ref("x", "/agents/a/briefs/b#andere"; kind=:html, panel="orig",
                                      quoted="Fahrten je Zone folgen einer Poisson-Verteilung")))
    @test occursin(key, html(pdf_ref("x", "/agents/a/briefs/b#annahmen"; kind=:html, panel="orig",
                                     quoted="Fahrten je Zone folgen einer Poisson-Verteilung")))
    # no anchor: the document's top; a query stays part of the address
    code = html(pdf_ref("(L. 4–9)", "/code?path=src/m.jl&line=4-9"; kind=:html, panel="orig"))
    @test occursin("href=\"/code?path=src/m.jl&amp;line=4-9\"", code) && !occursin("data-htmxo-pdf-anchor", code)
    @test occursin("data-htmxo-pdf-document=\"m.jl\"", code)
    # a PDF reference is as before: its key does not change
    pdf = html(pdf_ref("(S. 12)", "/files/k.pdf"; page=12, panel="orig", quoted="Kinderschutz ist Aufgabe aller Träger"))
    @test occursin("href=\"/files/k.pdf#page=12\"", pdf) && !occursin("data-htmxo-pdf-kind", pdf)
    @test occursin("data-htmxo-pdf-key=\"$(HTMXObjects._thread_digest("/files/k.pdf#page=12\nKinderschutz ist Aufgabe aller Träger"))\"", pdf)
    @test occursin("href=\"/files/k.pdf#page=1\"", html(pdf_ref("x", "/files/k.pdf"; panel="orig", kind=:pdf)))
    @test strip(to_markdown_string(h.p("Siehe ", pdf_ref("Annahmen", "/m#a"; kind=:html, panel="p"), "."))) ==
          "Siehe [Annahmen](/m#a)."
    @test_throws ArgumentError pdf_ref("x", "/m#a"; kind=:html, panel="p", page=2)
    @test_throws ArgumentError pdf_ref("x", "/m"; kind=:word, panel="p")
    @test_throws ArgumentError pdf_ref("x", "/m.pdf"; panel="p", page=1.5)
    # the panel lists PDFs and HTML documents together; an HTML document says so
    one = html(pdf_panel((title="Methodik", url="/m#a", kind=:html); id="p", assets=false))
    @test occursin("<span class=\"htmxo-pdf-title\" data-htmxo-pdf-url=\"/m\" data-htmxo-pdf-kind=\"html\">Methodik</span>", one)
    @test occursin("data-text-not-in-document=\"The quoted words were not found in this document\"", one)
    pills = html(pdf_panel(["LB" => "/lb.pdf", (url="/plan.pdf",), (title="Methodik", url="/m", kind=:html)]; id="p", assets=false))
    @test occursin("value=\"/lb.pdf\" checked=\"true\">LB</label>", pills)
    @test occursin("value=\"/plan.pdf\">plan.pdf</label>", pills)                                     # a record, named by its file
    @test occursin("value=\"/m\" data-htmxo-pdf-kind=\"html\">Methodik</label>", pills)
    @test count("data-htmxo-pdf-kind", pills) == 1
    many = html(pdf_panel([i == 9 ? (title="Methodik", url="/m", kind=:html) : "/d$i.pdf" for i in 1:9]; id="p", assets=false))
    @test occursin("<input type=\"radio\" name=\"htmxo-pdf-document-p\" value=\"/m\" data-htmxo-pdf-kind=\"html\">", many)
    @test count("data-htmxo-pdf-kind", many) == 1
    @test pdf_panel_texts(:de).not_in_document == "Die zitierten Worte stehen nicht in diesem Dokument"
    @test_throws ArgumentError pdf_panel([(url="/m", kind=:word)]; id="p")
    @test_throws ArgumentError pdf_panel([(url="",)]; id="p")
    @test_throws ArgumentError pdf_panel([(url="/m", other=1)]; id="p")
    @test_throws ArgumentError pdf_panel([(url="/m", title=3)]; id="p")
    @test_throws ArgumentError pdf_panel(["/m", (url="/m#x", kind=:html)]; id="p")                  # listed twice
end

@testitem "pdf_panel in a static export loads the files the export wrote" setup=[PdfFixtures] tags=[:unit] begin
    # Snag pdf-panel-static-81f73b0d (ODLPlaus:review): export_site rewrote a
    # reference's href, but its data-htmxo-pdf-url, the lone document's and the
    # chooser's radio values kept the live address, so the exported panel fetched
    # /unterlagen/lb (a 404 outside the bundle) and said the PDF was missing.
    using HTMXObjects, Treebars
    route!(PdfExportApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"])
    for f in ("pdfx_datei-lb.pdf", "pdfx_datei-anlage.pdf", "pdfx_datei-teil1.pdf", "pdfx_datei-teil9.pdf",
              "pdfx_pills.html", "pdfx_list.html")
        @test isfile(joinpath(dir, f))
    end
    @test read(joinpath(dir, "pdfx_datei-lb.pdf")) == PDF3
    index = read(joinpath(dir, "index.html"), String)
    tag(s, id) = match(Regex("<a [^>]*id=\"$id\"[^>]*>"), s).match
    # a reference: its link and its file name the written file
    r3 = tag(index, "r3")
    @test occursin("href=\"pdfx_datei-lb.pdf#page=3\"", r3) && occursin("data-htmxo-pdf-url=\"pdfx_datei-lb.pdf\"", r3)
    # a file the panel does not list keeps the title the live page gives it
    r2 = tag(index, "r2")
    @test occursin("data-htmxo-pdf-url=\"pdfx_datei-anlage.pdf\"", r2) && occursin("data-htmxo-pdf-document=\"anlage\"", r2)
    # the lone document and the "open file" link
    @test occursin("<span class=\"htmxo-pdf-title\" data-htmxo-pdf-url=\"pdfx_datei-lb.pdf\">Leistungsbeschreibung</span>", index)
    @test occursin(r"<a [^>]*data-htmxo-pdf-file=\"\"[^>]*>", index) &&
          occursin("href=\"pdfx_datei-lb.pdf\"", match(r"<a [^>]*data-htmxo-pdf-file=\"\"[^>]*>", index).match)
    # pills and a searchable list: each document's radio names its written file
    pills = read(joinpath(dir, "pdfx_pills.html"), String)
    @test occursin("value=\"pdfx_datei-lb.pdf\" checked=\"true\">LB</label>", pills)
    @test occursin("value=\"pdfx_datei-anlage.pdf\">Anlage</label>", pills)
    list = read(joinpath(dir, "pdfx_list.html"), String)
    @test count(r"<input type=\"radio\" name=\"htmxo-pdf-document-list\" value=\"pdfx_datei-teil\d\.pdf\"", list) == 9
    # an HTML document: the panel loads the fragment the export wrote below hx/,
    # the reference's link names the page (snag pdf-panel-shows-b0bebb33)
    rh = tag(index, "rh")
    @test occursin("data-htmxo-pdf-url=\"hx/pdfx_text.html\"", rh) && occursin("href=\"pdfx_text.html#methodik\"", rh)
    @test occursin("data-htmxo-pdf-kind=\"html\"", rh)
    fragment = read(joinpath(dir, "hx", "pdfx_text.html"), String)
    @test occursin("<h2 id=\"methodik\">Methodik</h2>", fragment) && !occursin("<html", fragment)
    @test occursin("<html", read(joinpath(dir, "pdfx_text.html"), String))
    @test occursin("value=\"hx/pdfx_text.html\" data-htmxo-pdf-kind=\"html\">Text</label>", pills)
    @test "hx/pdfx_text.html" in HTMXObjects._site_references(index)
    # no panel is left with an address of the live app
    for page in (index, pills, list)
        @test !occursin("data-htmxo-pdf-url=\"/", page) && !occursin("value=\"/pdfx", page)
    end
    # the reference check reads a panel's addresses, so one that escaped the walk fails the export
    @test "pdfx_datei-lb.pdf" in HTMXObjects._site_references(index)
    @test HTMXObjects._site_references("<span data-htmxo-pdf-url=\"/x\">x</span>") == ["/x"]
    # a request-scoped export puts its record_base before them, as before a link
    spec = StaticExport(; record_base="/odl")
    page = String(dispatch(:GET, "/"; static=spec).body)
    @test occursin("data-htmxo-pdf-url=\"/odl/pdfx_datei/lb\"", tag(page, "r3")) &&
          occursin("href=\"/odl/pdfx_datei/lb#page=3\"", tag(page, "r3"))
    @test occursin("data-htmxo-pdf-url=\"/odl/pdfx_datei/lb\">Leistungsbeschreibung</span>", page)
    @test occursin("value=\"/odl/pdfx_datei/anlage\">Anlage</label>",
                   String(dispatch(:GET, "/pdfx_pills"; static=spec).body))
    @test occursin("data-htmxo-pdf-url=\"/odl/hx/pdfx_text\"", tag(page, "rh")) &&
          occursin("href=\"/odl/pdfx_text#methodik\"", tag(page, "rh"))
    @test occursin("value=\"/odl/hx/pdfx_text\" data-htmxo-pdf-kind=\"html\">Text</label>",
                   String(dispatch(:GET, "/pdfx_pills"; static=spec).body))
    # the live page keeps the app's addresses
    live = String(dispatch(:GET, "/").body)
    @test occursin("data-htmxo-pdf-url=\"/pdfx_datei/lb\">Leistungsbeschreibung</span>", live)
    @test occursin("data-htmxo-pdf-url=\"/pdfx_datei/anlage\"", tag(live, "r2"))
    @test occursin("value=\"/pdfx_datei/anlage\">Anlage</label>", String(dispatch(:GET, "/pdfx_pills").body))
end

@testitem "pdf_panel browser: an exported panel served from a subdirectory shows the files the export wrote" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    # Snag pdf-panel-static-81f73b0d: served from /odl/, the exported panel
    # fetched the live /unterlagen/lb outside the bundle and showed no page.
    using HTMXObjects, HTTP, Sockets, Treebars
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        route!(PdfExportApp())
        vendorfiles()
        dir = joinpath(mktempdir(), "site")
        export_site(dir; pages=["/"])
        driver = raw"""<script>
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok, seen) => checks.push([ok ? name : name + ' ' + JSON.stringify(seen), Boolean(ok)]);
            const tick = () => fetch('/tick').then(r => r.text());
            const wait = async (cond, n = 400) => { for (let i = 0; i < n && !cond(); i++) await tick(); return cond(); };
            const aside = document.getElementById('orig'), view = aside.querySelector('[data-htmxo-pdf-pages]');
            const line = () => aside.querySelector('[data-htmxo-pdf-page-info]').textContent;
            const note = () => aside.querySelector('[data-htmxo-pdf-note]').textContent;
            const href = () => aside.querySelector('[data-htmxo-pdf-file]').getAttribute('href');
            const page = n => aside.querySelector('.htmxo-pdf-page[data-htmxo-pdf-page="' + n + '"]');
            const drawn = n => page(n) && page(n).hasAttribute('data-htmxo-pdf-drawn');
            const busy = () => view.getAttribute('aria-busy') === 'true';
            const shown = () => aside.htmxoPdfFile && aside.htmxoPdfFile.url;
            const radios = () => aside.querySelectorAll('[data-htmxo-pdf-document] input[type="radio"]');
            const radio = url => aside.querySelector('[data-htmxo-pdf-document] input[value="' + url + '"]');
            const seen = () => ({line: line(), note: note(), href: href(), busy: busy(), shown: shown(),
                                 hidden: aside.hidden, radios: Array.from(radios(), r => r.value)});
            const settled = (url, n) => wait(() => !busy() && shown() === url && drawn(n) && line() === 'page ' + n + ' of 3');
            try {
                // the toggle opens the lone document: the file the export wrote
                document.getElementById('toggle').click();
                await settled('pdfx_datei-lb.pdf', 1);
                check('toggle-shows-written-file', !aside.hidden && shown() === 'pdfx_datei-lb.pdf' &&
                      line() === 'page 1 of 3' && note() === '', seen());
                // a reference goes to its passage in that file, and marks it
                document.getElementById('r3').click();
                await settled('pdfx_datei-lb.pdf', 3);
                await wait(() => aside.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-active]'));
                check('ref-marks-passage', line() === 'page 3 of 3' && href() === 'pdfx_datei-lb.pdf#page=3' &&
                      aside.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-active]'), seen());
                // a reference to a file the panel does not list adds it, titled as the live page titles it
                document.getElementById('r2').click();
                await settled('pdfx_datei-anlage.pdf', 2);
                const added = radio('pdfx_datei-anlage.pdf');
                check('unlisted-added', radios().length === 2 && added && added.checked &&
                      added.closest('label').textContent.trim() === 'anlage', seen());
                // the first document's pill: the same file, not a second entry for it
                radio('pdfx_datei-lb.pdf').closest('label').click();
                await settled('pdfx_datei-lb.pdf', 1);
                check('pill-back', radios().length === 2 && radio('pdfx_datei-lb.pdf').checked && note() === '', seen());
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        </script>"""
        index = joinpath(dir, "index.html")
        write(index, replace(read(index, String), "</body>" => driver * "</body>"))
        types = Dict(".html" => "text/html; charset=utf-8", ".js" => "text/javascript", ".css" => "text/css",
                     ".pdf" => "application/pdf", ".woff2" => "font/woff2", ".svg" => "image/svg+xml")
        requested = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        # The bundle below /odl/, as a static server holds it; nothing else is there.
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.unescapeuri(HTTP.URI(req.target).path)
            path == "/tick" && return (sleep(0.05); HTTP.Response(200, "ok"))
            push!(requested, path)
            file = startswith(path, "/odl/") ? joinpath(dir, path[6:end]) : ""
            isfile(file) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => get(types, last(splitext(file)), "application/octet-stream")], read(file))
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=120000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/odl/index.html`; timeout=180)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel export browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 4
            end
            # every file the page asked for is in the bundle, the PDFs among them
            outside = filter(p -> !startswith(p, "/odl/") && p != "/favicon.ico", requested)
            @test isempty(outside)
            isempty(outside) || println("pdf_panel export browser: requests outside the bundle: ", outside)
            @test "/odl/pdfx_datei-lb.pdf" in requested && "/odl/pdfx_datei-anlage.pdf" in requested
        finally
            close(server)
        end
    end
end

@testitem "pdf_panel browser: hover lights, only a click moves" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        pdf = tiny_pdf(PDF_PAGES)
        ref(id, text; kw...) = pdf_ref(text, "/doc.pdf"; panel="orig", id, kw...)
        two_lines = "every provider and of everyone who works with children"
        content = h.div(; id="content")(
            h.p(ref("a", "(p. 1)"; page=1, quoted=two_lines), " Child protection is everyone's task."),
            h.p("Reports go to the youth office ", ref("b", "(p. 2)"; page=2, quoted="reported to the youth office"), "."),
            h.p("As above ", ref("c", "(ibid.)"; page=1, quoted=two_lines), "; ",
                ref("d", "(missing)"; page=2, quoted="This sentence is not in the document at all"), "; ",
                ref("e", "the reporting page"; page=2), "; ",
                pdf_ref("elsewhere", "/doc.pdf"; panel="nowhere", id="nowhere", quoted="words that are elsewhere")),
            # a row of a linked table: the row names the passage, its reference does not
            sortable_table(["Requirement"], [h.tr(h.td(ref("row-ref", "LB 2"; page=2, key="req-1",
                    quoted="The report names the facts observed")); data_htmxo_link_key="req-1", id="row")];
                link="orig-link", id="reqs"),
            h.template(; id="late")(ref("f", "(late)"; page=1, quoted="Other text on the first page")),
            h.div(; style="height: 3000px"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            // Each wait asks the server, which answers after 50 ms: Chrome's
            // virtual clock cannot outrun PDF.js's real work.
            const tick = () => fetch('/tick').then(r => r.text());
            const wait = async (cond, n = 400) => { for (let i = 0; i < n && !cond(); i++) await tick(); return cond(); };
            const events = [], gotos = [];
            document.addEventListener('htmxo:link', e => events.push(e.detail));
            document.addEventListener('htmxo:pdf-goto', e => gotos.push(e.detail.key));
            const aside = document.getElementById('orig'), beside = aside.closest('[data-htmxo-pdf-beside]');
            const ref = id => document.getElementById(id), key = id => ref(id).dataset.htmxoPdfKey;
            const hits = k => [...aside.querySelectorAll('.htmxo-pdf-hit')].filter(x => x.dataset.htmxoPdfKey === k);
            const lit = el => el.hasAttribute('data-htmxo-pdf-lit'), active = el => el.hasAttribute('data-htmxo-pdf-active');
            const over = (el, from) => el.dispatchEvent(new PointerEvent('pointerover', {bubbles: true, relatedTarget: from || null}));
            const note = () => aside.querySelector('[data-htmxo-pdf-note]').textContent;
            const pageLine = () => aside.querySelector('[data-htmxo-pdf-page-info]').textContent;
            const inPanel = el => { const a = aside.getBoundingClientRect(), r = el.getBoundingClientRect(); return r.top >= a.top && r.bottom <= a.bottom; };
            const unmodified = el => new Promise(ok => {   // whether the panel took a click on `el`
                el.addEventListener('click', e => { ok(e.defaultPrevented); e.preventDefault(); }, {once: true});
            });
            try {
                // closed at first; every reference lightly highlighted
                check('closed', aside.hidden && !beside.hasAttribute('data-htmxo-pdf-open'));
                check('toggle-unpressed', ref('toggle').getAttribute('aria-pressed') === 'false');
                check('chip-tinted', getComputedStyle(ref('a')).backgroundColor !== 'rgba(0, 0, 0, 0)');
                check('same-passage-same-key', key('a') === key('c') && key('a') !== key('b'));
                // pointing at a reference lights it and its twin; nothing opens or scrolls
                const y0 = scrollY;
                over(ref('a'));
                const said = events[events.length - 1];
                check('hover-announces', said && said.group === 'orig-link' && said.keys.join() === key('a') && said.source === ref('a'));
                check('hover-lights-twin', lit(ref('c')) && !lit(ref('b')));
                check('hover-no-open', aside.hidden && scrollY === y0);
                over(document.body, ref('a'));
                check('hover-ends', !lit(ref('c')) && events[events.length - 1].keys.length === 0);
                // a click opens the panel beside the text at the passage, marked most strongly,
                // the reference staying where it was on screen
                const before = ref('b').getBoundingClientRect().top;
                ref('b').click();
                check('opened', !aside.hidden && beside.hasAttribute('data-htmxo-pdf-open') && ref('toggle').getAttribute('aria-pressed') === 'true');
                check('held', Math.abs(ref('b').getBoundingClientRect().top - before) < 2);
                check('beside', aside.getBoundingClientRect().left >= ref('content').getBoundingClientRect().right);
                await wait(() => hits(key('b')).some(active) && pageLine() !== '' &&
                    aside.querySelector('.htmxo-pdf-page[data-htmxo-pdf-page="2"][data-htmxo-pdf-drawn]'));
                check('b-marked', hits(key('b')).length === 1 && active(hits(key('b'))[0]) && active(ref('b')));
                const page2 = aside.querySelector('.htmxo-pdf-page[data-htmxo-pdf-page="2"]');
                check('b-part-of-its-line', hits(key('b'))[0].getBoundingClientRect().width < 0.5 * page2.getBoundingClientRect().width);
                check('b-in-view', inPanel(hits(key('b'))[0]));
                check('page-line', pageLine() === 'page 2 of 2');
                check('note-empty', note() === '');
                check('two-pages', aside.querySelectorAll('.htmxo-pdf-page').length === 2);
                // another reference to the file keeps its pages laid out as they are
                const laidOut = aside.querySelector('.htmxo-pdf-page');
                ref('b').click();
                await wait(() => pageLine() === 'page 2 of 2' && hits(key('b')).some(active));
                for (let i = 0; i < 6; i++) await tick();   // a new layout would have replaced the pages by now
                check('no-relayout', aside.querySelector('.htmxo-pdf-page') === laidOut);
                // a's passage on page 1: one mark for both references, over two lines, in their colour
                await wait(() => hits(key('a')).length > 0);
                check('a-two-lines', hits(key('a')).length === 2);
                check('a-colour', hits(key('a'))[0].dataset.htmxoPdfHue === ref('a').dataset.htmxoPdfHue);
                // pointing at a reference while open lights its mark and scrolls nothing, even after a pause
                const s0 = aside.scrollTop, y1 = scrollY;
                over(ref('a'));
                check('hover-lights-mark', hits(key('a')).every(lit));
                for (let i = 0; i < 8; i++) await tick();
                check('hover-no-scroll', aside.scrollTop === s0 && scrollY === y1);
                over(document.body, ref('a'));
                check('hover-mark-ends', !hits(key('a')).some(lit));
                // pointing at a mark lights its references and scrolls nothing
                hits(key('a'))[0].dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
                check('mark-lights-refs', lit(ref('a')) && lit(ref('c')) && !lit(ref('b')));
                check('mark-hover-no-scroll', aside.scrollTop === s0 && scrollY === y1);
                aside.dispatchEvent(new MouseEvent('mouseleave'));
                check('mark-hover-ends', !lit(ref('a')));
                // a linked table row lights the passage keyed like it; its reference says nothing itself
                await wait(() => hits('req-1').length > 0);
                const n0 = events.length;
                over(ref('row-ref'));
                const fromRow = events.slice(n0);
                check('row-lights-mark', hits('req-1').length === 1 && lit(hits('req-1')[0]) && lit(ref('row-ref')));
                check('row-speaks-once', fromRow.length === 1 && fromRow[0].source === ref('row'));
                over(document.body, ref('row-ref'));
                // pointing at the passage lights the row; a click on it, its reference in view, scrolls nothing
                scrollTo(0, 0);
                await tick();
                hits('req-1')[0].dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
                check('mark-lights-row', ref('row').dataset.htmxoLinked === '' && lit(ref('row-ref')));
                hits('req-1')[0].click();
                check('mark-click-stays', scrollY === 0 && ref('row-ref').hasAttribute('data-htmxo-pdf-flash') && ref('row').dataset.htmxoLinked === '');
                aside.dispatchEvent(new MouseEvent('mouseleave'));
                check('mark-row-ends', !('htmxoLinked' in ref('row').dataset));
                // the panel stays in view while the page scrolls by
                scrollTo(0, document.body.scrollHeight);
                await tick();
                const top = aside.getBoundingClientRect().top;
                check('sticky', top >= 0 && top < 40 && aside.getBoundingClientRect().bottom <= innerHeight + 1);
                // a click on a mark goes to its reference, flashed
                hits(key('a'))[0].click();
                const r = ref('a').getBoundingClientRect();
                check('mark-goes', r.top >= 0 && r.bottom <= innerHeight && ref('a').hasAttribute('data-htmxo-pdf-flash'));
                check('goto-event', gotos.join() === 'req-1,' + key('a'));
                check('mark-gone-to', hits(key('a')).every(active) && !active(hits(key('b'))[0]));
                // quoted words the page lacks: the page's top, and the note says so
                ref('d').click();
                await wait(() => note() === 'The quoted words were not found on this page');
                check('not-found', note() === 'The quoted words were not found on this page');
                // a reference without quoted words: its page's top, no note, no passage gone to
                ref('e').click();
                await wait(() => note() === '');
                check('page-ref', note() === '' && !aside.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-active]'));
                // a reference that arrives later is marked on the page drawn
                ref('a').click();
                await wait(() => hits(key('a')).some(active) && pageLine() === 'page 1 of 2');
                const late = document.getElementById('late').content.firstElementChild.cloneNode(true);
                ref('content').appendChild(late);
                late.dispatchEvent(new CustomEvent('htmx:load', {bubbles: true}));
                await wait(() => hits(key('f')).length > 0);
                check('late-marked', hits(key('f')).length === 1);
                if (!hits(key('f')).length) check('late-debug ' + JSON.stringify({tasks: aside.htmxoPdfFile.boxes.map(e => !!e.task),
                    drawn: aside.htmxoPdfFile.boxes.map(e => Object.keys(e.drawn)), f: key('f'), url: ref('f').dataset.htmxoPdfUrl,
                    refs: document.querySelectorAll('[data-htmxo-pdf-panel="orig"]').length, hits: aside.querySelectorAll('.htmxo-pdf-hit').length}), false);
                // colours off: only the passages pointed at and gone to show
                aside.querySelector('[data-htmxo-pdf-colours]').click();
                check('colours-off', aside.dataset.htmxoPdfHues === 'off' && getComputedStyle(hits(key('f'))[0]).visibility === 'hidden' &&
                    getComputedStyle(hits(key('a'))[0]).visibility === 'visible');
                aside.querySelector('[data-htmxo-pdf-colours]').click();
                check('colours-on', getComputedStyle(hits(key('f'))[0]).visibility === 'visible');
                // the bar's next page
                aside.querySelector('[data-htmxo-pdf-step="1"]').click();
                check('step', pageLine() === 'page 2 of 2');
                // a modified click, and a reference whose panel is not on the page, open the file itself
                const ctrl = unmodified(ref('b'));
                ref('b').dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ctrlKey: true}));
                check('modified-click-own', !(await ctrl) && !active(ref('b')));
                const lone = unmodified(ref('nowhere'));
                ref('nowhere').click();
                check('no-panel-own', !(await lone));
                // closed: the content has the whole width, nothing gone to
                aside.querySelector('[data-htmxo-pdf-close]').click();
                check('closed-again', aside.hidden && !beside.hasAttribute('data-htmxo-pdf-open') &&
                    ref('toggle').getAttribute('aria-pressed') === 'false' && !active(ref('a')));
                // the toggle opens it as it was
                ref('toggle').click();
                check('reopened', !aside.hidden && aside.querySelectorAll('.htmxo-pdf-page').length === 2 && ref('toggle').getAttribute('aria-pressed') === 'true');
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(pdf_toggle("orig"; id="toggle"),
                pdf_beside(content, pdf_panel(["Fixture" => "/doc.pdf"]; id="orig", link="orig-link"))), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page) :
            path == "/doc.pdf" ? HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf) :
            path == "/tick" ? (sleep(0.05); HTTP.Response(200, "ok")) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=120000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=180)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 45
            end
        finally
            close(server)
        end
    end
end

@testitem "pdf_panel browser: the document chooser grows from a title to pills to a searchable list" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    # Snag pdf-panel-docume-fcc431e2: never a native select box (user rule
    # VerkehrsStrukturdaten:ux/decisions/2026-10-26T14-07-45-293-19mny0l).
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        pdf = tiny_pdf(PDF_PAGES)
        long = "Leistungsbeschreibung, Stand März 2026, mit allen Anlagen, Nachträgen und Antworten auf die Bieterfragen"
        content = h.div(; id="content")(
            h.p(pdf_toggle("one"; id="tone"), " ", pdf_ref("(Konzept)", "/b.pdf"; panel="one", id="rb", document="Konzept")),
            h.p(pdf_ref("(Ninth)", "/d9.pdf"; panel="eight", id="r9", document="Ninth"), " ",
                pdf_ref("(Later)", "/m13.pdf"; panel="many", id="r13")),
            h.div(; style="height: 1500px"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const LONG = document.getElementById('long').textContent;
            const panel = id => document.getElementById(id), ref = id => document.getElementById(id);
            const box = id => panel(id).querySelector('[data-htmxo-pdf-document]');
            const radios = id => [...box(id).querySelectorAll('input[type="radio"]')];
            const checkedUrl = id => (radios(id).find(r => r.checked) || {}).value;
            const shown = id => panel(id).htmxoPdfFile && panel(id).htmxoPdfFile.url;
            const field = id => box(id).querySelector('.htmxo-choice-current').textContent;
            const titles = id => radios(id).map(r => r.closest('label').textContent.trim());
            const oneLine = id => { const bar = panel(id).querySelector('.htmxo-pdf-bar');
                const a = bar.querySelector('[data-htmxo-pdf-step="-1"]').getBoundingClientRect();
                const b = bar.querySelector('[data-htmxo-pdf-step="1"]').getBoundingClientRect();
                return Math.abs(a.top - b.top) < 2 && bar.scrollWidth <= bar.clientWidth + 1; };
            try {
                check('no-select', document.querySelectorAll('select').length === 0);
                // one document: its title, no control; the toggle opens it
                const title = box('one').querySelector('.htmxo-pdf-title');
                check('one-title', title && title.textContent === LONG && radios('one').length === 0);
                ref('tone').click();
                check('one-opens', !panel('one').hidden && shown('one') === '/a.pdf');
                check('one-fits', oneLine('one') && title.scrollWidth <= title.clientWidth + 1);
                // a reference to a file not listed: a row of pills, the new file chosen
                ref('rb').click();
                check('one-to-pills', radios('one').length === 2 && box('one').querySelector('fieldset > legend').textContent === 'Documents' &&
                    checkedUrl('one') === '/b.pdf' && shown('one') === '/b.pdf');
                check('pill-titles', titles('one').join('|') === LONG + '|Konzept');
                const pill = radios('one')[1].closest('label');
                check('pill-look', getComputedStyle(pill).borderTopLeftRadius !== '0px' && getComputedStyle(radios('one')[1]).opacity === '0');
                check('pills-fit', oneLine('one'));
                // a pill's click shows its document
                radios('one')[0].closest('label').click();
                check('pill-chooses', checkedUrl('one') === '/a.pdf' && shown('one') === '/a.pdf');
                // eight documents are pills; a ninth makes them a searchable list
                check('eight-pills', radios('eight').length === 8 && !box('eight').querySelector('.htmxo-choice-list'));
                ref('r9').click();
                check('eight-to-list', box('eight').querySelector('.htmxo-choice-list') && radios('eight').length === 9 &&
                    checkedUrl('eight') === '/d9.pdf' && field('eight') === 'Ninth' && shown('eight') === '/d9.pdf');
                const list = box('eight').querySelector('.htmxo-choice-panel');
                box('eight').querySelector('.htmxo-choice-field').click();
                check('list-opens', list.matches(':popover-open'));
                const search = list.querySelector('.htmxo-choice-search');
                search.value = 'D3';
                search.dispatchEvent(new Event('input', {bubbles: true}));
                check('list-filters', [...list.querySelectorAll('.htmxo-choice-option')].filter(o => !o.classList.contains('htmxo-choice-out')).length === 1);
                search.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', bubbles: true, cancelable: true}));
                check('list-chooses', checkedUrl('eight') === '/d3.pdf' && shown('eight') === '/d3.pdf' && field('eight') === 'D3' &&
                    !list.matches(':popover-open'));
                // a list drawn by the server: a row's click shows its document; a reference adds a row
                box('many').querySelector('.htmxo-choice-field').click();
                box('many').querySelector('input[value="/m5.pdf"]').closest('label').click();
                check('many-chooses', checkedUrl('many') === '/m5.pdf' && shown('many') === '/m5.pdf' && field('many') === 'Many 5');
                ref('r13').click();
                check('many-adds-row', radios('many').length === 13 && checkedUrl('many') === '/m13.pdf' && field('many') === 'm13.pdf' &&
                    shown('many') === '/m13.pdf');
                // each panel keeps its own choice
                check('own-choice', checkedUrl('one') === '/a.pdf' && checkedUrl('eight') === '/d3.pdf');
                check('still-no-select', document.querySelectorAll('select').length === 0);
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(h.div(; id="long", hidden=true)(long),
                pdf_beside(content, pdf_panel([long => "/a.pdf"]; id="one")),
                pdf_panel(["D$i" => "/d$i.pdf" for i in 1:8]; id="eight"),
                pdf_panel(["Many $i" => "/m$i.pdf" for i in 1:12]; id="many")), driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page) :
            endswith(path, ".pdf") ? HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=120)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel chooser browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 18
            end
        finally
            close(server)
        end
    end
end

@testitem "pdf_panel browser: a document chosen in the chooser opens at its first page" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    # Snag pdf-panel-choose-708af86e (TenderViews): after a pill's click the
    # panel went on showing the other file's pages and page line ("page 3 of
    # 3") under the new file's name until the new file had loaded, so the
    # page read depended on how fast it loaded.
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        pdf = tiny_pdf([PDF_PAGES; [["Section 3: Records",
                                     "Every report is kept for ten years in the provider's records."]]])
        content = h.div(; id="content")(
            h.p("Records ", pdf_ref("(LB, p. 3)", "/lb.pdf"; page=3, panel="orig", id="r3",
                                    quoted="kept for ten years in the provider's records"), "."),
            h.p("Reports ", pdf_ref("(LB 2, p. 2)", "/lb2.pdf"; page=2, panel="orig", id="r2",
                                    quoted="reported to the youth office"), "."),
            h.div(; style="height: 1500px"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok, seen) => checks.push([ok ? name : name + ' ' + JSON.stringify(seen), Boolean(ok)]);
            const tick = () => fetch('/tick').then(r => r.text());
            const wait = async (cond, n = 400) => { for (let i = 0; i < n && !cond(); i++) await tick(); return cond(); };
            const aside = document.getElementById('orig'), view = aside.querySelector('[data-htmxo-pdf-pages]');
            const line = () => aside.querySelector('[data-htmxo-pdf-page-info]').textContent;
            const href = () => aside.querySelector('[data-htmxo-pdf-file]').getAttribute('href');
            const page = n => aside.querySelector('.htmxo-pdf-page[data-htmxo-pdf-page="' + n + '"]');
            const drawn = n => page(n) && page(n).hasAttribute('data-htmxo-pdf-drawn');
            const busy = () => view.getAttribute('aria-busy') === 'true';
            const radio = url => aside.querySelector('[data-htmxo-pdf-document] input[value="' + url + '"]');
            const shown = () => aside.htmxoPdfFile && aside.htmxoPdfFile.url;
            // page n's top in the panel's upper third: the panel is at that page
            const at = n => { const top = page(n).getBoundingClientRect().top - aside.getBoundingClientRect().top;
                              return top >= 0 && top < aside.clientHeight / 3; };
            const seen = () => ({line: line(), href: href(), busy: busy(), pages: view.children.length,
                                 scrollTop: aside.scrollTop, shown: shown(), drawn1: drawn(1)});
            const settled = (url, n) => wait(() => !busy() && shown() === url && drawn(n) && line() === 'page ' + n + ' of 3');
            try {
                // the first file, gone to its third page by a reference
                document.getElementById('r3').click();
                await settled('/lb.pdf', 3);
                check('lb-page-3', line() === 'page 3 of 3' && at(3) && aside.scrollTop > 0 && drawn(1), seen());
                // the other file's pill: at once the old pages, page line and place are gone
                radio('/lb2.pdf').closest('label').click();
                check('switch-at-once', radio('/lb2.pdf').checked && href() === '/lb2.pdf#page=1' && line() === '' &&
                    view.children.length === 0 && aside.scrollTop === 0 && busy(), seen());
                // what the reporter waited for holds only once the new file is shown, at page 1
                await wait(() => href() === '/lb2.pdf#page=1' && line().startsWith('page') && drawn(1));
                check('reporter-wait', line() === 'page 1 of 3' && shown() === '/lb2.pdf' && !busy(), seen());
                await settled('/lb2.pdf', 1);
                check('lb2-first-page', at(1) && !busy(), seen());
                // back to the first file: its first page, not the third it was at
                radio('/lb.pdf').closest('label').click();
                check('back-at-once', line() === '' && view.children.length === 0 && busy(), seen());
                await settled('/lb.pdf', 1);
                check('lb-first-page', at(1) && radio('/lb.pdf').checked, seen());
                // a reference to the other file goes to its own page
                document.getElementById('r2').click();
                await settled('/lb2.pdf', 2);
                await wait(() => aside.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-active]'));
                check('ref-own-page', line() === 'page 2 of 3' && aside.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-active]'), seen());
                check('ref-chooses', radio('/lb2.pdf').checked && href() === '/lb2.pdf#page=2', seen());
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(pdf_beside(content,
                pdf_panel(["LB" => "/lb.pdf", "LB 2" => "/lb2.pdf"]; id="orig"))), driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page) :
            path == "/lb.pdf" ? HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf) :
            # the other file takes a while: the switch is seen before it is shown
            path == "/lb2.pdf" ? (sleep(1); HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf)) :
            path == "/tick" ? (sleep(0.05); HTTP.Response(200, "ok")) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=120000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=180)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel switch browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 8
            end
        finally
            close(server)
        end
    end
end

@testitem "pdf_panel browser: opening and closing keep the reference in place" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        pdf = tiny_pdf(PDF_PAGES)
        # Rows that wrap anew when the table narrows or widens, under the
        # table's sticky control line and header.
        words = "Every provider makes sure that everyone who works with children in its care knows these requirements"
        rows = [h.tr(h.td("Requirement $i"),
                     h.td(repeat(words * " ", 1 + i % 3),
                          pdf_ref("(p. $(1 + i % 2))", "/doc.pdf"; page=1 + i % 2, panel="orig", id="ref-$i",
                                  quoted=isodd(i) ? "reported to the youth office" : "the task of every provider")),
                     h.td(repeat("The offer meets it. ", 1 + (i + 1) % 4)))
                for i in 1:60]
        content = h.div(; id="content")(sortable_table(["Requirement", "Text", "Offer"], rows; id="reqs"),
                                        h.div(; style="height: 1500px"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok, seen) => checks.push([ok ? name : name + ' ' + JSON.stringify(seen), Boolean(ok)]);
            const tick = () => fetch('/tick').then(r => r.text());
            const wait = async (cond, n = 400) => { for (let i = 0; i < n && !cond(); i++) await tick(); return cond(); };
            const aside = document.getElementById('orig');
            const top = el => el.getBoundingClientRect().top;
            const columns = () => [...document.querySelectorAll('colgroup[data-htmxo-columns] > col')].map(c => c.style.width).join();
            // `act`, then where `el` is at once and once the table has sized its columns for its new width
            async function kept(name, el, act) {
                const before = top(el), held = columns();
                act();
                const now = top(el);
                for (let i = 0; i < 8; i++) await tick();
                const settled = top(el);
                check(name + '-at-once', Math.abs(now - before) < 1, {before, now});
                check(name + '-settled', Math.abs(settled - before) < 1, {before, settled});
                check(name + '-wrapped-anew', columns() !== held, {held});   // the content did move under it
            }
            try {
                await wait(() => columns() !== '');
                // a reference clicked in the middle of the window stays there, opening and closing
                const ref = document.getElementById('ref-30');
                ref.closest('tr').scrollIntoView({block: 'center'});
                await tick();
                await kept('open', ref, () => ref.click());
                await wait(() => aside.querySelector('.htmxo-pdf-page[data-htmxo-pdf-drawn]'));
                aside.querySelector('[data-htmxo-pdf-step="1"]').click();
                await tick();
                await kept('close', ref, () => aside.querySelector('[data-htmxo-pdf-close]').click());
                check('closed', aside.hidden);
                // the toggle: the first row shown below the table's sticky header stays
                scrollBy(0, 300);
                await tick();
                const x = document.getElementById('content').getBoundingClientRect().left + 24;
                check('header-stuck', document.elementFromPoint(x, 4).closest('thead, .htmxo-table-toolbar'));
                let cell = null;
                for (let y = 4; !cell && y < innerHeight; y += 4) cell = document.elementFromPoint(x, y).closest('tbody td');
                await kept('toggle-open', cell, () => document.getElementById('toggle').click());
                await kept('toggle-close', cell, () => document.getElementById('toggle').click());
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(pdf_toggle("orig"; id="toggle"),
                pdf_beside(content, pdf_panel(["Fixture" => "/doc.pdf"]; id="orig"))), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page) :
            path == "/doc.pdf" ? HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf) :
            path == "/tick" ? (sleep(0.05); HTTP.Response(200, "ok")) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1200 --virtual-time-budget=120000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=180)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel keep browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 14
            end
        finally
            close(server)
        end
    end
end

@testitem "pdf_panel browser: an HTML document beside the text, its passages marked over its words" setup=[PdfFixtures, ChromeDump] tags=[:unit, :browser] begin
    # Snag pdf-panel-shows-b0bebb33: a cited brief section or code range (an HTML
    # fragment) opens in the same panel as the PDFs, under the same reader rule.
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        pdf = tiny_pdf(PDF_PAGES)
        # The fragment its address answers an htmx GET with; a plain GET gets a full page.
        brief = """
            <article>
            <h2 id="intro">Introduction</h2>
            <p id="p-early">The zones are counted once a year by the office.</p>
            <p id="p-long">Trips per zone follow a <em>Poisson distribution</em> whose rate grows with the number of residents and workplaces in the zone and in its neighbours.</p>
            <h2 id="later">Later section</h2>
            <p id="p-late">Again: the zones are counted once a year by the office, and nobody else counts them.</p>
            <pre><code class="language-julia" id="code">function rate(zone)
                exp(alpha + beta * log(residents(zone)))
            end</code></pre>
            <div style="height: 1500px"></div>
            <p id="p-end">The last words of the document stand here at its very end.</p>
            </article>"""
        ref(id, text, url; kw...) = pdf_ref(text, url; panel="orig", id, kind=:html, kw...)
        content = h.div(; id="content")(
            h.p("Trips ", ref("h1", "(model)", "/brief"; quoted="follow a Poisson distribution whose rate grows"),
                " are counted ", ref("h2", "(later)", "/brief#later"; quoted="the zones are counted once a year by the office"), "."),
            h.p("The rate ", ref("h3", "(code)", "/brief"; quoted="exp(alpha + beta * log(residents(zone)))"),
                "; the section ", ref("h4", "(later section)", "/brief#later"), "; ",
                ref("h5", "(missing)", "/brief"; quoted="This sentence is not in the document at all"), "; ",
                ref("h6", "(end)", "/brief"; quoted="The last words of the document stand here"), "; ",
                ref("hb", "(broken)", "/broken"; quoted="words that cannot be shown"), "; ",
                pdf_ref("(p. 2)", "/doc.pdf"; panel="orig", id="pd", page=2, quoted="reported to the youth office")),
            h.template(; id="late")(ref("hl", "(late)", "/brief"; quoted="number of residents and workplaces")),
            h.div(; style="height: 2000px"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const tick = () => fetch('/tick').then(r => r.text());
            const wait = async (cond, n = 400) => { for (let i = 0; i < n && !cond(); i++) await tick(); return cond(); };
            const aside = document.getElementById('orig'), beside = aside.closest('[data-htmxo-pdf-beside]');
            const ref = id => document.getElementById(id), key = id => ref(id).dataset.htmxoPdfKey;
            const hits = k => [...aside.querySelectorAll('.htmxo-pdf-hit')].filter(x => x.dataset.htmxoPdfKey === k);
            const lit = el => el.hasAttribute('data-htmxo-pdf-lit'), active = el => el.hasAttribute('data-htmxo-pdf-active');
            const over = (el, from) => el.dispatchEvent(new PointerEvent('pointerover', {bubbles: true, relatedTarget: from || null}));
            const note = () => aside.querySelector('[data-htmxo-pdf-note]').textContent;
            const busy = () => aside.querySelector('[data-htmxo-pdf-pages]').hasAttribute('aria-busy');
            const pageLine = () => aside.querySelector('[data-htmxo-pdf-page-info]').textContent;
            const pager = () => getComputedStyle(aside.querySelector('.htmxo-pdf-pager')).display;
            const inPanel = el => { const a = aside.getBoundingClientRect(), r = el.getBoundingClientRect(); return r.top >= a.top && r.bottom <= a.bottom; };
            const meets = (a, b) => { const r = a.getBoundingClientRect(), s = b.getBoundingClientRect();
                                      return r.left < s.right && r.right > s.left && r.top < s.bottom && r.bottom > s.top; };
            const doc = id => aside.querySelector('.htmxo-pdf-html [id="' + id + '"]');
            // where words stand on screen, as the test finds them itself: the last line's box
            const wordsAt = (node, words) => { const i = node.data.indexOf(words), r = document.createRange();
                                               r.setStart(node, i); r.setEnd(node, i + words.length);
                                               const all = r.getClientRects(); return all[all.length - 1]; };
            const near = (a, b) => Math.abs(a.right - b.right) < 1.5 && Math.abs(a.top - b.top) < 1.5;
            const unmodified = el => new Promise(ok => {
                el.addEventListener('click', e => { ok(e.defaultPrevented); e.preventDefault(); }, {once: true});
            });
            let loads = 0;
            document.addEventListener('htmx:load', e => { if (e.target.closest && e.target.closest('.htmxo-pdf-html')) loads++; });
            try {
                // a click on a reference to an HTML document opens it beside the text at the passage
                ref('h1').click();
                await wait(() => !busy() && hits(key('h1')).length > 0);
                check('opened', !aside.hidden && beside.hasAttribute('data-htmxo-pdf-open'));
                check('html-kind', aside.dataset.htmxoPdfKind === 'html' && !!doc('p-long'));
                check('fragment-swapped', !aside.textContent.includes('FULL PAGE') && loads > 0);
                check('no-page-line', pager() === 'none' && pageLine() === '');
                check('chosen', aside.querySelector('input[type="radio"][value="/brief"]').checked);
                check('h1-active', hits(key('h1')).every(active) && active(ref('h1')));
                check('h1-in-view', inPanel(hits(key('h1'))[0]));
                check('h1-over-its-words', hits(key('h1')).every(x => meets(x, doc('p-long'))) &&
                    hits(key('h1')).some(x => meets(x, doc('p-long').querySelector('em'))));
                const tail = doc('p-long').lastChild, h1last = () => hits(key('h1'))[hits(key('h1')).length - 1].getBoundingClientRect();
                const before = wordsAt(tail, 'rate grows');
                check('h1-ends-at-its-words', near(h1last(), before));
                check('fragment-untouched', !aside.querySelector('.htmxo-pdf-html .htmxo-pdf-hit') &&
                    doc('p-long').innerHTML.includes('<em>Poisson distribution</em> whose'));
                check('note-empty', note() === '');
                // the panel wider: the words wrap anew and the marks follow them
                beside.style.setProperty('--htmxo-pdf-width', '60%');
                await wait(() => near(h1last(), wordsAt(tail, 'rate grows')), 40);
                const after = wordsAt(tail, 'rate grows');
                check('resize-follows', near(h1last(), after) && (Math.abs(after.top - before.top) > 1 || Math.abs(after.right - before.right) > 1));
                // from the anchor on: the same words before it are not the passage
                ref('h2').click();
                await wait(() => !busy() && hits(key('h2')).some(active));
                check('anchor-first', hits(key('h2')).length > 0 &&
                    hits(key('h2')).every(x => meets(x, doc('p-late')) && !meets(x, doc('p-early'))));
                // a script that changes the fragment: the marks follow the words
                doc('p-early').append(' More words.'.repeat(60));
                await wait(() => hits(key('h2')).length > 0 && hits(key('h2')).every(x => meets(x, doc('p-late'))), 40);
                check('change-follows', hits(key('h2')).length > 0 && hits(key('h2')).every(x => meets(x, doc('p-late'))));
                // an anchor without quoted words: its element at the top, below the bar
                ref('h4').click();
                await wait(() => !busy());
                const bar = aside.querySelector('.htmxo-pdf-bar').getBoundingClientRect().bottom, top = doc('later').getBoundingClientRect().top;
                check('anchor-top', top >= bar - 1 && top < bar + 40 && note() === '');
                // quoted words the document lacks: said so
                ref('h5').click();
                await wait(() => note() === 'The quoted words were not found in this document');
                check('not-in-document', note() === 'The quoted words were not found in this document');
                // code the page's PrismJS highlights is marked over its tokens, the code left to PrismJS
                await wait(() => doc('code') && doc('code').querySelector('.token'), 600);
                ref('h3').click();
                await wait(() => !busy() && hits(key('h3')).some(active));
                check('code-highlighted', !!doc('code').querySelector('.token'));
                check('code-marked', hits(key('h3')).length > 0 && hits(key('h3')).every(x => meets(x, doc('code'))) &&
                    !doc('code').querySelector('.htmxo-pdf-hit'));
                // one box for the line, its tokens, spaces and punctuation together
                check('code-one-box', hits(key('h3')).length === 1);
                // a passage far down: the panel scrolls to it
                ref('h6').click();
                await wait(() => !busy() && hits(key('h6')).some(active));
                check('far-in-view', inPanel(hits(key('h6'))[0]));
                // pointing lights both and scrolls nothing; a click on a passage goes to its reference
                ref('h1').click();
                await wait(() => !busy() && hits(key('h1')).some(active) && inPanel(hits(key('h1'))[0]));
                const s0 = aside.scrollTop, y0 = scrollY;
                over(ref('h2'));
                check('hover-lights-mark', hits(key('h2')).every(lit) && !hits(key('h1')).some(lit) && aside.scrollTop === s0 && scrollY === y0);
                over(document.body, ref('h2'));
                check('hover-ends', !hits(key('h2')).some(lit));
                hits(key('h1'))[0].dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
                check('mark-lights-ref', lit(ref('h1')) && !lit(ref('h2')) && aside.scrollTop === s0 && scrollY === y0);
                aside.dispatchEvent(new MouseEvent('mouseleave'));
                scrollTo(0, document.body.scrollHeight);
                await tick();
                hits(key('h1'))[0].click();
                const r = ref('h1').getBoundingClientRect();
                check('mark-goes', r.top >= 0 && r.bottom <= innerHeight && ref('h1').hasAttribute('data-htmxo-pdf-flash'));
                // a reference that arrives later is marked in the document shown
                const late = document.getElementById('late').content.firstElementChild.cloneNode(true);
                ref('content').appendChild(late);
                late.dispatchEvent(new CustomEvent('htmx:load', {bubbles: true}));
                await wait(() => hits(key('hl')).length > 0, 40);
                check('late-marked', hits(key('hl')).length > 0 && hits(key('hl')).every(x => meets(x, doc('p-long'))));
                // colours off: only the passages pointed at and gone to show
                aside.querySelector('[data-htmxo-pdf-colours]').click();
                check('colours-off', getComputedStyle(hits(key('hl'))[0]).visibility === 'hidden' &&
                    getComputedStyle(hits(key('h1'))[0]).visibility === 'visible');
                aside.querySelector('[data-htmxo-pdf-colours]').click();
                // a PDF after the HTML document: its pages and page line, the document gone
                ref('pd').click();
                await wait(() => pageLine() === 'page 2 of 2' && hits(key('pd')).some(active));
                check('pdf-after-html', aside.dataset.htmxoPdfKind === 'pdf' && !aside.querySelector('.htmxo-pdf-doc') &&
                    pager() !== 'none' && aside.querySelector('input[type="radio"][value="/doc.pdf"]').checked);
                check('pdf-marked', hits(key('pd')).length === 1);
                // and the HTML document again: no pages, no page line
                ref('h1').click();
                await wait(() => !busy() && hits(key('h1')).some(active));
                check('html-after-pdf', aside.dataset.htmxoPdfKind === 'html' && !aside.querySelector('.htmxo-pdf-page') && pageLine() === '');
                // a document that fails to load says so
                ref('hb').click();
                await wait(() => note().startsWith('The file could not be shown'));
                check('broken', note().startsWith('The file could not be shown: 500') && !busy());
                // chosen in the chooser, an HTML document opens at its top
                aside.querySelector('input[type="radio"][value="/brief"]').click();
                await wait(() => !busy() && !!doc('intro'));
                check('chosen-top', aside.dataset.htmxoPdfKind === 'html' && aside.scrollTop === 0 && note() === '');
                // a modified click opens the document itself
                const ctrl = unmodified(ref('h1'));
                ref('h1').dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ctrlKey: true}));
                check('modified-click-own', !(await ctrl));
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(pdf_beside(content,
                pdf_panel(["Fixture" => "/doc.pdf", (title="Brief", url="/brief", kind=:html)]; id="orig"))), driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        html_type = ["Content-Type" => "text/html; charset=utf-8"]
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, html_type, page) :
            path == "/brief" ? HTTP.Response(200, html_type, HTTP.header(req, "HX-Request") == "true" ? brief :
                                             "<!doctype html><html><body><p>FULL PAGE</p></body></html>") :
            path == "/broken" ? HTTP.Response(500, "broken") :
            path == "/doc.pdf" ? HTTP.Response(200, ["Content-Type" => "application/pdf"], pdf) :
            path == "/tick" ? (sleep(0.05); HTTP.Response(200, "ok")) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=120000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=180)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("pdf_panel browser (HTML): ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 32
            end
        finally
            close(server)
        end
    end
end
