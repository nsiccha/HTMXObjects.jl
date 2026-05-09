# --- Structure browser ----------------------------------------------------

# Tree-render helpers for StructureRoutes. Build a parent→children map from
# DynamicObjects' parent_map, then render as nested <ul><li>.
function _structure_children_map(root::Type)
    parent_map = DynamicObjects._build_parent_map(root)
    children = Dict{Type, Vector{Tuple{Symbol, Type}}}()
    for (child, (parent, prop)) in parent_map
        push!(get!(children, parent, Tuple{Symbol, Type}[]), (prop, child))
    end
    for v in values(children)
        sort!(v; by = p -> string(p[1]))
    end
    children
end

function _structure_lint_index(root::Type)
    msgs = try DynamicObjects.analyze_structure(root) catch; DynamicObjects.LintMessage[] end
    out = Dict{Type, NamedTuple{(:warns, :errors, :msgs), Tuple{Int, Int, Vector{DynamicObjects.LintMessage}}}}()
    for m in msgs
        e = get!(() -> (warns=0, errors=0, msgs=DynamicObjects.LintMessage[]), out, m.type)
        push!(e.msgs, m)
        out[m.type] = (
            warns  = e.warns  + (m.severity === :warn  ? 1 : 0),
            errors = e.errors + (m.severity === :error ? 1 : 0),
            msgs   = e.msgs,
        )
    end
    out
end

_structure_lint_badge(warns::Int, errors::Int) =
    iszero(warns + errors) ? "" :
    string(" ", iszero(errors) ? "" : "✗$errors ", iszero(warns) ? "" : "⚠$warns")

function _render_structure_tree(T::Type, children::Dict, link_for, lints)
    name = string(nameof(T))
    info = get(lints, T, (warns=0, errors=0, msgs=DynamicObjects.LintMessage[]))
    label_parts = Any[h.a(; href = link_for(name))(name)]
    badge = _structure_lint_badge(info.warns, info.errors)
    isempty(badge) || push!(label_parts,
        h.small(; class = info.errors > 0 ? "text-danger" : "text-warn")(badge))
    kids = get(children, T, Tuple{Symbol, Type}[])
    isempty(kids) && return h.li(label_parts...)
    h.li(label_parts..., h.ul(map(p -> _render_structure_tree(p[2], children, link_for, lints), kids)...))
end

function _structure_lookup_type(root::Type, name::AbstractString)
    for T in DynamicObjects._all_types_in_tree(root)
        string(nameof(T)) == name && return T
    end
    nothing
end

function _structure_render_source(T::Type, prop::Symbol)
    props = try DynamicObjects.meta(T) catch; nothing end
    props === nothing && return h.p("No meta() for $(nameof(T))")
    haskey(props, prop) || return h.p("No property $prop on $(nameof(T))")
    info = props[prop]
    rhs = info.rhs
    src = rhs === nothing ? "(no rhs — forwarded/typed property)" :
          string(Base.remove_linenums!(deepcopy(rhs)))
    sig = isempty(info.indices) ? string(info.lhs) :
          string(info.lhs, "(", join(info.indices, ", "), ")")
    macros = isempty(info.macros) ? "" : join(string.(info.macros), " ") * " "
    deps = isempty(info.dependson) ? "(none)" : join(sort!(collect(info.dependson)), ", ")
    h.div(
        h.h3("$macros$sig"),
        h.p(h.small("dependson: $deps")),
        h.pre(h.code(; class="language-julia")(src)),
    )
end

function _structure_callers_by_name(prop::Symbol, root::Type)
    types_in_tree = DynamicObjects._all_types_in_tree(root)
    call_index = DynamicObjects._build_call_index(types_in_tree)
    get(call_index, prop, Vector{Tuple{Type,Symbol,Vector{Any}}}())
end

