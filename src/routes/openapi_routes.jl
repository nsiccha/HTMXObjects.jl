# --- OpenAPI endpoint -------------------------------------------------------
#
# `openapi(T)` renders `reflect(T)` as an OpenAPI 3.1 document (plain
# NamedTuples/Dicts/Vectors, JSON-serializable via `_schema_json_encode`),
# and `OpenAPIRoutes` serves it opt-in via @include:
#
#   @include openapi = OpenAPIRoutes(; root=MyApp)   # → GET /openapi
#
# `reflect` stays the stable seam — this file only READS its descriptors,
# so the `reflect(T)` output contract is unchanged.

# Verbs with an OpenAPI operation. `:WEBSOCKET` and `:SSE` are deliberately
# absent — OpenAPI has no WebSocket operation and cannot describe an open-ended
# event stream as one response, so `@ws`/`@sse` routes are skipped (see
# `openapi`). Everything else mirrors `_reflect_kw_source`'s transport view.
const _OPENAPI_METHODS = Dict(
    :GET => "get",
    :POST => "post",
    :PUT => "put",
    :PATCH => "patch",
    :DELETE => "delete",
)

# Map a `reflect` param `type` (a resolved Julia `Type`, or `nothing`) to an
# OpenAPI schema object. Unresolvable/unknown types degrade to `string` —
# the same fallback `reflect` documents for its own consumers.
function _openapi_type_schema(t)
    t isa Type || return (type="string",)
    t <: Bool && return (type="boolean",)
    t <: AbstractString && return (type="string",)
    t <: Symbol && return (type="string",)
    t === Char && return (type="string",)
    t <: Enum && return (type="string",)
    t <: Integer && return (type="integer",)
    t <: AbstractFloat && return (type="number",)
    t <: Dates.Date && return (type="string", format="date")
    t <: Dates.TimeType && return (type="string", format="date-time")
    if t <: AbstractArray
        E = eltype(t)
        E === Any && return (type="array",)
        return (type="array", items=_openapi_type_schema(E))
    end
    t <: Union{AbstractDict,NamedTuple} && return (type="object",)
    (type="string",)
end

# Normalize a `reflect` param `default` (already `_unquote`d) into a
# `_schema_json_encode`-compatible value. Structured values pass through;
# anything else degrades to its string rendering rather than failing the
# whole document.
_openapi_default(x::AbstractString) = string(x)
_openapi_default(x::Bool) = x
_openapi_default(x::Number) = x
_openapi_default(x::Symbol) = string(x)
_openapi_default(x::Enum) = string(x)
_openapi_default(x::AbstractVector) = map(_openapi_default, x)
_openapi_default(x::AbstractDict) = Dict{String,Any}(string(k) => _openapi_default(v) for (k, v) in x)
_openapi_default(x::NamedTuple) = map(_openapi_default, x)
_openapi_default(x) = string(x)

# Attach a param's doc/default onto a schema object. `default` is only
# meaningful when the param is optional, and a `nothing` default carries no
# information (it may mean "no default" — see `reflect`), so it is omitted.
function _openapi_annotate(schema, param)
    param.doc !== nothing && (schema = merge(schema, (description=param.doc,)))
    if !param.required && param.default !== nothing
        schema = merge(schema, (default=_openapi_default(param.default),))
    end
    schema
end

# One `parameters` entry. Built with the `NamedTuple{names}(values)` form
# because `in` is a reserved word and `(in=…,)` does not parse.
function _openapi_parameter(param, location::AbstractString)
    names = (:name, :in, :required, :schema)
    values = (string(param.name), location, param.required,
              _openapi_annotate(_openapi_type_schema(param.type), param))
    NamedTuple{names}(values)
end

# First non-empty line of a route docstring — the OpenAPI `summary`.
# Thin wrapper over the shared `_docstring_first_line` core: OpenAPI keeps
# the line verbatim (no heading shed), exactly as before.
function _openapi_summary(doc::AbstractString)
    line = _docstring_first_line(doc)
    line === nothing ? nothing : String(line)
