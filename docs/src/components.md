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

All form widgets accept `show_when=(field, op, value)` — emits `data-show-when-*` attributes that the client-side script (`show_when_script()`) reads to hide the input until another widget's value matches. Supported ops: `==`, `!=`, `startswith`, `endswith`. Drop `show_when_script()` once per page (typically in your `__page__`).

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

`get_form` is identical but uses `hx-get`. Positional `children` are inserted between the hidden inputs and the submit button (so you can put visible widgets in there). Pass them positionally: the returned form is a complete node, so calling it again later (`post_form(url; …)(extra...)`) appends `extra` after the submit button instead of inserting before it — collect conditionally-built widgets first and splat them (`post_form(url, rows...; …)`).

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

# Inside an @htmx/@dynamicstruct body, the macro resolves a property name
# directly to its route URL — same conventions as the `@get` markers:
@query_url results(; q="hello", limit=10)    # → query_url("/results"; q="hello", limit=10)
@query_url item(42)                          # → query_url("/item/42")
@query_url index                             # → query_url("/")
```

## Tables

### `render_table(table; …)` — sortable HTML table with optional CSV download

```julia
render_table([
    (id=1, name="Alice", score=92),
    (id=2, name="Bob",   score=88),
];
    download_filename = "scores.csv",   # filename for CSV download (download itself is true by default)
    sortable = true,                     # enables sortable column headers
)
```

Columns are auto-detected from the table (any `Tables.jl`-compatible source). Other useful kwargs: `id`, `caption`, `cell` (per-cell render override), `class` (default `"striped"`).

Drop `sortable_table_js()` and `download_table_js()` once per page (typically inside `__page__`) to enable the client-side sorting and CSV download.

#### Reading and restoring the sort state

`sortTable` marks the active `<th>` with both `data-sort-dir="asc"|"desc"` and
`aria-sort="ascending"|"descending"`, clearing both from the sibling headers.
`sortable_table_js()` also ships the accessor

```js
htmxoSortState(target) // -> {sort_col, sort_dir} | {}   (sort_col is 1-based)
```

where `target` is a CSS selector or element. An unsorted table yields `{}`, so
it spreads cleanly into an htmx `hx-vals`.

!!! warning "A `morph:` swap wipes a client-side sort"
    An idiomorph `hx-swap="morph:*"` re-imposes the server's child order on the
    `<tbody>` and removes any attribute the server did not render — so a user's
    column sort (rows **and** the caret) is silently wiped by the next swap. It
    is also idiomorph's worst case: a client-sorted DOM is maximally divergent
    from the server's order, so nearly every row must be relocated.

    Fix both by sending the sort state with the request and rendering rows in
    that order server-side:

    ```julia
    h.button("↻"; hx_get=string(__self__),
        hx_vals="js:{...htmxoSortState('#entries')}",
        hx_target="#entries", hx_swap="morph:outerHTML")
    ```

    Then, in the route (with `@param sort_col::Int = 0` and
    `@param sort_dir::String = "asc"`), sort the rows yourself and declare the
    order so the header agrees with it:

    ```julia
    sortable_table(headers, sorted_rows; id="entries",
        default_sort = sort_col == 0 ? nothing : sort_col => Symbol(sort_dir))
    ```

    `default_sort` **declares** the order (stamping `data-sort-dir` /
    `aria-sort` / the caret on that header); it does not sort `rows` for you.
    It forwards through `render_table` and `master_detail_table` too.

#### Client-side search {#table-search}

`searchable=true` on `sortable_table`, `render_table` or `master_detail_table`
adds a labelled search field above the table, a live "N of M rows shown" count
as the field's helper text (`role="status"`, `aria-live="polite"`) and a "No
matching rows" state below it:

```julia
sortable_table(["Party", "Category", "Amount"], rows; id="entries", searchable=true)
render_table(df; searchable=true, search_text=row -> "$(row.party) $(row.iban)")
```

The search matches a case-insensitive phrase against a row's visible cell text.
A row can replace that text with a `data-htmxo-search` attribute (in
`render_table`, with `search_text(row)`), for example to make metadata absent
from its cells searchable; it does not change sorting. `detail-<key>` companion
rows are neither matched nor counted: one hides with its master and reopens
when the master returns, and sorting a filtered table keeps the filter. The
field, count and empty state are left out of `?plain`/Markdown. Search needs
`sortable_table_js()` on the page.

App filters compose with the phrase search as named row predicates:

```js
// Checkbox: show only uncategorised rows, on top of the phrase search.
htmxoTableFilter('#entries', 'unassigned',
    checkbox.checked ? row => row.dataset.tac === 'Unassigned' : null);

