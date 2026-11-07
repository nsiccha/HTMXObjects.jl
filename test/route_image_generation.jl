@testitem "index and @param annotations resolve without evaluating" setup=[HTMXOTestImports] tags=[:unit] begin
    # Both places HTMXObjects reads an annotation go through
    # `DynamicObjects.resolve_annotation`, which looks names up instead of
    # `Core.eval`, refused into a closed module while an image is written
    # (snag `route-registrati-3c241ef5`): `_nested_prefix_and_step` for
    # `@include item(x::T)` and `_reflect_resolve_type` for `@param` types.
    m = Module(:AnnotationOwner)
    Core.eval(m, :(struct Stage end))
    Core.eval(m, :(struct Owner end))
    Core.eval(m, :(const Key = Symbol))
    Core.eval(m, :(module Inner struct Deep end end))
    forms = Any[:Symbol, :Stage, :Key, :(Inner.Deep), :(Vector{Stage}),
                :(Union{Int,Nothing}), :(NTuple{3,Int}), :(Val{:a}),
                GlobalRef(Base, :Int), Float64,
                # forms HTMXObjects' own copy (0.1.82) still evaluated
                :(typeof(1)), :(Vector{<:Real}), :(Vector{T} where T<:Integer)]
    expected = Any[Symbol, m.Stage, Symbol, m.Inner.Deep, Vector{m.Stage},
                   Union{Int,Nothing}, NTuple{3,Int}, Val{:a}, Int, Float64,
                   Int, Vector{<:Real}, Vector{T} where T<:Integer]
    indices = Any[Expr(:(::), Symbol(:x, i), f) for (i, f) in enumerate(forms)]
    prefix, step = HTMXObjects._nested_prefix_and_step(m.Owner, :item, (; indices), "")
    @test prefix == "item/" * join(("{x$i}" for i in eachindex(forms)), "/")
    for (got, want, form) in zip(step.types, expected, forms)
        @test got == want
    end
    resolve = HTMXObjects._reflect_resolve_type
    for (form, want) in zip(forms, expected)
        @test resolve(m, form) == want
    end
    # An unbound name maps to `nothing`, as in DO's `property_signature`.
    @test resolve(m, :NoSuchType) === nothing
    @test_throws UndefVarError HTMXObjects._nested_prefix_and_step(
        m.Owner, :item, (; indices=Any[:(x::NoSuchType)]), "")
end

@testitem "an app's routes register while a package image is written" setup=[HTMXOTestImports] tags=[:integration, :precompile] begin
    # Snag `route-registrati-3c241ef5`: registering `@include item(name::Symbol)`
    # evaluated `Symbol` into the module that declares the include. While a
    # package image is written Julia refuses that for every module but the one
    # being compiled, so precompiling a package that depends on an app whose
    # `__init__` calls `route!` failed with "Evaluation into the closed module",
    # and so did a `@compile_workload` routing an app that mounts another
    # package's page (htmxo-use, `prewarm_workload!`).
    mktempdir() do dir
        write(joinpath(dir, "ImageRouteOwner.jl"), """
        module ImageRouteOwner
        using HTMXObjects
        @htmx struct OwnerPage
            @direct @get index() = "owner"
            @include item(name::Symbol) = begin
                @direct @get source() = "item:" * repr(name)
            end
            # A call: HTMXObjects 0.1.82 still evaluated this form.
            @include nth(n::typeof(1)) = begin
                @direct @get source() = "nth:" * string(n + 1)
            end
        end
        end
        """)
        write(joinpath(dir, "ImageRouteApp.jl"), """
        module ImageRouteApp
        using HTMXObjects, ImageRouteOwner
        @htmx struct App
            @direct @get index() = "app"
            @include data = ImageRouteOwner.OwnerPage()
            @include row(n::Int) = begin
                @direct @get source() = "row:" * string(n + 1)
            end
        end
        __init__() = route!(App())
        end
        """)
        # Precompiling this loads ImageRouteApp from its image, so ImageRouteApp's
        # `__init__` registers its routes while this package's image is written.
        write(joinpath(dir, "ImageRouteDownstream.jl"), """
        module ImageRouteDownstream
        using HTMXObjects, ImageRouteApp
        const GENERATING = ccall(:jl_generating_output, Cint, ())
        const ANSWERS = (String(dispatch(:GET, "/row/41/source").body),
                         String(dispatch(:GET, "/data/item/abc/source").body),
                         String(dispatch(:GET, "/data/nth/6/source").body))
        end
        """)
        write(joinpath(dir, "ImageRouteWorkload.jl"), """
        module ImageRouteWorkload
        using HTMXObjects, ImageRouteOwner
        using PrecompileTools: @compile_workload
        @htmx struct WorkApp
            @direct @get index() = "work"
            @include data = ImageRouteOwner.OwnerPage()
        end
        @compile_workload begin
            route!(WorkApp())
            println(stderr, "[fixture] workload answered ",
                    String(dispatch(:GET, "/data/item/xyz/source").body))
        end
        end
        """)
        code = """
        pushfirst!(LOAD_PATH, $(repr(dir)))
        using ImageRouteDownstream, ImageRouteWorkload
        println(stderr, "[fixture] downstream answered ",
                ImageRouteDownstream.GENERATING, " ", ImageRouteDownstream.ANSWERS)
        """
        # A deadline, as in `test/prewarm_workload.jl`: `detach` makes the child a
        # process-group leader so a stop reaches its precompile workers too.
        cmd = detach(`$(Base.julia_cmd()) --startup-file=no
                      --project=$(Base.active_project()) -e $code`)
        out = Pipe()
        process = run(pipeline(cmd; stdout=out, stderr=out); wait=false)
        close(out.in)
        log = IOBuffer()
        reader = @async while !eof(out)
            write(log, readavailable(out))
        end
        finished = timedwait(() -> process_exited(process), 600; pollint=1) === :ok
        if !finished
            pid = getpid(process)
            run(Sys.iswindows() ? `taskkill /F /T /PID $pid` : `kill -KILL -- -$pid`)
        end
        timedwait(() -> istaskdone(reader), 30; pollint=0.5) === :ok || close(out)
        text = String(take!(log))
        ok = finished && success(process)
        ok || @info "Fixture precompile log" log=Text(text)
        @test finished
        @test ok
        @test !contains(text, "closed module")
        @test contains(text, """[fixture] downstream answered 1 ("row:42", "item::abc", "nth:7")""")
        @test contains(text, "[fixture] workload answered item::xyz")
    end
end
