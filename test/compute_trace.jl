using TestItemRunner

# `serve(; compute_trace)`: the DynamicObjects compute trace of one HTTP request
# (user decision `1wbhyfs`, todo `09gck4a`). A request opts in with `?__trace` or
# `X-HTMXO-Trace: 1` under `:requested`; `:all` traces every request; `false`
# ignores both. Its response carries `X-HTMXO-Trace-Id` and `Server-Timing`, its
# trace stays open until the operations it started end, and the closed trace is
# kept on the runtime tracker for `RuntimeRoutes` and logged once.
@testmodule ComputeTraceFixtures begin
    using HTMXObjects, HTTP, DynamicObjects
    import HTMXObjects: h
    export CTPageApp, CT_PARSES, CT_GATE, ct_reset!, ct_pipeline, ct_get, ct_body,
        ct_row, ct_hasrow, ct_settles, ct_poll_url, ct_running, ct_settle

    const CT_PARSES = Threads.Atomic{Int}(0)
    const CT_GATE = Ref(Base.Event())
    # What `@fresh ct_parse_state` costs: an Invoices-style YAML parse.
    ct_parse(n) = (Threads.atomic_add!(CT_PARSES, 1); sleep(0.002); n)

    @htmx struct CTPageApp
        "Parse the state"
        @fresh ct_parse_state(n::Int) = ct_parse(n)
        "The total, read from three parses"
        ct_total(n::Int) = ct_parse_state(n) + ct_parse_state(n) + ct_parse_state(n)
        "The slow part of the report"
        ct_report_part(key::String) = (wait(CT_GATE[]); ct_parse_state(7) + 1)

        @get ct_page(; n::Int=2) = h.p("total ", string(ct_total(n)))
        @get ct_shell() = htmx(h.p("shell"))
        @get ct_static() = h.p("no reads")
        @get ct_echo(; x::String="") = h.p("echo ", x)
        @get ct_active() = h.p(string(DynamicObjects._ACTIVE_TRACES[]))
        @get ct_report(; key::String="a") = h.p("report ", string(ct_report_part(key)))
        @include ct_runtime = RuntimeRoutes()
    end

    function ct_reset!()
        notify(CT_GATE[])
        CT_GATE[] = Base.Event()
        CT_PARSES[] = 0
        nothing
    end

    # `serve`'s own pipeline, without a socket: tracker → trace → router.
    ct_pipeline(tracker; compute_trace=:requested) = HTMXObjects._request_pipeline(
        [], nothing, nothing, tracker; compute_trace)

    ct_get(app, target; headers=Pair{String,String}[]) =
        app(HTTP.Request("GET", target, headers, UInt8[]))
    ct_body(response) = String(copy(HTMXObjects._message_body_bytes(response)))

    ct_row(rt, name) = only(filter(r -> r.property === name, compute_trace_rows(rt.trace)))
    ct_hasrow(rt, name) = any(r -> r.property === name, compute_trace_rows(rt.trace))
    ct_settles(f, seconds=10.0) = timedwait(f, seconds; pollint=0.01) === :ok

    ct_running(body) = contains(body, "hx-trigger=\"every ")
    # Poll `url` until it stops answering a running poller; the last answer.
    function ct_settle(app, url; headers=Pair{String,String}[])
        for _ in 1:400
            response = ct_get(app, url; headers)
            ct_running(ct_body(response)) || return response
            sleep(0.025)
        end
        error("operation never settled: $url")
    end

    function ct_poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
end

