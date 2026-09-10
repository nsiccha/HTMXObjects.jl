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

# Verbs with an OpenAPI operation. `:WEBSOCKET` is deliberately absent —
# OpenAPI has no WebSocket operation, so `@ws` routes are skipped (see
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
function _openapi_summary(doc::AbstractString)
    for line in split(doc, '\n')
        stripped = strip(line)
        isempty(stripped) || return String(stripped)
    end
    nothing
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

# One OpenAPI operation from a `reflect` route descriptor. `operation_id` is
# assigned by the caller, which sees the whole path group.
function _openapi_operation(route, method::AbstractString, operation_id::AbstractString)
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
    merge(operation, (responses=Dict("200" => (description="OK",)),))
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
- `operationId` is the route name, suffixed with `_<method>` only when one
  path serves several same-named routes (e.g. `@get status()` +
  `@post status()`).
- Julia types map to JSON-schema types (`Integer` → `integer`,
  `AbstractFloat` → `number`, `Bool` → `boolean`, strings/`Symbol`/`Char`/
  enums → `string`, arrays → `array`, dates → `string` + `format`);
  unresolvable types degrade to `string`.
- `@ws` routes are skipped: OpenAPI has no WebSocket operation.
- Each `servers` entry is a URL string or an `(url=…, description=…)` record;
  the key is omitted when no servers are given.
"""
function openapi(T::Type; title::AbstractString="",
        version::AbstractString="1.0.0", description=nothing, servers=[])
    grouped = Dict{String,Vector{Any}}()
    order = String[]
    for route in reflect(T)
        method = get(_OPENAPI_METHODS, route.verb, nothing)
        method === nothing && continue
        group = get!(Vector{Any}, grouped, route.path)
        isempty(group) && push!(order, route.path)
        push!(group, (route=route, method=method))
    end
    paths = Dict{String,Any}()
    for path in order
        group = grouped[path]
        counts = Dict{Symbol,Int}()
        for entry in group
            counts[entry.route.name] = get(counts, entry.route.name, 0) + 1
        end
        operations = Dict{String,Any}()
        for entry in group
            operation_id = string(entry.route.name)
            counts[entry.route.name] > 1 &&
                (operation_id = operation_id * "_" * entry.method)
            operations[entry.method] =
                _openapi_operation(entry.route, entry.method, operation_id)
        end
        paths[path] = operations
    end
    info = (title=(isempty(title) ? string(T) : String(title)),
            version=String(version))
    description !== nothing && (info = merge(info, (description=String(description),)))
    document = (openapi="3.1.0", info=info, paths=paths)
    server_records = [s isa AbstractString ? (url=String(s),) : s for s in servers]
    isempty(server_records) || (document = merge(document, (servers=server_records,)))
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
docstrings and `# Arguments` sections, and form `requestBody`s for
POST/PUT/PATCH params. Designed for agent tool-autogen, documentation
generators, and anything else that speaks OpenAPI.
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
# OpenAPI document. Mounted at `/docs` it answers the standard address —
# which requires `serve(docs=false)` (see `_warn_docs_prefix`): with
# Oxygen's built-in docs enabled, its `DocsMiddleware` intercepts every
# `/docs*` request before the main router and serves Oxygen's own
# (for `@htmx` apps, empty) Swagger instead.

# Pinned Swagger UI release. 5.x reads OpenAPI 3.1; the pin keeps the
# rendered viewer reproducible. Bumped deliberately, never floating.
const _SWAGGER_UI_VERSION = "5.7.2"

# Standalone viewer page. Assets load from a pinned CDN release
# (`cdn_base` re-points air-gapped deployments at a local mirror without a
# code change); the spec URL is emitted as a JSON string literal so
# quoting/escaping cannot break the initializer.
function _swagger_html(; title::AbstractString, spec_url::AbstractString,
        swagger_version::AbstractString, cdn_base::AbstractString)
    base = rstrip(String(cdn_base), '/') * "/swagger-ui@" * String(swagger_version)
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
lives. `cdn_base` re-points air-gapped deployments at a local mirror of the
pinned release.

Mounting at `/docs` requires `serve(docs=false)`: with Oxygen's built-in
docs enabled, its middleware serves its own Swagger for every `/docs*`
request and the mounted route never fires.
"""
@htmx struct SwaggerRoutes
    title::String = "API docs"
    spec_url::String = "/openapi"
    swagger_version::String = _SWAGGER_UI_VERSION
    cdn_base::String = "https://cdn.jsdelivr.net/npm"

    @get index() = MIMEResponse("text/html",
        _swagger_html(; title, spec_url, swagger_version, cdn_base))
end
