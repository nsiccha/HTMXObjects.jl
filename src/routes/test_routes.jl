# Provides web routes for running tests registered via TestModules. Include in an
# @htmx struct with `@include tests = TestRoutes(; __req__, test_module=@__MODULE__)`
# to add test listing, running, and cache management endpoints under /tests/.
@htmx struct TestRoutes
    # Mount with `@include tests = TestRoutes(; __req__, test_module=@__MODULE__)`.
    test_module = nothing
    prefix = "/tests"
    md = wants_markdown(__req__)
    @get index = test_list(test_module, md; prefix)
    @post run(name) = test_run!(test_module, name, md; prefix)
    @post run_all = test_run_all!(test_module, md; prefix)
    @post run_failed = test_run_failed!(test_module, md; prefix)
    @post run_missing = test_run_missing!(test_module, md; prefix)
    @post run_batch(; names="") = test_run_batch!(test_module, names, md; prefix)
    @post clear_cache = test_clear_cache!(test_module, md; prefix)
end
