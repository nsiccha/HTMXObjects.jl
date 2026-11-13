@testitem "runtime catalog shares text and gives each page fresh nodes" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _runtime_catalog, _runtime_block, _runtime_text, _runtime_head
    import HTMX

    catalog = _runtime_catalog()
    @test _runtime_catalog() === catalog
    for name in catalog.names
        expected = repr("text/html", last(getfield(HTMXObjects._runtime_blocks(), name))())
        @test repr("text/html", _runtime_block(name)) == expected
        first = _runtime_block(name)
        push!(HTMX.children(first), Raw("caller-owned addition"))
        HTMX.attrs(first)[:id] = "caller-owned"
        @test repr("text/html", _runtime_block(name)) == expected
        asset = catalog.assets[name]
        @test _runtime_text(name) === asset.text
        @test contains(repr("text/html", _runtime_head(name, "/vendor")),
            "/vendor/htmxo/$(asset.file)?v=$(asset.version)")
    end
end

@testitem "runtime catalog notices extension provider installation without a new method world" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _polling_page_assets_impl, _runtime_catalog, _runtime_text

    original = _polling_page_assets_impl[]
    provider = () -> (h.style(Raw("catalog-test-style")), h.script(Raw("catalog-test-script")))
    try
        _polling_page_assets_impl[] = nothing
        absent = _runtime_catalog()
        @test !haskey(absent.assets, :treebars_styles)
        @test_throws ErrorException _runtime_text(:treebars_styles)
        world = Base.get_world_counter()
        _polling_page_assets_impl[] = provider
        present = _runtime_catalog()
        @test Base.get_world_counter() == world
        @test present !== absent
        @test _runtime_text(:treebars_styles) == "catalog-test-style"
        @test _runtime_text(:treebars_script) == "catalog-test-script"
        @test _runtime_catalog() === present
        _polling_page_assets_impl[] = nothing
        @test _runtime_catalog() === absent
    finally
        _polling_page_assets_impl[] = original
    end
end