// Regex mode: 'search' names the built-in phrase match, so this replaces it.
htmxoTableFilter('#entries', 'search', (row, ctx) =>
    !ctx.input || new RegExp(ctx.input, 'i').test(ctx.text));
```

`htmxoTableFilter(target, name, predicate)` accepts the table, its wrapper, an
element inside it or a selector; it registers `predicate(row, ctx)` (or removes
the name when `predicate` is `null`) and filters again. A row is shown when
every predicate returns `true`. `ctx` has `query` (normalised lower-case
phrase), `input` (the field's raw value) and `text` (the row's lower-case
search text, ancestor text included in a hierarchy). Each predicate runs for
every row on every pass, also when the field is empty.

The query and the registered predicates are kept per table `id` and page path,
like the [selection](#table-selection), so they survive a re-render of the
table: after an `outerHTML` swap (a bulk action, a tab switch away and back)
the re-rendered table's empty field takes the last query, and the table
filters as it loads with the predicates still registered. A value the
re-rendered field already holds wins. Registering a name again replaces it, so
content that re-registers its predicates when swapped in keeps working.
`htmxoTableSearch(target, query)` sets the query as if typed (`''` clears it)
and filters, for example to "show rows like this one" or to start over after a
bulk action; remove a predicate with `null`. A table without an `id` keeps this
state on its wrapper element, so a swap that replaces the table drops it.

Each pass fires a bubbling `htmxo:table-filtered` event on the wrapper. Its
`detail` holds `shown`, `total`, `query`, `hiddenBy` (hidden rows per predicate
that first rejected them) and `notes`, which a listener may extend; the count
line appends each note after ` · `:

```js
document.addEventListener('htmxo:table-filtered', e => {
    const n = e.detail.hiddenBy.unassigned;
    if (n) e.detail.notes.push(`${n} already categorized hidden`);
});
```

#### Row selection {#table-selection}

`selectable="<input name>"` on `sortable_table`, `render_table` or
`master_detail_table` turns keyed rows into a multi-select grid whose
selection a bulk form submits with no application script:

```julia
h.form(; id="bulk", hx_post=string(__self__ / "archive"))(
    h.button("Archive selected"; data_htmxo_needs_selection="rows", disabled=true))
sortable_table(["Party", "Amount"],
    [h.tr(h.td(t.party), h.td(t.amount); data_htmxo_select_key=t.id) for t in transactions];
    selectable="rows", select_form="bulk", searchable=true)
# The archive route receives one `rows` value per selected row.
```

- **Keys.** A row is selectable when it has `data-htmxo-select-key` (else its
  `id`); `detail-<key>` companions never are. `master_detail_table` keys every
  master row and submits its `key` unless `select_value(item)` says otherwise.
- **Interaction.** Click selects one row; Ctrl/Cmd-click toggles; Shift-click
  and Shift+↑/↓ (or Shift+J/K) select the shown range from the anchor; ↑/↓ or
  j/k move; Ctrl/Cmd+A selects every shown row; Escape collapses to the focused
  row; Space/Enter toggle it. Shift-click does not select text, and clicks on a
  row's own links, buttons, inputs, labels or forms keep their behaviour.
  "Shown" excludes rows the search hides. In a `master_detail_table` a row
  click selects, so the detail opens from the row's native detail control (the
  ▸ disclosure in a flat table, *Details* in a hierarchy, or the label with
  `detail_toggle=:label`).
- **Submission.** One hidden `<input name=...>` per selected row, valued by
  its `data-htmxo-select-value` (else the key) and associated with
  `select_form` through the HTML `form` attribute, so the table may live
  outside the form. `data-htmxo-select-submit="false"` (in `master_detail_table`,
  `select_submit(item) = false`) keeps a row selectable but unsubmitted.
- **Feedback.** A live "N selected (M hidden by the filter)" count with
  *Select all shown* and *Clear* sits above the table; in a tree it also notes
  selected rows inside collapsed groups ("3 selected (2 in collapsed groups)"). Controls marked
  `data-htmxo-needs-selection="<input name>"` are disabled while nothing would
  be submitted. Each change fires a bubbling `htmxo:selection-changed` event
  with `detail` `{name, keys, rows, submitted, hidden}`.
- **State.** Selection is keyed per input name, form and page path, not held
  by DOM nodes: it survives sorting, filtering, a row's `outerHTML` swap and a
  table re-render, and rows that leave the table leave the selection. A row an
  app re-renders on its own (a row action with `hx-target="closest tr"`) needs
  only its key: the replacement takes over that key's selection and the
  roving `tabindex`, and the focus when the row it replaced, or a control in
  it, had the focus. Rows
  rendered `aria_selected="true"` start selected. `htmxoSelectRows(target, keys)`
  replaces the selection (`[]` clears); `htmxoSelectedKeys(target)` reads it.
- **Semantics and theme.** `aria-multiselectable` on the table, `aria-selected`
  on rows, one roving `tabindex="0"`. Selected rows are tinted and the active
  row marked from `--htmxo-accent` in light and dark; set
  `--htmxo-selected-row` to change the tint.

## Layout / widgets

### Hierarchical master/detail tables

Supply roots and a `children` callback to build one searchable tree table:

```julia
master_detail_table(["Name", "Status"], roots;
    key = item -> item.id,
    master = item -> (h.td(item.name), h.td(item.status)),
    children = item -> item.children,
    detail_url = item -> isempty(item.children) ? item.detail_url : nothing,
    initially_open = item -> item.kind == :family,
    searchable = true,
    id = "catalog")
