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
        release_retention!, hx_get, running, settle

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
    # Only a key's first computation is released; any later one — a restart
    # that retention should have prevented — stays blocked until the reset, so
    # a poller can settle only on the original computation's result.
    gated(key::Symbol, value) = let n = hit!(key)
        wait(gate(n == 1 ? key : Symbol(key, :_restarted)))
        value
    end
    # Outside functions that receive the root: one reads nothing from it, the
    # other reads the current request through it.
    pass_self(_app, value) = value
    read_request(app, value) = (app.__req__; value)

    # Every route is `@direct`: these items measure property retention, so each
    # response must come from the route itself, never from the default `:auto`
    # operation poller a slow first compile can trigger. The poll routes are
    # hand-shaped pollers, whose documented shape is `@fresh @direct @get`.
    @htmx struct RetentionProbe
        root_value(k::Int) = (hit!(:root_value); k)
        root_slow(k::Int) = gated(:root_slow, k)
        root_self(k::Int) = (hit!(:root_self); pass_self(__self__, k))
        root_self_slow(k::Int) = pass_self(__self__, gated(:root_self_slow, k))
        root_self_req(k::Int) = (hit!(:root_self_req); read_request(__self__, k))
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
        @direct @get self_value(k::Int) =
            h.p("self=$(root_self(k)) req=$(root_self_req(k))")
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

# An inline nested child first realized during a request — every indexed
# `@struct child(k)`, and a declaration-level child a custom factory never
# realized — is realized on the retained source, so later requests share its
# memoized and in-flight work and a poller on it settles (DynamicObjects
# `822765e`, snag `DynamicObjects/remount-drops-ne-af0c7132`; earlier pins
# rebuilt it per request). The custom factory primes nothing, so its
# declaration-level `single` child is shared without `_prime_managed_root!`.
@testitem "provider-retained roots reuse inline-child work across requests" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, Treebars

    for (label, provider) in pairs(retention_providers())
        reset_retention!()
        route!(RetentionProbe(); root_provider=provider)

        @test all(_ -> contains(String(hx_get("/values/1").body),
                                "root=1 child=1 single=1"), 1:3)
        @test retention_runs(:child_value) == 1
        @test retention_runs(:single_value) == 1

        @test all(_ -> running(String(hx_get("/poll_child/1").body)), 1:3)
        @test timedwait(() -> retention_runs(:child_slow) >= 1, 10.0;
                        pollint=0.01) === :ok
        release_retention!(:child_slow)
        @test contains(settle("/poll_child/1"), "child-done:1")
        @test retention_runs(:child_slow) == 1
    end
    reset_retention!()
end

# A body that passes `__self__` to an outside function is judged by what that
# function reads through it (DynamicObjects `c0c742c`, snag
# `DynamicObjects/remount-opaque-s-2938c22c`): reading no request context, its
# memoized and in-flight work is shared across request remounts, so a poller on
# it settles; reading the request, it is recomputed per request. The
# `RootProvider` docs state this rule; keep them and this item together.
@testitem "provider-retained roots share opaque __self__ work that reads no request context" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, Treebars

    for (label, provider) in pairs(retention_providers())
        reset_retention!()
        route!(RetentionProbe(); root_provider=provider)

        @test all(_ -> contains(String(hx_get("/self_value/1").body),
                                "self=1 req=1"), 1:3)
        @test retention_runs(:root_self) == 1
        # At least once per request: never shared across requests.
        @test retention_runs(:root_self_req) >= 3

        # Requests while the computation is held in flight attach to it.
        @test all(_ -> running(String(hx_get("/poll_self/1").body)), 1:3)
        @test timedwait(() -> retention_runs(:root_self_slow) >= 1, 10.0;
                        pollint=0.01) === :ok
        release_retention!(:root_self_slow)
        @test contains(settle("/poll_self/1"), "self-done:1")
        @test retention_runs(:root_self_slow) == 1
    end
    reset_retention!()
end
