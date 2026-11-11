using TestItemRunner

@testitem "service selections preserve mounts and separate public internal and compile routes" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    writes = Ref(0)
    @htmx struct SliceFixture
        @param factor::Int = 2
        calls::Base.RefValue{Int} = writes
        pure(x::Int) = x * factor
        @get omitted() = "omitted"
        @include item(key::String) = begin
            @get read(x::Int=3) = string(key, ":", pure(x))
            @post write(; x::Int) = begin
                calls[] += 1
                string(x)
            end
            @get hidden() = string(key)
        end
    end
    routes = reflect(SliceFixture)
    public = select_routes(routes; names=:read)
    hidden = select_routes(routes; names=:hidden)
    write = select_routes(routes; names=:write)
    plan = service_plan(SliceFixture, [
        ServiceSlice(:readers; routes=public, internal=hidden, compile=vcat(public, write)),
        ServiceSlice(:writers; routes=write, owns=[:stream]),
    ]; resources=[:stream => write])
    @test writes[] == 0
    readers = only(filter(s -> s.name === :readers, plan.slices))
    @test DynamicObjects.declaration_node_id(HTMXObjects._declaration_graph_from_application(plan.descriptor),
        SliceFixture, :item) in readers.execution.required
    @test service_owns(plan, :writers, :stream)
    @test !service_owns(plan, :readers, :stream)
    @test_throws ArgumentError service_owns(plan, :writers, :unknown)
    runtime = ServiceRuntime(plan, :readers, SliceFixture(); token="test-token",
                             contract="fixture/v1")
    unsupported = HTTP.Request("GET", "/item/a/hidden")
    unsupported.context[:htmxo_operation_policy] = OperationPolicy(:polling)
    @test_throws ArgumentError HTMXObjects._service_run(runtime, runtime.calls, unsupported)
    @test_throws ArgumentError serve(runtime; revise=:lazy)
    @test_throws ArgumentError serve(runtime; operation_stream=true)
    response = runtime(HTTP.Request("GET", "/item/a%20b/read/4?factor=5"))
    @test response.status == 200
    @test String(response.body) == "a b:20"
    short = runtime(HTTP.Request("GET", "/item/short/read?factor=4"))
    @test short.status == 200
    @test String(short.body) == "short:12"
    @test runtime(HTTP.Request("GET", "/omitted")).status == 404
    @test runtime(HTTP.Request("GET", "/item/a/hidden")).status == 404
    @test runtime(HTTP.Request("POST", "/item/a/write")).status == 404
    @test runtime(HTTP.Request("GET", "/item/a/read/4", ["HX-Preloaded" => "true"])).status == 400
    @test runtime(HTTP.Request("GET", "/item/a/read/4?__htmxo_poll=1")).status == 400
    @test String(HTMXObjects._service_run(runtime, runtime.calls,
        HTTP.Request("GET", "/item/a/hidden")).body) == "a"
    @test HTMXObjects.ROUTER(HTTP.Request("GET", "/item/a/read/4")).status == 404
    compiled = precompile_routes!(plan, :readers)
    @test Set(r.name for r in compiled) == Set([:read, :write])
    @test writes[] == 0
    @test drain_service!(runtime; timeout=1)
    @test runtime(HTTP.Request("GET", "/item/a/read/4")).status == 503
end

@testitem "service plans reject unresolved boundaries and duplicate mutable owners" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    @htmx struct SliceOwnershipFixture
        @get pure() = "pure"
        @get effectful_read() = "touches owned state"
        @get direct_read() = effectful_read()
        @post append(; value::Int) = string(value)
        @get omitted() = "omitted"
    end
    a = ServiceSlice(:a; routes=[:pure])
    b = ServiceSlice(:b; routes=[:pure])
    @test length(service_plan(SliceOwnershipFixture, [a, b]).slices) == 2
    @test_throws ArgumentError service_plan(SliceOwnershipFixture, [a, a])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:missing])])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:append]), ServiceSlice(:b; routes=[:append])])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:pure], forwards=[:append => :b]), b])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:pure], forwards=[:append => :missing])])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:effectful_read], owns=[:state]),
         ServiceSlice(:b; routes=[:effectful_read])]; resources=[:state => :effectful_read])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:effectful_read], owns=[:state]),
         ServiceSlice(:b; routes=[:direct_read], forwards=[:effectful_read => :a])];
        resources=[:state => :effectful_read])
    @test_throws ArgumentError service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:pure], owns=[:state]),
         ServiceSlice(:b; routes=[:pure], owns=[:state])]; resources=[:state => :effectful_read])
    plan = service_plan(SliceOwnershipFixture,
        [ServiceSlice(:a; routes=[:pure], forwards=[:effectful_read => :b]),
         ServiceSlice(:b; routes=[:effectful_read], owns=[:state])];
        resources=[:state => :effectful_read])
    @test_throws ArgumentError ServiceRuntime(plan, :a, SliceOwnershipFixture();
        token="token", contract="v1")
end

