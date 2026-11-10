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

@testitem "worker routes preserve request parameters through parent and nested mounts" setup=[FreshTransportFixtures, WorkerAppFixtures] tags=[:integration, :workers] begin
    using HTMXObjects, Test
    import HTMXObjects: _clear_operation_polls!

    function completed(response)
        body = body_text(response)
        running(body) || return body
        url = poll_url(body)
        answer = Ref(body)
        timedwait(240.0; pollint=0.25) do
            answer[] = body_text(hx_get(url))
            !running(answer[])
        end === :ok || error("worker parameter request never settled: $url\n$(answer[])")
        answer[]
    end
    try
        for workers in (0, 1), kind in (:request, :retained, :custom)
            configure_job_queue!(; workers)
            _clear_operation_polls!()
            provider = kind === :retained ? RootProvider(; scope=:job, key=_->:parameters,
                retention=RootRetention()) : kind === :custom ?
                RootProvider((T, ctx) -> T(; __req__=ctx.request)) : RootProvider()
            route!(WorkerApp.ParamApp(); root_provider=provider)
            for (dataset, version) in (("tiny", 1), ("another", 2))
                query = "dataset=$dataset&data_version=$version&tags=a&tags=b&child=9&method=sample&level=2&optional=7&enabled=true"
                body = completed(hx_get("/fit/results?$query"))
                @test contains(body, "dataset=$dataset version=$version tags=a,b child=9 method=sample")
                @test contains(body, "level=2 optional=7")
                pid = match(r"pid=(\d+)", body)
                @test pid !== nothing
                @test (parse(Int, pid.captures[1]) == getpid()) == (workers == 0)
                nested = completed(hx_get("/nested/deeper/results?$query"))
                @test contains(nested, "dataset=$dataset version=$version tags=a,b")
            end
            # The form wins over the query; a blank form field falls back to it.
            body = completed(hx_post("/fit/results?dataset=query&data_version=7&tags=q",
                "dataset=form&data_version=&tags=x&tags=y&child=11&method=post"))
            @test contains(body, "dataset=form version=7 tags=x,y child=11 method=post")
            untyped = completed(dispatch(:POST, "/fit/results";
                headers=["HX-Request" => "true"], body="dataset=no-content-type&data_version=8"))
            @test contains(untyped, "dataset=no-content-type version=8")
            defaults = completed(hx_get("/fit/results?optional=99"))
            @test contains(defaults, "dataset=default version=0 tags=default child=3 method=pathfinder")
            @test contains(defaults, "level=1 optional=4")
        end
        route!(WorkerApp.UploadApp())
        form = "--boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"tiny.txt\"\r\nContent-Type: text/plain\r\n\r\nrequested bytes\r\n--boundary--\r\n"
        body = completed(dispatch(:POST, "/received"; headers=["HX-Request" => "true",
            "Content-Type" => "multipart/form-data; boundary=boundary"], body=form))
        @test contains(body, "name=tiny.txt data=requested bytes")
        @test !contains(body, "pid=$(getpid()) ")
    finally
        configure_job_queue!(; workers=0, worker_stall=Inf)
        _clear_operation_polls!()
    end
end

