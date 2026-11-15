# Browser computation for semantic pages: `@browser`, `browser_module`, `bound`.
#
# A `semantic_app(…; presentation=:tabs)` page asks the server again for a
# result when an input it reads changes. A property declared
# `@browser(name) = browser_module(file, entry)` has a browser twin: an ES module
# (what `ReactiveKernels.js_source` emits) computing the same value from the
# page's inputs. A result that shows that property only through `bound(...)`
# marks is computed and redrawn in the browser instead, with no request, so a
# static export keeps following its inputs offline. The lowering of `@browser`
# and `bound` lives beside `@help` in HTMXObjects.jl; this file holds the
# values, the page regions, their runtime and the export's checks.

"""
    BrowserModule

An ES module a page runs in the browser, made by [`browser_module`](@ref):
its source text, the name of the exported function to call, and its
arguments as the module's `INPUTS` list names them (`(name, Julia type)`, in
order).
"""
struct BrowserModule
    source::String
    entry::String
    inputs::Vector{Tuple{String,String}}
end

const _BROWSER_ENTRY = r"^[A-Za-z_$][A-Za-z0-9_$]*$"
const _BROWSER_INPUTS = r"export\s+const\s+INPUTS\s*=\s*\[(.*?)\]\s*;?"s
const _BROWSER_INPUT = r"\{\s*\"?name\"?\s*:\s*\"([^\"]+)\"\s*,\s*\"?type\"?\s*:\s*\"([^\"]+)\"\s*\}"

function BrowserModule(source::AbstractString, entry)
    src = String(source)
    name = String(string(entry))
    occursin(_BROWSER_ENTRY, name) || throw(ArgumentError(
        "browser_module: the entry $(repr(name)) is not a JavaScript name"))
    occursin(r"</script"i, src) && throw(ArgumentError(
        "browser_module: the module text contains `</script`, which cannot be embedded in a page"))
    exported = Regex(string("export\\s+(?:async\\s+)?function\\s*\\*?\\s*", name, "\\s*\\(|",
                            "export\\s+(?:const|let|var)\\s+", name, "\\b|",
                            "export\\s*\\{[^}]*\\b", name, "\\b[^}]*\\}"))
    occursin(exported, src) || throw(ArgumentError(
        "browser_module: the module exports no function `$name`"))
    m = match(_BROWSER_INPUTS, src)
    m === nothing && throw(ArgumentError(string(
        "browser_module: the module exports no `INPUTS` list naming its arguments in order ",
        "(`export const INPUTS = [{ name: \"x\", type: \"Float64\" }, …]`, as ",
        "`ReactiveKernels.js_source` writes it)")))
    inputs = Tuple{String,String}[(String(x[1]), String(x[2])) for x in eachmatch(_BROWSER_INPUT, m[1])]
    BrowserModule(src, name, inputs)
end

const _BROWSER_FILES = Dict{Tuple{String,String},Tuple{Float64,BrowserModule}}()
const _BROWSER_FILES_LOCK = ReentrantLock()

"""
    browser_module(path, entry) -> BrowserModule
    browser_module(; source, entry) -> BrowserModule

The ES module a `@browser` declaration computes its property with, read from
the file `path` (relative to the working directory, read again when it
changes) or given as `source` text, such as the string
`ReactiveKernels.js_source` returns:

```julia
prediction = PREDICT(water, attenuation, density)
@browser(prediction) = browser_module("assets/shielding.mjs", :shielding)
```

The module is the one `ReactiveKernels.js_source` emits, and any other that
keeps its contract: it exports the function `entry`, which takes positional
arguments, and `INPUTS`, the list of their names and Julia types in that order
(`export const INPUTS = [{ name: "water", type: "Vector{Float64}" }, …]`).
`entry` returns the property's value: an object of named outputs for a named
tuple, or a number or array. An error it throws is shown in the result, under
its `name` (`DomainError`, …). The page passes each argument by its name: a
`@param` from its control (`Float64`, `Int64`, `Bool` and vectors of them, or
text), any other from the property of that name, which must not read an input;
its value goes into the page as data. The module is embedded in the page, so it
must be one self-contained file.
"""
function browser_module(path::AbstractString, entry)
    full = abspath(path)
    isfile(full) || throw(ArgumentError(
        "browser_module: no file $(repr(path)) (looked at $full)"))
    changed = mtime(full)
    key = (full, string(entry))
    lock(_BROWSER_FILES_LOCK) do
        cached = get(_BROWSER_FILES, key, nothing)
        cached !== nothing && cached[1] == changed && return cached[2]
        m = BrowserModule(read(full, String), entry)
        _BROWSER_FILES[key] = (changed, m)
        m
    end
