# Tables and captions

Render tabular values with captions, numeric formatting, sorting and linked detail views.

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
