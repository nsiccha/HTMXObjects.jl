# Changelog

## Unreleased

## 0.1.175

- A fresh link to a `#id` in an eager `master_detail_table` detail opens the
  enclosing groups and details and scrolls the target into view, including in
  static exports.

## 0.1.174

- `relative_to = RelativeTo(columns; default, sigdigits, suffix, comparable)`
  on `sortable_table`, `render_table` and `master_detail_table` lets a reader
  show compared columns relative to one they pick. The toolbar gets a
  *Relative to* control (`texts.relative_to`, *Relativ zu* in German) before
  the *Columns* menu. Picking a label divides each compared number cell by the
  same row's cell of that label under the same `header_groups` heading, in the
  browser: times `2, 4, 8` read `0.5×, 1×, 2×` against `4`. The exact ratios
  are the sort keys and the ⬇ CSV numbers, and the CSV names a divided column
  `"Primal / A relative to B"` (`texts.relative_column`). Only the compared
  cells change, so open and loaded details, search, selection, hidden columns,
  regrouping, row updates, lazy group rows and hover linking keep their state.
  `comparable(item, column)` (an item of `master_detail_table`, a row of
  `render_table`; `data_htmxo_compare` on `sortable_table`'s cells) says which
  pairs may be divided: a pair with different keys, a `missing` key, no number
  or a reference of `0` reads `–` and sorts last in both directions. `default`
  opens the table relative to a label, written by the server, so `?plain`,
  Markdown and `pdf_report` show it too. The pick is kept per table `id` and
  page path; `htmxoTableRelative('#id'[, label])` reads or sets it and
  `htmxo:relative-changed` announces it (snag `build-a-master-d-31c79059`,
  design `1exoqn6`).
- `TableTexts` gains `relative_to`, `relative_absolute` and `relative_column`.

## 0.1.173

- A tree grouping (`groupings = [name => :children, …]`) keeps what the page
  changed in a leaf when the reader regroups. The other groupings and the
  flat view used to show copies of each leaf's tree row, and picking the tree
  again brought back the rows it held before: a leaf's status replaced by id
  while another grouping showed (an htmx out-of-band swap, a script) came back
  old, and the other grouping's copy took the update but was thrown away. Now
  the leaf's first row in the tree is the row every grouping shows, moved
  between them, and the leaf's other rows in the tree take its elements that
  have an id when the tree comes back, as an out-of-band swap updates every
  element of that id while the tree shows. A table that opens on another
  grouping puts the rows it shows into its tree the same way (snag
  `tree-regroup-liv-09cbe71c`).

## 0.1.172

- `serve` reports addresses that leave a proxy's mount prefix. A response a
  browser receives (a page navigation or an htmx request) under
  `X-Forwarded-Prefix`, such as the KB's `/p/<slug>`, is checked for an
  `href`, `src`, `action`, `formaction`, `hx-get`/`-post`/`-put`/`-patch`/`-delete`,
  `hx-push-url`, `hx-replace-url`, `ws-connect` or `sse-connect` holding a
  root-absolute path outside the prefix, which the browser sends to the
  proxy's root instead of the app. Each such address is logged once per
  process at `Warn` (`_group=:mount_url`), naming the request, the attribute
  and the address, up to 100 addresses. It finds the addresses the `@htmx`
  macro cannot see, such as a literal an app's helper function puts on an
  attribute. Script text (a hyperscript `_` attribute) and `Raw` markup are
  not read, the overlay bar's own address is not reported, and the page is
  sent unchanged (snag `relied-on-the-ht-e42acfbb`).
- The `@htmx` macro's hardcoded-URL warning now also covers `ws_connect`,
  `hx_push_url` and `hx_replace_url`, and no longer looks at `hx_target` (a
  CSS selector) or `hx_post_url` (no such attribute). Its attribute list and
  the response check's are one list.

## 0.1.171

- `serve(; dev=true)` is a development mode for iterating on an app's UI: a
  saved source edit is applied before the next request, without a restart,
  and every open page reloads itself at the same scroll position. Before each
  request it checks the source files of the packages under the dev roots (by
  default every package Revise tracks that is not installed from a registry;
  `dev_roots` names them instead): their size and modification time on every
  request, their content at most once a second. It applies a changed package
  with Revise's `revise(mod; force=false)`, which does not depend on a file
  watcher noticing the edit. Edits inside an `@htmx struct`'s property and
  route bodies apply as well. An edit Revise cannot apply in a running
  process, such as a new struct field, is listed at the bottom of every open
  page and in the log until the server restarts, and routes of that struct
  can fail until then; an error page reloads by itself too. It needs `using Revise` before the app is loaded, and is for
  development only, never a deployed app (decision 14xfxqy, todo 074575c).

## 0.1.170

- `serve(; compute_trace=:requested)` shows what one request computed: a
  request that carries `?__trace` or `X-HTMXO-Trace: 1` runs inside
  DynamicObjects' `with_compute_trace`, which counts per property the reads,
  memory hits, memoized computations, `@fresh` runs, disk loads, waits and
  errors with their times, and logs the invalidations that dropped values.
  `compute_trace=:all` traces every request; the default `false` traces
  nothing and ignores the flag and the header. The trace stays open until the
  request and every operation it started have ended, so a route that answers
  with a poller is traced to the end of its computation. A traced response
  carries `X-HTMXO-Trace-Id` and a `Server-Timing` header with the ten
  properties that took the most own time (browser developer tools show it), a
  full page traced on request adds the header to its own same-origin htmx
  requests, and a closed trace writes one log line (`_group=:trace`) naming
  its three slowest properties. The latest 100 closed traces (`trace_limit`
  on `RuntimeTracker` and `configure_runtime!`) are listed by `RuntimeRoutes`'
  new `traces` and `trace(id)` pages (Markdown with `?plain`) and returned by
  the new `request_traces` and `request_trace`, as `RequestTrace` records.
  Only the per-property table and the invalidation log are kept, never read
  arguments (todo 09gck4a, decision 1wbhyfs).

## 0.1.169

- A retained root keeps the construction keywords of its `@param`s and of its
  mounted children's: a page that mounts `@include steep = Part(; a=0.4)`, or
  is routed as `route!(App(; a=0.4))`, shows `a = 0.4` in every request, also
  when a managed `RootRetention` or the store `semantic_app` switches on
  serves it. Before, a request served from a retained root read the type
  default instead, from the first request under a managed `RootRetention`
  and from the second one under the semantic store (snag
  retained-semanti-865defc0). The fix is DynamicObjects' `remount`, which now
  keeps every keyword its retained object was constructed with, so the
  `[compat]` floor of DynamicObjects rises to 0.5.23.

## 0.1.168

- A Pico page's `.container` uses the window at every width, not only from a
  1280 px window: `pico_bridge()` (loaded by every `htmx(...; pico_version)`
  and `pico_page` shell) lets it fill the window up to 1600 px with a 2rem
  margin on each side from 576 px on, where Pico steps it at 510, 700 and
  950 px. A 980 px window, the width a phone's browser lays out in desktop
  view, now gets a 916 px column instead of 700 px; a 1100 px window 1036 px
  instead of 950 px. Below 576 px Pico already fills the window, padded, and
  that is unchanged. `--htmxo-container-max-width` and
  `--htmxo-container-gutter` tune it at every width as before.

## 0.1.167

- A word longer than a table column can be (an identifier, a URL, a long
  `code` span) no longer makes a `sortable_table`, `render_table` or
  `master_detail_table` wider than its room. When the columns would not fit,
  a column whose widest word is longer than 16rem, or 40% of the room if that
  is less, narrows until the table fits, never below that bound nor below text
  kept on one line, and the word breaks inside it; a `code` span shrinks with
  it. Other columns keep their widths, so a table that is wide for its number
  of columns still scrolls in its own box. Apps can drop `overflow-wrap:
  anywhere` rules added to cells for this (snag table-wider-than-be5313e7).
- A `SemanticStatus` keeps its glyph on the line of its label's first word:
  the HTML and HXML join them with a no-break space, so a narrow column no
  longer leaves "•" above "Unknown". Markdown and plain text are unchanged;
  search and the CSV read it as a space. A `white-space: nowrap` on a status
  cell added only to keep the glyph with its label can go.

## 0.1.166

- Readers choose a table's columns. A `sortable_table`, `render_table` or
  `master_detail_table` of four or more columns has a *Columns* menu
  (`Spalten` with `table_texts(:de)`) in its toolbar line: a checkbox per
  column, the first column always shown, a `header_groups` heading hiding or
  showing its columns together. `hidden_columns=["Kaltmiete", 7]` opens the
  table with columns hidden (labels, `"Group / Leaf"` or 1-based positions),
  `column_menu=false` leaves the menu out, `column_menu=true` adds it to a
  smaller table. The reader's choice is kept in the browser per table id and
  page path, by column name, with a *Reset* button. Hidden columns stay hidden
  through sorting, search, regrouping, lazy group rows, row updates and bound
  redraws; detail rows and spanning cells span the shown columns, and the
  column widths are held over them. The ⬇ CSV writes the shown columns,
  Markdown and PDF the columns the table opens with.
  `htmxoTableColumns(target[, columns])` reads or sets the shown columns, and
  `htmxo:columns-changed` announces a change. New table texts: `columns`,
  `columns_reset`.

## 0.1.165

- An app is mounted where `route!` put it, outside requests too.
  `route!(app; prefix="api")` now gives `app` and its `@include`d children
  the prefix request roots have: `app.__prefix__ == "/api"`, so `app / "x"`,
  `string(app)` and the result addresses of a `semantic_app` built from
  `app` or a child outside a request (a report, `to_markdown_string`,
  `pdf_report`) name the registered routes. Before, they named `/x`, no
  route answered, and each tab's Markdown result was silently empty.
- `route!` reads `prefix="/api"` and `"/api/"` as `"api"`; a leading slash
  used to produce `//api/…` addresses, which a browser reads as another host.
- A `semantic_app` tab whose result address no route answers raises an
  `ArgumentError` naming the address and the object's `__prefix__`, both
  when the page draws a browser-computed result and when its Markdown is
  written, instead of showing the tab empty. A route that fails still shows
  its error article, as before.

## 0.1.164

- A static export (`StaticExport`, `export_site`) no longer greys or removes
  a `semantic_app` control whose choices can change. Its refresh region,
  which only draws the control again through the server, loses that request
  and stays as it is under both `controls=:disable` and `controls=:remove`,
  so a browser-computed input keeps its full contrast and takes mouse input
  (the injected `[data-static-disabled]` style had dimmed it to 0.45 and set
  `pointer-events: none`). Operations that need the server are still greyed
  or removed.

## 0.1.163

- Tables accept independent `density=:compact` and `header_align=:left`
  options. Compact tables use readable 0.9rem text, tighter cells and less
  space around the CSV/caption area; header alignment leaves numeric cells
  right-aligned. Combine them with `class=""` for plain rows. The options
  work with `render_table`, `sortable_table`, `master_detail_table` and
  browser-computed rows. Existing defaults and detail-panel sizing stay the
  same; sorting, CSV download and sticky headers remain available.

## 0.1.162

- Generated number sliders in a `semantic_app` sidebar now fill a row above
  their exact number field and unit, keeping the full control width for
  dragging even when an inline row would fit. Other forms keep their existing
  wrapping layout. `--htmxo-sidebar-width` still includes padding and the
  divider; `calc(20rem + 1px)` leaves 304 px for controls at a 16 px root font.

## 0.1.161

- Table sorting keeps equal numeric cells and complete numeric
  `data-sort-value` keys in their incoming order in either direction,
  including signed zeros and equivalent decimal or exponent spellings.
  Server `default_sort`, browser header clicks and offline redraws agree;
  CSV retains the row order and original numeric values. Ordinary text keeps
  its natural text tie-break (`2 x 5` before `2 x 10`). At the same leading
  number, numeric keys precede text ascending and follow it descending.

## 0.1.160

- `semantic_app(...; presentation=:tabs, result_height)` accepts a named tuple
  or dictionary keyed by tab names. For example,
  `result_height=(figure=nothing, numbers="32rem")` keeps the Picture tab's
  charts and facts in the page flow while all the Table tab's tables share
  one 32rem scrolling box. Omitted tabs keep the `:window` default; explicit
  `nothing` removes a bound. Existing scalar values retain their behavior.

## 0.1.159

- A `<details>` among semantic content keeps its `<summary>` in plain text
  (`repr("text/plain", …)`): the summary is a paragraph of its own before the
  body, as a `SemanticDisclosure` writes its label, instead of being dropped as
  a toggle label. A `<details>` whose body writes nothing (only buttons, or
  nothing at all) writes nothing, its summary included, as a
  `SemanticDisclosure` with nothing to open does.
- Markdown reads (`to_markdown_string`, `?plain`, and the input to `pdf_report`)
  keep the first summary as a bold label before the body; a heading summary
  stays a heading. HTMX 1.4.1 supplies this Markdown rule and is now the
  minimum supported HTMX version. A later summary stays in the body in both
  text projections (snag `in-the-kb-lane-c-bacb9ce6`).
- The web and web app environments pin HTMX 1.4.1 with this rendering fix.

## 0.1.158

- `bound(x; labels)` and `ColumnSpec(label; labels)` accept `Inf` and `-Inf`
  as distinct keys. Beside `digits`, `sigdigits` or `percent`, labels name
  exceptions and other numbers use that format; labels alone remain exhaustive.
  `bound(x; unit = "years")` appends a no-break space and the unit only to a
  number, never a label or `–`. Thus a halving time can read `12.3 years` or
  `No finite halving time`, on the server, in Markdown/PDF and after offline
  browser recomputation. Label cells sort by their value and expose their
  text to search and CSV; other numbers retain their exact CSV value. A bound
  table sizes its label columns again when its results change into words.

## 0.1.157

- `pdf_report` keeps tall pictures and their full captions
  inside the page body, clear of the footer. Image widths are resolved before
  scaling, including wide intrinsic and percentage widths. A caption longer
  than a page keeps its measured wrapping width
  when the whole figure is scaled. Ordinary captions retain their text size.

## 0.1.156

- A `semantic_app(…; presentation=:tabs)` page's result taller than its bound
  scrolls inside itself instead of lengthening the page, so the inputs beside
  it and the text around it stay where they are. A 201-row table in a picture
  embedded in an article made the page 15,072 px tall; it now scrolls in a box
  no taller than the window. `semantic_app(…; result_height = "32rem")` bounds
  the results at that CSS length, and `result_height = nothing` keeps them
  growing with the page; the default is `:window`, the window's height less
  `--htmxo-sticky-top`. A result that fits its bound stays in the page as it
  is, so nothing in it (a glossary term's explanation, a focus ring) is cut at
  an edge. Inside the box a table's controls and header stick to the box top,
  and a wide table's own box fits inside it; sorting, search, CSV, the
  keyboard row moves, hover linking and the page's Markdown are unchanged
  (snag `keep-the-caesium-ac035f3b`).

## 0.1.155

- A generated `Bool` input is a switch where a change applies at once: the
  sidebar of a `semantic_app(…; presentation=:tabs)` page, the shared inputs
  `place=` puts in its tabs, and a following tab's own inputs, live and in a
  static export. In a form a button sends (an operation card, `operation_form`,
  a `:tabs` mutation) it stays a checkbox. A switch is the same
  `<input type="checkbox" value="true">` with `role="switch"`, which Pico draws
  as a switch, so submission, Reset, the page address, Copy link, `?plain`
  (☑/☐) and browser-computed results are unchanged, and a refresh of its
  controls draws it again. `@control(name) = :switch` or `:checkbox` beside the
  `@param name::Bool` chooses it for every generated form; on any other input
  the page refuses it with an `ArgumentError` naming the input. The `htmx()`
  shell draws a switch's "on" track in the text colour with a knob in the page
  colour, as a chosen pill is filled, never Pico's azure, also for a
  hand-placed `cinput(…; switch=true)` (snag `preserve-the-exi-b16bdeb1`).

## 0.1.154

- A result that computes in the browser (`@browser`) and reads a finite input
  whose default is computed from a fixed field (`settings::Any = (; family = 0)`,
  `@param family::Int = Int(settings.family)` with `@options(family)`) carries
  the view rendered for each value of that input. Until now every view held the
  result for the default, because an input that follows its computed default
  was left out of each view's address, so after the reader picked another value
  the page showed the default's text beside browser values for the new one, on
  a live page and in a static export alike. A view at another value now sends
  that value. A literal default was not affected.
- The static export's check (`export_site`, `dispatch(…; static)`) changes a
  continuous input whose default is computed from a fixed field too. It used to
  leave such an input out of the address it probed, so a result that showed it
  outside `bound(...)` exported without a word and went stale; now the export
  names it, as for an input with a literal default (snag
  `static-export-fi-2f405405`).

## 0.1.153

- A `semantic_app(…; presentation=:tabs)` page draws its controls again for
  an input whose `@options` range or computed default reads another input with
  a range declared after it. With `@param a::Float64 = 1.0` and
  `@options(a) = number_domain(0.0, 2b)` declared before `@param b::Float64`
  and `@options(b) = number_domain(0.0, 1.0)`, the request the page sends when
  `b` changes evaluated `2b` with the text it sent for `b` (`2 * "0.9"`):
  `MethodError: no method matching *(::Int64, ::String)`, and the page showed
  an error in place of the controls, the control of `a` with them. A computed
  default (`@param c::Float64 = 2b`) that an out-of-range `c` falls back to
  failed the same way. An input's range and default now read each input they
  name as its control shows it, whichever was declared first. Declared after
  `b`, or read through a property (`upper = 2b`), the range was already right
  (snag `options-param-re-3392079f`).

## 0.1.152

- `bound(x; labels = [0 => "No dose", 3 => "200 mg (level 3)", …])` writes a
  value as the text a table names for it, so a level or category a browser
  module computes reads as words: on the server, in the page's Markdown
  (which a PDF report reads), and in the browser after each computation.
  The table is a list of `value => text` pairs or a `Dict`; a key is a
  number (`3` also names a module's `3.0`), a `Bool` or text. A value the
  table does not name is an `ArgumentError` naming the value and the keys,
  thrown by the server and shown by the browser in the result as a module's
  error is, never a silent fallback; no value (`NaN`, `missing`, `nothing`)
  writes `–`. `labels` takes no `digits`, `sigdigits`, `percent` or `date`.
- `ColumnSpec(label; labels)` does the same for a table column, in any
  `render_table` and in a bound table the browser writes again: each cell
  shows its label and sorts by its value, and search and the ⬇ CSV read the
  label. `sortable_table` and `master_detail_table` refuse it, as they refuse
  the number and day keywords (snag `bound-cannot-sho-5a0dbf64`, user
  decision `07gq4zu`).

## 0.1.151

- `export_site` writes a page with a browser result (`@browser`) whose
  controls take their `@options` from a fixed field with a default, or from a
  property computed from fixed fields: `limits::Any = (; a = (0.0, 2.0))`
  with `@options(a) = number_domain(limits.a...)`, a view mounted with its
  ranges (`@include view = View(; limits)`), or a `Symbol` choice listing a
  fixed field's pairs. Until now each such control was refused with "the
  server draws the control of `a` again when other inputs change (its
  `@options` read `limits`)", though no control of the page can change
  `limits`. Options that read an input, directly or through a property
  (`lim = 2b`, `@options(a) = number_domain(0.0, lim)`), are still refused,
  and the refusal now names that input (`b`), not the property (snag
  `export-site-opti-97b7d7a9`).
- A live page draws a control again when an input its `@options` read
  through a property changes: with `lim = 2b` and `@options(a) =
  number_domain(0.0, lim)`, changing `b` now redraws the range of `a`. Until
  now only the names the declaration writes counted, so the slider of `a`
  kept the range of the first `b`.

## 0.1.150

- A page that shows several `semantic_app(…; presentation=:tabs)` apps keeps
  each app's inputs and open tab in the page address under the app's address
  name, its mount path with dots: two apps mounted at `/first` and `/second`
  that both have an input `rate` write `?first.rate=5&second.rate=9`, and the
  open tab of the first `first.tab=other`. Until now the address kept one
  `rate` and one `tab` for the whole page, the one changed last, and a
  reopened link set it in every app. A page that shows one app, the app's own
  page included, writes plain names as before (`?rate=5&tab=other`), and the
  root object's own app writes plain names beside the others. An app reads its
  own name first, else the plain one, so a link written with plain names opens
  as before; where an app without a name keeps an input plainly, an app with a
  name writes it under its own name even at its default, so it does not take
  the other app's value. The browser chooses the names (it sees the whole
  page: `semantic_follow_script`, `tabset_script`), the server reads the same
  names when it renders a page, and a static export (`export_site`) applies
  them when it loads. The forms and the tab bar carry the app's name as
  `data-htmxo-url-scope` (snag `put-two-mounted-398bd499`, user decision
  `1wq2uyi`).
- `tabset(…; url_scope="first")` names the app a tabset belongs to: on a page
  that shows apps of more than one name it keeps its tab as `?first.tab=`,
  else as `?tab=`. A custom `semantic_app` `layout(parts)` passes
  `url_scope=parts.url_scope`.

## 0.1.149

- A day computed in the browser shows as a date, and a `NaN` from a browser
  module as no value (snag `show-a-year-s-wi-b018d869`, design `1lzmd6s`).
  `bound(x; date = :long)` and `ColumnSpec(label; date = :short)` (also
  `:month`) write a number of milliseconds since 1970, UTC (the unit of
  JavaScript dates and of a plot's temporal axis), or a `Dates.Date`, as
  `format_date` writes that day in the language of `texts`: `16 November
  2019`, `16 Nov 2019`, `Nov 2019` (`16. Nov. 2019` in German), on the
  server's first paint and, through the new `htmxoDateText`, in the browser
  after each computation. A day cell sorts by its value and exports its ISO
  day (`2019-11-16`) to the ⬇ CSV; `ColumnSpec(…; date)` works in any
  `render_table` and also writes `Date` values, which a column without it
  still shows as ISO. A `NaN`, `±Inf`, `missing` or `nothing` is no day:
  `–`. `date` takes no `digits`, `sigdigits` or `percent`, and
  `sortable_table` / `master_detail_table` refuse it as they refuse those.
- `bound(x)` and a table of browser outputs (`render_table(bound(p; columns))`)
  write a `NaN` as no value, `–`, as they write `missing`: in the table an
  empty number cell with no sort value and an empty ⬇ CSV field, on the server
  and in the browser. A module that returns numbers only has no other way to
  say "no reading". **Behaviour change** for those two only: they used to
  write `NaN`. `format_number(NaN)` and other tables still write `NaN`.
- The month names and layout of a day's style reach the browser only where a
  day is written (a bound mark's `data-htmxo-format`, a bound table's column
  description), so a page or table without days is byte-identical apart from
  the shared runtime's new `htmxoDateText`, which carries no month names.

## 0.1.148

- A `semantic_app(…; presentation=:tabs)` page with a sidebar is as tall as
  its inputs and results. Its layout took the window's height as its least
  height, which suits `app_layout` as a page's shell but not a part of a page:
  shown between two paragraphs of an article, the surface stayed one window
  tall and left the window's height less its content empty before the next
  paragraph (462 px in a 700 px window, 962 px in a 1200 px one), and a page
  holding only the surface scrolled although its content fitted (snag
  `tabs-surface-wit-b2cf6818`). An `app_layout` that is the page's shell still
  fills the window, its sidebar's divider reaching the window's bottom.

## 0.1.147

- A number input with a range (`number_domain`, `ninput(…; domain)`) stays
  inside a column narrower than its row. The slider (at least 5rem), the 7rem
  field and the unit kept one row that never wrapped, about 230 px wide, so in
  the 12rem sidebar of a `semantic_app(…; presentation=:tabs, shared=…)` page
  (176 px inside its padding) the unit was drawn up to 41 px into the result
  column, over the result's own text, and even a field without a unit crossed
  the divider (snag `number-control-u-68445236`). The row now wraps: in such a
  column the slider takes a line of its own, as wide as the column, above the
  field and its unit; a unit too long to fit beside its field goes under it.
  A column wide enough keeps the one row as before. The field and its unit
  are one `span.htmxo-number-entry` inside `.htmxo-number`, the slider after
  it; the field still comes first, so the label names it. An app stylesheet
  that selected `.htmxo-number > input[type="number"]` or
  `.htmxo-number > .htmxo-number-unit` selects them under
  `.htmxo-number-entry` now.

## 0.1.146

- The "Shown at" statement before each result of a
  `semantic_app(…; presentation=:tabs)` page's Markdown and PDF (`?plain`, a
  report, `pdf_report`) puts a colon after each input's label and each input
  on a line of its own: "Shown at:", then "Slope (per day): 0.20" and
  "Intercept: 80 units" below it, as one paragraph of lines. Since 0.1.135 it
  was one line, "Shown at: Slope (per day) 0.20; Intercept 80 units", in which
  a label that is a phrase with a comma ran into its value. A German page
  writes "Dargestellt bei:" and "Bezeichnung: Wert"; a label that ends in a
  colon keeps its own; a list of records writes its fields the same way,
  "Scenario (Dose (mg): 5)". The HTML page is unchanged (snag
  `shown-at-line-ru-25ece17f`, user decision `0xxd4et`).

## 0.1.145

- A numbered report's PDF contents list lists the sections `contents()`
  lists, and no other heading. Typst's outline used to list every heading of
  the PDF: an article's header and a plain `h.h2` in a view, once per state a
  `semantic_app` report shows, so BRR's snow report listed 12 entries where
  its page lists 2 (snag `pdf-contents-lis-087ca53a`). A report's Markdown
  (`to_markdown_string(…; report=true)`, `pdf_report(value, …)`) now marks the
  heading of each listed section with the class `htmxo-contents-entry`
  (`## 1 Results {#section-1 .htmxo-contents-entry}`), and `pdf_report`
  points the outline at those headings alone. Listed: each numbered section,
  and a `SemanticSection` written outside any numbered document, such as a
  closing "About this document" a report appends to its numbered body. Not
  listed: the document's title (`level=1`), a section inside the numbered
  document that took no number, and every heading that is not a
  `SemanticSection`'s. Those stay headings of the body and bookmarks of the
  PDF. Ordinary Markdown (`?plain`) is unchanged, and report Markdown that
  marks no heading keeps the outline of every heading.

## 0.1.144

- A static export no longer refuses a browser result (`@browser`) for markup
  that differs between two renders of the same inputs. Under a root with
  `__glossary__`, a result whose text used a term was refused with one "shows
  `a` outside `bound`" line per continuous input, although every input was
  shown through `bound(...)`: a linked term's definition carries an id that is
  new in every answer, and the export took that difference for the input's
  (snag `browser-result-u-88fa1fae`). When a view rendered with an input
  changed differs, the export now renders the unchanged inputs once more and
  names the input only if the view differs in more than those two renders do.
  A view that writes an id or a time of its own exports the same way. A
  refusal quotes what changed (`… for slope 2.0` becomes `… for slope 2.2…`),
  and a result whose renders of the same inputs do not line up, because it
  holds more or less markup each time, is named once, saying so.

## 0.1.143

- `pdf_report` keeps a captioned figure's pictures and caption on one page
  with or without an id. Quarto makes a figure only of a div whose id starts
  with `fig-` (a table with `tbl-`), so an id-less `with_caption` figure, such
  as AoV's `with_plot_caption` without `id=`, was a picture and a separate
  paragraph: the picture could end one page and its caption start the next,
  untagged as a caption (snag `pdf-report-id-le-8a1607df`). A report's
  Markdown (`report=true`, and every `pdf_report(value, …)`) now writes a
  `<!-- htmxo:caption -->` line just before the caption of each captioned
  figure Quarto does not float, and `pdf_report` sets a figure of pictures
  marked so as one Typst figure, its caption tagged `Caption`, that moves to
  the next page whole. An id-less captioned `render_table` becomes a captioned
  table the same way: its caption above it and tagged, the table still
  breaking across pages (HTMXObjects todo `0ikz55q`). A figure taller than
  the page's text area, with an id or without, has its pictures scaled down
  until it fits with its caption, where its caption ran over the page bottom.
  Figures of other content (prose, code) are unchanged, and so is Markdown
  outside a report. Regenerate saved report Markdown to get the marks. A
  figure Quarto numbers (`fig-…`) prints as before unless it is taller than a
  page.

## 0.1.142

- A computed default that reads no input stays static on an input that has a
  `@relevant` condition or declared `@options`. With
  `settings::Any = (; start = 1.0)`, `@param limit::Float64 = Float64(settings.start)`
  and `@relevant(limit) = has_limit`, the inputs the condition reads were
  taken as inputs the default reads, because both are arguments of the one
  call that extracts `limit`. The struct's first `@options` declaration was
  taken the same way for every input with a declared domain. Such an input now
  behaves as it already did without them: `export_site` writes a page with a
  browser result (`@browser`) instead of refusing it with "the server draws
  the control of `limit` again when other inputs change (its default reads
  other inputs)", a live page no longer asks the server to draw the controls
  again when `has_limit` changes, and the page address default of `limit` is
  its value, not `null`. A default that does read an input (`= median / 2`,
  `= has_limit ? 1.0 : 2.0`) is unchanged.
- That refusal names the inputs the default reads: "(its default reads
  `median`)" (snag `export-site-rele-5a6fd953`).

## 0.1.141

- A private `pdf_report` keeps the "not public" label ("nicht öffentlich")
  of a block of private content on the page where that content starts. The
  label is the first paragraph of the block's `::: {.htmxo-private}` div,
  `*not public*`, and nothing held it to the next block, so a private section
  starting near a page end left the label alone at the bottom of one page and
  the section's heading at the top of the next (snag
  `pdf-report-priva-c25e0698`). `pdf-report-labels.lua` now makes that
  paragraph sticky, as it does a disclosure's `::: {.htmxo-label}`; the
  private content itself can still continue across pages, paragraph spacing
  is unchanged, and the Markdown is the same as before.