end
browser_module(; source::AbstractString, entry) = BrowserModule(source, entry)

# --- `bound`: where a browser value shows in a view ---

"""
    bound(x)
    bound(x.field)
    bound(x.field[i])
    bound(x; digits=n)
    bound(x; columns=(:a, :b, …))

Inside an `@htmx` struct, marks where a route's view shows a value the browser
computes: a property declared `@browser`, one of its outputs or their elements
(`i` an integer literal), or a `@param`. On the server it shows the value, as
Julia's `string` writes it (rounded to `digits` decimals); a page that computes
the property in the browser rewrites it there after each change. With `columns`
it is the property's equal-length vector outputs as a Tables.jl table, for a
plot's `data(...)`; give the element showing it [`bound_columns_attrs`](@ref).

The `@htmx` macro recognizes `bound(...)` calls in its struct and records which
value each names, so `bound` needs no import there; it has no meaning outside
one.
"""
bound(_x...; _kw...) = throw(ArgumentError(string(
    "`bound` marks a value inside an `@htmx` struct's routes and properties, where ",
    "the macro records which property or `@param` it names; it has no meaning outside one")))

"""
    BoundValue

What `bound(x)` is on the server: the value, shown as text, and the path that
tells a browser page where its value comes from.
"""
struct BoundValue{T}
    path::Vector{Any}
    value::T
    digits::Union{Nothing,Int}
end

"""
    BoundColumns

What `bound(x; columns)` is on the server: the property's chosen equal-length
vector outputs as a Tables.jl table, and the path a browser page reads them
from.
"""
struct BoundColumns{T}
    path::Vector{Any}
    value::T
    columns::Vector{Symbol}
end

function _bound(path::Tuple, value; digits=nothing, columns=nothing)
    columns === nothing || return _bound_columns(Any[path...], value, columns)
    digits === nothing || digits isa Integer || throw(ArgumentError(
        "bound: `digits` must be an integer, got $(repr(digits))"))
    BoundValue(Any[path...], value, digits === nothing ? nothing : Int(digits))
end

function _bound_columns(path, value, columns)
    names = Symbol[Symbol(c) for c in (columns isa Union{Tuple,AbstractVector} ? columns : (columns,))]
    isempty(names) && throw(ArgumentError("bound(…; columns): name at least one column"))
    lengths = map(names) do c
        hasproperty(value, c) || throw(ArgumentError(
            "bound(…; columns): $(_bound_label(path)) has no output `$c`"))
        column = getproperty(value, c)
        column isa AbstractVector || throw(ArgumentError(
            "bound(…; columns): $(_bound_label(path)).$c is not a vector"))
        length(column)
    end
    allequal(lengths) || throw(ArgumentError(string(
        "bound(…; columns): the columns of ", _bound_label(path), " differ in length (",
        join((string(c, " ", n) for (c, n) in zip(names, lengths)), ", "), ")")))
    BoundColumns(path, value, names)
end

_bound_label(path) = join((p isa Integer ? string("[", p, "]") : string(i == 1 ? "" : ".", p.value)
                           for (i, p) in enumerate(path)), "")
_bound_wire(path) = Any[p isa QuoteNode ? string(p.value) : p for p in path]

Tables.istable(::Type{<:BoundColumns}) = true
Tables.columnaccess(::Type{<:BoundColumns}) = true
Tables.columns(b::BoundColumns) =
    NamedTuple{Tuple(b.columns)}(Tuple(getproperty(b.value, c) for c in b.columns))

"""
    bound_columns_attrs(b::BoundColumns; dataset="source_0") -> NamedTuple

The attributes of the element that shows the table `bound(x; columns)` made,
such as the element of a plot drawn from it. After the browser computes the
property again, a page calls `AoV.updateData(id, rows, dataset)` for an element
with an `id` (AlgebraOfVega's runtime) and raises `htmxo:bound-columns` on it
with the new columns in `event.detail`.
"""
bound_columns_attrs(b::BoundColumns; dataset::AbstractString="source_0") =
    (; data_htmxo_bound_columns=JSON.json(Dict("path" => _bound_wire(b.path),
        "columns" => string.(b.columns), "dataset" => String(dataset))))

