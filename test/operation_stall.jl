using TestItemRunner

# A polled operation that never finishes used to answer "running" forever:
# every poll renewed its registry entry, and no failure ever reached the
# reader (snag `invoices-income-2015193b`). Past the root's
# `OperationPolicy` stall bound the next poll now answers `OperationStalled`
# instead — unless the operation finished or failed, which always answers its
# own result. The fixtures age a retained operation by moving its
# `created_at` back rather than waiting ten minutes.
@testmodule StallFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export StallReadApp, StallQueuedApp, StallQueuedBoundApp, StallOffApp,
        StallMutationApp, StallBrowserApp, reset_stall!, stall_runs,
        release_stall!, age_operations!, hx_get, hx_post, running, poll_url,
        poll_token, settle, body_text, rerun_url, operation_age

    const stall_lock = ReentrantLock()
    const stall_counts = Dict{Symbol,Int}()
    const StallGates = Dict{Symbol,Base.Event}()

    function reset_stall!()
        lock(stall_lock) do
            empty!(stall_counts)
            for key in collect(keys(StallGates))
                notify(StallGates[key])   # free anything an earlier item left waiting
                StallGates[key] = Base.Event()
            end
        end
        nothing
    end

    stall_runs(key::Symbol) = lock(() -> get(stall_counts, key, 0), stall_lock)
    hit!(key::Symbol) = lock(() -> (stall_counts[key] = get(stall_counts, key, 0) + 1), stall_lock)
    gate(key::Symbol) = lock(() -> get!(Base.Event, StallGates, key), stall_lock)
    release_stall!(key::Symbol) = notify(gate(key))

    # Count the run, wait for the test to release it, then answer.
    function gated(key::AbstractString, answer)
        k = Symbol(key)
        run = hit!(k)
        wait(gate(k))
        hit!(Symbol(key, "_done"))
        answer(run)
    end

    @htmx struct StallReadApp
        "Compute the slow report"
        @get stall_report(; key::String="report") =
            gated(key, run -> h.p("report-$key:$run"))
        "Compute the doomed report"
        @get stall_doomed(; key::String="doomed") =
            gated(key, _ -> error("report exploded"))
    end

    @htmx struct StallQueuedApp
        "Compute the queued report"
        @queued @get queued_report(; key::String="queued") =
            gated(key, run -> h.p("queued-$key:$run"))
    end

    @htmx struct StallQueuedBoundApp
        "Compute the bounded queued report"
        @queued @get bounded_report(; key::String="bounded") =
            gated(key, run -> h.p("bounded-$key:$run"))
    end

    @htmx struct StallOffApp
        "Compute the unbounded report"
        @get unbounded_report(; key::String="unbounded") =
            gated(key, run -> h.p("unbounded-$key:$run"))
    end

    @htmx struct StallMutationApp
        "Submit the slow order"
        @post stall_order(; key::String="order") =
            gated(key, run -> h.p("ordered-$key:$run"))
    end

    @htmx struct StallBrowserApp
        "Compute the browser report"
        @get browser_report(; key::String="browser") =
            gated(key, run -> h.p("browser-report:$run"))
    end

    const hx = ["HX-Request" => "true"]
    hx_get(target) = dispatch(:GET, target; headers=hx)
    hx_post(target, body="") = dispatch(:POST, target;
        headers=[hx; "Content-Type" => "application/x-www-form-urlencoded";
                 "HTMXO-Swap" => "innerHTML"],
        body)

    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")

    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end

    poll_token(target) =
        only(match(r"__htmxo_operation=([0-9a-f]+)", target).captures)

    function rerun_url(body)
        found = match(r"<button[^>]*class=\"htmxo-operation-rerun\"[^>]*>", body)
        found === nothing && return nothing
        get_attr = match(r"hx-get=\"([^\"]*)\"", found.match)
        replace(only(get_attr.captures), "&amp;" => "&")
    end

    operation_age(response) =
        parse(Int, HTTP.header(response, "X-HTMXO-Operation-Age", "-1"))

    # Pretend every retained operation started `seconds` earlier.
    function age_operations!(seconds)
        for entry in values(HTMXObjects._operation_poll_snapshot())
            entry.created_at -= seconds
        end
        nothing
    end

    function settle(target)
        for _ in 1:400
            body = body_text(hx_get(target))
            running(body) || return body
            sleep(0.025)
        end
        error("operation never settled: $target")
    end
