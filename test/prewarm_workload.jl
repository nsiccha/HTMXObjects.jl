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

@testitem "package warmup joins the selected page's load-triggered GETs" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    using Treebars
    starts = String[]
    attached = String[]
    function observe(handler)
        function (req)
            if haskey(req.context, :htmxo_prestart)
                push!(starts, String(req.target))
            elseif haskey(req.context, :htmxo_warm_page) && HTMXObjects._operation_attach_request(req)
                push!(attached, HTMXObjects._request_route_path(req))
            end
            handler(req)
        end
    end
    @htmx struct WarmFragmentApp
        @direct @get panel() = h.div(lazy("/part_a"), lazy("/part_b?x=2"),
                                      h.div(; hx_get=__self__/"unused", hx_trigger="click"))
        @get part_a() = h.p("warm-a")
        @get part_b(; x::Int=1) = h.p("warm-b-$x")
        @get unused() = error("a click is not part of the page load")
    end
    route!(WarmFragmentApp())
    settings = (; middleware=[observe])
    for (mode, routes, urls, expected) in (
            (:linked, [:panel], (), ["/part_a", "/part_b?x=2"]),
            (:selected, [:panel], (), String[]),
            (:selected, [:panel, :part_a], (), ["/part_a"]),
            (:selected, [:panel], ["/part_b?x=2"], ["/part_b?x=2"]))
        empty!(starts)
        empty!(attached)
        # Omit the keyword entirely for the default.
        kw = mode === :linked ? (;) : (; fragments=mode)
        rows = prewarm_workload!(WarmFragmentApp; routes, urls, server_kwargs=settings, kw...)
        @test first(rows.routes).status == 200
        @test starts == expected
        @test sort(intersect(attached, ["/part_a", "/part_b"])) ==
              sort([first(split(x, '?')) for x in expected])
        @test all(e -> !haskey(e.request.context, :htmxo_warm_page),
                  values(HTMXObjects._operation_poll_snapshot()))
    end
    @test_throws ArgumentError prewarm_workload!(WarmFragmentApp; fragments=:all)
end

@testitem "a failed warm attachment releases only that workload's operations" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    @htmx struct FailedWarmApp
        @direct @get landing() = h.section(lazy("/child"))
        @direct @get empty_page() = h.section(lazy("/empty_panel"))
        @get empty_panel() = throw(CallerFault(404, "no records yet"))
        @direct @get broken_page() = h.section(lazy("/broken_panel"))
        @get broken_panel() = error("broken panel computation")
        @get child() = h.p("child")
    end
    route!(FailedWarmApp())
    token = Ref("")
    function reject_attach(handler)
        function (req)
            if haskey(req.context, :htmxo_warm_page) && HTMXObjects._operation_attach_request(req)
                token[] = HTMXObjects._operation_poll_token(req)
                return HTTP.Response(200, ["X-HTMXO-Error-Id" => "warm-test"], "failed")
            end
            handler(req)
        end
    end
    failure = try
        prewarm_workload!(FailedWarmApp; routes=[:landing], server_kwargs=(; middleware=[reject_attach]))
        nothing
    catch err
        err
    end
    @test failure isa ErrorException
    @test occursin("warm-test", sprint(showerror, failure))
    @test !isempty(token[])
    @test !haskey(HTMXObjects._operation_poll_snapshot(), token[])
    @test !haskey(HTMXObjects._pushed_answers, token[])
    @test !isopen(HTMXObjects._SERVER[])

    @test all(r -> r.status == 200, prewarm_workload!(FailedWarmApp; routes=[:empty_page]).routes)
    @test_throws ErrorException prewarm_workload!(FailedWarmApp; routes=[:empty_panel])
    @test_throws ErrorException prewarm_workload!(FailedWarmApp; routes=[:broken_page])

    # An ordinary navigation on the same temporary listener has its own token.
    unrelated = Ref("")
    prewarm_workload!(FailedWarmApp; routes=[:landing]) do base
        response = HTTP.get(base * "/landing", ["Accept" => "text/html"])
        address = HTMXObjects._prewarm_next(String(response.body))
        unrelated[] = HTTP.queryparams(HTTP.URI(address))["__htmxo_operation"]
    end
    try
        @test haskey(HTMXObjects._operation_poll_snapshot(), unrelated[])
    finally
        HTMXObjects._end_operation_poll!(unrelated[], :abandoned)
    end