@testitem "an opted-in request's trace names its slow @fresh property" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Logging, Test

    ct_reset!()
    route!(CTPageApp())
    tracker = RuntimeTracker()
    app = ct_pipeline(tracker)
    logger = Test.TestLogger()
    response = with_logger(logger) do
        ct_get(app, "/ct_page?n=3&__trace")
    end
    @test response.status == 200
    @test contains(ct_body(response), "total 9")
    id = parse(Int, HTTP.header(response, "X-HTMXO-Trace-Id"))
    rt = request_trace(id, tracker)
    @test rt isa RequestTrace
    @test rt.method == "GET"
    @test rt.target == "/ct_page?n=3&__trace"
    @test rt.status == 200
    @test isfinite(rt.response_s) && isfinite(rt.duration)
    # The @fresh parse ran three times in this one request; the memoized total once.
    parse_row = ct_row(rt, :ct_parse_state)
    @test parse_row.fresh == 3
    @test parse_row.self_s > 0
    @test ct_row(rt, :ct_total).computed == 1
    @test first(request_traces(tracker)) === rt
    # `Server-Timing` names it, with its own time in milliseconds.
    timing = HTTP.header(response, "Server-Timing")
    @test occursin(r"CTPageApp\.ct_parse_state;dur=[0-9.]+;desc=\"CTPageApp\.ct_parse_state \(3 fresh\)\"", timing)
    # One log line, when the trace closed.
    lines = [string(l.message) for l in logger.logs if l.group === :trace]
    @test length(lines) == 1
    @test occursin(Regex("trace $id GET /ct_page\\?n=3&__trace 200 [0-9.]+s: "), only(lines))
    @test occursin("CTPageApp.ct_parse_state", only(lines))
    @test occursin("(3 fresh)", only(lines))

    # The header asks too; each request has a trace of its own.
    again = ct_get(app, "/ct_page?n=3"; headers=["X-HTMXO-Trace" => "1"])
    rt2 = request_trace(parse(Int, HTTP.header(again, "X-HTMXO-Trace-Id")), tracker)
    @test rt2 isa RequestTrace && rt2.id != rt.id
    @test ct_hasrow(rt2, :ct_total)
    @test [t.id for t in request_traces(tracker)] == [rt2.id, rt.id]
    # "0" asks for nothing.
    off = ct_get(app, "/ct_page?n=3"; headers=["X-HTMXO-Trace" => "0"])
    @test !HTTP.hasheader(off, "X-HTMXO-Trace-Id")
end

@testitem "a request that does not ask is answered as before and starts no trace" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    ct_reset!()
    route!(CTPageApp())
    tracker = RuntimeTracker()
    traced = ct_pipeline(tracker)
    plain = ct_pipeline(tracker; compute_trace=false)
    for target in ("/ct_page?n=4", "/ct_static", "/ct_shell")
        a, b = ct_get(traced, target), ct_get(plain, target)
        @test a.status == b.status == 200
        @test ct_body(a) == ct_body(b)
        @test a.headers == b.headers
        @test !HTTP.hasheader(a, "X-HTMXO-Trace-Id")
        @test !HTTP.hasheader(a, "Server-Timing")
    end
    # No DynamicObjects trace is active while it runs (its hooks stay one atomic load).
    @test ct_body(ct_get(traced, "/ct_active")) == "<p>0</p>"
    @test ct_body(ct_get(traced, "/ct_active?__trace")) == "<p>1</p>"
    @test length(request_traces(tracker)) == 1
    @test isempty(tracker.open_traces)
end

@testitem "with compute_trace off the flag and the header are ignored" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    ct_reset!()
    route!(CTPageApp())
    tracker = RuntimeTracker()
    app = ct_pipeline(tracker; compute_trace=false)
    response = ct_get(app, "/ct_echo?x=1&__trace"; headers=["X-HTMXO-Trace" => "1"])
    # `__trace` is a framework name: it never reaches the route's parameters.
    @test response.status == 200
    @test ct_body(response) == "<p>echo 1</p>"
    @test !HTTP.hasheader(response, "X-HTMXO-Trace-Id")
    @test ct_body(ct_get(app, "/ct_active?__trace")) == "<p>0</p>"
    @test isempty(request_traces(tracker))
    @test_throws ArgumentError ct_pipeline(tracker; compute_trace=true)
    @test_throws ArgumentError serve(; compute_trace=:sometimes)
