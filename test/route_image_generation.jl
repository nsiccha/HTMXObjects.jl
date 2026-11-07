@testitem "index annotations are looked up, not evaluated" setup=[HTMXOTestImports] tags=[:unit] begin
    # `_lookup_annotation` resolves what `@include item(x::T)` captured without
    # `Core.eval`, which Julia refuses into a closed module while an image is
    # written (snag `route-registrati-3c241ef5`).
    lookup = HTMXObjects._lookup_annotation
    m = Module(:AnnotationOwner)
    Core.eval(m, :(struct Stage end))
    Core.eval(m, :(const Key = Symbol))
    Core.eval(m, :(module Inner struct Deep end end))
    @test lookup(m, :Symbol) === Symbol
    @test lookup(m, :Stage) === m.Stage
    @test lookup(m, :Key) === Symbol
    @test lookup(m, :(Inner.Deep)) === m.Inner.Deep
    @test lookup(m, :(Vector{Stage})) === Vector{m.Stage}
    @test lookup(m, :(Union{Int,Nothing})) === Union{Int,Nothing}
    @test lookup(m, :(NTuple{3,Int})) === NTuple{3,Int}
    @test lookup(m, :(Val{:a})) === Val{:a}
    @test lookup(m, GlobalRef(Base, :Int)) === Int
    @test lookup(m, Float64) === Float64
    # A form a lookup cannot express still evaluates outside image generation.
    @test lookup(m, :(typeof(1))) === Int
    @test lookup(m, :(Vector{<:Real})) == Vector{<:Real}
    @test_throws UndefVarError lookup(m, :NoSuchType)
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
                         String(dispatch(:GET, "/data/item/abc/source").body))
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
        @test contains(text, """[fixture] downstream answered 1 ("row:42", "item::abc")""")
        @test contains(text, "[fixture] workload answered item::xyz")
    end
end
