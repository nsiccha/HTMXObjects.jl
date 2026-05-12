"""
    TestRoutes(; test_module, prefix="/tests")

Mountable `@htmx` route bundle that wires up a test-runner UI for the
`@testset`s defined in `test_module`. Mount it under any `@htmx struct` via:

    @include tests = TestRoutes(; test_module=@__MODULE__)

Provides:

- `@get  index`        — render the cached test list (see [`test_list`](@ref))
- `@post run(name)`    — re-run a single named `@testset` (see [`test_run!`](@ref))
- `@post run_all`      — run every test (see [`test_run_all!`](@ref))
- `@post run_failed`   — re-run only previously-failed tests
- `@post run_missing`  — run tests with no cached result
- `@post run_batch`    — run a comma-separated batch of named tests
- `@post clear_cache`  — discard all cached results

The underlying `test_*` functions are only available when both `Test` and
`TestModules` are loaded (they're provided by the package's `TestModulesExt`
extension).
"""
@htmx struct TestRoutes
    # Mount with `@include tests = TestRoutes(; __req__, test_module=@__MODULE__)`.
    test_module = nothing
    prefix = "/tests"
    md = wants_markdown(__req__)
    @get index() = test_list(test_module, md; prefix)
    @post run(name) = test_run!(test_module, name, md; prefix)
    @post run_all() = test_run_all!(test_module, md; prefix)
    @post run_failed() = test_run_failed!(test_module, md; prefix)
    @post run_missing() = test_run_missing!(test_module, md; prefix)
    @post run_batch(; names="") = test_run_batch!(test_module, names, md; prefix)
    @post clear_cache() = test_clear_cache!(test_module, md; prefix)
end
