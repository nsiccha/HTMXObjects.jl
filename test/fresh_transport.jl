using TestItemRunner

# Cache policy and response transport are independent. `@fresh` (and every
# mutation verb) recomputes per invocation; under the default `:auto` policy a
# slow invocation is still answered by the Treebars poller and resumed by its
# token. Mutation polls resume the one submission and never re-run it.
@testmodule FreshTransportFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export FreshReadApp, FreshPageApp, FreshMutationApp, SharedPathApp, FreshRetainedApp,
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
    end

    # A mutation path that also declares a GET: the GET route serves the
    # mutation's polls itself.
    @htmx struct SharedPathApp
        @get shared_thing() = (fresh_hit!(:shared_get); h.p("shared-get"))
        "Change the shared thing"
        @post shared_thing() = gated(:shared_post, "shared-post")
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
        "Save the slow form"
        @post browser_save(; note::String="") = gated(:browser_post, "saved-$note")
    end

    const hx = ["HX-Request" => "true"]
    const form = "Content-Type" => "application/x-www-form-urlencoded"

    hx_get(target; headers=Pair{String,String}[]) =
        dispatch(:GET, target; headers=[hx; headers])
    hx_post(target, body=""; method=:POST) =
        dispatch(method, target; headers=[hx; form], body)
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
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

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
    @test !contains(first_url, "n=5")
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

    # A finished submission's token is spent; a lost or foreign one never
    # re-runs the submission — it answers "result unavailable".
    for target in (first_url, replace(first_url, poll_token(first_url) => "0"^64))
        gone = hx_get(target)
        @test gone.status == 200
        gone_body = String(gone.body)
        @test contains(gone_body, "aria-invalid=\"true\"")
        @test contains(gone_body, "Result unavailable")
        @test contains(gone_body, "not repeated")
        unavailable = dispatch(:GET, target)
        @test unavailable.status == 410
    end
    @test fresh_runs(:order) == 2

    # The mutation path's resume-only GET is not a GET route.
    not_allowed = dispatch(:GET, "/fresh_order")
    @test not_allowed.status == 405
    @test HTTP.header(not_allowed, "Allow") == "POST"
    malformed = "/fresh_order?__htmxo_poll=1&__htmxo_verb=TRACE"
    @test contains(String(hx_get(malformed).body), "Bad Request")
    @test dispatch(:GET, malformed).status == 400

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
    @test headers.status == 200
    @test HTTP.header(headers, "HX-Trigger") == "fresh-done"
    body = body_text(headers)
    @test contains(body, "treebar-terminal-content")
    @test contains(body, "<p>with-headers</p>")
    @test !contains(body, "HTTP/1.1")

    # A 204 would not swap: the poller still receives its (empty) terminal.
    nocontent = settle_response(targets[:nocontent])
    @test nocontent.status == 200
    @test contains(body_text(nocontent), "treebar-terminal-content")

    # Any other status retires the poller with an error article.
    conflict = settle(targets[:conflict])
    @test contains(conflict, "aria-invalid=\"true\"")
    @test contains(conflict, "HTTP 409")
    @test contains(conflict, "<p>conflict</p>")
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
            await fetch('/release');
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
            push!(requests, string(req.method, " ", req.target))
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
            # One click, one execution: the browser's polls resumed it.
            @test fresh_runs(:browser_post) == 1
            @test fresh_runs(:browser_read) == 1
            @test count(r -> startswith(r, "POST /browser_save"), requests) == 1
            @test any(r -> startswith(r, "GET /browser_save?") &&
                           contains(r, "__htmxo_verb=POST"), requests)
        finally
            release_fresh!(:browser_read)
            release_fresh!(:browser_post)
            close(server)
        end
    end
end