## 0.1.140

- In a `numbered(…)` document, the captioned figures and tables of a
  `semantic_app(…; presentation=:tabs)` result computed in the browser
  (`@browser`) take the document's next numbers ("Figure 1:", "Table 1:"), in
  reading order, on the page and in its Markdown and PDF alike, and `ref(id)`
  cites them. Since 0.1.135 they took none. The views the browser switches
  between for a finite input read the same numbers as the view shown. The
  page fetches each view with its captions' numbers left as markers, which the
  document fills in when it renders; the Markdown asks the result with the
  counts the document had reached at the view, and the result numbers its own
  captions from there in the page's reading order. A report's further states
  (`report_states`) are only in the report and take no number, so every number
  in the report reads as on the page; a state's copy renames its element ids
  (`fig-curve` becomes `fig-curve-state-1`), since a PDF refuses a cited id it
  finds twice, so `ref` cites the copy at the page's inputs. A result the
  server computes, which the page loads later, still takes none, as
  `numbered` documents for lazily loaded content; sections inside a result
  take none either. Outside a `numbered` document nothing changes (snag
  `semantic-app-tab-c64170a6`, user decision `1gxfoo7`).

## 0.1.139

- `pdf_report` sizes a table's columns by their content, as a browser sizes an
  HTML table: each column is at least as wide as its longest word, and the
  room left goes to the columns whose text would otherwise wrap, in proportion
  to how much longer their text is than their longest word. Pandoc gave a
  table with a row longer than 72 characters equal columns (from HTMX's equal
  `---` separators), so a long label wrapped to 8–10 lines beside nearly empty
  number columns, and a one-word header such as `Attempted` was hyphenated. A
  table that fits keeps its natural widths, and unequal widths an author wrote
  in hand-made Markdown are kept. A row that fits on a page is no longer split
  between two pages; a row taller than a page still breaks, so none of it runs
  past the page bottom. The table, its header and data cells, its caption and
  both PDF standards are unchanged. Done by `pdf-report-tables.lua`, which hands
  each table to `pdf-report-table` in `pdf-report-tables.typ` (snag
  `export-the-caesi-d781d110`, which also covers todo `0cjfnl2`). A
  600-row × 7-column table compiles in about 4.2 s and 990 MB instead of
  2.3 s and 610 MB (and on 47 pages instead of 124).

