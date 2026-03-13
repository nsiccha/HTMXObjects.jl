module HTMXObjects

export DynamicObjects, @persist, @dynamicstruct, @htmx, @cache_status, @is_cached, @cache_path
export create_app
export HTTP, queryparams, queryparams_all, formdata
export terminate, serve, staticfiles
export auto, htmx, h, Node, @__str, HyperscriptString
export route!, to_response, save_response, static_transform
export is_htmx, hx_target, hx_trigger, hx_current_url, hx_boosted, hx_prompt
export hx_response
export hx_link, queryparam, htmx_or, pathparams

using DynamicObjects, HTTP
import DynamicObjects: @persist
using HTMX
import HTMX: h, auto, Node, @__str, HyperscriptString

import Oxygen
import Oxygen: formdata
using Oxygen.Core: ServerContext, register, Nullable

const CONTEXT :: Ref{ServerContext} = Ref(ServerContext(; mod=@__MODULE__))

"""
    serve(; host="127.0.0.1", port=8080, async=false, revise=nothing, kwargs...)

Start the HTTP server. Passes all keyword arguments through to `Oxygen.Core.serve`.
When `async=false` (the default), blocks until interrupted and calls [`terminate`](@ref) on exit.
"""
function serve(; kwargs...)
    async = Base.get(kwargs, :async, false)
    try
        return Oxygen.Core.serve(CONTEXT[]; kwargs...)
    finally
        if !async
            terminate()
        end
    end
end

"""Stop the HTTP server started by [`serve`](@ref)."""
terminate() = Oxygen.Core.terminate(CONTEXT[])

"""
    staticfiles(folder, mountdir="static"; headers=[], loadfile=nothing)

Serve static files from `folder` at the URL prefix `mountdir`.
"""
staticfiles(
    folder::String,
    mountdir::String="static";
    headers::Vector=[],
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.staticfiles(CONTEXT[], CONTEXT[].service.router, folder, mountdir; headers, loadfile)

# --- Query parameter parsing (multi-value aware) ---

"""
    queryparams(req::HTTP.Request) -> Dict{String, Union{String, Vector{String}}}

Parse query parameters from the request URL. Unlike `HTTP.queryparams` (which
returns `Dict{String,String}` and drops duplicate keys), this preserves all
values: single-value keys map to a `String`, duplicate keys map to a
`Vector{String}`.

    queryparams("http://x/?a=1&b=2&b=3")  #=> Dict("a" => "1", "b" => ["2", "3"])
"""
function queryparams(req::HTTP.Request)
    query = HTTP.URI(req.target).query
    isempty(query) && return Dict{String, Union{String, Vector{String}}}()
    d = Dict{String, Union{String, Vector{String}}}()
    for part in split(query, "&", keepempty=false)
        kv = split(part, "=", limit=2)
        k = String(HTTP.URIs.unescapeuri(kv[1]))
        v = length(kv) >= 2 ? String(HTTP.URIs.unescapeuri(kv[2])) : ""
        if haskey(d, k)
            existing = d[k]
            if existing isa String
                d[k] = [existing, v]
            else
                push!(existing, v)
            end
        else
            d[k] = v
        end
    end
    d
end

"""
    queryparams_all(req::HTTP.Request, name::AbstractString) -> Vector{String}

Return all values for query parameter `name` as a vector.
Returns an empty vector if the parameter is absent.
"""
function queryparams_all(req::HTTP.Request, name::AbstractString)
    qp = queryparams(req)
    val = get(qp, name, nothing)
    isnothing(val) && return String[]
    val isa String ? [val] : val
end

"""
    @htmx struct MyApp ... end

Wraps `@dynamicstruct` and appends a `_reroute!` call so that Revise-triggered
re-evaluation automatically re-registers routes without a server restart.
"""
macro htmx(args...)
    struct_block = DynamicObjects.dynamicstruct(args[end]; (length(args) > 1 ? (docstring=args[1],) : (;))...)
    # Extract the type name from the struct expression
    struct_expr = args[end]
    @assert struct_expr.head == :struct
    type_name = struct_expr.args[2]
    Meta.isexpr(type_name, :(<:)) && (type_name = type_name.args[1])
    Meta.isexpr(type_name, :(curly)) && (type_name = type_name.args[1])
    # struct_block is already esc'd by dynamicstruct, so append to its inner block
    @assert Meta.isexpr(struct_block, :escape)
    push!(struct_block.args[1].args, :($(_reroute!)($type_name)))
    struct_block
end

"""
    htmx(body...; htmx_version="2.0.8", hyperscript_version="0.9.14", pico_version=nothing, extra_head=())

Generate a full HTML page with HTMX and optionally Hyperscript/PicoCSS loaded from CDN.
Pass `nothing` to any version kwarg to skip that library.
"""
function htmx(args...;
    head = h.head,
    body = h.body,
    htmx_version        = "2.0.8",
    hyperscript_version = "0.9.14",
    pico_version        = nothing,
    extra_head          = (),
)
    cdn = []
    isnothing(htmx_version)        || push!(cdn, h.script(src="https://cdn.jsdelivr.net/npm/htmx.org@$(htmx_version)/dist/htmx.min.js"))
    isnothing(hyperscript_version) || push!(cdn, h.script(src="https://unpkg.com/hyperscript.org@$(hyperscript_version)"))
    isnothing(pico_version)        || push!(cdn, h.link(rel="stylesheet", href="https://cdn.jsdelivr.net/npm/@picocss/pico@$(pico_version)/css/pico.min.css"))
    h.html(
        head(
            h.meta(charset="utf-8"),
            h.meta(name="viewport", content="width=device-width, initial-scale=1"),
            h.meta(name="color-scheme", content="light dark"),
            cdn...,
            extra_head...,
        ),
        body(args...),
    )
end

# --- Route registration and recording ---

# Parse path parameters by matching request URL segments against the route template.
# Uses only req.target (public HTTP.Request field) — no Oxygen/HTTP internals.
function pathparams(req::HTTP.Request, template::AbstractString)
    req_parts  = split(split(req.target, "?")[1], "/", keepempty=false)
    tmpl_parts = split(template, "/", keepempty=false)
    Dict(
        tmpl_part[2:end-1] => String(req_part)
        for (req_part, tmpl_part) in zip(req_parts, tmpl_parts)
        if startswith(tmpl_part, "{") && endswith(tmpl_part, "}")
    )
end

const _html_response = s -> HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body=s)

