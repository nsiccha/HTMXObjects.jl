# Run in a fresh process: julia --startup-file=no --project=. benchmark/rendering.jl
# First-use compilation and warm execution are reported separately. Compare
# revisions on the same Julia version and at similar host load; these timings
# are diagnostic measurements, not CI thresholds.
using HTMXObjects
const H = HTMXObjects
Base.cumulative_compile_timing(true)

function measure(label, f; samples=9)
    before = Base.cumulative_compile_time_ns()
    first = @timed f()
    after = Base.cumulative_compile_time_ns()
    warm = [@timed(f()) for _ in 1:samples]
    println(label, " first_s=", first.time,
        " compile_s=", (after[1] - before[1]) / 1e9,
        " warm_median_s=", sort([t.time for t in warm])[cld(samples, 2)],
        " bytes=", minimum(t.bytes for t in warm))
    first.value
end

println("Julia ", VERSION, " HTMXObjects ", Base.pkgversion(H),
    " HTTP ", Base.pkgversion(H.HTTP), " DynamicObjects ", Base.pkgversion(H.DynamicObjects))
table_a(rows) = master_detail_table(["Name", "Amount"], rows; key=x -> x.id,
    master=x -> h.tr(h.td(x.name), number_cell(x.amount)), detail=x -> h.p(x.name))
table_b(rows) = master_detail_table(["Name", "Amount"], rows; key=x -> x.id,
    master=x -> h.tr(h.td(x.name), number_cell(x.amount)), detail=x -> h.p(x.name))
sample_rows = [(; id=i, name="row $i", amount=i / 10) for i in 1:100]
measure("callbacks_a", () -> table_a(sample_rows))
measure("callbacks_b", () -> table_b(sample_rows))
for n in (500, 1000, 2000, 5000)
    rows = [(; id=i, name="row $i", amount=i / 10) for i in 1:n]
    table = measure("table_$n", () -> table_a(rows))
    measure("table_html_$n", () -> repr(MIME"text/html"(), table))
end
measure("shell_inline", () -> htmx(h.p("hello")))
measure("shell_linked", () -> htmx(h.p("hello"); runtime=:linked, assets="/vendor"))
measure("shell_extra_head", () -> htmx(h.p("hello"); runtime=:linked,
    assets="/vendor", extra_head=(h.script(; src="/own.js"),)))
assetnames = H._available_runtime_names()
measure("runtime_heads", () -> [H._runtime_head(n, "/vendor") for n in assetnames])
for n in (500, 1000, 2000, 4000)
    group_keys = string.(1:n)
    measure("group_ranks_$n", () -> H._md_group_ranks(group_keys, ["group"],
        Dict("group" => identity), ["group" => group_keys]))
end
for n in (10, 40, 160)
    body = Expr(:block, [Meta.parse("@get r$i() = \"ok\"") for i in 1:n]...)
    ex = Expr(:macrocall, Symbol("@htmx"), LineNumberNode(1),
        Expr(:struct, false, Symbol("BenchmarkRoutes", n), body))
    measure("macroexpand_$n", () -> macroexpand(Main, deepcopy(ex)); samples=3)
    Core.eval(Main, ex)
    T = getfield(Main, Symbol("BenchmarkRoutes", n))
    descriptor = measure("descriptor_$n", () -> semantic_descriptor(T); samples=3)
    H._shared_semantic_descriptor(T)
    routekeys = [(r.name, r.verb) for r in descriptor.routes]
    measure("operation_lookups_$n", () -> [H._operation_route(T, name, verb)
        for (name, verb) in routekeys])
    measure("semantic_app_$n", () -> semantic_app(Base.invokelatest(T)); samples=3)
end
