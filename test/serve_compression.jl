using TestItemRunner

@testitem "serve gzips eligible text responses for clients that accept gzip" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: _compress_buffered, _accepts_gzip, _buffered_bytes
    gunzip(r) = transcode(HTMXObjects.CodecZlib.GzipDecompressor, Vector{UInt8}(_buffered_bytes(r.body)))
    body_string(r) = String(Vector{UInt8}(_buffered_bytes(r.body)))
    header(r, name) = HTTP.hasheader(r, name) ? HTTP.header(r, name) : nothing
    request(accept; method="GET") =
        HTTP.Request(method, "/", accept === nothing ? [] : ["Accept-Encoding" => accept])
    page = repeat("<tr><td>row</td><td>2026-10-18</td><td>12.50</td></tr>\n", 100)
    html(body=page; status=200, headers=[]) =
        HTTP.Response(status, ["Content-Type" => "text/html; charset=utf-8", headers...], body)

    # Accept-Encoding (RFC 9110 §12.5.3): gzip's own entry decides, else `*`.
    for accept in ("gzip", "gzip, deflate, br", "br, GZIP;Q=0.5", "x-gzip", "*", "br, *;q=0.2")
        @test _accepts_gzip(accept)
    end
    for accept in ("", "br", "identity", "gzip;q=0", "gzip;q=0.000", "*;q=0",
                   "gzip;q=0, *", "gzip;q=junk", " , ")
        @test !_accepts_gzip(accept)
    end

    # The compressed answer: gzip, framed later, and Vary for caches.
    original = html(; headers=["Content-Length" => string(sizeof(page)), "HX-Trigger" => "loaded"])
    original_headers = copy(original.headers)
    r = _compress_buffered(request("gzip, br"), original)
    @test r !== original
    @test r.status == 200
    @test header(r, "Content-Encoding") == "gzip"
    @test header(r, "Vary") == "Accept-Encoding"
    @test header(r, "HX-Trigger") == "loaded"
    @test header(r, "Content-Type") == "text/html; charset=utf-8"
    # The identity length is dropped; `_frame_buffered!` sets the compressed one.
    @test header(r, "Content-Length") === nothing
    @test String(gunzip(r)) == page
    @test length(_buffered_bytes(r.body)) < sizeof(page) ÷ 10
    # The route's own response is untouched: it may be cached and sent again.
    @test original.headers == original_headers
    @test body_string(original) == page

    # Status codes with a body compress too: a 286 poll terminal, an error page.
    for status in (286, 404, 500)
        @test header(_compress_buffered(request("gzip"), html(; status)), "Content-Encoding") == "gzip"
    end

    # Other text types compress; Markdown is `text/*`.
    for type in ("text/markdown; charset=utf-8", "application/json", "application/javascript",
                 "image/svg+xml", "application/ld+json", "application/atom+xml", "text/css")
        local r = _compress_buffered(request("gzip"), HTTP.Response(200, ["Content-Type" => type], page))
        @test header(r, "Content-Encoding") == "gzip"
    end

    # A client without gzip gets the same bytes, plus Vary so a cache keeps
    # the forms apart.
    for accept in (nothing, "br", "gzip;q=0")
        local r = _compress_buffered(request(accept), original)
        @test header(r, "Content-Encoding") === nothing
        @test header(r, "Vary") == "Accept-Encoding"
        @test header(r, "Content-Length") == string(sizeof(page))
        @test body_string(r) == page
    end

    # Vary merges with what the route set.
    vary(v) = header(_compress_buffered(request("gzip"), html(; headers=["Vary" => v])), "Vary")
    @test vary("Origin") == "Origin, Accept-Encoding"
    @test vary("HX-Request, accept-encoding") == "HX-Request, accept-encoding"
    @test vary("*") == "*"
    two_vary = html(; headers=["Vary" => "Origin", "Vary" => "HX-Request"])
    r = _compress_buffered(request("gzip"), two_vary)
    @test [v for (k, v) in r.headers if k == "Vary"] == ["Origin, HX-Request, Accept-Encoding"]

    # A strong ETag names the identity bytes; the gzipped form gets a weak one.
    etag(accept, tag) = header(_compress_buffered(request(accept), html(; headers=["ETag" => tag])), "ETag")
    @test etag("gzip", "\"v1\"") == "W/\"v1\""
    @test etag("gzip", "W/\"v1\"") == "W/\"v1\""
    @test etag("br", "\"v1\"") == "\"v1\""

    # Left exactly as the route returned it (the same object, no Vary).
    unchanged(req, response) = _compress_buffered(req, response) === response
    @test unchanged(request("gzip"), html("short body"))
    @test unchanged(request("gzip"; method="HEAD"), html())
    for status in (204, 304)
        @test unchanged(request("gzip"), HTTP.Response(status, ["Content-Type" => "text/html"]))
    end
    @test unchanged(request("gzip"), html(; status=206, headers=["Content-Range" => "bytes 0-1/9"]))
    @test unchanged(request("gzip"), html(; headers=["Content-Range" => "bytes 0-1/9"]))
    @test unchanged(request("gzip"), html(; headers=["Content-Encoding" => "br"]))
    @test unchanged(request("gzip"), html(; headers=["Transfer-Encoding" => "chunked"]))
    @test unchanged(request("gzip"), html(; headers=["Cache-Control" => "public, No-Transform"]))
    @test unchanged(request("gzip"), HTTP.Response(200, ["Content-Type" => "image/png"], page))
    @test unchanged(request("gzip"), HTTP.Response(200, page))
    # A streamed body (HTTP.jl 2 cannot even build a `Response` from an `IOBuffer`).
    @test _buffered_bytes(IOBuffer(page)) === nothing
    @test _compress_buffered(request("gzip"), "raw") == "raw"

    # Bytes that do not shrink go out as they are; Vary still says they could have.
    noise = String(rand(Random.MersenneTwister(1), UInt8, 4096))
    r = _compress_buffered(request("gzip"), HTTP.Response(200, ["Content-Type" => "text/plain"], noise))
    @test header(r, "Content-Encoding") === nothing
    @test header(r, "Vary") == "Accept-Encoding"
    @test body_string(r) == noise