"""
    to_response(val)

Convert any Julia value to an `HTTP.Response`. Handles Nodes, plain strings,
arrays of either, and HTMX OOB-swap Pairs (via `auto`). Values that are
already an `HTTP.Response` pass through unchanged.
"""
to_response(val::HTTP.Response) = val
to_response(val) = auto(val; wrap=_html_response)

"""
    save_response(record_dir, url_path, response)

Save a response body to disk, mirroring the URL path structure
(`/post/42` → `record_dir/post/42.html`). Enables later replay via a static file server.
"""
function save_response(record_dir::String, url_path::String, response::HTTP.Response)
    rel = lstrip(url_path, '/')
    file = isempty(rel) ? "index.html" : rel * ".html"
    dest = joinpath(record_dir, file)
    mkpath(dirname(dest))
    write(dest, response.body)
    dest
end

# Paths that use kwargs (query params) and thus can't vary by query string on static servers.
# Populated by route! when record_dir is set; used by _disable_for_static to strip hx-get to these paths.
const _static_kwargs_paths = Set{String}()

const _STATIC_DISABLED_STYLE = Node("style", "[data-static-disabled]{opacity:.45;pointer-events:none;cursor:not-allowed}")

# Non-GET hx attribute names that are non-functional on a static server.
# Cobweb converts underscores to hyphens in attribute names, so these use hyphens.
const _HX_NONGET_ATTRS = Set([Symbol("hx-post"), Symbol("hx-put"), Symbol("hx-patch"), Symbol("hx-delete")])

import HTMX: Cobweb

