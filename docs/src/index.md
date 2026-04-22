# HTMXObjects.jl

Property-based web apps for Julia, built on [DynamicObjects.jl](https://github.com/nsiccha/DynamicObjects.jl),
[Oxygen.jl](https://github.com/OxygenFramework/Oxygen.jl), and
[HTMX.jl](https://github.com/nsiccha/HTMX.jl).

An HTMXObjects app is a pair of structs per feature:

- `XData`, a `@dynamicstruct` — holds data that lives for the server's lifetime
  (collections, caches, config).
- `XRoutes`, a `@htmx` struct — declares routes as properties. A fresh instance
  is built per request.

The framework wires both together so routes are Revise-reloadable, URLs respect
mount prefixes automatically, and common request-response concerns (HTMX
fragments, markdown negotiation, error pages) are handled without branching
inside route bodies.

## Quick start

Scaffold an app:

```julia
using HTMXObjects
create_app("MyApp.jl")
```

Then run it:

```bash
cd MyApp.jl && julia -i --project=app app/main.jl
```

A minimal app by hand:

```julia
using HTMXObjects
using HTMXObjects.DynamicObjects

@dynamicstruct struct AppData
    greeting::String = "Hello!"
end

const APPDATA = AppData()

@htmx struct AppRoutes
    __appdata__ = APPDATA
    (; greeting) = __appdata__

    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index = h.h1(greeting)
end

function __init__()
    route!(AppRoutes())
end
```

For larger apps, split each feature into its own file exposing a
`FeatureData`/`FeatureRoutes` pair and mount sub-routes from the root with
`@include`. See the
[paired data / routes architecture in the KB](https://github.com/nsiccha/Claude/blob/main/web-app-pattern.md)
for the full conventions.

## The two struct macros

### `@dynamicstruct` (data)

Holds state that outlives any single request — `Vector{String}` of items,
handles to external resources, results of expensive computations cached to
disk. Use one `const APPDATA = AppData()` at module top level; every
`@htmx struct` that needs access defaults its `__appdata__` to it.

### `@htmx` (routes)

`@htmx` wraps `@dynamicstruct` and adds a `_reroute!` call so Revise-triggered
re-evaluation automatically re-registers the struct's routes — no server
restart needed.

Properties without a RHS are fixed fields. Properties with a RHS (`name = expr`
or `name(args) = expr` / `name[args] = expr`) are derived and lazily
memoized per instance. Property bodies can reference siblings by bare name —
the macro rewrites them to `__self__.sibling`.

```julia
@htmx struct AppRoutes
    title = "My App"                         # derived, cached
    nav   = h.nav(h.strong(title))           # references `title`

    @get index           = h.main(nav, h.h1(title))
    @get post[id]        = h.p("post $id")       # GET /post/{id}
    @get page[id::Int]   = h.p("page $id")       # id auto-parsed to Int
end
```

## Routes

Prefix a property with a verb marker (`@get`, `@post`, `@put`, `@patch`,
`@delete`, `@ws`) to register it as a route when `route!(app)` is called.
Unmarked properties stay internal.

### Path and param syntax

| Declaration                         | Route(s)                                       |
|------------------------------------|------------------------------------------------|
| `@get index`                       | `GET /`                                        |
| `@get about`                       | `GET /about`                                   |
| `@get item(id)`                    | `GET /item/{id}` — `id::String`                |
| `@get item(id::Int)`               | `GET /item/{id}` — `id` auto-parsed            |
| `@get list(a, b=1)`                | `GET /list/{a}/{b}` + `GET /list/{a}` (b=1)    |
| `@get search(; q="", n::Int=1)`    | `GET /search?q=&n=` (query params)             |
| `@post submit(; name="")`          | `POST /submit` (form data)                     |
| `@get filter(cat; sort="name")`    | `GET /filter/{cat}?sort=` (mixed)              |
| `@delete remove(id)`               | `DELETE /remove/{id}`                          |
| `@ws feed`                         | `WEBSOCKET /feed` — body is `(__ws__) -> ...`  |

Rules:

- `index` maps to the struct's root (`/` at the top level, `/<prefix>` for
  included sub-structs).
- Call syntax `()` is required for kwargs; bracket syntax `[]` does not support
  `;` (Julia parses it as concatenation). Prefer `()` everywhere.
- Type annotations trigger `parse(T, str)` automatically (`_convert_param`).
  Built-ins include `Int`, `Float64`, `Bool`, `Symbol`, `Vector{T}`.
- Trailing positional defaults register the shortened route automatically — do
  not define two `@get` properties.

### Registering

```julia
route!(app)                              # register routes
route!(app; record_dir="site")           # + record every response to disk
route!(app; prefix="api")                # mount everything under /api
```

`route!` stores the type in `_registered_types` and (via the `_reroute!` hook
emitted by `@htmx`) re-registers automatically when Revise reloads the struct.
There is no `appdata` kwarg — shared data is threaded through `__appdata__`
(see [App data](#app-data-__appdata__)).

## Request &amp; response flow

Every request creates a fresh `T(; __req__ = request, __prefix__ = ..., ...)`.
The handler evaluates the property, and the return value flows through
`_resolve_response`:

1. `HTTP.Response` returns unchanged.
2. `Accept: text/markdown`, `?markdown`, or `?plain` → `to_markdown_string(val)`
   (falls back to `repr(MIME"text/markdown"(), val)`, then `string(val)`).
3. `?errors` → `filter_errors(val)` keeps only nodes tagged with `e.<tag>`.
4. HTMX request (`HX-Request: true`) → return the fragment as-is.
5. Otherwise wrap in `__page__(content)` if the struct (or any parent) defines
   one.

**Return bare content from routes.** Never call `__page__(...)` from a route
body (causes double layout) and never branch on `is_htmx(__req__)` /
`wants_markdown(__req__)` / `wants_errors(__req__)` — the framework does all of
this.

```julia
@htmx struct AppRoutes
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index      = h.div(h.h1("Hello"), h.p("World"))
    @get item(id)   = h.article(h.header("Item $id"))
end
```

## Magic properties

HTMXObjects auto-injects or recognises a small set of dunder-named properties.
Users do not need to declare them — the framework wires them up — but any route
body may reference them.

| Name            | Purpose                                                                     |
|-----------------|-----------------------------------------------------------------------------|
| `__self__`      | The struct instance. Every sibling reference is rewritten to `__self__.x`. |
| `__req__`       | The inbound `HTTP.Request`. `req` is a deprecated alias (warns).           |
| `__ws__`        | Inside `@ws` bodies: the WebSocket handle.                                 |
| `__parent__`    | In an `@include`d sub-struct: the parent instance.                         |
| `__prefix__`    | Current mount path (threaded by `route!` + `@include`).                    |
| `__appdata__`   | App-wide data. Falls through `__parent__` so nested structs see the same.  |
| `__page__`      | `content -> full_page(content)` — called by `_resolve_response`.           |
| `__error__`     | `err -> renderable` — called when a route throws (see [Errors](#error-handling)). |

Use `__self__/"path"` to build mount-prefix-aware URLs:

```julia
@get index = h.a(href = __self__/"about")("About")   # → "/<prefix>/about"
```

## Sub-routes with `@include`

Group related routes into a sub-struct and mount it at a path segment:

```julia
@htmx struct FeatureARoutes
    (; feature_a) = __appdata__
    (; items)     = feature_a

    @get index        = h.ul([h.li(x) for x in items]...)   # GET /feature_a
    @get show(id)     = h.p("showing $id")                   # GET /feature_a/show/{id}
end

@htmx struct AppRoutes
    __appdata__ = APPDATA

    @get index = h.h1("root")
    @include feature_a = FeatureARoutes()
end
```

### Two forms

- **External:** `@include name = ExternalStruct(; kwarg=value, ...)`. Mounts a
  struct defined elsewhere. The framework auto-injects
  `__parent__ = __self__` and `__prefix__ = parent_prefix * "/name"` so the
  child sees its ancestor and full URL prefix.
- **Block:** `@include name = begin ... end`. Declares an anonymous inline
  sub-struct. Equivalent to `name = struct _Include_name ... end`. Inline
  children inherit all parent properties — including `@param` declarations —
  via DynamicObjects' normal property-inheritance.

### Fallthrough

Because `__appdata__` is looked up through `__parent__`, nested structs see the
same APPDATA without having to pass it explicitly. Ditto for `@param`
properties on inline children.

### Destructure at the top

Pull parent / appdata slices into local names once at the top of the struct
body. Do **not** reach through `__appdata__.feature_a.items` in every route
body.

```julia
@htmx struct FeatureARoutes
    (; feature_a) = __appdata__
    (; items, item_count) = feature_a
    # routes use `items` / `item_count` directly
end
```

### Standalone external children — `@param` delegation

An external child struct does not inherit its parent's `@param` names into its
own `_param_names`. To both register params on the child *and* resolve them
from the parent, use the delegation form:

```julia
@htmx struct DoseResponseRoutes
    @param (; fit_key, top_chains) = __parent__   # register + resolve
    (; plot_height)                 = __parent__  # plain destructure, not a @param
    ...
end
```

Without this, `query_url(self, self)` would only serialize the child's own
params, and follow-up requests would silently fall back to defaults.

## `@param` and `query_url`

`@param` declares a request-derived, typed property — same extraction rules as
`@get`/`@post` kwargs (`queryparams` on GET/DELETE, `formdata` with query
fallback on POST/PUT/PATCH). Use it when multiple routes in the same struct (or
nested inline children) need the same params.

```julia
@htmx struct Analysis
    @param vessels::Vector{String} = ["Tablet-20"]
    @param n_bootstrap::Int        = 10
    @param fit_key::String                             # required — KeyError on miss
    @param note                    = "hi"              # untyped → raw String/Vector{String}

    # Block form:
    @param begin
        subjects::Vector{String} = String[]
        top_chains::Int          = 4
    end

    @get index = render(vessels, n_bootstrap)
    @get plot  = build_plot(vessels, n_bootstrap)
end
```

- `@param` properties are plain DO derived properties memoized per-request —
  **do not `@cached` them**; that would leak values across requests.
- Defaults are plain Julia expressions. Module-level variables and function
  calls work (unlike `@get` kwarg defaults, which are limited by
  `_eval_literal`).
- Required params throw `KeyError(:name)` on access when missing.

### `query_url(path, obj; overrides...)`

Build URLs that round-trip the current request's params:

```julia
@get plot = begin
    poll_url = query_url(__self__/"data", __self__)     # only params in __req__
    h.div(hx_get=poll_url, hx_trigger="every 1s")(...)
end
```

`query_url(path, obj)` iterates `_param_names(typeof(obj))` and emits only the
params that are **actually present in `obj.__req__`**. Explicit overrides
always win. The old one-arg `query_url(path; kwargs...)` still works for plain
URL building.

## App data (`__appdata__`)

Module-level mutable state is a thread-safety and hot-reload trap. Put it on an
`AppData` struct instead:

```julia
@dynamicstruct struct AppData
    items::Vector{String} = ["alpha", "beta"]
    counter::Ref{Int}     = Ref(0)
end

const APPDATA = AppData()

@htmx struct AppRoutes
    __appdata__ = APPDATA
    (; items, counter) = __appdata__

    @get index = h.p("count: $(counter[])")
end
```

`APPDATA` is the **only** `const` you need at module top level. `@dynamicstruct`
handles Revise-compatible mutation through property accessors. There is
intentionally no `appdata` kwarg on `route!` — the singleton lives with the
struct definition, keeping `route!`'s API state-free.

If initialisation needs to happen at runtime (file I/O, env reads), use
`const APPDATA = Ref{AppData}()` and assign in `__init__`.

For mutable shared state that route handlers read/write concurrently, use
`@dynamicstruct` with `cache_type=:parallel` (ThreadsafeDict-backed) or a
`Treebars.ThreadsafeDict` field. Never use a plain `Dict{K,V}()` — Oxygen
handles requests concurrently.

## Caching with `@cached` and `@persist`

```julia
@htmx struct AppRoutes
    @cached running = false

    toggle[__req__] = begin
        running = !running           # rewritten to __self__.running = !running
        @persist running             # flush to disk
        render_ui()
    end
end
```

`@cached` persists to `cache/<hash>/<index>.sjl`. All instances with the same
fixed fields share the cache, so each per-request `AppRoutes()` sees the
persisted value. `@persist name` writes the current value to disk.

## URL building — mount-prefix awareness

Every struct carries `__prefix__` — `route!` seeds the root and `@include`
appends `/<name>` at each level. Prefer `__self__/"path"` or `__parent__/"path"`
over hand-built strings so URLs survive mount changes (`route!(..; prefix="api")`)
and nesting changes.

```julia
h.a(href = __self__/"about")          # full path at this mount point
h.form(hx_post = __self__/"submit")   # POST back to this sub-struct
```

## Error handling

Every route handler is wrapped in try/catch. On exception, HTMXObjects:

1. Generates a short uid (hash of `time_ns()`).
2. Writes `ERROR_DIR[]/<uid>.log` with uid, ISO timestamp, method + target, and
   `showerror(io, err, bt)`.
3. Emits one `@error "HTMXObjects caught an error: <full path>"` — terse on
   purpose; the full stack is on disk.
4. Feeds the result of `__error__(err)` back through the same response
   pipeline — browsers see the error inside `__page__`, HTMX requests see the
   fragment, markdown requests see markdown.

`ERROR_DIR[]` is initialised from the `HTMXO_ERROR_DIR` env var (falls back to
`joinpath(tempdir(), "htmxo_errors")`).

### Customising

```julia
@htmx struct AppRoutes
    # Opt out — let exceptions propagate to Oxygen's 500 handler:
    # __error__ = rethrow

    # Custom rendering:
    __error__(err) = h.article(h.header("Oops"), h.p(sprint(showerror, err)))
end
```

`__error__` is looked up on the route's struct (or the innermost `@include`d
parent), so a top-level override covers everything while nested structs can
override for their own routes.

### Widget-level containment with `safely`

Route-level catching still lets one exception kill a whole composite route. For
dashboards that combine several independent panels, wrap each panel in
`safely`:

```julia
@get dashboard = h.div(
    safely(; obj=__self__) do
        render_ppc_plot(data)
    end,
    safely(; obj=__self__) do
        render_summary(data)    # runs independently; failure stays local
    end,
)
```

### Error-tagged HTML (`?errors` filter)

`e.<tag>(...)` is the error-tagged parallel to `h`. `?errors` walks the node
tree and keeps only `data-error` nodes and their ancestors — useful for
surfacing machine-readable error summaries from a composite page.

## Revise hot-reload

Confirmed empirically:

| Change                                             | Hot-reloaded?                      |
|---------------------------------------------------|------------------------------------|
| Plain function in the package                      | Yes                                |
| Plain function in the web module                   | Yes                                |
| `@htmx struct` body (literal or function call)     | Yes                                |
| New `@get`/`@post` added to a struct               | Yes (via `_reroute!`)              |
| `@testset` body in `web/src/test/runtests.jl`      | Yes                                |
| `@testset` via `../` path outside the pkg tree     | **No** — source-text cache mismatch |
| `@generated` function helper                       | **No** — world-age frozen          |
| `const` value                                      | **No** — Revise can't redefine consts |

### Gotcha: renaming the root `@htmx` struct

Revise does **not** re-run `__init__()`. If you rename the root struct (e.g.
`AppContext` → `AppRoutes`), `route!(AppRoutes())` never fires and every route
returns the framework's error article — with HTTP 200. Check `?plain` content,
not just status codes, when triaging "all routes broken".

**Fix without restarting:** temporarily add a bare top-level
`route!(AppRoutes())` expression in the module file. Revise evaluates new
top-level expressions, so routes register under the new root. Remove the line
once verified — future Revise reloads go through `_reroute!`, which finds the
type in `_registered_types` and re-registers correctly.

## Recording &amp; static replay

`route!(app; record_dir="site")` writes every response to disk mirroring the
URL path (`/post/42` → `site/post/42.html`). After recording, a plain static
server replays the session (`python -m http.server --directory site`).

Recorded nodes pass through `static_transform` first — non-GET `hx-*`
attributes and query-param `hx-get` links are stripped (static servers can't
vary responses by query string), and disabled elements get a dimmed style.

## HTML helpers

```julia
h.div(class="container")(              # positional children, keyword attributes
    h.h1("Title"),
    h.p(hx_get="/data", hx_target="#result")("Load"),
)
```

- Attribute names use underscores; they render as hyphenated HTML
  (`hx_get` → `hx-get`).
- `htmx(content; pico_version, htmx_version, hyperscript_version, extra_head, feedback)`
  builds a full HTML page. Pico CSS is opt-in (`pico_version="2"`); HTMX and
  Hyperscript are loaded from CDN by default.
- `@__str` embeds inline Hyperscript: `h.button(__"on click toggle .hidden on #menu")("Toggle")`.

### HTMX headers

Inspect the request with `is_htmx(req)`, `hx_target(req)`, `hx_trigger(req)`,
`hx_current_url(req)`, `hx_boosted(req)`, `hx_prompt(req)`.

Attach response headers with `hx_response`:

```julia
hx_response(content;
    trigger     = "itemSaved",    # HX-Trigger — fire a client event
    push_url    = "/new/path",    # HX-Push-Url
    retarget    = "#other",       # HX-Retarget
    reswap      = "outerHTML",    # HX-Reswap
    redirect    = "/login",       # HX-Redirect — full-page redirect
    refresh     = true,           # HX-Refresh
    location    = "/dashboard",   # HX-Location — client-side navigate
)
```

### Out-of-band swaps

`to_response` accepts `content => "id"` pairs — wraps content in a `<div>`
with `hx-swap-oob="true"` and the given id.

```julia
to_response([main_body, sidebar_html => "sidebar"])
```

## What belongs where

**On a `@dynamicstruct` (`XData`):**
- Collections (`items::Vector{...}`), caches, handles, config.
- Anything shared across requests.

**On a `@htmx struct` (`XRoutes`):**
- HTML fragments and page layouts — they benefit from sibling references.
- Routes marked with `@get`/`@post`/etc.
- `@param` declarations.
- Action handlers that mutate `@cached` state and return updated UI.

**Outside both:**
- Pure utilities that don't reference any property.
- Helper types (data models, `PersistentSet`).

The web module should contain **only** `APPDATA`, the struct definitions, and
`__init__`. No top-level standalone functions, no top-level `const`s besides
`APPDATA`, no custom Oxygen route handlers.

## Further reading

- [Web app pattern (KB)](https://github.com/nsiccha/Claude/blob/main/web-app-pattern.md)
  — directory layout, `web/Project.toml` sync, `start-web.sh`.
- [Testing pattern (KB)](https://github.com/nsiccha/Claude/blob/main/testing-pattern.md)
  — `web/src/test/` + symlink, `TestModules.@testset`, test UI.
- [Revise notes (KB)](https://github.com/nsiccha/Claude/blob/main/revise.md)
  — what Revise does and does not hot-reload.

## API reference

```@index
```

```@autodocs
Modules = [HTMXObjects]
```
