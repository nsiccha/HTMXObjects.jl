@testmodule ComparisonBrowserFixtures begin
    using HTMXObjects, HTTP, Sockets
    export browser_driver, browser_checks, pane_response

    # Page script: `body` runs after load with `check(name, ok)` in scope; the
    # outcomes are appended as `<pre id="checks">name:true|false</pre>`.
    browser_driver(body) = h.script(Raw("""
    window.addEventListener('load', async function() {
        const checks = [];
        const check = (name, ok) => checks.push([name, Boolean(ok)]);
        $body
        const result = document.createElement('pre'); result.id = 'checks';
        result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\\n'); document.body.appendChild(result);
    });
    """))

    # Serves `page` at `/` and every other request through `handler`, then
    # returns the driver's check lines (or `nothing` when none were written).
    function browser_checks(page, handler; window_size=nothing)
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ?
                HTTP.Response(200, ["Content-Type" => "text/html"], page) : handler(req)
        end
        size = isnothing(window_size) ? String[] : ["--window-size=$window_size"]
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage $size --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? nothing : split(checks[1], '\n')
        finally
            close(server)
        end
    end

    # A tall pane with an editable input, so retained DOM and scrolling are observable.
    pane_response(i) = HTTP.Response(200, ["Content-Type" => "text/html"],
        "<div id=\"loaded-$i\"><input id=\"input-$i\"><pre>$(repeat("full line\n", 100))</pre></div>")
end

@testitem "comparison view rendering" tags=[:unit] begin
    using HTMXObjects
    content = h.pre(h.code("complete <source> & data"))
    before = repr("text/html", content)
    html = repr("text/html", comparison_view(
        "First" => content, "Second" => "/pane/two", "Third" => "/pane/three";
        id="example", selected=(1, 3)))
    @test repr("text/html", content) == before
    @test contains(html, "role=\"tablist\"")
    @test count("role=\"tab\"", html) == 3
    @test count("role=\"tabpanel\"", html) == 3
    @test contains(html, "<dialog")
    @test contains(html, "aria-labelledby=\"comparison-example-title\"")
    @test contains(html, "aria-selected=\"false\"")
    @test contains(html, "complete &lt;source&gt; &amp; data")
    @test count("htmxo-md-load consume, load", html) == 0
    @test count("hx-get=", html) == 2
    @test !contains(html, "style=\"")
    @test html == repr("text/html", comparison_view(
        "First" => content, "Second" => "/pane/two", "Third" => "/pane/three";
        id="example", presentation=:tabs, selected=(1, 3)))
    # Refused: comparison requires two distinct valid pane identities.
    @test_throws ArgumentError comparison_view("one" => content; id="x")
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", selected=(1, 1))
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", active=3)
end

@testitem "comparison view inline rendering" tags=[:unit] begin
    using HTMXObjects
    content = h.pre(h.code("complete <source> & data"))
    html = repr("text/html", comparison_view(
        "First" => content, "Second" => "/pane/two", "Third" => "/pane/three", "Fourth" => "/pane/four";
        id="example", presentation=:inline, selected=(1, 3, 4)))
    @test contains(html, "data-htmxo-presentation=\"inline\"")
    @test !contains(html, "role=\"tab")
    @test !contains(html, "<dialog")
    @test !contains(html, "data-htmxo-compare-open")
    @test !contains(html, "data-htmxo-compare-home")
    @test count("data-htmxo-compare-choice", html) == 4
    @test count("checked=\"true\"", html) == 3
    @test contains(html, "<legend>Select at least one view</legend>")
    @test contains(html, "role=\"status\"")
    @test count("<section", html) == 4
    @test count("hidden=\"true\"", html) == 1
    @test contains(html, "aria-labelledby=\"comparison-example-heading-2\"")
    @test contains(html, "<h3 id=\"comparison-example-heading-2\">Second</h3>")
    # Selected URL panes load on display; unselected ones wait for selection.
    @test count("htmxo-md-load consume, load", html) == 2
    @test count("hx-get=", html) == 3
    @test contains(html, "complete &lt;source&gt; &amp; data")
    @test !contains(html, "style=\"")
    # Refused: inline shows no tabs, so an initial tab would be silently ignored.
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", presentation=:inline, active=1)
    # Refused: presentations are a closed set; an unknown one must not fall back.
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", presentation=:dialog)
    single = repr("text/html", comparison_view("one" => "/pane/one", "two" => "/pane/two";
        id="single", presentation=:inline, selected=(1,)))
    @test count("checked=\"true\"", single) == 1
    @test count("hidden=\"true\"", single) == 1
    @test count("htmxo-md-load consume, load", single) == 1
    @test count("hx-get=", single) == 2
    # Refused: inline must display a valid pane rather than an empty grid.
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", presentation=:inline, selected=())
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", presentation=:inline, selected=(3,))
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", presentation=:inline, selected=("1",))
end

