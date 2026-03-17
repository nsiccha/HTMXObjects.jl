module HTMXObjectsTests
using Test, Random, HTMXObjects, HTTP, Tables, TestModules
include("HTMXObjectsTests.jl")
end

using TestModules
runtests!(HTMXObjectsTests)
