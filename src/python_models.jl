# --- Python service models: endpoints that run an app's emitted model ---
#
# `python_service(T, dir; models = (; name = model, …))` (user decision
# `17jp1li`, every prong its first option) gives each named model typed
# endpoints for its own operations, `POST /models/<name>/{fit,predict,
# log_likelihood}`, added to the shipped document, and a small Python runtime
# (`<package>/runtime/`) that the hand-written backend methods can call as
# `self.models.<name>`. The draws travel in the requests (stateless). A
# model's Stan program runs through BridgeStan and is sampled with nutpie (no
# CmdStan: user decisions `1g9p2nw`, `0i2b1wr`), its JAX module through NumPyro.
# What each model gives (its artifacts, data, parameters and outputs) comes
# from `_py_model`, which the StanBlocks and ReactiveKernelsPPL extensions
# implement; neither package knows HTMXObjects.

# The BridgeStan release (its Python package and the C++ source the Dockerfile
# installs, which must agree) and the nutpie release a Stan program runs with.
# The runtime builds nutpie's model from the compiled library the way
# `nutpie.compile_stan_model` does, so a new nutpie needs its runtime checked.
const _PY_BRIDGESTAN_VERSION = "2.9.0"
const _PY_NUTPIE_VERSION = "0.16.11"

# One named value of a model: a data input, a parameter, an output. `schema`
# is the JSON schema of one value (of one draw's, for parameters and outputs).
struct _PyModelVar
    name::String
    schema::Any
end

"""
    _PyModel

What `python_service` needs of a model, as `_py_model(model, name; reference_draws)`
returns it (the StanBlocks and ReactiveKernelsPPL extensions):

- `kind`: `"stan"` (a Stan program and its `stan_interface`, run through
  BridgeStan and nutpie) or `"jax"` (a `jax_source` module, run through
  NumPyro);
- `files`: the artifacts, written into `<package>/runtime/<name>/`;
- `inputs`: the data a request carries;
- `parameters`: one draw's parameters, and `unconstrained` the length of the
  unconstrained vector a draw also carries (0: none);
- `predictions` / `likelihoods`: one draw's predictive draws and log
  likelihoods (empty: no `predict` / `log_likelihood` operation), and `fit`
  whether the model can be fitted;
- `reference`: `nothing`, or `(; data, draws, log_likelihood)`: draws and the
  log likelihoods the Julia model gives at them, for the generated tests.
"""
struct _PyModel
    kind::String
    files::Vector{Pair{String,String}}
    inputs::Vector{_PyModelVar}
    parameters::Vector{_PyModelVar}
    unconstrained::Int
    predictions::Vector{_PyModelVar}
    likelihoods::Vector{_PyModelVar}
    fit::Bool
    reference::Any
end

_py_model(m::_PyModel, name; reference_draws=0) = m
_py_model(model, name; reference_draws=0) = throw(ArgumentError(
    "python_service: no Python runtime for the model $name, a $(typeof(model)). " *
    "Pass a @slic model (load StanBlocks) or a bound @rkppl model (load ReactiveKernelsPPL)."))

# The operations of a model, in endpoint order.
_py_model_methods(m::_PyModel) = [method for (method, offered) in (
    "fit" => m.fit, "predict" => !isempty(m.predictions),
    "log_likelihood" => !isempty(m.likelihoods)) if offered && !isempty(m.parameters)]

# JSON schema of one value with `depth` array levels of `element`.
_py_nested_schema(element, depth::Integer) =
    depth == 0 ? element : Dict{String,Any}("type" => "array", "items" => _py_nested_schema(element, depth - 1))

# One value per draw.
_py_draws_schema(schema) = Dict{String,Any}("type" => "array", "items" => schema)

_py_object_schema(description, properties; required=collect(keys(properties))) = Dict{String,Any}(
    "type" => "object", "description" => description, "properties" => properties,
    "required" => sort!(String.(required)))

_py_ref(name) = Dict{String,Any}("\$ref" => "#/components/schemas/" * name)

