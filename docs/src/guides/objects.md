# Objects and routes

Separate data that survives requests from the request objects that render it,
then compose those routes under a shared prefix.

## Lifetimes

```@example objects
using HTMXObjects

@dynamicstruct struct Labels
    values = ["plasma", "serum"]
end
label_data = Labels();

@htmx struct LabelRoutes
    (; values) = __appdata__
    @get show(id::Int) = h.p(values[id])
end

@htmx struct LabelApp
    __appdata__ = label_data
    @include labels = LabelRoutes()
end

route!(LabelApp(); prefix="/inventory");
response = dispatch(:GET, "/inventory/labels/show/2");
@assert response.status == 200 # hide
Base.HTML(String(response.body))
```

`label_data` is the persistent data object. Each request receives a fresh route
object, and the included `LabelRoutes` obtains `__appdata__` from its parent.
The positional `id::Int` argument is parsed from the path before the route body
indexes the vector.

Derived properties with a right-hand side are evaluated lazily and memoised on
their object. Put expensive reusable work on the persistent object; put
request-derived rendering on the request object. A mutable data structure needs
its own concurrency and invalidation policy. Request reconstruction does not
invalidate a cache on an unrelated persistent object.

## Composition

`@include labels = LabelRoutes()` contributes the `labels` path segment.
Registration contributes `/inventory`. Reflection describes the type's route
tree before the registration prefix is applied:

```@example objects
[(r.verb, r.path) for r in reflect(LabelApp)]
```

Use route-relative links when the same component can appear under different
mounts. Within a route object, `__self__` identifies that object's mounted path;
`__self__/"show/2"` appends a child path. Hard-coded absolute URLs couple a
component to a particular registration prefix.

## Registration

`route!` registers the object type and its configuration on the process router.
`dispatch` sends an in-process request to it; `serve` opens the HTTP listener.
Register each independent example under a distinct prefix when several share a
Julia process. Mount application routes before opening the listener.

`@get`, `@post`, `@put`, `@patch`, `@delete`, `@ws`, `@sse`, `@include` and
`@param` are declaration forms inside `@htmx`, rather than standalone exported
macros. Their contract belongs to [`@htmx`](@ref). Use GET for retrieval;
declare a mutation as a mutation verb even when its result is HTML.

The [sample browser](../examples/sample-browser.md) uses this lifetime split
with a reusable selection property and an executed response check.
