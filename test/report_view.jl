using TestItemRunner

# A report's Markdown can differ from an ordinary read's: `pdf_report` of a
# value, `dispatch(…; report=true)` and `to_markdown_string(x; report=true)`
# write it with `HTMXObjects.page_report()` true, and `report_view(content,
# report)` shows `report` there. AlgebraOfVega gives a captioned figure its
# picture in a report this way, while `?plain` keeps the figure's summary
# (snag `plot-markdown-st-242cdfc9`, user design `0wwdtwg`, todo `1gcysqm`).

@testsnippet ReportProbes begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: h, to_markdown_string

    # What a component sees when its Markdown is written.
    struct ReportProbe end
    Base.show(io::IO, ::MIME"text/markdown", ::ReportProbe) =
        print(io, "report=", HTMXObjects.page_report())
    # A component that writes a child's Markdown itself.
    struct ShowsChild
        child::Any
    end
    Base.show(io::IO, m::MIME"text/markdown", x::ShowsChild) = (print(io, "["); show(io, m, x.child); print(io, "]"))
    # A component that renders Markdown of its own with `to_markdown_string`.
    struct RendersInner
        report::Union{Nothing,Bool}
    end
    Base.show(io::IO, ::MIME"text/markdown", x::RendersInner) =
        print(io, "inner(", to_markdown_string(ReportProbe(); report=x.report), ")")
end

@testitem "page_report is false outside a report and true while a report's Markdown is written" setup=[ReportProbes] tags=[:unit] begin
    @test HTMXObjects.page_report() === false
    @test to_markdown_string(ReportProbe()) == "report=false"
    @test to_markdown_string(ReportProbe(); report=false) == "report=false"
    @test to_markdown_string(ReportProbe(); report=true) == "report=true"
    @test HTMXObjects.page_report() === false

    # It reaches nested renders: an element's children, a component that shows
    # its child, and a to_markdown_string made inside, unless that one asks for
    # an ordinary read.
    @test contains(to_markdown_string(h.article(h.h1("T"), h.p(ReportProbe())); report=true), "report=true")
    @test to_markdown_string(ShowsChild(ShowsChild(ReportProbe())); report=true) == "[[report=true]]"
    @test to_markdown_string(ShowsChild(ReportProbe())) == "[report=false]"
    @test to_markdown_string(RendersInner(nothing); report=true) == "inner(report=true)"
    @test to_markdown_string(RendersInner(false); report=true) == "inner(report=false)"
    @test to_markdown_string(RendersInner(nothing)) == "inner(report=false)"
    @test to_markdown_string(RendersInner(true)) == "inner(report=true)"

    @test_throws ArgumentError to_markdown_string("x"; report=:yes)
    @test_throws ArgumentError to_markdown_string("x"; report=1)
    @test_throws ArgumentError dispatch(:GET, "/"; report="true")
end

@testitem "dispatch(…; report=true) writes a route's answer for a report, and a dispatch inside it keeps it" setup=[ReportProbes] tags=[:unit] begin
    # A cached value: the Markdown still follows each request, since the
    # component reads the flag when its Markdown is written.
    @htmx struct ReportRouteApp
        @direct @get report_probe() = h.div(h.p("probe"), h.p(ReportProbe()))
        @direct @fresh @get report_flag() = h.p("flag=", string(HTMXObjects.page_report()))
        @direct @fresh @get report_outer() = h.p("outer=", string(HTMXObjects.page_report()), " inner=",
            String(HTMXObjects._message_body_bytes(dispatch(:GET, "/report_flag"; headers=["HX-Request" => "true"]))))
        @direct @fresh @get report_outer_off() = h.p("inner=",
            String(HTMXObjects._message_body_bytes(
                dispatch(:GET, "/report_flag"; headers=["HX-Request" => "true"], report=false))))
    end
    route!(ReportRouteApp())
    md = ["Accept" => "text/markdown"]
    hx = ["HX-Request" => "true"]
    body(r) = String(HTMXObjects._message_body_bytes(r))

    @test contains(body(dispatch(:GET, "/report_probe"; headers=md)), "report=false")
    @test contains(body(dispatch(:GET, "/report_probe"; headers=md, report=true)), "report=true")
    @test contains(body(dispatch(:GET, "/report_probe?plain=1")), "report=false")
    @test contains(body(dispatch(:GET, "/report_probe?plain=1"; report=true)), "report=true")
    @test contains(body(dispatch(:GET, "/report_probe"; headers=md, report=false)), "report=false")

    # The route body reads it as well, in HTML answers too.
    @test contains(body(dispatch(:GET, "/report_flag"; headers=hx)), "flag=false")
    @test contains(body(dispatch(:GET, "/report_flag"; headers=hx, report=true)), "flag=true")

    # A dispatch made while a report's answer is built keeps the report, unless
    # it passes report=false; one made in an ordinary answer is ordinary.
    reported = body(dispatch(:GET, "/report_outer"; headers=hx, report=true))
    @test contains(reported, "outer=true") && contains(reported, "flag=true")
    ordinary = body(dispatch(:GET, "/report_outer"; headers=hx))
    @test contains(ordinary, "outer=false") && contains(ordinary, "flag=false")
    @test contains(body(dispatch(:GET, "/report_outer_off"; headers=hx, report=true)), "flag=false")
    # And a dispatch from a component's Markdown, written inside a report.
    struct FetchesFlag end
    Base.show(io::IO, ::MIME"text/markdown", ::FetchesFlag) =
        print(io, body(dispatch(:GET, "/report_flag"; headers=["Accept" => "text/markdown"])))
    @test contains(to_markdown_string(FetchesFlag(); report=true), "flag=true")
    @test contains(to_markdown_string(FetchesFlag()), "flag=false")
    @test HTMXObjects.page_report() === false
