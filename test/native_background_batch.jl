using TestItemRunner

@testmodule NativeBackgroundBatchFixture begin
    include(joinpath(@__DIR__, "..", "examples", "native_background_batch.jl"))
    export NativeBackgroundBatch
end

@testitem "native batch POST and startup share the background queue" setup=[NativeBackgroundBatchFixture] tags=[:integration, :semantic] begin
    using HTMXObjects, Treebars, HTTP

    gates = [Base.Event() for _ in 1:7]
    started = Channel{Int}(7)
    workspace = mktempdir()
    NativeBackgroundBatch.mount(workspace;
        before_compute=batch_id -> (put!(started, batch_id); wait(gates[batch_id])))
    settings = configure_job_queue!()
    configure_job_queue!(; max_running=2, abandon_after=Inf)

    function response(method, url)
        resp = dispatch(method, url; headers=["HX-Request" => "true"])
        @test resp.status == 200
        @test isempty(HTTP.header(resp, "X-HTMXO-Error-Id", ""))
        String(resp.body)
    end
    states() = [row for row in runtime_jobs(; states=(:queued, :running, :done, :failed))
                if startswith(row.target, "/result/")]
    wait_for(predicate) = timedwait(predicate, 10.0; pollint=0.01) === :ok

    try
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        for batch_id in 1:7
            write(joinpath(workspace, "request-$batch_id.txt"), string(10 * batch_id))
        end
        # No listener, browser or app-owned task/executor is needed at startup.
        @test contains(response(:GET, "/result/1"), "treebar-poller-inner")
        @test contains(response(:POST, "/submit/2"), "treebar-poller-inner")
        @test contains(response(:POST, "/submit/3"), "treebar-poller-inner")
        @test wait_for(() -> count(r -> r.state === :running, states()) == 2 &&
                            count(r -> r.state === :queued, states()) == 1)
        @test Set((take!(started), take!(started))) == Set((1, 2))
        @test configure_job_queue!().queued == 1
        @test only(filter(r -> r.state === :queued, states())).position == 1
        println("native batch states: ", [(r.target, r.state, r.position) for r in states()])

        # Running and queued repeats join the original computations.
        count_before = length(states())
        @test contains(response(:POST, "/submit/1"), "treebar-poller-inner")
        @test contains(response(:POST, "/submit/3"), "treebar-poller-inner")
        @test length(states()) == count_before
        @test !isready(started)
        @test configure_job_queue!().queued == 1
        board = repr("text/html", jobs_board(; all=true))
        @test contains(board, "2 running · 1 queued")
        @test contains(board, "queued · #1")
        @test contains(response(:GET, "/jobs"), "queued · #1")
        @test !isfile(joinpath(workspace, "result-3.txt"))

        # Inf survives more than the reaper's maximum one-second interval.
        sleep(1.2)
        @test configure_job_queue!().queued == 1
        notify(gates[1])
        @test wait_for(() -> any(r -> r.target == "/result/3" && r.state === :running, states()))
        @test take!(started) == 3
        notify(gates[2]); notify(gates[3])
        @test wait_for(() -> count(r -> r.state === :done, states()) == 3)
        for batch_id in 1:3
            expected = sum(abs2, 1:(10 * batch_id))
            @test read(joinpath(workspace, "result-$batch_id.txt"), String) == string(expected)
            @test contains(response(:GET, "/result/$batch_id"), "batch:$batch_id result:$expected")
        end
        @test !isready(started) # completed-result reads did not repeat the work

        # Positive control: a finite timeout abandons queued, never started work.
        response(:GET, "/result/5"); response(:GET, "/result/6")
        @test Set((take!(started), take!(started))) == Set((5, 6))
        configure_job_queue!(; abandon_after=0.15)
        @test contains(response(:GET, "/result/4"), "treebar-poller-inner")
        @test wait_for(() -> any(r -> r.target == "/result/4" && r.state === :failed &&
                                contains(something(r.error, ""), "abandoned"), states()))
        @test !isready(started)
        @test !isfile(joinpath(workspace, "result-4.txt"))

        # A path-stripping proxy is outside dispatch. Route internally and
        # forward its prefix so the returned progress URLs stay browser-facing.
        configure_job_queue!(; abandon_after=Inf)
        NativeBackgroundBatch.mount(workspace; prefix="/p/demo",
            before_compute=batch_id -> (put!(started, batch_id); wait(gates[batch_id])))
        headers = ["HX-Request" => "true", "X-Forwarded-Prefix" => "/p/demo"]
        submitted = dispatch(:POST, "/submit/7"; headers)
        @test submitted.status == 200
        @test isempty(HTTP.header(submitted, "X-HTMXO-Error-Id", ""))
        @test contains(String(submitted.body), "hx-get=\"/p/demo/result/7?")
        @test configure_job_queue!().queued == 1
        startup = dispatch(:GET, "/result/7"; headers)
        @test startup.status == 200
        @test isempty(HTTP.header(startup, "X-HTMXO-Error-Id", ""))
        @test contains(String(startup.body), "hx-get=\"/p/demo/result/7?")
        @test configure_job_queue!().queued == 1
        @test !isready(started)
        @test dispatch(:GET, "/p/demo/result/7"; headers).status == 404
    finally
        foreach(notify, gates)
        configure_job_queue!(; max_running=0, abandon_after=Inf)
        @test wait_for(() -> all(r -> r.state in (:done, :failed), states()))
        configure_job_queue!(; max_running=settings.max_running, abandon_after=settings.abandon_after)
    end
end
