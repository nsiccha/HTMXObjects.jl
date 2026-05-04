using Revise
using HTMXObjectsWeb

begin
    HTMXObjectsWeb.terminate()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8101
    HTMXObjectsWeb.serve(; host="0.0.0.0", revise=:lazy, port, async=true)
end
