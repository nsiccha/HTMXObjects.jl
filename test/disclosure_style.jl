using TestItemRunner

@testitem "the Pico bridge draws a disclosure as a box with the chevron before its label" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", pico_bridge())
    box = ":where(details:not(.dropdown, :has(> summary[role])))"
    # An open or clicked label keeps the closed label's colour, Pico's text
    # colour (Pico mutes the one and colours the other like a link).
    @test contains(css, box * " {\n    --htmxo-disclosure-inset: var(--htmxo-disclosure-padding, 1rem);\n" *
        "    --pico-accordion-active-summary-color: var(--pico-accordion-close-summary-color);")
    @test contains(css, "border: var(--pico-border-width) solid var(--pico-form-element-border-color);")
    @test contains(css, ":where(details:not(.dropdown) > summary:not([role]))::before {\n    content: \"\";")
    # Pico's own rules are overridden at exactly their specificity (`details
    # summary::after` is (0,0,3)), so app rules that beat Pico still win.
    @test contains(css, "details:where(:not(.dropdown)) > summary:where(:not([role]))::after { content: none; }")
    # The inner spacing is the bar's and the content's, so the bar needs no
    # pulling out past a padding that a component may have changed.
    @test contains(css, ":where(details)::details-content { padding-inline: var(--htmxo-disclosure-inset); }")
    # Snag table-geometry-m-bec37646: only the box's own rule asks `:has()`.
    # A `:has()` on a rule for the summary or the content made Chrome restyle
    # everything inside a `<details>` on any change in it (the KB's roster, a
    # table in a disclosure: two restyles of ~15,500 elements per cell update).
    @test count(":has(> summary[role])", css) == 1
    @test contains(css, ":last-child:where(details:not(.dropdown) > *):where(:not(summary[role], summary[role] ~ *))")
    @test !contains(css, "margin-inline: calc(-1 * var(--htmxo-disclosure-padding")
    # Snag followed-htmxo-s-6bd66da4: the spacing variable belongs to the box it
    # is set on. It is registered as not inheriting, only the box's own rule
    # reads it, and the bar takes the box's spacing from the inset it hands down.
    @test contains(css, "@property --htmxo-disclosure-padding { syntax: \"*\"; inherits: false; }")
    @test count("var(--htmxo-disclosure-padding", css) == 1
    @test contains(css, "    padding: 0.6rem var(--htmxo-disclosure-inset);\n")
    @test contains(css, "    margin-bottom: var(--htmxo-disclosure-inset);\n")
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
                const boxes = ['closed', 'open', 'semantic'];
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
                // The bar reaches the default box's edges, and bare text sits inside the box.
                const near = (a, b) => Math.abs(a - b) <= 0.5, border = parseFloat(css(det('open')).borderLeftWidth);
                // A button disclosure's content has no inset, nor has one inside a box,
                // which inherits the box's spacing variable (snag table-geometry-m-bec37646).
                const flushLeft = id => near(box(det(id).querySelector(':scope > p')).left, box(det(id)).left);
                out.buttonFlush = String(flushLeft('button') && flushLeft('innerbutton') &&
                    box(det('innerbutton')).left - box(det('outerbutton')).left >= 15);
                out.barToEdges = String(boxes.every(id => near(box(sum(id)).left, box(det(id)).left + border) &&
                    near(box(sum(id)).right, box(det(id)).right - border)));
                const bare = document.createRange(); bare.selectNode(det('bare').lastChild);
                out.bareInside = String(near(bare.getBoundingClientRect().left - box(det('bare')).left, 16 + border));
                // Padding a component sets does not push the bar out of its box: it insets the bar.
                const inside = id => box(sum(id)).left >= box(det(id)).left && box(sum(id)).right <= box(det(id)).right;
                out.noOverhang = String(['app', 'padded', 'flush'].every(inside));
                out.paddingInsets = String(near(box(sum('padded')).left - box(det('padded')).left, 10));
                // Controls: the variable drops the inner spacing, and a nested box stays inside.
                out.flush = String(near(box(det('flush').querySelector('p')).left, box(det('flush')).left) &&
                    near(box(sum('flush')).left, box(det('flush')).left));
                out.nestedInside = String(box(det('nested')).left - box(det('outer')).left >= 15);
                // The variable is the spacing of the box it is set on: an ordinary
                // disclosure inside the flush one keeps the default 16 px on its bar
                // and content, a wrapper that is not a <details> reaches no
                // disclosure, and a rule that selects the disclosures sets theirs
                // (snag followed-htmxo-s-6bd66da4).
                const spacing = id => [css(sum(id)).paddingLeft, css(sum(id)).paddingRight,
                    css(det(id), '::details-content').paddingLeft, css(det(id), '::details-content').paddingBottom,
                    css(sum(id)).marginBottom].join(' ');
                out.nestedKeepsSpacing = String(spacing('flushnested') === '16px 16px 16px 16px 16px' &&
                    spacing('flush') === '0px 0px 0px 0px 0px');
                out.wrapperNotInherited = String(spacing('inwrapper') === '16px 16px 16px 16px 16px');
                out.regionRule = String(spacing('inregion') === '8px 8px 8px 8px 8px');
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
            h.details(; id="button", open=true)(h.summary(; role="button")("Button summary"), h.p("x")),
            h.details(; id="outerbutton", open=true)(h.summary("Box around a button disclosure"),
                h.details(; id="innerbutton", open=true)(h.summary(; role="button")("Inner button"), h.p("x"))),
            h.details(; id="app", class="htmxo-test-menu")(h.summary("Menu badge"), h.p("x")),
            h.details(; id="padded", class="htmxo-test-padded", open=true)(h.summary("Own padding"), h.p("x")),
            h.details(; id="flush", class="htmxo-test-flush", open=true)(h.summary("No inner spacing"), h.p("x"),
                h.details(; id="flushnested", open=true)(h.summary("Ordinary, inside the flush one"), h.p("y"))),
            h.div(; class="htmxo-test-wrapper")(h.details(; id="inwrapper", open=true)(h.summary("Inside a wrapper"), h.p("x"))),
            h.div(; class="htmxo-test-region")(h.details(; id="inregion", open=true)(h.summary("Inside a region"), h.p("x"))),
            h.details(; id="bare", open=true)(h.summary("Bare text"), "Text with no element around it"),
            h.details(; id="outer", open=true)(h.summary("Outer"), h.details(; id="nested", open=true)(h.summary("Nested"), h.p("x"))),
            driver)
        # An app's own class rules, after the shell's stylesheets, as in
        # `extra_head`. Transitions are off, so a colour reads its new value
        # right after the theme switch (Pico eases the summary's colour).
        app = h.style(Raw(".htmxo-test-menu { border: 0; padding: 0; } .htmxo-test-menu > summary { padding: 0; } " *
                          ".htmxo-test-padded { padding: 0.05rem 0 0.05rem 0.5rem; border: 0; border-left: 2px solid; } " *
                          ".htmxo-test-flush { --htmxo-disclosure-padding: 0; padding: 0; border: 0; } " *
                          ".htmxo-test-wrapper { --htmxo-disclosure-padding: 0; } " *
                          ".htmxo-test-region details { --htmxo-disclosure-padding: 0.5rem; } " *
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
                       "dropdown-kept", "button-kept", "app-wins", "bar-to-edges", "bare-inside", "no-overhang",
                       "padding-insets", "flush", "nested-inside", "light-colours", "dark-colours", "button-flush",
                       "nested-keeps-spacing", "wrapper-not-inherited", "region-rule")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
