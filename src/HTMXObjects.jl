module HTMXObjects

export DynamicObjects, @persist, @dynamicstruct, @htmx, @cache_status, @is_cached, @cache_path, @clear_cache!, fetchindex, getstatus, cancel!, cancel_all!, PropertyComputationError, unwrap_error
export create_app
export HTTP, queryparams, formdata
export terminate, serve, staticfiles, dynamicfiles
export auto, htmx, h, Node, @__str, HyperscriptString
export route!, to_response, save_response, static_transform
export safely, ERROR_DIR
export is_htmx, hx_target, hx_trigger, hx_current_url, hx_boosted, hx_prompt
export hx_response
export hx_link, htmx_or
export wants_markdown, wants_errors, markdown_response, e, filter_errors, render_table, sortable_table_js, download_table_js, CaptionSpec, render_caption, with_caption, caption_style
export html_only, markdown_only, HtmlOnly, MarkdownOnly
export fmt_time, fmt_bytes, fmt_number, query_url, hidden_inputs, post_form, get_form, @query_url
export Long, ainput, sinput, sinput_custom, soption, linput, rinput, ninput, cinput, tinput, radio_group, loading_indicator_script, request_feedback, request_feedback_style, request_feedback_script, show_when_script, tabset, htmx_tabset, status_badge, nav_sidebar, lazy
export test_list, test_run!, test_run_all!, test_run_failed!, test_run_missing!, test_run_batch!, test_clear_cache!
export TestRoutes

using DynamicObjects, HTTP, Tables
import DynamicObjects: @persist, fetchindex, getstatus
using HTMX
import HTMX: h, auto, Node, @__str, HyperscriptString

import Oxygen
import Oxygen: formdata
using Oxygen.Core: ServerContext, register, Nullable

const CONTEXT :: Ref{ServerContext} = Ref(ServerContext(; mod=@__MODULE__))

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
"""
function serve(; parallel=false, kwargs...)
    async = Base.get(kwargs, :async, false)
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
    # Query strings are form-encoded: '+' represents a space. `unescapeuri` only
    # does percent-decoding, so translate '+' → ' ' before unescaping. Without
    # this, URLs written via JS `URLSearchParams.toString()` (which form-encodes
    # spaces as '+') round-trip spaces as literal '+' characters and break
    # downstream lookups.
    _form_unescape(s) = String(HTTP.URIs.unescapeuri(replace(s, '+' => ' ')))
    for part in split(query, "&", keepempty=false)
        kv = split(part, "=", limit=2)
        k = _form_unescape(kv[1])
        v = length(kv) >= 2 ? _form_unescape(kv[2]) : ""
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
        lhs = inner.args[1]
        name = if lhs isa Symbol
            lhs
        elseif Meta.isexpr(lhs, (:call, :ref))
            first(lhs.args) isa Symbol ? first(lhs.args) : nothing
        elseif Meta.isexpr(lhs, :(::)) && length(lhs.args) >= 1
            lhs.args[1] isa Symbol ? lhs.args[1] : nothing
        else
            nothing
        end
        if name === legacy
            loc = isnothing(lnn) ? "" : " (near $(lnn.file):$(lnn.line))"
            @warn "Deprecated: `$legacy` is a legacy framework property name — rename to `$replacement`$loc. The legacy name still works but will be emitted as a warning on every macro expansion."
        end
    end
    struct_expr
end

_warn_legacy_page_name!(struct_expr) = _warn_legacy_name!(struct_expr, :page, :__page__)
_warn_legacy_req_name!(struct_expr)  = _warn_legacy_name!(struct_expr, :req,  :__req__)

"""
    _warn_redundant_req_decl!(struct_expr)

Warn when the user explicitly writes `__req__ = nothing`. `_inject_req_aliases!`
adds this line automatically when no `req`/`__req__` is declared, so an explicit
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
    _inject_req_aliases!(struct_expr)

Ensure that `@htmx` struct bodies always declare both `req` and `__req__`
as properties so that:

1. `walk_rhs` rewrites bare references to either name in sibling property
   bodies (including the `@include ext = Ext(; req)` / `@include ext = Ext(; __req__)`
   shorthand — `req=req` / `__req__=__req__` desugars to a bare-symbol
   kwarg value that must resolve via `__self__`).
2. Route handlers can pass either kwarg name and have the other fall
   through to the alias.

Canonically, `__req__` holds the request and `req` is an alias property
that returns `__self__.__req__`. If the user explicitly declared only
`req = ...` (legacy), we inject `__req__ = req`. If neither is declared,
we inject `__req__ = nothing` and `req = __req__`. Injected lines carry
no `LineNumberNode`, so the legacy-name walker (which ran earlier) only
ever sees user-written assignments.
"""
function _inject_req_aliases!(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    has_req = false
    has_dunder = false
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
        lhs = inner.args[1]
        name = if lhs isa Symbol
            lhs
        elseif Meta.isexpr(lhs, (:call, :ref))
            first(lhs.args) isa Symbol ? first(lhs.args) : nothing
        elseif Meta.isexpr(lhs, :(::)) && length(lhs.args) >= 1
            lhs.args[1] isa Symbol ? lhs.args[1] : nothing
        else
            nothing
        end
        name === :req    && (has_req = true)
        name === :__req__ && (has_dunder = true)
    end
    prepend = Any[]
    if !has_dunder && !has_req
        push!(prepend, :(__req__ = nothing))
        push!(prepend, :(req = __req__))
    elseif !has_dunder
        push!(prepend, :(__req__ = req))
    elseif !has_req
        push!(prepend, :(req = __req__))
    end
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
            lhs isa Symbol && push!(result, (lhs, gen_name))
        end
    end
    result
end

# Find @include external struct properties: @include prop = ExternalStruct(; ...)
# Returns list of (prop_name, type_name_expr) pairs.
function _find_include_externals(struct_expr)
    body = struct_expr.args[3]
    result = Tuple{Symbol, Any}[]
    for arg in body.args
        arg isa Expr || continue
        expr = arg
        while Meta.isexpr(expr, :macrocall) && expr.args[1] != Symbol("@include")
            expr = expr.args[end]
        end
        Meta.isexpr(expr, :macrocall) && expr.args[1] == Symbol("@include") || continue
        inner = expr.args[end]
        inner isa Expr && inner.head == :(=) || continue
        prop_name = inner.args[1]
        rhs = inner.args[2]
        # RHS should be a call like ExternalStruct(; req, ...) — extract the type
        Meta.isexpr(rhs, :call) || continue
        type_expr = rhs.args[1]
        push!(result, (prop_name, type_expr))
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
# Default: no nested struct type known.
_nested_struct_type(::Type, ::Val) = nothing

"""
    _convert_include_to_struct!(struct_expr)

