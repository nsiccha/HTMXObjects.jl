using TestItemRunner


@testitem "an app that shows its errors' causes shows a server fault's exception and log entry" tags=[:unit, :server] begin
    using HTMXObjects, HTTP
    import HTMXObjects: _clear_operation_polls!

    struct ShownFault <: Exception
        detail::String
    end
    Base.showerror(io::IO, e::ShownFault) = print(io, "ShownFault: ", e.detail)

    @htmx struct CauseChild
        @get child_boom() = error("child exploded")
    end
    @htmx struct CauseApp
        __show_error_cause__ = true
        @get boom() = error("the <cause> & its\nsecond line")
        @get typed() = throw(ShownFault("unknown distribution :Normal_"))
        @get refused() = throw(CallerFault(404, "unknown probe 7"))
        @get long() = error(repeat("x", 20_000))
        @get missing_param(; n::Int) = h.p(n)
        @include child = CauseChild()
    end
    @htmx struct QuietApp
        @get quiet_boom() = error("not for the caller")
    end
    @htmx struct OffApp
        __show_error_cause__ = false
        @get off_boom() = error("not for the caller either")
    end
    @htmx struct BadSettingApp
        __show_error_cause__ = "yes"
        @get bad_boom() = error("bad setting")
    end
    @htmx struct GermanCauseApp
        __show_error_cause__ = true
        __error_texts__ = error_texts(:de)
        @get german_boom() = error("auf Deutsch")
    end
    _clear_operation_polls!()
    for app in (CauseApp(), QuietApp(), OffApp(), BadSettingApp(), GermanCauseApp())
        route!(app; operation_policy=:blocking)
    end
    body(r) = String(HTMXObjects._message_body_bytes(r))
    hx(target) = dispatch(:GET, target; headers=["HX-Request" => "true"])

    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            answer = hx("/boom")
            uid = HTTP.header(answer, "X-HTMXO-Error-Id")
            path = joinpath(dir, "$uid.log")
            html = body(answer)
            # The error-id line, then the type, bold, and the message as written
            # (escaped), in a block that wraps.
            @test contains(html, "<header>Error</header><p>Something went wrong. Error ID: <code>$uid</code></p>")
            @test contains(html, "<p><strong>ErrorException</strong></p><pre class=\"htmxo-error-cause\">the &lt;cause&gt; &amp; its\nsecond line</pre>")
            # The log entry, under a disclosure that names its file.
            @test contains(html, "<details class=\"htmxo-error-log-entry\"><summary>Log entry <code>$path</code></summary><pre class=\"htmxo-error-log\">")
            @test contains(html, "uid:       $uid")
            @test contains(html, "Stacktrace:")
            # The message's own type prefix is not repeated.
            typed = body(hx("/typed"))
            @test contains(typed, "<p><strong>ShownFault</strong></p><pre class=\"htmxo-error-cause\">unknown distribution :Normal_</pre>")
            # A caller fault's article is unchanged: it shows its message already.
            refused = body(hx("/refused"))
            @test contains(refused, "<header>Not Found</header><p>unknown probe 7</p>")
            @test !contains(refused, "htmxo-error-cause") && !contains(refused, "<details")
            @test !contains(body(hx("/missing_param")), "htmxo-error-cause")
            # A message too long for the page is left out whole; the log holds it.
            long = body(hx("/long"))
            @test contains(long, "<p>The message is 19.531 KiB long, too long for this page; the log entry holds it.</p>")
            @test !contains(long, "htmxo-error-cause")
            @test contains(long, repeat("x", 20_000))   # inside the log entry
            # An `@include`d struct inherits the root's setting.
            @test contains(body(hx("/child/child_boom")), "child exploded</pre>")
            # The Markdown answer carries it too.
            plain = dispatch(:GET, "/boom"; headers=["Accept" => "text/markdown"])
            @test plain.status == 500
            @test contains(body(plain), "**ErrorException**")
            @test contains(body(plain), "the <cause> & its")
            # Without the setting, or with it false, the article is as before.
            for (target, text) in ("/quiet_boom" => "not for the caller", "/off_boom" => "not for the caller either")
                quiet = hx(target)
                quiet_uid = HTTP.header(quiet, "X-HTMXO-Error-Id")
                @test body(quiet) == "<article aria-invalid=\"true\"><header>Error</header><p>Something went wrong. Error ID: <code>$quiet_uid</code></p></article>"
                @test contains(read(joinpath(dir, "$quiet_uid.log"), String), text)
            end
            # refused: a setting that is not a Bool.
            @test_throws "__show_error_cause__ must be true or false, got \"yes\"" HTMXObjects._show_error_cause(BadSettingApp())
            # In the app's language.
            german = body(hx("/german_boom"))
            @test contains(german, "<summary>Protokolleintrag <code>")
            @test contains(german, "auf Deutsch</pre>")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
end

@testitem "a failed polled operation's terminal shows its cause" tags=[:unit, :server, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!
    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing

    gate = Base.Event()
    @htmx struct PolledCauseApp
        __show_error_cause__ = true
        "Compute the doomed report"
        @get doomed() = (wait(gate); error("polled cause"))
    end
    _clear_operation_polls!()
    route!(PolledCauseApp())
    body(r) = String(HTMXObjects._message_body_bytes(r))
    hx(target) = dispatch(:GET, target; headers=["HX-Request" => "true"])
    running(r) = contains(body(r), "hx-trigger=\"every ")
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            started = hx("/doomed")
            @test running(started)
            url = replace(only(match(r"hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\"",
                                     body(started)).captures), "&amp;" => "&")
            notify(gate)
            failed = nothing
            for _ in 1:400
                answer = hx(url)
                running(answer) || (failed = answer; break)
                sleep(0.025)
            end
            uid = HTTP.header(failed, "X-HTMXO-Error-Id")
            @test contains(body(failed), "class=\"treebar-terminal\"")
            @test contains(body(failed), "<p><strong>ErrorException</strong></p><pre class=\"htmxo-error-cause\">polled cause</pre>")
            @test contains(body(failed), "<code>$(joinpath(dir, "$uid.log"))</code>")
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
end