# Include sortable_table_js() and sortable_table_styles() once in extra_head.
```

Column buttons sort siblings and move each whole subtree, keeping open details
next to their master and preserving loaded DOM. For plain expanded group
headings and model-name detail controls, pass `branches_collapsible=false,
detail_toggle=:label`. Branches then have no disclosure control, while the
complete first-cell label becomes a native button. Supply non-interactive label
content in that cell; links or inputs can live in the other cells. Markdown
keeps that label and the column names; it drops the search field. Detail
expansion still follows `initially_open`; search and sort retain loaded DOM.
The defaults keep the branch triangles and a Details button on each row with a
detail. A flat table (no `children`) instead gives each such row a compact
disclosure triangle (▸ closed, ▾ open, named "Details") in its first cell,
beside the cell's content, which may be a link; the row click remains a pointer
shortcut. Every branch and detail control is a native button carrying
`aria-controls`/`aria-expanded`, so it supports keyboard activation, as do
auto-wired sort headers. Sorting, search and CSV export read the cell's content,
not its controls. `initially_open` accepts a Boolean or
predicate and controls both branch expansion and leaf detail expansion. Groups
without a detail body or URL have no companion or request. Keys must be unique
after sanitisation throughout the tree and page.

Search matches a case-insensitive phrase against visible master cells and
ancestor text. A matching group includes its descendants; a matching leaf
retains its ancestors. Search temporarily reveals matching paths, then restores
branch/detail state when cleared. Collapsed details stay lazy, and detail-body
text is excluded. Use `search_text = item -> item.searchable_metadata` to replace
a row's search text. Labels wrap without truncation. Without `children`, the
existing flat master/detail behavior remains available; `searchable=true` also
works on flat tables. The count, app predicates and `htmxo:table-filtered`
event are shared with every searchable table; see
[Client-side search](#table-search).

Deep collapsed trees get *Expand all* / *Collapse all* buttons with
`expand_controls=true` (requires collapsible `children`). They open or close
every branch; detail rows keep their own state and collapsed details stay
lazy. While a search is active they act on the matching paths: *Collapse all*
keeps only the matching rows and their ancestors (hiding what a matching group
would reveal), *Expand all* shows every match again, and clearing the search
restores the branches the user had open. The buttons carry `aria-controls`
for the table body and are left out of Markdown.

`master` may also return the whole row, `h.tr(cells...; attrs...)`, when its
attributes are computed together with its cells. The cells fill the master row
and the attributes stay on it, beside the table's own id, toggle and hierarchy
attributes, which the row may not set. A `semantic_app` layout uses this to
declare its buttons' shared wiring once per row; see
[Rows of a `master_detail_table`](api.md#master-detail-rows).

Lazy detail controls are initialized before the slot's `htmx:afterSwap` event
reaches page listeners. Generated forms can be submitted as soon as the detail
appears, including concurrent actions with separate result targets. The normal
`htmx:afterSettle` event still marks the end of visual settling; applications
need no fixed pause or manual `htmx.process` call for the inserted controls.

#### Regroupable tables {#table-regrouping}

`groupings` lets the reader regroup one set of leaf rows. Each grouping is a
name and a `leaf -> group key(s)` function; `nothing` is the flat view, and
the first grouping is the default. One route renders the table, another a lazy
group's rows, both through the same call:

```julia
groupings = ["None" => nothing,
             "Counterparty" => t -> t.party,
             "IBAN" => t -> t.iban,
             "Rule" => t -> matching_rule_names(t)]   # several keys: listed under each

