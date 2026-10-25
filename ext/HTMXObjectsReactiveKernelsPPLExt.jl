"""
A bound `@rkppl` model in `python_service(T, dir; models = (; name = model))`:
its JAX module (`jax_source`) runs through NumPyro. The module has no
predictive draws, so the model offers `fit` and `log_likelihood` (one summed
value per draw).
"""
module HTMXObjectsReactiveKernelsPPLExt

using HTMXObjects: HTMXObjects, _PyModel, _PyModelVar, _py_nested_schema
using ReactiveKernelsPPL
using Random: Xoshiro, randn

const _Bound = Union{ReactiveKernelsPPL.StructuralPlan,ReactiveKernelsPPL.RKPPLBoundModel}

function HTMXObjects._py_model(binding::_Bound, name; reference_draws=2)
    plan = _rk_plan(binding)
    built = build_kernel(plan)
    text = jax_source(built, plan).text
    layout = built.layout
    dimension = layout.total
    example = constrain(layout, zeros(dimension))
    parameters = [_PyModelVar(String(k), _rk_schema(typeof(v))) for (k, v) in pairs(example)]
    columns = _rk_data_names(text)
    inputs = [_PyModelVar(c, _rk_schema(typeof(plan.columns[Symbol(c)]))) for c in columns]
    likelihoods = [_PyModelVar("log_likelihood", Dict{String,Any}("type" => "number"))]
    reference = reference_draws > 0 && dimension > 0 ?
        _rk_reference(built, plan, columns, reference_draws) : nothing
    _PyModel("jax", ["model.py" => text], inputs, parameters, dimension, _PyModelVar[], likelihoods,
             dimension > 0, reference)
end

_rk_plan(plan::ReactiveKernelsPPL.StructuralPlan) = plan
_rk_plan(binding::ReactiveKernelsPPL.RKPPLBoundModel) = bind_data(binding)

# The raw data `prepare_data` takes: the module's `DATA` names.
function _rk_data_names(text)
    line = something(findfirst(l -> startswith(l, "DATA = "), split(text, '\n')), 0)
    line == 0 && throw(ArgumentError("python_service: the JAX module declares no DATA"))
    [m.captures[1] for m in eachmatch(r"\"([^\"]+)\": \{\"dtype\"", split(text, '\n')[line])]
end

# The JSON schema of a value of type `T`.
_rk_schema(::Type{<:AbstractString}) = Dict{String,Any}("type" => "string")
_rk_schema(::Type{Bool}) = Dict{String,Any}("type" => "boolean")
_rk_schema(::Type{<:Integer}) = Dict{String,Any}("type" => "integer")
_rk_schema(::Type{<:Real}) = Dict{String,Any}("type" => "number")
_rk_schema(::Type{Union{Missing,T}}) where {T} =
    let s = _rk_schema(T); Dict{String,Any}("type" => [s["type"], "null"]) end
_rk_schema(::Type{A}) where {A<:AbstractArray} = _py_nested_schema(_rk_schema(eltype(A)), ndims(A))
_rk_schema(::Type{T}) where {T} = throw(ArgumentError(
    "python_service: no request form for a model value of type $T"))

# Draws and the log likelihoods the Julia model gives at them.
function _rk_reference(built, plan, columns, draws)
    rng = Xoshiro(20261025)
    unconstrained = [0.5 .* randn(rng, built.layout.total) for _ in 1:draws]
    values = Dict{String,Any}("unconstrained" => unconstrained)
    for u in unconstrained, (k, v) in pairs(constrain(built.layout, u))
        push!(get!(Vector{Any}, values, String(k)), _rk_rows(v))
    end
    likelihood = prepare_query(built, plan, :likelihood)
    log_likelihood = Dict{String,Any}("log_likelihood" =>
        [Base.invokelatest(likelihood, u) for u in unconstrained])
    data = Dict{String,Any}(c => _rk_rows(plan.columns[Symbol(c)]) for c in columns)
    (; data, draws=values, log_likelihood)
end

# A value as nested rows (a matrix row by row), as JSON carries it.
_rk_rows(x) = x
_rk_rows(x::Missing) = nothing
_rk_rows(x::AbstractVector) = [_rk_rows(v) for v in x]
_rk_rows(x::AbstractArray) = [_rk_rows(selectdim(x, 1, i)) for i in axes(x, 1)]

end
