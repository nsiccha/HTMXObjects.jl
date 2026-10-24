using TestItemRunner

# A route declared `::JSONResponse{T}` answers its plain value encoded through
# `T`, and `openapi` describes the same `T` as the route's response schema (snag
# `declare-the-json-8263a67b`, reporter ODLPlaus: every operation of a JSON API
# read `200: OK`, with no schema and no `components`).
@testmodule JSONResponseFixtures begin
    using HTMXObjects, Dates
    export JRAlarm, JRAlarms, JRLevel, low, high, JRNode, JRApp, JRRoot, JRPlain, JRErrors, JROther

    @enum JRLevel low high

    """
    One pre-alarm of the threshold rule.

    Raised when two neighbouring probes exceed it in the same hour.
    """
    struct JRAlarm
        "Start hour (UTC)."
        start::DateTime
        "Neighbouring probes of the group."
        probes::Vector{String}
        rain_share::Union{Float64,Nothing}
    end

    "Pre-alarms of the threshold rule."
    struct JRAlarms
        day::Date
        k::Float64
        n::Int
        level::JRLevel
        alarms::Vector{JRAlarm}
        extra::Union{Nothing,@NamedTuple{note::String}}
    end

    "A tree node."
    struct JRNode
        name::String
        children::Vector{JRNode}
    end

    module JROther
    struct JRAlarm
        id::Int
    end
    end

    @htmx struct JRApp
        "Pre-alarms for one threshold."
        @get alarms(; k::Float64=3.0)::JSONResponse{JRAlarms} = (;
            day=Date(2026, 10, 24), k, n=1, level=low,
            alarms=[(start=DateTime(2026, 10, 24, 2), probes=["a", "b"], rain_share=nothing)],
            extra=nothing, ignored="not sent")
        "Alarm rows from a column table."
        @get rows()::JSONResponse{Vector{JRAlarm}} =
            (start=[DateTime(2026, 1, 1)], probes=[["p"]], rain_share=[NaN])
        @get tree()::JSONResponse{JRNode} = JRNode("root", [JRNode("leaf", JRNode[])])
        @get untyped()::JSONResponse = (; a=1, b=[missing, 2.5], c=Dict("x" => :y))
        @get broken()::JSONResponse{JRAlarm} = (; start=DateTime(2026, 1, 1))
        "One alarm, or another answer the route finished itself."
        @get either(; kind::String="value")::JSONResponse{JRAlarm} =
            kind == "mime" ? MIMEResponse("application/json", "{\"error\":\"NotInSnapshot\"}") :
            kind == "json" ? JSONResponse((; error="NotInSnapshot", parts=[:ap3])) :
            kind == "http" ? HTTP.Response(503, ["Content-Type" => "application/json"];
                                           body="{\"error\":\"busy\"}") :
            (; start=DateTime(2026, 1, 1), probes=["p"], rain_share=0.5)
        @get other()::JSONResponse{Vector{JROther.JRAlarm}} = [JROther.JRAlarm(1)]
        @get html() = "plain"
    end

    @htmx struct JRErrors
        __error__ = err -> JSONResponse((; error="failed"))
        @get broken()::JSONResponse{JRAlarm} = (; start=DateTime(2026, 1, 1))
    end

    @htmx struct JRPlain
        @get ping() = "plain"
    end

    @htmx struct JRRoot
        @include jr_api = JRApp()
        @include jr_errors = JRErrors()
        @include jr_openapi = OpenAPIRoutes(; root=JRRoot)
    end
end

