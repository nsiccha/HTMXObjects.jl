# --- Reflection endpoint ---------------------------------------------------
#
# ReflectionRoutes — the HUMAN-READABLE semantic surface, mounted opt-in:
#
#   @include reflect = ReflectionRoutes(; root=MyApp)   # → /reflect
#
#   GET /reflect             accessible architecture explorer
#   GET /reflect/descriptor  deterministic flat application graph as JSON
#   GET /reflect/graph       compatibility nested semantic graph as JSON
#
# Deliberately a SEPARATE bundle from `SchemaRoutes`, not an extension of it.
# `/schema` answers a transport question — "what routes exist, with what
# parameters" — and its JSON is consumed by MCP tool-autogen and doc
# generators, so its shape is a contract that must not move. `/reflect`
# answers a semantic question — what the application IS: containment, declared
# computation dependencies, option domains, materialization, selection
# identity. Both read the same underlying walk (`semantic_descriptor`), so they
# cannot disagree about the route set; they present different questions.
#
# The compatibility `semantic_graph_view` stays structural `h.*` only. The
# architecture explorer added below uses one semantic root class and a paired,
# scoped stylesheet; native headings, links, forms, tables, details and
# `aria-*` state keep the entire surface usable without JavaScript.

# `Vector{Pair{Symbol,NamedTuple}}` is the shape DynamicObjects uses for
# `@options` declarations, and the shared encoder has no Pair method (nothing
# in `reflect`'s output is a Pair, which is why `/schema` never needed one).
# Encoded as a 2-element array so key and value stay distinguishable — the
# catch-all would otherwise stringify the whole pair into one opaque `"a => b"`.
function _schema_json_encode(io::IO, p::Pair)
    write(io, '[')
    _schema_json_encode(io, first(p))
    write(io, ',')
    _schema_json_encode(io, last(p))
    write(io, ']')
end

# --- small view helpers ----------------------------------------------------

_view_code(x) = h.code(string(x))
_view_text(::Nothing) = ""
_view_text(x) = string(x)

# Comma-separated `code` spans, or an em dash when there is nothing to list.
# An empty cell and a cell whose answer is "none" look identical in a table;
# the dash says the question was asked.
function _view_list(xs)
    isempty(xs) && return "—"
    children = Any[]
    for (i, x) in enumerate(xs)
        i == 1 || push!(children, ", ")
        push!(children, _view_code(_view_option_label(x)))
    end
    h.span(children...)
end

# A domain option is a RECORD — value plus the label a control renders, and
# possibly a group, help text or a disabled flag. Show the label: printing the
# whole NamedTuple fills the cell with field names and buries the one thing a
# reader is looking for. Anything without a label prints as itself.
_view_option_label(x) = x
_view_option_label(x::NamedTuple) =
    hasproperty(x, :label) ? x.label : (hasproperty(x, :value) ? x.value : x)

"""
    _view_domain(domain) -> renderable

Render one input's option domain. The `kind`s answer genuinely different
questions and are NOT flattened into one "here are the choices" cell:

- `:static` — DynamicObjects proved the value set (a `Bool`, an `Enum`); the
  options ARE the domain.
- `:declared` — the application declared `@options p = <expr>`. DynamicObjects
  records the expression and never evaluates it, so `options` is empty by
  design. Shown as the expression plus what it depends on. Rendering this as
  "no options" would assert the opposite of what it means.
- `:unrestricted` / absent — no domain is claimed.

The dependency list lives on the `declaration`, not on the domain: the domain
is what reflection could decide about a TYPE, and a declared one decides
nothing, so everything it knows sits in the record of what was written.
"""
function _view_domain(domain)
    domain === nothing && return "—"
    kind = get(domain, :kind, :unrestricted)
    if kind === :static
        options = get(domain, :options, [])
        isempty(options) ? _view_code(kind) :
            h.span(_view_code(kind), " ", _view_list(options))
    elseif kind === :declared
        declaration = get(domain, :declaration, nothing)
        expression = declaration === nothing ? nothing :
                     get(declaration, :expression_string, nothing)
        deps = declaration === nothing ? Symbol[] :
               get(declaration, :dependencies, Symbol[])
        children = Any[_view_code(kind)]
        isnothing(expression) || (push!(children, " "); push!(children, h.code(expression)))
        isempty(deps) || (push!(children, " depends on "); push!(children, _view_list(deps)))
        h.span(children...)
    else
        _view_code(kind)
    end
end

