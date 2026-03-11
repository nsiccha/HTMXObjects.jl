# HTMXObjects.jl

Property-based web pages for Julia. Each property of a `@htmx struct` is a
cacheable, indexable computation — and optionally a live Oxygen route and/or a
recorded static file.

## Quick start

```julia
using HTMXObjects

@htmx struct MyApp
    @get index = htmx(h.main(h.h1("Hello!")))
end

route!(MyApp())
serve()
```

## Core concepts

### `@htmx struct`

`@htmx` is an alias for `@dynamicstruct` (from DynamicObjects.jl) that signals
the struct's intended use as a web app. Properties without a RHS are regular
struct fields; properties with a RHS are computed lazily and cached.

```julia
@htmx struct MyApp
    base_url = "http://localhost:8080"   # plain field

    title = "My App"                     # cached computed property

    @get index = htmx(h.main(h.h1(title)))   # also a GET route
    @get post[id] = htmx(h.main(h.p(id)))    # indexed route: GET /post/{id}
end
```

### `@get` marker

Properties marked `@get` inside `@htmx struct` are registered as Oxygen GET
routes by `route!`. Unmarked properties remain internal.

### `route!`

```julia
route!(app)                          # register routes, no recording
route!(app; record_dir="site")       # register routes + record every response
route!(app; prefix="api")            # mount under /api/...
```

Property-to-route mapping:

| Property           | Route              |
|--------------------|--------------------|
| `@get index`       | `GET /`            |
| `@get about`       | `GET /about`       |
| `@get post[id]`    | `GET /post/{id}`   |
| `@get item[a, b]`  | `GET /item/{a}/{b}`|

### HTML generation

HTML is built with `h.<tag>(children...; attrs...)`:

```julia
h.div(class="container")(
    h.h1("Title"),
    h.p(hx_get="/data", hx_target="#result")("Load"),
)
```

Attribute names use underscores; they render as hyphenated HTML attributes
(`hx_get` → `hx-get`, `hx_swap_oob` → `hx-swap-oob`).

The `htmx(content)` helper produces a full HTML page. HTMX and Hyperscript are
loaded from CDN by default; PicoCSS and any other extras are opt-in:

```julia
htmx(body_content;
    htmx_version        = "2.0.8",    # nothing → skip
    hyperscript_version = "0.9.14",   # nothing → skip
    pico_version        = nothing,    # e.g. "2" to include PicoCSS
    extra_head          = (),         # additional <head> nodes, e.g. h.style("...")
)
```

### HTMX partial updates

Return a fragment (not a full page) from an indexed route; the browser page
uses `hx-target` and `hx-swap` to insert it:

```julia
counter_ui(n) = h.div(id="counter")(
    h.p("Count: $n"),
    h.button(hx_get="/increment/$n", hx_target="#counter", hx_swap="outerHTML")("+"),
)

@htmx struct CounterApp
    @get index     = htmx(h.main(counter_ui(0)))
    @get increment[n] = counter_ui(parse(Int, n) + 1)  # fragment only
end
```

### Out-of-band swaps

`auto` supports HTMX OOB swaps via `Pair`:

```julia
# content => "element-id" wraps content in <div id="element-id" hx-swap-oob="true">
to_response([main_content, sidebar_html => "sidebar"])
```

### Hyperscript

Use `@__str` to embed inline Hyperscript in the `_` attribute:

```julia
h.button(__"on click toggle .hidden on #menu")("Toggle")
```

### Request inspection

Inside manually-registered Oxygen routes (or any handler receiving `req`):

```julia
is_htmx(req)        # true if request came from HTMX
hx_target(req)      # value of HX-Target header
hx_trigger(req)     # value of HX-Trigger header
hx_current_url(req) # value of HX-Current-URL header
hx_boosted(req)     # true if hx-boost triggered the request
hx_prompt(req)      # value of HX-Prompt header
```

### Response headers

```julia
hx_response(content;
    trigger     = "itemSaved",    # HX-Trigger — fire a client event
    push_url    = "/new/path",    # HX-Push-Url — push browser history
    replace_url = "/new/path",    # HX-Replace-Url — replace history entry
    redirect    = "/login",       # HX-Redirect — full-page redirect
    refresh     = true,           # HX-Refresh — reload the page
    retarget    = "#other",       # HX-Retarget — override swap target
    reswap      = "outerHTML",    # HX-Reswap — override swap strategy
    location    = "/dashboard",   # HX-Location — client-side navigate
)
```

### Recording for static replay

When `record_dir` is given to `route!`, every GET response is written to disk
mirroring the URL path:

```
/          → site/index.html
/about     → site/about.html
/post/42   → site/post/42.html
```

After recording a session, a plain static server is enough to replay it:

```sh
python -m http.server 8000 --directory site
```

HTMX fragment requests are recorded too, so partial updates are replayed
correctly — the static server returns the pre-recorded fragment and HTMX
handles the DOM swap client-side.

## Caching

Properties can be cached to disk with `@cached` (from DynamicObjects):

```julia
@htmx struct MyApp
    @get @cached expensive[id] = slow_computation(id)
end
```

Cached properties are serialised to `cache/<hash>/<index>.sjl` and skipped on
subsequent calls. See DynamicObjects.jl for full caching documentation.

## API reference

```@index
```

```@autodocs
Modules = [HTMXObjects]
```
