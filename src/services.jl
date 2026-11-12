# Service composition uses the ordinary registrar and operation runner. A service
# has separate public and internal routers; loading a definition never exposes it.

"""
    ServiceSlice(name; routes, internal=[], forwards=[], compile=nothing, owns=[])

Select a service's public routes and additional internally callable operations.
Collections use the same descriptors, names, URLs and regexes as
[`precompile_routes!`](@ref). `forwards` contains `collection => service_name`
pairs: calls to these routes cross an explicit HTTP boundary instead of running
locally. `compile` defaults to the local public and internal routes and may
include other, unexposed operations. `owns` names application resources whose
initialization and writes belong to this service alone.

Selections may overlap and need not cover the application. Pure Julia property
calls remain local; this does not rewrite arbitrary calls into RPC. Use
[`dispatch`](@ref) for a declared HTTP operation boundary.
"""
struct ServiceSlice
    name::Symbol
    routes::Any
    internal::Any
    forwards::Vector{Pair}
    compile::Any
    owns::Vector{Symbol}
end
ServiceSlice(name; routes, internal=[], forwards=[], compile=nothing, owns=[]) =
    ServiceSlice(Symbol(name), routes, internal, Pair[p for p in forwards],
                 compile, Symbol[x for x in owns])

"Resolved service routes, ownership and the authored application's descriptor."
struct ServicePlan
    root::Type
    slices::Vector{NamedTuple}
    resources::Vector{NamedTuple}
    descriptor::NamedTuple
end

_service_route_key(route) = (route.verb, route.path)
_service_keys(routes) = Set(_service_route_key(route) for route in routes)
_service_routes(T, selection) = [route for (_, route) in _resolve_collection(T, selection)]

# Only HTTP/mount wiring is inferred here. DynamicObjects owns requirement
# traversal, containment context, boundary stopping and uncertainty diagnostics.
function _service_declarations(root, plans, resources)
    descriptor = application_descriptor(root)
    route_nodes = Dict{Tuple{Symbol,String},Vector{String}}()
    properties = Dict{Tuple{Symbol,String},Set{String}}()
    mounts = Set(n.id for n in descriptor.nodes if n.kind === :mount && n.fragment == "htmxobjects")
    for node in descriptor.nodes
        node.kind === :route && node.fragment == "htmxobjects" || continue
        key = (node.metadata.verb, node.metadata.path)
        push!(get!(Vector{String}, route_nodes, key), node.id)
        property = node.metadata.property_node
        property === nothing || push!(get!(Set{String}, properties, key), property)
    end
    edges = NamedTuple[]
    for edge in descriptor.edges
        edge.fragment == "htmxobjects" || continue
        if edge.kind === :reads
            push!(edges, _architecture_edge(:depends_on, edge.from, edge.to;
                metadata=(; via=edge.id, role=:operation_or_mount)))
        elseif edge.kind === :serves ||
                (edge.kind === :contains && edge.from in mounts && edge.to in mounts)
            push!(edges, _architecture_edge(:depends_on, edge.to, edge.from;
                metadata=(; via=edge.id, role=:mount_context)))
        end
    end
    nodes = NamedTuple[]
    service_ids = Dict{Symbol,String}()
    for plan in plans
        id = "htmx:service:" * _architecture_component(plan.name)
        service_ids[plan.name] = id
        push!(nodes, _architecture_node(id, :service, string(plan.name), (; name=plan.name)))
        public = _service_keys(plan.public)
        for route in plan.local_routes, target in route_nodes[_service_route_key(route)]
            exposure = _service_route_key(route) in public ? :public : :internal
            push!(edges, _architecture_edge(:depends_on, id, target;
                metadata=(; role=:local, exposure)))
        end
        for (key, destination) in sort!(collect(plan.forwards); by=first), target in route_nodes[key]
            exposure = key in public ? :public : :internal
            push!(edges, _architecture_edge(:depends_on, id, target;
                metadata=(; role=:forward, destination, exposure)))
        end
    end
    for resource in resources
        id = "htmx:resource:" * _architecture_component(resource.name)
        push!(nodes, _architecture_node(id, :resource, string(resource.name),
            (; name=resource.name)))
        push!(edges, _architecture_edge(:owns, service_ids[resource.owner], id))
        for route in resource.routes, target in route_nodes[_service_route_key(route)]
            push!(edges, _architecture_edge(:guards, id, target))
        end
    end
    descriptor = application_descriptor(root;
        contributions=((; namespace="htmxobjects.services", nodes, edges),))
    graph = _declaration_graph_from_application(descriptor)
    selected = NamedTuple[]
    for plan in plans
        boundaries = String[id for key in keys(plan.forwards) for id in route_nodes[key]]
        execution = DynamicObjects.declaration_selection(graph, service_ids[plan.name]; boundaries)
        compile_roots = String[id for route in plan.compile for id in route_nodes[_service_route_key(route)]]
        compilation = DynamicObjects.declaration_selection(graph, compile_roots)
        push!(selected, merge(plan, (; execution, compilation)))
    end
    (; descriptor, selected, properties)
end