end

@testitem "serve(; compress) answers on the wire, through a decompress=false relay, and opts out" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server] begin
    using Sockets
    const COMPRESS_PAGE_ROWS = 400
    @htmx struct ServeCompressionApp
        @direct @get compression_page() = h.table([h.tr(h.td("row $i"), h.td("12.50")) for i in 1:COMPRESS_PAGE_ROWS])
        @direct @get compression_markdown() = HTTP.Response(200,
            ["Content-Type" => "text/markdown; charset=utf-8"], repeat("- a line of markdown\n", 200))
        @direct @get compression_tiny() = HTTP.Response(200, ["Content-Type" => "text/plain"], "ok")
    end
    route!(ServeCompressionApp())

    # One raw HTTP/1.1 exchange: the exact head and body bytes on the wire.
    function raw_get(port, path; accept=nothing)
        sock = connect(ip"127.0.0.1", port)
        watchdog = Timer(_ -> close(sock), 120)
        try
            extra = accept === nothing ? "" : "Accept-Encoding: $accept\r\n"
            write(sock, "GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nAccept: text/html\r\n" *
                        "HX-Request: true\r\n$(extra)Connection: close\r\n\r\n")
            lines = split(readuntil(sock, "\r\n\r\n"), "\r\n")
            headers = Dict(lowercase(strip(k)) => strip(v)
                           for (k, v) in (split(l, ':'; limit=2) for l in lines[2:end]))
            body = read(sock, parse(Int, headers["content-length"]))
            (; status=parse(Int, split(lines[1])[2]), headers, body)
        finally
            close(watchdog)
            close(sock)
        end
    end
    gunzip(bytes) = String(transcode(HTMXObjects.CodecZlib.GzipDecompressor, bytes))

    port = free_port()
    serve(; port, async=true, access_log=nothing)
    try
        identity = raw_get(port, "/compression_page")
        @test identity.status == 200
        @test !haskey(identity.headers, "content-encoding")
        @test identity.headers["vary"] == "Accept-Encoding"
        page = String(copy(identity.body))   # `String` takes over a byte vector
        @test contains(page, "row $COMPRESS_PAGE_ROWS")

        gz = raw_get(port, "/compression_page"; accept="gzip, deflate, br, zstd")
        @test gz.status == 200
        @test gz.headers["content-encoding"] == "gzip"
        @test gz.headers["vary"] == "Accept-Encoding"
        @test !haskey(gz.headers, "transfer-encoding")
        @test parse(Int, gz.headers["content-length"]) == length(gz.body) < length(identity.body)
        @test gunzip(gz.body) == page

        md = raw_get(port, "/compression_markdown"; accept="gzip")
        @test md.headers["content-encoding"] == "gzip"
        @test gunzip(md.body) == repeat("- a line of markdown\n", 200)

        tiny = raw_get(port, "/compression_tiny"; accept="gzip")
        @test !haskey(tiny.headers, "content-encoding")
        @test !haskey(tiny.headers, "vary")
        @test String(tiny.body) == "ok"

        # A relay that forwards the client's headers and passes bytes through
        # untouched, as the KB's `/p/` proxy does: the gzip reaches the client
        # intact, and a client that did not ask still gets plain bytes.
        relayed = HTTP.get("http://127.0.0.1:$port/compression_page",
            ["Accept" => "text/html", "HX-Request" => "true", "Accept-Encoding" => "gzip"];
            decompress=false, retry=false)
        @test HTTP.header(relayed, "Content-Encoding") == "gzip"
        @test gunzip(Vector{UInt8}(HTMXObjects._buffered_bytes(relayed.body))) == page
        plain = HTTP.get("http://127.0.0.1:$port/compression_page",
            ["Accept" => "text/html", "HX-Request" => "true"];
            decompress=false, retry=false)
        @test !HTTP.hasheader(plain, "Content-Encoding")
        @test String(Vector{UInt8}(HTMXObjects._buffered_bytes(plain.body))) == page
        # HTTP.jl's own client asks for gzip and decompresses it.
        auto = HTTP.get("http://127.0.0.1:$port/compression_page",
            ["Accept" => "text/html", "HX-Request" => "true"]; retry=false)
        @test String(Vector{UInt8}(HTMXObjects._buffered_bytes(auto.body))) == page

        # In-process dispatch never goes through serve's compression.
        d = dispatch("GET", "/compression_page"; headers=["Accept-Encoding" => "gzip", "HX-Request" => "true"])
        @test !HTTP.hasheader(d, "Content-Encoding")
    finally
        terminate()
    end

    port = free_port()
    serve(; port, async=true, access_log=nothing, compress=false)
    try
        off = raw_get(port, "/compression_page"; accept="gzip")
        @test off.status == 200
        @test !haskey(off.headers, "content-encoding")
        @test !haskey(off.headers, "vary")
        @test contains(String(off.body), "row $COMPRESS_PAGE_ROWS")
    finally
        terminate()
    end
