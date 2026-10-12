using Pkg

include("provision.jl")
Pkg.test(; test_args=ARGS)
