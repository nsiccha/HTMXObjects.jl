module HTMXObjects

export DynamicObjects, @persist, @dynamicstruct, @htmx, @memo, @cache_status, @is_cached, @cache_path, @clear_cache!, fetchindex, getstatus, cancel!, cancel_all!, PropertyComputationError, unwrap_error
export create_app
export HTTP, queryparams, formparams, formdata, bodyparams, multipartparams, Upload
export terminate, serve, staticfiles, dynamicfiles
export auto, htmx, h, Node, @__str, HyperscriptString, Raw
export route!, record!, to_response, save_response, static_transform, MIMEResponse,
    RecordingState, RecordingRoutes, RECORDING_STATE
export safely, ERROR_DIR
export is_htmx, hx_target, hx_trigger, hx_current_url, hx_boosted, hx_prompt
export hx_response
export hx_link, htmx_or
export wants_markdown, wants_errors, markdown_response, e, filter_errors, render_table, sortable_table, sortable_table_js, sortable_table_styles, download_table_js, master_detail_table, master_detail_pair, CaptionSpec, render_caption, with_caption, caption_style
export html_only, markdown_only, HtmlOnly, MarkdownOnly
export fmt_time, fmt_bytes, fmt_number, query_url, hidden_inputs, post_form, get_form, @query_url
export Long, ainput, sinput, sinput_custom, soption, linput, rinput, ninput, cinput, tinput, radio_group, loading_indicator_script, request_feedback, request_feedback_style, request_feedback_script, show_when_script, tabset, tabset_styles, htmx_tabset, status_badge, nav_sidebar, app_layout, htmxo_breadcrumb, lazy, editor_form, editor_styles, GitRepo, EditorRoutes, htmxo_utility_styles, escape_html, html_escape, compose_box, compose_box_assets, compose_box_styles, compose_box_script, overlay_bar, overlay_bar_style, overlay_bar_script
export htmxo_theme, pico_bridge, vitepress_bridge,
    vitepress_asset_dir, vitepress_theme_install, htmxo_embed_html,
    vitepress_theme_enhanceapp_snippet, vitepress_head_scripts, vitepress_proxy_config
export GalleryItem, Gallery, gallery_grid, gallery_toolbar, gallery_controls_script,
    default_gallery_card, htmxo_gallery_styles, htmxo_syntax_head, find_item, section_items, parse_gallery_metadata
export TestItemInfo, discover_test_items
export test_list, test_output, test_run!, test_run_all!, test_run_failed!, test_run_missing!, test_run_batch!, test_run_tag!, test_clear_cache!
export TestRoutes, StructureRoutes, SchemaRoutes, SharedOpsRoutes
export Verb
export OperationContext, RootProvider

using DynamicObjects, HTTP, Tables
import DynamicObjects: @persist, fetchindex, getstatus, _nested_struct_type
using HTMX
import HTMX: h, auto, Node, @__str, HyperscriptString, Raw

import Oxygen
import Oxygen: formdata
using Oxygen.Core: ServerContext, register, Nullable

import LibGit2

const CONTEXT :: Ref{ServerContext} = Ref(ServerContext(; mod=@__MODULE__))

"""
    Verb{V}

Singleton type used as the **first positional argument** of every route IP
emitted by `@get`/`@post`/`@put`/`@patch`/`@delete`/`@ws`. Routes are pure
sugar over DynamicObjects' indexable properties:

    @get foo(x::Int) = body            # source

    compute_property(::T, ::Val{:foo}, ::Verb{:GET}, x::Int) = body   # emitted

The verb being part of the dispatch signature lets a single property name
host an arbitrary number of HTTP-method handlers (`@get foo() = …` and
`@post foo() = …` coexist), and lets verb-keyed route IPs share a name with
non-verb-keyed (data) IPs without collision. The route registrar threads
`Verb{V}()` into the IP call at request-handling time.

Bare-form route LHS (`@get foo = body`) is rejected at macro-expansion
time — every route must be a call form (`@get foo() = body`) so DO can
register it as an indexable property.
"""
struct Verb{V} end

# Forward declaration: `@htmx struct` (defined further down in this file at
# `RecordingRoutes`, `AppContext`, `TestRoutes`, `EditorRoutes`) emits a
# fully-qualified method definition `HTMXObjects.query_url(self::T; …) = …`
# during its expansion. Julia 1.10 errors with `UndefVarError: query_url not
# defined` when adding a method to `M.f` if `f` doesn't yet exist in `M` —
# even though the same form `f(args) = body` would create the binding when
# unqualified. The full `query_url` implementation is defined later in the
# file alongside the `@query_url` macro; this `function …end` just creates
# the binding so the in-file `@htmx struct` blocks can attach methods.
function query_url end

"""
    serve(; host="127.0.0.1", port=8080, async=false, parallel=false, revise=nothing, kwargs...)

Start the HTTP server. Passes all keyword arguments through to `Oxygen.Core.serve`.
When `async=false` (the default), blocks until interrupted and calls [`terminate`](@ref) on exit.

`parallel` controls request concurrency:
- `false` — single-threaded (default)
- `true` — multi-threaded on the `:default` threadpool (Oxygen's `serveparallel`)
- `:interactive` — multi-threaded on the `:interactive` threadpool, leaving `:default`
  free for heavy computation. Launch julia with e.g. `julia -t 8,4` for 8 computation
  threads and 4 request-handling threads.

**Footgun:** `julia -tauto,auto` and `JULIA_NUM_THREADS=auto,auto` both resolve the
second slot to `1`, not "match default" — `:interactive` stays at 1 thread even
with `auto`. To size both pools equally, compute shell-side:
`julia -t\$(nproc),\$(nproc)`. Without a sized `:interactive` pool,
`parallel=:interactive` is strictly worse than `parallel=false` (same effective
concurrency, plus extra spawn overhead per request, plus a startup `@warn`).
"""
function serve(; parallel=false, kwargs...)
    async = Base.get(kwargs, :async, false)
    kwargs = _with_access_timing(kwargs)
    serve_kwargs = if parallel === :interactive
        if Threads.nthreads(:interactive) <= 1
            @warn "Only 1 interactive thread available. Launch julia with e.g. \"julia -t 8,4\" to add more interactive threads for request handling."
        end
        (; handler=_interactive_stream_handler, parallel=false, kwargs...)
    else
        (; parallel, kwargs...)
    end
    try
        return Oxygen.Core.serve(CONTEXT[]; serve_kwargs...)
    finally
        if !async
            terminate()
        end
    end
end

# --- Access-log request timing ---------------------------------------------
# `serve` installs, by default, a middleware that stamps each request's start
# time plus a custom access-log line that appends the elapsed handling time.
# HTTP.jl's `logfmt` has no duration token and records no request-start, so the
# two pieces are required together. A caller can override either by passing their
# own `middleware` / `access_log` to `serve` — both are respected.

# Mirrors Oxygen's default access-log line (Oxygen `core.jl`: the `logfmt`
# assigned in `serve`) so the output is purely additive: the standard line, then
# a trailing elapsed time.
const _ACCESS_LOG_BASE = logfmt"$time_iso8601 - $remote_addr:$remote_port - \"$request\" $status"

"""
    _timing_middleware(handler)

Oxygen middleware that stamps `req.context[:t0]` with the request-start time so
[`_timed_access_log`](@ref) can report the elapsed handling time.
"""
function _timing_middleware(handler)
    function (req::HTTP.Request)
        req.context[:t0] = time()
        return handler(req)
    end
end

"""
    _timed_access_log(io, http)

Custom `access_log` writer: Oxygen's standard access-log line followed by the
request's elapsed handling time, formatted with SI units (e.g. ` 78.9ms`,
` 1.23s`, ` 5.0min`). The duration is omitted for requests that never passed
through [`_timing_middleware`](@ref) (e.g. connections rejected before routing).
"""
function _timed_access_log(io::IO, http)
    _ACCESS_LOG_BASE(io, http)
    t0 = Base.get(http.message.context, :t0, nothing)
    t0 === nothing || print(io, " ", fmt_time(time() - t0))
end

# Prepend the timing middleware to any caller-supplied `middleware`, and install
# the timed access-log writer unless the caller passed their own `access_log`
# (matching Oxygen's own default-only-if-absent behaviour).
function _with_access_timing(kwargs)
    kw = Dict{Symbol,Any}(kwargs)
    kw[:middleware] = Any[_timing_middleware, Base.get(kw, :middleware, [])...]
    haskey(kw, :access_log) || (kw[:access_log] = _timed_access_log)
    return kw
end

"""
    _interactive_stream_handler(middleware::Function)

Like Oxygen's `stream_handler` + `parallel_stream_handler`, but spawns each
request on the `:interactive` threadpool instead of `:default`.
"""
function _interactive_stream_handler(middleware::Function)
    base_handler = Oxygen.Core.stream_handler(middleware)
    function (stream::HTTP.Stream)
        task = Threads.@spawn :interactive begin
            handle = @async base_handler(stream)
            wait(handle)
        end
        wait(task)
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

"""
    dynamicfiles(folder, mountdir="static"; headers=[], loadfile=nothing)

Serve dynamic files from `folder` at the URL prefix `mountdir`.
Files are re-read from disk on each request (no caching).
"""
dynamicfiles(
    folder::String,
    mountdir::String="static";
    headers::Vector=[],
    loadfile::Nullable{Function}=nothing
) = Oxygen.Core.dynamicfiles(CONTEXT[], CONTEXT[].service.router, folder, mountdir; headers, loadfile)

# Append a new value to an existing query-parameter slot. String slot becomes
# a 2-element vector; vector slot grows in place.
_form_append(existing::String, v) = [existing, v]
_form_append(existing::AbstractVector, v) = (push!(existing, v); existing)

# --- Form-encoded parsing (multi-value aware) ---

# Parse a form-encoded string ("a=1&b=2&b=3") into a multi-value-preserving
# Dict. Shared by `queryparams` (URL query string) and `formparams` (request
# body). Query and `application/x-www-form-urlencoded` bodies use the same
# wire format, so one parser suffices.
function _parse_form_encoded(s::AbstractString)
    isempty(s) && return Dict{String, Union{String, Vector{String}}}()
    d = Dict{String, Union{String, Vector{String}}}()
    # '+' represents a space in form-encoded data. `unescapeuri` only does
    # percent-decoding, so translate '+' → ' ' before unescaping. Without this,
    # values produced by JS `URLSearchParams.toString()` (which form-encodes
    # spaces as '+') round-trip spaces as literal '+' characters and break
    # downstream lookups.
    _form_unescape(t) = String(HTTP.URIs.unescapeuri(replace(t, '+' => ' ')))
    for part in split(s, "&", keepempty=false)
        kv = split(part, "=", limit=2)
        k = _form_unescape(kv[1])
        v = length(kv) >= 2 ? _form_unescape(kv[2]) : ""
        if haskey(d, k)
            d[k] = _form_append(d[k], v)
        else
            d[k] = v
        end
    end
    d
end

"""
    queryparams(req::HTTP.Request) -> Dict{String, Union{String, Vector{String}}}

Parse query parameters from the request URL. Unlike `HTTP.queryparams` (which
returns `Dict{String,String}` and drops duplicate keys), this preserves all
values: single-value keys map to a `String`, duplicate keys map to a
`Vector{String}`.

    queryparams("http://x/?a=1&b=2&b=3")  #=> Dict("a" => "1", "b" => ["2", "3"])
"""
queryparams(req::HTTP.Request) = _parse_form_encoded(HTTP.URI(req.target).query)

"""
    formparams(req::HTTP.Request) -> Dict{String, Union{String, Vector{String}}}

Parse a urlencoded request body into a multi-value-preserving Dict. The
`formparams` analogue of `queryparams` — repeated body fields (`image=a&image=b`)
become a `Vector{String}` instead of collapsing to the last value, which is
what `Oxygen.formdata` (a thin wrapper over `URIs.queryparams`) does. Used by
the `@post`/`@put`/`@patch` argument extractor so a `Vector`-typed kwarg
receives every posted value.

Reads the body via `HTTP.payload`; an empty body yields an empty dict.
"""
function formparams(req::HTTP.Request)
    # Only an `application/x-www-form-urlencoded` body is parseable here — it's
    # the wire format `_parse_form_encoded` understands. A `multipart/form-data`
    # (file upload), JSON, or other binary body must NOT be fed to the
    # urlencoded parser: `unescapeuri` hits a raw `%` (0x25) byte followed by
    # non-hex bytes and throws `ArgumentError: invalid base 16 digit`. The
    # codegen'd POST/PUT/PATCH arg extractor calls `formparams` unconditionally,
    # so without this gate every multipart upload route 500s on a realistic
    # (non-trivially-byte-patterned) file. Such handlers read the raw body
    # themselves (e.g. `HTTP.parse_multipart_form`); any kwargs they declare
    # fall back to `queryparams`. Parse only when the content-type says
    # urlencoded, or is absent (a headerless client posting a urlencoded body).
    ct = lowercase(HTTP.header(req, "Content-Type", ""))
    isempty(ct) || occursin("application/x-www-form-urlencoded", ct) ||
        return Dict{String, Union{String, Vector{String}}}()
    # `copy` the payload before `String` consumes it: `String(::Vector{UInt8})`
    # takes ownership and EMPTIES the source vector (`HTTP.payload(req)` IS
    # `req.body`), which would zero the body for any handler that reads it after
    # the arg extractor runs. The copy is read-only w.r.t. `req`; existing
    # urlencoded callers only read the parsed Dict, so behaviour is unchanged.
    _parse_form_encoded(String(copy(HTTP.payload(req))))
end

"""
    Upload

One uploaded part of a `multipart/form-data` request body, as bound to a route
kwarg by the POST/PUT/PATCH argument extractor. `filename` is the client-supplied
name, `contenttype` the part's declared MIME type, `data` the raw bytes, `name`
the form field name. Declare `@post upload(; file)` and the handler receives an
`Upload` for `file` — no need to call `HTTP.parse_multipart_form` yourself.
"""
struct Upload
    name::String
    filename::String
    contenttype::String
    data::Vector{UInt8}
end
Base.show(io::IO, u::Upload) =
    print(io, "Upload(", repr(u.filename), ", ", repr(u.contenttype), ", ", length(u.data), " bytes)")

# Multi-value append for repeated multipart field names. Value-type-agnostic
# (works for `Upload` and `String` parts alike), mirroring `_form_append`.
_mp_append(existing::AbstractVector, v) = (push!(existing, v); existing)
_mp_append(existing, v) = Any[existing, v]

"""
    multipartparams(req::HTTP.Request) -> Dict{String, Any}

Parse a `multipart/form-data` body into a field-name → value map: a file part
(one carrying a filename) becomes an [`Upload`](@ref); a plain text part becomes
a `String`. Repeated field names collect into a `Vector`. Returns an empty dict
when the body isn't valid multipart. Non-destructive — `HTTP.parse_multipart_form`
reads `req.body` through its own buffer, leaving the request body intact.
"""
function multipartparams(req::HTTP.Request)
    d = Dict{String, Any}()
    parts = HTTP.parse_multipart_form(req)
    parts === nothing && return d
    for p in parts
        fname = p.filename === nothing ? "" : p.filename
        val = isempty(fname) ? String(read(p)) : Upload(p.name, fname, p.contenttype, read(p))
        d[p.name] = haskey(d, p.name) ? _mp_append(d[p.name], val) : val
    end
    d
end

"""
    bodyparams(req::HTTP.Request) -> AbstractDict

The request-body parameter source for the POST/PUT/PATCH argument extractor:
a `multipart/form-data` body routes to [`multipartparams`](@ref) (text fields as
`String`, file fields as [`Upload`](@ref)); everything else routes to
[`formparams`](@ref) (which itself only parses an
`application/x-www-form-urlencoded` body and returns an empty dict otherwise).
This is what lets a declared kwarg bind from either body shape through the one
shared `_lookup_param` path — `@post f(; x)` for a urlencoded field and
`@post upload(; file)` for a file both Just Work.
"""
function bodyparams(req::HTTP.Request)
    ct = lowercase(HTTP.header(req, "Content-Type", ""))
    occursin("multipart/form-data", ct) && return multipartparams(req)
    formparams(req)
end

"""
    _wrap_ws_bodies!(struct_expr)

Pre-process the struct body: for any `@ws` property, wrap the RHS in `(__ws__) -> RHS`.
This lets users write `@ws feed = begin ... __ws__ ... end` and have `__ws__` available
as the WebSocket variable, while DynamicObjects stores a callable `(__ws__) -> body`.
"""
function _wrap_ws_bodies!(struct_expr)
    body = struct_expr.args[3]
    for (i, arg) in enumerate(body.args)
        arg isa Expr || continue
        # Walk through nested macrocall layers to find @ws
        expr = arg
        depth = 0
        while Meta.isexpr(expr, :macrocall) && expr.args[1] != Symbol("@ws")
            expr = expr.args[end]
            depth += 1
        end
        Meta.isexpr(expr, :macrocall) && expr.args[1] == Symbol("@ws") || continue
        # Found @ws — the inner expression is an assignment: name = rhs
        inner = expr.args[end]
        inner isa Expr || continue
        if inner.head == :(=)
            rhs = inner.args[2]
            inner.args[2] = Expr(:(->), :__ws__, rhs)
        end
    end
    struct_expr
end

"""
    _warn_legacy_name!(struct_expr, legacy::Symbol, replacement::Symbol)

Scan the struct body for top-level property definitions named `legacy` and
emit a deprecation `@warn` pointing at `replacement`. Skips route-marked
properties (so `@get legacy(...)` — a user route literally named `legacy` —
is not flagged). The warning includes `file:line` from the nearest
`LineNumberNode` so the fix is mechanical.
"""
# Resolve the bound property name from the LHS of a `name = ...` (or
# `name(...) = ...`, `name[...] = ...`, `name::T = ...`) inside an `@htmx`
# struct body. Returns `nothing` when the LHS doesn't bind a plain symbol.
_as_symbol(s::Symbol) = s
_as_symbol(_) = nothing
_property_lhs_name(_) = nothing
_property_lhs_name(lhs::Symbol) = lhs
function _property_lhs_name(lhs::Expr)
    (lhs.head === :call || lhs.head === :ref) && return _as_symbol(first(lhs.args))
    lhs.head === :(::) && length(lhs.args) >= 1 && return _as_symbol(lhs.args[1])
    nothing
end

# Name of a kwarg slot in a `:parameters` expr — bare `Symbol` or `:kw` Expr.
_kwarg_name(_) = nothing
_kwarg_name(s::Symbol) = s
_kwarg_name(e::Expr) = e.head === :kw ? e.args[1] : nothing

# Symbol name from a typed param shape: `n` or `n::T`.
_typed_param_name(_) = nothing
_typed_param_name(s::Symbol) = s
function _typed_param_name(e::Expr)
    e.head === :(::) && length(e.args) >= 1 || return nothing
    _as_symbol(e.args[1])
end

# Split a `@param`-style LHS into `(name, type_or_nothing)`. Returns
# `(nothing, nothing)` if the LHS is not a recognized shape.
_split_param_lhs(_) = (nothing, nothing)
_split_param_lhs(lhs::Symbol) = (lhs, nothing)
function _split_param_lhs(lhs::Expr)
    lhs.head === :(::) && length(lhs.args) == 2 || return (nothing, nothing)
    name = _as_symbol(lhs.args[1])
    isnothing(name) ? (nothing, nothing) : (name, lhs.args[2])
end

function _warn_legacy_name!(struct_expr, legacy::Symbol, replacement::Symbol)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    lnn = nothing
    for arg in body.args
        if arg isa LineNumberNode
            lnn = arg
            continue
        end
        arg isa Expr || continue
        if Meta.isexpr(arg, :macrocall) && arg.args[1] in route_macros
            continue
        end
        inner = arg
        while Meta.isexpr(inner, :macrocall)
            inner = inner.args[end]
        end
        Meta.isexpr(inner, :(=)) || continue
        name = _property_lhs_name(inner.args[1])
        if name === legacy
            loc = isnothing(lnn) ? "" : " (near $(lnn.file):$(lnn.line))"
            @warn "Deprecated: `$legacy` is a legacy framework property name — rename to `$replacement`$loc. The legacy name still works but will be emitted as a warning on every macro expansion."
        end
    end
    struct_expr
end

_warn_legacy_page_name!(struct_expr) = _warn_legacy_name!(struct_expr, :page, :__page__)

# Attribute names that should be `__prefix__`-aware (and therefore should
# not be hardcoded root-absolute strings). `hx-*` attributes get
# underscore-to-hyphen translation by HTMX's node builder; we match the underscore form
# as written in source.
const _URL_BEARING_ATTRS = (
    :href, :src, :action, :formaction,
    :hx_get, :hx_post, :hx_put, :hx_patch, :hx_delete,
    :hx_post_url, :hx_target,
)

# Cheaply detect if an expression is a hardcoded root-absolute URL string —
# i.e. `"/foo"` or `"/foo/$id"`-style interpolation that begins with `/`.
# External (`http://…`, `//…`, `mailto:`), protocol-relative, or anchor URLs
# (`#…`) are fine; only literal absolute paths are flagged.
_is_hardcoded_root_url(expr::AbstractString) = startswith(expr, "/") && !startswith(expr, "//")
_is_hardcoded_root_url(expr::Expr) = Meta.isexpr(expr, :string) && !isempty(expr.args) &&
    _is_root_str_prefix(expr.args[1])
_is_hardcoded_root_url(_) = false
_is_root_str_prefix(s::AbstractString) = startswith(s, "/") && !startswith(s, "//")
_is_root_str_prefix(_) = false

"""
    _warn_hardcoded_url_in_attrs!(struct_expr)

Walk the struct body looking for `href="/foo"` / `hx_get="/foo"` /
`src="/foo"` etc. — root-absolute URL string literals on URL-bearing
attributes. Such URLs bypass `__prefix__` (so they break under any
non-root mount, base-path deploy, or `record!` target) and bypass
`__route__` (so updating a route's path requires hunting all literal
references). Suggest `__self__/"…"` (cross-route) or `__route__`
(self-link) instead.

Warning, not error: the hardcoded form still works for root-mounted
local dev. Apps adopt the prefix-aware form gradually.
"""
function _warn_hardcoded_url_in_attrs!(struct_expr)
    body = struct_expr.args[3]
    type_name = _struct_type_name(struct_expr)
    seen = Set{Tuple{Symbol,Any}}()  # dedupe identical (attr, value) pairs across passes

    function walk(node, lnn)
        if node isa Expr
            for arg in node.args
                if arg isa LineNumberNode
                    lnn = arg
                elseif arg isa Expr
                    if Meta.isexpr(arg, :kw) && length(arg.args) == 2 &&
                       arg.args[1] in _URL_BEARING_ATTRS &&
                       _is_hardcoded_root_url(arg.args[2])
                        attr = arg.args[1]
                        val = arg.args[2]
                        key = (attr, val)
                        if !(key in seen)
                            push!(seen, key)
                            shown = val isa AbstractString ? repr(val) :
                                    Meta.isexpr(val, :string) ? "string interp starting with `$(val.args[1])…`" :
                                    string(val)
                            loc = isnothing(lnn) ? "" : " (near $(lnn.file):$(lnn.line))"
                            @warn """
@htmx struct $type_name: hardcoded root-absolute URL `$shown` on `$attr`$loc — bypasses `__prefix__` (breaks under non-root mounts and static deploys). Prefer:
  `$attr=__self__/"<rest>"`           — cross-route URL, `__prefix__`-aware
  `$attr=__route__`                   — same URL as this handler call
  `$attr=string(__self__/"<rest>")`   — if the surrounding ctx wants a String
"""
                        end
                    end
                    walk(arg, lnn)
                end
            end
        end
        lnn
    end

    walk(body, nothing)
    struct_expr
end