end

@testitem "a warm navigation consumes the built-in operation stream" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    using Treebars
    release = Base.Event()
    stream_seen = Ref(false)
    function observe(handler)
        function (req)
            if haskey(req.context, :htmxo_warm_page) &&
                    HTMXObjects._operation_stream_tokens(req) !== nothing
                stream_seen[] = true
                notify(release)
            end
            handler(req)
        end
    end
    @htmx struct WarmStreamApp
        @direct @get warm_landing() = h.section(lazy("/warm_fragment"))
        @get warm_fragment() = (wait(release); h.p("stream-result"))
    end
    route!(WarmStreamApp())
    try
        rows = prewarm_workload!(WarmStreamApp; routes=[:warm_landing],
            timeout=10, server_kwargs=(; middleware=[observe]))
        @test all(row -> row.status == 200, rows.routes)
        @test stream_seen[]
        @test all(e -> !haskey(e.request.context, :htmxo_warm_page),
                  values(HTMXObjects._operation_poll_snapshot()))
    finally
        notify(release)
    end
end

@testmodule StandaloneWarmFixture begin
    using HTMXObjects
    export WarmForm, gate
    const gate = Ref(Base.Event())
    @htmx struct WarmForm
        @param label_text::String = "A & B"
        @param cards::Records = Records(:label_text; presets=[(label_text="one / two",)])
        @param heading::String = "current"
        @get first_view() = begin
            wait(gate[])
            h.p(string(heading, "|", first(cards).label_text); id="first-view-answer")
        end
        @direct @get health() = h.p("ready")
        @direct @get landing() = semantic_app(__self__; presentation=:tabs,
            select=e -> e.name === :first_view)
        __page__(body) = htmx(body, h.script(Raw(raw"""
            const timer = setInterval(() => {
              const answer = document.getElementById('first-view-answer');
              if (!answer) return;
              clearInterval(timer);
              fetch('/report?answer=' + encodeURIComponent(answer.textContent));
            }, 30);
            """)); assets=:vendor, runtime=:linked, pico_version=nothing)
    end
end

