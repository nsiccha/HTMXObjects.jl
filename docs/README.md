# Documentation

The site has four navigation groups. Each page owns the concept described below;
other pages link to it rather than repeating its contract.

| Group | Page | Purpose |
| --- | --- | --- |
| Start | `index.md` | Install the current source and dispatch a complete HTML route. |
| Guides | `guides/objects.md` | Separate persistent data from request objects and compose routes. |
| Guides | `guides/forms.md` | Bind typed query and form inputs to routes. |
| Guides | `guides/views.md` | Render HTML, Markdown, tables and captions from one value. |
| Guides | `guides/operations.md` | Choose request execution and inspect runtime work. |
| Guides | `guides/testing.md` | Check route responses and discover isolated test items. |
| Examples | `examples/sample-browser.md` | Build and verify a searchable sample inventory, including its rendered output. |
| Reference | `reference/routes.md` | Route declarations, registration, request context and reflection. |
| Reference | `reference/responses.md` | HTML, Markdown and semantic response values. |
| Reference | `reference/forms.md` | Inputs, forms, URLs and request feedback. |
| Reference | `reference/tables.md` | Tables, numeric formatting, captions and comparisons. |
| Reference | `reference/layout.md` | Navigation, tabs, threads, cards and document panels. |
| Reference | `reference/runtime.md` | Errors, asynchronous work, resources and streaming. |
| Reference | `reference/files.md` | Assets, recording, static export, galleries and editors. |
| Reference | `reference/testing.md` | Test discovery and child-process test controls. |
| Reference | `reference/objects.md` | Re-exported object, HTML and HTTP interfaces. |

With Julia 1.12 or newer, run from the repository root:

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The source entries in `docs/Project.toml` supply the unregistered dependency
closure. The build runs the examples, checks exported
docstrings, rejects warnings and lints authored pages. Generated output belongs
under `docs/build/`; no screenshots, recordings or figures belong in git.

On managed fleet hosts, use `kb-acquire-compute-token --why 'HTMXObjects docs
verification' -- kb-run-compact kb-docs-build`. This prepares the unregistered
dependency closure and VitePress before running the same build.

Desktop verification covers Start and the example at 1400 × 1000 in light and
dark themes. Figures are rendered HTML produced by the example itself: these
docs demonstrate web responses, with no statistical fit or plotting dependency.

Reference entries publish the signature and opening contract of each canonical
source docstring, with its visible source link. The full help-mode docstrings
remain in the source; long contextual snippets are not copied onto the site.
The build checks export coverage before shortening the rendered docstrings.
