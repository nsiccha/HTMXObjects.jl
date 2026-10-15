using TestItemRunner

# Cache policy and response transport are independent. `@fresh` (and every
# mutation verb) recomputes per invocation; under the default `:auto` policy a
# slow invocation is still answered by the Treebars poller and resumed by its
# token. Mutation polls resume the one submission and never re-run it.
@testmodule FreshTransportFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export FreshReadApp, FreshPageApp, FreshMutationApp, SharedPathApp, RenamedPathApp,
        CoveredPathApp, FreshRetainedApp,
        FreshFailureApp, FreshDirectApp, FreshBrowserApp, FreshGates,
        reset_fresh!, fresh_runs, release_fresh!, hx_get, hx_post, plain,
        poll_url, poll_token, running, settle, settle_response, body_text

    const fresh_lock = ReentrantLock()
    const fresh_counts = Dict{Symbol,Int}()
    const FreshGates = Dict{Symbol,Base.Event}()

    function reset_fresh!()
        lock(fresh_lock) do
            empty!(fresh_counts)
            for key in collect(keys(FreshGates))
                FreshGates[key] = Base.Event()
            end
        end
        nothing
    end

    fresh_runs(key::Symbol) = lock(() -> get(fresh_counts, key, 0), fresh_lock)

    function fresh_hit!(key::Symbol)
        lock(fresh_lock) do
            fresh_counts[key] = get(fresh_counts, key, 0) + 1
        end
    end

    gate(key::Symbol) = lock(() -> get!(Base.Event, FreshGates, key), fresh_lock)

    release_fresh!(key::Symbol) = notify(gate(key))

    # Count the invocation, then wait for the test to release it.
    function gated(key::Symbol, label)
        run = fresh_hit!(key)
        wait(gate(key))
        h.p("$(label):$(run)")
    end

    @htmx struct FreshReadApp
        "Render the fresh report"
        @fresh @get fresh_report(; n::Int=1) = gated(:read, "report-$n")
        @fresh @get fresh_quick() = (fresh_hit!(:quick); h.p("quick"))
        @fresh @get fresh_retarget_read() = (wait(gate(:retarget_read));
            hx_response(h.p("read-retargeted"); retarget="#card"))
    end

    @htmx struct FreshPageApp
        __page__(body) = htmx(h.main(body); pico_version=nothing)
        "Render the fresh page"
        @fresh @get fresh_page() = gated(:page, "page")
    end

    @htmx struct FreshMutationApp
        "Submit the fresh order"
        @post fresh_order(; n::Int=1) = gated(:order, "order-$n")
        # Finalized answers that the routes did not declare.
        @post fresh_headers() = (wait(gate(:headers));
            hx_response(h.p("with-headers"); trigger="fresh-done"))
        @post fresh_nocontent() = (wait(gate(:nocontent)); HTTP.Response(204))
        @post fresh_conflict() = (wait(gate(:conflict));
            HTTP.Response(409, ["Content-Type" => "text/html"], "<p>conflict</p>"))
        @post fresh_redirect() = begin
            fresh_hit!(:redirect)
            wait(gate(:redirect))
            HTTP.Response(200, ["Content-Type" => "text/plain",
                                "HX-Redirect" => "/created"], "Created")
        end
        @direct @post direct_redirect() = (wait(gate(:direct_redirect));
            HTTP.Response(200, ["Content-Type" => "text/plain",
                                "HX-Redirect" => "/created"], "Created"))
        # Finalized answers whose headers send them away from the poller.
        @post fresh_retarget() = (wait(gate(:retarget));
            hx_response(h.p("retargeted"); retarget="#card", reswap="outerHTML",
                        trigger="card-changed"))
        @post fresh_location() = (wait(gate(:location));
            hx_response(""; location="/elsewhere"))
    end

    # A mutation path that also declares a GET: the GET route serves the
    # mutation's polls itself.
    @htmx struct SharedPathApp
        @get shared_thing() = (fresh_hit!(:shared_get); h.p("shared-get"))
        "Change the shared thing"
        @post shared_thing() = gated(:shared_post, "shared-post")
    end

    # The same path shape under different parameter names: HTTP.jl files
    # `/renamed_thing/{uid}` and `/renamed_thing/{path_uid}` under one router node.
    @htmx struct RenamedPathApp
        @get renamed_thing(uid::String) = (fresh_hit!(:renamed_get); h.p("renamed-get-$uid"))
        "Change the renamed thing"
        @post renamed_thing(path_uid::String="") =
            gated(:renamed_post, "renamed-post-$path_uid")
    end

    # A mutation path that a less specific GET route covers: `/covered/patch`
    # also matches `/covered/{uid}`.
    @htmx struct CoveredChild
        @get index(uid::String) = (fresh_hit!(:covered_get); h.p("covered-get-$uid"))
        "Patch the covered thing"
        @post patch() = gated(:covered_patch, "covered-patch")
    end

    @htmx struct CoveredPathApp
        @include covered = CoveredChild()
    end

    @htmx struct FreshRetainedApp
        retained_child = (fresh_hit!(:child); 41)
        "Recompute against the retained child"
        @fresh @get retained_report() = begin
            run = fresh_hit!(:retained)
            wait(gate(:retained))
            h.p("retained:$(retained_child + 1):$(run)")
        end
        "Record against the retained child"
        @post retained_record() = begin
            run = fresh_hit!(:retained_post)
            wait(gate(:retained_post))
            h.p("recorded:$(retained_child):$(run)")
        end
    end

    @htmx struct FreshFailureApp
        "Fail the fresh read"
        @fresh @get fresh_doomed() = (wait(gate(:doomed)); error("fresh read exploded"))
        "Fail the submission"
        @post post_doomed() = (wait(gate(:post_doomed)); error("submission exploded"))
    end

    @htmx struct DirectIndexChild
        @fresh @direct @get index() = (sleep(0.3); h.p("direct-index"))
    end

    @htmx struct FreshDirectApp
        @fresh @direct @get direct_report() = (sleep(0.3); h.p("direct-report"))
        @direct @post direct_order() = (sleep(0.3); h.p("direct-order"))
        @include direct_child = DirectIndexChild()
    end

    @htmx struct FreshBrowserApp
        "Render the slow fresh panel"
        @fresh @get browser_panel() = gated(:browser_read, "panel")
        "Render the captured grouping"
        @fresh @get browser_grouped(; group_by::String="None",
                review_scope::String="all", focus_year::Int=0) =
            gated(:browser_grouped, "grouped-$group_by-$review_scope-$focus_year")
        "Save the slow form"
        @post browser_save(; note::String="") = gated(:browser_post, "saved-$note")
        "Save the card"
        @post browser_card(; which::String="") =
            (wait(gate(:browser_card)); card_answer(which))
        @direct @post browser_card_direct(; which::String="") =
            (wait(gate(:browser_card)); card_answer(which))
    end

    card_answer(which) = hx_response(h.div(; id="card-$which")(h.p("card:$which"));
        retarget="#card-$which", reswap="outerHTML", trigger="card-changed",
        toast="Card saved")

    const hx = ["HX-Request" => "true"]
    const form = "Content-Type" => "application/x-www-form-urlencoded"

    hx_get(target; headers=Pair{String,String}[]) =
        dispatch(:GET, target; headers=[hx; headers])
    # `HTMXO-Swap` is what `mutation_poll_script` declares for a submission
    # whose response swaps into a target.
    hx_post(target, body=""; method=:POST, swap="innerHTML") =
        dispatch(method, target;
                 headers=[hx; form; (isnothing(swap) ? Pair{String,String}[] :
                                     ["HTMXO-Swap" => swap])],
                 body)
    plain(method, target, body="") =
        dispatch(method, target; headers=[form], body)

    running(body) = contains(body, "hx-trigger=\"every ")

    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end

    poll_token(target) =
        only(match(r"__htmxo_operation=([0-9a-f]+)", target).captures)

    # Poll until the operation answers its terminal.
    function settle_response(target)
        for _ in 1:200
            response = hx_get(target)
            running(body_text(response)) || return response
            sleep(0.025)
        end
        error("operation never settled: $target")
    end
    settle(target) = body_text(settle_response(target))
    body_text(response) = String(HTMXObjects._message_body_bytes(response))