end

@testitem "report_view shows content in HTML and ordinary Markdown, and its report view in a report's Markdown" setup=[ReportProbes] tags=[:unit] begin
    live = h.div(h.p("live view"), h.button("Pick"; type="button"))
    paper = h.p("paper view", h.button("Zoom"; type="button"))
    page = h.article(h.h1("Title"), report_view(live, paper), h.p("after"))
    unwrapped(view) = h.article(h.h1("Title"), view, h.p("after"))

    # HTML is the content's, byte for byte, through show and the response writer.
    @test repr(MIME"text/html"(), page) == repr(MIME"text/html"(), unwrapped(live))
    @test HTMXObjects._message_body_bytes(to_response(page)) ==
          HTMXObjects._message_body_bytes(to_response(unwrapped(live)))
    @test HTMXObjects._with_report(() -> repr(MIME"text/html"(), page), true) ==
          repr(MIME"text/html"(), unwrapped(live))

    # Markdown: the shown view with its chrome stripped, as if written alone.
    ordinary = to_markdown_string(page)
    @test ordinary == to_markdown_string(unwrapped(live))
    @test contains(ordinary, "live view") && !contains(ordinary, "paper view") && !contains(ordinary, "Pick")
    # A report writes the article without HTMX's `---` seam, so the paper view
    # is compared as a report writes it alone.
    reported = to_markdown_string(page; report=true)
    @test reported == to_markdown_string(unwrapped(paper); report=true)
    @test contains(reported, "paper view") && !contains(reported, "live view") && !contains(reported, "Zoom")

    # `nothing` leaves a view out of reports only.
    controls = h.div(h.p("channel picker"), h.select(h.option("a"); name="channel"))
    figure = h.figure(report_view(h.p("plot"), h.p("picture")), report_view(controls, nothing))
    @test contains(to_markdown_string(figure), "channel picker")
    @test !contains(to_markdown_string(figure; report=true), "channel picker")
    @test contains(to_markdown_string(figure; report=true), "picture")

    # A whole answer, a leaf view, and semantic containers.
    @test to_markdown_string(report_view("live", "paper")) == "live"
    @test to_markdown_string(report_view("live", "paper"); report=true) == "paper"
    @test to_markdown_string(report_view("live", nothing); report=true) == ""
    @test to_markdown_string(report_view(ReportProbe(), ReportProbe()); report=true) == "report=true"
    section = SemanticSection("Results", report_view(h.p("live"), h.p("paper")))
    @test contains(to_markdown_string(section; report=true), "paper")
    @test contains(to_markdown_string(section), "live")
    disclosure = SemanticDisclosure("Controls", report_view(h.p("picker"), nothing))
    @test contains(to_markdown_string(h.div(disclosure)), "Controls")
    @test !contains(to_markdown_string(h.div(disclosure); report=true), "Controls")

    # Written directly, without the chrome strip, it shows the same view.
    @test contains(sprint(show, MIME"text/markdown"(), h.div(report_view(h.p("live"), h.p("paper")))), "live")
    @test contains(HTMXObjects._with_report(true) do
        sprint(show, MIME"text/markdown"(), h.div(report_view(h.p("live"), h.p("paper"))))
    end, "paper")
    @test sprint(show, MIME"text/plain"(), report_view("live", "paper")) == "live"

    # The readers of the HTML see the content: a static export walks it and
    # keeps the report view for a report made of the export.
    walked = static_transform(h.div(report_view(h.div("load"; hx_get="/rv", hx_include="#f"), h.p("paper"))),
                              StaticExport())
    @test !contains(repr(MIME"text/html"(), walked), "hx-get")
    @test contains(to_markdown_string(walked; report=true), "paper")
end

