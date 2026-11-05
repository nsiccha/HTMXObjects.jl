# A real package, because DynamicObjects' worker loads the package that defines
# the root object's type: an `@htmx` struct in a test module cannot be sent to
# a worker. Every value names the process that computed it.
module WorkerApp

using HTMXObjects
import HTMXObjects: h

@htmx struct App
    "Heavy read, computed where the job queue places it"
    @queued @get heavy(; n::Int=1) = h.p("heavy pid=$(getpid()) n=$(n)"; id="heavy")
    "Heavy read that sends a part ahead, then waits for a gate file before it finishes"
    @queued @get ahead(; gate::String="") = begin
        send_ahead(h.p("ahead-part pid=$(getpid())"; id="part"))
        while !isempty(gate) && !isfile(gate)
            sleep(0.05)
        end
        h.p("ahead-done pid=$(getpid())"; id="done")
    end
    "Light read, always here"
    @get light() = h.p("light pid=$(getpid())"; id="light")
end

end