# The components and paths of model `name`'s operations, added to `doc`.
function _py_model_document(doc, models)
    isempty(models) && return doc
    paths = Dict{String,Any}(String(k) => v for (k, v) in pairs(doc.paths))
    schemas = haskey(doc, :components) ?
        Dict{String,Any}(String(k) => v for (k, v) in pairs(doc.components.schemas)) : Dict{String,Any}()
    for (name, m) in models
        cname = _py_capwords(name)
        methods = _py_model_methods(m)
        variables(vars, wrap) = Dict{String,Any}(v.name => wrap(v.schema) for v in vars)
        # The data and draws, which the runtime takes and gives, and the
        # request and response of each operation the model offers.
        add = Dict{String,Any}(
            cname * "Data" => _py_object_schema("The data of the model $name.", variables(m.inputs, identity)),
            cname * "Draws" => let draws = variables(m.parameters, _py_draws_schema)
                m.unconstrained > 0 && (draws["unconstrained"] = _py_draws_schema(
                    _py_nested_schema(Dict{String,Any}("type" => "number"), 1)))
                _py_object_schema("Draws of the parameters of $name: one value per draw" *
                    (m.unconstrained > 0 ? ", and each draw's unconstrained vector." : "."), draws)
            end)
        "fit" in methods && merge!(add, Dict{String,Any}(
            cname * "FitRequest" => _py_object_schema("A fit of $name to `data`.", Dict{String,Any}(
                "data" => _py_ref(cname * "Data"),
                "chains" => Dict{String,Any}("type" => "integer", "default" => 4, "description" => "Chains to run."),
                "samples" => Dict{String,Any}("type" => "integer", "default" => 1000, "description" => "Draws per chain."),
                "warmup" => Dict{String,Any}("type" => "integer", "default" => 1000, "description" => "Warmup iterations per chain."),
                "seed" => Dict{String,Any}("type" => ["integer", "null"],
                                           "description" => "The random seed; none draws one.")); required=["data"])))
        "predict" in methods && merge!(add, Dict{String,Any}(
            cname * "PredictRequest" => _py_object_schema("Predictive draws of $name at `draws`.", Dict{String,Any}(
                "data" => _py_ref(cname * "Data"), "draws" => _py_ref(cname * "Draws"),
                "seed" => Dict{String,Any}("type" => ["integer", "null"],
                                           "description" => "The random seed; none draws one.")); required=["data", "draws"]),
            cname * "Prediction" => _py_object_schema("Predictive draws of $name: one value per draw.",
                variables(m.predictions, _py_draws_schema))))
        "log_likelihood" in methods && merge!(add, Dict{String,Any}(
            cname * "LogLikelihoodRequest" => _py_object_schema("The log likelihood of $name at `draws`.",
                Dict{String,Any}("data" => _py_ref(cname * "Data"), "draws" => _py_ref(cname * "Draws"))),
            cname * "LogLikelihood" => _py_object_schema("Log likelihoods of $name: one value per draw.",
                variables(m.likelihoods, _py_draws_schema))))
        for (key, schema) in add
            haskey(schemas, key) && throw(ArgumentError(
                "python_service: the model $name needs the schema $key, which the app already describes"))
            schemas[key] = schema
        end
        operations = Dict(
            "fit" => ("Fit $name to the data: draws of its parameters (NUTS).", "FitRequest", "Draws"),
            "predict" => ("Predictive draws of $name at the given draws.", "PredictRequest", "Prediction"),
            "log_likelihood" => ("The log likelihood of $name at the given draws.", "LogLikelihoodRequest", "LogLikelihood"))
        for method in methods
            summary, request, response = operations[method]
            path = "/models/" * name * "/" * method
            haskey(paths, path) && throw(ArgumentError(
                "python_service: the model $name needs the path $path, which the app already serves"))
            paths[path] = Dict{String,Any}("post" => Dict{String,Any}(
                "operationId" => name * "_" * method, "summary" => summary,
                "requestBody" => Dict{String,Any}("required" => true, "content" => Dict{String,Any}(
                    "application/json" => Dict{String,Any}("schema" => _py_ref(cname * request)))),
                "responses" => Dict{String,Any}("200" => Dict{String,Any}(
                    "description" => "Successful response", "content" => Dict{String,Any}(
                        "application/json" => Dict{String,Any}("schema" => _py_ref(cname * response)))))))
        end
    end
    merge(doc, (paths=paths, components=(schemas=schemas,)))
