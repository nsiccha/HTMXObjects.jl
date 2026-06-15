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
| `escape_html(s)`          | HTML-escape via Cobweb's escaper (handles entities) |
| `html_escape(s)`          | Minimal `&` / `<` / `>` escape — used inside generated JS strings |

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
| `TestRoutes`             | An `@htmx struct` you `@include` to mount a test runner UI under `/tests/` |
| `test_list`, `test_run!`, `test_run_all!`, `test_run_failed!`, `test_run_missing!`, `test_run_batch!`, `test_clear_cache!` | Underlying test runner functions (call directly or via the UI) |

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