end

# A route docstring minus its `# Arguments` section (those lines already
# became per-parameter `description`s). Mirrors `_parse_arguments_section`'s
# section bounds so the two never disagree about where the section ends.
function _openapi_description_body(doc::AbstractString)
    kept = String[]
    in_args = false
    for line in split(doc, '\n')
        stripped = strip(line)
        if stripped == "# Arguments"
            in_args = true
            continue
        end
        if in_args
            if !isempty(stripped) && startswith(stripped, "#")
                in_args = false
            else
                continue
            end
        end
        push!(kept, line)
    end
    body = strip(join(kept, '\n'))
    isempty(body) ? nothing : String(body)
end

# `requestBody` for one route's body-source params (POST/PUT/PATCH kwargs
# and `@param`s). HTMXObjects reads these from the form body, so the content
# is `application/x-www-form-urlencoded`.
function _openapi_request_body(body_params)
    properties = Dict{String,Any}()
    required = String[]
    for param in body_params
        properties[string(param.name)] =
            _openapi_annotate(_openapi_type_schema(param.type), param)
        param.required && push!(required, string(param.name))
    end
    schema = isempty(required) ?
        (type="object", properties=properties) :
        (type="object", properties=properties, required=required)
    (required=!isempty(required),
     content=Dict("application/x-www-form-urlencoded" => (schema=schema,)))
end

# --- Response schemas -----------------------------------------------------------
#
# A route declared `::JSONResponse{T}` (src/json_response.jl) answers `T` as
# `_json_write` encodes it; `_openapi_response_schema` describes `T` by the same
# rules, so the document and the payload read one declaration. Each struct type
# is described once under `components.schemas` and referenced by `$ref`:
# `schemas` holds the descriptions, `names` each type's component name (set
# before its description is built, so a recursive type refers to itself).
struct _OpenAPIComponents
    schemas::Dict{String,Any}
    names::Dict{Any,String}
end
_OpenAPIComponents() = _OpenAPIComponents(Dict{String,Any}(), Dict{Any,String}())

const _OPENAPI_REF = Symbol("\$ref")

# Leaves are described as parameters are (`_openapi_type_schema`). A float may
# be `null`: JSON has no `NaN` or `±Inf`, so `_json_write` sends those as `null`.
_openapi_response_schema(c, ::Type{Any}) = (;)
_openapi_response_schema(c, ::Type{Nothing}) = (type="null",)
_openapi_response_schema(c,
        ::Type{T}) where {T<:Union{Bool,Integer,AbstractString,Symbol,Char,Dates.TimeType}} =
    _openapi_type_schema(T)
_openapi_response_schema(c, ::Type{T}) where {T<:Enum} = isconcretetype(T) ?
    (type="string", enum=[string(x) for x in instances(T)]) : (type="string",)
_openapi_response_schema(c, ::Type{T}) where {T<:AbstractFloat} = (type=["number", "null"],)
_openapi_response_schema(c, ::Type{T}) where {T<:AbstractVector} =
    _openapi_array_schema(_openapi_response_schema(c, eltype(T)))
_openapi_response_schema(c, ::Type{T}) where {T<:AbstractDict} =
    _openapi_map_schema(_openapi_response_schema(c, valtype(T)))

function _openapi_response_schema(c, ::Type{T}) where {T}
    S = _json_nonnull(T)
    S !== T && S !== Union{} && return _openapi_nullable(_openapi_response_schema(c, S))
    T <: Real && return (type=["number", "null"],)
    _json_object_type(T) || return (;)   # abstract or unknown: any JSON value
    T <: NamedTuple ? _openapi_object_schema(c, T) : _openapi_component_ref(c, T)
end