"""
    service_plan(root, slices; resources=[]) -> ServicePlan

Resolve explicit service slices against one authored application's route
inventory. `resources` contains `resource_name => route_collection` pairs naming
every operation that accesses that mutable resource. Exactly one slice must own
each resource, and only its owner may execute those operations locally. Mutation
routes cannot execute in two services. GET is not proof of purity: declare
resources used by effectful reads too.

The plan preserves full mount/parameter descriptors, distinguishes public,
internal, forwarded and compile-only routes, and retains all package definitions.
It neither constructs the root nor executes a property. Unknown selections,
missing destinations and conflicting owners are errors.

Each slice's `execution` and `compilation` fields are DynamicObjects declaration
selections: required IDs, external boundaries, containing context, original
records, selection reasons and unresolved diagnostics. Mount computations are
retained alongside operation dependencies. `execution.unresolved` reports
uncertain dynamic/nested reads; all definitions remain loaded conservatively,
so an empty diagnostic list is not a whole-program or purity proof.
"""
function service_plan(root::Type, slices; resources=[])
    names = Symbol[slice.name for slice in slices]
    length(unique(names)) == length(names) || throw(ArgumentError("duplicate service names"))
    isempty(names) && throw(ArgumentError("a service plan needs at least one slice"))
    plans = NamedTuple[]
    for slice in slices
        public = _service_routes(root, slice.routes)
        internal = _service_routes(root, slice.internal)
        forwards = Dict{Tuple{Symbol,String},Symbol}()
        for (selection, destination) in slice.forwards
            destination = Symbol(destination)
            destination in names || throw(ArgumentError("unknown destination service $destination"))
            destination == slice.name && throw(ArgumentError("service $(slice.name) forwards to itself"))
            for route in _service_routes(root, selection)
                route.verb in (:SSE, :WEBSOCKET) && throw(ArgumentError(
                    "service boundaries require buffered HTTP operations"))
                key = _service_route_key(route)
                haskey(forwards, key) && throw(ArgumentError("duplicate forwarding boundary $key"))
                forwards[key] = destination
            end
        end
        local_routes = unique([r for r in vcat(public, internal)
                               if !haskey(forwards, _service_route_key(r))])
        compile = slice.compile === nothing ? copy(local_routes) :
                  _service_routes(root, slice.compile)
        for route in vcat(public, internal, compile)
            route.verb in (:SSE, :WEBSOCKET) && throw(ArgumentError(
                "service slices currently support buffered HTTP operations, not $(route.verb) $(route.path)"))
        end
        push!(plans, (; name=slice.name, public, internal, local_routes,
                       forwards, compile, owns=copy(slice.owns)))
    end
    byname = Dict(p.name => p for p in plans)
    local_keys = Dict(p.name => _service_keys(p.local_routes) for p in plans)
    mutation_owner = Dict{Tuple{Symbol,String},Symbol}()
    for plan in plans
        for (key, destination) in plan.forwards
            key in local_keys[destination] || throw(ArgumentError(
                "unresolved boundary $key from $(plan.name): $destination must execute it locally"))
        end
        for key in local_keys[plan.name]
            _verb_mutation(string(first(key))) || continue
            owner = get(mutation_owner, key, plan.name)
            owner == plan.name || throw(ArgumentError(
                "mutation $key has two local owners: $owner and $(plan.name)"))
            mutation_owner[key] = plan.name
        end
    end
    resource_plans = NamedTuple[]
    declared_resources = Set{Symbol}()
    for (name, selection) in resources
        name = Symbol(name)
        name in declared_resources && throw(ArgumentError("duplicate resource $name"))
        push!(declared_resources, name)
        owners = [p.name for p in plans if name in p.owns]
        length(owners) == 1 || throw(ArgumentError(
            "resource $name needs exactly one owner; found $(repr(owners))"))
        owner = only(owners)
        routes = _service_routes(root, selection)
        keys = _service_keys(routes)
        for plan in plans
            plan.name == owner && continue
            overlap = intersect(keys, local_keys[plan.name])
            isempty(overlap) || throw(ArgumentError(
                "service $(plan.name) executes $name operations $(collect(overlap)); owner is $owner, declare a forward"))
        end
        push!(resource_plans, (; name, owner, routes))
    end
    for plan in plans, name in plan.owns
        name in declared_resources || throw(ArgumentError("owned resource $name has no operation declaration"))
    end
    (; descriptor, selected, properties) = _service_declarations(root, plans, resource_plans)
    for resource in resource_plans
        resource_properties = Set{String}()
        for route in resource.routes
            union!(resource_properties, get(properties, _service_route_key(route), Set{String}()))
        end
        for plan in selected
            plan.name === resource.owner && continue
            overlap = intersect(resource_properties, Set(plan.execution.required))
            isempty(overlap) || throw(ArgumentError(
                "service $(plan.name) directly requires $(resource.name) operations owned by $(resource.owner); use dispatch at the declared forwarding boundary"))
        end
    end
    ServicePlan(root, selected, resource_plans, descriptor)
end
service_plan(root, slices; kwargs...) = service_plan(typeof(root), slices; kwargs...)

