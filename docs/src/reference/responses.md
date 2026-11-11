# Response values

Build content values and choose their HTML or Markdown representations.

Entries show the signature and opening contract. The source link on each entry
opens the full docstring; the guides contain executed usage examples.

```@eval
Main.DocSupport.export_index(:responses)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :responses)
```
