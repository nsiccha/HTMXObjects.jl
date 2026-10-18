using TestItemRunner

# A slow `:auto` page answers in many requests: the first one returns a poller
# after the grace period, the browser polls, and a `286` answer ends it. The
# access log has one line per request, so how long the operation took, how many
# polls it needed and how it ended could only be recovered by grouping lines by
# their bearer token (snag `polled-operation-3eec5c50`, reporter Invoices). Every
# polled operation now writes one record when it ends (`serve(; operation_log)`,
# `HTMXObjects.OPERATION_LOG`).
@testmodule OperationLogFixtures begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h
    import Test

    export OpLogReadApp, OpLogMutationApp, OpLogPropagateApp, reset_oplog!,
        release!, finished!, hx_get, hx_post, running, poll_url, settle,
        body_text, with_records, operation_lines

    const oplog_lock = ReentrantLock()
    const gates = Dict{Symbol,Base.Event}()
    const done = Dict{Symbol,Int}()

    function reset_oplog!()
        lock(oplog_lock) do
            for key in collect(keys(gates))
                notify(gates[key])   # free anything an earlier item left waiting
            end
            empty!(gates)
            empty!(done)
        end
        nothing
    end

    gate(key::Symbol) = lock(() -> get!(Base.Event, gates, key), oplog_lock)
    release!(key::Symbol) = notify(gate(key))
    finished!(key::Symbol) = lock(() -> get(done, key, 0) > 0, oplog_lock)

    function gated(key::AbstractString, answer)
        k = Symbol(key)
        wait(gate(k))
        try
            answer()
        finally
            lock(() -> (done[k] = get(done, k, 0) + 1), oplog_lock)
        end
    end

    @htmx struct OpLogReadApp
        "Compute the logged report"
        @get oplog_report(; key::String="report", token::String="") =
            gated(key, () -> h.p("report-$key"))
        "Compute the doomed report"
        @get oplog_doomed(; key::String="doomed") =
            gated(key, () -> error("report exploded"))
        "Answer at once"
        @get oplog_quick() = h.p("quick")
    end

    @htmx struct OpLogMutationApp
        "Submit the logged order"
        @post oplog_order(; key::String="order") =
            gated(key, () -> h.p("ordered-$key"))
    end

    # Failures propagate out of the poller instead of rendering inside it.
    @htmx struct OpLogPropagateApp
        "Compute the propagated failure"
        @get oplog_propagated(; key::String="propagated") =
            gated(key, () -> error("propagated failure"))
    end

    const hx = ["HX-Request" => "true"]
    hx_get(target) = dispatch(:GET, target; headers=hx)
    hx_post(target, body="") = dispatch(:POST, target;
        headers=[hx; "Content-Type" => "application/x-www-form-urlencoded";
                 "HTMXO-Swap" => "innerHTML"],
        body)

    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")

    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end

    function settle(target)
        for _ in 1:400
            response = hx_get(target)
            running(body_text(response)) || return response
            sleep(0.025)
        end
        error("operation never settled: $target")
    end

    # Run `f` with operation records on, capturing each record and the logged
    # lines; the process-wide setting is restored afterwards.
    function with_records(f)
        records = HTMXObjects.OperationRecord[]
        format = (io, record) -> begin
            push!(records, record)
            HTMXObjects._default_operation_log(io, record)
        end
        logger = Test.TestLogger()
        previous = HTMXObjects.OPERATION_LOG[]
        HTMXObjects.OPERATION_LOG[] = format
        try
            with_logger(() -> f(records), logger)
        finally
            HTMXObjects.OPERATION_LOG[] = previous
        end
        records, logger
    end

    operation_lines(logger) = [string(l.message) for l in logger.logs
                               if l.group === :operation]
end

