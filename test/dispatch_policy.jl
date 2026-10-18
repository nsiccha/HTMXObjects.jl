using TestItemRunner

# `dispatch(...; operation_policy=)` runs one in-process request under a policy
# of its own. Before it, a Julia caller timing a slow route of an `:auto` app
# got the poller back, and the only ways to get the finished fragment changed
# the answer (a Markdown read, `static=`) or the whole process (re-running
# `route!` with `:blocking`) — snag `dispatch-has-no-34fc6088`. Each item starts
# its request on its own task: a request answered inline is still waiting on
# the fixture's gate after the grace budget, where a poller has answered.
@testmodule DispatchPolicyFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export DispatchPolicyApp, DispatchPolicyPageApp, reset_dp!, dp_runs,
        release_dp!, dp_task, still_waiting, answered, body_text, running,
        poll_url, poll_token, hx

    const dp_lock = ReentrantLock()
    const dp_counts = Dict{Symbol,Int}()
    const dp_gates = Dict{Symbol,Base.Event}()

    function reset_dp!()
        lock(dp_lock) do
            empty!(dp_counts)
            for key in collect(keys(dp_gates))
                notify(dp_gates[key])   # free anything an earlier item left waiting
                dp_gates[key] = Base.Event()
            end
        end
        nothing
    end

    dp_runs(key::Symbol) = lock(() -> get(dp_counts, key, 0), dp_lock)
    hit!(key::Symbol) = lock(() -> (dp_counts[key] = get(dp_counts, key, 0) + 1), dp_lock)
    gate(key::Symbol) = lock(() -> get!(Base.Event, dp_gates, key), dp_lock)
    release_dp!(key::Symbol) = notify(gate(key))

    # Count the run, wait for the test to release it, then answer.
    function gated(key::AbstractString, answer)
        k = Symbol(key)
        run = hit!(k)
        wait(gate(k))
        answer(run)
    end

    @htmx struct DispatchPolicyApp
        "Compute the slow review"
        @get dp_listing(; key::String="listing") =
            gated(key, run -> h.p("listing-$key:$run"))
        "Submit the slow approval"
        @post dp_order(; key::String="order") =
            gated(key, run -> h.p("ordered-$key:$run"))
    end

    @htmx struct DispatchPolicyPageApp
        __page__(content) = htmx(h.main(content);
            htmx_version=nothing, hyperscript_version=nothing, overlay=false)
        "Compute the slow page"
        @get dp_page(; key::String="page") =
            gated(key, run -> h.p("page-$key:$run"))
    end

    const hx = ["HX-Request" => "true"]

    dp_task(method, target, headers; kwargs...) =
        Threads.@spawn dispatch(method, target; headers, kwargs...)

    # Well past the 0.1 s grace budget: a request that would answer with a
    # poller has answered by now.
    function still_waiting(task)
        sleep(0.5)
        !istaskdone(task)
    end

    # The request's response, once its gate is released; a request that never
    # answers fails the item instead of hanging the suite.
    function answered(task; timeout=30.0)
        timedwait(() -> istaskdone(task), timeout; pollint=0.01) === :ok ||
            error("the request did not answer within $timeout s")
        fetch(task)
    end

    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")

    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end

    poll_token(target) =
        only(match(r"__htmxo_operation=([0-9a-f]+)", target).captures)
end