@testitem "JSONResponse encodes a value through its declared type" setup=[JSONResponseFixtures] tags=[:unit] begin
    using HTMXObjects, Dates
    body(T, x) = String(to_response(JSONResponse{T}(x)).body)

    # A struct type is an object of exactly its fields, read by name from any
    # value that has them; an undeclared field is not sent, a nullable one
    # the value lacks is `null`.
    alarms = (; day=Date(2026, 10, 24), k=3.0, n=1, level=low,
              alarms=[(start=DateTime(2026, 10, 24, 2), probes=["a", "b"])],
              extra=nothing, ignored="not sent")
    @test body(JRAlarms, alarms) ==
        """{"day":"2026-10-24","k":3.0,"n":1,"level":"low","alarms":[{"start":"2026-10-24T02:00:00","probes":["a","b"],"rain_share":null}],"extra":null}"""
    @test endswith(body(JRAlarms, merge(alarms, (; extra=(; note="n")))),
                   "\"extra\":{\"note\":\"n\"}}")

    # A table (here a column table) stands for a vector of rows; a non-finite
    # float is `null`.
    @test body(Vector{JRAlarm}, (start=[DateTime(2026, 1, 1)], probes=[["p"]], rain_share=[NaN])) ==
        """[{"start":"2026-01-01T00:00:00","probes":["p"],"rain_share":null}]"""
    @test body(Vector{JRAlarm}, (start=DateTime[], probes=Vector{String}[], rain_share=Float64[])) == "[]"

    # Recursive types, dictionaries, the value's own shape under `Any`.
    @test body(JRNode, JRNode("root", [JRNode("leaf", JRNode[])])) ==
        """{"name":"root","children":[{"name":"leaf","children":[]}]}"""
    @test body(Dict{String,Int}, Dict("b" => 2, "a" => 1)) == """{"a":1,"b":2}"""
    @test String(to_response(JSONResponse((; a=1, b=[missing, 2.5], c=Dict("x" => :y)))).body) ==
        """{"a":1,"b":[null,2.5],"c":{"x":"y"}}"""
    @test body(String, "a\"b\n") == "\"a\\\"b\\n\""
    @test body(Int, 3.0) == "3"
    @test body(Float64, Inf) == "null"
    @test body(Union{Int,Nothing}, missing) == "null"

    # A value that does not fit its declaration fails loudly.
    err = try body(JRAlarm, (; start=DateTime(2026, 1, 1))); nothing catch e; e end
    @test err isa ArgumentError && contains(err.msg, "`probes`")
    @test_throws ArgumentError body(Float64, "x")
    @test_throws ArgumentError body(Vector{JRAlarm}, nothing)
    @test_throws InexactError body(Int, 3.5)

    @test HTTP.header(to_response(JSONResponse(1)), "Content-Type") ==
        "application/json; charset=utf-8"
end