end

@testitem "auto polls keep their captured query under inherited form values" setup=[FreshTransportFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars
        import HTMXObjects: _clear_operation_polls!, h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_fresh!()
        _clear_operation_polls!()
        route!(FreshBrowserApp())
        captured = "/browser_grouped?group_by=Counterparty&review_scope=all&focus_year=0"
        poller = body_text(hx_get(captured))
        @test running(poller)
        @test fresh_runs(:browser_grouped) == 1

        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('error', event => {
          fetch('/complete?status=' + encodeURIComponent('error: ' + event.message));
        });
        window.addEventListener('load', async () => {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(predicate, label) {
            for (let i = 0; i < 400; i++) {
              if (predicate()) return;
              await sleep(25);
            }
            throw new Error('timed out: ' + label);
          }
          try {
            // The live grouping changes after the operation was captured.
            // The auto poll must still fetch the Counterparty result.
            document.getElementById('live-group').value = 'None';
            await sleep(450);
            await fetch('/release');
            const result = document.getElementById('grouped-result');
            await until(() => result.textContent.includes('grouped-Counterparty-all-0') &&
                              !result.querySelector('.treebar-poller'), 'captured result');
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)));
          }
        });
        """))
        page = repr("text/html", htmx(h.main(
            h.form(; id="settings",
                    hx_vals="js:{review_scope:'changed',group_by:document.getElementById('live-group').value}",
                    hx_include="#included")(
                h.select(h.option("None"; value="None"),
                         h.option("Counterparty"; value="Counterparty", selected=true);
                         id="live-group", name="group_by"),
                h.input(; id="included", name="focus_year", value="999"),
                h.div(Raw(poller); id="grouped-result")),
            driver);
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false,
            overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            if path == "/release"
                release_fresh!(:browser_grouped)
                return HTTP.Response(204)
            end
            push!(requests, String(req.target))
            dispatch(req.method, String(req.target); headers=collect(req.headers))
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 30; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : "no receipt"
                    @test outcome == "/complete?status=passed"
                    outcome == "/complete?status=passed" ||
                        @info "Browser requests" outcome requests=join(requests, "\n")
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            polls = filter(target -> contains(target, "__htmxo_poll=1"), requests)
            @test !isempty(polls)
            for target in polls
                uri = HTTP.URI(target)
                fields = split(uri.query, '&')
                for key in ("group_by", "review_scope", "focus_year")
                    @test count(field -> startswith(field, key * "="), fields) == 1
                end
                params = HTTP.queryparams(uri)
                @test params["group_by"] == "Counterparty"
                @test params["review_scope"] == "all"
                @test params["focus_year"] == "0"
            end
            @test fresh_runs(:browser_grouped) == 1
        finally
            release_fresh!(:browser_grouped)
            close(server)
        end
    end
end

@testitem "slow fresh reads poll, resume their own invocation and never memoize" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshReadApp())

    # A fast fresh read answers inline within the grace budget — no poller —
    # and recomputes on every request.
    @test contains(String(hx_get("/fresh_quick").body), "quick")
    quick = String(hx_get("/fresh_quick").body)
    @test contains(quick, "<p>quick</p>") && !running(quick)
    @test fresh_runs(:quick) == 2

    # A slow fresh read is answered by a poller. Its body is still parked on
    # its gate, so any response at all proves the request was not held.
    resp1 = hx_get("/fresh_report?n=1")
    first_body = String(resp1.body)
    @test resp1.status == 200
    @test running(first_body)
    @test fresh_runs(:read) == 1
    # The documented route labels its progress exactly once.
    @test count("Render the fresh report", first_body) == 1

    # Identical arguments are a second invocation, with its own token.
    second_body = String(hx_get("/fresh_report?n=1").body)
    @test running(second_body)
    @test timedwait(() -> fresh_runs(:read) == 2, 10.0; pollint=0.01) === :ok
    first_url, second_url = poll_url(first_body), poll_url(second_body)
    @test poll_token(first_url) != poll_token(second_url)
    @test !contains(first_url, "__htmxo_verb")

    # Polls resume — they never start another invocation.
    @test running(String(hx_get(first_url).body))
    @test fresh_runs(:read) == 2

    release_fresh!(:read)
    first_done = settle(first_url)
    second_done = settle(second_url)
    @test contains(first_done, "<p>report-1:1</p>") ||
          contains(first_done, "<p>report-1:2</p>")
    @test contains(first_done, "treebar-terminal-content")
    @test first_done != second_done
    @test fresh_runs(:read) == 2

    # Nothing memoized the result: the next request recomputes inline.
    third = String(hx_get("/fresh_report?n=1").body)
    @test contains(third, "<p>report-1:3</p>")
    @test fresh_runs(:read) == 3

    # A read's lost token heals by recomputing — what a fresh GET would do.
    lost = replace(first_url, poll_token(first_url) => "0"^64)
    healed = String(hx_get(lost).body)
    running(healed) && (healed = settle(poll_url(healed)))
    @test contains(healed, "report-1:4")
    @test fresh_runs(:read) == 4
end

@testitem "a slow fresh page renders its shell and the load request joins the invocation" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshPageApp())

    page = String(dispatch(:GET, "/fresh_page"; headers=["Accept" => "text/html"]).body)
    @test contains(page, "<main>")
    @test contains(page, "htmxo-operation-load")
    attach = replace(only(match(r"hx-get=\"([^\"]*__htmxo_operation=[^\"]*)\"", page).captures),
                     "&amp;" => "&")
    @test fresh_runs(:page) == 1
    # The load-triggered request attaches to the running invocation.
    @test running(String(hx_get(attach).body))
    @test fresh_runs(:page) == 1
    release_fresh!(:page)
    body = String(hx_get(attach).body)
    running(body) && (body = settle(poll_url(body)))
    @test contains(body, "page:1")
    @test fresh_runs(:page) == 1
end

@testitem "slow mutations poll by token and never replay a submission" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot,
        _lookup_mutation_poll, _MUTATION_TERMINAL_TTL, _mutation_terminals

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshMutationApp())

    # Two identical HTMX submissions are two invocations, each answered by a
    # poller whose GET resumes carry the mutation verb.
    resp1 = hx_post("/fresh_order", "n=5")
    resp2 = hx_post("/fresh_order", "n=5")
    first_body, second_body = String(resp1.body), String(resp2.body)
    @test resp1.status == 200
    @test running(first_body) && running(second_body)
    @test count("Submit the fresh order", first_body) == 1
    @test timedwait(() -> fresh_runs(:order) == 2, 10.0; pollint=0.01) === :ok
    first_url, second_url = poll_url(first_body), poll_url(second_body)
    @test startswith(first_url, "/fresh_order?")
    @test contains(first_url, "__htmxo_verb=POST")
    # The submitted body never rides the poll URL (as an `n=` parameter;
    # a bare substring test would match the random token's `operation=5…`).
    @test !occursin(r"[?&]n=", first_url)
    @test poll_token(first_url) != poll_token(second_url)

    # Resuming never re-runs the body.
    @test running(String(hx_get(first_url).body))
    release_fresh!(:order)
    first_done = settle(first_url)
    second_done = settle(second_url)
    @test contains(first_done, "order-5:")
    @test contains(second_done, "order-5:")
    @test first_done != second_done
    @test fresh_runs(:order) == 2

    # The browser can miss the first terminal reply or have an overlapping
    # poll already in flight. Repeating that token replays the same terminal
    # without re-running the POST or replacing success with a 410 article.
    @test String(hx_get(first_url).body) == first_done
    @test String(hx_get(second_url).body) == second_done
    @test fresh_runs(:order) == 2
    @test isempty(filter(entry -> entry.signature.name === :fresh_order,
                         collect(values(_operation_poll_snapshot()))))

    # A foreign token still fails closed, with no replay of the submission.
    for target in (replace(first_url, poll_token(first_url) => "0"^64),)
        gone = hx_get(target)
        @test gone.status == 286
        gone_body = String(gone.body)
        @test contains(gone_body, "aria-invalid=\"true\"")
        @test contains(gone_body, "Result unavailable")
        @test contains(gone_body, "not repeated")
        unavailable = dispatch(:GET, target)
        @test unavailable.status == 410
    end
    @test fresh_runs(:order) == 2

    # Replayed terminals have a finite idle lifetime. After that bound, a
    # mutation still fails closed instead of repeating the side effect.
    first_terminal = _mutation_terminals[poll_token(first_url)]
    future = first_terminal.touched_at + _MUTATION_TERMINAL_TTL + 1
    @test _lookup_mutation_poll(poll_token(first_url),
        first_terminal.signature; now=future) === nothing
    @test dispatch(:GET, first_url).status == 410
    @test fresh_runs(:order) == 2

    # The mutation path's resume-only GET is not a GET route.
    not_allowed = dispatch(:GET, "/fresh_order")
    @test not_allowed.status == 405
    @test HTTP.header(not_allowed, "Allow") == "POST"
    malformed = "/fresh_order?__htmxo_poll=1&__htmxo_verb=TRACE"
    @test contains(String(hx_get(malformed).body), "Bad Request")
    @test dispatch(:GET, malformed).status == 400

    # A submission whose response swaps nowhere (`hx-swap="none"`), or whose
    # client does not declare its swap, cannot host a poller: it is answered
    # inline by its own response.
    for swap in ("none", nothing)
        reset_fresh!()
        task = Threads.@spawn hx_post("/fresh_order", "n=9"; swap)
        @test timedwait(() -> fresh_runs(:order) == 1, 10.0; pollint=0.01) === :ok
        sleep(0.3)
        @test !istaskdone(task)
        release_fresh!(:order)
        inline = body_text(fetch(task))
        @test contains(inline, "order-9:1") && !running(inline)
    end

    # A non-HTMX submission has no swap target for a poller: it is answered
    # inline by its own response.
    reset_fresh!()
    task = Threads.@spawn plain(:POST, "/fresh_order", "n=6")
    @test timedwait(() -> fresh_runs(:order) == 1, 10.0; pollint=0.01) === :ok
    sleep(0.3)
    @test !istaskdone(task)
    release_fresh!(:order)
    direct = fetch(task)
    @test direct.status == 200
    @test contains(String(direct.body), "order-6:1")
    @test !running(String(direct.body))
    @test isempty(filter(entry -> entry.signature.name === :fresh_order,
                         collect(values(_operation_poll_snapshot()))))
end

@testitem "a polled mutation's undeclared finalized answer keeps its headers" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshMutationApp())

    targets = Dict(key => poll_url(String(hx_post("/fresh_$(key)").body))
                   for key in (:headers, :nocontent, :conflict))
    foreach(release_fresh!, keys(targets))

    headers = settle_response(targets[:headers])
    @test headers.status == 286
    @test HTTP.header(headers, "HX-Trigger") == "fresh-done"
    body = body_text(headers)
    @test contains(body, "treebar-terminal-content")
    @test contains(body, "<p>with-headers</p>")
    @test !contains(body, "HTTP/1.1")
    replayed_headers = hx_get(targets[:headers])
    @test HTTP.header(replayed_headers, "HX-Trigger") == "fresh-done"
    @test body_text(replayed_headers) == body
    empty!(replayed_headers.headers)
    @test HTTP.header(hx_get(targets[:headers]), "HX-Trigger") == "fresh-done"

    # A 204 would not swap: the poller still receives its (empty) terminal,
    # with the stop-polling status that ends every poll.
    nocontent = settle_response(targets[:nocontent])
    @test nocontent.status == 286
    @test contains(body_text(nocontent), "treebar-terminal-content")

    # Any other status retires the poller with an error article.
    conflict = settle(targets[:conflict])
    @test contains(conflict, "aria-invalid=\"true\"")
    @test contains(conflict, "HTTP 409")
    @test contains(conflict, "<p>conflict</p>")
end

@testitem "a kept mutation terminal preserves finalized response headers and body" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshMutationApp();
        operation_policy=OperationPolicy(:auto; keep_terminal_tree=true))

    submitted = String(hx_post("/fresh_redirect").body)
    @test running(submitted)
    @test fresh_runs(:redirect) == 1
    target = poll_url(submitted)
    release_fresh!(:redirect)
    redirected = settle_response(target)
    redirected_body = body_text(redirected)
    @test redirected.status == 286
    @test HTTP.header(redirected, "HX-Redirect") == "/created"
    @test contains(redirected_body, "Created")
    @test contains(redirected_body, "treebar-terminal")
    @test !contains(redirected_body, "HTTP/1.1")
    @test fresh_runs(:redirect) == 1
    replayed_redirect = hx_get(target)
    @test HTTP.header(replayed_redirect, "HX-Redirect") == "/created"
    @test body_text(replayed_redirect) == redirected_body
    @test fresh_runs(:redirect) == 1

    targets = Dict(key => poll_url(String(hx_post("/fresh_$(key)").body))
                   for key in (:nocontent, :conflict))
    foreach(release_fresh!, keys(targets))
    nocontent = settle_response(targets[:nocontent])
    @test nocontent.status == 286
    @test contains(body_text(nocontent), "treebar-terminal-content")
    @test !contains(body_text(nocontent), "HTTP/1.1")
    conflict = settle_response(targets[:conflict])
    @test conflict.status == 286
    @test contains(body_text(conflict), "HTTP 409")
    @test contains(body_text(conflict), "<p>conflict</p>")
    @test !contains(body_text(conflict), "HTTP/1.1")

    # A direct route returns the same finalized answer without a poller or
    # retained tree; the kept terminal must retain its own transport benefits.
    direct_task = @async hx_post("/direct_redirect")
    @test timedwait(() -> istaskdone(direct_task), 0.2; pollint=0.01) === :timed_out
    release_fresh!(:direct_redirect)
    direct = fetch(direct_task)
    @test direct.status == 200
    @test HTTP.header(direct, "HX-Redirect") == "/created"
    @test body_text(direct) == "Created"
    @test !contains(body_text(direct), "treebar-terminal")
    @test redirected_body != body_text(direct)
end

# `HX-Retarget`/`HX-Reswap`/`HX-Reselect` move a poll terminal away from the
# poller and `HX-Location` swaps nothing, so the poller and its `every` trigger
# would stay and poll the spent token forever (snag auto-poller-endl-28fd6ff6).
# Such a terminal answers htmx's stop-polling status 286 with its headers; the
# browser side is the "retarget headers apply like a direct answer" item.
@testitem "a poll terminal its headers send elsewhere stops polling with 286" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    for keep_terminal_tree in (false, true)
        reset_fresh!()
        _clear_operation_polls!()
        route!(FreshMutationApp();
            operation_policy=OperationPolicy(:auto; keep_terminal_tree))
        targets = Dict(key => poll_url(String(hx_post("/fresh_$(key)").body))
                       for key in (:retarget, :location, :headers))
        foreach(release_fresh!, keys(targets))

        retargeted = settle_response(targets[:retarget])
        @test retargeted.status == 286
        @test HTTP.header(retargeted, "HX-Retarget") == "#card"
        @test HTTP.header(retargeted, "HX-Reswap") == "outerHTML"
        @test HTTP.header(retargeted, "HX-Trigger") == "card-changed"
        body = body_text(retargeted)
        # The bare terminal, whatever the tree policy: the answer leaves the
        # poller, so no kept tree can stand in its place.
        @test contains(body, "data-htmxo-auto-terminal")
        @test contains(body, "<p>retargeted</p>")
        @test !contains(body, "class=\"treebar-terminal\"")
        replayed = hx_get(targets[:retarget])
        @test replayed.status == 286
        @test body_text(replayed) == body

        located = settle_response(targets[:location])
        @test located.status == 286
        @test HTTP.header(located, "HX-Location") == "/elsewhere"

        # Headers that leave the swap alone end the poll the same way.
        @test settle_response(targets[:headers]).status == 286
    end

    route!(FreshReadApp())
    read = poll_url(String(hx_get("/fresh_retarget_read").body))
    release_fresh!(:retarget_read)
    answered = settle_response(read)
    @test answered.status == 286
    @test HTTP.header(answered, "HX-Retarget") == "#card"
    @test contains(body_text(answered), "<p>read-retargeted</p>")
end

@testitem "a mutation path's own GET route serves its polls" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(SharedPathApp())

    @test contains(String(hx_get("/shared_thing").body), "shared-get")
    @test fresh_runs(:shared_get) == 1

    submitted = String(hx_post("/shared_thing").body)
    @test running(submitted)
    target = poll_url(submitted)
    @test contains(target, "__htmxo_verb=POST")
    @test running(String(hx_get(target).body))
    # The poll resumed the submission; it did not run the GET route.
    @test fresh_runs(:shared_get) == 1
    release_fresh!(:shared_post)
    @test contains(settle(target), "shared-post:1")
    @test fresh_runs(:shared_post) == 1
    @test fresh_runs(:shared_get) == 1
    # A lost mutation token never falls back to the GET route.
    lost = String(hx_get(replace(target, poll_token(target) => "0"^64)).body)
    @test contains(lost, "Result unavailable")
    @test fresh_runs(:shared_get) == 1
end

@testitem "a GET route under other parameter names still serves its path" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars, Logging, Test
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    # No resume-only GET replaces the declared GET at the shared router node.
    logs, _ = Test.collect_test_logs(min_level=Logging.Warn) do
        route!(RenamedPathApp())
    end
    @test !any(log -> contains(string(log.message), "replacing existing registered route"), logs)

    @test contains(String(hx_get("/renamed_thing/abc").body), "renamed-get-abc")
    @test fresh_runs(:renamed_get) == 1

    submitted = String(hx_post("/renamed_thing/abc").body)
    @test running(submitted)
    target = poll_url(submitted)
    @test contains(target, "__htmxo_verb=POST")
    # The declared GET route resumes the submission without running itself.
    @test running(String(hx_get(target).body))
    @test fresh_runs(:renamed_get) == 1
    release_fresh!(:renamed_post)
    @test contains(settle(target), "renamed-post-abc:1")
    @test fresh_runs(:renamed_post) == 1
    @test fresh_runs(:renamed_get) == 1

    # The shortened mutation path `/renamed_thing` declares no GET.
    not_allowed = dispatch(:GET, "/renamed_thing")
    @test not_allowed.status == 405
    @test HTTP.header(not_allowed, "Allow") == "POST"
end

@testitem "a mutation path's resume-only GET leaves plain GETs to the route covering it" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(CoveredPathApp())

    # A plain GET of the mutation path is the covering GET route's request.
    @test contains(String(hx_get("/covered/abc").body), "covered-get-abc")
    covered = dispatch(:GET, "/covered/patch")
    @test covered.status == 200
    @test contains(body_text(covered), "covered-get-patch")
    @test fresh_runs(:covered_get) == 2

    # The mutation's polls still resume the submission, not the covering route.
    submitted = String(hx_post("/covered/patch").body)
    @test running(submitted)
    target = poll_url(submitted)
    @test startswith(target, "/covered/patch?")
    @test contains(target, "__htmxo_verb=POST")
    @test running(String(hx_get(target).body))
    release_fresh!(:covered_patch)
    @test contains(settle(target), "covered-patch:1")
    @test fresh_runs(:covered_patch) == 1
    @test fresh_runs(:covered_get) == 2
    lost = String(hx_get(replace(target, poll_token(target) => "0"^64)).body)
    @test contains(lost, "Result unavailable")
    @test fresh_runs(:covered_get) == 2
end

@testitem "fresh invocations on a retained root leave its caches alone" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    provider = RootProvider(scope=:session, key=_req -> "fresh-retained",
                            retention=RootRetention(max_entries=1))
    route!(FreshRetainedApp(); root_provider=provider)

    for (route, key, verb) in (("/retained_report", :retained, :GET),
                               ("/retained_record", :retained_post, :POST))
        bodies = [String((verb === :GET ? hx_get(route) : hx_post(route)).body)
                  for _ in 1:2]
        @test all(running, bodies)
        @test timedwait(() -> fresh_runs(key) == 2, 10.0; pollint=0.01) === :ok
        release_fresh!(key)
        done = [settle(poll_url(body)) for body in bodies]
        @test done[1] != done[2]
        @test fresh_runs(key) == 2
    end
    # Every invocation recomputed its own body, while the retained root's
    # memoized child computed once for all of them.
    @test fresh_runs(:child) == 1
    again = String(hx_get("/retained_report").body)
    @test contains(again, "retained:42:3")
    @test fresh_runs(:child) == 1
end

@testitem "failed fresh invocations surface through their poller" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshFailureApp())

    read_body = String(hx_get("/fresh_doomed").body)
    post_body = String(hx_post("/post_doomed").body)
    @test running(read_body) && running(post_body)
    release_fresh!(:doomed)
    release_fresh!(:post_doomed)
    read_done = settle(poll_url(read_body))
    post_done = settle(poll_url(post_body))
    @test contains(read_done, "aria-invalid")
    @test contains(post_done, "aria-invalid")
    @test !contains(read_done, "treebar-terminal-content\" data-htmxo-auto-terminal")
end

# htmx cancels polling on the element that sent a poll when the answer has
# status 286. Every answer that ends a poll carries it, not only the swap the
# live poller selects: a morph can leave the poll timer on an element that is
# no longer the poller, and nothing swapped into it would stop it
# (snag mutation-poller-4f9123b0).
@testitem "every answer that ends an operation poll stops polling with 286" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_fresh!()
    _clear_operation_polls!()
    route!(FreshReadApp())
    route!(FreshMutationApp())
    route!(FreshFailureApp())

    # A running answer keeps the poller polling; the result ends it.
    read_url = poll_url(String(hx_get("/fresh_report?n=7").body))
    order_url = poll_url(String(hx_post("/fresh_order", "n=7").body))
    for target in (read_url, order_url)
        still = hx_get(target)
        @test still.status == 200
        @test running(body_text(still))
    end
    release_fresh!(:read)
    release_fresh!(:order)
    @test settle_response(read_url).status == 286
    order_done = settle_response(order_url)
    @test order_done.status == 286
    @test contains(body_text(order_done), "order-7:1")
    # A replayed mutation terminal ends a poll too.
    @test hx_get(order_url).status == 286

    # Failures end the poll: the operation's own failure, an unavailable
    # token, a malformed poll.
    doomed_url = poll_url(String(hx_post("/post_doomed").body))
    release_fresh!(:post_doomed)
    failed = settle_response(doomed_url)
    @test failed.status == 286
    @test contains(body_text(failed), "aria-invalid")
    gone = hx_get(replace(order_url, poll_token(order_url) => "0"^64))
    @test gone.status == 286
    @test contains(body_text(gone), "Result unavailable")
    @test hx_get("/fresh_order?__htmxo_poll=1&__htmxo_verb=TRACE").status == 286

    # Only an HTMX poll is a poller: other requests keep their status.
    @test plain(:GET, replace(order_url, poll_token(order_url) => "0"^64)).status == 410
    @test hx_get("/fresh_quick").status == 200
    @test fresh_runs(:order) == 1
end

@testitem "@direct and fast fresh routes answer inline" setup=[FreshTransportFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars

    route!(FreshDirectApp())
    for _ in 1:2   # the first round compiles
        report = String(hx_get("/direct_report").body)
        order = String(hx_post("/direct_order").body)
        # `:index` collapses under a mount exactly as without the marker.
        child = String(hx_get("/direct_child").body)
        @test contains(report, "direct-report") && !running(report)
        @test contains(order, "direct-order") && !running(order)
        @test contains(child, "direct-index") && !running(child)
    end
    descriptor = HTMXObjects._property_descriptor(FreshDirectApp, :direct_report, :GET)
    @test descriptor.semantics.fresh
end

@testitem "slow fresh reads and submissions settle through a real browser" setup=[FreshTransportFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars
        import HTMXObjects: _clear_operation_polls!, h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_fresh!()
        _clear_operation_polls!()
        route!(FreshBrowserApp())
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent('error: ' + event.message));
        });
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(predicate, label) {
            for (let i = 0; i < 400; i++) {
              if (predicate()) return;
              await sleep(25);
            }
            throw new Error('timed out: ' + label);
          }
          const panel = document.getElementById('panel');
          const result = document.getElementById('result');
          try {
            htmx.ajax('GET', '/browser_panel', {target: '#panel', swap: 'innerHTML'});
            await until(() => panel.querySelector('.treebar-poller'), 'panel poller');
            htmx.trigger(document.getElementById('save-form'), 'submit');
            await until(() => result.querySelector('.treebar-poller'), 'save poller');
            // A swap-less submission cannot host a poller: it is answered
            // inline, so its after-request hook sees the real answer.
            htmx.trigger(document.getElementById('quiet-form'), 'submit');
            await sleep(300);
            if (document.body.dataset.quietDone) throw new Error('quiet POST answered early');
            await fetch('/release');
            await until(() => document.body.dataset.quietDone === 'yes', 'quiet answer');
            await until(() => panel.textContent.includes('panel:1') &&
                              !panel.querySelector('.treebar-poller'), 'panel result');
            await until(() => result.textContent.includes('saved-hello:1') &&
                              !result.querySelector('.treebar-poller'), 'save result');
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)) +
                  '&panel=' + encodeURIComponent(panel.innerHTML) +
                  '&result=' + encodeURIComponent(result.innerHTML));
          }
        });
        """))
        page = repr("text/html", htmx(h.main(
                h.div(; id="panel"),
                h.form(; id="save-form", hx_post="/browser_save",
                       hx_target="#result", hx_swap="innerHTML")(
                    h.input(; type="hidden", name="note", value="hello")),
                h.form(; id="quiet-form", hx_post="/browser_save", hx_swap="none",
                       hx_on__after_request="document.body.dataset.quietDone = event.detail.xhr.responseText.includes('saved-quiet') ? 'yes' : 'early'")(
                    h.input(; type="hidden", name="note", value="quiet")),
                h.div(; id="result"),
                driver);
                assets="/test-assets", sse_version=nothing, ws_version=nothing,
                preload_version=nothing, hyperscript_version=nothing,
                pico_version=nothing, feedback=false, compose=false,
                overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" &&
                return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            if path == "/release"
                release_fresh!(:browser_read)
                release_fresh!(:browser_post)
                return HTTP.Response(204)
            end
            push!(requests, string(req.method, " ", req.target, " swap=",
                                   HTTP.header(req, "HTMXO-Swap", "")))
            dispatch(req.method, String(req.target);
                headers=collect(req.headers),
                body=HTMXObjects._request_body_bytes(req))
        end
        try
            # Compile the poller paths before the browser's clock starts.
            warm = String(hx_get("/browser_panel").body)
            warm_post = String(hx_post("/browser_save", "note=warm").body)
            release_fresh!(:browser_read)
            release_fresh!(:browser_post)
            settle(poll_url(warm))
            settle(poll_url(warm_post))
            reset_fresh!()
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : "no receipt"
                    @test outcome == "/complete?status=passed"
                    outcome == "/complete?status=passed" ||
                        @info "Browser requests" outcome requests=join(requests, "\n")
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            # One submission, one execution: the browser's polls resumed it.
            @test fresh_runs(:browser_post) == 2
            @test fresh_runs(:browser_read) == 1
            posts = filter(r -> startswith(r, "POST /browser_save"), requests)
            @test length(posts) == 2
            @test count(r -> endswith(r, "swap=innerHTML"), posts) == 1
            @test count(r -> endswith(r, "swap=none"), posts) == 1
            @test any(r -> startswith(r, "GET /browser_save?") &&
                           contains(r, "__htmxo_verb=POST"), requests)
        finally
            release_fresh!(:browser_read)
            release_fresh!(:browser_post)
            close(server)
        end
    end
end

# The browser half of the 286 item above: a slow answer whose headers retarget
# it must end exactly as its `@direct` twin does. Each pair submits into
# `#content-<which>` and answers into `#card-<which>`, once with the card
# outside the submission's target and once inside it (the poller displaces the
# card there, so it has to come back before the retarget resolves).
@testitem "retarget headers on a poll terminal apply like a direct answer" setup=[FreshTransportFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars
        import HTMXObjects: _clear_operation_polls!, h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_fresh!()
        _clear_operation_polls!()
        route!(FreshBrowserApp())
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        receipt = Channel{String}(1)
        requests = Pair{String,Int}[]
        driver = h.script(Raw(raw"""
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent('error: ' + event.message));
        });
        var changed = 0;
        document.body.addEventListener('card-changed', function() { changed++; });
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          async function until(predicate, label) {
            for (let i = 0; i < 400; i++) {
              if (predicate()) return;
              await sleep(25);
            }
            throw new Error('timed out: ' + label);
          }
          const pairs = [['polled', 'direct'], ['polled-in', 'direct-in']];
          // Settled section markup, with the variant's name taken out.
          const settled = which => {
            const copy = document.getElementById('section-' + which).cloneNode(true);
            copy.querySelector('form').remove();
            return copy.innerHTML.split(which).join('X').replace(/ class=""/g, '');
          };
          try {
            ['polled', 'polled-in', 'direct', 'direct-in'].forEach(which =>
              htmx.trigger(document.getElementById('form-' + which), 'submit'));
            await until(() => ['polled', 'polled-in'].every(which =>
              document.querySelector('#content-' + which + ' .treebar-poller')), 'pollers');
            await fetch('/release');
            await until(() => ['polled', 'polled-in', 'direct', 'direct-in'].every(which =>
              (document.getElementById('card-' + which) || {}).textContent === 'card:' + which),
              'cards');
            await sleep(1000);   // no further poll may change anything
            const toasts = document.querySelectorAll('.htmxo-toast').length;
            for (const [polled, direct] of pairs) {
              if (settled(polled) !== settled(direct)) {
                throw new Error(polled + ' differs: ' + settled(polled) + ' vs ' + settled(direct));
              }
            }
            if (document.querySelector('.treebar-poller')) throw new Error('poller left behind');
            if (changed !== 4) throw new Error('card-changed fired ' + changed + ' times');
            if (toasts !== 4) throw new Error(toasts + ' toasts');
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)));
          }
        });
        """))
        section(which; inside) = h.section(; id="section-$which")(
            h.form(; id="form-$which",
                   hx_post=(startswith(which, "direct") ? "/browser_card_direct" : "/browser_card"),
                   hx_target="#content-$which")(
                h.input(; type="hidden", name="which", value=which)),
            inside ?
                h.div(; id="content-$which")(h.div(; id="card-$which")(h.p("old"))) :
                h.div(h.div(; id="content-$which")(h.p("content")),
                      h.div(; id="card-$which")(h.p("old"))))
        page = repr("text/html", htmx(h.main(
                h.div(; hx_vals="{\"ctx\":\"1\"}")(
                    section("polled"; inside=false), section("direct"; inside=false),
                    section("polled-in"; inside=true), section("direct-in"; inside=true)),
                driver);
                assets="/test-assets", sse_version=nothing, ws_version=nothing,
                preload_version=nothing, hyperscript_version=nothing,
                pico_version=nothing, feedback=false, compose=false,
                overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" &&
                return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, HTTP.unescapeuri(String(req.target)))
                return HTTP.Response(204)
            end
            if path == "/release"
                release_fresh!(:browser_card)
                return HTTP.Response(204)
            end
            response = dispatch(req.method, String(req.target);
                headers=collect(req.headers),
                body=HTMXObjects._request_body_bytes(req))
            push!(requests, string(req.method, " ", req.target) => response.status)
            response
        end
        try
            # Compile the poller paths before the browser's clock starts.
            warm = poll_url(String(hx_post("/browser_card", "which=warm").body))
            release_fresh!(:browser_card)
            settle(warm)
            reset_fresh!()
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : "no receipt"
                    @test outcome == "/complete?status=passed"
                    outcome == "/complete?status=passed" ||
                        @info "Browser requests" outcome requests=join(string.(requests), "\n")
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
            polls = filter(r -> contains(r.first, "__htmxo_poll=1"), requests)
            # Each polled submission's terminal is its operation's last poll.
            for token in unique(poll_token(r.first) for r in polls)
                mine = filter(r -> poll_token(r.first) == token, polls)
                @test last(mine).second == 286
                @test count(r -> r.second == 286, mine) == 1
            end
            @test length(unique(poll_token(r.first) for r in polls)) == 2
        finally
            release_fresh!(:browser_card)
            close(server)
        end
    end
end

# A morph swap (`hx-swap="morph:*"`, the live refresh's terminal) can reuse a
# running poller's element as other content: it strips the poller's
# attributes, but htmx only re-initializes an element that carries an `hx-*`
# attribute, so the element's `every` timer keeps polling the old URL and
# swaps each answer wherever the element now inherits. A KB tab polled a spent
# mutation token this way about twice a second for minutes (snag
# mutation-poller-4f9123b0). `morphAway` does to the poller what idiomorph
# does to an element it reuses. In the `htmx()` shell, `auto_terminal_script`
# cancels the stale timer's polls and drops an answer still in flight; on a
# page without the shell's runtime, the stop-polling 286 that ends every poll
# stops it.
@testitem "a poller a morph turned into other content stops polling" setup=[FreshTransportFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars
        import HTMXObjects: _clear_operation_polls!, h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_fresh!()
        _clear_operation_polls!()
        route!(FreshBrowserApp())
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        morph_away = raw"""
        const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
        async function until(predicate, label) {
          for (let i = 0; i < 400; i++) {
            if (await predicate()) return;
            await sleep(25);
          }
          throw new Error('timed out: ' + label);
        }
        function morphAway(el) {
          Array.from(el.attributes).forEach(a => el.removeAttribute(a.name));
          el.className = 'settled';
          el.textContent = 'settled';
        }
        window.addEventListener('error', function(event) {
          fetch('/complete?status=' + encodeURIComponent('error: ' + event.message));
        });
        // htmx arms a swapped-in poller when it settles (20 ms after the swap):
        // only a poller that has polled once carries the timer a morph strands.
        let polled = 0;
        document.addEventListener('htmx:afterRequest', function(event) {
          const path = (event.detail.requestConfig || {}).path || '';
          if (path.includes('__htmxo_poll=1')) polled++;
        });
        """
        # The shell: a slow submission's poller, morphed while one of its polls
        # is held in flight.
        shell_driver = h.script(Raw(morph_away * raw"""
        window.addEventListener('load', async function() {
          const result = document.getElementById('result');
          try {
            htmx.trigger(document.getElementById('save-form'), 'submit');
            await until(() => result.querySelector('.treebar-poller-inner'), 'save poller');
            await fetch('/hold');
            await until(async () => (await (await fetch('/held')).text()) === 'yes', 'held poll');
            morphAway(result.querySelector('.treebar-poller-inner'));
            await fetch('/mark?m=morphed');
            await fetch('/unhold');
            await sleep(800);
            await fetch('/release');
            await sleep(800);
            if (result.querySelector('.treebar-poller-inner')) throw new Error('a poller came back');
            if (!result.textContent.includes('settled')) throw new Error('morphed content lost');
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)) +
                  '&result=' + encodeURIComponent(result.innerHTML));
          }
        });
        """))
        # No shell runtime: a slow submission's poller (the header the shell's
        # `mutation_poll_script` would send is set by hand), morphed while it
        # runs.
        bare_driver = h.script(Raw(morph_away * raw"""
        window.addEventListener('load', async function() {
          const panel = document.getElementById('panel');
          try {
            htmx.ajax('POST', '/browser_save', {target: '#panel', swap: 'innerHTML',
              values: {note: 'bare'}, headers: {'HTMXO-Swap': 'innerHTML'}});
            await until(() => panel.querySelector('.treebar-poller-inner') && polled > 0,
                        'panel poller');
            morphAway(panel.querySelector('.treebar-poller-inner'));
            await fetch('/mark?m=morphed');
            await sleep(600);
            await fetch('/release');
            await sleep(1800);
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)));
          }
        });
        """))
        page_kwargs = (; assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false)
        shell_page = repr("text/html", htmx(h.main(
                h.form(; id="save-form", hx_post="/browser_save",
                       hx_target="#result", hx_swap="innerHTML")(
                    h.input(; type="hidden", name="note", value="morphed")),
                h.div(; id="result"), shell_driver); page_kwargs...))
        bare_page = repr("text/html", htmx(h.main(h.div(; id="panel"), bare_driver);
                                           treebars_assets=false, page_kwargs...))
        @test !contains(bare_page, "__htmxoAutoTerminal")
        page = Ref(shell_page)
        receipt = Channel{String}(1)
        seen = Tuple{Float64,String,String,Int}[]   # (time, kind, target, status)
        hold = Ref(false)
        held = Ref(false)
        unhold = Base.Event()
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" &&
                return HTTP.Response(200, ["Content-Type" => "text/html"], page[])
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, HTTP.unescapeuri(String(req.target)))
                return HTTP.Response(204)
            end
            path == "/hold" && (hold[] = true; return HTTP.Response(204))
            path == "/held" && return HTTP.Response(200, held[] ? "yes" : "no")
            path == "/unhold" && (notify(unhold); return HTTP.Response(204))
            if path == "/mark"
                push!(seen, (time(), "mark", String(req.target), 0))
                return HTTP.Response(204)
            end
            if path == "/release"
                release_fresh!(:browser_read)
                release_fresh!(:browser_post)
                return HTTP.Response(204)
            end
            poll = contains(req.target, "__htmxo_poll=1")
            arrived = time()
            if poll && hold[]
                hold[] = false
                held[] = true
                wait(unhold)
            end
            response = dispatch(req.method, String(req.target);
                headers=collect(req.headers),
                body=HTMXObjects._request_body_bytes(req))
            push!(seen, (arrived, poll ? "poll" : "request", String(req.target),
                        response.status))
            response
        end
        function browse()
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 60; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : "no receipt"
                    @test outcome == "/complete?status=passed"
                    outcome == "/complete?status=passed" ||
                        @info "Browser requests" outcome seen=join(string.(seen), "\n")
                    time()
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        end
        marked(m) = only(e[1] for e in seen if e[2] == "mark" && contains(e[3], m))
        polls() = filter(e -> e[2] == "poll", seen)
        try
            # Compile the poller paths before the browser's clock starts.
            warm = String(hx_get("/browser_panel").body)
            warm_post = String(hx_post("/browser_save", "note=warm").body)
            release_fresh!(:browser_read)
            release_fresh!(:browser_post)
            settle(poll_url(warm))
            settle(poll_url(warm_post))
            reset_fresh!()

            browse()
            # The poll held across the morph is the last one: the stale timer
            # sent nothing more, before or after the submission finished.
            morphed = marked("morphed")
            @test any(e -> e[1] < morphed, polls())
            @test !any(e -> e[1] > morphed, polls())
            @test fresh_runs(:browser_post) == 1

            empty!(seen)
            reset_fresh!()
            page[] = bare_page
            done = browse()
            morphed = marked("morphed")
            after = filter(e -> e[1] > morphed, polls())
            # Without the shell nothing cancels the stale timer, and it polls on
            # until the operation's last answer: 286 stops it, and the poller
            # its running answers planted inside it, for good. Before 286 it
            # polled the replayed terminal for as long as the page was open.
            @test !isempty(after)
            @test any(e -> e[4] == 286, after)
            @test !any(e -> e[1] > done - 1.0, polls())
            @test fresh_runs(:browser_post) == 1
        finally
            notify(unhold)
            release_fresh!(:browser_read)
            release_fresh!(:browser_post)
            close(server)
        end
    end
end
