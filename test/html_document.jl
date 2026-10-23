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

# `title=` writes the page's one `<title>`; `__lang__` / `__title__` declared on
# the route's mount chain are the shell's defaults, so a page without either is
# unchanged (co-report on snag building-a-germa-1f100d09, decision 1d43o5g).
@testitem "the page shell's title and declared language" tags=[:unit] begin
    using HTMXObjects
    page(p) = repr("text/html", p)
    # A whole element: the toast runtime's inline script names `<title>` in a comment.
    titles(page) = [m.match for m in eachmatch(r"<title>[^<]*</title>", page)]
    @test page(htmx(h.p("x"))) == page(htmx(h.p("x"); title=nothing))
    @test isempty(titles(page(htmx(h.p("x")))))
    titled = page(htmx(h.p("x"); title="Präsentation & Daten"))
    @test titles(titled) == ["<title>Präsentation &amp; Daten</title>"]
    @test contains(titled, "<meta name=\"color-scheme\" content=\"light dark\"><title>Präsentation &amp; Daten</title>")
    @test contains(page(HTMXObjects.pico_page(h.p("x"); title="App")), "<title>App</title>")
    # A declared language and title apply when the shell is given none; an
    # explicit keyword still wins.
    declared = (; lang="de", title="Seite")
    @test contains(page(HTMXObjects._with_page_meta(() -> htmx(h.p("x")), declared)),
        "<html lang=\"de\"")
    @test contains(page(HTMXObjects._with_page_meta(() -> htmx(h.p("x")), declared)),
        "<title>Seite</title>")
    @test contains(page(HTMXObjects._with_page_meta(() -> htmx(h.p("x"); lang="fr", title="Page"), declared)),
        "<html lang=\"fr\"")
    @test contains(page(HTMXObjects._with_page_meta(() -> htmx(h.p("x"); lang="fr", title="Page"), declared)),
        "<title>Page</title>")
    @test HTMXObjects._page_meta() == HTMXObjects._NO_PAGE_META
    # refused: an empty or non-string title is no title (no silent errors, dev §1)
    @test_throws ArgumentError htmx(h.p("x"); title="")
    @test_throws ArgumentError htmx(h.p("x"); title=:App)
    # refused: a page has one <title>, so a title beside an `h.title` in
    # `extra_head` would leave the browser to pick one
    @test_throws ArgumentError htmx(h.p("x"); title="App", extra_head=(h.title("Other"),))
    @test_throws ArgumentError HTMXObjects._with_page_meta(declared) do
        htmx(h.p("x"); extra_head=(h.title("Other"),))
    end
    # An `h.title` in `extra_head` alone still works as before.
    @test titles(page(htmx(h.p("x"); extra_head=(h.title("Other"),)))) == ["<title>Other</title>"]
end

@testitem "a subtree declares its pages' language and title" tags=[:integration, :server] begin
    using HTMXObjects
    @htmx struct PageLangDeck
        lang::Symbol
        __lang__ = string(lang)
        __title__ = lang === :de ? "Präsentation" : "Presentation"
        __page__(content) = h.div(class="deck")(content)
        @get index() = h.p(lang === :de ? "Grüß Gott" : "Hello")
        @get broken() = error("deck failed")
    end
    @htmx struct PageLangApp
        __lang__ = "en"
        __title__ = "Workbench"
        __page__(content) = HTMXObjects.pico_page(content)
        @get home() = h.p("home")
        @include extern(lang::Symbol) = PageLangDeck(lang)
    end
    route!(PageLangApp())
    full(path) = String(dispatch(:GET, path; headers=["Accept" => "text/html"]).body)
    head(page) = (match(r"<html[^>]*>", page).match, [m.match for m in eachmatch(r"<title>[^<]*</title>", page)])
    @test head(full("/extern/de")) == ("<html lang=\"de\" hx-ext=\"preload\">", ["<title>Präsentation</title>"])
    @test head(full("/extern/en")) == ("<html lang=\"en\" hx-ext=\"preload\">", ["<title>Presentation</title>"])
    @test head(full("/home")) == ("<html lang=\"en\" hx-ext=\"preload\">", ["<title>Workbench</title>"])
    @test contains(full("/extern/de"), "Grüß Gott")
    # A failing route's error page is still the subtree's page.
    @test head(full("/extern/de/broken")) == ("<html lang=\"de\" hx-ext=\"preload\">", ["<title>Präsentation</title>"])
    exported = String(dispatch(:GET, "/extern/de"; static=StaticExport()).body)
    @test head(exported) == ("<html lang=\"de\" hx-ext=\"preload\">", ["<title>Präsentation</title>"])
    fragment = String(dispatch(:GET, "/extern/de"; headers=["HX-Request" => "true"]).body)
    @test !contains(fragment, "<html") && !contains(fragment, "<title")
    mktempdir() do dir
        record!(PageLangApp(); record_dir=dir, paths=["/extern/de"], full=true, hx=false, markdown=false)
        recorded = read(only(filter(endswith(".html"), [joinpath(r, f) for (r, _, fs) in walkdir(dir) for f in fs])), String)
        @test head(recorded) == ("<html lang=\"de\" hx-ext=\"preload\">", ["<title>Präsentation</title>"])
    end

    # The shell's own keywords still win over a declaration.
    @htmx struct PageLangFixedApp
        __page__(content) = HTMXObjects.pico_page(content; lang="fr", title="Fixe")
        @include deck(lang::Symbol) = PageLangDeck(lang)
    end
    route!(PageLangFixedApp())
    @test head(full("/deck/de")) == ("<html lang=\"fr\" hx-ext=\"preload\">", ["<title>Fixe</title>"])

    # refused: a declaration that is not a language tag fails the route,
    # named after its struct, before the route body runs (no silent errors, dev §1)
    @htmx struct PageLangBadApp
        __lang__ = "German"
        __page__(content) = HTMXObjects.pico_page(content)
        @get bad_lang_page() = h.p("never rendered")
    end
    route!(PageLangBadApp())
    bad = dispatch(:GET, "/bad_lang_page"; headers=["Accept" => "text/html"])
    @test bad.status == 500 && !contains(String(bad.body), "never rendered")
    err = try
        HTMXObjects._page_meta_of(Any[PageLangBadApp()])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && contains(err.msg, "`__lang__` on PageLangBadApp")
end
