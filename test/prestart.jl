using TestItemRunner

# A load-triggered fragment (`lazy(url)`) used to start computing only when the
# browser asked for it, after the page had arrived and htmx had started. A page
# `serve` sends to a browser now starts those operations while it renders and
# adds each one's token to the fragment's `hx-get`, so the browser's request
# joins the running operation (`serve(; prestart)`, todo `0p1mocj`).
@testmodule PrestartFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h

    export PrestartApp, PrestartBrowserApp, reset_prestart!, release!, runs, served_get,
        body_text, with_prestart, prestart_token, fragment_url, poll_url,
        running, settle, RAW_RUNS

    const prestart_lock = ReentrantLock()
    const gates = Dict{String,Base.Event}()
    const counts = Dict{String,Int}()
    const RAW_RUNS = Ref(0)

    function reset_prestart!()
        lock(prestart_lock) do
            foreach(notify, values(gates))   # free what an earlier item left waiting
            empty!(gates)
            empty!(counts)
        end
        RAW_RUNS[] = 0
        HTMXObjects._clear_operation_polls!()
        nothing
    end

    gate(key) = lock(() -> get!(Base.Event, gates, key), prestart_lock)
    release!(key) = notify(gate(key))
    runs(key) = lock(() -> get(counts, key, 0), prestart_lock)

    function work(key)
        lock(() -> (counts[key] = get(counts, key, 0) + 1), prestart_lock)
        wait(gate(key))
        h.p("fragment-$key")
    end

    @htmx struct PrestartApp
        "The page"
        @get prestart_page() = h.section(
            lazy(query_url(__self__/"prestart_fragment"; key="a"); id="frag-a"),
            h.div(; hx_get=query_url(__self__/"prestart_fragment"; key="every"),
                  hx_trigger="load, every 2s"),
            h.div(; hx_vals="{\"x\": 1}")(
                lazy(query_url(__self__/"prestart_fragment"; key="vals"))),
            h.div(; hx_get=query_url(__self__/"prestart_fragment"; key="revealed"),
                  hx_trigger="revealed"),
            lazy("//example.com/prestart_fragment?key=external"),
            lazy(query_url(__self__/"prestart_direct"; key="direct")),
            lazy(string(__self__/"prestart_raw")),
            # Root-absolute: past a proxy's prefix, another server's address.
            lazy("/prestart_outside"),
        )
        "A page whose fragment lacks its required argument"
        @get prestart_broken_page() =
            h.section(lazy(string(__self__/"prestart_fragment"); id="broken"))
        "One fragment"
        @get prestart_fragment(; key::String) = work(key)
        "A fragment that answers inline"
        @direct @get prestart_direct(; key::String) = work(key)
        "A fragment that answers at once"
        @get prestart_outside() = h.p("outside")
    end

    # A page in the full shell, for Chrome: its fragment lands where the driver
    # waits for it, which then writes what it found into `#checks`.
    const BROWSER_DRIVER = h.script(HTMXObjects.Raw(raw"""
    window.addEventListener('load', async function () {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      for (let n = 0; n < 200 && !document.querySelector('#browser-part-done'); n++) await sleep(25);
      const done = document.querySelector('#browser-part-done');
      const result = document.createElement('pre'); result.id = 'checks';
      result.textContent = 'landed=' + Boolean(done) + ' text=' + (done ? done.textContent : '') +
        ' placeholder=' + Boolean(document.querySelector('[hx-get*="prestart_browser_part"]'));
      document.body.appendChild(result);
    });
    """))

    @htmx struct PrestartBrowserApp
        __page__(body) = htmx(h.main(body); assets=:vendor, pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        "The page"
        @get prestart_browser() = h.section(
            lazy("/prestart_browser_part?key=browser"; id="browser-part"),
            BROWSER_DRIVER)
        "Its fragment"
        @get prestart_browser_part(; key::String) =
            h.p(work(key).children...; id="browser-part-done")
    end

    body_text(response) = String(HTMXObjects._message_body_bytes(response))

    # A request as `serve` hands it to its pipeline.
    function served_get(target, headers::Pair{String,String}...)
        req = HTTP.Request("GET", target, collect(headers), UInt8[])
        req.context[:htmxo_served] = true
        HTMXObjects._fallback_middleware(HTMXObjects.ROUTER)(req)
    end

    # Run `f` with prestarts on, as `serve(; middleware)` turns them on.
    function with_prestart(f; middleware=[])
        previous = HTMXObjects._PRESTART_APP[]
        HTMXObjects._PRESTART_APP[] = HTMXObjects._prestart_pipeline(middleware)
        try
            f()
        finally
            HTMXObjects._PRESTART_APP[] = previous
        end
    end

    # The token the page added to the fragment `key`, or `nothing`.
    function prestart_token(body, key)
        found = match(Regex("hx-get=\"[^\"]*key=$key&amp;__htmxo_operation=([^\"&]+)\""), body)
        found === nothing ? nothing : only(found.captures)
    end
    fragment_url(key, token) = "/prestart_fragment?key=$key&__htmxo_operation=$token"

    running(body) = contains(body, "hx-trigger=\"every ")
    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
    function settle(get, url)
        for _ in 1:400
            response = get(url)
            response.status == 286 && return response
            sleep(0.025)
        end
        error("operation never settled: $url")
    end
end

@testitem "a browser page starts its load-triggered fragments and the browser's request joins them" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    HTTP.register!(HTMXObjects.ROUTER, "GET", "/prestart_raw",
        _ -> (RAW_RUNS[] += 1; HTTP.Response(200, "raw")))
    hx = ("HX-Request" => "true", "HX-Target" => "frag-a", "HX-Trigger" => "frag-a")
    with_prestart() do
        page = body_text(served_get("/prestart_page", "Accept" => "text/html"))
        token = prestart_token(page, "a")
        @test token !== nothing
        # It runs before any browser asked for it.
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
        entry = HTMXObjects._operation_polls[token]
        @test entry.prestarted && entry.polls == 0
        # The rest is the browser's to request: a trigger that repeats, values
        # only the browser evaluates, a lazy trigger, another server, a route
        # that answers inline, and a route `@htmx` does not handle.
        for key in ("every", "vals", "revealed", "external", "direct")
            @test prestart_token(page, key) === nothing
            @test runs(key) == 0
        end
        @test occursin("hx-get=\"/prestart_raw\"", page)
        @test RAW_RUNS[] == 0
        # With no proxy prefix, a root-absolute address is this server's.
        @test occursin("hx-get=\"/prestart_outside?__htmxo_operation=", page)

        # The browser's request joins it: the poller it gets polls the same
        # operation, and nothing is computed a second time.
        attach = body_text(served_get(fragment_url("a", token), hx...))
        @test running(attach)
        @test contains(poll_url(attach), "__htmxo_operation=$token")
        @test entry.polls == 1
        release!("a")
        final = settle(url -> served_get(url, hx...), poll_url(attach))
        @test contains(body_text(final), "fragment-a")
        @test runs("a") == 1
    end
    # An htmx swap of the same page prestarts too.
    reset_prestart!()
    with_prestart() do
        page = body_text(served_get("/prestart_page", "HX-Request" => "true"))
        @test prestart_token(page, "a") !== nothing
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
    end
    release!("a")
end

@testitem "a prestart that finished is answered bare to the browser's first request" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    with_prestart() do
        release!("a")   # computes at once
        page = body_text(served_get("/prestart_page", "Accept" => "text/html"))
        token = prestart_token(page, "a")
        @test token !== nothing
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
        sleep(0.2)
        answer = served_get(fragment_url("a", token), "HX-Request" => "true",
                            "HX-Target" => "frag-a")
        body = body_text(answer)
        @test answer.status == 200
        @test contains(body, "fragment-a")
        @test !running(body)
        @test runs("a") == 1
    end
end

@testitem "only a response a browser receives from serve prestarts" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    nav = "Accept" => "text/html"
    with_prestart() do
        # A script, an in-process dispatch, a Markdown read.
        @test prestart_token(body_text(served_get("/prestart_page")), "a") === nothing
        @test prestart_token(body_text(dispatch(:GET, "/prestart_page";
            headers=[nav])), "a") === nothing
        @test !occursin("__htmxo_operation",
            body_text(served_get("/prestart_page?plain", nav)))
        @test !occursin("__htmxo_operation",
            body_text(served_get("/prestart_page", "Accept" => "text/markdown")))
        # A fetch that does not ask for a page.
        @test prestart_token(body_text(served_get("/prestart_page",
            "Accept" => "*/*")), "a") === nothing
    end
    # `serve(; prestart=false)`.
    @test HTMXObjects._PRESTART_APP[] === nothing
    @test prestart_token(body_text(served_get("/prestart_page", nav)), "a") === nothing
    sleep(0.2)
    @test runs("a") == 0
    @test isempty(HTMXObjects._operation_polls)
end

@testitem "a prestart goes through the app's middleware with the page's credentials" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    seen = HTTP.Request[]
    guard(handler) = function (req)
        startswith(req.target, "/prestart_fragment") && push!(seen, req)
        startswith(req.target, "/prestart_fragment") &&
            HTTP.header(req, "Cookie") != "session=ok" &&
            return HTTP.Response(401)
        handler(req)
    end
    nav = "Accept" => "text/html"
    with_prestart(; middleware=[guard]) do
        # Refused without the cookie: the browser's request goes through the
        # same refusal itself.
        @test prestart_token(body_text(served_get("/prestart_page", nav)), "a") === nothing
        @test length(seen) == 1
        page = body_text(served_get("/prestart_page", nav, "Cookie" => "session=ok",
            "Accept-Language" => "de", "If-None-Match" => "\"x\"",
            "HX-Boosted" => "true", "Sec-Fetch-Dest" => "document"))
        @test prestart_token(page, "a") !== nothing
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
        req = seen[end]
        @test HTTP.header(req, "Cookie") == "session=ok"
        @test HTTP.header(req, "Accept-Language") == "de"
        @test HTTP.header(req, "HX-Request") == "true"
        @test HTTP.header(req, "HX-Target") == "frag-a"
        @test HTTP.header(req, "HX-Trigger") == "frag-a"
        @test HTTP.header(req, "Accept") == "*/*"
        @test isempty(HTTP.header(req, "If-None-Match"))
        @test isempty(HTTP.header(req, "HX-Boosted"))
        @test isempty(HTTP.header(req, "Sec-Fetch-Dest"))
    end
    release!("a")
end

@testitem "behind a path-stripping proxy a prestart reaches the route without the prefix" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    with_prestart() do
        page = body_text(served_get("/prestart_page", "Accept" => "text/html",
            "X-Forwarded-Prefix" => "/p/app"))
        # The app's own address carries the prefix the browser needs, and the
        # prestart reaches the route without it.
        token = prestart_token(page, "a")
        @test token !== nothing
        @test occursin("hx-get=\"/p/app/prestart_fragment?key=a&amp;__htmxo_operation=$token\"", page)
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
        # A root-absolute address leads past the proxy to another server.
        @test occursin("hx-get=\"/prestart_outside\"", page)
    end
    @test HTMXObjects._prestart_route_target(
        HTTP.Request("GET", "/x", ["X-Forwarded-Prefix" => "/p/app"]), "/p/app") == "/"
    @test HTMXObjects._prestart_route_target(
        HTTP.Request("GET", "/x", ["X-Forwarded-Prefix" => "/p/app"]), "/p/app?y=1") == "/?y=1"
    @test HTMXObjects._prestart_route_target(
        HTTP.Request("GET", "/x", ["X-Forwarded-Prefix" => "/p/app"]), "/p/apple") === nothing
    # A proxy that keeps the prefix in the path.
    @test HTMXObjects._prestart_route_target(
        HTTP.Request("GET", "/p/app/x", ["X-Forwarded-Prefix" => "/p/app"]),
        "/p/app/y") == "/p/app/y"
    release!("a")
end

@testitem "a prestart that fails before it starts records nothing, the browser's request does" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            with_prestart() do
                page = body_text(served_get("/prestart_broken_page",
                    "Accept" => "text/html"))
                @test occursin("hx-get=\"/prestart_fragment\"", page)
                @test isempty(readdir(dir))
                answer = served_get("/prestart_fragment", "HX-Request" => "true",
                    "HX-Target" => "broken")
                @test contains(body_text(answer), "Missing required parameter: key")
                @test length(readdir(dir)) == 1
            end
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
end

@testitem "load-only triggers qualify for a prestart" tags=[:unit] begin
    using HTMXObjects, Test
    load_only = HTMXObjects._prestart_load_only
    @test load_only("load")
    @test load_only(" load once ")
    @test load_only("load delay:200ms")
    @test load_only("load delay:1s, load")
    @test !load_only("load, every 2s")
    @test !load_only("every 1s")
    @test !load_only("load[ready]")
    @test !load_only("revealed")
    @test !load_only("intersect once")
    @test !load_only("load from:body")
    @test !load_only("click")
end

@testitem "a prestart no browser asked for is logged unclaimed" setup=[PrestartFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Logging, Test

    reset_prestart!()
    route!(PrestartApp())
    records = HTMXObjects.OperationRecord[]
    logger = Test.TestLogger()
    previous = HTMXObjects.OPERATION_LOG[]
    HTMXObjects.OPERATION_LOG[] = (io, record) -> begin
        push!(records, record)
        HTMXObjects._default_operation_log(io, record)
    end
    try
        with_logger(logger) do
            with_prestart() do
                page = body_text(served_get("/prestart_page", "Accept" => "text/html"))
                @test prestart_token(page, "a") !== nothing
            end
            release!("a")
            @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
            later = HTMXObjects._operation_poll_now() + HTMXObjects._OPERATION_POLL_TTL
            @test isempty(HTMXObjects._operation_poll_snapshot(; now=later))
        end
    finally
        HTMXObjects.OPERATION_LOG[] = previous
    end
    # The fragment and the one that answers at once.
    @test length(records) == 2
    @test all(r -> r.outcome === :unclaimed && r.polls == 0 && isnan(r.answered), records)
    @test count(r -> r.target == "/prestart_fragment?key=a", records) == 1
    lines = [string(l.message) for l in logger.logs if l.group === :operation]
    @test length(lines) == 2
    @test all(line -> occursin(r" unclaimed compute=\S+ answered=- polls=0$", line), lines)
end

@testitem "serve prestarts a page's fragments and serve(; prestart=false) does not" setup=[PrestartFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test

    reset_prestart!()
    route!(PrestartApp())
    nav = ["Accept" => "text/html"]
    hx = ["HX-Request" => "true", "HX-Target" => "frag-a", "HX-Trigger" => "frag-a"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing)
    try
        page = String(HTTP.get(base * "/prestart_page", nav; retry=false).body)
        token = prestart_token(page, "a")
        @test token !== nothing
        @test timedwait(() -> runs("a") == 1, 10.0; pollint=0.01) === :ok
        attach = String(HTTP.get(base * fragment_url("a", token), hx; retry=false).body)
        @test running(attach)
        release!("a")
        final = settle(url -> HTTP.get(base * url, hx; retry=false, status_exception=false),
                       poll_url(attach))
        @test contains(String(final.body), "fragment-a")
        @test runs("a") == 1
    finally
        terminate()
    end
    @test HTMXObjects._PRESTART_APP[] === nothing

    reset_prestart!()
    port = free_port()
    base = "http://127.0.0.1:$port"
    serve(; port, async=true, access_log=nothing, operation_log=nothing, prestart=false)
    try
        page = String(HTTP.get(base * "/prestart_page", nav; retry=false).body)
        @test prestart_token(page, "a") === nothing
        sleep(0.2)
        @test runs("a") == 0
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
end

@testitem "a prestarted fragment lands in Chrome through the address the page gave it" setup=[PrestartFixtures, HTMXOTestPorts, ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Test
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_prestart!()
        route!(PrestartBrowserApp())
        vendorfiles()
        targets = String[]
        recorder(handler) = req -> (push!(targets, req.target); handler(req))
        port = free_port()
        operation_log = HTMXObjects.OPERATION_LOG[]
        serve(; port, async=true, access_log=nothing, operation_log=nothing,
              middleware=[recorder])
        try
            release!("browser")
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/prestart_browser`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test checks !== nothing
            checks === nothing || @test checks[1] == "landed=true text=fragment-browser placeholder=false"
            # The page's own prestart, then the browser's request joining it.
            parts = filter(t -> startswith(t, "/prestart_browser_part"), targets)
            @test parts[1] == "/prestart_browser_part?key=browser"
            @test any(t -> occursin("__htmxo_operation=", t), parts[2:end])
            @test runs("browser") == 1
        finally
            terminate()
            HTMXObjects.OPERATION_LOG[] = operation_log
        end
    end
end
