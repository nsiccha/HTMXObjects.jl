# The renderer accepts both local named tuples and JSON observation records.
_service_get(value, key, default=nothing) = _architecture_get(value, key, default)
_service_ms(seconds) = seconds === nothing ? "—" : string(round(seconds * 1000; digits=2), " ms")
_service_time(seconds) = seconds === nothing ? "No activity" : string(Dates.unix2datetime(seconds), " UTC")

function _service_observation_state(observation, now, stale_after)
    observation === nothing && return "Not observed"
    status = string(_service_get(observation, :status, :invalid))
    status == "ok" || return get(Dict("unconfigured" => "Endpoint not configured",
        "unavailable" => "Unreachable or timed out", "denied" => "Access denied",
        "incompatible" => "Contract mismatch", "invalid" => "Invalid observation"), status, status)
    now - _service_get(observation, :checked_at, 0) > stale_after && return "Stale observation"
    snapshot = _service_get(observation, :snapshot)
    _service_get(snapshot, :accepting, false) || return "Responding · draining"
    _service_get(snapshot, :active, 0) > 0 ? "Responding · active" : "Responding · idle"
end

function _service_metric_table(metric)
    metric === nothing && return h.p("No request statistics available.")
    h.table(
        h.thead(h.tr(h.th("Window"), h.th("Calls"), h.th("Completed"),
            h.th("Failures"), h.th("Mean"), h.th("Maximum"))),
        h.tbody([begin
            counts = _service_get(metric, key)
            latency = _service_get(counts, :latency)
            h.tr(h.th(label; scope="row"),
                h.td(_service_get(counts, :requests, 0)),
                h.td(_service_get(counts, :completed, 0)),
                h.td(_service_get(counts, :failures, 0)),
                h.td(_service_ms(_service_get(latency, :mean_seconds))),
                h.td(_service_ms(_service_get(latency, :max_seconds))))
        end for (key, label) in ((:recent, "Last 60 s"), (:lifetime, "This generation"))]...))
end

function _service_operation_detail(operation, metric, names)
    destination = _service_get(operation, :destination)
    role = string(_service_get(operation, :role))
    exposure = string(_service_get(operation, :exposure))
    h.details(
        h.summary(h.code(string(_service_get(operation, :verb), " ", _service_get(operation, :path))),
            " · ", exposure, " · ", role,
            destination === nothing ? "" : " → " * names[destination]),
        metric === nothing ? h.p("No request statistics available.") : h.div(
            h.p(string(_service_get(metric, :active, 0), " active · Last activity: ",
                _service_time(_service_get(metric, :last_activity)))),
            _service_metric_table(metric),
            h.p(let counts = _service_get(metric, :lifetime)
                string("Failure totals: ", _service_get(counts, :client_errors, 0), " client errors · ",
                    _service_get(counts, :server_errors, 0), " server errors · ",
                    _service_get(counts, :exceptions, 0), " exceptions · ",
                    _service_get(counts, :transport_errors, 0), " transport failures")
            end)))
end

function _service_topology_styles()
    h.style(Raw("""
.htmxo-services { --htmxo-services-gap: 1rem; }
.htmxo-services > section > div {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 26rem), 1fr));
    gap: var(--htmxo-services-gap); align-items: start;
}
.htmxo-services article { min-width: 0; margin: 0; }
.htmxo-services code { white-space: normal; overflow-wrap: anywhere; }
.htmxo-services article > header h3 { margin-bottom: 0.4rem; }
.htmxo-services table { font-size: 0.85em; }
.htmxo-services summary code { color: inherit; }
.htmxo-services [data-role="connection"] > header { border-inline-start: 0.25rem solid var(--pico-primary-border); }
.htmxo-services [data-role="connection"] > header a { overflow-wrap: anywhere; }
"""))
end