_openapi_array_schema(items) = isempty(items) ? (type="array",) : (type="array", items=items)
_openapi_map_schema(values) = isempty(values) ? (type="object",) :
    (type="object", additionalProperties=values)

# `T`'s schema, admitting `null` as well. An empty schema admits it already.
function _openapi_nullable(schema)
    isempty(schema) && return schema
    t = get(schema, :type, nothing)
    t isa AbstractString && return merge(schema, (type=[t, "null"],))
    t isa AbstractVector && return "null" in t ? schema : merge(schema, (type=[t..., "null"],))
    (anyOf=[schema, (type="null",)],)
end

# An object of exactly `T`'s fields, listed in their declared order (a
# NamedTuple keeps it; the encoder sorts a Dict's keys). `_json_write` sends
# every declared field (`null` when it holds nothing), so every one is
# required; a field's type says whether it may be `null`.
function _openapi_object_schema(c, ::Type{T}) where {T}
    field_docs = _type_field_docs(T)
    properties = NamedTuple{fieldnames(T)}(map(fieldnames(T), fieldtypes(T)) do name, F
        schema = _openapi_response_schema(c, F)
        doc = get(field_docs, name, nothing)
        doc === nothing ? schema : merge(schema, (description=string(doc),))
    end)
    object = (type="object", properties=properties,
              required=[String(name) for name in fieldnames(T)])
    doc = _type_doc(T)
    doc === nothing ? object : merge((description=doc,), object)
end

function _openapi_component_ref(c, ::Type{T}) where {T}
    name = get(c.names, T, nothing)
    if name === nothing
        name = _openapi_component_name(c, T)
        c.names[T] = name
        c.schemas[name] = _openapi_object_schema(c, T)
    end
    NamedTuple{(_OPENAPI_REF,)}(("#/components/schemas/" * name,))
end

# A component is named after its type; a parametric type adds its parameters,
# and a name another type already holds is qualified by the module.
function _openapi_component_name(c, ::Type{T}) where {T}
    key(s) = replace(s, r"[^A-Za-z0-9._-]+" => "_")
    base = key(join([string(nameof(T)); [string(p) for p in T.parameters]], "_"))
    taken(name) = name in values(c.names)
    taken(base) || return base
    qualified = key(string(parentmodule(T))) * "." * base
    name, n = qualified, 1
    while taken(name)
        n += 1
        name = qualified * "_" * string(n)
    end
    name
end

# A struct's docstring and its field docstrings (`"…" field::T` lines), as
# the docs system holds them. A NamedTuple type carries none of its own.
function _type_docstr(::Type{T}) where {T}
    mod = parentmodule(T)
    multidoc = get(Base.Docs.meta(mod), Base.Docs.Binding(mod, nameof(T)), nothing)
    multidoc === nothing ? nothing : get(multidoc.docs, Union{}, nothing)
end
_type_docstr(::Type{<:NamedTuple}) = nothing

function _type_doc(T)
    docstr = _type_docstr(T)
    docstr === nothing && return nothing
    text = strip(join(docstr.text))
    isempty(text) ? nothing : String(text)
end

function _type_field_docs(T)
    docstr = _type_docstr(T)
    docstr === nothing ? Dict{Symbol,Any}() : get(docstr.data, :fields, Dict{Symbol,Any}())
end

# The `200` response of a route with declared output `returns`. Only a
# `JSONResponse` declaration says what the body holds; its description is the
# first line of the payload struct's docstring.
_openapi_ok(c, _returns) = (description="OK",)
function _openapi_ok(c, ::Type{J}) where {J<:JSONResponse}
    T = _json_payload_type(J)
    doc = _json_object_type(T) ? _type_doc(T) : nothing
    summary = doc === nothing ? nothing : _openapi_summary(doc)
    (description=something(summary, "OK"),
     content=Dict("application/json" => (schema=_openapi_response_schema(c, T),)))
end

