# Sample browser

The inventory below is synthetic. Each record identifies a sample, its material
and its storage location; it contains no patient data or measured outcome.
The application accepts a material name and returns the matching records as an
HTML table. The same route serves an ordinary browser request and an HTMX
fragment request, so the filtering rule has one implementation.

## Data

```@example samples
using HTMXObjects

@dynamicstruct struct Inventory
    samples = [
        (sample="S-A", material="plasma", location="Freezer A"),
        (sample="S-B", material="serum", location="Freezer B"),
        (sample="S-C", material="plasma", location="Freezer C"),
    ]
    matching(material) = filter(
        row -> isempty(material) || row.material == material, samples)
end

inventory = Inventory();
foreach(println, inventory.matching("plasma"))
```

`Inventory` owns the records and the selection rule. Its `matching` property is
indexed by the requested material. The empty string selects every record;
a nonempty string requires an exact match. This makes the response independent
of case folding, substring search and locale rules, which would otherwise need
their own contracts and examples.

The inventory is constructed before routes are registered and reused by later
requests. The records are treated as immutable for this example. A production
inventory that permits updates needs an explicit mutation and cache-invalidation
policy; replacing a vector behind a memoised property is not demonstrated here.
Keep that concern on the data object, where it can be tested without an HTTP
request, rather than making the route maintain another copy of the records.

## Routes

```@example samples
@htmx struct SampleBrowser
    __appdata__ = inventory
    (; matching) = __appdata__

    @get index(; material::String="") = h.section(
        h.h2(isempty(material) ? "All samples" : "Material: $material"),
        render_table(matching(material); sortable=false, download=false),
    )
end

app = SampleBrowser();
route!(app; prefix="/samples", operation_policy=:blocking);
foreach(println, [(route.verb, route.path, [p.name for p in route.params])
                  for route in reflect(SampleBrowser)])
```

The generated route description exposes the HTTP verb, relative path and
parameter names. Registration adds the `/samples` prefix. Reflection describes
the type independently of that registration, which lets a caller inspect an
application before mounting it under a particular URL.

`material` is a query parameter because it is a keyword argument of the GET
route. Its default makes the initial request valid without a query string. The
route reads the persistent inventory through `__appdata__`; its own request
object is rebuilt for each dispatch. The HTML section contains both the active
filter and the selected records, so a copied response retains enough context
to interpret the table.

The table receives a vector of named tuples. Its columns therefore come from
the record fields without a DataFrames dependency. Sorting and downloading are
disabled in this output because this example demonstrates server-side filtering.
The [table reference](../reference/tables.md) owns those controls and their
formatting options. HTML text nodes escape sample values; the application does
not concatenate input into a raw HTML string.

## Request and result

```@example samples
response = dispatch(:GET, "/samples/?material=plasma");
body = String(response.body);
@assert response.status == 200 # hide
Base.HTML("""
<figure class="docs-result">
  <div class="docs-preview">$body</div>
  <figcaption>The plasma request includes S-A and S-C; the serum sample S-B is absent.</figcaption>
</figure>
""")
```

This figure is the actual response body produced during the build. It is not a
screenshot of a separate app or a saved transcript. Changing the records or the
selection rule changes the displayed table on the next build. The visible
heading names the filter, while the sample identifiers show which records
survived it.

The in-process request reaches the same registered route used by an HTTP
listener. It does not traverse `serve` middleware, a browser, a proxy or the
network. Consequently this run verifies request parsing and response generation;
it makes no claim about browser interaction, deployment latency or middleware
behaviour. Those need checks at the corresponding boundary.

An ordinary page can wrap route content with `__page__`; an HTMX request then
receives the fragment for its target. This example returns a section directly,
so both requests have the same useful content. The [views guide](../guides/views.md)
shows the page/fragment distinction with an executed pair of responses.

## Diagnostics

The checks inspect both inclusion and exclusion. A status code alone would also
pass for a route that accidentally returned the whole inventory.

```@example samples
checks = (
    status=response.status,
    has_plasma_A=occursin("S-A", body),
    has_plasma_C=occursin("S-C", body),
    excludes_serum=!occursin("S-B", body),
)
@assert checks == (status=200, has_plasma_A=true,
                  has_plasma_C=true, excludes_serum=true)
foreach(println, pairs(checks))
```

The default and an unknown material exercise the other branches of the filter.
The unknown material is a valid string that selects no records; it is not a
parameter-conversion failure. Keeping those cases separate prevents the
application from confusing an empty result with an invalid request.

```@example samples
all_body = String(dispatch(:GET, "/samples/").body);
empty_body = String(dispatch(:GET, "/samples/?material=unknown").body);
ids = getproperty.(inventory.samples, :sample);
edge_checks = (
    default_includes_all=all(id -> occursin(id, all_body), ids),
    unknown_includes_none=all(id -> !occursin(id, empty_body), ids),
)
@assert all(edge_checks)
foreach(println, pairs(edge_checks))
```

These assertions run when the documentation is built. A change that drops a
matching record, includes the serum record or ignores the query fails before
the site is produced. The application does not need a browser session to check
these invariants. Add a browser check when introducing an interactive control,
since a correct server response cannot prove that a button targets the right
element or that its browser assets loaded.

The identifiers in the assertions are deliberately different from the filter
value. Checking only for the word `plasma` could pass because the heading repeats
the request, even if the table were empty. Checking record identifiers ties the
diagnostic to the rendered selection itself.

## Application

Save the data and route blocks in `sample_browser.jl` after following
[Start](../index.md). The command below opens a listener and is therefore a
shell instruction rather than a build-time code block.

```sh
julia --project=. -L sample_browser.jl -e 'serve(; host="127.0.0.1", port=8080)'
```

Visit `http://127.0.0.1:8080/samples/?material=plasma`. Removing the query string
shows the complete inventory. A form can submit the same `material` parameter
without changing the selection rule; [Forms](../guides/forms.md) demonstrates
that wiring. If this route later performs expensive work, choose its execution
policy using [Operations](../guides/operations.md) rather than copying the
blocking setting without considering the request lifetime.

```@raw html
<details><summary>Reproduce</summary>
```

Run from the repository root after provisioning the docs environment:

```sh
julia --project=docs docs/make.jl
```

The build executes every Julia block above in order. Its receipt identifies the
source revision and the Julia/package versions; no fit, recording or external
dataset is used.

```@eval
Main.DocSupport.receipt()
```

```@raw html
</details>
```