"""
    _disable_for_static(val) -> val

Walk a Node tree and disable elements that won't work on a static server:
- Strip `hx-post`, `hx-put`, `hx-patch`, `hx-delete` attributes
- Strip `hx-get` attributes whose URL contains `?` (query-param routes)
- Strip `hx-get` attributes pointing to kwargs routes (from `_static_kwargs_paths`)
- Mark affected elements with `data-static-disabled` and `disabled`

Non-Node values pass through unchanged.
"""
_disable_for_static(val) = val
_disable_for_static(val::AbstractArray) = _disable_for_static.(val)
_disable_for_static(val::Tuple) = _disable_for_static.(val)
_disable_for_static((content, id)::Pair) = _disable_for_static(content) => id

function _disable_for_static(node::Node)
    cn = parent(node)
    attrs = Cobweb.attrs(cn)
    children = Cobweb.children(cn)

    # Check if this element needs disabling
    disabled = false
    new_attrs = copy(attrs)

    # Remove non-GET hx attributes
    for attr in _HX_NONGET_ATTRS
        if haskey(new_attrs, attr)
            delete!(new_attrs, attr)
            disabled = true
        end
    end

    # Remove hx-get with query string or pointing to kwargs route
    hx_get_sym = Symbol("hx-get")
    if haskey(new_attrs, hx_get_sym)
        url = new_attrs[hx_get_sym]
        if occursin('?', url) || url in _static_kwargs_paths
            delete!(new_attrs, hx_get_sym)
            disabled = true
        end
    end

    if disabled
        new_attrs[Symbol("data-static-disabled")] = "true"  # renders as data-static-disabled
        new_attrs[:disabled] = "true"                        # renders as boolean attribute
    end

    # Recurse into children
    new_children = map(children) do child
        child isa Node ? _disable_for_static(child) :
        child isa Cobweb.Node ? parent(_disable_for_static(Node(child))) :
        child
    end

    Node(Cobweb.Node(Cobweb.tag(cn), new_attrs, new_children))
end

"""
    _inject_static_style(val)

If val is a full HTML page (contains a `<head>`), inject the disabled-element style block.
"""
_inject_static_style(val) = val
function _inject_static_style(node::Node)
    cn = parent(node)
    if Cobweb.tag(cn) == :head
        new_children = vcat(Cobweb.children(cn), [parent(_STATIC_DISABLED_STYLE)])
        return Node(Cobweb.Node(:head, copy(Cobweb.attrs(cn)), new_children))
    end
    # Recurse into children looking for <head>
    new_children = map(Cobweb.children(cn)) do child
        child isa Node ? parent(_inject_static_style(child)) :
        child isa Cobweb.Node ? parent(_inject_static_style(Node(child))) :
        child
    end
    Node(Cobweb.Node(Cobweb.tag(cn), copy(Cobweb.attrs(cn)), new_children))
end

"""
    static_transform(val)

Transform a value for static recording: disable non-functional elements and inject
the disabled-element style block.
"""
function static_transform(val)
    result = _disable_for_static(val)
    _inject_static_style(result)
end

# --- Convenience helpers ---

"""
    hx_link(url; kwargs...)

Create an `h.a` with both `href` and `hx-get` set to `url`. Extra kwargs
(`hx_target`, `hx_swap`, `class`, etc.) are forwarded to `h.a`.
"""
hx_link(url; kwargs...) = h.a(; href=url, hx_get=url, kwargs...)

"""
    queryparam(req, name, default="")

Read a single query parameter by name. Always returns a single `String`:
if the parameter appears multiple times, returns the first value.
"""
function queryparam(req::HTTP.Request, name, default="")
    val = get(queryparams(req), name, nothing)
    isnothing(val) && return default
    val isa String ? val : first(val)
end

"""
    htmx_or(full_page_fn, req, fragment)

Return `fragment` directly for HTMX requests; call `full_page_fn()` and wrap
its result for direct browser navigation. Typical usage:

    htmx_or(req, fragment) do
        htmx(h.main(search_input(q), fragment))
    end
"""
function htmx_or(full_page_fn::Function, req::HTTP.Request, fragment)
    to_response(is_htmx(req) ? fragment : full_page_fn())
end

# --- HTMX request header inspection ---
# All return "" / false when the header is absent (i.e. for non-HTMX requests).

