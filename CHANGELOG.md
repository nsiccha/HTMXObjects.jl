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

## 0.1.4

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
