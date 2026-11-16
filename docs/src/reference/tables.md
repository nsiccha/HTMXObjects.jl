# Tables and captions

Render tabular values with captions, numeric formatting, sorting and linked detail views.

For compact plain rows with left-aligned headers and right-aligned numbers:

```julia
render_table(data; density=:compact, header_align=:left, class="")
```

These options are independent and also work with `sortable_table`,
`master_detail_table`, and browser-computed `bound` tables. Compact density
reduces cell and CSV/caption spacing; it does not set the scrolling frame's
height. Use `semantic_app(...; result_height)` for that. Existing defaults
remain `density=:normal`, `header_align=nothing`, and `class="striped"`.

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