_view_table(headers, rows) = h.table(
    h.thead(h.tr((h.th(header) for header in headers)...)),
    h.tbody((h.tr((h.td(cell) for cell in row)...) for row in rows)...))

# --- per-section views -----------------------------------------------------

# Routes DECLARED at this node, with their full parameter list. `kind` is the
# semantic role of a parameter (`:path`, `:query`, `:form`, `:context`, …), so
# an inherited fixed field reads differently from something the caller supplies.
function _view_routes(node)
    isempty(node.routes) && return nothing
    rows = Any[]
    for route in node.routes
        params = get(route, :params, NamedTuple[])
        push!(rows, Any[
            _view_code(route.verb),
            _view_code(route.path),
            _view_text(get(route, :doc, nothing)),
            isempty(params) ? "—" :
                _view_table(["Parameter", "Type", "Kind", "Required", "Domain"],
                    [Any[_view_code(param.name),
                         _view_code(get(param, :type, "Any")),
                         _view_code(get(param, :kind, :query)),
                         get(param, :required, true) ? "yes" : "no",
                         _view_domain(get(param, :domain, nothing))]
                     for param in params])])
    end
    h.section(h.h3("Routes"),
              _view_table(["Verb", "Path", "Documentation", "Parameters"], rows))
end

# The DynamicObjects property records, verbatim. `role` separates inputs from
# operations from outputs; `dependencies` is the declared computation edge set —
# the thing a route table cannot show and the reason this view exists.
#
# The domain column reads the descriptor's OWN top-level `domain`, not
# `inputs[].domain`. An overrideable default (`n_chain::Integer = 8`) is a
# computed property with no call signature, so its `inputs` is empty and a
# per-input reading reports nothing for exactly the parameters an application
# most wants to see. Per-input domains still appear in the routes table, where
# the input is what the caller supplies.
function _view_properties(node)
    isempty(node.properties) && return nothing
    rows = [Any[_view_code(descriptor.name),
                _view_code(descriptor.role),
                _view_list(get(descriptor, :dependencies, Symbol[])),
                _view_code(descriptor.output.type),
                _view_domain(get(descriptor, :domain, nothing)),
                _view_code(descriptor.output.materialization.tier),
                _view_text(get(descriptor, :description, nothing))]
            for descriptor in node.properties]
    h.section(h.h3("Properties"),
              _view_table(["Property", "Role", "Depends on", "Type", "Domain",
                           "Materialization", "Documentation"], rows))
end

# `@options` declared AT the node — including any whose parameter matches no
# input. DynamicObjects reports those too rather than erroring, so showing them
# here is how an unattached declaration becomes visible instead of silent.
function _view_options(node)
    options = get(node, :options, ())
    isempty(options) && return nothing
    rows = [Any[_view_code(first(pair)),
                h.code(get(last(pair), :expression_string, "")),
                get(last(pair), :static, true) ? "static" : "dependent",
                _view_list(get(last(pair), :dependencies, Symbol[]))]
            for pair in options]
    h.section(h.h3("Option declarations"),
              _view_table(["Parameter", "Expression", "Evaluation", "Depends on"], rows))
end

function _view_resources(node)
    isempty(node.resources) && return nothing
    rows = [Any[_view_code(resource.name), _view_code(resource.role),
                _view_code(resource.tier), _view_code(resource.type),
                resource.versioned ? "yes" : "no"]
            for resource in node.resources]
    h.section(h.h3("Resources"),
              _view_table(["Name", "Role", "Tier", "Type", "Versioned"], rows))
end

# The selection identity of an indexed mount: which parameters pick this node
# out of its collection, and what each one may be. Without this an indexed
# child reads as a single node at a templated path, which is exactly the
# information a route table already fails to convey.
function _view_selection(node)
    node.indexed || return nothing
    rows = [Any[_view_code(input.name),
                _view_code(get(input, :type, "Any")),
                _view_domain(get(input, :domain, nothing))]
            for input in node.selection]
    h.section(h.h3("Selection"),
              h.p("Indexed mount — one node per selection."),
              _view_table(["Parameter", "Type", "Domain"], rows))
end