## 0.1.138

- A `@browser` module's data argument may be a matrix. The page passes a
  `Matrix` (any `AbstractMatrix`) property as the array of its rows, `m[i][j]`
  holding Julia's `m[i+1, j+1]`, which is the shape `ReactiveKernels.js_source`
  modules take (RK 0.1.264, RK decision `1r7ufgm`); one without rows arrives
  as an empty array whose `cols` is its column count
  (`Object.assign([], { cols: 3 })` for `zeros(0, 3)`), and `[]` is 0×0.
  Entries travel as vector entries do: `Inf`, `NaN` and `-0.0` intact, `Bool`s
  as booleans. Such a page answered HTTP 500 before, an `ArgumentError` that
  the argument is a `Matrix{Float64}` (snag `browser-module-m-1d4c9b53`).
  Arrays of three or more dimensions stay refused.

## 0.1.137

- A number field drawn from a `number_domain` with a `step` takes any number
  in the interval, as the server does: the step is the grid of the slider and
  of the field's arrow keys, no longer the field's own `step` attribute.
  Before, a number typed between grid values (273 on `50 .. 400` with
  `step=10`, 12.34 on `5 .. 20` with `step=0.5`) was invalid in the browser
  (`stepMismatch`), so native submission refused it and a result that
  follows its inputs, `@browser` ones included, silently kept the last
  valid values. The field's `step` is now `any`, or `1` for a whole-number
  input; `number_control_script` keeps the arrow keys on the grid (273 steps
  up to 280 and down to 270) and announces each step as `input` then
  `change`, as the browser does. The slider, `number_record` and
  `data-htmxo-number` are unchanged (snag `use-number-domai-f74b4f09`).

