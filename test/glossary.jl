using TestItemRunner

# An app declares its technical terms once (`Glossary` as `__glossary__` on its
# root) and every answer links the uses of its terms to their entries, with the
# definition beside the link on hover or keyboard focus (snag
# `no-glossary-prim-026537ac`, reporter VerkehrsStrukturdaten:ux; design
# decision 0xuzhdk, no preference on all four prongs = the recommended ones).

@testmodule GlossaryFixture begin
    using HTMXObjects
    import HTMXObjects: h
    const G = Glossary([
        GlossaryTerm("Registerzelle", "Ein Bezirk × Abschnitt mit einem Wert im Unternehmensregister.";
                     forms=["Registerzellen"]),
        GlossaryTerm("Modell vor Benchmarking", "Die Erwartung des Modells, bevor die Registerwerte die Zellen anpassen.";
                     forms=["Modells vor dem Benchmarking"]),
        "Modell" => "Die Deklaration, die die Schätzung erzeugt.",
        "R̂" => "Der Konvergenzwert der Ketten.",
        "posterior" => "The distribution after seeing the data.",
    ]; href="/glossar", title="Glossar")
    html(x) = repr("text/html", x)
    links(s) = count("class=\"htmxo-term\"", s)
    hrefs(s) = [m.captures[1] for m in eachmatch(r"<a href=\"([^\"]*)\" aria-describedby", s)]
end

@testitem "a glossary declares terms, forms and addresses" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    G = GlossaryFixture.G
    @test [t.term for t in G.terms] == ["Modell", "Modell vor Benchmarking", "posterior", "R̂", "Registerzelle"]
    @test Dict(t.term => t.id for t in G.terms) == Dict("Registerzelle" => "registerzelle", "Modell" => "modell",
        "Modell vor Benchmarking" => "modell-vor-benchmarking", "R̂" => "r", "posterior" => "posterior")
    @test GlossaryTerm("Größe", "x").id == "groesse"
    @test GlossaryTerm("95-%-Intervall", "x").id == "95-intervall"
    @test GlossaryTerm("x  y\n z", " d ").term == "x y z"
    @test_throws ArgumentError GlossaryTerm(" ", "d")
    @test_throws ArgumentError GlossaryTerm("a", "  ")
    @test_throws ArgumentError GlossaryTerm("a", "d"; id="has space")
    @test_throws ArgumentError GlossaryTerm("∑", "d")          # no id can be built
    @test GlossaryTerm("∑", "d"; id="sum").id == "sum"
    @test_throws ArgumentError Glossary(GlossaryTerm[])
    @test_throws ArgumentError Glossary(["Zelle" => "a", GlossaryTerm("Zelle!", "b")])     # one id
    @test_throws ArgumentError Glossary([GlossaryTerm("A", "a"; forms=["X"]), GlossaryTerm("B", "b"; forms=["X"])])
    @test_throws ArgumentError Glossary(["a" => "b"]; title=" ")
end

