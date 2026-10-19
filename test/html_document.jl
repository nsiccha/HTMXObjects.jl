@testmodule DocumentFixtures begin
    using HTMXObjects
    export dashboard

    # A route that returns its whole page shell, as an app without `__page__`
    # does: a heading, prose, one error-tagged status, an edit form and a
    # styled head.
    dashboard() = htmx(h.main(h.h1("Dashboard"), h.p("all districts ok"),
            e.span("failed: Kiel"), h.form(h.textarea("raw body"), h.button("Save")));
        extra_head=Any[h.style("td{padding:0}")])
end

@testitem "HTMLDocument projects as its root" setup=[DocumentFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    page = dashboard()
    md = to_markdown_string(page)
    @test md == to_markdown_string(page.root)
    @test repr("text/markdown", page) == repr("text/markdown", page.root)
    @test contains(md, "# Dashboard\n")
    @test contains(md, "all districts ok")
    @test contains(md, "failed: Kiel")
    # Not the struct repr, and no form chrome, styles or scripts.
    @test !contains(md, "HTMLDocument")
    @test !contains(md, "raw body")
    @test !contains(md, "padding")
    @test !contains(md, "<")

    # `?error` keeps only the error-tagged node, still as a document.
    errors = filter_errors(page)
    @test errors isa HTMLDocument
    html = repr("text/html", errors)
    @test startswith(html, "<!DOCTYPE html>\n<html")
    @test contains(html, "<span data-error=\"true\">failed: Kiel</span>")
    @test !contains(html, "all districts ok")
    @test isnothing(filter_errors(htmx(h.main("fine"))))

    # The same projections hold for a document nested in a node.
    nested = h.div(page)
    @test to_markdown_string(nested) == to_markdown_string(h.div(page.root))
    @test contains(repr("text/html", filter_errors(nested)), "failed: Kiel")
    @test !contains(repr("text/html", filter_errors(nested)), "all districts ok")
end

@testitem "A route returning an HTMLDocument negotiates Markdown and ?error" setup=[DocumentFixtures] tags=[:unit] begin
    using HTMXObjects
    @htmx struct DocumentRoutesProbe
        @get document_page() = dashboard()
    end
    route!(DocumentRoutesProbe())
    fetch_page(path; headers=Pair{String,String}[]) = let r = dispatch(:GET, path; headers)
        @test r.status == 200
        r
    end
    page = fetch_page("/document_page"; headers=["Accept" => "text/html"])
    @test startswith(String(page.body), "<!DOCTYPE html>\n<html")
    for r in (fetch_page("/document_page"; headers=["Accept" => "text/markdown"]),
              fetch_page("/document_page"; headers=["Accept" => "text/plain"]),
              fetch_page("/document_page?plain"), fetch_page("/document_page?markdown"))
        md = String(r.body)
        @test contains(HTMXObjects.HTTP.header(r, "Content-Type"), "text/markdown")
        @test contains(md, "# Dashboard\n")
        @test contains(md, "all districts ok")
        @test !contains(md, "HTMLDocument")
        @test !contains(md, "raw body")
        @test !contains(md, "<")
    end
    errors = String(fetch_page("/document_page?error"; headers=["Accept" => "text/html"]).body)
    @test startswith(errors, "<!DOCTYPE html>\n<html")
    @test contains(errors, "<span data-error=\"true\">failed: Kiel</span>")
    @test !contains(errors, "all districts ok")
    plain_errors = String(fetch_page("/document_page?plain&error").body)
    @test contains(plain_errors, "failed: Kiel")
    @test !contains(plain_errors, "all districts ok")
    @test !contains(plain_errors, "HTMLDocument")
end
