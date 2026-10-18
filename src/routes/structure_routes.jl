# --- Schema endpoint -------------------------------------------------------
#
# StructureRoutes (canonical alias: SchemaRoutes) — a single `@get index()`
# that serves the `reflect(root)` route walk as JSON. Mount opt-in via @include:
#
#   @include schema = SchemaRoutes(; root=MyApp)   # → /schema
#
# Route and param fields are `reflect`'s descriptor contract (see `reflect` in
# HTMXObjects.jl). By default each inherited `@param` is described once and
# routes refer to it (`_schema_document`); `?inherited=inline` serves the flat
# `reflect` array, which repeats every inherited `@param` on every route.

# RFC-8259 string escaping. Mirrors Claude/src/services.jl:115's _json_encode.
function _schema_json_encode(io::IO, x::AbstractString)
    write(io, '"')
    for c in x
        if c == '"';      write(io, "\\\"")
        elseif c == '\\'; write(io, "\\\\")
        elseif c == '\b'; write(io, "\\b")
        elseif c == '\f'; write(io, "\\f")
        elseif c == '\n'; write(io, "\\n")
        elseif c == '\r'; write(io, "\\r")
        elseif c == '\t'; write(io, "\\t")
        elseif c < ' ';   write(io, "\\u", lpad(string(UInt32(c); base=16), 4, '0'))
        else;              write(io, c)
        end
    end
    write(io, '"')
end
_schema_json_encode(io::IO, ::Nothing)  = write(io, "null")
_schema_json_encode(io::IO, x::Bool)   = write(io, x ? "true" : "false")
_schema_json_encode(io::IO, x::Integer) = write(io, string(x))
function _schema_json_encode(io::IO, x::AbstractFloat)
    isfinite(x) ? write(io, string(x)) : write(io, "null")
end
_schema_json_encode(io::IO, x::Symbol)           = _schema_json_encode(io, String(x))
_schema_json_encode(io::IO, ::Type{T}) where {T} = _schema_json_encode(io, string(T))
function _schema_json_encode(io::IO, xs::AbstractVector)
    write(io, '[')
    for (i, x) in enumerate(xs)
        i == 1 || write(io, ',')
        _schema_json_encode(io, x)
    end
    write(io, ']')
end
function _schema_json_encode(io::IO, xs::Tuple)
    write(io, '[')
    for (i, x) in enumerate(xs)
        i == 1 || write(io, ',')
        _schema_json_encode(io, x)
    end
    write(io, ']')
end
function _schema_json_encode(io::IO, dict::AbstractDict)
    write(io, '{')
    ordered = sort!(collect(pairs(dict)); by=pair -> string(first(pair)))
    for (i, (k, v)) in enumerate(ordered)
        i == 1 || write(io, ',')
        _schema_json_encode(io, string(k))
        write(io, ':')
        _schema_json_encode(io, v)
    end
    write(io, '}')
end
function _schema_json_encode(io::IO, nt::NamedTuple)
    write(io, '{')
    for (i, (k, v)) in enumerate(pairs(nt))
        i == 1 || write(io, ',')
        _schema_json_encode(io, String(k))
        write(io, ':')
        _schema_json_encode(io, v)
    end
    write(io, '}')
end
_schema_json_encode(io::IO, x) = _schema_json_encode(io, string(x))
_schema_json_encode(x) = sprint(_schema_json_encode, x)

"""
Wire values of `GET /schema?inherited=`: `shared` (the default) describes each
inherited `@param` once; `inline` repeats it on every route, as `reflect` does.
"""
module SchemaInherited
@enum Mode shared inline
end

