using TestItemRunner

@testitem "a choice among a few options is drawn as pills on every shell" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", htmxo_utility_styles())
    pill = "fieldset:not([role]) > label:has(> input[type=\"radio\"])"
    @test contains(css, pill * " {\n    position: relative;\n    display: inline-flex;")
    @test contains(css, pill * " > input[type=\"radio\"] {\n    position: absolute;")
    @test contains(css, "fieldset:not([role]) > label:has(> input[type=\"radio\"]:checked) {")
    @test contains(css, "background: var(--pico-contrast-background, CanvasText);")
    # Unlayered, like the other rules after the layer: Pico styles `label`
    # and radios unlayered, so a layered rule would lose to it.
    @test findfirst(pill, css).start > findfirst("/* Unlayered so it beats", css).start
    # Pages with and without Pico carry it.
    @test contains(repr("text/html", htmx(h.p("x"); pico_version="2")), pill)
    @test contains(repr("text/html", htmx(h.p("x"))), pill)
    # The markup the rule keys off: a fieldset whose labels wrap radios.
    html = repr("text/html", radio_group("basis", ["typical" => "Typical subject", "new" => "New subjects"];
                                         label="Prediction basis", value="typical"))
    @test contains(html, "<fieldset><legend>Prediction basis</legend><label><input type=\"radio\" name=\"basis\" value=\"typical\" checked=\"true\">Typical subject</label>")
    generated = repr("text/html", HTMXObjects._semantic_radio(:basis, "Prediction basis",
        (; options=[(value="typical", label="Typical subject"), (value="new", label="New subjects")]), "typical"))
    @test contains(generated, "<fieldset><legend>Prediction basis</legend><label><input type=\"radio\" name=\"basis\" value=\"typical\" checked=\"true\">Typical subject</label>")
end

