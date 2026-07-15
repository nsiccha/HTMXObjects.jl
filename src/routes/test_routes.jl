"""
    TestRoutes(; project)

Mountable `@htmx` route bundle for documented, selectively runnable
`@testitem`s in a Julia package. Mount it under any `@htmx struct` via:

    @include tests = TestRoutes(; project=pkgdir(MyPackage))

Provides:

- `@get index/status` — discover and render tests plus live run state
- `@get output(id)` — render one job's complete captured output
- `@post run(id)` — run one exact test item
- `@post run_selected(names)` — run an arbitrary checked subset
- `@post run_all/run_failed/run_missing` — common selections
- `@post run_tag(tag)` — run every item carrying one tag
- `@post clear` — discard completed run output

Test bodies are never imported into the web application. Every selection is
validated against the discovered catalog and launched through an isolated
`Pkg.test(test_args=...)` child process. The package's `test/runtests.jl`
maps `--htmxo-test=<relative-file>::<name>` arguments onto a TestItemRunner
filter.
"""
@htmx struct TestRoutes
    project = ""
    @get index() = test_list(project; prefix=string(__self__))
    @get status() = test_list(project; prefix=string(__self__))
    @get output(id) = test_output(project, id; prefix=string(__self__))
    @post run(id) = test_run!(project, id; prefix=string(__self__))
    @post run_selected(; names=String[]) = test_run_batch!(project, names; prefix=string(__self__))
    @post run_all() = test_run_all!(project; prefix=string(__self__))
    @post run_tag(tag) = test_run_tag!(project, tag; prefix=string(__self__))
    @post run_failed() = test_run_failed!(project; prefix=string(__self__))
    @post run_missing() = test_run_missing!(project; prefix=string(__self__))
    @post clear() = test_clear_cache!(project; prefix=string(__self__))
end
