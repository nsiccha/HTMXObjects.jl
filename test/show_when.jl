using TestItemRunner

@testitem "show_when marks a labeled widget with its field, predicate and option spelling" tags=[:unit] begin
    using HTMXObjects

    html(node) = repr("text/html", node)
    # A dependent starts hidden with the `hidden` attribute, never a class.
    marked(s, field, op, value; tag="label") = contains(s, Regex(string(
        "^<", tag, " [^>]*data-show-when-field=\"", field, "\" data-show-when-op=\"", op,
        "\" data-show-when-value=\"", value, "\" hidden=\"true\""))) && !contains(s, "u-hidden")
    # linput takes show_when like the other labeled widgets: the attributes
    # land on its label, and nothing reaches the input as a `show-when` attribute.
    subjects = html(linput((; subjects=10); show_when=(:basis, ==, "cohort")))
    @test marked(subjects, "basis", "eq", "cohort")
    @test !contains(subjects, "show-when=")
    @test marked(html(tinput((; notes=""); show_when=(:extended, ==, true))), "extended", "eq", "true")
    # An option object is compared in the spelling its radio carries.
    m1, m2 = (key="m1", label="Model 1"), (key="m2", label="Model 2")
    group = html(radio_group((; model=m2), [m1 => "Model 1", m2 => "Model 2"]))
    @test contains(group, "value=\"m2\" checked=\"true\"")
    @test marked(html(linput((; fit=""); show_when=(:model, ==, m2))), "model", "eq", "m2")
    @test marked(html(ninput((; draws=100); show_when=(:model, !=, m1))), "model", "neq", "m1")
    # Every widget kind, the fieldset of a radio group included.
    @test marked(html(sinput((; level="x"), ["x", "y"]; show_when=(:kind, ==, "b"))), "kind", "eq", "b")
    @test marked(html(sinput_custom((; level="x"), ["x", "y"]; show_when=(:kind, ==, "b"))), "kind", "eq", "b")
    @test marked(html(rinput((; spread=50); show_when=(:kind, ==, "b"))), "kind", "eq", "b")
    @test marked(html(cinput((; log=false); show_when=(:kind, ==, "b"))), "kind", "eq", "b")
    @test marked(html(radio_group((; method="a"), ["a", "b"]; show_when=(:basis, ==, "typical"))),
                 "basis", "eq", "typical"; tag="fieldset")
end

