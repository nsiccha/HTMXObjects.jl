---
outline: deep
---

# Examples

Each example is a standalone app. Run any of them with:

```bash
julia --project examples/<name>.jl
```

Then open `http://localhost:8080`.

## Hello World

The minimal HTMXObjects app — a single `@get index` route.

[View source](https://github.com/nsiccha/HTMXObjects.jl/blob/main/examples/hello.jl)

```julia
@htmx struct HelloApp
    @get index = htmx(
        h.main(class="container")(
            h.h1("Hello, World!"),
            h.p("Built with ", h.a(href="...")("HTMXObjects.jl")),
        );
        pico_version="2",
    )
end
```

## Counter

Demonstrates HTMX partial updates. Clicking "+" sends a GET to `/increment/{n}`,
returning only the updated counter fragment — HTMX swaps it in without a full
page reload.

[View source](https://github.com/nsiccha/HTMXObjects.jl/blob/main/examples/counter.jl)

```julia
@htmx struct CounterApp
    counter_ui[n::Int] = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(hx_get="/increment/$n", hx_target="#counter", hx_swap="outerHTML")("+"),
    )

    @get index = htmx(h.main(class="container")(h.h1("HTMX Counter"), counter_ui[0]); pico_version="2")
    @get increment[n::Int] = counter_ui[n + 1]
end
```

## Blog

Shows derived properties for data, a `__page__(content)` wrapper, `is_htmx(req)`
for returning fragments vs full pages, and mutable state with `@cached`/`@persist`.
Includes a `@post` form for adding new posts — in the recorded static version,
the form is automatically greyed out.

[View source](https://github.com/nsiccha/HTMXObjects.jl/blob/main/examples/blog.jl)

## Search

Live search using kwargs for automatic query-parameter extraction
(`@get results(; q="")`). Debounced input triggers partial updates.

[View source](https://github.com/nsiccha/HTMXObjects.jl/blob/main/examples/search.jl)

## Tabs

Tab navigation with out-of-band (OOB) swaps. Clicking a tab updates both the
panel content and the active-tab indicator in a single response, keeping the nav
in sync without a full reload.

[View source](https://github.com/nsiccha/HTMXObjects.jl/blob/main/examples/tabs.jl)

## Live HTMX inclusion (dev-mode demo)

A live HTMXO fragment fetched from a running app:

<div class="htmxo-embed" hx-get="/live-htmxo/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading live HTMXO content from /live-htmxo/ …</em>
</div>

In `vitepress dev`, the placeholder above is forwarded by Vite's proxy to a
local HTMXO server (configured in `.vitepress/config.mts` under
`vite.server.proxy['/live-htmxo']`). HTMX's request carries
`HX-Request: true`, so HTMXO returns a body fragment (no `<html>`/`<head>`)
that drops directly into the page. The fragment's components pick up
VitePress's brand colors automatically via the `--htmxo-*` bridge in the
docs head.

In production (`vitepress build`), point the same `/live-htmxo/*` URL at
recordings produced by `docs/record_examples.jl` — same markdown source,
no docs-side branching.

Set `HTMXO_DEV_TARGET=http://localhost:PORT` to point the proxy at a
different HTMXO app while you're working.
