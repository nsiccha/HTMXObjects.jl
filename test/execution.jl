using TestItemRunner

@testmodule ExecutionFixtures begin
    using HTMXObjects
    export CompileBench, make_bench, compile_sum, test_caller, policy

    # Only the small arithmetic grammar below reaches Julia's lowerer.
    function compile_sum(source, limits, output, diagnostics)
        expr = Meta.parse(source)
        if !Meta.isexpr(expr, :call, 3) || expr.args[1] !== :(+) ||
                !all(arg -> arg isa Int, expr.args[2:3])
            print(diagnostics, "expected two integer literals separated by +")
            return ExecutionResult(:failed)
        end
        code = Meta.lower(@__MODULE__, expr)
        print(output, "lowered")
        ExecutionResult(value=code.args[1], usage=(; syntax_nodes=4))
    end

    # The test route stands in for middleware that resolves a caller. The
    # workload takes the same trusted context through the non-HTTP operation.
    test_caller(req) = HTTP.header(req, "Authorization", "") == "Bearer fixture" ? :trusted : :public
    policy() = CapabilityPolicy(==(:trusted))
    @htmx struct CompileBench
        compiler::Executor
        permissions::CapabilityPolicy
        limits::ResourceEnvelope
        example::ApplicationWorkload
        refused::ApplicationWorkload = ApplicationWorkload(:compile_model, "2 + 3"; expected_status=:refused)
        unrelated = error("workload discovery computed an unrelated property")
        @fresh compile_model(source; context) = execute(compiler, source;
            capability=permissions, envelope=limits, context)
        @fresh availability(caller) = execution_availability(compiler; capability=permissions,
            envelope=limits, context=caller)
        @post compile(; source::String) = let result = compile_model(source; context=test_caller(__req__))
            HTTP.Response(result.status === :refused ? 403 : result.status === :ok ? 200 : 422,
                          string(result.status))
        end
    end
    make_bench() = CompileBench(Executor(compile_sum), policy(), ResourceEnvelope(input_bytes=64),
        ApplicationWorkload(:compile_model, "2 + 3"; check=result -> result.value isa Core.CodeInfo))
end

@testitem "a compile workload uses the same graph property as its route" setup=[ExecutionFixtures] tags=[:unit, :semantic] begin
    bench = make_bench()
    desc = application_descriptor(CompileBench)
    node(name) = only(n for n in desc.nodes if n.kind === :property && n.metadata.name === name).id
    dependencies = [edge.to for edge in desc.edges if edge.kind === :depends_on && edge.from == node(:compile_model)]
    @test all(name -> node(name) in dependencies, (:compiler, :permissions, :limits))
    @test application_workloads(bench) == (; example=bench.example, refused=bench.refused)
    route = only(semantic_descriptor(CompileBench).routes)
    @test isempty(intersect([p.name for p in route.params], [:compiler, :permissions, :limits]))
    for (caller, label) in ((:trusted, "available"), (:public, "refused"))
        page = semantic_app(bench; submit=entry -> string(entry.object.availability(caller)),
            submit_attrs=entry -> (; disabled=entry.object.availability(caller) !== :available))
        @test occursin(label, repr("text/html", page))
    end
    @test bench.availability(:trusted) === :available
    @test bench.availability(:public) === :refused
    workload = application_workloads(bench).example
    @test run_workload(bench, workload; context=:trusted).stdout == "lowered"
    @test bench.compile_model("2 + 3"; context=:public).status === :refused
    @test_throws ErrorException run_workload(bench, workload; context=:public)
    @test_throws ErrorException run_workload(bench,
        ApplicationWorkload(:compile_model, "2 + 3"; check=_ -> false); context=:trusted)
    @test run_workload(bench, ApplicationWorkload(:compile_model, "x"; expected_status=:failed);
                        context=:trusted).stderr == "expected two integer literals separated by +"
    @test run_workload(bench, application_workloads(bench).refused; context=:readonly).status === :refused

    route!(bench; prefix="/compile-contract", operation_policy=:blocking)
    headers = ["Content-Type" => "application/x-www-form-urlencoded"]
    url = "/compile-contract/compile"
    @test dispatch(:POST, url; headers, body="source=2%20%2B%203&context=trusted").status == 403
    allowed = [headers; "Authorization" => "Bearer fixture"]
    response = dispatch(:POST, url; headers=allowed, body="source=2%20%2B%203")
    @test (response.status, String(response.body)) == (200, "ok")
    @test dispatch(:POST, url; headers=allowed, body="source=x").status == 422
