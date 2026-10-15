using TestItemRunner

# A Markdown or `?error` response cannot carry a poller: the Markdown projection
# drops the poller's `hx-get` continuation, and `?error` filters a running
# poller to "(no errors)". Such a request used to poll whenever it carried
# `HX-Request: true` (or its root forced `:polling`), answering
# `Polling --- ### <label> — 0.1s so far` with no next poll URL, and a Markdown
# re-read of a poll URL healed into yet another poller (snag
# `markdown-negotia-5b39d614`). Each item below starts its request on its own
# task: a request answered inline is still waiting on the fixture's gate after
# the grace budget, where a poller would already have answered.
@testmodule InlineFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export InlineReadApp, InlinePollingApp, InlineMutationApp, reset_inline!,
        inline_runs, release_inline!, request_task, still_waiting, body_text,
        running, poll_url, poll_token, age_inline_operations!, hx, markdown

    const inline_lock = ReentrantLock()
    const inline_counts = Dict{Symbol,Int}()
    const InlineGates = Dict{Symbol,Base.Event}()

    function reset_inline!()
        lock(inline_lock) do
            empty!(inline_counts)
            for key in collect(keys(InlineGates))
                notify(InlineGates[key])   # free anything an earlier item left waiting
                InlineGates[key] = Base.Event()
            end
        end
        nothing
    end

    inline_runs(key::Symbol) = lock(() -> get(inline_counts, key, 0), inline_lock)
    hit!(key::Symbol) = lock(() -> (inline_counts[key] = get(inline_counts, key, 0) + 1), inline_lock)
    gate(key::Symbol) = lock(() -> get!(Base.Event, InlineGates, key), inline_lock)
    release_inline!(key::Symbol) = notify(gate(key))

    # Count the run, wait for the test to release it, then answer.
    function gated(key::AbstractString, answer)
        k = Symbol(key)
        run = hit!(k)
        wait(gate(k))
        answer(run)
    end

    @htmx struct InlineReadApp
        "Compute the slow listing"
        @get inline_listing(; key::String="listing") =
            gated(key, run -> h.p("listing-$key:$run"))
    end

    @htmx struct InlinePollingApp
        "Compute the forced listing"
        @get forced_listing(; key::String="forced") =
            gated(key, run -> h.p("forced-$key:$run"))
    end

    @htmx struct InlineMutationApp
        "Submit the slow order"
        @post inline_order(; key::String="order") =
            gated(key, run -> h.p("ordered-$key:$run"))
    end

    const hx = ["HX-Request" => "true"]
    const markdown = ["Accept" => "text/markdown"]

    request_task(method, target, headers; body="") =
        Threads.@spawn dispatch(method, target; headers, body)

    # Well past the 0.1 s grace budget: a request that would answer with a
    # poller has answered by now.
    function still_waiting(task)
        sleep(0.5)
        !istaskdone(task)
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

    # Pretend every retained operation started `seconds` earlier.
    function age_inline_operations!(seconds)
        for entry in values(HTMXObjects._operation_poll_snapshot())
            entry.created_at -= seconds
        end
        nothing
    end
end