@testitem "show_when hides and shows every widget kind, with and without Pico" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        basis(checked) = radio_group((; basis=checked),
            ["typical" => "Typical subject", "cohort" => "New subjects"])
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        pico_css = read(HTMXObjects._vendor_file(:pico), String)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const pico = document.documentElement.dataset.pico === '1';
            const widget = name => document.querySelector('[name="' + name + '"]')
                .closest('[data-show-when-field]');
            // Shown means laid out, which is what the reader sees: Pico gives
            // every label `display: block`, unlayered.
            const shown = name => getComputedStyle(widget(name)).display !== 'none';
            const radio = (name, value) =>
                document.querySelector('input[name="' + name + '"][value="' + value + '"]');
            const until = async ok => {
                const end = Date.now() + 5000;
                while (!ok() && Date.now() < end) await new Promise(r => setTimeout(r, 25));
            };
            // Positive control: with Pico loaded, a label is a block, the
            // rule a layered class cannot beat; without it, an inline label.
            check('control', getComputedStyle(document.querySelector('[name="kind"]').closest('label'))
                .display === (pico ? 'block' : 'inline'));
            // The second radio is the checked one, so reading the group's
            // first radio would hide `subjects`.
            check('checked-radio-shows', shown('subjects'));
            check('checked-radio-hides-neq', !shown('seed'));
            check('number-shows-neq', shown('draws'));
            check('fieldset-hides', !shown('method'));
            radio('basis', 'typical').click();
            check('other-radio-hides', !shown('subjects'));
            check('other-radio-shows-neq', shown('seed'));
            check('number-hides-neq', !shown('draws'));
            check('fieldset-shows', shown('method'));
            radio('basis', 'cohort').click();
            check('radio-again-shows', shown('subjects'));
            // A checkbox counts only while checked.
            const box = document.querySelector('input[name="extended"]');
            check('unchecked-box-hides', !shown('notes'));
            box.click();
            check('checked-box-shows', shown('notes'));
            box.click();
            check('unchecked-again-hides', !shown('notes'));
            // A select reads its value; every widget kind follows it.
            const kinds = ['detail', 'level', 'spread', 'log'];
            check('select-hides', kinds.every(name => !shown(name)));
            const select = document.querySelector('select[name="kind"]');
            select.value = 'b';
            select.dispatchEvent(new Event('change', {bubbles: true}));
            check('select-shows', kinds.every(shown));
            // A radio group outside the form, attached with form=.
            check('attached-group-shows', shown('elsewhere'));
            radio('place', 'near').click();
            check('attached-group-hides', !shown('elsewhere'));
            // A swap that replaces the group re-reads it without a new binding.
            document.getElementById('swap').click();
            await until(() => radio('basis', 'typical').checked && !shown('subjects'));
            check('swapped-group-hides', !shown('subjects'));
            radio('basis', 'cohort').click();
            check('swapped-group-shows', shown('subjects'));
            const out = document.createElement('pre'); out.id = 'checks';
            out.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(out);
        });
        """))
        page(pico) = repr("text/html", htmx(
            h.form(
                h.div(basis("cohort"); id="basis-slot"),
                linput((; subjects=10); show_when=(:basis, ==, "cohort")),
                linput((; seed=1); show_when=(:basis, !=, "cohort")),
                ninput((; draws=100); show_when=(:basis, !=, "typical")),
                radio_group((; method="a"), ["a", "b"]; show_when=(:basis, ==, "typical")),
                cinput((; extended=false); value="true"),
                tinput((; notes=""); show_when=(:extended, ==, true)),
                sinput((; kind="a"), ["a", "b"]),
                linput((; detail=""); show_when=(:kind, ==, "b")),
                sinput((; level="x"), ["x", "y"]; show_when=(:kind, ==, "b")),
                rinput((; spread=50); show_when=(:kind, ==, "b")),
                cinput((; log=false); show_when=(:kind, ==, "b")),
                linput((; elsewhere=""); show_when=(:place, ==, "far")),
                h.button("Reset basis"; id="swap", type="button", hx_get="/basis",
                         hx_target="#basis-slot", hx_swap="innerHTML");
                id="sim"),
            radio_group((; place="far"), ["near", "far"]; form="sim"),
            show_when_script(),
            driver;
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=pico ? HTMXObjects._PICO_VERSION : nothing,
            extra_head=(h.script(Raw(pico ? "document.documentElement.dataset.pico = '1';" : "")),),
            feedback=false, compose=false, overlay=false))
        pages = Dict("/" => page(false), "/pico" => page(true))
        # Every dependent starts hidden in the markup: what is shown at load,
        # the script showed.
        for markup in values(pages)
            @test count(r"data-show-when-value=\"[^\"]*\" hidden=\"true\"", markup) == 10
            @test count("data-show-when-field=", markup) == 10
        end
        @test contains(pages["/pico"], "/test-assets/pico.min.css")
        @test !contains(pages["/"], "pico.min.css")
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"], pages[path])
            path == "/basis" && return HTTP.Response(200, ["Content-Type" => "text/html"],
                repr("text/html", basis("typical")))
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/test-assets/pico.min.css" &&
                return HTTP.Response(200, ["Content-Type" => "text/css"], pico_css)
            HTTP.Response(404)
        end
        try
            for path in ("/", "/pico")
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                if !isnothing(checks)
                    for line in split(checks[1], '\n')
                        @test endswith(line, ":true")
                    end
                    @test count(==('\n'), checks[1]) + 1 == 19
                end
            end
        finally
            close(server)
        end
    end
end
