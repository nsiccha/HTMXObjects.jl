using TestItemRunner

# A running `:auto` read showed only its progress tree until the route
# returned. `send_ahead(content)` puts finished parts in front of the reader:
# each lands once, in order, above the tree, and the finished answer replaces
# them (snag `an-auto-read-on-8585ef04`, design decision `036a5ea`).
@testmodule SentAheadFixtures begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h, Raw

    export AheadApp, AheadSharedApp, AheadBrowserApp, reset_ahead!, release!, runs,
        poll_url, stream_token, open_stream, events_until, frames, carriers, BEACONS,
        beacon, seen, ahead_frames, aheads_until

    const ahead_lock = ReentrantLock()
    const gates = Dict{String,Base.Event}()
    const counts = Dict{String,Int}()
    const BEACONS = Tuple{Float64,String}[]

    function reset_ahead!()
        lock(ahead_lock) do
            foreach(notify, values(gates))   # free what an earlier item left waiting
            empty!(gates)
            empty!(counts)
            empty!(BEACONS)
        end
        HTMXObjects._clear_operation_polls!()
        nothing
    end

    gate(key) = lock(() -> get!(Base.Event, gates, key), ahead_lock)
    release!(key) = notify(gate(key))
    runs(key) = lock(() -> get(counts, key, 0), ahead_lock)
    beacon(text) = lock(() -> findfirst(b -> b[2] == text, BEACONS), ahead_lock)

    # Sends a part, waits for `<key>-1`, sends another, waits for `<key>-2`.
    function staged(key)
        lock(() -> (counts[key] = get(counts, key, 0) + 1), ahead_lock)
        send_ahead(h.p("first-$key"; id="first-$key"))
        wait(gate("$key-1"))
        send_ahead(h.p("second-$key"; id="second-$key"))
        wait(gate("$key-2"))
        h.p("final-$key"; id="final-$key")
    end

    @htmx struct AheadApp
        "A page"
        @get ahead_page() = h.p("page")
        "A slow fresh read that sends two parts ahead"
        @fresh @get ahead_fresh(; key::String) = staged(key)
        "A slow read that sends nothing ahead"
        @fresh @get ahead_quiet(; key::String) = (wait(gate("$key-1")); h.p("quiet-$key"))
        "A read that finishes within the grace period"
        @fresh @get ahead_fast(; key::String) =
            (send_ahead(h.p("fast-part-$key")); h.p("fast-$key"))
    end

    # A memoized read on a retained root, so several requests follow one
    # computation (the default root is built fresh for each request).
    @htmx struct AheadSharedApp
        "A slow memoized read that sends two parts ahead"
        @get ahead_shared(; key::String) = staged(key)
    end

    # The beacon the browser driver sent that starts with `prefix`, or `nothing`.
    seen(prefix) = lock(ahead_lock) do
        i = findfirst(b -> startswith(b[2], prefix), BEACONS)
        i === nothing ? nothing : BEACONS[i][2]
    end

    # The browser item's route: a typed-empty "figure" (a list), a script part
    # that adds one row and counts how often it ran, then an out-of-band part
    # that adds another row, then the finished answer.
    function browser_staged(key)
        send_ahead(h.div(; id="frame-$key")(h.p("frame"), h.ul(; id="rows-$key")))
        send_ahead(h.script(Raw("""
            window.__aheadRuns = window.__aheadRuns || {};
            window.__aheadRuns['$key'] = (window.__aheadRuns['$key'] || 0) + 1;
            var li = document.createElement('li'); li.textContent = 'scripted';
            document.getElementById('rows-$key').appendChild(li);
            """)))
        wait(gate("$key-1"))
        send_ahead(h.div(; hx_swap_oob="beforeend:#rows-$key")(h.li("swapped")))
        wait(gate("$key-2"))
        h.p("final-$key"; id="final-$key")
    end

    # Reports to the server: the first part on the page, both rows and how
    # often the script part ran, the finished answer and what is left of the
    # parts; then the same for a refresh of a live element holding a result.
    const BROWSER_DRIVER = h.script(Raw(raw"""
    (function () {
    window.addEventListener('load', async function () {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const beacon = text => fetch('/ahead_beacon?text=' + encodeURIComponent(text));
      const until = async (test, n) => { for (let i = 0; i < n; i++) { if (test()) return true; await sleep(25); } return false; };
      const runs = key => (window.__aheadRuns || {})[key] || 0;
      const regions = () => document.querySelectorAll('.htmxo-sent-ahead').length;
      await beacon(await until(() => document.querySelector('.htmxo-sent-ahead #frame-browser'), 1200) ? 'frame' : 'no-frame');
      await beacon(await until(() => document.querySelectorAll('#rows-browser li').length === 2, 1200) ?
        'rows:' + runs('browser') : 'no-rows');
      await beacon(await until(() => document.querySelector('#final-browser'), 1200) ?
        'final:' + regions() + ':' + runs('browser') + ':' + !!document.querySelector('#frame-browser') : 'no-final');
      // A live element already shows a result; its refresh's first part replaces it.
      htmx.ajax('GET', '/ahead_browser_part?key=live', { target: '#live', swap: 'innerHTML' });
      await beacon(await until(() => document.querySelector('#live #frame-live'), 1200) ?
        'live-frame:' + !!document.querySelector('#old') : 'no-live-frame');
      await beacon(await until(() => document.querySelector('#live #final-live'), 1200) ?
        'live-final:' + regions() + ':' + runs('live') : 'no-live-final');
    });
    })();
    """))

    @htmx struct AheadBrowserApp
        __page__(body) = htmx(h.main(body); assets=:vendor, pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        "The page"
        @get ahead_browser() = h.section(
            lazy("/ahead_browser_part?key=browser"; id="part"),
            h.div(; id="live", data_htmxo_live="")(h.p(; id="old")("old result")),
            BROWSER_DRIVER)
        "Its fragment"
        @fresh @get ahead_browser_part(; key::String) = browser_staged(key)
        "Where the driver reports"
        @get ahead_beacon(; text::String="") =
            (lock(() -> push!(BEACONS, (time(), text)), ahead_lock); h.p("ok"))
    end

    function poll_url(body)
        found = match(r"hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\"", body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
    stream_token(url) = only(match(r"__htmxo_operation=([0-9a-f]{64})", url).captures)

    # The numbers of the parts an answer carries.
    carriers(body) = [parse(Int, m[1]) for m in eachmatch(r"data-htmxo-part=\"([0-9]+)\"", body)]

    # A raw connection reading a stream, so the test sees each event as the
    # server writes it.
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

    # The `(event, data)` frames in a stream's text so far, `data` joined with
    # newlines as a browser joins it.
    function frames(text)
        found = Tuple{String,String}[]
        for m in eachmatch(r"event: ([a-z]+)\n((?:data: [^\n]*\n)+)\n", text)
            data = join((line[7:end] for line in split(chomp(m[2]), '\n')), '\n')
            push!(found, (String(m[1]), data))
        end
        found
    end

    # The data of the `ahead` frames in a stream's text so far.
    ahead_frames(text) = [f[2] for f in frames(text) if f[1] == "ahead"]

    # The stream's text once it holds `n` `ahead` frames.
    function aheads_until(stream, n; timeout=15)
        t0 = time()
        while length(ahead_frames(stream.received())) < n
            time() - t0 > timeout &&
                error("stream sent fewer than $n parts: $(repr(stream.received()))")
            sleep(0.005)
        end
        stream.received()
    end

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

@testitem "send_ahead outside an operation does nothing, and a started computation keeps its parts" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h

    @test send_ahead(h.p("nowhere")) === nothing
    @test HTMXObjects._SENT_AHEAD[] === nothing
    # A start whose result is no running computation binds nothing lasting.
    @test HTMXObjects._with_sent_ahead(() -> (send_ahead(h.p("x")); 1)) == 1

    html(x) = repr(MIME"text/html"(), x)
    gate = Base.Event()
    started = HTMXObjects._with_sent_ahead() do
        HTMXObjects._FreshOperation(Threads.@spawn(begin
            send_ahead(h.p("one"))
            wait(gate)
            send_ahead(h.p("two"))
            1
        end), nothing)
    end
    sink = HTMXObjects._sent_ahead_of(started)
    @test sink !== nothing
    @test timedwait(() -> length(HTMXObjects._sent_ahead_parts(sink, 0)) == 1, 10.0;
                    pollint=0.01) === :ok
    # A second start that joins the same computation: what its own list held
    # goes to the computation's, and so does everything it sends later.
    joined = HTMXObjects._with_sent_ahead() do
        send_ahead(h.p("joined"))
        started
    end
    @test joined === started
    @test HTMXObjects._sent_ahead_of(joined) === sink
    notify(gate)
    @test fetch(started) == 1
    @test last.(HTMXObjects._sent_ahead_parts(sink, 0)) ==
        html.([h.p("one"), h.p("joined"), h.p("two")])
    @test first.(HTMXObjects._sent_ahead_parts(sink, 1)) == [2, 3]
end

@testitem "an operation past its parts bound refuses the rest and records the first refusal once" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h

    dir = mktempdir()
    previous = HTMXObjects.ERROR_DIR[]
    HTMXObjects.ERROR_DIR[] = dir
    try
        sink = HTMXObjects._SentAhead()
        for i in 1:(HTMXObjects._SENT_AHEAD_PART_LIMIT + 3)
            HTMXObjects._add_part!(sink, "<p>$i</p>")
        end
        @test length(HTMXObjects._sent_ahead_parts(sink, 0)) == HTMXObjects._SENT_AHEAD_PART_LIMIT
        @test sink.refused == 3
        logs = filter(endswith(".log"), readdir(dir))
        @test length(logs) == 1
        @test contains(read(joinpath(dir, only(logs)), String), "send_ahead refused a part")
    finally
        HTMXObjects.ERROR_DIR[] = previous
    end
end

@testitem "a running poller carries the parts its page has not applied, and the stream sends each as it is added" setup=[SentAheadFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test
    import HTMXObjects: h

    reset_ahead!()
    route!(AheadApp())
    html(x) = repr(MIME"text/html"(), x)
    hx = ["HX-Request" => "true", "HX-Current-URL" => "http://localhost/ahead_page"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing)
    try
        first = String(HTTP.get(base * "/ahead_fresh?key=a", hx; retry=false).body)
        @test contains(first, "treebar-poller-inner")
        @test carriers(first) == [1]
        @test contains(first, "first-a")
        url = poll_url(first)
        token = stream_token(url)
        # A poll says how many parts its page applied, and gets only the rest.
        applied(n) = carriers(String(HTTP.get(base * url,
            [hx; "HTMXO-Sent-Ahead" => string(n)]; retry=false).body))
        @test applied(1) == Int[]
        @test applied(0) == [1]
        @test carriers(String(HTTP.get(base * url, hx; retry=false).body)) == [1]

        # A stream that pushes no answers still sends every part: the ones so
        # far when it opens, and each later one when it is added, not at a
        # clock tick (this stream has none).
        stream = open_stream(port, "/ahead_page?__htmxo_operations=$token")
        try
            @test ahead_frames(aheads_until(stream, 1)) ==
                [string(token, "\n1\n", html(h.p("first-a"; id="first-a")))]
            release!("a-1")
            text = aheads_until(stream, 2)
            @test ahead_frames(text) ==
                [string(token, "\n1\n", html(h.p("first-a"; id="first-a"))),
                 string(token, "\n2\n", html(h.p("second-a"; id="second-a")))]
            @test !any(f -> f[1] == "progress", frames(text))
            @test applied(1) == [2]
            release!("a-2")
            text = events_until(stream, "event: close")
            @test length(ahead_frames(text)) == 2
            @test any(f -> f[1] == "ready" && f[2] == token, frames(text))
        finally
            close(stream.sock)
        end
        final = HTTP.get(base * url, hx; retry=false, status_exception=false)
        @test final.status == 286
        @test contains(String(final.body), "final-a")
        @test carriers(String(final.body)) == Int[]
        @test runs("a") == 1

        # A pushing stream: its running answers carry no parts (the stream
        # sends them as `ahead` events), nor does the final answer.
        second = String(HTTP.get(base * "/ahead_fresh?key=b", hx; retry=false).body)
        token_b = stream_token(poll_url(second))
        stream = open_stream(port, "/ahead_page?__htmxo_operations=$token_b&__htmxo_push=1";
            headers=["Accept" => "text/event-stream",
                     "Referer" => "http://localhost/ahead_page"])
        try
            events_until(stream, "event: progress"; timeout=10)
            release!("b-1")
            text = aheads_until(stream, 2)
            @test ahead_frames(text)[2] ==
                string(token_b, "\n2\n", html(h.p("second-b"; id="second-b")))
            progress = [f[2] for f in frames(text) if f[1] == "progress"]
            @test !isempty(progress)
            @test all(p -> isempty(carriers(p)), progress)
            release!("b-2")
            text = events_until(stream, "event: close")
            result = only(f[2] for f in frames(text) if f[1] == "result")
            @test contains(result, "final-b")
            @test isempty(carriers(result))
        finally
            close(stream.sock)
        end

        # A read that sends nothing carries no parts.
        quiet = String(HTTP.get(base * "/ahead_quiet?key=q", hx; retry=false).body)
        @test contains(quiet, "treebar-poller-inner")
        @test isempty(carriers(quiet))
        @test !contains(quiet, "htmxo-sent-ahead")
        release!("q-1")
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
end

@testitem "Markdown, a blocking dispatch and an answer within the grace period get the finished answer alone" setup=[SentAheadFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test

    reset_ahead!()
    route!(AheadApp())
    hx = ["HX-Request" => "true"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing)
    try
        # A Markdown read waits for the finished answer and never shows parts.
        markdown = @async String(HTTP.get(base * "/ahead_fresh?key=m&plain", hx; retry=false).body)
        @test timedwait(() -> runs("m") == 1, 10.0; pollint=0.01) === :ok
        release!("m-1"); release!("m-2")
        text = fetch(markdown)
        @test contains(text, "final-m")
        @test !contains(text, "first-m")
        @test !contains(text, "second-m")

        # Neither does a blocking in-process dispatch.
        blocking = @async String(dispatch(:GET, "/ahead_fresh?key=d"; headers=hx,
                                          operation_policy=:blocking).body)
        @test timedwait(() -> runs("d") == 1, 10.0; pollint=0.01) === :ok
        release!("d-1"); release!("d-2")
        body = fetch(blocking)
        @test contains(body, "final-d")
        @test isempty(carriers(body))
        @test !contains(body, "first-d")

        # An answer within the grace period is the bare result.
        fast = String(HTTP.get(base * "/ahead_fast?key=f", hx; retry=false).body)
        @test contains(fast, "fast-f")
        @test !contains(fast, "fast-part-f")
        @test isempty(carriers(fast))
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
end

@testitem "every page that follows a memoized read on a retained root gets its parts" setup=[SentAheadFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Test

    reset_ahead!()
    route!(AheadSharedApp(); root_provider=RootProvider(scope=:job, key=_ -> "shared",
        retention=RootRetention(max_entries=4, ttl=600)))
    hx = ["HX-Request" => "true"]
    port = free_port()
    base = "http://127.0.0.1:$port"
    operation_log = HTMXObjects.OPERATION_LOG[]
    serve(; port, async=true, access_log=nothing, operation_log=nothing)
    try
        one = String(HTTP.get(base * "/ahead_shared?key=c", hx; retry=false).body)
        two = String(HTTP.get(base * "/ahead_shared?key=c", hx; retry=false).body)
        url_one, url_two = poll_url(one), poll_url(two)
        @test stream_token(url_one) != stream_token(url_two)
        @test carriers(one) == [1]
        @test carriers(two) == [1]
        release!("c-1")
        poll(url) = carriers(String(HTTP.get(base * url, hx; retry=false).body))
        @test timedwait(() -> poll(url_one) == [1, 2], 10.0; pollint=0.05) === :ok
        @test poll(url_two) == [1, 2]
        release!("c-2")
        @test runs("c") == 1
    finally
        terminate()
        HTMXObjects.OPERATION_LOG[] = operation_log
    end
end

@testitem "parts land once each in Chrome, and the finished answer replaces them" setup=[SentAheadFixtures, HTMXOTestPorts] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Test
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        reset_ahead!()
        route!(AheadBrowserApp())
        vendorfiles()
        port = free_port()
        operation_log = HTMXObjects.OPERATION_LOG[]
        serve(; port, async=true, access_log=nothing, operation_log=nothing)
        wait_for(prefix; timeout=60) =
            timedwait(() -> seen(prefix) !== nothing, timeout; pollint=0.02) === :ok
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/ahead_browser`
                proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test wait_for("frame")
                    @test seen("frame") == "frame"
                    # Several pushed answers replace the polling element while
                    # the operation waits; the script part must not run again.
                    sleep(2.5)
                    release!("browser-1")
                    @test wait_for("rows:")
                    @test seen("rows:") == "rows:1"
                    release!("browser-2")
                    @test wait_for("final:")
                    # No region is left, the script ran once, the frame is gone.
                    @test seen("final:") == "final:0:1:false"
                    @test wait_for("live-frame:")
                    # The first part replaced the live element's old result.
                    @test seen("live-frame:") == "live-frame:false"
                    release!("live-1")
                    release!("live-2")
                    @test wait_for("live-final:")
                    @test seen("live-final:") == "live-final:0:1"
                finally
                    process_exited(proc) || kill(proc)
                    wait(proc)
                end
            end
        finally
            foreach(release!, ("browser-1", "browser-2", "live-1", "live-2"))
            terminate()
            HTMXObjects.OPERATION_LOG[] = operation_log
        end
    end
end