end

# The runtime call each model operation's backend method makes.
function _py_model_call(model, method)
    data = "request.data.model_dump(by_alias=True)"
    draws = "request.draws.model_dump(by_alias=True)"
    args = method == "fit" ? Pair{String,Any}["" => data, "chains" => "request.chains",
            "samples" => "request.samples", "warmup" => "request.warmup", "seed" => "request.seed"] :
        method == "predict" ? Pair{String,Any}["" => data, "" => draws, "seed" => "request.seed"] :
        Pair{String,Any}["" => data, "" => draws]
    _PyCall("self.models." * model * "." * method, args)
end

# --- The runtime: <package>/runtime/ ---

function _py_runtime_init(header, package, models, kinds)
    lines = [header; ""; _py_docstring("""
        The models of the service, one attribute of `Models` each.

        `load_models()` returns the one shared instance. `python -m
        $package.runtime` prepares every model ahead of use (compiles each
        Stan program), as the Dockerfile does.""", 0)]
    push!(lines, "", "import functools", "from pathlib import Path", "", "HERE = Path(__file__).parent",
          "", "", "class Models:")
    append!(lines, _py_docstring("The models of the service.", 4))
    push!(lines, "", "    def __init__(self) -> None:")
    # The runtimes' libraries load with the first use of a model, so the
    # rest of the service runs (and its contract test passes) without them.
    "jax" in kinds && push!(lines, "        from .jax_model import JaxModel")
    "stan" in kinds && push!(lines, "        from .stan_model import StanModel")
    for (name, m) in models
        push!(lines, m.kind == "stan" ? "        self.$name = StanModel(HERE / \"$name\")" :
                     "        self.$name = JaxModel(__package__ + \".$name.model\")")
    end
    push!(lines, "", "    def all(self) -> list:")
    append!(lines, _py_docstring("Every model.", 8))
    push!(lines, "        return [" * join(["self." * name for (name, _) in models], ", ") * "]")
    push!(lines, "", "", "@functools.cache", "def load_models() -> Models:")
    append!(lines, _py_docstring("The models of the service, shared by every backend.", 4))
    push!(lines, "    return Models()")
end

_py_runtime_main(header) = [header; ""; _py_docstring("Prepare every model ahead of use.", 0);
    ""; "from . import load_models"; ""; "for model in load_models().all():"; "    model.prepare()"]

