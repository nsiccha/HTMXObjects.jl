using TestItemRunner

@testmodule MultipleChoiceFixtures begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain
    export MultipleChoicePage
    const DEFAULT_QUANTITIES = ["q1", "q3", "q5", "q7", "q11"]
    @htmx struct MultipleChoicePage
        @param choice_count::Int = 11
        "Drawn quantities"
        @param quantities::Vector{String} = copy(DEFAULT_QUANTITIES)
        @options(quantities) = option_domain(["q$i" => "Quantity $i" for i in 1:choice_count])
        "Included states"
        @param states::Vector{Bool} = [true]
        @options(states) = [true => "Enabled", false => "Disabled"]
        @get plot() = h.p(join(quantities, ",") * ":" * join(states, ","); class="result")
        @get summary() = h.p(join(quantities, ",") * ":" * join(states, ","))
        @get index() = semantic_app(__self__; presentation=:tabs,
                                    select=entry -> entry.name !== :index)
    end
end

@testitem "vector parameter controls preserve every choice and radio_max" setup=[MultipleChoiceFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects
    app = MultipleChoicePage()
    for presentation in (:tabs, :stacked), cutoff in (2, 12)
        html = repr("text/html", semantic_app(app; presentation, radio_max=cutoff,
            select=entry -> entry.name !== :index))
        @test !contains(html, "type=\"radio\"")
        @test !contains(html, "<select")
        @test contains(html, "data-htmxo-checkbox-group")
        @test contains(html, "data-htmxo-choice-list") == (cutoff == 2)
        for q in ("q1", "q3", "q5", "q7", "q11")
            @test contains(html, "name=\"quantities\" value=\"$q\" checked=\"true\"")
        end
        if cutoff == 2
            @test contains(html, "5 selected: Quantity 1, Quantity 3, Quantity 5, Quantity 7, Quantity 11")
        end
    end
    # The operation argument path, as well as promoted @param context.
    @htmx struct ArgumentChoices
        @options(items) = ["a", "b", "c"]
        @get result(; items::Vector{String}=["a", "c"]) = join(items, ",")
    end
    html = repr("text/html", operation_form(ArgumentChoices(), :result;
        values=(; items=["a", "c"]), radio_max=2))
    @test count("type=\"checkbox\"", html) == 3
    @test count("checked=\"true\"", html) == 2
    @test contains(html, "2 selected: a, c")
end

@testitem "multiple choice lists retain labels groups disabled options and validity" tags=[:unit] begin
    using HTMXObjects
    options = [(value="a", label="Äpfel", group="Fresh"),
               (value="b", label="Birnen", help="Ripe fruit"),
               (value="c", label="Unavailable", disabled=true)]
    list = choice_list((; fruit=["a", "b", "c"]), options; multiple=true, required=true,
                       label="Fruit", texts=error_texts(:de))
    html = repr("text/html", list)
    @test contains(html, "2 ausgewählt: Äpfel, Birnen")
    @test contains(html, ">Fresh</div>") && contains(html, "<small>Ripe fruit</small>")
    @test contains(html, "value=\"c\" disabled=\"true\"")
    @test !contains(html, " required=\"true\"")
    @test contains(html, "data-htmxo-choice-empty=\"\" disabled=\"true\"")
    @test HTMXObjects.to_markdown_string(list) == "Fruit Birnen, Äpfel\n\n"
    empty = repr("text/html", choice_list((; fruit=String[]), options; multiple=true, required=true))
    @test contains(empty, "0 selected")
    @test count(" required=\"true\"", empty) == 1
    @test !contains(empty, "data-htmxo-choice-empty=\"\" disabled")
end

@testitem "multiple choices submit and persist none one and many in a live tabs page" setup=[MultipleChoiceFixtures] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires Chrome")
        route!(MultipleChoicePage(); operation_policy=:blocking)
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
          const shown = () => document.querySelector('[id$="-get-plot-result"]').textContent;
          const list = () => document.querySelector('.htmxo-choice-list');
          const box = value => list().querySelector('input[value="' + value + '"]');
          const summary = () => list().querySelector('.htmxo-choice-current').textContent;
          const values = () => new FormData(box('q1').form).getAll('quantities');
          try {
            if (sessionStorage.getItem('empty')) {
              await until(() => shown() === ':', 'empty values after reload');
              check(summary() === '0 selected', 'empty summary after reload');
              check(values().join() === '', 'explicit empty form value after reload');
              await fetch('/complete?status=passed'); return;
            }
            await until(() => shown() === 'q1,q3,q5,q7,q11:true', 'initial selections');
            check(summary() === '5 selected: Quantity 1, Quantity 3, Quantity 5, Quantity 7, Quantity 11', 'summary');
            list().querySelector('button').click(); await sleep(50);
            const search = list().querySelector('input[type="search"]');
            search.value = 'Quantity 2';
            search.dispatchEvent(new Event('input', {bubbles:true}));
            await sleep(700);
            check(shown() === 'q1,q3,q5,q7,q11:true', 'search changed result');
            check(values().length === 5, 'filtered selections lost');
            search.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true, cancelable:true}));
            await until(() => shown() === 'q1,q2,q3,q5,q7,q11:true', 'keyboard add');
            check(list().querySelector('[popover]').matches(':popover-open'), 'popover closed on toggle');
            search.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true, cancelable:true}));
            await until(() => shown() === 'q1,q3,q5,q7,q11:true', 'keyboard remove');
            search.value = ''; search.dispatchEvent(new Event('input', {bubbles:true}));
            for (const value of ['q3','q5','q7','q11']) box(value).click();
            await until(() => shown() === 'q1:true', 'single vector');
            check(summary() === '1 selected: Quantity 1', 'single summary');
            const count = document.querySelector('input[name="choice_count"]');
            count.value = '12'; count.dispatchEvent(new Event('change', {bubbles:true}));
            await until(() => box('q12'), 'refreshed options');
            check(box('q1').checked && values().join() === 'q1', 'refresh lost single selection');
            box('q1').click();
            await until(() => shown() === ':true', 'empty vector');
            count.value = '13'; count.dispatchEvent(new Event('change', {bubbles:true}));
            await until(() => box('q13'), 'empty refreshed options');
            check(summary() === '0 selected' && values().join() === '', 'refresh restored computed default');
            const state = document.querySelector('input[name="states"][value="true"]');
            state.click();
            await until(() => shown() === ':', 'unchecked true is empty, not false');
            const url = new URL(location.href);
            check(url.searchParams.has('quantities') && url.searchParams.get('quantities') === '', 'empty address');
            check(url.searchParams.has('states') && url.searchParams.get('states') === '', 'empty boolean vector address');
            sessionStorage.setItem('empty', '1'); location.reload();
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