# `reflect`'s routes, each with the output its declaration names, read from the
# descriptor the operation policy reads (`_declared_output_type`). `reflect`'s
# own route shape is unchanged.
function _openapi_routes(::Type{T}) where {T}
    acc = Any[]
    hasmethod(DynamicObjects.meta, Tuple{Type{T}}) || return acc
    _reflect_walk!(acc, T, ""; enrich=(owner, route, _parents) -> (; route,
        returns=_declared_output_type(_property_descriptor(owner, route.name, route.verb))))
    acc
end

# One OpenAPI operation from a `reflect` route descriptor. `operation_id` is
# assigned by the caller, which sees the whole path group.
function _openapi_operation(route, method::AbstractString, operation_id::AbstractString,
        components::_OpenAPIComponents, returns)
    operation = (operationId=operation_id,)
    if route.doc !== nothing
        summary = _openapi_summary(route.doc)
        summary !== nothing && (operation = merge(operation, (summary=summary,)))
        body = _openapi_description_body(route.doc)
        if body !== nothing && body != summary
            operation = merge(operation, (description=body,))
        end
    end
    parameters = Any[]
    body_params = Any[]
    for param in route.params
        if param.source === :path
            push!(parameters, _openapi_parameter(param, "path"))
        elseif param.source === :query
            push!(parameters, _openapi_parameter(param, "query"))
        else
            push!(body_params, param)
        end
    end
    isempty(parameters) || (operation = merge(operation, (parameters=parameters,)))
    isempty(body_params) ||
        (operation = merge(operation, (requestBody=_openapi_request_body(body_params),)))
    merge(operation, (responses=Dict("200" => _openapi_ok(components, returns)),))
end

# One `operationId` per operation, unique in the document as OpenAPI requires
# (code generators name functions after them). A route name only one operation
# uses is its id. A shared name (`index` on every mount, or `messstellen` at
# `/messstellen` and `/ap3/messstellen`) takes an id built from its path,
# suffixed with `_<method>` when one path serves several same-named routes. An
# id that is still taken gets `_2`, `_3`, … in document order.
function _openapi_operation_ids(grouped, order)
    entries = [(path, entry) for path in order for entry in grouped[path]]
    uses = Dict{Symbol,Int}()
    for (_, entry) in entries
        uses[entry.route.name] = get(uses, entry.route.name, 0) + 1
    end
    wanted = map(entries) do (path, entry)
        name = entry.route.name
        uses[name] == 1 && return string(name)
        id = _openapi_path_id(path)
        count(e -> e.route.name === name, grouped[path]) > 1 ? id * "_" * entry.method : id
    end
    taken = Set(id for (id, (_, entry)) in zip(wanted, entries) if uses[entry.route.name] == 1)
    ids = Dict{Tuple{String,String},String}()
    for (id, (path, entry)) in zip(wanted, entries)
        if uses[entry.route.name] > 1
            base, n = id, 1
            while id in taken
                n += 1
                id = base * "_" * string(n)
            end
            push!(taken, id)
        end
        ids[(path, entry.method)] = id
    end
    ids
end

# `/ap3/stunden/{kenn}` → `ap3_stunden_kenn`; the root path `/` → `index`.
function _openapi_path_id(path::AbstractString)
    segments = [replace(strip(s, ['{', '}']), r"[^A-Za-z0-9_]+" => "_")
                for s in split(path, '/'; keepempty=false)]
    isempty(segments) ? "index" : join(segments, "_")
end