@testitem "service dependency plans retain local chains and expose unresolved reads without evaluating" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    evaluations = Ref(0)
    @htmx struct SliceDependencyFixture
        counter::Base.RefValue{Int}
        observations = begin
            counter[] += 1
            5
        end
        helper = observations * 2
        @get assess() = string(helper)
        @get forecast() = dispatch(:GET, "/assess")
        @get local_forecast() = string(helper + 1)
        @get opaque() = getproperty(__self__, Symbol("helper"))
        @get omitted() = "omitted"
    end
    app = SliceDependencyFixture(evaluations)
    plan = service_plan(app, [
        ServiceSlice(:owner; routes=[], internal=[:assess]),
        ServiceSlice(:reader; routes=[:forecast, :local_forecast, :opaque],
            forwards=[:assess => :owner], compile=[:assess]),
    ])
    slice = only(filter(s -> s.name === :reader, plan.slices))
    graph = HTMXObjects._declaration_graph_from_application(plan.descriptor)
    node(name) = DynamicObjects.declaration_node_id(graph, SliceDependencyFixture, name)
    @test node(:helper) in slice.execution.required
    @test node(:observations) in slice.execution.required
    @test node(:assess) ∉ slice.execution.required
    @test node(:assess) in slice.compilation.required
    @test node(:omitted) ∉ slice.execution.required
    external = only(slice.execution.boundaries)
    @test only(filter(n -> n.id == external, slice.execution.nodes)).metadata.name === :assess
    @test any(r -> r.node == external && r.edge !== nothing, slice.execution.reasons)
    @test any(d -> d.node == node(:opaque) && d.kind === :opaque_dependencies, slice.execution.unresolved)
    @test evaluations[] == 0
    repeated = service_plan(SliceDependencyFixture, [
        ServiceSlice(:owner; routes=[], internal=[:assess]),
        ServiceSlice(:reader; routes=[:forecast, :local_forecast, :opaque],
            forwards=[:assess => :owner], compile=[:assess]),
    ])
    @test plan.descriptor == repeated.descriptor
    @test plan.slices == repeated.slices
end

@testitem "service calls preserve policy identity and failures across a real HTTP boundary" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server] begin
    @htmx struct SliceBoundaryFixture
        counter::Base.RefValue{Int}
        @get identity() = HTTP.header(__req__, "X-Actor", "missing")
        @get view() = dispatch(:GET, "/identity")
        @fresh @get cookie() = HTTP.Response(200,
            ["Set-Cookie" => "service-session=server; Path=/"],
            HTTP.header(__req__, "Cookie", "none"))
        @fresh @get context() = join((
            get(__req__.context, :htmxo_lang, "missing"),
            string(export_audience(__req__)),
            HTTP.header(__req__, "X-HTMXO-Service-Token", "absent")), ":")
        @get context_view() = dispatch(:GET, "/context"; lang="de", audience=:private)
        @post update(; value::Int) = begin
            counter[] += 1
            string(value)
        end
        @post local_only() = "local"
    end
    plan = service_plan(SliceBoundaryFixture, [
        ServiceSlice(:front; routes=[:view, :context_view, :update, :cookie],
            forwards=[:identity => :owner, :context => :owner, :update => :owner, :cookie => :owner]),
        ServiceSlice(:owner; routes=[], internal=[:identity, :context, :update, :local_only, :cookie]),
    ])
    checked = Ref(0)
    policy = next -> req -> begin
        checked[] += 1
        HTTP.header(req, "X-Actor", "") == "reader" || return HTTP.Response(401)
        next(req)
    end
    port = free_port()
    # Two runtimes of one root type here share the identical root template;
    # the independent-process fixture verifies actual state isolation.
    app = SliceBoundaryFixture(Ref(0))
    owner = ServiceRuntime(plan, :owner, app; token="secret", contract="v1",
        middleware=[policy], identity_headers=["X-Actor", "X-Request-ID"])
    server = HTTP.serve!(owner, "127.0.0.1", port; verbose=false)
    front = ServiceRuntime(plan, :front, app; token="secret", contract="v1",
        endpoints=Dict(:owner => "http://127.0.0.1:$port"), middleware=[policy],
        identity_headers=["X-Actor", "X-Request-ID"])
    try
        request = HTTP.Request("GET", "/view", ["X-Actor" => "reader", "X-Request-ID" => "request-1"])
        result = front(request)
        @test result.status == 200
        @test String(result.body) == "reader"
        @test HTTP.header(result, "X-Request-ID") == "request-1"
        @test checked[] == 3 # public front, local dispatch policy, remote policy
        context = front(HTTP.Request("GET", "/context_view", ["X-Actor" => "reader"]))
        @test context.status == 200
        @test String(context.body) == "de:private:absent"
        body_headers = ["X-Actor" => "reader", "Content-Type" => "application/x-www-form-urlencoded"]
        written = front(HTTP.Request("POST", "/update", body_headers, "value=7"))
        @test written.status == 200
        @test String(written.body) == "7"
        @test app.counter[] == 1
        cookie = front(HTTP.Request("GET", "/cookie", ["X-Actor" => "reader", "Cookie" => "session=client"]))
        @test String(cookie.body) == "session=client"
        @test HTTP.header(cookie, "Set-Cookie") == "service-session=server; Path=/"
        other_client = front(HTTP.Request("GET", "/cookie", ["X-Actor" => "reader"]))
        @test String(other_client.body) == "none"
        @test front(HTTP.Request("POST", "/update", body_headers, "value=invalid")).status == 400
        @test app.counter[] == 1
        @test front(HTTP.Request("GET", "/view")).status == 401
        @test owner(HTTP.Request("GET", "/identity", ["X-Actor" => "reader"])).status == 404
        @test owner(HTTP.Request("GET", "/identity", ["X-HTMXO-Service-Token" => "wrong"])).status == 403
        headers = ["X-HTMXO-Service-Token" => "secret", "X-HTMXO-Service-Caller" => "front",
                   "X-HTMXO-Service-Contract" => "wrong", "X-HTMXO-Service-Audience" => "private",
                   "X-Actor" => "reader"]
        @test owner(HTTP.Request("GET", "/identity", headers)).status == 409
        headers[3] = "X-HTMXO-Service-Contract" => "v1"
        @test owner(HTTP.Request("POST", "/local_only", headers)).status == 404
    finally
        close(server)
    end
    @test front(HTTP.Request("GET", "/view", ["X-Actor" => "reader"])).status == 502
end
