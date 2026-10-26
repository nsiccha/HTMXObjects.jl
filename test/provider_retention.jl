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
        release_retention!, hx_get, running, settle,
        MountProbe, mount_providers, prefixed_get

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

    # An external `@include` child: `arg` is a constructor argument, and `work`
    # reads only it, so its count shows whether requests share the child.
    @htmx struct RetentionMount
        arg::String = ""
        work() = (hit!(Symbol(:mount_, arg)); arg)
        @direct @get index() = h.p("arg=$(work()) prefix=$(__prefix__)")
    end

    # External children whose constructor arguments read request context, the
    # way an app serves its API docs behind a path-stripping proxy: `spec_url`
    # follows `X-Forwarded-Prefix`.
    @htmx struct RetainedApi
        @param name::String = "none"
        spec_url = __self__ / "openapi"
        @include openapi = OpenAPIRoutes(; root=RetainedApi,
                                          servers=[chopsuffix(spec_url, "/openapi")])
        @include docs = SwaggerRoutes(; spec_url)
        @include addressed = RetentionMount(; arg=spec_url)
        @include prefixed = RetentionMount(; arg=__prefix__)
        @include named = RetentionMount(; arg=name)
        @include constant = RetentionMount(; arg="constant")
    end

    @htmx struct MountProbe
        @include mounts = RetainedApi()
    end

    function mount_providers()
        retained = MountProbe()
        custom = RootProvider(; scope=:job, key=_ -> :mounts) do _RootT, _context
            retained
        end
        managed = RootProvider(; scope=:job, key=_ -> :mounts,
                               retention=RootRetention())
        (; custom, managed)
    end

    hx_get(target) = dispatch(:GET, target; headers=["HX-Request" => "true"])
    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    prefixed_get(target, prefix) = body_text(dispatch(:GET, target;
        headers=isempty(prefix) ? Pair{String,String}[] : ["X-Forwarded-Prefix" => prefix]))
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

