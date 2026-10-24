@testmodule UrlParamsFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw
    export UrlParamsApp, SlowUrlParamsApp, PickedUrlParamsApp, KS, PROBES, alarms_view, bundle, bundle_name

    const KS = (3.0, 4.0, 5.0)
    const PROBES = ("a", "b", "c")

    # The page address's `k` drives the alarms list: rendered for one value,
    # its links swap a new version in. Its trigger never fires, so a click on a
    # link inside does not also reload it (htmx's default trigger is `click`).
    alarms_view(k) = h.div(; id="alarms", hx_get="/alarms", hx_trigger="none", hx_swap="outerHTML",
                           url_params(k = k; values = (k = KS,))...)(
        h.p("k=$k"; class="k"),
        (h.a("k$(Int(x))"; id="k$(Int(x))", href="#", hx_get="/alarms?k=$x",
             hx_target="#alarms", hx_swap="outerHTML") for x in KS)...)

    # The address's `m` drives the probe pane, sent as `kenn`; a `pick` event
    # carries its own probe, as a map click would.
    probe_pane() = h.div(; id="pane", hx_get="/probe", hx_trigger="load, pick from:body",
                         hx_vals="js:{...(event && event.detail && event.detail.kenn ? {kenn: event.detail.kenn} : {})}",
                         url_params(m = "a" => :kenn; values = (m = PROBES,))...)(h.p("loading"))

    # Another element's request into the pane.
    pane_button() = h.button("b"; id="pane-b", hx_get="/probe?kenn=b", hx_target="#pane")

    # Checks for the browser item: what a page opened with the address's
    # parameters shows, and what clicks write into the address.
    const DRIVER = raw"""
    window.addEventListener('load', async function () {
      const checks = [];
      const check = (name, ok) => checks.push([name, Boolean(ok)]);
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      // Waits for a condition, then for htmx to settle the swap (it processes
      // swapped-in links 20 ms after the swap).
      const wait = async cond => {
        for (let n = 0; n < 200 && !cond(); n++) await sleep(20);
        const ok = cond();
        await sleep(60);
        return ok;
      };
      const text = sel => (document.querySelector(sel) || {}).textContent;
      const param = n => new URLSearchParams(location.search).get(n);
      let failures = 0;
      document.body.addEventListener('htmx:responseError', () => failures++);
      document.body.addEventListener('htmx:sendError', () => failures++);
      const pick = kenn => document.body.dispatchEvent(new CustomEvent('pick', { detail: { kenn } }));
      try {
        if (location.search.includes('k=4.0')) {
          check('k-from-address', await wait(() => text('#alarms .k') === 'k=4.0'));
          check('m-from-address', await wait(() => text('#pane .probe') === 'probe b'));
          check('address-kept', param('k') === '4.0' && param('m') === 'b');
          document.getElementById('k5').click();
          check('k-click', await wait(() => text('#alarms .k') === 'k=5.0'));
          check('k-written', await wait(() => param('k') === '5.0') && param('m') === 'b');
          pick('c');
          check('m-click', await wait(() => text('#pane .probe') === 'probe c'));
          check('m-written', await wait(() => param('m') === 'c') && param('k') === '5.0');
          document.getElementById('k3').click();
          check('k-back-to-default', await wait(() => text('#alarms .k') === 'k=3.0'));
          check('tracked-default-written', await wait(() => param('k') === '3.0'));
        } else if (location.search.includes('k=9.0')) {
          check('unknown-m-default', await wait(() => text('#pane .probe') === 'probe a'));
          await sleep(300);
          check('unknown-k-kept', text('#alarms .k') === 'k=3.0');
        } else {
          check('default-probe', await wait(() => text('#pane .probe') === 'probe a'));
          await sleep(100);
          check('first-load-leaves-address', location.search === '');
          document.getElementById('k4').click();
          check('k-click', await wait(() => text('#alarms .k') === 'k=4.0'));
          check('only-k-written', await wait(() => param('k') === '4.0') && param('m') === null);
          // Another element's request into the pane writes the value it asked for.
          document.getElementById('pane-b').click();
          check('target-click', await wait(() => text('#pane .probe') === 'probe b'));
          check('target-written', await wait(() => param('m') === 'b') && param('k') === '4.0');
        }
        check('no-failed-request', failures === 0);
      } catch (err) {
        check('error: ' + String(err), false);
      }
      const result = document.createElement('pre'); result.id = 'checks';
      result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
      document.body.appendChild(result);
    });
    """

    @htmx struct UrlParamsApp
        __page__(content) = htmx(h.main(content); assets="/test-assets", sse_version=nothing,
            ws_version=nothing, preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false)
        "Alarms"
        @get alarms(; k::Float64=3.0) = alarms_view(k)
        "Probe"
        @get probe(; kenn::String="a") = h.p("probe $kenn"; class="probe")
        @get index() = h.div(alarms_view(3.0), probe_pane(), pane_button(), h.script(Raw(DRIVER)))
    end

    # Checks for the browser item over `SlowUrlParamsApp`, reported to
    # `/complete`: a link to a value its route answers through a poller ends
    # showing that value, with it in the address.
    const SLOW_DRIVER = raw"""
    window.addEventListener('error', event => {
      fetch('/complete?status=' + encodeURIComponent('error: ' + event.message));
    });
    window.addEventListener('load', async function () {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      async function until(cond, label) {
        for (let n = 0; n < 400 && !cond(); n++) await sleep(25);
        if (!cond()) throw new Error('timed out: ' + label + ' (shows ' +
          text('#alarms .k') + ', address ' + location.search + ')');
        await sleep(60);
      }
      const text = sel => (document.querySelector(sel) || {}).textContent;
      const param = n => new URLSearchParams(location.search).get(n);
      try {
        await until(() => text('#alarms .k') === 'k=4.0', 'k=4.0 from the address');
        document.getElementById('k5').click();
        await until(() => document.querySelector('.treebar-poller-inner'), 'the poller');
        await until(() => text('#alarms .k') === 'k=5.0', 'k=5.0 through the poller');
        await until(() => param('k') === '5.0', 'k=5.0 written');
        // Nothing takes it back: the address and the list stay at 5.0.
        await sleep(1500);
        if (text('#alarms .k') !== 'k=5.0' || param('k') !== '5.0')
          throw new Error('reverted to ' + text('#alarms .k') + ', address ' + location.search);
        document.getElementById('k3').click();
        await until(() => text('#alarms .k') === 'k=3.0' && param('k') === '3.0', 'k=3.0 written');
        fetch('/complete?status=passed');
      } catch (err) {
        fetch('/complete?status=' + encodeURIComponent(String(err)));
      }
    });
    """

    # The same list from a route that answers k = 5.0 more slowly than the
    # `:auto` grace, so a request for it swaps a poller in, whose polls bring
    # the list (snag url-params-outer-1b61cafa).
    @htmx struct SlowUrlParamsApp
        __page__(content) = htmx(h.main(content); assets="/test-assets", sse_version=nothing,
            ws_version=nothing, preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false)
        "Alarms"
        @fresh @get alarms(; k::Float64=3.0) = (k == 5.0 && sleep(0.8); alarms_view(k))
        @get index() = h.div(alarms_view(3.0), h.script(Raw(SLOW_DRIVER)))
    end

    # A part a selector outside it reloads, as an Ortsteil selector reloads its
    # map: its own request takes the selected value from the `change` event.
    picked_view(k) = h.section(; id="picked", hx_get="/picked", hx_trigger="change from:#k-select",
                               hx_swap="outerHTML",
                               hx_vals="js:{...(event?.target?.id === 'k-select' ? {k: event.target.value} : {})}",
                               url_params(k = k; values = (k = KS,))...)(h.p("k=$k"; class="k"))
    k_select() = h.select(; id="k-select", name="k")((h.option(string(x); value=string(x)) for x in KS)...)

    # Checks for the browser item over `PickedUrlParamsApp`, opened with
    # `?k=4.0`, whose part the server answers slowly for 4.0: the selector
    # changes while the address's value still loads (snag
    # static-url-param-d5a8157c).
    const PICKED_DRIVER = raw"""
    const checks = [];
    const check = (name, ok) => checks.push([name, Boolean(ok)]);
    // The selector changes right after the part's first request, the
    // address's, is sent: in a microtask, as the browser's virtual time stands
    // still while that request's held answer is pending.
    let changed = false;
    document.addEventListener('htmx:beforeRequest', function first(e) {
      if (e.detail.elt.id !== 'picked') return;
      document.removeEventListener('htmx:beforeRequest', first);
      queueMicrotask(() => {
        check('address-value-loading', document.getElementById('picked').classList.contains('htmx-request'));
        const select = document.getElementById('k-select');
        select.value = '5.0';
        select.dispatchEvent(new Event('change', { bubbles: true }));
        changed = true;
      });
    });
    window.addEventListener('load', async function () {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const wait = async cond => {
        for (let n = 0; n < 200 && !cond(); n++) await sleep(20);
        const ok = cond();
        await sleep(60);
        return ok;
      };
      const text = sel => (document.querySelector(sel) || {}).textContent;
      const param = n => new URLSearchParams(location.search).get(n);
      let failures = 0;
      document.body.addEventListener('htmx:responseError', () => failures++);
      document.body.addEventListener('htmx:sendError', () => failures++);
      let rejected = 0;
      window.addEventListener('unhandledrejection', () => rejected++);
      try {
        check('selector-changed', await wait(() => changed));
        check('selected-shown', await wait(() => text('#picked .k') === 'k=5.0'));
        check('selected-written', await wait(() => param('k') === '5.0'));
        // The address's answer, held back past this, does not take it back.
        await sleep(1500);
        check('selected-kept', text('#picked .k') === 'k=5.0' && param('k') === '5.0');
        check('no-failed-request', failures === 0 && rejected === 0);
      } catch (err) {
        check('error: ' + String(err), false);
      }
      const result = document.createElement('pre'); result.id = 'checks';
      result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
      document.body.appendChild(result);
    });
    """

    @htmx struct PickedUrlParamsApp
        __page__(content) = htmx(h.main(content); assets="/test-assets", sse_version=nothing,
            ws_version=nothing, preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false)
        "Picked"
        @get picked(; k::Float64=3.0) = picked_view(k)
        @get index() = h.div(k_select(), picked_view(3.0), h.script(Raw(PICKED_DRIVER)))
    end

    # The bundle file of an app address, flat, query folded into the name.
    bundle_name(address) = address == "/" ? "index.html" :
        replace(lstrip(address, '/'), r"[?=&]" => "-") * ".html"

    # A static export of the app: every address the pages reference, written
    # as `bundle_name` names it; `seen` lists what `url_map` was asked for.
    function bundle(app=UrlParamsApp())
        route!(app)
        files, queue, seen = Dict{String,String}(), ["/"], Set(["/"])
        asked = String[]
        url_map(address) = if startswith(address, "/") && !startswith(address, "/test-assets")
            push!(asked, address)
            address in seen || (push!(seen, address); push!(queue, address))
            bundle_name(address)
        end
        spec = StaticExport(; url_map, controls=:remove)
        while !isempty(queue)
            address = popfirst!(queue)
            headers = address == "/" ? Pair{String,String}[] : ["HX-Request" => "true"]
            response = dispatch(:GET, address; headers, static=spec)
            response.status == 200 || error("export of $address answered $(response.status)")
            files[bundle_name(address)] = String(response.body)
        end
        files, asked
    end
