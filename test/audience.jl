using TestItemRunner

# Public vs private content: `private(x; public)` and the audience of an
# answer (`export_audience`, `audience=` on `dispatch`, `StaticExport`,
# `export_site` and `pdf_report`). Design: user pick on
# TenderViews/decisions/2026-10-24T23-26-35-726-0id3m3n (one wrapper; exports
# public unless asked otherwise, the live app shows everything).

@testmodule AudienceFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw
    export AudienceApp, AudienceScriptApp, bundle_bytes

    const base = ""
    # Rendered for the live app before any export runs, so the export cannot
    # leave the private part out of it.
    const PRERENDERED = Raw(repr("text/html", private(h.p("SECRET-PRERENDERED"))))

    @htmx struct AudienceApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.h1("Modell"),
            h.p("Leser: ", string(export_audience(__req__))),
            private(h.div(h.p("SECRET-SPEC"), h.a("Details"; href=base * "/aud_detail"));
                    public = h.p("Kurzfassung")),
            h.a("Spezifikation"; href=base * "/aud_spec"),
            h.div(; id="spec", hx_get=base * "/aud_spec", hx_trigger="load"),
            h.a("Weiter"; href=base * "/aud_next"))
        # A private page: the whole answer is private, with no stand-in.
        @get aud_spec() = private(h.pre("SECRET-PAGE"))
        # Linked only from inside private content.
        @get aud_detail() = h.p("SECRET-DETAIL")
        # Found after the index, and linking the private page too.
        @get aud_next() = h.div(h.p("Weiter"), h.a("Spezifikation"; href=base * "/aud_spec"))
        @get aud_prerendered() = h.div(h.p("Vorab"), PRERENDERED)
        # A nested dispatch answers for the audience of the request it is made in.
        @get aud_nested() = h.div(h.p("Verschachtelt"),
            Raw(String(dispatch(:GET, base * "/aud_spec"; headers=["HX-Request" => "true"]).body)))
    end

    @htmx struct AudienceScriptApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.p("Karte"),
            h.script(Raw("window.spec = " * repr(static_url(__req__, base * "/aud_script_spec")) * ";")))
        @get aud_script_spec() = private(h.pre("SECRET-SCRIPT"))
    end

    # Every byte the bundle holds, as text.
    bundle_bytes(dir) = join(read(joinpath(d, f), String) for (d, _, fs) in walkdir(dir) for f in fs)
end

@testitem "private shows its content to the live app and its stand-in to a public reader" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: h, _with_audience, to_markdown_string
    page = h.article(h.h2("Modell"),
        private(h.p("SECRET"); public = h.p("Kurzfassung")),
        h.p("Ende"))
    live = repr("text/html", page)
    @test occursin("<p>SECRET</p>", live) && !occursin("Kurzfassung", live)
    # The live markup marks the private part, so markup rendered ahead of an
    # export can be recognised in its answer.
    @test occursin("<!--htmxo-private--><p>SECRET</p><!--/htmxo-private-->", live)
    public = _with_audience(() -> repr("text/html", page), :public)
    @test occursin("<p>Kurzfassung</p>", public) && !occursin("SECRET", public)
    @test !occursin("htmxo-private", public)
    @test _with_audience(() -> repr("text/html", page), :private) == live

    # Markdown alike, with the stand-in in the private part's place.
    @test occursin("SECRET", to_markdown_string(page)) && !occursin("Kurzfassung", to_markdown_string(page))
    md = _with_audience(() -> to_markdown_string(page), :public)
    @test occursin("Kurzfassung\n\nEnde", md) && !occursin("SECRET", md)

    # Without a stand-in a public reader gets nothing; text is escaped as an
    # element's child is; several values render in order.
    @test _with_audience(() -> repr("text/html", h.div("a", private("<b>x</b>"), "c")), :public) == "<div>ac</div>"
    @test repr("text/html", h.div(private("<b>x</b>"))) ==
          "<div><!--htmxo-private-->&lt;b&gt;x&lt;/b&gt;<!--/htmxo-private--></div>"
    @test occursin("<p>a</p><p>b</p>", repr("text/html", h.div(private([h.p("a"), h.p("b")]))))
    # A semantic element stays a block of its own in Markdown.
    card = private(SemanticCard("Modell", "y ~ x"))
    @test HTMXObjects.HTMX.markdown_block(card)
    @test !_with_audience(() -> HTMXObjects.HTMX.markdown_block(card), :public)
    # A whole answer renders what it shows; an empty one for a public reader.
    @test String(to_response(private(h.p("SECRET"))).body) == "<p>SECRET</p>"
    @test _with_audience(() -> String(to_response(private(h.p("SECRET"))).body), :public) == ""
