# Service slices

One authored application can run as a colocated service or as several Julia
processes. A `ServiceSlice` selects public routes, internal operations, explicit
forwarding boundaries and compile targets. Selections may overlap and may omit
parts of the application.

This API requires HTMXObjects 0.1.101 and DynamicObjects 0.5.19 or newer.

```@example service-plan
using HTMXObjects

@htmx struct Calculation
    twice(x::Int) = 2x
    @get assess(; x::Int) = string(twice(x))
    @get forecast(; x::Int) = dispatch(:GET, "/assess?x=$x")
    @get omitted() = "not selected"
end

plan = service_plan(Calculation, [
    ServiceSlice(:assessment; routes=[], internal=[:assess]),
    ServiceSlice(:forecast; routes=[:forecast], forwards=[:assess => :assessment],
                 compile=[:forecast, :assess]),
]);
[(s.name, public=[r.path for r in s.public], internal=[r.path for r in s.internal])
 for s in plan.slices]
```

The assessment process executes `/assess`, but that route is available only to
the forecast peer. The forecast process exposes `/forecast`. Neither exposes
`/omitted`. `compile=[:forecast, :assess]` makes both handler shapes compilation
targets in the forecast process; it does not expose or execute `/assess` there.
`precompile_routes!(plan, :forecast)` compiles without running operation bodies.

Collections accept route descriptors, names, concrete URLs and regular
expressions, as in [`precompile_routes!`](@ref). Use route descriptors or URLs
to distinguish the same operation mounted at different paths. Inherited mount
parameters and typed request parameters keep their ordinary route semantics.

## Local work and forwarding

Each slice has `execution` and `compilation` declaration selections.
DynamicObjects follows declared dependencies; HTMXObjects adds operation and
mount edges. Selections retain required declarations, context, external
boundaries, original records and edge-based reasons.

```@example service-plan
[(s.name, local_declarations=length(s.execution.required),
  external_boundaries=length(s.execution.boundaries)) for s in plan.slices]
```

Inspect `slice.execution.unresolved` for opaque, nested or missing declared
reads. These diagnostics remain visible while all definitions are retained;
they are not silently treated as a complete call graph. An empty list proves
neither purity nor complete coverage of arbitrary Julia helpers.

All application definitions are loaded in each process. Normal Julia property
calls and their dependencies remain local; service extraction does not rewrite
arbitrary Julia calls. Call [`dispatch`](@ref) at an explicit operation boundary.
Inside a service, it uses that slice's local and forwarded routes. A missing
local operation yields 404. A forwarding declaration must name a destination
which executes that operation locally; unresolved destinations fail at planning.

Internal routes are separate from the public interface. A peer is admitted only
to the routes that its slice explicitly forwards to this service. A caller cannot
turn every internal operation into a remotely callable endpoint.

```@example service-plan
function run_service(role; port, token)
    runtime = ServiceRuntime(plan, role, Calculation(); token,
        endpoints=Dict(:assessment => "http://127.0.0.1:9181"),
        contract="calculation/v1")
    serve(runtime; port)
end
nothing # hide
```

Call `run_service(:assessment; port=9181, token=ENV["HTMXO_SERVICE_TOKEN"])`
in one process and `run_service(:forecast; port=9182, token=ENV["HTMXO_SERVICE_TOKEN"])`
in another, loading the same application and plan in each.

Use one application instance and one service runtime per process. The shared
token identifies trusted deployment peers, and `contract` is an explicit
application protocol version. Configure trusted HTTP origins in `endpoints`;
use HTTPS when crossing an untrusted network. A contract mismatch returns 409.

## State, policy and process lifetime

Declare every operation which reads or writes a mutable resource, including
effectful GET routes, in `resources=[:stream => [:append, :assess]]`. Exactly
one slice must declare `owns=[:stream]`. Other slices must forward those
operations. Mutation routes cannot have two local owners even without a resource
declaration. Pure operations may overlap.

A local property dependency on an operation assigned to another resource owner
is rejected too: use `dispatch` at that boundary. The framework does not convert
a direct property call into a remote call.

Check [`service_owns`](@ref) before initializing owner state or starting singleton
background work. Use a retained [`RootProvider`](@ref) when state and caches must
survive requests. Ownership validation is a plan check: run only one active
generation of each mutable owner. Persistence and writer failover remain the
application's responsibility.

Put authentication and authorization middleware on `ServiceRuntime`, so public
requests, local dispatch and remote dispatch all apply it. `identity_headers`
selects headers inherited by nested dispatch (defaults: Authorization, Cookie
and X-Request-ID). Audience, language and request ID propagate; deployment
credentials are removed before application middleware runs. Application-specific
objects in request context are not serialized across processes.

Operations are buffered and blocking. SSE, WebSockets, speculative preload, polling policies and
cross-process `StaticExport` requests are unsupported. Automatic page prestart,
the process-global operation stream and Revise are disabled. Progress tokens
and cancellation handles do not migrate to a new process. A peer request has a
configurable `request_timeout` (60 seconds by default; overall deadline on HTTP
2; read timeout rounded up to whole seconds on HTTP 1). A transport failure returns 502; mutations are never
retried automatically because a lost response may follow a committed write.

Before replacement, call `drain_service!(runtime; timeout=30)`. It refuses new
requests with 503 and waits for admitted requests to finish. `false` means work
is still owned by that process; wait again or handle the uncertain outcome before
terminating it. The runtime does not cancel or transfer outstanding operations.
After a successful drain, stop the listener and start the replacement. Peers use
the configured origin on their next call; no client poll token is reused.

## Generated system view

