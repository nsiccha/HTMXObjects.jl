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

@testitem "caption actions stay one compact row under Pico" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = e => getComputedStyle(e), box = e => e.getBoundingClientRect();
                const plain = document.getElementById('plain');
                const buttons = id => [...document.querySelectorAll('#' + id + ' .caption-action')];
                const header = id => document.querySelector('#' + id + ' .caption-header');
                const oneRow = id => new Set(buttons(id).map(b => Math.round(box(b).top))).size === 1;
                const title = id => box(header(id).firstElementChild);
                // Positive control: Pico gives an ordinary button a bottom margin.
                out.picoSizesButtons = String(css(plain).marginBottom !== '0px');
                out.compactButtons = String(['narrow', 'wide', 'csv'].flatMap(buttons).every(b =>
                    css(b).marginBottom === '0px' && box(b).height < box(plain).height));
                // A 500 px column: the actions are one row below the title.
                out.narrowRowBelow = String(oneRow('narrow') && box(buttons('narrow')[0]).top >= title('narrow').bottom);
                // A wide column keeps them beside the title, on its right.
                out.wideRowBeside = String(oneRow('wide') && box(buttons('wide')[0]).top < title('wide').bottom &&
                    Math.abs(box(buttons('wide').at(-1)).right - box(header('wide')).right) < 2);
                // A row wider than its column wraps inside it instead of overflowing.
                const tiny = document.querySelector('#tiny figure');
                out.tinyContained = String(tiny.scrollWidth <= tiny.clientWidth &&
                    document.documentElement.scrollWidth <= innerWidth);
                // An uncaptioned download header keeps its button on the right of one line.
                const csv = buttons('csv')[0];
                out.csvRight = String(Math.abs(box(csv).right - box(header('csv')).right) < 2 &&
                    Math.abs(box(header('csv')).height - box(csv).height) < 2);
                out.done = '1';
            });
            """))
        actions = Tuple(h.button("⬇ $kind"; type="button", class="outline caption-action")
                        for kind in ("CSV", "PNG", "SVG", "HTML"))
        spec = CaptionSpec(; title="Ranking of districts",
            short="Childcare places per 100 children under six, by district and independent city")
        figure(id, width) = h.div(; id, style="width: $width")(
            with_caption(spec, h.div(; style="height: 60px")("plot"); actions))
        content = h.main(; class="container")(
            figure("narrow", "500px"), figure("wide", "1100px"), figure("tiny", "120px"),
            h.div(; id="csv", style="width: 300px")(
                sortable_table(["Name", "Score"], [h.tr(h.td("a"), h.td("1"))]; download=true)),
            h.button("Plain"; type="button", id="plain"), driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing,
                extra_head=(caption_style(),))))
            profile = joinpath(directory, "profile")
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`
            dump_dom(cmd)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("pico-sizes-buttons", "compact-buttons", "narrow-row-below", "wide-row-beside",
                       "tiny-contained", "csv-right")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end

@testitem "a caption's toggle is a small control beside its header" tags=[:unit] begin
    using HTMXObjects
    # The markup keeps the native disclosure; only the style moves it, so an
    # app's own markup, the Markdown and the static export do not change.
    @test contains(repr("text/html", render_caption(CaptionSpec(; title="T", long="L"))),
        "</div><details class=\"caption-long\"><summary>More</summary><div>L</div></details></figcaption>")
    css = repr("text/html", caption_style())
    @test contains(css, "figcaption.caption > details.caption-long { display: contents; }")
    # Unlayered, because Pico's and the Pico bridge's `details` rules are: a
    # layered rule loses to them whatever its specificity.
    @test findfirst("figcaption.caption > details.caption-long", css).start > last(findfirst("@layer htmxo {", css))
    @test findfirst("figcaption.caption > details.caption-long", css).start > findfirst(".caption-actions > .caption-action", css).start
end

@testitem "a caption's toggle takes no row, and its text opens across the figure" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = (e, p) => getComputedStyle(e, p), box = e => e.getBoundingClientRect();
                const near = (a, b, d = 1.5) => Math.abs(a - b) <= d;
                const fig = id => document.querySelector('#' + id + ' figure');
                const det = id => document.querySelector('#' + id + ' details.caption-long');
                const sum = id => det(id).querySelector('summary');
                const body = id => document.querySelector('#' + id + ' .plot, #' + id + ' .table-wrap');
                const offset = id => box(body(id)).top - box(fig(id)).top;
                const button = id => document.querySelector('#' + id + ' .caption-action');
                // Positive control: an ordinary disclosure on this page is the bridge's full-width box.
                const plain = document.querySelector('#plain');
                out.boxControl = String(near(box(plain).width, box(plain.parentElement).width) && css(plain).borderTopStyle === 'solid');
                // No row of its own: beside a button of its height a closed long text moves
                // the figure by nothing, and with no button, by at most what it is taller
                // than a line of text.
                out.noRow = String(near(offset('wide'), offset('without')));
                out.noRowAlone = String(offset('table') - offset('tableWithout') >= 0 && offset('table') - offset('tableWithout') <= 4);
                // It reads as a control: as tall as the button beside it, level with it,
                // outlined, with the chevron before the label, and not the bold bar.
                out.likeButton = String(near(box(sum('wide')).height, box(button('wide')).height) &&
                    near(box(sum('wide')).top, box(button('wide')).top, 3) &&
                    box(sum('wide')).left >= box(button('wide')).right &&
                    css(sum('wide')).borderTopStyle === 'solid' && css(sum('wide')).borderTopWidth !== '0px' &&
                    css(sum('wide'), '::before').backgroundImage.startsWith('url(') &&
                    Number(css(sum('wide')).fontWeight) < 600);
                out.reachable = String((sum('wide').focus(), document.activeElement === sum('wide')));
                // A caption with no actions has the toggle at the end of the title's line.
                out.noActions = String(near(box(sum('bare')).right, box(fig('bare')).right) && near(box(sum('bare')).top, box(fig('bare')).top, 12));
                // The actions keep their one compact row in a 500 px column, below the title,
                // and the toggle stays on the title's line.
                const buttons = [...document.querySelectorAll('#narrow .caption-action')];
                const title = box(document.querySelector('#narrow .caption-header').firstElementChild);
                out.narrowRow = String(new Set(buttons.map(b => Math.round(box(b).top))).size === 1 &&
                    box(buttons[0]).top >= title.bottom && box(sum('narrow')).top < title.bottom);
                // Below 16rem plus the toggle, it moves under the header; nothing overflows.
                out.tiny = String(box(sum('tiny')).top >= box(document.querySelector('#tiny .caption-header')).bottom &&
                    fig('tiny').scrollWidth <= fig('tiny').clientWidth && document.documentElement.scrollWidth <= innerWidth);
                // Opened: the text spans the figure below the header, the figure moves below
                // the text, the toggle stays put and its chevron turns; closed again, all returns.
                const content = det('wide').querySelector('div');
                const before = { top: box(sum('wide')).top - box(fig('wide')).top, left: box(sum('wide')).left, offset: offset('wide'),
                                 chevron: css(sum('wide'), '::before').transform };
                sum('wide').click();
                out.opens = String(det('wide').open && near(box(sum('wide')).top - box(fig('wide')).top, before.top) && near(box(sum('wide')).left, before.left) &&
                    box(content).top >= box(document.querySelector('#wide .caption-header')).bottom &&
                    box(content).left - box(fig('wide')).left < 24 && box(fig('wide')).right - box(content).right < 24 &&
                    box(content).width > 0.9 * box(fig('wide')).width && box(body('wide')).top >= box(content).bottom &&
                    css(sum('wide'), '::before').transform !== before.chevron);
                sum('wide').click();
                out.closes = String(!det('wide').open && near(offset('wide'), before.offset));
                // A table's caption gets the same toggle.
                sum('table').click();
                out.table = String(box(det('table').querySelector('div')).width > 0.9 * box(fig('table')).width);
                sum('table').click();
                // Dark: the outline still shows against the page.
                const lightBorder = css(sum('wide')).borderTopColor;
                document.documentElement.dataset.theme = 'dark';
                out.dark = String(css(sum('wide')).borderTopColor !== lightBorder);
                out.done = '1';
            });
            """))
        actions = (h.button("Export"; type="button", class="outline caption-action"),)
        many = Tuple(h.button("⬇ $kind"; type="button", class="outline caption-action")
                     for kind in ("CSV", "PNG", "SVG", "HTML"))
        long = h.div(h.p("Each point is one station."), h.p("Grey marks a station without a value."))
        spec = CaptionSpec(; title="Measured values", short="Latest value per station. Grey: no value.", long)
        without = CaptionSpec(; title=spec.title, short=spec.short)
        plot = h.div(; class="plot", style="height: 60px")("plot")
        rows = (name=["a", "b"], value=[1, 2])
        tablecell(id, caption) = h.div(; id)(render_table(rows; caption, download=false))
        cell(id, width, s; acts=actions) = h.div(; id, style="width: $width")(with_caption(s, plot; actions=acts))
        content = h.main(; class="container")(
            h.div(h.details(; id="plain")(h.summary("Ordinary"), h.p("x"))),
            cell("wide", "1000px", spec), cell("without", "1000px", without),
            cell("bare", "1000px", spec; acts=()),
            cell("narrow", "500px", spec; acts=many), cell("tiny", "200px", spec),
            tablecell("table", spec), tablecell("tableWithout", without),
            driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing,
                extra_head=(h.style(Raw("*, *::before, *::after { transition: none !important; }")),))))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("box-control", "no-row", "no-row-alone", "like-button", "reachable", "no-actions", "narrow-row", "tiny", "opens", "closes", "table", "dark")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
