@dynamicstruct struct PosteriorsData
    columns::Vector{String} = ["alpha", "beta", "gamma", "delta", "epsilon"]
end

@htmx struct PosteriorsRoutes
    (; posteriors) = __appdata__
    (; columns) = posteriors

    @get index(; filter::String="", max::Int=5) = begin
        cols = isempty(filter) ? columns[1:min(max, end)] :
            filter!(c -> occursin(Regex(filter), c), copy(columns))[1:min(max, end)]
        h.div(
            h.form(; hx_get=__self__, hx_target="closest div", hx_swap="outerHTML")(
                h.input(; type="text", name="filter", value=filter, placeholder="Filter columns..."),
            ),
            h.div(; class="u-grid-auto")(
                [h.div(h.h5(col), lazy(query_url(__self__/"plot"; col)))
                 for col in cols]...
            )
        )
    end

    @get plot(; col::String) = begin
        sleep(0.5 + rand())
        h.article(h.header(col), h.p("Rendered: $col ($(round(rand(), digits=2)))"))
    end
end
