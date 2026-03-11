module HTMXObjects

export DynamicObjects, @persist, @dynamicstruct, @htmx, @cache_status, @is_cached, @cache_path
export HTTP, queryparams, formdata
export Oxygen, @oxidize, terminate, serve
export auto, htmx, h, Node, @__str, HyperscriptString
export route!, to_response, save_response
export is_htmx, hx_target, hx_trigger, hx_current_url, hx_boosted, hx_prompt
export hx_response
export hx_link, queryparam, htmx_or

using DynamicObjects, HTTP, Oxygen
import DynamicObjects: @persist
using HTMX
import HTMX: h, auto, Node, @__str, HyperscriptString

macro htmx(args...)
    DynamicObjects.dynamicstruct(args[end]; (length(args) > 1 ? (docstring=args[1],) : (;))...)
end

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

# Convert any Julia value to an HTTP.Response via auto.
# Handles Nodes, plain strings, arrays of either, and HTMX OOB-swap Pairs.
to_response(val::HTTP.Response) = val
to_response(val) = auto(val; wrap=_html_response)

# Save a response body to disk, mirroring the URL path structure.
# Enables static file server replay: /post/42 → record_dir/post/42.html
function save_response(record_dir::String, url_path::String, response::HTTP.Response)
    rel = lstrip(url_path, '/')
    file = isempty(rel) ? "index.html" : rel * ".html"
    dest = joinpath(record_dir, file)
    mkpath(dirname(dest))
    write(dest, response.body)
    dest
end

# --- Convenience helpers ---

# `h.a` with `href` and `hx-get` both set to `url`.
# Avoids the common duplication of href="/foo" hx_get="/foo".
# Extra kwargs (hx_target, hx_swap, class, …) are forwarded to h.a.
hx_link(url; kwargs...) = h.a(; href=url, hx_get=url, kwargs...)

# Read a single query parameter by name, with an optional default.
# Shorthand for: get(queryparams(req), name, default)
queryparam(req::HTTP.Request, name, default="") = get(queryparams(req), name, default)

# Return `fragment` directly for HTMX requests; call `full_page_fn()` and wrap
# its result for direct browser navigation.  Typical usage:
#
#   htmx_or(req, fragment) do
#       htmx(h.main(search_input(q), fragment))
#   end
function htmx_or(full_page_fn::Function, req::HTTP.Request, fragment)
    to_response(is_htmx(req) ? fragment : full_page_fn())
end

# --- HTMX request header inspection ---
# All return "" / false when the header is absent (i.e. for non-HTMX requests).

is_htmx(req::HTTP.Request)       = HTTP.header(req, "HX-Request",      "") == "true"
hx_boosted(req::HTTP.Request)    = HTTP.header(req, "HX-Boosted",       "") == "true"
hx_target(req::HTTP.Request)     = HTTP.header(req, "HX-Target",        "")
hx_trigger(req::HTTP.Request)    = HTTP.header(req, "HX-Trigger",       "")
hx_current_url(req::HTTP.Request)= HTTP.header(req, "HX-Current-URL",   "")
hx_prompt(req::HTTP.Request)     = HTTP.header(req, "HX-Prompt",        "")

# --- HTMX response header builder ---
#
# Wraps any value (passed through to_response) and attaches HX-* response
# headers that instruct the client to perform additional actions after swap:
#
#   trigger      – fire a client-side event:  HX-Trigger
#   push_url     – push a URL to history:     HX-Push-Url
#   replace_url  – replace current URL:       HX-Replace-Url
#   redirect     – full-page redirect:        HX-Redirect
#   refresh      – full-page refresh:         HX-Refresh: true
#   retarget     – override swap target:      HX-Retarget
#   reswap       – override swap strategy:    HX-Reswap
#   location     – client-side navigate:      HX-Location
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

Register all computed (non-fixed) properties of `obj` as Oxygen GET routes.

- Non-indexed properties map to `GET /name` (e.g. `obj.about` → `/about`)
- Indexed properties map to `GET /name/{p1}/{p2}/...`
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

function route!(obj; prefix="", record_dir=nothing)
    T = typeof(obj)
    for (name, info) in DynamicObjects.meta(T)
        DynamicObjects.isfixed(info) && continue
        Symbol("@get") in info.macros || continue

        param_strs = [string(first(DynamicObjects.extractnames(idx))) for idx in info.indices]

        base = "/" * (isempty(prefix) ? "" : prefix * "/") * string(name)
        path = isempty(param_strs) ? base :
            base * "/" * join("{" .* param_strs .* "}", "/")
        name == :index && isempty(prefix) && (path = "/")

        # Capture loop variables to avoid closure-over-mutable-variable issues
        let obj=obj, name=name, param_strs=param_strs, path=path, record_dir=record_dir
            if isempty(param_strs)
                Oxygen.get(path) do _
                    resp = to_response(getproperty(obj, name))
                    isnothing(record_dir) || save_response(record_dir, path, resp)
                    resp
                end
            else
                # Store the real handler (captures obj/name/etc. by closure).
                push!(_route_handlers, idx_vals -> begin
                    val = getproperty(obj, name)[idx_vals...]
                    resp = to_response(val)
                    if !isnothing(record_dir)
                        save_path = "/" * join(vcat(string(name), idx_vals), "/")
                        save_response(record_dir, save_path, resp)
                    end
                    resp
                end)
                key = length(_route_handlers)
                # Generate a wrapper whose arg names match the route's {params}.
                param_syms = Symbol.(param_strs)
                func_args = [:_ ; param_syms]
                Oxygen.get(
                    eval(:(($(func_args...),) -> _route_handlers[$key]([$(param_syms...)]))),
                    path,
                )
            end
        end
    end
    obj
end

end # module HTMXObjects