"""
    _view_node(node, level=2) -> renderable

One graph node and everything under it. Children nest inside `details` so a
large application is navigable collapsed, and open by default so the whole
graph is present in the initial response — a reflection view whose content
appears only after interaction cannot be read as markdown or saved as a
recording.
"""
function _view_node(node, level::Integer=2)
    heading = getproperty(h, Symbol("h", min(level, 6)))
    sections = Any[heading(node.label), h.p(_view_code(node.path))]
    isnothing(node.doc) || push!(sections, h.p(node.doc))
    push!(sections, h.p("Type ", _view_code(node.type),
                        ", declared by ", _view_code(node.origin)))
    for view in (_view_selection(node), _view_options(node), _view_routes(node),
                 _view_properties(node), _view_resources(node))
        isnothing(view) || push!(sections, view)
    end
    if !isempty(node.children)
        push!(sections, h.details(; open=true)(
            h.summary(string(length(node.children), " contained node",
                             length(node.children) == 1 ? "" : "s")),
            (_view_node(child, level + 1) for child in node.children)...))
    end
    h.section(sections...)
end

"""
    semantic_graph_view(T) -> renderable

Human-readable rendering of the semantic graph of an `@htmx` application root
— containment and mount edges, declared computation dependencies, docs and
labels, parameters with their option domains, explicit and generated routes,
resources, and the template plus selection identity of indexed nodes.

Structural HTML only, so the mounting application styles it and `?plain`
renders it as markdown unchanged. The data is
[`semantic_descriptor`](@ref)`(T).graph`; this function only presents it.
"""
semantic_graph_view(T::Type) = _view_node(semantic_descriptor(T).graph)
semantic_graph_view(obj) = semantic_graph_view(typeof(obj))

# --- Reusable application architecture descriptor -------------------------

const _APPLICATION_DESCRIPTOR_SCHEMA = "htmxobjects.application-descriptor/v1"
const _APPLICATION_OBSERVATIONS_SCHEMA = "htmxobjects.application-observations/v1"

_architecture_component(x) = HTTP.URIs.escapeuri(string(x))
_mount_node_id(parts) = "htmx:mount:" *
    (isempty(parts) ? "root" : join(_architecture_component.(parts), "/"))

function _route_node_id(mount_id, route)
    signature = join((string(param.name, "::", get(param, :type, Any))
                      for param in get(route, :params, NamedTuple[])), ",")
    join(("htmx:route", _architecture_component(mount_id),
          _architecture_component(route.verb), _architecture_component(route.path),
          _architecture_component(route.name),
          _architecture_component(signature)), ":")
end

_artifact_node_id(mount_id, name, declaration) =
    join(("htmx:artifact", _architecture_component(mount_id),
          _architecture_component(name), string(declaration)), ":")

_architecture_node(id, kind, label, metadata) =
    (; id=string(id), kind, label=string(label), metadata,
       fragment="htmxobjects")

function _architecture_edge(kind, from_id, to_id; metadata=(;))
    id = join(("htmx:edge", _architecture_component(kind),
               _architecture_component(from_id), _architecture_component(to_id)), ":")
    (; id, kind, from=string(from_id), to=string(to_id), metadata,
       fragment="htmxobjects")
end

function _do_declaration_graph(root::Type; contributions=())
    isdefined(DynamicObjects, :declaration_graph) || throw(ArgumentError(
        "application_descriptor requires DynamicObjects.declaration_graph"))
    Base.invokelatest(getproperty(DynamicObjects, :declaration_graph), root;
                      contributions)
end

function _do_declaration_node_id(graph, T::Type, property=nothing;
                                 declaration::Integer=1)
    isdefined(DynamicObjects, :declaration_node_id) || throw(ArgumentError(
        "application_descriptor requires DynamicObjects.declaration_node_id"))
    lookup = getproperty(DynamicObjects, :declaration_node_id)
    property === nothing && return Base.invokelatest(lookup, graph, T)
    Base.invokelatest(lookup, graph, T, property; declaration)
end

_contribution_tuple(::Nothing) = ()
_contribution_tuple(x::NamedTuple) = (x,)
_contribution_tuple(xs::Tuple) = xs
_contribution_tuple(xs::AbstractVector) = Tuple(xs)
_contribution_tuple(x) = throw(ArgumentError(
    "contributions must be a contribution NamedTuple or a tuple/vector of them, got $(typeof(x))"))

function _descriptor_declaration(properties, descriptor)
    descriptor === nothing && return nothing
    index = findfirst(candidate -> isequal(candidate, descriptor), properties)
    index === nothing && return nothing
    name = descriptor.name
    count(candidate -> candidate.name === name, @view properties[begin:index])
end

