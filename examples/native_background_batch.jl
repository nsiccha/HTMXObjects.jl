# Derive one immutable request's result through the native operation queue.
# The callback supplies synthetic latency; it is not a scheduler.
module NativeBackgroundBatch

using HTMXObjects, DynamicObjects, HTTP

@htmx struct App
    directory::String
    before_compute::Function

    batch_result(batch_id::Int) = begin
        before_compute(batch_id)
        count = parse(Int, read(joinpath(directory, "request-$batch_id.txt"), String))
        computed = sum(abs2, 1:count)
        write(joinpath(directory, "result-$batch_id.txt"), string(computed))
        computed
    end

    "Read a batch result"
    @get result(batch_id::Int) = h.p("batch:$batch_id result:", batch_result(batch_id))

    # POST accepts/identifies the request; the result GET owns background work.
    # `@direct`: its answer IS the dispatched GET's response (headers included),
    # so it never waits behind a poller of its own.
    @direct @post submit(batch_id::Int) = dispatch(:GET,
        query_url("/result/$batch_id", __self__);
        headers=["HX-Request" => "true",
                 "X-Forwarded-Prefix" => HTTP.header(__req__, "X-Forwarded-Prefix", "")],
        parent=dispatch_parent(__req__))

    @fresh @direct @get jobs() = jobs_board(; all=true)
end

function mount(directory; before_compute=batch_id -> sleep(2), prefix="")
    root = App(directory, before_compute; __prefix__=prefix)
    # Required path inputs need a concrete value when compiling their forms.
    # This also activates retention before an unattended startup dispatch.
    surface = semantic_app(root; values=(; batch_id=1))
    route!(root)
    surface
end

end # module NativeBackgroundBatch