Pre-process: convert `@include prop = begin...end` to `prop = struct _Include_prop ... end`.
`@include prop = ExternalStruct(...)` is left as-is (just a metadata marker for route registration).
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
        inner isa Expr && inner.head == :(=) || continue
        prop_name = inner.args[1]
        rhs = inner.args[2]
        # Only convert begin...end blocks; leave ExternalStruct(...) calls as-is
        Meta.isexpr(rhs, :block) || continue
        # Convert to: prop = struct _Include_prop ... end
        struct_name = Symbol("_Include_", prop_name)
        child_struct = Expr(:struct, false, struct_name, rhs)
        # Replace the @include macrocall with the struct assignment
        body.args[i] = :($prop_name = $child_struct)
    end
    struct_expr
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

Returns the ordered list of declared param names for later `_param_names` emission.
`_req_of(__self__)` picks up whichever of `__req__` or legacy `req` is
populated on the enclosing instance.
"""
function _convert_params!(struct_expr)
    body = struct_expr.args[3]
    names = Symbol[]
    new_args = Any[]
    for arg in body.args
        if !(arg isa Expr)
            push!(new_args, arg); continue
        end
        if Meta.isexpr(arg, :macrocall) && arg.args[1] === Symbol("@param")
            # Strip the LineNumberNode that follows the macro name
            payload = [a for a in arg.args[2:end] if !(a isa LineNumberNode)]
            # Block form: @param begin ... end → expand each line
            if length(payload) == 1 && Meta.isexpr(payload[1], :block)
                for inner in payload[1].args
                    inner isa LineNumberNode && (push!(new_args, inner); continue)
                    rewritten = _rewrite_param_line(inner)
                    rewritten === nothing && continue
                    push!(names, rewritten[1])
                    push!(new_args, rewritten[2])
                end
            else
                # Single-line form: @param vessels::T = default
                # Multiple payload elements are a tuple literal (comma-separated)
                for inner in payload
                    rewritten = _rewrite_param_line(inner)
                    rewritten === nothing && continue
                    push!(names, rewritten[1])
                    push!(new_args, rewritten[2])
                end
            end
        else
            push!(new_args, arg)
        end
    end
    body.args = new_args
    names
end

# Parse a single `name::T = default` / `name = default` / `name::T` / `name` form
# and return `(name_sym, rewritten_assignment)` or `nothing` if unrecognized.
function _rewrite_param_line(expr)
    default_expr = nothing
    type_expr = nothing
    lhs = expr
    if Meta.isexpr(expr, :(=))
        lhs = expr.args[1]
        default_expr = expr.args[2]
    end
    name_sym = nothing
    if lhs isa Symbol
        name_sym = lhs
    elseif Meta.isexpr(lhs, :(::)) && length(lhs.args) == 2 && lhs.args[1] isa Symbol
        name_sym = lhs.args[1]
        type_expr = lhs.args[2]
    else
        return nothing
    end
    t = type_expr === nothing ? :nothing : type_expr
    req_expr = :($(_req_of)(__self__))
    rhs = default_expr === nothing ?
        :($(_extract_param)($req_expr, $(QuoteNode(name_sym)), $t)) :
        :($(_extract_param)($req_expr, $(QuoteNode(name_sym)), $t, $default_expr))
    (name_sym, Expr(:(=), name_sym, rhs))
end

function _htmx_transform(struct_expr; reroute=true, parent_params=Symbol[], kwargs...)
    _convert_include_to_struct!(struct_expr)
    _wrap_ws_bodies!(struct_expr)
    _warn_legacy_page_name!(struct_expr)
    _warn_legacy_req_name!(struct_expr)
    reroute && _warn_redundant_req_decl!(struct_expr)
    reroute && _inject_req_aliases!(struct_expr)
    own_params = _convert_params!(struct_expr)
    # Merge: parent params first (preserve order), then own, deduplicated.
    param_names = Symbol[]
    for n in parent_params
        n in param_names || push!(param_names, n)
    end
    for n in own_params
        n in param_names || push!(param_names, n)
    end
    inline_props = _find_inline_structs(struct_expr)
    include_externals = _find_include_externals(struct_expr)
    route_info = _extract_route_info(struct_expr)
    block = DynamicObjects.dynamicstruct(struct_expr;
        child_handler=s -> _htmx_transform(s; reroute=false, parent_params=param_names), kwargs...)
    type_name = _struct_type_name(struct_expr)
    @assert Meta.isexpr(block, :escape)
    # Emit _extract_args methods for each route property
    for ri in route_info
        push!(block.args[1].args, _generate_extract_args(type_name, ri.prop_name, ri.pos_params, ri.kw_params))
    end
    # Emit _nested_struct_type methods for inline structs and @include externals
    _type_fname = Expr(:., @__MODULE__, QuoteNode(:_nested_struct_type))
    for (prop, child_type) in inline_props
        push!(block.args[1].args, Expr(:(=),
            Expr(:call, _type_fname, :(::Type{$type_name}), :(::Val{$(QuoteNode(prop))})),
            child_type))
    end
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
    reroute && push!(block.args[1].args, :($(_reroute!)($type_name)))
    block
end

_route_macros() = Set([Symbol("@get"), Symbol("@post"), Symbol("@put"), Symbol("@patch"), Symbol("@delete"), Symbol("@ws")])

# Extract route property info from the struct body AST at macro expansion time.
# Returns [(prop_name::Symbol, positional_params, kwargs_params), ...]
# where positional_params = [(name::Symbol, type_expr_or_nothing), ...]
# and   kwargs_params     = [(name::Symbol, type_expr_or_nothing, has_default::Bool), ...]
function _extract_route_info(struct_expr)
    body = struct_expr.args[3]
    route_macros = _route_macros()
    routes = @NamedTuple{prop_name::Symbol, pos_params::Vector, kw_params::Vector}[]
    lnn = nothing
    for arg in body.args
        isa(arg, LineNumberNode) && (lnn = arg; continue)
        arg isa Expr || continue
        # Walk macrocall layers to find route markers
        expr = arg
        has_route = false
        while Meta.isexpr(expr, :macrocall)
            expr.args[1] in route_macros && (has_route = true)
            # macrocall args[2] is often a LineNumberNode
            expr.args[2] isa LineNumberNode && (lnn = expr.args[2])
            expr = expr.args[end]
        end
        has_route || continue
        # expr is the inner assignment: name(...) = rhs
        expr isa Expr && expr.head == :(=) || continue
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
            # Non-indexed route: @get name = ... (plain Symbol LHS)
            prop_name = lhs
            Meta.isexpr(prop_name, :(::)) && (prop_name = prop_name.args[1])
        end
        push!(routes, (prop_name=prop_name, pos_params=pos_params, kw_params=kw_params))
    end
    routes
end

# Extract type annotation from a parameter AST node (macro-time version of _extract_type).
function _macro_extract_type(idx)
    expr = Meta.isexpr(idx, :kw) ? idx.args[1] : idx
    Meta.isexpr(expr, :(::)) && length(expr.args) == 2 ? expr.args[2] : nothing
end

# Generate a _extract_args method definition for a route property.
# Types are left as AST expressions — Julia's compiler resolves them in the user's module.
function _generate_extract_args(type_name, prop_name, pos_params, kw_params)
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
                    __v__ isa $(_NoDefault) || push!(__kw__, $(QuoteNode(kname)) => __v__)
                end
            end)
        else
            push!(kw_stmts, quote
                let __v__ = $lookup_call
                    __v__ isa $(_NoDefault) && throw(KeyError($(QuoteNode(kname))))
                    push!(__kw__, $(QuoteNode(kname)) => __v__)
                end
            end)
        end
    end

    _M = @__MODULE__
    _fname = Expr(:., _M, QuoteNode(:_extract_args))
    _call = Expr(:call, _fname,
        :(::Type{$type_name}), :(::Val{$(QuoteNode(prop_name))}),
        :__req__, :__method__, :(__base_segments__::Int), :(__n_params__::Int))
    _body = quote
        __parts__ = split(split(__req__.target, "?")[1], "/", keepempty=false)
        __src__ = $(_kwargs_source)(__req__, __method__)
        __fallback__ = __method__ in $(_queryparams_verbs) ? nothing : $(queryparams)(__req__)
        __idx__ = Any[]
        $(pos_stmts...)
        __kw__ = Pair{Symbol,Any}[]
        $(kw_stmts...)
        (__idx__, __kw__)
    end
    Expr(:(=), _call, _body)
end

# Dispatch target for generated route arg extraction methods.
function _extract_args end


"""
    @htmx struct MyApp ... end

