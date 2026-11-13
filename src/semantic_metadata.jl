struct _PropertyDescriptorIndex
    descriptors::Vector{NamedTuple}
    names::Dict{Symbol,NamedTuple}
    verbs::Dict{Tuple{Symbol,DataType},NamedTuple}
end

const _property_descriptors_memo = _WorldMemo{_PropertyDescriptorIndex}()

_shared_property_index(T) = _world_memo!(_property_descriptors_memo, T) do
    descriptors = NamedTuple[_effective_route_descriptor(
        _mark_internal_inputs(descriptor)) for descriptor in
        Base.invokelatest(getproperty(DynamicObjects, :property_descriptors), T)]
    names = Dict{Symbol,NamedTuple}()
    verbs = Dict{Tuple{Symbol,DataType},NamedTuple}()
    for descriptor in descriptors
        get!(names, descriptor.name, descriptor)
        for input in get(descriptor, :inputs, ())
            type = get(input, :type, nothing)
            input.name === :__verb__ && type isa DataType &&
                get!(verbs, (descriptor.name, type), descriptor)
        end
    end
    _PropertyDescriptorIndex(descriptors, names, verbs)
end

_shared_property_descriptors(T) = _shared_property_index(T).descriptors

# First-declaration-wins, like DO's `property_descriptor(T, name)`: that method
# describes `metafirst(T, name)`, the first `meta(T)` entry of that name, and
# `property_descriptors(T)` is `meta(T)` in declaration order.
function _property_descriptor(T, name::Symbol)
    isdefined(DynamicObjects, :property_descriptors) || return nothing
    get(_shared_property_index(T).names, name, nothing)
end

# A fresh outer vector per call: the result escapes into consumer-facing
# graphs (`semantic_descriptor`), and must not alias the memo.
function _property_descriptors(T)
    isdefined(DynamicObjects, :property_descriptors) || return NamedTuple[]
    copy(_shared_property_descriptors(T))
end

# Descriptor for one EXACT declaration. The `(T, name)` method resolves through
# `metafirst` (first-declaration-wins), which collapses a name carrying several
# declarations — `@get index`, `@post index` and `@include index(x)` can all
# coexist under one key. Callers already holding the `info` that
# `_walk_route_meta` handed them pass it here so they descriptor-ize the
# declaration they actually walked.
function _property_descriptor(T, name::Symbol, info::NamedTuple)
    isdefined(DynamicObjects, :property_descriptor) || return nothing
    _effective_route_descriptor(_mark_internal_inputs(Base.invokelatest(
        getproperty(DynamicObjects, :property_descriptor), T, name, info)))
end

function _property_descriptor(T, name::Symbol, verb::Symbol)
    isdefined(DynamicObjects, :property_descriptors) || return nothing
    index = _shared_property_index(T)
    # Match the injected arg's exact TYPE, not just internal_input: every
    # verb carries an injected arg. Missing verbs keep first-declaration wins.
    get(index.verbs, (name, Verb{verb})) do
        get(index.names, name, nothing)
    end
end

# The compiler's read of the same descriptor. `semantic_app` resolves every
# operation of every rendered mount against its type's descriptor, so a table
# of N same-type rows with M operations each would otherwise rebuild the
# identical reflection N×(M+1) times — milliseconds each, dominating the render.
# Shared and world-keyed like `_shared_property_descriptors`; the public
# `semantic_descriptor` keeps returning a freshly built, caller-owned value.
struct _SemanticDescriptorIndex
    descriptor::NamedTuple
    operations::Dict{Tuple{Any,Symbol,Symbol},Vector{NamedTuple}}
end

const _semantic_descriptor_memo = _WorldMemo{_SemanticDescriptorIndex}()

_shared_semantic_index(T::Type) = _world_memo!(_semantic_descriptor_memo, T) do
    descriptor = _build_semantic_descriptor(T)
    operations = Dict{Tuple{Any,Symbol,Symbol},Vector{NamedTuple}}()
    for route in descriptor.routes
        candidates = get!(() -> NamedTuple[], operations, (route.owner, route.name, route.verb))
        push!(candidates, route)
    end
    _SemanticDescriptorIndex(descriptor, operations)
end

_shared_semantic_descriptor(T::Type) = _shared_semantic_index(T).descriptor
