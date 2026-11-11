using TestItemRunner

@testitem "independent service generations preserve writer state and drain in-flight readers" setup=[HTMXOTestImports, HTMXOTestPorts] tags=[:integration, :server] begin
    import JSON
    import Random

    script = joinpath(@__DIR__, "..", "examples", "service_slices", "server.jl")
    token = Random.randstring(32)
    children = []
    root = mktempdir()
    function start_service(role; port=free_port(), writer_url="")
        control = mktempdir(root; prefix=string(role) * "-")
        logfile = joinpath(control, "server.log")
        io = open(logfile, "w")
        command = `$(Base.julia_cmd()) --project=$(dirname(Base.active_project())) --threads=2,1 $script $role $port $control $writer_url`
        started = time()
        process = run(pipeline(addenv(command, "HTMXO_SERVICE_TOKEN" => token,
            "HTMXO_SERVICE_LAUNCHED_AT" => string(started)), stdout=io, stderr=io); wait=false)
        child = (; role, process, port, control, logfile, io, started,
                   url="http://127.0.0.1:$port")
        push!(children, child)
        child
    end
    function await_file(child, name; timeout=600)
        path = joinpath(child.control, name)
        status = timedwait(() -> isfile(path) || process_exited(child.process), timeout; pollint=0.05)
        status === :ok && isfile(path) || error(
            "$(child.role) did not produce $name: " * read(child.logfile, String))
        path
    end
    ready(child) = JSON.parse(read(await_file(child, "ready.json"), String))
    function request(child, path; method="GET", actor="demo")
        timeout = pkgversion(HTTP) >= v"2" ? (; request_timeout=300) : (; readtimeout=300)
        HTTP.request(method, child.url * path,
            ["X-Actor" => actor, "X-Request-ID" => "process-fixture", "Accept" => "application/json"];
            retry=false, status_exception=false, timeout...)
    end
    function payload(child, path; kwargs...)
        response = request(child, path; kwargs...)
        response.status == 200 || error("$(child.role) $path: $(response.status) $(String(response.body))")
        JSON.parse(String(response.body))
    end
    function memory(child)
        touch(joinpath(child.control, "measure"))
        JSON.parse(read(await_file(child, "memory.json"), String))["rss_bytes"]
    end
    try
        whole = start_service(:whole)
        writer = start_service(:writer)
        reader = start_service(:reader; writer_url=writer.url)
        whole_ready, writer_ready, reader_ready = ready(whole), ready(writer), ready(reader)
        @test length(Set([whole_ready["pid"], writer_ready["pid"], reader_ready["pid"]])) == 3
        @test "compile_only" in reader_ready["compile_routes"]
        writer_before = payload(writer, "/status")
        reader_before = payload(reader, "/status")
        for service in (whole, writer), (sequence, value) in enumerate([2.0, 4.0])
            @test payload(service, "/append?sequence=$sequence&value=$value"; method="POST")["sequence"] == sequence
        end
        @test payload(whole, "/forecast?scale=3") == payload(reader, "/forecast?scale=3") ==
              Dict("sequence" => 2, "forecast" => 27.0, "actor" => "demo")
        @test payload(whole, "/overlap?x=5") == payload(reader, "/overlap?x=5") == payload(writer, "/overlap?x=5")
        @test request(reader, "/forecast?scale=invalid").status == request(whole, "/forecast?scale=invalid").status == 400
        @test request(reader, "/forecast"; actor="denied").status == request(whole, "/forecast"; actor="denied").status == 401
        @test request(writer, "/append?sequence=1&value=9"; method="POST").status ==
              request(whole, "/append?sequence=1&value=9"; method="POST").status == 409
        @test HTTP.header(request(reader, "/forecast"), "X-Request-ID") == "process-fixture"
        for service in (whole, writer, reader)
            @test request(service, "/omitted").status == 404
            @test request(service, "/compile_only?value=1"; method="POST").status == 404
            @test request(service, "/assess").status == 404
        end
        @test request(reader, "/append?sequence=3&value=6"; method="POST").status == 404

        # Measure equivalent completed work before replacement. Each number is
        # process RSS, including Julia and shared library pages; sums may count
        # shared pages twice. This is neither PSS nor peak memory.
        measurements = (; whole_startup_seconds=whole_ready["startup_seconds"],
            writer_startup_seconds=writer_ready["startup_seconds"],
            reader_startup_seconds=reader_ready["startup_seconds"],
            whole_rss_bytes=memory(whole), writer_rss_bytes=memory(writer),
            reader_rss_bytes=memory(reader))
        println("SERVICE_MEASUREMENTS ", JSON.json(measurements))

        held = @async request(reader, "/held")
        await_file(reader, "entered"; timeout=180)
        touch(joinpath(reader.control, "drain"))
        pending = JSON.parse(read(await_file(reader, "drain.json"), String))
        @test pending["drained"] === false
        @test pending["active"] >= 1
        @test request(reader, "/status").status == 503
        @test payload(writer, "/append?sequence=3&value=6"; method="POST")["sequence"] == 3
        writer_at_replacement = payload(writer, "/status")
        @test writer_at_replacement["pid"] == writer_before["pid"]
        @test writer_at_replacement["identity"] == writer_before["identity"]
        touch(joinpath(reader.control, "release"))
        @test timedwait(() -> istaskdone(held), 60; pollint=0.05) === :ok
        completed = fetch(held)
        @test completed.status == 200
        @test JSON.parse(String(completed.body))["pid"] == reader_ready["pid"]
        @test timedwait(() -> process_exited(reader.process), 30; pollint=0.05) === :ok
        @test success(reader.process)
        @test JSON.parse(read(joinpath(reader.control, "drain.json"), String))["drained"] === true

        replacement = start_service(:reader; port=reader.port, writer_url=writer.url)
        replacement_ready = ready(replacement)
        @test replacement_ready["pid"] != reader_ready["pid"]
        @test replacement_ready["generation"] != reader_ready["generation"]
        @test payload(replacement, "/status")["identity"] != reader_before["identity"]
        @test payload(writer, "/status") == writer_at_replacement
        @test payload(replacement, "/forecast?scale=3") ==
              Dict("sequence" => 3, "forecast" => 54.0, "actor" => "demo")
        println("SERVICE_REPLACEMENT ", JSON.json((; writer_pid=writer_ready["pid"],
            old_reader_pid=reader_ready["pid"], new_reader_pid=replacement_ready["pid"],
            replacement_startup_seconds=replacement_ready["startup_seconds"])))
    finally
        # Tear down only children created by this fixture, with a bounded wait.
        for child in children
            touch(joinpath(child.control, "release"))
            touch(joinpath(child.control, "drain"))
        end
        for child in children
            if timedwait(() -> process_exited(child.process), 10; pollint=0.05) !== :ok
                kill(child.process, Base.SIGKILL)
                timedwait(() -> process_exited(child.process), 10; pollint=0.05)
            end
            close(child.io)
        end
    end
end