## 0.1.136

- A `semantic_app(…; presentation=:tabs)` page's Markdown (`?plain`,
  `Accept: text/markdown`, `to_markdown_string`, and a report:
  `dispatch(…; report=true)`, `pdf_report`) writes each tab's **result**: its
  label, then what the result's own address answers as Markdown at the page's
  inputs (the report view in a report), as `/result` read alone answers it.
  A result computed in the browser (`@browser`) is drawn by the server, so a
  PDF gets its figures as pictures and its facts and tables as text, without
  its buttons. Before, such a tab wrote the view's HTML as one line of raw
  HTML, which a PDF drops, and a result the server computes wrote nothing
  but its label (snag semantic-app-tab-91e9c1d6). A result takes no number in
  a `numbered` document, as on the page. The HTML page is unchanged and asks
  no result it does not show; a Markdown read asks each tab's result once.
- Each tab's result there starts with a line naming the inputs it reads and
  their values as their controls show them: "Shown at: Slope (per day) 0.20;
  Intercept 80 units" (a number range's `digits` and `unit`, an option's
  label, yes/no for a checkbox, each switched-on record of a `Records` list).
  New `ErrorTexts` texts `shown_at` ("Shown at", German "Dargestellt bei"),
  `shown_yes` and `shown_no` ("yes"/"no", "ja"/"nein").