_bound_kind(::Bool) = "bool"
_bound_kind(::Integer) = "int"
_bound_kind(::AbstractFloat) = "float"
_bound_kind(_) = "text"
_bound_text(b::BoundValue) = _bound_text(b.value, b.digits)
_bound_text(x::Bool, _) = string(x)
_bound_text(x::Integer, _) = string(x)
_bound_text(x::AbstractFloat, digits) =
    string(Float64(digits === nothing ? x : round(x; digits=digits)))
_bound_text(x, _) = string(x)

_bound_node(b::BoundValue) = h.span(_bound_text(b);
    data_htmxo_bound=JSON.json(_bound_wire(b.path)), data_htmxo_kind=_bound_kind(b.value),
    (b.digits === nothing ? (;) : (; data_htmxo_digits=string(b.digits)))...)

Base.show(io::IO, m::MIME"text/html", b::BoundValue) = show(io, m, _bound_node(b))
Base.show(io::IO, ::MIME"text/markdown", b::BoundValue) = print(io, _bound_text(b))
Base.show(io::IO, ::MIME"text/plain", b::BoundValue) = print(io, _bound_text(b))
Base.print(io::IO, b::BoundValue) = print(io, _bound_text(b))

# --- The regions of a page whose results the browser computes ---

# What one `semantic_app(…; presentation=:tabs)` render has emitted of its
# browser parts, so each binding, module and the runtime go into the page once,
# and what a static export of it cannot serve.
struct _BrowserPage
    id::String
    static::Any                      # the request's `StaticExport`, or `nothing`
    bindings::Dict{Symbol,String}    # property => its binding's element id
    payloads::Dict{String,Any}       # binding element id => what it says
    modules::Dict{String,String}     # module source => its element id
    written::Set{String}             # element ids already in the page
    runtime::Base.RefValue{Bool}
    problems::Vector{String}
end
_BrowserPage(id, static) = _BrowserPage(id, static, Dict{Symbol,String}(), Dict{String,Any}(),
    Dict{String,String}(), Set{String}(), Ref(false), String[])

_browser_static(obj) = (req = _req_of(obj); req isa HTTP.Request ?
    get(req.context, :htmxo_static_export, nothing) : nothing)

# The `@browser` properties the operation `name` of `obj` reads.
function _browser_reads(obj, name::Symbol)
    T = typeof(obj)
    declared = Base.invokelatest(_browser_properties, T)
    isempty(declared) && return Symbol[]
    found = _operation_reads(T, name)
    Symbol[p for p in declared if p in found.names]
end

# The values a finite input takes, as the page's controls offer them; `nothing`
# for a continuous or free input.
function _browser_finite_values(obj, route, param, current)
    T = param.type
    T === Bool && return Any[false, true]
    T isa Type && T <: Enum && return Any[instances(T)...]
    domain = try
        _resolved_input_domain(obj, typeof(obj), param, current)
    catch
        nothing
    end
    domain === nothing && return nothing
    get(domain, :multiple, false) && return nothing
    options = get(domain, :options, nothing)
    options === nothing || isempty(options) ? nothing :
        Any[o.value for o in options if !get(o, :disabled, false)]
end

const _BROWSER_VARIANTS_MAX = 64

# One rendering of a result's address, as the page loads it: the bare fragment,
# under the page's static export when there is one.
function _browser_render(url::AbstractString; static=nothing)
    resp = dispatch(:GET, url; headers=["HX-Request" => "true"], static,
                    operation_policy=:blocking)
    (; status=resp.status, body=String(_response_bytes(resp)),
       error=HTTP.header(resp, "X-HTMXO-Error-Id"))
end

_browser_json(x) = replace(JSON.json(x), "</" => "<\\/")

function _browser_variant_key(names, values)
    Dict{String,Any}(string(n) => _option_wire_string(values[n]) for n in names)
end