const _PY_STAN_RUNTIME = raw"""
\"\"\"Stan programs (StanBlocks' `stan_code` and `stan_interface`), run through
BridgeStan and sampled with nutpie.

A draw is the constrained value of each parameter. `predict` and
`log_likelihood` evaluate the program at each draw with BridgeStan, so its
transformed parameters and generated quantities are computed from the
request's data.
\"\"\"

import json
import secrets
import threading
from pathlib import Path
from typing import Any

import bridgestan
import nutpie
import numpy as np
from nutpie import _lib
from nutpie.compile_stan import CompiledStanModel

# nutpie runs the chains in threads of one process.
MAKE_ARGS = ["STAN_THREADS=true"]


class StanModel:
    \"\"\"A Stan program and its interface, in `directory`.

    The program is compiled at first use (or by `prepare`), next to
    `model.stan`; BridgeStan's make leaves an up-to-date library alone.
    \"\"\"

    def __init__(self, directory: Path) -> None:
        self.directory = Path(directory)
        text = (self.directory / "interface.json").read_text(encoding="utf-8")
        self.interface = json.loads(text)
        self._library: Path | None = None
        self._nutpie_library: Any = None
        self._lock = threading.Lock()

    @property
    def library(self) -> Path:
        \"\"\"The compiled program, a shared library.\"\"\"
        with self._lock:
            if self._library is None:
                self._library = bridgestan.compile_model(
                    self.directory / "model.stan", make_args=MAKE_ARGS
                )
            return self._library

    def prepare(self) -> None:
        \"\"\"Compile the program.\"\"\"
        self.library

    def instance(self, data: dict[str, Any]) -> bridgestan.StanModel:
        \"\"\"The program with `data`, the program's data.\"\"\"
        return bridgestan.StanModel(str(self.library), data, warn=False)

    def sampled(self, data: dict[str, Any]) -> CompiledStanModel:
        \"\"\"The program with `data`, as nutpie samples it.\"\"\"
        library = self.library
        with self._lock:
            # `nutpie.compile_stan_model` would compile the program again
            # in each process; this is the model it makes of the library
            # (nutpie is pinned to the release this follows).
            if self._nutpie_library is None:
                self._nutpie_library = _lib.StanLibrary(str(library))
        stan = self.directory / "model.stan"
        return CompiledStanModel(
            code=stan.read_text(encoding="utf-8"),
            library=self._nutpie_library,
            dims={},
            _coords={},
            model_name="model",
            model=None,
            data=data,
        ).with_data()

    @property
    def parameters(self) -> list[str]:
        \"\"\"The parameters, in the program's order.\"\"\"
        return list(self.interface["parameters"])

    def outputs(self, generative: str) -> list[str]:
        \"\"\"The outputs of one kind (`draw`, `pointwise_loglik`).\"\"\"
        return [
            output["name"]
            for output in self.interface["outputs"]
            if output["generative"] == generative
        ]

    def data(self, columns: dict[str, Any]) -> dict[str, Any]:
        \"\"\"The program's data for `columns`, the model's data by name.\"\"\"
        entries = self.interface["data"]
        encoded = {
            entry["name"]: encode(entry, columns[entry["name"]])
            for entry in entries
            if entry["supplied"]
        }
        for entry in entries:
            if not entry["supplied"]:
                encoded[entry["name"]] = computed(entry, encoded, entries)
        return encoded

    def fit(
        self,
        data: dict[str, Any],
        *,
        chains: int = 4,
        samples: int = 1000,
        warmup: int = 1000,
        seed: int | None = None,
    ) -> dict[str, list]:
        \"\"\"Draws of the parameters given `data` (nutpie's NUTS).\"\"\"
        encoded = self.data(data)
        trace = nutpie.sample(
            self.sampled(encoded),
            draws=samples,
            tune=warmup,
            chains=chains,
            seed=seed,
            save_warmup=False,
            progress_bar=False,
            store_unconstrained=True,
        )
        model = self.instance(encoded)
        unconstrained = np.asarray(trace.sample_stats["unconstrained_draw"])
        columns = model.param_names()
        found: dict[str, list] = {name: [] for name in self.parameters}
        for theta in unconstrained.reshape(-1, model.param_unc_num()):
            values = named(columns, model.param_constrain(theta))
            for name in self.parameters:
                found[name].append(values.get(name, []))
        return found

    def predict(
        self,
        data: dict[str, Any],
        draws: dict[str, list],
        *,
        seed: int | None = None,
    ) -> dict[str, list]:
        \"\"\"Predictive draws at each of `draws`.\"\"\"
        return self.at(data, draws, "draw", seed)

    def log_likelihood(
        self, data: dict[str, Any], draws: dict[str, list]
    ) -> dict[str, list]:
        \"\"\"Pointwise log likelihoods at each of `draws`.\"\"\"
        return self.at(data, draws, "pointwise_loglik", None)

    def at(
        self,
        data: dict[str, Any],
        draws: dict[str, list],
        generative: str,
        seed: int | None,
    ) -> dict[str, list]:
        \"\"\"The `generative` outputs at each draw.\"\"\"
        outputs = self.outputs(generative)
        found: dict[str, list] = {name: [] for name in outputs}
        count = len(draws[self.parameters[0]])
        if count == 0:
            return found
        model = self.instance(self.data(data))
        if seed is None:
            seed = secrets.randbits(31)
        rng = model.new_rng(seed)
        parameters = model.param_names()
        columns = model.param_names(include_tp=True, include_gq=True)
        for k in range(count):
            theta = model.param_unconstrain(
                np.array([at_draw(draws, name, k) for name in parameters])
            )
            values = named(
                columns,
                model.param_constrain(
                    theta, include_tp=True, include_gq=True, rng=rng
                ),
            )
            for name in outputs:
                found[name].append(values.get(name, []))
        return found


def indices(column: str) -> tuple[str, list[int]]:
    \"\"\"The value and the indices (from 1) of a column, `a.2.1`.\"\"\"
    name, *rest = column.split(".")
    if not all(part.isdigit() for part in rest):
        raise ValueError(f"no Python value for the Stan output {column}")
    return name, [int(part) for part in rest]


def named(columns: list[str], flat: Any) -> dict[str, Any]:
    \"\"\"The values of `flat` by name, arrays as nested lists.

    A value of size zero has no columns, so it is missing here.
    \"\"\"
    shapes: dict[str, list[int]] = {}
    cells = []
    for column, value in zip(columns, flat):
        name, place = indices(column)
        shape = shapes.setdefault(name, [0] * len(place))
        shapes[name] = [max(n, i) for n, i in zip(shape, place)]
        cells.append((name, place, float(value)))
    found: dict[str, Any] = {
        name: filled(shape) for name, shape in shapes.items()
    }
    for name, place, value in cells:
        if not place:
            found[name] = value
            continue
        row = found[name]
        for i in place[:-1]:
            row = row[i - 1]
        row[place[-1] - 1] = value
    return found


def filled(shape: list[int]) -> Any:
    \"\"\"Nested lists of `shape`.\"\"\"
    if not shape:
        return None
    return [filled(shape[1:]) for _ in range(shape[0])]


def at_draw(draws: dict[str, list], column: str, k: int) -> float:
    \"\"\"The value of the column `column` in the `k`-th draw.\"\"\"
    name, place = indices(column)
    value = draws[name][k]
    for i in place:
        value = value[i - 1]
    return value


def encode(entry: dict[str, Any], value: Any) -> Any:
    \"\"\"`value` as the program's data reads it.\"\"\"
    encoding = entry["encoding"]
    if encoding == "value":
        return value
    if encoding == "ragged":
        keys = entry["ragged"]
        ends, total = [], 0
        for group in value:
            total += len(group)
            ends.append(total)
        flat = [item for group in value for item in group]
        return {keys["values"]: flat, keys["ends"]: ends}
    if encoding == "tuple":
        return {
            field["key"]: encode(field, value[field["name"]])
            for field in entry["fields"]
        }
    raise ValueError(f"no encoding {encoding!r} for the data {entry['name']}")


def computed(
    entry: dict[str, Any], encoded: dict[str, Any], entries: list
) -> Any:
    \"\"\"A data value the program reads but the request does not carry.\"\"\"
    rule = entry["computed"]
    if rule["rule"] != "size":
        raise ValueError(f"no rule {rule['rule']!r} for {entry['name']}")
    value = encoded[rule["of"]]
    fields = next(e for e in entries if e["name"] == rule["of"])["fields"]
    for component in rule["component"]:
        field = next(f for f in fields if f["name"] == component)
        value = value[field["key"]]
        fields = field["fields"]
    for _ in range(rule["axis"] - 1):
        value = value[0] if len(value) else []
    return len(value)
"""

