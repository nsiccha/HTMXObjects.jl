"""
A StanBlocks model in `python_service(T, dir; models = (; name = model))`: its
Stan program (`stan_code`) and interface (`stan_interface`) run through
BridgeStan and nutpie, with the operations `stan_descriptor` offers (`:fit`,
`:predict`, `:pointwise_loglik` as `log_likelihood`).
"""
module HTMXObjectsStanBlocksExt

using HTMXObjects: HTMXObjects, _PyModel, _PyModelVar, _py_nested_schema, _schema_json_encode
using StanBlocks
using StanBlocks: BridgeStan, JSON
using Random: Xoshiro, randn

HTMXObjects._py_model(m::Union{StanBlocks.SlicModel,StanBlocks.StanModel}, name; reference_draws=2) =
    HTMXObjects._py_model(stan_descriptor(m; name=Symbol(name)), name; reference_draws)

function HTMXObjects._py_model(d::StanBlocks.ModelDescriptor, name; reference_draws=2)
    # The interface as plain JSON data (string keys, vectors).
    interface = JSON.parse(_schema_json_encode(stan_interface(d)))
    offered = Set(op.name for op in d.operations)
    outputs = Dict(o["name"] => o for o in interface["outputs"])
    inputs = [_PyModelVar(e["name"], _sb_input_schema(e)) for e in interface["data"] if e["supplied"]]
    parameters = [_sb_output(outputs[p]) for p in interface["parameters"]]
    kind(generative, operation) = operation in offered ?
        [_sb_output(o) for o in interface["outputs"] if o["generative"] == generative] : _PyModelVar[]
    likelihoods = kind("pointwise_loglik", :pointwise_loglik)
    reference = reference_draws > 0 && !isempty(parameters) && !isempty(likelihoods) ?
        _sb_reference(d, interface, likelihoods, reference_draws) : nothing
    _PyModel("stan", ["model.stan" => stan_code(d.model), "interface.json" => _schema_json_encode(interface)],
             inputs, parameters, 0, kind("draw", :predict), likelihoods, :fit in offered, reference)
end

# The JSON schema of one data value, by how the program reads it.
_sb_input_schema(entry) = _sb_input_schema(Val(Symbol(entry["encoding"])), entry)
_sb_input_schema(::Val{:value}, entry) = _py_nested_schema(_sb_element(entry["type"]), _sb_depth(entry))
_sb_input_schema(::Val{:ragged}, entry) = _py_nested_schema(_sb_element(entry["ragged"]["element"]), 2)
_sb_input_schema(::Val{:tuple}, entry) = Dict{String,Any}("type" => "object",
    "properties" => Dict{String,Any}(f["name"] => _sb_input_schema(f) for f in entry["fields"]),
    "required" => sort!([f["name"] for f in entry["fields"]]))
_sb_input_schema(::Val{E}, entry) where {E} = throw(ArgumentError(
    "python_service: no request form for the data $(entry["name"]), encoded as $E"))

_sb_element(type) = Dict{String,Any}("type" => type == "int" ? "integer" : "number")

# A square matrix type declared by one size has two matrix axes.
const _SB_SQUARE = ("cov_matrix", "corr_matrix", "cholesky_factor_corr", "cholesky_factor_cov")
_sb_depth(entry) = length(entry["size"]) + (entry["type"] in _SB_SQUARE ? 1 : 0)

function _sb_output(o)
    isempty(o["fields"]) || throw(ArgumentError(
        "python_service: the model output $(o["name"]) is a tuple, which has no Python runtime yet"))
    _PyModelVar(o["name"], _py_nested_schema(_sb_element(o["type"]), length(o["dims"])))
end

# Draws and the pointwise log likelihoods the compiled Julia model gives at
# them, with the request data that reproduces the model's own.
function _sb_reference(d, interface, likelihoods, draws)
    problem = stan_execute(d, :instantiate)
    model = problem.model
    dimension = BridgeStan.param_unc_num(model)
    rng = Xoshiro(20261025)
    unconstrained = [0.5 .* randn(rng, dimension) for _ in 1:draws]
    outputs = Dict(o["name"] => o for o in interface["outputs"])
    values = Dict{String,Any}(p => Any[] for p in interface["parameters"])
    for u in unconstrained
        flat = BridgeStan.param_constrain(model, u)
        offset = 0
        for p in interface["parameters"]
            dims = Int.(outputs[p]["dims"])
            n = prod(dims; init=1)
            push!(values[p], _sb_nested(flat[offset+1:offset+n], dims))
            offset += n
        end
    end
    found = stan_execute(d, :pointwise_loglik; problem, draws=reduce(hcat, unconstrained), seed=1)
    log_likelihood = Dict{String,Any}()
    for v in likelihoods
        all_draws = getproperty(found, Symbol(v.name))
        dims = Int.(outputs[v.name]["dims"])
        log_likelihood[v.name] = [_sb_nested(all_draws isa AbstractMatrix ? all_draws[:, k] : all_draws, dims)
                                  for k in 1:draws]
    end
    encoded = JSON.parse(stan_data_json(d.model))
    data = Dict{String,Any}(e["name"] => _sb_raw(e, encoded[e["name"]]) for e in interface["data"] if e["supplied"])
    (; data, draws=values, log_likelihood)
end

# A column-major flat value of shape `dims` as nested rows.
_sb_nested(flat, dims) = isempty(dims) ? only(flat) : _sb_rows(reshape(collect(flat), dims...))
_sb_rows(A::AbstractArray) = ndims(A) == 0 ? A[] : [_sb_rows(selectdim(A, 1, i)) for i in axes(A, 1)]

# The request value of data the program reads in the encoded form.
_sb_raw(entry, value) = _sb_raw(Val(Symbol(entry["encoding"])), entry, value)
_sb_raw(::Val{:value}, entry, value) = value
function _sb_raw(::Val{:ragged}, entry, value)
    flat, ends = value[entry["ragged"]["values"]], value[entry["ragged"]["ends"]]
    [flat[(g == 1 ? 1 : ends[g-1] + 1):ends[g]] for g in eachindex(ends)]
end
_sb_raw(::Val{:tuple}, entry, value) =
    Dict{String,Any}(f["name"] => _sb_raw(f, value[f["key"]]) for f in entry["fields"])

end