end

# Inflates every byte a client has received so far, as a browser does while
# an event stream is still open (no gzip trailer yet).
@testmodule SSEGzip begin
import HTMXObjects.CodecZlib as Z
export inflate_so_far

function inflate_so_far(bytes::Vector{UInt8})
    z = Z.ZStream()
    @assert Z.inflate_init!(z, 15 + 16) == Z.Z_OK
    out, chunk = UInt8[], Vector{UInt8}(undef, 1 << 16)
    try
        GC.@preserve bytes chunk begin
            z.next_in, z.avail_in = pointer(bytes), length(bytes)
            while true
                z.next_out, z.avail_out = pointer(chunk), length(chunk)
                code = Z.inflate!(z, Z.Z_SYNC_FLUSH)
                append!(out, view(chunk, 1:length(chunk) - z.avail_out))
                code in (Z.Z_OK, Z.Z_STREAM_END, Z.Z_BUF_ERROR) || error("inflate: $code")
                (code == Z.Z_STREAM_END || (z.avail_in == 0 && z.avail_out > 0)) && break
            end
        end
    finally
        Z.inflate_end!(z)
    end
    String(out)
end
end

@testitem "an event stream is one gzip stream that decodes completely after every write" setup=[HTMXOTestImports, SSEGzip] tags=[:unit, :sse] begin
    import HTMXObjects: _end_sse_gzip!, _sse_frame
    import HTMXObjects.CodecZlib as Z

    buf = IOBuffer()
    sse = SSEStream(buf, HTTP.Request("GET", "/events"); gzip=true)
    # A frame whose compressed form is larger than the compressor's output buffer.
    rng = Random.MersenneTwister(1)
    big = join((string("<tr><td>", randstring(rng, 8), "</td></tr>") for _ in 1:20_000), '\n')
    wire, sent = UInt8[], String[]
    for (x, event) in (("first", "a"), (big, "b"), ("", "c"))
        @test HTTP.WebSockets.send(sse, x; event)
        chunk = take!(buf)
        append!(wire, chunk)
        push!(sent, _sse_frame(x; event))
        # zlib's sync-flush marker (an empty stored block) ends every write,
        # so nothing of the frame waits in the compressor.
        @test chunk[end-3:end] == UInt8[0x00, 0x00, 0xff, 0xff]
        @test inflate_so_far(wire) == join(sent)
        x === big && @test length(chunk) > length(sse.gzip.out)
    end
    write(sse, ": keepalive\n\n")
    append!(wire, take!(buf))
    @test inflate_so_far(wire) == join(sent) * ": keepalive\n\n"

    # The end of the response writes the gzip trailer once and frees zlib.
    close(sse)
    _end_sse_gzip!(sse)
    append!(wire, take!(buf))
    @test sse.gzip === nothing
    @test String(transcode(Z.GzipDecompressor, wire)) == join(sent) * ": keepalive\n\n"
    @test length(wire) < sizeof(big) ÷ 2
    _end_sse_gzip!(sse)
    @test isempty(take!(buf))
    @test HTTP.WebSockets.send(sse, "late") == false

    # A plain stream writes the frames as they are.
    plain = SSEStream(buf, HTTP.Request("GET", "/events"))
    @test plain.gzip === nothing
    @test HTTP.WebSockets.send(plain, "first"; event="a")
    @test String(take!(buf)) == _sse_frame("first"; event="a")

    # A client that left before the trailer still frees the compressor.
    struct _GoneAfterHead <: IO end
    Base.unsafe_write(::_GoneAfterHead, ::Ptr{UInt8}, ::UInt) = throw(Base.IOError("client gone", 0))
    gone = SSEStream(_GoneAfterHead(), HTTP.Request("GET", "/events"); gzip=true)
    @test HTTP.WebSockets.send(gone, "x") == false
    _end_sse_gzip!(gone)
    @test gone.gzip === nothing
