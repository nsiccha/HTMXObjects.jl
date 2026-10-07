using TestItemRunner

# `@queued` on a property that is not a route (DynamicObjects' marker): every
# computation of it is heavy work, admitted through the job queue whoever calls
# it — a plain call from a `Threads.@threads` iteration, a progress-threaded
# call, another property body, or a route. It runs on `:default`, and
# HTMXObjects records it as a job.
@testmodule QueuedPropertyFixtures begin
    using HTMXObjects, Treebars
    import HTMXObjects: h

    export QueuedProps, QueuedPropsApp, prop_reset!, prop_peak, prop_done,
        prop_gate!, prop_release!

    const prop_lock = ReentrantLock()
    const prop_counts = Dict(:running => 0, :peak => 0, :done => 0)
    const prop_gates = Dict{Int,Base.Event}()

    prop_reset!() = lock(prop_lock) do
        foreach(k -> prop_counts[k] = 0, collect(keys(prop_counts)))
        empty!(prop_gates)
    end
    prop_peak() = lock(() -> prop_counts[:peak], prop_lock)
    prop_done() = lock(() -> prop_counts[:done], prop_lock)
    prop_gate!(b) = lock(() -> get!(Base.Event, prop_gates, b), prop_lock)
    prop_release!(b) = notify(prop_gate!(b))

    # A heavy body: counts how many run at once, and records its threadpool.
    # A gated batch (`b < 0`) holds until the test releases it.
    function heavy!(b::Int, i::Int)
        lock(prop_lock) do
            prop_counts[:running] += 1
            prop_counts[:peak] = max(prop_counts[:peak], prop_counts[:running])
        end
        try
            b < 0 ? wait(prop_gate!(b)) : sleep(0.05)
        finally
            lock(prop_lock) do
                prop_counts[:running] -= 1
                prop_counts[:done] += 1
            end
        end
        (i, Threads.threadpool())
    end

    @htmx struct QueuedProps
        "Synthetic heavy item"
        @queued @progress item(b::Int, i::Int) = heavy!(b, i)
        "Unmarked item"
        free_item(b::Int, i::Int) = heavy!(b, i)
        "Fresh heavy item"
        @queued @fresh fresh_item(b::Int, i::Int) = heavy!(b, i)
        # A coordinator: a `Threads.@threads` loop whose iterations call the
        # queued item with a plain (blocking) call.
        @queued batch(b::Int, n::Int) = begin
            total = Threads.Atomic{Int}(0)
            Threads.@threads for i in 1:n
                Threads.atomic_add!(total, first(item(b, i)))
            end
            total[]
        end
        # A caller with a progress tree: its loop's item calls are threaded
        # through `__progress__`, so each item's node hangs under "Items".
        @progress listing(b::Int, n::Int) = begin
            Treebars.@progress "Items" for i in 1:n
                item(b, i)
            end
            n
        end
    end

    # The same shape behind a `@queued` route, as an app writes it.
    @htmx struct QueuedPropsApp
        "Synthetic heavy item"
        @queued @progress item(b::Int, i::Int) = heavy!(b, i)
        @progress batch_result(b::Int, n::Int) = begin
            total = Threads.Atomic{Int}(0)
            Treebars.@progress "Items" Threads.@threads for i in 1:n
                Threads.atomic_add!(total, first(item(b, i)))
            end
            total[]
        end
        "Synthetic batch"
        @queued @direct @get run(b::Int; n::Int=4) = h.p("total:$(batch_result(b, n))")
    end
end

@testitem "@queued properties run at most max_running at once, from any task" setup=[QueuedPropertyFixtures] tags=[:integration, :semantic] begin
    using HTMXObjects
    cap = 2
    try
        configure_job_queue!(; max_running=cap, abandon_after=60)

        # 3×cap concurrent plain calls of the queued property: at most `cap`
        # bodies run at once, each on `:default`.
        prop_reset!()
        w = QueuedProps()
        results = fetch.([Threads.@spawn w.item(1, i) for i in 1:3cap])
        @test first.(results) == collect(1:3cap)
        @test all(==(:default), last.(results))
        @test prop_done() == 3cap
        @test prop_peak() == cap
        settings = configure_job_queue!()
        @test settings.running == 0 && settings.queued == 0

        # Control: the same calls of the unmarked property all run at once.
        prop_reset!()
        fetch.([Threads.@spawn w.free_item(2, i) for i in 1:3cap])
        @test prop_peak() == 3cap

        # Callers with the same arguments share one computation and one slot,
        # and a cached value takes none.
        prop_reset!()
        shared = fetch.([Threads.@spawn w.item(3, 1) for _ in 1:3])
        @test allequal(shared) && prop_done() == 1
        @test w.item(3, 1) == first(shared) && prop_done() == 1

        # Each computation is recorded as a job named after the property.
        labels = [r.label for r in runtime_jobs(runtime_tracker();
                                                states=(:queued, :running, :done))]
        @test count(==("item"), labels) >= 3cap + 1

        # A fresh `@queued` property admits every call, each its own job.
        prop_reset!()
        results = fetch.([Threads.@spawn w.fresh_item(4, i) for i in 1:3cap])
        @test first.(results) == collect(1:3cap) && all(==(:default), last.(results))
        @test prop_peak() == cap && prop_done() == 3cap
        @test timedwait(() -> count(r -> r.label == "fresh_item",
                                    runtime_jobs(runtime_tracker(); states=(:done,))) == 3cap,
                        10.0; pollint=0.05) === :ok
    finally
        configure_job_queue!(; max_running=0)
    end