"""Return `true` if the request was made by HTMX (has `HX-Request: true` header)."""
is_htmx(req::HTTP.Request)       = HTTP.header(req, "HX-Request",      "") == "true"
"""Return `true` if the request was boosted by HTMX (`HX-Boosted: true` header)."""
hx_boosted(req::HTTP.Request)    = HTTP.header(req, "HX-Boosted",       "") == "true"
"""Return the `HX-Target` header value (the `id` of the target element), or `""`."""
hx_target(req::HTTP.Request)     = HTTP.header(req, "HX-Target",        "")
"""Return the `HX-Trigger` header value (the `id` of the triggering element), or `""`."""
hx_trigger(req::HTTP.Request)    = HTTP.header(req, "HX-Trigger",       "")
"""Return the `HX-Current-URL` header value (the browser URL at the time of the request), or `""`."""
hx_current_url(req::HTTP.Request)= HTTP.header(req, "HX-Current-URL",   "")
"""Return the `HX-Prompt` header value (the user's response to `hx-prompt`), or `""`."""
hx_prompt(req::HTTP.Request)     = HTTP.header(req, "HX-Prompt",        "")

"""
    hx_response(val; trigger, push_url, replace_url, redirect, refresh, retarget, reswap, location)

Wrap any value (via `to_response`) and attach HX-* response headers that
instruct the HTMX client to perform additional actions after swap.
"""
function hx_response(val;
    trigger=nothing, push_url=nothing, replace_url=nothing,
    redirect=nothing, refresh=false,
    retarget=nothing, reswap=nothing, location=nothing,
)
    resp = to_response(val)
    hdrs = copy(resp.headers)
    isnothing(trigger)     || push!(hdrs, "HX-Trigger"     => trigger)
    isnothing(push_url)    || push!(hdrs, "HX-Push-Url"    => push_url)
    isnothing(replace_url) || push!(hdrs, "HX-Replace-Url" => replace_url)
    isnothing(redirect)    || push!(hdrs, "HX-Redirect"    => redirect)
    refresh                && push!(hdrs, "HX-Refresh"     => "true")
    isnothing(retarget)    || push!(hdrs, "HX-Retarget"    => retarget)
    isnothing(reswap)      || push!(hdrs, "HX-Reswap"      => reswap)
    isnothing(location)    || push!(hdrs, "HX-Location"    => location)
    HTTP.Response(resp.status, hdrs; body=resp.body)
end

"""
    route!(obj; prefix="", record_dir=nothing)

Register all `@get`/`@post`/`@put`/`@patch`/`@delete`-marked properties of `obj`
as Oxygen routes. The type is stored in `_registered_types` so that `_reroute!`
(called automatically by the `@htmx` macro) can re-register routes when Revise
updates the struct.

- Non-indexed properties map to `METHOD /name` (e.g. `obj.about` → `GET /about`)
- Indexed properties map to `METHOD /name/{p1}/{p2}/...`
- Type annotations auto-parse URL strings: `@get item[id::Int]` parses `id` to `Int`
- Trailing defaults register shortened routes: `@get filter[a, b=1]` registers
  both `GET /filter/{a}/{b}` and `GET /filter/{a}` (with `b=1` filled in)
- Kwargs (via call syntax) auto-extract from query params or form data:
  `@get search(; q="", page::Int=1)` extracts `q` and `page` from the query string
  (`GET` / `DELETE` → `queryparams`, `POST` / `PUT` / `PATCH` → `formdata`)
- The `:index` property (with empty prefix) maps to `GET /`

If `record_dir` is given, each response is also written to disk under that
directory, mirroring the URL path structure. This enables later replay via any
static HTTP server.

Returns `obj`.
"""

# Oxygen 1.10+ validates that the handler function's argument names match the
# path parameter names in the route string (e.g. {id} → an `id` argument).
# Since those names are only known at runtime we cannot spell them out in a
# do-block literal.  Instead we store the real handler closure here and use
# eval to generate a thin wrapper whose argument list carries the right names.
const _route_handlers = Any[]

const _http_verbs = Dict(
    Symbol("@get") => "GET",
    Symbol("@post") => "POST",
    Symbol("@put") => "PUT",
    Symbol("@patch") => "PATCH",
    Symbol("@delete") => "DELETE",
)