@testitem "dispatch operation_policy=:blocking answers one request inline" setup=[DispatchPolicyFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot,
        _operation_policies, _registered_types

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    reset_dp!()
    _clear_operation_polls!()
    route!(DispatchPolicyApp())
    route!(DispatchPolicyPageApp())
    registered = _registered_types[DispatchPolicyApp]

    # The HTMX fragment request waits for the slow route...
    task = dp_task(:GET, "/dp_listing?key=block", hx; operation_policy=:blocking)
    @test timedwait(() -> dp_runs(:block) >= 1, 10.0; pollint=0.01) === :ok
    @test still_waiting(task)
    # ...while an ordinary request of the same app keeps its `:auto` poller.
    ordinary = body_text(dispatch(:GET, "/dp_listing?key=ordinary"; headers=hx))
    @test running(ordinary)
    @test !contains(ordinary, "listing-ordinary")
    @test !istaskdone(task)
    release_dp!(:block)
    response = answered(task)
    body = body_text(response)
    @test response.status == 200
    @test startswith(HTTP.header(response, "Content-Type"), "text/html")
    @test strip(body) == "<p>listing-block:1</p>"   # the bare fragment
    @test !contains(body, "treebar")
    @test dp_runs(:block) == 1
    # Only the ordinary request's poller was retained.
    @test length(_operation_poll_snapshot()) == 1
    release_dp!(:ordinary)

    # A browser page visit (no `HX-Request`) under the policy object answers
    # the composed page inline, where `:auto` answers the page shell with a
    # load-triggered placeholder.
    browser = ["Accept" => "text/html"]
    task = dp_task(:GET, "/dp_page?key=page", browser;
                   operation_policy=OperationPolicy(:blocking))
    @test still_waiting(task)
    release_dp!(:page)
    page = body_text(answered(task))
    @test startswith(page, "<!DOCTYPE html>")
    @test contains(page, "page-page:1")
    @test !contains(page, "hx-trigger=\"load")
    shell = body_text(dispatch(:GET, "/dp_page?key=shell"; headers=browser))
    @test contains(shell, "hx-trigger=\"load")
    @test !contains(shell, "page-shell")
    release_dp!(:shell)

    # A mutation submitted with a swap target runs inline too.
    task = dp_task(:POST, "/dp_order?key=post", [hx; "HTMXO-Swap" => "innerHTML"];
                   operation_policy=:blocking)
    @test still_waiting(task)
    release_dp!(:post)
    @test strip(body_text(answered(task))) == "<p>ordered-post:1</p>"

    # Nothing registered changed.
    @test _operation_policies[DispatchPolicyApp].mode === :auto
    @test _registered_types[DispatchPolicyApp] == registered
    _clear_operation_polls!()
end

@testitem "a blocking dispatch of a poll URL joins the operation it names" setup=[DispatchPolicyFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

    reset_dp!()
    _clear_operation_polls!()
    route!(DispatchPolicyApp())

    # A read: the ordinary request retains its operation behind a poll URL; the
    # blocking dispatch of that URL waits for it and never recomputes.
    url = poll_url(body_text(dispatch(:GET, "/dp_listing?key=join"; headers=hx)))
    token = poll_token(url)
    @test haskey(_operation_poll_snapshot(), token)
    task = dp_task(:GET, url, hx; operation_policy=:blocking)
    @test still_waiting(task)
    release_dp!(:join)
    response = answered(task)
    # Answered to its caller, not into a poller: no stop-polling 286.
    @test response.status == 200
    @test strip(body_text(response)) == "<p>listing-join:1</p>"
    @test dp_runs(:join) == 1
    @test !haskey(_operation_poll_snapshot(), token)

    # A mutation: its poll URL waits for the retained submission, which runs
    # once.
    submitted = body_text(dispatch(:POST, "/dp_order?key=m1";
                                   headers=[hx; "HTMXO-Swap" => "innerHTML"]))
    @test running(submitted)
    mutation_url = poll_url(submitted)
    @test contains(mutation_url, "__htmxo_verb=POST")
    task = dp_task(:GET, mutation_url, hx; operation_policy=:blocking)
    @test still_waiting(task)
    release_dp!(:m1)
    mutation = answered(task)
    @test mutation.status == 200
    @test contains(body_text(mutation), "ordered-m1:1")
    @test dp_runs(:m1) == 1

    # With no operation to join, the URL is answered like a direct request:
    # the bare fragment, not a terminal wrapped for a live poller.
    release_dp!(:heal)
    unknown = "/dp_listing?key=heal&__htmxo_poll=1&__htmxo_operation=" *
              repeat("ab", 32)
    healed_response = dispatch(:GET, unknown; headers=hx, operation_policy=:blocking)
    healed = body_text(healed_response)
    @test healed_response.status == 200
    @test strip(healed) == "<p>listing-heal:1</p>"
    @test !contains(healed, "treebar-terminal-content")
    # Control: the same poll URL without the override still answers a
    # terminal a live poller can retire.
    release_dp!(:heal2)
    unknown2 = "/dp_listing?key=heal2&__htmxo_poll=1&__htmxo_operation=" *
               repeat("cd", 32)
    @test contains(body_text(dispatch(:GET, unknown2; headers=hx)), "treebar")
    _clear_operation_polls!()
end

@testitem "dispatch operation_policy= is request-scoped in both directions and validated" setup=[DispatchPolicyFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_policies

    reset_dp!()
    _clear_operation_polls!()
    route!(DispatchPolicyApp())

    # `:polling` answers a non-HTMX request with a poller, where the app's
    # `:auto` answers that request inline.
    polled = body_text(dispatch(:GET, "/dp_listing?key=forced"; operation_policy=:polling))
    @test running(polled)
    task = dp_task(:GET, "/dp_listing?key=direct", [])
    @test timedwait(() -> dp_runs(:direct) >= 1, 10.0; pollint=0.01) === :ok
    @test still_waiting(task)
    release_dp!(:direct)
    @test contains(body_text(answered(task)), "listing-direct:1")
    release_dp!(:forced)

    # Values are checked before anything runs, with route!'s normalization.
    @test_throws ArgumentError dispatch(:GET, "/dp_listing?key=bad";
                                        operation_policy=:fast)
    @test_throws ArgumentError dispatch(:GET, "/dp_listing?key=bad";
                                        operation_policy="blocking")
    @test dp_runs(:bad) == 0
    @test_throws ArgumentError route!(DispatchPolicyApp(); operation_policy="blocking")
    @test _operation_policies[DispatchPolicyApp].mode === :auto
    _clear_operation_polls!()
end