@testitem "remounting a parameter snapshot with a live request uses the new request" setup=[WorkerAppFixtures] tags=[:unit] begin
    using HTMXObjects, Test, HTTP
    first = HTTP.Request("GET", "/?dataset=first&data_version=1")
    second = HTTP.Request("GET", "/?dataset=second&data_version=2")
    app = DynamicObjects.remount(WorkerApp.ParamApp(); __req__=first,
        __param_request__=HTMXObjects._param_request(first))
    @test app.fit.dataset == "first"
    rebound = DynamicObjects.remount(app; __req__=second)
    @test rebound.fit.dataset == "second"
    @test rebound.nested.deeper.data_version == 2
    @test app.fit.dataset == "first"
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
            # A live request's reader is private; the fixtures' `dispatch` is
            # public outside any request, so the private requests say so.
            private_get(target) = dispatch(:GET, target;
                headers=["HX-Request" => "true"], audience=:private)
            # The heavy route's value names the worker's pid, not this process's.
            first = body_text(private_get("/heavy?n=1"))
            done = running(first) ? settle_slowly(poll_url(first)) : first
            pid = match(r"heavy pid=(\d+)", done)
            @test pid !== nothing
            @test parse(Int, pid.captures[1]) != getpid()
            status = HTMXObjects._worker_status()
            @test status.running && status.pid == parse(Int, pid.captures[1])
            # The worker binds the answer's page language (the app declares
            # `__lang__ = "de"`) and the reader's audience around the
            # computation, as this process does for its light route: a private
            # request's answer reads private, a public request's public.
            light = body_text(private_get("/light"))
            @test contains(light, "light pid=$(getpid()) lang=de audience=private")
            @test contains(done, "n=1 lang=de audience=private")
            public = body_text(hx_get("/heavy?n=2"))
            public = running(public) ? settle_slowly(poll_url(public)) : public
            @test contains(public, "heavy pid=$(status.pid) n=2 lang=de audience=public")
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

# Snag `caller-fault-in-53f41794`: a refusal raised in the worker reaches this
# process as itself (DynamicObjects 0.5.13), so nothing about the answer depends
# on `workers`. Before, each of these answered 500 with the message lost.
@testitem "a caller fault raised in a worker answers as it does in this process" setup=[FreshTransportFixtures, WorkerAppFixtures] tags=[:integration, :workers] begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: _clear_operation_polls!

    masked(body) = replace(body, r"Error ID: (<code>|`)[0-9a-f]+(</code>|`)" => "Error ID: <id>",
        r"pid=\d+" => "pid=<pid>")
    # A cold worker loads HTMXObjects and the fixture package first.
    function polled(path; seconds=240.0)
        answer = Ref(body_text(hx_get(path)))
        running(answer[]) || return answer[]
        url = poll_url(answer[])
        timedwait(seconds; pollint=0.25) do
            answer[] = body_text(hx_get(url))
            !running(answer[])
        end === :ok || error("operation never settled within $(seconds) s: $path\n$(answer[])")
        answer[]
    end
    # An operation's terminal wraps its answer when it ends a poll, and the poll's
    # status depends on timing, so a browser's row compares the answer itself.
    article(body) = masked(something(match(r"<article.*</article>"s, body), (; match=body)).match)

    # path => (status, what the message says)
    faults = [
        "/timecourse?n=0" => (400, "new subjects need at least 1 subject, got 0"),
        "/options?fit=not-a-fit" => (400, "Invalid value for parameter fit"),
        "/memoized?k=0" => (404, "unknown k 0"),
        "/required" => (400, "Missing required parameter: must"),
        "/typed?n=abc" => (400, "Invalid value for parameter n"),
        "/typed?colour=blue" => (400, "red"),
        "/typed?wait=soon" => (400, "Millis"),
        "/probe?k=0" => (409, "probe 0 is refused"),
    ]
    old_dir = HTMXObjects.ERROR_DIR[]
    try
        mktempdir() do dir
            HTMXObjects.ERROR_DIR[] = dir
            log_of(response) = read(joinpath(dir, HTTP.header(response, "X-HTMXO-Error-Id") * ".log"), String)
            answers = Dict{Int,Dict{Any,Any}}()
            printouts = Dict{Int,Any}()
            for workers in (0, 1)
                configure_job_queue!(; workers)
                _clear_operation_polls!()
                route!(WorkerApp.FaultApp(); root_provider=RootProvider())
                # The worker path is really taken: a computation names its process.
                pid = parse(Int, only(match(r"pid=(\d+)", polled("/timecourse?n=2")).captures))
                @test (pid == getpid()) == (workers == 0)
                seen = answers[workers] = Dict{Any,Any}()
                for (path, (status, message)) in faults
                    for (kind, headers) in (:markdown => ["Accept" => "text/markdown"], :html => Pair{String,String}[])
                        response = dispatch(:GET, path; headers, operation_policy=:blocking)
                        body = masked(body_text(response))
                        @test (path, kind, response.status) == (path, kind, status)
                        @test contains(body, message)
                        seen[(path, kind)] = (response.status, body)
                        contains(log_of(response), "status:    $status\n") || @test "log of $path" == "names $status"
                    end
                    seen[(path, :polled)] = article(polled(path))
                    @test contains(seen[(path, :polled)], message)
                end
                # The control: a server fault stays a 500 and says nothing more.
                boom = dispatch(:GET, "/boom"; headers=["Accept" => "text/markdown"], operation_policy=:blocking)
                @test boom.status == 500
                seen[:boom] = (boom.status, masked(body_text(boom)))
                @test !contains(seen[:boom][2], "server fault in the body")
                @test contains(log_of(boom), "server fault in the body")
                # The log keeps what the worker printed, for a refusal and a server fault.
                refused = dispatch(:GET, "/timecourse?n=0"; operation_policy=:blocking)
                printouts[workers] = map((refused, boom)) do response
                    contains(log_of(response), "RemoteComputationError: in worker process $pid")
                end
                route!(WorkerApp.FaultHookApp())
                hooked = dispatch(:GET, "/hooked"; operation_policy=:blocking)
                seen[:hook] = (hooked.status, masked(body_text(hooked)))
                @test contains(seen[:hook][2], "hook saw CallerFault status=422 message=hooked fault")
                @test hooked.status == 422
            end
            @test sort!(collect(keys(answers[1])); by=repr) == sort!(collect(keys(answers[0])); by=repr)
            for (row, answer) in answers[0]
                @test (row => answers[1][row]) == (row => answer)
            end
            @test printouts[0] == (false, false)
            @test printouts[1] == (true, true)
        end
    finally
        HTMXObjects.ERROR_DIR[] = old_dir
        configure_job_queue!(; workers=0, worker_stall=Inf)
        _clear_operation_polls!()
    end