end

@testitem "url_params writes the parameters the runtime reads" setup=[UrlParamsFixture] tags=[:unit] begin
    import HTMXObjects: _url_params_decode
    attrs = url_params(k = 3.0; values = (k = KS,))
    @test attrs == (; data_htmxo_url_params = "[[\"k\",\"k\",\"3.0\",[\"3.0\",\"4.0\",\"5.0\"]]]")
    renamed = _url_params_decode(url_params(m = "a" => :kenn, ort = nothing).data_htmxo_url_params)
    @test [(p.name, p.as, p.value, p.values) for p in renamed] ==
          [("m", "kenn", "a", nothing), ("ort", "ort", nothing, nothing)]
    html = repr("text/html", alarms_view(4.0))
    @test occursin("data-htmxo-url-params=\"[[&quot;k&quot;,&quot;k&quot;,&quot;4.0&quot;", html)
    @test !occursin("data-htmxo-url-files", html)
    # Misdeclarations fail when the page renders.
    @test_throws ArgumentError url_params()
    @test_throws ArgumentError url_params(k = 7.0; values = (k = KS,))
    @test_throws ArgumentError url_params(k = 3.0; values = (j = KS,))
    @test_throws ArgumentError url_params(a = 1 => :x, b = 2 => :x)
    # The shell carries the runtime.
    @test occursin("window.htmxoUrlParams", repr("text/html", htmx(h.p("x"))))
    @test occursin("window.htmxoUrlParams", repr("text/html", url_params_script()))
