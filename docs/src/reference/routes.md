# Routes and requests

Declare routes, register an application, inspect its generated interface and dispatch requests.

Entries show the signature and opening contract. The source link on each entry
opens the full docstring; the guides contain executed usage examples.

```@eval
Main.DocSupport.export_index(:routes)
```

```@autodocs
Modules = [HTMXObjects]
Private = false
Filter = value -> Main.DocSupport.belongs(value, :routes)
```

`SchemaRoutes` accepts the following query values for inherited parameters.

```@docs
HTMXObjects.SchemaInherited
```
