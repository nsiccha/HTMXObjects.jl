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
result
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

## Runtime inspection

```@example operations
@htmx struct MonitoredApp
    @include runtime = RuntimeRoutes()
    @get index() = h.p("Application")
end
[(r.verb, r.path) for r in reflect(MonitoredApp)]
```

`RuntimeRoutes` provides the mountable runtime surface. `runtime_snapshot`
reads a tracker's state; `track_requests` supplies request instrumentation.
Application-owned background work can be registered with `track_job!`, and
`jobs_board` renders tracked jobs. Tracking a job and scheduling a job are
different responsibilities; `configure_job_queue!` configures the queue.

Expose operational controls only where the application's access policy allows
them. An administrative route is not an authentication mechanism. The
[runtime reference](../reference/runtime.md) groups the tracker, job, error and
streaming interfaces with their full contracts.

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
