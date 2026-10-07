using TestItemRunner

# A route's background operation starts on the pool of the request that
# started it, so a request served on `:interactive` (HTTP.jl 2, or
# `serve(; parallel=:interactive)`) still gets its answer while application
# compute saturates every `:default` thread. `@queued` declares heavy
# computation: it runs on `:default`, admitted through the job queue, however
# the request is answered.
@testmodule OperationPoolFixtures begin
    using HTMXObjects
    import HTMXObjects: h

    export PoolApp, PoolStreamApp, pool_reset!, pool_started, pool_of,
        pool_release!, on_request_pool, spin!

    const pool_lock = ReentrantLock()
    const pool_starts = Dict{Symbol,Symbol}()
    const pool_gates = Dict{Symbol,Base.Event}()

    function pool_reset!()
        lock(pool_lock) do
            empty!(pool_starts)
            empty!(pool_gates)
        end
        nothing
    end

    pool_started(key::Symbol) = lock(() -> haskey(pool_starts, key), pool_lock)
    pool_of(key::Symbol) = lock(() -> get(pool_starts, key, :none), pool_lock)
    pool_gate(key::Symbol) = lock(() -> get!(Base.Event, pool_gates, key), pool_lock)
    pool_release!(key::Symbol) = notify(pool_gate(key))

    # Record the threadpool the body runs on; a gated body then holds until the
    # test releases it, so its operation is answered by a poller.
    function pool_work(key::Symbol; gated::Bool=true)
        lock(() -> (pool_starts[key] = Threads.threadpool()), pool_lock)
        gated && wait(pool_gate(key))
        h.p("pool:$(key)")
    end

    @htmx struct PoolApp
        "Ordinary memoized read"
        @get plain_read(; n::Int=1) = pool_work(Symbol(:plain_read, n))
        "Ordinary fresh read"
        @fresh @get plain_fresh(; n::Int=1) = pool_work(Symbol(:plain_fresh, n))
        "Ordinary submission"
        @post plain_post(; n::Int=1) = pool_work(Symbol(:plain_post, n))
        "Ordinary preloaded read"
        @preload @get plain_preload(; n::Int=1) = pool_work(Symbol(:plain_preload, n))
        "Heavy memoized read"
        @queued @get heavy_read(; n::Int=1) = pool_work(Symbol(:heavy_read, n))
        "Heavy fresh read"
        @queued @fresh @get heavy_fresh(; n::Int=1) = pool_work(Symbol(:heavy_fresh, n))
        "Heavy direct read"
        @queued @direct @get heavy_direct(; n::Int=1) =
            pool_work(Symbol(:heavy_direct, n); gated=false)
    end

    @htmx struct PoolStreamApp
        @queued @ws stream() = "ws"
    end

    # Run `f` on a task of the pool HTTP.jl 2 handles requests on, when that
    # pool exists; return the pool it ran on and its result.
    function on_request_pool(f)
        run = () -> (Threads.threadpool(), f())
        Threads.nthreads(:interactive) > 0 ? fetch(Threads.@spawn(:interactive, run())) :
            run()
    end

    # A non-yielding busy loop: it holds its `:default` thread the way CPU-bound
    # application compute does. It allocates, so GC safepoints stay reachable,
    # and gives up after `deadline` so a failing test cannot hang the process.
    function spin!(stop::Threads.Atomic{Bool}, spinning::Threads.Atomic{Int};
            deadline::Real=60.0)
        Threads.atomic_add!(spinning, 1)
        until = time() + deadline
        acc = 0.0
        while !stop[] && time() < until
            acc += sum(rand(8))
        end
        acc
    end
end

