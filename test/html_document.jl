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

# `htmx(...; lang)` / `pico_page(...; lang)` declare the page's language on
# `<html>`, so screen readers and hyphenation follow it, live and in a static
# export; a page without it is byte-identical (snag building-a-germa-1f100d09).
@testitem "the page shell declares its language" tags=[:unit] begin
    using HTMXObjects
    html_tag(page) = match(r"<html[^>]*>", repr("text/html", page)).match
    @test repr("text/html", htmx(h.p("x"))) == repr("text/html", htmx(h.p("x"); lang=nothing))
    @test html_tag(htmx(h.p("x"))) == "<html hx-ext=\"preload\">"
    @test html_tag(htmx(h.p("x"); lang="de")) == "<html lang=\"de\" hx-ext=\"preload\">"
    @test html_tag(htmx(h.p("x"); lang="de", preload_version=nothing)) == "<html lang=\"de\">"
    @test startswith(html_tag(htmx(h.p("x"); lang="de", error_texts=error_texts(:de))),
        "<html lang=\"de\" hx-ext=\"preload\" data-htmxo-error-texts=")
    @test html_tag(HTMXObjects.pico_page(h.p("x"); lang="de-CH")) == "<html lang=\"de-CH\" hx-ext=\"preload\">"
    for tag in ("en", "de-AT", "zh-Hant-TW", "sr-Latn", "es-419", "de-DE-1996")
        @test contains(html_tag(htmx(h.p("x"); lang=tag)), "lang=\"$tag\"")
    end
    # refused: not a language tag; a browser takes any value and silently
    # treats the page as an unknown language (no silent errors, dev §1)
    for bad in ("", "German", "de_DE", "de-", "-de", "de CH")
        @test_throws ArgumentError htmx(h.p("x"); lang=bad)
    end
    # refused: a locale symbol is not written as an attribute value; pass the tag string
    @test_throws ArgumentError htmx(h.p("x"); lang=:de)
    @test_throws ArgumentError HTMXObjects.pico_page(h.p("x"); lang="German")
end

@testitem "a page's language reaches live pages and static exports" tags=[:integration, :server] begin
    using HTMXObjects
    @htmx struct GermanShellApp
        __page__(content) = HTMXObjects.pico_page(content; lang="de")
        @get german_page() = h.p("Grüß Gott")
    end
    route!(GermanShellApp())
    live = String(dispatch(:GET, "/german_page"; headers=["Accept" => "text/html"]).body)
    @test startswith(live, "<!DOCTYPE html>\n<html lang=\"de\"") && contains(live, "Grüß Gott")
    exported = String(dispatch(:GET, "/german_page"; static=StaticExport()).body)
    @test startswith(exported, "<!DOCTYPE html>\n<html lang=\"de\"") && contains(exported, "Grüß Gott")
    # A swapped fragment is not a document and carries no `<html>`.
    fragment = String(dispatch(:GET, "/german_page"; headers=["HX-Request" => "true"]).body)
    @test !contains(fragment, "<html")
    mktempdir() do dir
        record!(GermanShellApp(); record_dir=dir, paths=["/german_page"], full=true, hx=false, markdown=false)
        recorded = read(joinpath(dir, "german_page.html"), String)
        @test startswith(recorded, "<!DOCTYPE html>\n<html lang=\"de\"")
    end
end