function _htmx_declaration_fragment(semantic, declaration)
    nodes = NamedTuple[]
    edges = NamedTuple[]
    mount_count = Ref(0)
    route_count = Ref(0)
    artifact_count = Ref(0)

    function walk(node, ancestry::Vector{Symbol}, parent_mount)
        mount_id = _mount_node_id(ancestry)
        type_id = _do_declaration_node_id(declaration, node.type)
        mount_count[] += 1
        push!(nodes, _architecture_node(mount_id, :mount, node.label, (
            path=node.path,
            name=node.name,
            type=string(node.type),
            type_node=type_id,
            documentation=node.doc,
            origin=node.origin,
            indexed=node.indexed,
            selection=node.selection,
            options=node.options,
        )))
        push!(edges, _architecture_edge(:mounts, type_id, mount_id;
                                        metadata=(; path=node.path)))
        parent_mount === nothing ||
            push!(edges, _architecture_edge(:contains, parent_mount, mount_id;
                                            metadata=(; path=node.path)))

        for route in node.routes
            route_id = _route_node_id(mount_id, route)
            route_count[] += 1
            declaration_index = _descriptor_declaration(node.properties,
                                                         get(route, :property, nothing))
            property_id = declaration_index === nothing ? nothing :
                _do_declaration_node_id(declaration, node.type, route.name;
                                        declaration=declaration_index)
            push!(nodes, _architecture_node(route_id, :route,
                                            string(route.verb, " ", route.path), (
                verb=route.verb,
                path=route.path,
                name=route.name,
                documentation=route.doc,
                parameters=route.params,
                origin=route.origin,
                owner_type=string(node.type),
                property_node=property_id,
            )))
            push!(edges, _architecture_edge(:serves, mount_id, route_id;
                                            metadata=(; verb=route.verb,
                                                       path=route.path)))
            property_id === nothing ||
                push!(edges, _architecture_edge(:reads, route_id, property_id;
                                                metadata=(; declaration=declaration_index)))
        end

        occurrences = Dict{Symbol,Int}()
        for property in node.properties
            occurrence = get(occurrences, property.name, 0) + 1
            occurrences[property.name] = occurrence
            tier = property.output.materialization.tier
            tier in (:mmap, :serialized) || continue
            property_id = _do_declaration_node_id(declaration, node.type, property.name;
                                                  declaration=occurrence)
            artifact_id = _artifact_node_id(mount_id, property.name, occurrence)
            artifact_count[] += 1
            push!(nodes, _architecture_node(artifact_id, :artifact,
                                            _humanize(property.name), (
                name=property.name,
                role=property.role,
                tier=tier,
                type=string(property.output.type),
                versioned=get(property.semantics, :versioned, false),
                property_node=property_id,
                mount=mount_id,
            )))
            push!(edges, _architecture_edge(:produces, property_id, artifact_id;
                                            metadata=(; tier)))
        end

        for child in node.children
            walk(child, [ancestry; child.name], mount_id)
        end
    end

    walk(semantic.graph, Symbol[], nothing)
    fragment = (namespace="htmxobjects", nodes, edges)
    statistics = (mounts=mount_count[], routes=route_count[],
                  artifacts=artifact_count[])
    fragment, statistics
end

"""
    application_descriptor(root; contributions=()) -> NamedTuple

Compose DynamicObjects' declaration graph with HTMXObjects' mount, route and
artifact reflection into a deterministic, JSON-serializable application
descriptor. `root` may be an application type or object. The flat `nodes` and
`edges` retain DynamicObjects' stable IDs and source/provenance records, then
add HTMXObjects nodes with the following relations:

- `:mounts` — a declared type is mounted at a URL location;
- `:serves` — a mount serves a route;
- `:reads` — a route is backed by its declared operation property;
- `:produces` — a declared materialized property produces an artifact.

DynamicObjects' `:contains`, `:depends_on` and `:describes` relations remain
unchanged. `contributions` uses DynamicObjects' plain-data contribution shape
`(; namespace, nodes, edges)`, so a domain package can add nodes and explicit
links without HTMXObjects depending on it or learning its vocabulary.

This function reflects declarations only. It does not construct `root`, run a
route, evaluate an option declaration, or compute a property. Use
[`application_observations`](@ref) for the separate optional live-state layer.
"""
function application_descriptor(root::Type; contributions=())
    external = _contribution_tuple(contributions)
    base = _do_declaration_graph(root)
    semantic = semantic_descriptor(root)
    htmx_fragment, statistics = _htmx_declaration_fragment(semantic, base)
    graph = _do_declaration_graph(root;
        contributions=(htmx_fragment, external...))
    (
        schema=_APPLICATION_DESCRIPTOR_SCHEMA,
        declaration_schema=graph.schema,
        root=graph.root,
        nodes=graph.nodes,
        edges=graph.edges,
        metadata=(
            root_type=string(root),
            declarations=graph.metadata,
            statistics,
            contribution_namespaces=get(graph.metadata, :contribution_namespaces,
                                        String[]),
        ),
    )
