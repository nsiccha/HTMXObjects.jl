# Components catalog

Quick reference for the form helpers, widgets, tables, and layout pieces. Each entry shows the signature and a minimal usage snippet — drop them into a `@get` route body.

The `nv` argument that appears throughout is a **name-value pair** — usually a `NamedTuple` like `(; mu=0.0)` or `(; method="default")`. The widget uses the field name as the input `name` and the field value as the default — so a `<form>` POST round-trips cleanly back to a `formdata`-decoded NamedTuple of the same shape.

## Form inputs

### `linput` — labelled text input

```julia
linput((; name="World"))            # Long-name placeholder, hits /name
linput((; name=""), "Type a name")  # explicit placeholder
```

### `sinput` — labelled `<select>`

```julia
sinput((; method="A"), ["A", "B", "C"])
sinput((; method="A"), ["A" => "Method A", "B" => "Method B"])  # value => label
```

### `sinput_custom` — `<select>` with a "custom value" option

```julia
sinput_custom((; level="info"), ["info", "warn", "error"]; placeholder="other…")
```

### `soption` — single `<option>`

```julia
h.select(soption("a"; selected_value="a"), soption("b"))
```

### `rinput` — range slider with read-out

```julia
rinput((; alpha=0.5); min=0, max=1, step=0.01)
```

### `ninput` — number input

```julia
ninput((; n=10); min=1, max=100, step=1)
```

### `cinput` — checkbox / switch

```julia
cinput((; verbose=true))
cinput((; dark_mode=false); switch=true)         # Pico-styled switch
```

### `tinput` — multi-line `<textarea>`

```julia
tinput((; notes=""); rows=4)
```

### `ainput` — auto-input (bare `<input>`)

```julia
ainput((; q=""); type="search", placeholder="Search…")
ainput("q"; type="search")                       # bare name version
```

### `radio_group` — radio buttons

```julia
radio_group((; method="A"), ["A", "B", "C"])
```

### `Long`

A marker type that turns a `Symbol` field name into a human-readable label (`(:plot_height_mm,)` → `"Plot height (mm)"`). Most widgets accept `label=Long(nv)` as a default — pass an explicit string to override.

### `show_when=` kwarg

All widgets accept `show_when="otherfield=othervalue"` — emits a tiny client-side script (`show_when_script()`) that hides the input until another widget's value matches. Drop `show_when_script()` once per page (typically in your `__page__`).

## Forms

### `post_form(url, children…; …)` / `get_form(url, children…; …)`

A complete inline form with hidden inputs and a submit button.

```julia
post_form("/respond/$slug/approved";
    label="Approve",
    btn_class="btn btn-success",
    hx_target="#list",
    hx_swap="innerHTML",
    msg="APPROVED",          # any extra kwarg → hidden input
)
```

`get_form` is identical but uses `hx-get`. Positional `children` are inserted between the hidden inputs and the submit button (so you can put visible widgets in there).

### `hidden_inputs(; key=val…)` — splat the hidden fields directly

```julia
h.form(; hx_post="/foo", hx_target="#list", hx_swap="innerHTML")(
    hidden_inputs(; script=path, worktree=wt)...,
    h.button(; class="btn", type="submit")("Go"),
)
```

### `query_url(path; key=val…)` and `@query_url`

```julia
query_url("/results"; q="hello", limit=10)
# "/results?q=hello&limit=10"

@query_url(/results; q, limit)         # captures locals; macro form
```

## Tables

### `render_table(rows; …)` — sortable HTML table with optional CSV download

```julia
render_table([
    (id=1, name="Alice", score=92),
    (id=2, name="Bob",   score=88),
];
    columns = [:id, :name, :score],
    download = "scores.csv",
    sortable = true,
)
```

Drop `sortable_table_js()` and `download_table_js()` once per page (typically inside `__page__`) to enable the client-side sorting and CSV download.

## Layout / widgets

### `tabset` and `htmx_tabset` — tab navigation

```julia
tabset(
    "Overview" => h.div("Overview content"),
    "Details"  => h.div("Details content"),
    "Logs"     => h.div("Log content"),
; active=1)

# HTMX-driven (each tab fetches its content lazily)
htmx_tabset(
    "Overview" => "/tab/overview",
    "Details"  => "/tab/details",
)
```

Drop `tabset_styles()` once per page to style the active-tab indicator.

### `nav_sidebar`

A vertical navigation panel — pass a vector of `("Label", "/url")` pairs (or `Pair`-of-`String`-with-children for nested groups).

### `status_badge` — colour-coded status pill

```julia
status_badge(:ok)            # green
status_badge(:warning)       # amber
status_badge(:failed)        # red
status_badge("custom"; class="bg-blue-500 text-white")
```

### `lazy(url, content…; tag=h.div, swap="outerHTML", …)` — lazy-load on view

```julia
lazy("/heavy_panel/42"; tag=h.section, id="heavy")
```

Renders an empty container with `hx-get=…` + `hx-trigger="load"` so the panel populates once it scrolls into view (or immediately on page load).

### `loading_indicator_script()` and `request_feedback_*`

Drop once per page to enable a centred loading indicator and click-feedback styling on every HTMX-triggered element.

## Links and links-as-actions

### `hx_link(url, label; …)` — `<a>` that uses `hx-get` (HTMX boost-style)

```julia
hx_link("/settings", "Settings"; hx_target="#main", hx_push_url="true")
```

### `htmx_or(htmx_value, full_value)`

Use inside a route body when you want different content for an HTMX partial vs. a full page load:

```julia
@get index = htmx_or(
    h.div(id="main")(content),                  # HTMX partial
    __page__(h.div(id="main")(content)),        # full page
)
```

## Formatting

| Helper          | Example output                  |
|-----------------|---------------------------------|
| `fmt_time(2.5)` | `"2.5 s"` (auto-picks unit)     |
| `fmt_bytes(1572864)` | `"1.5 MB"` (auto-picks unit) |
| `fmt_number(1234567)` | `"1.23M"`                  |

## Editor widgets (Git integration)

`editor_form` and `editor_styles` are the front-end pieces of `EditorRoutes`. See the `EditorRoutes` source for the full route surface; in most apps you just `@include` `EditorRoutes` and drop `editor_styles()` once on the page.

## Captions

For figures / tables that need a caption with a CSV-download button or a "show data" details:

```julia
with_caption(plot_node, CaptionSpec(; title="Posterior fit", csv=download_url))
```