"""
    openapi(T::Type; title="", version="1.0.0", description=nothing, servers=[]) -> NamedTuple

Render the route tree of an `@htmx` app type `T` as an OpenAPI 3.1 document
— plain `NamedTuple`s/`Dict`s/`Vector`s, directly JSON-serializable (see
[`SchemaRoutes`](@ref) for the lower-level `reflect` dump this builds on).

```julia
doc = openapi(MyApp; title="My API", version="2.0.0")
```

- `paths` maps each mount-resolved route path to its HTTP-method operations.
  Path params keep `reflect`'s `{name}` spelling, which is already OpenAPI's.
- A route docstring's first non-empty line becomes the operation `summary`;
  the remainder (minus any `# Arguments` section, which already became
  per-parameter descriptions) becomes `description`.
- `:path` params and GET/DELETE query params become `parameters` entries;
  POST/PUT/PATCH form params become an `application/x-www-form-urlencoded`
  `requestBody` — matching how the framework reads each transport.
- `operationId` is the route name when no other operation shares it. A
  shared name gets an id built from its path instead (`/ap3/messstellen` →
  `ap3_messstellen`, a mount's `index` at `/docs` → `docs`), suffixed with
  `_<method>` when one path serves several same-named routes (e.g.
  `@get status()` + `@post status()` → `status_get`, `status_post`). Ids are
  unique in the document, as OpenAPI requires.
- Julia types map to JSON-schema types (`Integer` → `integer`,
  `AbstractFloat` → `number`, `Bool` → `boolean`, strings/`Symbol`/`Char`/
  enums → `string`, arrays → `array`, dates → `string` + `format`);
  unresolvable types degrade to `string`.
- A route declared `::JSONResponse{T}` (see [`JSONResponse`](@ref)) gets an
  `application/json` `200` response whose schema describes `T` by the rules it
  is encoded with: a struct is an object of all its fields (all `required`; a
  field whose type admits `nothing` may be `null`), described once under
  `components.schemas` and referenced by `\$ref`, with its docstring and
  field docstrings as descriptions and its docstring's first line as the
  response `description`; a `NamedTuple` type is an inline object;
  `Vector{E}` is an array of `E`; floats may be `null` (non-finite values).
  Every other route keeps `{"200": {"description": "OK"}}`.
- `@ws` and `@sse` routes are skipped: OpenAPI has no WebSocket operation or
  event-stream response.
- Each `servers` entry is a URL string or an `(url=…, description=…)` record;
  the key is omitted when no servers are given; `components` likewise appears
  only when a response refers to one.
"""
function openapi(T::Type; title::AbstractString="",
        version::AbstractString="1.0.0", description=nothing, servers=[])
    grouped = Dict{String,Vector{Any}}()
    order = String[]
    for entry in _openapi_routes(T)
        route = entry.route
        method = get(_OPENAPI_METHODS, route.verb, nothing)
        method === nothing && continue
        group = get!(Vector{Any}, grouped, route.path)
        isempty(group) && push!(order, route.path)
        push!(group, (route=route, method=method, returns=entry.returns))
    end
    components = _OpenAPIComponents()
    operation_ids = _openapi_operation_ids(grouped, order)
    paths = Dict{String,Any}()
    for path in order
        operations = Dict{String,Any}()
        for entry in grouped[path]
            operations[entry.method] = _openapi_operation(entry.route, entry.method,
                operation_ids[(path, entry.method)], components, entry.returns)
        end
        paths[path] = operations
    end
    info = (title=(isempty(title) ? string(T) : String(title)),
            version=String(version))
    description !== nothing && (info = merge(info, (description=String(description),)))
    document = (openapi="3.1.0", info=info, paths=paths)
    server_records = [s isa AbstractString ? (url=String(s),) : s for s in servers]
    isempty(server_records) || (document = merge(document, (servers=server_records,)))
    isempty(components.schemas) ||
        (document = merge(document, (components=(schemas=components.schemas,),)))
    document
end

