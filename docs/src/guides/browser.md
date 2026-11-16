# Browser results

Compute a `presentation=:tabs` page's results in the browser from an emitted module, so the
page follows its inputs with no server, also as a static export.

A `presentation=:tabs` page asks the server again for a result when an input it
reads changes. A property can instead have a browser twin: an ES module that
computes the same value from the inputs, such as the one
`ReactiveKernels.js_source` emits from the kernel the property calls. A result
that shows that property only through `bound(...)` is then computed and redrawn
in the browser, with no request, so the page keeps following its inputs as a
static export (`export_site`) and offline:

```@example browser
using HTMXObjects
const LINE_JS = """
export function line(grid, a, b) {
  return { x: grid, y: grid.map(x => a * x + b), total: a + b };
}
export const INPUTS = [{ name: "grid", type: "Vector{Float64}" },
  { name: "a", type: "Float64" }, { name: "b", type: "Float64" }];
"""
@htmx struct Line
    "Slope"
    @param a::Float64 = 2.0
    "Intercept"
    @param b::Float64 = 1.0
    grid = [0.0, 1.0, 2.0]
    fit = (; x = grid, y = a .* grid .+ b, total = a + b)
    @browser(fit) = browser_module(; source = LINE_JS, entry = :line)
    "Line"
    @get result() = h.p("total ", bound(fit.total; digits = 1), " at slope ", bound(a))
    "Points"
    @get points() = render_table(bound(fit; columns = (:x, :y));
        columns = [:y => ColumnSpec("y"; digits = 2)], link = "line", link_key = :x)
    @get index() = semantic_app(__self__; presentation=:tabs,
        select=entry -> entry.name !== :index)
end
route!(Line(); prefix="/line", operation_policy=:blocking);
response = dispatch(:GET, "/line/result?a=3"; headers=["HX-Request" => "true"]);
@assert response.status == 200 # hide
println(String(response.body))
```

- **The module** is read from a file with `browser_module(path, entry)` or
  given as text with `browser_module(; source, entry)`. It exports the function
  `entry`, which takes positional arguments, and `INPUTS`, naming them and their
  Julia types in order. The page passes each by name: a `@param` from its
  control (numbers, `Bool`, text and vectors of them), any other from the
  property of that name, which must not read an input (`grid` above); its value
  goes into the page, non-finite numbers and `-0.0` included. Such data is a
  number, a `Bool`, text, or a vector or matrix of them. A matrix arrives as
  the array of its rows (`m[i][j]` is Julia's `m[i+1, j+1]`), as
  `ReactiveKernels.js_source` modules take it; one without rows is an empty
  array whose `cols` is its column count. A named tuple comes back as an object of named outputs.
- **`bound`** marks where a view shows a browser value: the property, one of its
  outputs (`bound(fit.total)`), an element of one (`bound(fit.y[2])`, the index
  an integer literal) or a `@param` (`bound(a)`). The server writes a number as
  `format_number` does, and so does the browser after each change: `digits=1`
  writes exactly one decimal (`4.0`), `digits=0` a whole number, `sigdigits=k`
  significant digits, `percent=true` the share 0.45 as `45%`, and
  `texts=table_texts(:de)` German marks (`0,120`, `45 %`). Without them a
  number keeps its digits (`4`, `3.81·10⁻⁵`). The value itself is not rounded.
- **A table of outputs:** `bound(fit; columns=(:x, :y))`. Given to
  `render_table` (`points` above), it is written again after each change, each
  column as its `ColumnSpec(label; digits, sigdigits, percent)` says, sorted
  and exported to CSV by the unrounded values, with the reader's sort kept and
  rows hover-linked by `link_key = :x`. For a plot's `data(...)`, give the
  element that draws it `bound_columns_attrs(...)`, and the browser hands it the
  new rows through AlgebraOfVega's `AoV.updateData` and an
  `htmxo:bound-columns` event. The table is its own `Tables.columns`, so a
  plot's `data(...)` layer (AlgebraOfGraphics keeps `Tables.columns` of its
  data) still holds it, and a plotting package can mark the element itself.
  Single-value outputs (a number, a `Bool`, text) make a table of one row,
  `bound(fit; columns=(:half,))` with `half::Float64`, for a mark at that
  value such as a rule. One table holds vectors of one length or single
  values, not both, so a plot of both takes two: one per kind.
- **Finite inputs** (a `Bool`, an enum, `@options`) that a result reads are
  views of their own: the page carries the result rendered for each value (at
  most 64) and shows the one the inputs select.
- **While an input moves** (a slider held down, a number being typed), the
  result follows each of its `input` events, redrawn once an animation frame at
  most. A result asked of the server and the page address wait for the release
  (`change`).
- **An error** the module throws is shown in the result under its name
  (`DomainError: …`), which keeps its last answer faded until the next one.
- **The page address**: a page applies the inputs its address names to its
  controls when it loads, so a static page's shared link reopens them.
- **`@relevant`** conditions with arithmetic of inputs (`a * b > 10`) are
  evaluated in the browser, like comparisons with literals.

`export_site` refuses a page with a browser result that would show something
stale, naming each part: a view that shows an input outside `bound` (the export
renders it with each continuous input changed and compares everything else), a
result that reads inputs but computes nothing in the browser, and a control the
server draws again (`@options` or `@help` that read other inputs, a default
computed from other inputs, which the refusal names, or a condition the
browser cannot evaluate). A default that reads no input, such as a fixed
field's value, is none of these, whatever `@relevant` condition or `@options`
its input has. Bind it, compute it in the module, or leave that
operation out of the page with `semantic_app(…; select=…)`.

The refusal of a view quotes what changed with the input. What two renders of
the same inputs differ in is not an input's doing and is left out of the
comparison: the link of a glossary term (its definition's id is new in every
answer), or an id or a time the view writes itself. A view that holds more or
less markup each time it is rendered cannot be compared, and the export says
so.