@testitem "operations start on their request's pool; @queued computations on :default" setup=[FreshTransportFixtures, OperationPoolFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    pool_reset!()
    _clear_operation_polls!()
    route!(PoolApp())

    request_pool, bodies = on_request_pool() do
        Dict(:plain_read1 => body_text(hx_get("/plain_read?n=1")),
             :plain_fresh1 => body_text(hx_get("/plain_fresh?n=1")),
             :plain_post1 => body_text(hx_post("/plain_post", "n=1")),
             :heavy_read1 => body_text(hx_get("/heavy_read?n=1")),
             :heavy_fresh1 => body_text(hx_get("/heavy_fresh?n=1")))
    end
    preload = last(on_request_pool() do
        dispatch(:GET, "/plain_preload?n=1";
                 headers=["HX-Request" => "true", "HX-Preloaded" => "true"])
    end)

    # Every start path is still answered by its poller (the preload by 204).
    @test all(running, values(bodies))
    @test preload.status == 204
    for key in (keys(bodies)..., :plain_preload1)
        @test timedwait(() -> pool_started(key), 10.0; pollint=0.01) === :ok
    end
    # Ordinary operations — memoized, fresh, a mutation, a preload — run where
    # their request runs.
    @test pool_of(:plain_read1) === request_pool
    @test pool_of(:plain_fresh1) === request_pool
    @test pool_of(:plain_post1) === request_pool
    @test pool_of(:plain_preload1) === request_pool
    # Heavy ones run on `:default`, memoized or fresh.
    @test pool_of(:heavy_read1) === :default
    @test pool_of(:heavy_fresh1) === :default

    for key in keys(bodies)
        pool_release!(key)
    end
    for (key, body) in bodies
        @test contains(settle(poll_url(body)), "pool:$(key)")
    end

    # A `@queued` route answered inline (`@direct`, or a non-HTMX request to
    # any route) still computes on `:default`, waiting on the request's task.
    direct = last(on_request_pool(() -> body_text(hx_get("/heavy_direct?n=1"))))
    @test contains(direct, "pool:heavy_direct1") && !running(direct)
    @test pool_of(:heavy_direct1) === :default
    pool_release!(:heavy_read2)
    plain_request = last(on_request_pool(() -> body_text(plain(:GET, "/heavy_read?n=2"))))
    @test contains(plain_request, "pool:heavy_read2") && !running(plain_request)
    @test pool_of(:heavy_read2) === :default

    # refused: a stream route's body runs on its connection's own task for the
    # connection's lifetime, so `@queued` would silently place nothing
    # (dev §1: no silent no-ops).
    @test_throws ArgumentError route!(PoolStreamApp())
end

@testitem "an ordinary operation starts while app compute saturates :default" setup=[FreshTransportFixtures, OperationPoolFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    # Saturating every `:default` thread needs a driver on another pool, which
    # needs interactive threads (Julia ≥ 1.12 starts with one by default).
    if Threads.nthreads(:interactive) > 0
        pool_reset!()
        _clear_operation_polls!()
        route!(PoolApp())

        # `@test` records into the calling task's testset; the driver returns
        # what it saw instead.
        seen = fetch(Threads.@spawn :interactive begin
            stop = Threads.Atomic{Bool}(false)
            spinning = Threads.Atomic{Int}(0)
            n = Threads.nthreads(:default)
            spinners = [Threads.@spawn(:default, spin!(stop, spinning)) for _ in 1:n]
            try
                saturated = timedwait(() -> spinning[] == n, 10.0; pollint=0.01)
                ordinary = body_text(hx_get("/plain_read?n=2"))
                heavy = body_text(hx_get("/heavy_read?n=3"))
                started = timedwait(() -> pool_started(:plain_read2), 10.0;
                                    pollint=0.01)
                (; saturated, ordinary, heavy, started,
                   ordinary_pool=pool_of(:plain_read2),
                   # Positive control: the saturation is real, so the heavy
                   # computation is still waiting for a `:default` thread.
                   heavy_waiting=!pool_started(:heavy_read3),
                   still_saturated=!stop[] && spinning[] == n)
            finally
                stop[] = true
                foreach(wait, spinners)
            end
        end)

        @test seen.saturated === :ok
        @test running(seen.ordinary) && running(seen.heavy)
        @test seen.started === :ok
        @test seen.ordinary_pool === :interactive
        @test seen.heavy_waiting
        @test seen.still_saturated

        pool_release!(:plain_read2)
        pool_release!(:heavy_read3)
        @test contains(settle(poll_url(seen.ordinary)), "pool:plain_read2")
        @test contains(settle(poll_url(seen.heavy)), "pool:heavy_read3")
        @test pool_of(:heavy_read3) === :default
    end
end

@testitem "the job queue admits @queued computations, fresh ones included, and only those" setup=[FreshTransportFixtures, OperationPoolFixtures] tags=[:integration, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    pool_reset!()
    _clear_operation_polls!()
    route!(PoolApp())
    try
        configure_job_queue!(; max_running=1, abandon_after=60)

        # The first heavy computation takes the one slot; a heavy fresh
        # invocation waits behind it.
        first = body_text(hx_get("/heavy_read?n=4"))
        @test timedwait(() -> pool_started(:heavy_read4), 10.0; pollint=0.01) === :ok
        waiting = body_text(hx_get("/heavy_fresh?n=4"))
        @test running(first) && running(waiting)
        @test timedwait(() -> configure_job_queue!().queued == 1, 10.0;
                        pollint=0.01) === :ok
        @test !pool_started(:heavy_fresh4)

        # Ordinary work is never admitted through the queue: it starts at once
        # although the slot is taken.
        ordinary = body_text(hx_get("/plain_fresh?n=4"))
        @test timedwait(() -> pool_started(:plain_fresh4), 10.0; pollint=0.01) === :ok
        @test configure_job_queue!().queued == 1

        # Finishing the running computation admits the waiting one.
        pool_release!(:heavy_read4)
        @test contains(settle(poll_url(first)), "pool:heavy_read4")
        @test timedwait(() -> pool_started(:heavy_fresh4), 10.0; pollint=0.01) === :ok
        @test configure_job_queue!().queued == 0
        @test pool_of(:heavy_fresh4) === :default
        pool_release!(:heavy_fresh4)
        @test contains(settle(poll_url(waiting)), "pool:heavy_fresh4")
        pool_release!(:plain_fresh4)
        @test contains(settle(poll_url(ordinary)), "pool:plain_fresh4")

        # A queued fresh invocation nobody watches is abandoned, never run.
        blocker = body_text(hx_get("/heavy_read?n=5"))
        @test timedwait(() -> pool_started(:heavy_read5), 10.0; pollint=0.01) === :ok
        unwatched = body_text(hx_get("/heavy_fresh?n=5"))
        @test timedwait(() -> configure_job_queue!().queued == 1, 10.0;
                        pollint=0.01) === :ok
        configure_job_queue!(; abandon_after=0.2)
        @test timedwait(() -> configure_job_queue!().queued == 0, 10.0;
                        pollint=0.02) === :ok
        configure_job_queue!(; abandon_after=60)
        # Its poller answers the standard error article, and the job ledger
        # records why it failed.
        @test contains(settle(poll_url(unwatched)), "aria-invalid")
        @test !pool_started(:heavy_fresh5)
        abandoned = [r for r in runtime_jobs(runtime_tracker(); states=(:failed,))
                     if r.target == "/heavy_fresh?n=5"]
        @test !isempty(abandoned) && contains(last(abandoned).error, "abandoned")
        pool_release!(:heavy_read5)
        @test contains(settle(poll_url(blocker)), "pool:heavy_read5")
    finally
        configure_job_queue!(; max_running=0, abandon_after=60)
        lock(() -> foreach(notify, values(OperationPoolFixtures.pool_gates)),
             OperationPoolFixtures.pool_lock)
        _clear_operation_polls!()
    end
end
