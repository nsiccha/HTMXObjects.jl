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

# An app in another language sets its error texts once on the root struct:
# `@htmx` threads `__error_texts__` down the `__parent__` chain, so an
# `@include`d struct's routes answer in it too, and the server-fault article
# keeps the recorded error id that ties it to its log (snag
# error-articles-i-c4c9b7f6, reporter ODLPlaus:ux; design pick `16ro3ue`).
# Before, every framework word was English and a German `__error__` hook could
# not see the id. An app without the setting is the control: byte-identical
# English.
@testitem "error articles speak the root's error_texts and keep the error id" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    @htmx struct ErrorTextsChild
        @get et_child_boom() = error("child server fault")
    end
    @htmx struct ErrorTextsApp
        __error_texts__ = error_texts(:de)
        __page__(content) = htmx(h.main(content))
        @get et_boom() = error("server fault")
        @get et_probe(kenn::String) = throw(CallerFault(404, "Sonde $kenn unbekannt"))
        @get et_needs(; n::Int) = h.p("n=$n")
        @get et_flag(; b::Bool) = h.p("b=$b")
        @include et_sub = ErrorTextsChild()
    end
    @htmx struct ErrorTextsEnglishApp
        @get en_boom() = error("server fault")
        @get en_needs(; n::Int) = h.p("n=$n")
    end
    route!(ErrorTextsApp())
    route!(ErrorTextsEnglishApp())
    hx = ["HX-Request" => "true"]
    quiet(path; headers=[]) = with_logger(NullLogger()) do
        dispatch(:GET, path; headers)
    end
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            page = quiet("/et_boom")
            @test page.status == 500
            uid = HTTP.header(page, "X-HTMXO-Error-Id", "")
            @test !isempty(uid) && isfile(joinpath(dir, "$uid.log"))
            @test contains(String(page.body), "<article aria-invalid=\"true\"><header>Fehler</header>" *
                "<p>Etwas ist schiefgegangen. Fehler-ID: <code>$uid</code></p></article>")
            plain = quiet("/et_boom?plain")
            plain_uid = HTTP.header(plain, "X-HTMXO-Error-Id", "")
            @test contains(String(plain.body), "### Fehler")
            @test contains(String(plain.body), "Etwas ist schiefgegangen. Fehler-ID: `$plain_uid`")

            child = quiet("/et_sub/et_child_boom"; headers=hx)
            child_uid = HTTP.header(child, "X-HTMXO-Error-Id", "")
            @test !isempty(child_uid)
            @test contains(String(child.body), "<header>Fehler</header><p>Etwas ist schiefgegangen. " *
                "Fehler-ID: <code>$child_uid</code></p>")

            probe = quiet("/et_probe/x"; headers=hx)
            @test contains(String(probe.body), "<header>Nicht gefunden</header><p>Sonde x unbekannt</p>")
            needs = quiet("/et_needs")
            @test needs.status == 400
            @test contains(String(needs.body), "<header>Ungültige Anfrage</header><p>Pflichtangabe fehlt: n</p>")
            flag = quiet("/et_flag?b=maybe"; headers=hx)
            @test contains(String(flag.body),
                "<p>Ungültiger Wert für b: &quot;maybe&quot;; zulässige Werte: false, true</p>")

            english = quiet("/en_boom")
            english_uid = HTTP.header(english, "X-HTMXO-Error-Id", "")
            @test String(english.body) == "<article aria-invalid=\"true\"><header>Error</header>" *
                "<p>Something went wrong. Error ID: <code>$english_uid</code></p></article>"
            @test contains(String(quiet("/en_needs").body),
                "<header>Bad Request</header><p>Missing required parameter: n</p>")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # Logs, `?error` and stack traces stay English whatever the app speaks.
    @test sprint(showerror, HTMXObjects.MissingRequiredParam(:n)) == "Missing required parameter: n"
    @test sprint(showerror, HTMXObjects.InvalidDomainValue(:b, "maybe", (false, true))) ==
        "Invalid value for parameter b: \"maybe\"; allowed values: false, true"
    @test sprint(showerror, HTMXObjects.OperationResultUnavailable(:save, :POST)) ==
        "The result of this POST save submission is no longer available. It ran at most once " *
        "and was not repeated; reload to see the current state."
end