"""
    _browser_region(page, spec, route, current, target, sent, attrs) -> Node

The result region of an operation that reads `@browser` properties: its view
rendered for the page's current values and for each value of the finite inputs
it is sent, the bindings of those properties to their modules (once per page),
the modules and the runtime (once per page). Under a static export it also
records in `page.problems` what of the view would still need the server.
"""
function _browser_region(page::_BrowserPage, spec, route, current, target, sent, attrs, browser)
    obj = spec.mounted
    T = typeof(obj)
    operation = spec.base_entry.name
    bindings = String[_browser_binding!(page, obj, p) for p in browser]
    finite = Pair{Symbol,Vector{Any}}[]
    for param in route.params
        param.source === :path && continue
        param.name in sent || continue
        values = _browser_finite_values(obj, route, param, current)
        values === nothing || push!(finite, param.name => values)
    end
    combos = Iterators.product((last(f) for f in finite)...)
    count = prod((length(last(f)) for f in finite); init=1)
    count <= _BROWSER_VARIANTS_MAX || throw(ArgumentError(string(
        "semantic_app: the result `", operation, "` computes in the browser and would need ",
        count, " views, one per value of its finite inputs ",
        join((string("`", first(f), "`") for f in finite), ", "), "; at most ",
        _BROWSER_VARIANTS_MAX, " are rendered. Read fewer of them in its view.")))
    names = Symbol[first(f) for f in finite]
    views = Tuple{String,String,Bool}[]   # variant key, markup, at the current values
    for combo in (isempty(finite) ? ((),) : combos)
        values = copy(current)
        for (n, v) in zip(names, combo)
            values[n] = v
        end
        at_current = all(n -> isequal(get(current, n, nothing), values[n]), names)
        rendered = _browser_render(_semantic_follow_url(target, obj, route, values, sent);
                                   static=page.static)
        push!(views, (_browser_json(_browser_variant_key(names, values)), rendered.body, at_current))
    end
    # The current values may be none of the finite ones (a value the address
    # named that the domain no longer offers): show the first view then.
    shown = something(findfirst(last, views), 1)
    page.static === nothing ||
        _browser_check!(page, obj, route, current, target, sent, operation, names)
    nodes = Any[h.div(Raw(views[shown][2]); class="htmxo-browser-view",
                      data_htmxo_variant=views[shown][1])]
    # Each view's markup as rendered, the shown one's too: the browser shows
    # a view again from its template, never from what the page made of it.
    if length(views) > 1
        for (key, body, _) in views
            push!(nodes, h.template(Raw(body); data_htmxo_variant=key))
        end
    end
    # What an input sends when its control sends nothing (hidden, or not on
    # the page): its default, for the finite inputs' view and the bound values.
    defaults = Dict{String,Any}()
    for n in sent
        wire = try
            _browser_param_default(obj, n)
        catch
            nothing  # an input with no single wire value (a list of records)
        end
        wire === nothing || (defaults[string(n)] = wire)
    end
    append!(nodes, _browser_scripts!(page, bindings))
    if !page.runtime[]
        page.runtime[] = true
        push!(nodes, semantic_browser_script())
    end
    h.div(nodes...; attrs..., data_htmxo_browser=join(bindings, ' '),
          data_htmxo_browser_inputs=_browser_json(Dict("names" => string.(names),
                                                       "defaults" => defaults)))
end

# The wire values a `@param`'s control sends when the reader set nothing.
function _browser_param_default(obj, name::Symbol)
    source = something(_param_declaring_object(obj, name), obj)
    unbound = Base.invokelatest(getproperty(DynamicObjects, :remount), source;
                                __req__=nothing, __param_request__=nothing)
    _semantic_address_wire(getproperty(unbound, name))
end

# The binding of the `@browser` property `name` of `obj`: which module computes
# it and where each of the module's arguments comes from. Emitted once per page;
# returns its element id.
function _browser_binding!(page::_BrowserPage, obj, name::Symbol)
    haskey(page.bindings, name) && return page.bindings[name]
    T = typeof(obj)
    m = getproperty(obj, _browser_property(name))
    m isa BrowserModule || throw(ArgumentError(string(
        "`@browser(", name, ")` on ", T, " must be a `browser_module(file, entry)`, got ",
        typeof(m))))
    params = Set{Symbol}(Base.invokelatest(_param_names, T))
    inputs = Any[]
    for (input, type) in m.inputs
        sym = Symbol(input)
        if sym in params
            push!(inputs, Dict{String,Any}("name" => input, "type" => type, "param" => input,
                                           "default" => _browser_param_default(obj, sym)))
            continue
        end
        _browser_is_property(T, sym) || throw(ArgumentError(string(
            "the browser module for `", name, "` on ", T, " takes `", input, "`, which is ",
            "neither a `@param` nor a property of ", T, "; the page passes each argument ",
            "by its name")))
        found = _operation_reads(T, sym)
        changing = sort!(Symbol[n for n in found.names if n in params])
        (isempty(changing) && found.complete) || throw(ArgumentError(string(
            "the browser module for `", name, "` on ", T, " takes `", input, "`, which ",
            isempty(changing) ? "may read the page's inputs" :
                string("reads the input", length(changing) > 1 ? "s " : " ",
                       join((string("`", c, "`") for c in changing), ", ")),
            "; the page can pass a `@param` or fixed data, so compute it in the module")))
        push!(inputs, Dict{String,Any}("name" => input, "type" => type,
                                       "value" => _browser_data(getproperty(obj, sym), input)))
    end
    id = string(page.id, "-browser-", name)
    module_id = get!(page.modules, m.source) do
        string(page.id, "-browser-module-", length(page.modules) + 1)
    end
    page.bindings[name] = id
    page.payloads[id] = Dict{String,Any}("property" => string(name), "module" => module_id,
                                         "entry" => m.entry, "inputs" => inputs)
    id
