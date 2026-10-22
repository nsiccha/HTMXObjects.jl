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
    # A refused resource operation is a caller fault titled with its reason
    # phrase, not the server-fault page that points at an error id; a 4xx with
    # no standard phrase reads under a plain title.
    refused = repr("text/html", HTMXObjects._invoke_error_handler(
        nothing, HTMXObjects._resource_refused(409, "Conflict"), nothing, nothing))
    @test contains(refused, "<header>Conflict</header>")
    @test contains(refused, "resource operation refused (409): Conflict")
    @test !contains(refused, "Error ID")
    unnamed = repr("text/html", HTMXObjects._invoke_error_handler(
        nothing, CallerFault(499, "client closed"), nothing, nothing))
    @test contains(unnamed, "<header>Request refused</header>")
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

# A route body throws `CallerFault(status, message)` when the request is at
# fault: an unknown resource id, an argument out of range. It is answered like
# a missing parameter, with its own status and message and no error record
# (snag json-api-errors-056cb64e: ODLPlaus's unknown probe id and out-of-range
# float were recorded 500s).
@testitem "a route body's CallerFault is answered with its status, not recorded" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    hooked = String[]
    @htmx struct CallerFaultRouteApp
        __on_error__ = (err, uid, path) -> push!(hooked, uid)
        "One probe"
        @get cf_probe(kenn::String) = kenn == "a1" ? h.p("probe a1") :
            throw(CallerFault(404, "unknown probe $kenn"))
        @get cf_window(; p_min::Float64=0.0) = 0 <= p_min <= 1 ? h.p("p_min=$p_min") :
            throw(CallerFault(400, "p_min must be in [0, 1], got $p_min"))
    end
    json_fault(err) = let fault = unwrap_error(err)
        MIMEResponse("application/json",
            "{\"status\":$(fault.status),\"error\":\"$(fault.message)\"}")
    end
    @htmx struct CallerFaultJsonApp
        __error__ = json_fault
        @direct @get cf_json(kenn::String) = throw(CallerFault(404, "unknown probe $kenn"))
    end
    route!(CallerFaultRouteApp())
    route!(CallerFaultJsonApp())
    hx = ["HX-Request" => "true"]
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            @test contains(String(dispatch(:GET, "/cf_probe/a1").body), "probe a1")

            missing_probe = @test_logs min_level=Logging.Error dispatch(:GET, "/cf_probe/zz")
            @test missing_probe.status == 404
            body = String(missing_probe.body)
            @test contains(body, "<header>Not Found</header>")
            @test contains(body, "unknown probe zz")
            @test !HTTP.hasheader(missing_probe, "X-HTMXO-Error-Id")

            plain = @test_logs min_level=Logging.Error dispatch(:GET, "/cf_probe/zz?plain")
            @test plain.status == 404
            @test contains(String(plain.body), "unknown probe zz")

            swapped = @test_logs min_level=Logging.Error dispatch(:GET, "/cf_probe/zz"; headers=hx)
            @test swapped.status == 200
            @test contains(String(swapped.body), "aria-invalid=\"true\"")
            @test contains(String(swapped.body), "unknown probe zz")

            out_of_range = @test_logs min_level=Logging.Error dispatch(:GET, "/cf_window?p_min=2")
            @test out_of_range.status == 400
            @test contains(String(out_of_range.body), "<header>Bad Request</header>")
            @test contains(String(out_of_range.body), "p_min must be in [0, 1], got 2.0")

            json = @test_logs min_level=Logging.Error dispatch(:GET, "/cf_json/zz")
            @test (json.status, HTTP.header(json, "Content-Type"), String(json.body)) ==
                (404, "application/json", "{\"status\":404,\"error\":\"unknown probe zz\"}")

            @test isempty(readdir(dir))
            @test isempty(hooked)
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # refused: a non-4xx status is not a caller fault; a server fault stays an
    # ordinary, recorded exception (user decision 0jvov7q, option 1).
    @test_throws ArgumentError CallerFault(500, "upstream down")
    @test_throws ArgumentError CallerFault(302, "moved")
    @test sprint(showerror, CallerFault(404, "unknown probe zz")) == "unknown probe zz"
end

