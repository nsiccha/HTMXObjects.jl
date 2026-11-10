using TestItemRunner

# `names(HTMXObjects)` is the public inventory. An exported name that resolves
# to nothing gives a consumer an `UndefVarError` at the use site and puts an
# entry with no definition into any API reference built from that list. Most
# often it is a re-export that outlived its removal from DynamicObjects: `@memo`
# (renamed `@memo!`) and `cancel!` / `cancel_all!` (removed with the retained
# compute Task) were exported this way until snag htmxo-unbound-pu-caefdfc5.
@testitem "every exported name is bound" tags=[:unit] begin
    unbound = sort!([n for n in names(HTMXObjects) if !isdefined(HTMXObjects, n)])
    @test unbound == Symbol[]
end