end

@testitem "serve gzips an event stream, and each event arrives while the body is still running" setup=[HTMXOTestImports, HTMXOTestPorts, SSEGzip] tags=[:integration, :server, :sse] begin
    using Sockets
    using HTTP.WebSockets: send
    import HTMXObjects.CodecZlib
    const SSE_GZIP_ROWS = 2000
    # The body waits after its first event until something releases it: the
    # client once it has decoded that event, or the watchdog if it never can.
    const SSE_GZIP_RELEASE = Channel{Symbol}(Inf)
    const SSE_GZIP_RELEASED_BY = Ref(:nobody)
    @htmx struct ServeCompressionSSEApp
        @sse compression_feed() = begin
            send(__sse__, h.table([h.tr(h.td("row $i"), h.td("12.50")) for i in 1:SSE_GZIP_ROWS]); event="table")
            SSE_GZIP_RELEASED_BY[] = take!(SSE_GZIP_RELEASE)
            send(__sse__, "after release"; event="later")
            "finished"
        end
    end
    route!(ServeCompressionSSEApp())

    gunzip(bytes) = String(transcode(CodecZlib.GzipDecompressor, bytes))
    # One raw HTTP/1.1 stream request. `on_bytes(body)` sees the body received
    # so far after every chunk (chunk framing removed); returns the head and
    # the whole body once the server ends the stream.
    function stream_get(port; accept=nothing, on_bytes=_ -> nothing)
        sock = connect(ip"127.0.0.1", port)
        watchdog = Timer(_ -> close(sock), 90)
        try
            extra = accept === nothing ? "" : "Accept-Encoding: $accept\r\n"
            write(sock, "GET /compression_feed HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n" *
                        "Accept: text/event-stream\r\n$(extra)\r\n")
            lines = split(readuntil(sock, "\r\n\r\n"), "\r\n")
            head = Dict(lowercase(strip(k)) => strip(v)
                        for (k, v) in (split(l, ':'; limit=2) for l in lines[2:end]))
            @assert head["transfer-encoding"] == "chunked"
            body = UInt8[]
            while true
                n = parse(Int, strip(first(split(readline(sock), ';'))); base=16)
                n == 0 && break
                append!(body, read(sock, n))
                readline(sock)
                on_bytes(body)
            end
            (; head, body)
        finally
            close(watchdog)
            close(sock)
        end
    end
    # The whole stream, with the body released at once.
    preset(port; kw...) = (put!(SSE_GZIP_RELEASE, :preset); stream_get(port; kw...))

    port = free_port()
    serve(; port, async=true, access_log=nothing)
    try
        # The first event decodes from the bytes received before the body
        # goes on: every write leaves the compressor whole.
        SSE_GZIP_RELEASED_BY[] = :nobody
        first_event = Ref("")
        watchdog = Timer(_ -> put!(SSE_GZIP_RELEASE, :watchdog), 30)
        held = stream_get(port; accept="gzip, deflate, br, zstd", on_bytes=function (body)
            isempty(first_event[]) || return
            so_far = inflate_so_far(body)
            contains(so_far, "\n\n") || return
            first_event[] = so_far
            put!(SSE_GZIP_RELEASE, :client)
        end)
        close(watchdog)
        @test SSE_GZIP_RELEASED_BY[] === :client
        @test held.head["content-encoding"] == "gzip"
        @test held.head["vary"] == "Accept-Encoding"
        @test startswith(held.head["content-type"], "text/event-stream")
        @test startswith(first_event[], "event: table\ndata: <table>")
        @test endswith(first_event[], "row $SSE_GZIP_ROWS</td><td>12.50</td></tr></table>\n\n")
        stream = gunzip(held.body)
        @test startswith(stream, first_event[])
        @test endswith(stream, "event: later\ndata: after release\n\n" *
                               "event: done\ndata: finished\n\nevent: close\ndata: \n\n")

        # On the wire: a fraction of the identity bytes, and the same stream.
        identity = preset(port)
        @test !haskey(identity.head, "content-encoding")
        @test identity.head["vary"] == "Accept-Encoding"
        @test String(copy(identity.body)) == stream
        @test length(held.body) < length(identity.body) ÷ 5
        refused = preset(port; accept="br, gzip;q=0")
        @test !haskey(refused.head, "content-encoding")
        @test refused.body == identity.body

        # HTTP.jl's own client asks for gzip and reads the stream decoded.
        put!(SSE_GZIP_RELEASE, :preset)
        auto = HTTP.get("http://127.0.0.1:$port/compression_feed", ["Accept" => "text/event-stream"]; retry=false)
        @test String(Vector{UInt8}(HTMXObjects._buffered_bytes(auto.body))) == stream
    finally
        terminate()
    end

    port = free_port()
    serve(; port, async=true, access_log=nothing, compress=false)
    try
        off = preset(port; accept="gzip")
        @test !haskey(off.head, "content-encoding")
        @test !haskey(off.head, "vary")
        @test startswith(String(copy(off.body)), "event: table\ndata: <table>")
    finally
        terminate()
    end
