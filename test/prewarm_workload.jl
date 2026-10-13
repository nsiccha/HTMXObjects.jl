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
    # deadline. On GitHub's Windows runners with Julia 1/pre, the worker whose
    # workload fails (the 404 fixture) has hung after reaching its exit hooks
    # (lts passes; todo 0f1uahf). A later run with an early exit hook did not
    # hang, so compare the original fixture with an early hook, a 5 s pause,
    # and an exit hook that calls Reseau's poller shutdown explicitly. A
    # further probe brackets Reseau's registered hook in place. Exit
    # hooks run last-registered first: "exit hooks reached" runs before
    # Reseau's `atexit(shutdown!)` (registered when HTTP.jl loads), and an
    # optional "exit hooks done" runs after it. The log is a pipe, not a
    # file: a file-backed stderr is buffered, so a stopped worker would lose
    # its output.
    function compile_fixture(name, url; early_hook=false, explicit_shutdown=false,
            wrap_shutdown_hook=false, settle=0, timeout=300)
        mktempdir() do dir
            early_exit_hook = early_hook ?
                "atexit(() -> println(stderr, \"[fixture] exit hooks done\"))" : ""
            shutdown_exit_hook = explicit_shutdown ? """
            atexit(() -> begin
                println(stderr, "[fixture] poller shutdown begin")
                HTMXObjects.HTTP.IOPoll.shutdown!()
                println(stderr, "[fixture] poller shutdown done")
            end)
            """ : ""
            wrapped_shutdown_hook = wrap_shutdown_hook ? """
            let target = HTMXObjects.HTTP.IOPoll.shutdown!
                hooks = Base.atexit_hooks
                idx = findfirst(h -> h === target, hooks)
                if idx === nothing
                    println(stderr, "[fixture] poller exit hook missing")
                else
                    hooks[idx] = () -> begin
                        println(stderr, "[fixture] poller exit hook begin")
                        target()
                        println(stderr, "[fixture] poller exit hook done")
                    end
                    println(stderr, "[fixture] poller exit hook wrapped")
                end
            end
            """ : ""
            # Even sleep(0) can yield, so omit it from the no-delay control.
            settle_delay = settle > 0 ? "sleep($settle)" : ""
            write(joinpath(dir, "$name.jl"), """
            module $name
            $early_exit_hook
            using HTMXObjects
            using PrecompileTools: @compile_workload
            $shutdown_exit_hook
            $wrapped_shutdown_hook
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
                    $settle_delay
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

    # Windows workers that truly hang remain stuck for the former 300 s cap;
    # 180 s leaves ample precompile time while bounding the added probe.
    deadline = Sys.iswindows() ? 180 : 300
    good = compile_fixture("PrewarmHealthPresent", "/health"; timeout=deadline)
    bad = compile_fixture("PrewarmHealthMissing", "/missing-health.css"; timeout=deadline)
    explicit = compile_fixture("PrewarmHealthMissingWithPollerShutdown", "/missing-health.css"; explicit_shutdown=true, timeout=deadline)
    wrapped = compile_fixture("PrewarmHealthMissingWithWrappedPollerHook", "/missing-health.css"; wrap_shutdown_hook=true, timeout=deadline)
    if Sys.iswindows()
        hooked = compile_fixture("PrewarmHealthMissingWithEarlyHook", "/missing-health.css"; early_hook=true, timeout=deadline)
        settled = compile_fixture("PrewarmHealthMissingSettled", "/missing-health.css"; settle=5, timeout=deadline)
        @info "Windows precompile exit probes" good.finished bad.finished hooked.finished settled.finished explicit.finished wrapped.finished hooked_exit_hooks_done=contains(hooked.log, "[fixture] exit hooks done") explicit_shutdown_done=contains(explicit.log, "[fixture] poller shutdown done") wrapped_hook_found=contains(wrapped.log, "[fixture] poller exit hook wrapped") wrapped_hook_done=contains(wrapped.log, "[fixture] poller exit hook done")
    end
    if Sys.iswindows() && !(good.finished && bad.finished && hooked.finished && settled.finished && explicit.finished && wrapped.finished)
        # Keep the failing shape visible until its upstream cause is fixed.
        @info "Precompile worker did not exit" good.finished good.drained good_log=Text(good.log) bad.finished bad.drained bad_log=Text(bad.log) hooked.finished hooked.drained hooked_log=Text(hooked.log) settled.finished settled.drained settled_log=Text(settled.log) explicit.finished explicit.drained explicit_log=Text(explicit.log) wrapped.finished wrapped.drained wrapped_log=Text(wrapped.log)
        @test_broken good.finished && bad.finished && hooked.finished && settled.finished && explicit.finished && wrapped.finished
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
        @test explicit.finished
        @test !explicit.ok
        @test contains(explicit.log, "[fixture] poller shutdown done")
        @test wrapped.finished
        @test !wrapped.ok
        @test contains(wrapped.log, "[fixture] poller exit hook wrapped") ||
              contains(wrapped.log, "[fixture] poller exit hook missing")
        if Sys.iswindows()
            @test !hooked.ok
            @test contains(hooked.log, "[fixture] exit hooks done")
            @test !settled.ok
            @test contains(settled.log, "HTTP 404")
        end
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
