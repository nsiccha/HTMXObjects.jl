using TestItemRunner

@testmodule DispatchBodyFixtures begin
using HTMXObjects, HTTP
export DispatchBodyApp, body_bytes, forward_request, request_cases

@htmx struct DispatchBodyApp
    @get dispatch_body_empty() = HTTP.Response(200, "empty")
    @post dispatch_body_echo() = HTTP.Response(200, HTMXObjects._request_body_bytes(__req__))
    @post dispatch_body_form(; label::String="none") = HTTP.Response(200, label)
end

body_bytes(message) = HTMXObjects._message_body_bytes(message)
forward_request(req) = dispatch(Symbol(req.method), String(req.target);
    headers=req.headers, body=req.body)
request_cases() = [
    ("GET", "/dispatch_body_empty", Pair{String,String}[], UInt8[], b"empty"),
    ("POST", "/dispatch_body_form", ["Content-Type" => "application/x-www-form-urlencoded"],
        b"label=hello+world", b"hello world"),
    ("POST", "/dispatch_body_echo", ["Content-Type" => "application/octet-stream"],
        UInt8[0x00, 0xff, 0x80, 0x0a], UInt8[0x00, 0xff, 0x80, 0x0a]),
]
end

@testitem "dispatch accepts buffered HTTP request bodies without consuming them" setup=[DispatchBodyFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP
    route!(DispatchBodyApp())
    for (method, target, headers, payload, expected) in request_cases()
        req = HTTP.Request(method, target, headers, copy(payload))
        before = body_bytes(req)
        # Forward twice: neither dispatch nor the route may consume the source.
        for _ in 1:2
            response = forward_request(req)
            converted = dispatch(method, target; headers, body=copy(before))
            @test response.status == converted.status == 200
            @test body_bytes(response) == body_bytes(converted) == expected
            @test body_bytes(req) == before
        end
    end
    if isdefined(HTTP, :BytesBody)
        payload = UInt8[0x00, 0xff, 0x80, 0x0a]
        body = HTTP.BytesBody(payload)
        @test HTTP.body_read!(body, zeros(UInt8, 1)) == 1
        cursor = body.next_index
        response = dispatch(:POST, "/dispatch_body_echo";
            headers=["Content-Type" => "application/octet-stream"], body)
        @test body_bytes(response) == payload[2:end]
        @test body.next_index == cursor
        @test !HTTP.body_closed(body)
        @test payload == UInt8[0x00, 0xff, 0x80, 0x0a]
    end
end

@testitem "HTTP serve handlers can forward request bodies directly to dispatch" setup=[DispatchBodyFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP
    route!(DispatchBodyApp())
    # Warm route compilation before the client's read timeout starts.
    for (method, target, headers, payload, _) in request_cases()
        dispatch(method, target; headers, body=copy(payload))
    end
    port = free_port()
    server = HTTP.serve!(forward_request, "127.0.0.1", port; verbose=false)
    try
        for (method, target, headers, payload, expected) in request_cases()
            response = HTTP.request(method, "http://127.0.0.1:$port$target", headers, copy(payload);
                status_exception=false, retry=false, readtimeout=60)
            @test response.status == 200
            @test body_bytes(response) == expected
        end
    finally
        close(server)
    end
end