@testitem "few-option choices read as pills in light and dark, with and without Pico" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const out = document.body.dataset, css = e => getComputedStyle(e), box = e => e.getBoundingClientRect();
                const pico = document.documentElement.dataset.pico === '1';
                const radios = id => Array.from(document.querySelectorAll('#' + id + ' input[type=radio]'));
                const pills = id => radios(id).map(r => r.parentElement);
                const probe = value => { const p = document.getElementById('probe'); p.style.backgroundColor = value; return css(p).backgroundColor; };
                const filled = () => pico ? probe('var(--pico-contrast-background)') : probe('CanvasText');
                const hidden = r => box(r).width <= 1 && css(r).opacity === '0';
                // Positive control: Pico, when loaded, draws its own checkbox and its role=group.
                const check = document.querySelector('#checks input');
                out.control = String(pico ? css(check).appearance === 'none' && box(check).width > 10 &&
                    css(document.querySelector('#joined')).display === 'inline-flex' : box(check).width > 5);
                // The hand-placed group, the generated one and a hand-written one are rows of pills,
                // their radios invisible inside them.
                const groups = ['placed', 'generated', 'handwritten'];
                out.pills = String(groups.every(id => pills(id).every(l => css(l).display === 'inline-flex' &&
                    parseFloat(css(l).borderTopLeftRadius) > 5 && css(l).borderTopStyle === 'solid') &&
                    radios(id).every(hidden) && pills(id).every(l => box(l).top === box(pills(id)[0]).top)));
                // The chosen pill is filled in the text colour, never Pico's azure; the others are not filled.
                const chosenFilled = id => radios(id).every(r => r.checked ?
                    css(r.parentElement).backgroundColor === filled() : css(r.parentElement).backgroundColor === 'rgba(0, 0, 0, 0)');
                out.chosen = String(groups.every(chosenFilled) &&
                    (!pico || css(pills('placed')[0]).backgroundColor !== probe('var(--pico-primary-background)')));
                // Tab reaches the radio, and its pill shows the focus ring.
                const third = radios('placed')[2];
                third.focus();
                out.focus = String(document.activeElement === third &&
                    css(third.parentElement).outlineStyle === 'solid' && css(third.parentElement).outlineWidth === '2px' &&
                    css(pills('placed')[0]).outlineStyle === 'none');
                // Choosing a pill checks its radio, moves the fill and submits with the form.
                pills('placed')[1].click();
                out.choose = String(radios('placed')[1].checked && chosenFilled('placed') &&
                    new FormData(document.getElementById('form')).get('basis') === 'new');
                // A disabled option is faded and cannot be chosen.
                const off = radios('disabled')[1];
                off.parentElement.click();
                out.disabled = String(css(off.parentElement).opacity === '0.5' && !off.checked && radios('disabled')[0].checked);
                // Checkboxes, a role=group bar and option cards keep their radios and boxes.
                out.kept = String(box(check).width > 5 && !hidden(document.querySelector('#joined input')) &&
                    !hidden(document.querySelector('#cards input')));
                // Long labels wrap onto further rows inside a narrow column.
                const narrow = pills('narrow');
                out.wraps = String(box(narrow[narrow.length - 1]).top > box(narrow[0]).top &&
                    narrow.every(l => box(l).right <= box(document.getElementById('narrow')).right + 1));
                if (pico) {
                    const light = css(pills('placed')[1]).backgroundColor, lightText = css(pills('placed')[1]).color;
                    document.documentElement.dataset.theme = 'dark';
                    out.dark = String(chosenFilled('placed') && css(pills('placed')[1]).backgroundColor !== light &&
                        css(pills('placed')[1]).color !== lightText);
                } else {
                    out.dark = 'true';
                }
                out.done = '1';
            });
            """))
        content = h.main(; class="container")(
            h.form(; id="form")(
                h.div(; id="placed")(radio_group("basis", ["typical" => "Typical subject", "new" => "New subjects", "both" => "Both"];
                                                 label="Prediction basis", value="typical")),
                h.div(; id="generated")(HTMXObjects._semantic_radio(:diet, "Diet",
                    (; options=[(value=i, label=string(i)) for i in 1:4]), 2)),
                h.fieldset(; id="handwritten")(h.legend("Sex"),
                    h.label(h.input(; type="radio", name="sex", value="f"), " female"),
                    h.label(h.input(; type="radio", name="sex", value="m", checked="true"), " male")),
                h.fieldset(; id="disabled")(h.legend("Disabled"),
                    h.label(h.input(; type="radio", name="d", value="a", checked="true"), "A"),
                    h.label(h.input(; type="radio", name="d", value="b", disabled="true"), "B")),
                h.div(; id="narrow")(radio_group("flag", ["g" => "g: gültig", "u" => "u: vom Land als unplausibel, aber korrekt markiert",
                                                          "f" => "f: fehlerhaft, wird ersetzt", "x" => "x: fehlt"]; value="u")),
                h.fieldset(; id="checks")(h.legend("Checks"), h.label(h.input(; type="checkbox", name="c"), "One")),
                h.fieldset(; id="joined", role="group")(h.label(h.input(; type="radio", name="j", value="a"), "A"),
                                                        h.label(h.input(; type="radio", name="j", value="b"), "B")),
                h.fieldset(; id="cards", class="htmxo-semantic-cards")(h.legend("Cards"),
                    h.div(; class="htmxo-semantic-card")(h.input(; id="card-a", type="radio", name="card", value="a"),
                                                          h.label("A"; NamedTuple{(:for,)}(("card-a",))...)))),
            h.div(; id="probe")("probe"),
            driver)
        # A narrow column for the wrapping check; transitions off so colours read
        # their new values right after the theme switch.
        app = h.style(Raw("#narrow { width: 18rem; } *, *::before, *::after { transition: none !important; }"))
        for pico in (true, false)
            marked = h.script(Raw(pico ? "document.documentElement.dataset.pico = '1';" : ""))
            dom = mktempdir() do directory
                copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
                fixture = joinpath(directory, "page.html")
                write(fixture, repr("text/html", htmx(content; assets="vendor",
                    pico_version=pico ? HTMXObjects._PICO_VERSION : nothing, htmx_version=nothing,
                    hyperscript_version=nothing, preload_version=nothing, extra_head=(app, marked))))
                profile = joinpath(directory, "profile")
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1200,1400 --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`)
            end
            @test contains(dom, "data-done=\"1\"")
            for marker in ("control", "pills", "chosen", "focus", "choose", "disabled", "kept", "wraps", "dark")
                @test contains(dom, "data-$marker=\"true\"")
            end
        end
    end
end
