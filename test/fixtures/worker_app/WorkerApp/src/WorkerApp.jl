# A real package, because DynamicObjects' worker loads the package that defines
# the root object's type: an `@htmx` struct in a test module cannot be sent to
# a worker. Every value names the process that computed it.
module WorkerApp

using HTMXObjects
import HTMXObjects: h

@htmx struct ParamChild
    @param (; dataset, data_version, tags, level, optional) = __parent__
    @param child::Int = 3
    @queued @get results(; method::String="pathfinder") =
        h.p("pid=$(getpid()) dataset=$dataset version=$data_version tags=$(join(tags, ',')) child=$child method=$method level=$level optional=$optional")
    @queued @post results(; method::String="pathfinder") =
        h.p("pid=$(getpid()) dataset=$dataset version=$data_version tags=$(join(tags, ',')) child=$child method=$method")
end

@htmx struct UploadApp
    @param file::Upload
    @queued @post received() =
        h.p("pid=$(getpid()) name=$(file.filename) data=$(String(copy(file.data)))")
end

@htmx struct ParamApp
    @param dataset::String = "default"
    @param data_version::Int = 0
    @param tags::Vector{String} = ["default"]
    @param level::Int = 1
    @options(level) = [1, 2]
    @param enabled::Bool = false
    @param optional::Int = 4
    @relevant(optional) = enabled
    @include fit = ParamChild()
    @include nested = begin
        @include deeper = begin
            @queued @get results() =
                h.p("pid=$(getpid()) dataset=$dataset version=$data_version tags=$(join(tags, ','))")
        end
    end
end

# What a body sees of the answer it serves: the page's language and the
# reader's audience, which a worker must bind as the requesting process has them.
seen() = "lang=$(something(HTMXObjects.page_lang(), "none")) audience=$(HTMXObjects._AUDIENCE[])"

@htmx struct App
    __lang__ = "de"
    "Heavy read, computed where the job queue places it"
    @queued @get heavy(; n::Int=1) = h.p("heavy pid=$(getpid()) n=$(n) $(seen())"; id="heavy")
    "Heavy read that sends a part ahead, then waits for a gate file before it finishes"
    @queued @get ahead(; gate::String="") = begin
        send_ahead(h.p("ahead-part pid=$(getpid())"; id="part"))
        while !isempty(gate) && !isfile(gate)
            sleep(0.05)
        end
        h.p("ahead-done pid=$(getpid())"; id="done")
    end
    "Light read, always here"
    @get light() = h.p("light pid=$(getpid()) $(seen())"; id="light")
end

# Types of the app's own that a parameter fault holds, in `allowed` and in `type`.
@enum Colour red green
struct Millis
    value::Int
end
Base.parse(::Type{Millis}, text::AbstractString) = Millis(parse(Int, text))

# Refusals raised inside a computation, which runs in the worker with `workers=1`.
@htmx struct FaultApp
    @param fit::String = "good"
    @options(fit) = ["good", "better"]
    @param n::Int = 1
    @param must::Int
    @param colour::Colour = red
    @param wait::Millis = Millis(1)
    scenario = n == 0 ? throw(CallerFault(400, "new subjects need at least 1 subject, got 0")) : n
    "A fresh route whose non-route property raises the fault"
    @queued @fresh @get timecourse() = h.p("timecourse pid=$(getpid()) scenario=$scenario")
    "A fresh route reading a parameter outside its options"
    @queued @fresh @get options() = h.p("options pid=$(getpid()) fit=$fit")
    "A memoized route raising the fault in its own body"
    @queued @get memoized(; k::Int=1) = k == 0 ? throw(CallerFault(404, "unknown k 0")) : h.p("memoized pid=$(getpid()) k=$k")
    "A required parameter that is missing"
    @queued @fresh @get required() = h.p("required $must")
    "A value the declared type rejects, and a value outside the app's own Enum and parsed type"
    @queued @fresh @get typed() = h.p("typed pid=$(getpid()) n=$n colour=$colour wait=$(wait.value)")
    "An unmarked route reading a @queued property that raises the fault"
    @queued heavy_probe(k::Int) = k == 0 ? throw(CallerFault(409, "probe 0 is refused")) : (; pid=getpid(), k)
    @fresh @get probe(; k::Int=1) = h.p("probe $(heavy_probe(k))")
    "A server fault"
    @queued @fresh @get boom() = error("server fault in the body")
end

# An `__error__` hook reads the fault through `unwrap_error`, as the docs say.
@htmx struct FaultHookApp
    __error__(err) = begin
        fault = unwrap_error(err)
        fault isa CallerFault ? h.p("hook saw CallerFault status=$(fault.status) message=$(fault.message)") :
            h.p("hook saw $(typeof(fault))")
    end
    @queued @fresh @get hooked() = throw(CallerFault(422, "hooked fault"))
end

end