end

@testitem "a static export walks private content as its audience reads it" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: h
    seen = String[]
    target(url) = (push!(seen, url); nothing)
    frag = h.div(h.a("Start"; href="/start"),
        private(h.div(h.p("SECRET"), h.a("Spezifikation"; href="/spec"));
                public = h.p("Kurzfassung", h.a("mehr"; href="/summary"))),
        private([h.p("a"), h.a("b"; href="/b")]))
    # The public export holds no private part, however it is serialized later,
    # and never asks url_map about a link inside one.
    public = static_transform(frag, StaticExport(; url_map=target))
    html = repr("text/html", public)
    @test !occursin("SECRET", html) && !occursin("/spec", html) && !occursin("<p>a</p>", html)
    @test occursin("<p>Kurzfassung<a href=\"/summary\">mehr</a></p>", html)
    @test seen == ["/start", "/summary"]
    empty!(seen)
    # A private export shows everything; content shown as several values takes
    # its place among the element's children.
    private_html = repr("text/html", static_transform(frag, StaticExport(; url_map=target, audience=:private)))
    @test occursin("<p>SECRET</p>", private_html) && !occursin("Kurzfassung", private_html)
    @test occursin("<p>a</p><a href=\"/b\">b</a></div>", private_html)
    @test seen == ["/start", "/spec", "/b"]
    # Recordings are public too.
    @test !occursin("SECRET", repr("text/html", static_transform(frag; record_base="/r")))
    # refused: an audience is :public or :private (user pick 0id3m3n)
    @test_throws ArgumentError StaticExport(; audience=:everyone)
    @test_throws ArgumentError StaticExport(; audience="public")
end

@testitem "a public dispatch answers private content with its stand-in" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceApp())
    body(resp) = String(resp.body)
    md = ["Accept" => "text/markdown"]

    # Outside any request a dispatch answers for the public.
    public = body(dispatch(:GET, "/"))
    @test occursin("Kurzfassung", public) && !occursin("SECRET", public)
    @test occursin("Leser: public", public)
    @test !occursin("SECRET", body(dispatch(:GET, "/"; headers=md)))
    # The live app's answer, and any asked for :private, shows everything.
    live = body(dispatch(:GET, "/"; audience=:private))
    @test occursin("SECRET-SPEC", live) && !occursin("Kurzfassung", live)
    @test occursin("Leser: private", live)
    @test occursin("SECRET-SPEC", body(dispatch(:GET, "/"; headers=md, audience=:private)))
    # A static export follows its audience, in Markdown too.
    @test !occursin("SECRET", body(dispatch(:GET, "/"; static=StaticExport())))
    @test !occursin("SECRET", body(dispatch(:GET, "/"; headers=md, static=StaticExport())))
    @test occursin("SECRET-SPEC", body(dispatch(:GET, "/"; headers=md, static=StaticExport(; audience=:private))))

    # A private page answers a public reader with an empty 404 that says so.
    for headers in ([], ["HX-Request" => "true"], md)
        resp = dispatch(:GET, "/aud_spec"; headers)
        @test resp.status == 404 && HTTP.header(resp, "X-HTMXO-Private") == "true" && body(resp) == ""
    end
    @test occursin("SECRET-PAGE", body(dispatch(:GET, "/aud_spec"; audience=:private)))
    # A nested dispatch answers for the request it is made in.
    @test occursin("SECRET-PAGE", body(dispatch(:GET, "/aud_nested"; audience=:private)))
    nested = body(dispatch(:GET, "/aud_nested"))
    @test occursin("Verschachtelt", nested) && !occursin("SECRET", nested)

    # Markup rendered for the live app ahead of the answer cannot be left out:
    # a public answer holding it fails instead.
    err = try dispatch(:GET, "/aud_prerendered"); nothing catch e e end
    @test err isa PrivateContentEscaped && occursin("/aud_prerendered", sprint(showerror, err))
    @test occursin("SECRET-PRERENDERED", body(dispatch(:GET, "/aud_prerendered"; audience=:private)))

    # refused: an audience is :public or :private (user pick 0id3m3n)
    @test_throws ArgumentError dispatch(:GET, "/"; audience=:all)
    # refused: one request has one audience
    @test_throws ArgumentError dispatch(:GET, "/"; static=StaticExport(), audience=:private)
