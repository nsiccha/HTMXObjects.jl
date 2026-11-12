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
    @test length(service_topology(plan).services) == 2
    @test occursin("Services", sprint(show, MIME"text/html"(), service_topology_view(plan)))
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
        ServiceSlice(:observer; routes=[]),
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

        # Observation reads apply identity policy and deployment authentication,
        # but neither execute operations nor increase their counts.
        before = service_observations(owner).snapshot
        peer = service_observations(front; peer=:owner, headers=["X-Actor" => "reader"], timeout=30)
        @test peer.status == :ok
        @test peer.snapshot["generation"] == owner.generation
        @test service_observations(owner).snapshot.operations == before.operations
        observer = ServiceRuntime(plan, :observer, app; token="secret", contract="v1",
            endpoints=Dict(:owner => "http://127.0.0.1:$port"))
        @test service_observations(observer; peer=:owner, headers=["X-Actor" => "reader"]).status == :ok
        @test service_observations(front; peer=:owner).status == :denied
        front.token = "wrong"
        @test service_observations(front; peer=:owner, headers=["X-Actor" => "reader"]).status == :denied
        front.token = "secret"
        front.contract = "wrong"
        @test service_observations(front; peer=:owner, headers=["X-Actor" => "reader"]).status == :incompatible
        front.contract = "v1"
        @test owner(HTTP.Request("GET", HTMXObjects._SERVICE_OBSERVATIONS_PATH)).status == 403
        mount_service_monitor!(front)
        @test front(HTTP.Request("GET", "/services")).status == 401
        page = front(HTTP.Request("GET", "/services", ["X-Actor" => "reader"]))
        @test page.status == 200
        @test occursin("Responding", String(page.body))
        @test HTTP.header(page, "Cache-Control") == "no-store"
        @test drain_service!(owner; timeout=1)
        @test service_observations(front; peer=:owner, headers=["X-Actor" => "reader"]).snapshot["accepting"] == false
    finally
        close(server)
    end
    @test front(HTTP.Request("GET", "/view", ["X-Actor" => "reader"])).status == 502
    @test service_observations(front; peer=:owner, headers=["X-Actor" => "reader"], timeout=0.2).status == :unavailable
    observations = service_observations(front).snapshot
    forward = only(filter(o -> o.path == "/identity", observations.operations))
    @test forward.lifetime.requests == 2
    @test forward.lifetime.transport_errors == 1
    @test forward.lifetime.failures == 1
    @test only(observations.forwards).lifetime.transport_errors == 1
end

@testitem "malformed service observations remain distinct from idle peers" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:unit, :server] begin
    import JSON
    @htmx struct ObservationFixture
        @get read() = "ok"
    end
    plan = service_plan(ObservationFixture, [ServiceSlice(:reader; routes=[]),
        ServiceSlice(:writer; routes=[:read])])
    body = Ref("not JSON")
    port = free_port()
    server = HTTP.serve!(_ -> HTTP.Response(200, body[]), "127.0.0.1", port; verbose=false)
    runtime = ServiceRuntime(plan, :reader, ObservationFixture(); token="test", contract="v1",
        endpoints=Dict(:writer => "http://127.0.0.1:$port"))
    try
        @test service_observations(runtime; peer=:writer, timeout=30).status == :invalid
        body[] = JSON.json((; schema="htmxobjects.service-observations/v1",
            service="writer", status="ok", snapshot=Dict()))
        invalid = service_observations(runtime; peer=:writer)
        @test invalid.status == :invalid
        @test invalid.snapshot === nothing
        @test isempty(service_observations(runtime).snapshot.operations)
    finally
        close(server)
    end
end

@testitem "service topology projects ownership visibility and grouped forward operations" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    @htmx struct TopologyCalculation
        twice(x::Int) = 2x
        @get assess(; x::Int) = string(twice(x))
        @post append(; x::Int) = string(x)
        @get forecast(; x::Int) = dispatch(:GET, "/assess?x=$x")
    end
    plan = service_plan(TopologyCalculation, [
        ServiceSlice(:writer; routes=[:append], internal=[:assess], owns=[:stream]),
        ServiceSlice(:reader; routes=[:forecast, :append], forwards=[:assess => :writer, :append => :writer]),
    ]; resources=[:stream => [:append]])
    topology = service_topology(plan)
    @test topology == service_topology(plan.descriptor)
    @test length(topology.services) == 2
    @test length(only(topology.connections).operations) == 2
    writer = only(filter(s -> s.name == :writer, topology.services))
    @test only(topology.resources).owner == writer.id
    @test only(writer.resources) == only(topology.resources).id
    @test only(filter(o -> o.path == "/assess", writer.operations)).exposure == :internal
    @test only(filter(o -> o.path == "/append", writer.operations)).exposure == :public
    @test only(topology.resources).routes == [only(filter(o -> o.path == "/append", writer.operations)).id]
    @test Set(e.kind for e in plan.descriptor.edges if e.fragment == "htmxobjects.services") == Set([:depends_on, :owns, :guards])
    html = sprint(show, MIME"text/html"(), application_explorer_view(plan.descriptor))
    @test occursin("stream", html) && occursin("Forwards", html)
    @test occursin("internal", html) && occursin("public", html)
    @test !occursin("architecture-reference-title", html)
    full = sprint(show, MIME"text/html"(), application_explorer_view(plan.descriptor; view=:map))
    @test occursin("architecture-reference-title", full)
    @test occursin("Services", full)
    reflected = ReflectionRoutes(; plan)
    route!(reflected)
    router = HTMXObjects.ROUTER
    @test occursin("Forwards", String(router(HTTP.Request("GET", "/")).body))
    @test occursin("htmxobjects.services", String(router(HTTP.Request("GET", "/descriptor")).body))
    @test occursin("architecture-reference-title", String(router(HTTP.Request("GET", "/?view=map")).body))
    whole = service_plan(TopologyCalculation, [ServiceSlice(:whole;
        routes=[:append, :forecast], internal=[:assess], owns=[:stream])]; resources=[:stream => [:append]])
    @test isempty(service_topology(whole).connections)
    @test length(service_topology(whole).services) == 1