@testitem "the first use of a term in each section links, with its definition" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h
    (; G, html, links, hrefs) = GlossaryFixture

    page = h.article(
        h.h2("Daten"),
        h.p("Die Registerzellen und jede Registerzelle danach."),
        h.p("Noch eine Registerzelle, und Registerzellenwerte sind kein Begriff."),
        h.h2("Modell"),
        h.p("Die Registerzelle im zweiten Abschnitt, das Modell vor\n   Benchmarking und das Modell."),
        h.p("Posterior heißt posterior, R̂ ist der Konvergenzwert."))
    out = html(link_terms(page, G))
    @test links(out) == 6
    @test hrefs(out) == ["/glossar#term-registerzelle", "/glossar#term-registerzelle",
                         "/glossar#term-modell-vor-benchmarking", "/glossar#term-modell",
                         "/glossar#term-posterior", "/glossar#term-r"]
    # The link keeps the text as written; the phrase wins over the term it holds.
    @test contains(out, ">Registerzellen</a>")
    @test contains(out, ">Modell vor\n   Benchmarking</a>")
    @test contains(out, ">Posterior</a>")
    @test !contains(out, ">Registerzellenwerte")
    # The definition is the link's description, in a tooltip beside it.
    for m in eachmatch(r"aria-describedby=\"([^\"]+)\"", out)
        @test count("id=\"$(m.captures[1])\"", out) == 1
    end
    @test contains(out, "class=\"htmxo-term-def\" role=\"tooltip\">Ein Bezirk × Abschnitt")
    # The value given is left as it was (inputs are read-only).
    @test links(html(page)) == 0

    # Each table, figure, caption and disclosure is read on its own.
    scoped = html(link_terms(h.section(
        h.p("Registerzelle im Text."),
        h.table(h.tbody(h.tr(h.td("Registerzelle"), h.td("Registerzelle")))),
        h.figure(h.figcaption("Registerzelle in der Legende")),
        h.details(h.summary("Registerzelle"), h.p("Registerzelle innen")),
        h.p("Registerzelle nach der Tabelle.")), G))
    @test links(scoped) == 4

    # Labels, code, links, controls and marked text stay as they are.
    for skipped in (h.h3("Registerzelle"), h.a("Registerzelle"; href="/x"), h.code("Registerzelle"),
                    h.pre("Registerzelle"), h.button("Registerzelle"), h.label("Registerzelle"),
                    h.table(h.thead(h.tr(h.th("Registerzelle")))), h.th("Registerzelle"),
                    h.p("Registerzelle"; data_htmxo_no_terms=""), h.script("Registerzelle"),
                    h.span("Registerzelle"; class="htmxo-math", data_htmxo_math="inline"))
        @test links(html(link_terms(skipped, G))) == 0
    end
    unchanged = h.div(h.p("nichts"))
    @test link_terms(unchanged, G) === unchanged

    # A header that is a term explains its column instead: `title` and ⓘ.
    header = html(link_terms(render_table([(Registerzelle="a", Wert=1)]; sortable=false), G))
    @test contains(header, "<th title=\"Ein Bezirk × Abschnitt mit einem Wert im Unternehmensregister.\">Registerzelle<span class=\"htmxo-column-help\"")
    @test links(header) == 0
    own = html(link_terms(h.table(h.thead(h.tr(h.th("Registerzelle"; title="eigene")))), G))
    @test !contains(own, "Ein Bezirk") && !contains(own, "htmxo-column-help")
end

@testitem "term links in Markdown, semantic containers and prose" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h, to_markdown_string
    (; G, html, links) = GlossaryFixture

    md = to_markdown_string(link_terms(h.p("Die Registerzellen des Modells."), G))
    @test strip(md) == "Die [Registerzellen](/glossar#term-registerzelle) des Modells."

    section = link_terms(SemanticSection("Registerzelle", "Jede Registerzelle zählt.",
        SemanticCard("Karte", "Eine Registerzelle in der Karte."), h.p("Registerzelle")), G)
    shtml = html(section)
    @test links(shtml) == 2          # the section's own run, and the card's
    @test contains(shtml, "<h2>Registerzelle</h2>")
    smd = to_markdown_string(section)
    @test contains(smd, "## Registerzelle")
    @test contains(smd, "Jede [Registerzelle](/glossar#term-registerzelle) zählt.")
    @test contains(smd, "Eine [Registerzelle](/glossar#term-registerzelle) in der Karte.")
    @test !contains(smd, "Ein Bezirk")   # the tooltip is HTML only

    prose = SemanticProse("Die *Registerzellen* und `Registerzelle` im Code, mit \$x_1\$.")
    linked = link_terms(prose, G)
    @test links(html(linked)) == 1
    @test contains(html(linked), "data-htmxo-math")
    pmd = strip(to_markdown_string(linked))
    @test contains(pmd, "*[Registerzellen](/glossar#term-registerzelle)*")
    @test contains(pmd, "`Registerzelle`")
    @test contains(pmd, "\$x_1\$")
    plain = SemanticProse("Nichts zu verlinken.")
    @test link_terms(plain, G) === plain
    # What the source escaped stays escaped in the linked prose's Markdown.
    escaped = strip(to_markdown_string(link_terms(SemanticProse(raw"Kosten \$5, \*kein\* Stern, je Registerzelle."), G)))
    @test escaped == raw"Kosten \$5, \*kein\* Stern, je [Registerzelle](/glossar#term-registerzelle)."

    # A term the matcher cannot see; without a glossary it is its text.
    use = h.p("Die ", term("Registerzellen-Summe"; of="Registerzelle"), " und ", term("R̂"), ".")
    uhtml = html(link_terms(use, G))
    @test links(uhtml) == 2
    @test contains(uhtml, ">Registerzellen-Summe</a>")
    @test html(use) == "<p>Die <span>Registerzellen-Summe</span> und <span>R̂</span>.</p>"
    @test strip(to_markdown_string(use)) == "Die Registerzellen-Summe und R̂."
    @test_throws ArgumentError link_terms(h.p(term("Zelle")), G)
    @test links(html(link_terms(h.p(term("x"; of="registerzelle")), G))) == 1   # by id

    # Private content is linked as each reader sees it.
    p = link_terms(h.div(private(h.p("Registerzelle privat"); public=h.p("Registerzelle öffentlich")),
                         h.p("Registerzelle danach")), G)
    @test links(with_audience(() -> repr("text/html", p), :private)) == 1
    @test links(with_audience(() -> repr("text/html", p), :public)) == 1
