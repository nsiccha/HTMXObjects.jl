# Operations

Choose whether a route answers inline or uses the framework's operation
lifecycle, and inspect the requests and jobs that the application tracks.

## Execution policy

```@example operations
using HTMXObjects
@htmx struct ReadyRoutes
    @get index() = h.p("Ready")
end
route!(ReadyRoutes(); prefix="/ready", operation_policy=:blocking);
response = dispatch(:GET, "/ready/";
    headers=["HX-Request" => "true"]);
result = (status=response.status, body=String(response.body))
@assert result == (status=200, body="<p>Ready</p>") # hide
foreach(println, pairs(result))
```

`:blocking` answers in the current request and is appropriate for this small,
deterministic example. The default [`OperationPolicy`](@ref) is `:auto`, which
selects execution according to the request. `:polling` explicitly chooses the
polling transport. Read the policy's conditions before relying on a response
being the final result of expensive work.

Keep an expensive calculation on its owning data object. A request can then
refer to that calculation without creating a separate data cache in the web
layer. If work continues after the initial response, the browser must follow
the returned lifecycle rather than treating a pending fragment as a completed
result. A build-time example should dispatch with a policy that waits for the
output it claims to show.

## Run a bounded graph operation

A route, a build job and a deployment check can all call the same graph
property. This example translates a small arithmetic expression to a stack
instruction. Both callers get the same permission check and byte limit.

```@example operations
function compile_add(source, envelope, output, diagnostics)
    expr = Meta.parse(source)
    if Meta.isexpr(expr, :call, 3) && expr.args[1] === :(+) &&
            all(x -> x isa Int, expr.args[2:3])
        return ExecutionResult(value=(op=:add, operands=Tuple(expr.args[2:3])))
    end
    print(diagnostics, "expected two integer literals joined by +")
    ExecutionResult(:failed)
end

@htmx struct CompilePage
    compiler::Executor
    permissions::CapabilityPolicy
    limits::ResourceEnvelope
    addition::ApplicationWorkload = ApplicationWorkload(:compile_model, "2 + 3";
        check=r -> r.value == (op=:add, operands=(2, 3)))
    @fresh compile_model(source; context) = execute(compiler, source;
        capability=permissions, envelope=limits, context)
    @fresh readiness(caller) = execution_availability(compiler;
        capability=permissions, envelope=limits, context=caller)
    @post compile(; source::String) = let caller = get(__req__.context, :principal, :guest)
        outcome = compile_model(source; context=caller)
        status = outcome.status === :ok ? 200 : outcome.status === :refused ? 403 : 422
        HTTP.Response(status, string(outcome.status))
    end
end

app = CompilePage(Executor(compile_add), CapabilityPolicy(==(:builder)),
    ResourceEnvelope(input_bytes=128, stdout_bytes=1024, stderr_bytes=256))
result = run_workload(app, application_workloads(app).addition; context=:builder)
@assert result.status === :ok # hide
@assert app.readiness(:guest) === :refused # hide
result.value
```

The application supplies caller identity. In this example its middleware sets
`req.context[:principal]`, and the tool supplies its own trusted context.
`@fresh` rechecks permission and capacity on every invocation. To show current
availability in a `semantic_app` form, read the same `readiness(caller)` property
in its `submit` and `submit_attrs` callbacks. Type-level
`application_descriptor(CompilePage)` exposes the declared dependencies without
checking permission or starting a compile.

An [`Executor`](@ref) applies its concurrency limit across calls sharing that
instance in one process. Use `@queued` when excess work should wait.
`execute` returns `:saturated` when its slots are occupied. Keep hard
wall-time, memory and task enforcement in the host adapter. Declare the limits
it can enforce using `hard_limits` and check the envelope before launching
work. An unsupported hard limit produces `:unavailable`. For custom inputs or
a syntax-node limit, pass `measure(input, Val(dimension))` to the executor.
Stream diagnostics to the two provided buffers. Adapters that launch children
own termination, bounded pipe draining and cleanup.

Precompile and acceptance tools read the same [`ApplicationWorkload`](@ref)
from the mounted object. [`run_workload`](@ref) throws when either the status
or the value differs from the example's expectation. Keep application behavior
on graph properties. A function below the graph can implement a compiler
primitive, a library callback or a process entry point.

## Runtime inspection

```@example operations
@htmx struct MonitoredApp
    @include runtime = RuntimeRoutes()
    @get index() = h.p("Application")
end
foreach(println, [(r.verb, r.path) for r in reflect(MonitoredApp)])
```

`RuntimeRoutes` provides the mountable runtime surface. `runtime_snapshot`
reads a tracker's state; `track_requests` supplies request instrumentation.
Application-owned background work can be registered with `track_job!`, and
`jobs_board` renders tracked jobs. Tracking a job and scheduling a job are
different responsibilities; `configure_job_queue!` configures the queue.

Expose operational controls only where the application's access policy allows
them. An administrative route is not an authentication mechanism. The
[runtime reference](../reference/runtime.md) groups the tracker, job, error and
streaming interfaces and links to their source contracts.

## Error boundary

A failed request has an HTTP status and a response body. Inspect both; a
successful transport does not imply that the returned HTML represents a
successful calculation. HTMXObjects records errors through its error recorder
and carries the error identifier in error responses. `CallerFault` distinguishes
caller-facing failures, while `ErrorTexts` supplies the words shown to readers.

Use `dispatch` to diagnose the route itself. Use an HTTP request through the
listener when diagnosing middleware or server behaviour, and a browser when
diagnosing polling, swapping or loaded assets. Each check observes a different
boundary.

The [sample browser](../examples/sample-browser.md) uses blocking dispatch and
asserts the response content before displaying it.
