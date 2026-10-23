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

Columns are auto-detected from the table (any `Tables.jl`-compatible source). Other useful kwargs: `id`, `caption`, `cell` (per-cell render override), `class` (default `"striped"`). A float is written in the table's language and sorts by its exact value; see [Numbers in table cells](#table-numbers).

Drop `sortable_table_js()` and `download_table_js()` once per page (typically inside `__page__`) to enable the client-side sorting and CSV download.

The CSV holds the text each cell shows, except in a number cell, which exports its exact number (see [Numbers in table cells](#table-numbers)). A cell shown on several lines (a `<br>`, or block children such as `div` or `p`) exports one quoted field with those lines, so `h.td(h.strong("6,28"), h.br(), h.small("6,01–6,55"))` becomes a field holding the two lines `6,28` and `6,01–6,55`, rather than `6,286,01–6,55`. A header shown on two lines exports its lines joined by a space.

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

#### Column explanations {#column-explanations}

A `String` header is wired for sorting: a header button that sorts by click or
keyboard, `default_sort` by its label, the column name in `?plain`. A pre-built
`h.th(...)` node is used as-is and gets none of that. To explain a column
without giving up sorting, pass a `ColumnSpec` where the `String` would go:

```julia
master_detail_table([ColumnSpec("Model"; help="Select a model to compare its sources."),
                     ColumnSpec("Primal"; help="RK / Stan log-density time; below 1× RK is faster."),
                     "Flags"],
    roots; key, master, children, searchable=true, default_sort="Primal")
```

`help` becomes the header button's `title`, so it shows on hover and assistive
technology reads it as the button's description; a `ⓘ` marker after the label
shows that the column has one. The marker is HTML-only: `?plain` and the CSV
export keep the label alone. With `sortable=false` the explanation stays, as
the `<th>`'s `title`. `ColumnSpec` works in every `headers` vector of
`sortable_table` and `master_detail_table`.

#### Multilevel headers {#table-header-groups}

Use `header_groups` when adjacent columns share a heading. The ranges refer
to positions in the flat `headers` vector; columns outside a range span both
header rows. Sorting uses the leaf columns; CSV and Markdown flatten grouped
leaf names with their heading (for example `Primal / Ratio`):

```julia
master_detail_table(["Model", "Ratio", "Wren", "RKPPL",
                     "Ratio", "Wren", "RKPPL"], roots;
    key, master, children,
    header_groups=["Primal" => 2:4, "Gradient" => 5:7])
```

Each group spans at least two columns. Groups cannot overlap. The same option
works with `sortable_table`. If a leaf name repeats, use its 1-based position
for `default_sort` rather than the ambiguous name.

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
`sortable_table_js()` on the page. Their wording follows `texts=`
([Built-in texts](#table-texts)).

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

The count counts the table's items, not its rows. `{total}` is every item the
table lists, and `{shown}` those the search and the predicates keep, whether or
not their group or branch is open: with an empty field and no predicate it reads
"42 of 42", however many groups are collapsed. In a [regroupable
table](#table-regrouping) a group row is not an item, a leaf listed under several
groups counts once, and the leaves of a lazy group that has not loaded yet count
too, by the `'search'` predicate alone on their own text until they load. An
item-named count such as `count="{shown} von {total} Einrichtungen"` therefore
stays right in a grouped table.

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
`detail` holds `shown` and `total` (the count's numbers), `query`, `hiddenBy`
(hidden items per predicate that first rejected them) and `notes`, which a
listener may extend; the count line appends each note after ` · `:

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
  ▸ disclosure in a flat table, the leaf label in a hierarchy, or the ⓘ
  control when a link or child expansion needs the label).
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

#### Hover linking {#table-linking}

A page often shows the same items twice, as marks on a plot or map and as rows
of a table. `link="<group>"` on `sortable_table`, `render_table` or
`master_detail_table` puts the table in a link group: hovering an item in one
member of the group highlights it in every other member, with no application
script.

```julia
master_detail_table(["Probe", "Land", "P(anomaly)"], probes;
    key=p -> p.kenn, master=cells, detail=probe_fragment,
    groupings, searchable=true, link="probes")
render_table(summary; link="probes", link_key=r -> r.kenn)
```

- **Keys.** `master_detail_table` keys each item row by `link_key(item)`,
  which defaults to its `key` (as a string, not the sanitised row id),
  including every copy of a leaf that a regrouped table lists under several
  groups; group rows have no key. `render_table` keys rows by `link_key(row)`.
  Hand-built `sortable_table` rows carry `data-htmxo-link-key`, or are keyed
  by their `data-htmxo-select-key`. A detail row counts as its master. Keys
  compare as strings.
- **Several tables of the same items.** A `master_detail_table`'s `key` names
  its row and detail ids, so it must be unique on the page. When two tables on
  one page show the same items, keep each table's `key` unique and give both
  the same `link_key`:

  ```julia
  master_detail_table(headers, probes; key=p -> p.kenn, master=cells,
      detail=probe_fragment, link="probes")
  master_detail_table(headers, trending; key=p -> "trend-" * p.kenn, master=cells,
      detail=probe_fragment, link="probes", link_key=p -> p.kenn)
  ```

  `link_key` without `link` throws, since it would highlight nothing.
- **The event.** Hovering or keyboard-focusing a keyed row dispatches
  `htmxo:link` on `document` with `detail` `{group, key, source}`; when the
  hover ends, `key` is `null`. Every linked table listens for it and marks the
  rows of its group that hold the key (`data-htmxo-linked`). A plot or any
  other element joins the group by listening for the same event and
  dispatching it on its own hover; page script can call
  `htmxoLink(group, key)` (`null` clears). The latest key per group is kept in
  `window.htmxoLinkState`, so a table that is swapped in, regrouped or filtered
  later shows it too.
- **Hidden rows.** A highlight never changes the table. An item inside a
  collapsed group or branch lights up the innermost shown row above it, with a
  dashed outline and a note in its first cell, `↳ inside` or `↳ 2 levels down`
  (the `linked_inside` and `linked_deep` texts, below). That includes a group
  whose rows load lazily. A row that the search or a filter hides lights up
  nothing. A lit row that is out of view scrolls into view inside the table's
  own scroll box (an `overflow: auto` wrapper), never the page, and only when
  the hover started outside that table.
- **Theme.** Lit rows are tinted and outlined from `--htmxo-accent`; set
  `--htmxo-linked-row` to change the tint. The rules ship in
  `sortable_table_styles()`, and the runtime in `sortable_table_js()`.

#### Built-in texts in another language {#table-texts}

The words of a table's built-in controls come from one `texts=` keyword on
`sortable_table`, `render_table`, `master_detail_table` and
`master_detail_pair`. `table_texts(locale; overrides...)` builds them:
`:en` (the default) and `:de` are built in, and any single text can be
replaced:

```julia
const DE = table_texts(:de; search="Einrichtungen filtern",
    count="{shown} von {total} Einrichtungen", empty="Keine passenden Einrichtungen")
master_detail_table(headers, facilities; key, master, detail, searchable=true, texts=DE)
```

The texts cover everything these tables write themselves: the search field
(`search`, `count`, `empty`), the selection bar (`selected`,
`selected_filtered`, `selected_collapsed`, `select_all`, `clear_selection`),
*Expand all* / *Collapse all*, the accessible names of the ▸ and ⓘ controls
(`toggle_children`, `details`), the *Group by* select and its pills
(`group_by`, `group_add`, `group_add_inner`, `group_level`, `group_kept`,
`group_stop`, `group_earlier`, `group_later`), lazy-detail status lines
(`loading`, `retrying`, `load_failed`), the toasts of a lazy group that fails
to load (`rows_failed`, `rows_missing`), the CSV button (`csv`), the toggle
of the table's caption (`more`, the same word as `caption_texts`, see
[Captions](#captions)) and the note on a row that holds a hovered item in a
collapsed group (`linked_inside`, `linked_deep`, see
[Hover linking](#table-linking)). The `TableTexts` docstring names them all.

A text in braces is a placeholder: `count` takes `{shown}` and `{total}` (items,
not rows: see [Client-side search](#table-search)), the
selection texts `{count}`, the grouping texts `{name}` (and `group_level` also
`{level}`), `rows_failed` takes `{status}` and `linked_deep` `{levels}`. The browser writes the live count
and status lines from the same templates, so they are strings, not Julia
functions: the count changes on every keystroke without asking the server. An
unknown locale, text name or placeholder throws an `ArgumentError`.

A table with other texts than English carries them as one `data-htmxo-texts`
attribute on its outermost element; an English table is unchanged. Pass the
same `texts` wherever the table is rendered again (lazy group rows, row
updates, regrouping), and to the `sortable_table` that holds hand-built
`master_detail_pair` rows. Markdown and CSV output leave these controls out,
and a lazy detail's placeholder (`loading`) too: Markdown writes no detail
row (see [Details in Markdown](#master-detail-markdown)).

#### Numbers in table cells {#table-numbers}

A table writes its numbers in its language: `texts = table_texts(:de)` writes
`0,156`, `1.234.567` and `3,81·10⁻⁵`, the English default `0.156`,
`1,234,567` and `3.81·10⁻⁵`. Each number cell keeps the exact value, so the
table sorts by the number, not by the text (`parseFloat` would read German
`0,156` as 0), and the ⬇ CSV download writes the number (`3.81e-5`), which a
spreadsheet or R/Python reads.

- **By themselves.** A float in a `render_table` column, and a bare float among
  the cells `master` returns (`master_detail_table`, `master_detail_pair`),
  becomes such a cell, written with the table's own `texts`. Integers, Bools
  and text stay as written: an integer column is as often a year, an id or a
  postcode (`2024`, `10115`) as a count, which would read `2.024` and
  `10.115`. A custom `cell=` renderer writes its own content.
- **In cells you build.** `number_cell(x; texts, digits, sigdigits, attrs...)`
  returns the `<td>`, for `sortable_table` rows or a `master` cell that needs
  attributes; pass it the table's `texts`. `format_number(x; texts, digits,
  sigdigits)` returns the text alone.

```julia
const DE = table_texts(:de)
rows = [h.tr(h.td(f.name), number_cell(f.share; texts=DE, sigdigits=3),
             number_cell(f.count; texts=DE)) for f in facilities]
sortable_table(["Einrichtung", "Anteil", "Anzahl"], rows; texts=DE)
format_number(1234567.25; texts=DE, digits=1)   # "1.234.567,3"
```

How much is written:

- With neither keyword, every digit Julia prints: `0.15623` writes `0,15623`,
  `2.0` writes `2`. A float below 10⁻⁴ or from 10¹⁵ up (in absolute value)
  is a power of ten with superscript digits, `3,81·10⁻⁵`, which reads the same
  in HTML, Markdown, a `pdf_report` and a pasted copy.
- `sigdigits = 3` rounds to three significant digits first, as
  `round(x; sigdigits = 3)` does: `0,156`, `1.230.000`.
- `digits = 2` writes exactly two decimals (0 to 10), halves away from zero,
  the same way as a [group summary](#table-regrouping): `0,16`. It never
  switches to a power of ten.

`missing` and `nothing` write `–` (no sort key, an empty CSV field); `Inf`,
`-Inf` and `NaN` write `∞`, `-∞` and `NaN`. The cell carries its value twice:
`data-sort-value` for sorting and `data-htmxo-number` for the CSV. A cell you
build yourself can carry them too, for example a number with a unit:
`h.td("6,28 €/m²"; data_sort_value = string(x), data_htmxo_number = string(x))`
sorts by `x` and exports `6.28`.

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
By default, clicking a branch row opens or closes its immediate children;
clicking a nested branch does the same at the next level. A non-interactive
branch label is a native button for keyboard use, with the disclosure glyph
inside that label rather than in a separate button. A branch whose first cell
contains a link or other control keeps a separate triangle, so that control
retains its action. A plain leaf label is a native detail button with a
disclosure glyph. A linked leaf or a branch with its own detail keeps a small,
unfilled ⓘ control after its label; row clicks on branches open children, while
ⓘ opens the paired detail.
In a selectable table, row clicks select and the branch control opens children.
An app-provided `master_attrs.onclick` continues to override the row shortcut.
A flat table (no `children`) gives each detail row a compact
disclosure triangle (▸ closed, ▾ open, named "Details") in its first cell,
beside the cell's content, which may be a link; the row click remains a pointer
shortcut. Every branch and detail control is a native button carrying
`aria-controls`/`aria-expanded`, so it supports keyboard activation, as do
auto-wired sort headers. Sorting, search and CSV export read the cell's content,
not its controls. However narrow the first column, its controls stay on their
label's line: the cell never wraps between a control and its label, only the
label's own text wraps. To keep a label on one line, give its content
`white-space: nowrap`, not the cell. `initially_open` accepts a Boolean or
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

The branches the reader opened or closed are kept per table `id` and page path,
like the [search](#table-search) and the selection, so a re-render of the table
opens them again (a lazy branch loads its rows again).

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

A row clicked the moment a swap inserts its table still loads its detail: htmx
binds inserted elements only when the swap settles, so the expand binds the slot
itself first. An expand that sends no request (an `htmx:confirm` listener that
declines it, say) leaves the slot unlatched, and the next expand tries again.

#### Details in Markdown {#master-detail-markdown}

A `?plain` reader or a PDF from [`pdf_report`](api.md) cannot click a row open,
so the Markdown of a `master_detail_table` is the table of its master rows,
followed by each eager detail under its row's label in bold (the label's words,
without links or emphasis), in row order:

```text
| LB | Abschnitt |
| --- | --- |
| LB § 3.2 | AP 2 |
| LB § 5.1 |  |

**LB § 3.2**

detail for lb-3-2
```

- A detail row is never a row of the Markdown table, in every Markdown read: `?plain`,
  `Accept: text/markdown`, `to_markdown_string`, and an app type whose own
  `show(io, MIME"text/markdown"(), x)` hands the table to HTMX.jl.
- A detail whose Markdown is empty writes nothing: `nothing`, `html_only(…)`, or a
  form. So do lazy details (`detail_url`), which are not on the page, as
  `lazy(url)` writes nothing. Wrap a detail in `html_only` to keep it out of
  Markdown and PDFs.
- A captioned table's details follow its figure, and a leaf listed under several
  groups is written once.
- Hand-built `master_detail_pair` rows in a `sortable_table` lose their
  one-cell rows too, but their details are not written after the table. Use
  `master_detail_table`, or write the content after the table yourself.
- The HTML is unchanged, and `?error` still finds an error inside a detail row.

#### Regroupable tables {#table-regrouping}

`groupings` lets the reader regroup one set of leaf rows. Each grouping is a
name and a `leaf -> group key(s)` function; `nothing` is the flat view, and
the first grouping is the default. The browser regroups: every leaf is on the
page, and the *Group by* control rebuilds the groups there with no request, so
the table regroups the same way in a live app and in a page recorded with
`record!` and served as plain files:

```julia
groupings = ["None" => nothing,
             "Counterparty" => t -> t.party,
             "IBAN" => t -> t.iban,
             "Rule" => t -> matching_rule_names(t)]   # several keys: listed under each

transactions_table(group_by="Counterparty") = master_detail_table(
    ["Counterparty", "Date", "Amount"], transactions;
    key = t -> t.id,
    master = t -> (h.td(t.party), h.td(t.date), h.td(string(t.amount))),
    detail = t -> h.p(t.memo),
    groupings, group_by,
    group_summary = ["Amount" => ColumnSummary(:sum, t -> t.amount; digits=2)],
    searchable = true, expand_controls = true,
    selectable = "tx", select_form = "bulk")
```

- **Groups.** A grouping renders one collapsible branch per group key, in
  first-appearance order, with its leaves below. A group row shows the key and
  the member count, and in each column `group_summary` names, a
  `ColumnSummary` of the group's leaves: `:sum`, `:mean`, `:min`, `:max` of
  `item -> number`, `:count`, or `:ratio` of two sums (Σ demand / Σ capacity).
  A leaf whose function returns `nothing` or `missing` is left out. The
  browser computes the summaries again for every grouping the reader picks,
  rounded to `digits` decimals and written with the table's `decimal` and
  `thousands` texts (`texts = table_texts(:de)` writes `1.234,5`); the CSV
  download writes the same decimals as a number (`1234.5`). Group rows
  sort among themselves by the same columns; leaves sort within their group.
- **The same leaves.** Leaf rows render through `master`, `detail` /
  `detail_url` and `master_attrs` as in the flat view. A leaf in several groups
  (a shared IBAN, a rule matching several counterparties) gets one row per
  group, each with its own id.
- **Group by.** With two or more groupings a *Group by* select joins the tree
  controls (for a `group_by` list, pills: see
  [Nested levels](#table-grouping-levels)). A change regroups in the browser:
  the search, the selection, the sort and the groups the reader opened carry
  over, a group holding a leaf whose detail is open opens, and the table fires
  `htmxo:regrouped` with the new `group_by` values. With `select_form` the
  select is associated with that form, so a bulk submission carries the active
  grouping. An unknown `group_by` throws an `ArgumentError`.
- **Group rows from the server.** The browser cannot run two things: your own
  `group_master(key, members)`, whose group row cells may hold anything Julia
  renders (links, a rule-mode select), and lazy groups (`group_rows_url`),
  whose leaves are not on the page. For those, pass `group_by_url`: a route
  that renders the same call for the `group_by` and `q` (the current search) it
  receives. With `group_master` the browser regroups at once and then swaps in
  the server's render of the new grouping; with lazy groups a change asks the
  server straight away. In a recorded page, or without `group_by_url`, a
  `group_master` table still regroups in the browser, with default group rows
  (key, count and `group_summary`): the request for the server's render rides
  a hidden element, which recording strips, never the control. Lazy groups
  cannot regroup without a server: a recording greys their control out, and
  without `group_by_url` they get none.
  Controls in `group_master` cells keep their own behaviour: they neither
  toggle nor select the group. Validate `group_by` in the route:

  ```julia
  transactions_table(self, group_by, q=""; group_rows=nothing) = master_detail_table(
      ["Counterparty", "Date", "Amount"], transactions;
      key = t -> t.id, master = t -> cells(t), detail = t -> h.p(t.memo),
      groupings, group_by, group_rows,
      group_by_url = self / "table",
      group_rows_url = (key, members) -> length(members) > 200 ?
          query_url(self / "rows"; group_by, key) : nothing,
      group_master = (key, members) -> (h.td(h.strong(key)), h.td(rule_mode_select(key)),
          h.td(string(sum(m.amount for m in members)))),
      searchable = true, search_query = q, expand_controls = true,
      selectable = "tx", select_form = "bulk")

  @get table(; group_by::String="Counterparty", q::String="") =
      transactions_table(__self__, group_by, q)
  @get rows(; group_by::String="Counterparty", key::String="") =
      transactions_table(__self__, group_by; group_rows=key)
  ```
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
- **Open groups.** The groups the reader opened or closed are kept per table
  `id` and page path, like the search and the selection, so a re-render of the
  table (a regroup and back, a bulk action) opens them again; a lazy group that
  was open loads its rows again.
- **Initially open.** `initially_open = true` opens every rendered group and
  leaf detail; lazy groups still load on first expand. A predicate is called
  with leaves only, never with group rows: each group holding a leaf it opens
  renders open, at every [level](#table-grouping-levels), so that leaf and its
  detail show on first paint (every copy of a leaf in several groups). Such a
  group renders its rows eagerly even when `group_rows_url` would make it
  lazy. A page reached from "open this document" passes
  `initially_open = t -> t.id == open_id`; it needs no script to open the
  group.
- **Row actions.** A route that changes rows renders the same call with
  `update_rows` / `update_groups` instead of the whole table; see
  [Row updates](#table-row-updates).

##### Nested levels and grouping pills {#table-grouping-levels}

Pass `group_by` as an ordered list to nest the groups level by level, the
first outermost. The *Group by* control is then a row of pills, one per
grouping: a pill turns its level on (as the innermost) or off, and the active
pills reorder by dragging, by their ‹ › buttons, or with ←/→ on a focused pill.
No active pill is the flat view. Each change regroups in the browser, at
every level. A table whose group rows or lazy groups need the server also
re-renders through `group_by_url`, sending the levels as repeated `group_by`
values, so that route takes a vector:

```julia
document_table(self, group_by, q=""; kw...) = master_detail_table(headers, documents;
    key = d -> d.id, master = d -> cells(d),
    detail_url = d -> query_url(self / "detail"; id=d.id),
    groupings = ["None" => nothing, "Review stage" => d -> d.stage, "Document type" => d -> d.kind],
    group_by, group_by_url = self / "table",
    group_master = (key, members) -> (
        h.td(h.strong(last(HTMXObjects.group_path(key))), " ($(length(members)))"),
        (h.td("") for _ in 2:length(headers))...),
    searchable = true, search_query = q, expand_controls = true, id = "documents", kw...)

@get table(; group_by::Vector{String}=["Review stage", "Document type"], q::String="") =
    document_table(__self__, group_by, q)
```

- **Levels.** Each group row is a branch of the group above it; leaves sit
  under their innermost group, and a leaf with no key at an inner level is
  listed directly in its outer group. A grouping that returns several keys
  lists the leaf under each, at any level. Counts, sorting, search (its count
  of items, ancestor paths), open groups, *Expand all* and selection work as
  with one level.
- **Group keys are paths.** With a list, each group is named by its path, a
  JSON array of its level keys, outermost first (`["Open","Invoice"]`): the
  `key` that `group_master` and `group_rows_url` receive, the value a selected
  group row submits (`tx_group=["Open","Invoice"]`), and what `group_rows` and
  `update_groups` take. `HTMXObjects.group_path(key)` decodes it. The default
  group row shows the group's own key; indentation shows the level. A single
  `group_by` name keeps one level, plain keys and the select.
- **The flat view.** With no active pill the pills send the flat grouping's
  name (here `None`); a `group_by` list of `[]`, `[""]` or `["None"]` renders
  the leaves. Without a flat grouping the last active pill stays on, as the
  select offers only the declared groupings: an empty `group_by` would reach a
  `Vector{String}` route as no values, and `query_url` would drop it from the
  action URLs.
- **The grouping elsewhere.** A bulk form named by `select_form` receives the
  levels as `group_by` values. In the browser, `htmxoGroupBy('#documents')`
  returns the `group_by` values of the table's current grouping, for either
  form of `group_by`, e.g. for an action's `hx-vals`
  (`js:{group_by: htmxoGroupBy('#documents')}`).
- **Lazy groups** load at any level. The subgroups of a loaded group can be
  lazy in turn, and *Expand all* loads and opens them all.
- **Row updates** name groups by path in `update_groups`. A named group that
  no longer exists leaves from the outermost level of its path that is gone.
- **Markdown** marks each level below the first with `›`, since it has no
  indentation; the pills are left out like the other controls.

##### Row updates {#table-row-updates}

`master_detail_table` writes each row's id, controls, hierarchy, search and
selection attributes itself, and a regroupable table lists a leaf once per
group it belongs to, so a per-row action cannot return `master(item)` for the
row it changed. It returns the rows the table itself would render, and only
those, by calling the table with `update_rows` (items, by `key`) and, in a
regroupable table, `update_groups` (group keys):

```julia
transactions_table(self, group_by, q=""; kw...) = master_detail_table(headers, transactions;
    key = t -> t.id,
    master = t -> (h.td(t.party), h.td(t.category),
        h.td(h.button("Flag"; hx_post=query_url(self / "flag"; id=t.id, group_by),
                      hx_target="closest tr", hx_swap="outerHTML"))),
    group_master = (key, members) -> (h.td(h.strong(key)),
        h.td(rule_mode_select(self, key, group_by)), h.td(count_flagged(members))),
    groupings, group_by, searchable = true, search_query = q, id = "transactions", kw...)

@direct @post flag(; id::String, group_by::String) =
    (toggle_flag!(id); transactions_table(__self__, group_by; update_rows=id))
@direct @post rule_mode(; group::String, mode::String, group_by::String) =
    hx_response(transactions_table(__self__, group_by; update_groups=group);
                toast="Rule for $group: $mode")
```

- **What comes back.** A `<tbody data-htmxo-row-update>` with each copy of the
  leaf in the active grouping, its detail row, and the rows of the groups it is
  in (their summaries are computed from their members); for `update_groups`,
  each group row with all its rows. A lazy group's rows come too, for a table
  that has loaded them. In a tree or a flat table, `update_rows` returns the
  item's own row and detail. In a tree that is not its child rows: a parent's
  key re-renders the parent row alone, so an action that changes which
  children a parent has names those child keys too (`update_rows=[parent,
  child]`, and the old parent's key when a child moves, since its summary
  changes). A child that moves to another parent keeps its key and row; the
  update renders it under the new parent and it moves there.
- **How it lands.** The table runtime applies any htmx response holding that
  body, whatever the requesting element's `hx-target` and `hx-swap`, so a
  row's existing `hx-target="closest tr"` keeps working. Each row replaces the
  row with its id in place and keeps what the reader did to it: an open
  branch, an open detail (a lazy one loads again), the selection, the search
  and its predicates, and the focus, which returns to the same control. A leaf
  that moves to another group arrives as another row, since a leaf's row id
  names its group; it takes its open detail and the focus along, and the page
  scrolls to the focus. If the reader had its detail open in view, the groups
  above it open at every level, so it stays in view: a group the update
  creates, one the reader closed, and a lazy one, which loads its rows first.
  A tree row that moves to another parent does the same. Focus that cannot
  return to its control goes to the row's detail control while a lazy detail
  loads again, and to the nearest group row that shows while the row is in a
  closed group. The new rows get `htmx:load`. A row new to the table, a new
  group, or a row whose place among its siblings changed (a group that a moved
  leaf now opens first, a child row whose date was edited) goes where a full
  render of the table puts it: after the row before it among its siblings, or
  before the row after it when only that one is on the page. The update
  carries those neighbours for each row whose preceding sibling it does not
  list (`data-htmxo-update-places`); with neither neighbour on the page, a new
  row joins the end of its group or table and an existing row stays put. In a
  lazy group the reader has not opened, a new row arrives with the group's
  other rows when the group loads. A sorted table then re-applies its sort.
  `htmxoUpdateRows(html)` applies a row update fetched by other means.
- **What the reader added to a row.** The rows' content is the update's,
  their details' too: an open detail stays open, but its content is what the
  call renders now (a lazy one loads again). Whatever the browser added after
  the render goes, a disclosure the reader opened, an editor loaded into it,
  text typed and not yet saved, unless the element holding it is marked
  `hx-preserve` with an `id`: as in any htmx swap, the update's element of that
  id gives way to the page's, which moves there with its state. Preserve the
  part the browser owns, not values the update should refresh, which a
  preserved element keeps as they were:

  ```julia
  detail = inv -> h.div(invoice_summary(inv),     # refreshed by every update
      h.details(; id="editor-$(inv.id)", hx_preserve=true,   # kept as the reader left it
          hx_get=query_url(self / "editor"; id=inv.id), hx_trigger="toggle once",
          hx_target="find .editor")(h.summary("Edit"), h.div(; class="editor")))
  ```

  Key the id by the item, unique on the page: a leaf that moves to another
  group finds its element in its new row by that id. A lazy detail's update
  holds only its placeholder, so the preserved elements of the content it had
  wait in it, hidden, until it loads again, at once if it is open and on the
  next expand if not; the load's response renders the same ids to claim them,
  as for any htmx swap. Elements in master cells are kept the same way.
- **What leaves.** The update speaks for the copies of each leaf in
  `update_rows` and for each group in `update_groups` with all its rows: those
  it no longer lists leave, with their detail rows. A key no longer among the
  items removes its rows; a group that no longer exists leaves with its rows.
  In a tree that holds at any depth: a named key no longer among the items,
  or the children of the items, removes its row with its detail and child
  rows. When an action moves a leaf to another group, name both groups:
  `update_rows=id, update_groups=[old, new]`.
- **The grouping.** Render the update for the grouping the reader sees: pass
  `group_by` into the action URLs that `master` and `group_master` build, as
  above. An update rendered for another grouping is refused with an error
  toast, and the table is left as it was. In the flat view `update_groups`
  names no rows.
- **Transport and toasts.** Like any route whose response is table rows,
  declare the action `@direct` (see `OperationPolicy`): an interim poller
  cannot stand in a table row. The response body is rows, so name a success
  toast on the route (`hx_response(...; toast=...)`) rather than with
  `data-htmxo-toast="body"`. Give the table an `id`.

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

A `tabset`'s open tab lives in the page URL. A tab click replaces the URL's
`tab` parameter with the tab's name (the history entry is replaced, not added),
and a page opened with `?tab=<name>` shows that tab, so a reload, Back or a
shared link reopens it. The browser does both; the app's routes need not read
`?tab=`. A tab's name is its label lowercased, with umlauts spelled out and
every other run of characters a `-`:

```julia
# ?tab=voralarme, ?tab=stoerungen, ?tab=guete-der-messungen-k-40
tabset("Voralarme" => alarms, "Störungen" => "/stoerungen",
       "Güte der Messungen (K-40)" => "/guete")

# names of your own; `active` picks the tab shown when the URL names none,
# by position or by name
tabset("Voralarme" => alarms, "Störungen" => "/stoerungen";
       names=["voralarme", "stoerungen"], active="stoerungen")

# a second tabset on the page keeps its own parameter (?insitu=…);
# tabsets that share a parameter share its value
tabset("K-40" => "/k40", "Cs-137" => "/cs137"; url_param="insitu")

# keep this tabset out of the URL
tabset("A" => a, "B" => b; url_param=nothing)
```

A lazy tab named by the URL loads once it shows, and the default tab's lazy
panel is not fetched until its tab is clicked. Two tabs with one name are an
`ArgumentError` while the URL or `active` picks tabs by name. Inside a docs embed (`.htmxo-embed`) the URL belongs to the
host page and is left alone. `htmx()` pages carry the script that does
this, `tabset_script()`; a page with its own `<head>` adds it next to
`tabset_styles()`.

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
`HX-Retarget` response. A failed request (an unswapped error status, no answer,
a timeout) flashes red, and the shell's
[failure toast](api.md#failure-toasts) says why. A request the page aborted, or
an answer that navigates, only clears the outline.

Only requests the reader started are marked. A request the page sends by
itself draws no outline, and its element does not dim: a poll, a preload, and
an element's own `load`, `revealed` or `intersect` trigger — `lazy(url)`, a
deferred page's placeholder, a `tabset`'s shown lazy panel, an infinite-scroll
sentinel. So a page that loads its main content lazily just shows it. A failure
among them still raises the failure toast.

## Links and links-as-actions

### `hx_link(url; …)` — `<a>` that uses `hx-get` (HTMX boost-style)

`hx_link(url; kwargs...)` returns a Node — append the link text via call syntax. `hx-target`, `hx-swap`, etc. pass through as kwargs.

```julia
hx_link("/settings"; hx_target="#main", hx_push_url="true")("Settings")
hx_link("/report/42"; hx_target="#main", preload=true)("Report")  # starts on hover
```

### Opening a link in a new tab {#new-tab-links}

A click on an htmx link swaps in place. A Ctrl/Cmd-click, Shift-click or
middle-click on one with a real `href` — `hx_link`, `nav_sidebar` and
`htmxo_breadcrumb` render one — opens that address in a new tab or window and
leaves the page as it is, as on any link. htmx alone would swap in place for
Ctrl/Cmd/Shift too, so the [`htmx`](@ref) shell carries
[`modifier_click_script`](@ref), which keeps those clicks from htmx; a link
without an `href`, or with `href="#…"`, stays htmx's. Give an app's own
`hx-get` link the page address as its `href` to get this.

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
| `format_number(1234567.25; texts=table_texts(:de))` | `"1.234.567,25"` (the table's language; see [Numbers in table cells](#table-numbers)) |

## Editor widgets (Git integration)

`editor_form` and `editor_styles` are the front-end pieces of `EditorRoutes`. See the `EditorRoutes` source for the full route surface; in most apps you just `@include` `EditorRoutes` and drop `editor_styles()` once on the page.

## Captions

`with_caption(spec, content)` wraps a figure (or any content) in a `<figure>` with a caption above it; `render_table(table; caption=spec)` captions a table the same way. `actions` puts buttons or links, such as a CSV download, on the right of the caption header, or in one row below the title when the column would leave the title less than `16rem` beside them:

```julia
cap = CaptionSpec(; title="Posterior fit", short="Median and 95% interval per dose.",
    long="Fitted with 4 chains of 1000 draws.")
with_caption(cap, plot_node; actions=(h.a("⬇ CSV"; href=csv_url, class="caption-action"),))
```

`title` and `short` form the caption's header line, and `long` is folded behind a **More** toggle. The toggle's word comes from `texts=`: `with_caption(cap, plot_node; texts=caption_texts(:de))` shows **Mehr**, and `caption_texts(:de; more="Erläuterung")` replaces it with the app's own word. `render_caption` takes the same keyword. An unknown locale or text name throws an `ArgumentError`. Include `caption_style()` once per page.
