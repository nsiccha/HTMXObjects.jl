using TestItemRunner

@testitem "JSON objects bind typed request parameters over HTTP" tags=[:integration] begin
    using HTMXObjects, HTTP, JSON, Sockets, Test

    struct Item
        name::String
        value::Float64
    end
    answer(value) = HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(value))
    @htmx struct JSONInputApi
        @post item(; name::String, value::Float64)::JSONResponse{Item} = (; name, value)
        @post created(; name::String, value::Float64)::JSONResponse{Item,201} = (; name, value)
        @put item(; name::String, value::Float64)::JSONResponse{Item} = (; name, value)
        @patch item(; name::String, value::Float64)::JSONResponse{Item} = (; name, value)
        @get item(; name::String, value::Float64)::JSONResponse{Item} = (; name, value)
        @post values(; text::String="default", nullable::Union{Nothing,Int}=7,
            numbers::Vector{Float64}=[9.0], enabled::Bool=false, data::Dict{String,Int}=Dict{String,Int}(),
            fields...) = answer((; text, nullable, numbers, enabled, data, fields=(; fields...)))
        @post record(; item::Item) = answer((; item.name, item.value))
        @post raw() = HTTP.Response(200, copy(__req__.body))
        @include params = begin
            @param count::Int = 1
            @param label::String = "default"
            @param nullable::Union{Nothing,Int} = 7
            @options(count) = [1, 2]
            @post show() = answer((; count, label, nullable))
        end
    end
    route!(JSONInputApi(); operation_policy=:blocking)
    listener = listen(ip"127.0.0.1", 0)
    port = getsockname(listener)[2]
    close(listener)
    serve(; port, async=true, access_log=nothing)
    function request(path, payload; method="POST", content_type="application/json")
        HTTP.request(method, "http://127.0.0.1:$port$path",
            ["Content-Type" => content_type], payload; status_exception=false)
    end
    try
        for method in ("POST", "PUT", "PATCH"), ct in ("application/json", "Application/JSON; charset=utf-8")
            response = request("/item", """{"name":"demo","value":3}"""; method, content_type=ct)
            @test response.status == 200
            @test JSON.parse(response.body) == Dict("name" => "demo", "value" => 3.0)
        end
        response = request("/item", "name=demo&value=3.0"; content_type="application/x-www-form-urlencoded")
        @test response.status == 200
        @test JSON.parse(response.body)["value"] == 3.0
        response = request("/created", """{"name":"created","value":3.0}""")
        @test response.status == 201
        @test JSON.parse(response.body) == Dict("name" => "created", "value" => 3.0)
        response = request("/item?value=4&name=query", """{"name":"body"}""")
        @test response.status == 200
        @test JSON.parse(response.body) == Dict("name" => "body", "value" => 4.0)
        response = request("/item?value=4&name=query", "not JSON"; method="GET")
        @test response.status == 200
        @test JSON.parse(response.body)["name"] == "query"

        response = request("/values?text=query&nullable=2&numbers=4&extra=query",
            """{"text":"","nullable":null,"numbers":[],"enabled":true,"data":{"a":2},"extra":null,"blank":"","list":[],"__private":3}""")
        @test response.status == 200
        values = JSON.parse(response.body)
        @test values["text"] == ""
        @test values["nullable"] === nothing
        @test values["numbers"] == []
        @test values["enabled"] === true
        @test values["data"] == Dict("a" => 2)
        @test values["fields"] == Dict("extra" => nothing, "blank" => "", "list" => [])
        response = request("/values", "{}")
        @test response.status == 200
        @test JSON.parse(response.body)["nullable"] == 7
        response = request("/values", """{"numbers":[1,2.5]}""")
        @test response.status == 200
        @test JSON.parse(response.body)["numbers"] == [1.0, 2.5]
        response = request("/record", """{"item":{"name":"nested","value":2}}""")
        @test response.status == 200
        @test JSON.parse(response.body) == Dict("name" => "nested", "value" => 2.0)
        response = request("/params/show?label=query&nullable=2",
            """{"count":2,"label":"","nullable":null}""")
        @test response.status == 200
        @test JSON.parse(response.body) == Dict("count" => 2, "label" => "", "nullable" => nothing)
        @test request("/params/show", """{"count":3}""").status == 400

        for payload in ("{", "[]", "null", "42", "\"text\"", "")
            response = request("/item", payload)
            @test response.status == 400
            @test occursin("application/json", String(response.body))
        end
        for payload in ("{}", "{\"name\":\"demo\"}",
                "{\"name\":\"demo\",\"value\":null}",
                "{\"name\":\"demo\",\"value\":{}}",
                "{\"name\":\"demo\",\"value\":[]}",
                "{\"name\":\"demo\",\"value\":\"3\"}")
            @test request("/item", payload).status == 400
        end
        for payload in ("{\"nullable\":1.5}", "{\"numbers\":[\"bad\"]}", "{\"enabled\":{}}",
                "{\"numbers\":null}", "{\"numbers\":3}", "{\"numbers\":\"abc\"}", "{\"data\":null}")
            @test request("/values", payload).status == 400
        end
        # Raw-body routes with no bound inputs do not force JSON decoding.
        response = request("/raw", "not JSON")
        @test response.status == 200
        @test String(response.body) == "not JSON"

        doc = openapi(JSONInputApi)
        content = doc.paths["/item"]["post"].requestBody.content
        @test haskey(doc.paths["/created"]["post"].responses, "201")
        @test haskey(doc.paths["/created"]["post"].requestBody.content, "application/json")
        @test Set(keys(content)) == Set(["application/json", "application/x-www-form-urlencoded"])
        @test content["application/json"].schema.properties["value"].type == "number"
        record = doc.paths["/record"]["post"].requestBody.content["application/json"]
        @test record.schema.properties["item"].type == "object"
        nullable = doc.paths["/values"]["post"].requestBody.content["application/json"].schema.properties["nullable"]
        @test Set(schema.type for schema in nullable.anyOf) == Set(["null", "integer"])
    finally
        HTMXObjects.terminate()
    end
end

@testitem "JSON body readers preserve request bytes and native values" tags=[:unit] begin
    using HTMXObjects, HTTP, JSON, Test
    payload = """{"string":"","array":[],"object":{},"number":2,"boolean":false,"null":null}"""
    bytes = Vector{UInt8}(payload)
    req = HTTP.Request("POST", "/", ["Content-Type" => "application/json"], bytes)
    values = bodyparams(req)
    @test values isa AbstractDict
    @test values["null"] === nothing
    @test values["boolean"] === false
    @test values["number"] == 2
    @test bodyparams(req) == values
    @test bodyparams(HTMXObjects._param_request(req)) == values
    @test bytes == Vector{UInt8}(payload)
    @test isempty(bodyparams(HTTP.Request("POST", "/", ["Content-Type" => "text/plain"], payload)))
end