@testitem "comparison generated forms retain shared context" setup=[ComparisonBrowserFixtures] tags=[:unit, :browser, :semantic] begin
    using HTMXObjects, HTTP
    @htmx struct ComparisonFormFixture
        @param variant::Symbol = :one
        @options(variant) = (:one, :two)

        @include sources = begin
            @get source_alpha() = h.p("alpha:$(variant)")
            @get source_beta() = h.p("beta:$(variant)")
            @get source_gamma() = h.p("gamma:$(variant)")
        end
    end
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        shared_driver = """
            const panels = htmxoComparisonPanels(document.getElementById('generated'));
            const forms = panels.map(p => p.querySelector('form'));
            const results = panels.map(p => p.querySelector('.htmxo-semantic-operation-result'));
            const shared = document.querySelector('.htmxo-semantic-context');
            const choose = value => { shared.querySelector('input[name="variant"][value="' + value + '"]').checked = true; };
            const wait = async (index, text) => { for (let n = 0; n < 100 && !results[index].textContent.includes(text); n++) await new Promise(r => setTimeout(r, 20)); };
            check('one-shared-context', document.querySelectorAll('.htmxo-semantic-context').length === 1);
            check('generated-context-selector', forms.every(f => f.getAttribute('hx-include') === '#' + shared.id));
            check('initially-on-demand', results.every(r => r.textContent === ''));
        """
        drivers = (
            tabs = shared_driver * raw"""
                const root = document.getElementById('generated');
                choose('two');
                root.querySelector('[data-htmxo-compare-open]').click();
                forms.slice(0, 2).forEach(f => f.querySelector('button[type="submit"]').click());
                await wait(0, 'alpha:two'); await wait(1, 'beta:two');
                check('dialog-submits-current-context', results[0].textContent === 'alpha:two' && results[1].textContent === 'beta:two');
                check('original-form-and-result', panels.every((p, i) => p.querySelector('form') === forms[i] && p.querySelector('.htmxo-semantic-operation-result') === results[i]));
                root.querySelector('dialog header button').click();
                check('inline-restores-same-result', results[0].closest('[data-htmxo-compare-home]') !== null && results[0].textContent === 'alpha:two');
                choose('one');
                forms[0].querySelector('button[type="submit"]').click(); await wait(0, 'alpha:one');
                check('later-context-change', results[0].textContent === 'alpha:one');
                check('independent-result', results[1].textContent === 'beta:two');
            """,
            inline = shared_driver * raw"""
                const root = document.getElementById('generated');
                const choices = Array.from(root.querySelectorAll('[data-htmxo-compare-choice]'));
                check('inline-shows-selected', !panels[0].hidden && !panels[1].hidden && panels[2].hidden);
                choose('two');
                forms.slice(0, 2).forEach(f => f.querySelector('button[type="submit"]').click());
                await wait(0, 'alpha:two'); await wait(1, 'beta:two');
                check('inline-submits-current-context', results[0].textContent === 'alpha:two' && results[1].textContent === 'beta:two');
                choices[2].click();
                check('third-pane-shown', !panels[2].hidden && results[2].textContent === '');
                choices[0].click();
                check('deselected-hidden', panels[0].hidden);
                choose('one');
                forms[2].querySelector('button[type="submit"]').click(); await wait(2, 'gamma:one');
                choices[0].click();
                check('reselected-same-result', !panels[0].hidden && panels[0].querySelector('form') === forms[0] && results[0].textContent === 'alpha:two');
                check('later-context-change', results[2].textContent === 'gamma:one');
                check('independent-result', results[1].textContent === 'beta:two');
            """,
        )
        for presentation in (:tabs, :inline)
            app = ComparisonFormFixture(; __cache_base__=mktempdir())
            entries = Any[]
            surface = semantic_app(app; render_operation=entry -> begin
                push!(entries, entry)
                h.div()
            end)
            widget = comparison_view((entry.title => h.div(entry.form, entry.result)
                                      for entry in entries)...; id="generated", presentation)
            route!(app)
            page = repr("text/html", htmx(surface, widget, browser_driver(drivers[presentation]);
                hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
            # A submission that outlives the `:auto` grace window (a cold first
            # call, a loaded host) is answered by a poller that resumes it with
            # GETs of its own path carrying `__htmxo_poll`; those are not new
            # submissions, so they are counted apart. Each resume is slowed so
            # Chrome's virtual clock, which skips ahead between polls, cannot
            # outrun the server and expire the driver's waits.
            requests = Dict{String,Int}()
            resumes = Dict{String,Int}()
            checks = browser_checks(page, req -> begin
                uri = HTTP.URI(req.target)
                if haskey(HTTP.queryparams(uri), "__htmxo_poll")
                    resumes[uri.path] = get(resumes, uri.path, 0) + 1
                    sleep(0.2)
                else
                    requests[uri.path] = get(requests, uri.path, 0) + 1
                end
                dispatch(req.method, req.target; headers=["HX-Request" => "true"])
            end)
            @test !isnothing(checks)
            for line in something(checks, String[])
                @test endswith(line, ":true")
            end
            @test get(requests, "/sources/source_alpha", 0) == 2 - (presentation === :inline)
            @test get(requests, "/sources/source_beta", 0) == 1
            @test get(requests, "/sources/source_gamma", 0) == (presentation === :inline)
            # Only a submitted operation is ever resumed.
            @test issubset(keys(resumes), keys(requests))
        end
    end
end

@testitem "comparison view browser" setup=[ComparisonBrowserFixtures] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        widget = comparison_view(("View $i" => "/pane/$i" for i in 1:6)...; id="example")
        driver = browser_driver(raw"""
            const root = document.getElementById('example');
            const tabs = Array.from(root.querySelectorAll('[data-htmxo-tab]'));
            const home = root.querySelector('[data-htmxo-compare-home]');
            const dialog = root.querySelector('dialog');
            const grid = root.querySelector('[data-htmxo-compare-grid]');
            const open = root.querySelector('[data-htmxo-compare-open]');
            const choices = Array.from(root.querySelectorAll('input[type=checkbox]'));
            const wait = async id => { for(let n=0;n<100 && !document.getElementById(id);n++) await new Promise(r=>setTimeout(r,20)); };
            const closeDialog = () => dialog.querySelector('header button').click();
            const choose = (i, checked) => { choices[i-1].checked=checked; choices[i-1].dispatchEvent(new Event('change',{bubbles:true})); };
            await wait('loaded-1');
            const panel = root.querySelector('[data-htmxo-pane="1"]');
            const field = document.getElementById('input-1');
            field.value = 'kept user input';
            check('first-pane-load', !!field && home.children.length === 6);
            check('initial-tab-state', tabs[0].getAttribute('aria-selected') === 'true' && !panel.hidden);
            open.click(); await wait('loaded-2');
            check('dialog-open', dialog.open);
            check('initial-two', grid.children.length === 2);
            choose(3,true); choose(4,true);
            const failed = root.querySelector('[data-htmxo-pane="3"] > [data-loaded]');
            for(let n=0;n<100 && failed.dataset.failed !== '1';n++) await new Promise(r=>setTimeout(r,20));
            await wait('loaded-4');
            check('failure-isolated', failed.dataset.failed === '1' && !!document.getElementById('loaded-4'));
            failed.click(); await wait('loaded-3');
            check('failed-pane-retries', failed.dataset.loaded === '1');
            choose(4,false);
            check('three-columns', grid.children.length === 3);
            choose(4,true); choose(5,true); choose(6,true); await wait('loaded-6');
            check('six-columns', grid.children.length === 6);
            check('same-panel-dom', root.querySelector('[data-htmxo-pane="1"]') === panel && field.value === 'kept user input');
            choose(1,false); choose(3,false); choose(5,false);
            check('arbitrary-subset', Array.from(grid.children).map(p=>p.dataset.htmxoPane).join(',') === '2,4,6');
            choose(2,false); choose(4,false);
            check('minimum-two', choices[3].checked && grid.children.length === 2);
            check('minimum-message', root.querySelector('[data-htmxo-compare-status]').textContent === 'Select at least two views');
            closeDialog();
            check('close-restores-panels', home.children.length === 6 && home.children[0] === panel && !panel.hidden);
            check('close-focus', document.activeElement === open);
            check('input-retained', field.value === 'kept user input');
            tabs[0].focus(); tabs[0].dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true}));
            check('keyboard-end', document.activeElement === tabs[5] && tabs[5].getAttribute('aria-selected') === 'true');
            tabs[5].dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));
            check('keyboard-wrap', document.activeElement === tabs[0]);
            check('one-visible-inline', Array.from(home.children).filter(p=>!p.hidden).length === 1);
            open.click();
            check('selection-persists', Array.from(grid.children).map(p=>p.dataset.htmxoPane).join(',') === '4,6');
            check('independent-scroll', Array.from(grid.children).every(p=>getComputedStyle(p).overflow === 'auto'));
            check('wide-dialog', dialog.querySelector('article').getBoundingClientRect().width > innerWidth*.9);
            closeDialog();
        """)
        page = repr("text/html", htmx(widget, driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        requests = Dict{String,Int}()
        checks = browser_checks(page, req -> begin
            path = HTTP.URI(req.target).path
            startswith(path, "/pane/") || return HTTP.Response(404)
            requests[path] = get(requests, path, 0) + 1
            i = split(path, '/')[end]
            i == "3" && requests[path] == 1 && return HTTP.Response(500)
            pane_response(i)
        end)
        @test !isnothing(checks)
        for line in something(checks, String[])
            @test endswith(line, ":true")
        end
        for i in 1:6
            @test get(requests, "/pane/$i", 0) == (i == 3 ? 2 : 1)
        end
    end
end

@testitem "comparison view inline browser" setup=[ComparisonBrowserFixtures] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        widget = comparison_view(("View $i" => "/pane/$i" for i in 1:6)...;
            id="inline", presentation=:inline, selected=(1, 4, 5))
        driver = browser_driver(raw"""
            const root = document.getElementById('inline');
            const grid = root.querySelector('[data-htmxo-compare-grid]');
            const panels = Array.from(grid.children);
            const choices = Array.from(root.querySelectorAll('[data-htmxo-compare-choice]'));
            const status = root.querySelector('[data-htmxo-compare-status]');
            const shown = () => panels.filter(p => !p.hidden && getComputedStyle(p).display !== 'none').map(p => p.dataset.htmxoPane).join(',');
            const pause = () => new Promise(r => setTimeout(r, 20));
            const wait = async id => { for (let n = 0; n < 100 && !document.getElementById(id); n++) await pause(); };
            const toggle = i => choices[i - 1].closest('label').click();
            await wait('loaded-1'); await wait('loaded-4'); await wait('loaded-5');
            check('no-tabs-or-dialog', !root.querySelector('[role=tablist], dialog, [data-htmxo-compare-open]'));
            check('initial-selection-shown', shown() === '1,4,5');
            check('unselected-not-loaded', !document.getElementById('loaded-2') && !document.getElementById('loaded-6'));
            const panel = panels[0];
            const field = document.getElementById('input-1');
            field.value = 'kept user input';
            const box = root.getBoundingClientRect();
            check('fills-viewport-height', Math.abs(box.height - innerHeight) <= 1);
            check('grid-within-viewport', grid.getBoundingClientRect().bottom <= box.bottom + 0.5);
            const visible = panels.filter(p => !p.hidden);
            check('columns-side-by-side', visible.every(p => Math.abs(p.getBoundingClientRect().top - visible[0].getBoundingClientRect().top) < 1));
            check('columns-scroll', visible.every(p => getComputedStyle(p).overflowY === 'auto' && p.scrollHeight > p.clientHeight));
            visible[0].scrollTop = 300;
            check('independent-scroll', visible[0].scrollTop === 300 && visible[1].scrollTop === 0 && visible[2].scrollTop === 0 && scrollY === 0);
            toggle(2); toggle(2); toggle(2);
            check('in-flight-reselect', choices[1].checked && shown() === '1,2,4,5');
            await wait('loaded-2');
            check('order-follows-panes', shown() === '1,2,4,5');
            toggle(3);
            const failed = panels[2].querySelector(':scope > [data-loaded]');
            for (let n = 0; n < 100 && failed.dataset.failed !== '1'; n++) await pause();
            check('failure-isolated', failed.dataset.failed === '1' && shown() === '1,2,3,4,5');
            failed.click(); await wait('loaded-3');
            check('failed-pane-retries', failed.dataset.loaded === '1');
            toggle(1);
            check('deselect-hides-in-place', panel.hidden && panel.parentElement === grid && shown() === '2,3,4,5');
            toggle(1);
            check('reselect-same-dom', panels[0] === panel && document.getElementById('input-1') === field && field.value === 'kept user input' && shown() === '1,2,3,4,5');
            toggle(1); toggle(3);
            check('arbitrary-subset', shown() === '2,4,5');
            toggle(2); toggle(5);
            check('single-selection', !choices[4].checked && shown() === '4');
            const single = panels[3];
            const width = single.getBoundingClientRect().width;
            check('single-fills-width', Math.abs(width - grid.clientWidth) <= 1);
            check('single-scrolls', getComputedStyle(single).overflowY === 'auto' && single.scrollHeight > single.clientHeight);
            toggle(4);
            check('minimum-one', choices[3].checked && shown() === '4');
            check('minimum-message', status.textContent === 'Select at least one view');
            toggle(6); await wait('loaded-6');
            check('message-clears', status.textContent === '' && shown() === '4,6');
            toggle(1);
            check('reselect-after-single-same-dom', panels[0] === panel && document.getElementById('input-1') === field && field.value === 'kept user input' && shown() === '1,4,6');
            check('labelled-columns', visible.every(p => document.getElementById(p.getAttribute('aria-labelledby')).textContent === 'View ' + p.dataset.htmxoPane));
        """)
        page = repr("text/html", htmx(widget, driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        requests = Dict{String,Int}()
        checks = browser_checks(page, req -> begin
            path = HTTP.URI(req.target).path
            startswith(path, "/pane/") || return HTTP.Response(404)
            requests[path] = get(requests, path, 0) + 1
            i = split(path, '/')[end]
            i == "3" && requests[path] == 1 && return HTTP.Response(500)
            i == "2" && sleep(0.3)
            pane_response(i)
        end; window_size="1280,800")
        @test !isnothing(checks)
        for line in something(checks, String[])
            @test endswith(line, ":true")
        end
        for i in 1:6
            @test get(requests, "/pane/$i", 0) == (i == 3 ? 2 : 1)
        end
    end
end