const _PY_JAX_RUNTIME = raw"""
\"\"\"JAX modules (ReactiveKernelsPPL's `jax_source`), run through NumPyro.

A draw carries the constrained value of each parameter and its
unconstrained vector, which `log_likelihood` reads.
\"\"\"

import importlib
import secrets
from typing import Any

import jax
import jax.numpy as jnp
import numpy as np
from numpyro.infer import MCMC, NUTS


class JaxModel:
    \"\"\"The `jax_source` module `module_name`.\"\"\"

    def __init__(self, module_name: str) -> None:
        self.module_name = module_name
        self._module = None

    @property
    def module(self) -> Any:
        \"\"\"The module, imported at first use.\"\"\"
        if self._module is None:
            self._module = importlib.import_module(self.module_name)
        return self._module

    def prepare(self) -> None:
        \"\"\"Import the module.\"\"\"
        self.module

    @property
    def parameters(self) -> list[str]:
        \"\"\"The parameters, in the module's order.\"\"\"
        return list(self.module.PARAMETERS)

    def data(self, columns: dict[str, Any]) -> dict[str, Any]:
        \"\"\"The module's prepared data for `columns`, the data by name.\"\"\"
        raw = {name: columns[name] for name in self.module.DATA}
        return self.module.prepare_data(**raw)

    def fit(
        self,
        data: dict[str, Any],
        *,
        chains: int = 4,
        samples: int = 1000,
        warmup: int = 1000,
        seed: int | None = None,
    ) -> dict[str, list]:
        \"\"\"Draws of the parameters given `data` (NumPyro's NUTS).\"\"\"
        module = self.module
        prepared = self.data(data)

        def potential(unconstrained: Any) -> Any:
            return -module.log_density(unconstrained, **prepared)

        mcmc = MCMC(
            NUTS(potential_fn=potential),
            num_warmup=warmup,
            num_samples=samples,
            num_chains=chains,
            chain_method="sequential",
            progress_bar=False,
        )
        shape = (chains, module.DIMENSION) if chains > 1 else module.DIMENSION
        if seed is None:
            seed = secrets.randbits(31)
        mcmc.run(jax.random.PRNGKey(seed), init_params=jnp.zeros(shape))
        return self.draws(mcmc.get_samples(), prepared)

    def draws(self, unconstrained: Any, prepared: dict[str, Any]) -> dict:
        \"\"\"The draws of `unconstrained`, one row per draw.\"\"\"
        module = self.module
        values = jax.vmap(lambda u: module.constrain(u, **prepared))(
            jnp.asarray(unconstrained)
        )
        draws = {name: np.asarray(values[name]).tolist() for name in values}
        draws["unconstrained"] = np.asarray(unconstrained).tolist()
        return draws

    def log_likelihood(
        self, data: dict[str, Any], draws: dict[str, list]
    ) -> dict[str, list]:
        \"\"\"The log likelihood at each of `draws`.\"\"\"
        module = self.module
        prepared = self.data(data)
        unconstrained = jnp.asarray(draws["unconstrained"], dtype=jnp.float64)
        if unconstrained.shape[0] == 0:
            return {"log_likelihood": []}
        values = jax.vmap(lambda u: module.log_likelihood(u, **prepared))(
            unconstrained
        )
        return {"log_likelihood": np.asarray(values).tolist()}
"""