Wraps `@dynamicstruct` and appends a `_reroute!` call so that Revise-triggered
re-evaluation automatically re-registers routes without a server restart.
`@ws` property bodies are automatically wrapped in `(__ws__) -> body`.
Inline `prop = struct ... end` definitions are processed as nested route structs.
"""
macro htmx(args...)
    _htmx_transform(args[end]; (length(args) > 1 ? (docstring=args[1],) : (;))...)
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
            (feedback ? request_feedback() : ())...,
            extra_head...,
        ),
        body(args...),
    )
end

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

# Convert a value to markdown text via show(io, MIME"text/markdown"(), val).
# HTMX.jl defines show for Node; users can extend with show(io, MIME"text/markdown", val::MyType).
to_markdown_string(val) = sprint(show, MIME"text/markdown"(), val)

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
- Type annotations auto-parse URL strings: `@get item(id::Int)` parses `id` to `Int`
- Trailing defaults register shortened routes: `@get filter(a, b=1)` registers
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


const _http_verbs = Dict(
    Symbol("@get") => "GET",
    Symbol("@post") => "POST",
    Symbol("@put") => "PUT",
    Symbol("@patch") => "PATCH",
    Symbol("@delete") => "DELETE",
    Symbol("@ws") => "WEBSOCKET",
)

# Store registered types so _reroute! can re-register after Revise updates
const _registered_types = Dict{DataType, NamedTuple{(:prefix, :record_dir), Tuple{String, Any}}}()
# Reverse lookup: included sub-struct type → set of registered parent types
const _included_type_parents = Dict{DataType, Set{DataType}}()

# Convert a string value to the target type. Strings pass through as-is.
# Called from generated _extract_args methods with actual Types (resolved at compile time).
_convert_param(val, ::Nothing) = val
_convert_param(val::AbstractString, T::Type{<:AbstractString}) = val
_convert_param(val::AbstractString, T::Type) = parse(T, val)
_convert_param(val::AbstractVector, ::Nothing) = val  # multi-value, no type annotation → keep as vector
_convert_param(val::AbstractVector, T::Type{<:AbstractString}) =
    error("expected single value for parameter (got $(length(val)) values: $(val)); use Vector type annotation if repeated values are intended")
_convert_param(val::AbstractVector, T::Type{<:AbstractVector}) = val  # multi-value + Vector annotation → keep as-is
_convert_param(val::AbstractVector, T::Type) =
    error("expected single value for parameter (got $(length(val)) values: $(val)); use Vector type annotation if repeated values are intended")
_convert_param(val::AbstractString, T::Type{<:AbstractVector}) = isempty(val) ? String[] : [val]  # single/empty → vector

# Determine whether kwargs come from queryparams (GET/DELETE) or formdata (POST/PUT/PATCH).
const _queryparams_verbs = Set(["GET", "DELETE"])
function _kwargs_source(req, method)
    method in _queryparams_verbs && return queryparams(req)
    isempty(HTTP.payload(req)) ? Dict{String, Any}() : formdata(req)
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
(`queryparams` for GET/DELETE, `formdata` for POST/PUT/PATCH with a `queryparams`
fallback), converts via `_convert_param(value, T)`, and returns `default` when the
key is absent or empty. Throws `KeyError(name)` if no default was supplied.

`T` may be `nothing` for untyped params (raw `String`/`Vector{String}`).
"""
function _extract_param(req, name, T, default=_NO_DEFAULT)
    method = req.method
    src = _kwargs_source(req, method)
    fallback = method in _queryparams_verbs ? nothing : queryparams(req)
    v = _lookup_param(src, fallback, name, T)
    if v isa _NoDefault
        default isa _NoDefault && throw(KeyError(name))
        return default
    end
    v
end

# Register a route handler directly on the HTTP router, bypassing Oxygen's
# argument-name validation. We extract path params ourselves via positional URL segment indexing.
_register_handler(method, path, handler) =
    HTTP.register!(CONTEXT[].service.router, get(Dict("WEBSOCKET" => "GET"), method, method), path, handler)

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

"""
    _record_error(err, bt, req) -> (uid, path)

Write a detailed error report to `joinpath(ERROR_DIR[], "<uid>.log")` and return
both the short uid and the full file path. Also emits an `@error` log entry
that includes the full path so the recorded file is one click away in the
terminal/log viewer.
"""
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
        if req isa HTTP.Request
            println(io, "method:    ", req.method)
            println(io, "target:    ", req.target)
        end
        println(io)
        showerror(io, err, bt)
        println(io)
    end
    @error "HTMXObjects caught an error: $path"
    (uid, path)
end

"""
    _default_error_render(uid, path)

Default rendering for a caught error — a small article pointing at the recorded
error id. Override by defining `__error__` on the route's enclosing struct
(or, to disable catching entirely, set `__error__ = rethrow`).
"""
_default_error_render(uid, path) = h.article(
    h.header(h.strong("Error")),
    h.p("Something went wrong. Error ID: ", h.code(uid)),
)

# Invoke the user's `__error__` hook if present, else fall back to the default.
# The hook is called with just the exception, so `__error__ = rethrow` works.
function _invoke_error_handler(obj, err, uid, path)
    if obj !== nothing && hasproperty(obj, :__error__)
        return getproperty(obj, :__error__)(err)
    end
    _default_error_render(uid, path)
