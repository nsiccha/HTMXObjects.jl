using TestItemRunner

# A number input declared with a range (`@options(x) = number_domain(…)` or a
# bare interval) is checked against it and drawn as a slider with a number
# field (snag semantic-numeric-de090127, user decision 1h0dqqn). Before, an
# interval domain was dropped: any number was accepted and the field had no
# bounds.
@testmodule NumberDomainFixtures begin
    using HTMXObjects, IntervalSets
    export Shielding, Scaling, Fitted, number_label

    @htmx struct Shielding
        "Attenuation per mm of snow water"
        @param attenuation::Float64 = 0.004
        @options(attenuation) = number_domain(0.001 .. 0.015; log=true, digits=4)
        """
        Snow density

        Mass of a cubic metre of snow.
        """
        @param density::Float64 = 300.0
        @options(density) = number_domain(50, 600; step=10, unit="kg/m³")
        "Share"
        @param share::Float64 = 0.5
        @options(share) = Interval{:open,:closed}(0, 1)
        "Layers"
        @param layers::Int = 3
        @options(layers) = 1 .. 10
        "Depth"
        @param depth::Float64 = 1.0
        @options(depth) = 0 .. Inf
        "Transmission"
        @get curve() = h.p(join(string.((attenuation, density, share, layers, depth)), ":"); class="result")
        @post set_share() = string("share:", share)
        @get index() = semantic_app(__self__; presentation=:tabs, select=entry -> entry.name === :curve)
    end

    @htmx struct Scaling
        """
        Scale

        # Arguments
        - `factor`: Factor
        """
        @get scaled(; factor::Float64=1.0) = string("scaled:", factor)
        @options(factor) = number_domain(0.5 .. 2; log=true)
    end

    # A fitted default with more digits than the field shows (snag
    # numeric-display-445153c6: Portfolio's snow attenuation).
    @htmx struct Fitted
        "Attenuation per mm of snow water"
        @param attenuation::Float64 = 0.003035586062774531
        @options(attenuation) = number_domain(0.001 .. 0.015; log=true, digits=4)
        "Transmission"
        @get curve() = h.p(string(attenuation); class="result")
        @get index() = semantic_app(__self__; presentation=:tabs, select=entry -> entry.name === :curve)
    end

    # The generated control (`<label data-htmxo-number>`) whose field is `name`.
    function number_label(html, name)
        for m in eachmatch(r"<label[^>]*data-htmxo-number=.*?</label>"s, html)
            contains(m.match, "name=\"$(name)\"") && return m.match
        end
        nothing
    end
end