# An external `@include` child whose constructor arguments read request context
# — the mount prefix through `__self__ / "…"` or `__prefix__`, or an `@param` —
# is built per request from those arguments, and a request that builds it alike
# keeps sharing the retained child's work (DynamicObjects `7c3852e`, snag
# `DynamicObjects/remount-reuses-a-77419def`). Earlier pins kept the first
# request's arguments for the life of the root: a viewer and document mounted
# behind two proxy prefixes served the first one's addresses (snag
# `retained-root-pr-a3e9ebb4`).
@testitem "provider-retained roots build external includes from each request's arguments" setup=[ProviderRetentionFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    for (label, provider) in pairs(mount_providers())
        reset_retention!()
        route!(MountProbe(); root_provider=provider)

        for prefix in ("", "/p/A", "/p/B", "")
            api = prefix * "/mounts"
            @test contains(prefixed_get("/mounts/docs", prefix),
                           "url: \"$api/openapi\"")
            @test contains(prefixed_get("/mounts/openapi", prefix),
                           "\"servers\":[{\"url\":\"$api\"}]")
            @test contains(prefixed_get("/mounts/addressed", prefix),
                           "arg=$api/openapi prefix=$api/addressed")
            @test contains(prefixed_get("/mounts/prefixed", prefix),
                           "arg=$api prefix=$api/prefixed")
            @test contains(prefixed_get("/mounts/constant", prefix),
                           "arg=constant prefix=$api/constant")
        end
        @test contains(prefixed_get("/mounts/named?name=a", ""), "arg=a")
        @test contains(prefixed_get("/mounts/named?name=b", ""), "arg=b")

        if label === :managed
            # The managed store realizes the children on its source at the first
            # (unprefixed) request; later requests that build a child alike share
            # its work, the others build their own.
            @test retention_runs(:mount_constant) == 1
            @test retention_runs(Symbol(:mount_, "/mounts/openapi")) == 1
            @test retention_runs(Symbol(:mount_, "/p/A/mounts/openapi")) == 1
        end
    end
    reset_retention!()
end

# `route!(app)` serves requests from `app`: every root built for a request takes
# `app`'s fixed fields and constructor overrides, whichever provider builds it
# (snag `route-drops-the-0fde2d8d`: the instance used to be dropped, and every
# root was built from the type's defaults).
@testmodule RouteInstanceFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export InstanceApp, FixedInstance, DEFAULT_DIR, fit_dirs, instance_get

    const DEFAULT_DIR = Ref("")
    # One subdirectory per fit, named after the directory's label.
    fit_dirs(labels...) = map(labels) do label
        dir = mktempdir()
        mkpath(joinpath(dir, "$label-fit"))
        dir
    end

    @htmx struct InstancePart
        dir::String = ""
        @direct @get index() = h.p("part dir=$dir")
    end

    @htmx struct InstanceApp
        dir::String = DEFAULT_DIR[]
        fits = sort!(readdir(dir))
        @options(fit) = fits
        @include part = InstancePart(; dir)
        @get index() = semantic_app(__self__; title="instance",
                                    select=entry -> entry.name === :show)
        "Show the fit"
        @direct @get show(; fit::String) = h.p("fit=$fit dir=$dir")
    end

    @htmx struct FixedInstance
        dir::String
        @direct @get index() = h.p("fixed dir=$dir")
    end

    function instance_get(target)
        response = dispatch(:GET, target; headers=["Accept" => "text/markdown"])
        (; response.status, body=String(HTMXObjects._message_body_bytes(response)))
    end
end

@testitem "route! builds every request root from the routed instance" setup=[RouteInstanceFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    default_dir, configured = fit_dirs("default", "configured")
    DEFAULT_DIR[] = default_dir
    # An explicit `RootProvider()` is the default; spelled out, it also replaces a
    # semantic store another item may have switched on for this type.
    providers = (; fresh=RootProvider(),
        managed=RootProvider(; scope=:job, key=_ -> :instance, retention=RootRetention()))
    for (label, provider) in pairs(providers)
        route!(InstanceApp(; dir=configured); prefix="instance", root_provider=provider)
        answer = instance_get("/instance/show?fit=configured-fit")
        @test answer.status == 200
        @test contains(answer.body, "dir=$configured")
        # The declared domain is the instance's directory, not the default one.
        @test instance_get("/instance/show?fit=default-fit").status == 400
        # A mounted child is built from the request root, so it sees the override.
        @test contains(instance_get("/instance/part").body, "part dir=$configured")
    end

    # A type with a required fixed field is routed from its instance; it used to
    # answer every request with a recorded 500 (no `FixedInstance(; __req__, …)`).
    route!(FixedInstance(configured); prefix="instance-fixed")
    answer = instance_get("/instance-fixed")
    @test answer.status == 200
    @test contains(answer.body, "fixed dir=$configured")
end

@testitem "route! of a bare instance still evaluates defaults per request" setup=[RouteInstanceFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    first_dir, second_dir = fit_dirs("first", "second")
    DEFAULT_DIR[] = first_dir
    route!(InstanceApp(); prefix="instance", root_provider=RootProvider())
    @test contains(instance_get("/instance/show?fit=first-fit").body, "dir=$first_dir")
    # Nothing was overridden, so each fresh root reads the default again.
    DEFAULT_DIR[] = second_dir
    @test contains(instance_get("/instance/show?fit=second-fit").body, "dir=$second_dir")
end

@testitem "the semantic store serves the instance route! was last given" setup=[RouteInstanceFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects

    default_dir, first_dir, second_dir = fit_dirs("default", "first", "second")
    DEFAULT_DIR[] = default_dir
    route!(InstanceApp(; dir=first_dir); prefix="instance")
    # Rendering the semantic surface switches on its managed store; the root it
    # retains carries the instance's directory.
    index = instance_get("/instance")
    @test index.status == 200
    @test contains(index.body, "Show the fit")
    @test HTMXObjects._is_semantic_root_provider(HTMXObjects._root_providers[InstanceApp])
    @test contains(instance_get("/instance/show?fit=first-fit").body, "dir=$first_dir")

    # Routing another instance keeps the store but drops the roots it built
    # from the earlier one.
    route!(InstanceApp(; dir=second_dir); prefix="instance")
    @test HTMXObjects._is_semantic_root_provider(HTMXObjects._root_providers[InstanceApp])
    @test contains(instance_get("/instance/show?fit=second-fit").body, "dir=$second_dir")
    @test instance_get("/instance/show?fit=first-fit").status == 400
end

# A fresh-per-request app can still keep one object across requests: hand it to
# `route!` as a constructor override or a fixed field. Every request root
# receives that same object, and the request-boundary `sync!` reaches it through
# the root's construction inputs, so a changed tracked file drops only what was
# derived from it while the rest of the root stays per request (snag
# `in-the-knowledge-9d9c3a5c`).
@testmodule RetainedObjectFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: TrackedFile
    import HTMXObjects: h

    export Rows, OverrideRowsApp, FixedRowsApp, rows_dir, rows_get, row_runs,
        reset_row_runs!

    const runs_lock = ReentrantLock()
    const runs = Dict{String,Int}()
    hit!(key) = lock(() -> (runs[key] = get(runs, key, 0) + 1), runs_lock)
    row_runs(key) = lock(() -> get(runs, key, 0), runs_lock)
    reset_row_runs!() = lock(() -> empty!(runs), runs_lock)

    @dynamicstruct struct Rows
        dir::String
        @struct row(name::String) = begin
            file = TrackedFile(joinpath(dir, name); read = path -> Base.read(path, String))
            html = (hit!(name); read(file))
        end
    end

    rows_html(rows) = join((rows.row(name).html for name in ("a", "b")), ",")

    # The default is never read: the routed instance overrides it.
    @htmx struct OverrideRowsApp
        rows = Rows(mktempdir())
        request = hit!("request")
        @direct @get index() = h.p("rows=$(rows_html(rows)) request=$request")
    end

    @htmx struct FixedRowsApp
        rows::Rows
        @direct @get index() = h.p("rows=$(rows_html(rows))")
    end

    function rows_dir()
        dir = mktempdir()
        write(joinpath(dir, "a"), "A1")
        write(joinpath(dir, "b"), "B1")
        dir
    end

    rows_get(target) = String(HTMXObjects._message_body_bytes(
        dispatch(:GET, target; headers=["HX-Request" => "true"])))
end

@testitem "an object handed to route! is shared by every request root and synced per request" setup=[RetainedObjectFixtures] tags=[:unit] begin
    using HTMXObjects

    reset_row_runs!()
    dir = rows_dir()
    route!(OverrideRowsApp(; rows=Rows(dir)); prefix="retained-override",
           root_provider=RootProvider())
    @test contains(rows_get("/retained-override"), "rows=A1,B1 request=1")
    @test contains(rows_get("/retained-override"), "rows=A1,B1 request=2")
    @test (row_runs("a"), row_runs("b")) == (1, 1)
    # A different size moves the tracked stamp at any timestamp granularity.
    write(joinpath(dir, "a"), "A2-changed")
    @test contains(rows_get("/retained-override"), "rows=A2-changed,B1 request=3")
    @test (row_runs("a"), row_runs("b")) == (2, 1)

    reset_row_runs!()
    dir = rows_dir()
    route!(FixedRowsApp(Rows(dir)); prefix="retained-fixed", root_provider=RootProvider())
    @test contains(rows_get("/retained-fixed"), "rows=A1,B1")
    @test contains(rows_get("/retained-fixed"), "rows=A1,B1")
    @test (row_runs("a"), row_runs("b")) == (1, 1)
    write(joinpath(dir, "b"), "B2-changed")
    @test contains(rows_get("/retained-fixed"), "rows=A1,B2-changed")
    @test (row_runs("a"), row_runs("b")) == (1, 2)
end
