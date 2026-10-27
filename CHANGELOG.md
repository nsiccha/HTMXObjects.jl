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

## 0.1.7

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