- `semantic_app(…; presentation=:tabs, report_states=["Steep" => (a = 0.5,),
  (b = 20.0,)])`: in a report only, each tab is written again for each
  declared state that names an input it reads, with that state's values in
  place of the page's, its own "Shown at" line and, before it, its caption
  when it has one. A state names inputs of the page (else an
  `ArgumentError`), and a value an input refuses makes the report throw.
  The page and an ordinary Markdown read are unchanged.

## 0.1.135

- A `SemanticProse`'s own headings follow the nesting, as a
  `SemanticSection`'s do, in its Markdown (`?plain`, `to_markdown_string`,
  `pdf_report`) and HTML (pages, static export) projections. Its shallowest
  heading is at the level a section opens where the prose renders (`##` /
  `<h2>` at the top of a page, one below each enclosing section or card
  heading), each other heading at most one level below the heading before it
  (a skipped level is closed up), none deeper than the sixth. A Julia
  docstring's `# Usage` inside a section headed `####` is now `#####`, so a
  `pdf_report` of it passes PDF/UA-1 where it failed with "the first heading
  must be of level 1" / "skipped from heading level 1 to 3" (snag
  `semanticprose-em-202acc7a`, design decision `120mafs`). Only heading lines
  change in the Markdown (a setext heading becomes one `#` line); prose
  without headings, or whose headings already sit there, is unchanged, and
  plain text keeps the source. Glossary-linked prose is placed the same way.
  A top-level prose's `# Title` is now `##` / `<h2>`; a page's title is
  `SemanticSection(title; level=1)`. Hand demotion of embedded headings
  (TenderViews' `_nest_headings`) is no longer needed and does no harm.

## 0.1.134

- `number_domain(…; digits=k)` sets how many decimals the generated number
  field **shows** while the reader is not editing it, written as
  `format_number(x; digits=k)` writes it: with `digits=4` a fitted default of
  0.003035586062774531 shows as `0.0030` (0.004 as `0.0040`) instead of the
  full value clipped by the field. Only the text is rounded: the field keeps
  the exact value, so the form submits it, `@browser` results read it, the
  page address leaves out a value equal to its default, Reset writes the
  default back, and clicking or tabbing into the field shows the value in
  full for typing. The rounded text is drawn over the field (`<span
  class="htmxo-number-value">` around the field holds a
  `.htmxo-number-shown` text, hidden from assistive technology) and
  `number_control_script` keeps it on the field's value; a page without the
  script shows the field's own text. `digits` is 0 to 10.
- **Behaviour change:** a value picked on the slider of a domain without
  `step` keeps three significant digits whether or not `digits` is given, as
  the explainer pictures pick them. Before, `digits` rounded slider values to
  that many decimals (0.0039 for `digits=4` where three significant digits give
  0.00387), which made a `log` slider jump in 10 % steps at its low end, and
  `digits` did not change what the field showed.

## 0.1.133

- Requires HTMX.jl 1.3 (`[compat] HTMX = "1.3"`). A report's Markdown
  (`pdf_report(value, …)`, `to_markdown_string(x; report=true)`,
  `dispatch(…; report=true)`) writes a plain `h.section` or `h.article`
  without the `---` line HTMX.jl puts before it for a Markdown reader, through
  HTMX.jl's `HTMX.with_markdown_seams`. Pandoc read that line as a horizontal
  rule, so the PDF drew a centred line before every such element where the
  page has none: under the title of `pdf_report(h.article(h.h1(…), …))`, and
  before each section of a report built from plain sections. A linked
  section's id stays on its heading (`## Eins {#t}`), an `h.hr()` keeps its
  rule, and ordinary Markdown (`?plain`, `Accept: text/markdown`, and
  `report=false` inside a report) keeps the `---`.

## 0.1.132

- **Breaking:** `bound(x)` writes a number as `format_number` writes it,
  on the server and after each browser computation alike: `2.0` writes `2`,
  `3.81e-5` writes `3.81·10⁻⁵` and an integer takes the thousands separator
  (`1,234`). `bound(x; digits=k)` writes exactly `k` decimals, halves away
  from zero (`0.120` for `digits=3`, `45` for `digits=0`), where it wrote
  Julia's `string(round(x; digits=k))` (`0.12`, `45.0`). A page that showed
  `bound(x; digits)` text changes to that; the value in the graph is never
  rounded.
- `bound(x; sigdigits, percent, texts)`: significant digits, a share as a
  percent (`percent=true` writes 0.45 as `45%`, `45 %` with
  `texts=table_texts(:de)`) and the table language's marks (`0,120`).
- `render_table(bound(p; columns))` on a `semantic_app` page that computes
  `p` in the browser is written again after each computation, offline and in
  a static `export_site` page: each cell as the server writes it (its sort
  value and ⬇ CSV value the unrounded number), with the reader's sort, the
  search, the row count and the hover-link keys following. Such a table
  refuses `cell`, `search_text`, `selectable`, a function `link_key` and sort
  keys computed by functions, which the browser cannot run.
- `ColumnSpec(label; digits, sigdigits, percent)` says how `render_table`
  writes the column's numbers (`"share" => ColumnSpec("Share"; digits=3)`);
  integers are number cells in such a column. `sortable_table` and
  `master_detail_table`, whose cells are built already, refuse it.
- `render_table(…; link_key=:column)` keys each row by its value in that
  column, a number as the browser's `String(x)` writes it (`20` for 20.0), as
  AlgebraOfVega keys a plot's marks by the same column.
- `format_number` and `number_cell` take `percent=true`; `TableTexts` has a
  `percent` text (`{number}%`, German `{number} %` with a no-break space).
  The percent is 100x with the decimal point moved, so 0.145 is 14.5 and
  rounds to `15%`.

## 0.1.131

- Requires HTMX.jl 1.2.1 (`[compat] HTMX = "1.2.1"`). Private block content
  written as Markdown is laid out by HTMX.jl's public `HTMX.markdown_div` and
  `HTMX.markdown_block_context` instead of HTMX.jl's internal Markdown stream.
  Where a block can start (top level, a `div`, `article`, `section`, `figure`,
  `blockquote`, `header`, after a list, nested marks) its
  `::: {.htmxo-private}` block is unchanged.
- Elsewhere it is one span that holds its content on its line, its parts set
  off by a line break: `## [*not public:* …]{.htmxo-private}` in a heading,
  `- [*not public:* \` then `…]{.htmxo-private}` in a list item, the same
  inside a link, and `[*not public:* <br>…]{.htmxo-private}` in a table cell.
  Before, a heading, list item or link held a fence that broke it.

## 0.1.130

- `bound(x; columns=…)` of single-value outputs (a number, a `Bool`, text) is
  a table of one row: `bound(prediction; columns=(:half,))` with
  `half::Float64` gives `Tables.getcolumn(b, :half) == [half]`, so a plot can
  draw a mark at a value the browser computes (a rule at `prediction.half`)
  and the page keeps it following the inputs offline. In the browser each
  such column becomes a one-value array (`n = 1`) for `AoV.updateData` and the
  `htmxo:bound-columns` event; before, the server refused the output as not a
  vector and the browser would have emptied the table. A table still does not
  mix single values and vectors: the error names both kinds and the table the
  single values can have. An output that is neither (a matrix) is refused
  naming its type.

## 0.1.129

- `numbered(content...)` numbers the sections, captioned figures and captioned
  tables inside it, with the same numbers in the HTML page, its Markdown and a
  `pdf_report` made from it: a `SemanticSection`'s title starts with `1`, `2.1`,
  …, a caption from `with_caption` or AlgebraOfVega's `with_plot_caption` with
  "Figure 3:", and a captioned table's with "Table 1:" (a caption without a
  title shows its number in bold by itself). `contents()` inside it
  shows its numbered sections as a box of links on the page and becomes Typst's
  contents list, with page numbers, in the PDF; `ref(id)` cites a numbered
  element as a link reading "Figure 3" or "Section 2.1". The words follow the
  page's language, or `texts=numbering_texts(:de)`. Pages that do not use
  `numbered` render as before.
- `render_caption` and `with_caption` take `kind=:figure` / `:table` (or
  `nothing` for no number) and `render_caption` an `id`, the figure `ref` cites.
- `pdf_report` switches Typst's own figure and table numbers off for a numbered
  document, so nothing is numbered twice, and refuses `number_sections=true`
  for it and `toc=true` beside a `contents()`.
- A `SemanticAlternatives` view after the first is wrapped in `html_only` in its
  HTML, which it already was in effect: Markdown writes the first view alone.
- `html_only(content)` renders its content in HTML as an element's child does:
  plain text, a vector or `nothing` inside it no longer throws a `MethodError`,
  and text is escaped. Content that rendered before renders the same bytes.

## 0.1.128

- A `semantic_app` result computed in the browser (`@browser`) follows an
  input while it moves: each `input` event of an input it reads (a
  `number_domain` slider held down, a number being typed) recomputes it, at
  most once an animation frame and never while its previous computation still
  runs, with the newest values. Before, it waited for the `change` on release,
  like a result asked of the server. A result asked of the server and the page
  address still follow the `change` (`semantic_follow_script`).

## 0.1.127

- A `semantic_app(…; presentation=:tabs)` page has a Reset button that returns
  every input to what the page shows when its address names nothing: the
  sidebar's and each tab's, to its `values=` entry or declared default; a
  computed default or `@resets` target follows its default again, and a list
  of records goes back to its one default record. The browser does it, so a
  static `export_site` page resets offline, with no request. Results, bound
  values, number sliders, choice lists and the page address follow as after a
  change the reader made. The open tab stays.
- The Reset ends the sidebar, or, on a page without one, follows each tab's
  inputs. A custom `layout(parts)` places `parts.reset` and a custom
  `render_operation(entry)` `entry.reset` (`nothing` where the default draws
  none). `semantic_app(…; reset=false)` draws none; on a page with
  `url_state=false` its forms carry `data-htmxo-defaults` for it. Its words are
  `ErrorTexts`' new `reset_inputs` (`Reset`, German `Zurücksetzen`).

## 0.1.126

- A caption without a title shows its summary alone: `CaptionSpec(; title="",
  short=text)` renders `text`, in HTML and Markdown, through `render_caption`,
  `with_caption`, the tables' `caption=` and AoV's `with_plot_caption`. Before,
  it rendered an empty `<strong></strong>` (`****` in Markdown) and a leading
  ` — `. A blank tier (whitespace only) is left out with its ` — ` in general:
  a blank summary leaves the title alone, and a long text with neither title
  nor summary opens the Markdown caption without a dash. Captions with a
  title are unchanged (snag `caption-empty-ti-4b05b833`).

## 0.1.125

- The table `bound(x; columns)` makes is its own `Tables.columns`, so it
  stays bound inside a plot's data: AlgebraOfGraphics' `data(b)` keeps
  `Tables.columns(b)`, which is now `b` itself and no longer a plain named
  tuple of its columns, so a plotting package reading a layer's data back can
  call `bound_columns_attrs` on it for the element that draws it. Its columns
  are only the chosen outputs: asking it for another output is an
  `ArgumentError` naming the columns it has.
- `bound(x; columns)` naming an output `x` lacks, an output that is not a
  vector, or outputs of different lengths raises the `ArgumentError` naming
  `x` that it was written to raise, where it raised
  `type Symbol has no field value`.

## 0.1.124

- `format_date(d; texts = table_texts(), style = :long)` writes a `Date` in
  the language of a table's texts, the date counterpart of `format_number`:
  `:long` writes `1 October 2015` / `1. Oktober 2015`, `:short` writes
  `1 Oct 2015` / `1. Okt. 2015` and `:month` writes `Oct 2015` / `Okt. 2015`.
  `missing` and `nothing` write `–`; a `DateTime` is refused (pass `Date(x)`).
- `TableTexts` carries the words: `months` and `months_short` (twelve names
  each, January first, the CLDR names browsers write) and the layouts
  `date_long`, `date_short` and `date_month`, which take `{day}`, `{month}`,
  `{month_short}` and `{year}`. `table_texts(; date_long = "{month} {day},
  {year}")` writes American English. A table's HTML is unchanged: the date
  texts are not among the texts a table sends the browser.

## 0.1.123

- `render_table` writes no value, `missing` or `nothing`, as `–` with no sort
  value and an empty ⬇ CSV field (an empty `number_cell`), in every column.
  Before, it wrote the words `missing` and `nothing`, which also sorted as
  text among the numbers. In a column of numbers or `IntervalEstimate`s the
  dash sits at the right with them, and an interval column keeps its five
  sort keys, its empty rows last in both directions; in a column of text or
  integers the dash sits where the text does, at the left or the column's
  `ColumnSpec(align)`. A custom `cell` still gets `missing` and `nothing` as
  they are. `master_detail_table` and `master_detail_pair` make a bare
  `missing` among the master cells the same empty number cell (it was loose
  text outside any cell); a bare `nothing` stays no cell, as HTMX drops a
  `nothing` child. A `SemanticTable`'s Markdown shows the dash too, and its
  tab-separated text writes an empty field (three in an interval column).

## 0.1.122

- A `semantic_app(…; presentation=:tabs)` page can compute a result in the
  browser. `@browser(name) = browser_module(file, entry)` gives a property an
  ES module that computes it from the inputs, in the contract
  `ReactiveKernels.js_source` emits (positional arguments named by its
  `INPUTS`, a named tuple returned as an object, errors named by their Julia
  exception); `browser_module(; source, entry)` takes the module's text. In a
  view, `bound(x)`, `bound(x.output)`, `bound(x.output[i])` and `bound(a)` (a
  `@param`), with `digits=`, show such a value; `bound(x; columns)` is a table
  for a plot, whose element takes `bound_columns_attrs(...)`. A result reading
  such a property is computed and redrawn in the browser with no request: the
  page carries its view for each value of the finite inputs it reads, the
  property's module and the data the module takes. A module error is shown in
  the result. So the page follows its inputs as a static export and offline.
- `export_site` refuses a page with such a result where it would show
  something stale, naming each part: a view showing an input outside `bound`,
  a result that reads inputs and computes nothing in the browser, a control the
  server draws again.
- A `presentation=:tabs` page applies the inputs its address names to its
  controls when it loads, so a static page's shared link reopens them; where
  the server already did, nothing changes.
- A `@relevant` condition comparing arithmetic of `@param`s (`a * b > 10`) is
  evaluated in the browser instead of re-rendering the control from the server.
- With DynamicObjects 0.5.21, which removed the private helper HTMXObjects read
  an operation's dependencies with, a `presentation=:tabs` page treated every
  operation as reading every input: all inputs went to the sidebar and every
  result was asked again on any change. Its dependencies are read again.

## 0.1.121

- `HTMXObjects.page_report()` says whether the Markdown being written is for a
  report. It is `true` while `pdf_report(value, …)` writes the value's
  Markdown, and inside `dispatch(…; report=true)` and
  `to_markdown_string(x; report=true)`, which take the new keyword. A
  `dispatch` or `to_markdown_string` made inside a report keeps it unless it
  passes `report=false`; live requests, `?plain` and `?markdown` reads, static
  exports and code outside any request read `false`. The flag reaches
  `@queued` bodies on a worker process and requests forwarded to another
  service slice.
- `report_view(content, report)` shows `content` in HTML and in ordinary
  Markdown reads, and `report` in a report's Markdown (`nothing` shows
  nothing there). Chrome is stripped from whichever view is shown. A figure
  can be an interactive plot in the browser, a summary in `?plain` and a
  picture in a PDF, and a control can stay out of a report without leaving
  `?plain`.