"""
    service_topology(plan_or_descriptor)

Project `htmxobjects.services` into `htmxobjects.service-topology/v1`, without
constructing an application or evaluating properties. `services` contain `id`,
`name`, `operations` and owned resource IDs. Each operation retains its route
`id`, `verb`, `path`, `role` (`:local`/`:forward`), `exposure`
(`:public`/`:internal`) and `destination`. `connections` group forwarded
operations by source/destination service ID. `resources` contain their owner
service ID and guarded route IDs. Ordering is deterministic. Older fragments
without exposure metadata report `:unknown`, never an assumed public route.
"""
service_topology(plan::ServicePlan) = service_topology(plan.descriptor)
function service_topology(descriptor::NamedTuple)
    descriptor.schema == _APPLICATION_DESCRIPTOR_SCHEMA || throw(ArgumentError(
        "expected $(_APPLICATION_DESCRIPTOR_SCHEMA)"))
    nodes = Dict(n.id => n for n in descriptor.nodes)
    services = sort!([n for n in descriptor.nodes
        if n.fragment == "htmxobjects.services" && n.kind === :service]; by=n -> n.id)
    resources = sort!([n for n in descriptor.nodes
        if n.fragment == "htmxobjects.services" && n.kind === :resource]; by=n -> n.id)
    names = Dict(n.metadata.name => n.id for n in services)
    operations = Dict(n.id => NamedTuple[] for n in services)
    owned = Dict(n.id => String[] for n in services)
    owners = Dict{String,String}()
    guarded = Dict(n.id => String[] for n in resources)
    connections = Dict{Tuple{String,String},Vector{NamedTuple}}()
    for edge in descriptor.edges
        edge.fragment == "htmxobjects.services" || continue
        if edge.kind === :owns
            push!(owned[edge.from], edge.to)
            owners[edge.to] = edge.from
        elseif edge.kind === :guards
            push!(guarded[edge.from], edge.to)
        elseif haskey(operations, edge.from) && edge.kind === :depends_on
            route = nodes[edge.to]
            role = edge.metadata.role
            destination = role === :forward ? names[edge.metadata.destination] : nothing
            operation = (; id=route.id, verb=route.metadata.verb,
                path=route.metadata.path, role,
                exposure=get(edge.metadata, :exposure, :unknown), destination)
            push!(operations[edge.from], operation)
            if destination !== nothing
                push!(get!(Vector{NamedTuple}, connections, (edge.from, destination)), operation)
            end
        end
    end
    order = op -> (string(op.verb), op.path, op.id)
    (; schema="htmxobjects.service-topology/v1",
        services=[(; id=n.id, name=n.metadata.name,
            operations=sort!(operations[n.id]; by=order), resources=sort!(owned[n.id])) for n in services],
        connections=[(; source=key[1], destination=key[2],
            operations=sort!(connections[key]; by=order)) for key in sort!(collect(keys(connections)))],
        resources=[(; id=n.id, name=n.metadata.name, owner=owners[n.id],
            routes=sort!(guarded[n.id])) for n in resources])
end

function _service_slice(plan::ServicePlan, name)
    index = findfirst(p -> p.name == Symbol(name), plan.slices)
    index === nothing && throw(ArgumentError("unknown service $(repr(name))"))
    plan.slices[index]
end

"""
    service_owns(plan, service, resource) -> Bool

Check a declared resource's owner before constructing application state or
starting its singleton background work. This is a plan check, not a distributed
lock: a deployment must run only one active generation of a mutable owner.
"""
function service_owns(plan::ServicePlan, service, resource)
    slice = _service_slice(plan, service)
    any(r -> r.name == Symbol(resource), plan.resources) ||
        throw(ArgumentError("unknown resource $(repr(resource))"))
    Symbol(resource) in slice.owns
end

"""
    precompile_routes!(plan::ServicePlan, service)

Compile this slice's selected handler shapes without executing their bodies.
Compile-only operations remain absent from both public and internal routers.
"""
precompile_routes!(plan::ServicePlan, name) =
    precompile_routes!(plan.root, _service_slice(plan, name).compile)

const _SERVICE_SCOPE = ScopedValues.ScopedValue{Any}(nothing)
const _SERVICE_OBSERVATIONS_PATH = "/__htmxobjects/services/observations"

Base.@kwdef mutable struct _ServiceCounts
    requests::Int = 0
    completed::Int = 0
    failures::Int = 0
    client_errors::Int = 0
    server_errors::Int = 0
    exceptions::Int = 0
    transport_errors::Int = 0
    total_seconds::Float64 = 0.0
    max_seconds::Float64 = 0.0
end

mutable struct _ServiceMetric
    lifetime::_ServiceCounts
    buckets::Vector{Tuple{Int,_ServiceCounts}}
    active::Int
    last_activity::Union{Nothing,Float64}
    last_seconds::Union{Nothing,Float64}
end
_ServiceMetric() = _ServiceMetric(_ServiceCounts(),
    [(typemin(Int), _ServiceCounts()) for _ in 1:60], 0, nothing, nothing)

_service_second() = floor(Int, time_ns() / 1.0e9)
function _service_bucket!(metric, second)
    index = mod(second, length(metric.buckets)) + 1
    stamp, bucket = metric.buckets[index]
    if stamp != second
        bucket = _ServiceCounts()
        metric.buckets[index] = (second, bucket)
    end
    bucket
end

function _service_completed!(counts, status, seconds, transport)
    counts.completed += 1
    counts.failures += status == 0 || status >= 400
    counts.client_errors += 400 <= status < 500
    counts.server_errors += status >= 500
    counts.exceptions += status == 0
    counts.transport_errors += transport
    counts.total_seconds += seconds
    counts.max_seconds = max(counts.max_seconds, seconds)
end

function _service_counts(counts)
    (; requests=counts.requests, completed=counts.completed, failures=counts.failures,
        client_errors=counts.client_errors, server_errors=counts.server_errors,
        exceptions=counts.exceptions, transport_errors=counts.transport_errors,
        latency=(; total_seconds=counts.total_seconds,
            mean_seconds=counts.completed == 0 ? nothing : counts.total_seconds / counts.completed,
            max_seconds=counts.completed == 0 ? nothing : counts.max_seconds))
