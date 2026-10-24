# Generate a Python service with one StanBlocks and one ReactiveKernelsPPL
# model into ARGS[1]: run by test/python_models.jl in a project that develops
# HTMXObjects beside both packages (`HTMXO_TEST_MODELS`).
using HTMXObjects, StanBlocks, ReactiveKernelsPPL

println("HTMXObjects at ", pkgdir(HTMXObjects))

@htmx struct ExtApi
    "A ping."
    @get ping()::JSONResponse{@NamedTuple{ok::Bool}} = (; ok=true)
end

# Grouped and ragged data, a vector parameter, two observations.
stan = @slic (; x = [1.0, 2.0, 3.0, 4.0], y = [0.2, -0.1, 0.3, 0.4], g = [1, 2, 1, 2],
               yr = [[0.1, 0.2], [0.3]]) begin
    sigma ~ exponential(1.)
    beta ~ normal(0., 10.)
    a::vector[2] ~ normal(0., 1.)
    y ~ normal(beta * x + a[g], sigma)
    yr ~ normal(beta, sigma)
end

# String levels and a level array.
x = [1.0, 2.0, 3.0, 4.0]; y = [0.2, -0.1, 0.3, 0.4]; g = ["a", "b", "a", "b"]
rk = @rkppl begin
    a ~ Normal(0, 5)
    b ~ Normal(0, 2)
    sigma ~ Exponential(1.0)
    c[levels(g)] .~ Normal.(0, 1)
    mu = a .+ b .* x .+ c[g]
    y .~ Normal.(mu, sigma)
end

python_service(ExtApi, ARGS[1]; package="ext_service", copyright="2026 Test Holder",
               models=(; stan, rk=rk(; x, g) | (; y)))
