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
    # Refused: comparison requires two distinct valid pane identities.
    @test_throws ArgumentError comparison_view("one" => content; id="x")
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", selected=(1, 1))
    @test_throws ArgumentError comparison_view("one" => content, "two" => content; id="x", active=3)
end

@testitem "comparison view browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        widget = comparison_view(("View $i" => "/pane/$i" for i in 1:6)...; id="example")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
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
            const result=document.createElement('pre'); result.id='checks';
            result.textContent=checks.map(([name,ok])=>name+':'+ok).join('\n'); document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(widget, driver;
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        requests = Dict{String,Int}()
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif startswith(path, "/pane/")
                requests[path] = get(requests, path, 0) + 1
                i = split(path, '/')[end]
                i == "3" && requests[path] == 1 && return HTTP.Response(500)
                HTTP.Response(200, ["Content-Type" => "text/html"], "<div id=\"loaded-$i\"><input id=\"input-$i\"><pre>$(repeat("full line\n", 100))</pre></div>")
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
            end
            for i in 1:6
                @test get(requests, "/pane/$i", 0) == (i == 3 ? 2 : 1)
            end
        finally
            close(server)
        end
    end
end
