using TestItemRunner

# `@interactive` starts a route's background operation on the `:interactive`
# threadpool. A request served there (`serve(; parallel=:interactive)`) then
# still gets its polled answer while application compute saturates every
# `:default` thread; unmarked routes keep starting on `:default`.
@testmodule OperationPoolFixtures begin
    using HTMXObjects
    import HTMXObjects: h

    export PoolApp, PoolDirectApp, PoolStreamApp, pool_reset!, pool_started,
        pool_of, pool_release!, spin!

    const pool_lock = ReentrantLock()
    const pool_starts = Dict{Symbol,Symbol}()
    const pool_gate = Ref(Base.Event())

    function pool_reset!()
        lock(pool_lock) do
            empty!(pool_starts)
            pool_gate[] = Base.Event()
        end
        nothing
    end

    pool_started(key::Symbol) = lock(() -> haskey(pool_starts, key), pool_lock)
    pool_of(key::Symbol) = lock(() -> get(pool_starts, key, :none), pool_lock)
    pool_release!() = notify(pool_gate[])

    # Record the threadpool the body runs on, then hold until the test releases
    # it, so every operation is answered by its poller.
    function pool_work(key::Symbol)
        lock(() -> (pool_starts[key] = Threads.threadpool()), pool_lock)
        wait(pool_gate[])
        h.p("pool:$(key)")
    end

    @htmx struct PoolApp
        "Default memoized read"
        @get default_read(; n::Int=1) = pool_work(Symbol(:default_read, n))
        "Interactive memoized read"
        @interactive @get interactive_read(; n::Int=1) =
            pool_work(Symbol(:interactive_read, n))
        "Interactive fresh read"
        @interactive @fresh @get interactive_fresh(; n::Int=1) =
            pool_work(Symbol(:interactive_fresh, n))
        "Interactive submission"
        @interactive @post interactive_post(; n::Int=1) =
            pool_work(Symbol(:interactive_post, n))
        "Interactive preloaded read"
        @interactive @preload @get interactive_preload(; n::Int=1) =
            pool_work(Symbol(:interactive_preload, n))
    end

    @htmx struct PoolDirectApp
        @interactive @direct @get both() = h.p("both")
    end

    @htmx struct PoolStreamApp
        @interactive @ws stream() = "ws"
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

@testitem "@interactive routes start their background operation on the :interactive pool" setup=[FreshTransportFixtures, OperationPoolFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    pool_reset!()
    _clear_operation_polls!()
    route!(PoolApp())

    # Julia runs an `:interactive` spawn on `:default` when it has no
    # interactive threads; the framework says so instead of hiding it.
    expected = Threads.nthreads(:interactive) > 0 ? :interactive : :default
    read = if expected === :default
        @test_logs (:warn, r"no :interactive threads") match_mode=:any hx_get(
            "/interactive_read?n=1")
    else
        hx_get("/interactive_read?n=1")
    end
    fresh = hx_get("/interactive_fresh?n=1")
    post = hx_post("/interactive_post", "n=1")
    control = hx_get("/default_read?n=1")
    preload = dispatch(:GET, "/interactive_preload?n=1";
                       headers=["HX-Request" => "true", "HX-Preloaded" => "true"])

    # Each start path: a memoized compute, a fresh invocation, a mutation and a
    # preload. Every one is still answered by its poller (the preload by 204).
    bodies = Dict(:interactive_read1 => body_text(read),
                  :interactive_fresh1 => body_text(fresh),
                  :interactive_post1 => body_text(post),
                  :default_read1 => body_text(control))
    @test all(running, values(bodies))
    @test preload.status == 204
    for key in (keys(bodies)..., :interactive_preload1)
        @test timedwait(() -> pool_started(key), 10.0; pollint=0.01) === :ok
    end
    @test pool_of(:interactive_read1) === expected
    @test pool_of(:interactive_fresh1) === expected
    @test pool_of(:interactive_post1) === expected
    @test pool_of(:interactive_preload1) === expected
    @test pool_of(:default_read1) === :default

    pool_release!()
    for (key, body) in bodies
        @test contains(settle(poll_url(body)), "pool:$(key)")
    end

    # refused: `@interactive` places a background operation, and a `@direct`
    # or WebSocket route never has one, so the marker would silently do
    # nothing (dev §1: no silent no-ops).
    @test_throws ArgumentError route!(PoolDirectApp())
    @test_throws ArgumentError route!(PoolStreamApp())
end

@testitem "an @interactive operation starts while app compute saturates :default" setup=[FreshTransportFixtures, OperationPoolFixtures] tags=[:unit, :semantic] begin
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
                marked = body_text(hx_get("/interactive_read?n=2"))
                unmarked = body_text(hx_get("/default_read?n=2"))
                started = timedwait(() -> pool_started(:interactive_read2), 10.0;
                                    pollint=0.01)
                (; saturated, marked, unmarked, started,
                   marked_pool=pool_of(:interactive_read2),
                   # Positive control: the saturation is real, so the unmarked
                   # operation is still waiting for a `:default` thread.
                   unmarked_waiting=!pool_started(:default_read2),
                   still_saturated=!stop[] && spinning[] == n)
            finally
                stop[] = true
                foreach(wait, spinners)
            end
        end)

        @test seen.saturated === :ok
        @test running(seen.marked) && running(seen.unmarked)
        @test seen.started === :ok
        @test seen.marked_pool === :interactive
        @test seen.unmarked_waiting
        @test seen.still_saturated

        pool_release!()
        @test contains(settle(poll_url(seen.marked)), "pool:interactive_read2")
        @test contains(settle(poll_url(seen.unmarked)), "pool:default_read2")
        @test pool_of(:default_read2) === :default
    end
end