end

@testmodule CompressionChrome begin
    include(joinpath(@__DIR__, "support", "chrome.jl"))
end

"""
A browser asks for gzip on its own. Through a real `serve`, Chrome loads the
vendored htmx script and swaps a table fragment, both gzipped, and the page
works.
"""
@testitem "a browser runs gzipped htmx and swaps a gzipped fragment from serve" setup=[CompressionChrome, HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server, :browser] begin
    @htmx struct ServeCompressionBrowserApp
        __page__(content) = htmx(h.main(content); assets=:vendor, pico_version=HTMXObjects._PICO_VERSION)
        @direct @get index() = h.div("waiting"; id="slot", hx_get=__self__/"compression_browser_rows", hx_trigger="load")
        @direct @get compression_browser_rows() =
            h.table([h.tr(h.td("browser row $i"), h.td("12.50")) for i in 1:300]; id="swapped")
    end
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        route!(ServeCompressionBrowserApp())
        vendorfiles()
        # What the browser asked for, seen inside `serve` (compression runs
        # after every middleware).
        asked = Channel{Tuple{String,String}}(Inf)
        record = handler -> req -> (put!(asked, (req.target, HTTP.header(req, "Accept-Encoding", ""))); handler(req))
        port = free_port()
        serve(; port, async=true, access_log=nothing, middleware=[record])
        try
            HTTP.get("http://127.0.0.1:$port/compression_browser_rows", ["HX-Request" => "true"]; retry=false)
            take!(asked)
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            @test contains(dom, "id=\"swapped\"") && contains(dom, "browser row 300")
            @test !contains(dom, ">waiting</div>")
            requests = Dict{String,String}()
            while isready(asked)
                target, accept = take!(asked)
                requests[first(split(target, '?'))] = accept
            end
            script = only(filter(t -> startswith(t, "/vendor/") && endswith(t, ".js") && contains(t, "htmx"), collect(keys(requests))))
            for target in (script, "/compression_browser_rows")
                @test contains(requests[target], "gzip")
                # The same request again: what Chrome was sent.
                local r = HTTP.get("http://127.0.0.1:$port$target",
                    ["Accept-Encoding" => requests[target], "HX-Request" => "true"];
                    decompress=false, retry=false)
                @test HTTP.header(r, "Content-Encoding") == "gzip"
            end
        finally
            terminate()
        end
    end