end

@testitem "a polled operation's work is in the trace of the request that started it" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Treebars, Test

    ct_reset!()
    HTMXObjects._clear_operation_polls!()
    route!(CTPageApp())
    tracker = RuntimeTracker()
    app = ct_pipeline(tracker)
    hx = ["HX-Request" => "true"]
    first_response = ct_get(app, "/ct_report?key=polled&__trace"; headers=hx)
    body = ct_body(first_response)
    # The route answered with a poller: its slow part has not run yet.
    @test ct_running(body)
    id = parse(Int, HTTP.header(first_response, "X-HTMXO-Trace-Id"))
    rt = request_trace(id, tracker)
    @test rt.status == 200 && isfinite(rt.response_s)
    @test isnan(rt.duration)
    @test haskey(tracker.open_traces, id)
    @test first(request_traces(tracker)) === rt
    # The page script would send the header on the polls: a poll that only
    # waits or reads memory keeps no trace of its own.
    url = ct_poll_url(body)
    @test ct_running(ct_body(ct_get(app, url; headers=[hx; "X-HTMXO-Trace" => "1"])))
    notify(CT_GATE[])
    @test ct_settles(() -> isfinite(rt.duration))
    @test !haskey(tracker.open_traces, id)
    # The work after the response is in this request's trace.
    @test ct_row(rt, :ct_report_part).computed == 1
    @test ct_row(rt, :ct_parse_state).fresh == 1
    @test rt.duration > rt.response_s
    final = ct_settle(app, url; headers=[hx; "X-HTMXO-Trace" => "1"])
    @test contains(ct_body(final), "report 8")
    @test [t.id for t in request_traces(tracker)] == [id]
end

@testitem "a traced page asks for the traces of its own htmx requests" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    ct_reset!()
    route!(CTPageApp())
    tracker = RuntimeTracker()
    app = ct_pipeline(tracker)
    untraced = ct_body(ct_get(app, "/ct_shell"))
    traced = ct_get(app, "/ct_shell?__trace")
    body = ct_body(traced)
    script = HTMXObjects._TRACE_PAGE_SCRIPT
    @test !contains(untraced, "data-htmxo-trace")
    @test count(script, body) == 1
    # Right after the body's opening tag; the rest of the page is as it was.
    @test occursin(r"<body[^>]*><script data-htmxo-trace>", body)
    @test replace(body, script => "") == untraced
    @test occursin("text/html", HTTP.header(traced, "Content-Type"))
    @test !HTTP.hasheader(traced, "Content-Length") ||
          parse(Int, HTTP.header(traced, "Content-Length")) == ncodeunits(body)
    # A fragment swap and a page traced under `:all` carry no script.
    @test !contains(ct_body(ct_get(app, "/ct_shell?__trace"; headers=["HX-Request" => "true"])),
                    "data-htmxo-trace")
    @test !contains(ct_body(ct_get(ct_pipeline(tracker; compute_trace=:all), "/ct_shell")),
                    "data-htmxo-trace")
    # The script asks only for same-origin requests.
    @test contains(script, "htmx:configRequest")
    @test contains(script, "location.origin")
end

