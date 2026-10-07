using TestItemRunner

@testitem "stream routes answer the client probe without streaming" setup=[HTMXOTestImports] tags=[:unit, :ws, :sse] begin
    probe_route_runs = Ref(0)

    @htmx struct StreamProbeRoutesApp
        @ws probe_feed() = begin
            probe_route_runs[] += 1
            for _ in __ws__ end
        end
        @sse probe_events(; n::Int) = begin
            probe_route_runs[] += 1
            n
        end
    end
    route!(StreamProbeRoutesApp())

    drive(path, headers::Pair{String,String}...) = begin
        req = HTTP.Request("GET", path, collect(headers), UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
    end

    # The probe is answered before upgrade, argument parsing (the sse route's
    # required `n` is absent) or stream start.
    for path in ("/probe_feed", "/probe_events")
        r = drive(path, "X-HTMXO-Probe" => "stream", "HX-Request" => "true")
        @test r.status == 204
        @test isempty(r.body)
        @test HTTP.header(r, "Cache-Control") == "no-store"
    end
    # Without the probe header both routes behave as before: a plain GET on a
    # ws route is told to upgrade, and an sse route needs a live connection.
    @test drive("/probe_feed").status == 426
    @test drive("/probe_events?n=1").status == 500
    @test probe_route_runs[] == 0

    # Client and server agree on the probe header.
    probe_js = repr("text/html", stream_probe_script())
    @test contains(probe_js, "'$(HTMXObjects._STREAM_PROBE_HEADER)': 'stream'")
    # The shell carries the runtime, and discover streams report to it.
    @test contains(repr("text/html", htmx(h.main())), probe_js)
    @test contains(repr("text/html", live_region_script()),
        "window.htmxoStreamProbe.failed(source.url)")
end

@testitem "refused streams reload the page through an auth gateway in a browser" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # A fake auth gateway in front of the app. While the login is expired,
        # stream requests get `401`, plus `HX-Refresh: true` when they carry
        # `HX-Request` (strato-tunnel's shape). A page navigation after an
        # expiry stands for the sign-in round trip. `refuse_upgrade` stands
        # for a non-auth failure: handshakes fail, everything else passes.
        expired = Ref(false)
        refuse_upgrade = Ref(false)
        loads = Ref(0)
        ws_opens = Ref(0)
        current_ws = Ref{Any}(nothing)
        probes = Tuple{String,Int}[]
        beacons = String[]
        probe_subs = KeySubscriptions()

        gateway = handler -> function (req)
            path = HTTP.URI(req.target).path
            probe = !isempty(HTTP.header(req, "X-HTMXO-Probe", ""))
            if path == "/"
                expired[] && loads[] > 0 && (expired[] = false)
                loads[] += 1
            elseif path in ("/sp_feed", "/sp_events")
                if expired[]
                    probe && push!(probes, (path, 401))
                    hx = HTTP.header(req, "HX-Request", "") == "true"
                    return HTTP.Response(401,
                        hx ? ["HX-Refresh" => "true"] : Pair{String,String}[], "expired")
                end
                if refuse_upgrade[] && HTTP.WebSockets.isupgrade(req)
                    return HTTP.Response(503, "restarting")
                end
                if probe
                    response = handler(req)
                    push!(probes, (path, response.status))
                    return response
                end
            end
            handler(req)
        end

        @htmx struct StreamProbeBrowserApp
            @get index(; mode::String="ws") = begin
                stream = if mode == "ws"
                    h.div(; id="stream", hx_ext="ws", ws_connect="/sp_feed")
                elseif mode == "sse"
                    sse_region("/sp_events?key=k", h.p("waiting"))
                else
                    live_region("/sp_events",
                        live_fragment("k", h.span("k"); fragment_url="/sp_card");
                        id="region", discover=true)
                end
                driver = h.script(Raw("""
                    // A fast reconnect keeps the run short; the probe's own
                    // spacing still bounds how often it asks.
                    htmx.config.wsReconnectDelay = function () { return 200; };
                    window.addEventListener('load', function () {
                        // Another origin's stream is never probed.
                        var x = window.htmxoStreamProbe.failed('wss://elsewhere.invalid/feed');
                        fetch('/sp_beacon?text=' + encodeURIComponent('xorigin:' + x));
                    });
                    """))
                htmx(h.main(stream), driver; assets=:vendor, hyperscript_version=nothing,
                    preload_version=nothing, compose=false, thread=false)
            end
            @ws sp_feed() = begin
                ws_opens[] += 1
                current_ws[] = __ws__
                for _ in __ws__ end
            end
            @sse sp_events(; key::Vector{String}=String[]) =
                serve_key_feed!(__sse__, probe_subs, key; poll=0.02)
            @get sp_card() = live_fragment("k", h.span("k"); fragment_url="/sp_card")
            @get sp_beacon(; text::String="") = (push!(beacons, text); "ok")
        end

        vendorfiles()
        route!(StreamProbeBrowserApp())
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        heartbeat = HTMXObjects._SSE_HEARTBEAT_SECONDS[]
        HTMXObjects._SSE_HEARTBEAT_SECONDS[] = 0.05
        serve(; port, async=true, middleware=[gateway])

        function until(pred, seconds)
            t0 = time()
            while !pred() && time() - t0 < seconds
                sleep(0.05)
            end
            pred()
        end
        function with_chrome(f, mode)
            url = "http://127.0.0.1:$port/?mode=$mode"
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile $url`
                proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    f()
                finally
                    process_exited(proc) || kill(proc)
                    wait(proc)
                end
            end
        end
        function reset!(; start_expired)
            expired[] = start_expired
            refuse_upgrade[] = false
            loads[] = 0
            empty!(probes)
            empty!(beacons)
        end

        try
            # Warm the page route so chrome's first load stays fast.
            @test HTTP.get("http://127.0.0.1:$port/?mode=ws";
                status_exception=false, retry=false, readtimeout=60).status == 200

            # ws: an open feed drops abnormally and every reconnect handshake
            # is refused. Close 1011 is on the extension's reconnect list; HTTP
            # 2.x will not send 1012 (it substitutes 1002, which ends the feed).
            reset!(; start_expired=false)
            with_chrome("ws") do
                @test until(() -> ws_opens[] >= 1 && current_ws[] !== nothing, 60)
                # Non-auth refusal: the probe reaches the app, which answers
                # 204 without HX-Refresh, so the page stays and the extension
                # keeps retrying. Retries every 200 ms send one probe only.
                refuse_upgrade[] = true
                HTTP.WebSockets.close(current_ws[], HTTP.WebSockets.CloseFrameBody(1011, "restart"))
                @test until(() -> !isempty(probes), 20)
                sleep(1.5)
                @test probes == [("/sp_feed", 204)]
                @test loads[] == 1
                # The login expires: the next probe (after the 5 s spacing)
                # gets 401 + HX-Refresh and the page reloads into sign-in,
                # after which the feed reconnects.
                expired[] = true
                refuse_upgrade[] = false
                @test until(() -> ws_opens[] >= 2, 30)
                @test probes == [("/sp_feed", 204), ("/sp_feed", 401)]
                @test loads[] == 2
                @test until(() -> length(beacons) >= 2, 10)
                @test beacons == ["xorigin:null", "xorigin:null"]
            end

            # sse extension and discover runtime: the login expired before the
            # stream connected, so the browser's EventSource ends CLOSED.
            for mode in ("sse", "discover")
                reset!(; start_expired=true)
                with_chrome(mode) do
                    @test until(() -> loads[] >= 2 && haskey(probe_subs.streams, "k"), 30)
                    @test probes == [("/sp_events", 401)]
                    @test loads[] == 2
                end
                @test until(() -> !haskey(probe_subs.streams, "k"), 10)
            end
        finally
            HTMXObjects._SSE_HEARTBEAT_SECONDS[] = heartbeat
            terminate()
        end
    end
end