transactions_table(self, group_by, q=""; group_rows=nothing) = master_detail_table(
    ["Counterparty", "Date", "Amount"], transactions;
    key = t -> t.id,
    master = t -> (h.td(t.party), h.td(t.date), h.td(string(t.amount))),
    detail = t -> h.p(t.memo),
    groupings, group_by, group_rows,
    group_by_url = self / "table",
    group_rows_url = (key, members) -> length(members) > 200 ?
        query_url(self / "rows"; group_by, key) : nothing,
    group_master = (key, members) -> (h.td(h.strong(key)), h.td(""),
        h.td(string(sum(m.amount for m in members)))),
    searchable = true, search_query = q, expand_controls = group_by != "None",
    selectable = "tx", select_form = "bulk")

@get table(; group_by::String="Counterparty", q::String="") =
    transactions_table(__self__, group_by, q)
@get rows(; group_by::String="Counterparty", key::String="") =
    transactions_table(__self__, group_by; group_rows=key)
```

- **Groups.** A grouping renders one collapsible branch per group key, in
  first-appearance order, with its leaves below. `group_master(key, members)`
  returns the group row's cells (default: the key and the member count).
  Controls in it, such as a rule-mode select, keep their own behaviour: they
  neither toggle nor select the group. Group rows sort among themselves by the
  same columns; leaves sort within their group.
- **The same leaves.** Leaf rows render through `master`, `detail` /
  `detail_url` and `master_attrs` as in the flat view. A leaf in several groups
  (a shared IBAN, a rule matching several counterparties) gets one row per
  group, each with its own id.
- **Group by.** With `group_by_url`, a *Group by* select joins the tree
  controls. A change GETs `group_by_url` with `group_by` and `q` (the current
  search) and swaps the table for the response. With `select_form` the select
  is associated with that form, so a bulk submission carries the active
  grouping. An unknown `group_by` throws an `ArgumentError`; validate it in the
  route.
- **Selection.** Keys are per leaf. Selecting a leaf selects every copy, it is
  submitted once, and the selection survives regrouping and the flat view.
  Group rows are selectable too and submit their key under
  `<selectable>_group` (here `tx_group=Shops`), so a bulk action can apply to
  whole groups; a group selection ends when the grouping changes.
- **Search.** A group row's text (its key and summary) is matched like any
  ancestor's, so search finds groups and leaves. `search_query` pre-fills the
  field after a regroup.
- **Lazy groups.** When `group_rows_url(key, members)` returns a URL, the
  group's leaves are not rendered. The group row carries the URL, its members'
  search text and (when selectable) their keys and submitted values. The first
  expand fetches the URL; the route renders the same call with
  `group_rows=key`, which returns a `<tbody data-htmxo-group-rows>` holding just
  that group's rows, and they join the current sort, search and selection.
  Until then a search matching a member keeps the group shown, with its toggle
  enabled so it can load; selected members stay selected and submitted; and
  *Expand all* loads every lazy group.

Markdown keeps the group and leaf rows and drops the controls. The
HTMXObjectsWeb gallery's *Regroupable table demo* (`web/src/regroup_demo.jl`)
runs this on synthetic transactions.

### `tabset` and `htmx_tabset` — tab navigation

```julia
tabset(
    "Overview" => h.div("Overview content"),
    "Details"  => h.div("Details content"),
    "Logs"     => h.div("Log content"),
; active=1)

# Lazy tabs: a URL is fetched on the tab's first click (the initially active
# one once it is visible); `preload=true` starts that fetch on hover
tabset("Overview" => h.div("Overview content"), "Details" => "/tab/details";
       preload=true)

# HTMX-driven (each tab fetches its content lazily)
htmx_tabset(
    "Overview" => "/tab/overview",
    "Details"  => "/tab/details",
)
```

Drop `tabset_styles()` once per page to style the active-tab indicator.

### `comparison_view` — tabs and selectable comparison columns {#comparison-view}

```julia
comparison_view(
    "Summary" => h.p("Complete summary"),
    "Source" => "/model/source",
    "Results" => "/model/results";
    id="model-views", active=1, selected=(1, 3))
