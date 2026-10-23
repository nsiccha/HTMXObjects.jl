using TestItemRunner

# A running `:auto` poller learned that its operation had ended at its next
# poll, and polled five times a second until then. Under `serve(;
# operation_stream=true)` the page holds one event stream that announces each
# operation's end, the poller then fetches its answer at once, and while the
# stream is open its timer polls go out at most once a second (todo `0p1mocj`,
# stage 2).
@testmodule OperationStreamFixtures begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h

    export StreamApp, StreamBrowserApp, reset_stream!, release!, runs, poll_url,
        stream_token, open_stream, events_until, BEACONS

    const stream_lock = ReentrantLock()
    const gates = Dict{String,Base.Event}()
    const counts = Dict{String,Int}()
    const BEACONS = Tuple{Float64,String}[]

    function reset_stream!()
        lock(stream_lock) do
            foreach(notify, values(gates))   # free what an earlier item left waiting
            empty!(gates)
            empty!(counts)
            empty!(BEACONS)
        end
        HTMXObjects._clear_operation_polls!()
        nothing
    end

    gate(key) = lock(() -> get!(Base.Event, gates, key), stream_lock)
    release!(key) = notify(gate(key))
    runs(key) = lock(() -> get(counts, key, 0), stream_lock)

    function work(key)
        lock(() -> (counts[key] = get(counts, key, 0) + 1), stream_lock)
        wait(gate(key))
        h.p("fragment-$key"; id="done-$key")
    end

    @htmx struct StreamApp
        "A page"
        @get stream_page() = h.p("page")
        "A slow fragment"
        @get stream_fragment(; key::String) = work(key)
    end

    # A page in the full shell, for Chrome. Its driver reports to the server
    # when the fragment's poller is on the page and when the fragment landed.
    const BROWSER_DRIVER = h.script(HTMXObjects.Raw(raw"""
    window.addEventListener('load', async function () {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const beacon = text => fetch('/stream_beacon?text=' + encodeURIComponent(text));
      let n = 0;
      for (; n < 400 && !document.querySelector('[data-htmxo-operation-stream]'); n++) await sleep(25);
      await beacon(n < 400 ? 'polling' : 'no-poller');
      for (n = 0; n < 1200 && !document.querySelector('#done-browser'); n++) await sleep(25);
      await beacon(n < 1200 ? 'landed' : 'never-landed');
    });
    """))

    @htmx struct StreamBrowserApp
        __page__(body) = htmx(h.main(body); assets=:vendor, pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        "The page"
        @get stream_browser() = h.section(
            lazy("/stream_browser_part?key=browser"; id="part"), BROWSER_DRIVER)
        "Its fragment"
        @get stream_browser_part(; key::String) = work(key)
        "Where the driver reports"
        @get stream_beacon(; text::String="") =
            (lock(() -> push!(BEACONS, (time(), text)), stream_lock); h.p("ok"))
    end

    function poll_url(body)
        found = match(r"hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\"", body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
    stream_token(url) = only(match(r"__htmxo_operation=([0-9a-f]{64})", url).captures)

    # A raw connection reading a stream, so the test sees each event as the
    # server writes it. Returns the socket and a buffer its reader fills.
    function open_stream(port, target; headers=["Accept" => "text/event-stream"])
        sock = Sockets.connect("127.0.0.1", port)
        head = join(("$k: $v\r\n" for (k, v) in headers), "")
        write(sock, "GET $target HTTP/1.1\r\nHost: localhost\r\n$(head)\r\n")
        buffer = IOBuffer()
        buffer_lock = ReentrantLock()
        reader = @async try
            while isopen(sock)
                chunk = readavailable(sock)
                isempty(chunk) && eof(sock) && break
                lock(() -> write(buffer, chunk), buffer_lock)
            end
        catch err
            err isa Base.IOError || err isa EOFError || rethrow()
        end
        received() = lock(() -> String(copy(buffer.data[1:buffer.size])), buffer_lock)
        (; sock, received, reader)
    end

    # The stream's text once it contains `needle`; an error after `timeout`.
    function events_until(stream, needle; timeout=15)
        t0 = time()
        while !contains(stream.received(), needle)
            time() - t0 > timeout &&
                error("stream never sent $(repr(needle)): $(repr(stream.received()))")
            sleep(0.005)
        end
        stream.received()
    end
end

@testitem "a stream request is a GET with __htmxo_operations that accepts an event stream" tags=[:unit] begin
    using HTMXObjects, HTTP, Test
    tokens(target, headers=["Accept" => "text/event-stream"]; method="GET") =
        HTMXObjects._operation_stream_tokens(HTTP.Request(method, target, headers, UInt8[]))
    a, b = repeat("a", 64), repeat("b", 64)
    @test tokens("/page") === nothing
    @test tokens("/page?x=1") === nothing
    @test tokens("/page?__htmxo_operations=$a", ["Accept" => "text/html"]) === nothing
    @test tokens("/page?__htmxo_operations=$a"; method="POST") === nothing
    @test tokens("/page?__htmxo_operations=$a") == [a]
    # Malformed and repeated tokens are dropped; at most 32 are followed.
    @test tokens("/page?__htmxo_operations=$a,nope,$a,$b") == [a, b]
    many = [string(i; base=16, pad=64) for i in 1:40]
    @test tokens("/x?__htmxo_operations=" * join(many, ",")) == many[1:32]
    # The stream-failure probe asks for no event stream, and is one too.
    @test tokens("/page?__htmxo_operations=$a", ["X-HTMXO-Probe" => "stream"]) == [a]

    # Only a poller rendered for a request `serve` received is marked.
    HTMXObjects._OPERATION_STREAM[] = true
    try
        served = HTTP.Request("GET", "/")
        served.context[:htmxo_served] = true
        @test HTMXObjects._operation_stream_wanted(served)
        @test !HTMXObjects._operation_stream_wanted(HTTP.Request("GET", "/"))
    finally
        HTMXObjects._OPERATION_STREAM[] = false
    end
    @test !HTMXObjects._operation_stream_wanted(HTTP.Request("GET", "/"))
end

@testitem "serve announces when a poller's operation ends, after the app's middleware" setup=[OperationStreamFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test

    reset_stream!()
    route!(StreamApp())
    seen = String[]
    recorder(handler) = req -> (push!(seen, req.target); handler(req))
    hx = ["HX-Request" => "true"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing,
          middleware=[recorder])
    try
        first = String(HTTP.get(base * "/stream_fragment?key=a", hx; retry=false).body)
        @test contains(first, "data-htmxo-operation-stream")
        url = poll_url(first)
        token = stream_token(url)
        unknown = repeat("0", 64)

        stream = open_stream(port, "/stream_page?__htmxo_operations=$token,$unknown")
        try
            # A token the server does not hold is gone at once; the running
            # one is announced only when its computation has ended.
            text = events_until(stream, "event: gone\ndata: $unknown\n\n")
            @test contains(text, "text/event-stream")
            sleep(0.3)
            @test !contains(stream.received(), "event: ready")
            release!("a")
            text = events_until(stream, "event: ready\ndata: $token\n\n")
            # Every operation sent: the stream closes.
            text = events_until(stream, "event: close")
            @test count("event: ready", text) == 1
        finally
            close(stream.sock)
        end
        # The stream went through the app's middleware like any request.
        @test any(t -> contains(t, "__htmxo_operations=$token"), seen)

        # The poll the page then sends answers the result and ends the poll.
        final = HTTP.get(base * url, hx; retry=false, status_exception=false)
        @test final.status == 286
        @test contains(String(final.body), "fragment-a")
        @test runs("a") == 1

        # An operation that ended before the stream opened is ready at once.
        second = String(HTTP.get(base * "/stream_fragment?key=b", hx; retry=false).body)
        token_b = stream_token(poll_url(second))
        release!("b")
        @test timedwait(() -> runs("b") == 1, 10.0; pollint=0.01) === :ok
        sleep(0.1)
        stream = open_stream(port, "/stream_page?__htmxo_operations=$token_b")
        try
            events_until(stream, "event: ready\ndata: $token_b\n\n")
        finally
            close(stream.sock)
        end

        # A stream request that accepts no event stream is an ordinary request.
        plain = HTTP.get(base * "/stream_page?__htmxo_operations=$token_b";
                         retry=false, status_exception=false)
        @test plain.status == 200
        @test !contains(HTTP.header(plain, "Content-Type", ""), "event-stream")
        # The stream-failure probe gets the stream routes' empty answer.
        probe = HTTP.get(base * "/stream_page?__htmxo_operations=$token_b",
                         ["X-HTMXO-Probe" => "stream"]; retry=false, status_exception=false)
        @test probe.status == 204
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
    @test HTMXObjects._OPERATION_STREAM[] == false
end

@testitem "serve(; operation_stream=false) marks no poller and answers no stream" setup=[OperationStreamFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test

    reset_stream!()
    route!(StreamApp())
    hx = ["HX-Request" => "true"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing,
          operation_stream=false)
    try
        first = String(HTTP.get(base * "/stream_fragment?key=c", hx; retry=false).body)
        @test contains(first, "__htmxo_poll=1")
        @test !contains(first, "data-htmxo-operation-stream")
        token = stream_token(poll_url(first))
        page = HTTP.get(base * "/stream_page?__htmxo_operations=$token",
                        ["Accept" => "text/event-stream"]; retry=false, status_exception=false)
        @test page.status == 200
        @test contains(String(page.body), "page")
        @test !contains(HTTP.header(page, "Content-Type", ""), "event-stream")
    finally
        release!("c")
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
end

@testitem "a streamed fragment lands in Chrome when its operation ends, polling about once a second" setup=[OperationStreamFixtures, HTMXOTestPorts] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Test
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_stream!()
        route!(StreamBrowserApp())
        vendorfiles()
        requests = Tuple{Float64,String}[]
        recorder(handler) = req -> (push!(requests, (time(), req.target)); handler(req))
        beacon(text) = findfirst(b -> b[2] == text, BEACONS)
        port = free_port()
        operation_log = HTMXObjects.OPERATION_LOG[]
        serve(; port, async=true, access_log=nothing, operation_log=nothing,
              middleware=[recorder])
        released = Ref(NaN)
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/stream_browser`
                proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> beacon("polling") !== nothing, 60.0; pollint=0.02) === :ok
                    @test timedwait(() -> any(r -> contains(r[2], "__htmxo_operations="), requests),
                                    10.0; pollint=0.01) === :ok
                    # Three seconds of a running operation on an open stream.
                    sleep(3.0)
                    released[] = time()
                    release!("browser")
                    @test timedwait(() -> beacon("landed") !== nothing ||
                                          beacon("never-landed") !== nothing,
                                    30.0; pollint=0.01) === :ok
                finally
                    process_exited(proc) || kill(proc)
                    wait(proc)
                end
            end
            landed = beacon("landed")
            @test landed !== nothing
            # The result followed the end of the operation, not a once-a-second
            # timer poll.
            landed === nothing || @test BEACONS[landed][1] - released[] < 0.5
            # While the operation ran, its poller polled about once a second
            # instead of five times (3 s at 200 ms would be 15 polls).
            streamed_from = first(r[1] for r in requests if contains(r[2], "__htmxo_operations="))
            polls = count(r -> streamed_from <= r[1] <= released[] &&
                               contains(r[2], "__htmxo_poll=1"), requests)
            @test polls <= 5
            @test runs("browser") == 1
        finally
            release!("browser")
            terminate()
            HTMXObjects.OPERATION_LOG[] = operation_log
        end
    end
end
