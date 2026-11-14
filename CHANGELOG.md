# Changelog

## Unreleased

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
