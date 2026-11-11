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

- A group summary over values known only within bounds shows the range it lies in.
  A `ColumnSummary(:sum | :mean | :min | :max, …)` function, or a `:ratio`'s
  numerator, may return an interval `lo .. hi` (IntervalSets.jl, a new dependency) for
  a leaf whose value is not known exactly. The group row then shows `9–100`: the low
  ends and the high ends folded apart (Σ low / Σ denominator to Σ high / Σ denominator
  for a `:ratio`), each rounded by `digits`/`sigdigits`, or one number when both ends
  round alike. The server render, Markdown and PDF, `summary_cell` and the browser's
  regroup write the same text. A range sorts by its low end, and the ⬇ CSV writes
  `9–100`. Two new `TableTexts` texts join the ends: `range` (`{lower}–{upper}`) and
  `range_signed` for a negative end (`{lower} to {upper}`, German `{lower} bis
  {upper}`). An interval as a `:ratio` denominator or a `:tally` number throws, as does
  an empty interval. Before, any non-number threw `ColumnSummary: a value must be a
  real number, nothing or missing`, so a leaf of unknown value could only be left out
  (a group of unfinished steps read `100`) or counted as 0 (`9`, an unmarked
  understatement). Snag `columnsummary-ra-702fd9be` (ProjectPlans' work-package
  progress).

## 0.1.98

- `prewarm_routes!` and `prewarm_workload!`: `timeout` bounds a hang, not a
  compile. It now limits the time a request (and the follow-ups of one
  transport) takes outside compilation: the elapsed time minus the time the
  process spent compiling meanwhile. Before, it was a plain HTTP read timeout,
  so a slow or busy machine's cold first request failed an app's
  `@compile_workload` although the server answered (snag
  `precompile-bruno-329ff905`: 44 s for one page on two busy CPUs, against the
  45 s default). A route that hangs or computes past `timeout` still fails. A
  dependant that raised `timeout` only to cover compile time can drop that.
- `timeout` accepts any positive number of seconds, `Inf` for no limit; a
  fractional value used to fail every request with an `InexactError`. A
  non-positive one is an `ArgumentError`.
- `prewarm_workload!` closes its server at once (`HTTP.forceclose`) after a
  failure, so a request the server never finishes cannot hold precompilation
  open.

## 0.1.97