## 0.1.120

- `pdf_report` writes PDF/A-2a, the archival standard, besides PDF/UA-1:
  the file embeds its fonts, a colour profile and its metadata, and declares
  both standards in its XMP metadata, which `pdf_report` checks after
  rendering. `archival=` picks another PDF/A level Typst writes with PDF/UA-1
  (`"a-3a"`, `"a-2u"`, `"a-3u"`, `"a-2b"`, `"a-3b"`), or `nothing` for
  PDF/UA-1 alone; any other value is an `ArgumentError` before Quarto runs.
  Before, every report was PDF/UA-1 only, and `metadata=` could not change
  the standard. **Behaviour change:** PDF/A refuses two things PDF/UA-1 alone
  accepts, so a report holding a CMYK image (any PDF/A level) or a character
  from Unicode's private use area, such as an icon font's glyph (the `a`
  levels), now fails with Typst's message and a hint: convert the image to
  RGB, pass `archival="a-2u"` for the character, or `archival=nothing`.
  veraPDF 1.30.3 passes the default on `--flavour ua1` and `--flavour 2a`.

## 0.1.119

- `number_domain(lower .. upper; log, step, digits, unit)` declares, in a
  number input's `@options`, which numbers it takes and how a reader picks
  one. `semantic_app` and `operation_form` draw it as a slider with a number
  field beside it and the unit after it; a `log` domain spaces the slider
  evenly in ratio. A bare interval, `@options(x) = 0 .. 1`, is the same domain
  without settings. A submitted number outside the interval answers 400 at its
  field, for `@param`s, operation arguments and JSON bodies. Before, an
  interval `@options` was ignored: any number was accepted and the field had
  no bounds. A form value outside the range recovers the default, as an
  unavailable choice does.
