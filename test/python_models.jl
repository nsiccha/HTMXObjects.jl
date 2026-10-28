using TestItemRunner

# `python_service(T, dir; models = (; name = model))`: typed endpoints for a
# model's own operations and a Python runtime (todo `1h9vesj`, user decision
# `17jp1li`). The fixtures are a hand-written Stan program and JAX module, so
# the generated runtime is checked against log likelihoods computed here from
# the normal density, independently of StanBlocks and ReactiveKernelsPPL.
@testmodule PythonModelFixtures begin
    using HTMXObjects
    import HTMXObjects: _PyModel, _PyModelVar
    export demo_models, normal_logpdf, STAN_PREDICT_CHECK

    normal_logpdf(v, m, s) = -0.5 * log(2pi) - log(s) - 0.5 * ((v - m) / s)^2

    const STAN = """
        data {
          int y_n;
          vector[y_n] y;
          int x_n;
          vector[x_n] x;
          int z_mem_n;
          int z_ends_n;
          tuple(vector[z_mem_n], array[z_ends_n] int) z;
        }
        parameters {
          real alpha;
          real<lower=0> sigma;
        }
        transformed parameters {
          vector[x_n] mu = alpha * x;
        }
        model {
          alpha ~ normal(0, 1);
          sigma ~ exponential(1);
          y ~ normal(alpha * x, sigma);
          for (g in 1:z_ends_n) {
            int s = g == 1 ? 1 : z.2[g - 1] + 1;
            z.1[s:z.2[g]] ~ normal(alpha, sigma);
          }
        }
        generated quantities {
          vector[y_n] y_gen;
          vector[y_n] y_likelihood;
          vector[z_ends_n] z_likelihood;
          vector[x_n] y_mean = mu;
          matrix[2, 3] grid;
          for (i in 1:2) {
            for (j in 1:3) {
              grid[i, j] = 10 * i + j;
            }
          }
          for (i in 1:y_n) {
            y_gen[i] = normal_rng(alpha * x[i], sigma);
            y_likelihood[i] = normal_lpdf(y[i] | alpha * x[i], sigma);
          }
          for (g in 1:z_ends_n) {
            int s = g == 1 ? 1 : z.2[g - 1] + 1;
            z_likelihood[g] = normal_lpdf(z.1[s:z.2[g]] | alpha, sigma);
          }
        }
        """

    size_of(name, of, component=String[]) = Dict{String,Any}("name" => name, "supplied" => false,
        "encoding" => "value", "fields" => [],
        "computed" => Dict{String,Any}("rule" => "size", "of" => of, "component" => component, "axis" => 1))
    value(name) = Dict{String,Any}("name" => name, "supplied" => true, "encoding" => "value", "fields" => [])
    output(name, generative) = Dict{String,Any}("name" => name, "generative" => generative)
    const INTERFACE = Dict{String,Any}(
        "data" => [size_of("y_n", "y"), value("y"), size_of("x_n", "x"), value("x"),
            size_of("z_mem_n", "z", ["mem"]), size_of("z_ends_n", "z", ["ends"]),
            Dict{String,Any}("name" => "z", "supplied" => true, "encoding" => "ragged",
                "ragged" => Dict{String,Any}("element" => "real", "values" => "1", "ends" => "2"),
                "fields" => [merge(value("mem"), Dict{String,Any}("key" => "1")),
                             merge(value("ends"), Dict{String,Any}("key" => "2"))])],
        "parameters" => ["alpha", "sigma"],
        "outputs" => [output("alpha", "posterior"), output("sigma", "posterior"),
            output("y_gen", "draw"), output("y_mean", "draw"), output("grid", "draw"),
            output("y_likelihood", "pointwise_loglik"),
            output("z_likelihood", "pointwise_loglik")])

    const JAX = """
        import jax
        import jax.numpy as jnp
        import numpy as np

        jax.config.update("jax_enable_x64", True)

        DIMENSION = 2
        PARAMETERS = {"alpha": {"start": 0, "stop": 1, "transform": "identity", "dims": ()}, "sigma": {"start": 1, "stop": 2, "transform": "exp", "dims": ()}}
        DATA = {"x": {"dtype": "float64", "ndim": 1, "ragged": False}, "y": {"dtype": "float64", "ndim": 1, "ragged": False}}


        def prepare_data(x, y):
            return {"x": np.asarray(x, dtype=np.float64), "y": np.asarray(y, dtype=np.float64)}


        def log_likelihood(unconstrained, x, y):
            alpha = unconstrained[0]
            sigma = jnp.exp(unconstrained[1])
            z = (y - alpha * x) / sigma
            return jnp.sum(-0.5 * jnp.log(2 * jnp.pi) - jnp.log(sigma) - 0.5 * z ** 2)


        def log_density(unconstrained, x, y):
            prior = -0.5 * unconstrained[0] ** 2 - jnp.exp(unconstrained[1]) + unconstrained[1]
            return prior + log_likelihood(unconstrained, x, y)


        def constrain(unconstrained, x, y):
            return {"alpha": unconstrained[0], "sigma": jnp.exp(unconstrained[1])}
        """

    # `predict` evaluates the program on the request's data: a transformed
    # parameter for other rows than the references' (four, not three), and a
    # matrix row by row.
    const STAN_PREDICT_CHECK = """
        from ps_service.runtime import load_models

        model = load_models().stanm
        data = {"x": [1.0, 2.0, 3.0, 4.0], "y": [0.0, 0.0, 0.0, 0.0], "z": [[0.1], [0.2, 0.3]]}
        draws = {"alpha": [0.5, -0.3], "sigma": [1.2, 0.8]}
        found = model.predict(data, draws, seed=1)
        assert found["y_mean"] == [[a * x for x in data["x"]] for a in draws["alpha"]], found["y_mean"]
        assert found["grid"] == 2 * [[[11.0, 12.0, 13.0], [21.0, 22.0, 23.0]]], found["grid"]
        assert [len(g) for g in found["y_gen"]] == [4, 4], found["y_gen"]
        likelihood = model.log_likelihood(data, draws)
        assert [len(v) for v in likelihood["y_likelihood"]] == [4, 4], likelihood
        print("checked")
        """

    number = Dict{String,Any}("type" => "number")
    numbers = Dict{String,Any}("type" => "array", "items" => number)

    function demo_models()
        x, y, z = [1.0, 2.0, 3.0], [0.4, 1.1, 1.3], [[0.1, -0.2], [0.3]]
        alpha, sigma = [0.5, -0.3], [1.2, 0.8]
        stan = _PyModel("stan", ["model.stan" => STAN, "interface.json" => HTMXObjects._schema_json_encode(INTERFACE)],
            [_PyModelVar("x", numbers), _PyModelVar("y", numbers),
             _PyModelVar("z", Dict{String,Any}("type" => "array", "items" => numbers))],
            [_PyModelVar("alpha", number), _PyModelVar("sigma", number)], 0,
            [_PyModelVar("y_gen", numbers), _PyModelVar("y_mean", numbers),
             _PyModelVar("grid", Dict{String,Any}("type" => "array", "items" => numbers))],
            [_PyModelVar("y_likelihood", numbers), _PyModelVar("z_likelihood", numbers)], true,
            (; data=Dict{String,Any}("x" => x, "y" => y, "z" => z),
               draws=Dict{String,Any}("alpha" => alpha, "sigma" => sigma),
               log_likelihood=Dict{String,Any}(
                   "y_likelihood" => [normal_logpdf.(y, a .* x, s) for (a, s) in zip(alpha, sigma)],
                   "z_likelihood" => [[sum(normal_logpdf.(g, a, s)) for g in z] for (a, s) in zip(alpha, sigma)])))
        u = [[0.5, 0.1], [-0.3, -0.2]]
        jax = _PyModel("jax", ["model.py" => JAX], [_PyModelVar("x", numbers), _PyModelVar("y", numbers)],
            [_PyModelVar("alpha", number), _PyModelVar("sigma", number)], 2, _PyModelVar[],
            [_PyModelVar("log_likelihood", number)], true,
            (; data=Dict{String,Any}("x" => x, "y" => y),
               draws=Dict{String,Any}("alpha" => first.(u), "sigma" => exp.(last.(u)), "unconstrained" => u),
               log_likelihood=Dict{String,Any}("log_likelihood" =>
                   [sum(normal_logpdf.(y, v[1] .* x, exp(v[2]))) for v in u])))
        (; stanm=stan, jaxm=jax)
    end