"""
    service_topology_view(plan_or_topology; observations=(), refresh="", stale_after=30)

Render service blocks, resource ownership and one arrow per forwarding pair.
Operations expand in place to show their complete request statistics. Pass a
collection of [`service_observations`](@ref) results to attach snapshots;
unobserved, failed and stale reads stay distinct from an idle responding peer.
`stale_after` is the snapshot age in seconds at render time. No requests or
application computations occur while rendering. `refresh` optionally supplies
an ordinary link for taking a fresh snapshot in the containing application.
"""
function service_topology_view(plan_or_topology; observations=(), refresh="", stale_after::Real=30)
    isfinite(stale_after) && stale_after > 0 || throw(ArgumentError("stale_after must be finite and positive"))
    topology = plan_or_topology isa ServicePlan ? service_topology(plan_or_topology) : plan_or_topology
    _service_get(topology, :schema) == "htmxobjects.service-topology/v1" ||
        throw(ArgumentError("expected htmxobjects.service-topology/v1"))
    services = _service_get(topology, :services)
    resources = Dict(_service_get(r, :id) => r for r in _service_get(topology, :resources))
    names = Dict(_service_get(s, :id) => string(_service_get(s, :name)) for s in services)
    observed = Dict(string(_service_get(o, :service)) => o for o in observations)
    metrics = Dict{String,Any}()
    forwards = Dict{Tuple{String,String},Any}()
    for (name, observation) in observed
        snapshot = _service_get(observation, :snapshot)
        metrics[name] = Dict((string(_service_get(o, :verb)), _service_get(o, :path)) => o
            for o in _service_get(snapshot, :operations, ()))
        for forward in _service_get(snapshot, :forwards, ())
            forwards[(name, string(_service_get(forward, :destination)))] = forward
        end
    end
    now = time()
    blocks = [begin
        id, name = _service_get(service, :id), string(_service_get(service, :name))
        observation = get(observed, name, nothing)
        snapshot = _service_get(observation, :snapshot)
        operations = _service_get(service, :operations)
        operation_metrics = get(metrics, name, Dict())
        owned = _service_get(service, :resources)
        h.article(
            h.header(h.h3(name), h.p(_service_observation_state(observation, now, stale_after))),
            isempty(owned) ? h.p("No owned resources") :
                h.p("Owns: ", join((string(_service_get(resources[r], :name)) for r in owned), ", ")),
            snapshot === nothing ? "" : h.p(h.small(
                "Generation ", h.code(_service_get(snapshot, :generation)), " · started ",
                _service_time(_service_get(snapshot, :started_at)), " · ",
                _service_get(snapshot, :metrics, false) ? "Statistics enabled" : "Statistics disabled")),
            h.h4("Operations"),
            [_service_operation_detail(op,
                get(operation_metrics, (string(_service_get(op, :verb)), _service_get(op, :path)), nothing), names)
                for op in operations]...;
            id, data_service=name)
    end for service in services]
    connections = [begin
        source, destination = names[_service_get(c, :source)], names[_service_get(c, :destination)]
        metric = get(forwards, (source, destination), nothing)
        h.article(
            h.header(h.h3(h.a(source; href="#" * _service_get(c, :source)), " → ",
                h.a(destination; href="#" * _service_get(c, :destination))),
                h.p("Forwards · ", _service_observation_state(get(observed, destination, nothing), now, stale_after))),
            h.ul([h.li(h.code(string(_service_get(op, :verb), " ", _service_get(op, :path))))
                for op in _service_get(c, :operations)]...),
            _service_metric_table(metric),
            metric === nothing ? "" : h.p(h.small("Last forward: ",
                _service_time(_service_get(metric, :last_activity)))); data_role="connection")
    end for c in _service_get(topology, :connections)]
    h.section(_service_topology_styles(),
        h.header(h.h1("Services"),
            h.p(string(length(services), " services · ", length(connections), " forward connections · ",
                length(resources), " owned resources")),
            isempty(observations) ? h.p("Declarations only; no runtime observations attached.") :
                h.p("Snapshots taken on request. An idle service may still be responding; a failed read is not zero traffic."),
            isempty(refresh) ? "" : h.a("Refresh observations"; href=refresh)),
        h.section(h.h2("Service operations and ownership"), h.div(blocks...)),
        h.section(h.h2("Forward connections"), isempty(connections) ? h.p("No forwarded operations.") : h.div(connections...));
        class="htmxo-services")
end
