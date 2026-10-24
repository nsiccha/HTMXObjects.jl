# --- JSONResponse: a route's JSON answer, encoded through its declared type ---
#
# A route declared `@get f(…)::JSONResponse{T} = value` returns its plain value.
# `_run_operation` wraps it (`_as_declared`), and `_finalized_response` encodes
# it through `T` (`_json_write`). `openapi` describes the same `T` as the route's
# response schema (`_openapi_response_schema`, src/routes/openapi_routes.jl), so
# the payload and its document read one declaration.

"""
    JSONResponse{T}(value)
    JSONResponse(value)

A finished `application/json` answer: `value` encoded through the declared type
`T`. Declare it as a route's return type and return the plain value; the route
answers with the encoded JSON, and [`openapi`](@ref) describes `T` as the
route's response schema:

```julia
"One pre-alarm of the threshold rule."
struct Alarm
    "Start hour (UTC)."
    start::DateTime
    probes::Vector{String}
    rain_share::Union{Float64,Nothing}
end

@get alarms(; k::Float64 = 3.0)::JSONResponse{Vector{Alarm}} = alarm_table(k)
```

The encoding follows `T`, not the value's own type:

- A struct or `NamedTuple` type is an object of exactly its fields, each read
  from the value by name, so a `NamedTuple`, another struct or a table row can
  stand for it. Every declared field is sent. A field the value lacks is `null`
  when its type admits `nothing`, and an error otherwise.
- `AbstractVector{E}` is an array of `E`. Any Tables.jl table (a `DataFrame`)
  is accepted for it, one object per row, each field of `E` read as a column.
- `AbstractDict{K,V}` is an object of `V` values keyed by `string(key)`.
- A type admitting `nothing` or `missing` sends either as `null`. A float that
  is not finite (`NaN`, `±Inf`) is `null`.
- `Date` and `DateTime` are ISO 8601 strings without an offset
  (`2026-10-24T02:00:00`); `Symbol`, `Char` and enums are strings.
- `Any` (and `JSONResponse(value)`, which is `JSONResponse{Any}`) encodes the
  value by its own shape.

A value that does not fit its declaration fails the request with an error
naming the type and field. Like [`MIMEResponse`](@ref), the answer is final: no
page shell, no Markdown projection, no `:auto` poller; an `__error__` hook may
return one to answer errors as JSON.

A body that returns a finished answer of its own on some branch (an
`HTTP.Response`, a `MIMEResponse` or another `JSONResponse`, such as an untyped
`JSONResponse((; error = "NotInSnapshot"))`) is answered as it is, with its own
status and content type; it is not encoded through `T` and is not an error.
`openapi` still describes only `T` as the route's `200` response, so name such
an answer in the route's docstring:

```julia
@get alarms(; k::Float64 = 3.0)::JSONResponse{Vector{Alarm}} =
    fitted() ? alarm_table(k) : JSONResponse((; error = "NotInSnapshot"))
```
"""
struct JSONResponse{T}
    value::Any
end
JSONResponse(value) = JSONResponse{Any}(value)

to_response(r::JSONResponse{T}) where {T} =
    HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8"];
                  body=sprint(_json_write, T, r.value))
_finalized_response(r::JSONResponse) = to_response(r)

# The payload type a `JSONResponse` declaration names.
_json_payload_type(::Type{JSONResponse{T}}) where {T} = T
_json_payload_type(::Type{JSONResponse}) = Any

# A route declared `::JSONResponse{T}` returns its plain value; the declaration
# makes that value the JSON answer. A finished answer the route chose itself
# and the operation sentinels pass unchanged.
_as_declared(_declared, value) = value
_as_declared(::Type{J}, value) where {J<:JSONResponse} = J(value)
_as_declared(::Type{<:JSONResponse},
             value::Union{HTTP.Response,MIMEResponse,JSONResponse,_PreloadSkipped,_Prestarted}) =
    value

# --- Encoding through the declared type ---

# The declared type without `Nothing`/`Missing`, and whether a value is either.
_json_nonnull(T) = Base.nonmissingtype(Base.nonnothingtype(T))
_json_isnull(x) = x === nothing || x === missing

# A concrete struct the encoder writes as an object of its fields. Numbers,
# strings, dates, tuples and collections have JSON forms of their own.
_json_object_type(T) =
    T isa DataType && isconcretetype(T) && isstructtype(T) && fieldcount(T) > 0 &&
    !(T <: Union{Tuple,Number,AbstractString,AbstractArray,AbstractDict,Dates.TimeType})

_json_string(io::IO, x) = _schema_json_encode(io, string(x))
_json_number(io::IO, x::Integer) = print(io, x)
_json_number(io::IO, x::Real) = (f = Float64(x); isfinite(f) ? print(io, f) : write(io, "null"))

_json_write(io::IO, ::Type{Any}, x) = _json_by_value(io, x)
_json_write(io::IO, ::Type{Nothing}, ::Nothing) = write(io, "null")
_json_write(io::IO, ::Type{Missing}, ::Missing) = write(io, "null")
_json_write(io::IO, ::Type{<:Bool}, x::Bool) = _json_by_value(io, x)
_json_write(io::IO, ::Type{T}, x::Real) where {T<:Integer} = _json_number(io, convert(T, x))
_json_write(io::IO, ::Type{<:Real}, x::Real) = _json_number(io, x)
_json_write(io::IO, ::Type{<:Union{AbstractString,Symbol,Char}}, x) = _json_string(io, x)
_json_write(io::IO, ::Type{T}, x::T) where {T<:Union{Enum,Dates.TimeType}} = _json_string(io, x)
_json_write(io::IO, ::Type{T}, x) where {T<:AbstractVector} = _json_array(io, eltype(T), x)
_json_write(io::IO, ::Type{T}, x::AbstractDict) where {T<:AbstractDict} =
    _json_pairs(io, valtype(T), _json_sorted_pairs(x))
