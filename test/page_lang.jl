using TestItemRunner

# A route's declared `__lang__` held only around the page shell, which runs
# after the operation has rendered its poller, so Treebars wrote the `:auto`
# poller of a German page in English ("❚❚ Polling — 6s so far"). The language
# now holds while the operation runs, and Treebars reads it through
# `HTMXObjects.page_lang()` (snag `treebars-poller-b46d6ecb`, todo `00ffv2g`).

@testitem "an :auto poller writes Treebars' words in the page's __lang__" tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test
    import HTMXObjects: h

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    gate = Base.Event()
    @htmx struct PageLangGermanApp
        __lang__ = "de"
        "Bericht berechnen"
        @get page_lang_de_slow() = (wait(gate); h.p("fertig"))
        @direct @get page_lang_de_now() = h.p("lang=", something(HTMXObjects.page_lang(), "none"))
    end
    @htmx struct PageLangPlainApp
        "Compute the report"
        @get page_lang_plain_slow() = (wait(gate); h.p("done"))
        @direct @get page_lang_plain_now() = h.p("lang=", something(HTMXObjects.page_lang(), "none"))
    end
    route!(PageLangGermanApp())
    route!(PageLangPlainApp())
    hx = ["HX-Request" => "true"]
    body(target) = String(HTMXObjects._message_body_bytes(dispatch(:GET, target; headers=hx)))
    try
        german = body("/page_lang_de_slow")
        @test contains(german, "treebar-poller")
        @test contains(german, "data-treebar-texts")
        @test contains(german, "Läuft")
        @test contains(german, "Live-Aktualisierung anhalten")
        @test !contains(german, ">Polling<")
        plain = body("/page_lang_plain_slow")
        @test contains(plain, "treebar-poller")
        @test !contains(plain, "data-treebar-texts")
        @test contains(plain, ">Polling<")
        @test contains(plain, "Pause live updates")
        # A route body that runs on the request's task (`@direct`) reads it too;
        # outside a route there is none.
        @test contains(body("/page_lang_de_now"), "lang=de")
        @test contains(body("/page_lang_plain_now"), "lang=none")
        @test HTMXObjects.page_lang() === nothing
    finally
        notify(gate)
    end
end
