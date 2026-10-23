using TestItemRunner

# An app linked its own fragments by URL string (`lazy("/usage_line")`), so a
# renamed or mistyped route failed only when the browser asked for it.
# `route_url(self, :name, args...; kwargs...)` resolves the route on `self`'s
# struct and checks the call when the page renders (todo `0p1mocj`, stage 3).

@testitem "route_url builds an app's own route address and checks the call" tags=[:unit] begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: h

    @htmx struct RouteUrlApp
        @param year::Int = 2026
        @get index() = h.main(lazy(route_url(__self__, :route_url_usage; n=3); id="usage"))
        @get route_url_usage(; n::Int=1) = h.p("n=$n")
        @get route_url_item(id::Int; format::String="html") = h.p("$id.$format")
        @get route_url_named(name::String) = h.p(name)
        @get route_url_needs(; q::String) = h.p(q)
        @post route_url_save() = h.p("saved")
        @include route_url_sub = begin
            @get index() = h.p(route_url(__self__, :leaf; k="v"))
            @get leaf(; k::String="") = h.p(k)
        end
    end
    app = RouteUrlApp()
    route!(app)

    @test route_url(app, :route_url_usage; n=3) == "/route_url_usage?n=3"
    @test route_url(app, :route_url_usage) == "/route_url_usage"
    @test route_url(app, :route_url_usage; n=nothing) == "/route_url_usage"
    @test route_url(app, :index) == "/"
    @test route_url(app, :route_url_item, 42; format="json") == "/route_url_item/42?format=json"
    @test route_url(app, :route_url_named, "a/b c") == "/route_url_named/a%2Fb%20c"
    # A struct's `@param` is a parameter of each of its routes.
    @test route_url(app, :route_url_usage; year=2025) == "/route_url_usage?year=2025"

    err(f) = try
        f(); nothing
    catch e
        e isa ArgumentError ? e.msg : rethrow()
    end
    @test occursin("RouteUrlApp has no GET route `route_url_missing`", err(() -> route_url(app, :route_url_missing)))
    @test occursin("has no GET route `route_url_save`", err(() -> route_url(app, :route_url_save)))
    @test occursin("takes 1 path argument (id), got 0", err(() -> route_url(app, :route_url_item)))
    @test occursin("has no parameter `m`", err(() -> route_url(app, :route_url_usage; m=1)))
    @test occursin("requires `q`", err(() -> route_url(app, :route_url_needs)))
    @test occursin("`n` is a Int64; got \"abc\"", err(() -> route_url(app, :route_url_usage; n="abc")))
    @test occursin("`id` is a Int64; got 3.5", err(() -> route_url(app, :route_url_item, 3.5)))
    @test err(() -> route_url(app, :route_url_usage; n="7")) === nothing

    # In a page: the address the fragment loads from, and under a mount and a
    # proxy prefix the browser-facing one.
    body(target, headers...) =
        String(HTMXObjects._message_body_bytes(dispatch(:GET, target; headers=collect(headers))))
    @test occursin("hx-get=\"/route_url_usage?n=3\"", body("/"))
    @test occursin("hx-get=\"/p/app/route_url_usage?n=3\"", body("/", "X-Forwarded-Prefix" => "/p/app"))
    @test occursin("<p>/route_url_sub/leaf?k=v</p>", body("/route_url_sub"))
    @test occursin("<p>/p/app/route_url_sub/leaf?k=v</p>", body("/route_url_sub", "X-Forwarded-Prefix" => "/p/app"))
end
