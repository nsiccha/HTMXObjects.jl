using TestItemRunner

@testitem "serve frames a buffered response with its Content-Length" setup=[HTMXOTestImports] tags=[:unit] begin
    frame(method, response) =
        HTMXObjects._frame_buffered!(HTTP.Request(method, "/"), response)
    content_length(r) =
        HTTP.hasheader(r, "Content-Length") ? HTTP.header(r, "Content-Length") : nothing

    # Bytes and strings in memory: the length of the body that is written.
    @test content_length(frame("GET", HTTP.Response(200, "héllo"))) == "6"
    @test content_length(frame("POST", HTTP.Response(200, UInt8[1, 2, 3]))) == "3"
    # An empty body (a redirect) is framed too: chunked, it would end only when
    # the connection task writes the last chunk.
    @test content_length(frame("GET", HTTP.Response(303, ["Location" => "/next"]))) == "0"
    @test content_length(frame("GET", HTTP.Response(500, "boom"))) == "4"

    # HTTP.jl's own framing stays: statuses without content, HEAD answers, a
    # response that is framed already, and a streamed body of unknown length.
    for status in (101, 204, 304)
        @test content_length(frame("GET", HTTP.Response(status))) === nothing
    end
    @test content_length(frame("HEAD", HTTP.Response(200, "body"))) === nothing
    @test content_length(frame("GET", HTTP.Response(200, ["Content-Length" => "4"], "body"))) == "4"
    chunked = frame("GET", HTTP.Response(200, ["Transfer-Encoding" => "chunked"], "body"))
    @test content_length(chunked) === nothing
    @test HTMXObjects._buffered_length(IOBuffer("streamed")) === nothing

    # Anything else is left for HTTP.jl's request adapter to report.
    @test HTMXObjects._frame_buffered!(HTTP.Request("GET", "/"), "raw") == "raw"
end

"""
The terminating write of a chunked HTTP.jl 1.x response happens on the
connection task after the handler task returns. This item keeps that task
parked and reads each response meanwhile: a buffered response must already be
complete.
"""
@testitem "a buffered response is complete before HTTP.jl's connection task resumes" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server] begin
    using Sockets

    const FRAMING_BODY = repeat("framed body line\n", 200)
    @htmx struct ServeFramingApp
        @get framing_text() = HTTP.Response(200, ["Content-Type" => "text/plain"], FRAMING_BODY)
        @get framing_redirect() = HTTP.Response(303, ["Location" => "/framing_text"])
        @get framing_page() = h.pre(FRAMING_BODY)
    end
    route!(ServeFramingApp())

    # The handler `serve(; parallel=:interactive)` installs. HTTP.jl's
    # connection task then waits for `resume` instead of closing the response.
    resume = Channel{Nothing}(Inf)
    handle = HTMXObjects._spawning_stream_handler(
        HTMXObjects._stream_handler(HTMXObjects._request_pipeline([], nothing, nothing)),
        :interactive)
    port = free_port()
    server = HTTP.listen!(stream -> (handle(stream); take!(resume)), "127.0.0.1", port)

    function fetch_while_parked(path)
        sock = connect(ip"127.0.0.1", port)
        watchdog = Timer(_ -> close(sock), 120)   # a missing response fails, not hangs
        try
            write(sock, "GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n\r\n")
            lines = split(readuntil(sock, "\r\n\r\n"), "\r\n")
            headers = Dict(lowercase(strip(k)) => strip(v)
                           for (k, v) in (split(l, ':'; limit=2) for l in lines[2:end]))
            len = get(headers, "content-length", nothing)
            body = len === nothing ? nothing : String(read(sock, parse(Int, len)))
            (; status=parse(Int, split(lines[1])[2]), headers, body)
        finally
            close(watchdog)
            close(sock)
            put!(resume, nothing)
        end
    end

    try
        r = fetch_while_parked("/framing_text")
        @test r.status == 200
        @test !haskey(r.headers, "transfer-encoding")
        @test get(r.headers, "content-length", nothing) == string(sizeof(FRAMING_BODY))
        @test r.body == FRAMING_BODY

        r = fetch_while_parked("/framing_redirect")
        @test r.status == 303
        @test !haskey(r.headers, "transfer-encoding")
        @test get(r.headers, "content-length", nothing) == "0"
        @test r.body == ""

        r = fetch_while_parked("/framing_page")
        @test r.status == 200
        @test !haskey(r.headers, "transfer-encoding")
        @test r.body !== nothing && contains(r.body, "<pre>framed body line")
    finally
        close(server)
    end
end