end

function _service_metric_snapshot(metric, second)
    recent = _ServiceCounts()
    for (stamp, bucket) in metric.buckets
        second - 60 < stamp <= second || continue
        for name in fieldnames(_ServiceCounts)
            value = getfield(bucket, name)
            setfield!(recent, name, name === :max_seconds ? max(recent.max_seconds, value) :
                getfield(recent, name) + value)
        end
    end
    (; active=metric.active, last_activity=metric.last_activity,
        last_seconds=metric.last_seconds, lifetime=_service_counts(metric.lifetime),
        recent=_service_counts(recent))
end

function _service_measure(f, service, key, req)
    metric = service.metrics[key]
    started = time_ns()
    lock(service.lock) do
        metric.active += 1
        metric.last_activity = time()
        metric.lifetime.requests += 1
        _service_bucket!(metric, _service_second()).requests += 1
    end
    status = 0
    # A new request scope owns its transport outcome, including nested dispatch.
    transport = Ref(false)
    try
        response = ScopedValues.with(_SERVICE_SCOPE => (; service, request=req, transport)) do
            f()
        end
        status = response.status
        response
    finally
        seconds = (time_ns() - started) / 1.0e9
        lock(service.lock) do
            metric.active -= 1
            metric.last_activity = time()
            metric.last_seconds = seconds
            _service_completed!(metric.lifetime, status, seconds, transport[])
            _service_completed!(_service_bucket!(metric, _service_second()), status, seconds, transport[])
        end
    end
end

"""
    ServiceRuntime(plan, service, app; endpoints=Dict(), token,
                   contract, middleware=[], root_provider=nothing,
                   identity_headers=["Authorization", "Cookie", "X-Request-ID"],
                   request_timeout=60, metrics=true)

Build isolated public and internal routers using the ordinary route registrar.
`app` is an instance of the plan's root. Run one instance of each application
type per process. Both local and forwarded `dispatch` calls pass through the
provided application `middleware`, as do public requests.

`endpoints` maps destination service names to trusted HTTP base URLs. Peers must
share a nonempty deployment `token` and an explicit `contract` version. The
reserved service headers are accepted only with that token; a peer may call
only the boundaries its slice declares. Identity headers propagate through
nested dispatch, along with audience, language and request ID. A service is
buffered and blocking: no poll token can outlive its process. HTTP failures
surface as 502 and mutations are never retried automatically.
`request_timeout` bounds each peer call (overall deadline on HTTP 2; read timeout
rounded up to whole seconds on HTTP 1). Arbitrary application context and
`StaticExport` do not cross peers.

Use `serve(service; ...)` to listen, and [`drain_service!`](@ref) before replacing
the process. Draining rejects new requests with 503 and waits for active work;
it never cancels work or claims a timed-out operation completed.

`metrics=true` collects bounded per-operation counts and latency summaries,
including forwarded calls. Set `metrics=false` to disable collection. Read them
with [`service_observations`](@ref); expose a protected system page explicitly
with [`mount_service_monitor!`](@ref). No request bodies or raw URLs are retained.
"""
mutable struct ServiceRuntime
    plan::ServicePlan
    name::Symbol
    public::HTTP.Router
    local_router::HTTP.Router
    calls::HTTP.Router
    incoming::Dict{Symbol,HTTP.Router}
    endpoints::Dict{Symbol,String}
    token::String
    contract::String
    generation::String
    middleware::Vector
    identity_headers::Vector{String}
    request_timeout::Float64
    lock::ReentrantLock
    accepting::Bool
    active::Int
    metrics::Union{Nothing,Dict{Tuple{Symbol,String},_ServiceMetric}}
    started_at::Float64
    monitors::Dict{String,Function}
end

function _service_register!(router, routes, handler)
    for route in routes
        # Include the same trailing-default URL variants as the registrar.
        path_params = [p for p in route.params if p.source === :path && !p.inherited]
        paths = String[route.path]
        for p in reverse(path_params)
            p.required && break
            endswith(last(paths), "/{" * string(p.name) * "}") || break
            push!(paths, first(rsplit(last(paths), '/'; limit=2)))
        end
        for path in paths
            HTTP.register!(router, string(route.verb), isempty(path) ? "/" : path, handler)
        end
    end
end

function _service_local_router(T, routes, provider, policy)
    routers = (; all=HTTP.Router(), get=HTTP.Router(_ -> _NoGetRoute(), _ -> _NoGetRoute()))
    task_local_storage(:htmxo_registration_routers, routers) do
        _register_routes(T; root_provider=provider, operation_policy=policy,
                         selection=_service_keys(routes))
    end
    routers.all
end

