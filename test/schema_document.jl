using TestItemRunner

# `GET /schema` describes each inherited `@param` once and lets routes refer
# to it; `?inherited=inline` keeps the flat `reflect` array (snag
# `schemaroutes-rep-4e4caea7`: ~115 root params repeated on ~217 routes made
# a 3 MB answer).
@testmodule SchemaDocumentFixtures begin
    using HTMXObjects
    export SDLeaf, SDMid, SDRoot

    @htmx struct SDLeaf
        @get read(id::Int; q::String="") = "read"
        @post write(; note::String="") = "write"
    end

    @htmx struct SDMid
        "The mid-level value, shadowing the root's."
        @param shared::Int = 2
        @param mid_only::Symbol = :m
        @include leaf = SDLeaf()
        @get index() = "mid"
    end

    @htmx struct SDRoot
        "The root-level value."
        @param shared::String = "root"
        @param other::Int = 1
        @include sd_mid = SDMid()
        @include sd_leaf = SDLeaf()
        @include sd_schema = SchemaRoutes(; root=SDRoot)
        @get sd_status() = "ok"
    end
end

@testitem "schema document - inherited @params are described once" setup=[SchemaDocumentFixtures] tags=[:unit] begin
    using HTMXObjects
    doc = HTMXObjects._schema_document(SDRoot)
    key(T, name) = string(T, ".", name)
    route(verb, path) = only(filter(r -> r.verb === verb && r.path == path, doc.routes))
    names(r) = [p.name for p in r.params]
    context(r) = doc.contexts[r.context]

    # One entry per declaration: the shadowing `shared` on SDMid is its own key.
    @test Set(keys(doc.params)) == Set([key(SDRoot, :shared), key(SDRoot, :other),
                                        key(SDMid, :shared), key(SDMid, :mid_only)])
    @test doc.params[key(SDRoot, :shared)] == (name=:shared, declared_by=SDRoot,
        type=String, required=false, default="root", doc="The root-level value.")
    @test doc.params[key(SDMid, :shared)].type === Int
    @test doc.params[key(SDMid, :shared)].declared_by === SDMid

    # A route keeps its call params inline and refers to its inherited context.
    read = route(:GET, "/sd_leaf/read/{id}")
    @test names(read) == [:id, :q]
    @test context(read) == [key(SDRoot, :shared), key(SDRoot, :other)]
    @test read.context_source === :query
    write = route(:POST, "/sd_leaf/write")
    @test names(write) == [:note]
    @test write.context == read.context          # one id per distinct set
    @test write.context_source === :body

    # The nearest declaring ancestor wins below a shadowing mount.
    @test context(route(:GET, "/sd_mid/leaf/read/{id}")) ==
          [key(SDMid, :shared), key(SDMid, :mid_only), key(SDRoot, :other)]
    # A struct's own `@param`s stay inline on its own routes.
    mid = route(:GET, "/sd_mid")
    @test names(mid) == [:shared, :mid_only]
    @test context(mid) == [key(SDRoot, :other)]
    status = route(:GET, "/sd_status")
    @test names(status) == [:shared, :other]
    @test status.context === nothing && status.context_source === nothing
end

@testitem "schema document - loses nothing reflect reports" setup=[SchemaDocumentFixtures] tags=[:unit] begin
    using HTMXObjects
    doc = HTMXObjects._schema_document(SDRoot)
    flat = HTMXObjects.reflect(SDRoot)
    @test [(r.verb, r.path, r.name, r.doc) for r in doc.routes] ==
          [(r.verb, r.path, r.name, r.doc) for r in flat]
    expand(route) = route.context === nothing ? NamedTuple[] :
        [(name=p.name, source=route.context_source, type=p.type,
          required=p.required, default=p.default, doc=p.doc, inherited=true)
         for p in (doc.params[k] for k in doc.contexts[route.context])]
    for (shared, inline) in zip(doc.routes, flat)
        @test Set(vcat(shared.params, expand(shared))) == Set(inline.params)
        @test length(shared.params) + length(expand(shared)) == length(inline.params)
    end
end

@testitem "GET /schema serves the document; ?inherited=inline the flat array" setup=[SchemaDocumentFixtures] tags=[:unit] begin
    using HTMXObjects
    route!(SDRoot())
    body(response) = String(response.body)

    default = dispatch(:GET, "/sd_schema")
    @test default.status == 200
    @test body(default) ==
          HTMXObjects._schema_json_encode(HTMXObjects._schema_document(SDRoot))
    @test startswith(body(default), "{\"routes\":")
    @test body(dispatch(:GET, "/sd_schema?inherited=shared")) == body(default)

    inline = dispatch(:GET, "/sd_schema?inherited=inline")
    @test inline.status == 200
    @test body(inline) == HTMXObjects._schema_json_encode(HTMXObjects.reflect(SDRoot))
    @test startswith(body(inline), "[")

    bad = dispatch(:GET, "/sd_schema?inherited=sometimes")
    @test bad.status == 400
    @test contains(body(bad), "Invalid value for parameter inherited")
end