end

"""
    _route_error_response(req, err, bt; error_obj=nothing, page_chain=Any[])

Record the error, invoke the user's `__error__` hook (or the default), and
return an `HTTP.Response` — honoring markdown mode, HTMX fragment mode, and
`page` wrappers the same way a successful response would.
"""
function _route_error_response(req, err, bt; error_obj=nothing, page_chain=Any[])
    uid, path = _record_error(err, bt, req)
    err_val = _invoke_error_handler(error_obj, err, uid, path)
    err_val isa HTTP.Response && return err_val
    if wants_markdown(req)
        return markdown_response(to_markdown_string(err_val))
    end
    is_htmx(req) && return to_response(err_val)
    for obj in reverse(page_chain)
        wrapper = _page_wrapper(obj)
        isnothing(wrapper) || (err_val = wrapper[err_val])
    end
    to_response(err_val)
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
function safely(f::Function; obj=nothing, req=nothing)
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
function _resolve_response(obj, req, val; record_dir=nothing, save_path=nothing)
    # Opt-out: route already produced a response
    val isa HTTP.Response && return val

    # Error filter: keep only data-error nodes (applied before markdown/rich)
    if wants_errors(req)
        val = filter_errors(val)
        isnothing(val) && return markdown_response("(no errors)")
    end

    # Record static version if requested
    if !isnothing(record_dir) && !isnothing(save_path)
        save_response(record_dir, save_path, to_response(static_transform(val)))
    end

    # Markdown mode
    if wants_markdown(req)
        if hasproperty(obj, :to_markdown)
            return to_response(getproperty(obj, :to_markdown)[val])
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
    to_response(wrapper[val])
end

_base_segments(path) = count(p -> !startswith(p, "{"), split(path, "/", keepempty=false))

function _register_indexed_route(T, method, name, path, n_params, record_dir)
    base = _base_segments(path)
    _register_handler(method, path, function(req)
        local obj
        try
            obj = T(; req, __req__=req)
        catch err
            return _route_error_response(req, err, catch_backtrace())
        end
        try
            idx_vals, kw_pairs = _extract_args(T, Val(name), req, method, base, n_params)
            prop = getproperty(obj, name)
            val = prop(idx_vals...; NamedTuple(kw_pairs)...)
            save_path = !isnothing(record_dir) ? "/" * join(vcat(string(name), string.(idx_vals)), "/") : nothing
            return _resolve_response(obj, req, val; record_dir, save_path)
        catch err
            bt = catch_backtrace()
            page_chain = _has_page(obj) ? Any[obj] : Any[]
            return _route_error_response(req, err, bt; error_obj=obj, page_chain)
        end
    end)
end

function _warn_docs_prefix(path, name)
    startswith(lstrip(path, '/'), "docs") &&
        @error "Route `$name` maps to path \"$path\" which starts with \"/docs\" — Oxygen reserves this prefix for its Swagger UI. The route will silently 404. Rename the route to avoid the \"/docs\" prefix."
end

function _register_routes(T; prefix="", record_dir=nothing, parent_chain=Symbol[])
    for (name, info) in DynamicObjects.meta(T)
        DynamicObjects.isfixed(info) && continue

        # Handle nested structs: inline struct definitions or @include externals
        nested_type = _nested_struct_type(T, Val(name))
        if !isnothing(nested_type) && !isempty(DynamicObjects.meta(nested_type))
            nested_prefix = isempty(prefix) ? string(name) : prefix * "/" * string(name)
            chain = vcat(parent_chain, [name])
            _register_included_routes(T, nested_type, chain, nested_prefix, record_dir)
            continue
        end

        method = nothing
        for (macro_sym, m) in _http_verbs
            macro_sym in info.macros && (method = m; break)
        end
        isnothing(method) && continue

        # Separate positional indices from kwargs (:parameters node)
        positional_indices = Any[]
        has_kwargs = false
        for idx in info.indices
            if Meta.isexpr(idx, :parameters)
                has_kwargs = true
            else
                push!(positional_indices, idx)
            end
        end

        param_strs = [string(first(DynamicObjects.extractnames(idx))) for idx in positional_indices]
        n_params = length(param_strs)

        base = "/" * (isempty(prefix) ? "" : prefix * "/") * string(name)
        path = isempty(param_strs) ? base :
            base * "/" * join("{" .* param_strs .* "}", "/")
        name == :index && isempty(prefix) && (path = "/")
        _warn_docs_prefix(path, name)

        # Detect trailing defaults for shortened route registration
        # Only need positions, not values — DynamicObjects handles defaults
        default_positions = Int[]
        for (j, idx) in enumerate(positional_indices)
            if Meta.isexpr(idx, :kw)
                push!(default_positions, j)
            elseif !isempty(default_positions)
                empty!(default_positions)
                break
            end
        end

        # Capture loop variables to avoid closure-over-mutable-variable issues
        let name=name, param_strs=param_strs, n_params=n_params, path=path, record_dir=record_dir, method=method, default_positions=default_positions, has_kwargs=has_kwargs
            if method == "WEBSOCKET"
                if isempty(param_strs) && !has_kwargs && !info.indexed
                    register(CONTEXT[], "WEBSOCKET", path, function(ws)
                        lambda = getproperty(T(; req=nothing, __req__=nothing), name)
                        lambda(ws)
                    end)
                else
                    # Indexed/kwargs WS route: extract params from ws.request
                    ws_base = _base_segments(path)
                    register(CONTEXT[], "WEBSOCKET", path, function(ws)
                        idx_vals, kw_pairs = _extract_args(T, Val(name), ws.request, "GET", ws_base, n_params)
                        prop = getproperty(T(; req=ws.request, __req__=ws.request), name)
                        lambda = prop(idx_vals...; NamedTuple(kw_pairs)...)
                        lambda(ws)
                    end)
                end
            elseif isempty(param_strs) && !has_kwargs && !info.indexed
                register(CONTEXT[], method, path, function(req)
                    local obj
                    try
                        obj = T(; req, __req__=req)
                    catch err
                        return _route_error_response(req, err, catch_backtrace())
                    end
                    try
                        val = getproperty(obj, name)
                        return _resolve_response(obj, req, val; record_dir, save_path=record_dir !== nothing ? path : nothing)
                    catch err
                        bt = catch_backtrace()
                        page_chain = _has_page(obj) ? Any[obj] : Any[]
                        return _route_error_response(req, err, bt; error_obj=obj, page_chain)
                    end
                end)
            elseif isempty(param_strs) && !has_kwargs
                # Zero-arg indexed property (e.g. @get index() = ...): call () to compute
                _register_indexed_route(T, method, name, path, 0, record_dir)
            elseif isempty(param_strs) && has_kwargs
                # kwargs-only route (no path params)
                !isnothing(record_dir) && push!(_static_kwargs_paths, path)
                _register_indexed_route(T, method, name, path, 0, record_dir)
            else
                # Register the full route (all params explicit)
                _register_indexed_route(T, method, name, path, n_params, record_dir)

                # Register shortened routes for trailing defaults
                # e.g. filter(a, b=1, c=2) → also /filter/{a}/{b} and /filter/{a}
                for k in length(default_positions):-1:1
                    cut = default_positions[k]  # position of first omitted param
                    short_params = param_strs[1:cut-1]
                    short_path = isempty(short_params) ? base :
                        base * "/" * join("{" .* short_params .* "}", "/")
                    name == :index && isempty(prefix) && isempty(short_params) && (short_path = "/")
                    _register_indexed_route(T, method, name, short_path, length(short_params), record_dir)
                end
            end
        end
    end
