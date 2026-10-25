using TestItemRunner

# Public vs private content: `private(x; public)` and the audience of an
# answer (`export_audience`, `audience=` on `dispatch`, `StaticExport`,
# `export_site` and `pdf_report`). Design: user pick on
# TenderViews/decisions/2026-10-24T23-26-35-726-0id3m3n (one wrapper; exports
# public unless asked otherwise, the live app shows everything).

@testmodule AudienceFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw, to_markdown_string
    export AudienceApp, AudienceScriptApp, bundle_bytes,
        AudienceDocApp, AudienceKeptApp, BUILDS, DOCS_DIR, document_pack

    const base = ""
    # Rendered for the live app before any export runs, so the export cannot
    # leave the private part out of it.
    const PRERENDERED = Raw(with_audience(() -> repr("text/html", private(h.p("SECRET-PRERENDERED"))), :private))

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
        # A body that renders its own Markdown, which HTMXObjects may run in a
        # task of its own.
        @get aud_selfmd() = MIMEResponse("text/plain",
            to_markdown_string(h.div(h.p("Offen"), private(h.p("SECRET-SELF"); public = h.p("Kurz")))))
        # Library code inside a route assembling Markdown for a public reader.
        @get aud_libmd() = MIMEResponse("text/plain",
            to_markdown_string(private(h.p("SECRET-LIB"); public = h.p("Kurz")); audience=:public))
    end

    @htmx struct AudienceScriptApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.p("Karte"),
            h.script(Raw("window.spec = " * repr(static_url(__req__, base * "/aud_script_spec")) * ";")))
        @get aud_script_spec() = private(h.pre("SECRET-SCRIPT"))
    end

    # Library code answering a private page it has to build: it looks the
    # document up and reads its file, which only a private reader's answer
    # does (TenderViews' `tender_document`; snag private-page-con-b8682fea).
    const BUILDS = Ref(0)
    const DOCS = Dict("lb" => "lb.pdf")
    const DOCS_DIR = Ref("")
    lazy_document(dir, id) = private() do
        BUILDS[] += 1
        file = get(DOCS, id, nothing)
        isnothing(file) && throw(CallerFault(404, "no document $(repr(id))"))
        MIMEResponse("application/pdf", read(joinpath(dir, file)))
    end

    @htmx struct AudienceDocApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.p("Unterlagen"),
            h.a("Leistungsbeschreibung"; href=base * "/aud_doc/lb"),
            private(; public = h.p("Kurz")) do
                BUILDS[] += 1
                h.p("SECRET-LAZY")
            end)
        @get aud_doc(id::String) = lazy_document(DOCS_DIR[], id)
    end

    # The same page in a root that is kept across requests.
    @htmx struct AudienceKeptApp
        @get aud_kept(id::String) = lazy_document(DOCS_DIR[], id)
    end

    # A directory holding the document.
    function document_pack()
        dir = mktempdir()
        write(joinpath(dir, "lb.pdf"), "%PDF-1.4 lb")
        dir
    end

    # Every byte the bundle holds, as text.
    bundle_bytes(dir) = join(read(joinpath(d, f), String) for (d, _, fs) in walkdir(dir) for f in fs)
end

@testitem "private shows its content to the live app and its stand-in to a public reader" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: h, _with_audience, to_markdown_string
    page = h.article(h.h2("Modell"),
        private(h.p("SECRET"); public = h.p("Kurzfassung")),
        h.p("Ende"))
    live = with_audience(() -> repr("text/html", page), :private)
    @test occursin("<p>SECRET</p>", live) && !occursin("Kurzfassung", live)
    # The live markup marks the private part, so markup rendered ahead of an
    # export can be recognised in its answer.
    @test occursin("<!--htmxo-private--><p>SECRET</p><!--/htmxo-private-->", live)
    public = _with_audience(() -> repr("text/html", page), :public)
    @test occursin("<p>Kurzfassung</p>", public) && !occursin("SECRET", public)
    @test !occursin("htmxo-private", public)
    @test _with_audience(() -> repr("text/html", page), :private) == live
    # Outside any request a value renders for the public.
    @test repr("text/html", page) == public

    # Markdown alike, with the stand-in in the private part's place.
    full = to_markdown_string(page; audience=:private)
    @test occursin("SECRET", full) && !occursin("Kurzfassung", full)
    md = _with_audience(() -> to_markdown_string(page), :public)
    @test occursin("Kurzfassung\n\nEnde", md) && !occursin("SECRET", md)
    @test to_markdown_string(page) == md

    # Without a stand-in a public reader gets nothing; text is escaped as an
    # element's child is; several values render in order.
    @test _with_audience(() -> repr("text/html", h.div("a", private("<b>x</b>"), "c")), :public) == "<div>ac</div>"
    @test _with_audience(() -> repr("text/html", h.div(private("<b>x</b>"))), :private) ==
          "<div><!--htmxo-private-->&lt;b&gt;x&lt;/b&gt;<!--/htmxo-private--></div>"
    @test occursin("<p>a</p><p>b</p>",
                   _with_audience(() -> repr("text/html", h.div(private([h.p("a"), h.p("b")]))), :private))
    # A semantic element stays a block of its own in Markdown.
    card = private(SemanticCard("Modell", "y ~ x"))
    @test _with_audience(() -> HTMXObjects.HTMX.markdown_block(card), :private)
    @test !_with_audience(() -> HTMXObjects.HTMX.markdown_block(card), :public)
    # A whole answer renders what it shows; an empty one for a public reader.
    @test _with_audience(() -> String(to_response(private(h.p("SECRET"))).body), :private) == "<p>SECRET</p>"
    @test _with_audience(() -> String(to_response(private(h.p("SECRET"))).body), :public) == ""
