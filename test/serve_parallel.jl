using TestItemRunner

@testitem "serve(; parallel) picks the request threadpool and warns only when threads sit unused" tags=[:unit] begin
    pool(parallel, interactive, default, http) =
        HTMXObjects._request_threadpool(parallel, interactive, default, VersionNumber(http))

    # HTTP.jl 2 already runs each connection on `:interactive`: the default uses a
    # sized interactive pool, so it must not warn that the pool is unused.
    @test pool(false, 32, 32, "2.8.0") == (nothing, nothing)
    @test pool(false, 1, 8, "2.8.0") == (nothing, nothing)
    @test pool(false, 0, 8, "2.8.0") == (nothing, nothing)

    # HTTP.jl 1.x serves every connection on one thread.
    p, w = pool(false, 32, 32, "1.11.0")
    @test p === nothing
    @test occursin("leaving 32 interactive threads unused", w)
    @test occursin("parallel=:interactive", w)
    @test pool(false, 1, 8, "1.11.0") == (nothing, nothing)

    @test pool(:interactive, 4, 4, "2.8.0") == (:interactive, nothing)
    @test pool(:interactive, 4, 4, "1.11.0") == (:interactive, nothing)
    p, w = pool(:interactive, 1, 8, "2.8.0")
    @test p === :interactive && occursin("one at a time", w)
    p, w = pool(:interactive, 0, 8, "2.8.0")
    @test p === :interactive && occursin("run on the :default threadpool", w)

    @test pool(true, 4, 8, "2.8.0") == (:default, nothing)
    p, w = pool(true, 4, 1, "2.8.0")
    @test p === :default && occursin("only 1 thread", w)
end
