using TestItemRunner

# A scoped `RootProvider(scope=:job|:session)` retains one source root and hands
# every request a DynamicObjects remount of it. These items drive that shape end
# to end through `dispatch`: repeated requests must reuse memoized work and
# attach to in-flight work instead of starting it again — the property a
# hand-shaped `polling_fetchindex` poller relies on.
@testmodule ProviderRetentionFixtures begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: h

    export RetentionProbe, retention_providers, reset_retention!, retention_runs,
        release_retention!, hx_get, running, settle, settled_body

    const runs_lock = ReentrantLock()
    const runs = Dict{Symbol,Int}()
    const gates = Dict{Symbol,Base.Event}()

    function reset_retention!()
        lock(runs_lock) do
            foreach(notify, values(gates))
            empty!(runs)
            empty!(gates)
        end
        nothing
    end

    retention_runs(key::Symbol) = lock(() -> get(runs, key, 0), runs_lock)
    hit!(key::Symbol) = lock(() -> (runs[key] = get(runs, key, 0) + 1), runs_lock)
    gate(key::Symbol) = lock(() -> get!(Base.Event, gates, key), runs_lock)
    release_retention!(key::Symbol) = notify(gate(key))
    # Count the computation, then hold it in flight until the test releases it.
    gated(key::Symbol, value) = (hit!(key); wait(gate(key)); value)
    # An outside function that receives the root but reads nothing from it.
    pass_self(_app, value) = value

    # Every route is `@direct`: these items measure property retention, so each
    # response must come from the route itself, never from the default `:auto`
    # operation poller a slow first compile can trigger. The poll routes are
    # hand-shaped pollers, whose documented shape is `@fresh @direct @get`.
    @htmx struct RetentionProbe
        root_value(k::Int) = (hit!(:root_value); k)
        root_slow(k::Int) = gated(:root_slow, k)
        root_self(k::Int) = (hit!(:root_self); pass_self(__self__, k))
        root_self_slow(k::Int) = pass_self(__self__, gated(:root_self_slow, k))
        @struct child(k::Int) = begin
            value() = (hit!(:child_value); k)
            slow() = gated(:child_slow, k)
        end
        @struct single = begin
            value() = (hit!(:single_value); 1)
        end
        @direct @get values(k::Int) =
            h.p("root=$(root_value(k)) child=$(child(k).value()) single=$(single.value())")
        @fresh @direct @get poll_root(k::Int) =
            Treebars.polling_fetchindex(x -> h.p("root-done:$x"), root_slow, k)
        @fresh @direct @get poll_child(k::Int) =
            Treebars.polling_fetchindex(x -> h.p("child-done:$x"), child(k).slow)
        @direct @get self_value(k::Int) = h.p("self=$(root_self(k))")
        @fresh @direct @get poll_self(k::Int) =
            Treebars.polling_fetchindex(x -> h.p("self-done:$x"), root_self_slow, k)
    end

    # A custom factory that returns one retained root (remounted by
    # `_provide_root`), and the managed store.
    function retention_providers()
        retained = RetentionProbe()
        custom = RootProvider(; scope=:job, key=_ -> :probe) do _RootT, _context
            retained
        end
        managed = RootProvider(; scope=:job, key=_ -> :probe,
                               retention=RootRetention())
        (; custom, managed)
    end

    hx_get(target) = dispatch(:GET, target; headers=["HX-Request" => "true"])
    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")

    # A hand-shaped poller polls its own route; repeat it until it answers.
    function settled_body(target; attempts=400)
        for _ in 1:attempts
            body = body_text(hx_get(target))
            running(body) || return body
            sleep(0.025)
        end
        nothing
    end
    function settle(target)
        body = settled_body(target)
        body === nothing && error("poller never settled: $target")
        body
    end
end

@testitem "provider-retained roots reuse root-level indexed work across requests" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, Treebars

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    for (label, provider) in pairs(retention_providers())
        reset_retention!()
        route!(RetentionProbe(); root_provider=provider)

        bodies = [String(hx_get("/values/1").body) for _ in 1:3]
        @test all(body -> contains(body, "root=1 child=1 single=1"), bodies)
        @test retention_runs(:root_value) == 1

        # Three requests while the computation is held in flight attach to the
        # one retained computation.
        @test all(_ -> running(String(hx_get("/poll_root/1").body)), 1:3)
        @test timedwait(() -> retention_runs(:root_slow) >= 1, 10.0;
                        pollint=0.01) === :ok
        release_retention!(:root_slow)
        @test contains(settle("/poll_root/1"), "root-done:1")
        @test retention_runs(:root_slow) == 1

        # The managed store realizes declaration-level children on its source.
        label === :managed && @test retention_runs(:single_value) == 1
    end
    reset_retention!()
end

# DynamicObjects shares a nested child with a remount only when the child was
# realized on the retained source before that remount. A child first realized
# during a request — every indexed `@struct child(k)`, and a declaration-level
# child under a custom factory — is rebuilt per request, so its memoized and
# in-flight work restarts. Its poller then never settles: every poll rebuilds
# the child and starts a fresh computation, so it always reports a just-started
# node. Tracked upstream as snag `DynamicObjects/remount-drops-ne-af0c7132`; an
# Unexpected Pass here means it landed: promote these to `@test`.
@testitem "provider-retained roots reuse inline-child work across requests" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, Treebars

    for (label, provider) in pairs(retention_providers())
        reset_retention!()
        route!(RetentionProbe(); root_provider=provider)

        @test all(_ -> contains(String(hx_get("/values/1").body),
                                "root=1 child=1 single=1"), 1:3)
        @test_broken retention_runs(:child_value) == 1
        label === :custom && @test_broken retention_runs(:single_value) == 1

        @test all(_ -> running(String(hx_get("/poll_child/1").body)), 1:3)
        @test timedwait(() -> retention_runs(:child_slow) >= 1, 10.0;
                        pollint=0.01) === :ok
        release_retention!(:child_slow)
        settled = settled_body("/poll_child/1"; attempts=40)
        @test_broken settled !== nothing && contains(settled, "child-done:1")
        @test_broken retention_runs(:child_slow) == 1
    end
    reset_retention!()
end

# DynamicObjects' remount shares a property's work only when it can prove the
# property independent of the request context. A body that passes `__self__` to
# an outside function is opaque to that proof, so the property is recomputed per
# request even though `pass_self` reads nothing (documented on
# `DynamicObjects.remount`; snag `DynamicObjects/remount-opaque-s-2938c22c`).
# These assertions pin the boundary the `RootProvider` docs state: if
# DynamicObjects changes it, update those docs together with this item.
@testitem "provider-retained roots recompute properties that pass __self__ out" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, Treebars

    for (label, provider) in pairs(retention_providers())
        reset_retention!()
        route!(RetentionProbe(); root_provider=provider)

        @test all(_ -> contains(String(hx_get("/self_value/1").body), "self=1"), 1:3)
        @test retention_runs(:root_self) == 3

        # Each poll starts its own computation instead of attaching to the one
        # still in flight from the previous request.
        @test all(_ -> running(String(hx_get("/poll_self/1").body)), 1:3)
        @test timedwait(() -> retention_runs(:root_self_slow) >= 3, 10.0;
                        pollint=0.01) === :ok
        release_retention!(:root_self_slow)
        @test retention_runs(:root_self_slow) == 3
    end
    reset_retention!()
end