end

@testitem "a read past its stall bound answers a terminal stall failure with Run again" setup=[StallFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    reset_stall!()
    _clear_operation_polls!()
    route!(StallReadApp())

    first_body = body_text(hx_get("/stall_report?key=stall1"))
    @test running(first_body)
    url = poll_url(first_body)
    token = poll_token(url)

    # Within the bound a poll keeps the running poller and reports its age.
    within = hx_get(url)
    @test running(body_text(within))
    @test 0 <= operation_age(within) < 600
    @test isempty(HTTP.header(within, "X-HTMXO-Error-Id", ""))

    age_operations!(601)
    stalled = hx_get(url)
    body = body_text(stalled)
    @test stalled.status == 286
    @test !isempty(HTTP.header(stalled, "X-HTMXO-Error-Id", ""))
    @test operation_age(stalled) >= 601
    @test !running(body)
    @test contains(body, "class=\"treebar-terminal\"")
    @test contains(body, "class=\"treebar-terminal-content\"")
    @test contains(body, "Operation stalled")
    @test contains(body, "Compute the slow report has been running for 10 min")
    @test contains(body, "longer than its 10 min stall bound")
    @test contains(body, "was not cancelled")
    # The open progress tree shows what was still running.
    @test contains(body, "treebar-frozen")
    # Run again re-requests the operation itself: captured args, no token.
    @test rerun_url(body) == "/stall_report?key=stall1"
    @test contains(body, "hx-target=\"closest .treebar-terminal-content\"")
    @test contains(body, "hx-params=\"none\"")
    # Nothing polls a stalled operation again; its entry is gone.
    @test !haskey(_operation_poll_snapshot(), token)
    @test stall_runs(:stall1) == 1

    # Run again, once the computation can finish, answers the report.
    release_stall!(:stall1)
    @test timedwait(() -> stall_runs(:stall1_done) >= 1, 10.0; pollint=0.01) === :ok
    again = body_text(hx_get(rerun_url(body)))
    running(again) && (again = settle(poll_url(again)))
    @test contains(again, "report-stall1:")
    @test !contains(again, "Operation stalled")
end

@testitem "an operation that finished or failed answers its own result past the bound" setup=[StallFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_poll_snapshot

    reset_stall!()
    _clear_operation_polls!()
    route!(StallReadApp())

    # Finished: the result wins however long it took.
    done_url = poll_url(body_text(hx_get("/stall_report?key=finish")))
    entry = _operation_poll_snapshot()[poll_token(done_url)]
    age_operations!(10_000)
    release_stall!(:finish)
    @test timedwait(() -> isready(entry.started), 10.0; pollint=0.01) === :ok
    finished = hx_get(done_url)
    finished_body = body_text(finished)
    @test contains(finished_body, "report-finish:1")
    @test !contains(finished_body, "Operation stalled")
    @test isempty(HTTP.header(finished, "X-HTMXO-Error-Id", ""))

    # Failed: the operation's own failure, not a stall.
    doomed_url = poll_url(body_text(hx_get("/stall_doomed?key=doom")))
    age_operations!(10_000)
    release_stall!(:doom)
    @test timedwait(() -> stall_runs(:doom_done) >= 1, 10.0; pollint=0.01) === :ok
    failed = settle(doomed_url)
    @test !contains(failed, "Operation stalled")
    @test contains(failed, "aria-invalid=\"true\"")
end

@testitem "the stall bound follows the root's OperationPolicy" setup=[StallFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_stall!()
    _clear_operation_polls!()
    route!(StallQueuedApp())
    route!(StallQueuedBoundApp(); operation_policy=OperationPolicy(:auto; queued_stall_after=60))
    route!(StallOffApp(); operation_policy=OperationPolicy(:auto; stall_after=nothing))

    # `@queued` work can wait in the job queue: unbounded by default.
    queued_url = poll_url(body_text(hx_get("/queued_report?key=q1")))
    # `stall_after=nothing` turns the bound off.
    off_url = poll_url(body_text(hx_get("/unbounded_report?key=off1")))
    # `queued_stall_after` bounds `@queued` work when a root asks for it.
    bounded_url = poll_url(body_text(hx_get("/bounded_report?key=b1")))

    age_operations!(100_000)
    queued = hx_get(queued_url)
    @test running(body_text(queued))
    @test operation_age(queued) >= 100_000
    @test running(body_text(hx_get(off_url)))
    bounded = body_text(hx_get(bounded_url))
    @test contains(bounded, "Operation stalled")
    @test contains(bounded, "longer than its 1 min stall bound")
    @test rerun_url(bounded) == "/bounded_report?key=b1"

    foreach(release_stall!, (:q1, :off1, :b1))
    @test contains(settle(queued_url), "queued-q1:1")
    @test contains(settle(off_url), "unbounded-off1:1")
end

@testitem "a stalled mutation is never re-submitted" setup=[StallFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!

    reset_stall!()
    _clear_operation_polls!()
    route!(StallMutationApp())

    first_body = body_text(hx_post("/stall_order", "key=m1"))
    @test running(first_body)
    url = poll_url(first_body)
    @test contains(url, "__htmxo_verb=POST")
    @test running(body_text(hx_get(url)))

    age_operations!(601)
    stalled = hx_get(url)
    body = body_text(stalled)
    @test !isempty(HTTP.header(stalled, "X-HTMXO-Error-Id", ""))
    @test contains(body, "Operation stalled")
    @test contains(body, "The POST submission was not repeated")
    @test rerun_url(body) === nothing
    @test !contains(body, "Run again")

    # The submission ran once and its token is spent: a later poll is told
    # the result is unavailable instead of running the order again.
    gone = body_text(hx_get(url))
    @test contains(gone, "Result unavailable")
    release_stall!(:m1)
    @test timedwait(() -> stall_runs(:m1_done) >= 1, 10.0; pollint=0.01) === :ok
    @test stall_runs(:m1) == 1
end

@testitem "OperationPolicy stall bounds, stalled URLs and messages" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: OperationStalled, _operation_unmarked_url, _human_seconds,
        _error_status_code, _operation_stall_after

    default = OperationPolicy()
    @test default.stall_after == 600.0
    @test default.queued_stall_after === nothing
    @test _operation_stall_after(default, false) == 600.0
    @test _operation_stall_after(default, true) === nothing
    custom = OperationPolicy(:polling; stall_after=30, queued_stall_after=3600)
    @test custom.stall_after == 30.0 && custom.queued_stall_after == 3600.0
    @test OperationPolicy(:auto; stall_after=nothing).stall_after === nothing
    # refused: a non-positive or infinite bound is not a bound (spell "no bound" as `nothing`)
    @test_throws ArgumentError OperationPolicy(:auto; stall_after=0)
    @test_throws ArgumentError OperationPolicy(:auto; queued_stall_after=-1)
    @test_throws ArgumentError OperationPolicy(:auto; stall_after=Inf)
    # The positional shapes keep today's defaults.
    @test OperationPolicy(:polling, "350ms", false).stall_after == 600.0
    legacy = OperationPolicy(:polling, "350ms", false, true)
    @test legacy.keep_terminal_tree && legacy.stall_after == 600.0

    @test _operation_unmarked_url("/a?__htmxo_poll=1&n=3&__htmxo_operation=ab") == "/a?n=3"
    @test _operation_unmarked_url("/a?__htmxo_operation=ab") == "/a"
    @test _operation_unmarked_url("/p/App/x?q=a%20b&__htmxo_page_load=t") == "/p/App/x?q=a%20b"
    @test _operation_unmarked_url("/plain") == "/plain"

    @test _human_seconds(45.9) == "45 s"
    @test _human_seconds(600) == "10 min"
    @test _human_seconds(601) == "10 min 1 s"
    @test _human_seconds(3720) == "1 h 2 min"

    read = OperationStalled("Income tax 2025", :GET, 603.2, 600.0, "/income_tax_2025")
    @test sprint(showerror, read) == "Income tax 2025 has been running for 10 min 3 s, " *
        "longer than its 10 min stall bound, so this page stopped waiting for it. " *
        "The computation was not cancelled and may still finish in the background. " *
        "Run again starts a fresh computation with the same arguments."
    post = OperationStalled("Save", :POST, 700.0, 600.0, nothing)
    @test endswith(sprint(showerror, post),
        "The POST submission was not repeated; reload to see the current state.")
    @test _error_status_code(read) == 504
end

@testitem "Run again replaces a stalled operation in a real browser" setup=[StallFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets, Treebars
        import HTMXObjects: _clear_operation_polls!, h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_stall!()
        _clear_operation_polls!()
        route!(StallBrowserApp())
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
          try {
            htmx.ajax('GET', '/browser_report?key=live', {target: '#panel', swap: 'innerHTML'});
            await until(() => panel.querySelector('.treebar-poller .treebar-poller-inner'), 'running poller');
            await fetch('/age');
            await until(() => panel.textContent.includes('Operation stalled'), 'stall terminal');
            // The live poller stopped and the wrapper terminalized.
            if (panel.querySelector('[hx-trigger^="every"]')) throw new Error('still polling');
            if (!panel.querySelector('.treebar-terminal')) throw new Error('wrapper not terminal');
            const button = panel.querySelector('button.htmxo-operation-rerun');
            if (!button) throw new Error('no Run again button');
            await fetch('/release');
            // htmx binds swapped-in content when it settles (20 ms after the
            // swap); a reader's click comes later than that.
            await sleep(300);
            button.click();
            await until(() => panel.textContent.includes('browser-report:') &&
                              !panel.textContent.includes('Operation stalled') &&
                              !panel.querySelector('[hx-trigger^="every"]'), 'rerun result');
            fetch('/complete?status=passed');
          } catch (err) {
            fetch('/complete?status=' + encodeURIComponent(String(err)) +
                  '&panel=' + encodeURIComponent(panel.innerHTML));
          }
        });
        """))
        page = repr("text/html", htmx(h.main(h.div(; id="panel"), driver);
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
            if path == "/age"
                age_operations!(601)
                return HTTP.Response(204)
            end
            if path == "/release"
                release_stall!(:live)
                return HTTP.Response(204)
            end
            push!(requests, string(req.method, " ", req.target))
            dispatch(req.method, String(req.target);
                headers=collect(req.headers),
                body=HTMXObjects._request_body_bytes(req))
        end
        try
            # Compile the poller and stall paths before the browser runs.
            warm_url = poll_url(body_text(hx_get("/browser_report?key=warm")))
            age_operations!(601)
            @test contains(body_text(hx_get(warm_url)), "Operation stalled")
            release_stall!(:warm)
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --password-store=basic --user-data-dir=$profile http://127.0.0.1:$port/`
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
            # The stalled computation ran once; Run again asked for the report
            # afresh with its captured argument and no token.
            @test stall_runs(:live) >= 1
            @test any(r -> r == "GET /browser_report?key=live", requests)
        finally
            release_stall!(:live)
            close(server)
        end
    end
end