@testitem "standalone warmup joins and starts the open semantic view" setup=[HTMXOTestImports, StandaloneWarmFixture] tags=[:integration, :server] begin
    using Treebars
    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    requests = NamedTuple[]
    report = Channel{String}(1)
    function observe(handler)
        function (req)
            target = String(req.target)
            if startswith(target, "/report?")
                put!(report, HTTP.queryparams(HTTP.URI(target))["answer"])
                return HTTP.Response(204)
            end
            stream = HTMXObjects._operation_stream_tokens(req) !== nothing
            poll = HTMXObjects._operation_poll_request(req)
            inner = haskey(req.context, :htmxo_prestart) || haskey(req.context, :htmxo_push)
            push!(requests, (; target, stream, poll, inner,
                warm=haskey(req.context, :htmxo_warm_page),
                current=HTTP.header(req, "HX-Current-URL", ""),
                element=HTTP.header(req, "HX-Target", "")))
            (stream || poll) && notify(gate[])
            handler(req)
        end
    end
    route!(WarmForm())
    vendorfiles()
    path = "/landing?heading=edited"
    view(q) = HTMXObjects._operation_unmarked_url(q.target)
    isview(q) = !q.inner && !q.poll && startswith(q.target, "/first_view?")
    for (prestart, operation_stream) in ((true, true), (false, true), (false, false))
        server = serve(; port=0, listenany=true, async=true, prestart, operation_stream,
                       middleware=[observe], access_log=nothing)
        base = "http://127.0.0.1:$(HTTP.port(server))"
        try
            empty!(requests)
            gate[] = Base.Event()
            rows = prewarm_routes!(base, [path]; operations=true)
            @test all(r -> r.error === nothing && r.status in (200, 286), rows)
            views = filter(q -> q.warm && isview(q), requests)
            fresh = only(filter(q -> !occursin("__htmxo_operation=", q.target), views))
            @test fresh.current == base * path
            @test !isempty(fresh.element)
            @test count(q -> occursin("__htmxo_operation=", q.target), views) == Int(prestart)
            params = HTTP.queryparams(HTTP.URI(fresh.target))
            @test params["cards.1.label_text"] == "one / two"
            @test params["heading"] == "edited"
            @test all(q -> view(q) == fresh.target, views)
            streams = filter(q -> q.stream, requests)
            @test [r.url for r in rows if r.transport === :stream] == [base * q.target for q in streams]
            @test isempty(streams) == !operation_stream
            @test all(q -> startswith(q.target, "/landing?__htmxo_operations=") &&
                           endswith(q.target, "&__htmxo_push=1"), streams)
            @test any(q -> q.warm && q.poll, requests)
            @test any(q -> q.warm && q.poll && !q.inner, requests) == !operation_stream
            @test isempty(HTMXObjects._warm_pages)
            @test all(e -> !haskey(e.request.context, :htmxo_warm_page),
                      values(HTMXObjects._operation_poll_snapshot()))

            # The inventory entry point has the same default. An immediate
            # direct answer opens no stream, and opting out preserves the rows.
            if prestart
                for browser in (true, false)
                    rows = prewarm_routes!(WarmForm, base, :health; operations=true, browser)
                    @test count(r -> r.transport === :browser, rows) == Int(browser)
                    @test all(r -> r.status == 200 && r.transport !== :stream, rows)
                end
            end

            if prestart && get(ENV, "HTMXO_BROWSER_TESTS", "") == "1"
                empty!(requests)
                gate[] = Base.Event()
                mktempdir() do profile
                    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
                    cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $(base * path)`
                    proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                    try
                        @test timedwait(() -> isready(report) || process_exited(proc), 90) == :ok
                        isready(report) || error("Chromium did not receive the first view")
                        @test take!(report) == "edited|one / two"
                        @test view(only(filter(isview, requests))) == fresh.target
                        @test any(q -> q.stream, requests)
                    finally
                        process_exited(proc) || kill(proc)
                        wait(proc)
                    end
                end
            end
        finally
            notify(gate[])
            close(server)
        end
    end
end

@testitem "a timed-out standalone stream leaves an ordinary pending view intact" setup=[HTMXOTestImports, StandaloneWarmFixture] tags=[:integration, :server] begin
    using Treebars
    route!(WarmForm())
    gate[] = Base.Event()
    server = serve(; port=0, listenany=true, async=true, prestart=false, access_log=nothing)
    base = "http://127.0.0.1:$(HTTP.port(server))"
    try
        ordinary = HTTP.get(base * "/first_view?heading=other", ["HX-Request" => "true"])
        address = HTMXObjects._prewarm_next(String(ordinary.body))
        token = HTTP.queryparams(HTTP.URI(address))["__htmxo_operation"]
        rows = prewarm_routes!(base, "/landing"; browser=true, timeout=2)
        stream = only(filter(r -> get(r, :transport, nothing) === :stream, rows))
        @test stream.status === nothing && occursin("outside compilation", stream.error)
        @test stream.requests == 1
        @test isempty(HTMXObjects._warm_pages)
        snapshot = HTMXObjects._operation_poll_snapshot()
        @test haskey(snapshot, token)
        @test all(e -> !haskey(e.request.context, :htmxo_warm_page), values(snapshot))
        notify(gate[])
        answer = HTTP.get(base * address, ["HX-Request" => "true"])
        @test answer.status == 286 && occursin("other|one / two", String(answer.body))
    finally
        notify(gate[])
        HTTP.forceclose(server)
    end
end