end

@testitem "a static export gives a url_params element the file of each value" setup=[UrlParamsFixture] tags=[:unit] begin
    files, asked = bundle()
    page = files["index.html"]
    # Each declared value's address went to `url_map`, so the export wrote it.
    for k in ("3.0", "4.0", "5.0")
        @test "/alarms?k=$k" in asked
        @test occursin("k=$k", files["alarms-k-$k.html"])
    end
    for m in ("a", "b", "c")
        @test "/probe?kenn=$m" in asked
        @test occursin("probe $m", files["probe-kenn-$m.html"])
    end
    # The page carries each value's file; an element's own `hx-get` names the
    # file of the value it was rendered with.
    @test occursin("data-htmxo-url-files=\"{&quot;3.0&quot;:&quot;alarms-k-3.0.html&quot;,&quot;4.0&quot;:&quot;alarms-k-4.0.html&quot;,&quot;5.0&quot;:&quot;alarms-k-5.0.html&quot;}\"", page)
    @test occursin("hx-get=\"alarms-k-3.0.html\"", page)
    @test occursin("hx-get=\"probe-kenn-a.html\"", page)
    # A swapped-in version carries the table too.
    @test occursin("data-htmxo-url-files", files["alarms-k-5.0.html"])
    # Without a `url_map` (or with one that maps nothing) no value has a file:
    # the element stays as rendered, and the runtime knows it is static.
    plain = repr("text/html", static_transform(alarms_view(3.0), StaticExport()))
    @test occursin("data-htmxo-url-files=\"{}\"", plain)
    undeclared = repr("text/html", static_transform(
        h.div(; hx_get="/probe", url_params(m = "a" => :kenn)...), StaticExport(; url_map=a -> "x.html")))
    @test occursin("data-htmxo-url-files=\"{}\"", undeclared)
