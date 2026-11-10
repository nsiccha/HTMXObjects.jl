# Response values

Build content values and choose their HTML or Markdown representations.

```@eval
Main.DocSupport.export_index(:responses)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :responses)
```
