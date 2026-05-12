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
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index() = h.div(
        h.h1("Hello, World!"),
        h.p("Built with ", h.a(href="https://github.com/nsiccha/HTMXObjects.jl")("HTMXObjects.jl")),
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
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    counter_ui(n::Int) = h.div(id="counter")(
        h.p("Count: $n"),
        h.button(hx_get="/increment/$n", hx_target="#counter", hx_swap="outerHTML")("+"),
    )

    @get index() = h.div(h.h1("HTMX Counter"), counter_ui(0))
    @get increment(n::Int) = counter_ui(n + 1)
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

## Embedded examples

Each app below is rendered into the docs via an HTMX placeholder
(`<div hx-get=".../hx/" hx-trigger="load">`) that fetches a body
fragment on page load and inlines it. Buttons inside each example point
at neighbouring fragment recordings, so partial-update interactions work
directly inside this page — no iframe, no separate scrollbars.

In `vitepress dev`, the same path can also be served live by Vite's
proxy: set `HTMXO_DEV_TARGET=http://localhost:PORT` and Vite forwards
`/live-htmxo/*` to a running HTMXO server, so editing a route reflects
in the docs page immediately. In production (`vitepress build`), the
recordings produced by `docs/record_examples.jl` take over — same
markdown source, no docs-side branching.

### Counter (live)

<div class="htmxo-embed" hx-get="/HTMXObjects.jl/dev/examples/counter/hx/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading counter…</em>
</div>

### Hello World

<div class="htmxo-embed" hx-get="/HTMXObjects.jl/dev/examples/hello/hx/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading hello…</em>
</div>

### Tabs

<div class="htmxo-embed" hx-get="/HTMXObjects.jl/dev/examples/tabs/hx/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading tabs…</em>
</div>

### Search

<div class="htmxo-embed" hx-get="/HTMXObjects.jl/dev/examples/search/hx/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading search…</em>
</div>

### Blog

<div class="htmxo-embed" hx-get="/HTMXObjects.jl/dev/examples/blog/hx/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading blog…</em>
</div>
