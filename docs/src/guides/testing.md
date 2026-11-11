# Testing

Check route responses without opening a socket, then discover the package's
documented test items for terminal or web execution.

## Response checks

```@example testing
using HTMXObjects
@htmx struct EchoRoutes
    @get index(; value::String="") = h.p(value)
end
route!(EchoRoutes(); prefix="/echo", operation_policy=:blocking);
response = dispatch(:GET, "/echo/?value=plasma");
body = String(response.body);
@assert response.status == 200
@assert body == "<p>plasma</p>"
(status=response.status, body=body)
```

The body check proves that the query reached the route. A status-only check
would also accept an empty paragraph or a response that ignored the query.
Use a distinct prefix for each fixture sharing the process router.

## Test discovery

```@example testing
catalog = discover_test_items(pkgdir(HTMXObjects));
@assert isempty(catalog.errors) # hide
items = catalog.items;
@assert !isempty(items) # hide
item = first(items);
(name=item.name, file=item.file, tags=item.tags)
```

Discovery parses test metadata without importing test bodies into the web
process. Write a test description immediately before its `@testitem` declaration
so the description, name, tags and source location can be shown together.
HTMXObjects uses TestItems and TestItemRunner; its terminal selector lives in
`test/select.jl`.

The following shell commands select tests in a checkout. The docs build performs
discovery and response assertions only; it does not launch this test suite.

```sh
julia --project=. test/select.jl --list
julia --project=. test/select.jl --file=test/enum_params.jl
```

The selector provisions missing unregistered dependencies before forwarding
arguments to `Pkg.test`. After provisioning, the ordinary Julia package test
command is also available. Filters for names, tags and files compose according
to the selector's documented help; an unknown selector fails rather than
reporting an empty success.

## Web runner

```@example testing
@htmx struct TestApp
    @include tests = TestRoutes(; project=pkgdir(HTMXObjects))
end
[(r.verb, r.path) for r in reflect(TestApp)]
```

The generated routes expose discovery, selection, execution state and captured
output. Test execution runs in a fresh Julia child process. The normal path is
`Pkg.test(test_args=...)`. If its sandbox setup fails in the supported cases,
the runner can execute `test/runtests.jl` under an instantiated `test/`
environment instead. Both paths keep test bodies out of the web process.

Only one child job runs per project at a time. Submitted identifiers are
validated against discovery before a child starts. Completed state belongs to
the web process; `test_clear_cache!` removes completed output and state.
The [testing reference](../reference/testing.md) documents the selection and
execution functions.

The [sample browser](../examples/sample-browser.md) checks inclusion, exclusion,
default selection and empty selection in one executed example.