@testitem "serve writes one operation line for a slow page next to its access lines" setup=[OperationLogFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Treebars, Logging, Test

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogReadApp())
    port = free_port()
    base = "http://127.0.0.1:$port"
    logger = TestLogger()
    previous = HTMXObjects.OPERATION_LOG[]
    with_logger(logger) do
        serve(; port, async=true)
    end
    fetch_hx(target) = HTTP.get(base * target, ["HX-Request" => "true"];
                                retry=false, readtimeout=20)
    try
        # On by default.
        @test HTMXObjects.OPERATION_LOG[] === HTMXObjects._default_operation_log
        # `String(body)` takes the bytes: read each body once.
        first_body = String(fetch_hx("/oplog_report?key=served").body)
        @test running(first_body)
        url = poll_url(first_body)
        @test contains(url, "__htmxo_operation=")
        for _ in 1:3
            @test running(String(fetch_hx(url).body))
        end
        release!(:served)
        @test timedwait(() -> finished!(:served), 10.0; pollint=0.01) === :ok
        final = nothing
        for _ in 1:400
            final = fetch_hx(url)
            final.status == 286 && break
            sleep(0.025)
        end
        @test final.status == 286
        @test contains(String(final.body), "report-served")
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = previous
    end
    lines = [string(l.message) for l in logger.logs if l.group === :operation]
    @test length(lines) == 1
    line = only(lines)
    @test occursin(r"^\S+ - operation GET /oplog_report\?key=served ok compute=\d+\.\ds answered=\d+\.\ds polls=\d+$", line)
    @test parse(Int, only(match(r"polls=(\d+)", line).captures)) >= 4
    # The bearer token stays out of the record.
    @test !contains(line, "__htmxo")
    # The access log still writes one line per request.
    access = [string(l.message) for l in logger.logs if l.group === :access]
    @test count(m -> contains(m, "\"GET /oplog_report?"), access) >= 5
end

@testitem "a polled operation records ok once with compute, answered and polls" setup=[OperationLogFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test

    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogReadApp())
    records, logger = with_records() do records
        # An operation that answers within the grace period is only a request.
        @test !running(body_text(hx_get("/oplog_quick")))
        @test isempty(records)

        url = poll_url(body_text(hx_get("/oplog_report?key=ok1&token=s3cret")))
        @test running(body_text(hx_get(url)))
        @test running(body_text(hx_get(url)))
        release!(:ok1)
        @test timedwait(() -> finished!(:ok1), 10.0; pollint=0.01) === :ok
        # The client asks again only later: the answer comes after the
        # computation finished, and the record keeps the two apart.
        sleep(0.5)
        final = settle(url)
        @test contains(body_text(final), "report-ok1")
        @test isempty(HTTP.header(final, "X-HTMXO-Error-Id", ""))
    end
    @test length(records) == 1
    r = only(records)
    @test r.outcome === :ok
    @test r.method == "GET"
    # Operation markers are gone, credential-like values are redacted.
    @test r.target == "/oplog_report?key=ok1&token=…"
    @test r.polls >= 3
    @test 0 < r.compute < r.answered
    @test r.answered - r.compute >= 0.4
    @test r.last_seen >= r.compute
    @test abs(r.started_at + r.answered - time()) < 5
    lines = operation_lines(logger)
    @test length(lines) == 1
    @test occursin(r" - operation GET /oplog_report\?key=ok1&token=… ok compute=\d+\.\ds answered=\d+\.\ds polls=\d+$", only(lines))
end

