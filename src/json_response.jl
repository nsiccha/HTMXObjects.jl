# --- JSONResponse: a route's JSON answer, encoded through its declared type ---
#
# A route declared `@get f(…)::JSONResponse{T} = value` returns its plain value.
# `_run_operation` wraps it (`_as_declared`), and `_finalized_response` encodes
# it through `T`, using JSON.jl for serialization. `openapi` describes the same
# `T` as the response schema (`_openapi_response_schema`, openapi_routes.jl), so
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
                  body=JSON.json(_response_value(T, r.value);
                                 allownan=true, nan="null", inf="null", ninf="null"))
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

# --- Project values through the declared response type ---
# JSON.jl owns the wire format. This layer only selects and validates the
# values promised by the OpenAPI schema, including Tables.jl column access.

_json_nonnull(T) = Base.nonmissingtype(Base.nonnothingtype(T))
_json_isnull(x) = x === nothing || x === missing
_json_object_type(T) =
    T isa DataType && isconcretetype(T) && isstructtype(T) && fieldcount(T) > 0 &&
    !(T <: Union{Tuple,Number,AbstractString,AbstractArray,AbstractDict,Dates.TimeType})

_response_value(::Type{Any}, x) = _response_value(x)
_response_value(::Type{Nothing}, ::Nothing) = nothing
_response_value(::Type{Missing}, ::Missing) = nothing
_response_value(::Type{<:Bool}, x::Bool) = x
_response_value(::Type{T}, x::Real) where {T<:Integer} = convert(T, x)
_response_value(::Type{<:Real}, x::Real) = _response_value(x)
_response_value(::Type{<:Union{AbstractString,Symbol,Char}}, x) = string(x)
_response_value(::Type{T}, x::T) where {T<:Union{Enum,Dates.TimeType}} = string(x)
_response_value(::Type{T}, x) where {T<:AbstractVector} = _response_array(eltype(T), x)
_response_value(::Type{T}, x::AbstractDict) where {T<:AbstractDict} =
    _response_pairs(valtype(T), _json_sorted_pairs(x))
_response_value(::Type{T}, x::NamedTuple) where {T<:AbstractDict} =
    _response_pairs(valtype(T), pairs(x))

function _response_value(::Type{T}, x) where {T}
    S = _json_nonnull(T)
    if S !== T && S !== Union{}
        return _json_isnull(x) ? nothing : _response_value(S, x)
    end
    _json_object_type(T) && return _response_object(T, x)
    isconcretetype(T) && !(x isa T) && throw(ArgumentError(
        "JSONResponse: cannot encode a `$(typeof(x))` value as the declared `$T`"))
    _response_value(x)
end

_response_value(::Union{Nothing,Missing}) = nothing
_response_value(x::Union{Bool,Integer}) = x
_response_value(x::Real) = Float64(x)
_response_value(x::Union{AbstractString,Symbol,Char,Enum,Dates.TimeType}) = string(x)
_response_value(x::NamedTuple) = map(_response_value, x)
_response_value(x::AbstractDict) = _response_pairs(Any, _json_sorted_pairs(x))
_response_value(x::Union{AbstractVector,Tuple}) = map(_response_value, x)
function _response_value(x)
    Tables.istable(x) && return _response_table(Any, x)
    _json_object_type(typeof(x)) && return _response_object(typeof(x), x)
    throw(ArgumentError("JSONResponse: no JSON form for a `$(typeof(x))` value"))
end

_response_object(::Type{T}, x) where {T} = NamedTuple{fieldnames(T)}(map(fieldnames(T)) do name
    F = fieldtype(T, name)
    _response_value(F, _response_field(T, F, x, name))
end)

_response_field(::Type{T}, F, x::T, name) where {T} = getfield(x, name)
function _response_field(::Type{T}, F, x, name) where {T}
    hasproperty(x, name) && return getproperty(x, name)
    _json_nonnull(F) === F && throw(ArgumentError(
        "JSONResponse: `$T` field `$name` is missing from the returned `$(typeof(x))`"))
    nothing
end

_json_sorted_pairs(x::AbstractDict) = sort!(collect(pairs(x)); by=pair -> string(first(pair)))
_response_pairs(::Type{V}, kvs) where {V} =
    JSON.Object(string(k) => _response_value(V, v) for (k, v) in kvs)

function _response_array(::Type{E}, x) where {E}
    _json_isnull(x) && throw(ArgumentError(
        "JSONResponse: a `$(typeof(x))` value for the declared `Vector{$E}`"))
    x isa Union{AbstractVector,Tuple} || !Tables.istable(x) || return _response_table(E, x)
    [_response_value(E, element) for element in x]
end

# Resolve each declared column once. Rows contain only declared fields, in
# declaration order; an untyped table keeps every column.
function _response_table(::Type{E}, table) where {E}
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
    [NamedTuple{names}(map(types, cells) do F, cell
        _response_value(F, cell === nothing ? nothing : cell[row])
    end) for row in 1:Tables.rowcount(columns)]
end
