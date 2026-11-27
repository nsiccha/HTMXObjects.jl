using TestItemRunner

# A tabs page's result that the page itself asks for the first time (an edit
# before the first answer arrived, a tab the reader opens, a tab a mutation's
# `open_tab` opens) shows its operation's progress in the result, as the page's
# first load does. What stands in for the first answer (the first-time
# progress bar, the load placeholder) is no result to keep on screen while the
# poller reports beside it (snag `open-tab-view-sh-28514d74`).
#
# A result on screen stays while its next answer computes, the progress beside
# it, and gives way to the progress after the page's `progress_after` seconds.
# A tab `open_tab` opens for other inputs starts over at once (user pick on
# decision `0ap3o0p`).

@testmodule FirstResultFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export FirstResultApp, ProgressAfterApp, hold!, release!

    const HELD = Dict{String,Base.Event}()
    const HELD_LOCK = ReentrantLock()
    hold!(keys...) = lock(HELD_LOCK) do
        foreach(notify, values(HELD))
        empty!(HELD)
        foreach(key -> HELD[key] = Base.Event(), keys)
    end
    release!(key) = lock(() -> haskey(HELD, key) && notify(HELD[key]), HELD_LOCK)
    release!() = lock(() -> foreach(notify, values(HELD)), HELD_LOCK)

    function answer(view, setting)
        key = string(view, ":", setting)
        gate = lock(() -> get(HELD, key, nothing), HELD_LOCK)
        isnothing(gate) || wait(gate)
        h.p("Result ", key; data_result=key)
    end

    const driver = h.script(Raw(read(joinpath(@__DIR__, "support", "first_result.js"), String)))
    @htmx struct FirstResultApp
        "Setting"
        @param setting::String = "a"
        @options(setting) = option_domain(["a", "b", "c"])
        "Initial view"
        @get initial() = answer("initial", setting)
        "Clicked view"
        @get clicked() = answer("clicked", setting)
        "Opened view"
        @get opened() = answer("opened", setting)
        "Add"
        @post add(; name::String) = hx_response(open_tab("opened"; setting=name); toast="Added " * name)
        # The delay is short for the test, and long enough to see the result
        # kept first.
        @get index() = semantic_app(__self__; presentation=:tabs, select=e -> e.name !== :index,
            progress_after=1.5)
        __page__(body) = htmx(h.main(body), driver; assets=:vendor, pico_version=nothing,
            feedback=false, compose=false, overlay=false)
    end

    @htmx struct ProgressAfterApp
        "Setting"
        @param setting::String = "a"
        "View"
        @get view() = h.p("view:", setting)
        @get index() = semantic_app(__self__; presentation=:tabs, select=e -> e.name === :view)
        @get never() = semantic_app(__self__; presentation=:tabs, select=e -> e.name === :view,
            progress_after=nothing)
        @get later() = semantic_app(__self__; presentation=:tabs, select=e -> e.name === :view,
            progress_after=7.5)
    end
end

