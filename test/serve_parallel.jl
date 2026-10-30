using TestItemRunner

@testitem "serve(; parallel) picks the request threadpool and warns only when threads sit unused" tags=[:unit] begin
    pool(parallel, interactive, default, http) =
        HTMXObjects._request_threadpool(parallel, interactive, default, VersionNumber(http))

    # HTTP.jl 2 already runs each connection on `:interactive`: the default uses a
    # sized interactive pool, so it must not warn that the pool is unused.
    @test pool(false, 32, 32, "2.8.0") == (nothing, nothing)
    @test pool(false, 1, 8, "2.8.0") == (nothing, nothing)
    @test pool(false, 0, 8, "2.8.0") == (nothing, nothing)

    # HTTP.jl 1.x serves every connection on one thread.
    p, w = pool(false, 32, 32, "1.11.0")
    @test p === nothing
    @test occursin("leaving 32 interactive threads unused", w)
    @test occursin("parallel=:interactive", w)
    @test pool(false, 1, 8, "1.11.0") == (nothing, nothing)

    @test pool(:interactive, 4, 4, "2.8.0") == (:interactive, nothing)
    @test pool(:interactive, 4, 4, "1.11.0") == (:interactive, nothing)
    p, w = pool(:interactive, 1, 8, "2.8.0")
    @test p === :interactive && occursin("one at a time", w)
    p, w = pool(:interactive, 0, 8, "2.8.0")
    @test p === :interactive && occursin("run on the :default threadpool", w)

    @test pool(true, 4, 8, "2.8.0") == (:default, nothing)
    p, w = pool(true, 4, 1, "2.8.0")
    @test p === :default && occursin("only 1 thread", w)
end

@testitem "a request task's failure reaches HTTP.jl as the task's own error" tags=[:unit] begin
    # HTTP.jl tells a client that hung up (an `IOError` such as EPIPE, logged
    # at Debug) from a server fault by the error itself.
    epipe = Base.IOError("write: broken pipe (EPIPE)", Base.UV_EPIPE)
    handle = HTMXObjects._spawning_stream_handler(_ -> throw(epipe), :interactive)
    stack = try
        handle(nothing)
        nothing
    catch err
        @test err === epipe
        current_exceptions()
    end
    # The `TaskFailedException` stays beneath it, so a logged exception stack
    # still shows where in the task it failed.
    @test stack !== nothing &&
        [typeof(e.exception) for e in stack] == [TaskFailedException, Base.IOError]
    @test HTMXObjects._spawning_stream_handler(_ -> :done, :interactive)(nothing) === nothing
end

"""
A client that leaves while its answer is written: a buffered answer released
after the client closed, and an event stream the client closes after its first
event. HTTP.jl 2 fails the buffered write, HTTP.jl 1.x the head it writes once
more after the event stream ends; it logs either as a hang-up only when it sees
the error itself. The shape `serve(; parallel)` used before is the positive
control: it logs these hang-ups as Errors.
"""
@testitem "a client that hangs up is not a server error with serve(; parallel)" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server] begin
    using Sockets, Logging
    using HTTP.WebSockets: send

    struct ServerRecords <: AbstractLogger
        levels::Vector{LogLevel}
        lock::ReentrantLock
    end
    Logging.min_enabled_level(::ServerRecords) = Logging.Debug
    Logging.shouldlog(::ServerRecords, args...) = true
    Logging.catch_exceptions(::ServerRecords) = true
    Logging.handle_message(r::ServerRecords, level, args...; kw...) =
        lock(() -> push!(r.levels, level), r.lock)

    const HANGUP_RELEASE = Channel{Nothing}(Inf)
    const HANGUP_BODY = repeat("x"^1023 * "\n", 8 * 1024)   # 8 MiB
    @htmx struct ServeHangupApp
        @get hangup_answer() = (take!(HANGUP_RELEASE);
            HTTP.Response(200, ["Content-Type" => "text/plain"], HANGUP_BODY))
        @sse hangup_feed() = begin
            for i in 1:2000
                send(__sse__, "event $i " * "y"^4000; event="tick") || break
                sleep(0.002)
            end
            "done"
        end
    end
    route!(ServeHangupApp())

    function hang_up_on_answer(port)
        sock = connect(ip"127.0.0.1", port)
        write(sock, "GET /hangup_answer HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n\r\n")
        close(sock)
        sleep(0.2)
        put!(HANGUP_RELEASE, nothing)
    end
    function hang_up_on_stream(port)
        sock = connect(ip"127.0.0.1", port)
        watchdog = Timer(_ -> close(sock), 60)
        write(sock, "GET /hangup_feed HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n" *
                    "Accept: text/event-stream\r\n\r\n")
        readuntil(sock, "event: tick")
        close(watchdog)
        close(sock)
    end

    inner = HTMXObjects._stream_handler(HTMXObjects._request_pipeline([], nothing, nothing))
    # Error-level records the server logs while clients hang up on `handle`.
    function server_errors(handle)
        records = ServerRecords(LogLevel[], ReentrantLock())
        port = free_port()
        server = with_logger(() -> HTTP.listen!(handle, "127.0.0.1", port), records)
        try
            for _ in 1:3
                hang_up_on_answer(port)
                hang_up_on_stream(port)
                sleep(0.5)
            end
            sleep(1)
        finally
            close(server)
        end
        lock(() -> count(>=(Logging.Error), records.levels), records.lock)
    end

    @test server_errors(stream -> wait(Threads.@spawn :interactive inner(stream))) >= 1
    @test server_errors(HTMXObjects._spawning_stream_handler(inner, :interactive)) == 0
end