function ServiceRuntime(plan::ServicePlan, name, app; endpoints=Dict(), token,
        contract, middleware=[], root_provider=nothing,
        identity_headers=["Authorization", "Cookie", "X-Request-ID"], request_timeout::Real=60,
        metrics::Bool=true)
    typeof(app) === plan.root || throw(ArgumentError("app type differs from the service plan"))
    isempty(token) && throw(ArgumentError("a service deployment token must not be empty"))
    isempty(contract) && throw(ArgumentError("an explicit service contract version is required"))
    isfinite(request_timeout) && request_timeout > 0 ||
        throw(ArgumentError("request_timeout must be finite and positive"))
    any(_service_header, identity_headers) && throw(ArgumentError(
        "identity_headers must not contain reserved service headers"))
    slice = _service_slice(plan, name)
    any(r -> r.path == _SERVICE_OBSERVATIONS_PATH, reflect(plan.root)) && throw(ArgumentError(
        "$(_SERVICE_OBSERVATIONS_PATH) is reserved for authenticated service observations"))
    addresses = Dict{Symbol,String}()
    for (peer, url) in endpoints
        url = rstrip(String(url), '/')
        uri = HTTP.URI(url)
        uri.scheme in ("http", "https") && !isempty(uri.host) &&
            isempty(uri.userinfo) && isempty(uri.path) && isempty(uri.query) &&
            isempty(uri.fragment) || throw(ArgumentError("service endpoint for $peer must be an HTTP origin"))
        addresses[Symbol(peer)] = url
    end
    for peer in values(slice.forwards)
        haskey(addresses, peer) || throw(ArgumentError("missing endpoint for service $peer"))
    end
    (; provider, policy) = _configure_route_root!(app; root_provider,
                                                 operation_policy=OperationPolicy(:blocking))
    local_router = _service_local_router(plan.root, slice.local_routes, provider, policy)
    service = ServiceRuntime(plan, slice.name, HTTP.Router(), local_router, HTTP.Router(),
        Dict{Symbol,HTTP.Router}(), addresses, String(token), String(contract),
        Random.randstring(24), collect(middleware), String[h for h in identity_headers],
        Float64(request_timeout), ReentrantLock(), true, 0,
        metrics ? Dict(key => _ServiceMetric() for key in
            union(_service_keys(slice.local_routes), keys(slice.forwards))) : nothing, time(),
        Dict{String,Function}())
    # Unknown routes still pass through application policy, but never allocate
    # a metric keyed by an arbitrary caller-controlled URL.
    service.public = _service_empty_router(service)
    service.calls = _service_empty_router(service)
    for route in slice.local_routes
        key = _service_route_key(route)
        _service_register!(service.calls, [route],
            req -> _service_run(service, local_router, req; key))
    end
    inventory = reflect(plan.root)
    for (key, peer) in slice.forwards
        routes = filter(r -> _service_route_key(r) == key, inventory)
        _service_register!(service.calls, routes,
            req -> _service_run(service, r -> _service_forward(service, peer, r), req; key))
    end
    _service_register!(service.public, slice.public, req -> service.calls(req))
    for caller in plan.slices
        allowed = [r for r in slice.local_routes
                   if get(caller.forwards, _service_route_key(r), nothing) == slice.name]
        isempty(allowed) && continue
        router = _service_empty_router(service)
        _service_register!(router, allowed, req -> service.calls(req))
        service.incoming[caller.name] = router
    end
    service
end

_service_empty_router(service) = HTTP.Router(
    req -> _service_run(service, _ -> HTTP.Response(404), req),
    req -> _service_run(service, _ -> HTTP.Response(405), req))

_service_header(name) = startswith(lowercase(String(name)), "x-htmxo-service-")
const _SERVICE_HOP_HEADERS = Set(["connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade", "host", "content-length"])

function _service_headers(req)
    hop = union(_SERVICE_HOP_HEADERS,
        Set(lowercase(strip(s)) for s in split(HTTP.header(req, "Connection", ""), ',')))
    Pair{String,String}[String(k) => String(v) for (k,v) in req.headers
                       if !(lowercase(k) in hop) && !_service_header(k)]
end

function _service_forward(service, peer, req; request_timeout=service.request_timeout)
    haskey(req.context, :htmxo_static_export) && throw(ArgumentError(
        "StaticExport dispatch cannot cross a service boundary"))
    headers = _service_headers(req)
    append!(headers, ["X-HTMXO-Service-Token" => service.token,
        "X-HTMXO-Service-Contract" => service.contract,
        "X-HTMXO-Service-Caller" => string(service.name),
        "X-HTMXO-Service-Audience" => string(export_audience(req))])
    lang = get(req.context, :htmxo_lang, nothing)
    lang === nothing || push!(headers, "X-HTMXO-Service-Lang" => lang)
    timeout = pkgversion(HTTP) >= v"2" ? (; request_timeout) :
              (; readtimeout=ceil(Int, request_timeout))
    try
        response = HTTP.request(req.method, service.endpoints[peer] * req.target,
            headers, req.body; status_exception=false, retry=false, redirect=false,
            connect_timeout=min(10, ceil(Int, request_timeout)), decompress=false, cookies=false, timeout...)
        HTTP.Response(response.status, _service_headers(response), response.body)
    catch err
        err isa HTTP.Exceptions.HTTPError || rethrow()
        scope = _SERVICE_SCOPE[]
        scope === nothing || (scope.transport[] = true)
        # No automatic retry: after a lost response a mutation may have committed.
        HTTP.Response(502, ["Content-Type" => "text/plain; charset=utf-8"],
            "Service $peer is unavailable; the operation outcome may be unknown.\n")
    end
end

function _service_run(service, router, req; key=nothing)
    if key !== nothing && service.metrics !== nothing
        return _service_measure(service, key, req) do
            _service_apply(service, router, req)
        end
    end
    ScopedValues.with(_SERVICE_SCOPE => (; service, request=req, transport=Ref(false))) do
        _service_apply(service, router, req)
    end
end