end

_browser_is_property(T::Type, name::Symbol) = isdefined(DynamicObjects, :metafirst) &&
    Base.invokelatest(getproperty(DynamicObjects, :metafirst), T, name) !== nothing

# The bindings `ids` and their modules, as the elements the page has not
# written yet: the first region that refers to one carries it.
function _browser_scripts!(page::_BrowserPage, ids)
    nodes = Any[]
    for id in ids
        id in page.written && continue
        push!(page.written, id)
        binding = page.payloads[id]
        module_id = binding["module"]
        if !(module_id in page.written)
            push!(page.written, module_id)
            source = only(s for (s, i) in page.modules if i == module_id)
            push!(nodes, h.script(Raw(source); type="text/plain", id=module_id,
                                  data_htmxo_browser_module=""))
        end
        push!(nodes, h.script(Raw(_browser_json(binding)); type="application/json", id=id,
                              data_htmxo_browser_binding=""))
    end
    nodes
end

# A module argument that is data, as JSON carries it.
_browser_data(x::Bool, _) = x
_browser_data(x::Union{AbstractString,Symbol}, _) = string(x)
function _browser_data(x::Real, name)
    isfinite(x) || throw(ArgumentError("the browser module argument `$name` is $x, which JSON cannot carry"))
    x
end
_browser_data(x::AbstractVector, name) = Any[_browser_data(v, name) for v in x]
_browser_data(x, name) = throw(ArgumentError(string(
    "the browser module argument `", name, "` is a ", typeof(x), "; the page passes numbers, ",
    "booleans, text and vectors of them")))

# --- What a static export of a browser page cannot serve ---

# The markup of a result with the values it shows through `bound` taken out:
# the text of each bound value, and everything inside an element that shows
# bound columns (a plot's data). What remains must not change with an input
# the browser computes from, or the static page would show it stale.
const _BOUND_SPAN = r"(<span data-htmxo-bound=\"[^\"]*\"[^>]*>)[^<]*(</span>)"
function _browser_skeleton(html::AbstractString)
    s = replace(String(html), _BOUND_SPAN => s"\1\2")
    out = IOBuffer()
    i = firstindex(s)
    marker = "data-htmxo-bound-columns="
    while true
        j = findnext(marker, s, i)
        j === nothing && (write(out, SubString(s, i)); break)
        open_start = findprev('<', s, first(j))
        open_end = findnext('>', s, last(j))
        (open_start === nothing || open_end === nothing) && (write(out, SubString(s, i)); break)
        tag = match(r"^<([A-Za-z][A-Za-z0-9-]*)", SubString(s, open_start)).captures[1]
        write(out, SubString(s, i, open_end))
        close_at = _browser_closing(s, nextind(s, open_end), lowercase(tag))
        close_at === nothing && break
        i = close_at
    end
    String(take!(out))
end

# Where the element `tag` opened just before `i` closes (the index of its `</`),
# skipping script and style text; `nothing` when it never does.
function _browser_closing(s, i, tag)
    depth = 1
    while true
        j = findnext('<', s, i)
        j === nothing && return nothing
        rest = SubString(s, j)
        m = match(r"^<(/?)([A-Za-z][A-Za-z0-9-]*)", rest)
        if m === nothing
            i = nextind(s, j)
            continue
        end
        name = lowercase(m.captures[2])
        if m.captures[1] == "" && name in ("script", "style")
            k = findnext(Regex("</" * name * "\\s*>", "i"), s, j)
            k === nothing && return nothing
            i = nextind(s, last(k))
            continue
        end
        if name == tag
            depth += m.captures[1] == "/" ? -1 : 1
            depth == 0 && return j
        end
        i = nextind(s, j)
    end
end