_json_write(io::IO, ::Type{T}, x::NamedTuple) where {T<:AbstractDict} =
    _json_pairs(io, valtype(T), pairs(x))

function _json_write(io::IO, ::Type{T}, x) where {T}
    S = _json_nonnull(T)
    if S !== T && S !== Union{}
        return _json_isnull(x) ? write(io, "null") : _json_write(io, S, x)
    end
    _json_object_type(T) && return _json_object(io, T, x)
    # An abstract or union declaration (`Number`, `Union{Int,String}`) says
    # less than the value does; a concrete one the value does not fit is an error.
    isconcretetype(T) && !(x isa T) && throw(ArgumentError(
        "JSONResponse: cannot encode a `$(typeof(x))` value as the declared `$T`"))
    _json_by_value(io, x)
end

# Declared `Any`: the value's own shape. A struct value is written through its
# own type's fields.
_json_by_value(io::IO, ::Union{Nothing,Missing}) = write(io, "null")
_json_by_value(io::IO, x::Bool) = write(io, x ? "true" : "false")
_json_by_value(io::IO, x::Real) = _json_number(io, x)
_json_by_value(io::IO, x::Union{AbstractString,Symbol,Char,Enum,Dates.TimeType}) = _json_string(io, x)
_json_by_value(io::IO, x::NamedTuple) = _json_pairs(io, Any, pairs(x))
_json_by_value(io::IO, x::AbstractDict) = _json_pairs(io, Any, _json_sorted_pairs(x))
_json_by_value(io::IO, x::Union{AbstractVector,Tuple}) = _json_array(io, Any, x)
function _json_by_value(io::IO, x)
    Tables.istable(x) && return _json_table(io, Any, x)
    _json_object_type(typeof(x)) && return _json_object(io, typeof(x), x)
    throw(ArgumentError("JSONResponse: no JSON form for a `$(typeof(x))` value"))
end

function _json_object(io::IO, ::Type{T}, x) where {T}
    write(io, '{')
    for (i, name) in enumerate(fieldnames(T))
        i == 1 || write(io, ',')
        _json_string(io, name)
        write(io, ':')
        F = fieldtype(T, name)
        _json_write(io, F, _json_field(T, F, x, name))
    end
    write(io, '}')
end

# A declared field, read from the value by name.
_json_field(::Type{T}, F, x::T, name) where {T} = getfield(x, name)
function _json_field(::Type{T}, F, x, name) where {T}
    hasproperty(x, name) && return getproperty(x, name)
    _json_nonnull(F) === F && throw(ArgumentError(
        "JSONResponse: `$T` field `$name` is missing from the returned `$(typeof(x))`"))
    nothing
end

_json_sorted_pairs(x::AbstractDict) = sort!(collect(pairs(x)); by=pair -> string(first(pair)))

function _json_pairs(io::IO, ::Type{V}, kvs) where {V}
    write(io, '{')
    for (i, (k, v)) in enumerate(kvs)
        i == 1 || write(io, ',')
        _json_string(io, k)
        write(io, ':')
        _json_write(io, V, v)
    end
    write(io, '}')
end

function _json_array(io::IO, ::Type{E}, x) where {E}
    _json_isnull(x) && throw(ArgumentError(
        "JSONResponse: a `$(typeof(x))` value for the declared `Vector{$E}`"))
    x isa Union{AbstractVector,Tuple} || !Tables.istable(x) || return _json_table(io, E, x)
    write(io, '[')
    for (i, element) in enumerate(x)
        i == 1 || write(io, ',')
        _json_write(io, E, element)
    end
    write(io, ']')
end

# A Tables.jl table (a `DataFrame`) for a declared `AbstractVector{E}`: one
# object per row. Each declared field of `E` is found as a column once, not per
# row; a declared `Any` row keeps every column.
function _json_table(io::IO, ::Type{E}, table) where {E}
    columns = Tables.columns(table)
    typed = _json_object_type(E)
    typed || E === Any || throw(ArgumentError(
        "JSONResponse: a table cannot encode as `Vector{$E}`; declare a row type"))
    names = typed ? fieldnames(E) : Tuple(Tables.columnnames(columns))
    types = typed ? fieldtypes(E) : map(_ -> Any, names)
    available = Set(Tables.columnnames(columns))
    cells = map(names, types) do name, F
        name in available && return Tables.getcolumn(columns, name)
        _json_nonnull(F) === F && throw(ArgumentError(
            "JSONResponse: `$E` field `$name` is not a column of the returned table"))
        nothing
    end
    write(io, '[')
    for row in 1:Tables.rowcount(columns)
        row == 1 || write(io, ',')
        write(io, '{')
        for (i, (name, F, cell)) in enumerate(zip(names, types, cells))
            i == 1 || write(io, ',')
            _json_string(io, name)
            write(io, ':')
            _json_write(io, F, cell === nothing ? nothing : cell[row])
        end
        write(io, '}')
    end
    write(io, ']')
end
