# Testing

HTMXObjects ships a small test-running UI you can mount inside any `@htmx` app, so you (and Revise) get a click-driven test runner that lives in the same web app you're developing.

## Mounting the UI

`TestRoutes` is an `@htmx struct` exposing `@get index`, `@post run(name)`, `@post run_all`, `@post run_failed`, `@post run_missing`, `@post run_batch(; names)`, and `@post clear_cache`. Mount it via `@include` inside your app:

```julia
using HTMXObjects, Test                  # `Test` triggers the test extension

@htmx struct App
    @include tests = TestRoutes(; __req__, test_module=@__MODULE__, prefix="/tests")

    @get index = h.main(class="container")(
        h.h1("My App"),
        h.p(h.a(href="/tests/")("Tests")),
    )
end
```

`Test` must be loaded for the routes to do anything — the UI implementation lives in `HTMXObjects.TestExt` and is activated by the package extension mechanism.

Once the app is running, navigate to `/tests/` to see the list of registered tests, run them individually, and inspect output/timings/cached results.

## Where tests come from

The runner looks at `test_module` and finds:

- `@testset`s registered via [TestModules.jl](https://github.com/nsiccha/TestModules.jl) (`@testmodule`-style)
- Plain `@testset` calls in the module's source

For app code that lives in `web/src/MyAppWeb.jl`, write tests in the same module (or a sub-module that's `using`-ed). With Revise running, edits are picked up live — the test list refreshes on the next `index` GET.

## Calling the runner directly

You can also drive the runner from Julia (e.g. from a CI script) — the same functions back the UI buttons:

| Function | Behaviour |
|----------|-----------|
| `test_list(test_module, md; prefix)`   | Render the test list (HTML or Markdown depending on `md`) |
| `test_run!(test_module, name, md; prefix)` | Run one test by name                                  |
| `test_run_all!(test_module, md; prefix)`   | Run every registered test                             |
| `test_run_failed!(test_module, md; prefix)` | Re-run only the previously-failed tests              |
| `test_run_missing!(test_module, md; prefix)` | Run tests that haven't been run yet                 |
| `test_run_batch!(test_module, names, md; prefix)` | Run a comma-separated batch of tests           |
| `test_clear_cache!(test_module, md; prefix)` | Discard cached pass/fail state                     |

`md::Bool` toggles between HTML (full UI) and Markdown (agent-friendly) output. `prefix` is the URL prefix the routes were mounted under (defaults to `/tests`).

## CI vs. interactive

The HTMX-driven UI is intentionally **stateful** — it remembers per-test pass/fail/timing across runs so you can iterate quickly. For CI, prefer:

```julia
# ci_runtests.jl
using Test, MyAppWeb
@testset "MyApp" begin
    # ... your test sets
end
```

…and let `julia --project=test test/runtests.jl` exercise the actual `@testset`s without the UI layer.

## Web-integrated test workflow

The recommended development loop:

1. Open the app — `julia --project=web -e 'using Revise; using MyAppWeb; MyAppWeb.run!()'`
2. Visit `/tests/` for the runner UI
3. Edit code in `web/src/MyAppWeb.jl` — Revise hot-reloads it
4. Click "Run failed" or a single test to verify your change without restarting Julia

This is the pattern used by every web app in the ecosystem (StanBlocks, BRM, Treebars, …). See [`testing-pattern.md`](https://github.com/nsiccha/Claude/blob/main/testing-pattern.md) in the project knowledge base for the full convention (`@testmodule` syntax, disk persistence, etc.).