end

@testitem "export_site leaves private content and private pages out of a public site" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"])
    # No byte of private content anywhere in the bundle.
    @test !occursin("SECRET", bundle_bytes(dir))
    @test isfile(joinpath(dir, "index.html")) && isfile(joinpath(dir, "aud_next.html"))
    # No file for the private page, none for a link only private content holds.
    @test !isfile(joinpath(dir, "aud_spec.html")) && !isfile(joinpath(dir, "hx/aud_spec.html"))
    @test !isfile(joinpath(dir, "aud_detail.html"))
    index = read(joinpath(dir, "index.html"), String)
    @test occursin("Kurzfassung", index) && occursin("href=\"aud_next.html\"", index)
    # Every element linking or loading the private page is left out, also in a
    # page written before that page was found private.
    @test !occursin("aud_spec", index) && !occursin("id=\"spec\"", index)
    @test !occursin("aud_spec", read(joinpath(dir, "aud_next.html"), String))

    # A private site shows everything, as the live app does.
    full = joinpath(mktempdir(), "full")
    export_site(full; pages=["/"], audience=:private)
    @test occursin("SECRET-PAGE", read(joinpath(full, "aud_spec.html"), String))
    @test isfile(joinpath(full, "hx/aud_spec.html")) && isfile(joinpath(full, "aud_detail.html"))
    @test occursin("SECRET-SPEC", read(joinpath(full, "index.html"), String))

    # refused: an audience is :public or :private (user pick 0id3m3n)
    @test_throws ArgumentError export_site(mktempdir(); pages=["/"], audience=:team)
end

@testitem "export_site fails on a private page a script names" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceScriptApp())
    vendorfiles()
    dir = mktempdir()
    err = try export_site(dir; pages=["/"]); nothing catch e e end
    @test err isa StaticSiteIncomplete
    @test any(((a, why),) -> a == "/aud_script_spec" && occursin("is private", why), err.failed)
    @test isempty(err.unresolved)
    @test !occursin("SECRET", bundle_bytes(dir))
end

@testitem "pdf_report checks its audience before running Quarto" tags=[:unit] begin
    using HTMXObjects
    mktempdir() do dir
        out = joinpath(dir, "report.pdf")
        # refused: an audience is :public or :private (user pick 0id3m3n)
        @test_throws ArgumentError pdf_report("# R", out; title="R", lang="de-DE", audience=:all)
        @test_throws ArgumentError pdf_report(h.p("R"), out; title="R", lang="de-DE", audience="public")
        # Markdown holding markup rendered for the live app is no public report.
        err = try
            pdf_report("# R\n\n" * repr("text/html", private(h.p("SECRET"))), out; title="R", lang="de-DE")
        catch e
            e
        end
        @test err isa PrivateContentEscaped
        # A private report takes it; here Quarto is missing.
        err = try
            pdf_report("# R\n\n" * repr("text/html", private(h.p("SECRET"))), out; title="R",
                       lang="de-DE", audience=:private, quarto="htmxo-no-such-quarto")
        catch e
            e
        end
        @test err isa ErrorException && occursin("Quarto not found", err.msg)
        @test readdir(dir) == []
    end
end

@testitem "pdf_report renders a value for its audience" tags=[:quarto] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects
        page = h.article(h.h1("Konzept"),
            h.p("Vorher."),
            private(h.p("Die vollständige Spezifikation."); public = h.p("Eine Kurzfassung.")),
            h.p("Nachher."))
        mktempdir() do dir
            text(path) = read(`pdftotext -enc UTF-8 $path -`, String)
            public = joinpath(dir, "public.pdf")
            pdf_report(page, public; title="Konzept", lang="de-DE")
            @test occursin("Eine Kurzfassung.", text(public)) && !occursin("Spezifikation", text(public))
            full = joinpath(dir, "full.pdf")
            pdf_report(page, full; title="Konzept", lang="de-DE", audience=:private)
            @test occursin("Die vollständige Spezifikation.", text(full)) && !occursin("Kurzfassung", text(full))
        end
    end
end
