# --- Generic tracked-collection CRUD --------------------------------------
#
# `Resource(collection; input, policy, render)` mounts collection/item CRUD over
# a Base-shaped tracked store. It is a BUNDLE, not a macro: it is an ordinary
# `@htmx struct`, so its routes, its `{key}` child and its option domains reach
# the reflection graph through exactly the same walk as hand-written routes —
# nothing here teaches the reflector a special case.
#
# The generated contract uses resource names, not action names:
#
#   GET    /resources        collection index
#   POST   /resources        collection index  (create)
#   GET    /resources/{key}  item index
#   PUT    /resources/{key}  item index        (complete replacement)
#   PATCH  /resources/{key}  item index        (partial update)
#   DELETE /resources/{key}  item index        (remove)
#
# The six live on two property names — `index` on the bundle and `index` on its
# indexed child — because same-name-different-verb routes share one URL by
# `Verb{V}` dispatch, and an `@include index(key)` collapses its own segment.
# So the URL shape above is the `:index` rule doing its job, not a second
# routing scheme.
#
# Division of labour, deliberately narrow:
#   * the STORE owns locking, versioning and invalidation;
#   * the POLICY owns authorization, validation, key derivation, optimistic
#     concurrency and response overrides;
#   * the BUNDLE owns only transport — parse, dispatch, render.
# Long-running or transformational work stays an explicit route; this is CRUD.

"""
    ResourcePolicy(; authorize, validate, key, precondition, respond, fields)

Application hooks for a [`Resource`](@ref) mount. Every hook is optional and
receives the same `context` NamedTuple — `(; operation, resource, collection,
key, draft, current, req)` — so a policy can be written against whichever
fields it cares about and ignore the rest.

- `authorize(context) -> Bool` — reject with 403 when false. Default: allow.
- `validate(context) -> nothing | AbstractString` — a returned string is the
  400 message. Default: accept.
- `key(context) -> key` — derive the key for a `POST` create. Default: error,
  because inventing keys is an application decision, not a framework one.
- `precondition(context) -> Bool` — optimistic-concurrency gate for
  `PUT`/`PATCH`/`DELETE`; false returns 409. Default: allow.
- `respond(context, value) -> value` — override the rendered response.
- `fields(input) -> Vector{Symbol}` — the writable field names of the draft
  type. Default: `fieldnames(input)`.

`operation` is one of `:list`, `:create`, `:show`, `:replace`, `:update`,
`:delete`.
"""
struct ResourcePolicy
    authorize::Any
    validate::Any
    key::Any
    precondition::Any
    respond::Any
    fields::Any
end

_resource_allow(_context) = true
_resource_accept(_context) = nothing
_resource_no_key(context) = throw(ArgumentError(string(
    "creating a ", repr(context.resource), " resource requires a key: pass ",
    "`policy = ResourcePolicy(; key = context -> …)`, or POST to an explicit key ",
    "with PUT instead")))
_resource_identity(_context, value) = value
_resource_fields(input) = input === Nothing ? Symbol[] : collect(fieldnames(input))

ResourcePolicy(; authorize=_resource_allow, validate=_resource_accept,
                 key=_resource_no_key, precondition=_resource_allow,
                 respond=_resource_identity, fields=_resource_fields) =
    ResourcePolicy(authorize, validate, key, precondition, respond, fields)

# --- store access (Base-shaped, nothing more) ------------------------------
#
# "Base-shaped" is the whole contract: `keys`, `haskey`, `getindex`,
# `setindex!`, `delete!`. Anything satisfying it is a tracked store, so a Dict,
# a DynamicObjects-backed registry and a bespoke type all mount unchanged.

_resource_keys(collection) = collect(keys(collection))

# Reflection must never force a collection. Several real mounts are backed by a
# value that is not a store yet (an unresolved stub, a lazily-built registry),
# and describing a route surface is not a reason to make one exist. So the
# descriptor PROBES: a store that answers reports its facts, one that does not
# reports `nothing` and stays a boundary. Route bodies do not use this — they
# touch the store directly and are entitled to fail loudly.
function _resource_probe(f, collection)
    try f(collection) catch; nothing end
end

# URL segments arrive as strings; the store's keys usually are not strings.
# Convert through the key type the store actually reports, so `/fits/17` finds
# `collection[17]` — and fall back to matching on `string(k)` for key types
# without a `_convert_param` conversion.
function _resource_key(collection, raw::AbstractString)
    ks = _resource_keys(collection)
    isempty(ks) && return raw
    KeyT = typeof(first(ks))
    KeyT === String && return raw
    converted = try _convert_param(raw, KeyT) catch; nothing end
    converted === nothing || return converted
    idx = findfirst(k -> string(k) == raw, ks)
    idx === nothing ? raw : ks[idx]