@testitem "a tabs page's results say after how long a refresh shows its progress" setup=[FirstResultFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    route!(ProgressAfterApp(); operation_policy=:blocking)
    page(path) = String(dispatch(:GET, path; headers=["HX-Request" => "true"]).body)
    result(html) = match(r"<div id=\"[^\"]*\" class=\"htmxo-semantic-operation-result\"[^>]*>", html).match
    @test contains(result(page("/")), " data-htmxo-progress-after=\"3\"")
    @test contains(result(page("/later")), " data-htmxo-progress-after=\"7.5\"")
    @test !contains(page("/never"), "data-htmxo-progress-after")
    @test contains(result(page("/never")), " data-htmxo-live")
    # The page script reads it where it diverts a refresh, and lets a page
    # start a result over.
    script = repr("text/html", HTMXObjects.live_refresh_script())
    @test contains(script, "data-htmxo-progress-after")
    @test contains(script, "htmxoLiveStartOver")
    for bad in (-1, NaN, Inf, "3", true)
        @test_throws "progress_after must be a number of seconds" semantic_app(
            ProgressAfterApp(); presentation=:tabs, progress_after=bad)
    end
    @test_throws "progress_after= times the results of presentation=:tabs" semantic_app(
        ProgressAfterApp(); progress_after=5)
end

@testitem "page scripts agree on what stands in for a first answer" tags=[:unit, :semantic] begin
    using HTMXObjects
    stand_in = HTMXObjects._awaits_first_answer_js()
    @test contains(stand_in, "function awaitsFirstAnswer(c)")
    # One definition, in the script that decides whether a live target holds
    # settled content and in the one that decides whether a region holds a
    # result to keep.
    for script in (HTMXObjects.live_refresh_script(), HTMXObjects.semantic_follow_script())
        @test contains(repr("text/html", script), stand_in)
    end
end

@testitem "a result asked for the first time shows its operation's progress in the result" setup=[FirstResultFixtures, HTMXOTestPorts] tags=[:browser, :semantic] begin
    using HTMXObjects, HTTP, JSON, Treebars
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        reports = Channel{String}(1)
        function control(handler)
            function (req)
                path = HTTP.URI(req.target).path
                if startswith(path, "/test-release/")
                    release!(String(last(split(path, '/'))))
                    return HTTP.Response(204)
                elseif path == "/test-report"
                    put!(reports, String(HTMXObjects._request_body_bytes(req)))
                    return HTTP.Response(204)
                end
                handler(req)
            end
        end
        hold!("initial:a", "initial:b", "clicked:b", "clicked:c", "opened:a", "opened:b")
        HTMXObjects._clear_operation_polls!()
        route!(FirstResultApp())
        vendorfiles()
        port = free_port()
        operation_log = HTMXObjects.OPERATION_LOG[]
        serve(; port, async=true, access_log=nothing, operation_log=nothing, middleware=[control])
        try
            mktempdir() do profile
                chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> isready(reports) || process_exited(proc), 100.0) === :ok
                    isready(reports) || error("Chrome returned no first-result report")
                    report = JSON.parse(take!(reports))
                    println("First result in a browser: ", JSON.json(report))
                    @test !haskey(report, "error")
                    haskey(report, "error") && return
                    # The page drew the open tab's result as a load placeholder,
                    # and the edit replaced its request.
                    @test report["placeholder"]
                    for (name, label) in ("edit" => "Initial view", "clicked" => "Clicked view",
                                          "opened" => "Opened view")
                        seen = report[name]
                        @test (name => seen["inResult"]) == (name => true)
                        @test (name => seen["beside"]) == (name => false)
                        @test (name => seen["standIn"]) == (name => false)
                        @test (name => seen["tree"]) == (name => true)
                        @test contains(seen["text"], label)
                    end
                    @test report["opened"]["tab"] == "true"
                    # Once a result is shown, its next slow answer reports beside it...
                    @test report["refresh"]["kept"] && report["refresh"]["beside"]
                    @test !report["refresh"]["inResult"]
                    # ...and after the page's `progress_after` takes its place.
                    taken = report["takeover"]
                    @test taken["inResult"] && taken["tree"] && contains(taken["text"], "Clicked view")
                    @test !taken["beside"] && !taken["kept"] && !taken["busy"]
                    @test taken["landed"]
                    # A tab `open_tab` opens for another setting starts over at once.
                    again = report["reopened"]
                    @test again["inResult"] && again["tree"] && contains(again["text"], "Opened view")
                    @test !again["beside"] && !again["kept"] && !again["standIn"]
                    @test again["landed"]
                    # Opened for the setting it shows, it keeps its result.
                    @test report["same"]["requests"] == 1
                    @test !report["same"]["bar"] && report["same"]["kept"]
                finally
                    process_exited(proc) || kill(proc)
                    wait(proc)
                end
            end
        finally
            release!()
            terminate()
            HTMXObjects.OPERATION_LOG[] = operation_log
        end
    end
end
