# Tables and captions

Render tabular values with captions, numeric formatting, sorting and linked detail views.

For compact plain rows with left-aligned headers and right-aligned numbers,
use `render_table(data; density=:compact, header_align=:left, class="")`.

These options are independent and also work with `sortable_table`,
`master_detail_table`, and browser-computed `bound` tables. Compact density
reduces cell and CSV/caption spacing; it does not set the scrolling frame's
height. Use `semantic_app(...; result_height)` for that. Existing defaults
remain `density=:normal`, `header_align=nothing`, and `class="striped"`.

A table of four or more columns has a *Columns* menu with which readers hide
and show columns; the first column always shows. Open a table with some
columns hidden with `hidden_columns=["Kaltmiete", 7]` (labels, `"Group /
Leaf"` names or 1-based positions), and turn the menu off with
`column_menu=false`. The reader's choice is kept in their browser per table
and page. The CSV download writes the shown columns; Markdown and PDF write
the columns the table opens with. The options work with `render_table`,
`sortable_table` and `master_detail_table`.

A regroupable table can use its own columns as levels. For example,
`groupings=["Output", "Quantity", "None" => nothing]` with
`group_by=["Output", "Quantity"]` opens a `master_detail_table` grouped by
output and then quantity. Each active level moves its repeated label into the
group heading. Turning a level off brings its column back. CSV and `?plain`
write one row per item in the flat schema, with an exact estimate and two
bounds for each interval column. A column explicitly hidden through the
Columns menu follows the usual export rules.

To let readers compare columns against one of their choice, pass
`relative_to=RelativeTo(["Wren", "RKPPL", "Soss"])`. The toolbar then offers
*Relative to*: picking a label divides each compared number cell by the same
row's cell of that label under the same heading, so times `2, 4, 8` read
`0.5×, 1×, 2×` against `4`. Sorting uses the exact ratios, the CSV download
writes them, and open details, search, selection and hidden columns stay as
they are. `comparable(item, column)` keys which pairs may be divided; other
pairs read `–` and sort last. `default="Wren"` opens the table relative to
that column, also in Markdown and PDF.

Entries show the signature and opening contract. The source link on each entry
opens the full docstring; the guides contain executed usage examples.

```@eval
Main.DocSupport.export_index(:tables)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :tables)
```
