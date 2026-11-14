@testitem "large master/detail tables avoid row-count allocation cliffs" tags=[:unit] begin
    using HTMXObjects

    rows = [(; id=i, name="row $i", amount=i / 10) for i in 1:1000]
    render() = master_detail_table(["Name", "Amount"], rows;
        key=x -> x.id, master=x -> h.tr(h.td(x.name), number_cell(x.amount)),
        detail=x -> h.p(x.name), id="allocation-check")
    render() # Compilation is outside the allocation budget.
    # The 1,000-item mixed master/detail body used to allocate 121 MB while
    # building a roughly 550 KB HTML table. Allow ample headroom over the
    # collection-child implementation's 24 MB without accepting that cliff.
    @test @allocated(render()) < 64_000_000
end

@testitem "a response writes the bytes repr writes, retained snapshots once" tags=[:unit] begin
    using HTMXObjects
    body(r) = r.body isa AbstractString ? String(r.body) : String(copy(r.body))

    # Rows an app retains as snapshots (htmxo-use §8g), composed in a Node.
    rows = [HTMLSnapshot(h.div(repeat("payload < & > ", 600); id="row-$i")) for i in 1:100]
    panel = h.div(h.h2("Rows"), rows...)
    html = repr("text/html", panel)
    @test body(to_response(panel)) == html
    respond() = to_response(panel)
    respond()
    # Snag html-response-bu-1c2ff016: `repr` doubled one buffer from 32 bytes,
    # so this 1.44 MB answer allocated 4.7 MB and copied every retained row into
    # each doubling. The answer is now assembled once, at its exact size.
    @test @allocated(respond()) < 1.25 * ncodeunits(html)
    # Returned whole, a snapshot's stored bytes are the answer.
    whole = HTMLSnapshot(panel)
    @test whole.html == html
    @test body(to_response(whole)) == html
    respond_whole() = to_response(whole)
    respond_whole()
    @test @allocated(respond_whole()) < 16_000

    # The writer keeps strings of 512 bytes or more by reference and copies the
    # rest; either side of that threshold, and around Unicode, escapes, Raw
    # blocks, a document and a semantic element, the bytes are `repr`'s.
    for k in (1, 100, 502, 503, 504, 2000)
        cell = HTMLSnapshot(h.td("x"^k))
        node = h.table(h.tbody([h.tr(h.td("cell $i <&> \"ü€\""), cell) for i in 1:50]...))
        @test body(to_response(node)) == repr("text/html", node)
        @test HTMLSnapshot(node).html == repr("text/html", node)
    end
    doc = HTMXObjects.HTMLDocument(h.html(h.head(h.title("T")),
        h.body(h.p("ü"^3000; title="a\"b<c>"), HTMXObjects.HTMX.Raw("<b>r</b>"^200), h.br())))
    @test body(to_response(doc)) == repr("text/html", doc)
    section = SemanticSection("S <x>", SemanticProse("prose & more"), SemanticFields(status="ok"))
    @test body(to_response(section)) == repr("text/html", section)
    @test body(to_response(h.div())) == "<div></div>"
end
