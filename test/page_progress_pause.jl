using TestItemRunner

# A visitor-facing app's `:auto` pollers showed Treebars' ❚❚ pause control, and
# pressing it froze the page while the work ran on. The app now declares
# `__progress_pause__ = false` once on its root; the value holds like
# `__lang__`, and Treebars reads it through `HTMXObjects.page_progress_pause()`
# (snag `visitor-apps-can-148cfaf6`, todo `0m1qpp4`).

@testitem "__progress_pause__ holds for the route, its :auto polls and its subtrees" tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test
    import HTMXObjects: h

    # Rendered on the request's task, so it shows the value the answer holds.
    struct PauseReading end
    Base.show(io::IO, ::MIME"text/html", ::PauseReading) =
        print(io, "<p>pause=", something(HTMXObjects.page_progress_pause(), "none"), "</p>")

    gate = Base.Event()
    @htmx struct ProgressPauseLab
        mode::Symbol
        __progress_pause__ = mode === :on ? true : nothing
        @direct @get progress_pause_lab_now() = PauseReading()
    end
    @htmx struct ProgressPauseVisitorApp
        __progress_pause__ = false
        "Compute the visitor report"
        @get progress_pause_slow() = (wait(gate); PauseReading())
        @direct @get progress_pause_now() = PauseReading()
        @include progress_pause_lab(mode::Symbol) = ProgressPauseLab(mode)
    end
    @htmx struct ProgressPausePlainApp
        @direct @get progress_pause_plain_now() = PauseReading()
    end
    route!(ProgressPauseVisitorApp())
    route!(ProgressPausePlainApp())

    hx = ["HX-Request" => "true"]
    body(target) = String(HTMXObjects._message_body_bytes(dispatch(:GET, target; headers=hx)))
    running(b) = contains(b, "hx-trigger=\"every ")
    function poll_url(b)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), b)
        found === nothing && error("no poll URL in response:\n" * b)
        replace(only(found.captures), "&amp;" => "&")
    end
    function settle(target)
        for _ in 1:400
            b = body(target)
            running(b) || return b
            sleep(0.025)
        end
        error("operation never settled: $target")
    end

    try
        @test contains(body("/progress_pause_now"), "pause=false")
        # The innermost declaration wins; `nothing` keeps the enclosing one.
        @test contains(body("/progress_pause_lab/on/progress_pause_lab_now"), "pause=true")
        @test contains(body("/progress_pause_lab/off/progress_pause_lab_now"), "pause=false")
        @test contains(body("/progress_pause_plain_now"), "pause=none")
        @test HTMXObjects.page_progress_pause() === nothing

        # An `:auto` operation's poll answers hold it too.
        first = body("/progress_pause_slow")
        @test running(first)
        url = poll_url(first)
        @test running(body(url))
        notify(gate)
        @test contains(settle(url), "pause=false")
    finally
        notify(gate)
    end

    # refused: a declaration that is not true, false or nothing fails the
    # route, named after its struct, before the route body runs (todo
    # `0m1qpp4`'s contract; no silent errors, dev §1)
    @htmx struct ProgressPauseBadApp
        __progress_pause__ = "no"
        @get progress_pause_bad() = h.p("never rendered")
    end
    route!(ProgressPauseBadApp())
    bad = dispatch(:GET, "/progress_pause_bad"; headers=hx)
    @test bad.status == 500 && !contains(String(HTMXObjects._message_body_bytes(bad)), "never rendered")
    err = try
        HTMXObjects._page_meta_of(Any[ProgressPauseBadApp()])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && contains(err.msg, "`__progress_pause__` on ProgressPauseBadApp")
end

@testitem "a running :auto poller under __progress_pause__ = false has no pause control" tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test
    import HTMXObjects: h

    @test Base.get_extension(HTMXObjects, :HTMXObjectsTreebarsExt) !== nothing
    gate = Base.Event()
    @htmx struct ProgressPauseHiddenApp
        __progress_pause__ = false
        "Compute the hidden-pause report"
        @get progress_pause_hidden_slow() = (wait(gate); h.p("done"))
    end
    @htmx struct ProgressPauseShownApp
        "Compute the shown-pause report"
        @get progress_pause_shown_slow() = (wait(gate); h.p("done"))
    end
    route!(ProgressPauseHiddenApp())
    route!(ProgressPauseShownApp())
    hx = ["HX-Request" => "true"]
    body(target) = String(HTMXObjects._message_body_bytes(dispatch(:GET, target; headers=hx)))
    pause_control(b) = occursin(r"<button[^>]*class=\"treebar-pause\"", b)
    # Treebars follows the declaration from the generation whose renderers take
    # `pause=`; an older one keeps showing the control.
    follows = hasmethod(Treebars.htmx_render_board, Tuple{Any}, (:pause,))
    try
        hidden = body("/progress_pause_hidden_slow")
        shown = body("/progress_pause_shown_slow")
        @test contains(hidden, "treebar-poller") && contains(shown, "treebar-poller")
        @test pause_control(shown)
        if follows
            @test !pause_control(hidden)
        else
            @test_broken !pause_control(hidden)
        end
    finally
        notify(gate)
    end
end