end

@testitem "python_service gives each model typed endpoints and a runtime" setup=[PythonServiceFixtures, PythonModelFixtures] tags=[:unit] begin
    using HTMXObjects
    dir = mktempdir()
    written = generate_service(dir; models=demo_models())
    relative = Set(relpath(p, dir) for p in written)
    for f in ("ps_service/runtime/__init__.py", "ps_service/runtime/__main__.py",
              "ps_service/runtime/stan_model.py", "ps_service/runtime/jax_model.py",
              "ps_service/runtime/stanm/__init__.py", "ps_service/runtime/stanm/model.stan",
              "ps_service/runtime/stanm/interface.json", "ps_service/runtime/jaxm/__init__.py",
              "ps_service/runtime/jaxm/model.py", "tests/test_models.py",
              "tests/references/stanm.json", "tests/references/jaxm.json", "setup.cfg")
        @test joinpath(split(f, '/')...) in relative
    end

    # The model operations are operations of the shipped document.
    specs = [String(k) => v for (k, v) in pairs(demo_models())]
    doc = HTMXObjects._py_model_document(openapi(PSApp; title="PS service", version="1.2.0"), specs)
    for (path, request, response) in [
            ("/models/stanm/fit", "StanmFitRequest", "StanmDraws"),
            ("/models/stanm/predict", "StanmPredictRequest", "StanmPrediction"),
            ("/models/stanm/log_likelihood", "StanmLogLikelihoodRequest", "StanmLogLikelihood"),
            ("/models/jaxm/fit", "JaxmFitRequest", "JaxmDraws"),
            ("/models/jaxm/log_likelihood", "JaxmLogLikelihoodRequest", "JaxmLogLikelihood")]
        op = doc.paths[path]["post"]
        @test op["requestBody"]["content"]["application/json"]["schema"]["\$ref"] == "#/components/schemas/" * request
        @test op["responses"]["200"]["content"]["application/json"]["schema"]["\$ref"] == "#/components/schemas/" * response
    end
    # A JAX module draws no predictions, so it has no predict endpoint.
    @test !haskey(doc.paths, "/models/jaxm/predict")
    @test !haskey(doc.components.schemas, "JaxmPredictRequest") && !haskey(doc.components.schemas, "JaxmPrediction")
    @test haskey(doc.paths, "/inner/alarms/{kenn}")
    schemas = doc.components.schemas
    @test sort!(collect(keys(schemas["StanmData"]["properties"]))) == ["x", "y", "z"]
    @test schemas["StanmData"]["properties"]["z"]["items"]["type"] == "array"
    @test sort!(collect(keys(schemas["StanmDraws"]["properties"]))) == ["alpha", "sigma"]
    @test sort!(collect(keys(schemas["JaxmDraws"]["properties"]))) == ["alpha", "sigma", "unconstrained"]
    @test schemas["StanmDraws"]["properties"]["sigma"] == Dict("type" => "array", "items" => Dict("type" => "number"))
    @test sort!(collect(keys(schemas["StanmLogLikelihood"]["properties"]))) == ["y_likelihood", "z_likelihood"]
    @test schemas["StanmFitRequest"]["required"] == ["data"]
    @test schemas["StanmFitRequest"]["properties"]["chains"]["default"] == 4

    read_file(f) = read(joinpath(dir, split(f, '/')...), String)
    backend = read_file("ps_service/backend.py")
    @test occursin("def models(self) -> Models:", backend)
    @test occursin("def stanm_fit(self, *, request: StanmFitRequest) -> StanmDraws:", backend)
    @test occursin("return self.models.stanm.fit(", backend)
    @test occursin("return self.models.stanm.predict(", backend)
    @test occursin("return self.models.jaxm.log_likelihood(", backend)
    # The app's own operations still answer 501 until a backend serves them.
    @test occursin("raise unimplemented(\"tree\")", backend)
    app = read_file("ps_service/app.py")
    @test occursin("request: Annotated[StanmFitRequest, Body()]", app)
    runtime = read_file("ps_service/runtime/__init__.py")
    @test occursin("self.stanm = StanModel(HERE / \"stanm\")", runtime)
    @test occursin("self.jaxm = JaxModel(__package__ + \".jaxm.model\")", runtime)
    @test read_file("ps_service/runtime/stanm/model.stan") == PythonModelFixtures.STAN
    pyproject = read_file("pyproject.toml")
    for dependency in ("bridgestan==2.9.0", "nutpie[stan]==0.16.11", "jax>=0.4.30", "numpyro>=0.15", "scipy>=1.11")
        @test occursin("\"$dependency\"", pyproject)
    end
    # Both runtimes need numpy; it is listed once.
    @test count("\"numpy>=1.26\"", pyproject) == 1
    @test occursin("requires-python = \">=3.12\"", pyproject)
    @test occursin("packages = [\"ps_service\", \"ps_service.runtime\", \"ps_service.runtime.jaxm\", \"ps_service.runtime.stanm\"]", pyproject)
    @test occursin("\"ps_service.runtime.stanm\" = [\"model.stan\", \"interface.json\"]", pyproject)
    dockerfile = read_file("Dockerfile")
    @test occursin("ARG BRIDGESTAN_VERSION=2.9.0", dockerfile)
    @test occursin("ENV BRIDGESTAN=/opt/bridgestan/bridgestan-\${BRIDGESTAN_VERSION}", dockerfile)
    @test occursin("releases/download/v\${BRIDGESTAN_VERSION}/bridgestan-\${BRIDGESTAN_VERSION}.tar.gz", dockerfile)
    @test occursin("python -m ps_service.runtime", dockerfile)
    @test occursin("chmod -R a+rX /opt/bridgestan", dockerfile)
    # No CmdStan anywhere (user decisions 1g9p2nw, 0i2b1wr).
    @test !any(p -> occursin("cmdstan", lowercase(read(p, String))), written)
    readme = read_file("README.md")
    @test occursin("| `stanm` | `POST /models/stanm/predict` | BridgeStan, nutpie |", readme)
    @test occursin("| `jaxm` | `POST /models/jaxm/fit` | NumPyro |", readme)
    tests = read_file("tests/test_models.py")
    @test occursin("def test_stanm_log_likelihood():", tests) && occursin("def test_jaxm_fit():", tests)
    @test !occursin("def test_jaxm_predict", tests)

    # Without models nothing of this is written.
    plain = mktempdir()
    @test !any(p -> occursin("runtime", p) || endswith(p, "setup.cfg"), generate_service(plain))
    plain_pyproject = read(joinpath(plain, "pyproject.toml"), String)
    @test !occursin("nutpie", plain_pyproject) && !occursin("bridgestan", plain_pyproject)
    @test occursin("requires-python = \">=3.10\"", plain_pyproject)
    # Without a Stan model, no BridgeStan in the image either.
    @test !occursin("bridgestan", lowercase(read(joinpath(plain, "Dockerfile"), String)))

    # refused: a model name is part of paths and Python names, so it must be a Python identifier (decision 17jp1li)
    @test_throws ArgumentError generate_service(mktempdir(); models=(; var"Bad-Name"=demo_models().stanm))
    @test_throws ArgumentError generate_service(mktempdir(); models=(; var"class"=demo_models().stanm))
    # refused: a model needs a runtime, which only the StanBlocks and ReactiveKernelsPPL extensions provide
    err = try generate_service(mktempdir(); models=(; m=42)); nothing catch e e end
    @test err isa ArgumentError && occursin("StanBlocks", err.msg) && occursin("ReactiveKernelsPPL", err.msg)
    # refused: reference_draws counts draws
    @test_throws ArgumentError generate_service(mktempdir(); models=demo_models(), reference_draws=-1)
