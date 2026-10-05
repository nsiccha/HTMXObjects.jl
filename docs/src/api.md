# API Reference

The full set of HTMXObjects exports, organised by use case. For walkthroughs see the [Home page](index.md), [Components catalog](components.md), [Testing](testing.md) and [Examples](examples.md).

## App scaffolding

```@docs
@htmx
create_app
route!
Verb
```

| Helper | Use |
|--------|-----|
| `@htmx struct App … end` | The whole package surface — declares an app, its data, and its routes |
| `create_app(name)`       | Scaffold a new HTMXObjects app (web/, app/, Project.toml) on disk |
| `route!(app)`            | Register all `@get`/`@post`/`@put`/`@delete`/`@ws`/`@sse` markers found in the struct on `HTMXObjects.ROUTER` (an `HTTP.Router`) |
| `Verb{V}`                | Singleton type threaded into route IPs as the first arg, lets one property host `@get`/`@post`/… simultaneously |
| `serve()`, `terminate()` | Start / stop an HTTP.jl server on `HTMXObjects.ROUTER` |
| `staticfiles(...)`, `dynamicfiles(...)` | Mount a folder's files as `GET` routes (read once / on every request) |

## DynamicObjects re-exports

HTMXObjects builds on [DynamicObjects.jl](https://github.com/nsiccha/DynamicObjects.jl) and re-exports the names you'll need most often:

`DynamicObjects`, `@persist`, `@dynamicstruct`, `@memo`, `@cache_status`, `@is_cached`, `@cache_path`, `@clear_cache!`, `fetchindex`, `getstatus`, `cancel!`, `cancel_all!`, `PropertyComputationError`, `unwrap_error`.

## HTMX.jl re-exports

`auto`, `h`, `Node`, `Raw`, `@__str`, `HyperscriptString`. See the [HTMX.jl docs](https://nsiccha.github.io/HTMX.jl/dev/) for full details.

`htmx(...)` is **not** one of them — it is HTMXObjects' own page shell, documented under [The page shell](@ref).

### Which HTMX.jl

HTMXObjects declares `HTMX = "1"` — it renders through `HTMX.Raw` and relies on `h.*` escaping text and attribute values by default, neither of which exists before HTMX 1.0. HTMX.jl is unregistered, so a consumer assembling its own environment must supply a 1.x checkout itself: that is the `dev` branch of [nsiccha/HTMX.jl](https://github.com/nsiccha/HTMX.jl). Anything off the pre-1.0 history still reports `version = "0.1.0"` and is rejected at resolve time — deliberately, so the mismatch surfaces as an unsatisfiable requirement rather than as an `UndefVarError` on `HTMX.Raw` at render time.

## HTTP / request helpers

| Export | Purpose |
|--------|---------|
| `HTTP`         | Re-exported `HTTP` module                                        |
| `queryparams(req)` | Decode `?a=1&b=2` query string into a dict                    |
| `formdata(req)`    | Decode `application/x-www-form-urlencoded` body into a dict  |
| `is_htmx(req)`     | `true` iff the request has `HX-Request` header set            |
| `hx_target(req)`   | Value of `HX-Target` header (or `nothing`)                    |
| `hx_trigger(req)`  | Value of `HX-Trigger` header                                   |
| `hx_current_url(req)` | Value of `HX-Current-URL` header                            |
| `hx_boosted(req)`  | `true` iff request was triggered by `hx-boost`                 |
| `hx_prompt(req)`   | Value of `HX-Prompt` header (when `hx-prompt` is on the trigger) |

## Response helpers

| Export | Purpose |
|--------|---------|
| `to_response(x)` | Coerce arbitrary content to an `HTTP.Response`                           |
| `save_response(...)` | Persist a response (used by static recording)                        |
| `static_transform(...)` | Convert dynamic responses to static-friendly form (`static_transform(val; record_base)` for recording, `static_transform(val, spec::StaticExport)` for a request-scoped export) |
| `StaticExport(; url_map, controls, record_base)` | Request-scoped static-export spec for `dispatch(...; static=)` — see [Request-scoped static export](#request-scoped-static-export) |
| `static_export(req)` | The `StaticExport` a static `dispatch` attached to this request, or `nothing` |
| `hx_response(...)` | Build a response with HTMX-specific response headers (HX-Trigger, HX-Redirect, HX-Push-Url, HX-Refresh, HX-Reswap, HX-Retarget, HX-Reselect, HX-Location) |
| `hx_link(href, label; ...)` | Render a link that uses `hx-get` + `hx-push-url` (HTMX boost-style) |
| `htmx_or(htmx_value, full_value)` | Pick which to return based on `is_htmx(req)`                   |
| `safely(f; obj, req)` | Run `f()` and return an inline error widget if it throws — keeps a panel from crashing the whole page |

A route may return a raw `HTTP.Response` — e.g. a `206` byte-range media
response — and it passes through the response pipeline unchanged.

## The page shell

A route's return value is a *fragment*. On direct browser navigation the
framework wraps it with the app's `__page__` property, which is normally built
on `htmx(...)` (or its `pico_page` shorthand). An HTMX swap gets the levels of
that chain which are not on screen yet — never the root shell, which is a whole
document; the manual's response-pipeline section has the rule and the
`?__chrome__=` override. That shell — not the route — owns
the document preamble: `<!DOCTYPE html>`, `<meta charset>`, the viewport and
color-scheme metas, the CDN tags, and the injected theme/feedback assets.

`htmx(...)` returns an [`HTMLDocument`](@ref), *not* a bare `Node`: the doctype
is not an element, so it cannot live in the `HTMX.Node` tree and is emitted by
`HTMLDocument`'s `show(::IO, ::MIME"text/html", …)` ahead of the `<html>` root.
Serialize it however you like — `repr("text/html", page)`, the response
pipeline, static recording — and the bytes always start with the doctype, so
pages render in **standards mode**. That matters beyond the legacy box model:
browser libraries refuse to run in quirks mode outright (KaTeX's
`katex.render` throws `KaTeX doesn't work in quirks mode`, and
`throwOnError: false` does not suppress it).

Fragments are not documents and never carry a doctype.

### Offline pages — `assets=:vendor`

By default the shell loads its JS/CSS from a CDN. A standalone app that must
run fully offline (air-gapped) vendors those files instead: `vendorfiles()`
mounts the exact pinned releases same-origin at `/vendor/...`, and
`assets=:vendor` points the shell at them. The bytes are the npm release
tarballs pinned in `Artifacts.toml` — byte-identical to the CDN files — and
download lazily on the first `vendorfiles()` call, so CDN users fetch nothing.

```julia
vendorfiles()                                  # → GET /vendor/htmx.min.js, …
__page__(content) = htmx(content; assets=:vendor)
```

Vendor mode serves each library solely at its pinned version (a different
version errors loudly); `pico_page` needs its pin spelled out, since its
floating `"2"` default is not the pin. A custom mount pairs with a matching
prefix: `vendorfiles("static/vendor")` + `assets="/static/vendor"`.

A static bundle has no routes to serve the files from, so copy them instead:
`copy_vendorfiles(dir; packages)` writes the same pinned files into `dir` and
returns their paths in load order. `vendor_head(base; packages)` returns the
matching head nodes (scripts, plus a stylesheet link for `:pico`, htmx before
its extensions) for a hand-built `HTMLDocument`. `base` is used as given, so
a relative prefix addresses the copies relative to the page. The `htmx()`
shell accepts the same relative string as `assets=`.

```julia
copy_vendorfiles(joinpath(bundle, "assets", "vendor"); packages=(:htmx, :pico))
head = h.head(h.meta(charset="utf-8"),
              vendor_head("assets/vendor"; packages=(:htmx, :pico))...)
# or: htmx(content; assets="assets/vendor", pico_version=HTMXObjects._PICO_VERSION)
```

```@docs
htmx
HTMXObjects.pico_page
HTMLDocument
vendorfiles
copy_vendorfiles
vendor_head
```

## Server-sent events

`@sse` turns a property into a `text/event-stream` endpoint. The body receives
the stream as `__sse__` and pushes events with `send` — the same
`HTTP.WebSockets.send` that `@ws` bodies use. Arguments are parsed and
validated like a `@get`'s *before* the stream starts, so a bad request still
gets an ordinary error response.

```julia
using HTTP.WebSockets: send

@htmx struct Jobs
    @sse progress(; n::Int=10) = begin
        for i in 1:n
            send(__sse__, h.p("step $i of $n"))
            sleep(0.5)
        end
        h.p("done")                         # sent as the final `done` event
    end
    @get index() = sse_region(query_url(__self__/"progress"; n=5), h.p("waiting…");
                              swap="beforeend")
end
```

- A value the body returns (other than `nothing`) is sent as `event: done`; a
  thrown error is recorded and its `__error__` rendering is sent as `done`
  instead. Either way the stream then ends with `event: close`.
- [`sse_region`](@ref) connects with htmx's SSE extension (loaded by `htmx()`
  page shells) and closes the source on `close`. Without that marker the
  browser's `EventSource` would reconnect and run a finished body again.
- An open-ended feed loops `while isopen(__sse__)`. A client that leaves makes
  the next write fail: `send` returns `false` and `isopen` turns `false`. A
  keep-alive comment every 15 s keeps proxies from dropping a quiet stream and
  notices departed clients.
- On reconnect the browser sends the `id` of the last event it saw; read it with
  [`last_event_id`](@ref) to resume instead of replaying.
- Each open stream holds a connection and a task until it ends. With the default
  `serve(; parallel=false)`, a body that computes without yielding (no `sleep`,
  `wait`, or I/O) stalls the whole server, and browsers allow about six
  HTTP/1.1 connections per host, so many streams on one page starve its
  other requests.
- `@sse` routes are GET-only streams: `openapi`, `prewarm_routes!`,
  `operation_form`, and `semantic_app`'s default renderer skip them or refuse
  them, and in-process [`dispatch`](@ref) answers with an error because there is
  no connection to stream on.

### Server-push refresh by key

A [`live_fragment`](@ref) subscribes to a resource key such as
`gh:owner/repo#12`: it re-`GET`s itself whenever the server invalidates
that key, so every open page refreshes just those fragments with no
polling and no client JavaScript. One [`KeySubscriptions`](@ref) registry
per app holds the live streams; an `@sse` route feeds it through
[`serve_key_feed!`](@ref), and any server code — a poller, a webhook, a
POST handler — pushes with [`invalidate_key!`](@ref):

```julia
const SUBS = KeySubscriptions()

@htmx struct Cards
    @get panel() = live_region(query_url(__self__/"key_events"; key=keys),
        (issue_card(__self__, k) for k in keys)...)
    @get card(; key::String="") = live_fragment(key, _card_body(key);
        fragment_url=query_url(__self__/"card"; key=key))
    @sse key_events(; key::Vector{String}=String[]) =
        serve_key_feed!(__sse__, SUBS, key)
end

invalidate_key!(SUBS, "gh:owner/repo#12")   # every subscribed card re-fetches
```

The page above opens ONE event stream for all its cards: the
[`live_region`](@ref) connects the multiplexed feed (its URL carries every
key), each fragment listens to that stream through its own key's event
(`refresh-<key>`), and only the invalidated key's fragments re-fetch. A
stream per fragment would cost one HTTP/1.1 connection each — browsers
allow about six per origin — so the multiplexed shape is the one for
per-row or per-reference liveness. A lone fragment may still pass
`events_url` to open its own stream instead.

When the live keys are not known up front — cards rendered many to a
page, or fragments swapped in later by htmx, a poller, or a modal — pass
`discover=true` and give the region the feed's base url instead:
`live_region(query_url(__self__/"key_events"); discover=true)`. The
[`live_region_script`](@ref) runtime (included by [`htmx`](@ref); a page
built without the shell includes it itself) gathers the `data-key`s of
the descendant fragments, opens one stream with `?key=…` for the union,
and reconnects whenever the set changes. Each reconnect is an ordinary
fresh [`serve_key_feed!`](@ref) subscription — no server change is
needed — and a push landing in the handover window re-fetches its
fragments twice, idempotent. With no fragments present the region holds
no stream. A fragment belongs to its nearest ancestor discover region.

`invalidate_key!` is the push half only: it does not touch the cache the
fragment route reads. Refresh the data first (or kick its background
rebuild), then invalidate, so the re-fetch renders the new state. The
fragment route answers with the same `live_fragment` call, so the re-fetch
is self-similar. In single-stream mode the swapped-out element's stream is
closed by the SSE extension and the fresh element opens a new one; in a
`live_region` the shared stream outlives every swap. An invalidation that
lands between the page render and the stream connect is missed; the
fragment shows render-time state until the next one. In `?plain` the
element degrades to its text content.

```@docs
SSEStream
last_event_id
sse_region
KeySubscriptions
subscribe_key!
unsubscribe_key!
serve_key_feed!
invalidate_key!
live_fragment
live_region
live_region_script
```

## Markdown / agent-readable responses

For routes that should serve an agent-readable Markdown view *and* an HTML view from the same handler:

| Export | Purpose |
|--------|---------|
| `wants_markdown(req)`  | `true` iff `?plain` / `?markdown` query param OR `Accept: text/markdown` / `text/plain` header is set |
| `wants_errors(req)`    | `true` iff `?error` query param is set                               |
| `markdown_response(...)` | Build a `text/markdown` response                                   |
| `html_only(...)` / `markdown_only(...)` / `HtmlOnly` / `MarkdownOnly` | Tag content for one rendering only |

For authoring Markdown that renders to HTML — the reverse direction:

| Export | Purpose |
|--------|---------|
| `render_markdown(text; rules, context)` | CommonMark (+ GFM tables/strikethrough/task lists) Markdown → `h` node tree, with inline text rules |
| `MarkdownRule(pattern, build)` | One rule: a `Regex` plus `build(match, context)` producing the replacement node(s) |
| `MARKDOWN_URL_RULE` | Stock rule linking bare `http(s)://` URLs; the default registry |
| `MarkdownRenderer` / `DefaultMarkdownRenderer()` | Renderer supertype / the stock renderer; subtype and add `markdown_node` overrides |
| `markdown_node(renderer, kind, node, rules, context)` | Per-node-kind override point (plus the single-node `markdown_node(renderer, node, ...)` form) |
| `markdown_children(renderer, node, rules, context)` | Joined-run children render, for override recursion |
| `markdown_text_run(renderer, run, in_link, rules, context)` | Joined-run override point (sees runs inside links too) |
| `markdown_parser(; extra_rules)` / `render_markdown(::CommonMark.Node)` | Parse with extra parser rules / render an inspected AST |
| `decorated_link(label, href, entry; class, attrs, base)` | `base` attrs always; `attrs(entry)` merged over them once known |

`render_markdown` parses with CommonMark.jl, so intra-word underscores in
identifiers stay verbatim (the stdlib parser took them as emphasis and deleted
them). Rules run on joined text runs — CommonMark splits `https://x/a_b&c`
into several `Text` nodes, and the joined run is what rules match — outside
links, code spans and fences only. The default registry (`rules=nothing`) links
bare URLs with GFM trailing-punctuation trimming; pass `rules=MarkdownRule[]`
for pure CommonMark, or a vector of `MarkdownRule`s (composed with
`MARKDOWN_URL_RULE`) for app references. `context` scopes one value to the
whole render. Rule-built nodes are ordinary nodes, so the `?plain` projection
stays faithful (`h.a` → `[text](url)`).

Apps with their own node needs subtype `MarkdownRenderer` and add
`markdown_node` methods for only the kinds they render differently; every
other kind falls through to stock, and the walk recurses through the same
renderer at every depth. `markdown_children` and `markdown_text_run` are the
recursion helpers for override authors; `parser_rules=` registers extra
CommonMark parser rules, and `render_markdown(::CommonMark.Node)` renders an
already-parsed tree.

Deferred decoration pairs a [`MarkdownRule`](@ref) with a DynamicObjects
`BackgroundCache` in batch mode: the build function reads `cache[key]` on the
render path and hands the entry to `decorated_link`, which renders a plain
anchor with `base` while the batch is out and merges `attrs(entry)` (state
colour, hover title) over it once it lands. Reads never block and failures
keep links plain — the
cache single-flights the drain, backs off, and logs with the cause — so first
paint never waits; the next render (a poll cycle, a push refresh) picks the
metadata up. `?plain` carries `[label](href)` either way.

## Error handling and tagging

| Export | Purpose |
|--------|---------|
| `e`                   | Error-tagged HTML builder — mirrors `h` (`e.div(...)`, `e.p(...)`, …) but injects `data-error="true"`. Pair with `filter_errors` and `?error` to expose machine-readable error summaries from a composite page |
| `filter_errors(html)` | Walk a Node tree and keep only nodes with `data-error="true"` (and their ancestors); used by the response pipeline when `?error` is on the query |
| `ERROR_DIR`           | `Ref{String}` — directory where caught route exceptions are logged (default `joinpath(tempdir(), "htmxo_errors")`, override via `HTMXO_ERROR_DIR` env var) |

## Semantic applications

`semantic_app` turns one mounted semantic graph into the ordinary operation
surface. Each route remains the executable declaration; the compiler discovers
it, renders its typed/domain-aware form, assigns a result target, and submits to
the already-registered route. `operation_form` remains available when one
operation needs custom placement.

```julia
@htmx struct ModelApp
    @param study::Symbol = :alpha

    @include models = begin
        @options model = (:base, :full)
        @get fit(; model::Symbol=:base) =
            h.p("$(study):$(model)")
    end

    @get index() = semantic_app(models; title="Model operations")
end
```

Adding another route inside `models` automatically adds its descriptor, form,
result target, and registered operation; there is no second operation list.
Mounted `@param` context without a matching `@options` declaration, including
its default, becomes a hidden input. A declared-domain `@param` is instead one
visible shared control, deduplicated across every mounted operation that carries
it; its submitted value still flows through the request extractor. An indexed
`@include` is intentionally fail-closed until an index is selected—call
`semantic_app(app.models(:chosen))` to compile that concrete subtree.
Generated result targets are stable for each mounted graph and distinct across
selected mounts, including application and forwarded prefixes. Two selected
children can therefore share a page; their forms, dependent refreshes, and
polling continue to target their own results without manually assigned IDs.

For custom placement, `operation_form` renders its request/fixed context inside
one local `.htmxo-semantic-context` fieldset. It does not need an external
context selector; the selector/include wiring is only needed when
`semantic_app` lifts that group outside several operation forms.

If that standalone form selects the page represented by its request context,
pass `navigate=true`. The generated GET form uses native `method` and `action`
attributes, so selection performs a full browser navigation: the selected
request rebuilds the page shell and navigation as well as its route fragment.
HTMX remains only on controls that need a dependent-domain refresh before
submission, and navigation mode is retained across that refresh. Static native
forms omit internal refresh fields; dynamic forms refresh only their control
region, leaving the form and button in place. Only control-rendering settings
ride the HTMX refresh URL, so the eventual browser location stays clean.
The mode is GET-only and requires context
inside the form; `semantic_app` operation cards remain local HTMX swaps. A raw
`hx_push_url="/custom"` is still available in that default HTMX mode, but
changing history alone does not rebuild an outer shell. Native navigation owns
its `method`/`action` and rejects form-level `hx_*` kwargs so this full-page
contract cannot silently degrade back into a fragment swap.

Fixed semantic state is the zero-boilerplate shared-control form. Declare each
field and domain once; zero-argument operations that depend on those fields
inherit effective `kind=:context` inputs from DynamicObjects. `semantic_app`
renders one shared control group per mounted source field and every operation
form includes that group automatically:

```julia
@htmx struct ModelGraph
    @options study = (:north, :south)
    study::Symbol
    @options dose = (50, 100)
    dose::Int

    @get fit() = h.p("fit:$(study):$(dose)")
    @post predict() = h.p("predict:$(study):$(dose)")
end

app = ModelGraph(:north, 50)
semantic_app(app)
```

A submitted non-default fixed selection is applied with
`DynamicObjects.remake`; request/route/prefix rebinding remains a `remount`.
The selected operation therefore executes against the rebuilt mounted target,
while unrelated retained caches keep their identity. This works when the
semantic graph is the routed root and when a fixed semantic bundle is mounted
as a concrete external `@include` child.

The first successful `semantic_app` render also activates a private managed
root provider for the rooted graph. Its identity is the root type plus the
normalized application mount prefix already carried by the request. The
current graph is seeded into that provider even when it was declared before a
request and already carries required fixed semantic state; later operations
receive a same-type request remount. Applications do **not** declare a job-key
helper, `Dict`, lock, factory, `RootProvider`, or cleanup call. An explicitly
supplied custom provider remains authoritative.

Operations from a graph compiled by `semantic_app` run through
`DynamicObjects.execute_materialization` with the provider-owned
`(; scope, key, retention)` context. Provider LRU/TTL release notifications call
`release_materialization!` and opportunistic `materialization_gc!` outside the
provider lock. Applications construct no executor/store and call no GC.

| Export | Purpose |
|--------|---------|
| `semantic_descriptor(obj_or_type)` | HTML-free hierarchical graph plus declaration-ordered, mount-resolved operation routes |
| `application_descriptor(obj_or_type; contributions)` | Deterministic flat DO+HTMXO declaration graph with stable node/edge IDs and source provenance |
| `application_observations(obj, descriptor; calls)` | Separate noncomputing live-state overlay keyed by declaration node IDs |
| `application_explorer_view(descriptor; …)` | Server-rendered Map, Inspector and searchable Reference for an application descriptor |
| `ReflectionRoutes` | Opt-in architecture explorer plus descriptor/observation JSON endpoints |
| `semantic_app(obj; values, title, submit, submit_attrs, render_operation)` | Compile a mounted graph into operation cards/forms and result targets |
| `operation_form(obj, name; …)` | Low-level generated form for one operation |
| `SemanticNode` and its sixteen elements | Reusable above-markup presentation values with peer format projections — see [The semantic element vocabulary](@ref) |
| `semantic_card(value)` | Option-value hook returning its reusable `SemanticCard` |
| `internal_input(input)` | Is this descriptor input framework-injected rather than author-declared? |

`render_operation(entry)` supplies `object`, `route`, `name`, `verb`, `path`,
`title`, `target_id`, `form`, and `result`. A parameter-free GET using fixed
defaults can feed `entry.title => (entry.object / entry.route.path)` into
`comparison_view`. This preserves the mounted index and external prefix;
`entry.path` is the reflected graph path. Use generated forms/results when
current context or form values need submission.

`submit` supplies **content inside the generated submit button**. It can be text
or presentational `h.*` nodes; avoid nesting another button, link, or input.
`submit_attrs` decorates the interactive button itself, so tooltip and accessible
label attributes belong there:

```julia
semantic_app(app.models(:chosen);
    submit=entry -> h.span(h.span(; class="icon", aria_hidden="true")),
    submit_attrs=entry -> (; title=entry.title, aria_label=entry.title, class="compact"),
    render_operation=entry -> h.div(entry.form, entry.result))
```

Both keywords accept a fixed value or an operation-entry callback.
`operation_form(...; submit, submit_attrs=(; title="Run", aria_label="Run"))`
uses the same button contract. Form-level `kwargs` continue to decorate the
form. Button submission attributes (`type`, `name`, `value`, `form*`, `hx_*`)
are compiler-owned; presentation cannot redirect the operation or its result.

Dependent refresh updates only `.htmxo-semantic-controls` and does not execute
the operation. The form, its attributes and target, and the original rich button
remain in place. Submit content never rides a hidden input as Julia text;
generated forms carry only the request/context inputs needed for submission.
Older full-form refresh requests remain accepted for already-rendered pages.

### Sharing settings across a table

Put common request settings and event handling on an enclosing `h.div`,
`h.table`, or `h.tbody`. These builders accept the ordinary htmx attributes;
no settings registry or per-row script is needed. For example:

```julia
h.div(
    h.table(h.tbody(rows...)),
    h.output("Ready"; aria_live="polite");
    class="operations-table",
    hx_swap="innerHTML",
    hx_vals="{\"view\":\"compact\"}",
    hx_on__before_request="this.querySelector('output').textContent = 'Working';",
    hx_on__after_request="this.querySelector('output').textContent = event.detail.successful ? 'Ready' : 'Request failed';")
```

The request events bubble from descendant controls to that ancestor, including
controls inserted by later swaps. `hx_on__before_request` spells
`hx-on--before-request`, the `htmx:beforeRequest` event; `hx_on_click` handles
bubbling ordinary clicks. Keep a longer shared handler in one page-shell
`h.script(Raw(...))` or script asset and call it from the ancestor, or register
one delegated `document.body.addEventListener(...)` there. Return row fragments
without repeating that page-level installation.

| Setting | Where it can be shared | Boundary |
|---|---|---|
| `hx_target`, `hx_swap` | Nearest common ancestor | A descendant's explicit value wins. Relative targets such as `next .row-operations` resolve from the requesting control. Generated operation forms retain their own stable target and swap. |
| `hx_vals`, `hx_headers` | Common ancestor | Use static JSON for common values. A nearer declaration overrides the same key; evaluated `js:` expressions must be trusted application code. |
| `hx_include` | Common ancestor | Use a stable selector for external controls. Extended selectors such as `find` are evaluated from the requester, even when inherited; they do not search from the ancestor that declares them. |
| `hx_on__…`, `hx_on_click` | Ancestor that receives bubbling events | The handler is installed on that ancestor; `this` is the ancestor and `event.target` identifies the originating node. These are event delegation, not inherited attributes. |
| Appearance | One wrapper class and a stylesheet selector | HTML `class`, `title`, and `aria-label` are not inherited. A generated submit button's accessible name remains on that button via `submit_attrs`. |

Request URLs, request triggers, operation result addresses, and successful form
inputs keep their local identities. In particular, `hx_get`, `hx_post`, and
`hx_trigger` are not inherited. Sharing a callback or NamedTuple avoids
duplicating the Julia declaration; each application of it still emits its
attributes. Put the common attributes on the ancestor once to reduce HTML
bytes. For a custom low-level `operation_form`, the default `target_id=nothing`
omits its target/swap attributes and allows both to inherit. A form with an
explicit `target_id` supplies its own swap as well.

Keep `semantic_app` responsible for discovering operations and creating their
forms/results. Its `submit`, `submit_attrs`, and `values` callbacks share
presentation policy across entries; `render_operation` places `entry.form` and
`entry.result` in each row's layout. Wrap those surfaces in the common settings
ancestor. Do not replace their generated controls or stable target addresses
with a parallel operation list.

The standalone [shared-settings table example](https://github.com/nsiccha/HTMXObjects.jl/blob/devibe/examples/shared_settings.jl)
uses this shape for 400 indexed mounts, with rich submit labels, one common
settings ancestor, and loadable row fragments. Run
`julia --project examples/shared_settings.jl`. The default page loads a row's
two discovered GET/POST forms when its **Load operations** button is clicked;
`/eager` renders all 800 forms up front for comparison. Its regression
fixture compares raw serialized bytes against the same markup with attributes
repeated on every row and exercises both shapes in a real browser. The reference
capture is 1,273,931 bytes repeated versus 912,836 bytes shared: 361,095 bytes
saved (28.3%), with the generated markup otherwise equal. The fixture also
checks that the mounted HTTP response body equals the measured shared markup.
This measures payload savings for that table, not a full-application latency
improvement.

**Render controls when needed.** Sharing settings removes repeated attributes;
loading a row's operation surface on demand also avoids generating and sending
the unopened forms. The example uses its ordinary mounted `detail` route:

```julia
h.td(
    h.button("Load operations"; type="button",
        hx_get=query_url(app / "detail"; row=number, session_key=app.session_key),
        hx_target="next .row-operations"),
    h.div(""; class="row-operations"))
# detail returns operation_surface(app.rows(number)), using semantic_app.
```

The same 400 row summaries then start at **88,748 bytes**, compared with
912,836 bytes including every form: **824,088 bytes saved (90.3%)**. The
measured last-row fragment is 2,062 bytes. The mounted HTTP response matches
the smaller serialization, and browser acceptance loads two independent rows,
refreshes dependent controls, and submits both GET and POST under the original
shared ancestor. No new settings or deferred-rendering API is involved.

Opening a row requires an extra request. Opening every row eventually loads
all its controls; this reduces initial HTML and DOM size. For a large number
of summaries, render a bounded range as well (for example,
`table_surface(app; indices=1:25)`) and provide page navigation in the app.
Use the eager shape when simultaneous controls for every row are required.

**Native submissions use successful HTML controls.** `hx_vals` and `hx_include`
add values to htmx requests only; they do not supply a native form submission.
Preserve the generated hidden request inputs. For a standalone native GET,
use `operation_form(...; navigate=true)`, which keeps context inside the form.
For a low-level POST with a native fallback, pass
`method="post", action=leaf / "write"` to `operation_form(leaf, :write; verb=:POST, …)`.
The example's load button and an external shared context panel need htmx;
choosing a native standalone form keeps its controls local.
Shared ancestor settings do not change that
boundary or the server's typed/domain validation.

The [htmx inheritance guide](https://htmx.org/docs/#inheritance),
[`hx-vals`](https://htmx.org/attributes/hx-vals/), and
[`hx-include`](https://htmx.org/attributes/hx-include/) describe the underlying
attribute rules. Measure UTF-8 response bytes as well as effective requests;
decoded attribute counts alone do not establish a payload reduction.

### Reusing generated markup

Retaining a generated form Node avoids rebuilding that Node, but rendering it
still projects its leaves and serializes the tree on every response. The existing
trusted-markup seam also accepts a previously serialized, server-generated
snapshot: `snapshot = repr("text/html", surface)`, then
`h.div(HTMX.Raw(snapshot))`. That reuses the exact emitted wiring and bytes.

A snapshot freezes its context. Reuse it only while the mounted root/provider
lifetime, selected indices, resolved external prefix, inherited request values,
current controls/domains, and presentation settings remain the same. Rebuild
when any of those change. It does not remount a root, rebind request values, or
activate a new semantic root provider; compile the appropriate graph before
reusing its markup. HTMXObjects supplies no automatic cache key or invalidation
policy for those changing inputs. `Raw` is for trusted generated HTML, with
ordinary application data escaped during the original Node serialization.

```@docs
semantic_descriptor
application_descriptor
application_observations
application_explorer_view
application_explorer_styles
ReflectionRoutes
semantic_app
operation_form
SemanticNode
SemanticCard
SemanticFields
SemanticCode
SemanticStatus
SemanticUnavailable
SemanticProse
SemanticTable
SemanticPlot
SemanticMetric
SemanticLink
SemanticAction
SemanticArtifact
SemanticSection
SemanticGroup
SemanticDisclosure
SemanticAlternatives
MarkdownRule
MARKDOWN_URL_RULE
render_markdown
MarkdownRenderer
DefaultMarkdownRenderer
markdown_node
markdown_children
markdown_text_run
markdown_parser
decorated_link
semantic_card
internal_input
```

### Application architecture explorer

`application_descriptor` composes the declaration graph owned by
DynamicObjects with HTMXObjects' mount-resolved route surface. It is pure
reflection: constructing the descriptor never constructs an application,
evaluates an `@options` expression, runs a route, or computes a property.
The returned shape is:

```julia
(
    schema = "htmxobjects.application-descriptor/v1",
    declaration_schema = "dynamicobjects.declaration-graph/v1",
    root = "…",               # stable DynamicObjects type-node ID
    nodes = [(; id, kind, label, metadata, fragment), …],
    edges = [(; id, kind, from, to, metadata, fragment), …],
    metadata = (
        root_type = "MyApp",
        declarations = (;),
        statistics = (mounts=1, routes=1, artifacts=0),
    ),
)
```

The DynamicObjects nodes retain declaration docs, signatures, direct declared
dependencies, option domains, source location, full normalized source/code and
extension metadata. HTMXObjects adds `:mount`, `:route` and `:artifact` nodes.
The combined edge vocabulary is deliberately explicit and finite:

| Edge | Meaning |
|------|---------|
| `:contains` | Declaration ownership or mounted containment |
| `:mounts` | A declared type appears at one mounted application location |
| `:serves` | A mount serves a route |
| `:reads` | A route is backed by its declared operation property |
| `:depends_on` | A direct dependency inferred from the authored DO declaration |
| `:produces` | A materialized property declares a durable artifact |
| `:describes` | An explicit external/domain descriptor link |

There is no inferred transitive Julia call graph. Domain packages extend the
descriptor through a plain-data contribution and remain optional dependencies:

```julia
base = DynamicObjects.declaration_graph(MyApp)
domain = (
    namespace = "my-domain",
    nodes = [(;
        id="my-domain:model:1", kind=:domain, label="Model declaration",
        metadata=(; documentation="…", full_code="…"),
    )],
    edges = [(;
        id="my-domain:edge:root-model", kind=:describes,
        from=base.root, to="my-domain:model:1", metadata=(;),
    )],
)
descriptor = application_descriptor(MyApp; contributions=(domain,))
```

Contributor IDs are globally unique and are never rewritten. The namespace is
kept as provenance in each merged record; duplicate IDs and dangling edge
endpoints are rejected by DynamicObjects. Unknown contribution kinds and
metadata are preserved and rendered by the inspector.

Mount the generated explorer wherever it belongs in the application:

```julia
@htmx struct MyApp
    @include reflect = ReflectionRoutes(; root=MyApp)
    # …
end
```

This adds the following routes at the chosen mount prefix (`/reflect` here):

| Route | Response |
|-------|----------|
| `GET /reflect` | Server-rendered Map, synchronized Inspector, and searchable Reference/table |
| `GET /reflect/descriptor` | `htmxobjects.application-descriptor/v1` JSON |
| `GET /reflect/graph` | Existing nested `semantic_descriptor(root).graph` JSON (compatibility surface) |
| `GET /reflect/observations` | Optional noncomputing live overlay JSON when `target` is configured |

Every map/reference entry is an ordinary anchor carrying `selected=<stable-id>`;
search is an ordinary GET parameter. Full labels and the complete inspector are
therefore usable without JavaScript or a client-side visualization library.
The one scoped semantic stylesheet is available separately as
`application_explorer_styles()`.

Live state never mutates the declaration descriptor. Call
`application_observations(object, descriptor)` explicitly, or mount
`ReflectionRoutes(; root=MyApp, target=object)` and opt into `?live=true`.
It delegates to DynamicObjects' `materialization_observation` path and does not
compute a property merely to display it. Indexed observations require explicit
`calls=(; node, args, kwargs)` records; unbound nested objects stay absent.

### The semantic element vocabulary

A `SemanticNode` sits ABOVE markup. Routes, properties and indexed properties
return these instead of building markup, and each element projects itself into
every output format through an ordinary `Base.show(::IO, ::MIME, ::Element)`
method — so HTML, Hyperview HXML, Markdown and plain text are **peers**, none
derived from another by translation. Elements nest, and a child that is not an
element is shown through its OWN `show`, which is what lets a DynamicObjects
node or an AlgebraOfVega layer drop in with no registration at all.

| Element | Holds |
|---------|-------|
| `SemanticProse(markdown)` | A run of prose, authored as Markdown |
| `SemanticFields(; facts...)` | Labelled facts |
| `SemanticTable(source)` | Any Tables.jl-compatible source |
| `SemanticPlot(layer)` | A plot as its specification, normally an AlgebraOfVega layer |
| `SemanticMetric(label, value; unit="")` | One labelled measurement, unit kept as data |
| `SemanticStatus(state; detail="")` | A state, not a colour |
| `SemanticUnavailable(reason)` | A declined computation, and why — not a state |
| `SemanticLink(label, target; external=false, code=false)` | A navigation target (`external=true` opens a new tab with a `↗` marker; `code=true` keeps an identifier label as code) |
| `SemanticAction(label, target)` | An operation offered to the reader |
| `SemanticArtifact(name, mime, bytes=nothing; target=nothing)` | A downloadable payload |
| `SemanticCode(language, text; anchor="")` | Source code, language kept as data |
| `SemanticSection(title, children...; anchor="")` | A document division — opens a heading level |
| `SemanticCard(title, children...; anchor="")` | A self-contained titled summary |
| `SemanticGroup(children...)` | An untitled run of siblings |
| `SemanticDisclosure(summary, children...)` | Content the reader opens |
| `SemanticAlternatives(default, ("label" => view)...)` | Several views of one content; the default renders, the rest collapse |

Six of these — `SemanticMetric`, `SemanticStatus`, `SemanticUnavailable`,
`SemanticLink`, `SemanticAction`, `SemanticArtifact` — are the ones that pay,
because HTML has no element for them. Written as markup, their meaning gets
buried in a `<span class="badge">` or an `hx-*` attribute that no other format
can read back out; held as data, a metric keeps its unit and a status keeps its
state in every projection.

`SemanticStatus` and `SemanticUnavailable` are the pair most often confused, and
picking the wrong one is a lie the type system cannot catch. A **status** is a
state the system is IN — running, converged, blocked, failed. An
**unavailability** is a computation that was DECLINED: the diagnostic does not
apply at this level, the summary needs draws this fit never produced. Nothing is
warning, erroring or pending there, so every status symbol asserts something
untrue, and `SemanticStatus(:warn)` type-checks while saying the opposite of
what happened. Reach for `SemanticUnavailable(reason)` whenever the honest
sentence is "there is nothing here, and here is why" — the whole point of the
vocabulary is that this distinction survives into Markdown and plain text, where
a mis-chosen element cannot be recovered from.

Four points where a projection is deliberately not a translation of the HTML:

- **`SemanticAction` degrades to a plain link** outside HTML. No other format
  can express "swap this in place", and the target is the honest remainder of
  the meaning.
- **`SemanticDisclosure` is content the reader OPENS, not content that is
  hidden** — which is exactly why it cannot be an `h.details` wrapper around
  semantic children. HTML collapses it, but Markdown and plain text have no
  viewport to collapse into, so their correct projection is the label followed
  by the whole body. Wrapping the children in markup instead would force the
  subtree down the HTML→Markdown path and lose every peer projection under it.
- **`SemanticProse`'s HTML peer renders its Markdown**, through
  [`render_markdown`](@ref) (CommonMark plus bare-URL linking), which escapes
  inline markup — so prose cannot smuggle HTML through. Its HXML peer is the
  source as plain text.
- **`SemanticAlternatives` projects its default view alone** outside HTML.
  Collapsed views have no text analogue, so Markdown, plain and HXML carry the
  default — the consent surface — and the alternatives' labels stay in HTML
  with the collapsed sections they head.

`SemanticTable` is gated by `Tables.istable`, not by a duck-typed
`propertynames` check: a `NamedTuple` of vectors, a `DataFrame` and a
`TreeArrays.TreeData` are tables; a `NamedTuple` of scalars, a scalar, a
`String`, a `Vector` and a `Dict` are not, and are shown through their own
projection rather than mangled into a spurious one-row table. Prefer passing the
richer source directly — materializing a `TreeData` into a `DataFrame` just to
render it loses information for nothing. The HTML projection delegates to
[`render_table`](@ref) with sorting and download off, since both are interactive
chrome rather than part of a semantic projection.

`anchor`, where present, becomes the HTML `id` — a document address, so an
element can be cited from elsewhere. An unaddressed element emits no attribute
at all rather than `id=""`.

Most elements project into the HTML element whose native rendering already
carries their meaning — `article` for a card, `section` for a division, `dl` for
fields, `details` for a disclosure, `pre`/`code` for code — which is why
HTMXObjects ships almost no CSS for them: Pico styles the element. So the audit
question for a semantic class is never *does it have CSS* but **does its HTML
element render as anything by itself** — and where the answer is no, a missing
rule is a bug rather than a deliberate default. **Two elements answer no**, and
[`htmxo_utility_styles`](@ref) supplies what their markup cannot. Both knobs are
CSS variables, so an app retunes them in its own scoped stylesheet, never
inline.

`SemanticGroup` is the **container** case: it has no counterpart element, so its
peer is a bare `div`, and **a group is a row that wraps.** Siblings share the
width and each keeps a minimum before the row breaks, so a pair of figures sits
side by side on a wide viewport and stacks on a narrow one, with nothing passed
at the call site.

`SemanticMetric` is the **inline** case: its peer is a `span` next to a
`strong`, and adjacent inline elements carry no separation of their own, so
**a metric is a label/value row with a gap.** Without the rule
`SemanticMetric("draws", 4000)` renders as the run-together `draws4000`, where a
reader cannot tell the value from a label that ends in a digit. The separator is
a gap rather than a literal colon in the markup: the text peers already say
`draws: 4000` in their own idiom, and keeping punctuation out of the HTML leaves
label and value independently styleable and scrapeable without stripping it back
off. A metric is deliberately **not** projected into `dl`/`dt`/`dd` — that peer
belongs to `SemanticFields`, and one HTML peer for both would erase the
distinction between labelled facts in a list and a single measurement whose unit
is data.

Layout is an HTML-only affordance — the same reason a disclosure collapses only
in HTML — so the Markdown and plain-text peers of both are unchanged: a group
projects there as its children in sequence and a metric as `**label:** value`,
either way.

```css
.my-app-wide-run { --htmxo-semantic-group-min: 30rem; --htmxo-semantic-group-gap: 2rem; }
.my-app-airy-metrics { --htmxo-semantic-metric-gap: 1rem; }
```

An app wanting a figure-over-caption metric sets `flex-direction: column` in
that same scoped stylesheet.

### What the compiler reads from a descriptor

`property_descriptor`, `property_descriptors` and `static_domain` are
**re-exported from DynamicObjects** — the descriptor schema itself is
DynamicObjects'. What follows is the other half of the contract: which of those
descriptor keys HTMXObjects' form compiler actually consumes, and what each one
does to the generated UI. A key not listed here has no rendering effect.

There is no authored-metadata macro. DynamicObjects **reflects** ordinary
fields, property signatures, inferred dependencies, result annotations,
`Bool`/`Enum` types and cache markers directly, so a descriptor is derived from
the declaration you already wrote. The single thing reflection cannot prove — a
finite domain that the type does not imply — is declared with
`@options <parameter> = <domain expression>`, as in the examples above. One
declaration covers **every** operation taking that parameter name.

(`@semantic`, `option_descriptor` and `dynamic_domain` were removed in
DynamicObjects `9490b55`. A stale `@semantic` block is a loud error at macro
expansion, not a silent no-op.)

For an ordinary route argument, **only the declared domain is merged into the
rendered control** — the rest comes from the route declaration. Effective
fixed-field `kind=:context` inputs instead carry their type/default/domain and
`source=(; type, property)` from the fixed field descriptor; HTMXObjects uses
that source to resolve, deduplicate, render, validate and rebuild the mounted
target. An option-backed `@param` is also `kind=:context`, with
`context_scope=:request`: its declaring property supplies the live domain and
shared-control identity, while submission continues through `@param` request
extraction rather than remaking fixed object state.

So, to answer the obvious question directly: help text, units and ordering are
**not** declarable, and there is no effect/side-effect policy key at all. A
control's label is the argument's documentation, not a separate declaration:
write it in the route docstring's `# Arguments` section, as below.

#### Injected inputs — the `internal` flag

`@get`/`@post`/… prepend `__verb__::HTMXObjects.Verb{V}` to the routed
property's signature so verb dispatch is a method-table lookup. DynamicObjects
is deliberately verb-agnostic — `property_signature` "returns *every*
positional arg, including any framework-injected leading arg" — so a raw
`DynamicObjects.property_descriptor(T, prop).inputs` reports that argument as
an ordinary positional with an unrestricted domain, **ahead of** the
operation's own parameters.

Every descriptor HTMXObjects itself hands back — `semantic_descriptor`'s node
`properties` and each route's `property` — therefore annotates each input with
an additive `internal::Bool`. A consumer enumerating what a route *requires*
filters on that flag rather than on the argument's name:

```julia
declared = [input for input in route.property.inputs if !input.internal]
```

For a descriptor read straight from DynamicObjects (the re-exported
`property_descriptor`, which reports the injected argument unmarked by design),
[`internal_input`](@ref) is the same predicate:

```julia
declared = [input for input in DynamicObjects.property_descriptor(T, :op).inputs
            if !internal_input(input)]
```

The argument is only ever *marked*, never dropped: the descriptor stays a
faithful account of the generated signature, and the verb is reachable as
`Verb{:GET}()` at any call site regardless.

| What you want to control | Where it actually comes from |
|--------------------------|------------------------------|
| Operation card title | The route's **docstring** — first non-empty line; falls back to a humanised property name |
| Control label | The param's doc as recorded by `reflect(T)` — for a route argument, its ``- `name`: Label`` entry under the route docstring's `# Arguments` heading; falls back to a humanised input name |
| Control order | Shared context discovery order, then route parameter declaration order — there is no ordering key |
| Which control is rendered | `domain` if present, else the declared Julia `type` — declare free-form prose as [`MultilineText`](@ref) for a `<textarea>` |
| Required marker / default | The declaration's own `required` / default value |
| Units | Not modelled. Put them in the param doc or the label |
| Execution transport | [`OperationPolicy`](@ref) at `route!` time — an app-level choice, not a per-operation descriptor key. Defaults to `:auto`; it governs every route under the app root, not just compiled operations; see [What the policy governs](#What-the-policy-governs) |

Two property-level keys do matter to the compiler: `role` must be `:operation`
(`semantic_app` rejects any discovered route whose descriptor says otherwise),
and a declared `output` of `HTTP.Response` / `MIMEResponse` keeps the operation
on the direct, non-polling transport regardless of policy.

### Domains and control selection

A domain is a `NamedTuple`. `static_domain(values; multiple, allow_custom)` is
the DynamicObjects constructor that normalises a list of values into one;
`@options` produces the other kind, which reflection reports **undecided**.
HTMXObjects reads these keys:

| Domain key | Meaning |
|------------|---------|
| `kind` | `:unrestricted` (or absent) falls back to the typed control; `:static` is a fixed option set; `:declared` is an `@options` declaration that HTMXObjects evaluates per request |
| `options` | Vector of option `NamedTuple`s (see below). **Empty for `:declared`** — see the next paragraph |
| `multiple` | Emits `multiple` on the select and accepts a vector on submit |
| `allow_custom` | Renders `sinput_custom` (datalist + free text) and **skips server-side domain validation** |
| `declaration` | `:declared` only — the recorded declaration: `parameter`, `expression`, `expression_string`, `dependencies`, `static`, `source`, `lnn` |

Reflection describes a **type**, and `@options` lowers to a lazily computed
property, so describing a type evaluates nothing: a `:declared` domain always
reports `options == NamedTuple[]` and `cardinality === nothing`. HTMXObjects
resolves it per request by calling
`DynamicObjects.property_options(object, parameter)` and normalising the result
through `static_domain`, carrying `multiple`/`allow_custom` across. That is the
only reason the option list ever has values — nothing pre-enumerates it.

Option values cross HTTP through [`option_wire_value`](@ref). The default uses
`value.key` when that property exists and otherwise preserves `string(value)`.
This lets a node-valued declaration such as `@options(model) = models` submit a
stable key like `bordet`, then recover the exact current `Model` node without a
`Base.parse` or `Base.string` shim. Extend `option_wire_value(::YourType)` when
the node's stable identity is not named `key`; the result must be unique within
each live domain. Generated controls, indexed mounts, query URLs, hidden inputs,
and server-side option recovery all use the same spelling.

A declared domain is evaluated against **the node**, so every name it reads must
be a property of that node. `@options dataset = choices(cohort)` requires
`cohort` to be a field (or otherwise a property) of the type declaring it — a
sibling argument of the same operation is not in scope and raises
`UndefVarError` at evaluation time. Promote such a dependency to a fixed field;
the `dependson` walk then also surfaces it as a `:context` input, so it is
submitted with the form and the node is remade with it before the domain is
asked.

`declaration.dependencies` with `static == false` additionally drives
**dependent refresh**: an input naming such a dependency re-fetches the form
when it changes, instead of executing the operation.

Each option carries `value` and `label`, plus optional `disabled` (rendered
disabled and excluded from validation), `help` (a `title=` tooltip on a
`<option>`, an inline suffix on a radio label) and `group` (groups options into
an `<optgroup>`).

Given a resolved domain the control is picked by this rule, in order:
`allow_custom` → `sinput_custom`; otherwise not `multiple` and at most
`radio_max` options (default 4) → a radio `fieldset`; otherwise a `<select>`.
Only with no domain, or `kind=:unrestricted`, does the input fall back to the
type-driven control: `Bool` renders a checkbox, a `Number` a number input,
[`MultilineText`](@ref) a `<textarea>`, and anything else — `String` included
— a single-line text input.

A `String` cannot carry a line break through a single-line input, so declare
free-form prose as `MultilineText`. The documented argument below renders as a
required `<textarea>` labelled "What looks wrong with this model":

```julia
@htmx struct ModelActions
    """
    Flag this model

    # Arguments
    - `note`: What looks wrong with this model
    """
    @post flag(; note::MultilineText) = record_flag(String(note))
end
```

The body receives a `MultilineText`, an `AbstractString` backed by a `String`,
with every submitted line break as `\n`. An optional argument defaults to
`MultilineText()` (Julia enforces the declared keyword type, so a bare `""`
default is a `TypeError`). A `MultilineText("…")` string-literal default
prefills the textarea; any other default expression leaves it blank, and a
blank submission uses the default.

```@docs
MultilineText
```

`operation_form(...; presentation=:cards)` is an explicit rich-presentation
override for finite, single-choice domains. It emits one native radio label per
option instead of applying the radio-count/select threshold. The option value
owns the rich card body by extending `semantic_card(value)` to return a
`SemanticCard(title, children...)`. Compose it with any of the other elements in
[The semantic element vocabulary](@ref): these values sit above markup and provide
peer HTML, Hyperview HXML (`application/vnd.hyperview+xml`), Markdown, and
plain-text projections. Two of those four are reachable through the mounted
route: a semantic node is exempt from markdown chrome-stripping, so the cards
render in a `?plain` / `?markdown` read even though they sit inside the
generated `<form>`. The response pipeline negotiates no
`application/vnd.hyperview+xml` arm, so the HXML projection is reached only by
`show`/`repr` on the node itself — requesting the route with that `Accept`
header returns the ordinary HTML page. Without a semantic card, the concise
option label is rendered as fallback content. Code languages are converted to symbols;
statuses accept any symbol, with distinct glyphs for `:ok`/`:available`,
`:warn`/`:blocked`, `:fail`, and `:pending`. HTMXObjects still owns the
radio's exact accessible name (the concise label), checked/disabled/required
state, visible help, stable wire value, native keyboard behavior, dependent
refresh, and `navigate=true` GET submission. Model-supplied card HTML is placed
beside the concise radio label in the generated card, rather than inside it, so
block content such as `article` and `pre` remains standards-compliant. Card
views should remain presentational: do not include links, buttons, inputs, or
other interactive controls that compete with the radio. HTMXObjects does not
truncate card content. Its associated label overlays the full card surface, so
clicking anywhere on the visual card selects the native radio without
JavaScript; the input remains directly focusable and keeps native keyboard
behavior. The overlay is part of `htmxo_utility_styles()`, auto-included by
`htmx()`; a hand-built page shell must include that style block itself.
`presentation=:auto` is the default and preserves the normal
heuristic above. Multiple and custom-value domains retain their existing
controls in either mode.

### Fail-closed contract

The four fail-closed cases are all `ArgumentError`, and all are raised **at
runtime, when you call `semantic_app` / `operation_form`** — that is, from
inside the route body that renders the surface. None is a macro-expansion or
precompile-time error, so a graph that compiles can still fail on the first
request that renders it.

| Case | Raised by | Message begins |
|------|-----------|----------------|
| Unselected indexed `@include` mount | `semantic_app` | `semantic_app cannot materialize child …` (`Indexed @include children need a selected index`) |
| Duplicate `(verb, path)` operation identity | `semantic_app` | `semantic_app found duplicate operation identity …` |
| Detached `@include` child (no `__parent__`) | `operation_form` | `operation_form on <T> cannot resolve …` |
| `@ws` route with the default renderer | `semantic_app` | `semantic_app has no default control for WebSocket operation …` |
| `@sse` route with the default renderer | `semantic_app` | `semantic_app has no default control for SSE operation …` |

Because they are ordinary route exceptions, they surface through the standard
response pipeline: an HTMX request gets **200** with the standard error article
and an `X-HTMXO-Error-Id` header, a non-HTMX request gets **500**. That is the
discriminator to recover against — not the status alone.

This is distinct from *submitted-value* failures. `HTMXObjects.MissingRequiredParam`
and `HTMXObjects.InvalidDomainValue` (raised when a form posts a value outside its
current domain) map to **400** on a non-HTMX request and render a `Bad Request`
article; under HTMX they too stay 200 with `X-HTMXO-Error-Id`. Neither type is
exported, so catching one needs the qualified name.

In short: **400 means the caller sent something wrong; 500 means the surface
itself could not be compiled.**

The detached-child case has one wrinkle worth knowing: the parent/child link is
registered by `route!`, and the check only fires when the route would actually
have inherited a parent-supplied `@param`. An unrouted app, or a child whose
operation needs nothing from its parent, renders standalone without complaint.

## Scoped root lifecycle

For a `semantic_app`, HTMXObjects automatically owns the keyed store, locking,
and root remounting. The default identity is `(root type, normalized mount
prefix)`, so the declaration and ordinary `route!(ModelApp())` call need no
lifecycle configuration.

`RootProvider` remains the explicit adapter for a non-semantic application or
a distributed/external store with an identity HTMXObjects cannot derive:

```julia
provider = RootProvider(
    scope=:job,
    key=req -> HTTP.header(req, "X-Job", "default"),
    retention=RootRetention(max_entries=64, ttl=3600),
)

route!(ModelApp(); root_provider=provider)
```

One source root is retained per `(root type, key)`. Every request receives a
same-type remount: request, route, prefix, params, and mounted-child context are
fresh, while unrelated model caches, in-flight work, mmap values, and indexed
subcaches retain their identity. `max_entries` applies LRU cleanup; optional
`ttl` is an idle timeout in seconds. Cleanup is opportunistic and removes only
the provider's reference, so work already holding a root can finish.

Outside `semantic_app`, `RootProvider()` remains fresh-per-request. The managed
store is process-local; use `RootProvider(factory; scope, key)` as the adapter
seam for a distributed or externally owned job/session store.

A retained root must still carry the current request: `_provide_root` rejects a
factory whose returned root does not. Retain the **payload** — a fitted model, a
dataset, a cache — never a mounted `@include` child, which belongs to the
request-scoped object graph.

Execution transport is a separate, app-level choice. You do not have to make it:
`route!` defaults `operation_policy` to `OperationPolicy(:auto)`, so the app
below already serves long routes without blocking the request task.

```julia
route!(ModelApp(); root_provider=provider)
```

Pass an explicit policy only to **tune** it or to **opt out**:

```julia
# tune the poller
route!(ModelApp(); operation_policy=OperationPolicy(; poll_interval="500ms"))
# opt out — a route surface that must answer inline
route!(ModelApp(); operation_policy=OperationPolicy(:blocking))
```

### What the policy governs

**The default is `:auto`.** An app that declares no `operation_policy` gets it,
and that is the whole configuration story: `OperationPolicy` exists to tune the
poller or to opt out, never to switch the good behaviour on. `:blocking` — the
historical transport, where a long route computes on the request task and the
response waits for it — is now reached only by asking for it. [`record!`](@ref)
is the one built-in caller that does: static export wants finished HTML, not a
poller written to disk.

"App-level" is literal, and it is the answer to the question this section is
otherwise easy to misread: the policy is stored per **root type** and threaded
into **every** route registered under that root — declared with `@options` or
not, inside the `semantic_app` graph or not. It is documented here because
`semantic_app` is where it usually first matters, not because it is scoped to
the compiler.

So a hand-written route that renders bespoke HTML into an htmx-targeted
fragment — a master/detail row detail, say — is governed by the policy exactly
like a compiled operation card is. It needs no declaration, no descriptor key,
and no hand-written poller.

Under `:auto` a route takes the polling transport when **all** of these hold;
otherwise it stays direct:

| Condition | Where it comes from |
|-----------|---------------------|
| The verb is `GET` | The poller issues GET refreshes, so mutations stay direct |
| The declared output is not `HTTP.Response` / `MIMEResponse` | A declared final response is returned as-is |
| The descriptor advertises `semantics.pending` | A Pending handle can exist; false for a fixed field or a `@fresh` one |

For an HTMX request, those conditions enter the polling transport directly.
For a browser navigation that accepts `text/html` and has a `__page__` wrapper,
`:auto` returns the composed page shell immediately. The
route region carries `hx-trigger="load"` and requests the same operation; that
fragment request then enters the ordinary grace/poll transport and replaces the
region with progress and, finally, the terminal fragment. Markdown/error
requests, API/curl requests, and routes without page chrome keep
their direct response.

Both the load URL and every capability-poll URL preserve the request-time
external prefix (`X-Forwarded-Prefix`), so the sequence remains under a
path-stripping reverse-proxy mount. `:polling` forces the polling transport on
eligible GETs; `:blocking` keeps every route direct.

A polling-mode route is *started* non-blockingly and answers within the grace
period (~0.1s) with a poller; an operation that finishes inside grace skips the
poller and returns its value directly. `polling_fetchindex` therefore remains
useful only for what the policy does not cover — a non-GET operation, a declared
final response, or a poller you want to shape by hand.

A hand-shaped poller under the default `:auto` policy must own the route's
transport by itself. Mark its wrapper route `@fresh @get`: `@fresh` makes that
route's descriptor non-pending, so the app-wide outer transport stays blocking,
while the route body re-runs on each inner poll to inspect the indexed
property's current state. The indexed property itself remains memoized and
coalesces the long-running work.

```julia
@fresh @get stage(name::Symbol) = polling_fetchindex(
    compute_steps, name;
    poll_url=query_url(__self__/"stage/$name"),
    label="Preparing $name",
) do result
    h.div(result)
end
```

Without the wrapper's `@fresh`, both transports are active: a slow inner
re-poll can cross the outer grace period and temporarily replace the shaped
Treebars fragment with HTMXObjects' generic interim poller. That presents as a
visible flip-flop between the two fragments. `OperationPolicy(:blocking)` also
avoids the conflict, but it applies to every route under the root type rather
than to this route alone.

Every emitted poller carries an independently generated, OS-random bearer
token. Keep it confidential. HTMXObjects binds the token to the original route,
typed arguments, and `RootProvider` scope/key, so a poll request reaches the
exact in-flight property even though the default provider constructs a fresh
root per request. Concurrent identical operations receive distinct,
non-enumerable tokens. A poll that cannot resume its operation — an unknown
token after a process restart, an expired entry, drifted arguments, or a
missing token — heals by re-executing a fresh operation with the poll
request's current args instead of failing: the token is a resumption hint,
and a healed request computes exactly what a fresh GET would. Successful
terminal rendering removes the retained operation immediately; a bounded
process-local registry expires abandoned or failed pollers.

A resolved `:auto` poll answers the result fragment in a select-matching
terminal node — no kept progress tree, no inspection chrome — and the
`htmx()` shell unwraps that node on swap, so the caller's target ends with
the bare result fragment. `keep_progress` does not change that: it governs
hand-shaped `polling_fetchindex` pollers (which keep their frozen tree for
post-hoc inspection), the direct-page replacement flow, and what a failed
`:auto` operation renders (the recorded error beside its open tree, rather
than a bare route-boundary article). To keep the finished tree below a
resolved `:auto` result, register the app with
`OperationPolicy(:auto; keep_terminal_tree=true)`: polled operations then
resolve through Treebars' done terminal — the result with the frozen tree
in a collapsed `<details>` — instead of the bare node. Operations that
finish within the grace budget still answer inline bare either way: no
poll, no tree. The kept tree is not bare-safe, so a route whose fragment
must be the direct children of a structural element keeps the default and
declares itself `@fresh @get`.

While loading, the interim poller swaps into the request's target and
transiently displaces its children. A first paint into a structural element
(`details` whose first child must be the `<summary>`, `table`/`tr`, `dl`,
`select`/`option`, `ul`/`li`) therefore shows the poller — not the shell
children — until the operation resolves; a fragment that self-polls on a
periodic trigger keeps its settled content while a re-fetch runs (the
interim diverts into the progress reporter beside it) instead. A route
whose fragment must be the direct children of such an
element and cannot tolerate the transient should declare itself
`@fresh @get` (blocking transport, no poller at all).

A documented route's auto poller carries no separate header label: the route
docstring's **first line** — the same summary that titles the route's semantic
operation card — renders **once**, as the live progress tree's own root. The
poller's badge label and interim header stay empty, so a long docstring never
repeats above the tree. Write that first line as a one-line human summary;
everything below it (the `# Arguments` reference included) stays API
documentation for curl callers and never reaches the status line. A docstring
that opens with a markdown heading sheds its `#` sigil; an undocumented route
falls back to its humanized property name for the badge and header.

Every `htmx()` page shell carries the Treebars stylesheet + script while the
Treebars extension is loaded, so pollers render quietly and terminalize with
no per-app wiring — ahead of `extra_head`, so apps can still override.
`treebars_assets=false` opts a shell out (the escape hatch for strict script
policies); a manual `extra_head` install alongside stays harmless but
redundant.

The progress tree is property-scoped. In generated DynamicObjects bodies,
source-visible `object.property` reads and `object.indexed(args...)` calls carry
the caller's progress node explicitly into the nested computation. Ordinary
Julia calls, constructors, arithmetic and loops remain ordinary: a property
read hidden inside a foreign helper is not attached to its caller. Use the
explicit DynamicObjects progress markers when that exhaustive/foreign-frame
instrumentation is intentional. No ambient or task-local progress context is
installed.

```@docs
RootProvider
RootRetention
OperationContext
OperationPolicy
```

## Preloading — `preload=true` and `@preload`

A click can start before it happens. `htmx()` loads htmx's
[`preload` extension](https://htmx.org/extensions/preload/), and the navigation
components take a `preload` keyword — `nav_sidebar`, `htmx_tabset`, `tabset`,
`htmxo_breadcrumb` and `hx_link`. `preload=true` requests a link's target once
the pointer has rested on it for 100 ms; any other extension trigger
(`"mousedown"`, `"preload:init"`, …) passes through as a string.

What a preload *does* is the route's decision:

| Route | The preload (`HX-Preloaded: true`) gets | The click that follows |
|-------|------------------------------------------|------------------------|
| unmarked | `204` before a root is built — no work at all | computes as usual |
| `@preload`, done within ~0.1 s | the fragment, `Cache-Control: private, max-age=10` | is answered by the browser cache |
| `@preload`, slower | `204`; the operation keeps running | joins that operation — its value when done, otherwise a poller on it |

```julia
@htmx struct App
    @preload @get summary(id::Int) = render_summary(load(id))  # cheap: browser-cached
    @preload @get posterior(id::Int) = fit_model(id)           # heavy: prewarmed and joined
    @get archive(id::Int) = archive!(id)                        # an action: never speculative
end
```

Mark only routes that are safe to run speculatively — reads, not actions. A
preloaded operation nobody clicks still runs to completion. Mutations are never
preloaded, marker or not.

Joining is scoped to the page that preloaded. `htmx()` includes
`preload_runtime_js`, which sends a random per-page `HTMXO-Client` id with the
page's same-origin GETs; a click joins only an operation preloaded under its own
id, route and typed arguments — the binding poll tokens use. Browser reuse is
scoped the same way (`Vary: HX-Request, HTMXO-Client`) and lasts
`HTMXObjects.PRELOAD_MAX_AGE[]` seconds (`0` keeps only the server-side join).
Unclaimed operations are dropped after two minutes, and the request-feedback
styling ignores preloads.

Only `hx-get` elements and boosted links send the client id. A plain
`<a href preload>` can use the browser-cache path but never joins a slow
operation. A recorded static site needs no marker: its fragments are plain files
the browser caches.

```@docs
HTMXObjects.PRELOAD_MAX_AGE
preload_runtime_js
```

## Forms and inputs

See the [Components catalog](components.md) for the full list with examples.

| Export | Returns |
|--------|---------|
| `post_form(url, children...; …)` / `get_form(url, …)` | Complete inline form with hidden inputs + submit button |
| `hidden_inputs(; key=val, …)`   | A `Vector{Node}` of `<input type="hidden">` elements    |
| `query_url(path; …)` / `@query_url`  | URL with encoded query string, type-safe                |
| `linput`, `sinput`, `sinput_custom`, `soption`, `rinput`, `ninput`, `cinput`, `tinput`, `ainput`, `radio_group` | Form input widgets (label, select, radio, number, checkbox, textarea, autocomplete, …) |
| `Long`                          | Label humanizer (`Long(:max_draws) == "max draws"`); the fallback label for an undocumented argument |
| `MultilineText`                 | Route-argument type for free-form prose; generated forms render it as a `<textarea>` |
| `tabset`, `tabset_styles`, `htmx_tabset` | Tab navigation widgets                            |
| `comparison_view`, `comparison_js`, `comparison_styles` | Selectable comparison columns, either inline tabs with a Compare dialog or shown directly inline, independently loaded and scrolling; see [components](components.md#comparison-view) |
| `nav_sidebar`, `status_badge`, `lazy` | Layout/state widgets                                  |
| `loading_indicator_script`, `request_feedback_*`, `show_when_script` | UX scripts injected into the page |

## Tables and captions

| Export | Returns |
|--------|---------|
| `render_table(rows; …)`   | Sortable HTML table with optional CSV download              |
| `sortable_table_js`, `download_table_js` | Companion scripts for `render_table`         |
| `master_detail_js` | Shared runtime for `master_detail_table`/`master_detail_pair` rows; auto-included by `htmx`, also carried by `sortable_table_js` |
| `master_detail_table(headers, roots; children, searchable, …)` | Hierarchical sibling sorting, ancestor-preserving search, keyboard branch/detail controls, and lazy details; see [components](components.md#hierarchical-master-detail-tables) |
| `CaptionSpec`, `render_caption`, `with_caption`, `caption_style` | Plot/table captions |

## Formatting

`fmt_time`, `fmt_bytes`, `fmt_number` — concise human-readable formatters.

## Theming & styles

HTMXObjects ships its own CSS variables and matches the host environment (raw Pico, VitePress) via a small set of bridges:

| Export | Purpose |
|--------|---------|
| `htmxo_theme()`           | The package's CSS-variable defaults — included automatically by `htmx()` |
| `pico_bridge()`           | Map `--htmxo-*` onto Pico's CSS tokens — also injected by `htmx()` when `pico_version` is set |
| `vitepress_bridge()`      | Map `--htmxo-*` onto VitePress's `--vp-*` tokens — for docs pages embedding HTMXO components |
| `htmxo_utility_styles()`  | Small set of `u-*` utility classes (`u-inline`, `u-w-full`, `u-text-success`, spacing scale `0..6`, …) used by built-in widgets, plus generic `[hx-*]` behavior conventions (`cursor: pointer` at rest, `cursor: progress` + dim while `htmx-request` is in flight) |
| `escape_html(s)`          | HTML-escape (`HTMX.escape`, 5 chars) — for hand-built HTML strings only; `h.*` escapes text + attrs itself, use `Raw` for trusted markup |
| `html_escape(s)`          | Minimal `&` / `<` / `>` escape — for hand-built HTML strings (never pre-escape a value passed through `h.*`) |

See [`htmxo-semantic-styling`](https://github.com/nsiccha/Claude/blob/main/skills/htmxo-semantic-styling/SKILL.md) for the project's CSS philosophy.

## Editor / Git integration

| Export | Purpose |
|--------|---------|
| `GitRepo(path)`        | Wrap a Git working tree as a `@dynamicstruct`-style object |
| `EditorRoutes`         | An `@htmx struct` of CRUD routes for editing files in a `GitRepo` |
| `editor_form`, `editor_styles` | Front-end widgets used by `EditorRoutes`           |

## Testing

See the dedicated [Testing](testing.md) page.

| Export | Purpose |
|--------|---------|
| `TestRoutes`             | Mount a selective, subprocess-isolated TestItems runner under an app route |
| `TestItemInfo`, `discover_test_items` | Parse names, tags, source locations, and adjacent Markdown descriptions without loading tests |
| `test_list`, `test_output`, `test_run!`, `test_run_all!`, `test_run_tag!`, `test_run_failed!`, `test_run_missing!`, `test_run_batch!`, `test_clear_cache!` | Render or drive the same runner used by the web UI |

## Gallery & static recording

For docs sites that want to embed a live or recorded HTMXObjects app:

| Export | Purpose |
|--------|---------|
| `GalleryItem(path)`            | `@dynamicstruct` wrapping one `.jl` example file (label, group, source, frontmatter) |
| `Gallery(gallery_dir)`         | Walks a directory of example files into a vector of `GalleryItem`s |
| `gallery_grid(items; ...)`     | Render a grid of cards (one per item) with section headings |
| `gallery_toolbar`, `gallery_controls_script` | Toolbar widget + JS for filter/group controls in the grid |
| `record!(app; record_dir, paths, full, hx, markdown)` | In-process recorder — drives `app`'s routes against the registered handlers and saves HTML / fragment / markdown variants |
| `RecordingRoutes`              | `@htmx struct` mountable under a docs build to drive `record!` from the running app |
| `RECORDING_STATE`, `RecordingState` | Internal state for the recording UI (queue, progress) |
| `MIMEResponse(content_type, body)` | Escape hatch for non-HTML route returns (JS, JSON, CSS, …). Bypasses `__page__` wrapping and the markdown/error branches of the response pipeline |

See the [`htmxo-gallery`](https://github.com/nsiccha/Claude/blob/main/skills/htmxo-gallery/SKILL.md) skill for the canonical wiring.

## Built-in route bundles

Drop-in `@htmx struct`s that ship with HTMXObjects and are mounted via `@include`:

| Export | Purpose |
|--------|---------|
| `TestRoutes`     | Test-runner UI (see Testing section) |
| `EditorRoutes`   | Git-backed inline file editor (see Editor section) |
| `SchemaRoutes` / `StructureRoutes` | JSON schema endpoint for an `@htmx` app's route tree (opt-in via `@include schema = SchemaRoutes(; root=T)`) |
| `OpenAPIRoutes` | OpenAPI 3.1 endpoint for an `@htmx` app's route tree (opt-in via `@include openapi = OpenAPIRoutes(; root=T)`) — see [OpenAPI](#openapi) |
| `SwaggerRoutes` | Version-pinned Swagger UI viewer for the app's OpenAPI document (opt-in via `@include docs = SwaggerRoutes(; spec_url="/openapi")`) — see [OpenAPI](#openapi) |
| `ReflectionRoutes` | Application architecture explorer plus deterministic descriptor and optional observation JSON endpoints |
| `SharedOpsRoutes`| Common HTMX ops (refresh, clear cache, …) reusable across apps |
| `RuntimeRoutes`  | Dev dashboard of in-flight and past requests with timings, and live job boards — see [Runtime dashboard](#runtime-dashboard) |
| `RecordingRoutes`| Static-recording driver (see Gallery section) |

### OpenAPI

`openapi(T; title, version, description, servers)` renders the route tree of
an `@htmx` app type `T` as an OpenAPI 3.1 document — plain data, directly
JSON-serializable. It reads the stable `reflect(T)` descriptors, so the
`reflect` contract is unchanged. A route docstring's first line becomes the
operation `summary` (the rest, minus any `# Arguments` section, becomes
`description`); path params keep their `{name}` spelling; GET/DELETE params
become `parameters` entries while POST/PUT/PATCH params become an
`application/x-www-form-urlencoded` `requestBody`. `@ws` and `@sse` routes are
skipped — OpenAPI has no WebSocket operation or event-stream response.

```julia
@htmx struct MyApp
    "List all widgets."
    @get widgets() = h.p("all")

    @include openapi = OpenAPIRoutes(; root=MyApp, title="My API", version="1.0.0")
end
```

This serves the document as JSON at `GET /openapi` (the mount prefix is
yours — mount wherever the document should live).

The human companion is [`SwaggerRoutes`](@ref): a version-pinned Swagger UI
viewer initialized against the document. Mount it next to the document
route:

```julia
@htmx struct MyApp
    @include openapi = OpenAPIRoutes(; root=MyApp, title="My API")
    @include docs = SwaggerRoutes(; spec_url="/openapi")   # → GET /docs
end
```

`spec_url` is explicit because the document's mount point is the consumer's
choice. Viewer assets load from a pinned CDN release (`swagger_version`,
`cdn_base` re-points air-gapped deployments at a local mirror).

```@docs
openapi
OpenAPIRoutes
SwaggerRoutes
```

### Runtime dashboard

`RuntimeRoutes` is a development view of what the server is doing right now and
what it did recently:

```julia
@htmx struct MyApp
    @include runtime = RuntimeRoutes()        # → GET /runtime
end
```

- **Running jobs** — a live Treebars board of every operation execution that
  outlived the `:auto` grace period, whether it continued in the background
  while its client polled or answered inline (POST/PUT/PATCH/DELETE,
  `OperationPolicy(:blocking)`, `@fresh` routes, declared `HTTP.Response` /
  `MIMEResponse` outputs, plain GETs without a page shell), plus work reported
  through `track_job!`: how long it has been running, how many requests
  started or joined the same computation, how many polls it answered, when a
  client last looked at it, and its live progress tree. The board polls
  `GET /runtime/jobs` and updates in place: new jobs appear, an expanded tree
  stays expanded, a finished job shows its outcome and leaves, and durations
  tick between polls; its *Pause* freezes it. A job nobody has polled for ten
  seconds is flagged *unwatched*: its page is gone, but the computation keeps
  running.
- **In-flight requests** — with their current age, request kind (page, HTMX,
  poll, WebSocket, SSE — the last two stay in flight for the life of the
  connection), the transport the operation layer chose, the matched route
  pattern and the thread pool handling them.
- **Route timings** — request count, errors, p50/p95/max and total handling
  time per route over the recorded history.
- **Recent jobs** (a board too, newest first) and **recent requests** —
  bounded histories with durations, outcomes and frozen progress trees.
- A process line: thread-pool sizes, running jobs against `:default` threads
  (highlighted when jobs outnumber compute threads and are time-sharing it),
  heap, GC time and free memory.

The view refreshes itself every two seconds (`RuntimeRoutes(; refresh="5s")`
to change; *Pause* stops it), `GET /runtime/snapshot` serves the same data as
JSON, and `POST /runtime/clear` forgets the history. The dashboard's routes are
`@fresh`, so they render inline on the request's own task and never queue
behind a saturated compute pool; its own requests and executions are left out
of what it shows.

Recording is independent of the server. Requests are recorded by
[`track_requests`](@ref), a plain HTTP.jl middleware
(`handler -> req -> response`) that `serve` installs outside its `middleware` by default
(`serve(; runtime_tracking=false)` opts out) and that any HTTP.jl server stack
can compose directly, e.g. `HTTP.serve(track_requests(router), host, port)`.
Jobs are recorded by HTMXObjects' own operation layer, whatever server
delivered the request: every execution is registered when it starts and shown
once it outlives the grace period, and one that crosses it as a poller is
handed to a watcher that stamps its outcome. A hand-rolled
`Treebars.polling_fetchindex` poller reports its compute through
[`track_job!`](@ref) by itself; call `track_job!` directly for other work you
start — an app's `Threads.@spawn`, a warm-up task.
Both ledgers are bounded (`configure_runtime!(; history_limit,
job_history_limit)`), process-local, and hold no headers, cookies or bodies;
request targets are stored with operation/page-load tokens and
credential-looking query values redacted. Follow-up polls are counted on their
job rather than stored as requests (`record_polls=true` keeps them).

Like `TestRoutes`, this is a development surface: mount it only where
developers can reach it.

#### Job boards on app pages

The same data drives per-user boards. [`runtime_jobs`](@ref) returns the jobs
as plain rows with their progress nodes; [`jobs_board`](@ref) renders them as a
live board (a Treebars board when Treebars is loaded, else a plain list) that
polls a route of your choice:

```julia
@htmx struct MyApp
    "Your running jobs"
    @fresh @get my_jobs() = jobs_board(; mine=__req__,
                                       poll_url=query_url(__self__ / "my_jobs"))
end
```

`mine=req` shows only the jobs started under the requesting session: jobs
record the scope of the [`RootProvider`](@ref) that served them and a salted,
in-process digest of its key (never the key itself), and a board matches
requests with the same `:session`/`:job` scope and key. Other sessions' jobs
never show unless the caller opts into the global view with `all=true`, as the
developer dashboard does. With the default `:request`-scoped provider every
request is its own session, so per-session boards need a session-scoped
provider. Serve the board from an `@fresh` route so it never queues behind the
work it shows.

Known limits: the ledgers are process-local and in memory, so they are empty
after a restart and per process in a multi-process deployment; an operation
that finishes within the grace period is a request, not a job; and a job has no
progress tree when DynamicObjects produced no substatus for it (an uncached
`@fresh` route) or Treebars is not loaded. Work started outside any request is
only visible when reported through `track_job!`.

#### Queued jobs

By default every operation that goes to the background starts computing at
once, so many heavy requests all run concurrently on the `:default` pool.
[`configure_job_queue!`](@ref) bounds that: with `max_running=n`, at most `n`
background computes run at a time and the rest wait in FIFO order, built on
DynamicObjects' `Deferred` executor hook. Waiting jobs show on the dashboard and
on job boards as `:queued`, with their position ("queued · #3"), and start as
earlier ones finish. A queued compute nobody has polled for `abandon_after`
seconds is abandoned before it starts and recorded as a failed job ("abandoned");
the next request for it starts afresh. Blocking executions are not queued.

```julia
configure_job_queue!(; max_running=2, abandon_after=60)
```

#### App-owned background batches

The public submission seam is the ordinary routed operation. Put the batch
computation on an indexed property, and let an ordinary `@get` read it and
return the result fragment. Under the default `OperationPolicy(:auto)`, an
in-process request with `"HX-Request" => "true"` starts that GET through the
configured queue and returns native progress while the work is unfinished.
Load Treebars to enable the progress transport.

For intentional startup or unattended work, disable abandonment explicitly:

```julia
configure_job_queue!(; max_running=30, abandon_after=Inf)
```

`Inf` applies process-wide, including browser-originated waiting jobs; running
jobs are never abandoned by this setting. The queue and retained roots are
process-local, so request/result files remain the application's restart and
recovery boundary.

[`examples/native_background_batch.jl`](https://github.com/nsiccha/HTMXObjects.jl/blob/devibe/examples/native_background_batch.jl)
is a complete synthetic example. Its heavy `batch_result(batch_id)` reads an
immutable request file and writes a result file; `@get result(batch_id::Int)`
renders its value. A lightweight manual POST delegates to that same GET:

```julia
@fresh @post submit(batch_id::Int) = dispatch(:GET,
    query_url("/result/$batch_id", __self__);
    headers=["HX-Request" => "true",
             "X-Forwarded-Prefix" => HTTP.header(__req__, "X-Forwarded-Prefix", "")],
    parent=dispatch_parent(__req__))
```

The POST itself stays inline and does only request acceptance/submission. Its
returned response contains the GET's native progress fragment. Save/validate a
new immutable request before dispatching; use a new batch identity when its
inputs change. Do not mark the heavy GET `@fresh` or declare its output as
`HTTP.Response`/`MIMEResponse`, since those select inline execution. Keep status
and job-board routes `@fresh` so they can answer while the workers are occupied.

Startup uses the same entry after registering routes, with no HTTP listener or
browser required:

```julia
# On the example's mounted graph, compile forms once to activate managed retention.
surface = semantic_app(root; values=(; batch_id=1))
route!(root)
response = dispatch(:GET, "/result/1";
                    headers=["HX-Request" => "true"])
```

Dispatch targets the **internally registered path**, including any actual
`route!(; prefix=...)` or `@include` mount. It does not traverse a reverse
proxy: `query_url(jobs/"execute"; id)` on a live request may contain an external
`/p/<app>` prefix that the internal router cannot match. For an internal
`/jobs/execute` mount, use `query_url("/jobs/execute", jobs; id)` and forward
`X-Forwarded-Prefix` separately as above; returned poll URLs retain the external
prefix. Also pass the cookies/headers required by an existing session provider's
key function. Startup must use the same intended provider key and mount prefix
as later requests; a different key selects a different retained graph. Explicit
POST body parameters must be passed as `query_url` overrides (§URL helpers).

Check both the response status and `X-HTMXO-Error-Id`: an HTMX error fragment can
have status 200. A successful progress response means submission, not batch
completion. Omitting the HX header under `:auto`, requesting static export, or
calling the heavy property directly does not select this queued transport.
`track_job!` records independently started work; it does not admit it to the
queue. A hand-shaped `polling_fetchindex` likewise does not by itself choose the
app queue's executor.

Repeat calls coalesce on the same retained graph and typed batch identity,
whether queued or running; successful results are memoized there too. A
`semantic_app` graph activates its managed provider when compiled; do that
before startup submission if no page has rendered yet. For a manual `route!`
app, use the scoped-root contract above instead. Poll tokens alone preserve
follow-up polling, not unrelated new submissions' computation identity. Bound
provider retention consistently with the required batch lifetime; `Inf` only
disables queue abandonment, not root eviction. Existing authored Treebars
progress can remain inside the indexed computation; no app-owned worker pool,
`Deferred` constructor or external admission layer is needed.

The focused acceptance in `test/native_background_batch.jl` demonstrates two
running jobs plus one FIFO waiting job, duplicate POST coalescing, result-file
completion without browser polling, and a finite-timeout abandonment control.
The concurrency bound counts background executions, not every transient inline
request shown by the runtime ledger.

```@docs
RuntimeRoutes
runtime_dashboard
runtime_jobs
jobs_board
track_job!
configure_job_queue!
track_requests
runtime_snapshot
runtime_tracker
RuntimeTracker
RuntimeRequest
RuntimeJob
configure_runtime!
clear_runtime_history!
```

## Route inventory, selection, and warming

One shared collection drives both halves of warming an app before it serves
live traffic — pre-listen compilation without executing anything, and
post-listen validation over real HTTP:

```julia
warm = select_routes(MyApp; verb=:GET, prefix="/agents")
precompile_routes!(MyApp, warm)  # safe pre-listen, never executes bodies
prewarm_routes!(base_url, warm)  # post-listen validation
```

| Export | Purpose |
|--------|---------|
| `reflect(T)` / `reflect(app)` | In-process route inventory: one `(verb, path, name, doc, params)` NamedTuple per route, mirroring what `route!` registers. `SchemaRoutes` serves this same inventory as JSON |
| `select_routes(routes; verb, prefix, names, pattern)` | Pure, stateless filter over the inventory (filters combine with AND); also accepts the app type directly. Returns the collection the two functions below consume |
| `precompile_routes!(root, coll=nothing)` | Pre-listen: `Base.precompile` each resolved handler body + argument parser. Reports `(verb, path, name, precompiled)` per route; bodies never run |
| `prewarm_routes!(base_url, coll; include_post=false)` | Post-listen: one real request per resolved route. Reports `(verb, path, name, url, status, error)` per route; non-`GET` routes are skipped unless `include_post=true`, failures never throw |

Collections also accept ergonomic shorthands wherever they go: concrete
`"/url"` strings (exact segments beat `{param}` placeholders), `:route_name`
symbols, and `Regex`es over paths. Zero-match entries throw an
`ArgumentError`, so a stale warm list fails loudly instead of warming
nothing. `{param}` templates are concretized with boring type samples for
requests — pass concrete URLs for an exact warm of id-lookup routes.

## In-process dispatch

`dispatch` runs one request against the registered route tree in-process
and returns the handler's `HTTP.Response` — the same status, body, and
headers a loopback request would see, with no listener, no socket, and no
serialization round-trip. `route!` must have registered the app first
(exactly as for `record!`):

```julia
route!(MyApp())
resp = dispatch(:GET, "/figure/qoi"; headers=["Accept" => "text/markdown"])
resp.status == 200 || error("embed failed: $(resp.status)")
markdown = String(resp.body)
```

| Argument | Shape |
|----------|-------|
| `method` | A `Verb` (`Verb{:GET}()`), `Symbol` (`:GET`), or `String` (`"GET"`, case-insensitive) |
| `url` | An app-relative target (`"/plot/x?plain=1"`); absolute URLs keep path + query, fragments strip |
| `headers` | A `Vector` of pairs, a `Dict`, or a `NamedTuple` |
| `body` | A `String` or `Vector{UInt8}` (for `POST`/`PUT`/`PATCH` routes) |
| `parent` | An optional Treebars progress node the route's compute hangs under |
| `static` | An optional `StaticExport` spec: this one request runs blocking and comes back in static form ([below](#request-scoped-static-export)) |

The request resolves through the live router, so `:index` collapse, verb
dispatch, path/query/body extraction (including repeated-key vectors), the
response pipeline (`Accept` negotiation, `?plain`/`?error` shapes,
`__page__` wrap), and the error pipeline (per-error log file plus the
`X-HTMXO-Error-Id` header) all behave exactly as over loopback.
Unmatched targets return the router's own 404/405 responses rather than
throwing, so `(resp.status, String(resp.body))` is the complete fetch
contract — the same shape `HTTP.get(...; status_exception=false)` yields.

`parent` exists for callers assembling a larger job in-process — a PDF
export fetching embeds, a batch warmup: the route's compute nests under
the caller's node instead of rooting a fresh `__status__` tree. Without it
the execution roots its own tree, exactly as over loopback. Scoped-root
(governed) and polling-mode executions attach best-effort after the fact;
when no progress node exists to attach (an uncached `@fresh` route),
`dispatch` warns rather than returning a silently unparented response.

`dispatch_parent(req)` reads that node back inside a route body (`__req__`
is the live request): `parent=dispatch_parent(__req__)` on a nested
`polling_fetchindex` hangs the nested compute under the dispatch caller.
With Treebars' ambient dispatch-parent protocol a bare nested poller
resolves the caller on its own; the explicit one-liner stays the portable
spelling (older Treebars, and a spawned route body on Julia 1.10). Route
bodies that run no nested polling need nothing: the route's own execution
already parents automatically. Off `dispatch` the accessor returns
`nothing`, so the kwarg is a no-op on ordinary requests.

Serve-time middleware (the access log, Revise, `serve`'s `middleware`) does
not run: `dispatch` resolves at the router, beneath the middleware stack.

### Request-scoped static export

`dispatch(...; static=StaticExport(...))` hands back one route's response in
static form, from inside a live server, without `record!` and without
re-registering anything. For that request only, execution is forced blocking
(never a Treebars poller or page-load placeholder) and the static transform is
applied to the route's value before serialization — after the `__page__` wrap
for a full-page request, so the page chrome is rewritten too. Nothing is written
to disk: the caller writes the returned body wherever it wants. Registration,
operation policies, and `record!`'s global state are neither read nor changed,
so ordinary requests served concurrently behave exactly as before.

```julia
figure_target(url) = startswith(url, "/report/figure?") ?
    "embeds/" * embed_name(url) * ".html" : nothing
spec = StaticExport(; url_map=figure_target, controls=:remove)
resp = dispatch(:GET, "/report/figure?doc=a&name=qoi";
                headers=["HX-Request" => "true"], parent=job, static=spec)
resp.status == 200 || error("embed failed: $(resp.status)")
write(joinpath(bundle, "embeds", "qoi.html"), resp.body)
```

| `StaticExport` keyword | Meaning |
|------------------------|---------|
| `url_map` | `nothing`, or `address -> target`. Called with the full value of every `hx-get`, `href`, and `src` (query included). A `String` replaces the attribute verbatim — relative targets such as `"embeds/qoi.html"` are emitted as given — and the element stays live; `nothing` takes the default rules; anything else throws. |
| `controls` | `:disable` (default) strips `hx-post`/`hx-put`/`hx-patch`/`hx-delete` and unmapped query-string `hx-get`s and greys the element out, as recording does. `:remove` drops those elements with their subtree, so the output carries no non-GET attribute and no greyed element. |
| `record_base` | Prefix the default rules prepend to rooted addresses an unmapped attribute keeps (`hx-get` under `<record_base>/hx`). Empty by default: unchanged. |

- **Fragments vs pages.** Send `"HX-Request" => "true"` for the bare fragment;
  without it the response is the full page (or the levels of the `__page__`
  chain the request owes), transformed as a whole.
- **Finished responses are refused.** A route that returns an `HTTP.Response`
  or `MIMEResponse` has no value to transform, so the call throws
  `StaticExportRefused` instead of returning live markup. Fetch such routes
  with a plain `dispatch`.
- **Markdown** (`Accept: text/markdown`, `?plain`) is forced blocking as well
  and returned as-is — it carries no attributes to rewrite.
- **Hand-rolled pollers decide their own `sync`.** HTMXObjects forces only its
  own operation transport. A route body that calls `polling_fetchindex`
  directly must block for an export too, or the export captures a live
  poller: `sync=wants_markdown(__req__) || static_export(__req__) !== nothing`.
- `parent=` works as for any dispatch: the blocking execution nests under the
  caller's node.