"""
    OpenAPIRoutes(; root::Type, title="", version="1.0.0", description=nothing, servers=[])

Opt-in OpenAPI endpoint for the route tree of an `@htmx` app. Mount via
`@include` on any `@htmx struct`:

```julia
@include openapi = OpenAPIRoutes(; root=MyApp)   # → GET /openapi
```

The single `GET` route (the `@get index()`) returns
[`openapi`](@ref)`(root; …)` serialized as JSON — an OpenAPI 3.1 document
with one operation per route, per-parameter descriptions from route
docstrings and `# Arguments` sections, form `requestBody`s for
POST/PUT/PATCH params, and response schemas for routes declared
`::JSONResponse{T}` (see [`JSONResponse`](@ref)). Designed for agent tool-autogen,
documentation generators, and anything else that speaks OpenAPI.
"""
@htmx struct OpenAPIRoutes
    root::Type = Any
    title::String = ""
    version::String = "1.0.0"
    description::Union{String,Nothing} = nothing
    servers::Vector = []

    @get index() = MIMEResponse("application/json",
        _schema_json_encode(openapi(root; title, version, description, servers)))
end

# --- Swagger UI endpoint ----------------------------------------------------
#
# `SwaggerRoutes` is the human companion to `OpenAPIRoutes`: a mountable
# bundle serving a version-pinned Swagger UI initialized against the app's
# OpenAPI document, typically mounted at the standard `/docs` address.

# Pinned Swagger UI release. 5.x reads OpenAPI 3.1; the pin keeps the
# rendered viewer reproducible. Bumped deliberately, never floating.
const _SWAGGER_UI_VERSION = "5.7.2"

# Standalone viewer page. Assets load from a pinned CDN release of the
# `swagger-ui-dist` npm package — the prebuilt browser bundle; the
# `swagger-ui` module package keeps its build under `dist/` and 404s at the
# package root (`cdn_base` re-points air-gapped deployments at a local
# mirror without a code change); the spec URL is emitted as a JSON string
# literal so quoting/escaping cannot break the initializer.
function _swagger_html(; title::AbstractString, spec_url::AbstractString,
        swagger_version::AbstractString, cdn_base::AbstractString)
    base = rstrip(String(cdn_base), '/') * "/swagger-ui-dist@" * String(swagger_version)
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>$(html_escape(String(title)))</title>
        <link rel="stylesheet" href="$(base)/swagger-ui.css" />
    </head>
    <body>
        <div id="swagger-ui"></div>
        <script src="$(base)/swagger-ui-bundle.js"></script>
        <script>
            window.onload = () => {
                window.ui = SwaggerUIBundle({
                    url: $(_schema_json_encode(String(spec_url))),
                    dom_id: '#swagger-ui',
                });
            };
        </script>
    </body>
    </html>
    """
end

"""
    SwaggerRoutes(; title="API docs", spec_url="/openapi", swagger_version=_SWAGGER_UI_VERSION, cdn_base="https://cdn.jsdelivr.net/npm")

Opt-in Swagger UI viewer for an `@htmx` app's OpenAPI document. Mount via
`@include` on any `@htmx struct`, next to its [`OpenAPIRoutes`](@ref):

```julia
@include openapi = OpenAPIRoutes(; root=MyApp)   # → GET /openapi
@include docs = SwaggerRoutes(; spec_url="/openapi")   # → GET /docs
```

The single `GET` route (the `@get index()`) returns a standalone HTML page
(`text/html` via [`MIMEResponse`](@ref), so no page shell is wrapped around
it) running a version-pinned Swagger UI release initialized against
`spec_url`. `spec_url` is explicit because the document's mount point is the
consumer's choice — point it at wherever the companion `OpenAPIRoutes`
lives. The page loads `<cdn_base>/swagger-ui-dist@<swagger_version>/swagger-ui.css`
and `.../swagger-ui-bundle.js` (the `swagger-ui-dist` npm package), so
`cdn_base` re-points air-gapped deployments at a local mirror laid out the
same way.
"""
@htmx struct SwaggerRoutes
    title::String = "API docs"
    spec_url::String = "/openapi"
    swagger_version::String = _SWAGGER_UI_VERSION
    cdn_base::String = "https://cdn.jsdelivr.net/npm"

    @get index() = MIMEResponse("text/html",
        _swagger_html(; title, spec_url, swagger_version, cdn_base))
end
