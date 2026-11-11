# Files and exports

Serve assets, record responses, export public content and manage file-backed galleries or editors.

Entries show the signature and opening contract. The source link on each entry
opens the full docstring; the guides contain executed usage examples.

```@eval
Main.DocSupport.export_index(:files)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :files)
```