@testitem "a route declared ::JSONResponse{T} answers its value as JSON" setup=[JSONResponseFixtures] tags=[:unit] begin
    using HTMXObjects
    drive(path, headers=Pair{String,String}[]) = begin
        req = HTTP.Request("GET", path, headers, UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
    end
    route!(JRRoot())

    response = drive("/jr_api/alarms?k=4.5")
    @test response.status == 200
    @test HTTP.header(response, "Content-Type") == "application/json; charset=utf-8"
    @test String(response.body) ==
        """{"day":"2026-10-24","k":4.5,"n":1,"level":"low","alarms":[{"start":"2026-10-24T02:00:00","probes":["a","b"],"rain_share":null}],"extra":null}"""
    # An HTMX request gets the same final answer: no page shell, no poller.
    @test String(drive("/jr_api/alarms?k=4.5", ["HX-Request" => "true"]).body) ==
        String(response.body)
    @test String(drive("/jr_api/rows").body) ==
        """[{"start":"2026-01-01T00:00:00","probes":["p"],"rain_share":null}]"""
    @test String(drive("/jr_api/untyped").body) == """{"a":1,"b":[null,2.5],"c":{"x":"y"}}"""

    # The declaration makes the route final for the operation policy.
    final(name) = HTMXObjects._declared_final_response(
        HTMXObjects._property_descriptor(JRApp, name, :GET))
    @test final(:alarms) && final(:untyped)
    @test !final(:html)
    @test contains(HTTP.header(drive("/jr_api/html"), "Content-Type"), "text/html")

    # A value that does not fit fails the request; an `__error__` hook can
    # answer that failure as JSON, with the error's status.
    @test drive("/jr_api/broken").status == 500
    failed = drive("/jr_errors/broken")
    @test failed.status == 500
    @test HTTP.header(failed, "Content-Type") == "application/json; charset=utf-8"
    @test String(failed.body) == """{"error":"failed"}"""

    # A finished answer the body returns on one branch is sent as it is, not
    # encoded through the declared type (snag `move-odlplaus-ap-8416729f`).
    @test String(drive("/jr_api/either").body) ==
        """{"start":"2026-01-01T00:00:00","probes":["p"],"rain_share":0.5}"""
    note = drive("/jr_api/either?kind=mime")
    @test note.status == 200
    @test HTTP.header(note, "Content-Type") == "application/json"
    @test String(note.body) == """{"error":"NotInSnapshot"}"""
    @test isempty(HTTP.header(note, "X-HTMXO-Error-Id"))
    untyped = drive("/jr_api/either?kind=json")
    @test untyped.status == 200
    @test String(untyped.body) == """{"error":"NotInSnapshot","parts":["ap3"]}"""
    busy = drive("/jr_api/either?kind=http")
    @test busy.status == 503
    @test String(busy.body) == """{"error":"busy"}"""
    @test isempty(HTTP.header(busy, "X-HTMXO-Error-Id"))
    @test String(drive("/jr_api/either?kind=mime", ["HX-Request" => "true"]).body) ==
        String(note.body)
end

@testitem "openapi describes a JSONResponse route's payload type" setup=[JSONResponseFixtures] tags=[:unit] begin
    using HTMXObjects
    ref(name) = NamedTuple{(Symbol("\$ref"),)}(("#/components/schemas/" * name,))
    doc = openapi(JRApp)
    ok(path) = doc.paths[path]["get"].responses["200"]
    schemas = doc.components.schemas

    alarms = ok("/alarms")
    @test alarms.description == "Pre-alarms of the threshold rule."
    @test alarms.content["application/json"].schema == ref("JRAlarms")
    @test schemas["JRAlarms"].description == "Pre-alarms of the threshold rule."
    @test schemas["JRAlarms"].type == "object"
    @test schemas["JRAlarms"].required == ["day", "k", "n", "level", "alarms", "extra"]
    properties = schemas["JRAlarms"].properties
    @test properties.day == (type="string", format="date")
    @test properties.k == (type=["number", "null"],)
    @test properties.n == (type="integer",)
    @test properties.level == (type="string", enum=["low", "high"])
    @test properties.alarms == (type="array", items=ref("JRAlarm"))
    @test properties.extra ==
        (type=["object", "null"], properties=(note=(type="string",),), required=["note"])
    # Properties keep the struct's field order.
    @test keys(properties) == (:day, :k, :n, :level, :alarms, :extra)
    # A nullable reference needs `anyOf`; a typed schema just admits `null`.
    @test HTMXObjects._openapi_response_schema(HTMXObjects._OpenAPIComponents(),
                                               Union{Nothing,JRNode}) ==
        (anyOf=[ref("JRNode"), (type="null",)],)

    alarm = schemas["JRAlarm"]
    @test startswith(alarm.description, "One pre-alarm of the threshold rule.\n\nRaised when")
    @test alarm.required == ["start", "probes", "rain_share"]
    @test alarm.properties.start ==
        (type="string", format="date-time", description="Start hour (UTC).")
    @test alarm.properties.probes == (type="array", items=(type="string",),
                                         description="Neighbouring probes of the group.")
    @test alarm.properties.rain_share == (type=["number", "null"],)

    # An array payload: items by `$ref`; the response has no struct docstring.
    @test ok("/rows").description == "OK"
    @test ok("/rows").content["application/json"].schema == (type="array", items=ref("JRAlarm"))
    # A route that may answer otherwise on one branch still documents `T`.
    @test ok("/either").content["application/json"].schema == ref("JRAlarm")
    # A recursive type refers to itself.
    @test schemas["JRNode"].properties.children == (type="array", items=ref("JRNode"))
    # An untyped `JSONResponse` says only that the body is JSON.
    @test ok("/untyped").content["application/json"].schema == NamedTuple()
    # A same-named type from another module gets a qualified component name.
    other = ok("/other").content["application/json"].schema.items[Symbol("\$ref")]
    @test other != "#/components/schemas/JRAlarm"
    @test endswith(other, ".JRAlarm")
    @test haskey(schemas, last(split(other, "/")))
    # Every other route keeps the plain `200: OK`.
    @test doc.paths["/html"]["get"].responses == Dict("200" => (description="OK",))

    encoded = HTMXObjects._schema_json_encode(doc)
    @test contains(encoded, "\"\$ref\":\"#/components/schemas/JRAlarm\"")

    # No `components` without a schema to hold, and `reflect` keeps its shape.
    @test !haskey(openapi(JRPlain), :components)
    @test openapi(JRPlain).paths["/ping"]["get"].responses == Dict("200" => (description="OK",))
    @test keys(only(filter(r -> r.name === :alarms, reflect(JRApp)))) ==
        (:verb, :path, :name, :doc, :params)
end

@testitem "OpenAPIRoutes serves the response schemas" setup=[JSONResponseFixtures] tags=[:unit] begin
    using HTMXObjects
    req = HTTP.Request("GET", "/jr_openapi", Pair{String,String}[], UInt8[])
    route!(JRRoot())
    response = first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
    @test response.status == 200
    body = String(response.body)
    @test contains(body, "\"components\":{\"schemas\":{")
    @test contains(body, "\"application/json\":{\"schema\":{\"\$ref\":\"#/components/schemas/JRAlarms\"}}")
end