function _service_apply(service, router, req)
    requested = get(req.context, :htmxo_operation_policy, nothing)
    requested === nothing || _blocking_policy(requested) || throw(ArgumentError(
        "service slices require blocking operations; polling policies cannot cross process generations"))
    req.context[:htmxo_operation_policy] = OperationPolicy(:blocking)
    isempty(HTTP.header(req, "X-Request-ID", "")) &&
        HTTP.setheader(req, "X-Request-ID" => Random.randstring(24))
    app = request -> begin
        # These transports may detach work from the admitted HTTP request.
        # Refuse them before the ordinary registrar can start such work.
        if _preload_request(request) || _operation_poll_request(request) ||
                _operation_attach_request(request)
            return HTTP.Response(400, "Service slices require a new blocking request, without preload or polling markers.\n")
        end
        router(request)
    end
    for middleware in reverse(service.middleware)
        app = middleware(app)
    end
    app(req)
end

function _service_authenticate!(service, req; observations=false)
    HTTP.header(req, "X-HTMXO-Service-Token", "") == service.token || return HTTP.Response(403)
    HTTP.header(req, "X-HTMXO-Service-Contract", "") == service.contract ||
        return HTTP.Response(409, "Service contract mismatch.\n")
    # Do not intern arbitrary unauthenticated request data as Symbols.
    caller_name = HTTP.header(req, "X-HTMXO-Service-Caller", "")
    index = findfirst(s -> string(s.name) == caller_name, service.plan.slices)
    index === nothing && return HTTP.Response(403)
    caller = service.plan.slices[index].name
    (observations || haskey(service.incoming, caller)) || return HTTP.Response(403)
    audience = HTTP.header(req, "X-HTMXO-Service-Audience", "")
    audience in ("public", "private") || return HTTP.Response(400)
    req.context[:htmxo_audience] = Symbol(audience)
    lang = HTTP.header(req, "X-HTMXO-Service-Lang", "")
    isempty(lang) || (req.context[:htmxo_lang] = _check_lang(lang, "service request"))
    for name in [first(h) for h in req.headers if _service_header(first(h))]
        HTTP.removeheader(req, String(name))
    end
    caller
end

function (service::ServiceRuntime)(req::HTTP.Request)
    path = HTTP.URI(req.target).path
    if path == _SERVICE_OBSERVATIONS_PATH
        caller = _service_authenticate!(service, req; observations=true)
        caller isa HTTP.Response && return caller
        return _service_run(service, request -> request.method == "GET" ?
            _service_json(service_observations(service)) : HTTP.Response(405), req)
    elseif haskey(service.monitors, path)
        if any(h -> _service_header(first(h)), req.headers)
            caller = _service_authenticate!(service, req; observations=true)
            caller isa HTTP.Response && return caller
        end
        return _service_run(service, request -> request.method == "GET" ?
            service.monitors[path](request) : HTTP.Response(405), req)
    end
    admitted = lock(service.lock) do
        service.accepting || return false
        service.active += 1
        true
    end
    admitted || return HTTP.Response(503, ["Retry-After" => "1"], "Service is draining.\n")
    try
        router = service.public
        if any(h -> _service_header(first(h)), req.headers)
            caller = _service_authenticate!(service, req)
            caller isa HTTP.Response && return caller
            router = service.incoming[caller]
        end
        response = router(req)
        HTTP.setheader(response, "X-HTMXO-Service-Generation" => service.generation)
        HTTP.setheader(response, "X-Request-ID" => HTTP.header(req, "X-Request-ID"))
        response
    finally
        lock(service.lock) do
            service.active -= 1
        end
    end
end

function _service_dispatch(req)
    scope = _SERVICE_SCOPE[]
    scope === nothing && return ROUTER(req)
    service = scope.service
    if !haskey(req.context, :htmxo_lang)
        lang = get(scope.request.context, :htmxo_lang, nothing)
        lang === nothing || (req.context[:htmxo_lang] = lang)
    end
    for name in service.identity_headers
        isempty(HTTP.header(req, name, "")) || continue
        value = HTTP.header(scope.request, name, "")
        isempty(value) || HTTP.setheader(req, name => value)
    end
    service.calls(req)
end

_service_json(value) = HTTP.Response(200,
    ["Content-Type" => "application/json", "Cache-Control" => "no-store"], _schema_json(value))

function _service_sum_counts(records)
    counts = _ServiceCounts()
    for record in records
        for name in (:requests, :completed, :failures, :client_errors, :server_errors,
                     :exceptions, :transport_errors)
            setfield!(counts, name, getfield(counts, name) + getproperty(record, name))
        end
        counts.total_seconds += record.latency.total_seconds
        counts.max_seconds = max(counts.max_seconds, something(record.latency.max_seconds, 0.0))
    end
    _service_counts(counts)
end

function _service_snapshot(service)
    slice = _service_slice(service.plan, service.name)
    lock(service.lock) do
        operations = NamedTuple[]
        if service.metrics !== nothing
            second = _service_second()
            for key in sort!(collect(keys(service.metrics)))
                destination = get(slice.forwards, key, nothing)
                push!(operations, merge((; verb=key[1], path=key[2],
                    role=destination === nothing ? :local : :forward, destination),
                    _service_metric_snapshot(service.metrics[key], second)))
            end
        end
        grouped = Dict{Symbol,Vector{NamedTuple}}()
        for operation in operations
            operation.destination === nothing && continue
            push!(get!(Vector{NamedTuple}, grouped, operation.destination), operation)
        end
        forwards = [begin
            records = grouped[peer]
            times = [r.last_activity for r in records if r.last_activity !== nothing]
            (; destination=peer, active=sum(r.active for r in records),
                last_activity=isempty(times) ? nothing : maximum(times),
                lifetime=_service_sum_counts(r.lifetime for r in records),
                recent=_service_sum_counts(r.recent for r in records))
        end for peer in sort!(collect(keys(grouped)))]
        (; generation=service.generation, started_at=service.started_at,
            accepting=service.accepting, active=service.active,
            metrics=service.metrics !== nothing, window_seconds=60,
            operations, forwards)
    end
