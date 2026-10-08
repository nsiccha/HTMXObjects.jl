using TestItemRunner

@testitem "startup workload warms routes and assets on a managed loopback server" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    @htmx struct StartupWarmApp
        @direct @get health() = h.p("healthy")
    end
    route!(StartupWarmApp())

    mktempdir() do dir
        write(joinpath(dir, "ready.css"), "body { color: green; }")
        staticfiles(dir, "startup-assets")
        callback_base = Ref("")
        rows = prewarm_workload!(StartupWarmApp;
            routes=[:health], urls=["/health", "/startup-assets/ready.css"],
            server_kwargs=(; revise=nothing)) do base
            callback_base[] = base
            @test HTTP.get(base * "/health"; retry=false).status == 200
        end
        @test startswith(callback_base[], "http://127.0.0.1:")
        @test length(rows.routes) == 3 # plain, HTMX and page transports
        @test all(row -> row.status == 200 && row.error === nothing, rows.routes)
        @test length(rows.urls) == 2
        @test all(row -> row.status == 200, rows.urls)
        @test !isopen(HTMXObjects._SERVER[])
        @test isempty(prewarm_workload!(StartupWarmApp;
            routes=[:health], operations=false).urls)
        @test only(prewarm_workload!(StartupWarmApp;
            routes=[:health], urls="/health", operations=false).urls).status == 200

        # A missing health/static asset must abort an @compile_workload block.
        failure = try
            prewarm_workload!(StartupWarmApp; routes=[:health],
                urls=["/startup-assets/missing-health.css"])
            nothing
        catch err
            err
        end
        @test failure isa ErrorException
        @test contains(sprint(showerror, failure), "/startup-assets/missing-health.css")
        @test contains(sprint(showerror, failure), "HTTP 404")
        @test !isopen(HTMXObjects._SERVER[])
    end
end

@testitem "missing health asset fails an actual PrecompileTools workload" setup=[HTMXOTestImports] tags=[:integration, :precompile] begin
    function compile_fixture(name, url)
        mktempdir() do dir
            source = """
            module $name
            using HTMXObjects
            using PrecompileTools: @compile_workload
            @htmx struct HealthApp
                @direct @get health() = "healthy"
            end
            @compile_workload begin
                route!(HealthApp())
                prewarm_workload!(HealthApp; routes=[:health], urls=[$(repr(url))])
            end
            end
            """
            path = joinpath(dir, "$name.jl")
            write(path, source)
            capture = IOBuffer()
            result = try
                Base.compilecache(Base.PkgId(name), path,
                                  capture, capture)
            catch err
                err
            end
            result, String(take!(capture))
        end
    end

    good, good_log = compile_fixture("PrewarmHealthPresent", "/health")
    @test !(good isa Exception)
    @test !contains(good_log, "failed to precompile")

    bad, bad_log = compile_fixture("PrewarmHealthMissing", "/missing-health.css")
    @test bad isa Exception
    @test contains(bad_log, "/missing-health.css")
    @test contains(bad_log, "HTTP 404")
end

@testitem "startup workload refuses skipped routes and non-loopback servers" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    @htmx struct StartupSelectionApp
        @get health() = h.p("healthy")
        @post change() = h.p("changed")
    end
    route!(StartupSelectionApp())
    @test_throws ArgumentError prewarm_workload!(StartupSelectionApp;
        server_kwargs=(; host="0.0.0.0"))
    @test_throws ErrorException prewarm_workload!(StartupSelectionApp;
        routes=[:change])
    @test !isopen(HTMXObjects._SERVER[])
end
