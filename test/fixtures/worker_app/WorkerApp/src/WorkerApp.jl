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

end
