using TestItemRunner

# Caller faults (4xx) are answered, not recorded: no error log or `@error`
# line, no `X-HTMXO-Error-Id`, no `__on_error__` (user decision `1danmww`). A
# late poll of a mutation whose result the server no longer holds is one: a KB
# tab's restored poller polled a spent token after a deploy and its 410 woke
# the error triage (snag spent-mutation-p-80878aaf). A server fault in the same
# app is the control: it is still recorded.
@testitem "caller faults are answered, not recorded as errors" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    hooked = String[]
    @htmx struct CallerFaultApp
        __on_error__ = (err, uid, path) -> push!(hooked, uid)
        @get fault_needs(; n::Int) = h.p("n=$n")
        @get fault_boom() = error("server fault")
        @post fault_save() = h.p("saved")
    end
    route!(CallerFaultApp())
    hx = ["HX-Request" => "true"]
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            missing_n = @test_logs min_level=Logging.Error dispatch(:GET, "/fault_needs")
            @test missing_n.status == 400
            @test contains(String(missing_n.body), "Bad Request")
            @test !HTTP.hasheader(missing_n, "X-HTMXO-Error-Id")
            fragment = @test_logs min_level=Logging.Error dispatch(:GET, "/fault_needs"; headers=hx)
            @test fragment.status == 200
            @test contains(String(fragment.body), "aria-invalid=\"true\"")
            @test !HTTP.hasheader(fragment, "X-HTMXO-Error-Id")
            spent = "/fault_save?__htmxo_poll=1&__htmxo_operation=$(repeat("0", 64))&__htmxo_verb=POST"
            gone = @test_logs min_level=Logging.Error dispatch(:GET, spent; headers=hx)
            @test gone.status == 286
            @test contains(String(gone.body), "Result unavailable")
            @test !HTTP.hasheader(gone, "X-HTMXO-Error-Id")
            @test dispatch(:GET, spent).status == 410
            @test isempty(readdir(dir))
            @test isempty(hooked)

            boom = dispatch(:GET, "/fault_boom")
            @test boom.status == 500
            uid = HTTP.header(boom, "X-HTMXO-Error-Id", "")
            @test !isempty(uid)
            @test readdir(dir) == ["$uid.log"]
            @test hooked == [uid]
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # A caller fault whose type names no title reads under a plain one, not
    # the server-fault page that points at an error id.
    refused = repr("text/html", HTMXObjects._invoke_error_handler(
        nothing, HTMXObjects._ResourceRefused(409, "Conflict"), nothing, nothing))
    @test contains(refused, "Request refused")
    @test contains(refused, "resource operation refused (409): Conflict")
    @test !contains(refused, "Error ID")
end

# An `__error__` hook that returns a `MIMEResponse` answers with it: a JSON
# API's error stays JSON, with the status the error would have had (500 for a
# server fault, 400 for a caller fault), instead of the escaped repr inside the
# page shell (snag json-api-errors-056cb64e). An `HTTP.Response` from the hook
# is the control: it keeps the status it chose.
@testitem "an __error__ hook's MIMEResponse is the answer, with the error's status" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    json_error(err) = MIMEResponse("application/json", "{\"error\":\"unknown item\"}")
    @htmx struct JsonErrorApp
        __error__ = json_error
        __page__(content) = htmx(h.main(content))
        "One item"
        @get json_item(k::String) = k == "a" ?
            MIMEResponse("application/json", "{\"k\":\"a\"}") :
            throw(ArgumentError("unknown item $k"))
        @direct @get json_needs(; n::Int) = MIMEResponse("application/json", "{\"n\":$n}")
    end
    @htmx struct OwnStatusErrorApp
        __error__ = err -> HTTP.Response(404, ["Content-Type" => "application/json"];
                                         body="{\"error\":\"gone\"}")
        @get own_status_item() = throw(ArgumentError("unknown"))
    end
    route!(JsonErrorApp())
    route!(OwnStatusErrorApp())
    content_type(r) = HTTP.header(r, "Content-Type")
    hx = ["HX-Request" => "true"]
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            ok = dispatch(:GET, "/json_item/a")
            @test (ok.status, content_type(ok), String(ok.body)) ==
                (200, "application/json", "{\"k\":\"a\"}")

            for target in ("/json_item/b", "/json_item/b?plain")
                fault = @test_logs (:error,) match_mode=:any dispatch(:GET, target)
                @test fault.status == 500
                @test content_type(fault) == "application/json"
                @test String(fault.body) == "{\"error\":\"unknown item\"}"
                uid = HTTP.header(fault, "X-HTMXO-Error-Id", "")
                @test isfile(joinpath(dir, "$uid.log"))
            end

            missing_n = @test_logs min_level=Logging.Error dispatch(:GET, "/json_needs")
            @test missing_n.status == 400
            @test content_type(missing_n) == "application/json"
            @test String(missing_n.body) == "{\"error\":\"unknown item\"}"
            @test !HTTP.hasheader(missing_n, "X-HTMXO-Error-Id")

            swapped = @test_logs min_level=Logging.Error dispatch(:GET, "/json_needs"; headers=hx)
            @test (swapped.status, content_type(swapped)) == (200, "application/json")

            own = @test_logs (:error,) match_mode=:any dispatch(:GET, "/own_status_item")
            @test (own.status, String(own.body)) == (404, "{\"error\":\"gone\"}")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
end