end

application_descriptor(root; contributions=()) =
    application_descriptor(typeof(root); contributions)

function _declaration_graph_from_application(descriptor)
    descriptor.schema == _APPLICATION_DESCRIPTOR_SCHEMA || throw(ArgumentError(
        "expected $(_APPLICATION_DESCRIPTOR_SCHEMA), got $(repr(descriptor.schema))"))
    (
        schema=descriptor.declaration_schema,
        root=descriptor.root,
        nodes=descriptor.nodes,
        edges=descriptor.edges,
        metadata=descriptor.metadata.declarations,
    )
end

"""
    application_observations(object, descriptor=application_descriptor(object); calls=())

Return a live-state overlay for an application descriptor without computing any
property. Records are keyed by the same stable declaration-node IDs used by
[`application_descriptor`](@ref). Fixed/scalar properties use
`DynamicObjects.materialization_observation`; indexed properties are absent
unless the caller supplies explicit `calls=(; node, args, kwargs)` records.

The overlay is intentionally separate from the static application descriptor,
so asking what an application declares never changes its state or materializes
work merely for display.
"""
function application_observations(object,
        descriptor=application_descriptor(object); calls=())
    isdefined(DynamicObjects, :declaration_observations) || throw(ArgumentError(
        "application_observations requires DynamicObjects.declaration_observations"))
    graph = _declaration_graph_from_application(descriptor)
    observed = Base.invokelatest(
        getproperty(DynamicObjects, :declaration_observations), object, graph; calls)
    (
        schema=_APPLICATION_OBSERVATIONS_SCHEMA,
        graph=descriptor.root,
        observations=observed.observations,
    )
end

# --- Accessible application explorer --------------------------------------

_architecture_get(x::NamedTuple, key::Symbol, default=nothing) = get(x, key, default)
_architecture_get(x::AbstractDict, key::Symbol, default=nothing) =
    haskey(x, key) ? x[key] : get(x, String(key), default)
_architecture_get(x, key::Symbol, default=nothing) =
    hasproperty(x, key) ? getproperty(x, key) : default

_architecture_value(::Nothing) = "—"
_architecture_value(x::Union{Symbol,Type}) = h.code(string(x))
_architecture_value(x::Union{AbstractString,Number,Bool}) = string(x)

function _architecture_value(xs::Union{AbstractVector,Tuple})
    isempty(xs) && return "—"
    h.ul((h.li(_architecture_value(x)) for x in xs)...)
end

function _architecture_record(record)
    children = Any[]
    entries = record isa AbstractDict ?
        sort!(collect(pairs(record)); by=pair -> string(first(pair))) :
        collect(pairs(record))
    for (key, value) in entries
        push!(children, h.dt(string(key)))
        push!(children, h.dd(_architecture_field_value(Symbol(string(key)), value)))
    end
    h.dl(children...)
end

_architecture_value(x::Union{NamedTuple,AbstractDict}) = _architecture_record(x)
_architecture_value(x::Pair) =
    h.span(_architecture_value(first(x)), " → ", _architecture_value(last(x)))
_architecture_value(x) = h.code(string(x))

function _architecture_field_value(key::Symbol, value)
    normalized = lowercase(string(key))
    if value isa AbstractString &&
            (occursin("source", normalized) || occursin("code", normalized) ||
             occursin("expression", normalized))
        return h.pre(h.code(value))
    end
    _architecture_value(value)
end

function _architecture_find_node(descriptor, id)
    index = findfirst(node -> string(node.id) == string(id), descriptor.nodes)
    index === nothing && throw(ArgumentError(
        "application descriptor has no node with id $(repr(id))"))
    descriptor.nodes[index]
end

function _architecture_relations(descriptor, node_id)
    incoming = [edge for edge in descriptor.edges if edge.to == node_id]
    outgoing = [edge for edge in descriptor.edges if edge.from == node_id]
    incoming, outgoing
end

function _architecture_documentation(node)
    metadata = _architecture_get(node, :metadata, (;))
    for key in (:documentation, :description, :doc)
        value = _architecture_get(metadata, key, nothing)
        value isa AbstractString && !isempty(value) && return value
    end
    declaration = _architecture_get(metadata, :descriptor, nothing)
    declaration === nothing && return nothing
    for key in (:description, :documentation, :doc)
        value = _architecture_get(declaration, key, nothing)
        value isa AbstractString && !isempty(value) && return value
    end
    nothing
