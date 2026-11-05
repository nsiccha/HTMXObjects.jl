using TestItemRunner

# The HTMXObjects half of the frontend/backend process split (brief
# HTMXObjects:process-split `wworuo`, GO `1j4ws7y`): `configure_job_queue!`
# forwards the worker count and runs a stall watchdog; a part a worker-bound body
# sends ahead comes back as a DynamicObjects requester message; and a `@queued`
# route of a real package computes in the worker process end to end.

@testitem "configure_job_queue! takes workers and worker_stall; a positive worker count needs DynamicObjects' executor" tags=[:unit] begin
    using HTMXObjects, Test

    settings = configure_job_queue!()
    @test settings.workers isa Int && settings.worker_stall == Inf
    @test configure_job_queue!(; workers=0).workers == 0
    @test_throws ArgumentError configure_job_queue!(; workers=-1)
    @test_throws ArgumentError configure_job_queue!(; worker_stall=0)
    @test configure_job_queue!(; worker_stall=120).worker_stall == 120
    @test configure_job_queue!(; worker_stall=Inf).worker_stall == Inf
    if HTMXObjects._has_queue_workers()
        try
            @test configure_job_queue!(; workers=1).workers == 1
        finally
            configure_job_queue!(; workers=settings.workers)
        end
    else
        err = try
            configure_job_queue!(; workers=1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("workers", sprint(showerror, err))
        @test configure_job_queue!().workers == 0
    end
    # A workers call leaves the other settings as they were.
    @test configure_job_queue!(; workers=0).max_running == settings.max_running
    @test configure_job_queue!().abandon_after == settings.abandon_after

    # The watchdog's inputs: this process's CPU time is readable on Linux and
    # moves when it works; the stall exception names what happened.
    ticks = HTMXObjects._process_cpu_ticks(getpid())
    if Sys.islinux()
        @test ticks isa Int
        let s = 0.0, t0 = time()
            while time() - t0 < 0.15; s += rand(); end
        end
        @test HTMXObjects._process_cpu_ticks(getpid()) >= ticks
    else
        @test ticks === nothing
    end
    @test HTMXObjects._process_cpu_ticks(-1) === nothing
    msg = sprint(showerror, HTMXObjects._WorkerStalled(4242, 2, 61.4))
    @test occursin("pid 4242", msg) && occursin("2 computation", msg) && occursin("61 s", msg)
    @test haskey(HTMXObjects.runtime_snapshot().process, :worker)
end

@testitem "a part sent ahead from a worker lands on the requesting operation's list through DynamicObjects' requester message" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h, _SentAhead, _SENT_AHEAD, _sent_ahead_parts, _receive_sent_ahead!

    if !HTMXObjects._has_requester_messages()
        @test_skip "DynamicObjects before 0.5.7: no requester messages"
    else
        send = HTMXObjects.DynamicObjects.send_to_requester
        # In the requesting operation's scope (where DynamicObjects runs the
        # handler for a message from the worker), the part lands on its list.
        sink = _SentAhead()
        HTMXObjects.ScopedValues.with(_SENT_AHEAD => sink) do
            send(:htmxo_sent_ahead, "<p>from the worker</p>")
            send(:htmxo_sent_ahead, "<p>and again</p>")
        end
        @test last.(_sent_ahead_parts(sink, 0)) == ["<p>from the worker</p>", "<p>and again</p>"]
        @test first.(_sent_ahead_parts(sink, 1)) == [2]
        # Outside an operation the message is dropped, as `send_ahead` is.
        @test send(:htmxo_sent_ahead, "<p>nowhere</p>") === nothing
        @test send_ahead(h.p("nowhere")) === nothing
        @test length(_sent_ahead_parts(sink, 0)) == 2
        @test _receive_sent_ahead!("<p>outside</p>") === nothing
    end
end

# The toy application is a real package (`test/fixtures/worker_app/WorkerApp`):
# the worker loads the package that defines the root object's type.
@testmodule WorkerAppFixtures begin
    const FIXTURES = joinpath(@__DIR__, "fixtures", "worker_app")
    FIXTURES in LOAD_PATH || push!(LOAD_PATH, FIXTURES)
    using WorkerApp
    export WorkerApp
end

@testitem "a @queued route of a package computes in the worker process, and its part sent ahead reaches the page" setup=[FreshTransportFixtures, WorkerAppFixtures] tags=[:integration, :workers] begin
    using HTMXObjects, Test
    import HTMXObjects: _clear_operation_polls!

    if !HTMXObjects._has_queue_workers()
        @test_skip "DynamicObjects before 0.5.7: no worker executor"
    else
        _clear_operation_polls!()
        route!(WorkerApp.App())
        # A cold worker loads HTMXObjects and the fixture package first.
        function settle_slowly(url; seconds=240.0)
            body = Ref("")
            ok = timedwait(seconds; pollint=0.25) do
                body[] = body_text(hx_get(url))
                !running(body[])
            end
            ok === :ok || error("operation never settled within $(seconds) s: $(url)\n$(body[])")
            body[]
        end
        try
            configure_job_queue!(; workers=1)
            # The heavy route's value names the worker's pid, not this process's.
            first = body_text(hx_get("/heavy?n=1"))
            done = running(first) ? settle_slowly(poll_url(first)) : first
            pid = match(r"heavy pid=(\d+)", done)
            @test pid !== nothing
            @test parse(Int, pid.captures[1]) != getpid()
            status = HTMXObjects._worker_status()
            @test status.running && status.pid == parse(Int, pid.captures[1])
            # A light route computes here.
            @test contains(body_text(hx_get("/light")), "light pid=$(getpid())")
            # A part the worker sends ahead reaches the running poller's answer
            # before the route finishes, and the finished answer replaces it.
            gate = tempname()
            started = body_text(hx_get("/ahead?gate=$(gate)"))
            @test running(started)
            poll = poll_url(started)
            seen = Ref("")
            @test timedwait(240.0; pollint=0.25) do
                seen[] = body_text(hx_get(poll))
                contains(seen[], "ahead-part pid=") || !running(seen[])
            end === :ok
            @test contains(seen[], "ahead-part pid=$(status.pid)")
            @test running(seen[])
            touch(gate)
            finished = settle_slowly(poll)
            @test contains(finished, "ahead-done pid=$(status.pid)")
            @test !contains(finished, "ahead-part pid=")
            # The runtime panel names the worker.
            panel = repr(MIME"text/html"(), system_load_panel("/load"))
            @test contains(panel, "Worker") && contains(panel, "pid $(status.pid)")
        finally
            configure_job_queue!(; workers=0, worker_stall=Inf)
            _clear_operation_polls!()
        end
    end
end
