@dynamicstruct struct CaptionsData
    scores = DataFrame(
        name = ["Alice", "Bob", "Carol", "Dave"],
        score = [95, 87, 92, 78],
        time_ms = [12.4, 8.1, 9.9, 11.2],
    )
    timings = DataFrame(
        stage = ["parse", "compile", "run", "teardown"],
        mean_ms = [3.2, 18.7, 124.5, 1.1],
        n = [1000, 1000, 1000, 1000],
    )
    scores_caption = CaptionSpec(;
        title = "Test scores",
        short = "Top 4 scores from the 2026-Q1 round, sortable.",
        long = "Includes only participants who completed all questions. " *
               "Tied scores are broken by completion time.",
    )
    timings_caption = CaptionSpec(;
        title = "Pipeline stage timings",
        short = "Mean per-stage runtime over n=1000 invocations.",
    )
    bar_caption = CaptionSpec(;
        title = "Bar chart: stage mean runtime",
        short = "Visual comparison of the same data shown in the timings table.",
        long = h.div(
            h.p("Bars are scaled to the maximum stage mean."),
            h.p("This is just an inline SVG to demonstrate that ", h.code("with_caption"),
                " also wraps non-table content."),
        ),
    )
end

@htmx struct CaptionsRoutes
    (; captions) = __appdata__
    (; scores, timings, scores_caption, timings_caption, bar_caption) = captions

    @get index = begin
        max_ms = maximum(timings.mean_ms)
        bar_w(v) = round(Int, 400 * v / max_ms)
        bars = h.svg(; width=480, height=20*nrow(timings)+10, class="u-bg-soft")(
            [h.g()(
                h.rect(; x=80, y=20*(i-1)+5, width=bar_w(timings.mean_ms[i]), height=14, fill="#3b82f6"),
                h.text(timings.stage[i]; x=5, y=20*(i-1)+16, font_size=12),
                h.text(string(timings.mean_ms[i], "ms"); x=85+bar_w(timings.mean_ms[i]), y=20*(i-1)+16, font_size=12),
            ) for i in 1:nrow(timings)]...
        )
        h.div(
            h.h1("Captions Demo"),
            h.p("Tables and figures wrapped with ", h.code("CaptionSpec"), " / ",
                h.code("with_caption"), ". The CSV download button lives in the caption header."),
            render_table(scores; download=true, caption=scores_caption),
            render_table(timings; download=true, caption=timings_caption),
            with_caption(bar_caption, bars),
            sortable_table_js(),
            download_table_js(),
            caption_style(),
        )
    end
end
