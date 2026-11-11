using TestItemRunner

@testitem "serve readiness reaches redirected stderr before shutdown" tags=[:integration, :server] begin
    using HTTP, Sockets

    # A fresh process matters: stderr inherited as a regular file is buffered,
    # unlike a terminal or pipe. A separate file reports listener startup without
    # flushing the captured log or making a request that could flush it for us.
    mktempdir() do dir
        for asynchronous in (false, true)
            listener = listen(ip"127.0.0.1", 0)
            port = Int(getsockname(listener)[2])
            close(listener)
            phase = joinpath(dir, "started-$asynchronous")
            logfile = joinpath(dir, "server-$asynchronous.log")
            code = """
            using HTMXObjects
            @htmx struct ReadinessApp
                @get health() = "ready"
            end
            route!(ReadinessApp(); operation_policy=:blocking)
            if $asynchronous
                serve(host="127.0.0.1", port=$port, async=true, revise=nothing,
                      access_log=nothing, verbose=-1)
                write($(repr(phase)), "listening")
                readline(stdin)
                terminate()
            else
                @async begin
                    while HTMXObjects._SERVER[] === nothing
                        sleep(0.01)
                    end
                    write($(repr(phase)), "listening")
                    readline(stdin)
                    terminate()
                end
                serve(host="127.0.0.1", port=$port, revise=nothing,
                      access_log=nothing, verbose=-1)
            end
            """
            input = Pipe()
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
            process = open(logfile, "w") do log
                run(pipeline(cmd; stdin=input, stdout=log, stderr=log); wait=false)
            end
            close(input.out)
            try
                started = timedwait(() -> isfile(phase) || process_exited(process),
                                    300; pollint=0.1) === :ok && isfile(phase)
                @test started
                if started
                    marker = "Serving on http://127.0.0.1:$port"
                    visible = timedwait(() -> occursin(marker, read(logfile, String)) ||
                                             process_exited(process), 10; pollint=0.05) === :ok
                    @test visible && occursin(marker, read(logfile, String))
                    @test process_running(process)
                    # Actual route content is the positive control for a working
                    # server; it is deliberately requested only AFTER the log check.
                    response = HTTP.get("http://127.0.0.1:$port/health"; readtimeout=60)
                    @test response.status == 200
                    @test String(response.body) == "ready"
                end
            finally
                close(input.in) # EOF asks only this child's control task to stop.
                exited = timedwait(() -> process_exited(process), 30; pollint=0.1) === :ok
                if !exited
                    kill(process, Base.SIGKILL)
                    wait(process)
                end
                @test exited
                @test success(process)
                @test occursin("Serving on http://127.0.0.1:$port", read(logfile, String))
                success(process) || @info "Readiness fixture log" log=Text(read(logfile, String))
            end
        end
    end
end