end

@testitem "glossary_section lists every entry at its address" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: to_markdown_string
    (; G, html, links) = GlossaryFixture
    section = glossary_section(G)
    out = html(section)
    @test contains(out, "<h2>Glossar</h2>")
    @test contains(out, "<dt id=\"term-registerzelle\"><dfn>Registerzelle</dfn></dt><dd>Ein Bezirk × Abschnitt")
    @test findfirst("term-modell\"", out).start < findfirst("term-registerzelle", out).start
    @test links(html(link_terms(section, G))) == 0
    md = to_markdown_string(section)
    @test contains(md, "## Glossar")
    @test contains(md, "[**Registerzelle**]{#term-registerzelle} — Ein Bezirk × Abschnitt mit einem Wert im Unternehmensregister.")
    @test contains(md, "[**R̂**]{#term-r} — Der Konvergenzwert der Ketten.")
end

@testitem "a root's __glossary__ links its answers and explains its columns" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: h
    (; links, hrefs) = GlossaryFixture

    @htmx struct GlossaryRootApp
        __glossary__ = GlossaryFixture.G
        @get glossary_root_page() = h.article(h.p("Die Registerzelle im Text."),
            sortable_table(["Registerzelle", ColumnSpec("Modell"), ColumnSpec("Wert"; help="eigene Hilfe")],
                           [["a", "b", "c"]]))
        @get glossary_root_glossar() = glossary_section(__glossary__)
    end
    @htmx struct GlossaryPlainApp
        @get glossary_plain_page() = h.p("Die Registerzelle im Text.")
    end
    @htmx struct GlossaryBadApp
        __glossary__ = "Registerzelle"
        @get glossary_bad_page() = h.p("x")
    end
    route!(GlossaryRootApp())
    route!(GlossaryPlainApp())
    route!(GlossaryBadApp())
    body(target; headers=["HX-Request" => "true"]) = String(HTMXObjects._message_body_bytes(dispatch(:GET, target; headers)))

    fragment = body("/glossary_root_page")
    @test links(fragment) == 1
    @test hrefs(fragment) == ["/glossar#term-registerzelle"]
    # A sortable column named after a term explains it with the definition;
    # an explanation of the app's own is kept.
    @test contains(fragment, "title=\"Ein Bezirk × Abschnitt mit einem Wert im Unternehmensregister.\"")
    @test contains(fragment, "title=\"Die Deklaration, die die Schätzung erzeugt.\"")
    @test contains(fragment, "title=\"eigene Hilfe\"")
    @test count("htmxo-column-help", fragment) == 3
    @test links(body("/glossary_root_page"; headers=[])) == 1      # the full page too
    md = body("/glossary_root_page"; headers=["Accept" => "text/markdown"])
    @test contains(md, "Die [Registerzelle](/glossar#term-registerzelle) im Text.")
    @test contains(body("/glossary_root_glossar"), "id=\"term-registerzelle\"")

    plain = body("/glossary_plain_page")
    @test links(plain) == 0
    @test contains(plain, "Die Registerzelle im Text.")
    # A declaration that is no `Glossary` is the route's error, named after its struct.
    bad = dispatch(:GET, "/glossary_bad_page"; headers=["Accept" => "text/html"])
    @test bad.status == 500
    err = try
        HTMXObjects._page_meta_of(Any[GlossaryBadApp()])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && contains(err.msg, "`__glossary__` on GlossaryBadApp")