end

_resource_key_type(collection) =
    let ks = _resource_keys(collection)
        isempty(ks) ? String : typeof(first(ks))
    end

# --- draft construction ----------------------------------------------------

# Build an `input` draft from the request. `PATCH` supplies only the fields
# present in the body and merges them over the current item, so a partial
# update never silently blanks an omitted field; `PUT`/`POST` construct the
# draft whole, which is what makes replacement total.
function _resource_draft(resource, req, current, partial::Bool)
    input = resource.input
    input === Nothing && return nothing
    source = bodyparams(req)
    names = resource.policy.fields(input)
    supplied = Dict{Symbol,Any}()
    for name in names
        value = _lookup_param(source, nothing, name, fieldtype(input, name))
        value === _NO_DEFAULT && continue
        supplied[name] = value
    end
    if partial
        current === nothing && return nothing
        values = Any[haskey(supplied, name) ? supplied[name] : getfield(current, name)
                     for name in names]
        return input(values...)
    end
    missing_fields = [name for name in names if !haskey(supplied, name)]
    isempty(missing_fields) || throw(MissingRequiredParam(first(missing_fields)))
    input(Any[supplied[name] for name in names]...)
end

# --- one gate for every mutating operation ---------------------------------
#
# authorize -> validate -> precondition, in that order, at ONE site. Each
# operation differs only in what it does after the gate, so forking the gate per
# verb would be five near-copies of the same three checks.
function _resource_gate(context)
    context.resource.policy.authorize(context) ||
        throw(_ResourceRefused(403, "Forbidden"))
    let message = context.resource.policy.validate(context)
        message === nothing ||
            throw(_ResourceRefused(400, string(message)))
    end
    context.resource.policy.precondition(context) ||
        throw(_ResourceRefused(409, "Conflict"))
    context
end

struct _ResourceRefused <: Exception
    status::Int
    message::String
end

Base.showerror(io::IO, err::_ResourceRefused) =
    print(io, "resource operation refused (", err.status, "): ", err.message)

# Carry the refusal's own status through the one `_error_status_code`
# chokepoint (403 / 404 / 409 instead of a blanket 500).
_unwrapped_status_code(err::_ResourceRefused) = err.status

_resource_context(resource, operation::Symbol; key=nothing, draft=nothing,
                  current=nothing, req=nothing) =
    (; operation, resource=resource.name, collection=resource.collection,
       key, draft, current, req)

function _resource_respond(resource, context, value)
    resource.policy.respond(context, value)
end

# --- default rendering -----------------------------------------------------
#
# Rendering is the application's business; these are only the fallbacks used
# when no `render` is supplied. They stay structural (`h.*` + `generic_html`) so
# `?plain` markdown and HX fragments come out of the ordinary response pipeline.

function _resource_render(resource, context, value)
    isnothing(resource.render) || return resource.render(context, value)
    context.operation === :list ? _resource_list_html(resource, value) :
        generic_html(value)
end

function _resource_list_html(resource, ks)
    isempty(ks) && return h.p(h.em("No $(resource.name) yet."))
    h.ul((h.li(hx_link(resource.__prefix__ * "/" * string(k))(string(k))) for k in ks)...)
end