end

@testitem "a generated model service passes pycodestyle, its contract and the Julia references" setup=[PythonServiceFixtures, PythonModelFixtures] tags=[:unit] begin
    using HTMXObjects
    python = service_python()
    if python === nothing
        @test_skip "no Python with fastapi, pydantic, pytest, pycodestyle, httpx and python-multipart (set HTMXO_TEST_PYTHON)"
    else
        dir = mktempdir()
        generate_service(dir; models=demo_models())
        style = run_python(python, dir, "-m", "pycodestyle", "ps_service", "tests")
        @test style.ok
        style.ok || println(style.output)
        result = run_python(python, dir, "-m", "pytest", "-q", "-rs", "-p", "no:cacheprovider", "tests")
        @test result.ok
        result.ok || println(result.output)
        # With HTMXO_TEST_PYTHON_MODELS=1 the Python must run the models
        # (nutpie with BridgeStan, JAX with NumPyro): no test may be skipped.
        if get(ENV, "HTMXO_TEST_PYTHON_MODELS", "") == "1"
            @test !occursin("skipped", result.output)
            @test occursin("7 passed", result.output)
        end
        if run_python(python, dir, "-c", "import bridgestan, nutpie").ok
            check = run_python(python, dir, "-c", STAN_PREDICT_CHECK)
            @test check.ok && occursin("checked", check.output)
            check.ok || println(check.output)
        else
            @test get(ENV, "HTMXO_TEST_PYTHON_MODELS", "") != "1"
        end
    end