end

@testitem "a server fault raised in a worker shows its cause where the app shows causes" setup=[FreshTransportFixtures, WorkerAppFixtures] tags=[:integration, :workers] begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: _clear_operation_polls!

    if !HTMXObjects._has_queue_workers()
        @test_skip "DynamicObjects before 0.5.7: no worker executor"
    else
        unescaped(s) = replace(s, "&#39;" => "'", "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&")
        function cause(body)
            m = match(r"<p><strong>(\w+)</strong></p><pre class=\"htmxo-error-cause\">(.*?)</pre>"s, body)
            m === nothing ? nothing : [unescaped(String(c)) for c in m.captures]
        end
        old_dir = HTMXObjects.ERROR_DIR[]
        try
            mktempdir() do dir
                HTMXObjects.ERROR_DIR[] = dir
                for workers in (0, 1)
                    configure_job_queue!(; workers)
                    _clear_operation_polls!()
                    route!(WorkerApp.ShownFaultApp(); root_provider=RootProvider())
                    # A cold worker loads HTMXObjects and the fixture package first.
                    boom = dispatch(:GET, "/boom"; headers=["HX-Request" => "true"], operation_policy=:blocking)
                    @test cause(body_text(boom)) == ["ErrorException", "server fault shown\nits second line"]
                    @test contains(body_text(boom), "<summary>Log entry <code>")
                    # An exception that holds the app cannot cross: the worker's
                    # printout up to its backtrace stands for it.
                    held = cause(body_text(dispatch(:GET, "/held"; headers=["HX-Request" => "true"],
                                                    operation_policy=:blocking)))
                    if workers == 0
                        @test held == ["HeldFault", "the held fault's message"]
                    else
                        @test held[1] == "RemoteComputationError"
                        @test contains(held[2], "HeldFault: the held fault's message")
                        @test !contains(held[2], "Stacktrace:")
                    end
                end
            end
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
            configure_job_queue!(; workers=0, worker_stall=Inf)
            _clear_operation_polls!()
        end
    end
end