end

@testitem "code that renders a value itself asks for its audience" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: h, to_markdown_string
    page = h.article(h.p("Offen"), private(h.p("SECRET"); public = h.p("Kurzfassung")))
    # Markdown: the keyword says who it is for; without it, outside any request,
    # it is for the public (snag to-markdown-stri-25778f31).
    public = to_markdown_string(page; audience=:public)
    @test occursin("Offen", public) && occursin("Kurzfassung", public) && !occursin("SECRET", public)
    full = to_markdown_string(page; audience=:private)
    @test occursin("SECRET", full) && !occursin("Kurzfassung", full)
    @test to_markdown_string(page) == public
    # The keyword wins over the audience it is rendered in.
    @test with_audience(() -> to_markdown_string(page; audience=:public), :private) == public
    @test with_audience(() -> to_markdown_string(page), :private) == full

    # with_audience covers every other rendering and returns f's value.
    html = with_audience(:private) do
        repr("text/html", page)
    end
    @test occursin("<!--htmxo-private--><p>SECRET</p><!--/htmxo-private-->", html)
    @test !occursin("SECRET", with_audience(() -> repr("text/html", page), :public))
    @test with_audience(() -> 42, :public) == 42
    snapshot = with_audience(() -> HTMLSnapshot(page), :public)
    @test !occursin("SECRET", repr("text/html", snapshot))
    # A task the code starts itself does not inherit the audience; it asks.
    @test occursin("SECRET", with_audience(:private) do
        fetch(Threads.@spawn with_audience(() -> to_markdown_string(page), :private))
    end)

    # refused: an audience is :public or :private (user pick 0id3m3n)
    @test_throws ArgumentError to_markdown_string(page; audience=:everyone)
    @test_throws ArgumentError with_audience(() -> 1, "public")
    err = try to_markdown_string(page; audience=:all); nothing catch e e end
    @test err isa ArgumentError && occursin("to_markdown_string", err.msg)
end

@testitem "a route body renders for its request's audience in any task" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceApp())
    body(resp) = String(resp.body)
    # Under `:auto` a fragment's body runs in a task HTMXObjects starts; it
    # renders for the request's audience there too (snag to-markdown-stri-25778f31).
    for headers in (["HX-Request" => "true"], String[], ["Accept" => "text/markdown"])
        public = body(dispatch(:GET, "/aud_selfmd"; headers))
        @test occursin("Kurz", public) && !occursin("SECRET", public)
        @test occursin("SECRET-SELF", body(dispatch(:GET, "/aud_selfmd"; headers, audience=:private)))
    end
    # Library code inside a live request asks for its own reader.
    lib = body(dispatch(:GET, "/aud_libmd"; audience=:private))
    @test occursin("Kurz", lib) && !occursin("SECRET", lib)
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

@testitem "a private page a function builds is built for a private reader only" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceDocApp())
    body(resp) = String(resp.body)
    error_id(resp) = HTTP.header(resp, "X-HTMXO-Error-Id")
    private_page(resp) = resp.status == 404 && HTTP.header(resp, "X-HTMXO-Private") == "true" &&
        body(resp) == "" && error_id(resp) == ""
    # A public reader gets the private page: nothing is looked up or read, so
    # neither a document missing on this host nor an unknown id fails it.
    DOCS_DIR[] = mktempdir()
    BUILDS[] = 0
    for headers in ([], ["HX-Request" => "true"], ["Accept" => "text/markdown"]), id in ("lb", "xx")
        @test private_page(dispatch(:GET, "/aud_doc/$id"; headers))
    end
    @test BUILDS[] == 0
    # A private reader's answer is built once.
    DOCS_DIR[] = document_pack()
    resp = dispatch(:GET, "/aud_doc/lb"; audience=:private)
    @test resp.status == 200 && body(resp) == "%PDF-1.4 lb"
    @test HTTP.header(resp, "Content-Type") == "application/pdf"
    @test BUILDS[] == 1
    # What fails while it is built is a recorded route error: a CallerFault
    # keeps its status.
    unknown = dispatch(:GET, "/aud_doc/xx"; audience=:private)
    @test unknown.status == 404 && !isempty(error_id(unknown))
    @test occursin("no document", body(unknown))
    DOCS_DIR[] = mktempdir()
    absent = dispatch(:GET, "/aud_doc/lb"; audience=:private)
    @test absent.status == 500 && !isempty(error_id(absent))