end

@testitem "a static export keeps term links on the exported glossary" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h
    (; links, hrefs) = GlossaryFixture

    @htmx struct GlossaryExportApp
        __glossary__ = Glossary(GlossaryFixture.G.terms; href="/glossary_export_glossar", title="Glossar")
        @get glossary_export_page() = h.p("Die Registerzelle im Text.")
        @get glossary_export_glossar() = glossary_section(__glossary__)
    end
    route!(GlossaryExportApp())
    page = String(HTMXObjects._message_body_bytes(dispatch(:GET, "/glossary_export_page";
        static=StaticExport(; record_base="/base"))))
    @test links(page) == 1
    @test hrefs(page) == ["/base/glossary_export_glossar#term-registerzelle"]

    dir = mktempdir()
    export_site(dir; pages=["/glossary_export_page"])
    exported = read(joinpath(dir, static_file_name("/glossary_export_page")), String)
    @test links(exported) == 1
    target = only(hrefs(exported))
    @test endswith(target, "#term-registerzelle")
    file = joinpath(dir, first(split(target, '#')))
    @test isfile(file)
    @test contains(read(file, String), "id=\"term-registerzelle\"")
end

@testitem "a report's term links point into the glossary it ends with" setup=[GlossaryFixture] tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h, to_markdown_string
    G = GlossaryFixture.G
    md = to_markdown_string(link_terms(h.article(h.p("Die Registerzelle und das Modell."),
                                                 h.p("Ein [Link](/glossar#term-unbekannt) bleibt.")), G))
    report = HTMXObjects._glossary_report(md, G)
    @test contains(report, "[Registerzelle](#term-registerzelle)")
    @test contains(report, "[Modell](#term-modell)")
    @test contains(report, "[Link](/glossar#term-unbekannt)")
    # The appended glossary lists the terms used, alphabetically.
    @test endswith(report, "## Glossar\n\n[**Modell**]{#term-modell} — Die Deklaration, die die Schätzung erzeugt.\n\n" *
                           "[**Registerzelle**]{#term-registerzelle} — Ein Bezirk × Abschnitt mit einem Wert im Unternehmensregister.\n")
    @test !contains(report, "term-posterior}")
    # A report that carries the glossary itself gets no second copy.
    whole = HTMXObjects._glossary_report(md * "\n\n" * to_markdown_string(glossary_section(G)), G)
    @test count("{#term-registerzelle}", whole) == 1
    # Nothing linked, nothing appended.
    @test HTMXObjects._glossary_report("Kein Begriff.", G) == "Kein Begriff."
end

@testitem "pdf_report links a value's terms into its appended glossary" setup=[GlossaryFixture] tags=[:quarto] begin
    using HTMXObjects, Test
    import HTMXObjects: h
    if isnothing(Sys.which("quarto"))
        @test_skip true
    else
        dir = mktempdir()
        out = pdf_report(h.article(h.p("Die Registerzelle und das Modell vor Benchmarking.")),
                         joinpath(dir, "glossar.pdf"); title="Bericht", lang="de-DE", glossary=GlossaryFixture.G)
        @test isfile(out)
        if !isnothing(Sys.which("pdftotext"))
            text = read(`pdftotext -layout $out -`, String)
            @test contains(text, "Glossar")
            @test contains(text, "Die Erwartung des Modells")
        end
    end