end

@testitem "execution admission enforces measurements and adapter guarantees" tags=[:unit] begin
    invoked = Ref(0)
    measured = Symbol[]
    function measure(input, ::Val{dimension}) where {dimension}
        push!(measured, dimension)
        dimension === :syntax_nodes ? 4 : dimension === :input_lines ? 1 : ncodeunits(input)
    end
    worker = Executor(; measure) do input, limits, output, diagnostic
        invoked[] += 1
        ExecutionResult(value=input)
    end
    capability = CapabilityPolicy(==(:trusted))
    call(limits) = execute(worker, "2 + 3"; context=:trusted, capability, envelope=limits)
    @test call(ResourceEnvelope(input_bytes=1, syntax_nodes=2)).status === :refused
    @test measured == [:input_bytes]
    empty!(measured)
    @test call(ResourceEnvelope(input_bytes=5, input_lines=1, syntax_nodes=3)).status === :refused
    @test measured == [:input_bytes, :input_lines, :syntax_nodes]
    @test all(limit -> call(limit).status === :unavailable,
              (ResourceEnvelope(wall_seconds=1), ResourceEnvelope(memory_bytes=1024), ResourceEnvelope(tasks=1)))
    @test invoked[] == 0
    @test call(ResourceEnvelope(syntax_nodes=4)).value == "2 + 3"
    @test invoked[] == 1
    @test execution_availability(worker; context=:public, capability) === :refused
    for state in (:unavailable, :saturated)
        cap = CapabilityPolicy(Returns(true); availability=Returns(state))
        @test execute(worker, ""; context=nothing, capability=cap).status === state
    end
    unlimited = Executor((args...) -> ExecutionResult())
    @test execute(unlimited, "x"; context=:trusted, capability, envelope=ResourceEnvelope(syntax_nodes=3)).status === :unavailable
    @test_throws ArgumentError Executor(identity; hard_limits=(:unknown,))
    @test_throws ArgumentError Executor(identity; concurrency=0)
    @test_throws ArgumentError ResourceEnvelope(wall_seconds=NaN)
    @test_throws ArgumentError ResourceEnvelope(stderr_bytes=-1)
    @test_throws ArgumentError ApplicationWorkload(:compile; kwargs=(; context=:trusted))
end

@testitem "execution results bound diagnostics and preserve adapter failure causes" tags=[:unit] begin
    cap = CapabilityPolicy(Returns(true))
    call(f; kw...) = execute(Executor(f), nothing; capability=cap, context=nothing, envelope=ResourceEnvelope(; kw...))
    written = Int[]
    limit = call(; stdout_bytes=3) do x, l, out, err
        push!(written, write(out, "αααα"))
        ExecutionResult(value="discard")
    end
    @test only(written) == 4
    @test (limit.status, limit.stdout, limit.value) == (:output_limit, "α", nothing)
    bytes = call(; stderr_bytes=2) do x, l, out, err
        write(err, UInt8[0xff, 0x41])
        ExecutionResult()
    end
    @test (bytes.stderr, bytes.stderr_truncated) == ("?A", false)
    failed = call((args...) -> error("compile failed"); stderr_bytes=7)
    @test (failed.status, failed.stderr) == (:failed, "compile")
    @test failed.stderr_truncated && !failed.stdout_truncated
    @test limit.stdout_truncated && !limit.stderr_truncated
    for (reply, status) in ((ExecutionResult(exit_code=2), :failed),
                             (ExecutionResult(signal=15), :signaled),
                             (ExecutionResult(:timeout; signal=9), :timeout))
        result = call((args...) -> reply)
        @test (result.status, result.exit_code, result.signal) == (status, reply.exit_code, reply.signal)
    end
    @test_throws InterruptException call((args...) -> throw(InterruptException()))
    @test_throws ArgumentError call((args...) -> "invalid adapter result")
end

