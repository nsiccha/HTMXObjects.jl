# HTMXObjects.jl

HTMXObjects turns Julia objects into HTTP routes that return HTML pages, fragments and Markdown.

[Start with installation and an executed example](https://nsiccha.github.io/HTMXObjects.jl/dev/).

The [documentation source](docs/README.md) describes the page structure and local build.
The [test selector](test/select.jl) provisions unregistered dependencies and selects test items.

HTMXObjects uses [DynamicObjects](https://github.com/nsiccha/DynamicObjects.jl) for object properties,
[HTMX](https://github.com/nsiccha/HTMX.jl) for HTML, and [HTTP](https://github.com/JuliaWeb/HTTP.jl) for requests.
