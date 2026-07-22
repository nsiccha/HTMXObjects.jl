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

`auto`, `htmx`, `h`, `Node`, `@__str`, `HyperscriptString`. See the [HTMX.jl docs](https://nsiccha.github.io/HTMX.jl/dev/) for full details.

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
        @semantic (inputs=(model=(domain=static_domain((:base, :full)),),),) @get fit(; model::Symbol=:base) =
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

| Export | Purpose |
|--------|---------|
| `semantic_descriptor(obj_or_type)` | HTML-free hierarchical graph plus declaration-ordered, mount-resolved operation routes |
| `semantic_app(obj; values, title, submit, render_operation)` | Compile a mounted graph into operation cards/forms and result targets |
| `operation_form(obj, name; …)` | Low-level generated form for one operation |
| `OperationPolicy`, `RootProvider`, `RootRetention`, `OperationContext` | Execution transport and request/session/job root-provider contracts |

## Scoped root lifecycle

For the ordinary in-process case, HTMXObjects owns the keyed store and its
locking:

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

`RootProvider()` remains fresh-per-request. The managed store is process-local;
use `RootProvider(factory; scope, key)` as the adapter seam for a distributed or
externally owned job/session store.

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