# The probes of an input's value: changed values its route should accept.
_browser_probes(x::AbstractFloat) = (x * 1.1 + 1e-3, x * 0.9 - 1e-3, x * 1.01, x * 0.99, x + 1, x - 1)
_browser_probes(x::Integer) = (x + 1, x - 1, x + 2)
_browser_probes(x::AbstractString) = (string(x, "x"), "")
_browser_probes(_) = ()

# Under a static export, what in the view of `operation` changes with an input
# outside its bound values, which a static page would show stale. Each
# continuous input it is sent is changed in turn; finite inputs are views of
# their own.
function _browser_check!(page::_BrowserPage, obj, route, current, target, sent, operation, finite)
    base = _browser_render(_semantic_follow_url(target, obj, route, current, sent))
    skeleton = _browser_skeleton(base.body)
    for param in route.params
        param.source === :path && continue
        name = param.name
        name in sent && !(name in finite) || continue
        value = get(current, name, nothing)
        tried = String[]
        checked = false
        for probe in _browser_probes(value)
            changed = copy(current)
            changed[name] = probe
            rendered = _browser_render(_semantic_follow_url(target, obj, route, changed, sent))
            if rendered.status != 200 || !isempty(rendered.error)
                push!(tried, string(repr(probe), " → HTTP ", rendered.status))
                continue
            end
            checked = true
            _browser_skeleton(rendered.body) == skeleton || push!(page.problems, string(
                "the result `", operation, "` shows `", name, "` outside `bound`: its view ",
                "changes when `", name, "` does, so a static page would show it stale; ",
                "show the value with `bound(...)` or leave `", operation,
                "` out with `semantic_app(…; select=…)`"))
            break
        end
        checked || push!(page.problems, string(
            "the export could not check the result `", operation, "` with `", name,
            "` changed (", isempty(tried) ? "no value to try" : join(tried, ", "), ")"))
    end
end

# Under a static export of a page with a browser region, what else on it needs
# the server: a result that reads inputs and computes nothing in the browser,
# and a control that the server draws again when other inputs change.
function _browser_server_parts!(page::_BrowserPage, specs, routes, follows, browser_regions, reads, complete)
    for (i, spec) in enumerate(specs)
        follows[i] && !browser_regions[i] || continue
        operation = spec.base_entry.name
        sent = sort!(collect(reads[i]))
        (isempty(sent) && complete[i]) && continue
        push!(page.problems, string(
            "the result `", operation, "` ", isempty(sent) ? "may read the page's inputs" :
                string("reads ", join((string("`", n, "`") for n in sent), ", ")),
            " but computes nothing in the browser, so a static page would show it stale; ",
            "declare `@browser` for what it shows or leave it out with `semantic_app(…; select=…)`"))
    end
    seen = Set{Symbol}()
    for route in routes, param in route.params
        param.name in seen && continue
        push!(seen, param.name)
        get(param, :kind, nothing) === nothing && continue
        reasons = String[]
        domain = _semantic_domain_dependencies(param)
        isnothing(domain) || isempty(domain) || push!(reasons, string(
            "its `@options` read ", join((string("`", n, "`") for n in sort!(collect(domain))), ", ")))
        relevance = get(param, :relevance, nothing)
        isnothing(relevance) || isempty(relevance.dependencies) || push!(reasons,
            "its `@relevant` condition is not one the browser evaluates (comparisons and arithmetic of `@param`s)")
        help = get(param, :help, nothing)
        isnothing(help) || isempty(help.dependencies) || push!(reasons, "its `@help` text reads other inputs")
        defaulted = get(param, :default_reads, nothing)
        isnothing(defaulted) || isempty(defaulted) || push!(reasons, "its default reads other inputs")
        isempty(reasons) && continue
        push!(page.problems, string("the server draws the control of `", param.name,
            "` again when other inputs change (", join(reasons, "; "),
            "), which a static page cannot"))
    end
end

# Hand the problems to the export: `export_site` lists them as this page's
# failure; any other static render fails with them.
function _browser_report!(page::_BrowserPage)
    isempty(page.problems) && return nothing
    spec = page.static
    if spec isa StaticExport && spec.url_map isa _SiteMap
        log = spec.url_map.log
        lock(() -> append!(log.problems, page.problems), log.lock)
        return nothing
    end
    throw(ArgumentError(string("semantic_app: this page computes results in the browser, ",
        "but a static export of it would show some stale:\n  ", join(unique(page.problems), "\n  "))))
end

