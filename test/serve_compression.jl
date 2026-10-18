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