end

@testitem "the models CI job installs the releases python_service pins" tags=[:unit] begin
    using HTMXObjects
    workflow = read(joinpath(pkgdir(HTMXObjects), ".github", "workflows", "test.yml"), String)
    @test occursin("BRIDGESTAN_VERSION: '$(HTMXObjects._PY_BRIDGESTAN_VERSION)'", workflow)
    @test occursin("NUTPIE_VERSION: '$(HTMXObjects._PY_NUTPIE_VERSION)'", workflow)
    @test occursin("\"bridgestan==\$BRIDGESTAN_VERSION\" \"nutpie[stan]==\$NUTPIE_VERSION\"", workflow)
    @test !occursin("cmdstan", lowercase(workflow))
end

# The extensions on StanBlocks and ReactiveKernelsPPL need those packages,
# which the test environment does not carry: `HTMXO_TEST_MODELS` names a Julia
# project that develops this HTMXObjects checkout beside them, and the script
# generates a service with one model of each there.
@testitem "python_service runs StanBlocks and ReactiveKernelsPPL models" setup=[PythonServiceFixtures] tags=[:integration] begin
    using HTMXObjects
    project = get(ENV, "HTMXO_TEST_MODELS", "")
    if isempty(project)
        @test_skip "HTMXO_TEST_MODELS names no Julia project with StanBlocks and ReactiveKernelsPPL"
    else
        dir = mktempdir()
        script = joinpath(@__DIR__, "support", "python_models_extensions.jl")
        out = IOBuffer()
        ok = success(pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no --project=$project $script $dir`);
                              stdout=out, stderr=out))
        output = String(take!(out))
        @test ok
        ok || println(output)
        # The project loads this checkout, not another one.
        @test occursin("HTMXObjects at " * pkgdir(HTMXObjects), output)
        python = service_python()
        if python !== nothing
            result = run_python(python, dir, "-m", "pytest", "-q", "-rs", "-p", "no:cacheprovider", "tests")
            @test result.ok
            result.ok || println(result.output)
            get(ENV, "HTMXO_TEST_PYTHON_MODELS", "") == "1" && @test !occursin("skipped", result.output)
        end
    end
end
