using TestItemRunner

@testitem "caption markdown joins title, short, and long with em-dash" tags=[:unit] begin
    using HTMXObjects

    title, short, long = "Fig 14", "amplitude is shown separately.", "Shape only: NPDE decorrelates."

    # Three tiers join exactly like Bruno's single-figure `_vplot_caption_text`
    # (single paragraph — Quarto promotes only the final paragraph to the
    # numbered caption, so a blank-line separator would break PDF numbering).
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short, long))) == "**Fig 14** — amplitude is shown separately. — Shape only: NPDE decorrelates."
    @test !contains(HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short, long))), "separately.Shape")

    # Missing tiers keep the compact caption; a missing short still separates
    # the title from a present long.
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short))) == "**Fig 14** — amplitude is shown separately."
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title))) == "**Fig 14**"
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, long))) == "**Fig 14** — Shape only: NPDE decorrelates."

    # Blank longs emit no separator: several Bruno composites pass `long=""`,
    # and an unconditional separator would leave a trailing " — ".
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short, long=""))) == "**Fig 14** — amplitude is shown separately."
    blank_md = HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short, long="   ")))
    @test !contains(blank_md, "— Shape")
    @test strip(blank_md) == "**Fig 14** — amplitude is shown separately."
    @test HTMXObjects.to_markdown_string(render_caption(
        CaptionSpec(; title, short, long=h.div()))) == "**Fig 14** — amplitude is shown separately."

    # Node longs (Bruno's `render_blocks` shape: `div(p, p, …)`) separate at
    # the header boundary; internal paragraph breaks are the paragraphs' own.
    node_md = HTMXObjects.to_markdown_string(render_caption(CaptionSpec(; title, short,
        long=h.div(h.p("Para one here."), h.p("Para two here.")))))
    @test contains(node_md, "separately. — Para one here.")
    @test contains(node_md, "Para one here.\n\nPara two here.")
    @test !contains(node_md, "More")

    # Figures and tables inherit the join through the shared `render_caption`.
    for node in (with_caption(CaptionSpec(; title, short, long), h.p("Figure content.")),
            render_table((dose=[1, 2], percent=[25, 75]);
                caption=CaptionSpec(; title, short, long), download=false))
        @test contains(HTMXObjects.to_markdown_string(node), "separately. — Shape only:")
    end

    # The separator is markdown-only: HTML is byte-identical to the pre-fix
    # rendering, so no consumer's app rendering changes.
    @test repr("text/html", render_caption(CaptionSpec(; title, short, long))) ==
        "<figcaption class=\"caption\"><div class=\"caption-header\">" *
        "<span><strong>Fig 14</strong> — amplitude is shown separately.</span></div>" *
        "<details class=\"caption-long\"><summary>More</summary>" *
        "<div>Shape only: NPDE decorrelates.</div></details></figcaption>"

    @htmx struct CaptionTierApp
        @get caption_tier() = render_table((dose=[1, 2], percent=[25, 75]);
            caption=CaptionSpec(; title="Response", short="Synthetic results.",
                long="Crossing fractions are computed across subjects."),
            download=false)
    end
    route!(CaptionTierApp())
    response = dispatch(:GET, "/caption_tier"; headers=["Accept" => "text/markdown"])
    @test response.status == 200
    @test contains(HTMXObjects.HTTP.header(response, "Content-Type"), "text/markdown")
    @test contains(String(response.body), "Synthetic results. — Crossing fractions")
    @test !contains(String(response.body), "results.Crossing")
end

@testitem "caption texts replace the long-text toggle's word" tags=[:unit] begin
    using HTMXObjects

    spec = CaptionSpec(; title="Kapazität", short="Plätze je Kreis", long="Stand: Oktober 2026.")
    html(node) = repr("text/html", node)

    # No texts, or the English set, renders exactly the caption pinned above.
    @test html(render_caption(spec; texts=caption_texts())) == html(render_caption(spec))
    @test html(render_caption(spec; texts=caption_texts(:en))) == html(render_caption(spec))
    @test contains(html(render_caption(spec)), "<summary>More</summary>")

    german = html(render_caption(spec; texts=caption_texts(:de)))
    @test contains(german, "<summary>Mehr</summary>")
    @test !contains(german, "More")

    # `with_caption` passes its texts on, and a keyword replaces one word.
    figure = html(with_caption(spec, h.p("Plot."); id="kapazitaet",
        texts=caption_texts(:de; more="Erläuterung")))
    @test contains(figure, "<summary>Erläuterung</summary>")
    @test contains(figure, "id=\"kapazitaet\"")

    # Markdown never shows the toggle, in any language.
    @test HTMXObjects.to_markdown_string(render_caption(spec; texts=caption_texts(:de))) ==
        HTMXObjects.to_markdown_string(render_caption(spec))

    # refused: a mistyped locale or text name must not silently fall back to
    # English, and caption texts fill no placeholder, so `{n}` would show
    # literally; the same rules as `table_texts` (decision 0c8h2ll, option 1).
    @test_throws ArgumentError caption_texts(:fr)
    @test_throws ArgumentError caption_texts(:de; less="Weniger")
    @test_throws ArgumentError caption_texts(:de; more="Mehr {n}")
end