@testitem "RuntimeRoutes lists traced requests and shows one trace" setup=[ComputeTraceFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    ct_reset!()
    route!(CTPageApp())
    tracker = runtime_tracker()
    clear_runtime_history!(tracker)
    app = ct_pipeline(tracker; compute_trace=:all)
    response = ct_get(app, "/ct_page?n=5")
    id = parse(Int, HTTP.header(response, "X-HTMXO-Trace-Id"))
    # Under `:all` a request that read no property (a plain handler, a static
    # file) is not kept, nor are the dashboard's own requests.
    HTTP.register!(HTMXObjects.ROUTER, "GET", "/ct_raw", req -> HTTP.Response(204))
    @test HTTP.hasheader(ct_get(app, "/ct_raw"), "X-HTMXO-Trace-Id")
    list = ct_get(app, "/ct_runtime/traces?plain")
    @test !HTTP.hasheader(list, "X-HTMXO-Trace-Id")
    @test [t.id for t in request_traces(tracker)] == [id]

    text = ct_body(list)
    @test contains(text, "Traced requests")
    @test contains(text, "[#$id](/ct_runtime/trace/$id)")
    @test contains(text, "/ct_page?n=5")
    @test contains(text, "CTPageApp.ct_parse_state")

    one = ct_body(ct_get(app, "/ct_runtime/trace/$id?plain"))
    @test contains(one, "# Trace #$id")
    @test contains(one, "GET /ct_page?n=5")
    @test occursin(r"\| `CTPageApp\.ct_parse_state` \| [0-9.]+ \|", one)
    @test contains(one, "Fresh")
    @test contains(one, "No invalidation.")
    @test contains(ct_body(ct_get(app, "/ct_runtime/trace/999999?plain")), "Not kept")
    @test contains(ct_body(ct_get(app, "/ct_runtime?live=false")), "/ct_runtime/traces")
    @test [t.id for t in request_traces(tracker)] == [id]

    # The ring is bounded; clearing the history forgets it.
    for n in 1:3
        ct_get(app, "/ct_page?n=$(10 + n)")
    end
    configure_runtime!(tracker; trace_limit=2)
    @test length(request_traces(tracker)) == 2
    @test request_trace(id, tracker) === nothing
    clear_runtime_history!(tracker)
    @test isempty(request_traces(tracker))
    configure_runtime!(tracker; trace_limit=100)
    @test contains(ct_body(ct_get(app, "/ct_runtime/traces?plain")), "No traced requests")
end

@testitem "Server-Timing metric names are HTTP tokens and descriptions are quoted" tags=[:unit] begin
    using HTMXObjects, Test

    struct CTParam{T} end
    rows = [(; type=CTParam{:a}, property=:value, calls=2, hits=1, computed=1, fresh=0,
              disk=0, waits=0, pending=0, errors=0, self_s=0.25, total_s=0.25,
              max_s=0.25, hit_s=0.0005, wait_s=0.0)]
    timing = HTMXObjects._server_timing(rows)
    @test timing == "CTParam__a_.value;dur=250.5;desc=\"CTParam{:a}.value (1 computed, 1 hits)\""
    @test HTMXObjects._http_quoted("a\"b\\c\nd") == "\"a\\\"b\\\\c d\""
    @test HTMXObjects._server_timing([]) == ""
end

@testitem "serve(; compute_trace=:requested) answers a traced request with its trace" setup=[ComputeTraceFixtures, HTMXOTestPorts] tags=[:integration, :server] begin
    using HTMXObjects, HTTP, Logging, Test

    ct_reset!()
    route!(CTPageApp())
    clear_runtime_history!(runtime_tracker())
    port = free_port()
    base = "http://127.0.0.1:$port"
    logger = Test.TestLogger()
    with_logger(logger) do
        serve(; port, async=true, compute_trace=:requested)
    end
    try
        traced = HTTP.get(base * "/ct_page?n=6&__trace"; retry=false, readtimeout=20)
        @test traced.status == 200
        id = parse(Int, HTTP.header(traced, "X-HTMXO-Trace-Id"))
        @test occursin("CTPageApp.ct_parse_state", HTTP.header(traced, "Server-Timing"))
        @test ct_row(request_trace(id), :ct_parse_state).fresh == 3
        plain = HTTP.get(base * "/ct_page?n=7"; retry=false, readtimeout=20)
        @test !HTTP.hasheader(plain, "X-HTMXO-Trace-Id")
        @test String(plain.body) == "<p>total 21</p>"
    finally
        terminate()
    end
    lines = [string(l.message) for l in logger.logs if l.group === :trace]
    @test length(lines) == 1
    @test occursin("GET /ct_page?n=6&__trace 200", only(lines))
end
