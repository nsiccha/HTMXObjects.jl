using TestItemRunner

# A route binds the parameters it declares and has always dropped the rest,
# answering with its defaults: a misspelled or guessed parameter got a
# confident wrong answer (snag `route-dsl-silent-76d5490b`: the KB's
# `?raw=1&field=command` served the elaboration, and `/mark` with `reason=`
# stored an empty note). An app opts into refusing them with
# `__undeclared_params__` (user decision `0tqhsuo`, no preference: the opt-in
# declaration on the app's struct).
@testitem "__undeclared_params__ refuses, warns about or ignores parameters a route does not take" tags=[:unit] begin
    using HTMXObjects
    using Test

    # The reporter's two routes in miniature, plus a route with no keywords,
    # one with a required keyword and one with a keyword splat.
    @htmx struct UPRows
        "Row"
        @get row(id::String; raw::String = "") = raw == "command" ? "command of $id" : "elaboration of $id"
        "Mark"
        @post mark(id::String; to::String, note::String = "") = "marked $id $to note=$(repr(note))"
        "Note"
        @post note(; text::String) = "note=$text"
        "Take"
        @post take(; fields...) = join(sort!(String.(collect(keys(fields)))), ",")
        "Stale check"
        @post stalecheck() = "checked"
    end
    @htmx struct UPStrictRoot
        __undeclared_params__ = (; action=:refuse, allow=("from", "by"))
        @param lang::String = "en"
        @include rows = UPRows()
        @include quiet = begin
            __undeclared_params__ = :ignore
            "Probe"
            @get probe(; q::String = "") = "q=$q"
        end
        @include inner = begin
            @param page::Int = 1
            "Show"
            @get show(; q::String = "") = "q=$q"
        end
    end
    @htmx struct UPWarnRoot
        __undeclared_params__ = :warn
        @include rows = UPRows()
    end
    @htmx struct UPGermanRoot
        __undeclared_params__ = :refuse
        __error_texts__ = error_texts(:de)
        @include rows = UPRows()
    end
    @htmx struct UPBadRoot
        __undeclared_params__ = :strict
        @include rows = UPRows()
    end
    @htmx struct UPFormRoot
        __undeclared_params__ = :refuse
        @param lang::String = "en"
        "Mark"
        @post mark(; to::String, note::String = "") = "marked $to note=$(repr(note))"
    end
    @htmx struct UPHost
        @include lenient = UPRows()
        @include strict = UPStrictRoot()
        @include warn = UPWarnRoot()
        @include german = UPGermanRoot()
        @include bad = UPBadRoot()
        @include form = UPFormRoot()
    end

    app = UPHost()
    route!(app; operation_policy=:blocking)
    form = ["Content-Type" => "application/x-www-form-urlencoded"]
    body(r) = String(r.body)

    # Without a declaration nothing changes: undeclared parameters are dropped
    # and the route answers with its defaults, the reporter's two cases.
    r = dispatch(:GET, "/lenient/row/7?plain=1&raw=1&field=command")
    @test r.status == 200
    @test body(r) == "elaboration of 7"
    r = dispatch(:POST, "/lenient/mark/7?plain=1"; headers=form, body="to=moot&reason=dup")
    @test r.status == 200
    @test body(r) == "marked 7 moot note=\"\""

    # `:refuse`: the same requests answer 400, naming the unknown parameter and
    # what the route takes: its keywords, the `@param`s of the chain from the
    # root down (here the enclosing app's `lang`), then the `allow` names.
    r = dispatch(:GET, "/strict/rows/row/7?plain=1&raw=1&field=command")
    @test r.status == 400
    @test occursin("Unknown parameter: field; accepted parameters: raw, lang, from, by", body(r))
    r = dispatch(:POST, "/strict/rows/mark/7?plain=1"; headers=form, body="to=moot&reason=dup")
    @test r.status == 400
    @test occursin("Unknown parameter: reason; accepted parameters: to, note, lang, from, by", body(r))
    r = dispatch(:POST, "/strict/rows/mark/7?plain=1"; headers=form, body="to=moot&note=dup")
    @test r.status == 200
    @test body(r) == "marked 7 moot note=\"dup\""

    # Declared names pass, and so do the `allow` list and the framework's own
    # names: `plain`, `v`, `tab` and every `__` protocol name.
    r = dispatch(:GET, "/strict/rows/row/7?plain=1&raw=command&lang=de&from=me&by=you&v=3&tab=x&__htmxo_x=1")
    @test r.status == 200
    @test body(r) == "command of 7"

    # A misspelled required keyword is named as the unknown parameter it is,
    # because the check runs before the arguments are parsed.
    r = dispatch(:POST, "/strict/rows/note?plain=1"; headers=form, body="txt=hi")
    @test r.status == 400
    @test occursin("Unknown parameter: txt; accepted parameters: text, lang, from, by", body(r))

    # A name counts with an empty value too, and in a POST's query string;
    # several are listed sorted.
    @test dispatch(:POST, "/strict/rows/mark/7?plain=1"; headers=form, body="to=moot&reason=").status == 400
    r = dispatch(:POST, "/strict/rows/mark/7?plain=1&reason=dup"; headers=form, body="to=moot")
    @test r.status == 400
    @test occursin("Unknown parameter: reason;", body(r))
    r = dispatch(:POST, "/strict/rows/mark/7?plain=1"; headers=form, body="to=moot&zeta=1&alpha=2")
    @test r.status == 400
    @test occursin("Unknown parameter: alpha, zeta;", body(r))

    # A route without keywords refuses a form field too. A body is a form when
    # its Content-Type says so; without one only for a route that reads form
    # fields. A JSON object's keys also submit parameters.
    r = dispatch(:POST, "/strict/rows/stalecheck?plain=1"; headers=form, body="reason=x")
    @test r.status == 400
    @test occursin("Unknown parameter: reason; accepted parameters: lang, from, by", body(r))
    @test dispatch(:POST, "/strict/rows/mark/7?plain=1"; body="to=moot&reason=dup").status == 400
    @test dispatch(:POST, "/german/rows/stalecheck?plain=1"; body="reason=x").status == 200
    r = dispatch(:POST, "/german/rows/stalecheck?plain=1";
        headers=["Content-Type" => "application/json"], body="{\"reason\": 1}")
    @test r.status == 400
    @test occursin("reason", body(r))
    @test dispatch(:POST, "/german/rows/stalecheck?plain=1";
        headers=["Content-Type" => "application/json"], body="{").status == 200

    # A keyword splat takes every field, so the policy leaves its route alone.
    r = dispatch(:POST, "/strict/rows/take?plain=1"; headers=form, body="a=1&b=2")
    @test r.status == 200
    @test body(r) == "a,b"

    # The innermost declaration wins, and an inline mount's own `@param` is
    # accepted beside the enclosing one.
    r = dispatch(:GET, "/strict/quiet/probe?plain=1&q=1&bogus=1")
    @test r.status == 200
    @test body(r) == "q=1"
    r = dispatch(:GET, "/strict/inner/show?plain=1&q=1&page=2&lang=de")
    @test r.status == 200
    @test body(r) == "q=1"
    r = dispatch(:GET, "/strict/inner/show?plain=1&q=1&pg=2")
    @test r.status == 400
    @test occursin("Unknown parameter: pg; accepted parameters: q, lang, page, from, by", body(r))

    # A page load in the browser is not checked: its address is the page's
    # own, where tab bars and `url_params` keep view state for the page's
    # scripts. The same address fetched by a script is.
    @test dispatch(:GET, "/strict/rows/row/7?raw=1&ortsteil=0101";
        headers=["Accept" => "text/html"]).status == 200
    @test dispatch(:GET, "/strict/rows/row/7?raw=1&ortsteil=0101").status == 400

    # The app's error texts word the refusal; a route that takes nothing says so.
    r = dispatch(:GET, "/german/rows/row/7?plain=1&field=command")
    @test r.status == 400
    @test occursin("Unbekannte Angabe: field; zulässige Angaben: raw", body(r))
    r = dispatch(:POST, "/german/rows/stalecheck?plain=1"; headers=form, body="reason=x")
    @test r.status == 400
    @test occursin("Unbekannte Angabe: reason; keine Angaben zulässig", body(r))
    @test sprint(showerror, HTMXObjects.UndeclaredParams(["field"], ["raw"])) ==
        "Unknown parameter: field; accepted parameters: raw"
    @test sprint(showerror, HTMXObjects.UndeclaredParams(["a", "b"], String[])) ==
        "Unknown parameter: a, b; no parameters accepted"

    # `:warn` answers as before and logs the refusal it would have made.
    r = @test_logs (:warn, "Unknown parameter: field; accepted parameters: raw") match_mode=:any dispatch(
        :GET, "/warn/rows/row/7?plain=1&raw=1&field=command")
    @test r.status == 200
    @test body(r) == "elaboration of 7"

    # A declaration it cannot read is the route's error, naming the struct.
    @test dispatch(:GET, "/bad/rows/row/7?plain=1&raw=1").status == 500
    bad(value) = try
        HTMXObjects._undeclared_params_value(app, value)
        nothing
    catch err
        err
    end
    for value in (:strict, (; action=:refuse, allowed=("x",)), (; allow=("x",)),
                  (; action=:refuse, allow="from"), (; action="refuse"), "refuse")
        err = bad(value)
        @test err isa ArgumentError
        @test err isa ArgumentError && occursin("`__undeclared_params__` on UPHost must be :ignore, :warn or :refuse", err.msg)
    end
    @test HTMXObjects._undeclared_params_value(app, (; action=:warn, allow=[:from, "by"])).allow == ["from", "by"]
    @test HTMXObjects._undeclared_params_value(app, :refuse).action === :refuse

    # A generated form submits only names its route accepts, and the
    # declaration renders nothing on a semantic page.
    form_html = repr("text/html", operation_form(app.form, :mark; verb=:POST, method="post",
                                                 action=app.form / "mark"))
    names = unique!([m[1] for m in eachmatch(r"name=\"([^\"]+)\"", form_html)])
    @test "to" in names
    @test all(n -> n in ("to", "note", "lang") || HTMXObjects._framework_param_name(n), names)
    @test !occursin("undeclared", repr("text/html", semantic_app(app.form)))
    r = dispatch(:POST, "/form/mark?plain=1"; headers=form, body="to=moot&note=dup&lang=en")
    @test r.status == 200
    @test body(r) == "marked moot note=\"dup\""