end

@testitem "a static export keeps the query of a pushed address" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    link = h.a("x"; href="#", hx_push_url="/insitu?groesse=cs137&k=4.0#karte",
               hx_replace_url="/?k=4.0")
    mapped = repr("text/html", static_transform(link, StaticExport(;
        url_map = a -> a == "/insitu" ? "insitu.html" : a == "/" ? "index.html" : nothing)))
    @test occursin("hx-push-url=\"insitu.html?groesse=cs137&amp;k=4.0#karte\"", mapped)
    @test occursin("hx-replace-url=\"index.html?k=4.0\"", mapped)
    based = repr("text/html", static_transform(link; record_base="/b"))
    @test occursin("hx-push-url=\"/b/insitu?groesse=cs137&amp;k=4.0#karte\"", based)
    # `true`, `false` and relative addresses stay as given.
    for value in ("true", "false", "?k=4.0")
        @test occursin("hx-push-url=\"$value\"",
            repr("text/html", static_transform(h.a("x"; hx_push_url=value), StaticExport(; url_map=a -> "y"))))
    end
end

@testitem "record! records the fragment of each declared value" setup=[UrlParamsFixture] tags=[:unit] begin
    dir = mktempdir()
    record!(UrlParamsApp(); record_dir=dir, record_base="/b", paths=["/"], markdown=false)
    for k in ("3.0", "4.0", "5.0")
        file = joinpath(dir, "hx", "alarms@k=$k.html")
        @test isfile(file) && occursin("k=$k", read(file, String))
    end
    for m in ("a", "b", "c")
        file = joinpath(dir, "hx", "probe@kenn=$m.html")
        @test isfile(file) && occursin("probe $m", read(file, String))
    end
    page = read(joinpath(dir, "index.html"), String)
    @test occursin("&quot;4.0&quot;:&quot;/b/hx/alarms@k=4.0.html&quot;", page)
    @test occursin("hx-get=\"/b/hx/alarms@k=3.0.html\"", page)
    # Outside `record!` nothing would write those files, so none is named.
    @test occursin("data-htmxo-url-files=\"{}\"",
        repr("text/html", static_transform(alarms_view(3.0); record_base="/b")))
end

