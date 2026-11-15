# Changelog

## Unreleased

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