```

The default `presentation=:tabs` shows one tab inline. **Compare** opens a
near-fullscreen dialog whose checkboxes select any subset of at least two
views. Selected columns stay side by side and scroll independently. Tabs
support ArrowLeft/ArrowRight, Home and End; Escape and Close dismiss the dialog
and return focus to Compare.

```julia
comparison_view(
    "Summary" => h.p("Complete summary"), "Source" => "/model/source",
    "Generated" => "/model/generated", "Results" => "/model/results";
    id="model-columns", presentation=:inline, selected=(2, 3, 4))
```

`presentation=:inline` shows the same checkboxes and the selected columns
directly in the page, with no tabs, Compare button or dialog. Unselected views
stay hidden in place. Select one or more views; a single selected pane fills
the available width. An initial single selection uses `selected=(2,)`.
The dialog presentation continues to require at least two selected views.
The comparison is limited to the viewport height
(`--htmxo-comparison-height`, default `100dvh`; subtract a sticky header with
`calc(100dvh - 4rem)` for a 4rem header), and each column scrolls independently. Nested fixed
`max-height` rules inside a column add a second, shorter scroll area.
`--htmxo-comparison-pane-width` (default `20rem`) is each column's minimum
width; wider selections scroll horizontally. `active` names the initial tab and
is refused with `presentation=:inline`.

In both presentations, URL bodies load independently when first shown, share
the master/detail single-flight loader, and allow retry after failure.
Selecting, deselecting and reselecting a view, or moving it into or out of the
dialog, retains its DOM, loaded content and user input. Supply eager content as
a node (`h.p("text")`); a string body denotes a fragment URL. `active` and
`selected` use 1-based indices; `id` must be unique on the page.
`htmx` includes `comparison_js()` and `comparison_styles()` automatically;
include both once for a hand-built page head. The application owns each
fragment route and its operation/result handling.

For parameter-free GET operations with fixed defaults, derive pane URLs from
the generated graph with `entry.title => (entry.object / entry.route.path)` in
`semantic_app`'s `render_operation` callback. The mounted owner carries selected
indices and the external prefix; bare `entry.path` is a reflected graph path.
This uses the same public URL recipe as `operation_form`'s default target.

A URL body GETs the supplied address; it does not submit changing shared
`semantic_app` controls. For custom placement of generated operations, pass
nodes containing `entry.form` and `entry.result` from `render_operation`, and
preserve the compiler's shared context controls with their original IDs. The
form keeps its generated submission wiring when moved into Compare. Showing
that node pane does not submit the form; its operation runs when submitted.

### `nav_sidebar`

A vertical navigation panel — pass a vector of `("Label", "/url")` pairs (or `Pair`-of-`String`-with-children for nested groups).

`nav_sidebar`, `htmx_tabset`, `tabset`, `htmxo_breadcrumb` and `hx_link` all take
`preload=true` to start a link's request while the pointer rests on it. Pair it
with `@preload` on the routes that should do something with that head start —
see *Preloading* in the [API reference](api.md).

### `status_badge` — semantic status pill

Renders a `<span>` whose class is picked from a small `state => "u-text-*"` map,
so colours come from the `--htmxo-*` CSS variables (no inline styles):

```julia
status_badge(:running)        # u-text-warning  "Running"
status_badge(:finishing)      # u-text-warning  "Finishing"
status_badge(:done)           # u-text-success  "Done"
status_badge(:failed)         # u-text-error    "Failed"
status_badge(:pending)        # u-text-muted    "Pending"