@testitem "number_domain declares an interval with how a reader picks a number" setup=[NumberDomainFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, IntervalSets

    d = number_domain(0.001 .. 0.015; log=true, digits=4)
    @test 0.004 in d && 0.001 in d && 0.015 in d
    @test !(0.5 in d) && !(-3 in d) && !(NaN in d) && !("0.004" in d) && !(nothing in d)
    @test repr(d) == "number_domain(0.001 .. 0.015; log=true, digits=4)"
    @test number_domain(1, 10) isa NumberDomain
    @test 10 in number_domain(1, 10) && !(11 in number_domain(1, 10))
    # It is no list of options: DynamicObjects never enumerates it.
    @test HTMXObjects.DynamicObjects.option_records(d) === nothing
    @test HTMXObjects.DynamicObjects.option_records(0 .. 1) === nothing

    @test number_record(d) == (lower=0.001, upper=0.015, closed=(true, true), log=true,
                               step=nothing, digits=4, unit=nothing)
    @test number_record(0 .. 1) == (lower=0, upper=1, closed=(true, true), log=false,
                                    step=nothing, digits=nothing, unit=nothing)
    @test number_record(number_domain(0 .. Inf; unit="m")).upper === nothing
    @test number_record(Interval{:open,:closed}(0, 1)).closed == (false, true)
    @test number_record([1, 2, 3]) === nothing
    @test number_record(Float64) === nothing

    @test_throws ArgumentError number_domain(0 .. 1; log=true)
    @test_throws ArgumentError number_domain(1 .. Inf; log=true)
    @test_throws ArgumentError number_domain(2 .. 1)
    @test_throws ArgumentError number_domain(0 .. 1; step=0)
    @test_throws ArgumentError number_domain(0 .. 1; digits=-1)
    @test_throws ArgumentError number_domain(0 .. 1; unit=:m)

    # A refusal reads the range as a comparison.
    text = HTMXObjects._number_range_text
    @test text(d, :attenuation) == "0.001 ≤ attenuation ≤ 0.015"
    @test text(HTMXObjects._number_domain(Interval{:open,:closed}(0, 1)), :share) == "0 < share ≤ 1"
    @test text(HTMXObjects._number_domain(0 .. Inf), :depth) == "depth ≥ 0"
    @test text(HTMXObjects._number_domain(-Inf .. 5), :x) == "x ≤ 5"

    # The slider's position for a value: evenly in ratio for a log domain.
    position = HTMXObjects._number_slider_position
    @test position(d, 0.001) == 0 && position(d, 0.015) == 500
    @test position(d, sqrt(0.001 * 0.015)) == 250
    @test position(d, 0.0123) == 463
    @test position(HTMXObjects._number_domain(Interval{:open,:closed}(0, 1)), 0.0) == 1
    @test position(d, nothing) == 0
end

@testitem "an interval or number_domain @options is enforced and drawn as a slider with a field" setup=[NumberDomainFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(Shielding(); operation_policy=:blocking)
    body(r) = String(copy(r.body isa AbstractString ? Vector{UInt8}(r.body) : r.body))
    GET(target) = dispatch(:GET, target)

    ok = GET("/curve?attenuation=0.0123&density=310&share=0.25&layers=4&depth=2.5")
    @test ok.status == 200
    @test contains(body(ok), "0.0123:310.0:0.25:4:2.5")
    for (target, message) in (
            "/curve?attenuation=0.5" => "allowed values: 0.001 ≤ attenuation ≤ 0.015",
            "/curve?attenuation=-3" => "allowed values: 0.001 ≤ attenuation ≤ 0.015",
            "/curve?density=700" => "allowed values: 50 ≤ density ≤ 600",
            "/curve?share=0" => "allowed values: 0 &lt; share ≤ 1",
            "/curve?layers=11" => "allowed values: 1 ≤ layers ≤ 10",
            "/curve?depth=-1" => "allowed values: depth ≥ 0")
        r = GET(target)
        @test r.status == 400
        @test contains(body(r), message)
        # The fault is shown at its field.
        @test contains(body(r), "data-htmxo-param=\"$(first(split(split(target, '?')[2], '=')))\"")
    end
    # A JSON body is checked as a form is.
    json = dispatch(:POST, "/set_share"; headers=["Content-Type" => "application/json"], body=Vector{UInt8}("{\"share\": 1.5}"))
    @test json.status == 400
    @test contains(body(json), "0 &lt; share ≤ 1")
    @test body(dispatch(:POST, "/set_share"; headers=["Content-Type" => "application/json"],
                        body=Vector{UInt8}("{\"share\": 0.75}"))) == "share:0.75"

    page = body(GET("/"))
    attenuation = number_label(page, "attenuation")
    @test attenuation !== nothing
    @test contains(attenuation, "<input type=\"number\" name=\"attenuation\" value=\"0.004\" min=\"0.001\" max=\"0.015\" step=\"any\" data-htmxo-number-field=\"\">")
    @test contains(attenuation, "<input type=\"range\" min=\"0\" max=\"500\" step=\"1\" value=\"256\" data-htmxo-number-slider=\"\" aria-label=\"Attenuation per mm of snow water\">")
    @test contains(attenuation, "&quot;log&quot;:true") && contains(attenuation, "&quot;digits&quot;:4")
    # `digits` rounds the text shown over the field, never the field's value
    # (snag numeric-display-445153c6).
    @test contains(attenuation, "<span class=\"htmxo-number-value\" data-htmxo-number-shown=\"\"><input type=\"number\" name=\"attenuation\" value=\"0.004\"")
    @test contains(attenuation, "<span class=\"htmxo-number-shown\" aria-hidden=\"true\">0.0040</span></span>")
    # The field comes before the slider: the label names the field.
    @test findfirst("type=\"number\"", attenuation)[1] < findfirst("type=\"range\"", attenuation)[1]
    density = number_label(page, "density")
    @test contains(density, "<span class=\"htmxo-number-unit\">kg/m³</span>")
    # The field and its unit are one entry, the slider after it: a column too
    # narrow for the row wraps the slider, never the unit alone (snag
    # number-control-u-68445236).
    @test contains(density, "<span class=\"htmxo-number\"><span class=\"htmxo-number-entry\"><input type=\"number\" name=\"density\"")
    @test contains(density, "kg/m³</span></span><input type=\"range\"")
    @test contains(attenuation, "<span class=\"htmxo-number-entry\"><span class=\"htmxo-number-value\"")
    # The step is the slider's grid (the record), not the field's: the field
    # takes any number in the interval, as the server does, so a number typed
    # between grid values is valid in the browser (snag use-number-domai-f74b4f09).
    @test contains(density, "<input type=\"number\" name=\"density\" value=\"300\" min=\"50\" max=\"600\" step=\"any\"")
    @test contains(density, "&quot;step&quot;:10") && !contains(density, "step=\"10\"")
    between = GET("/curve?density=273")
    @test between.status == 200 && contains(body(between), "0.004:273.0:")
    @test contains(number_label(body(GET("/?density=273")), "density"), "value=\"273\"")
    # Without `digits` the field stands alone and shows its value as it is.
    @test !contains(density, "htmxo-number-value") && !contains(density, "htmxo-number-shown")
    # Its help text describes the field and the slider.
    @test count("aria-describedby=", density) == 2
    @test contains(page, "Mass of a cubic metre of snow.")
    share = number_label(page, "share")
    @test contains(share, "type=\"range\" min=\"1\" max=\"500\"")
    # A whole-number input steps by one; a range without an upper end has no slider.
    layers = number_label(page, "layers")
    @test contains(layers, "step=\"1\" data-htmxo-number-field") && contains(layers, "&quot;step&quot;:1")
    depth = number_label(page, "depth")
    @test contains(depth, "min=\"0\"") && !contains(depth, "max=") && !contains(depth, "type=\"range\"")

    # A number in range is kept; one out of range recovers the default.
    kept = body(GET("/?attenuation=0.0123&density=310"))
    @test contains(number_label(kept, "attenuation"), "value=\"0.0123\"")
    @test contains(number_label(kept, "attenuation"), "aria-hidden=\"true\">0.0123</span>")
    @test contains(number_label(kept, "attenuation"), "type=\"range\" min=\"0\" max=\"500\" step=\"1\" value=\"463\"")
    @test contains(number_label(kept, "density"), "value=\"310\"")
    recovered = body(GET("/?attenuation=0.5"))
    @test contains(number_label(recovered, "attenuation"), "value=\"0.004\"")

    # An operation argument with a range: its form and its check.
    route!(Scaling(); operation_policy=:blocking)
    form = repr("text/html", semantic_app(Scaling()))
    factor = number_label(form, "factor")
    @test factor !== nothing && contains(factor, "Factor") && contains(factor, "max=\"2\"")
    @test GET("/scaled?factor=1.5").status == 200
    refused = GET("/scaled?factor=3")
    @test refused.status == 400 && contains(body(refused), "0.5 ≤ factor ≤ 2")

    # The same control placed by hand.
    hand = repr("text/html", ninput((; x=2.5); domain=number_domain(1, 10; unit="s"), label="Time"))
    @test contains(hand, "name=\"x\" value=\"2.5\" min=\"1\" max=\"10\" step=\"any\"")
    @test contains(hand, "<span class=\"htmxo-number-unit\">s</span>")
    # A whole-number input with a coarser grid: the field takes whole numbers,
    # the slider and the arrow keys the grid.
    whole = repr("text/html", HTMXObjects._number_control(:n, "N", number_domain(0, 100; step=5), 20; integer=true))
    @test contains(whole, "step=\"1\" data-htmxo-number-field") && contains(whole, "&quot;step&quot;:5")
    @test_throws ArgumentError ninput((; x=2.5); domain=[1, 2])
    @test_throws ArgumentError ninput((; x=2.5); domain=number_domain(1, 10), max=5)
    # A fitted default keeps every digit in the field and shows `digits` of
    # them; a whole number takes the decimals too; no value shows nothing.
    fitted = repr("text/html", ninput((; a=0.003035586062774531);
        domain=number_domain(0.001, 0.015; log=true, digits=4), label="Attenuation"))
    @test contains(fitted, "name=\"a\" value=\"0.003035586062774531\"")
    @test contains(fitted, "<span class=\"htmxo-number-shown\" aria-hidden=\"true\">0.0030</span>")
    @test contains(repr("text/html", ninput((; n=3); domain=number_domain(0, 10; digits=2))),
                   "aria-hidden=\"true\">3.00</span>")
    @test contains(repr("text/html", ninput((; n=1234.5); domain=number_domain(0, 1e4; digits=1))),
                   "aria-hidden=\"true\">1,234.5</span>")
    empty = repr("text/html", HTMXObjects._number_control(:x, "X", number_domain(0, 1; digits=2), nothing))
    @test contains(empty, "<span class=\"htmxo-number-value\"><input") &&
          contains(empty, "aria-hidden=\"true\"></span>")
    @test number_domain(0, 1; digits=10).digits == 10
    @test_throws ArgumentError number_domain(0, 1; digits=11)
    # Every page carries the script that keeps them together.
    @test contains(repr("text/html", htmx(h.p("x"))), "__htmxoNumberControl")
end

@testitem "a number slider writes its field, and the field moves the slider" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
          const out = document.body.dataset, form = document.querySelector('form');
          const field = n => form.querySelector('input[name="' + n + '"]');
          const slider = n => field(n).closest('[data-htmxo-number]').querySelector('input[type="range"]');
          const seen = [];
          form.addEventListener('input', e => seen.push('input:' + (e.target.name || 'slider')));
          form.addEventListener('change', e => seen.push('change:' + (e.target.name || 'slider')));
          function drag(n, position) {
            const s = slider(n);
            s.value = String(position);
            s.dispatchEvent(new Event('input', {bubbles: true}));
            s.dispatchEvent(new Event('change', {bubbles: true}));
            return field(n).value;
          }
          try {
            // Log domain: its ends and the middle in ratio, to three
            // significant digits; `digits` rounds only the text shown.
            out.lower = String(drag('attenuation', 0) === '0.001');
            out.upper = String(drag('attenuation', 500) === '0.015');
            out.middle = String(drag('attenuation', 250) === '0.00387');
            // The form sees each change once, from the field.
            out.events = String(seen.join() === 'input:attenuation,change:attenuation,input:attenuation,change:attenuation,input:attenuation,change:attenuation');
            // A step grid counted from the lower bound; three significant digits without one.
            out.step = String(drag('density', 227) === '300' && drag('density', 100) === '160');
            out.digits = String(drag('share', 1) === '0.002' && drag('share', 500) === '1');
            // Typing in the field moves the slider.
            field('attenuation').value = '0.0123';
            field('attenuation').dispatchEvent(new Event('input', {bubbles: true}));
            out.typed = String(slider('attenuation').value === '463');
            // Only the fields are submitted, and the label names the field.
            const sent = Array.from(new FormData(form).keys()).join();
            out.sent = String(sent === 'attenuation,density,share');
            out.labelled = String(field('attenuation').labels[0].control === field('attenuation'));
            out.valid = String(form.checkValidity());
            // A number typed between the grid's values is valid and kept as
            // typed (snag use-number-domai-f74b4f09: as the field's own step
            // the grid made it `stepMismatch`, so results kept the last
            // valid values).
            field('density').value = '273';
            field('density').dispatchEvent(new Event('input', {bubbles: true}));
            out.between = String(form.checkValidity() && field('density').value === '273' &&
              slider('density').value === String(Math.round((273 - 50) / 550 * 500)));
            // The arrow keys step along the grid: to the next grid value above
            // or below, announced as `input` then `change`; none past an end.
            function press(n, key) {
              seen.length = 0;
              const sent = field(n).dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true}));
              return [field(n).value, sent, seen.join()].join('|');
            }
            out.arrows = String(press('density', 'ArrowUp') === '280|false|input:density,change:density' &&
              slider('density').value === String(Math.round((280 - 50) / 550 * 500)) &&
              press('density', 'ArrowUp') === '290|false|input:density,change:density');
            field('density').value = '273';
            out.down = String(press('density', 'ArrowDown') === '270|false|input:density,change:density');
            field('density').value = '600';
            out.end = String(press('density', 'ArrowUp') === '600|false|' &&
              field('density').getAttribute('step') === 'any');
            // A domain without a step leaves the keys to the browser.
            out.free = String(press('attenuation', 'ArrowUp') === '0.0123|true|');
          } catch (error) { out.error = String(error); }
          out.done = '1';
        });
        """))
        content = h.form(
            ninput((; attenuation=0.004); domain=number_domain(0.001, 0.015; log=true, digits=4)),
            ninput((; density=300.0); domain=number_domain(50, 600; step=10, unit="kg/m³")),
            ninput((; share=0.5); domain=HTMXObjects.IntervalSets.Interval{:open,:closed}(0, 1)),
            driver)
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; pico_version=nothing,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing)))
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=3000 --dump-dom --user-data-dir=$(joinpath(directory, "profile")) file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"") && !contains(dom, "data-error=")
        for marker in ("lower", "upper", "middle", "events", "step", "digits", "typed", "sent", "labelled", "valid",
                       "between", "arrows", "down", "end", "free")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end

@testitem "a number field with digits shows its value rounded and keeps it exact" setup=[ChromeDump] tags=[:unit, :browser] begin
    # Snag numeric-display-445153c6: Portfolio's fitted attenuation default
    # 0.003035586062774531 with `digits=4` showed clipped in the field.
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
          const out = document.body.dataset, form = document.querySelector('form');
          const field = form.querySelector('input[name="fitted"]');
          const box = field.parentNode, text = box.querySelector('.htmxo-number-shown');
          const slider = field.closest('[data-htmxo-number]').querySelector('input[type="range"]');
          const shown = () => box.hasAttribute('data-htmxo-number-shown') ? text.textContent : null;
          const hidden = () => getComputedStyle(field).color === 'rgba(0, 0, 0, 0)' &&
            getComputedStyle(text).display === 'flex';
          const plain = () => getComputedStyle(field).color !== 'rgba(0, 0, 0, 0)' &&
            getComputedStyle(text).display === 'none';
          const sent = () => new FormData(form).get('fitted');
          function drag(position) {
            slider.value = String(position);
            slider.dispatchEvent(new Event('input', {bubbles: true}));
            slider.dispatchEvent(new Event('change', {bubbles: true}));
          }
          try {
            out.marked = String(document.documentElement.hasAttribute('data-htmxo-number-display'));
            // At rest: the exact value in the field, four decimals over it.
            out.initial = String(field.value === '0.003035586062774531' && shown() === '0.0030' && hidden());
            const f = field.getBoundingClientRect(), t = text.getBoundingClientRect();
            out.over = String(Math.abs(f.left - t.left) < 1 && Math.abs(f.top - t.top) < 1 &&
              Math.abs(f.width - t.width) < 1 && Math.abs(f.height - t.height) < 1);
            out.rects = [f.left, f.top, f.width, f.height, t.left, t.top, t.width, t.height].map(Math.round).join(',');
            // The text starts where the field writes its own, in its font.
            const fs = getComputedStyle(field), ts = getComputedStyle(text), px = s => parseFloat(s);
            out.aligned = String(Math.abs(px(ts.paddingLeft) - px(fs.paddingLeft) - px(fs.borderLeftWidth)) < 0.5 &&
              ts.fontSize === fs.fontSize && ts.fontFamily === fs.fontFamily);
            out.untouched = String(sent() === '0.003035586062774531');
            // Held slider: three significant digits in the field, four decimals shown.
            drag(250);
            out.slider = String(field.value === '0.00387' && shown() === '0.0039');
            drag(0);
            out.lower = String(field.value === '0.001' && shown() === '0.0010');
            // A typed number is kept and submitted as typed, shown rounded.
            field.value = '0.00312345';
            field.dispatchEvent(new Event('input', {bubbles: true}));
            out.typed = String(shown() === '0.0031' && field.value === '0.00312345' && sent() === '0.00312345');
            // Editing shows the field's own text.
            field.focus();
            out.focused = String(field.matches(':focus') && plain());
            field.blur();
            out.blurred = String(hidden());
            // No number: the field shows itself; a change brings the text back.
            field.value = '';
            field.dispatchEvent(new Event('input', {bubbles: true}));
            out.empty = String(shown() === null && plain());
            field.value = '0.004';
            field.dispatchEvent(new Event('change', {bubbles: true}));
            out.changed = String(shown() === '0.0040' && hidden());
            // A value the browser fills in again unannounced is shown on pageshow.
            field.value = '0.0123';
            window.dispatchEvent(new Event('pageshow'));
            out.restored = String(shown() === '0.0123');
            // Without the script's mark the field shows its own text.
            document.documentElement.removeAttribute('data-htmxo-number-display');
            out.unmarked = String(plain());
            document.documentElement.setAttribute('data-htmxo-number-display', '');
            out.valid = String(form.checkValidity());
          } catch (error) { out.error = String(error); }
          out.done = '1';
        });
        """))
        content = h.form(
            ninput((; fitted=0.003035586062774531); domain=number_domain(0.001, 0.015; log=true, digits=4),
                   label="Attenuation"),
            driver)
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; pico_version=nothing,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing)))
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=3000 --dump-dom --user-data-dir=$(joinpath(directory, "profile")) file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"") && !contains(dom, "data-error=")
        for marker in ("marked", "initial", "over", "aligned", "untouched", "slider", "lower", "typed", "focused",
                       "blurred", "empty", "changed", "restored", "unmarked", "valid")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end