@testitem "multiple choice validity reset and show_when use the selected boxes" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        options = [(value="a", label="Alpha"), (value="b", label="Beta", group="Group"),
                   (value="c", label="Unavailable", disabled=true)]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
          const out = document.body.dataset, form = document.querySelector('form');
          const list = document.querySelector('.htmxo-choice-list'), panel = list.querySelector('[popover]');
          const a = list.querySelector('input[value="a"]'), b = list.querySelector('input[value="b"]');
          const wait = () => new Promise(r => setTimeout(r, 50));
          const sent = () => new FormData(form).getAll('choice');
          try {
            out.empty = String(!form.checkValidity() && sent().length === 1 && sent()[0] === '');
            a.click(); await wait();
            out.one = String(form.checkValidity() && sent().join() === 'a' && panel.matches(':popover-open') &&
              document.getElementById('empty').hidden && !document.getElementById('alpha').hidden);
            b.click(); await wait();
            list.querySelector('input[value="c"]').click();
            out.many = String(sent().join() === 'a,b' && form.checkValidity());
            const field = list.querySelector('.htmxo-choice-field');
            out.aligned = String(Math.abs(panel.getBoundingClientRect().top - field.getBoundingClientRect().bottom - 2) < 2);
            form.reset(); await wait();
            out.reset = String(!form.checkValidity() && sent().join() === '' &&
              list.querySelector('.htmxo-choice-current').textContent === '0 selected');
            // The same requirement applies to generated checkbox pills.
            a.click();
            const pills = document.querySelector('[data-htmxo-checkbox-group]');
            pills.querySelector('input[value="a"]').click(); await wait();
            out.pills = String(form.checkValidity() && new FormData(form).getAll('pill').join() === 'a');
            pills.querySelector('input[value="a"]').click(); await wait();
            out.required = String(!form.checkValidity());
            pills.querySelector('input[value="a"]').click();
            async function setChoices(values) {
              const template = document.createElement('template');
              template.setAttribute('data-htmxo-set-inputs', JSON.stringify({choice:values}));
              document.body.appendChild(template);
              template.dispatchEvent(new Event('htmx:load', {bubbles:true}));
              await wait();
            }
            await setChoices(['a', 'b']);
            out.setmany = String(sent().join() === 'a,b' && form.checkValidity() &&
              list.querySelector('.htmxo-choice-current').textContent === '2 selected: Alpha, Beta');
            await setChoices(['']);
            out.setempty = String(sent().length === 1 && sent()[0] === '' && !form.checkValidity() &&
              list.querySelector('.htmxo-choice-current').textContent === '0 selected');
            await setChoices(['c']);
            out.disabled = String(sent().join() === '' && !list.querySelector('input[value="c"]').checked);
            // An unavailable set_inputs choice waits for an options refresh.
            list.querySelector('input[value="c"]').disabled = false;
            document.body.dispatchEvent(new Event('htmx:afterSettle', {bubbles:true}));
            await wait();
            out.setlater = String(sent().join() === 'c' && form.checkValidity());
            const record = document.querySelector('input[name="rows.1.tags"][value="a"]').closest('fieldset');
            record.querySelector('input[value="b"]').click(); await wait();
            out.records = String(new URL(location.href).searchParams.getAll('rows.1.tags').join() === 'a,b');
            record.querySelector('input[value="a"]').click();
            record.querySelector('input[value="b"]').click(); await wait();
            const query = new URL(location.href).searchParams;
            out.recordempty = String(query.has('rows.1.tags') && query.get('rows.1.tags') === '');
          } catch (error) { out.error = String(error); }
          out.done = '1';
        });
        """))
        # Initially only the popover is required; enable the pills' requirement
        # after checking the list, so each group's validity is tested separately.
        pills = HTMXObjects._semantic_checkboxes(:pill, "Pills", (; options), String[])
        enable = h.script(Raw("document.addEventListener('input', e => { if(e.target.name==='pill') e.target.closest('fieldset').setAttribute('data-htmxo-required','true'); }, true);"))
        record = HTMXObjects._semantic_checkboxes("rows.1.tags", "Record choices", (; options), ["a"])
        content = h.form(h.style(Raw(".htmxo-choice-list { width: 145px; }")),
            choice_list((; choice=String[]), options; multiple=true, required=true), pills, record,
            h.input(; type="hidden", name="rows.1.label", value="Row 1"),
            h.div("Empty"; id="empty", HTMXObjects._show_when_attrs((:choice, ==, ""))...),
            h.div("Alpha"; id="alpha", HTMXObjects._show_when_attrs((:choice, ==, "a"))...), enable, driver;
            data_htmxo_address="{\"rows\":{\"records\":{\"label\":\"Row\",\"fields\":{\"tags\":[\"a\"]}}}}")
        dom = mktempdir() do directory
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", htmx(content; pico_version=nothing,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing)))
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=3000 --dump-dom --user-data-dir=$(joinpath(directory, "profile")) file://$fixture`)
        end
        @test contains(dom, "data-done=\"1\"") && !contains(dom, "data-error=")
        for marker in ("empty", "one", "many", "aligned", "reset", "pills", "required", "setmany", "setempty", "disabled", "setlater", "records", "recordempty")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end


@testitem "Records preserve multiple values and explicit empty vector fields" tags=[:unit, :semantic] begin
    using HTMXObjects
    @htmx struct VectorRecords
        @param tags::Vector{String} = ["a", "b"]
        @options(tags) = ["a", "b", "c"]
        @param note::String = "default"
        @param rows::Records = Records(:tags, :note)
        @get result() = h.p(join((join(row.tags, ",") * "|" * row.note for row in rows), ";"))
    end
    app = VectorRecords()
    route!(app; operation_policy=:blocking)
    body(url) = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    @test body("/result?rows.1.tags=a&rows.1.tags=c") == "<p>a,c|default</p>"
    @test body("/result?rows.1.tags=c") == "<p>c|default</p>"
    @test body("/result?rows.1.tags=") == "<p>|default</p>"
    @test body("/result?rows.1.label=A") == "<p>a,b|default</p>"
    @test body("/result?rows.1.tags=c&rows.1.note=first&rows.1.note=last") == "<p>c|last</p>"
    @test body("/result?rows.1.tags=a&rows.1.tags=c&rows.2.tags=") == "<p>a,c|default;|default</p>"
    @test record_view(app, (; label="Empty", tags=String[], note="x")).tags == String[]
    @test record_view(app, (; label="Many", tags=["a", "c"], note="x")).tags == ["a", "c"]
    src = Dict("rows.1.tags" => "", "rows.1.on" => ["false", "true"])
    fallback = Dict("rows.1.tags" => ["a", "c"])
    @test HTMXObjects._submitted_records(src, fallback, :rows, Set(["tags"])) ==
        [Dict("tags" => "", "on" => "true")]
end
