# --- Structure browser ----------------------------------------------------
#
# Routes + HTML rendering only. The pure-DO compute (tree walk, lint
# aggregation, type lookup, caller index, property metadata extraction)
# lives in DynamicObjects's public API:
#
#   tree_children_map(root)     → parent→children map
#   lint_index(root)            → per-type warn/error counts + msgs
#   lookup_type(root, name)     → name-string → Type
#   callers_by_name(prop, root) → call sites for a property name
#   property_source_info(T, p)  → rhs_string, signature, macros, dependson
#
# Non-web consumers (REPL, scripts, other web frameworks) can use those
# directly without loading HTMXObjects.

# Inline lint badge text, tucked next to a type name in the tree view.
_structure_lint_badge(warns::Int, errors::Int) =
    iszero(warns + errors) ? "" :
    string(" ", iszero(errors) ? "" : "✗$errors ", iszero(warns) ? "" : "⚠$warns")

# Render the parent→children map as nested <ul><li>.
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

# Render a property's source info NamedTuple (from
# DynamicObjects.property_source_info) as an HTML block.
function _render_property_source(T::Type, prop::Symbol)
    info = DynamicObjects.property_source_info(T, prop)
    info === nothing && return h.p("No meta() for $(nameof(T))")
    deps = isempty(info.dependson) ? "(none)" : join(info.dependson, ", ")
    h.div(
        h.h3("$(info.macros)$(info.signature)"),
        h.p(h.small("dependson: $deps")),
        h.pre(h.code(; class="language-julia")(info.rhs_string)),
    )
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
        local lints    = DynamicObjects.lint_index(root)
        local children = DynamicObjects.tree_children_map(root)
        local link_for = n -> query_url(__self__/"type"; name = n)
        local n_warn   = sum(v.warns  for v in values(lints); init=0)
        local n_err    = sum(v.errors for v in values(lints); init=0)
        h.div(
            h.h2("DO type tree"),
            _nav_links,
            h.p(h.small("All DynamicObjects types reachable from $(string(nameof(root))). Click a type to view its dependency structure. Badges: ✗ errors / ⚠ warnings from analyze_structure(). $(n_warn) warns, $(n_err) errors total — see /structure/lints for the global dump.")),
            h.ul(_render_structure_tree(root, children, link_for, lints)),
        )
    end

    @get type = begin
        T = DynamicObjects.lookup_type(root, name)
        isnothing(T) && return h.div(_nav_links, h.h2("Unknown type: $name"))
        # `meta(T)` only has methods for types declared via `@dynamicstruct`/
        # `@htmx`. Plain Julia types reachable through the tree (Int, String,
        # …) have no metadata — handle that explicitly via `hasmethod` rather
        # than catching every possible error from `meta(T)` itself.
        props = hasmethod(DynamicObjects.meta, Tuple{Type{T}}) ? DynamicObjects.meta(T) : nothing
        prop_links = props === nothing ? h.div() : h.div(
            h.h3("Property source / callers"),
            h.ul(map(sort!(unique!([n for (n, _) in props]); by=string)) do p
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
        T = DynamicObjects.lookup_type(root, name)
        isnothing(T) && return h.div(_nav_links, h.h2("Unknown type: $name"))
        h.div(
            h.p(h.a(; href = query_url(__self__/"type"; name))("← back to $(name)")),
            h.h2("$(name).$(prop) source"),
            _render_property_source(T, Symbol(prop)),
        )
    end

    @get callers = begin
        sites = DynamicObjects.callers_by_name(Symbol(prop), root)
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
        msgs = DynamicObjects.analyze_structure(root)
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