@testitem "a number control stays inside a column narrower than its row" setup=[ChromeDump] tags=[:unit, :browser] begin
    # Snag number-control-u-68445236 (Portfolio's dose picture): in the 12rem
    # sidebar of a :tabs page the slider (at least 5rem), the 7rem field and
    # the unit stayed on one row 230 px wide in a 176 px column, so the unit
    # was drawn up to 41 px into the result column and the field 8 px past
    # the divider.
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # One line per control: its column, its index there, whether every
        # part lies inside the column's content box, whether the slider has a
        # line of its own, whether the unit shares the field's line, and
        # whether the whole control is one line.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const out = [];
            const overlap = (a, b) => a.top < b.bottom && a.bottom > b.top;
            for (const column of document.querySelectorAll('aside, [data-probe]')) {
                const name = column.dataset.probe || 'sidebar', cs = getComputedStyle(column);
                const c = column.getBoundingClientRect();
                const left = c.left + parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
                const right = c.right - parseFloat(cs.paddingRight) - parseFloat(cs.borderRightWidth);
                column.querySelectorAll('.htmxo-number').forEach((row, i) => {
                    const field = row.querySelector('input[data-htmxo-number-field]');
                    const parts = [field.closest('.htmxo-number-value') || field,
                        row.querySelector('input[data-htmxo-number-slider]'),
                        row.querySelector('.htmxo-number-unit')].map(el => el && el.getBoundingClientRect());
                    const [f, s, u] = parts;
                    const inside = parts.every(r => !r || (r.left >= left - 0.5 && r.right <= right + 0.5));
                    out.push(name + ' ' + i + ': ' + [inside, s ? !overlap(s, f) : '-', u ? overlap(u, f) : '-',
                        parts.every(r => !r || overlap(r, f))].join(' '));
                });
            }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = out.join('\n');
            document.body.appendChild(result);
        });
        """))
        controls() = (
            ninput((; dose=200.0); domain=number_domain(50, 400; step=10, digits=0, unit="mg"), label="Oral dose"),
            ninput((; clearance=10.0); domain=number_domain(5, 20; step=0.5, digits=1, unit="L/h"), label="Typical clearance"),
            ninput((; noise=0.2); domain=number_domain(0.05, 0.5; step=0.05, digits=2), label="Log-scale measurement SD"),
            ninput((; per_kg=2.0); domain=number_domain(1, 10; unit="mg·h/L per kg body weight"), label="Exposure per kilogram"),
            ninput((; depth=1.0); domain=number_domain(0, Inf; unit="mm"), label="Sampling depth"))
        content = h.div(
            app_layout(h.aside(controls()...), h.p("Result")),
            h.div(; class="probe-narrow", data_probe="narrow")(controls()...),
            h.div(; class="probe-wide", data_probe="wide")(controls()...))
        app_css = h.style(Raw(".probe-narrow { width: 8rem; } .probe-wide { width: 36rem; }"))
        page = repr("text/html", htmx(content, driver; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION,
            htmx_version=nothing, hyperscript_version=nothing, feedback=false, compose=false, overlay=false,
            extra_head=(app_css,)))
        # The control is the page whose rows neither wrap nor shrink, as
        # before the fix: the probe must see the overflow there, or it cannot
        # tell the two apart.
        rules = r"\.htmxo-number \{.*?\.htmxo-number-entry > \.htmxo-number-value \{[^}]*\}"s
        @test occursin(rules, page)
        control = replace(page, rules => r -> replace(r, "flex-wrap: wrap; " => "", "min-width: 0; " => ""))
        @test control != page
        pages = Dict("/" => page, "/control" => control,
                     "/vendor/pico.min.css" => read(HTMXObjects._vendor_file(:pico), String))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => endswith(path, ".css") ? "text/css" : "text/html"], pages[path])
        end
        measure(path) = mktempdir() do profile
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1600,900 --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? Dict{String,Vector{String}}() :
                Dict(String(k) => split(v) for (k, v) in (split(l, ": "; limit=2) for l in split(checks[1], '\n')))
        end
        try
            m = measure("/")
            # "<inside> <slider on its own line> <unit beside the field> <one line>"
            @test length(m) == 15
            for column in ("sidebar", "narrow", "wide"), i in 0:4
                @test m["$column $i"][1] == "true"
            end
            # In the sidebar the slider spans the column above the field, and a
            # short unit stays beside its field; a long one goes under it.
            for i in 0:3
                @test m["sidebar $i"][2] == "true"
            end
            @test m["sidebar 0"][3] == "true" && m["sidebar 1"][3] == "true"
            @test m["sidebar 3"][3] == "false"
            # A control without a slider keeps its unit beside the field.
            @test m["sidebar 4"][2:4] == ["-", "true", "true"]
            # A column wide enough keeps every control on one line.
            for i in 0:4
                @test m["wide $i"][4] == "true"
            end
            # Without the wrap, the sidebar's rows pass the column.
            c = measure("/control")
            @test length(c) == 15
            @test count(i -> c["sidebar $i"][1] == "false", 0:4) >= 4
        finally
            close(server)
        end
    end
end

@testitem "a number field with digits on a live tabs page keeps its exact default through the address and Reset" setup=[NumberDomainFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires Chrome")
        route!(Fitted(); operation_policy=:blocking)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          function check(ok, label) { if (!ok) throw new Error(label); }
          async function until(check, label) {
            const end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await sleep(25);
            }
          }
          const result = () => (document.querySelector('.result') || {}).textContent;
          const field = () => document.querySelector('input[name="attenuation"]');
          const text = () => {
            const box = field().parentNode;
            return box.hasAttribute('data-htmxo-number-shown') ? box.querySelector('.htmxo-number-shown').textContent : null;
          };
          const slider = () => field().closest('[data-htmxo-number]').querySelector('input[type="range"]');
          const named = () => new URL(location.href).searchParams.get('attenuation');
          const exact = '0.003035586062774531';
          try {
            // Untouched: the exact default computes, shows rounded, and the
            // address names nothing.
            await until(() => result() === exact, 'initial result');
            check(field().value === exact && text() === '0.0030', 'initial field ' + field().value + ' / ' + text());
            check(named() === null, 'address names the default');
            const s = slider();
            s.value = '500';
            s.dispatchEvent(new Event('input', {bubbles: true}));
            s.dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => result() === '0.015', 'result follows the slider');
            await until(() => named() === '0.015', 'address keeps the value');
            check(text() === '0.0150', 'slider value shown ' + text());
            // Reset writes the exact default back, and the address drops it.
            document.querySelector('.htmxo-semantic-reset').click();
            await until(() => result() === exact, 'result after Reset');
            await until(() => named() === null, 'address after Reset');
            check(field().value === exact && text() === '0.0030', 'field after Reset ' + field().value + ' / ' + text());
            await fetch('/complete?status=passed');
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once:true});
        """))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                content = String(dispatch(:GET, req.target; headers=["HX-Request" => "true"]).body)
                return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html",
                    htmx(Raw(content), driver; assets="/test-assets", sse_version=nothing,
                        ws_version=nothing, preload_version=nothing, pico_version=nothing,
                        feedback=false, compose=false, overlay=false)))
            end
            haskey(assets, path) && return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            dispatch(req.method, req.target; headers=collect(req.headers), body=HTMXObjects._request_body_bytes(req))
        end
        try
            mktempdir() do profile
                process = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=joinpath(profile, "browser.log")); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 120; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : read(joinpath(profile, "browser.log"), String)
                    @test outcome == "/complete?status=passed"
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        finally
            close(server)
        end
    end
