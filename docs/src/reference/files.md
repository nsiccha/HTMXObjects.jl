# Files and exports

Serve assets, record responses, export public content and manage file-backed galleries or editors.

```@eval
Main.DocSupport.export_index(:files)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :files)
```