end

_service_number(x) = x isa Real && !(x isa Bool) && isfinite(x) && x >= 0
_service_optional_number(x) = x === nothing || _service_number(x)
function _service_valid_counts(counts)
    counts isa AbstractDict || return false
    all(k -> get(counts, k, nothing) isa Integer && !(counts[k] isa Bool) && counts[k] >= 0,
        ("requests", "completed", "failures", "client_errors", "server_errors", "exceptions", "transport_errors")) || return false
    latency = get(counts, "latency", nothing)
    latency isa AbstractDict && _service_number(get(latency, "total_seconds", nothing)) &&
        all(k -> haskey(latency, k) && _service_optional_number(latency[k]), ("mean_seconds", "max_seconds"))
end
function _service_valid_metric(metric)
    metric isa AbstractDict && get(metric, "active", nothing) isa Integer && metric["active"] >= 0 &&
        haskey(metric, "last_activity") && _service_optional_number(metric["last_activity"]) &&
        all(k -> _service_valid_counts(get(metric, k, nothing)), ("lifetime", "recent"))
end
function _service_valid_snapshot(snapshot)
    snapshot isa AbstractDict || return false
    get(snapshot, "generation", nothing) isa AbstractString &&
        _service_number(get(snapshot, "started_at", nothing)) &&
        get(snapshot, "accepting", nothing) isa Bool && get(snapshot, "metrics", nothing) isa Bool &&
        get(snapshot, "active", nothing) isa Integer && snapshot["active"] >= 0 &&
        get(snapshot, "window_seconds", nothing) == 60 || return false
    operations, forwards = get(snapshot, "operations", nothing), get(snapshot, "forwards", nothing)
    operations isa AbstractVector && forwards isa AbstractVector || return false
    all(op -> _service_valid_metric(op) && get(op, "verb", nothing) isa AbstractString &&
        get(op, "path", nothing) isa AbstractString && get(op, "role", nothing) in ("local", "forward") &&
        (get(op, "destination", nothing) === nothing || op["destination"] isa AbstractString), operations) &&
        all(f -> _service_valid_metric(f) && get(f, "destination", nothing) isa AbstractString, forwards)
end

"""
    service_observations(runtime; peer=runtime.name, headers=[], timeout=2)

Read `htmxobjects.service-observations/v1` without executing application work.
The local read is a consistent locked snapshot. A different `peer` performs one
authenticated, non-retried HTTP read using `endpoints` and the deployment
token/contract; runtime middleware still applies. Pass identity `headers` when
calling outside a request; within a request the configured identity headers,
audience and language are inherited. Timeout has the transport's HTTP 1/2 rules.

The result has `service`, `status`, `checked_at` (Unix seconds), `elapsed_seconds`,
`http_status` and `snapshot`. Status is `:ok`, `:unconfigured`, `:unavailable`,
`:denied`, `:incompatible` or `:invalid`; failed reads have no snapshot and are
never interpreted as zero traffic. Successful remote snapshots are plain JSON
records (string keys); local snapshots are named tuples. Both share the schema.

Snapshots contain the process `generation`, `started_at`, `accepting`, `active`,
`metrics`, per-route `operations` and per-destination `forwards`. Each metric
contains `lifetime` and `recent` counts: requests begun, completed, failures
(HTTP >=400 or thrown exceptions), client/server/exception/transport categories,
and total/mean/maximum latency in seconds. Operations also retain active calls,
last activity (Unix seconds) and last duration. The recent window comprises the
current monotonic-clock second and preceding 59 seconds; starts and completions
belong to their respective seconds. Storage never grows with request count or
URL parameters. Counts reset with the runtime's generation. Inspection does not
count itself, and lack of traffic says nothing about peer health.
"""
function service_observations(service::ServiceRuntime; peer=service.name, headers=[], timeout::Real=2)
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("timeout must be finite and positive"))
    name = string(peer)
    index = findfirst(s -> string(s.name) == name, service.plan.slices)
    index === nothing && throw(ArgumentError("unknown service $(repr(peer))"))
    peer = service.plan.slices[index].name
    envelope(status, snapshot=nothing; http_status=nothing, elapsed_seconds=0.0) =
        (; schema="htmxobjects.service-observations/v1", service=name, status,
            checked_at=time(), elapsed_seconds, http_status, snapshot)
    peer === service.name && return envelope(:ok, _service_snapshot(service); http_status=200)
    haskey(service.endpoints, peer) || return envelope(:unconfigured)
    req = HTTP.Request("GET", _SERVICE_OBSERVATIONS_PATH, [String(k) => String(v) for (k,v) in headers])
    scope = _SERVICE_SCOPE[]
    if scope !== nothing
        for header in service.identity_headers
            isempty(HTTP.header(req, header, "")) || continue
            value = HTTP.header(scope.request, header, "")
            isempty(value) || HTTP.setheader(req, header => value)
        end
        req.context[:htmxo_audience] = export_audience(scope.request)
        lang = get(scope.request.context, :htmxo_lang, nothing)
        lang === nothing || (req.context[:htmxo_lang] = lang)
    end
    started = time_ns()
    # Observation transport failures must not contaminate an enclosing business call.
    response = ScopedValues.with(_SERVICE_SCOPE => (; service, request=req, transport=Ref(false))) do
        _service_forward(service, peer, req; request_timeout=Float64(timeout))
    end
    elapsed = (time_ns() - started) / 1.0e9
    if response.status != 200
        status = response.status in (401, 403) ? :denied :
            response.status == 409 ? :incompatible : :unavailable
        return envelope(status; http_status=response.status, elapsed_seconds=elapsed)
    end
    data = try
        JSON.parse(String(response.body))
    catch err
        err isa ArgumentError || rethrow()
        return envelope(:invalid; http_status=200, elapsed_seconds=elapsed)
    end
    if !(data isa AbstractDict) || get(data, "schema", nothing) != "htmxobjects.service-observations/v1" ||
            get(data, "service", nothing) != name || get(data, "status", nothing) != "ok" ||
            !_service_valid_snapshot(get(data, "snapshot", nothing))
        return envelope(:invalid; http_status=200, elapsed_seconds=elapsed)
    end
    envelope(:ok, data["snapshot"]; http_status=200, elapsed_seconds=elapsed)