end

# Register a single included route handler with chained property access through the parent.
"""
    _register_included_handler(ParentT, NestedT, method, name, chain, path, n_params, record_dir)

Register a route handler for a nested `@include` struct property.

For direct browser visits (non-HTMX), the response is wrapped by nesting all
`__page__` wrappers (or legacy `page`) found along the property chain from
root to leaf. If the root defines `__page__` and a nested struct also defines
one, the result is `root.__page__(nested.__page__(fragment))` — innermost
wraps first, then each ancestor.

# TODO: add an API to opt out of page nesting for specific structs (e.g. a `page_nest=false`
# property or a `_page_passthrough` convention) for cases where a nested struct wants to
# fully replace the parent's page rather than compose with it.
"""
function _register_included_handler(ParentT, NestedT, method, name, chain, path, n_params, record_dir)
    base = _base_segments(path)
    _register_handler(method, path, function(req)
        local parent, nested
        try
            parent = ParentT(; req, __req__=req)
        catch err
            return _route_error_response(req, err, catch_backtrace())
        end
        try
            nested = foldl((o, n) -> getproperty(o, n), chain; init=parent)
        catch err
            bt = catch_backtrace()
            page_chain = _has_page(parent) ? Any[parent] : Any[]
            return _route_error_response(req, err, bt; error_obj=parent, page_chain)
        end
        try
            idx_vals, kw_pairs = _extract_args(NestedT, Val(name), req, method, base, n_params)
            val = let prop = getproperty(nested, name)
                if isempty(idx_vals) && isempty(kw_pairs) && !(prop isa DynamicObjects.IndexableProperty)
                    prop
                else
                    prop(idx_vals...; NamedTuple(kw_pairs)...)
                end
            end
            sp = !isnothing(record_dir) ? "/" * join(vcat(string.(chain), string(name), string.(idx_vals)), "/") : nothing
            # Collect page wrappers along the chain (root → ... → nested) for nesting.
            page_chain = _collect_page_chain(parent, chain)
            return _resolve_response_nested(page_chain, req, val; record_dir, save_path=sp)
        catch err
            bt = catch_backtrace()
            page_chain = _collect_page_chain(parent, chain)
            return _route_error_response(req, err, bt; error_obj=nested, page_chain)
        end
    end)
end

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

Look up the framework-managed request on `obj`, preferring the canonical
`__req__` name over the legacy `req` name. Prefers whichever is non-nothing
so that `@include ext = Ext(; req)` call sites (which only populate `req`
even on migrated child structs whose body declares `__req__ = nothing`)
still surface the real request rather than the compute-default `nothing`.
The legacy `req` name is deprecated — the `@htmx` macro emits a warning at
expansion time when it sees a `req` property (see `_warn_legacy_req_name!`).
"""
function _req_of(obj)
    if hasproperty(obj, :__req__)
        r = getproperty(obj, :__req__)
        isnothing(r) || return r
    end
    hasproperty(obj, :req) ? getproperty(obj, :req) : nothing
end

"""
    _collect_page_chain(root, chain) -> Vector

Walk the property chain from `root` and collect objects that define a
`__page__` (or legacy `page`) property. Deduplicates inherited pages: if a
nested struct's page property is inherited from its parent (inline struct),
it is skipped.

