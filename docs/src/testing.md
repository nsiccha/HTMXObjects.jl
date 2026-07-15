# Testing

HTMXObjects uses [TestItems.jl](https://github.com/julia-vscode/TestItems.jl)
and [TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl) for one
set of tests with two entry points: ordinary `Pkg.test()` for terminals and CI,
and `TestRoutes` for selecting and inspecting tests inside an HTMXO app.

Test code is never loaded into the web process. Every web-triggered selection
runs through `Pkg.test(test_args=...)` in a fresh Julia child process, so a test
failure or module mutation cannot take down or contaminate the host app.

## Writing documented test items

Put `TestItemRunner` in the package's test target and use `@testitem` rather
than a custom test-module registry:

```toml
[extras]
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
TestItemRunner = "f8b46487-2199-4994-9208-9a1283c18c0a"

[targets]
test = ["Test", "TestItemRunner"]
```

```julia
using TestItemRunner

@testsnippet CommonImports begin
    using MyPackage
end

"""
Checks the public parse contract.

The full Markdown description is shown in the web UI.
"""
@testitem "parse a valid record" setup=[CommonImports] tags=[:unit, :parser] begin
    @test parse_record("ok").valid
end
```

The docstring must be immediately before `@testitem`; putting a docstring
inside its body is invalid Julia documentation syntax. TestItemRunner still
runs the item normally, while HTMXObjects discovers the adjacent description,
name, tags, and source location without evaluating the file.

The package's `test/runtests.jl` supplies a filter to
`@run_package_tests`. HTMXObjects' version accepts exact internal selectors as
well as friendly `--name`, `--tag`, and `--file` filters. Copy that small runner
when adopting this workflow in another package.

## Command-line workflow

Run the complete suite using the standard Julia package command:

```julia
pkg> test
```

For a subset, `test/select.jl` forwards its arguments through `Pkg.test`:

```sh
julia --project=. test/select.jl --name="parse a valid record"
julia --project=. test/select.jl --tag=unit
julia --project=. test/select.jl --file=test/parser.jl --tag=parser
julia --project=. test/select.jl --list
```

Repeated values select any value within that category; different categories
combine, so `--file=… --tag=…` means tests matching both. Unknown names, tags,
files, and exact selectors fail loudly instead of silently reporting success.

Programmatic callers can use the same contract directly:

```julia
using Pkg
Pkg.test(; test_args=["--tag=unit"])
```

## Mounting the web UI

Mount `TestRoutes` with the package project directory:

```julia
using HTMXObjects, MyPackage

@htmx struct App
    @include tests = TestRoutes(; project=pkgdir(MyPackage))

    @get index() = h.main(; class="container")(
        h.h1("My app"),
        h.a(; href=__self__/"tests/")("Tests"),
    )
end
```

Navigate to the included route (normally `/tests/`). The page supports:

- one test, any checked subset, all tests, or all tests carrying a tag;
- re-running failed or not-yet-run items;
- expandable Markdown descriptions and source locations;
- live pass/fail/error state, duration, exit code, and escaped child output;
- bounded inline previews for large logs, with the complete output always
  reachable from the job row;
- polling while the child is active and clearing completed history.

Only one child job runs per project at a time. Client-supplied IDs are checked
against the freshly discovered catalog before a process is started. Completed
state lives in the web process and is intentionally bounded; the tests
themselves always run in a clean process, so Revise is not part of the test
correctness model.

## Direct API

The routes are thin wrappers around ordinary functions:

| Function | Behaviour |
|---|---|
| `discover_test_items(project)` | Parse metadata without importing test code |
| `test_list(project; prefix)` | Render the catalog, selections, state, and output previews |
| `test_output(project, id; prefix)` | Render one validated job's complete captured output |
| `test_run!(project, id; prefix)` | Start one catalog item |
| `test_run_batch!(project, ids; prefix)` | Start an arbitrary checked subset |
| `test_run_all!(project; prefix)` | Start the complete catalog |
| `test_run_tag!(project, tag; prefix)` | Start every item carrying a tag |
| `test_run_failed!` / `test_run_missing!` | Select from the latest in-memory state |
| `test_clear_cache!(project; prefix)` | Delete completed job output and state |

These calls return the refreshed UI immediately; execution continues
asynchronously in the child process. `TestRoutes.status` supplies the polling
fragment while a job is active.