# The `/schema` document: `reflect`'s route walk with every inherited `@param`
# described once. An app root's `@param`s reach every route mounted below it,
# so the flat array repeated ~115 root params on each of ~217 routes — 3 MB of
# copies (snag `schemaroutes-rep-4e4caea7`). Here a route keeps its own params
# inline and names a shared `context` instead:
#
#   routes    reflect's route fields, with `params` holding the route's call
#             params and its owner's own `@param`s, plus `context` and
#             `context_source` (query or body: where the route reads them)
#   contexts  "c<n>" => the param keys one route inherits, each distinct set once
#   params    "<DeclaringType>.<name>" => (name, declared_by, type, required,
#             default, doc) — keyed by the declaring type, so a shadowing
#             `@param` of the same name stays a separate entry
#
# The walk's cache already resolved which type declares each inherited param;
# the document reads that answer instead of resolving it again.
function _schema_document(::Type{T}) where {T}
    params = Dict{String,NamedTuple}()
    contexts = Dict{String,Vector{String}}()
    context_ids = Dict{Vector{String},String}()
    routes = NamedTuple[]
    hasmethod(DynamicObjects.meta, Tuple{Type{T}}) || return (; routes, contexts, params)
    cache = _ReflectCache()
    _reflect_walk!(routes, T, ""; cache, enrich=(owner, route, parents) -> begin
        method = String(route.verb)
        entry = _reflect_param_entry(cache, owner, method, parents)
        # `_reflect_route` appends the owner's `@param`s after the call params.
        own = route.params[1:end - length(entry.params)]
        context_keys = String[]
        for (param, declarer) in zip(entry.params, entry.declared_by)
            param.inherited || (push!(own, param); continue)
            key = declarer === nothing ? string(param.name) :
                  string(declarer, ".", param.name)
            get!(params, key) do
                (name=param.name, declared_by=declarer, type=param.type,
                 required=param.required, default=param.default, doc=param.doc)
            end
            push!(context_keys, key)
        end
        context = isempty(context_keys) ? nothing :
                  get!(() -> "c$(length(context_ids) + 1)", context_ids, context_keys)
        context === nothing || (contexts[context] = context_keys)
        (verb=route.verb, path=route.path, name=route.name, doc=route.doc,
         params=own, context=context,
         context_source=context === nothing ? nothing : _reflect_kw_source(method))
    end)
    (; routes, contexts, params)
end

_schema_payload(root, mode::SchemaInherited.Mode) = _schema_payload(root, Val(mode))
_schema_payload(root, ::Val{SchemaInherited.shared}) = _schema_document(root)
_schema_payload(root, ::Val{SchemaInherited.inline}) = reflect(root)

"""
    StructureRoutes(; root::Type)

JSON schema endpoint for the route tree of an `@htmx` app. Mount opt-in via
`@include` on any `@htmx struct`:

```julia
@include schema = SchemaRoutes(; root=MyApp)   # → GET /schema
```

The single `GET /schema` route (the `@get index()`) returns one JSON object:

- `routes` — one object per route with `verb`, `path`, `name`, `doc`, and
  `params` (see [`reflect`](@ref) for the field contract), where `params`
  holds the route's own inputs: its path and keyword params and its struct's
  own `@param`s. `context` names the route's inherited `@param`s (or is
  `null`), and `context_source` says where the route reads them
  (`"query"` or `"body"`).
- `contexts` — each distinct set of inherited `@param`s once, as an id
  mapped to a list of `params` keys.
- `params` — each inherited `@param` once, keyed `"<DeclaringType>.<name>"`,
  with `name`, `declared_by`, `type`, `required`, `default`, and `doc`.

`GET /schema?inherited=inline` returns `reflect(root)` as a flat array
instead: the same route objects with every inherited `@param` repeated on
every route that accepts it (`"inherited": true`). Any other `inherited`
value is a 400. Designed for MCP tool-autogen, documentation generators,
and other tooling that needs a machine-readable route index.

`StructureRoutes` is a back-compat alias; prefer [`SchemaRoutes`](@ref).
"""
@htmx struct StructureRoutes
    root::Type = Any

    @get index(; inherited::SchemaInherited.Mode=SchemaInherited.shared) =
        MIMEResponse("application/json",
                     _schema_json_encode(_schema_payload(root, inherited)))
end

"""
    SchemaRoutes(; root::Type)

Canonical name for [`StructureRoutes`](@ref) — the opt-in JSON schema
endpoint. Mount via:

```julia
@include schema = SchemaRoutes(; root=MyApp)   # → GET /schema
```
"""
const SchemaRoutes = StructureRoutes
