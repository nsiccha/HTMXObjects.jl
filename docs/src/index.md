# HTMXObjects.jl

Property-based web pages for Julia. Each property of a `@htmx struct` is a
cacheable, indexable computation — and optionally a live Oxygen route and/or a
recorded static file.

## Quick start

Scaffold a new app:

```julia
using HTMXObjects
create_app("MyApp.jl")
```

Then run it:

```bash
cd MyApp.jl && julia -i --project=app app/main.jl
```

Or create an app manually:

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

`@htmx` wraps `@dynamicstruct` (from DynamicObjects.jl) and appends a
`_reroute!` call so that Revise-triggered re-evaluation automatically
re-registers routes — no server restart needed. Properties without a RHS are regular
struct fields; properties with a RHS are computed lazily and cached.

```julia
@htmx struct MyApp
    title = "My App"                         # derived property (cached)

    nav = h.nav(h.strong(title))             # references `title` by name

    @get index = htmx(h.main(nav, h.h1(title)))       # also a GET route
    @get post[id] = htmx(h.main(h.p(id)))             # indexed route: GET /post/{id}
    @get page[id::Int] = htmx(h.main(h.p("Page $id")))  # typed: id auto-parsed to Int
end
```

### Route markers

Properties marked with `@get`, `@post`, `@put`, `@patch`, or `@delete` inside
`@htmx struct` are registered as Oxygen routes by `route!`. Unmarked properties
remain internal.

### `route!`

```julia
route!(app)                          # register routes, no recording
route!(app; record_dir="site")       # register routes + record every response
route!(app; prefix="api")            # mount under /api/...
```

Property-to-route mapping:

| Property                  | Route(s)                               |
|---------------------------|----------------------------------------|
| `@get index`              | `GET /`                                |
| `@get about`              | `GET /about`                           |
| `@get post[id]`           | `GET /post/{id}` (id is a String)      |
| `@get post[id::Int]`      | `GET /post/{id}` (id auto-parsed to Int) |
| `@get item[a, b]`         | `GET /item/{a}/{b}`                    |
| `@get filter[a, b=1]`     | `GET /filter/{a}/{b}` + `GET /filter/{a}` (b defaults to 1) |
| `@get search(; q="", page::Int=1)` | `GET /search` (q, page from query string) |
| `@post submit(; name="")`  | `POST /submit` (name from form data)   |
| `@get items(category; sort="name")` | `GET /items/{category}` (sort from query string) |
| `@delete remove[id]`      | `DELETE /remove/{id}`                  |

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

### Derived properties and cross-references

Properties defined with `=` are lazily computed and cached. Crucially, any
reference to another property name in the RHS is **automatically rewritten** to
`__self__.<name>` — so properties can reference each other by bare name:

```julia
@htmx struct BlogApp
    posts = [(id="1", title="Hello", body="...")]

    # `posts` here automatically becomes `__self__.posts`
    post_list = h.ul([h.li(p.title) for p in posts])

    @get index = htmx(h.main(post_list))
end
```

This means data, reusable UI fragments, and routes can all live inside the
struct — no global `const`s or standalone functions needed.

### Reusable fragments with indexed properties

Define parameterised helpers as indexed properties using function-call syntax.
These act like methods that can reference other properties:

```julia
@htmx struct CounterApp
    counter_ui(n) = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(hx_get="/increment/$n", hx_target="#counter", hx_swap="outerHTML")("+"),
    )

    @get index            = htmx(h.main(counter_ui(0)))
    @get increment[n::Int] = counter_ui(n + 1)  # n auto-parsed from URL string
end
```

Both `prop(args)` and `prop[args]` define indexed properties, but the calling
convention differs:

| Syntax              | Caching behaviour                         |
|---------------------|-------------------------------------------|
| `app.prop[args]`    | Cached per index — same args return same result |
| `app.prop(args)`    | Fresh computation each time               |

Use `()` for UI fragments (which should render fresh) and `[]` for routes or
expensive lookups.

### Query params & form data via kwargs

Use **call syntax** `()` with keyword arguments to automatically extract values
from query parameters (GET/DELETE) or form data (POST/PUT/PATCH):

```julia
@htmx struct SearchApp
    # kwargs-only: GET /search?q=foo&page=2
    @get search(; q="", page::Int=1) = h.p("q=$q page=$page")

    # mixed positional + kwargs: GET /filter/{category}?sort=name
    @get filter(category; sort="name") = h.p("$category sorted by $sort")

    # POST form data: name and email extracted from form fields
    @post submit(; name="", email="") = h.p("Hello $name")
end
```