- `number_record(domain)` gives the domain as plain data, and each generated
  control carries it as JSON in `data-htmxo-number`, for page scripts that
  compute in the browser.
- `ninput(nv; domain)` draws the same control by hand. The `htmx()` shell
  carries the new `number_control_script()`, which keeps the slider and the
  field on one value; the field alone still works without it.

## 0.1.118

- A `tabset`'s default `id` also reads what the call names the tabset by: its
  tab bar's `label`, its `url_param` and its tabs' `names`. So two tabsets with
  the same tabs and panels that a page tells apart by `label` (one model view in
  two cards) get ids of their own, and each tab's `aria-controls` names its own
  panel instead of the first card's. A tabset that passes none of them, or the
  default `url_param="tab"`, keeps the id it had. Which tab is open (`active`)
  and `preload` do not count. Tabsets alike in all of it still share an id;
  give them a `label` or an `id` of their own.

## 0.1.117

- An HTMX read whose answer swaps nowhere (`hx-swap="none"`) is answered with
  its finished result under every `OperationPolicy`, as a swap-less mutation
  already was: a progress poller in it would never poll. The page's
  `mutation_poll_script()` now declares the swap (`HTMXO-Swap`) on `GET`s too;
  a read that does not declare it polls as before. So `choice_list(nv, url)`
  loads its options from a slow route under the default `:auto` policy, where
  the list used to read the poller as a failed request; the options route
  needs no `@direct`.

## 0.1.116

- `choice_list(nv, url)` loads a long or shared option list from an address
  instead of carrying it in the page, and the new `choice_options(options)`
  answers that address with the rows an inline list draws. The page carries
  only the chosen option, as a row of the list, so the field shows, submits,
  validates and reads in Markdown before any request. The list asks the
  address when the reader first points at or focuses it, at the latest when it
  opens; every list on the page naming the same address shares one request and
  one parsed answer. A required list with nothing chosen still refuses an empty
  submit, and a failed load says so in the list and is asked again on the next
  open. A static export maps the address as a fragment. Inline
  `choice_list(nv, options)` is unchanged.

## 0.1.115

- The generated Services page preserves each request's `X-Forwarded-Prefix`
  in its refresh link, so observations can be refreshed behind a path-stripping
  reverse proxy.

## 0.1.114

- `dispatch(...; body=req.body)` accepts HTTP.jl 2's buffered `EmptyBody`
  and `BytesBody`, so a plain `HTTP.serve!` handler can forward empty, form
  and binary requests directly. Dispatch copies the unread bytes without
  consuming the original body. String and byte-vector inputs remain supported.

## 0.1.113

- Service plans include resource ownership, guarded operations and public/internal
  exposure in their descriptor. `service_topology` projects service blocks and
  grouped forwarding connections. The reflection explorer has a compact Services
  view, also available through `ReflectionRoutes(; plan)`.