end

@testitem "a private part a function builds is built when a private reader is shown it" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    import HTMXObjects: h, to_markdown_string
    route!(AudienceDocApp())
    body(resp) = String(resp.body)
    answers = ([], ["HX-Request" => "true"], ["Accept" => "text/markdown"])
    BUILDS[] = 0
    for headers in answers
        public = body(dispatch(:GET, "/"; headers))
        @test occursin("Kurz", public) && !occursin("SECRET", public)
    end
    @test BUILDS[] == 0
    for headers in answers
        built = BUILDS[]
        live = body(dispatch(:GET, "/"; headers, audience=:private))
        @test occursin("SECRET-LAZY", live) && !occursin("Kurz", live)
        @test BUILDS[] == built + 1
    end
    # Rendering it yourself, and a static export, build it for a private
    # reader only.
    part = private(() -> (BUILDS[] += 1; h.p("SECRET-PART")); public = h.p("Kurz"))
    built = BUILDS[]
    @test !occursin("SECRET", to_markdown_string(part)) && !occursin("SECRET", repr("text/html", part))
    @test !occursin("SECRET", repr("text/html", static_transform(h.div(part), StaticExport())))
    @test BUILDS[] == built
    @test occursin("SECRET-PART", to_markdown_string(part; audience=:private))
    @test occursin("SECRET-PART", with_audience(() -> repr("text/html", part), :private))
    @test occursin("SECRET-PART",
        repr("text/html", static_transform(h.div(part), StaticExport(; audience=:private))))
    @test BUILDS[] == built + 3
end

@testitem "export_site leaves out a private page a function builds without building it" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    route!(AudienceDocApp())
    vendorfiles()
    # The documents are not on this host: a public site needs none of them.
    DOCS_DIR[] = mktempdir()
    BUILDS[] = 0
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"])
    @test BUILDS[] == 0
    @test !occursin("SECRET", bundle_bytes(dir)) && !occursin("%PDF", bundle_bytes(dir))
    @test !occursin("aud_doc", read(joinpath(dir, "index.html"), String))
    # A private site carries the document.
    DOCS_DIR[] = document_pack()
    full = joinpath(mktempdir(), "full")
    export_site(full; pages=["/"], audience=:private)
    @test occursin("%PDF-1.4 lb", bundle_bytes(full)) && occursin("SECRET-LAZY", bundle_bytes(full))
end

@testitem "a private page a function builds answers each reader in a kept root" setup=[HTMXOTestImports, AudienceFixture] tags=[:unit] begin
    using Treebars
    # The route's value is kept across requests; each answer is built for its
    # own reader.
    route!(AudienceKeptApp(); root_provider=RootProvider(scope=:session, key=req -> "k",
                                                         retention=RootRetention()))
    DOCS_DIR[] = document_pack()
    @test dispatch(:GET, "/aud_kept/lb").status == 404
    for _ in 1:2
        @test String(dispatch(:GET, "/aud_kept/lb"; audience=:private).body) == "%PDF-1.4 lb"
    end
    @test dispatch(:GET, "/aud_kept/lb").status == 404
end

@testitem "pdf_report checks its audience before running Quarto" tags=[:unit] begin
    using HTMXObjects
    mktempdir() do dir
        out = joinpath(dir, "report.pdf")
        # refused: an audience is :public or :private (user pick 0id3m3n)
        @test_throws ArgumentError pdf_report("# R", out; title="R", lang="de-DE", audience=:all)
        @test_throws ArgumentError pdf_report(h.p("R"), out; title="R", lang="de-DE", audience="public")
        # Markdown holding markup rendered for the live app is no public report.
        live_html = with_audience(() -> repr("text/html", private(h.p("SECRET"))), :private)
        err = try
            pdf_report("# R\n\n" * live_html, out; title="R", lang="de-DE")
        catch e
            e
        end
        @test err isa PrivateContentEscaped
        # A private report takes it; here Quarto is missing.
        err = try
            pdf_report("# R\n\n" * live_html, out; title="R",
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
            public = joinpath(dir, "public.pdf")
            @test pdf_report(page, public; title="Konzept", lang="de-DE") == public
            full = joinpath(dir, "full.pdf")
            @test pdf_report(page, full; title="Konzept", lang="de-DE", audience=:private) == full
            if isnothing(Sys.which("pdftotext"))
                @test_skip "pdftotext (poppler-utils) reads the text layer"
            else
                text(path) = read(`pdftotext -enc UTF-8 $path -`, String)
                @test occursin("Eine Kurzfassung.", text(public)) && !occursin("Spezifikation", text(public))
                @test occursin("Die vollständige Spezifikation.", text(full)) && !occursin("Kurzfassung", text(full))
            end
        end
    end
end