@testitem "a report's Markdown writes a plain section or article without HTMX's --- seam" setup=[ReportProbes] tags=[:unit] begin
    # HTMX.jl writes a `---` line before a plain `<section>`/`<article>` for a
    # Markdown reader. Pandoc reads it as a horizontal rule, so a report's PDF
    # drew a line the page does not have (snag `contents-with-no-6e01ea0e`,
    # user design `1o8j77d`). Ordinary reads keep it; an `h.hr()` keeps its rule.
    seam(md) = "---" in split(md, '\n')
    plain = h.div(h.section(h.h2("Purpose"), h.p("A package.")), h.article(h.h2("Use"), h.p("x")))
    as_divs = h.div(h.div(h.h2("Purpose"), h.p("A package.")), h.div(h.h2("Use"), h.p("x")))
    @test seam(to_markdown_string(plain))
    @test seam(to_markdown_string(plain; report=false))
    @test !seam(to_markdown_string(plain; report=true))
    @test to_markdown_string(plain; report=true) == to_markdown_string(as_divs; report=true)

    # The reported document: a numbered one whose sections are plain, so its
    # contents list is empty and writes nothing.
    doc = numbered(contents(), h.div(h.section(h.h2("Purpose"), h.p("A package."))))
    @test seam(to_markdown_string(doc; lang="en-GB"))
    @test !seam(to_markdown_string(doc; lang="en-GB", report=true))

    # A linked section keeps its id on its heading, and an intended rule stays.
    linked = to_markdown_string(h.div(h.p(h.a("go"; href="#t")), h.section(id="t")(h.h2("Eins"), h.p("Text"))); report=true)
    @test occursin("## Eins {#t}", linked) && !seam(linked)
    @test seam(to_markdown_string(h.div(h.p("a"), h.hr(), h.p("b")); report=true))

    # A Markdown render made inside a report keeps it, unless it asks for an
    # ordinary read, which writes the seam again.
    struct RendersSection
        report::Union{Nothing,Bool}
    end
    Base.show(io::IO, ::MIME"text/markdown", x::RendersSection) =
        print(io, to_markdown_string(h.section(h.p("x")); report=x.report))
    @test !seam(to_markdown_string(RendersSection(nothing); report=true))
    @test seam(to_markdown_string(RendersSection(false); report=true))

    # A route's answer for a report, as `dispatch(…; report=true)` writes it.
    @htmx struct ReportSeamApp
        @direct @get report_seam_page() = h.div(h.section(h.h2("Purpose"), h.p("A package.")))
    end
    route!(ReportSeamApp())
    md = ["Accept" => "text/markdown"]
    body(r) = String(HTMXObjects._message_body_bytes(r))
    @test seam(body(dispatch(:GET, "/report_seam_page"; headers=md)))
    @test !seam(body(dispatch(:GET, "/report_seam_page"; headers=md, report=true)))
    @test HTMXObjects.HTMX.markdown_seams()
end

@testitem "pdf_report writes a value's Markdown for a report" setup=[ReportProbes] tags=[:unit] begin
    seen = Bool[]
    struct RecordsReport
        seen::Vector{Bool}
    end
    Base.show(io::IO, ::MIME"text/markdown", x::RecordsReport) =
        (push!(x.seen, HTMXObjects.page_report()); print(io, "recorded"))
    mktempdir() do dir
        # The Markdown is written before Quarto is looked for.
        err = try
            pdf_report(h.article(h.h1("R"), h.p(RecordsReport(seen))), joinpath(dir, "r.pdf");
                       title="R", lang="en-GB", quarto="htmxo-no-such-quarto")
        catch e
            e
        end
        @test err isa ErrorException && occursin("Quarto not found", err.msg)
    end
    @test !isempty(seen) && all(seen)
    @test HTMXObjects.page_report() === false
end

@testitem "pdf_report prints a report_view's report view" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        import HTMXObjects: h
        svg = """<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#336"/></svg>"""
        picture = h.img(; src="bar.svg", alt="A dark blue bar")
        page = h.article(h.h1("Report"),
            h.figure(report_view(h.p("Interactive plot only"), picture), h.figcaption("A bar")),
            report_view(h.p("Channel picker only"), nothing),
            h.p("Printed text."))
        mktempdir() do dir
            write(joinpath(dir, "bar.svg"), svg)
            out = joinpath(dir, "report.pdf")
            @test pdf_report(page, out; title="Report", lang="en-GB", resources=dir) == out
            bytes = read(out, String)
            @test occursin("<pdfuaid:part>1</pdfuaid:part>", bytes)
            # Typst writes the structure tree uncompressed: the picture is a figure.
            @test occursin("/Type/StructElem/S/Figure", bytes)
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                text = read(`pdftotext -enc UTF-8 $out -`, String)
                @test contains(text, "Printed text.") && contains(text, "A bar")
                @test !contains(text, "Interactive plot only")
                @test !contains(text, "Channel picker only")
            end
        end
    end
end