end

function _architecture_url(base, node_id; query="", live=false)
    query_url(base; selected=node_id,
              q=isempty(query) ? nothing : query,
              live=live ? true : nothing) * "#architecture-inspector"
end

function _architecture_relation_list(descriptor, edges; incoming::Bool,
                                     base="", query="", live=false)
    isempty(edges) && return h.p("None")
    h.ul((begin
        peer_id = incoming ? edge.from : edge.to
        peer = _architecture_find_node(descriptor, peer_id)
        h.li(
            h.code(string(edge.kind)), " ", incoming ? "from " : "to ",
            h.a(peer.label; href=_architecture_url(base, peer.id;
                                                   query, live)),
            h.small(" ", peer.id),
        )
    end for edge in edges)...)
end

function _architecture_observation(overlay, node_id)
    overlay === nothing && return nothing
    observations = _architecture_get(overlay, :observations, ())
    index = findfirst(record ->
        string(_architecture_get(record, :node, "")) == string(node_id), observations)
    index === nothing ? nothing : observations[index]
end

function _architecture_inspector(descriptor, selected;
                                 overlay=nothing, base="", query="", live=false)
    node = _architecture_find_node(descriptor, selected)
    incoming, outgoing = _architecture_relations(descriptor, node.id)
    fields = Any[]
    for (key, value) in pairs(node)
        key in (:id, :kind, :label) && continue
        push!(fields, h.dt(_humanize(key)))
        push!(fields, h.dd(_architecture_field_value(key, value)))
    end
    observation = _architecture_observation(overlay, node.id)
    sections = Any[
        h.header(
            h.small(string(node.kind)),
            h.h2(node.label; id="architecture-inspector-title"),
            h.code(node.id),
        )]
    observation === nothing || push!(sections, h.aside(
        h.h3("Live observation"),
        h.p("Read without computing; keyed to this declaration node."),
        _architecture_value(observation);
        aria_label="Live observation"))
    append!(sections, Any[
        h.section(
            h.h3("Declaration record"),
            h.dl(fields...),
        ),
        h.section(
            h.h3("Relationships"),
            h.h4("Incoming"),
            _architecture_relation_list(descriptor, incoming; incoming=true,
                                        base, query, live),
            h.h4("Outgoing"),
            _architecture_relation_list(descriptor, outgoing; incoming=false,
                                        base, query, live),
        )])
    h.article(sections...;
        id="architecture-inspector",
        tabindex="-1",
        aria_labelledby="architecture-inspector-title",
    )
end

function _architecture_kind_order(nodes)
    kinds = String[]
    for node in nodes
        kind = string(node.kind)
        kind in kinds || push!(kinds, kind)
    end
    kinds
end

function _architecture_map(descriptor, selected;
                           base="", query="", live=false)
    groups = Any[]
    for kind in _architecture_kind_order(descriptor.nodes)
        members = [node for node in descriptor.nodes if string(node.kind) == kind]
        cards = map(members) do node
            incoming, outgoing = _architecture_relations(descriptor, node.id)
            documentation = _architecture_documentation(node)
            current = node.id == selected ? (; aria_current="true") : (;)
            content = Any[h.strong(node.label), h.code(node.id)]
            documentation === nothing || push!(content, h.span(documentation))
            push!(content, h.small(string(length(incoming), " incoming · ",
                                          length(outgoing), " outgoing")))
            h.li(
                h.a(content...;
                    href=_architecture_url(base, node.id; query, live),
                    data_kind=kind,
                    current...,
                )
            )
        end
        expanded = any(node -> node.id == selected, members) ? (; open=true) : (;)
        push!(groups, h.details(; expanded...)(
            h.summary(string(_humanize(Symbol(kind)), " (", length(members), ")")),
            h.ol(cards...),
        ))
    end
    h.nav(groups...; class="htmxo-architecture-map",
          aria_label="Application architecture map")
end

function _architecture_matches(node, query)
    isempty(query) && return true
    needle = lowercase(query)
    haystack = lowercase(join((string(node.id), string(node.kind),
                               string(node.label), string(node.metadata)), " "))
    occursin(needle, haystack)
end