"""
    StructureRoutes(; root::Type)

Live browser for the DynamicObjects type tree rooted at `root`. Mount inside
an `@htmx struct` with `@include structure = StructureRoutes(; root=AppContext)`
to expose:

- `/structure` — tree of every type reachable from `root`, with per-type lint
  badges (`✗N` errors, `⚠N` warns) from `DynamicObjects.analyze_structure`.
- `/structure/type?name=T` — `DynamicObjects.structure(T)` rendering with
  inline lint hints, plus a per-property links list to source/callers.
- `/structure/source?name=T&prop=p` — the property's RHS expression
  (lnn-stripped), signature, and `dependson` set.
- `/structure/callers?name=T&prop=p` — every site that calls a property named
  `p` (matched by callee NAME across the whole tree, not by resolved owner
  type — cross-type collisions show up too).
- `/structure/lints[?severity=error|warn]` — aggregated lint dump grouped
  by type.

Useful for debugging refactors, finding misplaced IPs, and locating
single-callsite helpers without grepping. Cheap to mount — recomputes lints
on each request.
"""
@htmx struct StructureRoutes
    # Generic structure browser. Mount via `@include structure = StructureRoutes(; root=AppContext)`.
    root::Type = Any

    @param begin
        name::String     = ""
        prop::String     = ""
        severity::String = ""
    end

    _nav_links = h.p(
        h.a(; href = string(__self__))("tree"), " · ",
        h.a(; href = string(__self__/"lints"))("lints"), " · ",
        h.small(h.em("?name=T&prop=p for source/callers")),
    )

    @get index = begin
        local lint_index = _structure_lint_index(root)
        local children   = _structure_children_map(root)
        local link_for   = n -> query_url(__self__/"type"; name = n)
        local n_warn     = sum(v.warns  for v in values(lint_index); init=0)
        local n_err      = sum(v.errors for v in values(lint_index); init=0)
        h.div(
            h.h2("DO type tree"),
            _nav_links,
            h.p(h.small("All DynamicObjects types reachable from $(string(nameof(root))). Click a type to view its dependency structure. Badges: ✗ errors / ⚠ warnings from analyze_structure(). $(n_warn) warns, $(n_err) errors total — see /structure/lints for the global dump.")),
            h.ul(_render_structure_tree(root, children, link_for, lint_index)),
        )
    end

    @get type = begin
        T = _structure_lookup_type(root, name)
        isnothing(T) && return h.div(_nav_links, h.h2("Unknown type: $name"))
        props = try DynamicObjects.meta(T) catch; nothing end
        prop_links = props === nothing ? h.div() : h.div(
            h.h3("Property source / callers"),
            h.ul(map(sort!(collect(keys(props)); by=string)) do p
                ps = string(p)
                h.li(
                    h.code(ps), " — ",
                    h.a(; href = query_url(__self__/"source"; name, prop = ps))("source"), " · ",
                    h.a(; href = query_url(__self__/"callers"; name, prop = ps))("callers"),
                )
            end...),
        )
        h.div(
            _nav_links,
            h.h2("Structure of $(string(nameof(T)))"),
            h.p(h.small("DynamicObjects.structure — bond colors mark identical worst-case dependency sets")),
            DynamicObjects.structure(T),
            prop_links,
        )
    end

    @get source = begin
        T = _structure_lookup_type(root, name)
        isnothing(T) && return h.div(_nav_links, h.h2("Unknown type: $name"))
        h.div(
            h.p(h.a(; href = query_url(__self__/"type"; name))("← back to $(name)")),
            h.h2("$(name).$(prop) source"),
            _structure_render_source(T, Symbol(prop)),
        )
    end

    @get callers = begin
        sites = _structure_callers_by_name(Symbol(prop), root)
        h.div(
            h.p(isempty(name) ? h.a(; href = string(__self__))("← tree") :
                                h.a(; href = query_url(__self__/"type"; name))("← back to $(name)")),
            h.h2("Callers of `$(prop)`"),
            h.p(h.small("Matched by callee NAME across the whole tree (not by resolved owner type — name collisions across types appear here too).")),
            isempty(sites) ? h.p(h.em("no call sites found")) :
            h.ul(map(sites) do (caller_T, caller_prop, args)
                argstr = isempty(args) ? "" : "(" * join(string.(args), ", ") * ")"
                h.li(
                    h.a(; href = query_url(__self__/"source"; name = string(nameof(caller_T)), prop = string(caller_prop)))(
                        string(nameof(caller_T)), ".", string(caller_prop)
                    ),
                    " — calls ", h.code("$(prop)$argstr"),
                )
            end...),
        )
    end

    @get lints = begin
        msgs = try DynamicObjects.analyze_structure(root) catch; DynamicObjects.LintMessage[] end
        sev_filter = isempty(severity) ? nothing : Symbol(severity)
        filtered = sev_filter === nothing ? msgs : filter(m -> m.severity === sev_filter, msgs)
        by_type = Dict{Type, Vector{DynamicObjects.LintMessage}}()
        for m in filtered
            push!(get!(by_type, m.type, DynamicObjects.LintMessage[]), m)
        end
        ordered = sort!(collect(keys(by_type)); by = T -> string(nameof(T)))
        h.div(
            _nav_links,
            h.h2("Global DO lints"),
            h.p(h.small("From DynamicObjects.analyze_structure($(string(nameof(root)))). $(length(filtered)) messages across $(length(ordered)) types.")),
            h.p(
                h.a(; href = string(__self__/"lints"))("all"), " · ",
                h.a(; href = query_url(__self__/"lints"; severity="error"))("errors only"), " · ",
                h.a(; href = query_url(__self__/"lints"; severity="warn"))("warns only"),
            ),
            isempty(ordered) ? h.p(h.em("(no lints — clean tree)")) :
            h.div(map(ordered) do T
                tname = string(nameof(T))
                ms = by_type[T]
                h.section(
                    h.h3(h.a(; href = query_url(__self__/"type"; name = tname))(tname)),
                    h.ul(map(ms) do m
                        sev_class = m.severity === :error ? "text-danger" : "text-warn"
                        prop_label = m.prop === nothing ? "(struct-level)" : string(m.prop)
                        h.li(
                            h.span(; class = sev_class)(m.severity === :error ? "✗" : "⚠"),
                            " ", h.strong(prop_label), " — ", m.short,
                            isempty(m.long) || m.long == m.short ? "" :
                                h.details(h.summary("details"), h.pre(h.code(m.long))),
                        )
                    end...),
                )
            end...),
        )
    end
end