- `ServiceRuntime` collects bounded per-operation and per-destination request,
  failure and latency summaries by default (`metrics=false` opts out).
  `service_observations` reads local or authenticated peer snapshots with process
  generation IDs and explicit failure states. `mount_service_monitor!` adds a
  protected Services page and JSON endpoints, readable while draining;
  `service_topology_view` embeds the same view with supplied observations.

## 0.1.112

- A `Records` card has a fold control, the disclosures' chevron as the first
  button in its head (`aria-expanded`, `aria-controls` naming its fields,
  accessible name `Fields`, German `Felder`: the new `ErrorTexts` text
  `record_fields`). Every card starts open. A folded card is its on/off box,
  its label and a summary of its values in field order: a choice by its
  option's label, a number after its field's label (`Age (years): 50`), a
  checked box by its label, other text as entered, leaving out fields that
  do not apply (`@relevant`); its fields, Duplicate and Remove give way until
  it is unfolded. The fold changes no input, result or page address (the
  fields are hidden by a stylesheet rule, not `hidden`). A new or duplicated
  card opens, a fold follows its card when the cards are renumbered and when
  the form's controls are drawn again, and a reload opens every card.
  (`cb10946`)
- A pill's option help (`radio_group`, a generated choice) is a
  `span.htmxo-option-help` after the option's label, which it was in the same
  text node before; it reads as before.

## 0.1.111

- An input section (`semantic_app(…; presentation=:tabs, sections)`) that
  holds one input whose label reads as the section's heading (ignoring case
  and surrounding space) shows that text once: the input's own legend, or the
  text its `<label>` starts with, stays its accessible name but is not shown
  (class `htmxo-heading-named`). This holds after the input refreshes. A
  checkbox's label, a label that reads otherwise, a section of several inputs
  and an app's `semantic_control` override are unchanged.

## 0.1.110

- `Records` cards are compact and show every field: a card field's docstring
  help text, the same in every card, is shown once under the cards after the
  field's label (each card's field names it in `aria-describedby`; it hides
  while the field applies to no card), while a computed `@help` stays in each
  card. Inside a card, fields sit closer, inputs are lower, pills are smaller,
  and a two-pill choice may share a row with a short field. A
  `semantic_control` override in a card receives `default` without the
  docstring's help text. (`10311f9`)

## 0.1.109

- `@resets(input) = source` (or a tuple of source inputs) restores a generated
  form input's current default when a named source changes. Reader overrides
  are cleared before controls, results and the page address refresh; later
  edits persist until another source change. Initial explicit URL parameters
  and direct requests retain their values. A delayed refresh preserves an edit
  made after it started. (`e81f9f8`)

## 0.1.108

- Vector choices render as checkbox pills up to `radio_max` and a searchable
  checkbox popover above it, also available as `choice_list(; multiple=true)`.
  The closed field shows the selected count and complete, wrapping labels;
  toggling keeps the popover open. Required groups need one enabled selection.
- Promoted vector `@param` controls retain their multiple-choice domain instead
  of becoming radios. Repeated values, filtered selections and explicit empty
  selections survive submission, dependent refreshes and page reloads. In query
  strings and form bodies, `name=` now means an empty vector; an omitted name
  still uses its default, and scalar blank handling is unchanged.
- Records vector fields and `set_inputs` retain complete selections, including
  an explicit empty selection.
- Choice-list Markdown includes every selected label. Built-in English and
  German `ErrorTexts` include `choice_selected` with a `{count}` placeholder.

## 0.1.107

- Generated single-choice controls with no enabled default remain unselected
  while dependent defaults, options and relevance conditions read the
  parameter's declared default. Empty option lists no longer replace a typed
  parameter with `nothing` while rendering a semantic application page.

## 0.1.106

- Generated single-choice controls recover a removed or disabled selection
  using the current declared default. Still-offered selections stay explicit;
  recovered computed defaults follow their inputs again. Without an enabled
  default the control stays unselected. Controls, hidden inputs and initial
  result URLs use the same resolved choice; direct execution keeps validating
  submitted values. Results and the page address wait for dependent controls
  to finish refreshing, including when that takes longer than the debounce.

## 0.1.105

- Generated semantic forms evaluate bare-identifier `@param` defaults, including
  imported constants and references to other inputs, instead of displaying or
  submitting the identifier's name. Explicit values still override defaults,
  and defaults that read another input follow its changes.

## 0.1.104

- A vector `@param` with `@options` keeps its declared vector type when a
  query or form submits one selection. Repeated selections resolve each
  option against the current domain, including object-valued options;
  unavailable or unknown selections answer 400.

## 0.1.103

- Bind `application/json` object fields automatically to POST/PUT/PATCH keywords
  and `@param`, including worker requests and keyword splats. Native JSON values
  use JSON.jl's typed conversion; explicit null and empty values override query
  fallback. Malformed bodies and rejected values answer 400.
- Include JSON request bodies and nullable types in OpenAPI descriptions.
- **Breaking:** JSON field names now participate in `__undeclared_params__`.
  Declare or allow intentionally accepted fields in apps using `:refuse`.

## 0.1.102

- `serve` flushes stderr after its readiness message, so Julia's default logger
  exposes `Serving on` immediately when output is redirected to a regular file,
  in both blocking and asynchronous modes. Custom loggers retain their own
  filtering and output handling.

## 0.1.101

- Extract overlapping, non-exhaustive `ServiceSlice` selections from one
  application. `service_plan` separates public, internal, forwarded and
  compile-only operations, preserves mount/input context, and uses DynamicObjects
  0.5.19 declaration selections to explain local requirements and unresolved reads.
- `ServiceRuntime` uses isolated HTTP routers and explicit peer boundaries, with
  shared policy, identity/context propagation and resource-owner validation.
  The first transport is blocking and buffered; `drain_service!` keeps admitted
  work owned by its process while rejecting new requests during replacement.
- Selectively compile handlers without executing their bodies. The runnable
  ordered-stream example verifies colocated/split parity and reader replacement
  while the writer keeps its PID, state and cache; measurements include both
  split processes rather than inferring savings from route counts.

- Documentation is organized into Start, Guides, Examples and Reference.
  The landing page and guides execute their Julia examples during the build.
- The sample-browser example renders its actual response and checks the selected
  records. Public exports are grouped by task and checked for reference coverage.
- Documentation builds reject warnings and no longer depend on recorded app
  embeds. The docs workflow follows the development branch used by the package.

- `JSONResponse{T,Status}` declares a JSON route's HTTP status and generated
  OpenAPI response entry together, for example `JSONResponse{CreatedItem,201}`
  for a POST that creates an item. Return the plain value; projection still
  follows `T`. `JSONResponse{T}` and `JSONResponse(value)` keep their 200 defaults,
  and finished responses returned by the body still pass through unchanged.

## 0.1.100

- A `@param` whose default is computed from other inputs
  (`@param threshold::Float64 = criterion.threshold`, `criterion` reading `output`)
  shows the value it computes in every generated control, and follows it until the
  reader sets it. A number or text field and the hidden inputs of a generated form
  carried the default's source text (`value="criterion.threshold"`), which the page
  then sent and the view refused with 400; the controls of an option domain showed the
  value, but kept the one computed for the inputs the page opened with. Now a control
  that shows its computed default is marked `data-htmxo-follows`, the page sends no
  marked field and no hidden copy of it (the server computes the default for the
  inputs sent), and its control is drawn again when an input the default reads
  changes. A value the reader types or chooses, one the page address names, one
  `values=` gives and one `set_inputs` sets is sent as before. The page address keeps
  such an input once the reader sets it, even at the value its default computes
  (`data-htmxo-address` gives it `null`); a computed default that reads no input
  (`@param fit = first(fits)`) keeps the value it computes there, as before.
  `semantic_refresh_script` and `semantic_follow_script` do this; a hand-built
  `<head>` includes both, as before.

## 0.1.99

- `ColumnSummary` accepts interval values for summaries with bounded inputs.
  Rendering preserves the range, including signed ranges, in HTML, Markdown
  and CSV. Empty intervals and unsupported interval arithmetic are rejected.
- Numeric formatting accepts an explicit significant-digit budget for summary
  cells, with display and sorting based on the underlying value.
