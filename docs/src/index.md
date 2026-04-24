# HTMXObjects.jl

Property-based web apps for Julia. Built on
[DynamicObjects.jl](https://github.com/nsiccha/DynamicObjects.jl),
[Oxygen.jl](https://github.com/OxygenFramework/Oxygen.jl), and
[HTMX.jl](https://github.com/nsiccha/HTMX.jl).

## One idea

Every HTMXObjects app is split along a single axis:

- **Data** — persistent, lives for the server's lifetime. Collections,
  filesystem handles, expensive computations, mutable caches. Lives on
  `@dynamicstruct` types. This is the *backend*.
- **Requests** — ephemeral, regenerated on every HTTP request. URL handlers,
  HTML fragments, request-derived parameters, page layouts. Lives on `@htmx`
  types. This is the *UI*.

A fresh `@htmx` instance is built for every inbound request, injected with the
inbound `HTTP.Request`, and discarded after the response is sent. It reaches
through to the single long-lived `@dynamicstruct` tree for anything that needs
to survive between requests. Nothing ephemeral leaks into data; nothing
persistent leaks into requests.

Keeping this split clean is the whole discipline:

| `@dynamicstruct` (data, backend)              | `@htmx` (requests, UI)                           |
|-----------------------------------------------|--------------------------------------------------|
| Built once, at module init                    | Built fresh per request                          |
| `Vector`s, `DataFrame`s, `@cached` results    | HTML fragments and page layouts                  |
| File / DB / network handles                   | `@get` / `@post` / … route properties            |
| Thread-safe mutation (`cache_type=:parallel`) | `@param` request-derived values                  |
| No HTTP knowledge                             | Has `__req__`, `__prefix__`, `__appdata__`       |

Everything else in this document — `@include`, `@param`, `query_url`, the
response pipeline, error handling — exists to make that split ergonomic.

## Quick start

Scaffold:

```julia
using HTMXObjects
create_app("MyApp.jl")    # writes Project.toml, src/MyApp.jl, app/
```

Run:

```bash
cd MyApp.jl && julia -i --project=app app/main.jl
```

A minimal app written by hand:

```julia
module MyApp

using HTMXObjects

# 1. Data — persistent, lives for the server's lifetime.
@dynamicstruct struct AppData
    items::Vector{String} = ["alpha", "beta", "gamma"]
end

const APPDATA = AppData()

# 2. Requests — fresh instance per HTTP request.
@htmx struct AppRoutes
    __appdata__ = APPDATA
    (; items) = __appdata__

    __page__(content) = htmx(h.main(; class="container")(content); pico_version="2")

    @get index = h.div(
        h.h1("Items"),
        h.ul([h.li(x) for x in items]...),
    )
end

function __init__()
    route!(AppRoutes())
end

end
```

That is the whole shape. A `@dynamicstruct` holds the list. A `@htmx` struct
declares `/` → `GET` rendering HTML. Revise reloads on save; the server never
needs to restart.

## Data layer — `@dynamicstruct`

Persistent state. Built once when the module loads; lives until the process
exits. Use it for anything that is expensive to build, mutable, or needs to
outlive a single request.

```julia
@dynamicstruct struct AppData
    items::Vector{String}    = ["alpha", "beta"]
    counter::Ref{Int}        = Ref(0)
    dataset                  = load_big_dataframe()   # run once at construction
    compute_result(x)        = expensive(x)           # memoised per argument
end

const APPDATA = AppData()
```

### Conventions

- **One `const APPDATA = AppData()`** at module top level. It is the only
  module-level `const` the app needs.
- **Feature-scoped sub-structs.** For anything non-trivial, give each feature
  its own `XData` `@dynamicstruct` and compose them as properties of
  `AppData`. See `BayesianRegressionModels` (`Formula`, `Dataset`,
  `ExampleEntry`, `AppData`) for an example.
- **No standalone top-level functions** in the web module. If a function uses
  app state, make it a derived property on the owning `@dynamicstruct`. If it
  is genuinely stateless, inline it or put it in the underlying package.
- **No module-level `Dict{K,V}()`.** Oxygen serves requests concurrently. Use
  a `@dynamicstruct` with `cache_type=:parallel` or a `ThreadsafeDict` field.
- **No module-level mutable state.** Mutate through property accessors on
  `AppData` so Revise can hot-reload the definition without losing data.

See the [DynamicObjects docs](https://github.com/nsiccha/DynamicObjects.jl)
for the full property grammar (`@cached`, `@persist`, indexed properties,
inline `@struct` children, docstring interpolation).

## Request layer — `@htmx`

Fresh instance per request. The framework wires in `__req__`, `__prefix__`,
and falls `__appdata__` through from the parent. Everything else is user
code. A `@htmx` struct is a `@dynamicstruct` plus:

- Route markers (`@get`, `@post`, `@put`, `@patch`, `@delete`, `@ws`) turn
  properties into HTTP endpoints.
- `@include` composes sub-structs under a path segment.
- `@param` declares request-derived typed properties shared across routes.
- A `_reroute!` hook fires on Revise re-evaluation so routes re-register
  without a server restart.

```julia
@htmx struct AppRoutes
    __appdata__ = APPDATA
    (; items) = __appdata__

    # Page layout — called by the response pipeline on direct browser nav.
    __page__(content) = htmx(h.main(; class="container")(content); pico_version="2")

    # Sibling references are rewritten to `__self__.x` by the macro, so a
    # derived property can reference other properties by bare name.
    title = "My items"
    header = h.header(h.strong(title))

    @get index    = h.main(header, h.ul([h.li(x) for x in items]...))
    @get show(id) = h.article(h.header("Item "), h.code(id))
end
```

A property with a RHS is derived and lazily memoised on the instance (i.e.
for the duration of one request). A property without a RHS (`items::Vector{String}`)
is a fixed field — rarely needed on a `@htmx` struct.

Route properties can take positional path params (`show(id)`) or kwargs
(`search(; q="")` — auto-extracted from query or form). Type annotations
trigger `parse(T, ...)` automatically.

## Wiring data to requests — `__appdata__`

`__appdata__` is the bridge. The root `@htmx` struct sets it; every nested
`@include`d struct inherits it through the `__parent__` chain. Destructure
what you need at the top of each routes struct and refer to local names
everywhere else.

```julia
@dynamicstruct struct AppData
    items = ["alpha", "beta"]
    counter = Ref(0)
    dataset = load_big_dataframe()
end
const APPDATA = AppData()

@htmx struct AppRoutes
    __appdata__ = APPDATA
    (; items, counter, dataset) = __appdata__   # destructure once
    @get index = h.p("count: $(counter[])")
    # use `items` / `dataset` directly — never `__appdata__.items`
end
```

If initialisation needs runtime values (env reads, file I/O), use
`const APPDATA = Ref{AppData}()` and assign it in `__init__`.

## Composition — `@include`

Group related routes into a sub-`@htmx` struct, mount it under a path
segment.

**External form** — reuse a named type:

```julia
@htmx struct PipelineRoutes
    (; dataset) = __appdata__           # falls through via __parent__
    @get index   = h.p("rows: $(nrow(dataset))")
    @post submit = ...
end

@htmx struct AppRoutes
    __appdata__ = APPDATA
    @include pipeline = PipelineRoutes()   # mounts PipelineRoutes at /pipeline
end
```

**Inline form** — keep a tightly scoped feature in one place:

```julia
@htmx struct AppContext
    __appdata__ = APPDATA
    (; examples_dir) = __appdata__

    @include examples = begin
        @struct example_store = begin     # inline DO sub-store
            entries() = [ExampleEntry(f) for f in readdir(examples_dir; join=true)]
            find(label) = findfirstelement(e -> e.label == label, entries())
        end

        @get index = h.ul([h.li(e.label) for e in example_store.entries()]...)
    end
end
```

Both forms thread `__req__`, `__appdata__`, and `__prefix__` automatically:

- `__parent__ = __self__` — children see the enclosing struct.
- `__prefix__ = parent.__prefix__ * "/<name>"` — each `@include` appends one
  segment.
- `__appdata__` falls through the `__parent__` chain via `getproperty`.

### Destructure once at the top, reach up via `__parent__`

The root destructures from `__appdata__`. Deeper children reach up through
`__parent__` to the slices their parent already destructured. Never re-dig
through `__appdata__.feature.items` in every route body.

```julia
@htmx struct AnalysisRoutes
    (; dataset, fit_resolver) = __appdata__
    (; chain_analysis, posteriors_data) = dataset
    @include chains     = ChainsRoutes()        # sees __parent__ = this
    @include posteriors = PosteriorsRoutes()
end

@htmx struct ChainsRoutes
    (; chain_analysis, fit_resolver) = __parent__    # up to AnalysisRoutes
    @param (; fit_key) = __parent__                  # see @param delegation
end
```

## Routes

A verb marker turns a property into a route. The property name becomes the
URL path (minus the `:index` special case, which maps to the struct's mount
point).

```julia
@htmx struct AppRoutes
    @get  index         = list_view()                 # GET /
    @get  item(id)      = render_item(id)             # GET /item/{id}  (id::String)
    @get  page(id::Int) = render_page(id)             # GET /page/{id}  (auto-parsed to Int)
    @get  search(; q="", n::Int=1) = ...              # GET /search?q=&n=
    @post submit(; name="") = persist!(name)          # POST /submit (form-encoded)
    @get  range(a, b=1) = ...                         # GET /range/{a}/{b} AND /range/{a}
    @delete remove(id) = drop!(id)                    # DELETE /remove/{id}
    @ws     feed = (__ws__) -> ...                    # WebSocket at /feed
end
```

### Rules

- **Use `()` syntax for parameters.** `@get foo[bar](; q="")` hits a DO
  assertion — Julia parses `;` inside `[]` as matrix concatenation.
- **Untyped params are `String`.** Annotate with `::Int`, `::Float64`,
  `::Bool`, `::Symbol`, or `::Vector{T}` for auto-parsing. Extend
  `_convert_param(val::AbstractString, ::Type{T})` to support new types.
- **Trailing positional defaults register shortened routes automatically.**
  `@get range(a, b=1)` handles both `/range/{a}/{b}` and `/range/{a}`. Do not
  write two `@get` properties.
- **Kwargs sourcing** — `queryparams(req)` on GET/DELETE; `formdata(req)`
  with `queryparams` fallback on POST/PUT/PATCH.
- **Multi-value query params** (`?tag=a&tag=b`) — untyped kwargs receive
  `Vector{String}`; `Vector{T}`-typed kwargs coerce each element; scalar-
  typed kwargs receive the first value.
- **Multi-verb routes on one name are allowed** — `@get user(id)` +
  `@put user(id)` + `@delete user(id)` all register at `/user/{id}`.
  Internally they are renamed to `user_GET`, `user_PUT`, … and the bare
  name is no longer a DO property. If only a single verb targets `name`,
  the bare name stays accessible as `app.name`.

### Register with `route!`

```julia
route!(app)                          # register routes
route!(app; record_dir="site")       # + record every response to disk
route!(app; prefix="api")            # mount everything under /api
```

There is no `appdata` kwarg — shared state is threaded through
`__appdata__`. `route!` stores the type in `_registered_types`; the
`_reroute!` hook emitted by `@htmx` re-registers automatically when Revise
reloads the struct.

## Request-derived state — `@param`

`@param name::T = default` is a derived property that pulls itself from the
current request (same extraction rules as `@get`/`@post` kwargs — shared
`_lookup_param` primitive). It is memoised per instance (i.e. per request).
Use it when several routes in the same struct (or inline children) need the
same params.

```julia
@htmx struct Analysis
    @param vessels::Vector{String} = ["Tablet-20"]
    @param fit_key::String                           # required — KeyError on miss
    @param note                    = "hi"            # untyped → raw String/Vector{String}

    @param begin
        subjects::Vector{String} = String[]
        top_chains::Int          = 4
    end

    @get index = render(vessels, subjects, top_chains)
    @get plot  = build_plot(vessels, fit_key)
end
```

### Rules

- **Never wrap with `@cached`.** `@param` is per-request state;
  `@cached` would persist to disk and leak across requests.
- **Required params throw `KeyError(:name)` on access.**
- **Defaults are full Julia expressions.** Module-level variables and
  function calls work (unlike `@get` kwarg defaults, which are limited to
  literals).
- **Inline `@include` children inherit parent `@param`s for free.** External
  children do not — use the delegation form:

```julia
@htmx struct ChildRoutes
    @param (; fit_key, top_chains) = __parent__   # register + resolve
    (; plot_height)                = __parent__   # plain destructure, not a @param
end
```

### `query_url(path, obj)` — round-tripping params

```julia
@get plot = begin
    poll_url = query_url(__self__ / "data", __self__)
    h.div(hx_get=poll_url, hx_trigger="every 1s")(...)
end
```

`query_url(path, obj)` iterates `_param_names(typeof(obj))` and emits only
the params that were **actually present** in `obj.__req__`. Explicit kwarg
overrides always win. Defaults stay implicit — the URL only carries what the
user set.

`query_url(path; kwargs...)` (single argument) just builds a plain URL with
escaped query parameters.

## Response pipeline

Every route's return value flows through `_resolve_response` unless it is
already an `HTTP.Response`. Precedence (first match wins):

1. `HTTP.Response` → returned as-is.
2. `?error` on the query string → `filter_errors(val)` keeps only `e.*`
   nodes and their ancestors.
3. Markdown requested (`?markdown`, `?plain`, or `Accept: text/markdown`/
   `text/plain`) → `to_markdown_string(val)`.
4. HTMX request (`HX-Request: true`) → fragment returned as-is.
5. Otherwise → wrap in `__page__(content)` if any ancestor defines one.

**Never branch on request mode inside a route body.** Return bare content;
the framework handles the rest:

```julia
# BAD — double-wraps browser responses.
@get index = __page__(h.div(...))

# BAD — the pipeline already does this.
@get item(id) = is_htmx(__req__) ? fragment : __page__(fragment)
@get item(id) = if wants_markdown(__req__) markdown else html end

# GOOD
@get index = h.div(...)
```

### `__page__` — the full-page wrapper

Define it on the root `@htmx` struct (or any ancestor). It gets called with
whatever content a browser route returned, for full-page renders:

```julia
__page__(content) = htmx(
    h.div(; class="layout")(
        nav_sidebar(["Pipeline" => "/pipeline", "Examples" => "/examples"]),
        h.main(; class="container")(h.div(; id="content")(content)),
    );
    pico_version="2",
    extra_head=(h.title("My app"), h.style(my_css)),
)
```

### Same route serves humans and agents

The markdown branch means the same route handles both browsers (HTML) and
agents (markdown via `curl -H "Accept: text/markdown"` or `?plain`). For
mode-specific bits inside shared content, wrap with `html_only(...)` /
`markdown_only(...)`:

```julia
h.div(
    h.h1("Dashboard"),                    # both
    html_only(h.nav(buttons...)),         # HTML only
    markdown_only("*hint: use ?plain*"),  # markdown only
    h.table(data...),                     # both (auto-converts)
)
```

## Magic properties

Framework-recognised names. Users don't declare them — the macro / request
handler injects them — but route bodies may reference them.

| Name            | Set by                              | Purpose                                               |
|-----------------|--------------------------------------|-------------------------------------------------------|
| `__self__`      | `@dynamicstruct`                     | The current struct instance.                          |
| `__req__`       | `route!` handler (per request)       | The inbound `HTTP.Request`.                           |
| `__ws__`        | `@ws` body wrapper                   | The WebSocket handle inside `@ws` bodies.             |
| `__parent__`    | `@include` desugar                   | Parent struct instance in a sub-struct.               |
| `__prefix__`    | `route!` + `@include`                | Current mount path.                                   |
| `__appdata__`   | User (`= APPDATA`) + `@include`      | App data; falls through the `__parent__` chain.       |
| `__page__`      | User                                 | `content -> full_page(content)`. Called by pipeline.  |
| `__error__`     | User (optional)                      | `err -> renderable`. Called on caught exceptions.     |

## URL building — `__self__ / "path"`

Every `@htmx` struct carries `__prefix__` — `route!` seeds the root,
`@include` appends `/<name>` at each level. Build URLs through
`__self__/"..."` or `__parent__/"..."` so mount changes
(`route!(..; prefix="api")`) and nesting changes don't break links:

```julia
h.a(href    = __self__/"about")           # full path at this mount point
h.form(hx_post = __self__/"submit")        # POST back to this sub-struct
```

`@query_url prop(args; kw=val)` follows `@get` conventions: positional args
become path segments, kwargs become query params. Useful for polling:

```julia
h.div(hx_get=@query_url(stage(:bench; force=true)), hx_trigger="every 1s")(...)
```

## Caching — `@cached` and `@persist`

`@cached` persists results to disk under `cache/<hash>/<index>.sjl`. The key
includes the struct's fixed fields, so every per-request `AppRoutes()` sees
the same persisted value.

```julia
@htmx struct AppRoutes
    @cached running = false

    @post toggle = begin
        running = !running               # rewritten to __self__.running = !running
        @persist running                 # flush to disk
        render_ui()
    end
end
```

Most `@cached` usage belongs on the *data* side (`AppData`). On `@htmx`
structs, prefer it for genuinely app-wide toggles (running/stopped,
last-submitted formula, etc.), never for per-request state — that is what
`@param` is for.

## Async work and polling — IPs + `polling_fetchindex`

Long-running computations (sampling, compilation, parameter fits) must not
block the HTTP request handler. HTMXObjects apps handle this by driving
**IndexableProperties (IPs)** on the data side through `polling_fetchindex`
on the routes side. Three facts anchor the pattern — read carefully, because
conflating them is the single most common async bug:

1. **Every function-form DO property is an IP.** Any LHS with parens —
   `name() = expr`, `name(x) = expr`, `name(x; kw=1) = expr` — produces an
   IP. The parens are what matter; arguments are not required. A zero-arg
   function form `name() = expr` **is still an IP**. IPs are backed by a
   `ThreadsafeDict` (under `cache_type=:parallel`, the usual setting for
   `AppData`), spawn and deduplicate `Task`s per key, and are pollable.
2. **Bare-property form (`name = expr`) is NOT an IP.** It is a
   lazy-memoised derived value on the instance. Not pollable. If you need
   to poll something, lift it to function form — even if it takes no
   arguments.
3. **`@cached` ONLY adds disk serialisation.** It does **not** create IPs
   and IPs do **not** require it. A function-form property is already an
   IP and already pollable without `@cached`. Use `@cached` when (and only
   when) you want the result to survive a server restart.

### The canonical pattern

```julia
# Data side: function-form property on AppData is the IP.
@dynamicstruct struct AppData
    # ... fields ...

    # Function form → IP. No @cached, no wrapping macro. This alone makes
    # it a ThreadsafeDict-backed, task-spawning, pollable computation.
    compute_steps(text, namespace, name::Symbol) = begin
        ...                                            # slow work
        result                                          # whatever the UI renders
    end
end

const APPDATA = AppData(; cache_type=:parallel)

# Routes side: polling_fetchindex drives the IP from an HTMX route.
@htmx struct PipelineRoutes
    (; compute_steps) = __appdata__
    @param formula::String = ""
    @param label::String   = ""

    @get stage(name::Symbol; force::Bool=false) = polling_fetchindex(
        compute_steps, formula, namespace_from(label), name;
        poll_url = query_url(__self__/"stage/$name"; formula, label),
        label    = "Pipeline - $name",
        force,
    ) do result
        # This block runs only once the IP resolves.
        render(result)
    end
end
```

What `polling_fetchindex(ip, args...; poll_url, label, force=false) do result ... end`
actually does:

- **First call**: kicks off the `Task` for `ip[args...]` (via
  `ThreadsafeDict.get!` — deduplicating concurrent requests for the same
  args), and returns a progress fragment with
  `hx-get=poll_url` + `hx-trigger="every Ns"`. The HTMX client polls.
- **Subsequent polls** hit `poll_url` and re-enter the handler:
  - Still running → same progress fragment.
  - Failed → error article.
  - Resolved → the `do result` block's rendering.
- **`force=true`** invalidates the cached entry for those args and re-runs
  the task.

The route itself is just a plain `@get` returning a fragment. No branching
on request mode; the response pipeline handles the rest.

### Prepopulating the progress tree — `@progress` and `prepare_progress!`

`polling_fetchindex` gives the user a live progress view while the IP runs.
By default they see a single node that fills in as the IP's body executes.
For multi-stage pipelines, you almost always want **all phases visible as
pending up front** so the user can see the whole shape before anything
finishes. Two variants, pick by how the phase list is known:

**Static list — `@progress` blocks.** When the phases are literal in the
source, use Treebars' `@progress` macro. Every `@progress "label"` marker
inside a `@progress begin … end` block is pre-enumerated as a pending
child before the block starts, then starts/finishes in order:

```julia
using Treebars: @progress

compute_all = (text) -> begin
    @progress "Pipeline" begin
        @progress "Parse";       raw  = Meta.parse(text)
        @progress "Transform";   tx   = transform(raw)
        @progress "Compile";     lib  = compile(tx)
        @progress "Fit";         draws = fit(lib)
        (; raw, tx, lib, draws)
    end
end
```

All four labels appear immediately as pending siblings under "Pipeline";
each becomes active/finished as the block advances.

**Data-driven list — `prepare_progress!` + `with_prepared_progress`.** When
the phase set depends on runtime values (the user picked a stage from a
DAG, or the chain length varies with inputs), build the pending nodes by
hand and sandwich each phase:

```julia
using Treebars: prepare_progress!, with_prepared_progress

compute_steps(text, namespace, name::Symbol) = begin      # IP on AppData
    r      = run(text, namespace)
    chain  = step_chain[name]                             # NamedTuple: step_key => spec
    # Pre-create one pending ProgressNode per step, attached to this IP's
    # own __status__. All of them show up as dim "pending" siblings
    # immediately; the user sees the full pipeline shape before anything
    # starts.
    phases = [prepare_progress!(__status__; description=string(k))
              for k in keys(chain)]
    vals = map(pairs(chain), phases) do (step_name, spec), phase
        # Start this phase, run the body, finalize/fail on exit.
        with_prepared_progress(phase) do progress
            # progress is the live ProgressNode for this phase.
            # Work done here attaches under it (see next section).
            resolve(r, spec)
        end
    end
    merge((; data=r.df), NamedTuple{keys(chain)}(Tuple(vals)))
end
```

This is what BRM's `compute_steps` IP does. `with_prepared_phases(f,
parent, descriptions)` is a bulk helper if you'd rather skip the
`prepare_progress!` / `with_prepared_progress` boilerplate.

### Nesting IP progress — `fetchindex!(status, ip, args...)`

Inside a phase body you will often access **another IP** whose own
computation is itself long-running and reports progress (an MCMC sampler,
a Pathfinder init, a remote fetch). Calling `other_ip[args...]` would
work — the inner IP kicks off its own Task and its progress attaches to
nothing visible. What you want is for the inner IP's progress to **nest
under the current phase** so the user sees one tree instead of orphaned
siblings.

`fetchindex!` is the primitive for that (exported from DynamicObjects;
the Treebars-attaching method lives in `DynamicObjects/ext/TreebarsExt.jl`
and activates when Treebars is `using`'d):

```julia
# Two methods:
fetchindex!(::Nothing, ip, indices...)              # == ip[indices...] — no progress
fetchindex!(status::ProgressNode, ip, indices...)   # attach ip's substatus under `status`
```

The non-`nothing` form calls `Treebars.add_child!(status, getstatus(ip[indices...]))`
before returning, so the inner IP's progress tree becomes a child of
`status`. Used inside `with_prepared_progress`:

```julia
with_prepared_progress(phase) do progress
    if step_name === :stan_fit_pathfinder
        # Pathfinder is a function-form property (IP). Fetching it under
        # `progress` nests the sampler's own progress subtree under this
        # phase node.
        fetchindex!(progress, r.stan.pathfinder, r.stan.fit_instance, r.stan.init)
        resolve(r, spec)                   # reads the cached value via @memo
    else
        resolve(r, spec)
    end
end
```

Known users of the non-`nothing` form:

- BRM's `compute_steps` — warms the `pathfinder` and `posterior_warmup`
  IPs under the matching phase's progress.
- bruno's `_rpkpd` (`web-pkpd/src/analysis/sim_state.jl`) — forwards the
  caller's status into `pkpd`'s IP fetch so the sampling progress nests
  correctly when called from a route that already opened a phase.

Pattern shorthand inside an IP body:

- Always forward the current phase's `progress` into inner IP fetches —
  plain `ip[args]` orphans the subtree.
- Use `fetchindex!(progress, ip, args...)` to warm and attach; then read
  the cached value back via plain access or `@memo ip(args)` / `ip[args]`
  on later lines if you need the value.

### Translating the rules into action

- **Make a property pollable** → lift it to function form
  (`name(args...) = expr` or `name() = expr`). Do **not** add `@cached` for
  pollability.
- **Make a property survive a restart** → add `@cached` (disk persistence),
  independently of whether it's an IP.
- **Pre-populate the progress tree** → `@progress "label"` markers for
  statically-known phases, `prepare_progress!` + `with_prepared_progress`
  (or `with_prepared_phases`) for data-driven phase sets.
- **Nest an inner IP's progress under the current phase** →
  `fetchindex!(status, ip, args...)`. Plain `ip[args]` skips progress
  attachment and the sub-tree floats.
- **Call an IP from inside an HTTP request handler** → never block.
  Use `polling_fetchindex(ip, args...; poll_url, label) do result ... end`.
- **Call an IP from inside another DO property body** → blocking is fine
  (the outer body is itself in a spawned Task). Use `fetchindex!(progress,
  ip, args...)` so progress nests; use bare `fetchindex(ip, args...)` or
  `ip[args...]` if you don't need progress.
- **Access form matters on IPs too.** `o.prop(args)` is fresh-each-call
  (re-runs the body on every access); `o.prop[args]` is ThreadsafeDict-
  cached per key (what `fetchindex` / `polling_fetchindex` dispatch
  through). `@memo o.prop(args)` rewrites to `o.prop[args]` for
  readability.

See BRMMacroWeb (`compute_steps` IP + `PipelineRoutes.stage` route) and
the `pathfinder` / `posterior_warmup` IPs under `AppData.run.stan` for
worked examples.

## Error handling

### Where errors go — `/tmp/htmxo_errors/<uid>.log`

**Every caught route exception writes a full report to
`/tmp/htmxo_errors/<uid>.log` by default.** That is the first place to
look when a route returns the framework's error article. The in-browser
article only shows the short `<uid>` — the uid, ISO timestamp, request
method + target, and full `showerror(io, err, bt)` backtrace all live in
the log file on disk.

```
/tmp/htmxo_errors/<uid>.log          ← default; tempdir() + "htmxo_errors"
$HTMXO_ERROR_DIR/<uid>.log           ← if the env var is set
```

The exact directory is held in `ERROR_DIR[]` (a `Ref{String}`), set by
`__init__` from the `HTMXO_ERROR_DIR` environment variable, falling back
to `joinpath(tempdir(), "htmxo_errors")` — which resolves to
`/tmp/htmxo_errors` on Linux and macOS. You can reassign `ERROR_DIR[]` at
runtime; no auto-rotation, no size cap.

The uid is a short base-16 hash of `time_ns()` — same uid printed in the
error article, emitted in the `@error` log line, and used as the filename.
Grep the uid from your terminal/log viewer back to the file in one click.

### What happens on exception

Every route handler is wrapped in try/catch. On exception, HTMXObjects:

1. Generates a short uid (`hash(time_ns())`).
2. Writes `$ERROR_DIR[]/<uid>.log` (default `/tmp/htmxo_errors/<uid>.log`)
   containing uid, ISO timestamp, method + target, and
   `showerror(io, err, bt)`.
3. Emits one `@error "HTMXObjects caught an error: <full path>"` — terse;
   the full stack trace is on disk.
4. Feeds the result of `__error__(err)` (or the default renderer) back
   through the response pipeline.

### Status codes

- **HTMX requests → HTTP 200** so vanilla HTMX still swaps the error article
  in without needing `response-targets`.
- **Non-HTMX requests (curl, direct browser nav, uptime checks) → HTTP 500**
  so logs and monitors see errors as errors.
- If your `__error__` hook returns an `HTTP.Response` directly, its status is
  respected — no rewrite.

### Customising

```julia
@htmx struct AppRoutes
    # Opt out — let exceptions propagate to Oxygen's 500 handler:
    # __error__ = rethrow

    # Custom rendering:
    __error__(err) = h.article(h.header("Oops"), h.p(sprint(showerror, err)))
end
```

### Widget-level containment — `safely`

For composite routes (dashboards with several independent panels), wrap each
panel in `safely` so one failure doesn't kill the others:

```julia
@get dashboard = h.div(
    safely(; obj=__self__) do
        render_ppc_plot(data)
    end,
    safely(; obj=__self__) do
        render_summary(data)
    end,
)
```

### Error-tagged HTML — `e.*`

`e.<tag>` is the error-tagged parallel to `h.<tag>` (adds
`data-error="true"`). The `?error` filter keeps only `data-error` nodes and
their ancestors — useful for exposing machine-readable error summaries from
a composite page.

## Static recording & replay

```julia
route!(app; record_dir="site")
```

Every response is saved to disk mirroring the URL path (`/post/42` →
`site/post/42.html`). `static_transform` walks the Node tree and:

- Strips `hx-post`, `hx-put`, `hx-patch`, `hx-delete` attributes.
- Strips `hx-get` attributes whose URL contains `?` or points at a
  kwargs-only route.
- Marks affected elements with `data-static-disabled` + `disabled`, and
  injects a `<style>` block dimming them.

After recording, replay with any static server:

```bash
python -m http.server --directory site
```

## Revise hot-reload

| Change                                             | Hot-reloaded?                       |
|---------------------------------------------------|--------------------------------------|
| Plain function in the package / web module         | Yes                                  |
| `@dynamicstruct` / `@htmx` struct body              | Yes                                  |
| New `@get`/`@post` added to a struct               | Yes (via `_reroute!`)                |
| `@testset` body in `web/src/test/runtests.jl`      | Yes                                  |
| `@testset` via `../` path outside the pkg tree     | **No** — source-text cache mismatch  |
| `@generated` function helper                       | **No** — world-age frozen            |
| `Revise.includet(SubModule, file)`                 | **Breaks all tracking** — never use  |
| `const` value change                               | **No** — `APPDATA` must never be reassigned |

### Gotcha: renaming the root `@htmx` struct

Revise does **not** re-run `__init__()`. Renaming the root struct (e.g.
`AppContext` → `AppRoutes`) means `route!(AppRoutes())` never fires, so no
routes register. Every route returns the framework's error article with
HTTP 200 — easy to miss if you only check status codes.

**Triage:** `curl -s ...?plain` and check the body, not just the status.

**Fix without restart:** temporarily add a bare top-level
`route!(AppRoutes())` line in the module file. Revise evaluates new
top-level expressions, so routes register under the new root. Remove the
line once verified — subsequent reloads go through `_reroute!`.

## HTML building with `h`

`h` (re-exported from HTMX.jl) builds a Cobweb `Node` tree.

```julia
h.div(; class="container")(              # keyword attributes, positional children
    h.h1("Title"),
    h.p(; hx_get="/data", hx_target="#result")("Load"),
)
```

- Underscores in attribute names become hyphens (`hx_get` → `hx-get`).
- `htmx(content; pico_version, htmx_version, hyperscript_version,
  extra_head, feedback)` wraps content in a full HTML page with CDN tags.
- `@__str` embeds inline Hyperscript: `h.button(__"on click toggle .hidden on #menu")("Toggle")`.
- HTMX inherits `hx-swap`, `hx-target`, `hx-trigger` from ancestors. Use
  `hx-disinherit="hx-swap ..."` on a container when its children should
  not inherit.

### HTMX headers

Inspect the request with `is_htmx(req)`, `hx_target(req)`,
`hx_trigger(req)`, `hx_current_url(req)`, `hx_boosted(req)`,
`hx_prompt(req)`.

Attach response headers with `hx_response`:

```julia
hx_response(content;
    trigger     = "itemSaved",    # HX-Trigger — fire a client event
    push_url    = "/new/path",    # HX-Push-Url
    retarget    = "#other",       # HX-Retarget
    reswap      = "outerHTML",    # HX-Reswap
    redirect    = "/login",       # HX-Redirect
    refresh     = true,           # HX-Refresh
    location    = "/dashboard",   # HX-Location
)
```

### Out-of-band swaps

`to_response` accepts `content => "id"` pairs — wraps content in a `<div>`
with `hx-swap-oob="true"` and the given id:

```julia
to_response([main_body, sidebar_html => "sidebar"])
```

## Form helpers

All exported from `HTMXObjects`.

**Inputs:** `linput`, `sinput`, `sinput_custom`, `soption`, `rinput`,
`ninput`, `cinput`, `tinput`, `radio_group`, `ainput`.

**Forms:** `get_form`, `post_form`, `hidden_inputs`.

**Tables:** `render_table(table; id, sortable, download, download_filename,
caption, cell, class, kwargs...)` — any Tables.jl-compatible table as an
`h.table` with click-to-sort headers and CSV download. Multi-table pages
work automatically (`th.closest('table')`).

**Widgets:** `status_badge(state::Symbol)`, `nav_sidebar(items)`,
`htmx_tabset(items; active, target)`, `lazy(url; tag, swap, kwargs...)`,
`tabset`, `request_feedback` (pulsating outline while in-flight, teal flash
on success, coral on error — included by default in `htmx()`).

**Conditional visibility:** `sinput(...; show_when=(field, op, value))` with
`show_when_script()` once per page. Ops: `==`, `!=`, `startswith`,
`endswith`.

**Captions:** `CaptionSpec(; title, short, long)`, `render_caption(spec)`,
`with_caption(spec, content)`.

See the docstrings for full signatures.

## Git-backed inline editors

Three primitives for editable content backed by a git repository:

- `GitRepo` — `@dynamicstruct` owning a working directory. Auto-`git init`s
  on first access. API: `blob_sha`, `read_blob`, `list_commits`,
  `write_file!`, `locked_update!`, `editor(relpath)`.
- `editor_form(; id, post_url, content, version, ...)` — HTML form with
  Save/Cancel buttons and Escape-to-cancel.
- `EditorRoutes` — `@htmx` mountable via `@include` under a parent that
  exposes `editor` (`GitRepo.editor(relpath)`) and `container_id::String`
  locals. Ships with `@get form`, `@post save`, `@get history`,
  `@post restore`.

Parent `@param` values auto-forward through edit/save/cancel/history/
restore via `query_url(path, __parent__)`, so a parameterised parent
(`@param name::String` picking a file) round-trips with no extra wiring.

For partial-file edits (e.g. one key of a multi-key YAML), use
`repo.locked_update!(relpath; message) do current ... end` instead of
`write_file!` — the former serialises under the per-repo lock and composes
with `write_file!`, avoiding the read-then-write race that optimistic
concurrency would surface as a spurious conflict.

See `HTMXObjects/web/src/git_editor_demo.jl` for a worked example.

## `serve` and threading

```julia
serve(; host="127.0.0.1", port=8080, async=false, parallel=false, revise=nothing, kwargs...)
```

- `parallel=false` → single-threaded (default).
- `parallel=true` → Oxygen's default thread pool.
- `parallel=:interactive` → `:interactive` threadpool, leaving `:default`
  free for heavy computation. Launch Julia with e.g. `julia -t 8,4` for 8
  computation threads + 4 request-handling threads.
- `revise=:lazy` is the usual dev setting.

## What belongs where — summary

**On a `@dynamicstruct` (data, backend):**

- Collections (`items::Vector{...}`), caches, filesystem/DB handles.
- Expensive computations (`@cached`).
- Shared parsers, stores, resolvers.
- Anything that outlives a single request.

**On a `@htmx` (requests, UI):**

- HTML fragments and page layouts (sibling references make these ergonomic).
- Routes (`@get`/`@post`/etc.).
- `@param` declarations.
- Action handlers that mutate state on `AppData` and return updated UI.

**Outside both:**

- Pure utilities that don't reference any property. Prefer promoting them
  to a property on the relevant struct anyway.
- Types (`struct ExampleEntry`, `PersistentSet`, ...).

The web module should contain only `APPDATA`, struct definitions, and
`__init__`. No top-level functions, no module-level `const` besides
`APPDATA`, no custom Oxygen route handlers.

## Anti-patterns (observed in the wild)

- Manual `formdata(req)` / `queryparams(req)` in route bodies. Use kwargs
  or `@param` — type coercion, defaults, and multi-value handling are free.
- `__page__(...)` inside a route body (double layout). Return bare content.
- `is_htmx(__req__) ? fragment : full` dual-path. The pipeline does this.
- `if wants_markdown(__req__) ... else ... end` branches. Ditto.
- Plain `Dict{K,V}()` at module top level. Oxygen is concurrent.
- `const FOO = ...` besides `APPDATA`.
- Standalone `function foo(...) ... end` at module top level. Promote to a
  property on the owning struct. Plain `function` blocks inside a
  `@htmx`/`@dynamicstruct` body cause a parse error (the macro parses the
  body as property definitions).
- `Revise.includet(SubModule, file)` — clobbers Revise's pkgdata and breaks
  all tracking.
- `@enum X A B C` for form-driven data. Julia's `@enum` has no `parse`
  method. Use `String` or `Symbol`.
- Custom Oxygen route handlers alongside `route!`. Extend `route!` instead.

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