_py_runtime_file(header, source) = [header; ""; split(strip(source, '\n'), '\n')]

# --- The generated tests: the runtime against the Julia model ---

function _py_models_test(header, package, models)
    lines = [header; ""; _py_docstring("""
        The model endpoints, against the Julia models they were generated from.

        `references/<name>.json` holds draws and the log likelihoods the Julia
        model gives at them. A model whose runtime is not installed (nutpie
        with BridgeStan, or JAX with NumPyro) is skipped.""", 0)]
    append!(lines, [
        "",
        "import json",
        "import math",
        "from pathlib import Path",
        "",
        "import pytest",
        "from fastapi.testclient import TestClient",
        "",
        "from $package.app import create_app",
        "",
        "REFERENCES = Path(__file__).parent / \"references\"",
        "",
        "",
        "def runtime(kind):",
    ])
    append!(lines, _py_docstring("Skip unless the runtime of `kind` is installed.", 4))
    append!(lines, [
        "    if kind == \"stan\":",
        "        pytest.importorskip(\"bridgestan\")",
        "        pytest.importorskip(\"nutpie\")",
        "    else:",
        "        pytest.importorskip(\"jax\")",
        "        pytest.importorskip(\"numpyro\")",
        "",
        "",
        "def reference(name):",
    ])
    append!(lines, _py_docstring("The reference of the model `name`.", 4))
    append!(lines, [
        "    text = (REFERENCES / f\"{name}.json\").read_text(encoding=\"utf-8\")",
        "    return json.loads(text)",
        "",
        "",
        "def post(path, body):",
    ])
    append!(lines, _py_docstring("The answer of the service to `body` at `path`.", 4))
    append!(lines, [
        "    response = TestClient(create_app()).post(path, json=body)",
        "    assert response.status_code == 200, response.text",
        "    return response.json()",
        "",
        "",
        "def close(actual, expected):",
    ])
    append!(lines, _py_docstring("Whether `actual` equals `expected` to rounding.", 4))
    append!(lines, [
        "    if isinstance(expected, list):",
        "        return len(actual) == len(expected) and all(",
        "            close(a, e) for a, e in zip(actual, expected)",
        "        )",
        "    if isinstance(expected, dict):",
        "        return set(actual) == set(expected) and all(",
        "            close(actual[k], v) for k, v in expected.items()",
        "        )",
        "    return math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9)",
        "",
        "",
        "def count(values):",
    ])
    append!(lines, _py_docstring("The numbers of draws in a dict of draws or outputs.", 4))
    push!(lines, "    return {len(v) for v in values.values()}")
    for (name, m) in models
        m.reference === nothing && continue
        methods = _py_model_methods(m)
        kind = _py_literal(m.kind)
        if "log_likelihood" in methods
            push!(lines, "", "", "def test_$(name)_log_likelihood():")
            append!(lines, _py_docstring("$name gives the Julia model's log likelihoods.", 4))
            append!(lines, [
                "    runtime($kind)",
                "    ref = reference(\"$name\")",
                "    body = {\"data\": ref[\"data\"], \"draws\": ref[\"draws\"]}",
                "    found = post(\"/models/$name/log_likelihood\", body)",
                "    assert close(found, ref[\"log_likelihood\"])",
            ])
        end
        if "predict" in methods
            push!(lines, "", "", "def test_$(name)_predict():")
            append!(lines, _py_docstring("$name draws one prediction per draw.", 4))
            append!(lines, [
                "    runtime($kind)",
                "    ref = reference(\"$name\")",
                "    body = {\"data\": ref[\"data\"], \"draws\": ref[\"draws\"], \"seed\": 1}",
                "    found = post(\"/models/$name/predict\", body)",
                "    assert count(found) == count(ref[\"draws\"])",
            ])
        end
        if "fit" in methods
            push!(lines, "", "", "def test_$(name)_fit():")
            append!(lines, _py_docstring("$name gives draws of every parameter.", 4))
            append!(lines, [
                "    runtime($kind)",
                "    ref = reference(\"$name\")",
                "    body = {\"data\": ref[\"data\"], \"chains\": 1, \"samples\": 10}",
                "    body.update(warmup=10, seed=1)",
                "    found = post(\"/models/$name/fit\", body)",
                "    assert set(found) == set(ref[\"draws\"])",
                "    assert count(found) == {10}",
            ])
        end
    end
    lines