end

# A multipart body that does not parse used to escape the check as HTTP.jl's
# parse error, so an app that only warned answered 500 before a route that
# reads its own body could answer it, and a route binding a field from such a
# body answered 500 with no declaration at all (snag `undeclared-param-65ddfd9b`:
# the KB's `/code/upload` refusal turned into a 500 once it declared `:warn`).
@testitem "a multipart body that does not parse is the caller's 400, and the undeclared-parameter check leaves it to the route" tags=[:unit] begin
    using HTMXObjects, HTTP, Logging
    using Test

    @htmx struct UBRows
        "Upload"
        @post upload() = begin
            fields = try
                multipartparams(__req__)
            catch err
                err isa HTMXObjects.UnreadableBody || rethrow()
                return HTTP.Response(400, "refused by the route: " * err.reason)
            end
            "stored " * join(sort!(collect(keys(fields))), ",")
        end
        "Take a file"
        @post take(; file::Upload) = "took $(file.filename)"
    end
    @htmx struct UBWarn
        __undeclared_params__ = (; action=:warn, allow=("ext",))
        @include rows = UBRows()
    end
    @htmx struct UBRefuse
        __undeclared_params__ = (; action=:refuse, allow=("ext",))
        @include rows = UBRows()
    end
    @htmx struct UBGerman
        __undeclared_params__ = :refuse
        __error_texts__ = error_texts(:de)
        @include rows = UBRows()
    end
    @htmx struct UBHost
        @include ub_lenient = begin
            @include rows = UBRows()
        end
        @include ub_warn = UBWarn()
        @include ub_refuse = UBRefuse()
        @include ub_german = UBGerman()
    end
    app = UBHost()
    route!(app; operation_policy=:blocking)
    body(r) = String(r.body)

    file = "--b\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\n" *
           "Content-Type: image/png\r\n\r\nPNG\r\n--b--\r\n"
    good = ["Content-Type" => "multipart/form-data; boundary=b"]
    other = ["Content-Type" => "multipart/form-data; boundary=other"]
    post(path, headers, payload) = with_logger(NullLogger()) do
        dispatch(:POST, path; headers, body=payload)
    end

    # `multipartparams` throws the caller fault, naming what was wrong; a request
    # that names no boundary still yields an empty dict.
    req(headers, payload) = HTTP.Request("POST", "/", headers, Vector{UInt8}(payload))
    err = try
        multipartparams(req(other, file)); nothing
    catch e
        e
    end
    @test err isa HTMXObjects.UnreadableBody
    @test err.format == "multipart/form-data"
    @test err.reason == "boundary delimiter not found"
    @test sprint(showerror, err) ==
        "Unreadable request body: not valid multipart/form-data (boundary delimiter not found)"
    @test_throws HTMXObjects.UnreadableBody bodyparams(req(other, file))
    @test isempty(multipartparams(req(["Content-Type" => "multipart/form-data"], file)))
    @test multipartparams(req(good, file))["file"].filename == "a.png"

    # HTTP 1.x reports two malformed parts as a `MethodError` on a `nothing`
    # its parser returned; any other exception is a defect and is not a caller
    # fault.
    rejection = HTMXObjects._multipart_rejection
    @test rejection(MethodError(convert, (HTTP.Multipart, nothing))) == "a part has no form-data name"
    @test rejection(MethodError(iterate, (nothing,))) ==
        "no delimiter found separating header from multipart body"
    @test rejection(ErrorException("boundary delimiter not found")) == "boundary delimiter not found"
    @test rejection(MethodError(convert, (HTTP.Multipart, 1))) === nothing
    @test rejection(MethodError(HTTP.parse_multipart_form, (1,))) === nothing
    @test rejection(BoundsError([1], 2)) === nothing

    # Without a declaration: a route that reads its own body answers it, and a
    # route that binds a field from it answers 400, never 500.
    r = post("/ub_lenient/rows/upload?plain=1&ext=png", other, file)
    @test r.status == 400
    @test body(r) == "refused by the route: boundary delimiter not found"
    r = post("/ub_lenient/rows/take?plain=1", other, file)
    @test r.status == 400
    @test occursin("Unreadable request body: not valid multipart/form-data (boundary delimiter not found)", body(r))
    @test post("/ub_lenient/rows/take?plain=1", good, file).status == 200

    # `:warn` and `:refuse` read no names from such a body, say so once, and
    # leave it to the route: the same answers as without a declaration.
    for mount in ("ub_warn", "ub_refuse")
        local r
        r = @test_logs (:warn, "Unreadable request body: not valid multipart/form-data (boundary delimiter not found); its parameter names were not checked") match_mode=:any dispatch(
            :POST, "/$mount/rows/upload?plain=1&ext=png"; headers=other, body=file)
        @test r.status == 400
        @test body(r) == "refused by the route: boundary delimiter not found"
        r = post("/$mount/rows/take?plain=1", other, file)
        @test r.status == 400
        @test occursin("Unreadable request body: not valid multipart/form-data", body(r))
    end
    # A body that is not an envelope at all, too.
    @test body(post("/ub_refuse/rows/upload?plain=1&ext=png", good, "%PDF-1.4 not an envelope")) ==
        "refused by the route: boundary delimiter not found"
    # The check still reads the query string of such a request.
    r = post("/ub_refuse/rows/upload?plain=1&ext=png&bogus=1", other, file)
    @test r.status == 400
    @test occursin("Unknown parameter: bogus; accepted parameters: ext", body(r))
    # And a body that parses is checked as before.
    r = post("/ub_refuse/rows/take?plain=1", good, file)
    @test r.status == 200
    @test body(r) == "took a.png"

    # The app's error texts word the fault.
    r = post("/ub_german/rows/take?plain=1", other, file)
    @test r.status == 400
    @test occursin("Unlesbarer Inhalt der Anfrage: kein gültiges multipart/form-data (boundary delimiter not found)", body(r))
end