end

@testitem "service metrics count policy failures bounded routes and in-flight work" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    import JSON
    entered, released = Channel{Nothing}(1), Channel{Nothing}(1)
    @htmx struct MetricsFixture
        entered::Channel{Nothing}
        released::Channel{Nothing}
        @fresh @get read(; value::Int=1) = string(value)
        @fresh @get outer() = dispatch(:GET, "/read?value=9")
        @fresh @get held() = begin
            put!(entered, nothing)
            take!(released)
            "complete"
        end
    end
    plan = service_plan(MetricsFixture, [ServiceSlice(:only; routes=[:read, :outer, :held])])
    app = MetricsFixture(entered, released)
    policy = next -> req -> begin
        HTTP.header(req, "X-Fail") == "throw" && error("policy exception")
        HTTP.header(req, "X-Fail") == "deny" && return HTTP.Response(403)
        next(req)
    end
    runtime = ServiceRuntime(plan, :only, app; token="test", contract="v1", middleware=[policy])
    initial = service_observations(runtime)
    @test all(o -> o.lifetime.requests == 0, initial.snapshot.operations)
    @test runtime(HTTP.Request("GET", "/outer")).status == 200
    @test runtime(HTTP.Request("GET", "/read?value=invalid")).status == 400
    @test runtime(HTTP.Request("GET", "/read", ["X-Fail" => "deny"])).status == 403
    @test_throws ErrorException runtime(HTTP.Request("GET", "/read", ["X-Fail" => "throw"]))
    for i in 1:20
        @test runtime(HTTP.Request("GET", "/read?value=$i")).status == 200
        @test runtime(HTTP.Request("GET", "/missing/$i")).status == 404
    end
    snapshot = service_observations(runtime).snapshot
    read_metric = only(filter(o -> o.path == "/read", snapshot.operations))
    @test read_metric.lifetime.requests == read_metric.lifetime.completed == 24
    @test read_metric.lifetime.failures == 3
    @test read_metric.lifetime.client_errors == 2
    @test read_metric.lifetime.exceptions == 1
    @test read_metric.lifetime.latency.mean_seconds >= 0
    @test read_metric.last_activity !== nothing
    @test read_metric.recent.requests == read_metric.lifetime.requests
    @test read_metric.recent.failures == read_metric.lifetime.failures
    @test read_metric.recent.latency.total_seconds ≈ read_metric.lifetime.latency.total_seconds
    @test length(runtime.metrics) == 3
    @test all(m -> length(m.buckets) == 60, values(runtime.metrics))
    expired = HTMXObjects._service_metric_snapshot(runtime.metrics[(:GET, "/read")], HTMXObjects._service_second() + 61)
    @test expired.recent.requests == 0
    @test expired.lifetime.requests == 24
    pending = @async runtime(HTTP.Request("GET", "/held"))
    take!(entered)
    active = service_observations(runtime).snapshot
    @test active.active == 1
    @test only(filter(o -> o.path == "/held", active.operations)).active == 1
    mount_service_monitor!(runtime)
    @test_throws ArgumentError mount_service_monitor!(runtime; path="/read")
    @test_throws ArgumentError mount_service_monitor!(runtime)
    @test runtime(HTTP.Request("GET", "/services/topology")).status == 200
    @test runtime(HTTP.Request("GET", "/services/observations", ["X-Fail" => "deny"])).status == 403
    @test !drain_service!(runtime; timeout=0.01)
    monitor = runtime(HTTP.Request("GET", "/services/observations"))
    @test monitor.status == 200
    @test only(JSON.parse(String(monitor.body)))["snapshot"]["accepting"] == false
    put!(released, nothing)
    @test fetch(pending).status == 200
    @test drain_service!(runtime; timeout=1)
    @test service_observations(runtime).snapshot.active == 0
    disabled = ServiceRuntime(plan, :only, app; token="test", contract="v1", metrics=false)
    @test disabled(HTTP.Request("GET", "/read")).status == 200
    @test disabled.metrics === nothing
    @test service_observations(disabled).snapshot.metrics == false
    @test isempty(service_observations(disabled).snapshot.operations)
    @test service_observations(disabled).snapshot.generation != initial.snapshot.generation
    stale = merge(initial, (; checked_at=time() - 120))
    html = sprint(show, MIME"text/html"(), service_topology_view(plan; observations=[stale]))
    @test occursin("Stale observation", html)
end