**Important**: Use `()` call syntax, NOT `[]` bracket syntax. In Julia,
semicolons inside `[]` mean array concatenation — `prop[; q=""]` does **not**
create kwargs. Only `prop(; q="")` works.

Type annotations apply: `page::Int=1` parses the query string value to `Int`.
Missing kwargs use the default value from the signature.

### HTMX partial updates

Return a fragment (not a full page) from an indexed route; the browser page
uses `hx-target` and `hx-swap` to insert it. See the counter example above —
`increment[n]` returns only the updated `#counter` div, which HTMX swaps in
without a full page reload.

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

When `record_dir` is given to `route!`, every response is written to disk
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

#### Automatic disabling of non-functional elements

Recorded responses are automatically transformed by `static_transform` to
disable elements that won't work on a static server:

- **Non-GET verbs** (`hx-post`, `hx-put`, `hx-patch`, `hx-delete`) are stripped
- **Query-param routes** (`hx-get` pointing to kwargs routes like `@get search(; q="")`)
  are stripped, since the static server can't vary its response by query string
- **Plain GET path routes** (`hx-get="/post/1"`) are preserved — they work fine
- Affected elements receive `data-static-disabled` and `disabled` attributes
- A `<style>` block is injected to dim disabled elements (opacity 0.45, no pointer events)

The transform operates on the Node tree before serialization — no regex on HTML.

You can also call `static_transform(node)` manually to preview the effect:

```julia
app = MyApp()
original = app.index
static_version = static_transform(original)
```

## Caching

Properties can be cached to disk with `@cached` (from DynamicObjects):

```julia
@htmx struct MyApp
    @get @cached expensive[id] = slow_computation(id)
end
```

Cached properties are serialised to `cache/<hash>/<index>.sjl` and skipped on
subsequent calls. See DynamicObjects.jl for full caching documentation.

## Mutable state with `@cached` and `@persist`

For apps that need mutable state (e.g. a timer, a to-do list), combine
`@cached` properties with assignment and `@persist`:

```julia
@htmx struct TimerApp
    @cached running = false
    @cached current_log = nothing

    toggle[req] = begin
        if running
            current_log = nothing
            running = false
        else
            current_log = (1, time())
            running = true
        end
        @persist running
        @persist current_log
        timer_content
    end

    timer_content = h.div(id="timer")(
        h.p(running ? "Running..." : "Stopped"),
        h.button(hx_post="/toggle", hx_target="#timer", hx_swap="outerHTML")(
            running ? "Stop" : "Start"
        ),
    )
end
```

**How it works:**

- Writing `running = false` inside a property RHS is rewritten by
  `walk_rhs` to `__self__.running = false`, which calls `setproperty!`
  and updates the in-memory cache.
- `@persist running` serialises the current value to disk, so it survives
  server restarts.
- `@cached` properties share their disk cache across all instances with
  the same fixed fields, so creating a fresh `TimerApp()` in each request
  handler still sees the persisted state.

## Fresh instance per request

`route!` creates a fresh `T(; __req__=request)` for every incoming request.
Non-cached derived properties (like HTML fragments) recompute each time,
while `@cached` properties are loaded from the shared disk cache.
This avoids stale HTML — each request sees up-to-date state.

## All HTTP verbs via route markers

`route!` registers properties marked with any of `@get`, `@post`, `@put`,
`@patch`, or `@delete`:

```julia
@htmx struct RecipeApp
    @get index = htmx(h.main(recipe_grid))
    @post add_recipe = begin
        url = formdata(__req__)["url"]
        # ... handle add ...
        recipe_grid
    end
    @delete remove_recipe = begin
        url = queryparam(__req__, "url")
        # ... handle remove ...
        to_response("")
    end
end
```

## What belongs inside vs outside the struct

**Inside (as derived properties):**

- HTML fragments and page layouts — they benefit from cross-referencing
  other properties by name
- Data collections (`items`, `posts`) — replaces global `const`s
- State (`@cached running`, `@cached log`) — persisted across requests
- Action handlers (`toggle[req]`, `add_item[req]`) — they modify state
  and return updated UI

**Outside (as standalone functions or types):**

- Pure utilities that don't reference any property (`fmt_hms(seconds)`,
  `flat_texts(node)`)
- Custom types (`PersistentSet`, data models)
- Pure standalone logic that doesn't fit as a property

## Downstream dependency note

When using `@oxidize` in a package that depends on HTMXObjects, Oxygen
must be listed as a **direct** dependency in that package's Project.toml —
not just as a transitive dependency through HTMXObjects. This is because
`@oxidize` is a macro that runs at precompile time and needs to resolve
in the downstream module's namespace.

## API reference

```@index
```

```@autodocs
Modules = [HTMXObjects]
```
