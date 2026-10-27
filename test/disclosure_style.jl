using TestItemRunner

@testitem "the Pico bridge draws a disclosure as a box with the chevron before its label" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", pico_bridge())
    box = ":where(details:not(.dropdown, :has(> summary[role])))"
    # An open or clicked label keeps the closed label's colour, Pico's text
    # colour (Pico mutes the one and colours the other like a link).
    @test contains(css, box * " {\n    --pico-accordion-active-summary-color: var(--pico-accordion-close-summary-color);")
    @test contains(css, "border: var(--pico-border-width) solid var(--pico-form-element-border-color);")
    @test contains(css, box * " > :where(summary)::before {\n    content: \"\";")
    # Pico's own rules are overridden at exactly their specificity (`details
    # summary::after` is (0,0,3)), so app rules that beat Pico still win.
    @test contains(css, "details:where(:not(.dropdown, :has(> summary[role]))) > summary::after { content: none; }")
    # The caption's toggle is no longer faded.
    @test !contains(repr("text/html", caption_style()), "opacity")
    # Pages that load Pico carry it; pages without Pico do not.
    @test contains(repr("text/html", htmx(h.p("x"); pico_version="2")), "--htmxo-disclosure-padding")
    @test !contains(repr("text/html", htmx(h.p("x"))), "--htmxo-disclosure-padding")
end

@testitem "disclosures read as boxes under Pico, in light and dark" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = (e, p) => getComputedStyle(e, p), box = e => e.getBoundingClientRect();
                const det = id => document.querySelector('details#' + id + ', #' + id + ' details');
                const sum = id => det(id).querySelector(':scope > summary');
                const label = id => { const r = document.createRange(); r.selectNodeContents(sum(id)); return r.getClientRects()[0]; };
                const boxes = ['closed', 'open', 'semantic', 'caption'];
                const bodyColor = () => css(document.getElementById('para')).color;
                // Positive control: Pico is loaded and styles its own dropdown's summary.
                out.picoLoaded = String(css(sum('dropdown')).borderTopWidth !== '0px');
                out.boxed = String(boxes.every(id => css(det(id)).borderTopWidth !== '0px' && css(det(id)).borderTopStyle === 'solid'));
                out.bar = String(boxes.every(id => Number(css(sum(id)).fontWeight) >= 600 &&
                    css(sum(id)).backgroundColor !== 'rgba(0, 0, 0, 0)'));
                // The chevron sits before the label (Pico floats it to the far edge) and turns when opened.
                out.chevronBefore = String(boxes.every(id => css(sum(id), '::before').backgroundImage.startsWith('url(') &&
                    css(sum(id), '::after').content === 'none' && label(id).left - box(det(id)).left >= 30) &&
                    css(sum('closed'), '::before').transform !== css(sum('open'), '::before').transform);
                // Open content stays inside the box, below a divider.
                const inner = det('open').querySelector('p');
                out.openInside = String(css(sum('open')).borderBottomWidth !== '0px' &&
                    box(inner).left - box(det('open')).left >= 15 && box(inner).bottom < box(det('open')).bottom);
                out.captionOpaque = String(css(sum('caption')).opacity === '1');
                // Pico's dropdown, a button summary and an app's own disclosure keep their looks.
                out.dropdownKept = String(css(det('dropdown')).borderTopWidth === '0px' &&
                    css(sum('dropdown'), '::before').backgroundImage === 'none');
                out.buttonKept = String(css(det('button')).borderTopWidth === '0px');
                out.appWins = String(css(det('app')).borderTopWidth === '0px' && css(sum('app')).paddingLeft === '0px');
                // The label keeps the body text colour open, closed and focused (Pico mutes an
                // open label and colours a clicked one like a link), in both themes.
                const colours = () => boxes.every(id => css(sum(id)).color === bodyColor()) &&
                    css(det('open')).getPropertyValue('--pico-accordion-active-summary-color') ===
                    css(det('open')).getPropertyValue('--pico-color') &&
                    css(det('open')).getPropertyValue('--pico-color') !== '';
                out.lightColours = String(colours());
                const lightBorder = css(det('closed')).borderTopColor;
                document.documentElement.dataset.theme = 'dark';
                out.darkColours = String(colours() && css(det('closed')).borderTopColor !== lightBorder);
                out.done = '1';
            });
            """))
        spec = CaptionSpec(; title="Employment", short="by zone", long="The posterior mean, with central 95% intervals.")
        content = h.main(; class="container")(
            h.p(; id="para")("Body text."),
            h.details(; id="closed")(h.summary("Land use, residents and ", h.code("social"), " infrastructure"), h.p("Residents 1,331")),
            h.details(; id="open", open=true)(h.summary("Land use (open)"), h.p("Residents 1,331")),
            h.div(; id="semantic")(Raw(repr("text/html", SemanticDisclosure("Stan program", SemanticCode("stan", "model { }"))))),
            h.div(; id="caption")(with_caption(spec, h.div("plot"))),
            h.details(; id="dropdown", class="dropdown")(h.summary("Menu"), h.ul(h.li("One"))),
            h.details(; id="button")(h.summary(; role="button")("Button summary"), h.p("x")),
            h.details(; id="app", class="htmxo-test-menu")(h.summary("Menu badge"), h.p("x")),
            driver)
        # An app's own class rules, after the shell's stylesheets, as in
        # `extra_head`. Transitions are off, so a colour reads its new value
        # right after the theme switch (Pico eases the summary's colour).
        app = h.style(Raw(".htmxo-test-menu { border: 0; padding: 0; } .htmxo-test-menu > summary { padding: 0; } " *
                          "*, *::before, *::after { transition: none !important; }"))
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing, extra_head=(app,))))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1200,1000 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("pico-loaded", "boxed", "bar", "chevron-before", "open-inside", "caption-opaque",
                       "dropdown-kept", "button-kept", "app-wins", "light-colours", "dark-colours")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
