# --- Reflection endpoint ---------------------------------------------------
#
# ReflectionRoutes — the HUMAN-READABLE semantic surface, mounted opt-in:
#
#   @include reflect = ReflectionRoutes(; root=MyApp)   # → /reflect
#
#   GET /reflect        the semantic graph, rendered
#   GET /reflect/graph  the same graph as JSON
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
# The view is structural `h.*` only — sections, headings, tables, `code`. No
# classes, no inline styles, no framework-specific markup: the mounting
# application's stylesheet decides how it looks, and `?plain` renders it as
# markdown through the ordinary response pipeline with no special-casing here.

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

Render one input's option domain. The four `kind`s answer genuinely different
questions and are NOT flattened into one "here are the choices" cell:

- `:static` — DynamicObjects proved the value set (a `Bool`, an `Enum`); the
  options ARE the domain.
- `:declared` — the application declared `@options p = <expr>`. DynamicObjects
  records the expression and never evaluates it, so `options` is empty by
  design. Shown as the expression plus what it depends on. Rendering this as
  "no options" would assert the opposite of what it means.
- `:dynamic` — a provider supplies the values at runtime.
- `:unrestricted` / absent — no domain is claimed.
"""
function _view_domain(domain)
    domain === nothing && return "—"
    kind = get(domain, :kind, :unrestricted)
    deps = get(domain, :dependencies, Symbol[])
    if kind === :static
        options = get(domain, :options, [])
        isempty(options) ? _view_code(kind) :
            h.span(_view_code(kind), " ", _view_list(options))
    elseif kind === :declared
        declaration = get(domain, :declaration, nothing)
        expression = declaration === nothing ? nothing :
                     get(declaration, :expression_string, nothing)
        children = Any[_view_code(kind)]
        isnothing(expression) || (push!(children, " "); push!(children, h.code(expression)))
        isempty(deps) || (push!(children, " depends on "); push!(children, _view_list(deps)))
        h.span(children...)
    elseif kind === :dynamic
        provider = get(domain, :provider, nothing)
        children = Any[_view_code(kind)]
        isnothing(provider) || (push!(children, " via "); push!(children, _view_code(provider)))
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

"""
    ReflectionRoutes(; root::Type)

Mountable reflection surface for an `@htmx` application. Mount opt-in via
`@include` on any `@htmx struct`:

```julia
@include reflect = ReflectionRoutes(; root=MyApp)   # → GET /reflect
```

Provides:

- `@get index()` — the semantic graph of `root`, rendered for a human
  ([`semantic_graph_view`](@ref)); markdown under `?plain`.
- `@get graph()` — the same graph as JSON, for tooling that wants the semantic
  model rather than the flat route table.

Distinct from [`SchemaRoutes`](@ref), which serves the flat `reflect(root)`
route index at `/schema` and is unchanged by this bundle. Mount either, both,
or neither.
"""
@htmx struct ReflectionRoutes
    root::Type = Any

    @get index() = semantic_graph_view(root)
    @get graph() = MIMEResponse("application/json",
                                _schema_json_encode(semantic_descriptor(root).graph))
end