- With `configure_job_queue!(; workers=1)`, a worker-bound body can build links and forms
  from its object as a body in this process does. `query_url(path, obj)`,
  `query_url(obj; …)`, `hidden_inputs(obj)` and `get_form`/`post_form(…; obj)` forward
  the `@param`s the request set. In the worker an object has no live request, only the
  request's `@param` input (0.1.68), and these read that input now. Before, each raised
  `MethodError: no method matching queryparams(::Nothing)` and the route answered 500.
  Outside any request they forward only their overrides; they raised that `MethodError`
  too. Snag `query-url-in-a-w-b1bfa0bb` (Bruno's QT memo routes).

## 0.1.96

- A list of records: `@param scenarios::Records = Records(:regimen, :age, :weight;
  label="Scenario")` (new exports `Records`, `record_view`, `all_records`). Each record
  has a value for the named `@param`s, typed, checked and read under their `@options`,
  `@relevant` and defaults as those `@param`s are, per record. A route reads the
  records switched on as `NamedTuple`s of `label` and field values; `record_view(obj,
  record)` is the struct as it answers one record. A request names them
  `scenarios.<i>.<field>` (`.label`, `.on`); without any, one record of the fields' own
  values. On an app page the list is a card per record (Include box, label, Duplicate,
  Remove, and Add, which copies the last), its fields laid out as a section's; results
  follow it and the page address keeps it. Six new `ErrorTexts` texts word the cards
  (English and German). The follow script reads `name.<i>.<field>` as an input `name`
  (todo `1w1bnkx`, for Bruno's web-sim; decision `1a5bx6n`).

## 0.1.95

- A single choice among options that carry `columns` (an option record's field, a
  `NamedTuple` or `name => value` pairs) is drawn as a table of its options: a
  `sortable_table` with the option's label (a radio button) first and its columns after
  it. A click on a row, or Enter on a focused row, chooses it; the chosen row is marked;
  more than `radio_max` options get the search field. Results follow it and the page
  address keeps it, as for pills.
- `semantic_app(…; presentation=:tabs, place=(fit = :upload,))` draws a sidebar input's
  control in an operation's tab instead of the sidebar, still an input of the sidebar's
  form (`form=`): web-sim's table of fits beside the form that adds one.
  `render_operation` receives the placed controls as `entry.placed`.
- `set_inputs(; inputs...)` (exported): in a mutation's answer, sets inputs of the app
  page once a control offers the value, so the fit an upload added becomes the choice
  (todo `0we4wfo`, for Bruno's web-sim; decision `04rngh7`).

## 0.1.94

- A generated form draws help text under a `@param`'s control. A docstring's first
  paragraph stays the label; the paragraphs after a blank line are the help text, in a
  `<small class="htmxo-help">` the field names in `aria-describedby` (a span between
  backticks is code). The new `@help(name) = text` declaration computes it from any input
  or property for the request (`"14 doses of 60.0 mg every 24 h"`), and the control is
  drawn again when what it reads changes. `semantic_control` receives it as `c.help`.
  A one-paragraph docstring is a label as before.
- `CallerFault(status, message; param=:name)` names the input at fault; a missing or
  rejected submitted value names its parameter by itself. An htmx answer carries
  `X-HTMXO-Error-Param: <name>` and its article `data-htmxo-param`. On an app page
  (`semantic_app(…; presentation=:tabs)`) the message appears under that input's field,
  marked `aria-invalid`, and a result its tab already shows stays, faded
  (`data-htmxo-stale`), until an answer for corrected inputs replaces it. Inline, polled
  and worker answers alike; the Markdown answer is unchanged. `CallerFault` has a new
  field, `param` (todo `1tixesk`, for Bruno's web-sim; decision `04rngh7`).

## 0.1.93

- An app page groups its inputs under headings: `semantic_app(…; presentation=:tabs,
  sections=[…])` takes `heading => names` pairs and the new exported
  `InputSection(heading, names; settings=false)`. Each section is a `<fieldset>` whose
  `<legend>` is its heading, drawn wherever its inputs are placed (the sidebar or a tab),
  its inputs in the order it names them; sections marked `settings=true` come after the
  others, and inputs no section names keep their place, first. Inside a section, short
  fields (a number, a checkbox, a choice between two pills) share a row, so Age and
  Weight sit side by side in a 19rem sidebar. A field whose `@relevant` condition is
  false is hidden as before, and a section none of whose fields applies is hidden with
  them, also live in the browser. Placement, requests, the page address, results and
  the page's Markdown are unchanged. An input in two sections or one no operation
  takes is an `ArgumentError` (todo `1r8adzh`, for Bruno's web-sim; user decision `076o1gn`).
- An app can show a server fault's cause on the page: with `__show_error_cause__ = true`
  on its root struct (read along the `__parent__` chain), the article under
  `Something went wrong. Error ID: …` also shows the exception's type, bold, and its
  message in a wrapping block, and a disclosure *Log entry `<path>`* holding the whole
  log entry. Polled operations, `safely` panels and failures in DynamicObjects' worker
  process show it the same way; an exception that could not cross from the worker shows
  as `RemoteComputationError` with the worker's printout, its backtrace left to the log.
  A message over 16 KiB or a log entry over 256 KiB is left out whole, saying its size.
  Three new `ErrorTexts` texts word it (`log_entry`, `message_omitted`, `log_omitted`;
  English and German). Without the setting every article is byte-identical to before;
  a caller fault's article never changes (todo `02sz67d`, for Bruno's web-sim; user
  decision `076o1gn`).

## 0.1.92

- `live_thread(items; texts)` and `live_thread_texts(locale; texts...)` /
  `LiveThreadTexts`: the words the thread writes itself (the older-items
  control, "Start of thread", the "↓ N new" / "↓ Latest" pill, the status
  line's "… failed: …", "request timed out", "network error" and the
  `response` disclosure) follow the page's language, German under
  `__lang__ = "de"`, and any of them can be replaced. An English thread renders
  byte-identically to 0.1.91 (snag `rendered-the-kb-38730db8`).

## 0.1.91

- A `multipart/form-data` body that does not parse is the caller's fault, answered
  `400 Bad Request`, never 500 (snag `undeclared-param-65ddfd9b`).
  `multipartparams` and `bodyparams` throw the new caller fault
  `HTMXObjects.UnreadableBody(format, reason)`, where `reason` is what HTTP.jl's parser
  found wrong (`boundary delimiter not found`, `a part has no form-data name`, …).
  A route that binds a keyword or `@param` from such a body answers
  `Unreadable request body: not valid multipart/form-data (boundary delimiter not found)`,
  worded by the app's `ErrorTexts` (new text `unreadable_body`, English and German).
  Before, HTTP.jl's own error escaped as a 500.
- `__undeclared_params__` leaves such a body to the route. Under `:warn` or `:refuse`
  it submits no parameter names, one warning says its names were not checked, and the
  route answers as it would without a declaration. Before, the parse error escaped
  the check, so even `:warn` answered 500 before a route that reads its own body
  could answer it (the KB's `/code/upload`).
- **Breaking** for code that tells these failures apart by type: `multipartparams`
  used to throw HTTP.jl's `ErrorException`, or on HTTP 1.x a `MethodError` for a part
  with no form-data name or no header. Catch `HTMXObjects.UnreadableBody` and read its
  `reason` instead. A request that names no boundary still yields an empty dict.

## 0.1.90

- `ColumnSpec(label; align = :left | :center | :right)` aligns a column: its sortable
  header (label, `ⓘ`, `▾` sort menu and caret, still sorting) and every cell the table
  renders in it, as `data-htmxo-align` in the HTML the server sends (snag
  `sortable-table-h-6312a3b4`). It works in `sortable_table` (hand-built rows are
  copied, never changed; a cell that sets its own alignment keeps it), in
  `render_table(columns = [... => ColumnSpec(...)])` and in `master_detail_table`,
  including group rows and their summaries, row updates, lazy rows and the row the
  browser regroups from. Before, a sortable header could carry no alignment, so a
  right-aligned column's heading sat at the left edge, far from its numbers (the KB's
  Markdown tables with `---:`). Any other `align` throws an `ArgumentError`.
- Number columns are right-aligned by default: a number cell (`number_cell`, floats in
  `render_table` and `master` cells, `IntervalEstimate` / `interval_cell`, group
  summaries, any `<td>` with `data-htmxo-number`) sits at the right of its column, and
  a column whose cells are all number cells right-aligns its header. Pages built on
  `sortable_table_styles()` (every `htmx()` / `pico_page` page) show their number
  columns at the right with no change; `align = :left` keeps a column at the left.
  Markdown, CSV and search are unchanged.

## 0.1.89

- `copy_vendorfiles(dir; packages, runtime, pages)` takes the rendered HTML of a
  bundle's pages and writes only the vendor files they name (snag
  `static-export-ve-d88dbadd`): the Pico build a page links instead of all twenty,
  the runtime blocks its shell links instead of every block, page helper and
  component asset, and the libraries of `packages` it loads, with what those load
  in turn (KaTeX's fonts, every PrismJS grammar the autoloader can fetch). A page
  names a file through an element's `href` or `src` whose address ends in the
  file's path below `dir`, so pages of any folder and `assets` prefix count. On
  Portfolio's one-page site this leaves out 27 files, 1.83 MB. `pages` is one string
  or byte vector or a collection of them; a string without markup (a file name) is
  an `ArgumentError`. Without `pages` nothing changes.

## 0.1.88

- `pdf_panel_assets()` and `card_deck_assets()` join the page runtime that
  `htmx(...; runtime=:linked)` links (snag `pdf-panel-assets-69b95c16`). Placed in
  `extra_head` exactly as they return, for a page that mounts the component with
  `assets=false` (one `pdf_overlay` panel on every page, say), they become
  browser-cached files on the vendor mount instead of about 79 KB (pdf_panel) and
  15 KB (card_deck) of inline style and script on every navigation:
  `<mount>/htmxo/pdf_panel_styles.css`, `pdf_panel_script.js`,
  `card_deck_styles.css` and `card_deck_script.js`, each with its `?v=` content
  version. `vendorfiles()` serves them (immutable at the current version),
  `copy_vendorfiles` writes them into a bundle, and a default static export puts them
  back inline. An inline shell, and a component that carries its own assets, are
  unchanged.

## 0.1.87

- `pdf_overlay` and `pdf_beside` keep the panel above a bar fixed along the bottom of
  the window, as they keep it below a page's sticky header (`--htmxo-sticky-top`).
  Every placement (beside the content, on the right, below), its resize edge and the
  tab a closed panel leaves end above the higher of `--htmxo-sticky-bottom` (new: the
  height of an app's own fixed bottom bar) and `--htmxo-overlay-h`, the live height
  that the KB's overlay bar (`htmx(…; overlay=true)`) publishes, and follow the bar as
  it grows. The largest size below and "is this reference in view" count that band
  too. Before, the panel on the right and below reached the window's bottom, so the
  bar hid their lowest 70 px and the tab below entirely (snag
  `pdf-overlay-floa-0fc53f98`, reported by `Claude:pdf-crosslinks`).
- The panel's script now measures `--htmxo-sticky-top` as a length, so `3rem` counts as
  48 px rather than 3 px where it sets the largest size below, lifts a reference above
  the panel, and decides whether a reference is in view.

## 0.1.86

- `pdf_overlay(panel; placements=(:right, :bottom), placement)` floats a `pdf_panel` over
  the page, so the page keeps its width and layout: on the right (40 % of the window, at
  least 22rem, below `--htmxo-sticky-top`) or below (the whole width, half the window
  high; `--htmxo-pdf-sheet-height`). Mount it once outside the swapped region, with an
  empty document list, and every `pdf_ref` naming its id opens it (todo `0eqeadr`,
  decision `Claude:pdf-crosslinks/0v6tyyq`).
- `pdf_beside(content, panel; placements=(:beside,), placement)` offers the same
  floating placements beside its own. With two or more placements, the panel's bar has
  a switch between them (`data-htmxo-pdf-place` buttons, hidden on a narrow screen,
  where every placement lies below).
- The panel's inner edge resizes it in every placement: the divider beside the
  content, the left edge on the right, the top edge below. It is a focusable separator
  (arrow keys, Home, End) and follows a mouse, a pen or a finger. The placement picked
  last and each placement's size are kept in `localStorage` (`htmxo-pdf-placement`,
  `htmxo-pdf-size-<placement>`); a browser that keeps nothing gets the app's placement.
- A panel closed after showing a document leaves a tab on its edge that reopens it at
  the same document and place.
- A reference that the panel below would cover is scrolled just above it.
- A reference inside a modal dialog (`showModal()`) opens the panel inside the dialog,
  above its content and usable there; the panel goes back to its place, still open,
  when the dialog closes. Before, it opened beneath the dialog's top layer, where the
  dialog's inertness made it unusable.
- New texts in `PdfPanelTexts`: `placement`, `beside`, `right`, `bottom`, `resize`,
  `reopen`. `window.htmxoPdf.place(panel, placement)` switches from a script.
- **Breaking** for a page's own CSS only: the open `pdf_beside` grid has a third
  column, the 1rem divider between the content and the panel (it replaces the 1rem
  gap), and the panel's cell is `grid-column: 3`. On a narrow screen the open panel is
  the full-width sheet below (it was a card 60 % of the window high, inset by .5rem).

## 0.1.85

- `pdf_panel` shows HTML documents next to PDFs (snag `pdf-panel-shows-b0bebb33`):
  a cited section of a brief, a range of code, a page of the app. `pdf_ref(text, url;
  kind=:html, quoted, panel)` names its place as the address's `#anchor` (`page=` is
  refused for one), and `pdf_panel` lists it as a record `(; url, title, kind=:html)`
  beside its PDFs (`url` and `title => url` stay PDFs). The panel fetches the address
  with `HX-Request: true` and swaps the fragment in as htmx does, so the page's code
  highlighting runs on it; it opens at the anchor and at the quoted words (looked for
  from the anchor on first), marks them under the same reader rule as a PDF's passages,
  and hides the page line. The marks are boxes over the words, never elements in the
  fragment, and follow them as the panel's width or the fragment changes. New text
  `not_in_document` in `PdfPanelTexts`. `window.htmxoPdf.show` takes `kind` and
  `anchor`. A static export rewrites an HTML document's address to the fragment it
  writes below `hx/`.

## 0.1.84

- `export_site` writes a page or fragment whose inline `<script>`, `<style>` or HTML
  comment is longer than about ten million characters, such as a region map that carries
  its data inline. Such an export used to stop with
  `PCRE.exec error: match limit exceeded`: each script, style and comment was found with
  one regular expression matched across its whole text, and PCRE gives up after about
  ten million steps. Now only the opening tag is matched, and the closing tag is
  searched for from there, so a text of any length is read in time proportional to its
  length. What the export reads and writes is unchanged.

## 0.1.83

- Index and `@param` annotations resolve through `DynamicObjects.resolve_annotation`
  (DynamicObjects 0.5.14), so every annotation form resolves while a package image is
  written, not only `x::T`, `x::Mod.T` and `x::T{…}`: a call (`x::typeof(y)`), a `<:`
  or `>:` parameter (`xs::Vector{<:Real}`), a `where` clause, a tuple and a macro call
  (`x::@NamedTuple{a::Int}`) too. Only syntax that resolver cannot express still
  evaluates; while an image is written into a closed module that is refused with an
  `ArgumentError` saying to name the annotation (`const T = …`, then `x::T`).
  HTMXObjects' own resolver from 0.1.82 is gone. `[compat] DynamicObjects` is now
  `0.5.14`.

## 0.1.82

- `route!` registers an app while a package image is written. An app package whose
  `__init__` calls `route!` used to make every package that depends on it fail to
  precompile with ``Evaluation into the closed module `<Pkg>` breaks incremental
  compilation`` as soon as the app mounted an indexed `@include` or `@struct` with a
  typed index, such as `DataSources`' `source_item(name::Symbol)`. A `@compile_workload`
  that routes an app mounting another package's such page failed the same way, and so
  did `reflect` there. Registration evaluated each index annotation into the module that
  declares the include, and Julia refuses evaluation into every module but the one being
  compiled while an image is written. Annotations are now looked up by name: `x::T`,
  `x::Mod.T` and `x::T{…}` of those resolve anywhere. A guard that returns from
  `__init__` before `route!` while `ccall(:jl_generating_output, Cint, ()) != 0` is no
  longer needed.
- An annotation a lookup cannot express (a call such as `x::typeof(y)`, a `where`, or a
  `<:` parameter) still evaluates, which works at run time. While an image is written
  into a closed module it is refused with an `ArgumentError` that names the annotation
  and says to give it a name (`const T = …`, then `x::T`).

## 0.1.81

- `__undeclared_params__` lets an app refuse query and form parameters that a route
  does not take. A route has always dropped them and answered with its defaults, so a
  misspelled or guessed parameter got a wrong answer that looked right:
  `?raw=1&field=command` served what `?raw=1` serves. Declared on the root struct,
  `__undeclared_params__ = (; action=:refuse, allow=("from", "by"))` answers such a
  request `400 Bad Request` with
  `Unknown parameter: field; accepted parameters: raw, lang, from, by`
  (`HTMXObjects.UndeclaredParams`, worded by the app's `ErrorTexts`). `:warn` answers
  as before and logs one warning per request; `:ignore` is the default. It is read along
  the mount chain like `__lang__`, so a mounted struct can declare its own. A route
  takes its keywords, every `@param` from the root down, its semantic context inputs,
  the `allow` names and the framework's own (`plain`, `markdown`, `error`, `v`, `tab`,
  `__…`). Not checked: a route with a keyword splat, a browser's page load (its address
  keeps view state for the page's scripts), a JSON or other raw body, and a mutation's
  result poll. Without a declaration nothing changes.
- `ErrorTexts` gains `unknown_params` (`{names}`), `accepted_params` (`{accepted}`) and
  `no_params`, in English and German.

## 0.1.80

- `SemanticProse(@doc(f))` works on Julia 1.11 and later in a process without a REPL
  session, such as a script, a test run or a deployed app. Before, it failed with
  `MethodError: no method matching String(::Base.Docs.DocStr)`: there `@doc` returns the
  first stored docstring, unparsed, unless something has loaded the `REPL` standard
  library. HTMXObjects now loads `REPL`, so `@doc` gives a binding's whole documentation
  as a `Markdown.MD` on every Julia version, as it always did on 1.10.
- New dependency: the `REPL` standard library. Julia 1.10 always has it loaded, so
  nothing changes there. An environment that develops HTMXObjects by path needs a
  `Pkg.resolve()` to record it.
- `SemanticProse(doc::Base.Docs.DocStr; references, math)` renders one stored docstring
  alone, for example a single method's entry out of `Base.Docs.meta`. The docstring is not
  written to.

## 0.1.79

- A table writes the numbers in its texts with its `thousands` text, on the server and
  in the browser: the search count (`{shown}`, `{total}`), the selection bar (`{count}`),
  the `linked_inside_many` note, and a default group row's own count. A German table
  over 1,672 items now reads `1.672 von 1.672 Messstellen`, where it read
  `1672 von 1672 Messstellen` beside group sums that already wrote `1.672`. English
  follows its own separator: `1,672 of 1,672 rows shown`. A count under 1,000 is
  unchanged. A page exported earlier keeps its old runtime until it is exported again.
  Code that reads a number back from one of these texts, or from `[data-htmxo-group-count]`,
  now finds the separator in it; `htmxo:table-filtered` still carries plain numbers.
  Snag `table-count-with-cd40a1a4` (ODLPlaus:ux-audit).

## 0.1.78

- With `configure_job_queue!(; workers=1)`, a refusal raised in a `@queued` computation
  answers as it does with `workers=0`. A `CallerFault` answers its status and message, and
  a missing required `@param`, an `@options` violation or a value its type rejects answers
  400 with its message, inline or polled. An `__error__` hook reads the fault through
  `unwrap_error`. Before, each answered `500 Something went wrong` with the message lost
  (snag `caller-fault-in-53f41794`). A server fault stays a 500, and the error log keeps the
  worker's printout for both.
- The `[compat]` floor for DynamicObjects rises from 0.5.10 to 0.5.13, which carries the
  worker's exception to this process.
- **Breaking:** an `__error__` hook no longer gets `DynamicObjects.RemoteComputationError`
  from `unwrap_error(err)` for such a failure, only for an exception that cannot cross. That
  answers 500, and its log says why: it serializes to more than 1 MiB (a refused `@options`
  value carries its whole list, and a list of 60,000 short strings was over), holds a DynamicObjects
  object or something else that cannot be serialized, or has a type from a package this
  process has not loaded. A hook that tested for that error reads `err.cause` instead.

## 0.1.77

- A `private(...)` entry of a Pico `nav` shows its label ("nicht öffentlich", "not
  public") instead of an empty box, in a `pico_page` header, a breadcrumb and a
  sidebar, and its outline stays inside the nav's row. An entry inside private content
  shows no box at all. The cause was Pico's `nav li::before`, which beat the label;
  `pico_bridge()` now sets it. The label takes up about 100 px of the header, so a full
  one reaches its next line sooner: `test/site_frame.jl`'s header with one such entry
  now stays on one line down to a 900 px window, and used to down to 768 px.
  `nav li.htmxo-private { --htmxo-private-label: "intern"; }` shortens it.

## 0.1.76

- `live_thread(items; focus=key)` opens an item taller than the scroll box at its start,
  and does not follow new messages until the reader scrolls to the bottom. Before, it
  centred every item, so a long message opened in its middle with its start out of view:
  a 1500 px item in a 300 px box opened 600 px past its first line. An item that fits the
  box is still centred, and still follows new messages when it opens at the bottom.

## 0.1.75

- `master_detail_table(...; detail_toggle=:label)` no longer writes a link or another
  control inside the row's detail button. A row whose first cell holds one keeps it as
  it is and gets the default's separate control: ▸ in a flat table, ⓘ in a hierarchy or
  grouped table. Before, the first cell's `<a>` landed inside the `<button>`: invalid
  HTML, and a tap on the button hit the link, so the page navigated and the detail did
  not open. Rows with a plain label are unchanged.
- The same check now reads what a value writes, so a `SemanticLink` or a `Raw` link
  counts as a link in every mode. A `Raw` label that writes no control now counts as
  plain: in a hierarchy without `:label` it becomes the row's own button, like any
  other plain label, instead of getting ⓘ. Snag `first-cell-link-f4fd6680`
  (ODLPlaus:review:ux).

## 0.1.74

- `export_site(...; aliases)` can link an address to a file the bundle does not carry,
  and the export then never renders, copies or checks that address. Such a target is
  another site's URL (`https://…`, `//host/…`) or a path from the bundle's root that
  leaves it (`../station-kenn-K.html`). This lets a section exported on its own link
  pages of a site published beside it. `aliases` may also be a function
  `(address; fragment) -> target` that returns `nothing` for addresses it leaves alone.
  Before, any target that did not start with `/` was an `ArgumentError`. Snag
  `native-static-re-756c2710` (ODLPlaus:ux).
- A dictionary of `aliases` now matches an address whatever the order and escaping
  of its query's parameters. Before, a key matched only the exact string the crawl
  built. For a `url_params` value that string is the parameters in the element's
  declaration order, escaped with `HTTP.URIs.escapeuri`, so a key written in another
  order or escaping missed silently and the address was rendered. Two keys that name
  one address with different targets are an `ArgumentError`.
- A page that `file_name` puts in a folder (`gemeinsamer-fit/index.html`) now writes
  its links from that folder. Before, they were written from the root, so the export's
  reference check refused them. A fragment's links are written for the pages of the
  folder above its `hx/` folder. A page that loads a fragment written for another
  folder is now a failure. Exports whose pages all sit in the root are unchanged.

## 0.1.73

- `master_detail_table(...; detail_instance=true)` (and `master_detail_pair`) makes
  each row's lazy detail slot a place of its own (`data-htmxo-instance="<row key>"`,
  `instance_scope_script`), so rows that load the same fragment, such as one station
  in several day rows, keep their ids apart, below any place around the table. It
  needs `detail_url`; without it the table refuses with an `ArgumentError`. Tables
  without the keyword are unchanged.

## 0.1.72

- One fragment can be open in several places of a page at once
  (`instance_scope_script`, carried by the `htmx()` shell). Mark each place with
  `data-htmxo-instance="<key>"`. Every id an answer swapped into the place defines
  gets `--<key>` appended, and so does every reference to it in that answer: the
  attributes that name ids (`for`, `popovertarget`, `aria-*`, …), `#id` in links,
  `style`, SVG paint and htmx selectors, `data-*` values, and the string literals of
  inline scripts and handlers. The fragment keeps one address, so `export_site`
  writes it once, and the renaming happens in the browser, live and in an export.
  `master_detail_table` rows, lazy details, row updates and browser regrouping work
  inside a place. Snag `shared-fragment-e919a4d2` (ODLPlaus wrote one station view
  per place, 22,798 files, to keep its plot ids apart).

## 0.1.71

- A fresh request root (`RootProvider()`, or a custom `:request` factory) is a fresh
  root again, not a remount view. 0.1.68 remounted every root to carry the request's
  `@param` input to the worker, and with that a custom request factory's root that
  did not carry the current request was no longer refused, and a `private` part a
  function builds failed when it read its context after the route returned. Now the
  default factory passes that input when it builds the root, and a custom factory's
  root, checked first, is remade with it. Session and job roots are remounted as
  before.
- `[compat] DynamicObjects = "0.5.10"`. Its worker builds each fresh request root
  from that root's own construction inputs, which the fresh roots above rely on with
  `configure_job_queue!(; workers=1)`: on 0.5.8 and 0.5.9 the worker reused the first
  root it built, so a later request computed with the first request's parameters.
  An environment that pins an older DynamicObjects is refused when it resolves.

## 0.1.70

- `--htmxo-disclosure-padding` is the inner spacing of the `<details>` it is set
  on only. `pico_bridge` registers it as not inheriting (`@property`, universal
  syntax, `inherits: false`), and the summary bar takes its spacing from its own
  box. Before, a component that set the variable to 0 (as it must when it sets
  its own `padding`) passed that 0 to every ordinary disclosure nested inside
  it, whose bar and content then sat flush against its border. An unset
  variable still means `1rem`, and every disclosure that sets it on itself
  renders as before.
- **Breaking** for a value set on a wrapper that is not a `<details>` (`.app {
  --htmxo-disclosure-padding: … }`): it no longer reaches the disclosures inside.
  Select the disclosures instead: `.app details { --htmxo-disclosure-padding: … }`.

## 0.1.69

- A worker-bound body renders under the answer's page language and audience:
  `__init__` registers `_PAGE_META` and `_AUDIENCE` with DynamicObjects 0.5.8's
  `carry_to_worker!`, so `page_lang()` and `private` read in the worker as they do in
  the serving process (the glossary stays with the page shell). `configure_job_queue!(;
  workers=1)` is therefore offered only on a DynamicObjects that carries scoped values
  (0.5.8); on an older one a positive count is refused, as before on one without the
  executor.
## 0.1.68

- Worker-bound `@queued` routes preserve request-derived `@param` values,
  including parent forwarding and nested mounts. Request views carry serializable
  query and form input alongside the live request, so the worker uses the submitted
  values instead of silently using defaults. Typed conversion, required parameters,
  option domains, relevance, multipart uploads and form/query precedence use the
  same extractors in both processes; no application changes are needed.

## 0.1.66

- `configure_job_queue!(; workers=1)` meets DynamicObjects 0.5.7's worker executor: a
  `@queued` route or property computes in the worker process, its progress tree is rebuilt
  live under the computation's node (the operation's poller shows it unchanged), and a part
  it `send_ahead`s reaches the requesting operation's list as a DynamicObjects requester
  message. `configure_job_queue!(; worker_stall=s)` adds a watchdog that restarts a worker
  whose in-flight computations have been quiet (no progress frame, message or CPU time) for
  `s` seconds, failing them with `ComputeAbandoned` and recording the event;
  `job_queue_settings()` reports it. `runtime_snapshot().process.worker` and
  `system_load_panel` show the worker's pid, in-flight count and last message. The
  0.1.59 request-read guard and send-ahead forwarder, internal and unwired, are gone:
  DynamicObjects keeps `__req__`-reading bodies local and carries the parts itself.
  `[sources.Treebars]` is Treebars 0.1.6 (`e03f2c7`), which DynamicObjects 0.5.7 requires.

## 0.1.65

- Semantic content that holds HTML nodes reads as text in plain text. A `tabset`,
  a layout `h.div` or a `render_table` inside a `SemanticSection`
  (`repr("text/plain", section)`) printed Julia's `Node(:div, OrderedDict(…))`
  dump, tab-bar internals included. It now writes its text in the blocks its
  Markdown has, without the markup: each tab's label over its content (a lazy tab
  `Label (/address)`), a link `label (target)`, a table one tab-separated line per
  row, a list item `- item`. Scripts, styles and buttons write nothing, and a
  master/detail table's eager details follow it, as in Markdown.

## 0.1.64

- `configure_job_queue!(; workers=n)` forwards a worker count to DynamicObjects' worker
  executor behind `@queued`, so heavy computations run in worker processes and a
  first-call compile, a GC pause or a deadlock in them never stalls this process's
  pages, pollers and exports (the frontend/backend process split; design in brief
  HTMXObjects:process-split `wworuo`). `job_queue_settings()` reports `workers`. On a
  DynamicObjects whose `configure_queue!` does not take `workers` yet, `workers=0` is
  accepted and a positive count is refused with an `ArgumentError`.

## 0.1.63

- `pdf_report` lets table cells break after underscore runs in identifiers,
  including inline code. Long model parameter names now wrap inside their
  cells instead of painting over adjacent columns. The identifier's characters
  and the table's accessibility structure are preserved.

## 0.1.62

- `SemanticProse(doc::Markdown.MD; references=Dict(), math=true)` displays Julia
  documentation without treating unresolved `@ref` references as URLs. Supplied
  string-keyed destinations become ordinary links; other references keep their
  formatted labels. The normalized Markdown is shared by all prose projections,
  and the original doc object is unchanged. Pass `doc` instead of `string(doc)`
  to opt in; authored strings keep their existing source contract.
- `jldoctest` code blocks use Julia syntax highlighting, including named doctests
  and options. Their contents stay intact, and the browser no longer requests
  a nonexistent Prism `jldoctest` grammar.

## 0.1.61

- `pdf_report` keeps a `SemanticDisclosure` label with the start of its body,
  including eager tab labels and master-detail labels. A label could previously
  stand alone at the bottom of a page while its first heading and content moved
  to the next. Labels remain bold text, without adding a heading level, and long
  bodies continue across pages. Their Markdown now encloses the label alone in
  `::: {.htmxo-label}`; ordinary bold paragraphs keep their pagination. Lazy-tab
  links and empty disclosures keep their existing projection.
  **Breaking:** Markdown bytes include this fence. Regenerate saved Markdown to
  get the repair, and account for the fence if comparing or parsing the old form.

## 0.1.60

- `pdf_report` tags a code block as one Code element, with a paragraph per line.
  Quarto's highlighting tagged each token as a Code element of its own, an empty
  one for every line and a whitespace-only one for every space between two
  coloured tokens, and PAC's Quality tab warned "Tagged text consists of only
  whitespace" for each (103 in BRM's six-page model view). The colours stay those
  of Quarto's `arrow` theme; which words are coloured now follows Typst's grammar
  for the language, and code lines are set slightly closer. A blank line in a
  code block is kept on the page and left out of the tags.
  **Breaking:** `metadata=` can no longer set `syntax-highlighting` or
  `highlight-style` (an `ArgumentError`): each of Quarto's themes brings the
  warnings back. Remove the key.

## 0.1.59

- `staticfiles(folder, mountdir; bundle=true)` serves a finished site, such as an
  `export_site` bundle another process wrote, and `export_site` writes all of it: once
  the crawl reaches any of its files, every file of the folder is written at its own path,
  byte for byte, including the files only its scripts load. Before, an app that served
  such a bundle and exported itself got the one page its link named, without the
  page's styles and scripts (snag `private-prebuilt-1136df2c`).
- `staticfiles(...; private=true)` (and `dynamicfiles`) serves the folder to private
  readers only: a public answer is a private page's empty `404` (`X-HTMXO-Private:
  true`), so a public `export_site` writes none of it and leaves out the elements that
  link it.
- The reference check of `export_site` looks a relative address up where a browser
  resolves it: in the folder of the HTML file that names it (for a fragment below
  `hx/`, the folder of the page that shows it). It used to look it up in the root, so a
  page written below the root passed while its links pointed at nothing.
  **Breaking:** an export that passed that way now fails, naming each such reference.
- A mounted folder's `index.html` answers at the folder's address with a trailing
  slash; the address without one redirects (`308`) there, relative to itself, so the
  page's relative links resolve inside the folder. An export writes it as
  `<mount>/index.html`, and links to the folder name that file.
  **Breaking:** a client that does not follow redirects gets the `308` for the
  address without the slash; request the address with it.

## 0.1.58

- `pdf_report` sets math wherever the browser does. `\(…\)` and `\[…\]` lost their
  commands (`\[ q_{\mathrm{cut}}(\phi,\theta) \]` printed `[ q_{}(,) ]`, and veraPDF
  passed it), and a ```` ```math ```` fence printed as code.
  **Breaking:** Markdown that writes `\[1\]` to mean a bracket now gets a formula, as
  `render_markdown` already read it; write `[1]`.
- `pdf_report` keeps a TeX command outside any delimiters as text (`\alpha`, `C:\Users`),
  as the browser shows it. It disappeared without a word.
  **Breaking:** a `\newpage` that did nothing now prints; remove it.
- `pdf_report` sets `\!` and `\;` at their width, in every kind of math: Pandoc rounded
  `\!` to -1 em, which overprinted what stood before it, and `\;` to nothing.

## 0.1.57

- `pdf_report`: a web or mail address in `metadata=` (a subtitle, an author) becomes
  a link to itself, like one in the Markdown. It stayed text, and PAC (PDF Accessibility
  Checker) failed the report's Link completeness for it. The text of a link `pdf_report`
  cannot open that shows an address with a scheme or a mail address is linked too.

## 0.1.56

- Content units: `unit_tree(…; wrap=c -> SemanticSection("Im Projekt", c))` puts a
  heading or anything else around a tree, only for a reader and a layer with something
  to show, and the browser's layer switch hides it with its content.
  `unit_references(doc, targets; layer, separator, wrap)` links several units at once,
  with the same rule: a line's prefix goes with its last link.

## 0.1.55

- Content units, a document whose pieces of information each have one identity,
  several layers written separately and children at any depth:
  `SemanticUnit`, `SemanticUnitLayer` and `SemanticUnits` declare them;
  `unit_tree(doc, ids...; layer=nothing, control=true)` places them;
  `unit_reference(doc, target; label, layer, fallback)` links to one from elsewhere;
  `unit_ids(doc, ids...)` names what a tree places; `unit_view_control(doc; param)`
  switches a page to one layer; `unit_texts` holds their words. A layer takes any
  content and a `String` is Markdown, and a `Symbol` names another layer saying the
  same thing, which stands once among all layers. In a browser a unit shows its first layer and
  opens the others in place. A link to `#<id>` or `#<id>--<layer>` opens what holds
  it, on load, Back, Forward and after a swap, and a static export needs no server
  for any of it. `layer=:short` reads one layer alone, complete and in order.
  Layer and audience are separate: only layers declared `public=true` reach a
  public reader, so the others, their labels and the ids and titles of units with
  nothing public are absent from a public page, its Markdown, its PDF and its
  static export, and a reference or a link in prose to what they cannot reach
  goes. A page holding units in something else listens for the synchronous
  `htmxo:unit-before-reveal` and `htmxo:unit-reveal` events
  (`unit_script`). Every `htmx()` page carries `unit_script` and `unit_styles`,
  inert without units.
- The Markdown of a `SemanticSection` or `SemanticCard` title, a `SemanticLink`
  label and a `SemanticDisclosure` summary escapes `*` and a `_` at a word's edge.
  These are plain text and HTML shows them as written. An unmatched `*` also ran
  Pandoc's emphasis over the heading's `{#anchor}`, so `pdf_report` refused every
  link to `H*(10)`. A `?plain` reader now sees `H\*(10)` there.
- A table cell spanning columns counts them: it sorts under its first column, its row
  is not ordered by the columns it only covers, and a CSV leaves those blank, so
  later cells stay in their columns. Before, a later cell sorted and exported one
  column too far left. Tables without a `colspan` are unchanged.
- A table in `render_markdown` or `SemanticProse` sits in a `.table-wrap` like every
  other table: one wider than its column scrolls there instead of running over what
  holds it (a card, a `<details>`, half a table row).

## 0.1.54

- `pdf_report`: a letter with a combining mark also reads once in Chrome's
  PDFium and in xpdf. 0.1.52 gave its mark an empty ActualText span, which those
  two ignore, so they read the mark twice (`R̂̂`). One span now holds all the
  letter's glyphs, and the pages stay pixel for pixel. Measured with Poppler,
  xpdf, PDFium, MuPDF, pdf.js and pdfminer. pypdf reads `R ̂`, with a space.

## 0.1.53

- A slow row update (`master_detail_table(...; update_rows)` or `update_groups`)
  no longer leaves its interim poller on the page. The rows landed in the table
  and no swap replaced the poller, so it stayed in the request's `hx-target` for
  good, its running tree showing and its badge going stale. It now leaves when
  the rows land, and the target has what it held before, as after a direct
  answer. A row the poller stood in for (`hx-target="closest tr"`) goes back
  before it is updated. Under `serve`'s default operation stream the pushed
  answer has to reach the table first, which takes Treebars 0.1.5.
- A poller that a later request's poller replaced no longer comes back when that
  one leaves. What it displaced does.

## 0.1.52

- `pdf_report`: a letter with a combining mark and no precomposed form (`R̂`,
  written `R` and U+0302) reads once in the PDF's text layer, as on the page.
  Typst writes such a letter twice, `R̂R̂` in `pdftotext` and to anything else
  that reads the text layer, while veraPDF and PAC pass the file
  (typst/typst#8767). `pdf_report` now corrects the finished PDF. The pages
  stay pixel for pixel, and a report without such a letter stays byte for
  byte. It warns, naming the letter, when the font draws one with more glyphs
  than it has code points, and leaves that letter as Typst wrote it.

## 0.1.51

- `export_site` can render pages concurrently (keyword `parallel`), as many
  at once as the process can keep busy: its default threads, or fewer under a
  CPU quota (a container, a systemd scope with `CPUQuota=`). Pages render
  ahead of the crawl, each on a task of its own, and their files are written
  one at a time in the order a one-thread export writes them, so the bundle
  has the files, links and failures of one page at a time, byte for byte
  where a page draws no value anew for each render (a random id, a
  process-wide counter such as a `choice_list`'s element ids). It is the
  default when the process has more than one default thread and no more than
  it has CPUs, so start Julia with `-t` set to its CPUs: more threads than
  CPUs made an export slower (ODLPlaus, Julia 1.10, two CPUs: one page at a
  time 1,362 s, eight threads rendering concurrently 1,706 s). Two threads
  took 1,122 s on a quieter host and gained nothing on a saturated one
  (2,346 s against 2,069-2,638 s one page at a time, with up to 1.5 times the
  CPU), so pass `parallel=false` where other work needs the CPUs. The routes
  run as they run under `serve`, several at once, so state a route keeps between
  requests needs a lock, and a `file_name` function is called from several
  threads. Before, an export used one CPU however many it had.

## 0.1.50

- A plain string works wherever a caption is taken:
  `render_table(df; caption="AUC by dose")`, and likewise the `caption` keyword
  of `sortable_table` and `master_detail_table`, and `with_caption` and
  `render_caption`. It is a caption with only that title, the same as
  `CaptionSpec(; title="AUC by dose")`, as a string already is for
  AlgebraOfVega's `with_plot_caption`. Before, a table renderer took the string
  and then failed with a `MethodError` from `with_caption`.

## 0.1.49

- Tabsets with the same labels on one page switch only their own panels. Before,
  they shared their ids, so a tab click could hide its own panels and show
  another tabset's, leaving an empty panel that the other tab could not bring
  back. A `tabset`'s default `id` now comes from its labels and what its panels
  say, not from its labels alone. It stays the same from one render to the next
  as long as they do, and it changes with them. `private` content does not
  count, only its public stand-in, and a value of a type HTMXObjects cannot read
  counts by its type. Anything that names a tabset, such as a link to it, passes
  `id=`.
- Tabsets alike in all of it share an id and still work, eager and lazy: a tab
  finds its panel inside its own tabset. A lazy tab's `hx-target` is now
  `next #<panel id>`, not `#<panel id>`.

## 0.1.48

- A route's keyword splat receives the submitted fields it does not declare:
  `@post create(; template, fields...)` gets every other form field in
  `fields`, under its own name (`fields[:dose]`, `for (name, value) in
  fields`), so a form whose fields come from data needs no paired-list
  encoding. Values are as submitted: a `String`, a `Vector{String}` for a
  repeated field, an `Upload` for a multipart file. A field a declared keyword
  or the struct's `@param`s read, an empty value (an unchecked checkbox, a
  blank text field) and a framework name (`plain`, `markdown`, `error`, `v`,
  every `__`-prefixed marker) are not in it. A POST, PUT or PATCH reads the
  body and then the query string, as for a declared keyword. Generated forms
  render no control for the splat, `reflect` lists no parameter for it, and
  `route_url` accepts keywords such a GET route does not declare. A route
  without a splat still ignores the fields it does not declare. Before, the
  splat was read as a required field named `fields` and every request
  answered 400.

## 0.1.47

- `sinput`, `sinput_custom`, `soption`, `radio_group` and `choice_list` take
  option records besides plain values and `value => label` pairs: a
  `NamedTuple` with a `value` field and any of `label`, `disabled`, `help` and
  `group`, the spellings of DynamicObjects' `option_domain`, which may also be
  passed whole. A `disabled=true` option is shown but cannot be chosen (a
  faded pill, a faded list row the arrow keys skip, a disabled `<option>`); `help`
  follows a pill's label, is a list row's second line and a select option's
  tooltip; `group` heads list rows and makes `<optgroup>`s. They render through
  the same code as the controls `semantic_app` generates for an `@options`
  domain, so a hand-placed option that must show but not be chosen needs no
  hand-built `<select>` or fieldset. An `option_domain` passed whole keeps its
  labels, which iterating it lost. Every earlier spelling renders as before,
  including a `NamedTuple` without a `value` field (an option object
  identified by its `key`). Typing a disabled option's value into
  `sinput_custom`'s box does not choose it.

## 0.1.46

- `IntervalEstimate(estimate, lower, upper; width_digits, log, digits,
  sigdigits)` keeps `format_interval`'s rounding options on the value, and
  every table writes it with them: a `render_table` or `SemanticTable` column,
  a bare `master` cell of `master_detail_table` / `master_detail_pair`, and
  Markdown/PDF. A positive quantity spanning decades is
  `IntervalEstimate(0.5, 0.02, 3.1; log = true)`, written `0.5 (0.02–3)`
  instead of `0.5 (0.0–3.1)`, with no hand-built `interval_cell` rows. Options
  `format_interval` refuses for the interval are refused when the value is
  made. A keyword given to `format_interval(x)` or `interval_cell(x)` replaces
  the value's (`width_digits` alone; `log`, `digits` and `sigdigits` as one
  rule). The value prints as the call that makes it. Values made without
  options, and `format_interval` / `interval_cell` on three numbers, are
  written as before.

## 0.1.45

- Add the `minus` text to `TableTexts`: the sign of a negative number that
  `format_number`, `number_cell`, `format_interval`, `interval_cell` and the
  group summaries of `ColumnSummary` write, on the server and in the browser.
  English keeps `-`; German writes the minus sign `−` (U+2212), so
  `format_interval(-0.42, -0.61, -0.25; texts = table_texts(:de))` is
  `−0,42 (−0,61 bis −0,25)`. Sort keys, `data-htmxo-number` and the ⬇ CSV
  keep `-`, and a table's search finds `−0,42` from a typed `-0,42`.
  **Breaking:** German text with a negative number changes from `-` to `−`;
  a dependant that compares it with a hyphen writes `−`, or passes
  `table_texts(:de; minus = "-")` to keep the hyphen.

## 0.1.44

- Add `pico_color` to `htmx` and `pico_page`: the page's accent colour, as the
  name of one of Pico's 20 colour builds (`:cyan`, `:jade`, …; `:azure` is
  Pico's default). The shell loads Pico's own `css/pico.<colour>.min.css`, with
  its light and dark shades, from the CDN or the vendor mount, so an app no
  longer redeclares Pico's `--pico-primary*` variables in `extra_head`.
  `vendorfiles` and `copy_vendorfiles` carry every colour build of the pinned
  Pico. An unknown name, or `pico_color` without Pico, throws an
  `ArgumentError`.

## 0.1.43

- **Breaking:** Move `python_service` and its StanBlocks and ReactiveKernelsPPL
  model runtimes to PythonServices.jl. Add PythonServices with a compat floor
  of `0.1.0` and import `using PythonServices: python_service`; existing
  `python_service(AppType, dir; ...)` calls work when HTMXObjects is loaded.
  `openapi`, `OpenAPIRoutes`, `SwaggerRoutes`, and `JSONResponse` remain here.

## 0.1.42

- Add opt-in `ErrorRecorder` / `record_error!` for error-hook capture metadata
  (git HEAD, worktree status and UTC time) and a bounded, deduplicated failing-URL
  index. Existing error responses and logs keep their standard behavior.
- Add visibility-aware `poll_trigger`, `process_rss_bytes`, `system_load_panel`,
  and explicit `collect_and_measure!` / `last_memory_collection` /
  `memory_collect_panel`. Runtime snapshots and the dashboard now include
  current RSS and load averages alongside their existing memory measurements.

## 0.1.41

- `export_site` also shares the file of a page whose own address has a query.
  A page address with a query that adds parameters to another page in the
  bundle, such as `/station?kenn=K&region=de&ebene=tage` to a probe's own page
  `/station?kenn=K`, shares that page's file when its `url_params` elements
  declare every added parameter with `values` holding its value. Links to it
  name the page's file with the added parameters only
  (`station-kenn-K.html?region=de&ebene=tage`). Before, the only page such an
  address could share was its path (`/station`), so every view of a probe's
  page was a page file of its own (snag `odlplaus-static-02f57da3`, reporter
  ODLPlaus). The addresses wait as before until nothing else is left to
  render; those with fewer parameters are now decided first, so a page's own
  address with a query is written before the addresses that extend it, in any
  order of `pages`. Where several pages qualify, the one that leaves out the
  fewest parameters is taken. Deciding them no longer scans every waiting
  address each time.

## 0.1.40

- A table's search field, with its label and count, stays inside a column
  narrower than their line instead of widening the page. The label kept its
  text, the field (at least 8rem) and the unbroken count on one line, so in a
  column narrower than that line (about 480 px with German texts: a sidebar, a
  split pane, RegionExplorer's view pane at an 80 % map share) it ran past the
  column. The label now wraps: its text, the field and the count each move to a
  further line only when they no longer fit, the field shrinks below 8rem only
  in a column narrower than that, and the count breaks only when it alone is
  wider than the column. This covers `sortable_table`,
  `render_table(searchable=true)` and `master_detail_table`. Where the line
  fits, nothing moves. Two layouts change just above that width: a long search
  text puts the count under the field instead of breaking its own text beside
  them, and a grouped or selectable table can put the search beside its
  *Group by* pills, one line fewer, where the search used to take a line of its
  own.

## 0.1.39

- A table cell with `data-status` shows its status under Pico, as the docs say:
  `<td data-status="success">` and `th` are bold and take the status colour.
  Pico's own cell rule hid both before, so such cells become coloured and bold,
  and a `muted` cell becomes grey and bold. An app's stylesheet still wins, even
  a bare `td`, and `tr[data-status]` leaves its cells as they are.
- `--htmxo-success`, `--htmxo-warning` and `--htmxo-error` now hold 4.5:1 as
  text in light as well as in dark: `light-dark(#217d72, #2a9d8f)`,
  `light-dark(#9c6311, #e9a23b)` and `light-dark(#ca3f1c, #e76f51)`. The dark
  shades are unchanged. In light they were 3.32, 2.17 and 3.09:1 on a white page.
  Filled badges, `SemanticStatus` and banner edges use the same tones. A page
  that declares no `color-scheme` gets the light shades. `pico_bridge()` no longer
  names `--pico-color-green-550` and its siblings, which Pico's page stylesheet
  never defined.
- Status text in a hover-lit or selected table row moves towards the text
  colour like the row's other tones, so it keeps 4.5:1 on the tint.

## 0.1.38

- Text in a table row that hover linking (`link=`) lights or a selection marks
  stays readable in both themes. Pico's link, muted, slate-button and
  `del`/`ins` colours sit barely above 4.5:1 on the page, so the rows' tints
  took them as low as 3.9:1 on a row under the pointer, and to 2.97:1 (light)
  and 2.36:1 (dark) on a row both selected and lit. Inside such a row these
  colours now move towards the text colour and keep their hue, so each holds
  4.5:1. The tints, the outline, `--htmxo-linked-row` and `--htmxo-selected-row`
  are unchanged; an app that sets a stronger tint checks that contrast itself.

## 0.1.37

- A caption's long text opens from a small toggle at the end of the caption's
  row, beside its actions, in the look of the caption's buttons, instead of a
  full-width box in a row of its own. Beside an action a closed long text moves
  the figure by nothing, 63 px less per figure at 16 px text; in a caption with
  no actions it adds at most 4 px. Opened, the text spans the figure below the
  header, in a thin frame, and the toggle stays where it was. This covers
  `render_caption`, `with_caption`, `render_table(caption=)` and every caller of
  them. The markup and the Markdown are unchanged: `caption_style` moves the
  native `<details>`. Every other disclosure stays the Pico bridge's box. CSS an
  app wrote for `.caption-long` may need revisiting: the `<details>` now has
  `display: contents`, so rules on its own box no longer apply.

## 0.1.36

- A `pico_page` header that does not fit its window continues on further lines
  and stays in the page. Pico keeps a nav on one line, so labels broke (`In-`
  over `situ`) and the last entries ran off the right edge, which widened the
  page. The navigation now goes below the brand, starting where the brand does,
  and its entries wrap whole, each added line about 56 px tall. A header that
  fits its window stays where it was, also where it runs past `.container`. The
  rule is in `pico_bridge` and sits on `body > header nav`, so an app's own
  header on the `htmx()` shell wraps too. To keep one line, set
  `body > header nav, body > header nav ul { flex-wrap: nowrap; }` in the app's
  stylesheet.

## 0.1.35

- A flat `master_detail_table` passes axe-core's `aria-conditional-attr`. ARIA
  allows `aria-expanded` on a row only inside a `treegrid`, so its rows no longer
  carry it: the row's native detail control (▸/▾, or the label with
  `detail_toggle=:label`) carries `aria-expanded` and `aria-controls`, and the row
  carries `data-htmxo-detail-open="true"|"false"`. Hierarchy and grouped tables
  are `treegrid`s and keep `aria-expanded` on their rows. **Breaking:** CSS or
  script that reads `tr[aria-expanded]` on a flat `master_detail_table` row reads
  `tr[data-htmxo-detail-open]` instead. Rows built with `master_detail_pair`
  directly are unchanged, and still fail that rule in a `sortable_table`.

## 0.1.34

- A `tabset` follows the ARIA tabs pattern. Its tab bar is a `tablist`, each tab
  a `tab` with `aria-selected` and `aria-controls`, and each panel a `tabpanel`
  named by its tab, and these stay right through a click, a URL that names a tab
  and a static export. New keyword: `tabset(...; label="Auswertungen")` names the
  tab bar.
- A `tabset` works from the keyboard. Tab reaches the open tab; the arrow keys,
  Home and End move the focus along the tabs, and Enter or Space opens the one in
  focus. Moving the focus opens nothing, so a lazy tab still loads only when it
  is opened and the URL changes only then. The keys come from `tabset_script()`,
  which `htmx()` pages carry. A page with its own `<head>` that has not added it
  keeps every tab as a stop in the page's Tab order, opened with Enter.
- Opening a tab no longer touches the panels of a `tabset` nested inside it,
  which used to leave the inner tabset showing a different panel from its open
  tab.
- A tabset with `url_param=nothing` now carries the small inline script every
  other tabset has, for the case above. It still writes nothing to the URL.

## 0.1.33

- A `sortable_table` that fits its column stays in the page when something in
  a row sticks out past the column. The table runtime judged `fits` or `wide`
  from `wrap.scrollWidth`, which counts every descendant's overflow, so a few
  pixels in one open row turned a long table into a window-tall box, shortened
  the page and moved the clicked row off screen. It now reads the table's own
  width. A block in a row that really is wider than the column runs past it,
  and the page scrolls sideways; give it its own scroll box (`overflow-x: auto`).
- **Breaking** for a component that sets `padding` on its own `<details>`:
  `pico_bridge` no longer pulls a disclosure's `summary` out past the box's
  padding, which left it sticking out of any box whose padding had changed. The
  box has no padding of its own: the inner spacing, still
  `--htmxo-disclosure-padding`, sits on the bar and on `::details-content`.
  Default boxes render the same. A component's own `padding` now insets its
  bar and content inside its box, on top of that inner spacing. To keep the
  earlier inset, add `--htmxo-disclosure-padding: 0` to the component. A browser
  without `::details-content` (before Chrome 131, Safari 18.4, Firefox 143)
  draws the content flush with the box's border.

## 0.1.32

- `card_deck(cards; id, view=:grid, search=true, group_filter=true,
  view_param="view", card_param="card", texts=nothing, class="", assets=true)`:
  a deck of cards the reader sees as a grid (each group under its heading) or
  as a carousel (one card at a time, previous/next, its position, the arrow
  keys), and switches between the two. A search box filters the cards by their
  words (every word, any order, no case or accents) with a count of matches,
  and a group filter (pills, or a searchable list past seven groups) filters
  them by group; the carousel pages over the cards left. The view and the
  current card ride the page address (`?view=carousel&card=<id>`, or `#<id>`),
  so a link opens the deck at a card. The deck carries its style and script
  (`card_deck_assets`, `card_deck_styles`, `card_deck_script`) and needs no
  route, so a static export works as live. Its words follow the page's
  language (`card_deck_texts`, `CardDeckTexts`: English and German). Hooks:
  `window.htmxoDeck.show` / `.view` and the `htmxo:deck-change` event. In
  Markdown the controls are left out. Example: `examples/card_deck.jl`.
  Todo `0r7kj9c`, for the KB's flashcards.

## 0.1.31

- A static export (`export_site`, a `StaticExport` `dispatch`, `record!`)
  rewrites the files a `pdf_panel` and its `pdf_ref`s load as it rewrites
  their links: a reference's and the lone document's `data-htmxo-pdf-url`,
  and each chooser document's radio value. `export_site` follows them, and
  its reference check reads `data-htmxo-pdf-url` too. Before, only the
  `href` was rewritten, so an exported panel fetched the live address
  (`/unterlagen/lb`, a 404 outside the bundle) and showed "missing PDF".
  `pdf_ref` now always carries its document's title (`data-htmxo-pdf-document`,
  by default the file name of the address it was given), so a referenced file
  the panel does not list keeps its live title in an export. Snag
  `pdf-panel-static-81f73b0d`.