end

@testitem "a @queued coordinator gives its slot back while its threads wait" setup=[QueuedPropertyFixtures] tags=[:integration, :semantic] begin
    using HTMXObjects
    cap = 2
    try
        configure_job_queue!(; max_running=cap, abandon_after=60)
        prop_reset!()
        w = QueuedProps()
        # `cap` coordinators take every slot, then wait on 3×cap queued items
        # each from `Threads.@threads` iterations: without giving their slots
        # back this deadlocks.
        coordinators = [Threads.@spawn w.batch(b, 3cap) for b in 10:9+cap]
        settled = timedwait(() -> all(istaskdone, coordinators), 60.0; pollint=0.05)
        @test settled === :ok
        # Deadlocked: switch the queue off so the fetches below cannot hang.
        settled === :ok || configure_job_queue!(; max_running=0)
        @test fetch.(coordinators) == fill(sum(1:3cap), cap)
        @test prop_done() == cap * 3cap
        @test prop_peak() <= cap
        @test configure_job_queue!().running == 0
    finally
        configure_job_queue!(; max_running=0)
    end
end

@testitem "a caller waiting on a @queued property shows it queued" setup=[QueuedPropertyFixtures] tags=[:integration, :semantic] begin
    using HTMXObjects, Treebars
    try
        configure_job_queue!(; max_running=1, abandon_after=60)
        prop_reset!()
        w = QueuedProps()
        # A gated item holds the one slot; the caller's item waits behind it.
        blocker = Threads.@spawn w.item(-1, 1)
        @test timedwait(() -> configure_job_queue!().running == 1, 10.0;
                        pollint=0.01) === :ok
        caller = Threads.@spawn w.listing(20, 1)
        @test timedwait(() -> configure_job_queue!().queued == 1, 10.0;
                        pollint=0.01) === :ok
        tree = Treebars.render_text(w.__status__)
        @test contains(tree, "Items")
        @test contains(tree, "queued · #1")
        prop_release!(-1)
        @test fetch(caller) == 1
        @test !contains(Treebars.render_text(w.__status__), "queued · #")
        fetch(blocker)
    finally
        prop_release!(-1)
        configure_job_queue!(; max_running=0)
    end
end

@testitem "@queued routes waiting on @queued properties all complete" setup=[QueuedPropertyFixtures] tags=[:integration, :semantic] begin
    using HTMXObjects, HTTP
    cap = 2
    try
        configure_job_queue!(; max_running=cap, abandon_after=60)
        prop_reset!()
        route!(QueuedPropsApp())
        router = HTMXObjects.ROUTER
        # `cap` inline requests of the queued route take every slot; each
        # waits on its batch's queued items from `Threads.@threads`.
        responses = [Threads.@spawn router(HTTP.Request("GET", "/run/$(b)?n=$(3cap)"))
                     for b in 30:29+cap]
        settled = timedwait(() -> all(istaskdone, responses), 60.0; pollint=0.05)
        @test settled === :ok
        settled === :ok || configure_job_queue!(; max_running=0)
        @test all(r -> contains(String(fetch(r).body), "total:$(sum(1:3cap))"), responses)
        @test prop_done() == cap * 3cap
        @test prop_peak() <= cap
    finally
        configure_job_queue!(; max_running=0)
    end
end

@testitem "@queued needs an indexed property" tags=[:unit, :semantic] begin
    using HTMXObjects
    # refused: DynamicObjects admits only call-form computations through an
    # executor (its `@queued` marker), so a bare property could not queue.
    bare = :(@htmx struct BareQueued
        @queued total = 1
    end)
    @test_throws "call form" macroexpand(@__MODULE__, bare)
end
