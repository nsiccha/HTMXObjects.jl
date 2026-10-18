using TestItemRunner

# `reflect` resolves every inherited `@param` of every route. The walk caches
# that resolution (snag `schemaroutes-rep-4e4caea7`: ~115 root params on ~217
# routes cost ~25k DO meta scans per `/schema` read). These items pin that the
# cached answer is the per-route answer — nearest declaring ancestor, source by
# verb — and that the cache is actually what serves a walk.
@testmodule ReflectCacheFixtures begin
    using HTMXObjects
    export RCLeaf, RCMid, RCRoot

    @htmx struct RCLeaf
        @get a(; q::String="") = "a"
        @post b(; note::String="") = "b"
    end

    @htmx struct RCMid
        "The mid-level value, shadowing the root's."
        @param shared::Int = 2
        @include leaf = RCLeaf()
        @get index() = "mid"
    end

    @htmx struct RCRoot
        "The root-level value."
        @param shared::String = "root"
        @param other::Int = 1
        @include mid = RCMid()
        @include leaf = RCLeaf()
        @get index() = "root"
    end
end

@testitem "reflect - cached inherited params keep each route's own answer" setup=[ReflectCacheFixtures] tags=[:unit] begin
    using HTMXObjects
    routes = HTMXObjects.reflect(RCRoot)
    route(verb, path) = only(filter(r -> r.verb === verb && r.path == path, routes))
    param(r, name) = only(filter(p -> p.name === name, r.params))

    root_get = route(:GET, "/leaf/a")
    @test param(root_get, :q).inherited == false
    @test param(root_get, :shared) == (name=:shared, source=:query, type=String,
        required=false, default="root", doc="The root-level value.", inherited=true)
    @test param(root_get, :other).type === Int

    # Same owner, other verb: the cached list is per read-location.
    @test param(route(:POST, "/leaf/b"), :shared).source === :body

    # Same owner type under a different ancestor chain: the nearest
    # declaring ancestor wins, not whichever chain the cache saw first.
    mid_get = route(:GET, "/mid/leaf/a")
    @test param(mid_get, :shared).type === Int
    @test param(mid_get, :shared).default == 2
    @test param(mid_get, :shared).inherited
    @test param(route(:GET, "/mid"), :shared).inherited == false

    # Routes sharing a cached list still get their own `params` vectors.
    @test route(:GET, "/leaf/a").params !== route(:GET, "/mid/leaf/a").params
    @test length(unique(objectid(r.params) for r in routes)) == length(routes)
end

@testitem "reflect - one walk resolves each (type, param) once" setup=[ReflectCacheFixtures] tags=[:unit] begin
    using HTMXObjects
    cache = HTMXObjects._ReflectCache()
    acc = NamedTuple[]
    HTMXObjects._reflect_walk!(acc, RCRoot, ""; cache)
    @test acc == HTMXObjects.reflect(RCRoot)
    # One param list per (owner, read-location, ancestor chain) — not per route.
    @test Set(keys(cache.param_props)) == Set([
        (RCRoot, :query, ()),
        (RCMid, :query, (RCRoot,)),
        (RCLeaf, :query, (RCRoot,)), (RCLeaf, :body, (RCRoot,)),
        (RCLeaf, :query, (RCRoot, RCMid)), (RCLeaf, :body, (RCRoot, RCMid))])
    @test all(k -> k[2] in (:shared, :other), keys(cache.local_params))
    @test length(cache.local_params) <= 3 * 2
end