status_badge(:failed; label="Error!")                              # custom label
status_badge(:custom; classes=Dict(:custom => "u-text-accent"))    # custom palette
```

### `lazy(url, content…; tag=h.div, swap="outerHTML", …)` — lazy-load on view

```julia
lazy("/heavy_panel/42"; tag=h.section, id="heavy")
```

Renders an empty container with `hx-get=…` + `hx-trigger="load"` so the panel populates once it scrolls into view (or immediately on page load).

### `live_thread` — infinite, live-updating thread

A chat-style list for a growing, partly-mutable sequence (agent transcripts,
logs, comments): it starts at the newest item, pages older items in as the
viewer scrolls up, keeps the newest items live, and never re-renders what did
not change — so polling does not flicker, flash or move the page.

Items are `key => content` pairs, oldest first. Keys are stable and unique; the
component stores each item's key and a digest of its HTML, and the client
reconciles by key: identical items are not touched, changed items are morphed in
place (with [idiomorph](https://github.com/bigskysoftware/idiomorph) when the page
loads it, keeping `<details>` open state and focused inputs; otherwise replaced),
new items are inserted, vanished ones removed. The client holds the viewport
with its own scroll anchoring, sticks to the bottom while the viewer is there,
and otherwise counts arrivals in a "↓ N new" pill.

The server side is three routes. Declare them `@fresh @direct` — `@fresh` so
each request reads the thread now, `@direct` because the default `:auto`
operation policy would otherwise answer a slow render with an interim poller,
which the client reports as an error:

```julia
@fresh @direct @get index() = live_thread(latest_items();
    id="chat", older_url=__self__/"older", tail_url=__self__/"tail",
    cursor=oldest_key(),        # cursor for the page before these; nothing = no older
    since=last_final_key(),     # newest item that will never change again ("" if none)
    version=current_version())  # any token that changes whenever the thread does

@fresh @direct @get older(; before::String) =
    live_thread_page(items_before(before); cursor=oldest_key_or_nothing())

@fresh @direct @get tail(; since::String="", v::String="") =
    v == current_version() ? live_thread_unchanged() :          # 204: nothing to do
        live_thread_tail(items_after(since); since=last_final_key(), version=current_version())
```

- **Older pages** (`GET older_url?before=<cursor>`) return the items before the
  cursor and the next cursor (`nothing` at the start). Overlapping pages are
  fine; items the client already holds are skipped.
- **The tail** (`GET tail_url?since=<since>&v=<version>`) returns every item
  after the `since` key the client sent. The client reconciles exactly that
  region, so items there may change, be inserted mid-way, reorder or disappear;
  everything up to `since` is final and never revisited. Pick `since` as the
  newest item that can no longer change. When the route cannot honour `since`,
  answer `live_thread_tail(items; reset=true, cursor=…)`: the client reconciles
  its whole list (still by key) and restarts older paging.
- **Refresh now** after the viewer sends something: return
  `hx_response(…; trigger=live_thread_refresh("#chat"))` from the POST, or call
  `window.htmxoThread.refresh("#chat", {bottom: true})` from JS. `poll=nothing`
  makes a thread refresh only on demand (e.g. from a websocket message).

The runtime ships with every `htmx(...)` page (`thread=false` leaves it out;
`live_thread_assets()` adds it to other pages). New items are processed like an
htmx swap (scripts run, `hx-*` wired, `htmx:load` fires) and the thread root
emits `htmxo:thread-updated` after each change. Size the scroll box with
`height="40vh"` or `--htmxo-thread-height`. A runnable demo is
[`examples/chat.jl`](examples.md#chat).

### `loading_indicator_script()` and `request_feedback_*`

Drop once per page to enable a centred loading indicator and click-feedback styling on every HTMX-triggered element.
`htmx()` includes `request_feedback()` by default (`feedback=true`);
`loading_indicator_script()` is deprecated in its favour. Request feedback marks the requesting element
and the element htmx resolved as the request's target. That covers an inherited
`hx-target`, relative selectors such as `next .result` or `closest tr`, and an
`HX-Retarget` response.

## Links and links-as-actions

### `hx_link(url; …)` — `<a>` that uses `hx-get` (HTMX boost-style)

`hx_link(url; kwargs...)` returns a Node — append the link text via call syntax. `hx-target`, `hx-swap`, etc. pass through as kwargs.

```julia
hx_link("/settings"; hx_target="#main", hx_push_url="true")("Settings")
hx_link("/report/42"; hx_target="#main", preload=true)("Report")  # starts on hover
```

### `htmx_or(full_page_fn, req, fragment)`

Inside a route body, return `fragment` for HTMX requests and call `full_page_fn()` for direct browser navigation. Typically used with do-block syntax:

```julia
@get index() = htmx_or(__req__, content_fragment) do
    htmx(h.main(class="container")(h.h1("Hello"), content_fragment))
end
```

(`__req__` is a magic property on every `@htmx` instance — don't declare it
as a path param. Prefer defining `__page__(content)` and returning the bare
`content_fragment` — the response pipeline applies the `__page__` levels the
request actually needs, all of them on a direct visit and only the ones not
already on screen on an HTMX swap. See the response-pipeline section of the
manual.)

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