function _architecture_reference(descriptor, selected;
                                 base="", query="", live=false)
    matches = [node for node in descriptor.nodes if _architecture_matches(node, query)]
    controls = Any[
        h.label("Search every ID, label, kind and metadata field",
                h.input(; type="search", name="q", value=query,
                        autocomplete="off")),
        h.input(; type="hidden", name="selected", value=selected),
        h.button("Search"; type="submit"),
    ]
    live && push!(controls, h.input(; type="hidden", name="live", value="true"))
    isempty(query) || push!(controls, h.a("Clear";
        href=query_url(base; selected, live=live ? true : nothing)))
    table = isempty(matches) ? h.p("No descriptor nodes match this search.") :
        _view_table(["Kind", "Full label", "Documentation", "Stable ID",
                     "Connections"],
            [begin
                incoming, outgoing = _architecture_relations(descriptor, node.id)
                Any[h.code(string(node.kind)),
                    h.a(node.label; href=_architecture_url(base, node.id;
                                                          query, live)),
                    something(_architecture_documentation(node), "—"),
                    h.code(node.id),
                    string(length(incoming), " in / ", length(outgoing), " out")]
            end for node in matches])
    h.section(
        h.h2("Reference"; id="architecture-reference-title"),
        h.form(controls...; method="get", action=base, role="search"),
        h.p(string(length(matches), " of ", length(descriptor.nodes),
                   " nodes shown.")),
        table;
        id="architecture-reference",
        aria_labelledby="architecture-reference-title",
    )
end

"""
    application_explorer_styles() -> Node

Return the scoped structural CSS used by [`application_explorer_view`](@ref).
The explorer uses one semantic root class and native `nav`, `section`, `article`,
`table`, `dl` and form elements; state is expressed with `aria-current` and
`data-kind`, never inline styles or appearance utility classes.
"""
application_explorer_styles() = h.style(Raw("""
.htmxo-architecture-explorer {
    --htmxo-architecture-card-min: 13rem;
    --htmxo-architecture-gap: 1rem;
}
.htmxo-architecture-explorer > header { margin-bottom: 2rem; }
.htmxo-architecture-explorer > header nav ul { align-items: center; }
.htmxo-architecture-map {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, var(--htmxo-architecture-card-min)), 1fr));
    gap: var(--htmxo-architecture-gap);
    align-items: start;
}
.htmxo-architecture-map > details { min-width: 0; margin-block: 1.5rem; }
.htmxo-architecture-map > details > summary { font-size: 1.25rem; font-weight: 700; }
.htmxo-architecture-map > details > ol {
    display: grid;
    grid-template-columns: 1fr;
    gap: var(--htmxo-architecture-gap);
    padding: 0;
    list-style: none;
}
.htmxo-architecture-map > details > ol > li { min-width: 0; }
.htmxo-architecture-map > details > ol > li > a {
    display: grid;
    gap: 0.4rem;
    height: 100%;
    padding: 1rem;
    border: var(--pico-border-width) solid var(--pico-muted-border-color);
    border-radius: var(--pico-border-radius);
    background: var(--pico-card-background-color);
    color: inherit;
    text-decoration: none;
    overflow-wrap: anywhere;
}
.htmxo-architecture-map > details > ol > li > a:hover,
.htmxo-architecture-map > details > ol > li > a:focus,
.htmxo-architecture-map > details > ol > li > a[aria-current="true"] {
    border-color: var(--pico-primary-border);
    box-shadow: 0 0 0 var(--pico-outline-width) var(--pico-primary-focus);
}
.htmxo-architecture-map code,
.htmxo-architecture-explorer table code,
.htmxo-architecture-explorer dd,
.htmxo-architecture-explorer pre { overflow-wrap: anywhere; white-space: pre-wrap; }
.htmxo-architecture-explorer > article { scroll-margin-top: 1rem; }
.htmxo-architecture-explorer > article > header { display: grid; gap: 0.35rem; }
.htmxo-architecture-explorer > article dl,
.htmxo-architecture-explorer > article dd { min-width: 0; }
.htmxo-architecture-explorer > article aside {
    border-inline-start: 0.25rem solid var(--pico-primary-border);
    padding-inline-start: 1rem;
}
.htmxo-architecture-explorer form[role="search"] {
    display: grid;
    grid-template-columns: minmax(12rem, 1fr) auto auto;
    gap: var(--htmxo-architecture-gap);
    align-items: end;
}
@media (max-width: 40rem) {
    .htmxo-architecture-explorer form[role="search"] { grid-template-columns: 1fr; }
}
"""))

