# Changelog

All notable changes to HTMXObjects.jl are documented here, newest first.

Every landing that adds or changes public API (an export, a keyword, a method,
or documented behaviour a dependant can call) bumps the patch digit in
`Project.toml` and adds its entry under a new heading at the top of this file.
An entry that breaks something a dependant relies on says **Breaking:** and
what to change. The minor digit, the breaking one in
[semantic versioning](https://semver.org/) before 1.0, has not moved yet.
A package or app that calls that API states the version as its floor, for
example `[compat] HTMXObjects = "0.1.1"`. An environment that pins an older
HTMXObjects commit is then refused when it resolves, with
`Unsatisfiable requirements detected for package HTMXObjects`, instead of
failing at render with a `MethodError`.

## 0.1.27

- `pdf_panel(documents; id, link, texts)`: a side panel that shows a PDF
  beside the content quoting it, every page one below the other, each drawn
  by PDF.js as it comes into view, with the passage of every reference marked
  on its page in the reference's colour. `pdf_ref(text, url; page, panel,
  quoted, key, hue)` is the reference: a chip that links to `url#page=N`
  (its Markdown) and on a page with the panel opens it at the passage.
  Every reference and mark is always lightly highlighted; pointing at one
  shows it and its counterparts more strongly and scrolls nothing; only a
  click moves: a reference's click opens the panel at its passage, a mark's
  click goes to its reference. References, marks and linked table rows share
  one hover-link group (`htmxo:link`). `pdf_toggle(panel)` shows and hides
  the panel, `pdf_beside(content, panel)` pins it beside the content, and
  `pdf_panel_texts(:en | :de; texts...)` gives its words (by default in the
  page's language). `window.htmxoPdf.show`/`.toggle`, and the events
  `htmxo:pdf-toggle` and `htmxo:pdf-goto`, serve page scripts. Lifted from
  TenderViews' crosswalk originals panel; `examples/pdf_panel.jl` is a
  runnable demo.

## 0.1.26

- `compose_box(name; submit=:modifier)` makes Enter and Shift+Enter insert a
  new line in the box and Ctrl+Enter or Cmd+Enter send its form. The form's
  submit button sends as before. Use it where readers write several lines or
  do not expect Enter to send. `submit=:enter`, the default, keeps the
  existing behaviour: Enter sends and Shift+Enter inserts a new line. A box's
  markup is unchanged unless it passes `:modifier`, which adds
  `data-htmxo-submit="modifier"` to the textarea. A hand-written
  `htmxo-compose-textarea` opts in with that attribute too. Any other `submit`
  value throws an `ArgumentError`.

## 0.1.25

- A table column whose texts start with the same number now sorts by the
  rest of the text: `2 x 5`, `2 x 10`, `2 x 15` in that order, and reversed
  when sorted descending. Before, two such texts compared equal, so a click
  on the header turned its arrow and left the rows where they were. Texts
  with the same leading number compare as whole texts with each run of
  digits read as its number, as `Intl.Collator`'s `numeric` option does
  (`2 x 05` equals `2 x 5`). This holds for a click (`sortTable`) and for the
  order `sortable_table(...; default_sort)` writes on the server. Different
  leading numbers, and texts that do not start with a number, sort as before.

## 0.1.24

- A number control shows a float as the shortest text that reads back as the
  same number: `10000`, `-50`, `0.5`, `1000000`, `1.5e-5`, not `string`'s
  `10000.0` or `1.0e6`. It is written as `format_number` writes it, with `.`,
  no grouping and an `e` exponent for a power of ten, the form
  `<input type="number">` reads. This covers `ninput`'s value, `rinput`'s value
  and its `<output>`, and so the float fields `semantic_app` and
  `operation_form` generate, with their defaults and the values a page's
  address or a submitted form names (`?threshold=10000` shows `10000`).
  Integer values and strings are unchanged.

## 0.1.23

- `HTMXObjects.pico_page` draws a site frame: `brand` (the header's home link,
  `label => href`), `nav` (the main navigation: `label => href` links,
  `private(label => href)` links, or elements placed as they are), `nav_label`,
  `footer` and `skip_link`. The link to the page being read carries
  `aria-current="page"` with nothing passed for it: the shell reads the
  request's address, forwarded prefix included. The entry whose `href` is that
  address or the longest one above it is marked; the app's home only on
  itself. The nav's name and the skip link's text follow the page's language
  ("Hauptnavigation", "Zum Inhalt springen" on a German page). The skip link
  shows once the keyboard reaches it and moves to `<main id="main">`. Without
  `brand` and `nav` the page is unchanged. Before, apps built this frame on
  `htmx()` themselves (ArbeitsplatzAtlas, VerkehrsStrukturdaten, ODLPlaus,
  PFIVergleich, MietspiegelBayes, DBSVergleich, RegionExplorer's
  `explorer_page`).
- `pico_page`'s `pico_version` defaults to Pico's pinned release under vendor
  assets (`assets=:vendor` or a mount path), so `pico_page(content;
  assets=:vendor)` works without `pico_version=HTMXObjects._PICO_VERSION`. The
  CDN default stays `"2"`.
- `pico_page` passes every keyword it does not name itself to `htmx`
  (`katex_version`, `prism_version`, `feedback`, …), not only `extra_head`,
  `assets`, `runtime`, `tables`, `error_texts`, `lang` and `title`.
- `htmxo_utility_styles` hides `.htmxo-skip-link` until it has focus and sets
  a header nav link with `aria-current="page"` in bold.

## 0.1.22

- A static export (`dispatch(...; static=StaticExport(...))`, `static_transform`,
  `record!`) treats an `hx-get` whose request sends values as a control a
  static server cannot serve, like one whose address has a query: htmx puts
  those values in the query of a GET. They are a `<form>`'s fields, a named
  `input`/`select`/`textarea`/`button`'s own value, and what an `hx-include`,
  `hx-vals` or `hx-vars` on the element or an enclosing element adds (an
  `unset` value stops what an element inherits). Unless `url_map` maps its
  address, such an element is disabled, or removed under `controls=:remove`.
  Before, only the address was looked at, so a pager form
  (`<form hx-get="/qt/fit/ppc">`) kept live controls whose requests 404 on a
  static host. A `url_params` element keeps its `hx-get`, since the export
  gives it the file of each value it declares. `export_site` is unchanged: its
  crawl maps every address of the app.

## 0.1.21

- `send_ahead(content)` puts finished parts in front of the reader while a
  slow `:auto` read is still running. Each part lands once, in the order
  sent, in a region above the running poller's progress tree, and the route's
  finished answer replaces the parts with the poller. A part's scripts run
  once (AlgebraOfVega's `append_data` / `replace_data` / `update_spec` for a
  figure an earlier part drew) and its `hx-swap-oob` elements replace their
  targets, so a figure fills dose by dose without being drawn again. Parts
  reach the page on its operation stream (`ahead` events) the moment they are
  sent, and with the next poll otherwise. Every page that follows the same
  computation gets the same parts. A Markdown or `?plain` read, a blocking
  `dispatch`, a static export and an answer within the grace period get the
  finished answer alone; there `send_ahead` does nothing. A refresh of a
  `data-htmxo-live` target (a `semantic_app` tab whose inputs changed) shows
  the old result until its first part arrives, which replaces it. The `htmx()`
  shell installs the new `sent_ahead_script()` with the Treebars assets.
  Before, a running read showed only its progress tree until it returned
  (snag `an-auto-read-on-8585ef04`, design decision `036a5ea`).

## 0.1.20

- A `semantic_app(…; presentation=:tabs)` page keeps its inputs in the page
  address. After the reader changes an input of the sidebar or of a read's
  tab, every such input whose value differs from its default is a parameter
  of the address beside `?tab=` (`/?tab=dose_response&basis=cohort&subjects=40`),
  written with `history.replaceState`; an input at its default, an empty one
  and one `@relevant` hides are left out. The page shows the values its
  address names, a tab's own arguments included, so a reload or a shared link
  reopens the same inputs and results. Before, only `?tab=` was kept and a
  reload reset every input. `url_state=false` turns it off for one page.

## 0.1.19

- `export_site` writes one file for a page that applies its address in the
  browser, with no `file_name` of the app's. A page address with a query
  (`/?region=09&jahr=2024`, a region explorer's zoom link) shares the file of
  its page when that page is in the bundle too and its `url_params` elements
  declare every parameter of the query with `values` holding the query's
  value: links to it name `index.html?region=09&jahr=2024`, and the page's
  runtime loads the view from the fragment written for it. Before, every such
  address was a page file of its own (`index-jahr-2024-region-09.html`)
  unless the app passed a `file_name` that named it with its query
  (RegionExplorer apps, ArbeitsplatzAtlas, VerkehrsStrukturdaten). A page
  address whose query the page does not apply that way (a parameter no
  element declares, or declares without `values`, a value outside them) is
  still a file of its own; a `file_name` that names an address with its query
  works as before.

## 0.1.18

- `python_service(…; models)` runs a `@slic` model's Stan program through
  BridgeStan and samples it with nutpie; CmdStanPy and CmdStan are gone from
  the generated service (user decisions `1g9p2nw` and `0i2b1wr`).
  - `fit` samples with nutpie (pinned `0.16.11`) over the BridgeStan library
    of the program.
  - `predict` and `log_likelihood` evaluate the program at each posted draw
    with BridgeStan's `param_constrain(…, include_tp=True, include_gq=True)`,
    so its transformed parameters and generated quantities are computed from
    the request's data. CmdStan's standalone generated quantities answered a
    transformed parameter with the fitted values instead.
  - The requests and responses are unchanged: a draw is still the
    constrained value of each parameter.
  - **Breaking** for a deployment of a generated service with a Stan model:
    `pyproject.toml` depends on `bridgestan==2.9.0` and `nutpie[stan]==0.16.11`
    instead of `cmdstanpy` and needs Python 3.12 or later (nutpie), and the
    `Dockerfile` installs BridgeStan's C++ source (`BRIDGESTAN`) and `curl`
    instead of CmdStan. Regenerate the service.

## 0.1.17

- A generated single choice is never a native `<select>`
  (`semantic_app`, `operation_form`):
  - Up to `radio_max` options it is a row of pills. **The default `radio_max`
    is now 8** (it was 4), so a choice among 5 to 8 options that rendered as a
    `<select>` now renders as pills.
  - Past `radio_max` it is a searchable drop-down, `choice_list`, instead of
    a `<select>`. A required choice without a default now starts with no
    option chosen, as pills do; the `<select>` silently submitted its first
    option.
  - A `multiple` domain stays a `<select multiple>`, and an `allow_custom`
    domain stays `sinput_custom`.
- `semantic_app(…; radio_max)` sets the cutoff for every control of the
  surface, `presentation = :stacked` or `:tabs`, the shared sidebar's
  included. A refreshed shared control keeps the cutoff, which it also does
  now for `operation_form(…; radio_max)`.
- `choice_list(nv, options; label, value, show_when, required, texts)`: a single
  choice among many options for an app's own forms.
  - It is a field, styled as an input, that opens the options as a popover
    under it, with a search field. Typing filters the list, ignoring case and
    accents; the arrow keys move, Enter or a click chooses, and Escape or a
    click elsewhere closes it.
  - The options are radios, so it submits, validates and drives `show_when`
    like `radio_group`. A `?plain` read shows its label and the chosen option.
  - `choice_list_script()` is its script; every `htmx()` shell carries it.
- `ErrorTexts` gains `choice_search` ("Search…" / "Suchen…") and
  `choice_no_match` ("No matching option" / "Keine passende Auswahl"). A
  generated list reads them from the object's `__error_texts__`.

## 0.1.16

- Touch screens reach every explanation a mouse reaches by hovering, without
  leaving the page or triggering the element's other action
  (`glossary_script`, in every `htmx()` shell):
  - A tap (touch or pen) on a glossary term's use shows its definition in the
    same box instead of opening the glossary. The box stays open, with a link
    to the entry (the glossary's `title` with →), until a second tap on the
    term, a tap elsewhere or Escape. A mouse click or Enter still opens the
    entry, and hover and focus are unchanged.
  - An explained column's `ⓘ` (`ColumnSpec` `help`, or a header named after a
    term) is a target of its own beside the label's sort button: hovering it
    shows the explanation in the box of a term's use, and a click or tap on it
    pins the box open, without sorting. A click or tap on the label still
    sorts, and the label keeps the explanation as its `title`.
- Markup: the term box is `<span class="htmxo-term-def">` holding the
  definition (`<span id=… role="tooltip">`, the link's `aria-describedby`)
  and the entry link `a.htmxo-term-more`. The column `ⓘ` is
  `<span class="htmxo-term htmxo-column-help">` after the sort button (before:
  inside it), holding `.htmxo-column-help-mark` and the box; with
  `sortable=false` the `title` moves from the `<th>` to a `<span>` around the
  label. Markdown, `?plain` and CSV export are unchanged.

## 0.1.15

- `semantic_app(obj; presentation=:tabs)` lays a semantic graph out as an app
  page: the inputs two or more operations read in an `app_layout` sidebar, one
  `tabset` tab per operation with the inputs only it reads above its result.
  `shared=[…]` chooses the sidebar, `active=` the tab the page opens on when
  its address names none (`?tab=` is kept), and `layout(parts)` /
  `render_operation(entry)` replace the page or a tab. A mutation keeps its
  form and button. The default `presentation=:stacked` is unchanged.
- On that page a read's result follows its inputs: it is asked for again
  300 ms after an input it reads changes while it is shown, and when its tab
  is opened, but not when the values it reads are the ones its shown result
  was asked for. The open tab's result starts with the page. The new page
  runtime `semantic_follow_script()` does this; the `htmx()` shell installs it.
- `@relevant(name) = condition` declares when a `@param` applies. Where the
  condition is false the parameter is its default, whatever was submitted, so
  such requests compute alike, and every generated form hides its control. The
  browser evaluates comparisons of `@param`s with literals (and `!`, `&&`,
  `||` of them); any other condition re-renders the control from the server.
  `show_when_script()` reads such conditions as JSON in `data-show-when`, and
  the `htmx()` shell now installs it, so a page no longer needs to add it.
- `semantic_control(obj, ::Val{name}, control)`: define a method to render one
  input of your struct your own way in every generated form.
- A generated checkbox for a `Bool` input submits `true`; it submitted the
  browser's `on`, which a `Bool` input refused (400). A `@param` read outside
  a request is its default, as an `@options` one already was, where it threw.

## 0.1.14

- A `show_when` widget hides on a Pico page too. It starts with the `hidden`
  attribute and `show_when_script()` sets and clears that attribute, where
  both used the `u-hidden` class. That class sits in `@layer htmxo`, and
  Pico's unlayered `label { display: block }` beats every layered rule, so
  `linput`, `ninput`, `sinput`, `sinput_custom`, `rinput`, `cinput` and
  `tinput` stayed visible with Pico loaded; only `radio_group`'s fieldset hid.
  Pico's `[hidden] { display: none !important }`, and the browser's own
  `[hidden]` rule without Pico, now hide every widget kind. Code that looked
  for `.u-hidden` on a `show_when` widget reads its `hidden` property instead.

## 0.1.13

- `IntervalEstimate(estimate, lower, upper)`, `format_interval` and
  `interval_cell`: an estimate with its interval in one table cell,
  `22 (13–34)`, with no more digits than the interval supports. All three
  numbers are rounded, halves away from zero, at the place of the second
  significant digit of the interval's width, and every decimal of that place
  is written: `3.21 (2.95–3.48)`, `3.20 (2.95–3.48)`, `22,400 (21,500–23,300)`.
  `width_digits = 1` rounds at the first. `log = true` keeps the significant
  digits that `upper / lower` supports, for a positive quantity spanning
  decades: `0.5 (0.02–3)`. `digits` and `sigdigits` work as in
  `format_number`.
- A table writes an `IntervalEstimate` as that cell by itself, as it does a
  float: in a `render_table` column, as a bare cell `master` returns, and as
  text in a `SemanticTable`'s Markdown.
- A column of interval cells gets the five `interval_sort_keys` by itself in
  `sortable_table`, `render_table` and `master_detail_table`, chosen from the
  `▾` beside its label, with no `ColumnSpec(sort_keys)`.
- The ⬇ CSV, and a `SemanticTable`'s tab-separated text, write such a column
  as three columns of exact numbers. The bounds are named with the
  `sort_lower` and `sort_upper` texts: `Median`, `Median / Lower bound`,
  `Median / Upper bound`.
- New `TableTexts` `interval` (`{estimate} ({lower}–{upper})`) and
  `interval_signed`, used when a bound is negative: `-5 (-8 to -2)`, German
  `bis`.
- Snag `show-a-posterior-83417d72`, design decision `1mges5z`.

## 0.1.12

- `SemanticSection(...; level=1)` makes a section the page's title. `level`
  (1–6) fixes the heading level a section opens at wherever it renders, and
  the sections inside it follow from there; left out (`level=nothing`), the
  level follows the nesting as before. A page made of one section had no way
  to have an `<h1>`: sections open at `<h2>` / `##` below a page's own title.
  A card directly inside a `level=1` section is `##` in Markdown, one below
  it.
- `glossary_section(g; level=1)` for a page that is the glossary alone: the
  glossary's `title` is the page's `<h1>` / `#`, its topics `<h2>` / `##`.
  `@get glossar() = glossary_section(__glossary__)` rendered `<h2>Glossar`
  and `<h3>` topics with no `<h1>`, and the app could not add its own `<h1>`
  without repeating the heading. The glossary `pdf_report` appends is
  unchanged. Snag `serving-verkehrs-a871a8f7`.

## 0.1.11

- `show_when` follows a radio group and a checkbox. `show_when_script()` read
  the first control the field named, a radio group's first radio whatever was
  checked, and listened to that one control alone, so a widget keyed on a
  `radio_group` or a `cinput` never followed the reader's choice. It now reads
  the field as the form submits it: the checked radio's value, a checkbox's
  `value` while checked and `""` while unchecked, every chosen option of a
  `<select multiple>`, including controls attached to the form with `form=`.
  It re-evaluates on any `change` on the page and after every htmx swap, so a
  group swapped in later needs no binding. For several values, `==`,
  `startswith` and `endswith` hold when one matches, `!=` when none equals.
- `linput` takes `show_when=` like the other labeled widgets. It passed the
  keyword through to the `<input>` as a stray `show-when` attribute, so the
  label never hid.
- The `show_when` value is spelled with `option_wire_value`, so an option
  object matches the radio or `<option>` that `radio_group` and `sinput`
  render for it. Plain strings, symbols, numbers and booleans are spelled as
  before. Snag `show-when-on-a-r-4239e3d1`.

## 0.1.10

- `[compat] DynamicObjects = "0.5.1"`. DynamicObjects 0.5.1 is the first
  version whose job queue carries the requester's `ScopedValue`s (`ffb9d70`),
  which 0.1.9 relies on for a `@queued` body to render for the request's
  reader in its page language. An environment that pins an older
  DynamicObjects is now refused when it resolves, instead of rendering such a
  body for the public. **Breaking:** DynamicObjects 0.4.x and 0.5.0 no longer
  resolve; update DynamicObjects to 0.5.1 or later. Todo `1vkv7a1`, snag
  `dynamicobjects-h-c580a9f3`.

## 0.1.9

- The request's audience and page language reach every task that runs a
  route's work: an `:auto` operation's body, a memoized compute, a `@queued`
  body in DynamicObjects' job queue, and a task the route spawns. What such a
  body renders itself (`to_markdown_string(x)`, `repr("text/html", x)`) is for
  the request's reader, and `HTMXObjects.page_lang()` there is the route's
  `__lang__`. Before, a `@queued` body rendered for the public, and every
  background body saw `page_lang() === nothing`. The `@queued` half needs
  DynamicObjects at or after `ffb9d70`, whose job queue carries the requester's
  `ScopedValue`s. HTMXObjects now depends on ScopedValues.jl. Todo `0qm6sdu`,
  from snag `queued-hx-respon-fb8c1312`.

## 0.1.8

- A glossary by topic, with other names, related entries and private terms
  (snag `moving-verkehrss-02fbe479`, design decision `16ra5z8`).
  `Glossary(["topic" => terms, …])` lists each topic under its own heading in
  `glossary_section`, topics and terms in the order written; a glossary given
  as terms stays alphabetical. New `GlossaryTerm` keywords: `also` (other
  names the entry shows, `"name" => "note"` for a note; shown, not matched),
  `see` (related entries by term or id, linked from the entry; an undeclared
  one is an `ArgumentError`) and `private` (the entry, its topic when all its
  terms are private, and every link to it and its definition are left out of
  public answers; a public reader sees its uses as plain text). The labels
  follow the page language (`Also:` / `See also:`, `Auch:` / `Siehe auch:`).
  The entry a link opens is highlighted. `pdf_report`'s appended glossary
  follows the report's audience and language, and links a related entry only
  where the report lists it.

## 0.1.7

- `ColumnSummary(:tally, item -> category; order, label, color)`: a group row
  of a regroupable `master_detail_table` counts its leaves in each category of
  a column (a status, a class), or adds up the `category => number` pairs a
  leaf gives as its own breakdown. The cell shows the total and a small stacked
  bar, one segment per category, on a scale the group rows of one level share;
  Markdown and PDF write `5 (shown: 2; partly: 3)`. It is computed on the
  server and again in the browser for every regroup, live and in a `record!`
  bundle; it sorts by and exports its total. Colours: `color`, else the new
  `--htmxo-category-1` … `-8` palette. Snag `group-summary-ta-fb04d13e`.
- `summary_cell(summary, items; texts)`: the same group cell for a row an app
  builds itself, such as a tree grouping's branch rows.
- `group_summary` may name a table's first column: the group's key and count
  move to the first column no summary names (before, it threw).

## 0.1.6

- `master_detail_table(...; groupings)`: a group row's id carries the
  table's name, `row-<id>--group--<path>` (`row-t1--group--20--mg`), or
  without an `id` a name from the leaves' keys. Two regroupable tables on one
  page whose groups share a key keep their ids apart, and a row update or a
  lazy group's rows land in their own table. `id = nothing` is no id. Leaf
  ids are unchanged (`5da191b`). **Breaking:** a page script that finds a
  group row by `row-group--<path>` builds `row-<id>--group--<path>` instead.

## 0.1.5

- A glossary of an app's terms, linked wherever a page uses them (snag
  `no-glossary-prim-026537ac`, design decision `0xuzhdk`). New exports
  `Glossary`, `GlossaryTerm`, `glossary_section`, `term`, `link_terms` and
  `glossary_script`. An app declares `__glossary__ = Glossary(terms; href,
  title)` on its root and mounts `glossary_section(__glossary__)` at `href`.
  Every answer under that root (a page, a fragment, an `hx_response`, `?plain`,
  a static export) then links the first use of each term in each section, table, figure,
  caption and disclosure to its entry, with the definition beside it on hover
  or keyboard focus. A `sortable_table` / `master_detail_table` column named
  after a term gets its definition as the column's ⓘ explanation.
- `pdf_report(…; glossary)`: with a glossary (by default the route's
  `__glossary__`), a report's term links point into the report, which ends
  with a section listing the terms it uses.
- `htmx()` page shells carry the glossary runtime (`glossary_script`) among
  their runtime blocks. It marks `<html>` with the class `htmxo-terms` and
  does nothing else on a page without terms.

## 0.1.4

- `record!`: a recorded `hx-get` whose address has a query (a zoom link,
  `hx-get="/region?key=a&measure=x"`) names the fragment file the recording
  writes for that address, `<record_base>/hx/region@key=a&measure=x.html`,
  when it records the address: a value a `url_params` element declares, or a
  query path in `paths`. The order of its parameters does not matter. Before,
  every `hx-get` with a query was disabled. Any other one still is
  (`b76c6ca`).
- `record!`: a query path in `paths` is saved under its query
  (`/region?key=a` → `region@key=a.html`, `hx/region@key=a.html`,
  `md/region@key=a.md`), so two queries of one path are two files instead of
  a `_RecordDestinationCollision`. **Breaking:** a single query path was saved
  without its query (`region.html`); list the path without the query to keep
  that file (`b76c6ca`).

## 0.1.3

- `hx_response(value; …)`'s value is rendered when HTMXObjects answers, for
  that request's reader and in its page language. A `@queued` route that
  answers with it now shows the live app's reader its `private` parts (they
  were left out, and the page language was lost, because the body runs in the
  job queue's task), and a memoized `hx_response` value renders for each
  reader. Snag `queued-hx-respon-fb8c1312`.
  **Breaking:** `hx_response` returns an `HTMXObjects.HXResponse`, not an
  `HTTP.Response`. A route that returns it is unchanged. Code that reads its
  status, headers or body, or returns it from a handler outside HTMXObjects'
  routes, calls `to_response(hx_response(…))` first.

## 0.1.2

- `sortable_table(headers, rows; default_sort)`, and `render_table` and
  `master_detail_table` through it: the table writes its rows in the order a
  click on that header gives in the browser, so the first paint, `?plain`, a
  PDF and a `record!` bundle show the order the header says. Before, it only
  marked the header (`c8f3fa3`). A tree sorts each set of siblings, a grouped
  table its groups by their `group_summary`. **Breaking:** rows given in
  another order with `default_sort` set are now reordered. A row that must
  stay at the top marks itself `data_htmxo_pinned=""` (below); a caller that
  sorted its rows to match the header can drop that sort.
- `data-htmxo-pinned` on a table row: it stays ahead of the other rows in
  every sort, on the server and in the browser (`c8f3fa3`).
- A column sort in the browser reads a cell's `data-htmxo-number` when it has
  no `data-sort-value`, so a group sum sorts by its exact number; `1.234,5`
  sorted as 1.234 before (`c8f3fa3`).

## 0.1.1

The first version that names an API line. It carries everything on `devibe`
up to this release, so an "HTMXObjects ≥ `<commit>`" floor stated for any
earlier commit is met by 0.1.1. Among it:

- `private(content; public, mark)`: `mark=false` shows the content without
  the "not public" outline and label (`fc05a25`).
- `dispatch(…; lang)` and `to_markdown_string(val; audience, lang)`: the
  language of the answer and of the words HTMXObjects writes itself
  (`e9743c1`).
- `SemanticStatus(state; label)`: the word a reader sees for the state
  (`730d839`).
- `ColumnSummary(reduce, values...; sigdigits)` and
  `format_number(...; sigdigits)` (`1d77f71`).
- `master_detail_table(...; group_masters)`: the group rows alone after a
  browser regroup (`d01e891`).
- `ColumnSpec(label; sort_keys)`: several sort orders per column (`3ccf858`).
- `master_detail_table(...; initially_open_detail)`: `initially_open` opens a
  tree branch's rows and leaves its own detail closed; this keyword opens
  details (`7d111cc`).
- `SemanticArtifact(name, mime, bytes; target, label, size, texts)`: a
  download control that names its format and size (`11943f4`).
- `master_detail_table(...; groupings = [name => :children, …], leaf_key,
  leaf_order)`: a `children` tree as one of the groupings; it opens as the
  tree, and the flat list and the other groupings list its leaves, regrouped
  in the browser (`cdea7fb`).

## 0.1.0

Every commit from the first (`1a172b0`) until 0.1.1. The number names no API
line, so a dependant cannot use it as a floor.