# Store registered types so _reroute! can re-register after Revise updates
const _registered_types = Dict{DataType, NamedTuple{(:prefix, :record_dir), Tuple{String, Any}}}()

# Extract the type annotation from an index expression, or nothing if untyped.
# Handles: id::Int, id::Int=1, id, id=1
function _extract_type(idx)
    expr = Meta.isexpr(idx, :kw) ? idx.args[1] : idx
    Meta.isexpr(expr, :(::)) && length(expr.args) == 2 ? expr.args[2] : nothing
end

# Convert a string value to the target type. Strings pass through as-is.
_convert_param(val, ::Nothing) = val
_convert_param(val::AbstractString, T::Type{<:AbstractString}) = val
_convert_param(val::AbstractString, T::Type) = parse(T, val)
_convert_param(val::AbstractVector, ::Nothing) = val  # multi-value, no type annotation → keep as vector
_convert_param(val::AbstractVector, T::Type{<:AbstractString}) = first(val)  # multi-value → first string
_convert_param(val::AbstractVector, T::Type) = parse(T, first(val))  # multi-value → parse first
_convert_param(val, ::Type) = val  # already converted (e.g. default value)

# Determine whether kwargs come from queryparams (GET/DELETE) or formdata (POST/PUT/PATCH).
const _queryparams_verbs = Set(["GET", "DELETE"])
_kwargs_source(req, method) = method in _queryparams_verbs ? queryparams(req) : formdata(req)

# Extract kwarg info from a :parameters node's args.
# Returns [(name::String, type_or_nothing, default_value), ...]
function _extract_kwargs(params_args)
    result = Tuple{String, Any, Any}[]
    for arg in params_args
        if Meta.isexpr(arg, :kw)
            kwname_expr = arg.args[1]
            default_val = arg.args[2]
            kwtype = _extract_type(arg)
            kwname = string(first(DynamicObjects.extractnames(kwname_expr)))
            push!(result, (kwname, kwtype, default_val))
        else
            # Bare kwarg without default (rare but possible): prop(; q)
            kwtype = _extract_type(arg)
            kwname = string(first(DynamicObjects.extractnames(arg)))
            push!(result, (kwname, kwtype, nothing))
        end
    end
    result
end

function _register_indexed_route(T, method, name, path, param_strs, param_types, suffix_defaults, kwargs_info, record_dir)
    # Store the real handler (captures name/etc. by closure).
    push!(_route_handlers, (idx_vals, kw_pairs, req) -> begin
        prop = getproperty(T(; req), name)
        val = if isempty(kw_pairs)
            prop[idx_vals...]
        else
            # Use function call form — prop[a; kw=v] is vcat in Julia, not getindex
            Base.getindex(prop, idx_vals...; NamedTuple(kw_pairs)...)
        end
        resp = to_response(val)
        if !isnothing(record_dir)
            save_path = "/" * join(vcat(string(name), string.(idx_vals)), "/")
            save_response(record_dir, save_path, to_response(static_transform(val)))
        end
        resp
    end)
    key = length(_route_handlers)
    # Generate a wrapper whose arg names match the route's {params}.
    # URL params arrive as strings — convert typed params before calling the handler.
    param_syms = Symbol.(param_strs)
    defaults = [isnothing(d) ? :nothing : QuoteNode(d) for d in suffix_defaults]
    func_args = [:_req_ ; param_syms]
    # Build conversion expressions: _convert_param(x, Type) for typed, x for untyped
    all_types = param_types  # types for URL params (suffix defaults already have correct types)
    converted = [isnothing(t) ? s : :($_convert_param($s, $t)) for (s, t) in zip(param_syms, all_types)]
    default_converted = [isnothing(d) ? :nothing : QuoteNode(d) for d in suffix_defaults]
    # Build kwargs extraction code
    kwargs_code = if isempty(kwargs_info)
        :(Pair{Symbol,Any}[])
    else
        kw_exprs = map(kwargs_info) do (kwname, kwtype, default_val)
            src_expr = :(_kwargs_source(_req_, $method))
            val_expr = if isnothing(default_val)
                :($(src_expr)[$kwname])
            else
                :(get($(src_expr), $kwname, $(isnothing(default_val) ? :nothing : QuoteNode(default_val))))
            end
            converted_expr = if isnothing(kwtype)
                val_expr
            else
                :($_convert_param($val_expr, $kwtype))
            end
            :($(QuoteNode(Symbol(kwname))) => $converted_expr)
        end
        :(Pair{Symbol,Any}[$(kw_exprs...)])
    end
    register(CONTEXT[], method, path,
        eval(:(($(func_args...),) -> _route_handlers[$key](
            [$(converted...), $(default_converted...)],
            $kwargs_code,
            _req_
        )))
    )