"""
    application_explorer_view(descriptor; selected="", query="", overlay=nothing,
                              base="", live=false, live_available=overlay !== nothing)

Render a server-side application architecture explorer with synchronized Map,
Inspector and searchable Reference views. Every node is an ordinary link and
every search is an ordinary GET, so the complete descriptor remains navigable
without JavaScript or a client-side visualization library. `selected` is a
stable node ID and therefore forms a durable deep link. Full labels, IDs,
documentation, signatures, dependencies, source/code provenance and unknown
contribution metadata are rendered rather than abbreviated or discarded.

When supplied, `overlay` is displayed in a separate live-observation panel; it
is never merged into or substituted for the declaration graph.
"""
function application_explorer_view(descriptor; selected="", query="",
        overlay=nothing, base="", live::Bool=false,
        live_available::Bool=overlay !== nothing)
    descriptor.schema == _APPLICATION_DESCRIPTOR_SCHEMA || throw(ArgumentError(
        "expected $(_APPLICATION_DESCRIPTOR_SCHEMA), got $(repr(descriptor.schema))"))
    selected_id = isempty(selected) ? descriptor.root : selected
    _architecture_find_node(descriptor, selected_id)
    live_control = if live_available
        live ? h.a("Show declarations only";
                   href=query_url(base; selected=selected_id,
                                  q=isempty(query) ? nothing : query)) :
               h.a("Add live observations";
                   href=query_url(base; selected=selected_id,
                                  q=isempty(query) ? nothing : query,
                                  live=true))
    else
        h.small("No live object attached; showing declarations only.")
    end
    h.section(
        application_explorer_styles(),
        h.header(
            h.p("Application architecture"),
            h.h1("Map, Inspector, Reference"),
            h.p("Static declarations are primary. Routes, dependencies, artifacts, source and contributed domain links share stable IDs."),
            h.nav(h.ul(
                h.li(h.a("Map"; href="#architecture-map")),
                h.li(h.a("Inspector"; href="#architecture-inspector")),
                h.li(h.a("Reference"; href="#architecture-reference")),
                h.li(live_control),
            ); aria_label="Explorer sections"),
        ),
        h.section(
            h.h2("Map"; id="architecture-map-title"),
            h.p(string(length(descriptor.nodes), " nodes · ",
                       length(descriptor.edges), " declared relationships")),
            _architecture_map(descriptor, selected_id; base, query, live);
            id="architecture-map",
            aria_labelledby="architecture-map-title",
        ),
        _architecture_inspector(descriptor, selected_id;
                                overlay, base, query, live),
        _architecture_reference(descriptor, selected_id;
                                base, query, live);
        class="htmxo-architecture-explorer",
    )
end

"""
    ReflectionRoutes(; root::Type, target=nothing, contributions=())

Mountable reflection surface for an `@htmx` application. Mount opt-in via
`@include` on any `@htmx struct`:

```julia
@include reflect = ReflectionRoutes(; root=MyApp)   # → GET /reflect
```

Provides:

- `@get index(; selected, q, live)` — the application architecture explorer,
  rendered on the server with stable node deep links and search.
- `@get graph()` — the same graph as JSON, for tooling that wants the semantic
  model rather than the flat route table (the existing nested graph contract).
- `@get descriptor()` — the deterministic flat [`application_descriptor`](@ref)
  as JSON.
- `@get observations()` — the separate noncomputing live overlay as JSON when
  `target` is supplied.

Distinct from [`SchemaRoutes`](@ref), which serves the flat `reflect(root)`
route index at `/schema` and is unchanged by this bundle. Mount either, both,
or neither.
"""
@htmx struct ReflectionRoutes
    root::Type = Any
    target::Any = nothing
    contributions::Any = ()

    @get index(; selected::String="", q::String="", live::Bool=false) = begin
        local app_graph = application_descriptor(root; contributions)
        overlay = live ? begin
            target === nothing && throw(ArgumentError(
                "live observations requested but ReflectionRoutes has no target object"))
            application_observations(target, app_graph)
        end : nothing
        application_explorer_view(app_graph; selected, query=q, overlay,
                                  base=__route__, live,
                                  live_available=target !== nothing)
    end
    @get graph() = MIMEResponse("application/json",
                                _schema_json_encode(semantic_descriptor(root).graph))
    @get descriptor() = MIMEResponse("application/json",
        _schema_json_encode(application_descriptor(root; contributions)))
    @get observations() = begin
        target === nothing && throw(ArgumentError(
            "ReflectionRoutes observations require an explicit target object"))
        local app_graph = application_descriptor(root; contributions)
        MIMEResponse("application/json",
                     _schema_json_encode(application_observations(target, app_graph)))
    end
end