end

# The README section of the models.
function _py_models_readme(package, models)
    isempty(models) && return String[]
    rows = String[]
    for (name, m) in models, method in _py_model_methods(m)
        push!(rows, "| `$name` | `POST /models/$name/$method` | " *
                    (m.kind == "stan" ? "BridgeStan, nutpie" : "NumPyro") * " |")
    end
    [
        "",
        "## Models",
        "",
        "Each model has endpoints of its own, which the generated backend answers by",
        "running the model. The draws travel in the requests: `fit` returns them, and",
        "`predict` and `log_likelihood` take them, so the service stores nothing.",
        "",
        "| Model | Endpoint | Runs through |",
        "|---|---|---|",
        rows...,
        "",
        "Your own backend methods reach the same models as `self.models.<name>`:",
        "`fit(data, chains=…, samples=…, warmup=…, seed=…)`, `predict(data, draws, seed=…)`",
        "and `log_likelihood(data, draws)`, with `data` the model's data by name. A Stan",
        "program is compiled with [BridgeStan](https://roualdes.us/bridgestan/), which",
        "needs a C++ toolchain and `make` and downloads its C++ source to `~/.bridgestan`",
        "unless `BRIDGESTAN` names one; nutpie samples it. `python -m $package.runtime`",
        "compiles every program ahead of use, as the Dockerfile does.",
        "`tests/test_models.py` checks each model against draws and log likelihoods of",
        "the Julia model it was generated from.",
    ]
end