Service topology and request observations require HTMXObjects 0.1.113 or newer.
The plan is also the source for the system view; no separate diagram inventory is
needed. [`service_topology`](@ref) projects its descriptor into service blocks,
one connection per source/destination pair, and resource ownership:

```@example service-plan
topology = service_topology(plan)
[(c.source, c.destination, [string(o.verb, " ", o.path) for o in c.operations])
 for c in topology.connections]
```

`plan.descriptor` uses `htmxobjects.application-descriptor/v1`. Its
`htmxobjects.services` fragment contains service and resource nodes. A service's
`depends_on` edges to route nodes carry `role=:local` or `role=:forward`,
`exposure=:public` or `exposure=:internal`, and a forward's `destination`.
`owns` edges link services to resources; `guards` edges link resources to every
declared operation that accesses them. `service_topology(plan)` returns the
versioned `htmxobjects.service-topology/v1` projection, with stable IDs and
deterministic ordering. Neither accessor evaluates application properties.

`application_explorer_view(plan.descriptor)` opens the compact Services view.
Its Application map tab retains the full declaration explorer; `view=:map` or a
`selected` node ID opens that view directly. Mount `ReflectionRoutes(; plan)`
to expose the same tabs and descriptor JSON through an application's `@include`.

For a runtime page with current observations, mount the monitor before serving:

```@example service-plan
import HTTP
runtime = ServiceRuntime(plan, :forecast, Calculation(); token="example-only",
    endpoints=Dict(:assessment => "http://127.0.0.1:9181"),
    contract="calculation/v1", middleware=[next -> req -> begin
        HTTP.header(req, "X-Actor", "") == "operator" || return HTTP.Response(403)
        next(req)
    end])
mount_service_monitor!(runtime; path="/services", timeout=2)
service_observations(runtime).snapshot.metrics
```

This adds `/services`, `/services/topology` and `/services/observations`, all
protected by runtime middleware. The page shows operations, resources, forward
arrows and statistics; operation details expand in place. Refresh takes a new
snapshot; there is no background polling.
Peers are read concurrently with the supplied timeout. A peer without an endpoint
stays visibly unconfigured. Access denied, contract mismatch, unavailable peers
and stale supplied snapshots are distinct from a responding but idle service.
Monitor routes remain readable while the runtime drains.
Cold compilation counts toward the timeout; the process example allows 30 seconds.

## Request statistics

`ServiceRuntime` collects bounded statistics by default; pass `metrics=false`
to disable collection. Read local data with `service_observations(runtime)` or
a peer with `service_observations(runtime; peer=:assessment,
headers=["X-Actor" => "operator"], timeout=2)`. Peer reads use the deployment
token and contract plus the peer's application middleware. Within a request,
identity headers, audience and language propagate automatically. A peer may read
observations without having a forwarded business operation. The internal
observation endpoint requires deployment authentication even when no monitor
page is mounted.

Each result has a status, check time and optional snapshot. A snapshot carries
the runtime's generation, start time, drain state, active requests, per-operation
records and per-destination forward aggregates. Counters reset on restart; compare
generation IDs before comparing totals. A failed peer read has no snapshot and
does not manufacture zero counts. Remote snapshots have JSON string keys; local
snapshots are named tuples. [`service_topology_view`](@ref) accepts a collection
of either accessor's results when embedding a view yourself.

Each operation records starts, completions, failures, active calls, last activity
and latency (total, mean and maximum seconds). Counts include policy rejection,
parameter errors, application failure and transport failure. A failure is an HTTP
status of 400 or greater, or a thrown exception; client, server, exception and
transport categories are also available. A transport failure returning 502 counts
in both server and transport categories. Nested dispatch counts each operation it
calls; totals are operation calls, not unique user requests. Failed deployment
authentication, unknown routes and requests rejected by draining are outside the
operation counters.

Recent totals cover the current monotonic-clock second and preceding 59 seconds;
starts and completions count in their respective seconds, so a long operation
can complete in a window where it did not start. Latency covers middleware through buffered response creation, not
socket delivery. Storage is fixed by selected route templates and 60 buckets per
route, independent of request volume, URL parameters and body size. No raw URLs,
bodies or identity headers are retained. Observation reads do not count themselves
and never compute application properties.

## Runnable process example

The repository's `examples/service_slices/application.jl` declares an ordered
stream, assessment, forecast, shared pure computation and an omitted route. Its
`server.jl` runs the same definition as `whole`, `writer` or `reader`. From the
repository root, set the same deployment token in both shells and start:

```sh
julia --project=. -t2,1 examples/service_slices/server.jl writer 9181 /tmp/slice-writer
julia --project=. -t2,1 examples/service_slices/server.jl reader 9182 /tmp/slice-reader http://127.0.0.1:9181
```

The example's deliberately simple policy requires `X-Actor: demo`. Append with
`POST /append?sequence=1&value=2` on the writer, then request
`GET /forecast?scale=3` on the reader. A colocated baseline uses `whole` on
another port. Each control directory receives `ready.json`; touching `drain`
requests a graceful stop. Use a fresh control directory for each generation.
Each process mounts `/services`; send `X-Actor: demo` to inspect it. The reader's
page reads the writer through its configured origin. The writer shows the reader
as unconfigured until an endpoint is supplied for it.

`test/service_processes.jl` verifies parity and reader replacement while the
writer retains its PID, stream and cache. It records startup to listener readiness
and process RSS after equivalent work. The split memory cost is the sum of writer
and reader RSS; shared pages may be counted twice. These are observations under
the test host's load, not peak-memory, PSS or speedup claims. Loading fewer routes
does not imply loading fewer package definitions.