end

@testitem "a term's definition opens on hover or focus, inside the window and outside scrolling tables" setup=[GlossaryFixture, ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, Test
        import HTMXObjects: h, Raw
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function () {
          const checks = [];
          const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
          const runtime = document.documentElement.classList.contains('htmxo-terms');
          const parts = id => {
            const link = document.querySelector('#' + id + ' .htmxo-term > a');
            return {link, box: document.getElementById(link.getAttribute('aria-describedby'))};
          };
          const shown = box => getComputedStyle(box).display === 'block';
          // Whether the box's centre is the box, i.e. nothing clips or covers it.
          const visible = box => {
            const b = box.getBoundingClientRect();
            const at = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
            return at !== null && box.contains(at);
          };
          const prose = parts('prose'), p = document.getElementById('prose');
          const height = p.getBoundingClientRect().height;
          check('hidden at rest', !shown(prose.box));
          check('reads as text', getComputedStyle(prose.link).color === getComputedStyle(p).color);
          check('dotted underline', getComputedStyle(prose.link).textDecorationStyle === 'dotted');
          prose.link.focus();
          check('open on focus', shown(prose.box));
          check('beside, not in, the line', p.getBoundingClientRect().height === height);
          check('below the term', prose.box.getBoundingClientRect().top >= prose.link.getBoundingClientRect().bottom - 1);
          prose.link.blur();
          check('closed after focus', !shown(prose.box));
          const cell = parts('scroller');
          cell.link.focus();
          check('table cell open', shown(cell.box));
          check('table cell unclipped', visible(cell.box));
          cell.link.blur();
          const edge = parts('edge');
          edge.link.focus();
          check('edge inside the window', edge.box.getBoundingClientRect().right <= document.documentElement.clientWidth);
          if (runtime) {
            document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
            check('escape closes', !shown(edge.box));
            edge.link.blur();
            prose.link.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}));
            check('open on hover', shown(prose.box));
            prose.link.dispatchEvent(new MouseEvent('mouseout', {bubbles: true, relatedTarget: document.body}));
            check('closed after hover', !shown(prose.box));
          }
          const out = document.createElement('pre'); out.id = 'checks';
          out.textContent = checks.join('\n'); document.body.appendChild(out);
        });
        """))
        content = link_terms(h.main(
            h.p("Die Registerzelle steht im Text."; id="prose"),
            h.div(h.table(h.tbody((h.tr(h.td(i == 6 ? "Registerzelle" : "Zeile $i")) for i in 1:6)...));
                  id="scroller", style="overflow: auto; height: 3em; margin-top: 2em"),
            h.p("Am Rand steht das Modell"; id="edge", style="text-align: right"),
            driver; style="max-width: 30rem"), GlossaryFixture.G)
        dir = mktempdir()
        shell = joinpath(dir, "shell.html")
        write(shell, repr("text/html", htmx(content; htmx_version=nothing, sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing, katex_version=nothing, feedback=false)))
        # The control: the stylesheet alone, without the runtime.
        bare = joinpath(dir, "bare.html")
        write(bare, "<!DOCTYPE html>" * repr("text/html", h.html(h.head(h.meta(; charset="utf-8"), htmxo_utility_styles()),
                                                               h.body(content))))
        results = Dict{String,Dict{String,Bool}}()
        for (name, file) in (("shell", shell), ("bare", bare))
            profile = mktempdir()
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=300,700 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$file`)
            m = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(m)
            results[name] = Dict(String(first(split(l, ':'))) => endswith(l, ":true") for l in split(m.captures[1], '\n'))
        end
        @test all(values(results["shell"]))
        @test length(results["shell"]) == 13
        @test results["shell"]["table cell unclipped"] && !results["bare"]["table cell unclipped"]
        @test results["bare"]["open on focus"] && results["bare"]["closed after focus"]
    end
end
