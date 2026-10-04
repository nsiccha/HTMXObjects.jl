using TestItemRunner

@testitem "inferred Enum forms round trip through typed request parameters" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    @enum SubmissionStage stage_queued stage_active stage_complete

    @htmx struct EnumOperations
        stage::SubmissionStage
        @get source() = string(stage, "::", typeof(stage))
        @post source() = string(stage, "::", typeof(stage))
        @get positional(value::SubmissionStage) = string(value)
        @get keyword(; value::SubmissionStage) = string(value)
        @get many(; stages::Vector{SubmissionStage}) = join(string.(stages), ",")
    end
    @htmx struct EnumHost
        @include workspace = EnumOperations(stage_queued)
    end

    app = EnumHost()
    html = repr("text/html", semantic_app(app; values=(value=stage_queued,)))
    @test contains(html, "name=\"stage\"")
    for stage in instances(SubmissionStage)
        @test contains(html, "value=\"$(stage)\"")
    end
    route!(app; operation_policy=:blocking)

    for stage in instances(SubmissionStage)
        @test HTMXObjects._convert_param(SubString(string(stage)), SubmissionStage) === stage
        response = dispatch(:GET, "/workspace/source?stage=$(stage)&plain=1")
        @test response.status == 200
        @test String(response.body) == string(stage, "::", SubmissionStage)

        posted = dispatch(:POST, "/workspace/source?plain=1";
            headers=["Content-Type" => "application/x-www-form-urlencoded"],
            body="stage=$(stage)")
        @test posted.status == 200
        @test String(posted.body) == string(stage, "::", SubmissionStage)

        for path in ("/workspace/positional/$(stage)",
                     "/workspace/keyword?value=$(stage)")
            result = dispatch(:GET, path)
            @test result.status == 200
            @test String(result.body) == string(stage)
        end
    end

    refreshed = dispatch(:GET, "/workspace/source?stage=stage_active&__htmxo_form=1")
    @test refreshed.status == 200
    @test contains(String(refreshed.body), "value=\"stage_active\" checked=\"true\"")
    repeated = dispatch(:GET, "/workspace/many?stages=stage_queued&stages=stage_complete")
    @test repeated.status == 200
    @test String(repeated.body) == "stage_queued,stage_complete"

    # The inferred static domain admits only its instance wire values; neither
    # unknown names nor integer storage codes are offered form choices.
    for invalid in ("missing_stage", "0")
        bad = dispatch(:GET, "/workspace/source?stage=$(invalid)")
        @test bad.status == 400
        @test contains(String(bad.body), "Invalid value for parameter stage")
        @test HTTP.hasheader(bad, "X-HTMXO-Error-Id")
    end
    @test app.workspace.stage === stage_queued
end

@testitem "inferred Enum context submits over HTTP" tags=[:integration, :server, :semantic] begin
    using HTMXObjects, HTTP, Sockets

    @enum HTTPStage http_first http_second
    @htmx struct HTTPEnumOperations
        stage::HTTPStage
        @get source() = string(stage, "::", typeof(stage))
    end
    @htmx struct HTTPEnumHost
        @include workspace = HTTPEnumOperations(http_first)
    end

    app = HTTPEnumHost()
    @test contains(repr("text/html", semantic_app(app)), "value=\"http_second\"")
    route!(app; operation_policy=:blocking)
    socket = listen(Sockets.localhost, 0)
    port = Int(getsockname(socket)[2])
    close(socket)
    server = HTTP.serve!("127.0.0.1", port; verbose=false) do request
        first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, request))(request)
    end
    try
        response = HTTP.get("http://127.0.0.1:$port/workspace/source?stage=http_second&plain=1";
                            retry=false)
        @test response.status == 200
        @test String(response.body) == string(http_second, "::", HTTPStage)
        @test app.workspace.stage === http_first
    finally
        close(server)
    end
end

@testitem "Enum conversion uses the same wire identity as generated controls" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    @enum WireStage wire_first wire_second
    HTMXObjects.option_wire_value(stage::WireStage) = "stage/" * string(stage)
    @htmx struct WireEnumApp
        stage::WireStage
        @get selected() = string(stage)
    end

    app = WireEnumApp(wire_first)
    html = repr("text/html", semantic_app(app))
    route!(app; operation_policy=:blocking)
    for stage in instances(WireStage)
        wire = HTMXObjects.option_wire_value(stage)
        @test contains(html, "value=\"$(wire)\"")
        @test HTMXObjects._convert_param(wire, WireStage) === stage
        response = dispatch(:GET, "/selected?stage=" * HTTP.escapeuri(wire))
        @test response.status == 200
        @test String(response.body) == string(stage)
    end
end