@testitem "url_params elements follow the address in a real browser, live and exported" setup=[UrlParamsFixture, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        files, _ = bundle()
        requests = String[]
        missing_files = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        # `/live/…` is the app; `/static/…` the exported files, as a static host
        # serves them (no app behind it, the query ignored).
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            endswith(path, "/test-assets/htmx.min.js") &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            if startswith(path, "/static/")
                name = path[length("/static/")+1:end]
                push!(requests, name)
                haskey(files, name) && return HTTP.Response(200, ["Content-Type" => "text/html"], files[name])
                push!(missing_files, name)
                return HTTP.Response(404)
            end
            target = replace(String(req.target), r"^/live" => "")
            push!(requests, target)
            dispatch(req.method, isempty(target) ? "/" : target; headers=collect(req.headers))
        end
        # Each run asks for exactly these, once each: one request per change,
        # no reload of an element the address already matches.
        runs = (
            ("live/?k=4.0&m=b", 10, ["/?k=4.0&m=b", "/probe?kenn=b", "/alarms?k=4.0", "/alarms?k=5.0",
                                     "/probe?kenn=c", "/alarms?k=3.0"]),
            ("live/", 7, ["/", "/probe?kenn=a", "/alarms?k=4.0", "/probe?kenn=b"]),
            ("live/?k=9.0&m=x", 3, ["/?k=9.0&m=x", "/probe?kenn=a"]),
            ("static/index.html?k=4.0&m=b", 10, ["index.html", "probe-kenn-b.html", "alarms-k-4.0.html",
                                                 "alarms-k-5.0.html", "probe-kenn-c.html", "alarms-k-3.0.html"]),
            ("static/index.html", 7, ["index.html", "probe-kenn-a.html", "alarms-k-4.0.html", "probe-kenn-b.html"]),
            ("static/index.html?k=9.0&m=x", 3, ["index.html", "probe-kenn-a.html"]))
        try
            for (url, n, expected) in runs
                empty!(requests)
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/$url`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                isnothing(checks) && continue
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == n
                @test sort(requests) == sort(expected)
                all(endswith(":true"), lines) && sort(requests) == sort(expected) ||
                    @info "url_params browser run" url checks=join(lines, "\n") requests=join(requests, "\n")
            end
            @test isempty(missing_files)
        finally
            close(server)
        end
    end
end

@testitem "a selector changed while the address's value loads loads the selected one" setup=[UrlParamsFixture, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        files, _ = bundle(PickedUrlParamsApp())
        requests = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        # The page renders the part for 3.0; the address asks for 4.0, whose
        # answer is held back so that the selector changes while it loads.
        held = ("/picked?k=4.0", "picked-k-4.0.html")
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            endswith(path, "/test-assets/htmx.min.js") &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            target = startswith(path, "/static/") ? path[length("/static/")+1:end] :
                replace(String(req.target), r"^/live" => "")
            push!(requests, target)
            target in held && sleep(1.0)
            startswith(path, "/static/") ?
                HTTP.Response(200, ["Content-Type" => "text/html"], files[target]) :
                dispatch(req.method, isempty(target) ? "/" : target; headers=collect(req.headers))
        end
        runs = (
            ("live/?k=4.0", ["/?k=4.0", "/picked?k=4.0", "/picked?k=5.0"]),
            ("static/index.html?k=4.0", ["index.html", "picked-k-4.0.html", "picked-k-5.0.html"]))
        try
            for (url, expected) in runs
                empty!(requests)
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/$url`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                isnothing(checks) && continue
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == 6
                @test sort(requests) == sort(expected)
                all(endswith(":true"), lines) && sort(requests) == sort(expected) ||
                    @info "url_params selector run" url checks=join(lines, "\n") requests=join(requests, "\n")
            end
        finally
            close(server)
        end
    end
end

@testitem "a link to a value answered through a poller writes it into the address" setup=[UrlParamsFixture] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets, Treebars
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        # The plain poller, whose terminal unwraps to the list, and the kept
        # terminal tree, which holds it.
        for keep_terminal_tree in (false, true)
            HTMXObjects._clear_operation_polls!()
            route!(SlowUrlParamsApp(); operation_policy=OperationPolicy(:auto; keep_terminal_tree))
            receipt = Channel{String}(1)
            requests = String[]
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2])
            close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
                path = HTTP.URI(req.target).path
                path == "/test-assets/htmx.min.js" &&
                    return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
                path == "/favicon.ico" && return HTTP.Response(204)
                if path == "/complete"
                    isready(receipt) || put!(receipt, String(req.target))
                    return HTTP.Response(204)
                end
                push!(requests, String(req.target))
                dispatch(req.method, String(req.target); headers=collect(req.headers))
            end
            try
                page = "http://127.0.0.1:$port/?k=4.0"
                mktempdir() do profile
                    cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $page`
                    process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                    try
                        @test timedwait(() -> isready(receipt) || process_exited(process), 30; pollint=0.05) === :ok
                        outcome = isready(receipt) ? take!(receipt) : "no receipt"
                        @test outcome == "/complete?status=passed"
                        outcome == "/complete?status=passed" ||
                            @info "url_params through a poller" keep_terminal_tree outcome requests=join(requests, "\n")
                    finally
                        process_exited(process) || kill(process)
                        wait(process)
                    end
                end
                # The list loaded k = 4.0 once, for the address; the poller's
                # result was not followed by a request for the old value.
                loads = filter(t -> !contains(t, "__htmxo_poll=1"), requests)
                @test loads == ["/?k=4.0", "/alarms?k=4.0", "/alarms?k=5.0", "/alarms?k=3.0"]
                @test any(t -> startswith(t, "/alarms?k=5.0&__htmxo_poll=1"), requests)
            finally
                close(server)
            end
        end
    end
end