@testitem "an HTMX request negotiating Markdown or ?error is answered inline" setup=[InlineFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    reset_inline!()
    HTMXObjects._clear_operation_polls!()
    route!(InlineReadApp())

    variants = (
        (key="plain", target="/inline_listing?key=plain&plain", headers=hx),
        (key="md", target="/inline_listing?key=md&markdown", headers=hx),
        (key="accept", target="/inline_listing?key=accept", headers=[hx; markdown]),
        (key="text", target="/inline_listing?key=text",
         headers=[hx; "Accept" => "text/plain"]),
    )
    for v in variants
        task = request_task(:GET, v.target, v.headers)
        @test timedwait(() -> inline_runs(Symbol(v.key)) >= 1, 10.0; pollint=0.01) === :ok
        @test still_waiting(task)
        release_inline!(Symbol(v.key))
        response = fetch(task)
        body = body_text(response)
        @test response.status == 200
        @test startswith(HTTP.header(response, "Content-Type"), "text/markdown")
        @test contains(body, "listing-$(v.key):1")
        @test !contains(body, "Polling")
        @test inline_runs(Symbol(v.key)) == 1
    end
    # Nothing was retained for a poller nobody could follow.
    @test isempty(HTMXObjects._operation_poll_snapshot())

    # `?error` answers once the operation finished, not "(no errors)" for a
    # poller that has not finished yet.
    task = request_task(:GET, "/inline_listing?key=errors&error", hx)
    @test timedwait(() -> inline_runs(:errors) >= 1, 10.0; pollint=0.01) === :ok
    @test still_waiting(task)
    release_inline!(:errors)
    @test body_text(fetch(task)) == "(no errors)"

    # Control: an HTML HTMX request of the same slow route still polls.
    html = body_text(dispatch(:GET, "/inline_listing?key=html";
                              headers=[hx; "Accept" => "text/html"]))
    @test running(html)
    release_inline!(:html)
end

@testitem "a Markdown read of a poll URL joins the operation it names" setup=[InlineFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

    reset_inline!()
    _clear_operation_polls!()
    route!(InlineReadApp())

    # The HTML transport retains the operation behind its poll URL.
    first_body = body_text(dispatch(:GET, "/inline_listing?key=join";
                                    headers=[hx; "Accept" => "text/html"]))
    @test running(first_body)
    url = poll_url(first_body)
    token = poll_token(url)
    @test haskey(_operation_poll_snapshot(), token)

    # Read as Markdown — `HX-Request` and all, as a command-line reader
    # copying the poller's request would — it waits for that operation
    # instead of answering a poller it cannot follow, and never recomputes.
    task = request_task(:GET, url, [hx; markdown])
    @test still_waiting(task)
    release_inline!(:join)
    response = fetch(task)
    body = body_text(response)
    @test startswith(HTTP.header(response, "Content-Type"), "text/markdown")
    @test contains(body, "listing-join:1")
    @test !contains(body, "Polling")
    @test inline_runs(:join) == 1
    @test parse(Float64, HTTP.header(response, "X-HTMXO-Operation-Age")) >= 0
    # The answer spends the token, as a terminal poll does.
    @test !haskey(_operation_poll_snapshot(), token)

    # A finished operation answers at once.
    done_url = poll_url(body_text(dispatch(:GET, "/inline_listing?key=done";
        headers=[hx; "Accept" => "text/html"])))
    entry = _operation_poll_snapshot()[poll_token(done_url)]
    release_inline!(:done)
    @test timedwait(() -> isready(entry.started), 10.0; pollint=0.01) === :ok
    @test contains(body_text(dispatch(:GET, done_url; headers=[hx; markdown])),
                   "listing-done:1")

    # With no operation to join (an unknown or spent token), the read is a
    # direct request of the same URL: it computes inline instead of healing
    # into a fresh poller.
    unknown = "/inline_listing?key=heal&__htmxo_poll=1&__htmxo_operation=" *
              repeat("ab", 32)
    task = request_task(:GET, unknown, [hx; markdown])
    @test timedwait(() -> inline_runs(:heal) >= 1, 10.0; pollint=0.01) === :ok
    @test still_waiting(task)
    release_inline!(:heal)
    healed = body_text(fetch(task))
    @test contains(healed, "listing-heal:1")
    @test !contains(healed, "Polling")
    @test isempty(_operation_poll_snapshot())
end

@testitem "a Markdown read of a stalled operation answers the stall" setup=[InlineFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

    reset_inline!()
    _clear_operation_polls!()
    route!(InlineReadApp())

    url = poll_url(body_text(dispatch(:GET, "/inline_listing?key=stalled";
        headers=[hx; "Accept" => "text/html"])))
    token = poll_token(url)
    # Past the default 600 s bound the wait ends at once (one grace budget),
    # answering the failure a poll would: recorded, with the route's status.
    age_inline_operations!(601)
    response = dispatch(:GET, url; headers=markdown)
    body = body_text(response)
    @test response.status == 504
    @test !isempty(HTTP.header(response, "X-HTMXO-Error-Id", ""))
    @test contains(body, "Operation stalled")
    @test !haskey(_operation_poll_snapshot(), token)
    @test inline_runs(:stalled) == 1
    release_inline!(:stalled)
end

@testitem "Markdown is answered inline under :polling, and by a mutation" setup=[InlineFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars

    reset_inline!()
    HTMXObjects._clear_operation_polls!()
    route!(InlinePollingApp(); operation_policy=OperationPolicy(:polling))
    route!(InlineMutationApp())

    # `:polling` forces a poller on an eligible request — but not on one whose
    # answer is Markdown, with or without `HX-Request`.
    for (key, headers) in (("bare", markdown), ("htmx", [hx; markdown]))
        task = request_task(:GET, "/forced_listing?key=$key", headers)
        @test timedwait(() -> inline_runs(Symbol(key)) >= 1, 10.0; pollint=0.01) === :ok
        @test still_waiting(task)
        release_inline!(Symbol(key))
        @test contains(body_text(fetch(task)), "forced-$key:1")
    end
    # Control: the same root still forces the poller on an HTML request.
    @test running(body_text(dispatch(:GET, "/forced_listing?key=page")))
    release_inline!(:page)

    # A swapping HTMX submission negotiating Markdown answers its own result.
    task = request_task(:POST, "/inline_order",
        [hx; markdown; "HTMXO-Swap" => "innerHTML";
         "Content-Type" => "application/x-www-form-urlencoded"];
        body="key=m1")
    @test timedwait(() -> inline_runs(:m1) >= 1, 10.0; pollint=0.01) === :ok
    @test still_waiting(task)
    release_inline!(:m1)
    @test contains(body_text(fetch(task)), "ordered-m1:1")
    @test inline_runs(:m1) == 1
end