## 0.1.30

- `export_site`: an extensionless data address whose `Content-Type` the
  export's own table does not name takes the first extension the media-type
  database lists for it (mime-db, through the new dependency MIMEs.jl): an
  Xfig download (`application/x-xfig`) is written as `.fig`, a GIF as `.gif`.
  The types the table names keep the names they had (`image/jpeg` → `.jpg`).
  For a type the database does not list either (`application/vnd.myapp`),
  `file_name` is asked with `ext=""`: an app's own `file_name` names the file
  with an extension of its choosing, and the answer fails only when the name
  it gives has none. Before, such an answer failed before `file_name` was
  asked, although the failure told the app to pass one. Snag
  `export-custom-mi-904ff844`.

## 0.1.29

- `pdf_panel`: a document chosen in the chooser opens at its first page,
  whatever page the panel was at in the file before, and a reference at its
  own page. The moment another file is chosen or referenced, the pages, the
  page line and the place of the one shown go, and the panel says it is
  loading until the new file is shown; before, it went on showing the old
  file's pages and page line under the new file's name while that loaded.
  While the panel goes to a page, its pages (`data-htmxo-pdf-pages`) carry
  `aria-busy="true"`, which a browser test waits for to go. Snag
  `pdf-panel-choose-708af86e`.

## 0.1.28

- `pdf_panel`'s document chooser is never a native select box any more. One
  document is its title, as text; two to eight are a row of pills
  (`radio_group`'s look); more are a field that opens a searchable list
  (`choice_list`). A reference to an unlisted file adds it and draws the
  chooser again in the form its new number of documents calls for. The
  chooser keeps the `data-htmxo-pdf-document` mark; each document in it is a
  radio whose value is the file's address, and a lone title carries it as
  `data-htmxo-pdf-url`. The bar's controls stay together, the page line
  between its buttons, and the chooser takes a line of its own when it does
  not fit beside them. `pdf_panel_texts` gains `search` and `no_match`, the
  long list's search field and its no-match line. Snag
  `pdf-panel-docume-fcc431e2`.
- **Breaking:** a page script or browser test that read the chooser as a
  `<select>` (`select.value`, its `<option>`s) reads the checked radio in
  `[data-htmxo-pdf-document]` instead, or calls `window.htmxoPdf.show`.

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
