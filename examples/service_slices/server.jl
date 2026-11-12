# julia --project=. -t2,1 examples/service_slices/server.jl ROLE PORT CONTROL_DIR [WRITER_URL]
# ROLE is whole, writer or reader. Set HTMXO_SERVICE_TOKEN in the environment.
started = time()
include("application.jl")
using .ServiceExample
using HTMXObjects
import JSON

length(ARGS) in (3, 4) || error("expected ROLE PORT CONTROL_DIR [WRITER_URL]")
role = Symbol(ARGS[1])
port = parse(Int, ARGS[2])
control = abspath(ARGS[3])
mkpath(control)
runtime = ServiceExample.runtime(role; writer_url=length(ARGS) == 4 ? ARGS[4] : "",
    token=ENV["HTMXO_SERVICE_TOKEN"], gate_dir=control)
compiled = precompile_routes!(runtime.plan, role)
# Allow first-use compilation on the example's cold peer processes.
mount_service_monitor!(runtime; timeout=30)
server = serve(runtime; port, async=true, parallel=:interactive,
    runtime_tracking=false, access_log=nothing, operation_log=nothing)

function receipt(name, value)
    temporary = joinpath(control, name * ".tmp")
    write(temporary, JSON.json(value))
    mv(temporary, joinpath(control, name); force=true)
end
receipt("ready.json", (; pid=getpid(), generation=runtime.generation,
    startup_seconds=time() - parse(Float64, get(ENV, "HTMXO_SERVICE_LAUNCHED_AT", string(started))),
    startup_origin=haskey(ENV, "HTMXO_SERVICE_LAUNCHED_AT") ? "process-launch" : "script-entry",
    rss_bytes=process_rss_bytes(),
    compile_routes=[string(r.name) for r in compiled]))
try
    while true
        if isfile(joinpath(control, "measure"))
            receipt("memory.json", (; pid=getpid(), rss_bytes=process_rss_bytes()))
            rm(joinpath(control, "measure"))
        end
        if isfile(joinpath(control, "drain"))
            drained = drain_service!(runtime; timeout=0.1)
            receipt("drain.json", (; drained, active=runtime.active))
            drained && break
        end
        sleep(0.02)
    end
finally
    close(server)
end
