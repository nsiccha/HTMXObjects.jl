@testitem "a static export removes an hx-get whose request sends values" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: h
    # htmx puts what a GET sends into its query: a form's fields, a named
    # control's own value, and what an `hx-include`/`hx-vals`/`hx-vars` on the
    # element or an enclosing one adds. No static file answers that query, so
    # such an element is a control the export cannot serve, as one whose
    # address carries a query is. Before, only the address was looked at: an
    # exported subject pager (`<form hx-get="/qt/fit/ppc">`) kept live Prev,
    # Next and page-size controls that 404 on a static host (snag
    # request-scoped-s-ce782361).
    pager(url, page) = h.form(
        h.button("Next ›"; type="submit", name="ppc_page", value=string(page + 1)),
        h.input(; type="number", name="ppc_page", value=string(page)),
        h.select(h.option("5"; value="5"); name="ppc_page_size"),
        h.input(; type="hidden", name="dataset", value="d");
        hx_get=url, hx_target="#sv-pager", hx_swap="outerHTML", hx_trigger="change, submit")
    frag = h.div(pager("/svpager", 1), h.p("keep"))
    removed = repr("text/html", static_transform(frag,
        StaticExport(; url_map=_ -> nothing, controls=:remove)))
    @test !contains(removed, "<form") && !contains(removed, "ppc_page")
    @test contains(removed, "keep")
    disabled = repr("text/html", static_transform(frag, StaticExport()))
    @test occursin(r"<form[^>]* data-static-disabled=\"true\"", disabled)
    @test !contains(disabled, "hx-get")
    # A recording applies the same rule.
    @test !contains(repr("text/html", static_transform(frag; record_base="/b")), "hx-get")

    stripped(x) = !contains(repr("text/html", static_transform(x, StaticExport())), "hx-get")
    @test stripped(h.select(h.option("a"); name="k", hx_get="/svk"))
    @test stripped(h.input(; name="q", hx_get="/svq", hx_trigger="keyup"))
    @test stripped(h.button("Go"; name="k", value="2", hx_get="/svk"))
    @test stripped(h.div(; hx_get="/svk", hx_include="#filters"))
    @test stripped(h.button("↻"; hx_get="/svk", hx_vals="js:{...htmxoSortState('#t')}"))
    @test stripped(h.div(; hx_get="/svk", data_hx_vars="x:1"))
    # Without a name or an addition, the request is its address alone.
    @test !stripped(h.button("Go"; hx_get="/svk"))
    @test !stripped(h.div(; hx_get="/svk", hx_trigger="load"))

    # What an enclosing element adds reaches every request inside it, until an
    # element says `unset`.
    inherited = repr("text/html", static_transform(h.div(
            h.a("sent"; hx_get="/svsent"),
            h.div(h.a("unset"; hx_get="/svunset"); hx_include="unset");
            hx_include="#filters"), StaticExport()))
    @test !contains(inherited, "/svsent") && contains(inherited, "hx-get=\"/svunset\"")
    @test stripped(h.div(h.a("v"; hx_get="/svv"); hx_vals="{\"a\": 1}"))
    @test !stripped(h.div(h.a("v"; hx_get="/svv"); hx_vals="unset"))

    # The caller's `url_map` still decides: a target keeps the element live,
    # its values then sent to that target.
    live(url) = url == "/svpager" ? "https://live.example/svpager" : nothing
    mapped = repr("text/html", static_transform(pager("/svpager", 1), StaticExport(; url_map=live)))
    @test contains(mapped, "hx-get=\"https://live.example/svpager\"")
    @test !contains(mapped, "data-static-disabled")

    # A `url_params` element's runtime loads the file of each value it
    # declares, whatever its request includes.
    declared = h.div(; id="sv-k", hx_get="/svk", hx_trigger="change from:#k", hx_include="#k",
                     url_params(k = "a"; values = (k = ("a", "b"),))...)
    files(url) = startswith(url, "/svk?") ? "hx/svk-" * replace(url[6:end], '=' => '-') * ".html" : nothing
    kept = repr("text/html", static_transform(declared, StaticExport(; url_map=files)))
    @test contains(kept, "hx-get=\"hx/svk-k-a.html\"") && !contains(kept, "data-static-disabled")
    @test contains(repr("text/html", static_transform(declared, StaticExport())), "hx-get=\"/svk\"")

    # The reported call: one route's fragment exported in-process, with no
    # address mapped.
    @htmx struct SentValuesApp
        @get svppc(; ppc_page::Int=1, dataset::String="d") =
            h.div(h.p("page $ppc_page of $dataset"), pager(string(__self__/"svppc"), ppc_page);
                  id="sv-pager")
    end
    route!(SentValuesApp())
    hx = ["HX-Request" => "true"]
    resp = dispatch(:GET, "/svppc?ppc_page=2&dataset=d"; headers=hx,
                    static=StaticExport(; controls=:remove, url_map=_ -> nothing))
    body = String(resp.body)
    @test resp.status == 200 && contains(body, "page 2 of d")
    @test !contains(body, "<form") && !contains(body, "hx-get")
    livebody = String(dispatch(:GET, "/svppc?ppc_page=2"; headers=hx).body)
    @test contains(livebody, "<form") && contains(livebody, "hx-get=\"/svppc\"")
end
