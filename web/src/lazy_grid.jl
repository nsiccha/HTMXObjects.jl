@dynamicstruct struct LazyGridData end

@htmx struct LazyGridRoutes
    @get index = h.div(
        h.h1("Lazy Grid Demo"),
        lazy("/posteriors"),
    )
end