end

"""
An `EventSource` asks for gzip by itself. Chrome reads a gzipped `@sse`
stream through `sse_region`: a large table event and the final value both
land in the page, and the stream it was sent is the gzip one.
"""
@testitem "a browser reads a gzipped event stream from serve" setup=[CompressionChrome, HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server, :browser, :sse] begin
    using HTTP.WebSockets: send
    @htmx struct ServeCompressionSSEBrowserApp
        __page__(content) = htmx(h.main(content); assets=:vendor, pico_version=HTMXObjects._PICO_VERSION)
        @direct @get index() = sse_region(__self__/"compression_browser_feed", h.p("waiting"); swap="beforeend")
        @sse compression_browser_feed() = begin
            send(__sse__, h.table([h.tr(h.td("stream row $i"), h.td("12.50")) for i in 1:300]; id="streamed"))
            h.p("stream done"; id="stream-done")
        end
    end
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        route!(ServeCompressionSSEBrowserApp())
        vendorfiles()
        asked = Channel{Tuple{String,String}}(Inf)
        record = handler -> req -> (put!(asked, (req.target, HTTP.header(req, "Accept-Encoding", ""))); handler(req))
        port = free_port()
        serve(; port, async=true, access_log=nothing, middleware=[record])
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            @test contains(dom, "id=\"streamed\"") && contains(dom, "stream row 300")
            @test contains(dom, "id=\"stream-done\"")
            requests = Dict{String,String}()
            while isready(asked)
                target, accept = take!(asked)
                requests[first(split(target, '?'))] = accept
            end
            @test contains(get(requests, "/compression_browser_feed", ""), "gzip")
            # The same request again: Chrome was sent the gzip stream.
            r = HTTP.get("http://127.0.0.1:$port/compression_browser_feed",
                ["Accept" => "text/event-stream", "Accept-Encoding" => requests["/compression_browser_feed"]];
                decompress=false, retry=false)
            @test HTTP.header(r, "Content-Encoding") == "gzip"
        finally
            terminate()
        end
    end
end
