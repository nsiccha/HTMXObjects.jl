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