"""
    _warn_redundant_req_decl!(struct_expr)

Warn when the user explicitly writes `__req__ = nothing`. `_inject_dunder_props!`
adds this line automatically when no `__req__` is declared, so an explicit
declaration is redundant noise.
"""
function _warn_redundant_req_decl!(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    lnn = nothing
    for arg in body.args
        if arg isa LineNumberNode
            lnn = arg
            continue
        end
        arg isa Expr || continue
        if Meta.isexpr(arg, :macrocall) && arg.args[1] in route_macros
            continue
        end
        inner = arg
        while Meta.isexpr(inner, :macrocall)
            inner = inner.args[end]
        end
        Meta.isexpr(inner, :(=)) || continue
        lhs = inner.args[1]
        lhs === :__req__ || continue
        rhs = inner.args[2]
        rhs === :nothing || (rhs isa QuoteNode && rhs.value === nothing) || continue
        loc = isnothing(lnn) ? "" : " (near $(lnn.file):$(lnn.line))"
        @warn "Redundant: `__req__ = nothing` is injected automatically by `@htmx` — remove this line$loc."
    end
    struct_expr
end

"""
    _inject_dunder_props!(struct_expr)

Ensure that `@htmx` struct bodies always declare `__parent__`, `__prefix__`,
`__req__`, `__appdata__`, `__route__`, and `__on_error__` as properties so route
bodies can reference them and so the `__parent__` chain threads request context,
appdata, the mount prefix, the per-request route URL, and the error hook down
through `@include`d sub-structs.

Defaults:
- `__parent__ = nothing` — set by `@include` desugar to point at the enclosing struct.
- `__prefix__ = ""` — root-level mount path (no leading `/`); `@include` builds
  `parent.__prefix__ * "/childname"` for each nested sub-struct.
- `__req__` / `__appdata__` / `__on_error__` — fall through `__parent__` if
  present, else `nothing`. `__req__` is supplied by HTMXO at request-handler
  construction. `__appdata__` is supplied by the user — the conventional pattern
  is to override the default inside the root `@htmx struct` body
  (`__appdata__ = APP_DATA` with `const APP_DATA = AppData()` at module scope) so
  the singleton is part of the struct's definition, not of `route!`'s API.
  `__on_error__` is the optional post-error side-effect hook (see
  `_default_error_render`); defining it once on the root `@htmx struct` body
  propagates it to every route — including `@include`d upstream structs the app
  cannot edit.
- `__route__ = ""` — defaults to empty; `_register_route_handler` sets it to
  the current request's path (query string stripped, **mount-prefix-aware**:
  the request `__prefix__` is prepended when a path-stripping proxy removed it,
  so `__route__` is the full externally-visible path and stays consistent with
  `__prefix__`) when constructing the struct for a real request, so route
  bodies can write `hx_get=__route__` / `href=__route__` — and
  `query_url(__self__;…)`, which builds on `__route__` — instead of recomputing
  `__self__/"name/\$id"`. For non-request constructions (e.g., `route!` at
  module init) it stays `""`.

The legacy short names `req` / `appdata` are no longer recognised.
"""
function _inject_dunder_props!(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    has_req = false
    has_appdata = false
    has_parent = false
    has_prefix = false
    has_route = false
    has_on_error = false
    for arg in body.args
        arg isa Expr || continue
        if Meta.isexpr(arg, :macrocall) && arg.args[1] in route_macros
            continue
        end
        inner = arg
        while Meta.isexpr(inner, :macrocall)
            inner = inner.args[end]
        end
        Meta.isexpr(inner, :(=)) || continue
        name = _property_lhs_name(inner.args[1])
        name === :__req__      && (has_req = true)
        name === :__appdata__  && (has_appdata = true)
        name === :__parent__   && (has_parent = true)
        name === :__prefix__   && (has_prefix = true)
        name === :__route__    && (has_route = true)
        name === :__on_error__ && (has_on_error = true)
    end
    prepend = Any[]
    has_parent   || push!(prepend, :(__parent__ = nothing))
    has_prefix   || push!(prepend, :(__prefix__ = ""))
    has_req      || push!(prepend, :(__req__      = isnothing(__parent__) ? nothing : __parent__.__req__))
    has_appdata  || push!(prepend, :(__appdata__  = isnothing(__parent__) ? nothing : __parent__.__appdata__))
    has_route    || push!(prepend, :(__route__    = isnothing(__parent__) ? "" : __parent__.__route__))
    has_on_error || push!(prepend, :(__on_error__ = isnothing(__parent__) ? nothing : __parent__.__on_error__))
    if !isempty(prepend)
        body.args = vcat(prepend, body.args)
    end
    struct_expr
end

# Find inline struct properties: prop = struct Name ... end
# Returns list of (prop_name, child_struct_name) pairs.
function _find_inline_structs(struct_expr)
    parent_name = _struct_type_name(struct_expr)
    body = struct_expr.args[3]
    result = Tuple{Symbol, Symbol}[]
    for arg in body.args
        arg isa Expr || continue
        if Meta.isexpr(arg, :(=)) && Meta.isexpr(arg.args[2], :struct)
            lhs = arg.args[1]
            Meta.isexpr(lhs, (:call, :ref)) && (lhs = lhs.args[1])
            Meta.isexpr(lhs, :(::)) && (lhs = lhs.args[1])
            child_name = arg.args[2].args[2]  # struct Name from `prop = struct Name ... end`
            # DO renames child to Parent_ChildName
            gen_name = Symbol(parent_name, "_", child_name)
            let n = _as_symbol(lhs); isnothing(n) || push!(result, (n, gen_name)) end
        end
    end
    result
end

# Find @include external struct properties:
#   @include prop = ExternalStruct(; ...)              # classic, non-indexed
#   @include prop(args…) = ExternalStruct(args…; …)    # indexed include
# Returns list of (prop_name, type_name_expr, index_params) tuples where
# `index_params` is a `Vector{Symbol}` (empty for non-indexed).
function _find_include_externals(struct_expr)
    body = struct_expr.args[3]
    result = Tuple{Symbol, Any, Vector{Symbol}}[]
    for arg in body.args
        arg isa Expr || continue
        expr = arg
        while Meta.isexpr(expr, :macrocall) && expr.args[1] != Symbol("@include")
            expr = expr.args[end]
        end
        Meta.isexpr(expr, :macrocall) && expr.args[1] == Symbol("@include") || continue
        inner = expr.args[end]
        Meta.isexpr(inner, :(=)) || continue
        lhs = inner.args[1]
        rhs = inner.args[2]
        # RHS should be a call like ExternalStruct(; __req__, ...) — extract the type.
        Meta.isexpr(rhs, :call) || continue
        type_expr = rhs.args[1]
        prop_name, index_params = if lhs isa Symbol
            (lhs, Symbol[])
        elseif Meta.isexpr(lhs, :call) && lhs.args[1] isa Symbol
            ips = Symbol[]
            for a in lhs.args[2:end]
                Meta.isexpr(a, :parameters) && continue   # kwargs
                bare = Meta.isexpr(a, :kw) ? a.args[1] : a
                push!(ips, Meta.isexpr(bare, :(::)) ? bare.args[1] : bare)
            end
            (lhs.args[1], ips)
        else
            continue
        end
        push!(result, (prop_name, type_expr, index_params))
    end
    result
end

# Extract type name from a struct expression.
function _struct_type_name(struct_expr)
    type_name = struct_expr.args[2]
    Meta.isexpr(type_name, :(<:)) && (type_name = type_name.args[1])
    Meta.isexpr(type_name, :(curly)) && (type_name = type_name.args[1])
    type_name
end

# Default: no inline struct properties.
_inline_struct_props(::Type) = ()

# Map a route-macro symbol to the verb short symbol used in `Verb{V}` and
# `_http_verbs`. `Symbol("@get")` → `:GET`; `Symbol("@ws")` → `:WEBSOCKET`
# (the special case — the macro name `@ws` is shorter than the HTTP-method
# label "WEBSOCKET" Oxygen expects).
function _verb_short(verb::Symbol)
    verb === Symbol("@ws") && return :WEBSOCKET
    s = String(verb)
    startswith(s, "@") ? Symbol(uppercase(s[2:end])) : verb
end

"""
    _convert_include_to_struct!(struct_expr)

Pre-process `@include` lines:

- `@include prop = begin...end` is rewritten to `prop = struct _Include_prop ... end`
  so DO's inline-struct machinery wires `__parent__=__self__` automatically.
- `@include prop = ExternalStruct(; ...)` keeps the external call but its kwargs
  are augmented with `__parent__=__self__, __prefix__=__self__.__prefix__ * "/prop"`
  so the sub-struct receives the request/appdata chain (via `__parent__`) and the
  correct mount prefix at construction time. User-provided values for these kwargs
  win; we only fill them in if absent.
"""
function _convert_include_to_struct!(struct_expr)
    body = struct_expr.args[3]
    for (i, arg) in enumerate(body.args)
        arg isa Expr || continue
        # Walk through nested macrocall layers to find @include
        expr = arg
        while Meta.isexpr(expr, :macrocall) && expr.args[1] != Symbol("@include")
            expr = expr.args[end]
        end
        Meta.isexpr(expr, :macrocall) && expr.args[1] == Symbol("@include") || continue
        inner = expr.args[end]
        Meta.isexpr(inner, :(=)) || continue
        lhs = inner.args[1]
        rhs = inner.args[2]
        prop_name, index_params, lhs_idx_exprs = if lhs isa Symbol
            (lhs, Symbol[], Any[])
        elseif Meta.isexpr(lhs, :call) && lhs.args[1] isa Symbol
            ips = Symbol[]
            idx_exprs = Any[]
            for a in lhs.args[2:end]
                Meta.isexpr(a, :parameters) && continue
                push!(ips, Meta.isexpr(a, :(::)) ? a.args[1] : a)
                push!(idx_exprs, a)   # preserve type annotations
            end
            (lhs.args[1], ips, idx_exprs)
        else
            continue
        end
        if Meta.isexpr(rhs, :block)
            # Convert to: prop[(args…)] = struct _Include_prop ... end
            # __prefix__ extends the parent's prefix with the include name
            # plus any index_params interpolated at runtime — same shape as
            # what `_inject_include_prefix!` does for the call form.
            # `:index` is dropped from the URL segment (mirrors `_route_path`
            # and `_nested_prefix_and_step`), so an `@include index(x) = …`
            # inside `/skills` produces children at `/skills/{x}`, not
            # `/skills/index/{x}`.
            struct_name = Symbol("_Include_", prop_name)
            prefix_expr = prop_name === :index ?
                :(__parent__.__prefix__) :
                :(__parent__.__prefix__ * "/" * $(string(prop_name)))
            for ip in index_params
                prefix_expr = :($prefix_expr * "/" * string($ip))
            end
            pushfirst!(rhs.args, :(__prefix__ = $prefix_expr))
            child_struct = Expr(:struct, false, struct_name, rhs)
            body.args[i] = isempty(index_params) ?
                :($prop_name = $child_struct) :
                Expr(:(=), Expr(:call, prop_name, lhs_idx_exprs...), child_struct)
        elseif Meta.isexpr(rhs, :call)
            # Only inject __prefix__ (HTMXO-specific). Leave @include in place
            # for DO to handle __parent__ and __status__ wiring. For indexed
            # includes, the runtime prefix interpolates the per-call arg values.
            _inject_include_prefix!(rhs, prop_name; index_params)
        end
    end
    struct_expr
end

"""
    _inject_verb_in_route_lhs!(struct_expr)

For every `@get`/`@post`/`@put`/`@patch`/`@delete`/`@ws` macrocall in the
struct body, rewrite the call-form LHS to inject
`__verb__::HTMXObjects.Verb{V}` as the **first positional argument**, where
`V` is the verb short symbol (`:GET`, `:POST`, `:WEBSOCKET`, …). After this
rewrite, DynamicObjects' `@dynamicstruct` sees:

    @get foo(x::Int) = body          # source
    foo(__verb__::HTMXObjects.Verb{:GET}, x::Int) = body   # after rewrite (LHS)

and emits `compute_property(::T, ::Val{:foo}, __verb__::Verb{:GET}, x::Int) = body`.
The route registrar threads `Verb{V}()` into `prop(Verb{V}(), idx_vals…; kw…)`
at request-handling time, so verb dispatch is purely a method-table lookup.
The arg is named (`__verb__`) so route bodies can forward the verb to
sub-router routes — e.g. `__self__.pipeline.index(__verb__)` to delegate
from `@get index()` to an `@include`d sub-router's `@get index()`.

Bare-form LHS is impossible here — `_extract_route_info` already rejected it.
The injection is idempotent guarded: if the first positional arg already has
a `::Verb{…}` annotation (e.g. when re-running on a Revise re-eval),
this is a no-op.
"""
function _inject_verb_in_route_lhs!(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    for arg in body.args
        arg isa Expr || continue
        expr = arg
        verb = Symbol("")
        while Meta.isexpr(expr, :macrocall)
            expr.args[1] in route_macros && (verb = expr.args[1])
            expr = expr.args[end]
        end
        verb === Symbol("") && continue
        Meta.isexpr(expr, :(=)) || continue
        lhs = expr.args[1]
        Meta.isexpr(lhs, (:call, :ref)) || continue
        verb_short = _verb_short(verb)
        verb_type = Expr(:(::), :__verb__, Expr(:curly, GlobalRef(@__MODULE__, :Verb), QuoteNode(verb_short)))
        # Skip past `:parameters` if present (must come immediately after
        # the called name); insertion goes after both the name and any
        # leading `:parameters` block so positional args stay positional.
        insert_pos = 2
        if length(lhs.args) >= 2 && Meta.isexpr(lhs.args[2], :parameters)
            insert_pos = 3
        end
        # Idempotency: if a `::Verb{…}` is already at insert_pos, skip.
        if length(lhs.args) >= insert_pos
            existing = lhs.args[insert_pos]
            if Meta.isexpr(existing, :(::))
                ann = existing.args[end]
                if Meta.isexpr(ann, :curly) && length(ann.args) >= 1 &&
                   (ann.args[1] === :Verb || (ann.args[1] isa GlobalRef && ann.args[1].name === :Verb))
                    continue
                end
            end
        end
        insert!(lhs.args, insert_pos, verb_type)
    end
    struct_expr
end

"""
    _inject_include_prefix!(call_expr, prop_name; index_params=Symbol[])

Mutate the kwargs of `SomeStruct(args...; ...)` so that
`__prefix__=__self__.__prefix__ * "/prop_name"[ * "/" * string(arg)…]` is
present (without overriding any user-provided value). For an indexed include
(`@include prop(x, y) = External(x, y)`), the `index_params` are interpolated
into the prefix at runtime so each invocation of the property gets the URL
segment for its current arg values.

`__parent__` and `__status__` are handled by DynamicObjects' `@include`
processing.
"""
function _inject_include_prefix!(call_expr, prop_name; index_params::Vector{Symbol}=Symbol[])
    params_idx = findfirst(a -> Meta.isexpr(a, :parameters), call_expr.args)
    if params_idx === nothing
        params = Expr(:parameters)
        insert!(call_expr.args, 2, params)
    else
        params = call_expr.args[params_idx]
    end
    has_prefix = any(kw -> _kwarg_name(kw) === :__prefix__, params.args)
    if !has_prefix
        # `:index` drops the URL segment — mirrors `_route_path` and
        # `_nested_prefix_and_step`. So `@include index(x) = External(x)`
        # mounts children at `/parent/{x}`, not `/parent/index/{x}`.
        prefix_expr = prop_name === :index ?
            :(__self__.__prefix__) :
            :(__self__.__prefix__ * "/" * $(string(prop_name)))
        for ip in index_params
            prefix_expr = :($prefix_expr * "/" * string($ip))
        end
        push!(params.args, Expr(:kw, :__prefix__, prefix_expr))
    end
    call_expr
end

# Default: no @param properties declared.
_param_names(::Type) = ()

"""
    _convert_params!(struct_expr) -> Vector{Symbol}

Find `@param name::T = default` lines in a `@htmx` struct body and rewrite them
to plain derived-property assignments that call
`_extract_param(_req_of(__self__), ...)` at property-access time. Supports:

    @param vessels::Vector{String} = ["Tablet-20"]
    @param fit_key::String                             # required, errors on miss
    @param note = "hi"                                 # untyped, with default
    @param begin
        vessels::Vector{String} = ["Tablet-20"]
        n_bootstrap::String     = "10"
    end
    @param (; fit_key, top_chains, max_draws) = __parent__   # delegate to parent

The delegation form registers each listed name as a param on this struct (so
`query_url(__self__)` serializes them) and resolves their value at access time
via `source.<name>` — typically `__parent__.<name>` — rather than extracting
from the request directly. See `_rewrite_param_delegation`.

Returns the ordered list of declared param names for later `_param_names` emission.
"""
function _convert_params!(struct_expr)
    body = struct_expr.args[3]
    names = Symbol[]
    new_args = Any[]
    process_line! = inner -> begin
        delegated = _rewrite_param_delegation(inner)
        if delegated !== nothing
            for (n, assign) in delegated
                push!(names, n)
                push!(new_args, assign)
            end
            return
        end
        rewritten = _rewrite_param_line(inner)
        rewritten === nothing && return
        push!(names, rewritten[1])
        push!(new_args, rewritten[2])
    end
    for arg in body.args
        if !(arg isa Expr)
            push!(new_args, arg); continue
        end
        # Peel a `Core.@doc "str" @param …` wrapper — Julia's parser wraps
        # `"doc"\n@param x = …` inside a struct body, making arg.args[1] a
        # GlobalRef(Core,:@doc) rather than Symbol("@param"), which the bare
        # check below would miss. Capture the wrapper so it can be re-attached
        # on the lowered property, letting DynamicObjects capture info.doc.
        doc_wrapper = nothing
        param_arg = arg
        if Meta.isexpr(arg, :macrocall)
            mname = arg.args[1]
            if (mname isa GlobalRef ? mname.name : mname) === Symbol("@doc") &&
               length(arg.args) >= 4
                doc_wrapper = arg
                param_arg = arg.args[end]
            end
        end
        if Meta.isexpr(param_arg, :macrocall) && param_arg.args[1] === Symbol("@param")
            # Strip the LineNumberNode that follows the macro name
            payload = [a for a in param_arg.args[2:end] if !(a isa LineNumberNode)]
            # Block form: @param begin ... end → expand each line
            is_block = length(payload) == 1 && Meta.isexpr(payload[1], :block)
            if is_block
                # Block form: outer @doc wrapper is ambiguous across multiple params —
                # don't re-attach (each block-line param gets info.doc=nothing). Deferred.
                for inner in payload[1].args
                    inner isa LineNumberNode && (push!(new_args, inner); continue)
                    process_line!(inner)
                end
            else
                # Single-line form: @param vessels::T = default
                # Multiple payload elements are a tuple literal (comma-separated)
                n_before = length(new_args)
                for inner in payload
                    process_line!(inner)
                end
                # Single-param with outer @doc: re-attach the wrapper on the one
                # newly-pushed rewrite so DO captures the doc string onto info.doc.
                if !isnothing(doc_wrapper) && length(new_args) - n_before == 1
                    new_args[end] = Expr(:macrocall, doc_wrapper.args[1:end-1]..., new_args[end])
                end
            end
        else
            push!(new_args, arg)
        end
    end
    body.args = new_args
    names
end

# Parse a delegation form `@param (; a, b, c) = source` — register a/b/c as
# params on this struct and resolve their values via `source.a` / `source.b`
# / `source.c` at property-access time. Typical use: `@param (; a, b) = __parent__`
# so the child both (a) serializes these keys through `query_url(__self__)` and
# (b) mirrors whatever value the parent resolved them to.
# Returns `Vector{Tuple{Symbol, Expr}}` or `nothing` if the expression isn't a
# delegation form.
# TODO: assert at macro-expand time that `source`'s type declares each name as
# an `@param`, so a parent-side rename fails loudly rather than silently
# shadowing the child's default extraction path.
function _rewrite_param_delegation(expr)
    Meta.isexpr(expr, :(=), 2) || return nothing
    lhs, source = expr.args
    Meta.isexpr(lhs, :tuple) && length(lhs.args) == 1 || return nothing
    params = lhs.args[1]
    Meta.isexpr(params, :parameters) || return nothing
    out = Tuple{Symbol, Expr}[]
    for n in params.args
        name_sym = _typed_param_name(n)
        name_sym === nothing && return nothing
        push!(out, (name_sym, Expr(:(=), name_sym, Expr(:., source, QuoteNode(name_sym)))))
    end
    out
end

# Parse a single `name::T = default` / `name = default` / `name::T` / `name` form
# and return `(name_sym, rewritten_assignment)` or `nothing` if unrecognized.
function _rewrite_param_line(expr)
    default_expr = nothing
    lhs = expr
    if Meta.isexpr(expr, :(=))
        lhs = expr.args[1]
        default_expr = expr.args[2]
    end
    name_sym, type_expr = _split_param_lhs(lhs)
    name_sym === nothing && return nothing
    t = type_expr === nothing ? :nothing : type_expr
    req_expr = :($(_req_of)(__self__))
    rhs = default_expr === nothing ?
        :($(_extract_param)($req_expr, $(QuoteNode(name_sym)), $t)) :
        :($(_extract_param)($req_expr, $(QuoteNode(name_sym)), $t, $default_expr))
    (name_sym, Expr(:(=), name_sym, rhs))
end

# Parse a single `name::T = default` / `name = default` / `name::T` / `name` form
# and return `(name_sym, rewritten_assignment)` for @header, or `nothing` if unrecognized.
# Produces `name = _extract_header(_req_of(__self__), :name, T, default)`.
function _rewrite_header_line(expr)
    default_expr = nothing
    lhs = expr
    if Meta.isexpr(expr, :(=))
        lhs = expr.args[1]
        default_expr = expr.args[2]
    end
    name_sym, type_expr = _split_param_lhs(lhs)
    name_sym === nothing && return nothing
    t = type_expr === nothing ? :nothing : type_expr
    req_expr = :($(_req_of)(__self__))
    rhs = default_expr === nothing ?
        :($(_extract_header)($req_expr, $(QuoteNode(name_sym)), $t)) :
        :($(_extract_header)($req_expr, $(QuoteNode(name_sym)), $t, $default_expr))
    (name_sym, Expr(:(=), name_sym, rhs))
end

"""
    _convert_headers!(struct_expr) -> Vector{Symbol}

Find `@header name::T = default` lines in a `@htmx` struct body and rewrite them
to plain derived-property assignments that call
`_extract_header(_req_of(__self__), ...)` at property-access time. The header key
is derived from the kwarg name by replacing `_` with `-` (so `x_kb_agent_id`
binds HTTP header `X-KB-Agent-ID`; HTTP.jl header lookup is case-insensitive).
Supports single-line and block forms identical to `@param`.

Returns the ordered list of declared header names for threading to child structs.
"""
function _convert_headers!(struct_expr)
    body = struct_expr.args[3]
    names = Symbol[]
    new_args = Any[]
    process_line! = inner -> begin
        rewritten = _rewrite_header_line(inner)
        rewritten === nothing && return
        push!(names, rewritten[1])
        push!(new_args, rewritten[2])
    end
    for arg in body.args
        if !(arg isa Expr)
            push!(new_args, arg); continue
        end
        if Meta.isexpr(arg, :macrocall) && arg.args[1] === Symbol("@header")
            payload = [a for a in arg.args[2:end] if !(a isa LineNumberNode)]
            if length(payload) == 1 && Meta.isexpr(payload[1], :block)
                for inner in payload[1].args
                    inner isa LineNumberNode && (push!(new_args, inner); continue)
                    process_line!(inner)
                end
            else
                for inner in payload
                    process_line!(inner)
                end
            end
        else
            push!(new_args, arg)
        end
    end
    body.args = new_args
    names
end

function _htmx_transform(struct_expr; reroute=true, parent_params=Symbol[], parent_headers=Symbol[], is_child=false, kwargs...)
    # Capture externals BEFORE _convert_include_to_struct! strips the @include
    # wrapper from `@include prop = ExternalStruct(...)` lines (the begin-block
    # form turns into an inline struct, but the call form is left as a bare
    # assignment, so _find_include_externals would no longer recognize it).
    include_externals = _find_include_externals(struct_expr)
    route_info = _extract_route_info(struct_expr)

    # With `Verb{V}` injected as the first positional argument of every route
    # IP, same-name routes on different verbs and same-name `@include` members
    # are all distinguished by method dispatch — no internal-name mangling.
    # We only reject exact same-`(name, verb)` duplicates, which would emit
    # identical `compute_property(::T, ::Val{name}, ::Verb{V}, …)` methods
    # that overwrite each other.
    let seen = Set{Tuple{Symbol, Symbol}}(), dups = Tuple{Symbol, Symbol}[]
        for ri in route_info
            key = (ri.prop_name, ri.verb)
            key in seen && push!(dups, key)
            push!(seen, key)
        end
        isempty(dups) || error("""
            @htmx struct $(_struct_type_name(struct_expr)): duplicate route definitions $(unique(dups)) — same property name AND same verb. Each (name, verb) pair must be unique because both produce identical `compute_property(::T, ::Val{name}, ::Verb{V}, …)` methods.

            Don't write:

                @get foo() = list_view()
                @get foo() = other_view()    # ← rejected (same verb)

            Either rename one, or merge into a single route with a positional/kwarg switch:

                @get foo(slug::String="") = isempty(slug) ? list_view() : item_view(slug)
            """)
    end

    # Inject `::HTMXObjects.Verb{V}` as the first positional arg of every
    # route LHS so DO emits a verb-keyed `compute_property` method.
    _inject_verb_in_route_lhs!(struct_expr)

    _convert_include_to_struct!(struct_expr)

    _wrap_ws_bodies!(struct_expr)
    _warn_legacy_page_name!(struct_expr)
    reroute && _warn_redundant_req_decl!(struct_expr)
    reroute && _warn_hardcoded_url_in_attrs!(struct_expr)
    reroute && _inject_dunder_props!(struct_expr)
    own_params = _convert_params!(struct_expr)
    own_headers = _convert_headers!(struct_expr)
    # Merge: parent params/headers first (preserve order), then own, deduplicated.
    param_names = Symbol[]
    for n in parent_params
        n in param_names || push!(param_names, n)
    end
    for n in own_params
        n in param_names || push!(param_names, n)
    end
    header_names = Symbol[]
    for n in parent_headers
        n in header_names || push!(header_names, n)
    end
    for n in own_headers
        n in header_names || push!(header_names, n)
    end
    inline_props = _find_inline_structs(struct_expr)

    block = DynamicObjects.dynamicstruct(struct_expr;
        child_handler=s -> _htmx_transform(s; reroute=false, parent_params=param_names, parent_headers=header_names, is_child=true),
        is_child, kwargs...)
    type_name = _struct_type_name(struct_expr)
    @assert Meta.isexpr(block, :escape)
    # Emit one `_extract_args(::Type{T}, ::Val{name}, ::Verb{V}, …)` method
    # per route entry. Keying on `Verb{V}` lets multiple routes share the
    # same property name (different verbs) without colliding.
    for ri in route_info
        push!(block.args[1].args, _generate_extract_args(type_name, ri.prop_name, ri.verb, ri.pos_params, ri.kw_params))
    end
    # Emit _nested_struct_type methods for @include externals.
    # (Inline `@struct` children are emitted by DO's macro itself, on the same
    # generic, so HTMXO only needs to add the @include-external methods here.)
    _type_fname = Expr(:., DynamicObjects, QuoteNode(:_nested_struct_type))
    for (prop, type_expr) in include_externals
        push!(block.args[1].args, Expr(:(=),
            Expr(:call, _type_fname, :(::Type{$type_name}), :(::Val{$(QuoteNode(prop))})),
            type_expr))
    end
    # Emit _param_names method if this struct declared any @param properties
    if !isempty(param_names)
        _pn_fname = Expr(:., @__MODULE__, QuoteNode(:_param_names))
        push!(block.args[1].args, Expr(:(=),
            Expr(:call, _pn_fname, :(::Type{$type_name})),
            Tuple(param_names)))
    end
    # Emit _inline_struct_props for backward compat
    all_nested = Symbol[p for (p, _) in inline_props]
    if !isempty(all_nested)
        _fname = Expr(:., @__MODULE__, QuoteNode(:_inline_struct_props))
        push!(block.args[1].args, Expr(:(=),
            Expr(:call, _fname, :(::Type{$type_name})),
            Tuple(all_nested)))
    end
    # Emit `Base.:/(::T, ::AbstractString)` so route bodies can write
    # `__self__/"plots"` and get the fully-qualified URL relative to this
    # struct's mount point. `__prefix__` is threaded through construction:
    # the root receives it from `route!`, and `@include` desugar passes
    # `__prefix__=__self__.__prefix__ * "/childname"` to each nested sub-struct.
    push!(block.args[1].args, :(
        Base.:/(self::$type_name, p::AbstractString) =
            self.__prefix__ * "/" * lstrip(p, '/')
    ))
    _qurl_fname = Expr(:., @__MODULE__, QuoteNode(:query_url))
    push!(block.args[1].args, :(
        $(_qurl_fname)(self::$type_name; overrides...) =
            $(_qurl_fname)(self.__route__, self; overrides...)
    ))
    # Emit `Base.print(io, ::T)` so route bodies can write
    # `href=__self__` (the struct's index URL — `__prefix__` for non-root
    # mounts, `"/"` for the root). HTMX stringifies attribute values via
    # `print(io, val)`, so this is what makes `href=__self__` resolve to a
    # bare URL rather than the struct's default Julia repr.
    push!(block.args[1].args, :(
        Base.print(io::IO, self::$type_name) =
            print(io, isempty(self.__prefix__) ? "/" : self.__prefix__)
    ))
    # Wrap _reroute!(T) in Base.invokelatest so it always dispatches at the
    # latest world. Without this, on Revise re-eval the call site captures the
    # world age before the freshly-emitted `meta(::Type{T})` /
    # `_nested_struct_type(::Type{T}, …)` methods are visible, producing
    # `MethodError: meta(::Type{T}) (method too new …)` from `_register_routes`.
    reroute && push!(block.args[1].args, :($Base.invokelatest($(_reroute!), $type_name)))
    block
end

_route_macros() = Set([Symbol("@get"), Symbol("@post"), Symbol("@put"), Symbol("@patch"), Symbol("@delete"), Symbol("@ws")])

# Extract route property info from the struct body AST at macro expansion time.
# Returns [(prop_name::Symbol, verb::Symbol, positional_params, kwargs_params), ...]
# where verb is the route macro symbol (e.g. Symbol("@get")), and
#   positional_params = [(name::Symbol, type_expr_or_nothing), ...]
#   kwargs_params     = [(name::Symbol, type_expr_or_nothing, has_default::Bool), ...]
function _extract_route_info(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    routes = @NamedTuple{prop_name::Symbol, verb::Symbol, pos_params::Vector, kw_params::Vector}[]
    lnn = nothing
    for arg in body.args
        arg isa LineNumberNode && (lnn = arg; continue)
        arg isa Expr || continue
        # Walk macrocall layers to find route markers
        expr = arg
        has_route = false
        verb = Symbol("")
        while Meta.isexpr(expr, :macrocall)
            if expr.args[1] in route_macros
                has_route = true
                verb = expr.args[1]
            end
            # macrocall args[2] is often a LineNumberNode
            expr.args[2] isa LineNumberNode && (lnn = expr.args[2])
            expr = expr.args[end]
        end
        has_route || continue
        # expr is the inner assignment: name(...) = rhs
        Meta.isexpr(expr, :(=)) || continue
        lhs = expr.args[1]
        pos_params = Tuple{Symbol, Any}[]
        kw_params = Tuple{Symbol, Any, Bool}[]
        if Meta.isexpr(lhs, (:call, :ref))
            prop_name = lhs.args[1]
            Meta.isexpr(prop_name, :(::)) && (prop_name = prop_name.args[1])
            for idx in lhs.args[2:end]
                if Meta.isexpr(idx, :parameters)
                    for kw_arg in idx.args
                        if Meta.isexpr(kw_arg, :kw)
                            kw_name_expr = kw_arg.args[1]
                            kw_type = _macro_extract_type(kw_arg)
                            kw_name = first(DynamicObjects.extractnames(kw_name_expr))
                            push!(kw_params, (kw_name, kw_type, true))
                        else
                            kw_type = _macro_extract_type(kw_arg)
                            kw_name = first(DynamicObjects.extractnames(kw_arg))
                            push!(kw_params, (kw_name, kw_type, false))
                        end
                    end
                else
                    p_type = _macro_extract_type(idx)
                    p_name = first(DynamicObjects.extractnames(idx))
                    push!(pos_params, (p_name, p_type))
                end
            end
        else
            # Bare-form route LHS (`@get name = body`) is rejected at
            # macro-expansion time. Every route must be a call form
            # (`@get name() = body`) so DO can register it as an indexable
            # property dispatching on the `::Verb{V}` first positional arg.
            # Without that, two routes for the same name (e.g. `@get foo`
            # and `@post foo`) would emit identical
            # `compute_property(::T, ::Val{:foo})` methods and shadow each
            # other; and a route + a same-named non-verb IP could not coexist.
            bare_name = lhs isa Symbol ? lhs :
                        (Meta.isexpr(lhs, :(::)) && lhs.args[1] isa Symbol ? lhs.args[1] : :unknown)
            error("""
                @htmx struct $(_struct_type_name(struct_expr)): bare-form route `$(verb) $(bare_name) = …` is not allowed. Every route must be a call form so it can be registered as an indexable property dispatching on `::Verb{V}` as the first positional argument.

                Don't write:

                    $(verb) $(bare_name) = body

                Write:

                    $(verb) $(bare_name)() = body

                The empty parentheses make `$(bare_name)` an indexable property; the route registrar then invokes it as `prop(Verb{:$(_verb_short(verb))}())` so multiple HTTP verbs and non-verb IPs can share the name `:$(bare_name)` without collision.
                """)
        end
        push!(routes, (prop_name=prop_name, verb=verb, pos_params=pos_params, kw_params=kw_params))
    end
    routes
end

# Extract type annotation from a parameter AST node (macro-time version of _extract_type).
function _macro_extract_type(idx)
    expr = Meta.isexpr(idx, :kw) ? idx.args[1] : idx
    Meta.isexpr(expr, :(::)) && length(expr.args) == 2 ? expr.args[2] : nothing
end

# Generate an `_extract_args(::Type{T}, ::Val{name}, ::Verb{V}, …)` method
# for one route. Keying on `Verb{V}` (instead of the legacy `__method__`
# string arg) lets multiple routes with the same property name but different
# verbs each get their own typed parameter parser.
#
# `verb` is the route macro symbol (e.g. `Symbol("@get")`); we map it to the
# verb short symbol (`:GET`) for the `::Verb{V}` annotation.
function _generate_extract_args(type_name, prop_name, verb, pos_params, kw_params)
    verb_short = _verb_short(verb)

    # Build positional param conversion statements (by URL segment position)
    pos_stmts = Expr[]
    for (i, (pname, ptype)) in enumerate(pos_params)
        segment_expr = :(__parts__[__base_segments__ + $i])
        convert_call = ptype === nothing ?
            :($(_convert_param)($segment_expr, nothing)) :
            :($(_convert_param)($segment_expr, $ptype))
        push!(pos_stmts, :($i <= __n_params__ && push!(__idx__, $convert_call)))
    end

    # Build kwarg conversion statements — delegate per-key lookup to `_lookup_param`
    # so @param, @get, @post, etc. share one parsing path.
    kw_stmts = Expr[]
    for (kname, ktype, has_default) in kw_params
        type_expr = ktype === nothing ? :nothing : ktype
        lookup_call = :($(_lookup_param)(__src__, __fallback__, $(QuoteNode(kname)), $type_expr))
        if has_default
            push!(kw_stmts, quote
                let __v__ = $lookup_call
                    __v__ === $(_NO_DEFAULT) || push!(__kw__, $(QuoteNode(kname)) => __v__)
                end
            end)
        else
            push!(kw_stmts, quote
                let __v__ = $lookup_call
                    __v__ === $(_NO_DEFAULT) && throw($(MissingRequiredParam)($(QuoteNode(kname))))
                    push!(__kw__, $(QuoteNode(kname)) => __v__)
                end
            end)
        end
    end

    # Source selection is fixed at codegen time: GET/DELETE/WEBSOCKET pull
    # from queryparams, the rest from bodyparams (with queryparams fallback).
    # bodyparams routes by Content-Type: urlencoded → formparams (multi-value
    # preserved, repeated `image=a&image=b` → `Vector{String}`), multipart →
    # multipartparams (file fields → `Upload`, text fields → `String`).
    _is_query_verb = verb_short in (:GET, :DELETE, :WEBSOCKET)

    _M = @__MODULE__
    _fname = Expr(:., _M, QuoteNode(:_extract_args))
    _verb_ann = Expr(:(::), Expr(:curly, GlobalRef(_M, :Verb), QuoteNode(verb_short)))
    _call = Expr(:call, _fname,
        :(::Type{$type_name}), :(::Val{$(QuoteNode(prop_name))}), _verb_ann,
        :__req__, :(__base_segments__::Int), :(__n_params__::Int))
    _body = if _is_query_verb
        quote
            __parts__ = split(split(__req__.target, "?")[1], "/", keepempty=false)
            __src__ = $(queryparams)(__req__)
            __fallback__ = nothing
            __idx__ = Any[]
            $(pos_stmts...)
            __kw__ = Pair{Symbol,Any}[]
            $(kw_stmts...)
            (__idx__, __kw__)
        end
    else
        quote
            __parts__ = split(split(__req__.target, "?")[1], "/", keepempty=false)
            __src__ = $(bodyparams)(__req__)
            __fallback__ = $(queryparams)(__req__)
            __idx__ = Any[]
            $(pos_stmts...)
            __kw__ = Pair{Symbol,Any}[]
            $(kw_stmts...)
            (__idx__, __kw__)
        end
    end
    Expr(:(=), _call, _body)
end

# Dispatch target for generated route arg extraction methods.
function _extract_args end


"""
    @htmx struct MyApp ... end

Wraps `@dynamicstruct` and appends a `_reroute!` call so that Revise-triggered
re-evaluation automatically re-registers routes without a server restart.
`@ws` property bodies are automatically wrapped in `(__ws__) -> body`. WS routes
accept the same path-param + kwargs surface as GET — `@ws feed(id::Int; q="") = body`
mounts at `/feed/{id}` and the handler receives the typed `id` (same `_convert_param`
path as GET) plus `q` from the upgrade request's query string.
Inline `prop = struct ... end` definitions are processed as nested route structs.
"""
macro htmx(args...)
    isempty(args) && error("@htmx: missing struct definition.")
    kwargs = Dict{Symbol,Any}(DynamicObjects._parse_macro_opt(a) for a in args[1:end-1])
    _htmx_transform(args[end]; kwargs...)
end

"""
    htmx(body...; htmx_version="2.0.8", hyperscript_version="0.9.14", pico_version=nothing, feedback=true, extra_head=())

Generate a full HTML page with HTMX and optionally Hyperscript/PicoCSS loaded from CDN.
Pass `nothing` to any version kwarg to skip that library.
Set `feedback=false` to disable automatic request feedback (pulsating borders, success/error flash).
"""
function htmx(args...;
    head = h.head,
    body = h.body,
    htmx_version        = "2.0.8",
    hyperscript_version = "0.9.14",
    pico_version        = nothing,
    feedback             = true,
    compose              = true,
    overlay              = true,
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
            # Theme defaults: declared at zero specificity inside `@layer htmxo`
            # so any subsequent `:root { --htmxo-...: ... }` (host-supplied or
            # via `pico_bridge` / `vitepress_bridge`) wins automatically.
            htmxo_theme(),
            (isnothing(pico_version) ? () : (pico_bridge(),))...,
            (feedback ? request_feedback() : ())...,
            (compose ? compose_box_assets() : ())...,
            # Thin-hook bootstrap: load the relocated overlay bundle from
            # `KB_ORIGIN/overlay/bar.js` instead of inlining `<style>`+`<script>`.
            # The bar is `position:fixed`, so a deferred async load has no
            # layout-shift to guard (no skeleton/placeholder needed).
            (overlay ? (h.script(""; src = KB_ORIGIN * "/overlay/bar.js", defer = true),) : ())...,
            htmxo_utility_styles(),
            tabset_styles(),
            editor_styles(),
            extra_head...,
        ),
        body(args...),
    )
end

"""
    pico_page(content; pico_version="2", class="container", extra_head=())

Thin wrapper around [`htmx`](@ref) for the canonical `__page__` pattern:
wrap `content` in `h.main(class=class)(content)` and assemble a full
Pico-CSS HTML page. Replaces the repeated boilerplate

    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

with

    __page__(content) = pico_page(content)
    # or with extras:
    __page__(content) = pico_page(content; extra_head=(h.title("My App"),))
"""
pico_page(content; pico_version="2", class="container", extra_head=()) =
    htmx(h.main(class=class)(content); pico_version, extra_head)

# --- Route registration and recording ---

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
    MIMEResponse(content_type, body)

Small wrapper for routes that return non-HTML content (JS, JSON, CSS,
SVG, plain text, etc.) without hand-rolling an `HTTP.Response`.
`_resolve_response` converts it to `HTTP.Response(200,
["Content-Type" => content_type]; body)`. The recording flow's
`_save_typed_response` then dispatches on Content-Type to pick the
right file extension (`.js` for `application/javascript`, `.json` for
`application/json`, etc.). One line, fully recordable, MIME-aware.

```julia
@get aov_runtime_js = MIMEResponse("application/javascript",
    strip_script(sprint(show, MIME"text/html"(), vega_runtime())))
```
"""
struct MIMEResponse
    content_type::String
    body
end

to_response(m::MIMEResponse) =
    HTTP.Response(200, ["Content-Type" => m.content_type]; body=m.body)

# Dispatch hook used by `_resolve_response` / `_resolve_response_nested`
# to bypass the HTML-page pipeline for handler return values that are
# already a final HTTP response shape. Methods return the finalized
# `HTTP.Response` (or `nothing` for values that should still flow
# through the normal HTML / markdown / HX pipeline). Add a method to
# this function to teach the framework about a new escape-hatch type.
_finalized_response(::Any) = nothing
_finalized_response(r::HTTP.Response) = r
_finalized_response(m::MIMEResponse) = to_response(m)

# Convert a value to markdown text via show(io, MIME"text/markdown"(), val).
# HTMX.jl defines show for Node; users can extend with show(io, MIME"text/markdown", val::MyType).
# Interactive chrome (form/input/textarea/button) is dropped first by
# `_strip_md_chrome` so a `?plain`/`?markdown` read never serializes a form's
# fields into prose (e.g. an edit-form textarea pre-filled with the raw body).
# An all-chrome val strips to `nothing` → empty markdown.
to_markdown_string(val) = let stripped = _strip_md_chrome(val)
    isnothing(stripped) ? "" : sprint(show, MIME"text/markdown"(), stripped)
end

# --- Dual-view wrappers: html_only / markdown_only ---

"""
    html_only(content)

Wrap content that should only appear in HTML responses. In markdown mode,
this produces an empty string. Use for interactive elements, styling, badges,
etc. that have no meaningful text representation.
"""
struct HtmlOnly
    content
end
html_only(content) = HtmlOnly(content)

"""
    markdown_only(text)

Wrap text that should only appear in markdown responses. In HTML mode,
this is invisible (renders as empty string). Use for structured markdown
output (code blocks with markers, custom formatting) that has no HTML equivalent.
"""
struct MarkdownOnly
    text::String
end
markdown_only(text) = MarkdownOnly(text)

# HTML rendering: HtmlOnly renders its content, MarkdownOnly is invisible
to_response(val::HtmlOnly) = to_response(val.content)
to_response(::MarkdownOnly) = to_response("")
auto(val::HtmlOnly; wrap) = auto(val.content; wrap)
auto(::MarkdownOnly; wrap) = ""

# HTML rendering via show dispatch — HtmlOnly renders content, MarkdownOnly is invisible
Base.show(io::IO, m::MIME"text/html", val::HtmlOnly) = show(io, m, val.content)
Base.show(io::IO, ::MIME"text/html", ::MarkdownOnly) = nothing

# Markdown rendering via show dispatch — HtmlOnly skipped, MarkdownOnly prints text
Base.show(io::IO, ::MIME"text/markdown", ::HtmlOnly) = nothing
Base.show(io::IO, ::MIME"text/markdown", val::MarkdownOnly) = print(io, val.text)


"""
    _save_typed_response(record_dir, url_path, response)

Save an `HTTP.Response` body using a file extension derived from its
Content-Type header. Used by the recording flow to capture routes that
hand-roll their response (`/aov_runtime_js` → `.js`, `/spec/<id>` → `.json`,
etc.) so the deployed static site serves them with the right MIME.
"""
function _save_typed_response(record_dir::String, url_path::String, response::HTTP.Response)
    ct = HTTP.header(response, "Content-Type", "")
    ext = if occursin("application/javascript", ct) || occursin("text/javascript", ct)
        ".js"
    elseif occursin("application/json", ct)
        ".json"
    elseif occursin("text/css", ct)
        ".css"
    elseif occursin("text/markdown", ct) || occursin("text/plain", ct)
        ".md"
    elseif occursin("image/svg", ct)
        ".svg"
    else
        ".html"
    end
    save_response(record_dir, url_path, response; ext)
end

"""
    save_response(record_dir, url_path, response; ext=".html")

Save a response body to disk, mirroring the URL path structure
(`/post/42` → `record_dir/post/42<ext>`). Enables later replay via a
static file server. Pass `ext=".md"` for markdown recordings (under the
`/md/` subtree); see also [`_save_typed_response`](@ref) which picks
the extension from the response's Content-Type.
"""
function save_response(record_dir::String, url_path::String, response::HTTP.Response; ext::String=".html")
    rel = lstrip(url_path, '/')
    # Trailing slash means "directory entry" — the URL `/foo/` and `/` both
    # map to a synthetic `index<ext>` under the matching directory. Without
    # this, `/hx/` becomes `hx/<ext>`, which is wrong (server can't serve it
    # cleanly and `cleanUrls` defeats it).
    file = if isempty(rel)
        "index" * ext
    elseif endswith(rel, '/')
        rel * "index" * ext
    else
        rel * ext
    end
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
# HTMX converts underscores to hyphens in attribute names, so these use hyphens.
const _HX_NONGET_ATTRS = Set([Symbol("hx-post"), Symbol("hx-put"), Symbol("hx-patch"), Symbol("hx-delete")])

"""
    escape_html(s) -> String

Escape `&`, `"`, `'`, `<`, `>`. Thin re-export of `HTMX.escape`.

For building a **raw HTML string by hand** — not for values passed
through `h.*`. As of the escape-by-default flip, `h.*` escapes text
children and all attribute values exactly once, so **never** pre-escape
a value you hand to a node builder (that double-escapes). Reach for
`escape_html` only when you assemble HTML text yourself; for deliberate
trusted markup inside a node use [`Raw`](@ref) instead.
"""
escape_html(s::AbstractString) = HTMX.escape(s)

"""
    html_escape(s) -> String

Escape `&`, `<`, `>` in `s` for safe interpolation into a **hand-built
raw HTML string** (e.g. `replace(_, => "<a href=...>...")` for a `<pre>`
block). Never pre-escape a value passed through `h.*` — node builders
escape text and attributes themselves; use [`Raw`](@ref) for trusted
markup inside a node.

For values that may contain quotes / apostrophes, use
[`escape_html`](@ref) (which delegates to `HTMX.escape`) for the full
5-character escape set.
"""
html_escape(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

"""
    _disable_for_static(val) -> val

Walk a Node tree and disable elements that won't work on a static server:
- Strip `hx-post`, `hx-put`, `hx-patch`, `hx-delete` attributes
- Strip `hx-get` attributes whose URL contains `?` (query-param routes)
- Strip `hx-get` attributes pointing to kwargs routes (from `_static_kwargs_paths`)
- Mark affected elements with `data-static-disabled` and `disabled`

Non-Node values pass through unchanged.
"""
_disable_for_static(val; record_base::String="") = val
_disable_for_static(val::AbstractArray; record_base::String="") = [_disable_for_static(x; record_base) for x in val]
_disable_for_static(val::Tuple; record_base::String="") = Tuple(_disable_for_static(x; record_base) for x in val)
_disable_for_static((content, id)::Pair; record_base::String="") = _disable_for_static(content; record_base) => id

# Rewrite an absolute-from-root URL (`/foo/bar`) by prepending `prefix`.
# External URLs (`https://…`), anchors (`#…`), schemes (`mailto:…`), and
# protocol-relative (`//…`) pass through unchanged. Empty `prefix` is a no-op.
function _rewrite_static_url(url::AbstractString, prefix::AbstractString)
    isempty(prefix) && return url
    isempty(url) && return url
    if startswith(url, "//") || startswith(url, "http://") || startswith(url, "https://") ||
       startswith(url, "#") || occursin(':', url) && !startswith(url, "/")
        return url
    end
    startswith(url, "/") || return url
    rstrip(prefix, '/') * url
end

# `hx-get` URLs in recordings should fetch fragments — they live under
# the `/hx/` subtree of `record_base`. Convenience wrapper.
_rewrite_hx_url(url::AbstractString, record_base::AbstractString) =
    _rewrite_static_url(url, isempty(record_base) ? "" : (rstrip(record_base, '/') * "/hx"))

function _disable_for_static(node::Node; record_base::String="")
    attrs = HTMX.attrs(node)
    children = HTMX.children(node)

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

    # Remove hx-get with query string or pointing to kwargs route; otherwise
    # rewrite it to the recorded-fragment subtree under `record_base`.
    hx_get_sym = Symbol("hx-get")
    if haskey(new_attrs, hx_get_sym)
        url = new_attrs[hx_get_sym]
        if occursin('?', url) || url in _static_kwargs_paths
            delete!(new_attrs, hx_get_sym)
            disabled = true
        else
            new_attrs[hx_get_sym] = _rewrite_hx_url(url, record_base)
        end
    end

    # Rewrite `<a href="/foo">` to `record_base * /foo` so links from a
    # recorded page land on the matching full-page recording (not the
    # `/hx/` fragment subtree — full pages link to other full pages).
    href_sym = Symbol("href")
    if haskey(new_attrs, href_sym)
        new_attrs[href_sym] = _rewrite_static_url(new_attrs[href_sym], record_base)
    end
    src_sym = Symbol("src")
    if haskey(new_attrs, src_sym)
        new_attrs[src_sym] = _rewrite_static_url(new_attrs[src_sym], record_base)
    end

    if disabled
        new_attrs[Symbol("data-static-disabled")] = "true"  # renders as data-static-disabled
        new_attrs[:disabled] = "true"                        # renders as boolean attribute
    end

    # Recurse into children
    new_children = map(child -> _disable_child(child, record_base), children)

    Node(HTMX.tag(node), new_attrs, new_children)
end

_disable_child(child, record_base) = child
_disable_child(child::Node, record_base) = _disable_for_static(child; record_base)

"""
    _inject_static_style(val)

If val is a full HTML page (contains a `<head>`), inject the disabled-element style block.
"""
_inject_static_style(val) = val
function _inject_static_style(node::Node)
    if HTMX.tag(node) == :head
        new_children = vcat(HTMX.children(node), [_STATIC_DISABLED_STYLE])
        return Node(:head, copy(HTMX.attrs(node)), new_children)
    end
    # Recurse into children looking for <head>
    new_children = map(_inject_child, HTMX.children(node))
    Node(HTMX.tag(node), copy(HTMX.attrs(node)), new_children)
end

_inject_child(child) = child
_inject_child(child::Node) = _inject_static_style(child)

"""
    static_transform(val; record_base="")

Transform a value for static recording: disable non-functional elements,
rewrite surviving `hx-get` URLs to point at the recorded fragment subtree
under `record_base`, and inject the disabled-element style block (full
pages only).

`record_base` is the URL prefix where the recording will be served (e.g.
`/HTMXObjects.jl/dev/examples/counter`). Each rooted `hx-get="/foo"`
becomes `hx-get="<record_base>/hx/foo"` so HTMX-driven sub-fetches resolve
to the recorded fragment under `<record_dir>/hx/foo.html`. Empty
`record_base` (default) skips rewriting — useful when recording for a
root-served deployment, though that's rare in practice.
"""
function static_transform(val; record_base::String="")
    result = _disable_for_static(val; record_base)
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
    htmx_or(full_page_fn, req, fragment)

Return `fragment` directly for HTMX requests; call `full_page_fn()` and wrap
its result for direct browser navigation. Typical usage:

    htmx_or(req, fragment) do
        htmx(h.main(search_input(q), fragment))
    end
"""
function htmx_or(full_page_fn, req::HTTP.Request, fragment)
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
- Type annotations auto-parse URL strings: `@get item(id::Int)` parses `id` to `Int`
- Trailing defaults register shortened routes: `@get filter(a, b=1)` registers
  both `GET /filter/{a}/{b}` and `GET /filter/{a}` (with `b=1` filled in)
- Kwargs (via call syntax) auto-extract from query params or form data:
  `@get search(; q="", page::Int=1)` extracts `q` and `page` from the query string
  (`GET` / `DELETE` → `queryparams`, `POST` / `PUT` / `PATCH` → `formparams`).
  Both parsers preserve multi-value keys, so a `Vector`-typed kwarg receives
  every repeated value (`?tag=a&tag=b` or repeated `image=a&image=b` body fields).
- The `:index` property (with empty prefix) maps to `GET /`

If `record_dir` is given, each response is also written to disk under that
directory, mirroring the URL path structure. This enables later replay via any
static HTTP server.

Returns `obj`.
"""


const _http_verbs = Dict(
    Symbol("@get") => "GET",
    Symbol("@post") => "POST",
    Symbol("@put") => "PUT",
    Symbol("@patch") => "PATCH",
    Symbol("@delete") => "DELETE",
    Symbol("@ws") => "WEBSOCKET",
)

# Store registered types so _reroute! can re-register after Revise updates.
# Stores `(prefix, record_dir)` per root type — these are re-supplied to
# `_register_routes` when Revise re-evaluates the struct definition.
# Frozen NamedTuple shape: Julia 1.10 cannot redefine a `const` whose
# stored type changes, so widening this without a restart is impossible.
# Companion dict `_record_bases` carries the `record_base` URL prefix so
# new fields can be added without touching this const.
const _registered_types = Dict{DataType, NamedTuple{(:prefix, :record_dir), Tuple{String, Any}}}()
const _record_bases = Dict{DataType, String}()
# Reverse lookup: included sub-struct type → set of registered parent types
const _included_type_parents = Dict{DataType, Set{DataType}}()

"""
    OperationContext

Request-local context passed to a [`RootProvider`](@ref). `scope` and `key`
describe the provider-selected application lifetime (`:request`, `:session`, or
`:job`); `transport` is `:http` or `:websocket`. The provider owns any storage
behind session/job keys — HTMXObjects only supplies the request, externally
visible route/prefix, and a uniform construction seam.
"""
struct OperationContext{R,K}
    request::R
    prefix::String
    route::String
    transport::Symbol
    scope::Symbol
    key::K
end

"""
    RootProvider(factory; scope=:request, key=nothing)

Construct roots for registered operations. `factory` is called as
`factory(RootT, context)` and must return a `RootT`. For `scope=:session` or
`:job`, pass a `key(req)` function and let the application-owned factory decide
how roots are retained or reconstructed. The default request provider preserves
the historic behavior: a fresh root is constructed for every request with
`__req__`, `__route__`, and `__prefix__` populated by HTMXObjects.
"""
struct RootProvider{F,K}
    factory::F
    scope::Symbol
    key::K
end

function RootProvider(factory; scope::Symbol=:request, key=nothing)
    scope in (:request, :session, :job) ||
        throw(ArgumentError("root-provider scope must be :request, :session, or :job (got $(repr(scope)))"))
    isnothing(key) && scope !== :request &&
        throw(ArgumentError("root-provider scope $(repr(scope)) requires a key(req) function"))
    keyfn = isnothing(key) ? (_req -> nothing) : key
    RootProvider{typeof(factory),typeof(keyfn)}(factory, scope, keyfn)
end

_default_root_factory(RootT, context::OperationContext) =
    RootT(; __req__=context.request, __route__=context.route,
          _prefix_kw(context.prefix)...)

RootProvider(; scope::Symbol=:request, key=nothing) =
    RootProvider(_default_root_factory; scope, key)

_normalize_root_provider(::Nothing) = RootProvider()
_normalize_root_provider(provider::RootProvider) = provider
_normalize_root_provider(factory) = RootProvider(factory)

# Companion registry rather than another field on `_registered_types`: that
# const's NamedTuple value type is frozen under Julia 1.10/Revise.
const _root_providers = Dict{DataType,Any}()
# Convert a string value to the target type. Strings pass through as-is.
# Called from generated _extract_args methods with actual Types (resolved at compile time).
_convert_param(val, ::Nothing) = val
# When the user wrote `@get foo(arg::String)`, the URL parser hands us a
# SubString{String}; without a coercion the typed iscached method dispatch
# misses (it only matches ::String, not ::SubString{String}).
_convert_param(val::AbstractString, T::Type{<:AbstractString}) = convert(T, val)
_convert_param(val::AbstractString, ::Type{Symbol}) = Symbol(val)
_convert_param(val::AbstractString, T::Type) = parse(T, val)
_convert_param(val::AbstractVector, ::Nothing) = val  # multi-value, no type annotation → keep as vector
_convert_param(val::AbstractVector, T::Type{<:AbstractString}) =
    error("expected single value for parameter (got $(length(val)) values: $(val)); use Vector type annotation if repeated values are intended")
_convert_param(val::AbstractVector, T::Type{<:AbstractVector}) = val  # multi-value + Vector annotation → keep as-is
_convert_param(val::AbstractVector, T::Type) =
    error("expected single value for parameter (got $(length(val)) values: $(val)); use Vector type annotation if repeated values are intended")
_convert_param(val::AbstractString, T::Type{<:AbstractVector}) = isempty(val) ? String[] : [val]  # single/empty → vector
# Multipart Upload values flow through the same lookup path. Untyped (`::Nothing`)
# is already covered by the `_convert_param(val, ::Nothing) = val` catch-all above.
_convert_param(val::Upload, ::Type{Upload}) = val
_convert_param(val::Upload, T::Type{<:AbstractVector}) = [val]  # single file declared as a Vector

# Determine whether kwargs come from queryparams (GET/DELETE) or formparams (POST/PUT/PATCH).
const _queryparams_verbs = Set(["GET", "DELETE"])
function _kwargs_source(req, method)
    method in _queryparams_verbs && return queryparams(req)
    bodyparams(req)
end

# Sentinel for "no default provided" / "key was absent". Distinguishes required
# params from those defaulting to `nothing`, and acts as the missing-marker
# returned by `_lookup_param`.
struct _NoDefault end
const _NO_DEFAULT = _NoDefault()

"""
    _lookup_param(src, fallback, name, T) -> value or _NO_DEFAULT

Low-level parameter lookup shared by `_extract_param` and the route-macro's
generated `_extract_args` methods. Given a precomputed primary source dict and
optional fallback dict (e.g. queryparams for POST), look up `name`, apply
`_convert_param(value, T)` when present, or return the `_NO_DEFAULT` sentinel
when the key is absent/empty so callers can decide between default or error.
"""
function _lookup_param(src, fallback, name, T)
    key = String(name)
    v = get(src, key, nothing)
    if (v === nothing || v == "") && fallback !== nothing
        v = get(fallback, key, nothing)
    end
    (v === nothing || v == "") && return _NO_DEFAULT
    _convert_param(v, T)
end

"""
    _extract_param(req, name, T, default=_NO_DEFAULT) -> value

Extract a single typed parameter from an HTTP request, mirroring the behavior of
`@get`/`@post` kwarg extraction. Looks up `name` in the method-appropriate source
(`queryparams` for GET/DELETE, `formparams` for POST/PUT/PATCH with a `queryparams`
fallback), converts via `_convert_param(value, T)`, and returns `default` when the
key is absent or empty. Throws `MissingRequiredParam(name)` if no default was supplied.

`T` may be `nothing` for untyped params (raw `String`/`Vector{String}`).
"""
function _extract_param(req, name, T, default=_NO_DEFAULT)
    method = req.method
    src = _kwargs_source(req, method)
    fallback = method in _queryparams_verbs ? nothing : queryparams(req)
    v = _lookup_param(src, fallback, name, T)
    _resolve_extracted(v, default, name)
end
_resolve_extracted(::_NoDefault, ::_NoDefault, name) = throw(MissingRequiredParam(name))
_resolve_extracted(::_NoDefault, default, _) = default
_resolve_extracted(v, _default, _name) = v

# Convert a kwarg-style symbol name to an HTTP header key by replacing `_` with
# `-`. HTTP.jl header lookup is case-insensitive, so `x-kb-agent-id` finds the
# `X-KB-Agent-ID` header that the KB curl wrapper injects.
_kwarg_to_header_name(name::Symbol) = replace(String(name), '_' => '-')

"""
    _extract_header(req, name, T, default=_NO_DEFAULT) -> value

Extract a single typed HTTP request header. The header key is derived from `name`
by replacing `_` with `-` (`x_kb_agent_id` → `x-kb-agent-id`; HTTP.jl lookup is
case-insensitive, so this matches `X-KB-Agent-ID`). Converts the raw string via
`_convert_param(value, T)` and returns `default` when the header is absent or
empty. Throws `MissingRequiredParam(name)` if no default was supplied and the header is absent.

`T` may be `nothing` for untyped headers (raw `String`).
"""
function _extract_header(req, name, T, default=_NO_DEFAULT)
    v = HTTP.header(req, _kwarg_to_header_name(name), "")
    v_or_sentinel = isempty(v) ? _NO_DEFAULT : _convert_param(v, T)
    _resolve_extracted(v_or_sentinel, default, name)
end

# Register a route handler directly on the HTTP router, bypassing Oxygen's
# argument-name validation. We extract path params ourselves via positional URL segment indexing.
# Wraps the handler so that pending Revise errors are surfaced as the
# framework's standard error article (see `_check_revise_errors!`) — this is
# the single chokepoint for all HTTP route registrations, so the check
# applies uniformly to plain, indexed, `@include`'d, and WebSocket routes.
function _register_handler(method, path, handler)
    wrapped = function(req)
        try
            _check_revise_errors!()
        catch err
            return _route_error_response(req, err, catch_backtrace())
        end
        handler(req)
    end
    HTTP.register!(CONTEXT[].service.router, get(Dict("WEBSOCKET" => "GET"), method, method), path, wrapped)
end

# Oxygen validates handler argument names against `{path}` placeholders. Our
# emitted runner intentionally extracts every argument from the request so it
# can apply one typed validation path to HTTP and WebSocket operations. Register
# the GET upgrade directly, as Oxygen ultimately does, and keep it behind the
# same Revise-error chokepoint as every other emitted route.
function _register_websocket_handler(path, handler)
    _register_handler("WEBSOCKET", path, function(req)
        HTTP.WebSockets.isupgrade(req) &&
            HTTP.WebSockets.upgrade(ws -> handler(ws, req), req.context[:stream])
    end)
end

# --- Error handling ---

"""
    ERROR_DIR

Directory where HTMXObjects writes per-error log files. Initialized in `__init__`
from the `HTMXO_ERROR_DIR` environment variable, falling back to
`joinpath(tempdir(), "htmxo_errors")`. Can be reassigned at runtime.
"""
const ERROR_DIR = Ref{String}("")

# Short unique id derived from the high-resolution clock. No UUID dep needed;
# `time_ns()` advances monotonically, so collisions require two calls in the
# same nanosecond from different threads — we hash it anyway for uniform width.
_error_uid() = string(hash(time_ns()); base=16)

# Revise is loaded? Returns the module or `nothing`. Used by every Revise-
# diagnostic helper below.
_revise_module() = get(Base.loaded_modules, Base.PkgId(Base.UUID(_REVISE_UUID), "Revise"), nothing)

# If Revise is loaded and has unresolved revision errors queued, append them
# to `io`. Oxygen's `revise=:lazy` mode already logs these to the console on
# each request; duplicating them into the per-error log lets a stale-code
# failure be diagnosed from the recorded file alone.
_qe_file(key::Tuple) = length(key) >= 2 ? key[2] : key
_qe_file(key) = key
_qe_err_bt(val::Tuple) = length(val) >= 2 ? (val[1], val[2]) : (val, nothing)
_qe_err_bt(val) = (val, nothing)

function _append_revise_errors(io)
    rev = _revise_module()
    isnothing(rev) && return
    # why: Revise.queue_errors is internal, not API. If a future Revise
    # version renames/removes the field, fail open (skip the section)
    # rather than break every error log.
    qe = try getfield(rev, :queue_errors) catch; return end
    isempty(qe) && return
    println(io)
    println(io, "--- Pending Revise errors ($(length(qe))) ---")
    for (key, val) in qe
        println(io, "file: ", _qe_file(key))
        err, bt = _qe_err_bt(val)
        isnothing(bt) ? showerror(io, err) : showerror(io, err, bt)
        println(io)
    end
end

# For each tracked source file, return `(full_path, seen_time::Float64)`
# where `seen_time` is Revise's most recent observation of that file.
# Handles both `Revise.WatchList` layouts:
#   * newer (HiWo5+):  per-file `wl.file_ctimes[basename]`
#   * older (brhA5 etc): per-directory `wl.timestamp` (shared across the dir)
# Either is the same precision Revise's own dir-watcher uses internally,
# so comparing `stat(file).mtime/ctime` against `seen_time` reproduces the
# missed-event check at `pkgs.jl:335` of older Revise.
function _revise_seen_per_file(rev)
    out = Tuple{String,Float64}[]
    try
        watched_files = getfield(rev, :watched_files)
        watched_files_lock = getfield(rev, :watched_files_lock)
        Base.lock(watched_files_lock)
        try
            for (dir, wl) in watched_files
                T = typeof(wl)
                if hasfield(T, :file_ctimes)
                    for (basename, ct) in getfield(wl, :file_ctimes)
                        push!(out, (joinpath(dir, basename), ct))
                    end
                elseif hasfield(T, :timestamp) && hasfield(T, :trackedfiles)
                    ts = getfield(wl, :timestamp)
                    for (basename, _id) in getfield(wl, :trackedfiles)
                        push!(out, (joinpath(dir, basename), ts))
                    end
                end
            end
        finally
            Base.unlock(watched_files_lock)
        end
    catch
        # why: Revise's watched_files / watched_files_lock / WatchList
        # internals are private. Fail open (return empty list) on layout
        # changes rather than break freshness reporting.
    end
    out
end

# Find tracked source files whose on-disk `mtime`/`ctime` is newer than
# Revise's recorded view (per `_revise_seen_per_file`). A mismatch means
# the OS-level FS-watch event silently dropped — Revise believes the file
# is unchanged but the user already edited it. Returns
# `Vector{Tuple{file, age_seconds}}`.
#
# Files currently in `revision_queue` are excluded — Revise has noticed
# them, just hasn't processed yet. `MISSED_EDIT_GRACE_S` absorbs the
# watcher's normal latency between a save and the inotify/kqueue event
# firing.
const MISSED_EDIT_GRACE_S = 1.0
function _revise_missed_edits()
    rev = _revise_module()
    isnothing(rev) && return Tuple{String,Float64}[]
    try
        revision_queue = getfield(rev, :revision_queue)
        revision_queue_lock = getfield(rev, :revision_queue_lock)
        queued = Set{String}()
        Base.lock(revision_queue_lock)
        try
            for (pkgdata, relfile) in revision_queue
                # why: Revise pkgdata internals are not API. Empty basedir
                # means we fall back to using relfile as-is — degraded but
                # non-fatal output.
                base = try getfield(pkgdata, :info).basedir catch; "" end
                full = isempty(base) || isabspath(relfile) ? String(relfile) : joinpath(base, String(relfile))
                push!(queued, full)
            end
        finally
            Base.unlock(revision_queue_lock)
        end

        missed = Tuple{String,Float64}[]
        for (full, seen_time) in _revise_seen_per_file(rev)
            full in queued && continue
            isfile(full) || continue
            s = stat(full)
            delta = max(s.mtime, s.ctime) - seen_time
            delta > MISSED_EDIT_GRACE_S && push!(missed, (full, delta))
        end
        sort!(missed; by = x -> -x[2])
        return missed
    catch
        # Revise's internals are not API; if the field shapes change in a
        # future version, fail open rather than break every request.
        return Tuple{String,Float64}[]
    end
end

# Append a "Revise freshness" section to the error log: most-recent file
# Revise has noticed, files in revision_queue (pending), and any files
# whose disk mtime/ctime exceeds Revise's recorded view (missed by the
# watcher). Shares the layout-aware lookup with `_revise_missed_edits`.
function _append_revise_freshness(io)
    rev = _revise_module()
    isnothing(rev) && return
    seen = _revise_seen_per_file(rev)
    latest = 0.0; latest_file = ""
    for (full, st) in seen
        st > latest && (latest = st; latest_file = full)
    end
    queued = String[]
    try
        revision_queue = getfield(rev, :revision_queue)
        revision_queue_lock = getfield(rev, :revision_queue_lock)
        Base.lock(revision_queue_lock)
        try
            for (_pkgdata, relfile) in revision_queue
                push!(queued, String(relfile))
            end
        finally
            Base.unlock(revision_queue_lock)
        end
    catch
        # why: Revise's revision_queue / revision_queue_lock are private.
        # Fail open (no queued list) rather than break the freshness
        # section — this runs on every error-log write.
    end
    missed = _revise_missed_edits()
    println(io)
    println(io, "--- Revise freshness ---")
    if latest > 0.0
        age = max(0.0, time() - latest)
        println(io, "last_seen_change: ", Libc.strftime("%Y-%m-%dT%H:%M:%S", latest),
                " (", round(age; digits=1), "s ago) — ", latest_file)
    else
        println(io, "last_seen_change: (Revise has not recorded any timestamps yet)")
    end
    if !isempty(queued)
        println(io, "revision_queue (", length(queued), " pending):")
        for f in queued; println(io, "  - ", f); end
    end
    if !isempty(missed)
        println(io, "missed_edits (", length(missed), " — disk newer than Revise's view):")
        for (f, age) in missed; println(io, "  - ", f, "  (+", round(age; digits=1), "s)"); end
    end
end

# Both checks: queue errors (Revise tried but failed to revise) and missed
# edits (the FS watcher silently dropped a save). Either condition means
# the running code is stale — throw so the per-route try/catch turns it
# into the framework's error article + log entry. The log itself includes
# `_append_revise_errors` and `_append_revise_freshness` sections so the
# agent / developer sees exactly what's stale and why.
struct ReviseHasErrors <: Exception
    files::Vector{String}
end
function Base.showerror(io::IO, e::ReviseHasErrors)
    print(io, "Revise has ", length(e.files), " unresolved revision error(s); the running code is stale.")
    println(io)
    for f in e.files
        println(io, "  - ", f)
    end
    print(io, "See the 'Pending Revise errors' section below for the failures, then fix them and re-request.")
end

struct ReviseMissedEdits <: Exception
    files::Vector{Tuple{String,Float64}}
end
function Base.showerror(io::IO, e::ReviseMissedEdits)
    print(io, "Revise's file watcher missed ", length(e.files),
          " edit(s) — the running code is stale, and Revise will not catch up on its own.")
    println(io)
    for (f, age) in e.files
        println(io, "  - ", f, "  (disk +", round(age; digits=1), "s newer than Revise's view)")
    end
    print(io, "Fix: re-save the file(s) above (`touch <path>` is enough) so Revise's directory watcher refires. ")
    print(io, "See 'Revise freshness' below for the same data.")
end

struct MissingRequiredParam <: Exception
    name::Symbol
end
function Base.showerror(io::IO, e::MissingRequiredParam)
    print(io, "Missing required parameter: ", e.name)
end

function _check_revise_errors!()
    # Both checks: queue errors (Revise tried but failed) and missed edits
    # (FS watcher silently dropped a save). Either condition means the
    # running code is stale.
    rev = _revise_module()
    isnothing(rev) && return
    # Queue errors first: a failed revision is the more direct staleness signal.
    # why: Revise.queue_errors is internal — fail open (treat as empty) on
    # field rename rather than mask every request as having stale code.
    qe = try getfield(rev, :queue_errors) catch; nothing end
    if qe !== nothing && !isempty(qe)
        files = String[]
        for k in keys(qe)
            push!(files, string(_qe_file(k)))
        end
        throw(ReviseHasErrors(files))
    end
    # Missed-by-watcher edits: silent staleness.
    missed = _revise_missed_edits()
    isempty(missed) || throw(ReviseMissedEdits(missed))
end

"""
    _record_error(err, bt, req) -> (uid, path)

Write a detailed error report to `joinpath(ERROR_DIR[], "<uid>.log")` and return
both the short uid and the full file path. Also emits an `@error` log entry
that includes the full path so the recorded file is one click away in the
terminal/log viewer.
"""
_print_req_meta(io, req::HTTP.Request) =
    (println(io, "method:    ", req.method); println(io, "target:    ", req.target))
_print_req_meta(args...) = nothing

# PropertyComputationError's 2-arg showerror prints its own filtered backtrace;
# don't append `bt` for it. All other error types use the standard 3-arg form.
_show_err(io, err::PropertyComputationError, _bt) = showerror(io, err)
_show_err(io, err, bt) = showerror(io, err, bt)

function _record_error(err, bt, req)
    dir = ERROR_DIR[]
    isempty(dir) && (dir = joinpath(tempdir(), "htmxo_errors"))
    isdir(dir) || mkpath(dir)
    uid = _error_uid()
    path = joinpath(dir, uid * ".log")
    open(path, "w") do io
        println(io, "# HTMXObjects error")
        println(io, "uid:       ", uid)
        println(io, "timestamp: ", Libc.strftime("%Y-%m-%dT%H:%M:%S", time()))
        _print_req_meta(io, req)
        println(io)
        # PropertyComputationError's 2-arg showerror already prints the cause's
        # filtered backtrace; passing `bt` would make Julia's default 3-arg
        # fallback append the outer Oxygen/HTTP trace a second time.
        # Inner-only guard: if `showerror` itself throws (e.g. a user
        # exception with a broken `Base.show` overload), we still want the
        # file to close with the header + a marker noting what failed, and
        # the outer @error / response path to fire normally. No extra log
        # line on the server side — the file path itself stays the canonical
        # record.
        try
            _show_err(io, err, bt)
        catch e_show
            println(io, "<showerror threw ", typeof(e_show), ">: ",
                    sprint(io2 -> showerror(io2, e_show); context=:limit=>true))
        end
        println(io)
        _append_revise_errors(io)
        _append_revise_freshness(io)
    end
    @error "HTMXObjects caught an error: $path"
    (uid, path)
end

"""
    _default_error_render(uid, path)

Default rendering for a caught error — a small article pointing at the recorded
error id. Override by defining `__error__` on the route's enclosing struct
(or, to disable catching entirely, set `__error__ = rethrow`).

To run an extra side effect *after* an error is recorded — notifying an
external service, incrementing a metric — define `__on_error__(err, uid, path)`
on the root `@htmx` struct. `@htmx` auto-injects `__on_error__` into every
struct (defaulting through `__parent__`, like `__appdata__`), so a single
root-level definition propagates to every route — including `@include`d
upstream structs the app cannot edit. It is invoked for its side effect only
(return value ignored) and does not replace the error article; a failure inside
it is logged, not swallowed. Fires for both route errors and `safely`-wrapped
widget errors.

In dev (Revise loaded), include the full log path so the article matches
the `@error` line on stderr (`HTMXObjects caught an error: <path>`) — the
same string is already in the server log, including it here lets the
developer / agent open the file in one step from the in-browser article.
In prod (Revise not loaded), keep just the uid.
"""
function _default_error_render(uid, path)
    if _revise_module() !== nothing
        h.article(
            h.header("Error"),
            h.p("HTMXObjects caught an error: ", h.code(path));
            aria_invalid="true",
        )
    else
        h.article(
            h.header("Error"),
            h.p("Something went wrong. Error ID: ", h.code(uid));
            aria_invalid="true",
        )
    end
end

# `__on_error__` is auto-injected into every `@htmx` struct (default `nothing`,
# falling through `__parent__`), so the property is always present but may be
# `nothing`. When non-nothing, invoke it as a side effect (return value ignored)
# after the error is recorded but before rendering — the hook point for running
# an extra command once HTMXObjects' built-in logging has run. A failure inside
# the hook is logged, never swallowed silently. Then invoke the user's
# `__error__` render hook if present, else fall back to the default. `__error__`
# is called with just the exception, so `__error__ = rethrow` works.
function _invoke_error_handler(obj, err, uid, path)
    if obj !== nothing && hasproperty(obj, :__on_error__)
        hook = getproperty(obj, :__on_error__)
        if hook !== nothing
            try
                hook(err, uid, path)
            catch hook_err
                @error "HTMXObjects __on_error__ hook failed" exception=(hook_err, catch_backtrace())
            end
        end
    end
    if obj !== nothing && hasproperty(obj, :__error__)
        return getproperty(obj, :__error__)(err)
    end
    inner = unwrap_error(err)
    if inner isa MissingRequiredParam
        return h.article(
            h.header("Bad Request"),
            h.p(sprint(showerror, inner));
            aria_invalid="true",
        )
    end
    _default_error_render(uid, path)
end

"""
    _route_error_response(req, err, bt; error_obj=nothing, page_chain=Any[])

Record the error, invoke the user's `__error__` hook (or the default), and
return an `HTTP.Response` — honoring markdown mode, HTMX fragment mode, and
`page` wrappers the same way a successful response would.
"""
# Status-code policy for caught route exceptions:
#   HTMX requests keep 200 so vanilla HTMX still swaps in the error article
#     without needing `htmx.config.responseHandling` or response-targets.
#   Non-HTMX (curl, direct browser nav, uptime checks, monitoring) get 500
#     so logs / health checks / load balancers see errors as errors,
#     except MissingRequiredParam which maps to 400 (client error).
# If the user's `__error__` hook returns an `HTTP.Response` directly, their
# status choice is respected — not rewritten.
_error_status_code(err) = unwrap_error(err) isa MissingRequiredParam ? 400 : 500
_with_error_status(req, resp::HTTP.Response, err) =
    is_htmx(req) ? resp : HTTP.Response(_error_status_code(err), resp.headers; body=resp.body)

_passthrough_response(r::HTTP.Response) = r
_passthrough_response(_) = nothing

# Expose the recorded error-log uid to the client as a response header so the
# overlay bar's traffic-observer (D3) can attach it to a bug report without
# scraping the rendered error body. Framework-namespaced (not `HX-*`) to stay
# clear of htmx's reserved response-header namespace; same-origin so JS reads it
# via `xhr.getResponseHeader('X-HTMXO-Error-Id')` with no CORS expose-list.
function _stamp_error_id(resp::HTTP.Response, uid)
    HTTP.setheader(resp, "X-HTMXO-Error-Id" => uid)
    resp
end

function _route_error_response(req, err, bt; error_obj=nothing, page_chain=Any[])
    uid, path = _record_error(err, bt, req)
    err_val = _invoke_error_handler(error_obj, err, uid, path)
    direct = _passthrough_response(err_val)
    isnothing(direct) || return _stamp_error_id(direct, uid)
    if wants_markdown(req)
        return _stamp_error_id(_with_error_status(req, markdown_response(to_markdown_string(err_val)), err), uid)
    end
    is_htmx(req) && return _stamp_error_id(to_response(err_val), uid)   # always 200 for HTMX
    for obj in reverse(page_chain)
        wrapper = _page_wrapper(obj)
        isnothing(wrapper) || (err_val = wrapper(err_val))
    end
    _stamp_error_id(_with_error_status(req, to_response(err_val), err), uid)
end

"""
    safely(f; obj=nothing, req=nothing)

Run `f()` and return its result; on exception, record the error and return
the same renderable that `__error__` would produce at the route level. Use
this for widget-level error containment — e.g. one of several panels composed
inside a route handler where a failure in one panel should not take down the
whole page.

    safely(; obj=__self__) do
        h.article(... expensive rendering ...)
    end

If `obj` defines `__error__`, that hook is used; otherwise the default article
with the recorded uid is returned.
"""
function safely(f; obj=nothing, req=nothing)
    try
        return f()
    catch err
        bt = catch_backtrace()
        uid, path = _record_error(err, bt, req)
        return _invoke_error_handler(obj, err, uid, path)
    end
end

"""
    _resolve_response(obj, req, val; record_dir=nothing, save_path=nothing)

Convert a route handler's return value to an HTTP response, automatically
handling markdown, HTMX fragment, and full-page modes.

Convention-based properties on `obj`:
- `__page__(content)` — wraps fragment in full page (for direct browser requests). Legacy name `page` still works with a deprecation warning.
- `to_markdown(val)` — custom markdown serializer

If the route returns an `HTTP.Response` directly, it passes through unchanged.
"""
function _resolve_response(obj, req, val; record_dir=nothing, save_path=nothing, record_base::String="")
    # Pre-finalized values (a route handler returning an `HTTP.Response`
    # or a `MIMEResponse` escape hatch for non-HTML bodies) bypass the
    # `__page__` wrap entirely — adding `<html>…</html>` around raw JS
    # / JSON / CSS bytes would break the Content-Type contract. Dispatch
    # on `_finalized_response`: the method on bare values returns
    # `nothing` so we fall through to the regular pipeline.
    let finalized = _finalized_response(val)
        if !isnothing(finalized)
            if !isnothing(record_dir) && !isnothing(save_path)
                _save_typed_response(record_dir, save_path, finalized)
            end
            return finalized
        end
    end

    # Recording for the regular HTML pipeline. Mirrors the runtime branches
    # below (markdown / HX-fragment / wrapped page) so the on-disk shape
    # matches what a live request would produce.
    if !isnothing(record_dir) && !isnothing(save_path)
        wrapper = _page_wrapper(obj)
        if wants_markdown(req)
            # Recording skips markdown for values whose type doesn't define
            # `show(::IO, ::MIME"text/markdown", ...)` — `showable` is the
            # explicit check, rather than catching any error from rendering.
            if showable(MIME"text/markdown"(), val)
                save_response(record_dir, "/md" * save_path,
                    HTTP.Response(200, ["Content-Type" => "text/markdown"]; body=to_markdown_string(val));
                    ext=".md")
            end
        elseif is_htmx(req)
            save_response(record_dir, "/hx" * save_path, to_response(static_transform(val; record_base)))
        elseif !isnothing(wrapper)
            save_response(record_dir, save_path, to_response(static_transform(wrapper(val); record_base)))
        else
            save_response(record_dir, save_path, to_response(static_transform(val; record_base)))
        end
    end

    # Error filter: keep only data-error nodes (applied before markdown/rich)
    if wants_errors(req)
        val = filter_errors(val)
        isnothing(val) && return markdown_response("(no errors)")
    end

    # Markdown mode
    if wants_markdown(req)
        if hasproperty(obj, :to_markdown)
            return to_response(getproperty(obj, :to_markdown)(val))
        else
            return markdown_response(to_markdown_string(val))
        end
    end

    # HTMX fragment or no page wrapper defined → return as-is
    fragment_resp = to_response(val)
    wrapper = _page_wrapper(obj)
    if is_htmx(req) || isnothing(wrapper)
        return fragment_resp
    end

    # Full page wrap for direct browser navigation
    to_response(wrapper(val))
end

# For URL paths whose only `{x}` placeholders are at the very end (the
# common single-route case), this is equivalent to "count the fixed
# segments" — but that fails for nested-include paths like
# `/sub/{pn}/leaf/{x}/{y}` where include-arg placeholders are interleaved
# with fixed segments. Computing as `total - n_leaf_args` always lands at
# the segment immediately preceding the leaf's own args.
_base_segments(path, n_params::Int) =
    length(split(path, "/", keepempty=false)) - n_params

# When `route!` is called without an explicit `prefix=` kwarg, mount_prefix is "".
# In that case we must NOT pass `__prefix__=""` to the constructor — that would
# clobber any default the struct itself sets in its body (e.g. an env-driven
# `__prefix__ = get(ENV, "BASEPATH", "/proxy/8000")`). Only override when there is
# an actual prefix to set. Children get their `__prefix__` via the `@include`
# desugar reading `__self__.__prefix__`, so the resolved root value propagates
# either way.
_prefix_kw(mp) = isempty(mp) ? NamedTuple() : (; __prefix__=mp)

# Per-request mount prefix (Fork B — overlay/same-origin support). Resolution
# order, computed at root construction where `req` is in scope:
#   1. an explicit registration prefix (`route!(...; prefix=)`) always wins;
#   2. else the `X-Forwarded-Prefix` header a reverse-proxy sets (the KB's
#      `/p/<slug>` proxy, or Strato) — so every app is prefix-aware behind a
#      proxy with zero app code;
#   3. else "" — `_prefix_kw` then passes nothing, preserving any struct-body
#      `__prefix__` default (e.g. an env-driven BASEPATH).
# The header value is normalized to a single leading slash, no trailing slash
# (`/p/raumplan`), matching how `__prefix__` is printed verbatim as a URL prefix.
function _request_prefix(req::HTTP.Request, registration_prefix::AbstractString)
    isempty(registration_prefix) || return registration_prefix
    fwd = HTTP.header(req, "X-Forwarded-Prefix", "")
    fwd = strip(fwd, '/')
    isempty(fwd) ? "" : "/" * fwd
end

# Per-request URL of the route being handled, with query string stripped —
# used to populate `__route__` on the struct so route bodies can write
# `hx_get=__route__` / `href=__route__` instead of recomputing
# `__self__/"name/$id"`. Falls back to `req.target` if URL parsing fails.
function _request_route_path(req::HTTP.Request)
    target = req.target
    isempty(target) && return ""
    qi = findfirst('?', target)
    isnothing(qi) ? target : target[1:qi-1]
end

# Prefix-aware form: prepend the request `prefix` when a path-stripping reverse
# proxy (e.g. the Strato tunnel, which strips `X-Forwarded-Prefix` from the
# path before forwarding) removed it, so `__route__` is the full
# externally-visible path — matching `__prefix__`. This restores the invariant
# that `query_url(__self__;…)` (which builds on `__route__`) and `href=__self__`
# / `__self__/"…"` (which build on `__prefix__`) agree on the mount prefix,
# while still preserving the current handler's path params (carried in the
# stripped path, which `__prefix__`/`string(self)` lack). No-op when there is no
# prefix, or when the path already carries it (non-stripping proxy, or a
# registration-prefix mount whose routes register at `prefix * path`).
function _request_route_path(req::HTTP.Request, prefix::AbstractString)
    rp = _request_route_path(req)
    isempty(prefix) && return rp
    (rp == prefix || startswith(rp, prefix * "/")) && return rp
    prefix * rp
end

function _operation_context(provider::RootProvider, req::HTTP.Request,
        root_prefix::AbstractString, transport::Symbol)
    prefix = _request_prefix(req, root_prefix)
    OperationContext(req, prefix, _request_route_path(req, prefix), transport,
                     provider.scope, provider.key(req))
end

function _provide_root(provider::RootProvider, RootT, context::OperationContext)
    root = provider.factory(RootT, context)
    root isa RootT || throw(ArgumentError(
        "root provider for $(RootT) returned $(typeof(root)); expected an instance of $(RootT)"))
    root
end

# Shared request/session/job target resolution for HTTP and WebSocket routes.
# Keeping this below the registration funnel means both transports construct
# the same root type through the same provider and walk the same include chain.
function _operation_target(provider::RootProvider, RootT, chain::Vector,
        req::HTTP.Request, root_prefix::AbstractString, root_segs::Int,
        transport::Symbol)
    context = _operation_context(provider, req, root_prefix, transport)
    root = _provide_root(provider, RootT, context)
    leaf = isempty(chain) ? root : _walk_chain(root, chain, req, root_segs)
    (; context, root, leaf)
end

# The common typed pass-through runner. Route code never manually reads query,
# form, multipart, or WebSocket upgrade parameters: the emitted `_extract_args`
# method validates/coerces them, then the verb-keyed DO property is invoked.
function _run_operation(target, LeafT, name::Symbol, verb_inst::Verb,
        req::HTTP.Request, base::Int, n_params::Int)
    idx_vals, kw_pairs = _extract_args(LeafT, Val(name), verb_inst, req, base, n_params)
    prop = getproperty(target.leaf, name)
    value = prop(verb_inst, idx_vals...; NamedTuple(kw_pairs)...)
    (; context=target.context, root=target.root, leaf=target.leaf,
       idx_vals, kw_pairs, value)
end

"""
    _register_route_handler(RootT, LeafT, chain, method, name, path, n_params, record_dir; root_prefix="")

Single chokepoint for HTTP route handler registration. Routes are uniform
since bare-form LHS is rejected at macro time — every route is an
indexable property dispatching on `::Verb{V}` as the first positional arg.
The handler:

1. Constructs the root struct.
2. Walks the include chain if any.
3. Calls `_extract_args(LeafT, Val(name), Verb{V}(), req, base, n_params)`
   to parse URL/query/form params.
4. Invokes `prop(Verb{V}(), idx_vals…; kw…)` where `prop = getproperty(leaf, name)`
   is the IP wrapper.

`Verb{V}` is the singleton encoded from `Symbol(method)` at registration
time (`"GET"` → `Verb{:GET}`).

WebSocket handlers share the root-provider and typed operation runner below,
but retain a transport-specific `ws` signature and response lifecycle.
"""
function _register_route_handler(RootT, LeafT, chain::Vector, method, name,
        path, n_params, record_dir; root_prefix="", record_base::String="",
        root_provider=RootProvider())
    base = _base_segments(path, n_params)
    is_included = !isempty(chain)
    # Number of URL segments consumed by the root prefix (e.g. "/foo/bar" → 2)
    root_segs = isempty(root_prefix) ? 0 :
                count(==('/'), strip(root_prefix, '/')) + 1
    # Verb singleton, fixed per registration. `method` is "GET"/"POST"/…;
    # `Symbol(method)` is the verb short symbol used in `Verb{V}`.
    verb_inst = Verb{Symbol(method)}()
    _register_handler(method, path, function(req)
        local context, root, leaf
        try
            target = _operation_target(root_provider, RootT, Symbol[], req,
                                       root_prefix, root_segs, :http)
            context = target.context
            root = target.root
        catch err
            return _route_error_response(req, err, catch_backtrace())
        end

        if is_included
            try
                leaf = _walk_chain(root, chain, req, root_segs)
            catch err
                bt = catch_backtrace()
                page_chain = _has_page(root) ? Any[root] : Any[]
                return _route_error_response(req, err, bt; error_obj=root, page_chain)
            end
        else
            leaf = root
        end

        try
            target = (; context, root, leaf)
            operation = _run_operation(target, LeafT, name, verb_inst, req, base, n_params)
            idx_vals = operation.idx_vals
            val = operation.value

            save_path = if isnothing(record_dir)
                nothing
            elseif is_included
                "/" * join(vcat(string.(chain), string(name), string.(idx_vals)), "/")
            else
                "/" * join(vcat(string(name), string.(idx_vals)), "/")
            end

            if is_included
                page_chain = _collect_page_chain(root, chain, req, root_segs)
                return _resolve_response_nested(page_chain, req, val; record_dir, save_path, record_base)
            else
                return _resolve_response(leaf, req, val; record_dir, save_path, record_base)
            end
        catch err
            bt = catch_backtrace()
            page_chain = is_included ?
                _collect_page_chain(root, chain, req, root_segs) :
                (_has_page(leaf) ? Any[leaf] : Any[])
            return _route_error_response(req, err, bt; error_obj=leaf, page_chain)
        end
    end)
end

function _warn_docs_prefix(path, name)
    startswith(lstrip(path, '/'), "docs") &&
        @error "Route `$name` maps to path \"$path\" which starts with \"/docs\" — Oxygen reserves this prefix for its Swagger UI. The route will silently 404. Rename the route to avoid the \"/docs\" prefix."
end

# Build the URL path for a route property. `prefix` is the enclosing mount
# path without leading slash (`""` for root, `"examples"` for an @include,
# `"app/examples"` for a nested @include). `:index` collapses its name
# segment at any depth — bare `@get index` maps to the prefix itself,
# `@get index(slug)` to the prefix plus the param(s) — so both the top-level
# and `@include` registration paths go through one rule.
function _route_path(prefix::AbstractString, name::Symbol, param_strs::AbstractVector)
    segs = String[]
    isempty(prefix) || push!(segs, prefix)
    name === :index || push!(segs, string(name))
    for p in param_strs
        push!(segs, "{" * p * "}")
    end
    isempty(segs) ? "/" : "/" * join(segs, "/")
end

# Compute the URL prefix and the chain step (`(name, types)`) for a nested
# include. For non-indexed includes the prefix gains one segment (`/<name>`)
# and the step has empty `types`. For indexed includes (`@include sub(x::T) = …`)
# the prefix also gains a `{x}` placeholder per index_param, and `types` lists
# the resolved Julia Type per param so the request handler can convert URL
# segments via `_convert_param`.
function _nested_prefix_and_step(OwnerT, name::Symbol, info, prefix::AbstractString)
    pos_idx_names = String[]
    types = Any[]
    mod = parentmodule(OwnerT)
    for idx in info.indices
        Meta.isexpr(idx, :parameters) && continue
        ex = Meta.isexpr(idx, :kw) ? idx.args[1] : idx
        nm = first(DynamicObjects.extractnames(ex))
        push!(pos_idx_names, string(nm))
        type_expr = Meta.isexpr(ex, :(::)) && length(ex.args) == 2 ? ex.args[2] : nothing
        push!(types, isnothing(type_expr) ? nothing : Core.eval(mod, type_expr))
    end
    # Drop `:index` from the URL segment — mirrors `_route_path`'s
    # `name === :index || push!(segs, string(name))` rule. So
    # `@include index(x::String) = …` inside `@include skills = …` produces
    # `/skills/{x}`, not `/skills/index/{x}`. When prefix is empty and
    # name === :index, the nested prefix becomes empty; the param loop below
    # appends `/{x}` segments and the request-router formats the leading slash.
    nested_prefix = if name === :index
        prefix
    elseif isempty(prefix)
        string(name)
    else
        prefix * "/" * string(name)
    end
    for nm in pos_idx_names
        nested_prefix = isempty(nested_prefix) ? "{" * nm * "}" :
                                                 nested_prefix * "/{" * nm * "}"
    end
    # `url_name` is kept on the step for backwards compatibility with
    # `_chain_steps` consumers that read it — always equal to `name`.
    step = (name=name, types=types, url_name=name)
    (nested_prefix, step)
end

# Split `info.indices` into positional indices (excluding the `:parameters`
# kwargs node), produce the URL-segment names, count them, and locate any
# trailing-default positions for shortened-route emission. Identical block
# previously inlined in both top-level and included registration paths.
function _route_param_shape(positional_indices)
    param_strs = [string(first(DynamicObjects.extractnames(idx))) for idx in positional_indices]
    n_params = length(param_strs)
    default_positions = Int[]
    for (j, idx) in enumerate(positional_indices)
        if Meta.isexpr(idx, :kw)
            push!(default_positions, j)
        elseif !isempty(default_positions)
            empty!(default_positions)
            break
        end
    end
    (param_strs, n_params, default_positions)
end

# Unified per-route registration: handles all five shapes (WEBSOCKET / plain
# non-indexed / zero-arg indexed / kwargs-only / general-with-trailing-default
# shortening) in one place. Both `_register_routes` (top-level) and
# `_register_included_routes` (nested @include) funnel here.
function _register_one_route(OwnerT, RouteT, chain::Vector, prefix::AbstractString,
                              mount_prefix::AbstractString, name::Symbol, info,
                              method::AbstractString, record_dir, record_base::AbstractString,
                              root_provider::RootProvider)
    positional_indices = Any[]
    has_kwargs = false
    # The first positional index of every route is the injected
    # `::HTMXObjects.Verb{V}` annotation (see `_inject_verb_in_route_lhs!`).
    # It's a dispatch arg, not a URL param, so skip it here.
    saw_verb = false
    for idx in info.indices
        if Meta.isexpr(idx, :parameters)
            has_kwargs = true
        elseif !saw_verb && _is_verb_annotation(idx)
            saw_verb = true
        else
            push!(positional_indices, idx)
        end
    end

    param_strs, n_params, default_positions = _route_param_shape(positional_indices)
    path = _route_path(prefix, name, param_strs)
    _warn_docs_prefix(path, name)

    let name=name, chain=chain, param_strs=param_strs, n_params=n_params, path=path,
        record_dir=record_dir, method=method, default_positions=default_positions,
        has_kwargs=has_kwargs, mount_prefix=mount_prefix, prefix=prefix,
        OwnerT=OwnerT, RouteT=RouteT
        if method == "WEBSOCKET"
            # WS: `@ws feed() = body` is wrapped by `_wrap_ws_bodies!` to a
            # function-returning IP. After Verb injection, the IP signature
            # is `(::Verb{:WEBSOCKET}, url_args…)` so the registered handler
            # threads `Verb{:WEBSOCKET}()` like any other route.
            ws_base = _base_segments(path, n_params)
            ws_root_segs = isempty(mount_prefix) ? 0 :
                           count(==('/'), strip(mount_prefix, '/')) + 1
            ws_verb = Verb{:WEBSOCKET}()
            _register_websocket_handler(path, function(ws, req)
                target = _operation_target(root_provider, OwnerT, chain, req,
                                           mount_prefix, ws_root_segs, :websocket)
                operation = _run_operation(target, RouteT, name, ws_verb,
                                           req, ws_base, n_params)
                operation.value(ws)
            end)
        elseif isempty(param_strs) && has_kwargs
            # kwargs-only route (no path params): mark static for the recorder
            !isnothing(record_dir) && push!(_static_kwargs_paths, path)
            _register_route_handler(OwnerT, RouteT, chain, method, name, path, 0, record_dir;
                                    root_prefix=mount_prefix, record_base, root_provider)
        elseif isempty(param_strs)
            # Zero-arg call form (e.g. `@get index() = ...`)
            _register_route_handler(OwnerT, RouteT, chain, method, name, path, 0, record_dir;
                                    root_prefix=mount_prefix, record_base, root_provider)
        else
            # Register the full route (all params explicit)
            _register_route_handler(OwnerT, RouteT, chain, method, name, path, n_params, record_dir;
                                    root_prefix=mount_prefix, record_base, root_provider)

            # Register shortened routes for trailing defaults
            # e.g. filter(a, b=1, c=2) → also /filter/{a}/{b} and /filter/{a}
            for k in length(default_positions):-1:1
                cut = default_positions[k]  # position of first omitted param
                short_params = param_strs[1:cut-1]
                short_path = _route_path(prefix, name, short_params)
                _register_route_handler(OwnerT, RouteT, chain, method, name, short_path,
                                        length(short_params), record_dir;
                                        root_prefix=mount_prefix, record_base, root_provider)
            end
        end
    end
end

# Detect `::Verb{V}` (with or without `HTMXObjects.` qualifier) on a
# positional arg AST. Used by `_register_one_route` to skip the dispatch arg
# when computing URL params, and by `_inject_verb_in_route_lhs!` for
# idempotency.
function _is_verb_annotation(idx)
    Meta.isexpr(idx, :(::)) || return false
    # Accept both `::Verb{V}` (length 1) and `__verb__::Verb{V}` (length 2);
    # in both cases the annotation type is at args[end].
    ann = idx.args[end]
    Meta.isexpr(ann, :curly) || return false
    head = ann.args[1]
    head === :Verb && return true
    head isa GlobalRef && head.name === :Verb && return true
    Meta.isexpr(head, :.) && length(head.args) == 2 && head.args[2] === QuoteNode(:Verb) && return true
    false
end

# Shared iteration core: walk `meta(IterT)`, skip fixed entries, dispatch
# nested-struct entries to `recurse_nested(name, info, nested_type)` and route
# entries to `register_route(name, info, method)`. Both top-level and included
# registration share this exact body.
#
# `Base.invokelatest` on every `meta(T)` call: during Revise's cascading
# re-eval of multiple files, this function may be re-entered from a caller
# stuck in an older world while a freshly-emitted `meta(::Type{NestedT})`
# lives in the new world. Without invokelatest the dispatch fails with
# `MethodError ... method may be too new`, which HTMXObjects' Revise gate
# then surfaces as a request-blocking `_check_revise_errors!` failure on
# every subsequent route.
function _walk_route_meta(IterT, recurse_nested, register_route)
    for (name, info) in Base.invokelatest(DynamicObjects.meta, IterT)
        DynamicObjects.isfixed(info) && continue

        # Per-entry classification: an HTTP-verb macro on this entry means it's
        # a route. `meta(T)` is a Vector{Pair} since the DO migration and can
        # hold multiple entries under the same key (e.g. `@get index`,
        # `@post index`, and `@include index(x)`), distinguished by
        # `info.macros`. Without this check, a route entry could be
        # misclassified as a nested-include recurse.
        method = nothing
        for (macro_sym, m) in _http_verbs
            macro_sym in info.macros && (method = m; break)
        end
        if !isnothing(method)
            register_route(name, info, method)
            continue
        end

        # Not a route — try nested-include recursion.
        nested_type = _nested_struct_type(IterT, Val(name))
        if !isnothing(nested_type) && !isempty(Base.invokelatest(DynamicObjects.meta, nested_type))
            recurse_nested(name, info, nested_type)
            continue
        end
    end
end

function _register_routes(T; prefix="", record_dir=nothing, record_base::String="",
        parent_chain=Any[], root_provider=get(_root_providers, T, RootProvider()))
    mount_prefix = isempty(prefix) ? "" : "/" * prefix
    _walk_route_meta(T,
        (name, info, nested_type) -> begin
            nested_prefix, step = _nested_prefix_and_step(T, name, info, prefix)
            chain = vcat(parent_chain, [step])
            _register_included_routes(T, nested_type, chain, nested_prefix, record_dir;
                                      root_prefix=mount_prefix, record_base, root_provider)
        end,
        (name, info, method) -> _register_one_route(T, T, Symbol[], prefix,
            mount_prefix, name, info, method, record_dir, record_base, root_provider),
    )
end

# `@include`'d nested route registration goes through `_register_route_handler`
# with a non-empty `chain`. Page-wrapper nesting: for direct browser visits
# (non-HTMX), the response is wrapped by nesting all `__page__` wrappers (or
# legacy `page`) found along the property chain from root to leaf. If the root
# defines `__page__` and a nested struct also defines one, the result is
# `root.__page__(nested.__page__(fragment))` — innermost wraps first, then
# each ancestor.
#
# TODO: add an API to opt out of page nesting for specific structs (e.g. a
# `page_nest=false` property or a `_page_passthrough` convention) for cases
# where a nested struct wants to fully replace the parent's page rather than
# compose with it.
"""
    _page_wrapper(obj) -> wrapper or nothing

Look up the "page" wrapper on `obj`, preferring the framework-managed
`__page__` name over the legacy `page` name. Returns `nothing` if neither is
defined. The legacy `page` name is deprecated — the `@htmx` macro emits a
warning at expansion time when it sees a `page` property (see
`_warn_legacy_page_name!`).
"""
function _page_wrapper(obj)
    hasproperty(obj, :__page__) && return getproperty(obj, :__page__)
    hasproperty(obj, :page)     && return getproperty(obj, :page)
    nothing
end

"""
    _has_page(obj) -> Bool

True if `obj` defines either `__page__` or the legacy `page` property.
"""
_has_page(obj) = hasproperty(obj, :__page__) || hasproperty(obj, :page)

"""
    _req_of(obj) -> HTTP.Request or nothing

Look up the framework-managed request on `obj`. `@htmx` always injects
`__req__` (defaulting to `nothing`) when not user-declared.
"""
_req_of(obj) = hasproperty(obj, :__req__) ? getproperty(obj, :__req__) : nothing

"""
    _collect_page_chain(root, chain) -> Vector

Walk the property chain from `root` and collect objects that define a
`__page__` (or legacy `page`) property. Deduplicates inherited pages: if a
nested struct's page property is inherited from its parent (inline struct),
it is skipped.

Never use `DynamicObjects.meta` to inspect properties — use `hasproperty` and type checks.
"""
# Walk `chain` from `root`, yielding each intermediate object so callers can
# both construct the leaf and inspect intermediate page-bearing structs in a
# single pass. Each step is either a `Symbol` (legacy non-indexed shape) or a
# `NamedTuple{(:name, :types), …}` (indexed-aware shape: `types` lists the
# URL-segment Type per index_param, with `nothing` for untyped). For indexed
# steps the corresponding URL segments after the name segment are extracted
# and converted via `_convert_param`, then threaded into the property call.
function _chain_steps(root, chain::AbstractVector, req::HTTP.Request, root_segs::Int)
    parts = split(split(req.target, "?")[1], "/", keepempty=false)
    cursor = root_segs
    objs = Any[root]
    obj = root
    for step in chain
        name     = step isa Symbol ? step : step.name
        types    = step isa Symbol ? Any[] : step.types
        # `url_name` defaults to `name` for legacy step shapes; new steps
        # (built by `_nested_prefix_and_step`) carry it explicitly. When
        # `url_name === :index`, the URL has no name segment for this step
        # (`_route_path` / `_nested_prefix_and_step` collapse it), so we
        # don't advance the cursor.
        url_name = step isa Symbol ? name :
                   (hasproperty(step, :url_name) ? step.url_name : name)
        url_name === :index || (cursor += 1)
        obj = if isempty(types)
            getproperty(obj, name)
        else
            args = Any[_convert_param(parts[cursor + j], types[j]) for j in 1:length(types)]
            cursor += length(types)
            getproperty(obj, name)(args...)
        end
        push!(objs, obj)
    end
    objs
end

_walk_chain(root, chain, req, root_segs) = last(_chain_steps(root, chain, req, root_segs))

function _collect_page_chain(root, chain, req::HTTP.Request, root_segs::Int)
    pages = Any[]
    objs = _chain_steps(root, chain, req, root_segs)
    for (i, obj) in enumerate(objs)
        _has_page(obj) || continue
        if i > 1
            prev = objs[i - 1]
            prev_type = typeof(prev)
            obj_type = typeof(obj)
            # Skip pages inherited from the parent (same defining type) or
            # from an inline child (type name prefix matches parent's).
            prev_type == obj_type && continue
            startswith(string(nameof(obj_type)), string(nameof(prev_type)) * "_") && continue
        end
        push!(pages, obj)
    end
    pages
end

"""Like `_resolve_response`, but applies nested page wrappers (innermost first, then outward)."""
function _resolve_response_nested(page_chain, req, val; record_dir=nothing, save_path=nothing, record_base::String="")
    # Same finalized-value passthrough as `_resolve_response`. Routes
    # inside `@include`d substructs (e.g. `PipelineRoutes.aov_runtime_js`
    # returning `MIMEResponse("application/javascript", …)`) land here,
    # not in the top-level resolver — without this dispatch the raw body
    # would get wrapped in `__page__` and served with text/html.
    let finalized = _finalized_response(val)
        if !isnothing(finalized)
            if !isnothing(record_dir) && !isnothing(save_path)
                _save_typed_response(record_dir, save_path, finalized)
            end
            return finalized
        end
    end
    if wants_errors(req)
        val = filter_errors(val)
        isnothing(val) && return markdown_response("(no errors)")
    end
    # Same recording policy as `_resolve_response`: markdown / HX-fragment /
    # full-page-wrapped, picked by the request header alone.
    if !isnothing(record_dir) && !isnothing(save_path)
        if wants_markdown(req)
            # Recording skips markdown for values whose type doesn't define
            # `show(::IO, ::MIME"text/markdown", ...)` — `showable` is the
            # explicit check, rather than catching any error from rendering.
            if showable(MIME"text/markdown"(), val)
                save_response(record_dir, "/md" * save_path,
                    HTTP.Response(200, ["Content-Type" => "text/markdown"]; body=to_markdown_string(val));
                    ext=".md")
            end
        elseif is_htmx(req)
            save_response(record_dir, "/hx" * save_path, to_response(static_transform(val; record_base)))
        else
            wrapped = val
            for obj in reverse(page_chain)
                wrapper = _page_wrapper(obj)
                isnothing(wrapper) || (wrapped = wrapper(wrapped))
            end
            save_response(record_dir, save_path, to_response(static_transform(wrapped; record_base)))
        end
    end
    if wants_markdown(req)
        # Use the innermost (last) struct for markdown, if any
        obj = isempty(page_chain) ? nothing : last(page_chain)
        if !isnothing(obj) && hasproperty(obj, :to_markdown)
            return to_response(getproperty(obj, :to_markdown)(val))
        else
            return markdown_response(to_markdown_string(val))
        end
    end
    is_htmx(req) && return to_response(val)
    # Apply page wrappers: innermost (last) wraps first, then each outer one
    for obj in reverse(page_chain)
        wrapper = _page_wrapper(obj)
        isnothing(wrapper) || (val = wrapper(val))
    end
    to_response(val)
end

# Register routes from a nested @include struct with chained property access through the parent.
# `root_prefix` is the parent's mount prefix (with leading "/") — passed verbatim
# to the handler so `ParentT(; __prefix__=root_prefix)` constructs correctly,
# and the parent's `@include` desugar then threads `/<name>` per nesting level.
function _register_included_routes(ParentT, NestedT, chain::Vector, prefix::String,
        record_dir; root_prefix::String="", record_base::String="",
        root_provider=get(_root_providers, ParentT, RootProvider()))
    # Track reverse lookup so _reroute!(NestedT) can trigger parent re-registration
    push!(get!(Set{DataType}, _included_type_parents, NestedT), ParentT)
    _walk_route_meta(NestedT,
        (name, info, nested_type) -> begin
            nested_prefix, step = _nested_prefix_and_step(NestedT, name, info, prefix)
            _register_included_routes(ParentT, nested_type, vcat(chain, [step]),
                nested_prefix, record_dir; root_prefix, record_base, root_provider)
        end,
        (name, info, method) -> _register_one_route(ParentT, NestedT, chain,
            prefix, root_prefix, name, info, method, record_dir, record_base,
            root_provider),
    )
end

# --- Reflection -----------------------------------------------------------
#
# `reflect(T)` returns the route tree of an `@htmx` app as plain data — one
# NamedTuple descriptor per route — for schema-autogen consumers (the
# KB-MCP), docs, and tooling. It MIRRORS the registration walk
# (`_register_routes` → `_walk_route_meta` → `_register_one_route` /
# `_register_included_routes`) so the reported `path`/`verb` match what
# `route!` actually registers — but collects descriptors instead of
# registering handlers. Plain NamedTuples (not new structs) keep it
# Revise-friendly and trivially JSON-serializable.
#
# Route descriptor:  (verb::Symbol, path::String, name::Symbol,
#                     doc::Union{String,Nothing}, params::Vector{NamedTuple})
# Param descriptor:  (name::Symbol, source::Symbol, type, required::Bool,
#                     default, doc::Union{String,Nothing}, inherited::Bool)
#   source ∈ :path | :query | :body   (where the value is read);
#   inherited=true marks a `@param` reaching this route from an ancestor
#   struct (auto-threaded into nested @include children, or an explicit
#   `@param (;x)=__parent__` delegation) — its type/required/default are
#   resolved from the nearest ancestor that declares it locally.

# Normalize a raw doc value from info.doc (AbstractString, Expr, or nothing)
# to Union{String,Nothing}. Interpolated Expr docs degrade gracefully to nothing.
_normalize_doc(::Nothing) = nothing
_normalize_doc(d::AbstractString) = isempty(strip(d)) ? nothing : string(d)
_normalize_doc(d) = nothing  # Expr (:string with interpolation) — skip initial cut

# Read the per-declaration docstring from an `info` NamedTuple defensively —
# `get` with default so reflect never crashes against a DO version that hasn't
# added the `doc` field yet (degrades to doc=nothing until DO's change lands).
_decl_doc(info) = _normalize_doc(get(info, :doc, nothing))

# Parse a Julia `# Arguments` section from a docstring into a name→description
# map. Lines matching `- \`name\`: description` under a `# Arguments` header
# are collected; the section ends at the next `#`-header. Names not in the
# route sig are ignored; sig args absent from the section get doc=nothing.
function _parse_arguments_section(doc::AbstractString)
    result = Dict{Symbol,String}()
    in_args = false
    for line in split(doc, '\n')
        stripped = strip(line)
        if stripped == "# Arguments"
            in_args = true
            continue
        end
        if in_args
            !isempty(stripped) && startswith(stripped, "#") && break
            m = match(r"^-\s+`(\w+)`:\s+(.+)$", stripped)
            m === nothing && continue
            result[Symbol(m.captures[1])] = String(strip(m.captures[2]))
        end
    end
    result
end

_reflect_resolve_type(_mod, ::Nothing) = nothing
function _reflect_resolve_type(mod, ty)
    ty === :nothing && return nothing
    # Unresolvable annotation ⇒ `nothing` (consumers map it to String),
    # matching DO `property_signature`'s type contract. Serves the @param path;
    # the call-sig path resolves via DO directly (see `_reflect_call_params`).
    try Core.eval(mod, ty) catch; nothing end
end

# Source bucket for request-parsed params by HTTP method — mirrors the
# query-vs-body split in `_generate_extract_args` / `_kwargs_source`.
_reflect_kw_source(method) = method in ("GET", "DELETE", "WEBSOCKET") ? :query : :body

# Split a route's call signature into (path_params, kwargs) via DO's
# `property_signature(info, mod)` — the canonical AST→structured parser
# (decision 1t1vfwh). We pass the per-route, verb-specific `info` that
# `_walk_route_meta` hands us, so multi-verb same-name routes
# (`@get user(id)` + `@post user(; …)`) each keep their own signature — the
# `(T, prop)` form would collapse them via `metafirst` (first-decl-wins). The
# `(info, mod)` form never returns `nothing` (empty indices → empty lists), but
# we guard anyway. Positionals become path params (skipping the injected
# `__verb__::Verb{V}`, filtered by name per DO's verb-agnostic contract);
# kwargs read from query/body by method. `type` is a resolved `Type` (or
# `nothing`); `default` is meaningful only when `!required`.
function _reflect_call_params(OwnerT, info, method, arg_docs=Dict{Symbol,String}())
    sig = Base.invokelatest(DynamicObjects.property_signature, info, parentmodule(OwnerT))
    kwsrc = _reflect_kw_source(method)
    path_params = NamedTuple[]
    kwargs = NamedTuple[]
    sig === nothing && return (path_params, kwargs)
    mk = (p, source) -> (name=p.name, source=source, type=p.type, required=p.required,
                         default=(p.required ? nothing : p.default),
                         doc=get(arg_docs, p.name, nothing), inherited=false)
    for p in sig.positional
        p.name === :__verb__ && continue
        push!(path_params, mk(p, :path))
    end
    for p in sig.kwargs
        push!(kwargs, mk(p, kwsrc))
    end
    (path_params, kwargs)
end

# Parse a LOCAL `@param` on `T` into (type, required, default), or `nothing`
# if `nm` is absent or only reaches `T` by inheritance/delegation. A local
# `@param`'s emitted RHS is `_extract_param(req, :name, T[, default])` —
# arity-4 (no default) ⇒ required, arity-5 ⇒ has default.
function _reflect_local_param(T, nm)
    info = Base.invokelatest(DynamicObjects.metafirst, T, nm)
    info === nothing && return nothing
    rhs = info.rhs
    if Meta.isexpr(rhs, :call) && length(rhs.args) >= 4 && rhs.args[1] === _extract_param
        has_default = length(rhs.args) >= 5
        return (type=_reflect_resolve_type(parentmodule(T), rhs.args[4]),
                required=!has_default, default=has_default ? rhs.args[5] : nothing,
                doc=_decl_doc(info))
    end
    nothing
end

# Build param descriptors for every `@param` of `OwnerT` (`_param_names`
# includes names inherited from ancestors). A locally-declared param is read
# straight off `OwnerT`; an inherited/delegated one is resolved from the
# nearest ancestor in `parent_stack` that declares it locally. `source` is the
# read-location (query/body by method); `inherited` carries the provenance.
function _reflect_param_props(OwnerT, method, parent_stack)
    src = _reflect_kw_source(method)
    out = NamedTuple[]
    for nm in Base.invokelatest(_param_names, OwnerT)
        loc = _reflect_local_param(OwnerT, nm)
        inherited = loc === nothing
        if inherited
            for anc in Iterators.reverse(parent_stack)
                loc = _reflect_local_param(anc, nm)
                loc === nothing || break
            end
        end
        if loc === nothing
            push!(out, (name=nm, source=src, type=nothing, required=false,
                        default=nothing, doc=nothing, inherited=inherited))
        else
            push!(out, (name=nm, source=src, type=loc.type, required=loc.required,
                        default=loc.default, doc=loc.doc, inherited=inherited))
        end
    end
    out
end

function _reflect_walk!(acc, IterT, prefix, parent_stack=Any[])
    _walk_route_meta(IterT,
        (name, info, nested_type) -> begin
            nested_prefix, _step = _nested_prefix_and_step(IterT, name, info, prefix)
            _reflect_walk!(acc, nested_type, nested_prefix, push!(copy(parent_stack), IterT))
        end,
        (name, info, method) -> begin
            route_doc = _decl_doc(info)
            arg_docs = isnothing(route_doc) ? Dict{Symbol,String}() :
                       _parse_arguments_section(route_doc)
            path_params, kwargs = _reflect_call_params(IterT, info, method, arg_docs)
            param_strs = [string(p.name) for p in path_params]
            path = _route_path(prefix, name, param_strs)
            params = vcat(path_params, kwargs, _reflect_param_props(IterT, method, parent_stack))
            push!(acc, (verb=Symbol(method), path=path, name=name, doc=route_doc, params=params))
        end)
end

"""
    reflect(::Type{T}) -> Vector{NamedTuple}

Reflect the route tree of an `@htmx` app type `T` into plain data — one
descriptor per route, with `verb`, mount-resolved `path`, `name`, `doc`, and
`params`. Each param carries `name`, `source` (`:path`/`:query`/`:body`),
resolved `type`, `required`, `default`, `doc`, and `inherited`. The single
ergonomic entry point for schema-autogen
(the KB-MCP), docs, and tooling; mirrors the registration walk so paths/verbs
match what `route!` registers.
"""
function reflect(::Type{T}) where {T}
    hasmethod(DynamicObjects.meta, Tuple{Type{T}}) || return NamedTuple[]
    acc = NamedTuple[]
    _reflect_walk!(acc, T, "")
    acc
end

"""
    route!(app; prefix="", record_dir=nothing, record_base="", root_provider=nothing)

Register every `@get`/`@post`/`@put`/`@patch`/`@delete`/`@ws` route declared on
`app`'s `@htmx struct` (and all transitively-`@include`d sub-structs) with the
Oxygen router. Returns `app`.

- `prefix` — mount the entire app under a URL prefix (e.g. `prefix="api"` puts
  the root route at `/api/`). Default: root (`""`).
- `record_dir` — if set, every served response is also persisted to disk via
  [`save_response`](@ref) under that directory; intended for static export.
- `record_base` — URL prefix to strip from saved file paths when `record_dir`
  is set (for deploying to a non-root subpath).
- `root_provider` — a [`RootProvider`](@ref), or a callable
  `factory(RootT, context)`, used by both HTTP and WebSocket operations.
  `nothing` preserves the historic fresh-root-per-request behavior.

`route!` stores its registration settings per type in internal registries so the
`_reroute!` hook emitted by `@htmx` can re-register routes on Revise reloads —
**you do not need to call `route!` again after editing a route body**.
"""
function route!(obj; prefix="", record_dir=nothing, record_base="", root_provider=nothing)
    T = typeof(obj)
    provider = _normalize_root_provider(root_provider)
    _registered_types[T] = (; prefix, record_dir)
    _record_bases[T] = record_base
    _root_providers[T] = provider
    !isnothing(record_dir) && empty!(_static_kwargs_paths)
    _register_routes(T; prefix, record_dir, record_base, root_provider=provider)
    obj
end

"""
    record!(app; record_dir, record_base="", paths=["/"], full=true, hx=true, markdown=true)

Drive each path through the in-process route handler with one or more
header sets, writing recordings under `record_dir`. No subprocess, no
HTTP listener — looks each path up via `HTTP.Handlers.gethandler` on
`CONTEXT[].service.router` and invokes the handler with a manufactured
`HTTP.Request`. The handler's existing save logic in `_resolve_response`
writes the appropriate file shape.

Each path is hit once per enabled variant:

  * `full=true`     — plain GET. Saves the page-wrapped HTML at `<record_dir>/<path>.html`.
  * `hx=true`       — `HX-Request: true`. Saves the body fragment at `<record_dir>/hx/<path>.html`.
  * `markdown=true` — `Accept: text/markdown`. Saves the markdown view at `<record_dir>/md/<path>.md` (only if the route's `to_markdown_string(val)` succeeds; otherwise skipped).

Calls `route!(app; record_dir, record_base)` first to register the
handlers with the recording config. Returns `app`.

Use this in place of the subprocess+HTTP recorder when you can drive an
app from the same Julia process — much faster (no port, no warmup) and
deterministic in CI.
"""
function record!(app;
        record_dir::String,
        record_base::String="",
        paths::AbstractVector{<:AbstractString}=String["/"],
        full::Bool=true,
        hx::Bool=true,
        markdown::Bool=true,
    )
    route!(app; record_dir, record_base)
    isdir(record_dir) || mkpath(record_dir)
    router = CONTEXT[].service.router
    for path in paths
        full     && _drive_record_path(router, String(path), Pair{String,String}[])
        hx       && _drive_record_path(router, String(path), ["HX-Request" => "true"])
        markdown && _drive_record_path(router, String(path), ["Accept" => "text/markdown"])
    end
    app
end

# In-process equivalent of an HTTP request: locate the registered handler
# in the router's trie, invoke it with a synthesized Request. The
# handler's normal save_response side effects still run.
function _drive_record_path(router, path::AbstractString, headers)
    req = HTTP.Request("GET", path, headers, UInt8[])
    found = HTTP.Handlers.gethandler(router, req)
    handler = first(found)
    if handler === HTTP.Handlers.default404 || handler === nothing
        @warn "record!: no route registered" path
        return
    end
    handler(req)
end

# Recording shims. Implementation is held in mutable `Ref`s so the
# Treebars extension can swap them in at `__init__` time without
# triggering Julia's "method overwriting during precompile" rule
# (which forbids redefining same-signature methods across the core
# and an extension). Without the ext: each shim no-ops or runs
# synchronously — the route returns the summary article in one go.
# With the ext loaded: each Ref points at a `Treebars.*` call, so
# the route renders a live `polling_fetchindex` tree while recording
# runs.  The actual `RecordingState` / `RecordingRoutes` definitions
# live below `_reroute!` because the `@htmx` macro interpolates
# `_reroute!` at expansion time.
const _recording_progress_init_impl  = Ref{Any}(() -> nothing)
const _recording_progress_phase_impl = Ref{Any}((parent, description) -> nothing)
const _recording_run_phase_impl      = Ref{Any}((f, phase) -> f(phase))
const _recording_polling_impl        = Ref{Any}(
    (render_result, ip, indices...; poll_url=nothing, label=nothing,
        force::Bool=false, poll_interval=nothing, cancel_url=nothing, kwargs...) ->
        render_result(ip(indices...; kwargs...))
)

_recording_progress_init()  = _recording_progress_init_impl[]()
_recording_progress_phase(parent, description::AbstractString) =
    _recording_progress_phase_impl[](parent, description)
_recording_run_phase(f, phase) = _recording_run_phase_impl[](f, phase)
_recording_polling(args...; kwargs...) = _recording_polling_impl[](args...; kwargs...)

# Called by @htmx macro expansion — re-registers routes when Revise updates the struct
function _reroute!(T::DataType)
    if haskey(_registered_types, T)
        args = _registered_types[T]
        _register_routes(T; args.prefix, args.record_dir,
            record_base=get(_record_bases, T, ""),
            root_provider=get(_root_providers, T, RootProvider()))
    end
    # If T is an @include'd sub-struct, re-register its parent(s)
    if haskey(_included_type_parents, T)
        for ParentT in _included_type_parents[T]
            haskey(_registered_types, ParentT) || continue
            args = _registered_types[ParentT]
            _register_routes(ParentT; args.prefix, args.record_dir,
                record_base=get(_record_bases, ParentT, ""),
                root_provider=get(_root_providers, ParentT, RootProvider()))
        end
    end
end

# Re-register every previously registered root type. Top-level so Revise
# evaluates it as a new expression once; on initial load the dict is empty
# (no-op). On running servers, this rebuilds all route handler closures
# after a HTMXObjects refactor that invalidates the captured ones (e.g.
# the `_register_indexed_route` / `_register_included_handler` →
# `_register_route_handler` unification). `HTTP.register!` is idempotent
# (overwrites), so re-running this on initial load too is harmless.
for T in collect(keys(_registered_types))
    _reroute!(T)
end

include("routes/recording_routes.jl")

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
    @get index() = htmx(h.main(
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

# --- Plain/rich response helpers ---

"""
    wants_markdown(req::HTTP.Request) -> Bool

Return `true` if the client wants a markdown response (for LLM/CLI consumption).
Checks for `Accept: text/markdown` or `text/plain` header, or a `?plain` / `?markdown`
query parameter.
"""
wants_markdown(req::HTTP.Request) = let accept = HTTP.header(req, "Accept", ""), qp = queryparams(req)
    contains(accept, "text/markdown") || contains(accept, "text/plain") ||
    haskey(qp, "markdown") || haskey(qp, "plain")
end

"""
    wants_errors(req::HTTP.Request) -> Bool

Return `true` if the client wants only error-tagged elements (via `?error` query parameter).
"""
wants_errors(req::HTTP.Request) = haskey(queryparams(req), "error")

"""
    e

Error-tagged HTML builder. Works exactly like `h`, but adds `data-error="true"` to
every element. Elements with this attribute survive the `?error` filter.

    e.div(id="foo")("content")  # <div id="foo" data-error="true">content</div>
    e.span("error!")             # <span data-error="true">error!</span>
"""
e(tag, args...; kwargs...) = h(tag, args...; data_error="true", kwargs...)
Base.getproperty(::typeof(e), tag::Symbol) = (args...; kwargs...) -> e(tag, args...; kwargs...)

"""
    filter_errors(val)

Walk a Node tree and keep only nodes that have `data-error="true"` or contain
a descendant with `data-error="true"`. Non-error branches are removed.
Non-Node values pass through unchanged.
"""
filter_errors(val) = val
filter_errors(val::AbstractArray) = filter(!isnothing, filter_errors.(val))
filter_errors(val::Tuple) = filter(!isnothing, filter_errors.(val))
# For child-walking inside filter_errors(::Node): keep error-bearing Nodes,
# drop everything else (text, primitives) so non-error subtrees prune away.
_filter_errors_child(_) = nothing
_filter_errors_child(child::Node) = filter_errors(child)
filter_errors((content, id)::Pair) = let filtered = filter_errors(content)
    isnothing(filtered) ? nothing : filtered => id
end

function _has_error_attr(node::Node)
    get(HTMX.attrs(node), Symbol("data-error"), nothing) == "true"
end
_has_error_attr(::Any) = false

function filter_errors(node::Node)
    # If this node is an error node, keep it entirely
    _has_error_attr(node) && return node

    # Otherwise, recurse into children and keep only error-containing branches
    new_children = []
    for child in HTMX.children(node)
        filtered = _filter_errors_child(child)
        !isnothing(filtered) && push!(new_children, filtered)
        # Drop non-Node children (text) in non-error nodes
    end

    # If no error children survived, prune this branch
    isempty(new_children) && return nothing

    # Keep this node as a structural wrapper with only error children
    Node(HTMX.tag(node), copy(HTMX.attrs(node)), new_children)
end

# Interactive elements counted as "chrome" and dropped from markdown output.
# Dropping the node drops its whole subtree, so children of a `<form>` go with
# it; standalone `<button>`/`<input>`/`<textarea>` are dropped wherever they
# appear (form-wrapped or not). Extend this set (e.g. select/option/label) only
# via the open design decisions — see the markdown-read contract in `htmxo-use`.
const _MD_CHROME_TAGS = Set{Symbol}((:form, :input, :textarea, :button))

_is_md_chrome(tag) = Symbol(lowercase(string(tag))) in _MD_CHROME_TAGS

"""
    _strip_md_chrome(val)

Walk a Node tree and DROP interactive-chrome nodes (`_MD_CHROME_TAGS`:
`<form>` / `<input>` / `<textarea>` / `<button>`) entirely — node and subtree —
so they emit nothing into markdown. Everything else (prose, headings, links,
tables, non-chrome structure, and ALL text) is preserved. Non-Node values pass
through unchanged; a value that is itself all-chrome strips to `nothing`.

Applied automatically by [`to_markdown_string`](@ref) so every
`?plain` / `?markdown` / `Accept: text/markdown` read drops form chrome with no
consumer annotation — the automatic counterpart to [`html_only`](@ref), which
is the explicit per-node opt-out for other HTML-only content.
"""
_strip_md_chrome(val) = val
_strip_md_chrome(val::AbstractArray) = filter(!isnothing, _strip_md_chrome.(val))
_strip_md_chrome(val::Tuple) = filter(!isnothing, _strip_md_chrome.(val))
_strip_md_chrome((content, id)::Pair) = let f = _strip_md_chrome(content)
    isnothing(f) ? nothing : f => id
end

# Re-insertable child: a surviving Node passes through; a chrome Node → nothing
# (dropped). Unlike filter_errors (which prunes non-error text), text / primitive
# children are KEPT as-is so non-chrome prose survives.
_strip_md_chrome_child(child) = child
_strip_md_chrome_child(child::Node) = _strip_md_chrome(child)

function _strip_md_chrome(node::Node)
    _is_md_chrome(HTMX.tag(node)) && return nothing
    new_children = []
    for child in HTMX.children(node)
        kept = _strip_md_chrome_child(child)
        isnothing(kept) || push!(new_children, kept)
    end
    Node(HTMX.tag(node), copy(HTMX.attrs(node)), new_children)
end

"""
    markdown_response(text) -> HTTP.Response

Create a `text/markdown` HTTP response from a string.
"""
markdown_response(text) = HTTP.Response(200, ["Content-Type" => "text/markdown; charset=utf-8"], body=text)

# --- Captions ---

"""
    CaptionSpec(; title, short="", long=nothing)

Caption metadata for a figure or table. `title` is a short bold heading,
`short` is a one-line summary (typically built from live state so every
parameter is visible), and `long` is an optional longer description shown
behind a `<details>` toggle inside the `<figcaption>`.

`long` may be a `String` or any HTMX `Node` (e.g. `h.div(h.p(...), h.p(...))`).
"""
struct CaptionSpec
    title::String
    short::String
    long::Any
end
CaptionSpec(; title, short="", long=nothing) = CaptionSpec(title, short, long)

"""
    caption_style()

Return a `<style>` node with default CSS for `render_caption` / `with_caption`:
flex layout for the caption header (title left, actions right) and small
spacing for the `<details>` body. Include once per page.
"""
caption_style() = h.style(Raw("""
@layer htmxo {
figure.captioned { margin: 0 0 1rem 0; }
figcaption.caption { margin-bottom: 0.5rem; }
.caption-header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; }
.caption-actions { display: inline-flex; gap: 0.25rem; flex-shrink: 0; }
.caption-action { padding: 0.1rem 0.5rem; font-size: 0.85em; margin: 0; }
.caption-long { margin-top: 0.25rem; }
.caption-long > summary { cursor: pointer; font-size: 0.9em; opacity: 0.75; }
}
"""))

_wrap_long(s::AbstractString) = h.div(s)
_wrap_long(s) = s

"""
    render_caption(spec::CaptionSpec; actions=())

Return a `<figcaption>` node for `spec`. `actions` is an iterable of nodes
(buttons, links, …) rendered on the right side of the caption header.

Use `with_caption(spec, content; actions)` to wrap content in a `<figure>` —
this function returns just the `<figcaption>` so it can be embedded in a
custom layout if needed.
"""
function render_caption(spec::CaptionSpec; actions=())
    header_kids = Any[h.span(h.strong(spec.title), isempty(spec.short) ? "" : " — ", spec.short)]
    if !isempty(actions)
        push!(header_kids, h.span(; class="caption-actions")(actions...))
    end
    header = h.div(; class="caption-header")(header_kids...)
    body = isnothing(spec.long) ? "" :
        h.details(; class="caption-long")(
            h.summary("More"),
            _wrap_long(spec.long),
        )
    h.figcaption(; class="caption")(header, body)
end

_as_children(content) = (content,)
_as_children(content::Tuple) = content
_as_children(content::AbstractVector) = content

"""
    with_caption(spec::CaptionSpec, content; actions=())

Wrap `content` (a single node or iterable of nodes) in a `<figure>` with the
caption rendered above it. Pass `actions` (e.g. download buttons) to populate
the right side of the caption header.
"""
function with_caption(spec::CaptionSpec, content; actions=(), id=nothing)
    fig_attrs = isnothing(id) ? (; class="captioned") : (; class="captioned", id)
    h.figure(; fig_attrs...)(render_caption(spec; actions), _as_children(content)...)
end

# --- Table rendering ---

# Normalise a `default_sort` direction to the `data-sort-dir` token.
function _sort_dir_token(dir)
    d = Symbol(lowercase(string(dir)))
    d in (:asc, :ascending) && return "asc"
    d in (:desc, :descending) && return "desc"
    error("sortable_table: default_sort direction must be :asc or :desc, got $(repr(dir))")
end

# Resolve `default_sort` to a `(1-based column index, "asc"|"desc")` pair.
# Accepts `col`, `col => dir`, where `col` is a 1-based `Integer` or a header
# label matching one of the `String` headers.
function _resolve_default_sort(default_sort, headers)
    isnothing(default_sort) && return nothing
    col, dir = default_sort isa Pair ?
        (first(default_sort), last(default_sort)) : (default_sort, :asc)
    idx = if col isa Integer
        Int(col)
    else
        label = string(col)
        found = findfirst(hdr -> hdr isa AbstractString && string(hdr) == label, headers)
        isnothing(found) && error(
            "sortable_table: default_sort column $(repr(label)) does not match any String header")
        found
    end
    1 <= idx <= length(headers) || error(
        "sortable_table: default_sort column index $idx out of range 1:$(length(headers))")
    headers[idx] isa AbstractString || error(
        "sortable_table: default_sort column $idx is a pre-built header node. Only " *
        "auto-wired String headers can be stamped; wire the marker yourself with " *
        "`data_sort_dir=` + `aria_sort=` if the header is a custom node.")
    (idx, _sort_dir_token(dir))
end

# Build one auto-wired sortable `<th>` (1-based column `i`). When `ds = (idx,
# dir)` names this column, stamp exactly what `sortTable` sets client-side:
# `data-sort-dir`, `aria-sort`, and the trailing caret `<span>`. That makes a
# `morph:` swap re-impose the sorted state rather than wipe it, keeps the caret
# consistent with the rows the server actually emitted, and lets the next click
# toggle from the right direction (`sortTable` reads `data-sort-dir`).
function _sortable_th(label, i, ds)
    onclick = "sortTable($(i-1), this)"
    if !isnothing(ds) && first(ds) == i
        dir = last(ds)
        h.th(label, h.span(dir == "asc" ? " ▲" : " ▼"; class="htmxo-sort-caret");
            onclick, class="u-pointer", data_sort_dir=dir,
            aria_sort=(dir == "asc" ? "ascending" : "descending"))
    else
        h.th(label; onclick, class="u-pointer")
    end
end

"""
    sortable_table_js()

Return an `h.script(...)` node containing the `sortTable` and `htmxoSortState`
JavaScript functions for click-to-sort table headers. Include this once per
page (e.g. in `extra_head`).

The JS finds the `<tbody>` relative to the clicked header (no hardcoded ID),
so multiple sortable tables can coexist on the same page. Numeric values are
sorted numerically; everything else uses `localeCompare`.

# Sort state — the public read surface
`sortTable` marks the active `<th>` with **both** `data-sort-dir="asc"|"desc"`
and `aria-sort="ascending"|"descending"`, and clears both from every sibling
`<th>`. Read that state with:

    htmxoSortState(target) -> {sort_col, sort_dir} | {}

`target` is a CSS selector or element; `sort_col` is **1-based** (matching
`default_sort`), `sort_dir` is `"asc"`/`"desc"`. An unsorted table yields `{}`.

# Sort state vs. `morph:` swaps
An idiomorph `hx-swap="morph:*"` syncs attributes against the server's HTML and
removes any the server did not render — so a client-set sort marker **and the
row order** are wiped by the next morph that covers the `<thead>`/`<tbody>`.
To make a user's sort survive a morph, send the state out with the request and
have the server render rows in that order:

```julia
h.button("↻"; hx_get=string(__self__),
    hx_vals="js:{...htmxoSortState('#entries')}",
    hx_target="#entries", hx_swap="morph:outerHTML")
```

then render with `sortable_table(rows...; default_sort=sort_col => sort_dir)`
so the server-rendered header agrees with the server-rendered row order.
See [`sortable_table`](@ref).
"""
function sortable_table_js()
    h.script(Raw(raw"""
function sortTable(col, th) {
    // Accept sortTable(th): with a single <th> element, derive the column
    // index from its position in the header row. Lets a hand-built RICH header
    // (one holding a button/link — which can't be a plain auto-wired String
    // header) opt into sorting WITHOUT hardcoding its column index. Legacy
    // sortTable(col, th) (col a number) is unchanged.
    if (th === undefined && col && col.nodeType === 1) {
        th = col;
        col = Array.prototype.indexOf.call(th.parentNode.children, th);
    }
    const tbody = th.closest('table').querySelector('tbody');
    // Paired-row pattern: a sortable row may carry a sibling row whose id
    // starts with "detail-" instead of "row-" (or any custom prefix → the
    // companion's id mirrors it). We sort only the primary rows and keep
    // each detail row pinned to its parent. Rows without an id are treated
    // as primary too. Skip primaries whose first cell is empty (sub-headers).
    // `:scope > tr` keeps inner tables (e.g. a markdown table inside a
    // detail row) from being treated as primaries.
    const all = Array.from(tbody.querySelectorAll(':scope > tr'));
    const isCompanion = r => r.id && r.id.startsWith('detail-');
    const primaries = all.filter(r => !isCompanion(r) && r.cells.length > col);
    const companionFor = r => {
        if (!r.id) return null;
        const idx = r.id.indexOf('-');
        if (idx < 0) return null;
        // Pair via an attribute selector, NOT `#detail-<key>`: row keys can
        // contain `:` (e.g. agent ids like `Claude:agents2`) or start with a
        // digit (timestamp slugs), both of which are illegal in a `#id`
        // selector and would throw. `[id="..."]` sidesteps CSS-identifier
        // rules; our keys never contain `"`.
        return tbody.querySelector(':scope > [id="detail-' + r.id.slice(idx + 1) + '"]');
    };
    const asc = th.dataset.sortDir !== 'asc';
    th.dataset.sortDir = asc ? 'asc' : 'desc';
    // `aria-sort` mirrors `data-sort-dir` on the active <th>: it is the
    // standard accessible marker, and it is what `sortable_table`'s
    // `default_sort=` stamps server-side. Exactly one <th> per header row
    // carries either attribute — clear both from the siblings.
    th.setAttribute('aria-sort', asc ? 'ascending' : 'descending');
    th.closest('tr').querySelectorAll('th').forEach(h => {
        if (h !== th) { delete h.dataset.sortDir; h.removeAttribute('aria-sort'); }
    });
    // Sort key: prefer `data-sort-value` if the cell sets one, else the
    // visible text. This lets callers force a semantic order (e.g. status:
    // proposed → approved → rejected) without re-encoding the displayed text.
    const sortKey = cell => (cell.dataset.sortValue ?? cell.textContent).trim();
    primaries.sort((a, b) => {
        const av = sortKey(a.cells[col]);
        const bv = sortKey(b.cells[col]);
        const an = parseFloat(av), bn = parseFloat(bv);
        if (!isNaN(an) && !isNaN(bn)) return asc ? an - bn : bn - an;
        return asc ? av.localeCompare(bv) : bv.localeCompare(av);
    });
    primaries.forEach(r => {
        tbody.appendChild(r);
        const c = companionFor(r);
        if (c) tbody.appendChild(c);
    });
    // Sort caret in a dedicated trailing <span> per <th>: the old approach
    // assigned th.textContent, which flattens EVERY child node to a text node,
    // so sorting any column destroyed interactive content living in a header
    // (a batch-action button, a link — e.g. the KB agents table's Model ⟳
    // refresh and its bulk ↻/⏸/▶/🗑 buttons both went inert after a sort).
    // Managing a caret span leaves rich header content untouched.
    th.closest('tr').querySelectorAll('th').forEach(h => {
        const oldCaret = h.querySelector(':scope > .htmxo-sort-caret');
        if (oldCaret) oldCaret.remove();
    });
    const caret = document.createElement('span');
    caret.className = 'htmxo-sort-caret';
    caret.textContent = asc ? ' ▲' : ' ▼';
    th.appendChild(caret);
}

// Read a table's CURRENT client-side sort state. `target` is a CSS selector
// or an element (the <table>, or any node inside or around it). Returns
// {sort_col, sort_dir} — 1-based column index, 'asc'|'desc' — or {} when the
// table is unsorted, so it spreads cleanly into an htmx hx-vals:
//
//     hx-vals="js:{...htmxoSortState('#my-table')}"
//
// Read it BEFORE the swap, not after. A `morph:*` (idiomorph) swap syncs
// attributes against the server's HTML and REMOVES any the server did not
// render — so the client-set `data-sort-dir` / `aria-sort` and the caret
// span are all gone once the morph lands, and the server's child order is
// re-imposed on the rows. Ride the state out with the request, render the
// rows in that order, and stamp it back with
// `sortable_table(...; default_sort=col => dir)`.
function htmxoSortState(target) {
    const root = typeof target === 'string' ? document.querySelector(target) : target;
    if (!root) return {};
    const table = root.tagName === 'TABLE' ? root
        : (root.querySelector('table') || root.closest('table'));
    if (!table) return {};
    const th = table.querySelector('thead th[data-sort-dir]');
    if (!th) return {};
    return {
        sort_col: Array.prototype.indexOf.call(th.parentNode.children, th) + 1,
        sort_dir: th.dataset.sortDir,
    };
}
"""))
end

"""
    sortable_table_styles()

Return an `h.style(...)` node with the canonical CSS for tables marked
`class="htmxo-sortable-table"`: every `<th>` gets `cursor: pointer` (sortable
by default), and any `<th>` with a `colspan` (i.e. a group span over multiple
columns) opts out and centres its text.

Also covers the master/detail paired-row pattern (`tr#row-<key>` +
`tr#detail-<key>`): primary-row hover highlight, master-row cursor when the
row carries an `onclick`, and a padding/border reset on the detail cell.
These rules are intentionally **outside any `@layer`** — Pico styles `<tr>`
and `<td>` unlayered and an unlayered rule beats any `@layer`-ed rule
regardless of specificity (htmxo-semantic-styling cracked pattern 9), so
wrapping them in `@layer htmxo` would leave them ineffective against
Pico's defaults. Pair with [`sortable_table_js`](@ref).
"""
function sortable_table_styles()
    h.style(Raw("""
@layer htmxo {
.htmxo-sortable-table thead th { cursor: pointer; }
.htmxo-sortable-table thead th[colspan] { cursor: default; text-align: center; border-bottom: none; }
/* Body cells with a hyperscript handler are clickable too (htmx-attr cells
   already get cursor:pointer from the global rule in htmxo_utility_styles). */
.htmxo-sortable-table tbody td[_] { cursor: pointer; }
}
/* Master/detail paired-row rules — INTENTIONALLY UNLAYERED so they beat
   Pico's unlayered tr/td defaults. The sortable_table_js convention pairs
   a primary row `tr#row-<key>` with a hidden detail row `tr#detail-<key>`. */
.htmxo-sortable-table tbody tr[id^="row-"]:hover {
    background: var(--pico-table-row-stripped-background-color);
}
.htmxo-sortable-table tbody tr[id^="row-"][onclick] > td { cursor: pointer; }
.htmxo-sortable-table tbody tr[id^="detail-"] > td { padding: 0; border: none; }
"""))
end

"""
    download_table_js()

Return an `h.script(...)` node containing the `downloadTableCsv` JavaScript function
used by `render_table(...; download=true)`. Include this once per page (e.g. in `extra_head`).

The JS reads the closest `<table>` relative to the clicked button, serializes the
visible header cells and body rows to CSV (escaping `"`, `,`, and newlines), and
triggers a Blob download. Sort indicator arrows (` ▲`/` ▼`) added by
`sortable_table_js()` are stripped from header text.
"""
function download_table_js()
    h.script(Raw(raw"""
function downloadTableCsv(btn, filename) {
    const wrap = btn.closest('figure, .table-wrap') || btn.parentElement;
    const table = wrap.querySelector('table');
    const esc = s => {
        s = String(s);
        return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    const headers = Array.from(table.querySelectorAll('thead th'))
        .map(th => esc(th.textContent.replace(/ [▲▼]$/, '').trim()));
    const rows = Array.from(table.querySelectorAll('tbody tr'))
        .filter(tr => !(tr.id && tr.id.startsWith('detail-')))
        .map(tr =>
            Array.from(tr.cells).map(td => esc(td.textContent.trim())).join(','));
    const csv = [headers.join(','), ...rows].join('\n');
    const blob = new Blob([csv], {type: 'text/csv;charset=utf-8;'});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename || 'table.csv';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}
"""))
end

"""
    render_table(table; id=nothing, sortable=true, download=true, download_filename=nothing, caption=nothing, cell=nothing, class="striped", kwargs...)

Render any Tables.jl-compatible table (DataFrame, NamedTuple of vectors, etc.)
as an `h.table` HTML node.

# Keyword arguments
- `id`: tbody element id (auto-generated if `nothing`)
- `sortable`: add click-to-sort headers (default `true`; requires `sortable_table_js()` on the page)
- `download`: add a "⬇ CSV" button (default `true`; requires `download_table_js()` on the page).
  Placed in the caption header when `caption` is given, otherwise above the table.
- `download_filename`: filename for the CSV download (default: `id * ".csv"`)
- `caption`: a `CaptionSpec` to render above the table inside a `<figure>`
- `cell(value, column_name, row_index)`: custom cell renderer (default: `string(value)`)
- `class`: table CSS class (default `"striped"`)
- Extra kwargs are forwarded to `h.table()`

# Example
```julia
df = DataFrame(name=["Alice", "Bob"], score=[95, 87])
cap = CaptionSpec(; title="Scores", short="Ranked test scores.", long="Data collected 2026-Q1.")
page = htmx(
    h.body(
        render_table(df; download=true, caption=cap),
        sortable_table_js(), download_table_js()
    );
    pico_version="2"
)
```
"""
function render_table(table; id=nothing, sortable=true, download=true, download_filename=nothing, caption=nothing, cell=nothing, class="striped", kwargs...)
    cols = Tables.columnnames(Tables.columns(table))
    isnothing(id) && (id = "tbl-" * string(hash(cols), base=16))

    body_rows = [
        h.tr([h.td(isnothing(cell) ? string(Tables.getcolumn(row, c)) : cell(Tables.getcolumn(row, c), c, ri))
              for c in cols]...)
        for (ri, row) in enumerate(Tables.rows(table))
    ]

    sortable_table([string(c) for c in cols], body_rows;
        id, sortable, download, download_filename, caption, class, kwargs...)
end

"""
    sortable_table(headers, rows; sortable=true, class="striped", id=nothing,
                   download=false, download_filename=nothing, caption=nothing,
                   default_sort=nothing, kwargs...)

Lower-level table renderer for pre-built rows. Use when cells need rich
attributes (`data-status`, `hx-*`, `data-sort-value`, …) that
`render_table`'s value-to-content callback can't carry. `render_table`
itself delegates to this after materialising rows from a Tables.jl source.

# Arguments
- `headers`: `Vector` of header entries. Each entry is either:
    - a `String` — auto-wired into `h.th(label; onclick="sortTable(i, this)", class="u-pointer")`
      when `sortable=true`, or a plain `h.th(label)` otherwise.
    - any HTML node (e.g. `h.th("")`, `h.th("Actions")`) — used as-is.
      That's the per-column opt-out: pass a node and the auto-wiring is skipped.
      To make a RICH header sortable anyway (e.g. one holding a button), wire
      it yourself with `onclick="sortTable(this)"` — passing the `<th>` element
      lets `sortTable` derive the column index from its DOM position, so no
      index is hardcoded. The sort caret is kept in a trailing child `<span>`,
      so any buttons/links in a header survive a sort.
- `rows`: `Vector{<:Node}` of pre-built `h.tr(...)` rows. The caller controls
  every `<td>`, including `data-sort-value` for semantic sort keys (see
  `sortable_table_js` for the sort-key resolution rules) and `id="row-X"` /
  `id="detail-X"` for the paired-row pattern.
- `sortable`: master toggle for the auto-wiring of String headers (default `true`).
  Pre-built `h.th` headers are unaffected.
- `default_sort`: declare the order `rows` are ALREADY in, as `col` or
  `col => dir` — `col` a 1-based column index or a `String` header label, `dir`
  `:asc` (default) or `:desc`. Stamps `data-sort-dir` / `aria-sort` / the sort
  caret on that header, exactly as a client-side `sortTable` click would.
  It **declares** the order, it does not perform it: `sortable_table` receives
  pre-built row nodes, so the caller must emit `rows` in that order. Requires
  `sortable=true` and a `String` header at `col`.

Other keyword arguments behave the same as in [`render_table`](@ref).

# Example
```julia
rows = [h.tr(h.td(h.code(name)),
             h.td(data_sort_value=string(w))(h.strong(status)))
        for (name, status, w) in entries]
sortable_table(["Name", "Status"], rows; id="entries", download=false)
```

# Surviving a `morph:` swap
An idiomorph `hx-swap="morph:*"` re-imposes the server's child order on the
`<tbody>` and strips any attribute the server did not render — so a user's
client-side sort (rows *and* caret) is silently wiped by the next morph, and
that swap is idiomorph's worst case, since a client-sorted DOM is maximally
divergent from the server's order. Ride the sort state out with the request and
render rows in that order:

```julia
h.button("↻"; hx_get=string(__self__),
    hx_vals="js:{...htmxoSortState('#entries')}",
    hx_target="#entries", hx_swap="morph:outerHTML")

# ...and in the route, with `@param sort_col::Int = 0` / `@param sort_dir::String = "asc"`:
sortable_table(headers, sorted_rows; id="entries",
    default_sort=(sort_col == 0 ? nothing : sort_col => Symbol(sort_dir)))
```

Pair with [`sortable_table_js`](@ref) (which ships `htmxoSortState`) and
[`sortable_table_styles`](@ref).
"""
function sortable_table(headers, rows;
                        sortable=true, class="striped", id=nothing,
                        download=false, download_filename=nothing,
                        caption=nothing, default_sort=nothing, kwargs...)
    isnothing(id) && (id = "tbl-" * string(hash(headers), base=16))

    if !isnothing(default_sort) && !sortable
        error("sortable_table: default_sort requires sortable=true (nothing reads the marker otherwise)")
    end
    ds = _resolve_default_sort(default_sort, headers)

    th_nodes = [
        hdr isa AbstractString ?
            (sortable ?
                _sortable_th(string(hdr), i, ds) :
                h.th(string(hdr))) :
            hdr
        for (i, hdr) in enumerate(headers)
    ]

    # Always include `htmxo-sortable-table` when sorting is on — that's
    # the hook `sortable_table_styles()` reads, and it makes call sites
    # forget-proof.
    table_class = sortable ? string(class, " htmxo-sortable-table") : class

    table_node = h.table(; class=table_class, role="grid", kwargs...)(
        h.thead(h.tr(th_nodes...)),
        h.tbody(rows...; id),
    )

    fname = something(download_filename, id * ".csv")
    download_btn = download ?
        h.button("⬇ CSV"; type="button", class="outline caption-action",
            onclick="downloadTableCsv(this, '$(fname)')") :
        nothing

    if !isnothing(caption)
        actions = download ? (download_btn,) : ()
        fig_id = startswith(id, "tbl-") ? id : "tbl-$id"
        with_caption(caption, table_node; actions, id=fig_id)
    elseif download
        h.figure(; class="captioned")(
            h.figcaption(; class="caption")(
                h.div(; class="caption-header")(
                    h.span(""),
                    h.span(; class="caption-actions")(download_btn))
            ),
            table_node,
        )
    else
        table_node
    end
end

# --- Master / detail tables ---

# Sanitise `key` to a CSS-identifier-safe token for use in `id="row-<key>"`
# / `id="detail-<key>"`. `sortable_table_js`'s companion-pair lookup uses
# `querySelector('#detail-' + key)` — a CSS selector — so a `:`, `.`, `/`,
# leading digit, or space in the raw key throws `SyntaxError` and breaks
# the whole sort. Replacing every non-`[A-Za-z0-9_-]` char with `--`
# normalises ids like `Bruno:pkpd` → `Bruno--pkpd`, matching the convention
# the KB agents panel established by hand.
_md_safe_key(key) = replace(string(key), r"[^A-Za-z0-9_\-]" => "--")

"""
    master_detail_safe_key(key) -> String

Sanitise `key` to a CSS-identifier-safe token. `master_detail_pair` /
`master_detail_table` call this internally; reach for it directly only
when constructing row ids by hand outside the helpers.
"""
master_detail_safe_key(key) = _md_safe_key(key)

# The custom DOM event name a lazy master/detail slot listens for, and that
# its master row's toggle fires on expand. One source of truth for both sites
# (the slot's `hx-trigger` and the toggle's `htmx.trigger(...)` call).
_md_lazy_event() = "htmxo-md-load"

"""
    master_detail_toggle_js(safe_key; lazy_slot_id=nothing) -> String

Return the click-handler JS snippet for the master row of a master/detail
pair. The snippet ignores clicks on interactive descendants (`a`,
`button`, `input`, `textarea`, `select`, `form`), toggles the
`#detail-<safe_key>` row's `hidden` attribute, and mirrors the open state
to `aria-expanded` on the master. `safe_key` MUST already be CSS-safe
(see [`master_detail_safe_key`](@ref)).

Exposed for callers that need to extend the toggle (e.g. lazy-load a
fragment into a slot on open, empty it on close) — concatenate the
extension onto the returned string. The extension can read the standard
toggle's `show` local (true on open, false on close).

Pass `lazy_slot_id` to have the toggle drive a lazy detail slot itself: on
expand (`show`), it fires the `htmxo-md-load` event at `#<lazy_slot_id>` —
but only when that slot is neither already loaded (`data-loaded='1'`) nor in
flight (`data-loading='1'`) — latching `data-loading='1'` before firing so
repeat clicks while the request is outstanding coalesce (single-flight,
idempotent). This is the seam [`master_detail_pair`](@ref) drives for its
`detail_url` mode; you rarely need it directly. Deliberately **not**
`hx-trigger="load"` (fires for every collapsed slot at page load) nor
`revealed`/`intersect` (a late intersection response can clobber a
freshly-focused open slot) — the trigger is the explicit expand event.
"""
function master_detail_toggle_js(safe_key; lazy_slot_id=nothing)
    base = string(
        "if(event.target.closest('a,button,input,textarea,select,form'))return;",
        "var d=document.getElementById('detail-", safe_key, "');if(!d)return;",
        "var show=d.hidden;d.hidden=!show;",
        "this.setAttribute('aria-expanded',show);",
    )
    isnothing(lazy_slot_id) && return base
    string(base,
        "if(show){var s=document.getElementById('", lazy_slot_id, "');",
        "if(s&&s.dataset.loaded!=='1'&&s.dataset.loading!=='1')",
        "{s.dataset.loading='1';htmx.trigger(s,'", _md_lazy_event(), "');}}",
    )
end

# The lazy detail slot — the proven single-flight + click-to-retry shape,
# generalised from the KB For-You `_foryou_lazy_detail_slot`. Lives permanently
# in the (collapsed) detail cell; loads once on the first expand event, reuses
# the loaded DOM thereafter. `placeholder` is shown until the fetch lands (and
# must carry a `[data-status]` element for the loading/retry text swaps to have
# a target — the default does). `also_load=true` (an initially-open row) adds
# `load` so that one slot fetches on render; collapsed slots never do.
function _md_lazy_slot(safe, url, placeholder; also_load::Bool=false)
    ph = isnothing(placeholder) ? h.small(data_status="muted")("Loading…") : placeholder
    ev = _md_lazy_event()
    h.div(id="detail-slot-$safe",
          class="htmxo-md-detail-slot",
          data_loaded="0",
          hx_get=string(url),
          hx_trigger=also_load ? "$ev, load" : ev,
          hx_target="this", hx_swap="innerHTML",
          hx_on__before_request="this.dataset.loading='1';delete this.dataset.failed;" *
                                "var p=this.querySelector('[data-status]');" *
                                "if(p)p.textContent='Loading…'",
          hx_on__after_request="delete this.dataset.loading;" *
                               "if(event.detail.successful){this.dataset.loaded='1';delete this.dataset.failed;}" *
                               "else{this.dataset.loaded='0';this.dataset.failed='1';" *
                               "var p=this.querySelector('[data-status]');" *
                               "if(p)p.textContent='Failed to load — click to retry';}",
          hx_on__click="if(this.dataset.failed==='1'&&!this.dataset.loading){" *
                       "this.dataset.loading='1';htmx.trigger(this,'$ev');}")(
        ph)
end

"""
    master_detail_pair(key, master_cells, detail_body, ncols::Int;
                       master_class=nothing,
                       detail_class=nothing,
                       master_attrs=(),
                       initially_open::Bool=false,
                       detail_url=nothing)

Build the `(master_tr, detail_tr)` pair for one master/detail item.

The master `<tr>` carries id `"row-<safe>"` and an onclick that toggles
the paired detail `<tr id="detail-<safe>">`, where `safe` is `key` run
through [`master_detail_safe_key`](@ref). The detail row wraps
`detail_body` in a single `<td colspan="\$ncols">` cell. By default the
detail is collapsed initially (`hidden=true`, `aria-expanded="false"` on
the master) — pass `initially_open=true` for rows whose body IS the content
the user came to see (a question + answer brief, for example).

# Arguments
- `master_cells`: iterable of `<td>` nodes for the master row.
- `detail_body`: any content placed inside the detail row's spanning `<td>`.
  In lazy mode (`detail_url` set) this instead becomes the slot's pre-load
  **placeholder** (`nothing` → a default muted "Loading…").
- `ncols`: the master row's column count (drives the detail cell's
  `colspan` so the detail aligns with the table width).

# Keyword arguments
- `master_class`, `detail_class`: extra CSS classes on the two rows
  (default `nothing` — no extra class). The `row-…` / `detail-…` id
  pattern is what [`sortable_table_styles`](@ref) and the
  `sortable_table_js` companion-pair lookup key off; classes are for
  app-side styling on top.
- `master_attrs`: iterable of `name => value` pairs (or a NamedTuple)
  for extra attributes on the master `<tr>` (`data_status`, `data_aid`,
  `data_activity`, `data_sort_value`, …). Note: HTML attribute names
  use underscores in the `h` builder (`data_status`, not `data-status`).
  **These are applied LAST and OVERWRITE** what this function built — so
  `master_attrs=(onclick=…,)` **replaces** the toggle outright; it does
  **not** compose with it. To extend the toggle, rebuild it yourself and
  concatenate your extension onto it (it can read the toggle's `show`
  local; it runs only for clicks the toggle did not early-`return` on):

  ```julia
  safe = master_detail_safe_key(key)
  onclick = master_detail_toggle_js(safe) * my_extra_js
  ```

  **In lazy mode (`detail_url` set) you MUST also carry the lazy seam**,
  or the detail silently never loads — a collapsed row issues no request
  by design, so "never loads" is indistinguishable from "correctly lazy"
  until someone expands a row and sits on a permanent placeholder:

  ```julia
  onclick = master_detail_toggle_js(safe; lazy_slot_id="detail-slot-\$safe") * my_extra_js
  ```

  `master_detail_toggle_js` / `master_detail_safe_key` are **not
  exported** — qualify them (`HTMXObjects.master_detail_toggle_js`).
- `initially_open`: render the row open instead of collapsed. When
  `true`, omits `hidden` on the detail row and sets `aria-expanded="true"`
  on the master (vs `"false"` when collapsed) so collapsed-look CSS keyed
  off `[aria-expanded="false"]` (or `:not([aria-expanded="true"])`) shows
  the expanded look from the first render. First click toggles as usual.
- `detail_url`: opt in to **lazy** detail loading. When set (a URL string),
  the detail cell hosts a slot that `hx-get`s `detail_url` into itself on the
  **first expand** and reuses the loaded DOM thereafter — `detail_body` is
  not rendered eagerly; it serves as the pre-load placeholder instead
  (default: a muted "Loading…"). The load is single-flight (repeat clicks
  while in flight coalesce) with click-to-retry on failure, driven by the
  toggle's `lazy_slot_id` seam — never by `load`/`revealed`/`intersect`
  (see [`master_detail_toggle_js`](@ref)). A collapsed row issues no
  request; an `initially_open=true` lazy row loads once on render. **Explicit
  invalidation:** set the slot's `data-loaded='0'` (id `detail-slot-<safe>`)
  to force a reload on the next expand — an open row reloads on next expand,
  a collapsed row stays lazy; there is no refetch-on-re-open by default.
  **Custom onclick:** the lazy trigger lives on the master row's `onclick`,
  which a caller-supplied `master_attrs=(onclick=…,)` overwrites — see the
  `master_attrs` note above for the `lazy_slot_id` seam you must carry.
  HTMXObjects owns only the load/latch/retry mechanics — response caching,
  content hashing, TTL/LRU, and refresh-gating stay the caller's concern.
  Default `nothing` → today's eager `detail_body`, unchanged.

The pair MUST be interleaved into the row list passed to
[`sortable_table`](@ref) (master, detail, master, detail, …) so the
`sortable_table_js` companion-pair logic keeps them paired through a
column sort. Use [`master_detail_table`](@ref) to do the interleaving
for you.

For an inline form inside `detail_body`, prefer `hx-swap="none"` and
suppress any `HX-Redirect` on the response — otherwise a successful
POST yanks the user off the table.
"""
function master_detail_pair(key, master_cells, detail_body, ncols::Int;
                            master_class=nothing,
                            detail_class=nothing,
                            master_attrs=(),
                            initially_open::Bool=false,
                            detail_url=nothing)
    safe = _md_safe_key(key)
    lazy = !isnothing(detail_url)
    tr_kwargs = Dict{Symbol,Any}(
        :id      => "row-$safe",
        :onclick => lazy ?
            master_detail_toggle_js(safe; lazy_slot_id="detail-slot-$safe") :
            master_detail_toggle_js(safe),
    )
    # Every master row is expandable, so it always carries aria-expanded
    # reflecting state: "true" open, "false" collapsed. This matches what
    # master_detail_toggle_js sets on click (so the initial render and the
    # post-click DOM agree) and is the a11y-correct shape. Collapsed-look
    # CSS can key off `[aria-expanded="false"]` or the equivalent
    # `:not([aria-expanded="true"])`. (Pre-HTMX-116ab2c the `h` builder
    # dropped every string `"false"`, forcing a no-attr + `:not(...)`
    # workaround; that drop is now scoped to true boolean attrs.)
    tr_kwargs[:aria_expanded] = initially_open ? "true" : "false"
    isnothing(master_class) || (tr_kwargs[:class] = master_class)
    for (k, v) in pairs(master_attrs)
        tr_kwargs[Symbol(k)] = v
    end
    master = h.tr(; tr_kwargs...)(master_cells...)
    detail_kwargs = Dict{Symbol,Any}(:id => "detail-$safe")
    initially_open || (detail_kwargs[:hidden] = true)
    isnothing(detail_class) || (detail_kwargs[:class] = detail_class)
    # Lazy mode: the detail cell hosts a slot that fetches `detail_url` on the
    # first expand (see `_md_lazy_slot`); `detail_body` becomes its pre-load
    # placeholder. Eager mode: `detail_body` is the final content, unchanged.
    cell_body = lazy ?
        _md_lazy_slot(safe, detail_url, detail_body; also_load=initially_open) :
        detail_body
    detail = h.tr(; detail_kwargs...)(
        h.td(colspan=string(ncols))(cell_body),
    )
    (master, detail)
end

"""
    master_detail_table(headers, items;
                        key, master, detail=nothing, detail_url=nothing,
                        master_attrs=nothing,
                        master_class=nothing,
                        detail_class=nothing,
                        kwargs...)

Render a `sortable_table` whose primary rows expand into paired,
hidden-by-default detail rows on click. The helper takes care of the
five gotchas in `htmxo-master-detail`: CSS-safe key sanitisation,
interactive-descendant click guard, state-reflecting `aria-expanded`, paired
`row-…` / `detail-…` ids, and a `colspan`-spanning detail cell.

# Arguments
- `headers`: as in [`sortable_table`](@ref).
- `items`: any iterable.

# Keyword arguments
- `key(item)`: function returning the row key (sanitised internally).
- `master(item)`: function returning the master row's `<td>` cells
  (vector or tuple of nodes).
- `detail(item)`: function returning the detail row's body (placed
  inside one `<td colspan=ncols>`). Optional when `detail_url` is given —
  it then builds the per-row pre-load placeholder instead.
- `detail_url(item)` (or a bare URL `String`): opt in to **lazy** detail
  loading — each row's detail is fetched into its slot on first expand
  instead of rendered eagerly. Supply exactly one of `detail` / `detail_url`
  (or both: `detail` as the lazy placeholder). See [`master_detail_pair`](@ref)
  for the slot's single-flight / retry / invalidation contract.
- `master_attrs(item)`: optional function returning an iterable of
  `name => value` pairs for extra `<tr>` attributes on the master row.
- `master_class`, `detail_class`: optional extra CSS classes on the rows.
- `initially_open`: `true`, `false`, or a predicate `item -> Bool`.
  When the predicate is `true` for an item, that row renders open from
  the first paint (see [`master_detail_pair`](@ref) for the mechanics).
  Defaults to `false` (all rows collapsed initially).
- Remaining `kwargs...` forward to [`sortable_table`](@ref) (`id`,
  `caption`, `download`, `class`, …).

For **lazy** detail loading (fetch each row's detail on first expand rather
than rendering every collapsed detail up front), pass `detail_url` — the
proven single-flight + click-to-retry slot, no hand-rolled `htmx.ajax` glue
or custom onclick needed. Without it, detail bodies are eager.

Include [`sortable_table_js`](@ref) on the page (which also brings in
the master/detail hover + detail-cell reset rules via
[`sortable_table_styles`](@ref)).
"""
function master_detail_table(headers, items;
                             key, master, detail=nothing,
                             detail_url=nothing,
                             master_attrs=nothing,
                             master_class=nothing,
                             detail_class=nothing,
                             initially_open::Union{Bool,Function}=false,
                             kwargs...)
    ncols = length(headers)
    (!isnothing(detail_url) || !isnothing(detail)) || throw(ArgumentError(
        "master_detail_table: supply `detail` (eager body) or `detail_url` (lazy URL)"))
    # `detail_url` may be a per-item `item -> url` callback or a bare String
    # (same URL for every row — unusual, but supported).
    _url = detail_url isa Union{Nothing,Function} ? detail_url : (_ -> detail_url)
    rows = Any[]
    _open = initially_open isa Function ? initially_open : (_ -> initially_open)
    for item in items
        attrs = isnothing(master_attrs) ? () : master_attrs(item)
        # In lazy mode `detail(item)` (if given) is the per-row placeholder.
        body = isnothing(detail) ? nothing : detail(item)
        url  = isnothing(_url) ? nothing : _url(item)
        (m, d) = master_detail_pair(key(item), master(item), body, ncols;
                                    master_class, detail_class, master_attrs=attrs,
                                    initially_open=_open(item), detail_url=url)
        push!(rows, m, d)
    end
    sortable_table(headers, rows; kwargs...)
end

# --- Formatting helpers ---

"""
    fmt_time(t) -> String

Format a time duration `t` (in seconds) with appropriate SI units.
Returns e.g. `"1.23ns"`, `"456μs"`, `"78.9ms"`, `"1.23s"`, `"5.0min"`, `"2.5hr"`.
"""
function fmt_time(t)
    t < 0 && return "-" * fmt_time(-t)
    t < 1e-6 && return string(round(t * 1e9; sigdigits=2)) * "ns"
    t < 1e-3 && return string(round(t * 1e6; sigdigits=2)) * "μs"
    t < 1.0  && return string(round(t * 1e3; sigdigits=2)) * "ms"
    t < 60   && return string(round(t; sigdigits=2)) * "s"
    t < 3600 && return string(round(t / 60; sigdigits=2)) * "min"
    return string(round(t / 3600; sigdigits=2)) * "hr"
end

"""
    fmt_bytes(n) -> String

Format a byte count `n` with appropriate binary units (B, KB, MB, GB, TB).
"""
function fmt_bytes(n)
    n < 0 && return "-" * fmt_bytes(-n)
    n < 1024 && return string(Int(n)) * " B"
    n < 1024^2 && return string(round(n / 1024; sigdigits=2)) * " KB"
    n < 1024^3 && return string(round(n / 1024^2; sigdigits=2)) * " MB"
    n < 1024^4 && return string(round(n / 1024^3; sigdigits=2)) * " GB"
    return string(round(n / 1024^4; sigdigits=2)) * " TB"
end

"""
    fmt_number(x; sigdigits=2) -> String

Format a number with SI suffixes (K, M, B, T) or scientific notation for very small values.
"""
function fmt_number(x; sigdigits=2)
    isnan(x) && return "NaN"
    isinf(x) && return x > 0 ? "∞" : "-∞"
    x < 0 && return "-" * fmt_number(-x; sigdigits)
    x == 0 && return "0"
    x < 1e-3 && return string(round(x; sigdigits))
    x < 1e3  && return string(round(x; sigdigits))
    x < 1e6  && return string(round(x / 1e3; sigdigits)) * "K"
    x < 1e9  && return string(round(x / 1e6; sigdigits)) * "M"
    x < 1e12 && return string(round(x / 1e9; sigdigits)) * "B"
    return string(round(x / 1e12; sigdigits)) * "T"
end

include("test_items.jl")

include("routes/test_routes.jl")

include("routes/structure_routes.jl")

include("routes/shared_ops_routes.jl")

_hidden_input(k, v) = [h.input(; type="hidden", name=string(k), value=string(v))]
_hidden_input(k, v::AbstractVector) = [h.input(; type="hidden", name=string(k), value=string(x)) for x in v]

"""
    hidden_inputs(; kwargs...) -> Vector{Node}

Generate hidden `<input>` elements for each keyword argument. Splat into a form
to pass parameters to `@post` routes via `formdata`:

    h.form(; hx_post="/foo", hx_target="#list", hx_swap="innerHTML")(
        hidden_inputs(; script=path, worktree=wt)...,
        h.button(; class="btn", type="submit")("Go"),
    )

Vector values produce repeated inputs (one `<input>` per element).
"""
hidden_inputs(; kwargs...) = mapreduce(((k, v),) -> _hidden_input(k, v), vcat, kwargs; init=[])

"""
    hidden_inputs(obj; skip=(), overrides...) -> Vector{Node}

Object-form of [`hidden_inputs`](@ref) — the GET-form hop symmetric to
[`query_url(path, obj)`](@ref). Emit a hidden `<input>` for every `@param`
declared on `obj`'s type that is actually present in the inbound request
(`_req_of(obj)`) — exactly the set `query_url(path, obj)` forwards into a URL.
**Zero consumer burden:** pass the route object and the framework collects the
params the user set; there is no hand-listed set of hidden inputs to drift out
of sync with the `@param` block.

`skip` (any iterable of `Symbol`) drops params the form supplies another way —
the field a visible control already submits, paging params, etc. `overrides`
set explicit values that win over the auto-collected one and are emitted even
if absent from the request (same semantics as
`query_url(path, obj; overrides...)`). A skipped key is never emitted, even if
also passed as an override.

    h.form(; hx_get="/fit/compute", hx_target="#out")(
        hidden_inputs(__self__; skip=[:source])...,   # forward every set @param but `source`
        source_select,
    )

For the common case, [`get_form`](@ref)/[`post_form`](@ref) take this directly
via their `obj=` / `skip=` keywords.
"""
function hidden_inputs(obj; skip=(), overrides...)
    names = _param_names(typeof(obj))
    skipset = Set{Symbol}(Symbol(s) for s in skip)
    override_keys = Set(keys(overrides))
    present = queryparams(_req_of(obj))
    kws = Pair{Symbol,Any}[]
    for n in names
        (n in skipset || n in override_keys) && continue
        haskey(present, String(n)) || continue
        push!(kws, n => getproperty(obj, n))
    end
    for (k, v) in pairs(overrides)
        k in skipset && continue
        push!(kws, k => v)
    end
    hidden_inputs(; kws...)
end

"""
    _form(method, url, children...; obj=nothing, skip=(), label="Submit", btn_class="btn", confirm="", form_class="", kwargs...)

Shared implementation for `get_form` and `post_form`. `method` is `:hx_get` or
`:hx_post`. Positional `children` are inserted before the submit button.

Hidden inputs come from one of two paths, depending on `obj`:

- `obj === nothing` (default): the non-form-attr keyword arguments each become a
  hidden `<input>` field (`hidden_inputs(; …)`).
- `obj` given: the route object's set `@param`s are auto-collected
  (`hidden_inputs(obj; skip, …)`), and the non-form-attr keyword arguments
  become `query_url`-style **overrides** rather than standalone inputs. `skip`
  drops params a visible control already supplies. This is the zero-burden
  object-forwarding form symmetric to `query_url(path, obj)`.

`obj` is a keyword (not positional) because route objects are plain structs
(`<: Any`), so a positional `obj` would be indistinguishable from a `children`
node in the existing `get_form(url, children...)` varargs.
"""
const _FORM_KEYS = Set([:label, :btn_class, :confirm, :form_class])
_is_form_attr(k) = startswith(String(k), "hx_") || k in (:id, :class, :style, :enctype)

function _form(method, url, children...; obj=nothing, skip=(), label="Submit", btn_class="btn", confirm="", form_class="", kwargs...)
    form_kw = filter(((k, _),) -> _is_form_attr(k), pairs(kwargs))
    hidden_kw = filter(((k, _),) -> !_is_form_attr(k), pairs(kwargs))
    merged_class = isempty(form_class) ? "u-inline" : "u-inline $form_class"
    base_attrs = filter(((_, v),) -> !isempty(string(v)), pairs((;
        method => url,
        hx_confirm=confirm, class=merged_class,
    )))
    btn = isnothing(label) ? [] : [h.button(; class=btn_class, type="submit")(label)]
    # With `obj`, the non-form-attr kwargs are overrides for the auto-collected
    # @params (not standalone hidden inputs) — see `hidden_inputs(obj; …)`.
    hidden = isnothing(obj) ? hidden_inputs(; hidden_kw...) : hidden_inputs(obj; skip, hidden_kw...)
    h.form(; base_attrs..., form_kw...)(
        hidden...,
        children...,
        btn...,
    )
end

"""
    post_form(url, children...; obj=nothing, skip=(), kwargs...)

Generate a complete inline POST form. Extra keyword arguments become hidden
`<input>` fields. Positional `children` are inserted before the submit button.

    post_form("/respond/slug/approved";
        label="Approve", btn_class="btn btn-approve",
        hx_target="#list", hx_swap="innerHTML",
        msg="APPROVED.",
    )

Pass `obj=<route object>` to auto-forward its set `@param`s as hidden inputs
with zero hand-listing (see [`hidden_inputs(obj)`](@ref) / [`get_form`](@ref));
`skip` drops params a visible control supplies, and the extra kwargs become
`query_url`-style overrides.
"""
post_form(url, children...; kwargs...) = _form(:hx_post, url, children...; kwargs...)

"""
    get_form(url, children...; obj=nothing, skip=(), kwargs...)

Generate a complete inline GET form. Same API as [`post_form`](@ref) but uses
`hx-get` instead of `hx-post`.

    get_form("/analysis/dose_response",
        sinput((; sources), source_options; multiple=true),
        sinput((; outcomes), outcome_options; multiple=true);
        hx_target="#results", hx_swap="innerHTML",
        fit_key, top_chains=string(top_chains),
    )

**Object-forwarding form** (symmetric to `query_url(path, obj)`): pass
`obj=<route object>` to auto-collect a hidden `<input>` for every `@param` the
user set — no hand-list to keep in sync with the `@param` block. `skip` drops
params a visible control already submits; remaining kwargs are `query_url`-style
overrides. See [`hidden_inputs(obj)`](@ref).

    get_form(__self__/"fit/compute",
        source_select;                 # the visible control for `source`
        obj=__self__, skip=[:source],  # forward every OTHER set @param, zero hand-list
        hx_target="#fit", hx_swap="innerHTML",
    )
"""
get_form(url, children...; label=nothing, kwargs...) = _form(:hx_get, url, children...; label, kwargs...)

"""
    lazy(url; tag=h.div, swap="outerHTML", kwargs...)

Return a placeholder element that fetches `url` via HTMX on page load and
replaces itself with the response (`hx-swap="outerHTML"`).

Useful for "render immediately, fill in asynchronously" patterns where each
item in a list independently loads its own content after the page appears.

```julia
# Status cell that loads asynchronously after the table renders
lazy(query_url("/pod_status"; pod=pod_id); tag=h.td, id="status-\$pod_id")
```

Extra `kwargs` (e.g. `id`, `style`, `class`) are forwarded to the element.
"""
lazy(url, content...; tag=h.div, swap="outerHTML", kwargs...) =
    tag(; hx_get=url, hx_trigger="load", hx_swap=swap, kwargs...)(
        (isempty(content) ? (h.progress(),) : content)...
    )

"""
    query_url(path; kwargs...) -> String

Build a URL with properly escaped query parameters. Parameters with `nothing`
values are omitted. Vector values produce repeated keys (`a=1&a=2`).

New parameters are always **appended** — existing query parameters in `path`
are preserved as-is (no deduplication or override).

    query_url("/search"; q="hello world", page=2)  # → "/search?q=hello%20world&page=2"
    query_url("/search?q=hello"; page=2)            # → "/search?q=hello&page=2"
"""
# Append URL-encoded query-param entries: `Vector` values produce repeated keys,
# everything else produces one `key=value` pair.
_push_qparam!(parts, k, v::AbstractVector) =
    for item in v; push!(parts, HTTP.URIs.escapeuri(string(k)) * "=" * HTTP.URIs.escapeuri(string(item))); end
_push_qparam!(parts, k, v) =
    push!(parts, HTTP.URIs.escapeuri(string(k)) * "=" * HTTP.URIs.escapeuri(string(v)))

query_url(path; kwargs...) = begin
    filtered = filter(p -> !isnothing(p.second), pairs(kwargs))
    isempty(filtered) && return path
    parts = String[]
    for (k, v) in filtered
        _push_qparam!(parts, k, v)
    end
    isempty(parts) ? path : path * (occursin('?', path) ? "&" : "?") * join(parts, "&")
end

"""
    query_url(path, obj; overrides...) -> String

Build a URL from `path`, auto-collecting every `@param` declared on `obj`'s type
that is actually present in the inbound request (`_req_of(obj)`). Params with
no declared `@param` are ignored; params not present in the request are omitted
(so the URL only carries what the user explicitly set, and defaults remain
implicit). Explicit `overrides` always win and are emitted even if absent from
the request.

Presence is checked against `queryparams(_req_of(obj))` regardless of the
inbound request method — `query_url` always builds GET-style URLs.
"""
function query_url(path, obj; overrides...)
    names = _param_names(typeof(obj))
    override_keys = Set(keys(overrides))
    present = queryparams(_req_of(obj))
    kws = Pair{Symbol,Any}[]
    for n in names
        n in override_keys && continue
        haskey(present, String(n)) || continue
        push!(kws, n => getproperty(obj, n))
    end
    for (k, v) in pairs(overrides)
        push!(kws, k => v)
    end
    query_url(path; kws...)
end

_unquote(x::QuoteNode) = x.value
_unquote(x) = x

# Pull the property name out of an `@query_url` head: bare symbol, or
# `__self__.prop` style `:.` expression. Anything else is a usage error.
_query_url_name(x) = error("@query_url: property name must be a symbol, got $x")
_query_url_name(s::Symbol) = s
function _query_url_name(e::Expr)
    e.head === :. || error("@query_url: property name must be a symbol, got $e")
    _unquote(e.args[2])
end

# Bucket a single call argument into positional / kwargs based on its shape.
_classify_call_arg!(positional, _, arg) = (push!(positional, arg); nothing)
function _classify_call_arg!(positional, kwargs, arg::Expr)
    arg.head === :parameters && return (append!(kwargs, arg.args); nothing)
    arg.head === :kw         && return (push!(kwargs, arg); nothing)
    push!(positional, arg)
    nothing
end

# `kw` is either a bare Symbol (`name`) or a `:kw`/`:(=)` Expr (`name=value`).
_query_url_kw(kw::Symbol) = Expr(:kw, kw, esc(kw))
_query_url_kw(kw::Expr) = Expr(:kw, kw.args[1], esc(kw.args[2]))

"""
    @query_url prop(pos1, pos2; kw1=val1, kw2=val2)

Build a `query_url` from a property-call expression, following the same conventions as
`@get` route definitions. Positional args become path segments, kwargs become query params.

Designed for use inside `@htmx`/`@dynamicstruct` bodies, where it intercepts the call
before `walk_rhs` turns it into a property access.

    @query_url fit(; dataset="foo", model="bar")    # → query_url("/fit"; dataset="foo", model="bar")
    @query_url item(42)                              # → query_url("/item/42")
    @query_url item(id; format="json")               # → query_url("/item/\$(id)"; format="json")
    @query_url index                                 # → query_url("/")
"""
macro query_url(expr)
    _query_url = GlobalRef(@__MODULE__, :query_url)
    if expr isa Symbol
        path = expr === :index ? "/" : "/$expr"
        return esc(:($(_query_url)($path)))
    end
    Meta.isexpr(expr, :call) || error("@query_url expects a call expression like `prop(args...; kwargs...)`")
    name = _query_url_name(expr.args[1])

    # Separate positional args and kwargs
    positional = []
    kwargs = []
    for arg in expr.args[2:end]
        _classify_call_arg!(positional, kwargs, arg)
    end

    # Build path: "/name" or "/name/$arg1/$arg2"
    base = name === :index ? "/" : "/$name"
    if isempty(positional)
        path_expr = base
    else
        segments = [base; [:("/" * string($(esc(a)))) for a in positional]...]
        path_expr = Expr(:call, :*, segments...)
    end

    # Build query_url call
    if isempty(kwargs)
        return :($(_query_url)($path_expr))
    else
        kw_exprs = map(_query_url_kw, kwargs)
        return DynamicObjects.fixcall(Expr(:call, _query_url, path_expr, Expr(:parameters, kw_exprs...)))
    end
end

# --- Label humanization ---

"""
    Long(x)

Convert a symbol/string to a human-readable label by replacing underscores with spaces.
Add methods for custom labels: `Long(::Val{:pk}) = "Pharmacokinetics"`.
"""
Long(x) = replace(string(x), "_" => " ")
Long(nt::NamedTuple) = Long(_aname(nt))

# --- Form input helpers ---

_aname(nt::NamedTuple) = string(first(keys(nt)))
_aname(name::AbstractString) = name
_avalue(nt::NamedTuple, default=nothing) = first(nt)
_avalue(::AbstractString, default=nothing) = default

# Normalize option entries: a plain value `v` becomes `(v, v)`; pre-paired
# entries (Tuple or Pair) are returned as-is. Used by radio_group / sinput.
_option_pair(o) = (o, o)
_option_pair(o::Tuple) = o
_option_pair(o::Pair) = o
_option_key(o) = o
_option_key(o::Pair) = first(o)
# Wrap a scalar value into a single-element vector; pass vectors through.
_as_vector(v::AbstractVector) = v
_as_vector(v) = [v]

"""
    ainput(nv; kwargs...)

Smart `h.input` wrapper that accepts a `NamedTuple` or `String`. A `NamedTuple`
like `(; fit_key)` extracts name and value automatically:

    ainput((; fit_key); type="hidden")
    # equivalent to: h.input(; name="fit_key", value=fit_key, type="hidden")
"""
ainput(nt::NamedTuple; value=first(nt), kwargs...) = h.input(; name=_aname(nt), value, kwargs...)
ainput(name::AbstractString; kwargs...) = h.input(; name, kwargs...)

"""
    linput(nv, placeholder=Long(nv); label=Long(nv), kwargs...)

A labeled text `<input>` wrapped in a `<label>`.
All extra `kwargs` (e.g. `hx_get`, `hx_target`) are passed to the `<input>`.
"""
linput(nv, placeholder=Long(nv); label=Long(nv), kwargs...) = h.label(
    label,
    ainput(nv; placeholder, kwargs...)
)

"""
    sinput(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, kwargs...)

A labeled `<select>` wrapped in a `<label>`. Each element of `options` is rendered
via [`soption`](@ref). Extra `kwargs` (e.g. `hx_get`, `hx_target`) go on the `<select>`.

When `show_when=(field, op, value)` is set, the label gets `data-show-when-*`
attributes and `class="u-hidden"`. Include [`show_when_script`](@ref) once per
page to wire up the client-side visibility logic.
"""
sinput(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, kwargs...) = begin
    name = _aname(nv)
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    h.label(
        label,
        h.select([
            soption(option; selected_value=value) for option in options
        ]...; name, aria_label=label, kwargs...);
        show_attrs...
    )
end

"""
    sinput_custom(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, placeholder="Add custom…", kwargs...)

Like [`sinput`](@ref), but includes a text input and button for adding custom
options client-side. The custom value is appended to the `<select>` and
auto-selected so it is included in form submissions. Duplicates are skipped.
Extra `kwargs` go on the `<select>`.
"""
sinput_custom(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, placeholder="Add custom…", kwargs...) = begin
    name = _aname(nv)
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    uid = string(hash(name), base=16)
    sel_id = "sinput_custom_sel_$(uid)"
    inp_id = "sinput_custom_inp_$(uid)"
    option_values = Set(string.([_option_key(o) for o in options]))
    extra_options = isnothing(value) ? [] : [v for v in _as_vector(value) if !(string(v) in option_values)]
    all_options = vcat(options, extra_options)
    h.label(
        label,
        h.div(
            h.select([
                soption(option; selected_value=value) for option in all_options
            ]...; id=sel_id, name, aria_label=label, kwargs...),
            h.span(
                h.input(; id=inp_id, type="text", placeholder,
                    class="u-grow",
                    # Swallow this staging input's native `change` (fired on
                    # blur/Enter-commit) so it never bubbles to an enclosing
                    # `hx_trigger="change"` form with stale pre-append state. The
                    # ONLY change the form should see is the select's explicit
                    # post-append `dispatchEvent` below — which carries the new
                    # value deterministically on both the Add-button and Enter paths.
                    onchange="event.stopPropagation()",
                    onkeydown="if(event.key==='Enter'){event.preventDefault();this.nextElementSibling.click()}"),
                h.button("Add"; type="button", onclick="""
                    (function(){
                        var inp=document.getElementById('$(inp_id)');
                        var sel=document.getElementById('$(sel_id)');
                        var v=inp.value.trim();
                        if(!v) return;
                        for(var i=0;i<sel.options.length;i++){if(sel.options[i].value===v){sel.options[i].selected=true;inp.value='';return;}}
                        var o=document.createElement('option');
                        o.value=v;o.text=v;o.selected=true;
                        sel.add(o);inp.value='';
                        sel.dispatchEvent(new Event('change',{bubbles:true}));
                    })()
                """);
                class="u-flex-tight u-mt-1"
            )
        );
        show_attrs...
    )
end

"""
    soption(option; value=option, selected_value=nothing, kwargs...)
    soption((value, label)::Union{Tuple,Pair}; kwargs...)

Render an `<option>` tag. When given a `Pair` or `Tuple`, the first element is the
value attribute and the second is the display label.
"""
soption((value, option)::Union{Tuple,Pair}; kwargs...) = soption(option; value, kwargs...)
_is_selected(value, selected_value) = value == selected_value
_is_selected(value, selected_value::AbstractVector) = string(value) in string.(selected_value)
soption(option; value=option, selected_value=nothing, kwargs...) = h.option(
    option; value, selected=string(_is_selected(value, selected_value)), kwargs...
)

"""
    rinput(nv; label=Long(nv), value=_avalue(nv, 50), min=0, max=100, step=1, show_when=nothing, kwargs...)

A labeled range slider `<input type="range">` with a live `<output>` display.
Extra `kwargs` go on the `<input>`.
"""
rinput(nv; label=Long(nv), value=_avalue(nv, 50), min=0, max=100, step=1, show_when=nothing, kwargs...) = begin
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    h.label(
        label,
        h.span(
            ainput(nv; type="range", value, min, max, step,
                oninput="this.nextElementSibling.textContent=this.value", kwargs...),
            h.output(string(value));
            class="u-flex-tight"
        );
        show_attrs...
    )
end

"""
    ninput(nv; label=Long(nv), value=_avalue(nv, 0), min=nothing, max=nothing, step=nothing, show_when=nothing, kwargs...)

A labeled number `<input type="number">`. Only `min`, `max`, `step` that are
not `nothing` are included as attributes. Extra `kwargs` go on the `<input>`.
"""
ninput(nv; label=Long(nv), value=_avalue(nv, 0), min=nothing, max=nothing, step=nothing, show_when=nothing, kwargs...) = begin
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    num_attrs = filter(((_, v),) -> !isnothing(v), pairs((; min, max, step)))
    h.label(
        label,
        ainput(nv; type="number", value, num_attrs..., kwargs...);
        show_attrs...
    )
end

"""
    cinput(nv; label=Long(nv), checked=_avalue(nv, false), switch=false, show_when=nothing, kwargs...)

A labeled checkbox `<input type="checkbox">`. Set `switch=true` to use Pico CSS's
toggle-switch style (`role="switch"`). Extra `kwargs` go on the `<input>`.
"""
cinput(nv; label=Long(nv), checked=_avalue(nv, false), switch=false, show_when=nothing, kwargs...) = begin
    name = _aname(nv)
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    check_attrs = checked ? (; checked="true") : (;)
    role_attrs = switch ? (; role="switch") : (;)
    h.label(
        h.input(; type="checkbox", name, check_attrs..., role_attrs..., kwargs...),
        label;
        show_attrs...
    )
end

"""
    tinput(nv; label=Long(nv), value=_avalue(nv, ""), placeholder=Long(nv), rows=3, show_when=nothing, kwargs...)

A labeled `<textarea>`. Extra `kwargs` go on the `<textarea>`.
"""
tinput(nv; label=Long(nv), value=_avalue(nv, ""), placeholder=Long(nv), rows=3, show_when=nothing, kwargs...) = begin
    name = _aname(nv)
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    h.label(
        label,
        h.textarea(value; name, placeholder, rows, kwargs...);
        show_attrs...
    )
end

"""
    radio_group(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, kwargs...)

A `<fieldset>` of radio buttons. Each element of `options` becomes
`<label><input type="radio" .../> Label</label>`. Options can be plain values
or `value => label` pairs. Extra `kwargs` go on each `<input>`.
"""
radio_group(nv, options; label=Long(nv), value=_avalue(nv), show_when=nothing, kwargs...) = begin
    name = _aname(nv)
    show_attrs = isnothing(show_when) ? (;) : _show_when_attrs(show_when)
    h.fieldset(
        h.legend(label),
        [begin
            opt_value, opt_label = _option_pair(option)
            checked_attrs = string(opt_value) == string(value) ? (; checked="true") : (;)
            h.label(
                h.input(; type="radio", name, value=opt_value, checked_attrs..., kwargs...),
                string(opt_label)
            )
        end for option in options]...;
        show_attrs...
    )
end

# --- Conditional visibility (show_when) ---

const _SHOW_WHEN_OPS = Dict{Function,String}(
    (==) => "eq", (!=) => "neq",
    startswith => "startswith", endswith => "endswith",
)

function _show_when_attrs((field, op, value))
    op_name = get(_SHOW_WHEN_OPS, op, nothing)
    isnothing(op_name) && error("show_when: unsupported predicate $op; use ==, !=, startswith, or endswith")
    (;  data_show_when_field=string(field),
        data_show_when_op=op_name,
        data_show_when_value=string(value),
        class="u-hidden")
end

"""
    show_when_script()

Return a `<script>` that wires `change` listeners for all `[data-show-when-field]`
elements. Include once per page (like [`loading_indicator_script`](@ref)).

Evaluates visibility on load and re-initializes on `htmx:afterSettle` for
dynamically swapped content.
"""
show_when_script() = h.script(Raw(raw"""
(function() {
  function evalShowWhen(el) {
    var field = el.dataset.showWhenField;
    var op = el.dataset.showWhenOp;
    var val = el.dataset.showWhenValue;
    var form = el.closest('form') || el.closest('[hx-target]') || document.body;
    var ctrl = form.querySelector('[name="' + field + '"]');
    if (!ctrl) return;
    var cv = ctrl.value;
    var show = op === 'eq' ? cv === val
             : op === 'neq' ? cv !== val
             : op === 'startswith' ? cv.startsWith(val)
             : op === 'endswith' ? cv.endsWith(val)
             : false;
    el.classList.toggle('u-hidden', !show);
  }
  function initShowWhen(root) {
    (root || document).querySelectorAll('[data-show-when-field]').forEach(function(el) {
      if (el.dataset.showWhenBound) return;
      el.dataset.showWhenBound = '1';
      evalShowWhen(el);
      var field = el.dataset.showWhenField;
      var form = el.closest('form') || el.closest('[hx-target]') || document.body;
      var ctrl = form.querySelector('[name="' + field + '"]');
      if (ctrl) ctrl.addEventListener('change', function() { evalShowWhen(el); });
    });
  }
  initShowWhen();
  document.body.addEventListener('htmx:afterSettle', function(e) { initShowWhen(e.detail.elt); });
})();
"""))

# --- Theme ---

"""
    htmxo_theme()

`<style>` block with HTMXO's framework-agnostic CSS theme variables.

Defines the `--htmxo-*` custom properties that every HTMXO-emitted style
consumes (`request_feedback_style`, `tabset_styles`, `status_badge`, …).
Defaults are sensible standalone (the values that have shipped historically),
and are declared at zero specificity (`:where(:root)`) inside `@layer htmxo`
so any host's `:root { --htmxo-...: ... }` override wins automatically — no
specificity wars, no host detection in component code. See [`pico_bridge`](@ref)
and [`vitepress_bridge`](@ref) for one-line adapters.
"""
htmxo_theme() = h.style(Raw("""
@layer htmxo {
    :where(:root) {
        --htmxo-accent:  #4a90d9;
        --htmxo-success: #2a9d8f;
        --htmxo-warning: #e9a23b;
        --htmxo-error:   #e76f51;
        --htmxo-border:  currentColor;
        --htmxo-muted:   color-mix(in srgb, currentColor 60%, transparent);
    }
}
"""))

"""
    pico_bridge()

`<style>` block remapping `--htmxo-*` to Pico CSS's color tokens. Include
once at the page level when an HTMXO app uses Pico CSS, so HTMXO components
pick up the host's accent / borders / status colors. Loaded automatically by
[`htmx`](@ref) when `pico_version` is non-`nothing`.
"""
pico_bridge() = h.style(Raw("""
:root {
    --htmxo-accent:  var(--pico-primary, #4a90d9);
    --htmxo-success: var(--pico-color-green-550, #2a9d8f);
    --htmxo-warning: var(--pico-color-amber-550, #e9a23b);
    --htmxo-error:   var(--pico-color-red-550, #e76f51);
    --htmxo-border:  var(--pico-border-color, currentColor);
    --htmxo-muted:   var(--pico-muted-color, color-mix(in srgb, currentColor 60%, transparent));
}
"""))

"""
    vitepress_bridge()

`<style>` block remapping `--htmxo-*` to VitePress's brand/state tokens.
Include in VitePress's `head` (via `config.mts`) when embedding HTMXO
recordings/fragments inside docs pages, so HTMXO components match the docs
theme automatically. Falls back to HTMXO defaults when a token is missing.
"""
vitepress_bridge() = h.style(Raw("""
:root {
    --htmxo-accent:  var(--vp-c-brand-1, #4a90d9);
    --htmxo-success: var(--vp-c-success-1, #2a9d8f);
    --htmxo-warning: var(--vp-c-warning-1, #e9a23b);
    --htmxo-error:   var(--vp-c-danger-1, #e76f51);
    --htmxo-border:  var(--vp-c-divider, currentColor);
    --htmxo-muted:   var(--vp-c-text-3, color-mix(in srgb, currentColor 60%, transparent));
}
"""))

# --- VitePress integration helpers ---

const _VITEPRESS_ASSETS_DIR = joinpath(dirname(@__DIR__), "assets", "vitepress")

"""
    vitepress_asset_dir() -> String

Absolute path of the bundled VitePress assets directory inside HTMXObjects.
Contains `htmxo-embed.ts`, the canonical theme module that powers
`<div data-hx-base="…">` placeholders and `.htmxo-embed` link rewriting.
"""
vitepress_asset_dir() = abspath(_VITEPRESS_ASSETS_DIR)

"""
    vitepress_theme_install(theme_dir; force=true) -> String

Copy the bundled `htmxo-embed.ts` into a VitePress theme directory.
Call from `make.jl` before DocumenterVitepress runs:

    HTMXObjects.vitepress_theme_install(joinpath(@__DIR__, "src", ".vitepress", "theme"))

Then in the theme's `index.ts`:

    import { setupHtmxoEmbed } from './htmxo-embed';
    // …inside enhanceApp({ router }):
    setupHtmxoEmbed(router);

Returns the destination path. Overwrites by default so the asset stays in
sync with the installed HTMXObjects version.
"""
function vitepress_theme_install(theme_dir::AbstractString; force::Bool=true)
    isdir(theme_dir) || mkpath(theme_dir)
    asset_dir = vitepress_asset_dir()
    dst_dir = abspath(theme_dir)
    # All sibling assets in `assets/vitepress/` get mirrored — currently
    # `htmxo-embed.ts` (the embed wiring) and `htmxo-gallery.css` (the
    # canonical gallery layout). Both load together because
    # `htmxo-embed.ts` does a side-effect `import './htmxo-gallery.css'`.
    for f in ("htmxo-embed.ts", "htmxo-gallery.css", "htmxo-syntax.css")
        cp(joinpath(asset_dir, f), joinpath(dst_dir, f); force)
    end
    joinpath(dst_dir, "htmxo-embed.ts")
end

"""
    htmxo_embed_html(; base, swap="innerHTML", placeholder="Loading…", class_="htmxo-embed")

Build the placeholder `<div>` that `setupHtmxoEmbed` resolves at runtime.
`base` is the path suffix below the deploy abspath (e.g. `"live-aov/"`)
— in dev it resolves to `"/<base>"` (Vite proxy), in prod to
`"<deploy-abspath>/<base>"` (committed recordings).

Use as an HTMX `Node` from a Julia-driven page, or stringify and embed
in markdown:

    println(io, htmxo_embed_html(; base="live-aov/"))
"""
htmxo_embed_html(; base::AbstractString,
                   swap::AbstractString="innerHTML",
                   placeholder::AbstractString="Loading…",
                   class_::AbstractString="htmxo-embed") =
    h.div(; class=class_, data_hx_base=base, hx_trigger="load", hx_swap=swap)(
        h.em(placeholder),
    )

"""
    vitepress_theme_enhanceapp_snippet() -> String

The canonical TS snippet to paste into a VitePress theme's
`enhanceApp({ router })`. Already split into the import line and the
function call so it slots into existing themes without restructuring.
"""
vitepress_theme_enhanceapp_snippet() = """
// At the top of theme/index.ts:
import { setupHtmxoEmbed } from './htmxo-embed';

// Inside enhanceApp({ router }):
setupHtmxoEmbed(router);
"""

"""
    vitepress_head_scripts(; htmx_version="2.0.8") -> String

The canonical `head` entries for VitePress's `config.mts` — loads
HTMX from the jsdelivr CDN. Paste into the `head: [ … ]` list.
"""
vitepress_head_scripts(; htmx_version::AbstractString="2.0.8") = """
    ['script', { src: 'https://cdn.jsdelivr.net/npm/htmx.org@$(htmx_version)/dist/htmx.min.js' }],
"""

"""
    vitepress_proxy_config(; prefix="/live-htmxo", target_env="HTMXO_DEV_TARGET",
                              default_target="http://localhost:8101") -> String

The canonical `vite.server.proxy` entry forwarding `<prefix>/*` to a
running HTMXObjects app during `vitepress dev`. In production the same
markdown is backed by static recordings, so no proxy is needed.
"""
vitepress_proxy_config(; prefix::AbstractString="/live-htmxo",
                         target_env::AbstractString="HTMXO_DEV_TARGET",
                         default_target::AbstractString="http://localhost:8101") = """
        '$prefix': {
            target: process.env.$target_env || '$default_target',
            changeOrigin: true,
            rewrite: (path) => path.replace(/^$prefix/, ''),
        }
"""

# --- Utility classes ---

"""
    htmxo_utility_styles()

`<style>` block with HTMXO's small utility-class set. Replaces inline
`style="..."` on common patterns: visibility, cursor, flex/grid layout,
spacing, typography, and theme-aware text colors. All classes are scoped
under `@layer htmxo` so host stylesheets always win on conflict.

Class prefixes:
- `u-`            general utilities (display, layout, typography, spacing)
- `u-text-*`      semantic text colors mapped to `--htmxo-*` tokens
- `u-mt-*` etc.   margin / padding scale: `0`, `1` (0.25rem), `2` (0.5rem),
                  `3` (0.75rem), `4` (1rem), `5` (1.5rem), `6` (2rem)
"""
htmxo_utility_styles() = h.style(Raw("""
@layer htmxo {
/* === Generic behavior conventions === */
/* Any element triggering an htmx action is clickable. */
[hx-get], [hx-post], [hx-put], [hx-patch], [hx-delete] { cursor: pointer; }

/* `data-status` on a leaf text element (cells, badges, pills) colors the
   text by status; on a container with `.htmxo-status-banner` it colors the
   left border instead (see banner rules below). */
td[data-status], th[data-status], span[data-status], small[data-status] { font-weight: bold; }
[data-status="success"]:not(.htmxo-status-banner) { color: var(--htmxo-success); }
[data-status="error"]:not(.htmxo-status-banner)   { color: var(--htmxo-error); }
[data-status="warning"]:not(.htmxo-status-banner) { color: var(--htmxo-warning); }
[data-status="muted"]:not(.htmxo-status-banner)   { color: var(--htmxo-muted); }

.u-hidden { display: none; }
.u-inline { display: inline; }
.u-inline-block { display: inline-block; }
.u-block { display: block; }
.u-flex { display: flex; align-items: center; gap: 0.5rem; }
.u-flex-tight { display: flex; align-items: center; gap: 0.25rem; }
.u-flex-wide { display: flex; align-items: center; gap: 1rem; }
.u-flex-wrap { flex-wrap: wrap; }
.u-flex-between { display: flex; justify-content: space-between; align-items: center; }
.u-stack { display: flex; flex-direction: column; gap: 0.5rem; }
.u-stack-tight { display: flex; flex-direction: column; gap: 0.25rem; }
.u-stack-wide { display: flex; flex-direction: column; gap: 1rem; }
.u-grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.u-grid-auto { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
/* Sidebar + main page layout. Stacks on phone-sized viewports (<768px);
   becomes a 2-col grid above. Pair with `app_layout(sidebar, content)`. */
.htmxo-app-layout { display: block; min-height: 100vh; }
.htmxo-app-layout > aside { padding: 1rem 0; }
.htmxo-app-layout > main { min-width: 0; padding: 1rem 0; }
@media (min-width: 768px) {
    .htmxo-app-layout {
        display: grid;
        grid-template-columns: var(--htmxo-sidebar-width, 12rem) 1fr;
        grid-template-areas: "sidebar content";
        column-gap: 2rem;
    }
    .htmxo-app-layout > aside { grid-area: sidebar; padding: 1rem 1rem 1rem 0; border-right: 1px solid var(--pico-muted-border-color); }
    .htmxo-app-layout > main { grid-area: content; }
    .htmxo-app-layout > aside > nav { position: sticky; top: 1rem; max-height: calc(100vh - 2rem); overflow-y: auto; }
}
.u-bg-soft { background: var(--pico-card-background-color, #f8f8f8); }
.u-btn-sm { padding: 0.3rem 0.8rem; }
.u-btn-xs { padding: 0.2rem 0.6rem; }
.u-input-grow { flex: 1; min-width: 20rem; max-width: 500px; }
.u-link-plain { text-decoration: none; color: inherit; }
.u-my-2 { margin: 0.5rem 0; }
.u-my-1 { margin: 0.25rem 0; }
.u-my-4 { margin: 1rem 0; }
.u-pointer { cursor: pointer; }
.u-w-full { width: 100%; }
.u-grow { flex: 1; min-width: 0; }
.u-min-w-0 { min-width: 0; }
.u-narrow { max-width: 900px; }
.u-truncate { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.u-pre-wrap { white-space: pre-wrap; }
.u-mono { font-family: monospace; }
.u-no-border { border: none; }
.u-text-bold { font-weight: bold; }
.u-text-normal { font-weight: normal; }
.u-text-xs { font-size: 0.75em; }
.u-text-sm { font-size: 0.85em; }
.u-text-lg { font-size: 1.1em; }
.u-text-muted { color: var(--htmxo-muted); }
.u-text-success { color: var(--htmxo-success); }
.u-text-error { color: var(--htmxo-error); }
.u-text-warning { color: var(--htmxo-warning); }
.u-text-accent { color: var(--htmxo-accent); }
.u-text-center { text-align: center; }
.u-text-left { text-align: left; }
.u-text-right { text-align: right; }
.u-mt-0 { margin-top: 0; }
.u-mt-1 { margin-top: 0.25rem; }
.u-mt-2 { margin-top: 0.5rem; }
.u-mt-3 { margin-top: 0.75rem; }
.u-mt-4 { margin-top: 1rem; }
.u-mt-5 { margin-top: 1.5rem; }
.u-mt-6 { margin-top: 2rem; }
.u-mb-0 { margin-bottom: 0; }
.u-mb-1 { margin-bottom: 0.25rem; }
.u-mb-2 { margin-bottom: 0.5rem; }
.u-mb-3 { margin-bottom: 0.75rem; }
.u-mb-4 { margin-bottom: 1rem; }
.u-mb-5 { margin-bottom: 1.5rem; }
.u-mb-6 { margin-bottom: 2rem; }
.u-ml-1 { margin-left: 0.25rem; }
.u-ml-2 { margin-left: 0.5rem; }
.u-ml-4 { margin-left: 1rem; }
.u-mr-1 { margin-right: 0.25rem; }
.u-mr-2 { margin-right: 0.5rem; }
.u-mr-3 { margin-right: 0.75rem; }
.u-m-0 { margin: 0; }
.u-p-0 { padding: 0; }
.u-p-2 { padding: 0.5rem; }
.u-p-4 { padding: 1rem; }
.u-sticky-top { position: sticky; top: 0; max-height: 100vh; overflow-y: auto; }
.u-scroll-y { max-height: 300px; overflow: auto; }
.u-scroll-y-lg { max-height: 400px; overflow: auto; }
.u-card { background: var(--pico-card-background-color, transparent); padding: 1rem; border-radius: 0.5rem; }
.u-code-block { background: var(--pico-code-background-color, #f6f8fa); padding: 1rem; border-radius: 0.5rem; overflow-x: auto; }
/* Status banner — colored left-border callout. State via data-status. */
.htmxo-status-banner { padding: 0.5rem 1rem; margin-bottom: 0.5rem; min-width: 0; overflow: hidden; background: var(--pico-card-background-color, transparent); border-left: 4px solid var(--htmxo-border); }
.htmxo-status-banner[data-status="success"] { border-left-color: var(--htmxo-success); }
.htmxo-status-banner[data-status="error"]   { border-left-color: var(--htmxo-error); }
.htmxo-status-banner[data-status="warning"] { border-left-color: var(--htmxo-warning); }
.htmxo-status-banner[data-status="accent"]  { border-left-color: var(--htmxo-accent); }

/* Breadcrumb nav. Build with `htmxo_breadcrumb([("Home", "/", "/"), ...])`.
   Children are <span> (current page, marked aria-current) or <a> (link).
   Separators are generated via ::before — no separator element in markup. */
.htmxo-breadcrumb { font-size: 0.85em; margin-bottom: 1rem; padding: 6px 0; border-bottom: 1px solid var(--pico-muted-border-color); }
.htmxo-breadcrumb > * + *::before { content: ' / '; color: var(--pico-muted-color); margin: 0 6px; }
.htmxo-breadcrumb [aria-current="page"] { color: var(--pico-color); font-weight: 500; }
.htmxo-breadcrumb a { text-decoration: none; color: var(--pico-primary); }
.htmxo-breadcrumb a:hover { text-decoration: underline; }
.u-badge { display: inline-block; padding: 0.15em 0.5em; border-radius: 3px; font-size: 0.8em; font-weight: 600; line-height: 1.2; color: var(--htmxo-bg, #fff); background: var(--htmxo-muted); }
.u-badge.u-badge-success { background: var(--htmxo-success); }
.u-badge.u-badge-error   { background: var(--htmxo-error); }
.u-badge.u-badge-warning { background: var(--htmxo-warning); }
.u-badge.u-badge-accent  { background: var(--htmxo-accent); }
.u-badge.u-badge-muted   { background: var(--htmxo-muted); }
.u-badge-soft { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 1rem; font-size: 0.8em; line-height: 1.2; cursor: pointer; user-select: none; border: 1px solid transparent; background: color-mix(in srgb, var(--htmxo-muted) 25%, transparent); }
.u-badge-soft.u-badge-success { background: color-mix(in srgb, var(--htmxo-success) 35%, transparent); }
.u-badge-soft.u-badge-error   { background: color-mix(in srgb, var(--htmxo-error)   35%, transparent); }
.u-badge-soft.u-badge-warning { background: color-mix(in srgb, var(--htmxo-warning) 35%, transparent); }
.u-badge-soft.u-badge-accent  { background: color-mix(in srgb, var(--htmxo-accent)  35%, transparent); }

/* Generic equal-column grid. Column count and gap are tunable per
   instance via CSS variables on the element itself or an ancestor:
       <div class="htmxo-grid" style="--htmxo-grid-cols:16">…</div>   /* DON'T — inline */
   Apps should set the variables in their own scoped stylesheet:
       .my-app-dense-grid { --htmxo-grid-cols: 16; --htmxo-grid-gap: 0.25rem; }
       <div class="htmxo-grid my-app-dense-grid">…</div> */
.htmxo-grid {
    display: grid;
    grid-template-columns: repeat(var(--htmxo-grid-cols, 4), 1fr);
    gap: var(--htmxo-grid-gap, 0.5rem);
}

/* "← Back" link. Subtler than a primary link; sits above content as a
   navigation hint. Pair with `<a class="htmxo-back-link" href="…">← Back</a>`. */
.htmxo-back-link {
    display: inline-block;
    margin-bottom: 0.5rem;
    font-size: 0.9em;
    text-decoration: none;
    color: var(--htmxo-muted, currentColor);
}
.htmxo-back-link:hover { text-decoration: underline; }
}
"""))

# --- Request feedback ---

"""
    request_feedback_style()

CSS for automatic HTMX request feedback: pulsating border while in-flight,
brief color flash on success/failure. Themed via `--htmxo-accent`,
`--htmxo-success`, `--htmxo-error` (see [`htmxo_theme`](@ref)).
"""
request_feedback_style() = h.style(Raw("""
@layer htmxo {
@keyframes htmx-pulse {
    0%, 100% { outline-color: color-mix(in srgb, var(--htmxo-accent) 30%, transparent); }
    50% { outline-color: var(--htmxo-accent); }
}
.htmx-request-active {
    outline: 2px solid var(--htmxo-accent);
    outline-offset: -2px;
    animation: htmx-pulse 1s ease-in-out infinite;
}
.htmx-request-success {
    outline: 2px solid var(--htmxo-success);
    outline-offset: -2px;
    animation: htmx-fade-success 1s ease-out forwards;
}
.htmx-request-error {
    outline: 2px solid var(--htmxo-error);
    outline-offset: -2px;
    animation: htmx-fade-error 2s ease-out forwards;
}
@keyframes htmx-fade-success {
    0% { outline-color: var(--htmxo-success); }
    100% { outline-color: transparent; }
}
@keyframes htmx-fade-error {
    0% { outline-color: var(--htmxo-error); }
    100% { outline-color: transparent; }
}
}
"""))

"""
    request_feedback_script()

JS that hooks into HTMX events to add visual feedback classes on the target element
of each request.
"""
request_feedback_script() = h.script(Raw("""
document.addEventListener('DOMContentLoaded', function() {
    function getTarget(evt) {
        var elt = evt.detail.elt;
        var targetSel = elt.getAttribute('hx-target');
        if (targetSel) {
            if (targetSel === 'this') return elt;
            var found = document.querySelector(targetSel);
            if (found) return found;
        }
        return elt;
    }
    function isPolling(elt) {
        var trigger = elt.getAttribute('hx-trigger') || '';
        return trigger.indexOf('every') !== -1;
    }
    function isPollingRelated(elt) {
        return isPolling(elt) || (elt.querySelector && !!elt.querySelector('[hx-trigger*="every"]'));
    }
    function clearFeedback(el) {
        el.classList.remove('htmx-request-active', 'htmx-request-success', 'htmx-request-error');
    }
    document.body.addEventListener('htmx:beforeRequest', function(e) {
        var elt = e.detail.elt;
        if (isPolling(elt)) return;
        var t = getTarget(e);
        clearFeedback(t);
        t.classList.add('htmx-request-active');
        if (t !== elt) {
            clearFeedback(elt);
            elt.classList.add('htmx-request-active');
        }
    });
    document.body.addEventListener('htmx:oobAfterSwap', function(e) {
        var t = e.detail.target || e.detail.elt;
        if (!t) return;
        clearFeedback(t);
        t.classList.add('htmx-request-success');
        setTimeout(function() { clearFeedback(t); }, 1000);
    });
    document.body.addEventListener('htmx:afterRequest', function(e) {
        var elt = e.detail.elt;
        if (isPollingRelated(elt)) return;
        var t = getTarget(e);
        t.classList.remove('htmx-request-active');
        if (e.detail.successful) {
            t.classList.add('htmx-request-success');
            setTimeout(function() { clearFeedback(t); }, 1000);
            if (t !== elt) {
                elt.classList.remove('htmx-request-active');
                elt.classList.add('htmx-request-success');
                setTimeout(function() { clearFeedback(elt); }, 1000);
            }
        } else {
            t.classList.add('htmx-request-error');
            setTimeout(function() { clearFeedback(t); }, 2000);
            if (t !== elt) {
                elt.classList.add('htmx-request-error');
                setTimeout(function() { clearFeedback(elt); }, 2000);
            }
        }
    });
});
"""))

"""
    request_feedback()

Combined style + script nodes for automatic HTMX request feedback.
Included by default in `htmx()`.
"""
request_feedback() = (request_feedback_style(), request_feedback_script())

"""
    overlay_bar_style()

CSS for the framework debug/dev overlay bar — a thin fixed bottom strip
(collapsed: app · route · owner · Report; opened: the bug/feedback report
form). Plain `#id`-scoped rules (no `@layer`) so it sits above app content
and Pico regardless of stacking. Injected by [`htmx`](@ref) when `overlay=true`.
"""
overlay_bar_style() = h.style(Raw("""
#htmxo-overlay-bar {
  position: fixed; left: 0; right: 0; bottom: 0; z-index: 2147483000;
  font: 13px/1.4 system-ui, -apple-system, sans-serif;
  background: var(--htmxo-overlay-bg, #1e1e2e); color: var(--htmxo-overlay-fg, #e8e8f0);
  border-top: 1px solid rgba(255,255,255,.12); box-shadow: 0 -2px 12px rgba(0,0,0,.25);
}
#htmxo-overlay-bar .hob-collapsed { display: flex; align-items: center; gap: 1rem; padding: 4px 12px; }
#htmxo-overlay-bar .hob-secure { flex: 0 0 auto; cursor: default; }
#htmxo-overlay-bar .hob-id { flex: 1 1 auto; font-weight: 600; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
#htmxo-overlay-bar .hob-route { opacity: .85; font-weight: 400; }
#htmxo-overlay-bar .hob-owner { opacity: .75; }
#htmxo-overlay-bar .hob-toggle { background: rgba(255,255,255,.12); color: inherit; border: 0; border-radius: 4px; padding: 2px 10px; cursor: pointer; font: inherit; }
#htmxo-overlay-bar[data-state="collapsed"] .hob-form,
#htmxo-overlay-bar[data-state="collapsed"] .hob-chat { display: none; }
#htmxo-overlay-bar[data-state="open"] .hob-collapsed,
#htmxo-overlay-bar[data-state="open"] .hob-chat { display: none; }
#htmxo-overlay-bar[data-state="chat"] .hob-collapsed,
#htmxo-overlay-bar[data-state="chat"] .hob-form { display: none; }
#htmxo-overlay-bar .hob-form { display: block; padding: 8px 12px; }
#htmxo-overlay-bar .hob-formhead { display: flex; gap: 1rem; align-items: center; margin-bottom: 6px; font-weight: 600; }
#htmxo-overlay-bar .hob-fh-id { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
#htmxo-overlay-bar .hob-fh-owner { opacity: .75; font-weight: 400; }
#htmxo-overlay-bar .hob-kind { display: flex; gap: 1rem; margin-bottom: 6px; }
#htmxo-overlay-bar .hob-text { width: 100%; box-sizing: border-box; background: rgba(0,0,0,.25); color: inherit; border: 1px solid rgba(255,255,255,.15); border-radius: 4px; padding: 6px; font: inherit; resize: vertical; }
#htmxo-overlay-bar .hob-opts { display: flex; gap: 1rem; margin: 6px 0; opacity: .9; }
#htmxo-overlay-bar .hob-actions { display: flex; align-items: center; gap: 1rem; }
#htmxo-overlay-bar .hob-status { opacity: .85; }
#htmxo-overlay-bar .hob-send { margin-left: auto; background: var(--htmxo-overlay-accent, #7c6ff0); color: #fff; border: 0; border-radius: 4px; padding: 4px 16px; cursor: pointer; font: inherit; font-weight: 600; }
#htmxo-overlay-bar .hob-send:disabled { opacity: .5; cursor: default; }
#htmxo-overlay-bar code { background: rgba(0,0,0,.3); padding: 0 4px; border-radius: 3px; }
#htmxo-overlay-bar[data-state="chat"] .hob-chat { display: flex; flex-direction: column; padding: 8px 12px; max-height: 80vh; }
#htmxo-overlay-bar .hob-chathead { display: flex; gap: 1rem; align-items: center; margin-bottom: 6px; font-weight: 600; }
#htmxo-overlay-bar .hob-ch-title { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
#htmxo-overlay-bar .hob-ch-todo { color: var(--htmxo-overlay-accent, #7c6ff0); text-decoration: none; font-weight: 400; }
#htmxo-overlay-bar .hob-ch-pick,
#htmxo-overlay-bar .hob-ch-close { background: rgba(255,255,255,.12); color: inherit; border: 0; border-radius: 4px; padding: 2px 8px; cursor: pointer; font: inherit; font-size: 12px; }
#htmxo-overlay-bar .hob-ch-thread { overflow-y: auto; resize: vertical; height: 40vh; min-height: 12vh; max-height: 80vh; background: rgba(0,0,0,.18); border-radius: 4px; padding: 6px; margin-bottom: 6px; }
#htmxo-overlay-bar .hob-ch-thread .kb-msg-window { margin: 0; }
#htmxo-overlay-bar .hob-ch-compose { display: flex; gap: .5rem; align-items: flex-end; }
#htmxo-overlay-bar .hob-ch-text { flex: 1 1 auto; box-sizing: border-box; background: rgba(0,0,0,.25); color: inherit; border: 1px solid rgba(255,255,255,.15); border-radius: 4px; padding: 6px; font: inherit; resize: vertical; }
#htmxo-overlay-bar .hob-ch-send { background: var(--htmxo-overlay-accent, #7c6ff0); color: #fff; border: 0; border-radius: 4px; padding: 6px 16px; cursor: pointer; font: inherit; font-weight: 600; }
#htmxo-overlay-bar .hob-ch-send:disabled { opacity: .5; cursor: default; }
#htmxo-overlay-bar .hob-ch-status { opacity: .85; margin-top: 4px; min-height: 1em; }
#htmxo-overlay-bar .kb-bubble.hob-anchor { outline: 2px solid var(--htmxo-overlay-accent, #7c6ff0); outline-offset: 1px; border-radius: 4px; animation: hob-flash 1.4s ease-out; }
@keyframes hob-flash { from { background: rgba(124,111,240,.4); } to { background: transparent; } }
@media print { #htmxo-overlay-bar { display: none; } }
"""))

"""
    overlay_bar_script()

JS for the overlay bar (D1 + D3). On `DOMContentLoaded` it builds the strip
DOM, resolves where-you-are from `window.location` (proxied `/p/<slug>/…` →
slug from the path; direct → app via `/agents/app-for-port?port=`), and
attaches `document.body` htmx-event listeners: route tracking through partial
swaps (`htmx:pushedIntoHistory` / `htmx:historyRestore` / `popstate` /
`htmx:afterSettle`) and a traffic observer (`htmx:afterRequest` /
`htmx:sendError`) that captures a FAILED app request — reading the
`X-HTMXO-Error-Id` response header — as pre-filled bug context. The report
posts raw context to the root-absolute `POST /agents/report`; the KB resolves
the owner and files the todo.

On a successful report the bar **morphs into a live chat** (`data-state="chat"`)
with the resolved owner: it renders the owner's thread via
`GET /agents/<owner>/messages?embedded=1&around=<seed-ts>` (chrome-stripped to
the `kb-msg-window`), anchors+highlights the just-filed report bubble
(`[data-ts]`, falling back to the latest-window + last bubble when `/report`
returns no seed `ts`), and opens an inline reply box that `POST`s to
`/agents/<owner>/dispatch` (`from=user`). Live updates ride the `@ws events()`
hub at `/agents/events` (filtering the `messages:<owner>` marker), with a ~10s
poll fallback until that marker is wired. A "change agent" control re-targets
the chat and the owner's durable todo is cross-linked in the header.

All KB calls are root-absolute (same-origin via the prefix-proxy) and degrade
visibly if an endpoint isn't reachable.
"""
overlay_bar_script() = h.script(Raw("""
document.addEventListener('DOMContentLoaded', function() {
  if (window.__htmxoOverlayInit) { return; }
  window.__htmxoOverlayInit = true;

  var ctx = { app: '', route: '/', url: '', owner: '', proxied: false };
  var lastError = null;
  var bar, collapsedOwner, fhId, fhOwner, errRow, errUid, statusEl, textEl, sendBtn, inclErr, appEl, routeEl;
  var chatThread, chatText, chatSendBtn, chatTitle, chatTodo, chatPick, chatClose, chatStatus;
  var chatOwner = '', chatTodoUrl = '', chatWs = null, chatPoll = null;
  var FUTURE_TS = '2099-01-01T00:00:00';
  var origPadBottom = null;

  // The bar is position:fixed;bottom:0, so it floats OVER the last bar-height
  // of page content. Reserve that space at the page bottom = the bar's CURRENT
  // height (collapsed ~30px / open / chat up to 60vh) so bottom content scrolls
  // clear above it. We add to the app's OWN body padding-bottom (captured once)
  // rather than clobbering it, and also expose the height as `--htmxo-overlay-h`
  // for apps that want it. A ResizeObserver on the bar keeps this in sync across
  // every state transition, async chat-content growth, and viewport resize.
  function syncOverlayPad() {
    if (!bar) { return; }
    if (origPadBottom === null) {
      origPadBottom = parseFloat(window.getComputedStyle(document.body).paddingBottom) || 0;
    }
    var h = bar.offsetHeight || 0;
    document.body.style.paddingBottom = (origPadBottom + h) + 'px';
    document.documentElement.style.setProperty('--htmxo-overlay-h', h + 'px');
  }

  function parseLocation() {
    var path = window.location.pathname || '/';
    var parts = path.split('/').filter(function(s) { return s.length > 0; });
    if (parts.length >= 2 && parts[0] === 'p') {
      ctx.proxied = true; ctx.app = parts[1]; ctx.route = '/' + parts.slice(2).join('/');
    } else {
      ctx.proxied = false; ctx.route = path;
    }
    if (ctx.route === '') { ctx.route = '/'; }
    ctx.url = window.location.href;
  }

  function buildBar() {
    bar = document.createElement('div');
    bar.id = 'htmxo-overlay-bar';
    bar.setAttribute('data-state', 'collapsed');
    bar.innerHTML =
      '<div class="hob-collapsed">' +
        '<span class="hob-secure" title="Secure deployment" hidden>&#128274;</span>' +
        '<span class="hob-id"><span class="hob-app"></span> · <span class="hob-route"></span></span>' +
        '<span class="hob-owner"></span>' +
        '<button type="button" class="hob-toggle">Report &#9650;</button>' +
      '</div>' +
      '<form class="hob-form">' +
        '<div class="hob-formhead"><span class="hob-secure" title="Secure deployment" hidden>&#128274;</span><span class="hob-fh-id"></span><span class="hob-fh-owner"></span>' +
          '<button type="button" class="hob-toggle">&#9660;</button></div>' +
        '<div class="hob-kind">' +
          '<label><input type="radio" name="hob-kind" value="bug" checked> bug</label>' +
          '<label><input type="radio" name="hob-kind" value="feedback"> feedback</label>' +
        '</div>' +
        '<textarea class="hob-text" rows="3" placeholder="what happened…"></textarea>' +
        '<div class="hob-opts">' +
          '<label><input type="checkbox" class="hob-incl-ctx" checked> route+state</label>' +
          '<label class="hob-errrow" hidden><input type="checkbox" class="hob-incl-err" checked> error-log <code class="hob-erruid"></code></label>' +
        '</div>' +
        '<div class="hob-actions"><span class="hob-status"></span>' +
          '<button type="button" class="hob-send">Send</button></div>' +
      '</form>' +
      '<div class="hob-chat">' +
        '<div class="hob-chathead">' +
          '<span class="hob-secure" title="Secure deployment" hidden>&#128274;</span>' +
          '<span class="hob-ch-title"></span>' +
          '<a class="hob-ch-todo" target="_blank" rel="noopener" hidden>todo &#8599;</a>' +
          '<button type="button" class="hob-ch-pick">change agent</button>' +
          '<button type="button" class="hob-ch-close">&#9660;</button>' +
        '</div>' +
        '<div class="hob-ch-thread"></div>' +
        '<div class="hob-ch-compose">' +
          '<textarea class="hob-ch-text" rows="2" placeholder="reply to this agent…"></textarea>' +
          '<button type="button" class="hob-ch-send">Send</button>' +
        '</div>' +
        '<div class="hob-ch-status"></div>' +
      '</div>';
    document.body.appendChild(bar);
    appEl = bar.querySelector('.hob-app');
    routeEl = bar.querySelector('.hob-route');
    collapsedOwner = bar.querySelector('.hob-owner');
    fhId = bar.querySelector('.hob-fh-id');
    fhOwner = bar.querySelector('.hob-fh-owner');
    errRow = bar.querySelector('.hob-errrow');
    errUid = bar.querySelector('.hob-erruid');
    statusEl = bar.querySelector('.hob-status');
    textEl = bar.querySelector('.hob-text');
    sendBtn = bar.querySelector('.hob-send');
    inclErr = bar.querySelector('.hob-incl-err');
    chatTitle = bar.querySelector('.hob-ch-title');
    chatTodo = bar.querySelector('.hob-ch-todo');
    chatPick = bar.querySelector('.hob-ch-pick');
    chatClose = bar.querySelector('.hob-ch-close');
    chatThread = bar.querySelector('.hob-ch-thread');
    chatText = bar.querySelector('.hob-ch-text');
    chatSendBtn = bar.querySelector('.hob-ch-send');
    chatStatus = bar.querySelector('.hob-ch-status');
    var toggles = bar.querySelectorAll('.hob-toggle');
    for (var i = 0; i < toggles.length; i++) { toggles[i].addEventListener('click', toggleOpen); }
    sendBtn.addEventListener('click', send);
    chatSendBtn.addEventListener('click', sendChat);
    chatPick.addEventListener('click', pickAgent);
    chatClose.addEventListener('click', closeChat);
    chatText.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendChat(); }
    });
  }

  function render() {
    var appLabel = ctx.app || '(app)';
    appEl.textContent = '🐞 ' + appLabel;
    routeEl.textContent = ctx.route;
    collapsedOwner.textContent = ctx.owner ? ('👤 ' + ctx.owner) : '';
    fhId.textContent = appLabel + ' · ' + ctx.route;
    fhOwner.textContent = ctx.owner ? ('owner: ' + ctx.owner) : '';
  }

  function refresh() { parseLocation(); render(); }

  function toggleOpen() {
    var open = bar.getAttribute('data-state') === 'open';
    bar.setAttribute('data-state', open ? 'collapsed' : 'open');
    if (!open) { statusEl.textContent = ''; refresh(); }
  }

  function resolveOwner() {
    var q = ctx.proxied ? ('slug=' + encodeURIComponent(ctx.app))
                        : ('port=' + encodeURIComponent(window.location.port));
    fetch('/agents/app_for_port?' + q, { headers: { 'Accept': 'application/json' } })
      .then(function(r) { return r.ok ? r.json() : null; })
      .then(function(d) {
        if (!d) { return; }
        if (d.slug && !ctx.app) { ctx.app = d.slug; }
        if (d.owner) { ctx.owner = d.owner; }
        render();
        // Direct access: the slug is only known once app_for_port resolves it.
        // (Proxied access already knows it from the path — see the init call.)
        if (!ctx.proxied) { applySecure(ctx.app); }
      })
      .catch(function() {});
  }

  // Surface the secure-deployment soft-guard (backend decision d22m82) in the
  // UI: /repos carries `secure` per slug, so when the resolved slug is secure
  // we reveal the 🔒 badges (collapsed strip + form/chat heads). Defensive and
  // async — any failure leaves the badges hidden (fail-safe: default not-secure).
  function applySecure(slug) {
    if (!slug) { return; }
    fetch('/repos', { headers: { 'Accept': 'application/json' } })
      .then(function(r) { return r.ok ? r.json() : null; })
      .then(function(list) {
        if (!list || !list.length) { return; }
        var secure = false;
        for (var i = 0; i < list.length; i++) {
          if (list[i] && list[i].name === slug) { secure = !!list[i].secure; break; }
        }
        if (!secure) { return; }
        var els = bar.querySelectorAll('.hob-secure');
        for (var j = 0; j < els.length; j++) { els[j].hidden = false; }
      })
      .catch(function() {});
  }

  function captureError(uid, status) {
    lastError = { uid: uid, status: status };
    errRow.hidden = false;
    errUid.textContent = uid ? ('#' + uid) : ('HTTP ' + status);
    var bug = bar.querySelector('input[name="hob-kind"][value="bug"]');
    if (bug) { bug.checked = true; }
  }

  function attachObservers() {
    document.body.addEventListener('htmx:pushedIntoHistory', refresh);
    document.body.addEventListener('htmx:historyRestore', refresh);
    window.addEventListener('popstate', refresh);
    document.body.addEventListener('htmx:afterSettle', refresh);
    document.body.addEventListener('htmx:afterRequest', function(e) {
      var xhr = e.detail && e.detail.xhr;
      if (!xhr) { return; }
      var failed = (e.detail.successful === false) || (xhr.status >= 400);
      if (!failed) { return; }
      var uid = '';
      try { uid = xhr.getResponseHeader('X-HTMXO-Error-Id') || ''; } catch (err) {}
      captureError(uid, xhr.status);
    });
    document.body.addEventListener('htmx:sendError', function(e) { captureError('', 0); });
  }

  function fetchThread(aroundTs) {
    var u = '/agents/' + encodeURIComponent(chatOwner) + '/messages?embedded=1&around=' + encodeURIComponent(aroundTs);
    // HX-Request: true => the KB returns the bare kb-msg-window fragment (no full-page
    // chrome); the kb-msg-window strip below is then just belt-and-suspenders.
    return fetch(u, { headers: { 'Accept': 'text/html', 'HX-Request': 'true' } })
      .then(function(r) { return r.ok ? r.text() : Promise.reject('HTTP ' + r.status); });
  }

  // Wake-safe anchor: seed_ts is a reliable LOWER BOUND, not the bubble's exact
  // ts (the woken-agent case stamps the turn ts async, a few seconds later). So
  // we highlight the newest from=user bubble with ts >= floorTs — the just-filed
  // report is always the newest user turn right after the POST — not an exact
  // data-ts == seed_ts match (which misses the wake case).
  function pickAnchor(floorTs) {
    var users = chatThread.querySelectorAll('.kb-bubble[data-role="user"]');
    var best = null;
    for (var i = 0; i < users.length; i++) {
      var ts = users[i].getAttribute('data-ts') || '';
      if (!floorTs || ts >= floorTs) { best = users[i]; }
    }
    if (best) { return best; }
    if (users.length) { return users[users.length - 1]; }
    var all = chatThread.querySelectorAll('.kb-bubble');
    return all.length ? all[all.length - 1] : null;
  }

  function injectThread(html, floorTs, keepScroll) {
    var atBottom = keepScroll && chatThread.scrollHeight > 0 &&
      (chatThread.scrollHeight - chatThread.scrollTop - chatThread.clientHeight) < 48;
    var tmp = document.createElement('div');
    tmp.innerHTML = html;
    // Defensive chrome-strip: keep only the message window until leg 3 slims embedded=1.
    var win = tmp.querySelector('.kb-msg-window');
    chatThread.innerHTML = '';
    chatThread.appendChild(win ? win : tmp);
    if (window.htmx) { try { window.htmx.process(chatThread); } catch (e) {} }
    if (keepScroll) {
      if (atBottom) { chatThread.scrollTop = chatThread.scrollHeight; }
      return;
    }
    var target = pickAnchor(floorTs);
    if (target) {
      target.classList.add('hob-anchor');
      target.scrollIntoView({ block: 'center' });
    } else {
      chatThread.scrollTop = chatThread.scrollHeight;
    }
  }

  function reloadLatest() {
    if (!chatOwner) { return; }
    fetchThread(FUTURE_TS).then(function(html) {
      injectThread(html, '', true);
    }).catch(function() {});
  }

  function subscribeWs() {
    if (chatWs) { try { chatWs.close(); } catch (e) {} chatWs = null; }
    try {
      var proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      var sock = new WebSocket(proto + '//' + window.location.host + '/agents/events');
      chatWs = sock;
      sock.onmessage = function(ev) {
        if ((ev.data || '') === ('messages:' + chatOwner)) { reloadLatest(); }
      };
      sock.onclose = function() { if (chatWs === sock) { chatWs = null; } };
      sock.onerror = function() {};
    } catch (e) { chatWs = null; }
  }

  function startPoll() {
    stopPoll();
    // Fallback until leg 3 wires the messages:<aid> live-push marker.
    chatPoll = setInterval(reloadLatest, 10000);
  }
  function stopPoll() { if (chatPoll) { clearInterval(chatPoll); chatPoll = null; } }

  function enterChat(owner, todoUrl, seedTs) {
    if (!owner) { return; }
    chatOwner = owner;
    chatTodoUrl = todoUrl || '';
    bar.setAttribute('data-state', 'chat');
    chatTitle.textContent = '💬 ' + owner;
    if (chatTodoUrl) { chatTodo.setAttribute('href', chatTodoUrl); chatTodo.hidden = false; }
    else { chatTodo.hidden = true; }
    chatStatus.textContent = 'loading…';
    var anchor = seedTs || FUTURE_TS;
    var highlight = seedTs || '';
    fetchThread(anchor).then(function(html) {
      injectThread(html, highlight, false);
      chatStatus.textContent = '';
    }).catch(function(err) {
      chatStatus.textContent = 'could not load thread (' + err + ')';
    });
    subscribeWs();
    startPoll();
  }

  function sendChat() {
    var msg = (chatText.value || '').trim();
    if (!msg || !chatOwner) { return; }
    chatSendBtn.disabled = true;
    chatStatus.textContent = 'sending…';
    var b = new URLSearchParams();
    b.set('from', 'user');
    b.set('message', msg);
    fetch('/agents/' + encodeURIComponent(chatOwner) + '/dispatch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: b.toString()
    }).then(function(r) {
      if (!r.ok) { return Promise.reject('HTTP ' + r.status); }
    }).then(function() {
      chatText.value = '';
      chatStatus.textContent = '';
      reloadLatest();
    }).catch(function(err) {
      chatStatus.textContent = 'send failed (' + err + ')';
    }).then(function() { chatSendBtn.disabled = false; });
  }

  function pickAgent() {
    var who = window.prompt('Chat with which agent?', chatOwner);
    if (!who) { return; }
    who = who.trim();
    if (!who || who === chatOwner) { return; }
    enterChat(who, chatTodoUrl, '');
  }

  function closeChat() {
    if (chatWs) { try { chatWs.close(); } catch (e) {} chatWs = null; }
    stopPoll();
    bar.setAttribute('data-state', 'collapsed');
    statusEl.textContent = '';
    refresh();
  }

  function send() {
    refresh();
    var kindEl = bar.querySelector('input[name="hob-kind"]:checked');
    var inclErrOn = inclErr && !errRow.hidden && inclErr.checked;
    var body = new URLSearchParams();
    body.set('kind', kindEl ? kindEl.value : 'bug');
    body.set('text', textEl.value || '');
    body.set('app', ctx.app || '');
    body.set('route', ctx.route || '');
    body.set('url', ctx.url || '');
    var euid = (inclErrOn && lastError) ? (lastError.uid || '') : '';
    if (euid) { body.set('error_uid', euid); }
    // screenshot: reserved field, not captured in v1 (omitted when none).
    statusEl.textContent = 'sending…';
    sendBtn.disabled = true;
    fetch('/agents/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    }).then(function(r) {
      if (!r.ok) { return Promise.reject('HTTP ' + r.status); }
      return r.json().catch(function() { return {}; });
    }).then(function(d) {
      textEl.value = '';
      var owner = (d && d.owner) ? d.owner : ctx.owner;
      var todoUrl = (d && d.todo_url) ? d.todo_url : '';
      // Seed ts from /report (ask #1, leg 1) — `seed_ts` is the contract key; it
      // is a LOWER BOUND used to scope the window (see pickAnchor). Empty => latest-window.
      var seedTs = (d && (d.seed_ts || d.ts || d.thread_ts)) || '';
      if (owner) {
        statusEl.textContent = 'filed → ' + owner;
        enterChat(owner, todoUrl, seedTs);
      } else {
        statusEl.textContent = 'filed';
        setTimeout(function() { bar.setAttribute('data-state', 'collapsed'); statusEl.textContent = ''; }, 1800);
      }
    }).catch(function(err) {
      statusEl.textContent = 'could not file (' + err + ')';
    }).then(function() { sendBtn.disabled = false; });
  }

  buildBar();
  parseLocation();
  render();
  resolveOwner();
  // Proxied access knows its slug from the /p/<slug>/ path right away — resolve
  // secure-ness immediately. (Direct access fires this from resolveOwner once
  // app_for_port supplies the slug.)
  if (ctx.proxied) { applySecure(ctx.app); }
  attachObservers();
  syncOverlayPad();
  // ResizeObserver catches every bar height change — state transitions
  // (collapsed↔open↔chat), async chat-thread growth, and 60vh shifts on
  // viewport resize — in one registration. The resize listener is a cheap
  // fallback for browsers without ResizeObserver.
  if (window.ResizeObserver) {
    try { new ResizeObserver(syncOverlayPad).observe(bar); } catch (e) {}
  }
  window.addEventListener('resize', syncOverlayPad);
});
"""))

"""
    KB_ORIGIN

Origin prefix for the relocated overlay bundle served at
`<KB_ORIGIN>/overlay/bar.js` — the thin-hook bootstrap `htmx(...; overlay=true)`
emits in place of the old inline `<style>`+`<script>`. Default `""` →
root-absolute `/overlay/bar.js`, same-origin under the supported `/p/<slug>/`
proxy. Set to an absolute origin (e.g. `"http://localhost:4200"`) for
direct-port / dev access; the pre-existing cross-origin runtime-fetch limit
then applies (the bar's own `/repos` + `/agents/...` calls are same-origin to
the *page*, not to `KB_ORIGIN`) — documented here, not solved.
"""
const KB_ORIGIN = ""

"""
    overlay_bar()

!!! note "Dead code as of the th8p6p thin-hook cutover"
    `htmx(...; overlay=true)` no longer injects this inline bundle — it emits a
    single `<script src=\$KB_ORIGIN/overlay/bar.js defer>` bootstrap instead, and
    the real `overlay_bar_script`/`overlay_bar_style` are served from the KB at
    `/overlay/bar.js`. These three definitions are retained (not called) only to
    keep the flip minimal + cleanly revertible; removal is a later follow-up.

Combined style + script for the framework debug/dev overlay bar (the v1
feedback spine). Was injected by [`htmx`](@ref) on full-page responses when
`overlay=true` (the default; pass `overlay=false` to opt out). The bar resolves
its own context client-side and talks to the KB root-absolute, mirroring
[`request_feedback`](@ref)'s zero-server-context model.
"""
overlay_bar() = (overlay_bar_style(), overlay_bar_script())

"""
    compose_box_styles()

CSS for the [`compose_box`](@ref) auto-growing compose textarea + the toast it
raises on a failed submit. Deliberately **unlayered** (not inside
`@layer htmxo`) so the `.htmxo-compose-textarea` class beats Pico's unlayered
`textarea { resize: … }` rule — a layered rule would lose regardless of
specificity and the drag-handle/scrollbar would reappear.
"""
compose_box_styles() = h.style(Raw(raw"""
.htmxo-compose-textarea {
    resize: none; overflow: hidden; field-sizing: content; line-height: 1.4;
}
.htmxo-toast {
    position: fixed; bottom: 1rem; right: 1rem; z-index: 9999;
    padding: 0.5rem 0.85rem; border-radius: 0.3rem; font-size: 0.85em;
    background: var(--pico-card-background-color, #fff);
    border: 1px solid var(--pico-muted-border-color, #ccc);
    box-shadow: 0 2px 8px rgba(0,0,0,0.15); max-width: 28rem;
    opacity: 0; transform: translateY(0.5rem);
    transition: opacity 0.3s ease, transform 0.3s ease;
}
.htmxo-toast-show { opacity: 1; transform: translateY(0); }
.htmxo-toast-error { border-color: var(--pico-color-red-500, #d32f2f); color: var(--pico-color-red-500, #d32f2f); }
.htmxo-toast-info { color: var(--pico-color, inherit); }
"""))

"""
    compose_box_script()

JS driving [`compose_box`](@ref): auto-grow (no-op when the browser supports
`field-sizing: content`, JS fallback otherwise), Enter-to-send /
Shift+Enter-newline, localStorage draft persistence for `.htmxo-compose-draft`
elements (keyed by `data-draft-key`), and a submit guard on
`.htmxo-compose-form` forms (clear drafts + reset on 2xx, toast on
failure / network error). Re-binds on `htmx:afterSettle`; idempotent per
element. Exposes `window.htmxoToast(text, status)` and
`window.htmxoComposeRebind(root)` for reuse. Body-listener attachment is
deferred to `DOMContentLoaded` so the script is safe to inject in `<head>`.
"""
compose_box_script() = h.script(Raw(raw"""
(function() {
    var FIELD_SIZING = !!(window.CSS && CSS.supports && CSS.supports('field-sizing', 'content'));
    function autoGrow(el) {
        if (!el || FIELD_SIZING) return;
        el.style.height = 'auto';
        el.style.height = el.scrollHeight + 'px';
    }
    function draftKey(el) { return el.getAttribute('data-draft-key') || ''; }
    function restoreDrafts(root) {
        var scope = root && root.querySelectorAll ? root : document;
        scope.querySelectorAll('.htmxo-compose-draft').forEach(function(el) {
            if (el.dataset.htmxoDraftBound === '1') return;
            el.dataset.htmxoDraftBound = '1';
            var k = draftKey(el);
            if (!k) return;
            try { var saved = localStorage.getItem(k); if (saved && !el.value) el.value = saved; } catch (e) {}
            if (el.classList.contains('htmxo-compose-textarea')) autoGrow(el);
            el.addEventListener('input', function() {
                try { if (el.value) localStorage.setItem(k, el.value); else localStorage.removeItem(k); } catch (e) {}
            });
        });
    }
    function bindTextareas(root) {
        var scope = root && root.querySelectorAll ? root : document;
        scope.querySelectorAll('.htmxo-compose-textarea').forEach(function(el) {
            if (el.dataset.htmxoTaBound === '1') { autoGrow(el); return; }
            el.dataset.htmxoTaBound = '1';
            autoGrow(el);
            el.addEventListener('input', function() { autoGrow(el); });
            el.addEventListener('keydown', function(e) {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    var f = el.closest('form');
                    if (!f) return;
                    if (f.requestSubmit) f.requestSubmit();
                    else f.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
                }
            });
        });
    }
    function clearFormDrafts(form) {
        form.querySelectorAll('.htmxo-compose-draft').forEach(function(el) {
            var k = draftKey(el); if (!k) return;
            try { localStorage.removeItem(k); } catch (e) {}
        });
    }
    function toast(text, status) {
        var t = document.createElement('div');
        t.className = 'htmxo-toast htmxo-toast-' + (status || 'info');
        t.textContent = text;
        document.body.appendChild(t);
        void t.offsetWidth;
        t.classList.add('htmxo-toast-show');
        setTimeout(function() {
            t.classList.remove('htmxo-toast-show');
            setTimeout(function() { t.remove(); }, 350);
        }, 4000);
    }
    window.htmxoToast = toast;
    window.htmxoComposeRebind = function(root) { restoreDrafts(root); bindTextareas(root); };
    function init() {
        restoreDrafts(document);
        bindTextareas(document);
        document.body.addEventListener('htmx:afterSettle', function(evt) {
            restoreDrafts(evt.detail && evt.detail.elt);
            bindTextareas(evt.detail && evt.detail.elt);
        });
        // 2xx → clear drafts + reset the form. Non-2xx → keep value, toast.
        document.body.addEventListener('htmx:afterRequest', function(evt) {
            var form = evt.target && evt.target.closest && evt.target.closest('.htmxo-compose-form');
            if (!form) return;
            if (evt.detail && evt.detail.successful) {
                clearFormDrafts(form);
                form.reset();
                form.querySelectorAll('.htmxo-compose-textarea').forEach(autoGrow);
            } else {
                toast('send failed — your text is preserved, retry when ready', 'error');
            }
        });
        // No response at all (server down, network drop). Same UX as a non-2xx.
        document.body.addEventListener('htmx:sendError', function(evt) {
            var form = evt.target && evt.target.closest && evt.target.closest('.htmxo-compose-form');
            if (!form) return;
            toast('send failed — unreachable; your text is preserved', 'error');
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
})();
"""))

"""
    compose_box_assets()

Combined style + script nodes for [`compose_box`](@ref). Injected into the
page head by `htmx(...)` when `compose=true` (the default), mirroring
[`request_feedback`](@ref).
"""
compose_box_assets() = (compose_box_styles(), compose_box_script())

"""
    compose_box(name; value="", placeholder="", draft_key=nothing, rows=1, class="")

Emit an auto-growing `<textarea>` compose box: it sizes to its content (one row
when empty via `rows=1`, growing with each wrapped/entered line, no scrollbar
or drag handle), and submits its enclosing `<form>` on Enter (Shift+Enter
inserts a newline).

For the draft-persistence and submit-feedback behaviour, the surrounding form
should carry the `htmxo-compose-form` class — then a 2xx submit clears drafts +
resets the box and a failed/again-unreachable submit raises a toast while
preserving the typed text. Pass `draft_key` to persist the in-progress text to
`localStorage` under that key (the box also gets the `htmxo-compose-draft`
class). All behaviour is driven by [`compose_box_assets`](@ref), injected by
`htmx(...; compose=true)` by default.
"""
function compose_box(name; value="", placeholder="", draft_key=nothing, rows=1, class="")
    cls = "htmxo-compose-textarea"
    isnothing(draft_key) || (cls *= " htmxo-compose-draft")
    isempty(class)       || (cls *= " " * class)
    isnothing(draft_key) ?
        h.textarea(value; name, rows, placeholder, class=cls) :
        h.textarea(value; name, rows, placeholder, class=cls, data_draft_key=draft_key)
end

"""
    loading_indicator_script()

Return a `Node` `<script>` that sets `aria-busy` on HTMX target elements during
requests. Pico CSS renders a spinner automatically for `aria-busy` elements.

!!! note
    Deprecated in favor of `request_feedback()` which provides richer visual feedback.
"""
loading_indicator_script() = h.script(Raw("""
document.body.addEventListener('htmx:beforeRequest', function(e) {
    e.detail.elt.setAttribute('aria-busy', 'true');
});
document.body.addEventListener('htmx:afterRequest', function(e) {
    e.detail.elt.removeAttribute('aria-busy');
});
"""))

# --- Tabset ---

"""
    tabset_styles()

CSS that turns `tabset(...)`'s Pico `<nav>` + `.tab-panel` markup into a
classic tab strip: the active tab's border-bottom replaces the nav's
horizontal rule along its own width, producing one continuous line.

Scoped to `.tabset` on the outer `<div>`, so plain `<nav><ul>` menus elsewhere
are untouched. Auto-included by `htmx()`; inject manually via `extra_head`
if you're building your own `<head>`.
"""
tabset_styles() = h.style(Raw("""
@layer htmxo {
.tabset > nav {
    margin: 0;
    padding: 0 0 0 1rem;
    border-bottom: 2px solid var(--htmxo-border);
}
.tabset > nav ul {
    align-self: flex-end;
    gap: 0.25rem;
    margin: 0;
    padding: 0;
    list-style: none;
}
.tabset > nav ul li {
    padding: 0;
    margin: 0;
}
.tabset > nav ul li a {
    display: block;
    padding: 0.5rem 1rem;
    border: 2px solid transparent;
    border-bottom: none;
    border-radius: 0.35rem 0.35rem 0 0;
    background: transparent;
    text-decoration: none;
}
.tabset > nav ul li a.contrast {
    border-color: var(--htmxo-border);
    background: transparent;
}
.tabset > .tab-panel {
    padding: 1rem;
    border: 2px solid var(--htmxo-border);
    border-top: none;
    border-radius: 0 0 0.35rem 0.35rem;
}
}
"""))

function _tabset_panel(content::AbstractString, i, active)
    # String content = URL → lazy load via hx-get on first reveal
    h.div(;
        class=i == active ? "tab-panel u-w-full" : "tab-panel u-w-full u-hidden",
        data_panel="tab-$i",
        hx_get=content,
        hx_trigger="revealed once",
        hx_swap="innerHTML",
    )
end
function _tabset_panel(content, i, active)
    # Non-string content = eager render
    h.div(content;
        class=i == active ? "tab-panel u-w-full" : "tab-panel u-w-full u-hidden",
        data_panel="tab-$i",
    )
end

"""
    tabset(tabs::Pair...; active=1, id="tabset-\$(hash(first.(tabs)))")

Client-side tabs using Pico CSS nav + hyperscript.

Eager (content rendered immediately):

    tabset("Tab 1" => content1, "Tab 2" => content2; active=1)

Lazy (content is a URL string, fetched via HTMX on first tab click):

    tabset("Tab 1" => "/api/tab1", "Tab 2" => "/api/tab2")

Mixed (eager + lazy):

    tabset("Summary" => render_summary(), "Details" => "/api/details")
"""
tabset(tabs::Pair...; active=1, id="tabset-$(hash(first.(tabs)))") = h.div(; id, class="tabset")(
    h.nav(
        h.ul([
            h.li(h.a(label;
                href="#",
                class = i == active ? "contrast" : "secondary",
                _="on click
                    halt the event
                    remove .contrast from <a/> in closest <nav/>
                    add .secondary to <a/> in closest <nav/>
                    remove .secondary from me
                    add .contrast to me
                    set panel to my @data-panel
                    add .u-hidden to <div.tab-panel/> in closest <div/>
                    remove .u-hidden from <div.tab-panel[data-panel='\${panel}']/> in closest <div/>
                ",
                data_panel="tab-$i",
            ))
            for (i, (label, _)) in enumerate(tabs)
        ]...)
    ),
    [_tabset_panel(content, i, active) for (i, (_, content)) in enumerate(tabs)]...
)

"""
    htmx_tabset(items; active=nothing, target="#content", ...)

HTMX-driven tab row: each tab click fetches content from the server.
`items` is a collection of `"Label" => url` pairs.
`tab_attrs(label)` returns extra per-tab named-tuple attributes (e.g. hx_include).
"""
function htmx_tabset(items; active=nothing, target="#content",
                     active_class="primary", inactive_class="secondary",
                     btn_class="outline btn-xs",
                     tab_attrs=Returns(NamedTuple()))
    h.div(; class="tab-row")(
        [h.a(label; role="button",
            class=((active == label ? active_class : inactive_class) * " " * btn_class),
            hx_get=url,
            hx_target=target, hx_swap="outerHTML",
            _="on click remove .$active_class from <a/> in closest <.tab-row/> then add .$inactive_class to <a/> in closest <.tab-row/> then remove .$inactive_class from me then add .$active_class to me",
            tab_attrs(label)...)
         for (label, url) in items]...
    )
end

# --- Status badge ---

# Default mapping picks the matching `u-text-*` utility class — themed via
# the `--htmxo-*` variables (see `htmxo_theme`) and works without inline styles.
const _DEFAULT_STATUS_CLASSES = (
    running   = "u-text-warning",
    finishing = "u-text-warning",
    done      = "u-text-success",
    failed    = "u-text-error",
    pending   = "u-text-muted",
)

"""
    status_badge(state::Symbol; classes=_DEFAULT_STATUS_CLASSES, label=nothing)

Render a `<span>` badge for a status state, picking a `u-text-*` utility class matching
the state. Override the display text with `label` (defaults to titlecased state name).
Pass `classes=Dict(:custom => "u-text-accent")` to remap.

    status_badge(:running)                                  # u-text-warning
    status_badge(:failed; label="Error!")                    # u-text-error "Error!"
    status_badge(:custom; classes=Dict(:custom => "u-text-accent"))
"""
function status_badge(state::Symbol; classes=_DEFAULT_STATUS_CLASSES, label=nothing)
    text = something(label, titlecase(string(state)))
    cls = get(classes, state, "u-text-muted")
    h.span(text; class=cls)
end

# --- Nav sidebar ---

"""
    nav_sidebar(items::Vector{<:Pair}; prefix="", target="#content", active_class="contrast", inactive_class="secondary")

Render a Pico CSS sidebar `<aside>` with HTMX-enabled navigation links.
Each item is a `"Label" => "/path"` pair. Links use hyperscript to toggle active styling.

    nav_sidebar(["Overview" => "/overview", "Settings" => "/settings"]; prefix="/app")
"""
function nav_sidebar(items::Union{AbstractVector{<:Pair}, Tuple{Vararg{Pair}}}; prefix="", target="#content", active_class="contrast", inactive_class="secondary")
    h.aside(
        h.nav(
            h.ul(
                [h.li(h.a(label;
                    href=prefix * path,
                    hx_get=prefix * path,
                    hx_target=target,
                    hx_push_url=prefix * path,
                    _="on click remove .$active_class from <a/> in closest <nav/> then add .$inactive_class to <a/> in closest <nav/> then remove .$inactive_class from me then add .$active_class to me",
                    class=inactive_class,
                )) for (label, path) in items]...
            )
        )
    )
end

"""
    htmxo_breadcrumb(items; target="#content")

Render a Pico-styled breadcrumb `<nav>`. Each `item` is a tuple
`(label, frag_url, push_url)`. When `frag_url` is `nothing`, the segment
renders as plain text (the current page). Otherwise it's an `<a>` that issues
`hx-get=frag_url` into `target` and updates the URL bar via `hx-push-url=push_url`.

```
htmxo_breadcrumb([
    ("Home",     "/",          "/"),
    ("Projects", "/projects",  "/projects"),
    ("Detail",   nothing,      nothing),
])
```
"""
function htmxo_breadcrumb(items; target="#content")
    parts = []
    for (label, frag_url, push_url) in items
        if isnothing(frag_url)
            push!(parts, h.span(label; aria_current="page"))
        else
            push!(parts, h.a(label;
                hx_get=frag_url, hx_target=target, hx_swap="innerHTML",
                hx_push_url=push_url))
        end
    end
    h.nav(parts...; class="htmxo-breadcrumb", aria_label="breadcrumb")
end

"""
    app_layout(sidebar, content; content_id="content")

Two-column app shell — sidebar `<aside>` next to a main content column. Inspired
by Pico's docs layout (CSS Grid with named areas, sticky inner nav, stacks on
mobile <1024px). `sidebar` is rendered as-is (typically [`nav_sidebar`](@ref));
`content` is wrapped in `<div class="htmxo-app-content" id=content_id>` so HTMX
swaps targeting `#content` work out of the box.

Sidebar width defaults to `12rem` via the `--htmxo-sidebar-width` CSS variable;
apps can override it in their own scoped style:

    .htmxo-app-layout { --htmxo-sidebar-width: 10rem; }

```
__page__(content) = htmx(
    app_layout(
        nav_sidebar(["Table" => "/", "Gallery" => "/gallery"]),
        content,
    );
    pico_version="2",
)
```
"""
function app_layout(sidebar, content; content_id="content")
    h.div(; class="htmxo-app-layout")(
        sidebar,
        h.main(content; id=content_id),
    )
end

"""
    editor_styles()

CSS for [`editor_form`](@ref): monospace `<textarea>`/`<input>` editor body
(`.htmxo-editor-input`) and the Save/Cancel button row (`.htmxo-editor-actions`).
Scoped class names, no global selectors. Auto-included by [`htmx`](@ref); inject
manually via `extra_head` if you build your own `<head>`.
"""
editor_styles() = h.style(Raw("""
@layer htmxo {
.htmxo-editor-input {
    font-family: monospace;
    font-size: 0.85em;
    width: 100%;
}
.htmxo-editor-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.5rem;
}
}
"""))

"""
    editor_form(; id, post_url, content="", version="", ...) -> Node

Inline edit form for text content. Renders a `<textarea>` (default) or text
`<input>` with Save/Cancel buttons and Escape-to-cancel. On submit, POSTs to
`post_url` with form fields `content` (or `field_name`) and `version`; the
response is swapped into `#target_id` via `hx-swap=\$swap`.

`version` is a hidden conflict token — echoed back by the save handler so it
can detect concurrent edits. Empty string is fine for apps that don't check.

Cancel:
- `cancel_url` → Cancel issues `hx-get` to that URL.
- `cancel_onclick` → Cancel runs that JS (e.g. `"this.closest('#\$id').remove()"`).
Exactly one must be given.

# Arguments
- `id`                   — container/form element id.
- `tag`                  — outer tag (default `h.div`).
- `class`                — outer element class.
- `post_url`             — URL for Save.
- `target_id`            — `hx-target` for Save response (default `id`).
- `swap`                 — `hx-swap` value (default `"outerHTML"`).
- `content`              — initial content.
- `version`              — hidden version/hash token for conflict detection.
- `field_name`           — form field name for the edited text (default `"content"`).
- `input`                — `:textarea` or `:text`.
- `rows`                 — textarea rows.
- `placeholder`          — input placeholder.
- `label`                — optional label rendered above the editor.
- `save_label`           — submit-button label (default `"Save"`).
- `cancel_url`           — URL for Cancel (`hx-get`).
- `cancel_onclick`       — inline JS for Cancel.
"""
function editor_form(;
    id,
    tag             = h.div,
    class           = "",
    post_url,
    target_id       = id,
    swap            = "outerHTML",
    content         = "",
    version         = "",
    field_name      = "content",
    input           = :textarea,
    rows            = 15,
    placeholder     = "",
    label           = nothing,
    save_label      = "Save",
    cancel_url      = nothing,
    cancel_onclick  = nothing,
)
    (cancel_url === nothing) == (cancel_onclick === nothing) &&
        error("editor_form: provide exactly one of `cancel_url` or `cancel_onclick`")

    input_node = input === :textarea ?
        h.textarea(content; name=field_name, rows=string(rows), class="htmxo-editor-input") :
        input === :text ?
            h.input(; type="text", name=field_name, value=content,
                      placeholder, class="htmxo-editor-input") :
            error("editor_form: `input` must be `:textarea` or `:text`, got $(repr(input))")

    cancel_btn = cancel_url !== nothing ?
        h.button("Cancel";
            type="button", class="secondary outline",
            data_cancel="",
            hx_get=cancel_url, hx_target="#$target_id", hx_swap=swap) :
        h.button("Cancel";
            type="button", class="secondary outline",
            data_cancel="",
            onclick=cancel_onclick)

    tag(; id, class,
          onkeydown="if(event.key==='Escape'){this.querySelector('[data-cancel]').click()}")(
        isnothing(label) ? "" : h.label(label),
        h.form(; hx_post=post_url, hx_target="#$target_id", hx_swap=swap)(
            input_node,
            h.input(; type="hidden", name="version", value=version),
            h.div(; class="htmxo-editor-actions")(
                h.button(save_label; type="submit"),
                cancel_btn,
            ),
        ),
    )
end

# ── Git-backed versioned content store ──────────────────────────────────────

# Parse "Name <email@example.com>" → (name, email). Fallback email keeps
# LibGit2.Signature happy when callers pass a bare name.
function _parse_author(s::AbstractString)
    m = match(r"^(.*?)\s*<(.+?)>\s*$", s)
    m === nothing ? (String(s), "noreply@localhost") : (String(m[1]), String(m[2]))
end

"""
    GitRepo(; path, author="HTMXObjects <noreply@localhost>")

A `@dynamicstruct` owning a directory managed as a git repo — the backend
for [`EditorRoutes`](@ref). Auto-`git init`s on first access; mutations
serialised via a per-instance `ReentrantLock`.

"""
# --- File-based galleries ---

"""
    parse_gallery_metadata(raw::AbstractString) -> Dict{String,String}

Parse `# key: value` header lines from a Julia source file. Stops at
the first non-comment line. Comment lines without a `:` are ignored.
Keys are lowercased. Standard keys: `title`, `description`, `id`,
`section`. Apps may read additional keys directly from `item.metadata`.
"""
function parse_gallery_metadata(raw::AbstractString)
    md = Dict{String,String}()
    for line in split(raw, '\n')
        s = lstrip(line)
        if isempty(strip(line))
            isempty(md) ? continue : break
        end
        startswith(s, "#") || break
        body = strip(s[2:end])
        idx = findfirst(==(':'), body)
        isnothing(idx) && continue
        key = lowercase(strip(body[1:idx-1]))
        val = strip(body[idx+1:end])
        isempty(key) && continue
        md[String(key)] = String(val)
    end
    md
end

# Strip the leading metadata block (comment + blank lines) and return
# the rest of the file body verbatim. Used as `code_string` so docs can
# show "the actual code" without the docs frontmatter.
function _strip_gallery_header(raw::AbstractString)
    lines = split(raw, '\n')
    i = 1
    while i <= length(lines)
        s = lstrip(lines[i])
        if isempty(strip(lines[i]))
            i += 1
        elseif startswith(s, "#")
            body = strip(s[2:end])
            occursin(':', body) || break  # comment without `key:` ends the header
            i += 1
        else
            break
        end
    end
    join(lines[i:end], '\n')
end

"""
    GalleryItem(path)

Single gallery entry parsed from a Julia source file at `path`. Reads
the metadata header (`# key: value` lines) and captures the rest of the
file as `code_string`. The body is `Base.include`-able by the app so it
can be eval'd to produce a value (Vega-Lite spec, Stan model, formula
text, …) the app's renderer turns into HTML.

Standard properties:

  * `path`         — absolute file path.
  * `id`           — defaults to filename without extension; override via `# id: …`.
  * `title`        — defaults to `id`; override via `# title: …`.
  * `description`  — `# description: …` or empty.
  * `section`      — `# section: …` or the parent directory's basename.
  * `metadata`     — full parsed header dict.
  * `code_string`  — file body with the header stripped.

`Base.show(io, MIME"text/markdown"(), item)` produces the agent-friendly
view: `## title \\n *description* \\n ```julia\\ncode\\n``` `.
"""
@dynamicstruct struct GalleryItem
    path::String
    raw = read(path, String)
    metadata = parse_gallery_metadata(raw)
    id = get(metadata, "id", first(splitext(basename(path))))
    title = get(metadata, "title", id)
    description = get(metadata, "description", "")
    section = get(metadata, "section", basename(dirname(path)))
    # `# tags: foo, bar baz` — comma- or whitespace-separated. Empty if
    # the header doesn't declare any. Drives both the searchable text
    # corpus (so `tag:` matches without users having to know the field)
    # and any future tag-chip filter UI.
    tags = String[String(t) for t in split(get(metadata, "tags", ""), r"[,\s]+"; keepempty=false)]
    code_string = _strip_gallery_header(raw)
end

function Base.show(io::IO, ::MIME"text/markdown", item::GalleryItem)
    println(io, "## ", item.title)
    println(io)
    isempty(item.description) || (println(io, "*", item.description, "*"); println(io))
    println(io, "```julia")
    print(io, rstrip(item.code_string))
    println(io)
    println(io, "```")
end

# `_section.md` per directory: either a `# Title` first-line markdown,
# a `title: Foo` key/value, or the file content interpreted as the
# section title. Returns `(section_id => title)` for each subdir that
# has a `_section.md`. Subdir basename is the section id; matches the
# default `section` for items without an explicit `# section:` header.
function _read_section_title(path::AbstractString)
    text = read(path, String)
    for line in split(text, '\n')
        s = strip(line)
        isempty(s) && continue
        # `# Foo` heading
        if startswith(s, "#")
            body = strip(s[2:end])
            startswith(body, "#") && (body = strip(lstrip(body, '#')))
            isempty(body) && continue
            occursin(':', body) || return String(body)
            # `title: Foo` key/value disguised as a comment
            idx = findfirst(==(':'), body)
            key = lowercase(strip(body[1:idx-1]))
            key == "title" && return String(strip(body[idx+1:end]))
            continue
        end
        # `title: Foo` plain key/value
        if occursin(':', s)
            idx = findfirst(==(':'), s)
            key = lowercase(strip(s[1:idx-1]))
            key == "title" && return String(strip(s[idx+1:end]))
        end
        # First non-empty non-comment line is the title
        return String(s)
    end
    return ""
end

# Walk a gallery directory, return (items::Vector{GalleryItem},
# section_titles::Dict{section_id => title}). Items are sorted by
# (section, filename) so the gallery has stable order.
function _collect_gallery(gallery_dir::AbstractString)
    items = GalleryItem[]
    section_titles = Dict{String,String}()
    for (root, dirs, files) in walkdir(gallery_dir)
        sort!(files)
        sort!(dirs)
        for f in files
            if f == "_section.md"
                sec_id = basename(root)
                section_titles[sec_id] = _read_section_title(joinpath(root, f))
            elseif endswith(f, ".jl")
                push!(items, GalleryItem(joinpath(root, f)))
            end
        end
    end
    items, section_titles
end

"""
    Gallery(gallery_dir)

Walks `gallery_dir` recursively and builds one `GalleryItem` per `.jl`
file. Reads section titles from `_section.md` files in each
subdirectory (first non-empty line, or `title: …` key/value).

Items are sorted by `(section, filename)` for stable gallery order.

`find_item(g, id)` returns the item with the given id, or `nothing`.
`section_items(g, section)` returns the items belonging to that section.
"""
@dynamicstruct struct Gallery
    gallery_dir::String
    _walk = _collect_gallery(gallery_dir)
    items = first(_walk)
    section_titles = last(_walk)
end

function find_item(g::Gallery, id::AbstractString)
    for it in g.items
        it.id == id && return it
    end
    nothing
end

section_items(g::Gallery, section::AbstractString) =
    filter(it -> it.section == section, g.items)

"""
    gallery_grid(items; section_titles=Dict(), card_renderer=default_gallery_card,
                        controls=true, search=true, pagination=true,
                        page_size=25, page_sizes=(10, 25, 50, 100, 0),
                        search_placeholder="Search (regex; literal fallback)…")

Render a single-column grid of `card_renderer(item)` cards, grouped by
section. Sections appear in directory-traversal order (preserved by
`Gallery.items`). The section heading uses
`section_titles[section_id]` if present, falling back to the bare
section id (typically the directory basename).

When `controls=true` (default), the result is wrapped in a
`.htmxo-gallery-root` that also carries a sticky toolbar with a search
box and pagination controls. The toolbar is driven by an inline
controller script that toggles `is-search-hidden` / `is-page-hidden`
classes on cards (and `is-empty` on sections whose visible-card count
drops to zero). The controller works identically in:

  * Live HTMXObjects pages (browser executes the inline `<script>` as
    part of normal page load).
  * Recorded fragments embedded into VitePress docs (HTMX innerHTML
    swaps don't auto-execute scripts, but `setupHtmxoEmbed` from
    `htmxo-embed.ts` re-executes inline scripts inside `.htmxo-embed`
    after every swap so the controller wires up there too).

URL state: the search query mirrors `?q=`, the current page mirrors
`?page=`, and the page size mirrors `?ps=` — so a deep-link to a
filtered/paginated view round-trips.

Pass `controls=false` to opt out and recover the original bare
`.htmxo-gallery` `<div>` (used by apps that want to compose their own
toolbar).

Standard CSS classes: `htmxo-gallery-root`, `htmxo-gallery-toolbar`,
`htmxo-gallery-search`, `htmxo-gallery-pagination`, `htmxo-gallery`,
`htmxo-gallery-section`, `htmxo-gallery-section-heading`,
`htmxo-gallery-card`, `htmxo-gallery-card-title`,
`htmxo-gallery-card-description`, `htmxo-gallery-card-code`.
"""
function gallery_grid(items::AbstractVector{GalleryItem};
        section_titles::AbstractDict=Dict{String,String}(),
        card_renderer=default_gallery_card,
        controls::Bool=true,
        search::Bool=true,
        pagination::Bool=true,
        page_size::Int=25,
        page_sizes=(10, 25, 50, 100, 0),
        search_placeholder::AbstractString="Search (regex; literal fallback)…")
    seen = String[]
    groups = Dict{String,Vector{GalleryItem}}()
    for it in items
        if !haskey(groups, it.section)
            push!(seen, it.section)
            groups[it.section] = GalleryItem[]
        end
        push!(groups[it.section], it)
    end
    sections = map(seen) do sec
        title = get(section_titles, sec, sec)
        h.section(; data_section=sec)(
            h.h3(title),
            [card_renderer(it) for it in groups[sec]]...,
        )
    end
    inner = h.div(; class="htmxo-gallery")(sections...)
    (controls && (search || pagination)) || return inner
    h.div(; class="htmxo-gallery-root")(
        gallery_toolbar(; search, pagination, page_size, page_sizes,
                          search_placeholder),
        inner,
        h.div("No items match the current filter."; class="htmxo-gallery-empty"),
        h.script(Raw(gallery_controls_script())),
    )
end

"""
    gallery_toolbar(; search=true, pagination=true,
                       page_size=25, page_sizes=(10, 25, 50, 100, 0),
                       search_placeholder="Search…")

Build the gallery toolbar fragment used by `gallery_grid(; controls=true)`.
Exposed standalone so apps that compose their own gallery wrapper can
reuse the same controls. `0` in `page_sizes` is shown as "all" — the
controller reads `parseInt(value)` and treats `<=0` as "no pagination".
"""
function gallery_toolbar(; search::Bool=true, pagination::Bool=true,
        page_size::Int=25, page_sizes=(10, 25, 50, 100, 0),
        search_placeholder::AbstractString="Search (regex; literal fallback)…")
    parts = []
    search && push!(parts, h.input(;
        type="search",
        placeholder=search_placeholder,
        autocomplete="off"))
    if pagination
        # `selected` is a boolean HTML attribute — its mere presence
        # selects, regardless of value. Only emit it on the matching
        # option (and via `selected="selected"` so renderers that
        # require a string value still emit the attribute).
        _opt(label, value) = (value == string(page_size)) ?
            h.option(label; value=value, selected="selected") :
            h.option(label; value=value)
        ps_options = [v == 0 ? _opt("all", "0") : _opt(string(v), string(v))
                      for v in page_sizes]
        push!(parts, h.div(; class="htmxo-gallery-pagination")(
            h.span("Page size: "),
            h.select(; data_role="page-size")(ps_options...),
            h.button("←"; type="button", data_role="prev",
                     aria_label="Previous page"),
            h.span("Page 1"; data_role="page-info"),
            h.button("→"; type="button", data_role="next",
                     aria_label="Next page"),
        ))
    end
    h.div(; class="htmxo-gallery-toolbar")(parts...)
end

# Inline controller for the gallery toolbar. Emitted as a `<script>` so
# it runs both:
#   * As part of normal page load (live app), and
#   * As part of an htmx swap into `.htmxo-embed` — but only because
#     `setupHtmxoEmbed` re-executes inline scripts after the swap, since
#     `innerHTML` assignment does not run `<script>` tags by default.
#
# The controller is scoped to `document.currentScript.closest('.htmxo-gallery-root')`
# so multiple galleries on the same page get independent state.
"""
    gallery_controls_script() -> String

The inline JS that wires up the gallery toolbar. Returned as a string
so it can be embedded as `h.script(gallery_controls_script())`. Idempotent:
running it multiple times against the same root is harmless (each run
re-binds listeners on the same elements; classes are re-derived from
the current input/select state).
"""
gallery_controls_script() = """
(() => {
    // Initialize every uninitialized `.htmxo-gallery-root` on the page,
    // not just the closest one to the current script. htmx may execute
    // a swapped `<script>` body via `eval` (no `currentScript`) or by
    // re-inserting it elsewhere, so closest-based scoping is fragile.
    // Instead each script invocation scans the document and wires up
    // any roots it finds; the `data-htmxo-controls-init` sentinel keeps
    // re-runs idempotent.
    const initRoot = (root) => {
        if (root.dataset.htmxoControlsInit === '1') return;
        root.dataset.htmxoControlsInit = '1';
        const gallery = root.querySelector('.htmxo-gallery');
        const search  = root.querySelector('.htmxo-gallery-toolbar input[type="search"]');
        const psSel   = root.querySelector('[data-role="page-size"]');
        const prevBtn = root.querySelector('[data-role="prev"]');
        const nextBtn = root.querySelector('[data-role="next"]');
        const pageInfo= root.querySelector('[data-role="page-info"]');
        const empty   = root.querySelector('.htmxo-gallery-empty');
        if (!gallery) return;

        const cards    = () => Array.from(gallery.querySelectorAll(':scope > section > article, :scope > article'));
        const sections = () => Array.from(gallery.querySelectorAll(':scope > section'));
        const params   = new URLSearchParams(window.location.search);
        let page = Math.max(0, (parseInt(params.get('page') || '1', 10) || 1) - 1);

        if (search && params.get('q'))  search.value = params.get('q');
        if (psSel  && params.get('ps')) psSel.value  = params.get('ps');

        const haystack = c => (c.dataset.searchText
            || (c.textContent || '').toLowerCase().replace(/\\s+/g, ' ').trim());

        const setAttr = (el, name, on) => {
            if (on) el.setAttribute(name, ''); else el.removeAttribute(name);
        };

        const applyFilter = () => {
            const raw = (search && search.value || '').trim();
            let re = null, lit = '';
            if (raw) {
                try { re = new RegExp(raw, 'i'); }
                catch (_) { lit = raw.toLowerCase(); }
            }
            if (search) {
                if (lit) search.dataset.mode = 'literal';
                else delete search.dataset.mode;
            }
            cards().forEach(c => {
                const hay = haystack(c);
                const show = !raw
                    || (re && re.test(hay))
                    || (lit && hay.includes(lit));
                setAttr(c, 'data-search-hidden', !show);
            });
        };

        const applyPagination = () => {
            const visible = cards().filter(c => !c.hasAttribute('data-search-hidden'));
            const ps = psSel ? (parseInt(psSel.value, 10) || 0) : 0;
            const total = visible.length;
            const pages = ps > 0 ? Math.max(1, Math.ceil(total / ps)) : 1;
            if (page >= pages) page = pages - 1;
            if (page < 0)      page = 0;
            visible.forEach((c, i) => {
                const inPage = ps <= 0 || (i >= page * ps && i < (page + 1) * ps);
                setAttr(c, 'data-page-hidden', !inPage);
            });
            // Search-hidden cards must not also carry data-page-hidden —
            // when search clears, those cards re-become candidates and
            // pagination needs to re-decide their fate.
            cards().filter(c => c.hasAttribute('data-search-hidden'))
                   .forEach(c => c.removeAttribute('data-page-hidden'));
            if (pageInfo) pageInfo.textContent =
                'Page ' + (page + 1) + ' / ' + pages + ' \\u2022 ' + total
                + (total === 1 ? ' item' : ' items');
            if (prevBtn) prevBtn.disabled = page === 0;
            if (nextBtn) nextBtn.disabled = page >= pages - 1;
            if (empty)   empty.hidden = total !== 0;
        };

        const applySectionVisibility = () => sections().forEach(sec => {
            const allCards = sec.querySelectorAll(':scope > article');
            const anyVisible = Array.from(allCards).some(c =>
                !c.hasAttribute('data-search-hidden')
                && !c.hasAttribute('data-page-hidden'));
            setAttr(sec, 'data-empty', !anyVisible);
        });

        const refresh = () => { applyFilter(); applyPagination(); applySectionVisibility(); };

        const syncUrl = () => {
            // URL sync only makes sense for top-level pages (the user's
            // address bar is the gallery's address). Inside an
            // `.htmxo-embed` the URL belongs to the docs host and we
            // must not stomp it.
            if (root.closest('.htmxo-embed')) return;
            const url = new URL(window.location.href);
            const q = (search && search.value || '').trim();
            if (q) url.searchParams.set('q', q); else url.searchParams.delete('q');
            if (page > 0) url.searchParams.set('page', String(page + 1));
            else          url.searchParams.delete('page');
            history.replaceState(null, '', url);
        };

        if (search)  search.addEventListener('input',  () => { page = 0; refresh(); syncUrl(); });
        if (psSel)   psSel.addEventListener('change',  () => { page = 0; refresh(); syncUrl(); });
        if (prevBtn) prevBtn.addEventListener('click', () => { page--;   refresh(); syncUrl(); });
        if (nextBtn) nextBtn.addEventListener('click', () => { page++;   refresh(); syncUrl(); });

        // Hash navigation: clicking a card title's `#id` anchor must
        // reveal the card even if it was filtered or paginated out.
        // Reset search, recompute filters, jump to the page that
        // contains the card, and scroll it into view.
        const jumpToHash = () => {
            const id = decodeURIComponent((window.location.hash || '').slice(1));
            if (!id) return;
            const sel = 'article[data-id="' + CSS.escape(id) + '"], #' + CSS.escape(id);
            const card = gallery.querySelector(sel);
            if (!card) return;
            if (search && search.value) search.value = '';
            applyFilter();
            const visible = cards().filter(c => !c.hasAttribute('data-search-hidden'));
            const ps = psSel ? (parseInt(psSel.value, 10) || 0) : 0;
            const idx = visible.indexOf(card);
            if (idx >= 0 && ps > 0) page = Math.floor(idx / ps);
            applyPagination(); applySectionVisibility(); syncUrl();
            card.scrollIntoView({ block: 'start' });
        };
        window.addEventListener('hashchange', jumpToHash);

        refresh();
    };
    document.querySelectorAll('.htmxo-gallery-root').forEach(initRoot);
})();
"""

"""
    default_gallery_card(item::GalleryItem)

Default card layout: title heading + description (always visible) +
inline source code block. No collapsible details — important info
is visible directly. Apps wrap this with their own
`card_renderer = item -> h.article(default_gallery_card(item),
my_render(item))` to add Vega-Lite plots, PPC plots, etc.
"""
default_gallery_card(item::GalleryItem) = h.article(;
        id=item.id,
        data_id=item.id,
        data_section=item.section,
        data_tags=join(item.tags, " "),
        # Canonical search corpus: title + description + tags + section
        # + id, lowercased so the controller can `includes()` directly.
        # Custom card renderers can either set their own `data-search-text`
        # or let the controller fall back to `textContent`.
        data_search_text=lowercase(strip(string(
            item.title, ' ', item.description, ' ',
            join(item.tags, ' '), ' ', item.section, ' ', item.id))))(
    h.h4(
        h.a(item.title; href="#" * item.id),
    ),
    isempty(item.description) ? h.span() :
        h.p(item.description),
    h.pre(h.code(item.code_string)),
)

"""
    htmxo_gallery_styles()

`<style>` block with the canonical gallery layout: single-column,
flat (no card frame), proper heading hierarchy, themed via `--htmxo-*`
tokens. Include via `extra_head` in `htmx(...)` so all HTMXO apps
present galleries the same way.

Source of truth is
`HTMXObjects/assets/vitepress/htmxo-gallery.css` — same file is
imported by `htmxo-embed.ts` so the docs-embedded fragment matches.
"""
htmxo_gallery_styles() = h.style(Raw(
    read(joinpath(_VITEPRESS_ASSETS_DIR, "htmxo-gallery.css"), String)))

"""
    htmxo_syntax_head(; languages=("julia", "stan"))

Head elements (script tags + theme-aware `<style>`) for client-side
PrismJS syntax highlighting that flips with the host theme
(VitePress `html.dark`, Pico `data-theme="dark"`). Any `<code
class="language-…">` that PrismJS recognizes will be tokenized; the
token coloring uses `--htmxo-syntax-*` CSS variables which adapt
automatically.

Use as a splat in `extra_head=` of `htmx(...)`:

    extra_head=(htmxo_gallery_styles(), htmxo_syntax_head()...)

The same token CSS gets shipped to docs themes via
`vitepress_theme_install` (alongside `htmxo-embed.ts`/`htmxo-gallery.css`)
so embedded fragments inherit the theme-aware coloring without
needing the script tags from the fragment to execute (which they
wouldn't, since `innerHTML` swaps don't run scripts).
"""
function htmxo_syntax_head(; languages=("julia", "stan"))
    base = "https://cdn.jsdelivr.net/npm/prismjs@1"
    syntax_css = read(joinpath(_VITEPRESS_ASSETS_DIR, "htmxo-syntax.css"), String)
    (h.script(; src="$base/prism.min.js"),
     (h.script(; src="$base/components/prism-$lang.min.js") for lang in languages)...,
     h.style(Raw(syntax_css)))
end

@dynamicstruct struct GitRepo
    path::String
    author::String = "HTMXObjects <noreply@localhost>"
    _lock = ReentrantLock()

    _ensure() = begin
        if !isdir(joinpath(path, ".git"))
            mkpath(path)
            close(LibGit2.init(path))
        end
        nothing
    end

    _signature() = begin
        name, email = _parse_author(author)
        LibGit2.Signature(name, email)
    end

    read_blob(spec) = begin
        _ensure()
        repo = LibGit2.GitRepo(path)
        try
            obj = LibGit2.GitObject(repo, spec)
            try
                obj isa LibGit2.GitBlob || error("GitRepo.read_blob: $(spec) is not a blob")
                String(LibGit2.rawcontent(obj))
            finally
                close(obj)
            end
        finally
            close(repo)
        end
    end

    @struct editor(relpath; default_content="") = begin
        abs_path = joinpath(path, relpath)

        current_content() = begin
            if !isfile(abs_path)
                mkpath(dirname(abs_path))
                write(abs_path, default_content)
            end
            read(abs_path, String)
        end

        # IP form (`name() = …`) keeps these recomputed on every call.
        # Bare-property form would cache per editor instance and silently go
        # stale when the underlying git state changes.
        current_version() = begin
            _ensure()
            repo = LibGit2.GitRepo(path)
            try
                try
                    obj = LibGit2.GitObject(repo, "HEAD:" * relpath)
                    try
                        string(LibGit2.GitHash(obj))
                    finally
                        close(obj)
                    end
                catch err
                    err isa LibGit2.GitError || rethrow()
                    ""
                end
            finally
                close(repo)
            end
        end

        versions() = begin
            _ensure()
            Base.lock(_lock) do
                repo = LibGit2.GitRepo(path)
                try
                    out = NamedTuple{(:sha,:timestamp,:author,:message,:blob_sha),
                                     Tuple{String,Int64,String,String,String}}[]
                    walker = try
                        LibGit2.GitRevWalker(repo)
                    catch err
                        err isa LibGit2.GitError || rethrow()
                        return out
                    end
                    try
                        try
                            LibGit2.push_head!(walker)
                        catch err
                            err isa LibGit2.GitError || rethrow()
                            return out
                        end
                        prev_blob = ""
                        for oid in walker
                            commit = LibGit2.GitCommit(repo, oid)
                            try
                                blob = try
                                    o = LibGit2.GitObject(repo, string(oid) * ":" * relpath)
                                    try string(LibGit2.GitHash(o)) finally close(o) end
                                catch err
                                    err isa LibGit2.GitError || rethrow()
                                    ""
                                end
                                if !isempty(blob) && blob != prev_blob
                                    sig = LibGit2.author(commit)
                                    push!(out, (
                                        sha       = string(oid),
                                        timestamp = Int64(sig.time),
                                        author    = sig.name * " <" * sig.email * ">",
                                        message   = LibGit2.message(commit),
                                        blob_sha  = blob,
                                    ))
                                end
                                prev_blob = blob
                            finally
                                close(commit)
                            end
                        end
                    finally
                        close(walker)
                    end
                    out
                finally
                    close(repo)
                end
            end
        end

        read_version(sha) = __parent__.read_blob(sha * ":" * relpath)

        # Optimistic-concurrency write: `version` must match the current
        # blob_sha (or "" for a brand-new file). On mismatch returns
        # `(:conflict, current_blob_sha)` without writing.
        write!(content; version::AbstractString="",
                        message::AbstractString="edit " * relpath) = begin
            Base.lock(_lock) do
                _ensure()
                current = current_version()
                current == version || return (:conflict, current)
                mkpath(dirname(abs_path))
                write(abs_path, content)
                repo = LibGit2.GitRepo(path)
                try
                    LibGit2.add!(repo, relpath)
                    sig = _signature()
                    oid = LibGit2.commit(repo, message; author=sig, committer=sig)
                    (:ok, string(oid))
                finally
                    close(repo)
                end
            end
        end

        # Atomic read-modify-write under the per-repo lock. `f(current_content)`
        # runs inside the lock; its return value is written and committed. For
        # partial-file edits (e.g. one key in a multi-key YAML) this avoids the
        # read-then-write race that `write!`'s optimistic concurrency would
        # report as a spurious conflict. Returns `(:ok, commit_sha)` on change
        # or `(:nochange, current_blob_sha)` if `f` returned identical content.
        update!(f; message::AbstractString="edit " * relpath) = begin
            Base.lock(_lock) do
                _ensure()
                current = isfile(abs_path) ? read(abs_path, String) : ""
                new_content = f(current)
                if new_content == current
                    return (:nochange, current_version())
                end
                mkpath(dirname(abs_path))
                write(abs_path, new_content)
                repo = LibGit2.GitRepo(path)
                try
                    LibGit2.add!(repo, relpath)
                    sig = _signature()
                    oid = LibGit2.commit(repo, message; author=sig, committer=sig)
                    (:ok, string(oid))
                finally
                    close(repo)
                end
            end
        end
    end
end

include("routes/editor_routes.jl")

function __init__()
    # Per-process error log dir for caught route exceptions.
    ERROR_DIR[] = get(ENV, "HTMXO_ERROR_DIR", joinpath(tempdir(), "htmxo_errors"))
end

end # module HTMXObjects
