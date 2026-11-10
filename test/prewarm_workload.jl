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
    # Each fixture is precompiled by `using` it in a child `julia`, with a
    # deadline. Windows Julia 1/pre can leave a failing worker alive after its
    # expected HTTP 404 and exit-hook marker. CI run 38421167567 reproduced
    # the same hang in an HTTP-only control, so the diagnostic variants are
    # recorded in todo 0f1uahf and no longer run on every CI pass. Keep the
    # bounded failing fixture until a fixed external build exits normally.
    # The log is a pipe, not a file: a file-backed stderr is buffered, so a
    # stopped worker would lose its output.
    function compile_fixture(name, url; timeout=300)
        mktempdir() do dir
            write(joinpath(dir, "$name.jl"), """
            module $name
            using HTMXObjects
            using PrecompileTools: @compile_workload
            @htmx struct HealthApp
                @direct @get health() = "healthy"
            end
            @compile_workload begin
                route!(HealthApp())
                try
                    prewarm_workload!(HealthApp; routes=[:health], urls=[$(repr(url))])
                finally
                    println(stderr, "[fixture] workload finished")
                    atexit(() -> println(stderr, "[fixture] exit hooks reached"))
                end
            end
            end
            """)
            code = "pushfirst!(LOAD_PATH, $(repr(dir))); using $name"
            # `detach` makes the child a process-group leader on Unix, so the
            # deadline can stop the precompile worker it spawns as well.
            cmd = detach(`$(Base.julia_cmd()) --startup-file=no
                          --project=$(Base.active_project()) -e $code`)
            out = Pipe()
            process = run(pipeline(cmd; stdout=out, stderr=out); wait=false)
            close(out.in)
            log = IOBuffer()
            reader = @async while !eof(out)
                write(log, readavailable(out))
            end
            finished = timedwait(() -> process_exited(process), timeout; pollint=1) === :ok
            if !finished
                pid = getpid(process)
                run(Sys.iswindows() ? `taskkill /F /T /PID $pid` : `kill -KILL -- -$pid`)
            end
            # The pipe reaches EOF once every process holding it has exited.
            drained = timedwait(() -> istaskdone(reader), 30; pollint=0.5) === :ok
            drained || close(out)
            (; finished, ok=finished && success(process), drained,
               log=String(take!(log)))
        end
    end

    deadline = Sys.iswindows() ? 180 : 300
    good = compile_fixture("PrewarmHealthPresent", "/health"; timeout=deadline)
    bad = compile_fixture("PrewarmHealthMissing", "/missing-health.css"; timeout=deadline)
    if Sys.iswindows() && !(good.finished && bad.finished)
        # Known Windows hang (todo 0f1uahf): record it and show where it stopped.
        @info "Precompile worker did not exit" good.finished good.drained good_log=Text(good.log) bad.finished bad.drained bad_log=Text(bad.log)
        @test_broken good.finished && bad.finished
    else
        good.ok && !bad.ok ||
            @info "Fixture precompile logs" good_log=Text(good.log) bad_log=Text(bad.log)
        @test good.finished
        @test good.ok
        @test !contains(lowercase(good.log), "failed to precompile")
        @test contains(good.log, "[fixture] workload finished")
        @test bad.finished
        @test !bad.ok
        @test contains(bad.log, "/missing-health.css")
        @test contains(bad.log, "HTTP 404")
    end
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

@testitem "a prewarm timeout bounds a hang, not a compile" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    # Snag precompile-bruno-329ff905: an app page's cold first request compiled
    # for 44 s on two busy CPUs, the 45 s timeout cut it off although the
    # server answered 200, and the app failed to precompile. Here the page's
    # first render compiles six fresh 800-statement methods, with a short wait
    # between them as a real page has (I/O, locks, tasks): a few seconds of
    # compilation, several times the 0.5 s timeout below. Those waits are what
    # let the old elapsed-time limit fire on one thread. A handler waiting on
    # an event is the hang.
    chunk(k) = Expr(:block, (:(x = muladd(x, 1.0001, $(Float64(i + 1000k))) +
                               (x > $(Float64(i)) ? sin(x) : cos(x))) for i in 1:800)...)
    prewarm_cold = Function[(@eval $(Symbol(:prewarm_cold, k))(x) = ($(chunk(k)); x))
                            for k in 1:6]
    cold_page() = sum(f -> (sleep(0.01); Base.invokelatest(f, 1.0)), prewarm_cold)
    prewarm_release = Base.Event()
    @htmx struct PrewarmTimeoutApp
        @direct @get cold() = h.p(string(cold_page()))
        @direct @get stuck() = (wait(prewarm_release); h.p("late"))
        @direct @get health() = h.p("healthy")
    end
    route!(PrewarmTimeoutApp())

    started = time()
    cold = prewarm_workload!(PrewarmTimeoutApp; routes=[:cold],
        operations=false, timeout=0.5)
    elapsed = time() - started
    @test only(cold.routes).status == 200
    # Control: the request took several timeouts of elapsed time, which a
    # limit on elapsed time would have failed.
    @test elapsed > 1.5

    started = time()
    failure = try
        prewarm_workload!(PrewarmTimeoutApp; routes=[:stuck],
            operations=false, timeout=1)
        nothing
    catch err
        err
    end
    elapsed = time() - started
    notify(prewarm_release)
    @test failure isa ErrorException
    @test contains(sprint(showerror, failure),
        "no answer within 1 s outside compilation")
    # Neither the request nor closing the server waited for the handler.
    @test elapsed < 20
    @test !isopen(HTMXObjects._SERVER[])

    # A fractional or unlimited timeout works (it was `Int(timeout)`); a
    # non-positive one is refused before any request.
    @test only(prewarm_workload!(PrewarmTimeoutApp; routes=[:health],
        operations=false, timeout=2.5).routes).status == 200
    @test only(prewarm_workload!(PrewarmTimeoutApp; routes=[:health],
        operations=false, timeout=Inf).routes).status == 200
    @test_throws ArgumentError prewarm_workload!(PrewarmTimeoutApp;
        routes=[:health], timeout=0)
    @test_throws ArgumentError prewarm_routes!("http://127.0.0.1:1", ["/"];
        timeout=-1)
end
