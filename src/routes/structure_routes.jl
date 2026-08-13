# --- Schema endpoint -------------------------------------------------------
#
# StructureRoutes (canonical alias: SchemaRoutes) — a single `@get index()`
# that returns `reflect(root)` serialized as JSON. Mount opt-in via @include:
#
#   @include schema = SchemaRoutes(; root=MyApp)   # → /schema
#
# The JSON shape mirrors the reflect() descriptor contract exactly; see
# `reflect` in HTMXObjects.jl for field docs.

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
    StructureRoutes(; root::Type)

JSON schema endpoint for the route tree of an `@htmx` app. Mount opt-in via
`@include` on any `@htmx struct`:

```julia
@include schema = SchemaRoutes(; root=MyApp)   # → GET /schema
```

The single `GET /schema` route (the `@get index()`) returns
`reflect(root)` serialized as JSON — one object per route, each with
`verb`, `path`, `name`, `doc`, and `params` (see [`reflect`](@ref) for
the full field contract). Designed for MCP tool-autogen, documentation
generators, and other tooling that needs a machine-readable route index.

`StructureRoutes` is a back-compat alias; prefer [`SchemaRoutes`](@ref).
"""
@htmx struct StructureRoutes
    root::Type = Any

    @get index() = MIMEResponse("application/json", _schema_json_encode(reflect(root)))
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
