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
| `route!(app)`            | Register all `@get`/`@post`/`@put`/`@delete`/`@ws` markers found in the struct on the Oxygen router |
| `Verb{V}`                | Singleton type threaded into route IPs as the first arg, lets one property host `@get`/`@post`/… simultaneously |
| `terminate()`, `serve()`, `staticfiles(...)`, `dynamicfiles(...)` | Re-exports from Oxygen for serving |

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
| `static_transform(...)` | Convert dynamic responses to static-friendly form                  |
| `hx_response(...)` | Build a response with HTMX-specific response headers (HX-Trigger, HX-Redirect, HX-Push-Url, HX-Refresh, HX-Reswap, HX-Retarget, HX-Reselect, HX-Location) |
| `hx_link(href, label; ...)` | Render a link that uses `hx-get` + `hx-push-url` (HTMX boost-style) |
| `htmx_or(htmx_value, full_value)` | Pick which to return based on `is_htmx(req)`                   |
| `safely(f; obj, req)` | Run `f()` and return an inline error widget if it throws — keeps a panel from crashing the whole page |

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

```@docs
htmx
HTMXObjects.pico_page
HTMLDocument
```

## Markdown / agent-readable responses

For routes that should serve an agent-readable Markdown view *and* an HTML view from the same handler:

| Export | Purpose |
|--------|---------|
| `wants_markdown(req)`  | `true` iff `?plain` / `?markdown` query param OR `Accept: text/markdown` / `text/plain` header is set |
| `wants_errors(req)`    | `true` iff `?error` query param is set                               |
| `markdown_response(...)` | Build a `text/markdown` response                                   |
| `html_only(...)` / `markdown_only(...)` / `HtmlOnly` / `MarkdownOnly` | Tag content for one rendering only |

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
Mounted `@param` context and declared defaults become hidden inputs. An indexed
`@include` is intentionally fail-closed until an index is selected—call
`semantic_app(app.models(:chosen))` to compile that concrete subtree.

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
| `semantic_app(obj; values, title, submit, render_operation)` | Compile a mounted graph into operation cards/forms and result targets |
| `operation_form(obj, name; …)` | Low-level generated form for one operation |

```@docs
semantic_descriptor
semantic_app
operation_form
```

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
`kind=:context` inputs instead carry their type/default/domain and
`source=(; type, property)` from the fixed field descriptor; HTMXObjects uses
that source to resolve, deduplicate, render, validate and rebuild the mounted
target.

So, to answer the obvious question directly: labels, help text, units and
ordering are **not** declarable, and there is no effect/side-effect policy key
at all.

| What you want to control | Where it actually comes from |
|--------------------------|------------------------------|
| Operation card title | The route's **docstring** — first non-empty line; falls back to a humanised property name |
| Control label | The param's doc as recorded by `reflect(T)`; falls back to a humanised input name |
| Control order | Fixed context source declaration order, then route parameter declaration order — there is no ordering key |
| Which control is rendered | `domain` if present, else the declared Julia `type` |
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
type-driven control.

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
| The descriptor advertises `semantics.pending` | True for any ordinary computed route body; false for a fixed field or a `@fresh` one |

For an HTMX request, those conditions enter the polling transport directly.
For a browser navigation that accepts `text/html` and has a `__page__` wrapper,
`:auto` returns the composed page shell immediately. The route region carries
`hx-trigger="load"` and requests the same operation; that fragment request then
enters the ordinary grace/poll transport and replaces the region with progress
and, finally, the terminal fragment. Markdown/error requests, API/curl requests,
and routes without page chrome keep their direct response.

Both the load URL and every capability-poll URL preserve the request-time
external prefix (`X-Forwarded-Prefix`), so the sequence remains under a
path-stripping reverse-proxy mount. `:polling` forces the polling transport on
eligible GETs; `:blocking` keeps every route direct.

A polling-mode route is *started* non-blockingly and answers within the grace
period (~0.1s) with a poller; an operation that finishes inside grace skips the
poller and returns its value directly. `polling_fetchindex` therefore remains
useful only for what the policy does not cover — a non-GET operation, a declared
final response, or a poller you want to shape by hand.

Every emitted poller carries an independently generated, OS-random bearer
token. Keep it confidential: possession authorizes polling that one operation.
HTMXObjects also binds the token to the original route, typed arguments, and
`RootProvider` scope/key, so a poll request reaches the exact in-flight property
even though the default provider constructs a fresh root per request.
Concurrent identical operations receive distinct, non-enumerable tokens.
Successful terminal rendering removes the retained operation immediately; a
bounded process-local registry expires abandoned or failed pollers.

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

## Forms and inputs

See the [Components catalog](components.md) for the full list with examples.

| Export | Returns |
|--------|---------|
| `post_form(url, children...; …)` / `get_form(url, …)` | Complete inline form with hidden inputs + submit button |
| `hidden_inputs(; key=val, …)`   | A `Vector{Node}` of `<input type="hidden">` elements    |
| `query_url(path; …)` / `@query_url`  | URL with encoded query string, type-safe                |
| `linput`, `sinput`, `sinput_custom`, `soption`, `rinput`, `ninput`, `cinput`, `tinput`, `ainput`, `radio_group` | Form input widgets (label, select, radio, number, checkbox, textarea, autocomplete, …) |
| `Long`                          | Marker type for long-text fields                          |
| `tabset`, `tabset_styles`, `htmx_tabset` | Tab navigation widgets                            |
| `nav_sidebar`, `status_badge`, `lazy` | Layout/state widgets                                  |
| `loading_indicator_script`, `request_feedback_*`, `show_when_script` | UX scripts injected into the page |

## Tables and captions

| Export | Returns |
|--------|---------|
| `render_table(rows; …)`   | Sortable HTML table with optional CSV download              |
| `sortable_table_js`, `download_table_js` | Companion scripts for `render_table`         |
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
| `htmxo_utility_styles()`  | Small set of `u-*` utility classes (`u-inline`, `u-w-full`, `u-text-success`, spacing scale `0..6`, …) used by built-in widgets |
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
| `SharedOpsRoutes`| Common HTMX ops (refresh, clear cache, …) reusable across apps |
| `RecordingRoutes`| Static-recording driver (see Gallery section) |
