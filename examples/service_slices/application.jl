module ServiceExample

using HTMXObjects
import JSON
import Random
import HTTP

"An ordered stream owned by exactly one process."
mutable struct OrderedStream
    lock::ReentrantLock
    values::Vector{Float64}
end
OrderedStream() = OrderedStream(ReentrantLock(), Float64[])

@htmx struct Application
    own_stream::Bool
    gate_dir::String
    @state stream = own_stream ? OrderedStream() : nothing
    @state identity = Random.randstring(24)
    cached_identity = Random.randstring(24)
    @param scale::Float64 = 2.0
    calibration(value::Float64) = value * 1.5

    @fresh @get status() = JSONResponse((; pid=getpid(), identity, cached_identity))
    @fresh @get overlap(; x::Float64=2) = JSONResponse((; value=calibration(x)))
    @post append(; sequence::Int, value::Float64) = lock(stream.lock) do
        sequence == length(stream.values) + 1 ||
            throw(CallerFault(409, "Expected sequence $(length(stream.values) + 1)"))
        push!(stream.values, value)
        JSONResponse((; sequence, value))
    end
    @fresh @get assess() = lock(stream.lock) do
        JSONResponse((; sequence=length(stream.values), total=sum(stream.values)))
    end
    @fresh @get forecast() = begin
        response = dispatch(:GET, "/assess"; headers=["Accept" => "application/json"])
        response.status == 200 || return response
        assessment = JSON.parse(String(response.body))
        JSONResponse((; sequence=assessment["sequence"],
                        forecast=calibration(Float64(assessment["total"])) * scale,
                        actor=HTTP.header(__req__, "X-Actor", "")))
    end
    @fresh @get held() = begin
        isempty(gate_dir) && error("held route needs gate_dir")
        write(joinpath(gate_dir, "entered"), string(getpid()))
        timedwait(() -> isfile(joinpath(gate_dir, "release")), 30; pollint=0.02) === :ok ||
            error("gate was not released")
        JSONResponse((; pid=getpid(), identity))
    end
    @post compile_only(; value::Int) = error("compile-only body must never execute")
    @get omitted() = "not extracted"
end

function plan(; colocated=false)
    slices = if colocated
        [ServiceSlice(:whole; routes=[:status, :overlap, :append, :forecast, :held],
            internal=[:assess], compile=[:forecast, :assess, :compile_only], owns=[:stream])]
    else
        [ServiceSlice(:writer; routes=[:status, :overlap, :append], internal=[:assess],
             owns=[:stream]),
         ServiceSlice(:reader; routes=[:status, :overlap, :forecast, :held],
             forwards=[:assess => :writer], compile=[:forecast, :assess, :compile_only])]
    end
    service_plan(Application, slices; resources=[:stream => [:append, :assess]])
end

function runtime(name; writer_url="", token, gate_dir="")
    selected = plan(; colocated=name === :whole)
    app = Application(service_owns(selected, name, :stream), gate_dir)
    provider = RootProvider(; scope=:job, key=req -> "example",
                            retention=RootRetention(; max_entries=1))
    policy = next -> req -> begin
        HTTP.header(req, "X-Actor", "") == "demo" || return HTTP.Response(401)
        next(req)
    end
    ServiceRuntime(selected, name, app;
        endpoints=isempty(writer_url) ? Dict() : Dict(:writer => writer_url), token,
        contract="ordered-stream/v1", root_provider=provider, middleware=[policy],
        identity_headers=["X-Actor", "X-Request-ID"], request_timeout=300)
end

end