Never use `DynamicObjects.meta` to inspect properties — use `hasproperty` and type checks.
"""
function _collect_page_chain(root, chain)
    pages = Any[]
    _has_page(root) && push!(pages, root)
    obj = root
    for name in chain
        prev_type = typeof(obj)
        obj = getproperty(obj, name)
        if _has_page(obj)
            # Skip if the page property is inherited (same defining type as parent)
            prev_type == typeof(obj) && continue
            # Skip if the page property type is a child of the previous page owner
            # (inline structs inherit parent properties — detect by type name prefix)
            obj_name = string(nameof(typeof(obj)))
            prev_name = string(nameof(prev_type))
            startswith(obj_name, prev_name * "_") && continue
            push!(pages, obj)
        end
    end
    pages
end

"""Like `_resolve_response`, but applies nested page wrappers (innermost first, then outward)."""
function _resolve_response_nested(page_chain, req, val; record_dir=nothing, save_path=nothing)
    val isa HTTP.Response && return val
    if wants_errors(req)
        val = filter_errors(val)
        isnothing(val) && return markdown_response("(no errors)")
    end
    if !isnothing(record_dir) && !isnothing(save_path)
        save_response(record_dir, save_path, to_response(static_transform(val)))
    end
    if wants_markdown(req)
        # Use the innermost (last) struct for markdown, if any
        obj = isempty(page_chain) ? nothing : last(page_chain)
        if !isnothing(obj) && hasproperty(obj, :to_markdown)
            return to_response(getproperty(obj, :to_markdown)[val])
        else
            return markdown_response(to_markdown_string(val))
        end
    end
    is_htmx(req) && return to_response(val)
    # Apply page wrappers: innermost (last) wraps first, then each outer one
    for obj in reverse(page_chain)
        wrapper = _page_wrapper(obj)
        isnothing(wrapper) || (val = wrapper[val])
    end
    to_response(val)
end

# Register routes from a nested @include struct with chained property access through the parent.
function _register_included_routes(ParentT, NestedT, chain::Vector{Symbol}, prefix::String, record_dir)
    # Track reverse lookup so _reroute!(NestedT) can trigger parent re-registration
    push!(get!(Set{DataType}, _included_type_parents, NestedT), ParentT)
    for (name, info) in DynamicObjects.meta(NestedT)
        DynamicObjects.isfixed(info) && continue

        # Recurse into nested structs: inline struct definitions or @include externals
        nested_type = _nested_struct_type(NestedT, Val(name))
        if !isnothing(nested_type) && !isempty(DynamicObjects.meta(nested_type))
            _register_included_routes(ParentT, nested_type, vcat(chain, [name]),
                prefix * "/" * string(name), record_dir)
            continue
        end

        method = nothing
        for (macro_sym, m) in _http_verbs
            macro_sym in info.macros && (method = m; break)
        end
        isnothing(method) && continue

        # Build path
        positional_indices = Any[]
        has_kwargs = false
        for idx in info.indices
            if Meta.isexpr(idx, :parameters)
                has_kwargs = true
            else
                push!(positional_indices, idx)
            end
        end

        param_strs = [string(first(DynamicObjects.extractnames(idx))) for idx in positional_indices]
        n_params = length(param_strs)

        base = "/" * prefix * "/" * string(name)
        path = isempty(param_strs) ? base :
            base * "/" * join("{" .* param_strs .* "}", "/")
        # :index on nested struct → just the prefix path
        name == :index && (path = "/" * prefix)
        _warn_docs_prefix(path, name)

        # Track kwargs-only paths for static recording
        !isnothing(record_dir) && isempty(param_strs) && has_kwargs && push!(_static_kwargs_paths, path)

        # Detect trailing defaults (only positions — DynamicObjects handles values)
        default_positions = Int[]
        for (j, idx) in enumerate(positional_indices)
            if Meta.isexpr(idx, :kw)
                push!(default_positions, j)
            elseif !isempty(default_positions)
                empty!(default_positions)
                break
            end
        end

        let name=name, chain=chain, param_strs=param_strs, n_params=n_params, path=path, method=method, record_dir=record_dir, default_positions=default_positions, base=base
            # Register the full route
            _register_included_handler(ParentT, NestedT, method, name, chain, path, n_params, record_dir)

            # Register shortened routes for trailing defaults
            for k in length(default_positions):-1:1
                cut = default_positions[k]
                short_params = param_strs[1:cut-1]
                short_path = isempty(short_params) ? base :
                    base * "/" * join("{" .* short_params .* "}", "/")
                name == :index && isempty(short_params) && (short_path = "/" * prefix)
                _register_included_handler(ParentT, NestedT, method, name, chain, short_path, length(short_params), record_dir)
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
    if haskey(_registered_types, T)
        args = _registered_types[T]
        _register_routes(T; args.prefix, args.record_dir)
    end
    # If T is an @include'd sub-struct, re-register its parent(s)
    if haskey(_included_type_parents, T)
        for ParentT in _included_type_parents[T]
            haskey(_registered_types, ParentT) || continue
            args = _registered_types[ParentT]
            _register_routes(ParentT; args.prefix, args.record_dir)
        end
    end
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
filter_errors((content, id)::Pair) = let filtered = filter_errors(content)
    isnothing(filtered) ? nothing : filtered => id
end

function _has_error_attr(node::Node)
    cn = parent(node)
    attrs = Cobweb.attrs(cn)
    get(attrs, Symbol("data-error"), nothing) == "true"
end
_has_error_attr(node::Cobweb.Node) = _has_error_attr(Node(node))
_has_error_attr(::Any) = false

function filter_errors(node::Node)
    # If this node is an error node, keep it entirely
    _has_error_attr(node) && return node

    # Otherwise, recurse into children and keep only error-containing branches
    cn = parent(node)
    children = Cobweb.children(cn)
    new_children = []
    for child in children
        if child isa Node || child isa Cobweb.Node
            filtered = filter_errors(child isa Cobweb.Node ? Node(child) : child)
            !isnothing(filtered) && push!(new_children, parent(filtered))
        end
        # Drop non-Node children (text) in non-error nodes
    end

    # If no error children survived, prune this branch
    isempty(new_children) && return nothing

    # Keep this node as a structural wrapper with only error children
    Node(Cobweb.Node(Cobweb.tag(cn), copy(Cobweb.attrs(cn)), new_children))
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
caption_style() = h.style("""
figure.captioned { margin: 0 0 1rem 0; }
figcaption.caption { margin-bottom: 0.5rem; }
.caption-header { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; }
.caption-actions { display: inline-flex; gap: 0.25rem; flex-shrink: 0; }
.caption-action { padding: 0.1rem 0.5rem; font-size: 0.85em; margin: 0; }
.caption-long { margin-top: 0.25rem; }
.caption-long > summary { cursor: pointer; font-size: 0.9em; opacity: 0.75; }
""")

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
            spec.long isa AbstractString ? h.div(spec.long) : spec.long,
        )
    h.figcaption(; class="caption")(header, body)
end

"""
    with_caption(spec::CaptionSpec, content; actions=())

Wrap `content` (a single node or iterable of nodes) in a `<figure>` with the
caption rendered above it. Returns `nothing` for `spec` is not allowed —
use `content` directly if there is no caption.
"""
function with_caption(spec::CaptionSpec, content; actions=())
    children = (content isa Tuple || content isa AbstractVector) ? content : (content,)
    h.figure(; class="captioned")(render_caption(spec; actions), children...)
end

# --- Table rendering ---

"""
    sortable_table_js()

Return an `h.script(...)` node containing the `sortTable` JavaScript function
for click-to-sort table headers. Include this once per page (e.g. in `extra_head`).

The JS finds the `<tbody>` relative to the clicked header (no hardcoded ID),
so multiple sortable tables can coexist on the same page. Numeric values are
sorted numerically; everything else uses `localeCompare`.
"""
function sortable_table_js()
    h.script(raw"""
function sortTable(col, th) {
    const tbody = th.closest('table').querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const asc = th.dataset.sortDir !== 'asc';
    th.dataset.sortDir = asc ? 'asc' : 'desc';
    th.closest('tr').querySelectorAll('th').forEach(h => { if (h !== th) delete h.dataset.sortDir; });
    rows.sort((a, b) => {
        const av = a.cells[col].textContent.trim();
        const bv = b.cells[col].textContent.trim();
        const an = parseFloat(av), bn = parseFloat(bv);
        if (!isNaN(an) && !isNaN(bn)) return asc ? an - bn : bn - an;
        return asc ? av.localeCompare(bv) : bv.localeCompare(av);
    });
    rows.forEach(r => tbody.appendChild(r));
    th.closest('tr').querySelectorAll('th').forEach(h => {
        h.textContent = h.textContent.replace(/ [▲▼]$/, '');
    });
    th.textContent += asc ? ' ▲' : ' ▼';
}
""")
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
    h.script(raw"""