"""
    semantic_browser_script()

The runtime of the results a `semantic_app` page computes in the browser
(`@browser`): it loads each property's module once, calls it with the page's
inputs, shows the view of the finite inputs' values and writes the bound
values into it. A page that has such a result carries it in that result;
nothing to add by hand.
"""
semantic_browser_script() = h.script(Raw(raw"""
(function() {
  if (window.__htmxoSemanticBrowser) return;
  window.__htmxoSemanticBrowser = true;
  var style = document.createElement('style');
  style.textContent = '.htmxo-browser-view[data-htmxo-stale]{opacity:.45}' +
    '.htmxo-browser-fault{color:var(--pico-del-color,#c62828)}';
  document.head.appendChild(style);
  var has = function(o, k) { return Object.prototype.hasOwnProperty.call(o, k); };
  // Each module once per page, from the text the page embeds.
  var modules = new Map();
  function moduleOf(id) {
    var found = modules.get(id);
    if (found) return found;
    var el = document.getElementById(id);
    if (!el) return Promise.reject(new Error('the page has no browser module ' + id));
    found = import(URL.createObjectURL(new Blob([el.textContent], {type: 'text/javascript'})));
    modules.set(id, found);
    return found;
  }
  function parsed(el) {
    return el.__htmxoParsed || (el.__htmxoParsed = JSON.parse(el.textContent));
  }
  function bindingOf(id) {
    var el = document.getElementById(id);
    if (!el) throw new Error('the page has no browser binding ' + id);
    return parsed(el);
  }
  // A module argument from the wire strings a control sends, by its Julia type.
  function scalar(type, s) {
    if (/^(Float16|Float32|Float64|AbstractFloat|Real|Number|U?Int(8|16|32|64|128)?|Integer)$/.test(type))
      return s === '' ? NaN : Number(s);
    if (type === 'Bool') return s === 'true';
    return s;
  }
  function argument(input, values) {
    if (has(input, 'value')) return input.value;
    var given = values[input.param];
    var strings = given && given.length ? given : (input['default'] || []);
    var vector = /^(?:Abstract)?Vector\{(.+)\}$/.exec(input.type);
    if (vector) return strings.filter(function(s) { return s !== ''; })
      .map(function(s) { return scalar(vector[1], s); });
    return scalar(input.type, strings.length ? strings[0] : '');
  }
  // `bound(x.field[i])`: the path's parts after its root, indices 1-based.
  function at(value, path) {
    for (var i = 1; i < path.length; i++) {
      if (value === null || value === undefined) return undefined;
      var k = path[i];
      value = typeof k === 'number' ? value[k - 1] : value[k];
    }
    return value;
  }
  // Julia's `round(x; digits)`, ties to even, and `string(::Float64)`.
  function roundDigits(x, d) {
    var p = Math.pow(10, d), y = x * p, r = Math.round(y);
    if (Math.abs(y % 1) === 0.5) r = 2 * Math.round(y / 2);
    return r / p;
  }
  function juliaFloat(x) {
    if (x !== x) return 'NaN';
    if (x === Infinity) return 'Inf';
    if (x === -Infinity) return '-Inf';
    if (x === 0) return 1 / x < 0 ? '-0.0' : '0.0';
    var m = /^(-?)(\d)(?:\.(\d+))?e([+-]\d+)$/.exec(x.toExponential());
    var sign = m[1], digits = m[2] + (m[3] || ''), e = Number(m[4]);
    if (e > -5 && e < 6) {
      if (e < 0) return sign + '0.' + '0'.repeat(-e - 1) + digits;
      var whole = digits.length > e + 1 ? digits.slice(0, e + 1) : digits + '0'.repeat(e + 1 - digits.length);
      return sign + whole + '.' + (digits.slice(e + 1) || '0');
    }
    return sign + digits[0] + '.' + (digits.slice(1) || '0') + 'e' + e;
  }
  window.__htmxoJuliaFloat = juliaFloat;
  function text(value, kind, digits) {
    if (value === undefined || value === null) return null;
    if (kind === 'bool') return String(value === true || value === 'true');
    if (kind === 'float') {
      var n = typeof value === 'number' ? value : Number(value);
      return juliaFloat(digits === null || digits === '' ? n : roundDigits(n, Number(digits)));
    }
    if (kind === 'int') return String(typeof value === 'number' ? value : Number(value));
    return String(value);
  }
  function patch(view, results, values, defaults) {
    view.querySelectorAll('[data-htmxo-bound]').forEach(function(el) {
      var path = JSON.parse(el.getAttribute('data-htmxo-bound')), root = path[0], value;
      if (has(results, root)) value = at(results[root], path);
      else {
        var wire = values[root] && values[root].length ? values[root] : defaults[root];
        value = wire && wire.length ? wire[0] : undefined;
      }
      var shown = text(value, el.getAttribute('data-htmxo-kind'), el.getAttribute('data-htmxo-digits'));
      if (shown !== null && el.textContent !== shown) el.textContent = shown;
    });
    view.querySelectorAll('[data-htmxo-bound-columns]').forEach(function(el) {
      var spec = JSON.parse(el.getAttribute('data-htmxo-bound-columns'));
      if (!has(results, spec.path[0])) return;
      var table = at(results[spec.path[0]], spec.path), columns = {}, n = 0;
      spec.columns.forEach(function(c) {
        var column = Array.from(table[c]);
        columns[c] = column;
        n = column.length;
      });
      if (el.id && window.AoV && typeof window.AoV.updateData === 'function')
        window.AoV.updateData(el.id, {n: n, columns: columns}, spec.dataset);
      el.dispatchEvent(new CustomEvent('htmxo:bound-columns',
        {bubbles: true, detail: {path: spec.path, columns: columns, n: n}}));
    });
  }
  function sameKey(a, b) {
    var ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && ka.every(function(k) { return a[k] === b[k]; });
  }
  // The view rendered for the finite inputs' current values; the shown one
  // is replaced by its template when they change.
  function viewFor(region, values, inputs) {
    var key = {};
    inputs.names.forEach(function(name) {
      var wire = values[name] && values[name].length ? values[name] : inputs.defaults[name];
      key[name] = wire && wire.length ? wire[0] : '';
    });
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (!view || sameKey(JSON.parse(view.getAttribute('data-htmxo-variant')), key)) return view;
    var template = Array.prototype.find.call(region.querySelectorAll(':scope > template[data-htmxo-variant]'),
      function(t) { return sameKey(JSON.parse(t.getAttribute('data-htmxo-variant')), key); });
    if (!template) return null;
    view.setAttribute('data-htmxo-variant', template.getAttribute('data-htmxo-variant'));
    if (window.htmx && typeof window.htmx.swap === 'function')
      window.htmx.swap(view, template.innerHTML, {swapStyle: 'innerHTML'});
    else view.innerHTML = template.innerHTML;
    return view;
  }
  function fault(region, error) {
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (view) view.setAttribute('data-htmxo-stale', '');
    var note = region.querySelector(':scope > .htmxo-browser-fault');
    if (!note) {
      note = document.createElement('p');
      note.className = 'htmxo-browser-fault';
      note.setAttribute('role', 'alert');
      region.insertBefore(note, region.firstChild);
    }
    note.textContent = (error && error.name ? error.name + ': ' : '') +
      (error && error.message !== undefined ? error.message : String(error));
  }
  function clear(region) {
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (view) view.removeAttribute('data-htmxo-stale');
    var note = region.querySelector(':scope > .htmxo-browser-fault');
    if (note) note.remove();
  }
  var latest = new WeakMap();
  // Called by `semantic_follow_script` in place of a request, with the values
  // the region's request would carry. The newest call wins.
  window.__htmxoBrowserCompute = function(region, pairs) {
    var token = {};
    latest.set(region, token);
    var values = {};
    pairs.forEach(function(p) { (values[p[0]] = values[p[0]] || []).push(p[1]); });
    var inputs = JSON.parse(region.getAttribute('data-htmxo-browser-inputs') || '{"names":[],"defaults":{}}');
    var results = {};
    var work = (region.getAttribute('data-htmxo-browser') || '').split(' ').filter(Boolean).map(function(id) {
      var binding = bindingOf(id);
      return moduleOf(binding.module).then(function(mod) {
        var f = mod[binding.entry];
        if (typeof f !== 'function') throw new Error('the browser module exports no function ' + binding.entry);
        return f.apply(null, binding.inputs.map(function(i) { return argument(i, values); }));
      }).then(function(value) { results[binding.property] = value; });
    });
    return Promise.all(work).then(function() {
      if (latest.get(region) !== token) return;
      var view = viewFor(region, values, inputs);
      if (!view) throw new Error('no view of this result was rendered for these values');
      patch(view, results, values, inputs.defaults);
      clear(region);
      region.dispatchEvent(new CustomEvent('htmxo:browser-computed', {bubbles: true, detail: {results: results}}));
    }).catch(function(error) {
      if (latest.get(region) !== token) return;
      fault(region, error);
      if (window.console) console.error(error);
    });
  };
})();
"""))