# A failed polled operation answers with Treebars' failure terminal, which
# records the error itself (through `safely`) rather than through
# `_route_error_response`. The answer still carries what a route error's does:
# the recorded uid as `X-HTMXO-Error-Id`, and the runtime ledger's error note.
# Without the header, a failed htmx answer (a 200 or 286 the page swaps in)
# reads as content (snag htmx-terminal-er-93025c20). The fixture covers all
# three transports: a poll of a retained operation, the request that started
# the operation, and a poll that heals an unknown token into a fresh one. For
# the last two, a wrapped `_operation_polling_impl` lets the operation fail
# before Treebars renders the answer, the way a slow failure past the grace
# budget does in a live app.
@testitem "a failed polled operation's answer carries its recorded error id" tags=[:unit, :server, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!, _operation_polling_impl
    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing

    hooked = String[]
    doom_gate = Base.Event()
    @htmx struct FailedPollApp
        __on_error__ = (err, uid, path) -> push!(hooked, uid)
        "Compute the doomed report"
        @get doomed_report() = (wait(doom_gate); error("report exploded"))
    end
    @htmx struct FailedInlineApp
        __on_error__ = (err, uid, path) -> push!(hooked, uid)
        "Compute the instant failure"
        @get doomed_now() = error("failed at once")
    end
    tracker = RuntimeTracker(; record_polls=true)
    _clear_operation_polls!()
    route!(FailedPollApp())
    route!(FailedInlineApp(); operation_policy=OperationPolicy(:polling))
    app = track_requests(HTMXObjects.ROUTER; tracker)
    hx_get(target) = app(HTTP.Request("GET", target, ["HX-Request" => "true"], UInt8[]))
    body(r) = String(HTMXObjects._message_body_bytes(r))
    running(r) = contains(body(r), "hx-trigger=\"every ")
    # The snapshot lists requests newest first.
    newest_record(kind) = first(filter(r -> r.kind === kind, runtime_snapshot(tracker).history))
    function recorded(answer, dir)
        uid = HTTP.header(answer, "X-HTMXO-Error-Id", "")
        !isempty(uid) &&
            contains(body(answer), "class=\"treebar-terminal\"") &&
            contains(body(answer), "Error ID: <code>$uid</code>") &&
            "$uid.log" in readdir(dir) && last(hooked) == uid
    end

    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            # A poll of a retained operation that has failed since.
            started = hx_get("/doomed_report")
            @test running(started)
            @test !HTTP.hasheader(started, "X-HTMXO-Error-Id")
            url = replace(only(match(r"hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\"",
                                     body(started)).captures), "&amp;" => "&")
            notify(doom_gate)
            failed = nothing
            for _ in 1:400
                answer = hx_get(url)
                running(answer) || (failed = answer; break)
                sleep(0.025)
            end
            @test failed.status == 286
            @test recorded(failed, dir)
            uid = HTTP.header(failed, "X-HTMXO-Error-Id")
            @test contains(newest_record(:poll).error, "report exploded [error $uid]")

            # The request that started the operation, and a heal.
            old_polling = _operation_polling_impl[]
            _operation_polling_impl[] = (render, started, args...) -> begin
                timedwait(() -> isready(started), 10.0; pollint=0.005)
                old_polling(render, started, args...)
            end
            try
                inline = hx_get("/doomed_now")
                @test inline.status == 200
                @test recorded(inline, dir)
                uid = HTTP.header(inline, "X-HTMXO-Error-Id")
                @test contains(newest_record(:htmx).error, "failed at once [error $uid]")

                healed = hx_get("/doomed_now?__htmxo_poll=1&__htmxo_operation=$(repeat("0", 64))")
                @test healed.status == 286
                @test recorded(healed, dir)
                uid = HTTP.header(healed, "X-HTMXO-Error-Id")
                @test contains(newest_record(:poll).error, "failed at once [error $uid]")
            finally
                _operation_polling_impl[] = old_polling
            end
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end

    # The answer follows `_route_error_response`'s rule: htmx keeps the
    # swapping status, any other request takes the error's own, and an
    # unrecorded caller fault carries no id. Without a noted failure the
    # answer is untouched.
    function stamped(headers, err, uid)
        req = HTTP.Request("GET", "/doomed_now", headers, UInt8[])
        isnothing(err) || HTMXObjects._note_operation_failure!(req, err, uid)
        answer = HTMXObjects._stamp_operation_headers(
            req, HTTP.Response(200, "terminal"), false)
        (answer.status, HTTP.header(answer, "X-HTMXO-Error-Id", ""))
    end
    hx = ["HX-Request" => "true"]
    page = Pair{String,String}[]
    @test stamped(hx, ErrorException("x"), "abc") == (200, "abc")
    @test stamped(page, ErrorException("x"), "abc") == (500, "abc")
    @test stamped(page, CallerFault(404, "gone"), nothing) == (404, "")
    @test stamped(hx, nothing, nothing) == (200, "")
end