end

function _register_routes(T; prefix="", record_dir=nothing)
    for (name, info) in DynamicObjects.meta(T)
        DynamicObjects.isfixed(info) && continue
        method = nothing
        for (macro_sym, m) in _http_verbs
            macro_sym in info.macros && (method = m; break)
        end
        isnothing(method) && continue

        # Separate positional indices from kwargs (:parameters node)
        positional_indices = Any[]
        kwargs_info = Tuple{String, Any, Any}[]  # [(name, type_or_nothing, default), ...]
        for idx in info.indices
            if Meta.isexpr(idx, :parameters)
                kwargs_info = _extract_kwargs(idx.args)
            else
                push!(positional_indices, idx)
            end
        end

        param_strs = [string(first(DynamicObjects.extractnames(idx))) for idx in positional_indices]
        param_types = [_extract_type(idx) for idx in positional_indices]

        base = "/" * (isempty(prefix) ? "" : prefix * "/") * string(name)
        path = isempty(param_strs) ? base :
            base * "/" * join("{" .* param_strs .* "}", "/")
        name == :index && isempty(prefix) && (path = "/")

        # Detect trailing default values: prop[a, b=1, c=2]
        # Find the first index with a default — all after it must also have defaults
        defaults = Pair{Int, Any}[]  # [(position => default_value), ...]
        for (j, idx) in enumerate(positional_indices)
            if Meta.isexpr(idx, :kw)
                push!(defaults, j => idx.args[2])
            elseif !isempty(defaults)
                # Non-default after default — can only shorten trailing defaults
                empty!(defaults)
                break
            end
        end

        # Capture loop variables to avoid closure-over-mutable-variable issues
        let name=name, param_strs=param_strs, param_types=param_types, path=path, record_dir=record_dir, method=method, defaults=defaults, kwargs_info=kwargs_info
            if isempty(param_strs) && isempty(kwargs_info)
                register(CONTEXT[], method, path, function(req)
                    val = getproperty(T(; req), name)
                    resp = to_response(val)
                    isnothing(record_dir) || save_response(record_dir, path, to_response(static_transform(val)))
                    resp
                end)
            elseif isempty(param_strs) && !isempty(kwargs_info)
                # kwargs-only route (no path params)
                !isnothing(record_dir) && push!(_static_kwargs_paths, path)
                _register_indexed_route(T, method, name, path, String[], Any[], Any[], kwargs_info, record_dir)
            else
                # Register the full route (all params explicit)
                _register_indexed_route(T, method, name, path, param_strs, param_types, [], kwargs_info, record_dir)

                # Register shortened routes for trailing defaults
                # e.g. filter[a, b=1, c=2] → also /filter/{a}/{b} and /filter/{a}
                for k in length(defaults):-1:1
                    cut = first(defaults[k])  # position of first omitted param
                    short_params = param_strs[1:cut-1]
                    short_types = param_types[1:cut-1]
                    suffix_vals = [last(d) for d in defaults[k:end]]
                    short_path = isempty(short_params) ? base :
                        base * "/" * join("{" .* short_params .* "}", "/")
                    name == :index && isempty(prefix) && isempty(short_params) && (short_path = "/")
                    _register_indexed_route(T, method, name, short_path, short_params, short_types, suffix_vals, kwargs_info, record_dir)
                end
            end
        end
    end
end