"""
    Resource(collection; input=Nothing, policy=ResourcePolicy(), render=nothing,
             name="resource")

Mount collection/item CRUD over a Base-shaped tracked `collection` — anything
supporting `keys`, `haskey`, `getindex`, `setindex!` and `delete!`.

```julia
@include fits = Resource(store.fits; input = FitDraft, policy = FitPolicy(store))
```

registers `GET`/`POST` on `/fits` and `GET`/`PUT`/`PATCH`/`DELETE` on
`/fits/{key}`. Because the bundle is an ordinary `@htmx struct`, all six routes,
the `{key}` selection identity and the draft type appear in
[`semantic_descriptor`](@ref) and [`navigation`](@ref) with no special-casing.

- `input` — the draft type built from the request body on create/replace/update.
  Its `fieldnames` are the writable fields; `PATCH` merges over the current item.
- `policy` — a [`ResourcePolicy`](@ref): authorization, validation, key
  derivation, optimistic concurrency, response override.
- `render(context, value)` — response rendering; defaults to a key list for the
  collection and [`generic_html`](@ref) for an item.
- `name` — the human label used in default rendering and error messages.

The store owns locking, versioning and invalidation. Long-running or
transformational work is an explicit route, not a resource verb.
"""
@htmx struct Resource
    collection::Any
    input::Type = Nothing
    policy::ResourcePolicy = ResourcePolicy()
    render::Any = nothing
    name::String = "resource"

    """List the collection."""
    @get index() = let context = _resource_context(__self__, :list; req=__req__)
        _resource_gate(context)
        _resource_respond(__self__, context,
                          _resource_render(__self__, context, _resource_keys(collection)))
    end

    """Create one item in the collection."""
    @post index() = let draft = _resource_draft(__self__, __req__, nothing, false)
        context = _resource_context(__self__, :create; draft, req=__req__)
        _resource_gate(context)
        key = policy.key(context)
        collection[key] = draft
        stored = _resource_context(__self__, :create; key, draft,
                                   current=collection[key], req=__req__)
        _resource_respond(__self__, stored,
                          _resource_render(__self__, stored, collection[key]))
    end

    @include index(key::String) = ResourceItem(key)
end

"""
    ResourceItem(key)

The item half of a [`Resource`](@ref) mount — `GET`/`PUT`/`PATCH`/`DELETE` at
`/<resource>/{key}`. Constructed by `Resource`'s indexed `@include`; not mounted
directly.
"""
@htmx struct ResourceItem
    key::String
    resource = __parent__

    # Resolve the URL segment against the store's own key type once, here, so
    # every verb below addresses the same entry.
    stored_key = _resource_key(resource.collection, key)
    exists = haskey(resource.collection, stored_key)
    current = exists ? resource.collection[stored_key] : nothing

    """Show one item."""
    @get index() = _resource_item(__self__, :show) do context
        _resource_render(resource, context, context.current)
    end

    """Replace one item completely."""
    @put index() = _resource_item(__self__, :replace;
                                  draft=() -> _resource_draft(resource, __req__, nothing, false)) do context
        resource.collection[__self__.stored_key] = context.draft
        _resource_render(resource, context, resource.collection[__self__.stored_key])
    end

    """Update part of one item."""
    @patch index() = _resource_item(__self__, :update;
                                    draft=() -> _resource_draft(resource, __req__, __self__.current, true)) do context
        resource.collection[__self__.stored_key] = context.draft
        _resource_render(resource, context, resource.collection[__self__.stored_key])
    end

    """Remove one item."""
    @delete index() = _resource_item(__self__, :delete) do context
        delete!(resource.collection, __self__.stored_key)
        _resource_render(resource, context, (; deleted=__self__.key))
    end
end

# Shared item-verb body: 404 on a missing key, build the context, run the one
# gate, then hand control to the per-verb action. Every item verb needs exactly
# this preamble, so it lives once.
function _resource_item(action, item, operation::Symbol; draft=() -> nothing)
    resource = item.resource
    item.exists || throw(_ResourceRefused(404,
        string(resource.name, " ", repr(item.key), " not found")))
    context = _resource_context(resource, operation; key=item.stored_key,
                                draft=draft(), current=item.current,
                                req=item.__req__)
    _resource_gate(context)
    _resource_respond(resource, context, action(context))
end

"""
    resource_descriptor(obj) -> NamedTuple or nothing

Runtime reflection for a mounted [`Resource`](@ref): the facts that are field
VALUES and therefore invisible to the type-level
[`semantic_descriptor`](@ref) — the store's key type and current size, the draft
type and its writable fields, and the operations the mount actually exposes.

Returns `nothing` for anything that is not a `Resource`, so a caller can map it
over a whole graph without a type test.
"""
resource_descriptor(::Any) = nothing
function resource_descriptor(resource::Resource)
    input = resource.input
    keys_probe = _resource_probe(_resource_keys, resource.collection)
    (; name=resource.name,
       path=_nav_path(resource.__prefix__),
       # `nothing` here means "the store did not answer", not "empty" — a
       # stub-backed mount reflects its shape without being forced into
       # existence. `count == 0` is a real, answered, empty store.
       inspectable=keys_probe !== nothing,
       key_type=_resource_probe(_resource_key_type, resource.collection),
       count=keys_probe === nothing ? nothing : length(keys_probe),
       input=input,
       fields=NamedTuple[(; name, type=fieldtype(input, name))
                         for name in resource.policy.fields(input)],
       operations=[:list, :create, :show, :replace, :update, :delete])
end
