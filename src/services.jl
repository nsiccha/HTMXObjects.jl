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
function _service_declarations(root, plans)
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
        for route in plan.local_routes, target in route_nodes[_service_route_key(route)]
            push!(edges, _architecture_edge(:depends_on, id, target; metadata=(; role=:local)))
        end
        for (key, destination) in sort!(collect(plan.forwards); by=first), target in route_nodes[key]
            push!(edges, _architecture_edge(:depends_on, id, target;
                metadata=(; role=:forward, destination)))
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
    (; descriptor, selected, properties) = _service_declarations(root, plans)
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

"""
    ServiceRuntime(plan, service, app; endpoints=Dict(), token,
                   contract, middleware=[], root_provider=nothing,
                   identity_headers=["Authorization", "Cookie", "X-Request-ID"],
                   request_timeout=60)

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
        identity_headers=["Authorization", "Cookie", "X-Request-ID"], request_timeout::Real=60)
    typeof(app) === plan.root || throw(ArgumentError("app type differs from the service plan"))
    isempty(token) && throw(ArgumentError("a service deployment token must not be empty"))
    isempty(contract) && throw(ArgumentError("an explicit service contract version is required"))
    isfinite(request_timeout) && request_timeout > 0 ||
        throw(ArgumentError("request_timeout must be finite and positive"))
    any(_service_header, identity_headers) && throw(ArgumentError(
        "identity_headers must not contain reserved service headers"))
    slice = _service_slice(plan, name)
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
        Float64(request_timeout), ReentrantLock(), true, 0)
    _service_register!(service.calls, slice.local_routes, req -> local_router(req))
    inventory = reflect(plan.root)
    for (key, peer) in slice.forwards
        routes = filter(r -> _service_route_key(r) == key, inventory)
        _service_register!(service.calls, routes, req -> _service_forward(service, peer, req))
    end
    _service_register!(service.public, slice.public, req -> service.calls(req))
    for caller in plan.slices
        allowed = [r for r in slice.local_routes
                   if get(caller.forwards, _service_route_key(r), nothing) == slice.name]
        isempty(allowed) && continue
        router = HTTP.Router()
        _service_register!(router, allowed, req -> local_router(req))
        service.incoming[caller.name] = router
    end
    service
end

_service_header(name) = startswith(lowercase(String(name)), "x-htmxo-service-")
const _SERVICE_HOP_HEADERS = Set(["connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade", "host", "content-length"])

function _service_headers(req)
    hop = union(_SERVICE_HOP_HEADERS,
        Set(lowercase(strip(s)) for s in split(HTTP.header(req, "Connection", ""), ',')))
    Pair{String,String}[String(k) => String(v) for (k,v) in req.headers
                       if !(lowercase(k) in hop) && !_service_header(k)]
end

function _service_forward(service, peer, req)
    haskey(req.context, :htmxo_static_export) && throw(ArgumentError(
        "StaticExport dispatch cannot cross a service boundary"))
    headers = _service_headers(req)
    append!(headers, ["X-HTMXO-Service-Token" => service.token,
        "X-HTMXO-Service-Contract" => service.contract,
        "X-HTMXO-Service-Caller" => string(service.name),
        "X-HTMXO-Service-Audience" => string(export_audience(req))])
    lang = get(req.context, :htmxo_lang, nothing)
    lang === nothing || push!(headers, "X-HTMXO-Service-Lang" => lang)
    timeout = pkgversion(HTTP) >= v"2" ? (; request_timeout=service.request_timeout) :
              (; readtimeout=ceil(Int, service.request_timeout))
    try
        response = HTTP.request(req.method, service.endpoints[peer] * req.target,
            headers, req.body; status_exception=false, retry=false, redirect=false,
            connect_timeout=10, decompress=false, cookies=false, timeout...)
        HTTP.Response(response.status, _service_headers(response), response.body)
    catch err
        err isa HTTP.Exceptions.HTTPError || rethrow()
        # No automatic retry: after a lost response a mutation may have committed.
        HTTP.Response(502, ["Content-Type" => "text/plain; charset=utf-8"],
            "Service $peer is unavailable; the operation outcome may be unknown.\n")
    end
end

function _service_run(service, router, req)
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
    ScopedValues.with(_SERVICE_SCOPE => (; service, request=req)) do
        app(req)
    end
end

function (service::ServiceRuntime)(req::HTTP.Request)
    admitted = lock(service.lock) do
        service.accepting || return false
        service.active += 1
        true
    end
    admitted || return HTTP.Response(503, ["Retry-After" => "1"], "Service is draining.\n")
    try
        router = service.public
        if any(h -> _service_header(first(h)), req.headers)
            HTTP.header(req, "X-HTMXO-Service-Token", "") == service.token ||
                return HTTP.Response(403)
            HTTP.header(req, "X-HTMXO-Service-Contract", "") == service.contract ||
                return HTTP.Response(409, "Service contract mismatch.\n")
            caller = Symbol(HTTP.header(req, "X-HTMXO-Service-Caller", ""))
            haskey(service.incoming, caller) || return HTTP.Response(403)
            router = service.incoming[caller]
            audience = HTTP.header(req, "X-HTMXO-Service-Audience", "")
            audience in ("public", "private") || return HTTP.Response(400)
            req.context[:htmxo_audience] = Symbol(audience)
            lang = HTTP.header(req, "X-HTMXO-Service-Lang", "")
            isempty(lang) || (req.context[:htmxo_lang] = _check_lang(lang, "service request"))
            # Deployment credentials are transport metadata, never app input.
            for name in [first(h) for h in req.headers if _service_header(first(h))]
                HTTP.removeheader(req, String(name))
            end
        end
        response = _service_run(service, router, req)
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
    _service_run(service, service.calls, req)
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
