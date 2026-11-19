@testitem "page themes follow the shell through live and static rendering" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr(MIME"text/html"(), x)
    content = h.article(h.h1("Results"))
    override = h.style(Raw("article { --jb-card-accent: black }"))
    page(; kw...) = HTMXObjects.pico_page(content; assets=:vendor, extra_head=(override,), kw...)

    @test html(page()) == html(page(; theme=nothing))
    @test !occursin("IBM Plex Sans", html(page()))
    @test_throws ArgumentError page(; theme=:typo)
    inline = html(page(; theme=:juliabayes))
    @test occursin("data:font/woff2;base64,", inline)
    @test occursin("SIL OPEN FONT LICENSE", inline)
    @test first(findfirst("--jb-purple:", inline)) < first(findfirst(html(override), inline))

    linked = page(; theme=:juliabayes, runtime=:linked)
    @test occursin("/vendor/htmxo/juliabayes.css?v=", html(linked))
    @test !occursin("data:font/woff2", html(linked))
    css = HTMXObjects._runtime_text(:juliabayes)
    @test occursin("<style>" * css * "</style>" * html(override), html(static_transform(linked)))

    portfolio_css = HTMXObjects._runtime_text(:nsiccha)
    @test occursin("main .grid", portfolio_css)
    @test !occursin(portfolio_css, html(page()))
    @test occursin(portfolio_css, html(page(; theme=:nsiccha)))
    portfolio_linked = page(; theme=:nsiccha, runtime=:linked)
    @test occursin("/vendor/htmxo/nsiccha.css?v=", html(portfolio_linked))
    @test occursin("<style>" * portfolio_css * "</style>" * html(override), html(static_transform(portfolio_linked)))

    # A custom theme works without Pico and can contain CSS string content
    # that would otherwise end a <style> element in an HTML document.
    custom = htmx(content; theme="p::after {content:'</StYlE>'}", extra_head=(override,))
    @test occursin("<style>p::after {content:'\\3c /StYlE>'}</style>" * html(override), html(custom))
    @test !occursin("IBM Plex Sans", html(custom))
    @test occursin("p::after", html(static_transform(custom)))
    @test occursin(html(override), html(htmx(content; theme=override)))
    @test_throws ArgumentError htmx(content; theme=h.link(rel="icon", href="/logo.svg"))
end

@testitem "the page shell accepts attributes on the document root" tags=[:unit] begin
    using HTMXObjects
    html(page) = repr(MIME"text/html"(), page)
    root(page) = match(r"<html[^>]*>", html(page)).match
    content = h.p("Report")
    attrs = (; data_theme="light", data_design="A & \"B\"", hidden=false, dir=nothing)
    for shell in (htmx, HTMXObjects.pico_page)
        @test html(shell(content; html_attrs=(;))) == html(shell(content))
        page = shell(content; lang="en", html_attrs=attrs)
        @test root(page) == "<html lang=\"en\" hx-ext=\"preload\" data-theme=\"light\" data-design=\"A &amp; &quot;B&quot;\">"
        @test root(static_transform(page)) == root(page)
    end

    # The caller and shell may repeat the same attribute, using either spelling.
    @test root(htmx(content; html_attrs=(; var"HX-EXT"="preload"))) == root(htmx(content))
    @test_throws ArgumentError htmx(content; html_attrs=(; var"HX-EXT"="other"))
    @test_throws ArgumentError htmx(content; lang="en", html_attrs=(; lang="de"))
    @test_throws ArgumentError htmx(content; error_texts=error_texts(:de),
        html_attrs=(; data_htmxo_error_texts="other"))
    @test_throws ArgumentError htmx(content; html_attrs=(; data_theme="light", var"data-theme"="dark"))
    @test_throws ArgumentError htmx(content; html_attrs=(; var"bad name"="value"))
end

@testitem "the themed site example exports both pages with one local stylesheet" tags=[:integration] begin
    using HTMXObjects
    include(joinpath(pkgdir(HTMXObjects), "examples", "themed_site.jl"))
    mktempdir() do dir
        ThemedSite.main(["export", dir])
        home = read(joinpath(dir, "index.html"), String)
        model = read(joinpath(dir, "model.html"), String)
        css = read(joinpath(dir, "vendor", "htmxo", "juliabayes.css"), String)
        @test all(html -> occursin("href=\"vendor/htmxo/juliabayes.css?v=", html), (home, model))
        @test occursin("data:font/woff2;base64,", css)
        @test occursin("href=\"model.html\"", home)
        live = String(dispatch(:GET, "/model").body)
        @test occursin("href=\"/vendor/htmxo/juliabayes.css?v=", live)
        frag = String(dispatch(:GET, "/model"; headers=["HX-Request" => "true"]).body)
        @test occursin("Outcome model", frag)
        @test !occursin("juliabayes.css", frag)
    end
end

@testitem "a linked custom theme exports its relative assets" tags=[:integration] begin
    using HTMXObjects
    @htmx struct BrandedApp
        __page__(content) = htmx(h.main(content); assets=:vendor,
            html_attrs=(; data_theme="light", data_design="lab"),
            theme=h.link(rel="stylesheet", href="/theme-test-brand/site.css"))
        @get index() = h.h1("Branded page")
    end
    mktempdir() do dir
        assets = mkdir(joinpath(dir, "branding"))
        css = "h1 { background-image: url(mark.svg) }"
        mark = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><circle r="1"/></svg>"""
        write(joinpath(assets, "site.css"), css)
        write(joinpath(assets, "mark.svg"), mark)
        staticfiles(assets, "theme-test-brand")
        vendorfiles()
        route!(BrandedApp(); prefix="/themed-doc", operation_policy=:blocking)
        out = joinpath(dir, "site")
        url = "/themed-doc/"
        live = String(dispatch(:GET, url).body)
        @test occursin("href=\"/theme-test-brand/site.css\"", live)
        export_site(out; pages=[url])
        page = read(joinpath(out, static_file_name(url)), String)
        for document in (live, page)
            root = match(r"<html[^>]*>", document).match
            @test occursin("data-theme=\"light\"", root)
            @test occursin("data-design=\"lab\"", root)
        end
        @test occursin("href=\"theme-test-brand/site.css\"", page)
        @test read(joinpath(out, "theme-test-brand", "site.css"), String) == css
        @test read(joinpath(out, "theme-test-brand", "mark.svg"), String) == mark
    end
end
