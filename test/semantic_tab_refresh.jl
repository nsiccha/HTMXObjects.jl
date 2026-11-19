using TestItemRunner

@testmodule TabRefreshFixtures begin
    using HTMXObjects
    export TabRefreshApp, release!, reset_gates!

    const gates = Dict{Int, Base.Event}()
    function reset_gates!()
        empty!(gates)
        for i in 2:11
            gates[i] = Base.Event()
        end
    end
    release!(value) = notify(gates[value])
    release!() = foreach(notify, values(gates))

    function answer(value)
        haskey(gates, value) && wait(gates[value])
        value == 11 && error("Tab fixture failed")
        result = h.p("Result $value"; data_value=value)
        value == 3 ? hx_response(result; trigger="tab-header") : result
    end

    const driver = h.script(Raw(read(joinpath(@__DIR__, "support", "tab_refresh.js"), String)))
    @htmx struct TabRefreshApp
        @param setting::Int = 0
        "Preview"
        @get tab_preview() = answer(setting)
        @get index() = semantic_app(__self__; presentation=:tabs, select=e -> e.name === :tab_preview)
        __page__(body) = htmx(h.main(body), driver; assets=:vendor, pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
    end
end

@testitem "a committed tab edit follows its live result through the operation stream" setup=[TabRefreshFixtures, HTMXOTestPorts] tags=[:browser, :semantic] begin
    using HTMXObjects, HTTP, JSON, Treebars
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1" || Base.pkgversion(Treebars) < v"0.1.5"
        @test_skip true
    else
        @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
        reports = Channel{String}(1)
        function control(handler)
            function (req)
                path = HTTP.URI(req.target).path
                if startswith(path, "/test-release/")
                    release!(parse(Int, last(split(path, '/'))))
                    return HTTP.Response(204)
                elseif path == "/test-report"
                    put!(reports, String(HTMXObjects._request_body_bytes(req)))
                    return HTTP.Response(204)
                end
                handler(req)
            end
        end
        reset_gates!()
        HTMXObjects._clear_operation_polls!()
        route!(TabRefreshApp())
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
                    isready(reports) || error("Chrome returned no tab refresh report")
                    report = JSON.parse(take!(reports))
                    println("Tab refresh browser timings (ms): ", JSON.json(report))
                    @test !haskey(report, "error")
                    haskey(report, "error") && return
                    @test report["typingRequests"] == 0
                    @test report["invalid"]["requests"] == 0
                    for name in ("inline", "stream", "headers", "late", "pause", "veto",
                                 "superseded", "newer", "drop", "legacy", "failure")
                        trial = report[name]
                        @test trial["requests"] == 1
                        @test trial["nextTurn"]
                    end
                    @test !report["inline"]["deferred"]
                    @test report["stream"]["deferred"] && report["stream"]["pushed"]
                    @test report["stream"]["polls"] == 0
                    @test report["stream"]["offers"] == 1
                    @test report["headers"]["polls"] == 1 && report["headerEvents"] == 1
                    @test report["late"]["polls"] == 1 && report["late"]["pushed"]
                    for name in ("pause", "veto", "newer")
                        @test report[name]["pushed"] && report[name]["offers"] == 1
                    end
                    @test report["superseded"]["offers"] == 0
                    @test report["failure"]["errorStatus"] == 286
                    @test !isempty(report["failure"]["errorId"])
                    for name in ("drop", "legacy", "failure")
                        @test report[name]["polls"] >= 1 && !report[name]["pushed"]
                    end
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