function route!(obj; prefix="", record_dir=nothing)
    T = typeof(obj)
    _registered_types[T] = (; prefix, record_dir)
    !isnothing(record_dir) && empty!(_static_kwargs_paths)
    _register_routes(T; prefix, record_dir)
    obj
end

# Called by @htmx macro expansion — re-registers routes when Revise updates the struct
function _reroute!(T::DataType)
    haskey(_registered_types, T) || return
    args = _registered_types[T]
    _register_routes(T; args.prefix, args.record_dir)
end

# --- App scaffolding ---

const _HTMXOBJECTS_UUID = "b12ef442-5798-4353-80f3-9562b03a0cb6"
const _REVISE_UUID = "295af30f-e4ad-537b-8983-00126c2a3abe"

"""
    create_app(path; port=8000, module_name=nothing, setup=true)

Generate a new HTMXObjects app at `path` with the standard package + app structure:

    path/
    ├── Project.toml
    ├── src/<ModuleName>.jl
    └── app/
        ├── Project.toml
        └── main.jl

`module_name` defaults to the directory basename (with `.jl` stripped).
If `setup=true` (default), runs `Pkg.develop` and `Pkg.instantiate` to make the
app immediately runnable. Then start with:

    cd path && julia -i --project=app app/main.jl
"""
function create_app(path::AbstractString; port::Int=8000, module_name::Union{Nothing,AbstractString}=nothing, setup::Bool=true)
    path = abspath(path)
    basename_raw = basename(path)
    if isnothing(module_name)
        module_name = replace(basename_raw, r"\.jl$" => "")
    end
    app_uuid = string(Base.UUID(rand(UInt128)))

    isdir(path) && error("Directory already exists: $path")

    # Find HTMXObjects source path for Pkg.develop
    htmxobjects_path = dirname(dirname(pathof(HTMXObjects)))

    # Create directories
    mkpath(joinpath(path, "src"))
    mkpath(joinpath(path, "app"))

    # --- Project.toml ---
    write(joinpath(path, "Project.toml"),
"name = \"$module_name\"
uuid = \"$app_uuid\"
version = \"0.1.0\"

[deps]
HTMXObjects = \"$_HTMXOBJECTS_UUID\"
")

    # --- src/ModuleName.jl ---
    write(joinpath(path, "src", "$module_name.jl"),
"module $module_name

using HTMXObjects

@htmx struct AppContext
    req = nothing

    @get index = htmx(h.main(
        h.h1(\"$module_name\"),
        h.p(\"Edit src/$module_name.jl and Revise will reload automatically.\"),
    ))
end

function __init__()
    route!(AppContext())
end

end # module $module_name
")

    # --- app/Project.toml ---
    write(joinpath(path, "app", "Project.toml"),
"[deps]
HTMXObjects = \"$_HTMXOBJECTS_UUID\"
$module_name = \"$app_uuid\"
Revise = \"$_REVISE_UUID\"
")

    # --- app/main.jl ---
    write(joinpath(path, "app", "main.jl"),
"using Revise
using $module_name

begin
    $module_name.terminate()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : $port
    $module_name.serve(; host=\"0.0.0.0\", revise=:lazy, port, async=true)
end
")

    @info "Created app at $path" module_name app_uuid

    if setup
        @info "Setting up dependencies..."
        app_dir = joinpath(path, "app")
        setup_code = """
        using Pkg
        Pkg.develop([
            Pkg.PackageSpec(path=$(repr(htmxobjects_path))),
            Pkg.PackageSpec(path=$(repr(path))),
        ])
        Pkg.instantiate()
        """
        run(`$(Base.julia_cmd()) --project=$app_dir -e $setup_code`)
        @info "Ready! Run with:" cmd="cd $path && julia -i --project=app app/main.jl $port"
    else
        @info "Next steps:" setup="cd $(joinpath(path, "app")) && julia --project=. -e 'using Pkg; Pkg.develop([Pkg.PackageSpec(path=\"$htmxobjects_path\"), Pkg.PackageSpec(path=\"..\")]); Pkg.instantiate()'" run="cd $path && julia -i --project=app app/main.jl $port"
    end
    path
end

end # module HTMXObjects
