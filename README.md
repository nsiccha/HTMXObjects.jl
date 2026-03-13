# HTMXObjects.jl

[![Dev Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://nsiccha.github.io/HTMXObjects.jl/dev/)
[![CI](https://github.com/nsiccha/HTMXObjects.jl/actions/workflows/test.yml/badge.svg)](https://github.com/nsiccha/HTMXObjects.jl/actions/workflows/test.yml)

Property-based web pages using [DynamicObjects.jl](https://github.com/nsiccha/DynamicObjects.jl), [HTMX.jl](https://github.com/nsiccha/HTMX.jl), and [Oxygen.jl](https://github.com/OxygenFramework/Oxygen.jl).

## Features

- **`@htmx` struct**: define web-facing objects with derived, indexed, and cached properties
- **Route markers**: `@get`, `@post`, and other decorators for mapping properties to HTTP endpoints
- **Static site recording**: capture rendered pages for static deployment

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/nsiccha/HTMXObjects.jl")
```

## Related packages

- [HTMX.jl](https://github.com/nsiccha/HTMX.jl) -- hyperscript HTML generation with HTMX support
- [DynamicObjects.jl](https://github.com/nsiccha/DynamicObjects.jl) -- lazy/cached property system
- [Oxygen.jl](https://github.com/OxygenFramework/Oxygen.jl) -- HTTP server framework