end

function _service_all_observations(service, timeout)
    records = Vector{Any}(undef, length(service.plan.slices))
    @sync for (i, slice) in enumerate(service.plan.slices)
        @async records[i] = service_observations(service; peer=slice.name, timeout)
    end
    records
end

"""
    mount_service_monitor!(runtime; path="/services", timeout=2)

Mount a Services page plus `path * "/topology"` and `path * "/observations"`
JSON endpoints directly on this runtime, without adding application routes or
changing its plan. All three apply runtime middleware and remain readable while
draining. The page and observations endpoint read all services concurrently,
using explicitly configured peer origins and a bounded timeout per read.
Unconfigured peers stay visible as unconfigured. No polling/background tasks
continue after the request: refresh the page to take another snapshot.

Mount before serving. Paths must be literal absolute paths without a trailing
slash; an existing application/monitor path is refused. Mounting is explicit:
protect it with runtime middleware like other private operational pages.
"""
function mount_service_monitor!(service::ServiceRuntime; path="/services", timeout::Real=2)
    path = String(path)
    startswith(path, "/") && path != "/" && !endswith(path, "/") &&
        !occursin(r"[?#{\s]", path) || throw(ArgumentError("monitor path must be a literal absolute path"))
    isfinite(timeout) && timeout > 0 || throw(ArgumentError("timeout must be finite and positive"))
    paths = [path, path * "/topology", path * "/observations"]
    any(p -> p == _SERVICE_OBSERVATIONS_PATH || haskey(service.monitors, p), paths) &&
        throw(ArgumentError("monitor path is already reserved or mounted"))
    # Match through the normal registrar, so parameterized routes conflict too.
    probe = HTTP.Router(_ -> false, _ -> true)
    _service_register!(probe, reflect(service.plan.root), _ -> true)
    any(p -> probe(HTTP.Request("GET", p)), paths) && throw(ArgumentError("monitor path shadows an application route"))
    topology = service_topology(service.plan)
    service.monitors[path * "/topology"] = _ -> _service_json(topology)
    service.monitors[path * "/observations"] = _ -> _service_json(_service_all_observations(service, timeout))
    service.monitors[path] = _ -> begin
        observations = _service_all_observations(service, timeout)
        page = pico_page(service_topology_view(topology; observations, refresh=path);
            title="Services")
        HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8", "Cache-Control" => "no-store"],
            sprint(show, MIME"text/html"(), page))
    end
    service
end

"""
    drain_service!(service; timeout=30) -> Bool

Refuse new requests, then wait at most `timeout` seconds for active requests to
finish. Return `true` only when no work remains. A `false` result leaves the
service draining; outstanding requests retain ownership until they finish or
their process exits. Calling this again continues waiting.
"""
function drain_service!(service::ServiceRuntime; timeout::Real=30)
    isfinite(timeout) && timeout >= 0 || throw(ArgumentError("timeout must be finite and nonnegative"))
    lock(service.lock) do
        service.accepting = false
    end
    timedwait(() -> lock(() -> service.active == 0, service.lock), timeout;
              pollint=0.01) === :ok
end

"""
    serve(service::ServiceRuntime; kwargs...)

Listen with this service's isolated router and the normal HTMXObjects HTTP
pipeline. Service operations are blocking and buffered; automatic page prestart
and the process-global operation stream are disabled. Put application policy in
the runtime's `middleware`, so it applies to internal calls as well.
"""
function serve(service::ServiceRuntime; prestart=false, operation_stream=false,
        revise=nothing, middleware=[], kwargs...)
    prestart === false && operation_stream === false || throw(ArgumentError(
        "service slices require prestart=false and operation_stream=false"))
    revise in (nothing, :none) || throw(ArgumentError(
        "replace a service process to load new definitions; Revise is not supported"))
    isempty(middleware) || throw(ArgumentError(
        "put service policy in ServiceRuntime(middleware=...), so it also protects internal calls"))
    _serve(service; prestart=false, operation_stream=false, revise, kwargs...)
end
