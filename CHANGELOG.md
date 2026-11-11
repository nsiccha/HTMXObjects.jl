# Changelog

## Unreleased

## 0.1.102

- Bind `application/json` object fields automatically to POST/PUT/PATCH keywords
  and `@param`, including worker requests and keyword splats. Native JSON values
  use JSON.jl's typed conversion; explicit null and empty values override query
  fallback. Malformed bodies and rejected values answer 400.
- Include JSON request bodies and nullable types in OpenAPI descriptions.
- **Breaking:** JSON field names now participate in `__undeclared_params__`.
  Declare or allow intentionally accepted fields in apps using `:refuse`.

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