# `error_texts` follows `table_texts`: keyword overrides, a status table merged
# into the locale's, and loud refusals for a text that would lose meaning.
@testitem "error_texts takes overrides and refuses texts that lose meaning" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _invoke_error_handler, _reason_phrase, _caller_fault_message

    de = error_texts(:de)
    @test de == error_texts(:de) && error_texts() == HTMXObjects._EN_ERROR_TEXTS
    @test _reason_phrase(de, 404) == "Nicht gefunden" && _reason_phrase(de, 400) == "Ungültige Anfrage"
    @test _reason_phrase(de, 299) === nothing
    # Every status the English table names has a German phrase.
    @test first.(de.reasons) == first.(error_texts(:en).reasons)
    custom = error_texts(:de; reasons=Dict(404 => "Unbekannt"),
        server_fault="Ein Fehler ist aufgetreten ({id}); bitte melden: {id}")
    @test _reason_phrase(custom, 404) == "Unbekannt" && _reason_phrase(custom, 400) == "Ungültige Anfrage"
    @test repr("text/html", _invoke_error_handler(nothing, ErrorException("x"), "u9", nothing)) ==
        "<article aria-invalid=\"true\"><header>Error</header><p>Something went wrong. Error ID: <code>u9</code></p></article>"
    @test repr("text/html", HTMXObjects._default_error_render("u9", nothing, custom)) ==
        "<article aria-invalid=\"true\"><header>Fehler</header><p>Ein Fehler ist aufgetreten (" *
        "<code>u9</code>); bitte melden: <code>u9</code></p></article>"
    @test _caller_fault_message(HTMXObjects.OperationStalled("Fit", :POST, 75.0, 60.0, nothing), de) ==
        "Fit läuft seit 1 min 15 s, länger als die Grenze von 1 min, daher wartet diese Seite nicht mehr " *
        "darauf. Die Berechnung wurde nicht abgebrochen und kann im Hintergrund noch fertig werden. " *
        "Die POST-Übermittlung wurde nicht wiederholt; laden Sie die Seite neu, um den aktuellen Stand zu sehen."
    # A 4xx with no reason phrase reads under the plain `refused` title.
    @test contains(repr("text/html", HTMXObjects._invoke_error_handler(
        nothing, CallerFault(499, "abgebrochen"), nothing, nothing)), "<header>Request refused</header>")
    # refused: the article must keep the recorded error id that ties it to its log (snag error-articles-i-c4c9b7f6)
    @test_throws ArgumentError error_texts(:de; server_fault="Etwas ist schiefgegangen.")
    @test_throws ArgumentError error_texts(:fr)
    @test_throws ArgumentError error_texts(:de; bogus="x")
    @test_throws ArgumentError error_texts(:de; missing_param="{param} fehlt")
    # refused: a misspelt setting must not silently answer in English
    @test_throws ArgumentError HTMXObjects._error_texts_value(:de)
end

# A custom `__error__` hook that takes two arguments also receives the
# recorded error id (`nothing` for an unrecorded caller fault), so a hook in
# the app's own wording — or a JSON API's error body — keeps it. A
# one-argument hook is called as before (snag error-articles-i-c4c9b7f6).
@testitem "a two-argument __error__ hook receives the recorded error id" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    @htmx struct TwoArgHookApp
        __error__(err, uid) = h.p("id=", something(uid, "none"))
        @get two_boom() = error("server fault")
        @get two_probe(kenn::String) = throw(CallerFault(404, "unknown $kenn"))
    end
    one_arg(err) = h.p("one argument")
    @htmx struct OneArgHookApp
        __error__ = one_arg
        @get one_boom() = error("server fault")
    end
    @htmx struct OneArgMethodHookApp
        __error__(err) = h.p("one-argument method")
        @get one_method_boom() = error("server fault")
    end
    two_args(err, uid) = h.p("value id=", something(uid, "none"))
    @htmx struct TwoArgValueHookApp
        __error__ = two_args
        @get two_value_boom() = error("server fault")
    end
    route!(TwoArgValueHookApp())
    route!(TwoArgHookApp())
    route!(OneArgHookApp())
    route!(OneArgMethodHookApp())
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            boom = with_logger(NullLogger()) do; dispatch(:GET, "/two_boom"); end
            uid = HTTP.header(boom, "X-HTMXO-Error-Id", "")
            @test !isempty(uid) && contains(String(boom.body), "<p>id=$uid</p>")
            probe = with_logger(NullLogger()) do; dispatch(:GET, "/two_probe/x"); end
            @test probe.status == 404 && contains(String(probe.body), "<p>id=none</p>")
            one = with_logger(NullLogger()) do; dispatch(:GET, "/one_boom"); end
            @test one.status == 500 && contains(String(one.body), "<p>one argument</p>")
            method = with_logger(NullLogger()) do; dispatch(:GET, "/one_method_boom"); end
            @test method.status == 500 && contains(String(method.body), "<p>one-argument method</p>")
            value = with_logger(NullLogger()) do; dispatch(:GET, "/two_value_boom"); end
            value_uid = HTTP.header(value, "X-HTMXO-Error-Id", "")
            @test !isempty(value_uid) && contains(String(value.body), "<p>value id=$value_uid</p>")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # `__error__ = rethrow` keeps its one-argument call.
    @test !applicable(rethrow, ErrorException("x"), "u1")
end