@testitem "failed, propagated and stalled operations record how they ended" setup=[OperationLogFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test

    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogReadApp())
    route!(OpLogPropagateApp();
           operation_policy=OperationPolicy(:auto; keep_progress=false))
    records, _ = with_records() do records
        # A failure Treebars renders inside the poller's terminal.
        url = poll_url(body_text(hx_get("/oplog_doomed?key=doomed1")))
        release!(:doomed1)
        @test timedwait(() -> finished!(:doomed1), 10.0; pollint=0.01) === :ok
        failed = settle(url)
        @test contains(body_text(failed), "data-treebar-status=\"failed\"")
        @test count(r -> r.outcome === :failed, records) == 1

        # A failure that propagates out of the poller to the route boundary.
        url = poll_url(body_text(hx_get("/oplog_propagated?key=prop1")))
        release!(:prop1)
        @test timedwait(() -> finished!(:prop1), 10.0; pollint=0.01) === :ok
        settle(url)
        @test count(r -> r.outcome === :failed, records) == 2

        # A computation past its stall bound answers `OperationStalled`.
        url = poll_url(body_text(hx_get("/oplog_report?key=stall1")))
        for entry in values(HTMXObjects._operation_poll_snapshot())
            entry.created_at -= 601
        end
        stalled = hx_get(url)
        @test contains(body_text(stalled), "Operation stalled")
        release!(:stall1)
    end
    failures = filter(r -> r.outcome === :failed, records)
    @test [r.target for r in failures] ==
          ["/oplog_doomed?key=doomed1", "/oplog_propagated?key=prop1"]
    @test all(r -> 0 < r.compute <= r.answered, failures)
    stall = only(filter(r -> r.outcome === :stalled, records))
    @test stall.target == "/oplog_report?key=stall1"
    @test isnan(stall.compute)
    @test stall.answered >= 601
    @test length(records) == 3
end

@testitem "an operation nobody reaches any more is recorded as abandoned" setup=[OperationLogFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test

    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogReadApp())
    records, logger = with_records() do records
        url = poll_url(body_text(hx_get("/oplog_report?key=gone1")))
        @test running(body_text(hx_get(url)))
        release!(:gone1)
        @test timedwait(() -> finished!(:gone1), 10.0; pollint=0.01) === :ok
        # The page was closed: nothing polls it for the registry's TTL, and
        # the next registry access drops it.
        later = HTMXObjects._operation_poll_now() + HTMXObjects._OPERATION_POLL_TTL
        @test isempty(HTMXObjects._operation_poll_snapshot(; now=later))
    end
    r = only(records)
    @test r.outcome === :abandoned
    @test r.polls == 1
    @test isnan(r.answered)
    @test r.compute >= 0
    @test 0 <= r.last_seen < 60
    @test occursin(r" abandoned compute=\d+\.\ds answered=- polls=1 last_poll=\d+\.\ds$",
                   only(operation_lines(logger)))
end

@testitem "a mutation records once although its terminal is replayed" setup=[OperationLogFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test

    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogMutationApp())
    records, _ = with_records() do records
        url = poll_url(body_text(hx_post("/oplog_order", "key=m1")))
        @test contains(url, "__htmxo_verb=POST")
        release!(:m1)
        @test timedwait(() -> finished!(:m1), 10.0; pollint=0.01) === :ok
        first_answer = body_text(settle(url))
        @test contains(first_answer, "ordered-m1")
        # A lost answer is replayed from the terminal cache.
        @test contains(body_text(hx_get(url)), "ordered-m1")
    end
    r = only(records)
    @test r.outcome === :ok
    @test r.method == "POST"
    @test r.target == "/oplog_order"
end

@testitem "operation_log=nothing writes no records" setup=[OperationLogFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Treebars, Logging, Test

    reset_oplog!()
    HTMXObjects._clear_operation_polls!()
    route!(OpLogReadApp())
    previous = HTMXObjects.OPERATION_LOG[]
    try
        serve(; port=free_port(), async=true, access_log=nothing,
              operation_log=nothing)
        @test HTMXObjects.OPERATION_LOG[] === nothing
        terminate()
        logger = TestLogger()
        with_logger(logger) do
            url = poll_url(body_text(hx_get("/oplog_report?key=off1")))
            release!(:off1)
            @test contains(body_text(settle(url)), "report-off1")
        end
        @test isempty(operation_lines(logger))
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = previous
    end
end