end

@testitem "a number slider on a live tabs page refreshes the result and the address" setup=[NumberDomainFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires Chrome")
        route!(Shielding(); operation_policy=:blocking)
        assets = Dict("/test-assets/htmx.min.js" => read(HTMXObjects._vendor_file(:htmx), String),
            "/test-assets/_hyperscript.min.js" => read(HTMXObjects._vendor_file(:hyperscript), String))
        receipt = Channel{String}(1)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          function check(ok, label) { if (!ok) throw new Error(label); }
          async function until(check, label) {
            const end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() > end) throw new Error('timeout: ' + label);
              await sleep(25);
            }
          }
          const shown = () => (document.querySelector('.result') || {}).textContent;
          const field = n => document.querySelector('input[name="' + n + '"]');
          const slider = n => field(n).closest('[data-htmxo-number]').querySelector('input[type="range"]');
          try {
            if (sessionStorage.getItem('reloaded')) {
              await until(() => shown() === '0.015:273.0:0.5:3:1.0', 'result after reload');
              check(field('attenuation').value === '0.015' && slider('attenuation').value === '500', 'controls after reload');
              check(field('density').value === '273', 'typed density after reload');
              await fetch('/complete?status=passed'); return;
            }
            await until(() => shown() === '0.004:300.0:0.5:3:1.0', 'initial result');
            const s = slider('attenuation');
            s.value = '500';
            s.dispatchEvent(new Event('input', {bubbles: true}));
            s.dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => shown() === '0.015:300.0:0.5:3:1.0', 'result follows the slider');
            await until(() => new URL(location.href).searchParams.get('attenuation') === '0.015', 'address keeps the value');
            // A density typed between the slider's grid values (`step=10`)
            // refreshes the result and the address with the typed number
            // (snag use-number-domai-f74b4f09).
            field('density').value = '273';
            field('density').dispatchEvent(new Event('input', {bubbles: true}));
            field('density').dispatchEvent(new Event('change', {bubbles: true}));
            await until(() => shown() === '0.015:273.0:0.5:3:1.0', 'result follows a number between grid values');
            await until(() => new URL(location.href).searchParams.get('density') === '273', 'address keeps the typed number');
            sessionStorage.setItem('reloaded', '1'); location.reload();
          } catch (error) {
            await fetch('/complete?status=' + encodeURIComponent(String(error)));
          }
        }, {once:true});
        """))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                content = String(dispatch(:GET, req.target; headers=["HX-Request" => "true"]).body)
                return HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html",
                    htmx(Raw(content), driver; assets="/test-assets", sse_version=nothing,
                        ws_version=nothing, preload_version=nothing, pico_version=nothing,
                        feedback=false, compose=false, overlay=false)))
            end
            haskey(assets, path) && return HTTP.Response(200, ["Content-Type" => "application/javascript"], assets[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/complete"
                isready(receipt) || put!(receipt, String(req.target))
                return HTTP.Response(204)
            end
            dispatch(req.method, req.target; headers=collect(req.headers), body=HTMXObjects._request_body_bytes(req))
        end
        try
            mktempdir() do profile
                process = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=joinpath(profile, "browser.log")); wait=false)
                try
                    @test timedwait(() -> isready(receipt) || process_exited(process), 120; pollint=0.05) === :ok
                    outcome = isready(receipt) ? take!(receipt) : read(joinpath(profile, "browser.log"), String)
                    @test outcome == "/complete?status=passed"
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        finally
            close(server)
        end
    end
end