@testitem "capacity is shared during execution and released on failure" tags=[:unit] begin
    started = Channel{Nothing}(1)
    resume = Channel{Nothing}(1)
    ex = Executor() do input, limits, output, diagnostic
        input === :check && return ExecutionResult(value=:done)
        put!(started, nothing)
        take!(resume)
        error("failed after admission")
    end
    kw = (; capability=CapabilityPolicy(Returns(true)), context=nothing)
    active = @async execute(ex, :block; kw...)
    try
        take!(started)
        @test execution_availability(ex; kw...) === :saturated
        @test execute(ex, :check; kw...).status === :saturated
    finally
        put!(resume, nothing)
    end
    @test fetch(active).status === :failed
    @test execution_availability(ex; kw...) === :available
    @test execute(ex, :check; kw...).value === :done
end

@testitem "a host adapter compiles a model in a child and enforces its deadline" setup=[ExecutionFixtures] tags=[:integration, :execution] begin
    # The child only compiles this trusted kernel, specialized to the literal
    # scale read from the model. It never evaluates submitted Julia syntax.
    worker = raw"""
        gaussian(y, mu, ::Val{S}) where S = -0.5 * ((y - mu) / S)^2
        source = read(stdin, String)
        model = match(r"^y ~ normal\(mu, ([1-9][0-9]?)\)$", source)
        if isnothing(model)
            print(stderr, "expected a normal model with a positive literal scale")
            exit(65)
        end
        scale = Val(parse(Int, only(model.captures)))
        precompile(gaussian, (Float64, Float64, typeof(scale))) || exit(1)
        print(gaussian(3.0, 1.0, scale))
    """
    function host_adapter(source, envelope, output, diagnostics)
        cmd = `$(Base.julia_cmd()) --startup-file=no -t1 -e $worker`
        outpipe, errpipe = Pipe(), Pipe()
        child = run(pipeline(cmd; stdin=IOBuffer(source), stdout=outpipe, stderr=errpipe); wait=false)
        close(outpipe.in)
        close(errpipe.in)
        timeout = false
        @sync begin
            @async try
                write(output, outpipe)
            finally
                close(outpipe)
                closewrite(output)
            end
            @async try
                write(diagnostics, errpipe)
            finally
                close(errpipe)
                closewrite(diagnostics)
            end
            try
                timeout = timedwait(() -> process_exited(child), envelope.wall_seconds; pollint=0.01) === :timed_out
            finally
                process_exited(child) || kill(child, Base.SIGKILL)
                wait(child)
            end
        end
        ExecutionResult(timeout ? :timeout : :ok; exit_code=Int(child.exitcode), signal=Int(child.termsignal))
    end
    ex = Executor(host_adapter; hard_limits=(:wall_seconds,))
    smoke = ApplicationWorkload(:compile_model, "y ~ normal(mu, 2)"; check=r -> r.stdout == "-0.5")
    bench = CompileBench(ex, policy(), ResourceEnvelope(wall_seconds=40, input_bytes=128), smoke)
    fixture = application_workloads(bench).example
    @test run_workload(bench, fixture; context=:trusted).exit_code == 0
    warmed = Ref(false)
    prewarm_workload!(bench; routes=Symbol[], operations=false) do _
        warmed[] = run_workload(bench, fixture; context=:trusted).status === :ok
    end
    @test warmed[]
    bad = ApplicationWorkload(:compile_model, "invalid"; expected_status=:failed)
    failed = run_workload(bench, bad; context=:trusted)
    @test failed.exit_code == 65
    @test occursin("expected a normal model", failed.stderr)
    noisy = CompileBench(ex, policy(), ResourceEnvelope(wall_seconds=40, stdout_bytes=2), smoke)
    clipped = run_workload(noisy, ApplicationWorkload(:compile_model, "y ~ normal(mu, 2)";
        expected_status=:output_limit); context=:trusted)
    @test clipped.stdout == "-0"
    impatient = CompileBench(ex, policy(), ResourceEnvelope(wall_seconds=0.001), smoke)
    timed = run_workload(impatient, ApplicationWorkload(:compile_model, "y ~ normal(mu, 2)";
        expected_status=:timeout); context=:trusted)
    @test timed.status === :timeout
    @test execution_availability(ex; capability=policy(), context=:trusted) === :available
end
