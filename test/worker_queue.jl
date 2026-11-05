using TestItemRunner

# The HTMXObjects half of the frontend/backend process split (brief
# HTMXObjects:process-split `wworuo`, GO `1j4ws7y`): `configure_job_queue!`
# forwards a worker count to DynamicObjects' worker executor behind `@queued`;
# a worker-bound body gets the answer's context as plain values and never the
# request; the parts it sends ahead reach the requesting operation's list.

@testitem "configure_job_queue! takes workers: zero is a no-op, a positive count needs DynamicObjects' worker executor" tags=[:unit] begin
    using HTMXObjects, Test

    settings = configure_job_queue!()
    @test haskey(settings, :workers) && settings.workers isa Int
    @test configure_job_queue!(; workers=0).workers == 0
    @test_throws ArgumentError configure_job_queue!(; workers=-1)
    if HTMXObjects._has_queue_workers()
        try
            @test configure_job_queue!(; workers=1).workers == 1
        finally
            configure_job_queue!(; workers=settings.workers)
        end
    else
        err = try
            configure_job_queue!(; workers=1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("workers", sprint(showerror, err))
        @test occursin("DynamicObjects", sprint(showerror, err))
        @test configure_job_queue!().workers == 0
    end
    # A workers call leaves the other settings as they were.
    @test configure_job_queue!(; workers=0).max_running == settings.max_running
    @test configure_job_queue!().abandon_after == settings.abandon_after
end

@testitem "a worker-bound body gets the answer's prefix, language and audience as plain values" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: _worker_context, _with_worker_context, _PAGE_META, _AUDIENCE,
        _NO_PAGE_META, _page_meta, page_lang

    with = HTMXObjects.ScopedValues.with
    context = with(_PAGE_META => merge(_NO_PAGE_META, (; lang="de")), _AUDIENCE => :public) do
        _worker_context("/app")
    end
    @test context == (; __prefix__="/app", lang="de", audience=:public)
    @test context.__prefix__ isa String
    # Outside a request the context is what a worker would see without one.
    @test _worker_context("") == (; __prefix__="", lang=nothing, audience=_AUDIENCE[])

    # Re-established in a worker, what the body reads is the request's.
    seen = _with_worker_context(context) do
        (page_lang(), _AUDIENCE[], _page_meta().prefix)
    end
    @test seen == ("de", :public, "/app")
    @test page_lang() === nothing
    # A context without a value keeps the ambient one.
    @test _with_worker_context(() -> _AUDIENCE[], (; lang="fr")) == _AUDIENCE[]
    @test _with_worker_context(page_lang, (; lang="fr")) == "fr"
end

@testitem "a @queued route that reads the request stays in this process; one that does not may run in a worker" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h, _reads_request, _worker_eligible

    @htmx struct WorkerEligibility
        "Heavy, request-free"
        @queued @get portable(; n::Int=1) = h.p("n=$n")
        "Heavy, reads the request itself"
        @queued @get direct(; n::Int=1) = h.p(string(__req__.method, n))
        "The request's method, read by a sibling"
        method_name = string(__req__.method)
        "Heavy, reads the request through a sibling"
        @queued @get indirect() = h.p(method_name)
        "Heavy, reads the request's route"
        @queued @get routed() = h.p(string(__route__))
        "Ordinary"
        @get light() = h.p("light")
    end

    @test !_reads_request(WorkerEligibility, :portable)
    @test !_reads_request(WorkerEligibility, :light)
    @test _reads_request(WorkerEligibility, :direct)
    @test _reads_request(WorkerEligibility, :indirect)
    @test _reads_request(WorkerEligibility, :routed)

    @test _worker_eligible(WorkerEligibility, :portable, true)
    @test !_worker_eligible(WorkerEligibility, :light, false)
    @test !_worker_eligible(WorkerEligibility, :portable, false)
    # The route that reads the request computes here, and says so once.
    @test (@test_logs (:warn, r"reads the request") _worker_eligible(WorkerEligibility, :direct, true)) == false
    @test !_worker_eligible(WorkerEligibility, :indirect, true)
end

@testitem "parts a worker-bound body sends ahead leave through its channel and land on the requesting operation's list" tags=[:unit] begin
    using HTMXObjects, Test
    import HTMXObjects: h, _SentAhead, _SentAheadForwarder, _with_sent_ahead_forwarding,
        _receive_sent_ahead!, _sent_ahead_parts, _add_part!, _watch_sent_ahead!, _SENT_AHEAD

    html(x) = repr(MIME"text/html"(), x)
    sent = String[]
    rv = _with_sent_ahead_forwarding(s -> push!(sent, s)) do
        send_ahead(h.p("one"))
        send_ahead(h.p("two"))
        1
    end
    @test rv == 1
    @test sent == html.([h.p("one"), h.p("two")])

    # The forwarding list keeps nothing, shows nothing to a page and is
    # followed by no stream.
    forwarding = _SentAhead(; forward=_SentAheadForwarder(s -> nothing))
    _add_part!(forwarding, "<p>x</p>")
    @test isempty(forwarding.parts) && forwarding.bytes == 0
    @test isempty(_sent_ahead_parts(forwarding, 0))
    @test _watch_sent_ahead!(forwarding, Channel{String}(1), "+t") === nothing

    # On the requesting side a received part lands as `send_ahead` would put it.
    sink = _SentAhead()
    HTMXObjects.ScopedValues.with(_SENT_AHEAD => sink) do
        foreach(_receive_sent_ahead!, sent)
    end
    @test last.(_sent_ahead_parts(sink, 0)) == sent
    @test first.(_sent_ahead_parts(sink, 1)) == [2]
    # Outside an operation a received part is dropped, as `send_ahead` is.
    @test _receive_sent_ahead!("<p>nowhere</p>") === nothing
    @test length(_sent_ahead_parts(sink, 0)) == 2
end