function downloadTableCsv(btn, filename) {
    const wrap = btn.closest('figure, .table-wrap') || btn.parentElement;
    const table = wrap.querySelector('table');
    const esc = s => {
        s = String(s);
        return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    const headers = Array.from(table.querySelectorAll('thead th'))
        .map(th => esc(th.textContent.replace(/ [▲▼]$/, '').trim()));
    const rows = Array.from(table.querySelectorAll('tbody tr')).map(tr =>
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
""")
end

"""
    render_table(table; id=nothing, sortable=true, download=false, download_filename=nothing, caption=nothing, cell=nothing, class="striped", kwargs...)

Render any Tables.jl-compatible table (DataFrame, NamedTuple of vectors, etc.)
as an `h.table` HTML node.

# Keyword arguments
- `id`: tbody element id (auto-generated if `nothing`)
- `sortable`: add click-to-sort headers (default `true`; requires `sortable_table_js()` on the page)
- `download`: add a "⬇ CSV" button (default `false`; requires `download_table_js()` on the page).
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
function render_table(table; id=nothing, sortable=true, download=false, download_filename=nothing, caption=nothing, cell=nothing, class="striped", kwargs...)
    cols = Tables.columnnames(Tables.columns(table))
    isnothing(id) && (id = "tbl-" * string(hash(cols), base=16))

    headers = if sortable
        [h.th(string(c); onclick="sortTable($(i-1), this)", style="cursor:pointer")
         for (i, c) in enumerate(cols)]
    else
        [h.th(string(c)) for c in cols]
    end

    body_rows = [
        h.tr([h.td(isnothing(cell) ? string(Tables.getcolumn(row, c)) : cell(Tables.getcolumn(row, c), c, ri))
              for c in cols]...)
        for (ri, row) in enumerate(Tables.rows(table))
    ]

    table_node = h.table(; class, role="grid", kwargs...)(
        h.thead(h.tr(headers...)),
        h.tbody(body_rows...; id)
    )

    fname = something(download_filename, id * ".csv")
    download_btn = download ? h.button("⬇ CSV"; type="button", class="outline caption-action",
                                        onclick="downloadTableCsv(this, '$(fname)')") : nothing

    if !isnothing(caption)
        actions = download ? (download_btn,) : ()
        with_caption(caption, table_node; actions)
    elseif download
        h.figure(; class="captioned")(
            h.figcaption(; class="caption")(
                h.div(; class="caption-header")(h.span(""), h.span(; class="caption-actions")(download_btn))
            ),
            table_node,
        )
    else
        table_node
    end
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

# --- Test UI stubs (implemented by TestExt when Test is loaded) ---
function test_list end
function test_run! end
function test_run_all! end
function test_run_batch! end
function test_run_failed! end
function test_run_missing! end
function test_clear_cache! end

# --- Shared route structs for @include ---

# Provides web routes for running tests registered via TestModules. Include in an
# @htmx struct with `@include tests = TestRoutes(; __req__, test_module=@__MODULE__)`
# to add test listing, running, and cache management endpoints under /tests/.
@htmx struct TestRoutes
    test_module = nothing
    prefix = "/tests"
    md = wants_markdown(__req__)
    @get index = test_list(test_module, md; prefix)
    @post run(name) = test_run!(test_module, name, md; prefix)
    @post run_all = test_run_all!(test_module, md; prefix)
    @post run_failed = test_run_failed!(test_module, md; prefix)
    @post run_missing = test_run_missing!(test_module, md; prefix)
    @post run_batch(; names="") = test_run_batch!(test_module, names, md; prefix)
    @post clear_cache = test_clear_cache!(test_module, md; prefix)
end

"""
    hidden_inputs(; kwargs...) -> Vector{Node}

Generate hidden `<input>` elements for each keyword argument. Splat into a form
to pass parameters to `@post` routes via `formdata`:

    h.form(; hx_post="/foo", hx_target="#list", hx_swap="innerHTML")(
        hidden_inputs(; script=path, worktree=wt)...,
        h.button(; class="btn", type="submit")("Go"),
    )
"""
_hidden_input(k, v) = [h.input(; type="hidden", name=string(k), value=string(v))]
_hidden_input(k, v::AbstractVector) = [h.input(; type="hidden", name=string(k), value=string(x)) for x in v]
hidden_inputs(; kwargs...) = vcat([_hidden_input(k, v) for (k, v) in kwargs]...)

"""
    _form(method, url, children...; label="Submit", btn_class="btn", confirm="", hx_target="", hx_swap="", hx_include="", form_class="", kwargs...)

Shared implementation for `get_form` and `post_form`. `method` is `:hx_get` or
`:hx_post`. Extra keyword arguments become hidden `<input>` fields. Positional
`children` are inserted before the submit button.
"""
const _FORM_KEYS = Set([:label, :btn_class, :confirm, :form_class])
_is_form_attr(k) = startswith(String(k), "hx_") || k in (:id, :class, :style, :enctype)

function _form(method, url, children...; label="Submit", btn_class="btn", confirm="", form_class="", kwargs...)
    form_kw = filter(((k, _),) -> _is_form_attr(k), pairs(kwargs))
    hidden_kw = filter(((k, _),) -> !_is_form_attr(k), pairs(kwargs))
    base_attrs = filter(((_, v),) -> !isempty(string(v)), pairs((;
        method => url, style="display:inline",
        hx_confirm=confirm, class=form_class,
    )))
    btn = isnothing(label) ? [] : [h.button(; class=btn_class, type="submit")(label)]
    h.form(; base_attrs..., form_kw...)(
        hidden_inputs(; hidden_kw...)...,
        children...,
        btn...,
    )
end

"""
    post_form(url, children...; kwargs...)

Generate a complete inline POST form. Extra keyword arguments become hidden
`<input>` fields. Positional `children` are inserted before the submit button.

    post_form("/respond/slug/approved";
        label="Approve", btn_class="btn btn-approve",
        hx_target="#list", hx_swap="innerHTML",
        msg="APPROVED.",
    )
"""
post_form(url, children...; kwargs...) = _form(:hx_post, url, children...; kwargs...)

"""
    get_form(url, children...; kwargs...)

Generate a complete inline GET form. Same API as [`post_form`](@ref) but uses
`hx-get` instead of `hx-post`.

    get_form("/analysis/dose_response",
        sinput((; sources), source_options; multiple=true),
        sinput((; outcomes), outcome_options; multiple=true);
        hx_target="#results", hx_swap="innerHTML",
        fit_key, top_chains=string(top_chains),
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
query_url(path; kwargs...) = begin
    filtered = filter(p -> !isnothing(p.second), pairs(kwargs))
    isempty(filtered) && return path
    parts = String[]
    for (k, v) in filtered
        if v isa AbstractVector
            for item in v
                push!(parts, HTTP.URIs.escapeuri(string(k)) * "=" * HTTP.URIs.escapeuri(string(item)))
            end
        else
            push!(parts, HTTP.URIs.escapeuri(string(k)) * "=" * HTTP.URIs.escapeuri(string(v)))
        end
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
    expr isa Expr && expr.head === :call || error("@query_url expects a call expression like `prop(args...; kwargs...)`")
    name_expr = expr.args[1]
    # In DO/HTMXO context, name may be __self__.prop (a :. expression) — extract the symbol
    if name_expr isa Expr && name_expr.head === :.
        name = name_expr.args[2]
        name = name isa QuoteNode ? name.value : name
    elseif name_expr isa Symbol
        name = name_expr
    else
        error("@query_url: property name must be a symbol, got $name_expr")
    end

    # Separate positional args and kwargs
    positional = []
    kwargs = []
    for arg in expr.args[2:end]
        if arg isa Expr && arg.head === :parameters
            append!(kwargs, arg.args)
        elseif arg isa Expr && arg.head === :kw
            push!(kwargs, arg)
        else
            push!(positional, arg)
        end
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
        kw_exprs = [kw isa Symbol ? Expr(:kw, kw, esc(kw)) : Expr(:kw, kw.args[1], esc(kw.args[2])) for kw in kwargs]
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
attributes and `style="display:none"`. Include [`show_when_script`](@ref) once per
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
    option_values = Set(string.([o isa Pair ? first(o) : o for o in options]))
    extra_options = isnothing(value) ? [] : [v for v in (value isa AbstractVector ? value : [value]) if !(string(v) in option_values)]
    all_options = vcat(options, extra_options)
    h.label(
        label,
        h.div(
            h.select([
                soption(option; selected_value=value) for option in all_options
            ]...; id=sel_id, name, aria_label=label, kwargs...),
            h.span(
                h.input(; id=inp_id, type="text", placeholder,
                    style="min-width:0;flex:1",
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
                style="display:flex;gap:0.25em;margin-top:0.25em"
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
            style="display:flex;align-items:center;gap:0.5ch"
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
            opt_value, opt_label = option isa Union{Tuple,Pair} ? option : (option, option)
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
        style="display:none")
end

"""
    show_when_script()

Return a `<script>` that wires `change` listeners for all `[data-show-when-field]`
elements. Include once per page (like [`loading_indicator_script`](@ref)).

Evaluates visibility on load and re-initializes on `htmx:afterSettle` for
dynamically swapped content.
"""
show_when_script() = h.script(raw"""
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
    el.style.display = show ? '' : 'none';
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
""")

# --- Request feedback ---

"""
    request_feedback_style()

CSS for automatic HTMX request feedback: pulsating border while in-flight,
brief color flash on success/failure.
"""
request_feedback_style() = h.style("""
@keyframes htmx-pulse {
    0%, 100% { outline-color: color-mix(in srgb, #4a90d9 30%, transparent); }
    50% { outline-color: #4a90d9; }
}
.htmx-request-active {
    outline: 2px solid #4a90d9;
    outline-offset: -2px;
    animation: htmx-pulse 1s ease-in-out infinite;
}
.htmx-request-success {
    outline: 2px solid #2a9d8f;
    outline-offset: -2px;
    animation: htmx-fade-success 1s ease-out forwards;
}
.htmx-request-error {
    outline: 2px solid #e76f51;
    outline-offset: -2px;
    animation: htmx-fade-error 2s ease-out forwards;
}
@keyframes htmx-fade-success {
    0% { outline-color: #2a9d8f; }
    100% { outline-color: transparent; }
}
@keyframes htmx-fade-error {
    0% { outline-color: #e76f51; }
    100% { outline-color: transparent; }
}
""")

"""
    request_feedback_script()

JS that hooks into HTMX events to add visual feedback classes on the target element
of each request.
"""
request_feedback_script() = h.script("""
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
""")

"""
    request_feedback()

Combined style + script nodes for automatic HTMX request feedback.
Included by default in `htmx()`.
"""
request_feedback() = (request_feedback_style(), request_feedback_script())

"""
    loading_indicator_script()

Return a `Node` `<script>` that sets `aria-busy` on HTMX target elements during
requests. Pico CSS renders a spinner automatically for `aria-busy` elements.

!!! note
    Deprecated in favor of `request_feedback()` which provides richer visual feedback.
"""
loading_indicator_script() = h.script("""
document.body.addEventListener('htmx:beforeRequest', function(e) {
    e.detail.elt.setAttribute('aria-busy', 'true');
});
document.body.addEventListener('htmx:afterRequest', function(e) {
    e.detail.elt.removeAttribute('aria-busy');
});
""")

# --- Tabset ---

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
function _tabset_panel(content::AbstractString, i, active)
    # String content = URL → lazy load via hx-get on first reveal
    base_style = i == active ? "width:100%;" : "display:none; width:100%;"
    h.div(;
        class="tab-panel",
        data_panel="tab-$i",
        style=base_style,
        hx_get=content,
        hx_trigger="revealed once",
        hx_swap="innerHTML",
    )
end
function _tabset_panel(content, i, active)
    # Non-string content = eager render
    h.div(content;
        class="tab-panel",
        data_panel="tab-$i",
        style = i == active ? "width:100%;" : "display:none; width:100%;",
    )
end

tabset(tabs::Pair...; active=1, id="tabset-$(hash(first.(tabs)))") = h.div(; id)(
    h.nav(
        h.ul([
            h.li(h.a(label;
                href="#",
                class = i == active ? "contrast" : "secondary",
                _="on click
                    remove .contrast from <a/> in closest <nav/>
                    add .secondary to <a/> in closest <nav/>
                    remove .secondary from me
                    add .contrast to me
                    set panel to my @data-panel
                    hide <div.tab-panel/> in closest <div/>
                    show <div.tab-panel[data-panel='\${panel}']/> in closest <div/>
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

const _DEFAULT_STATUS_COLORS = (running="orange", finishing="orange", done="green", failed="red", pending="gray")

"""
    status_badge(state::Symbol; colors=_DEFAULT_STATUS_COLORS, label=nothing)

Render a colored `<span>` badge for a status state. Uses Pico-friendly inline styles.
Override the display text with `label`, or it defaults to the titlecased state name.

    status_badge(:running)                       # orange "Running"
    status_badge(:failed; label="Error!")         # red "Error!"
    status_badge(:custom; colors=Dict(:custom => "blue"))
"""
function status_badge(state::Symbol; colors=_DEFAULT_STATUS_COLORS, label=nothing)
    color = get(colors, state, "inherit")
    text = something(label, titlecase(string(state)))
    h.span(text; style="color:$color;")
end

# --- Nav sidebar ---

"""
    nav_sidebar(items::Vector{<:Pair}; prefix="", target="#content", active_class="contrast", inactive_class="secondary")

Render a Pico CSS sidebar `<aside>` with HTMX-enabled navigation links.
Each item is a `"Label" => "/path"` pair. Links use hyperscript to toggle active styling.

    nav_sidebar(["Overview" => "/overview", "Settings" => "/settings"]; prefix="/app")
"""
function nav_sidebar(items::Union{AbstractVector{<:Pair}, Tuple{Vararg{Pair}}}; prefix="", target="#content", active_class="contrast", inactive_class="secondary")
    h.aside(; style="max-height:100vh; overflow-y:auto; position:sticky; top:0;")(
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

function __init__()
    ERROR_DIR[] = get(ENV, "HTMXO_ERROR_DIR", joinpath(tempdir(), "htmxo_errors"))
end

end # module HTMXObjects
