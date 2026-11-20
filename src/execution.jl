"""
    ResourceEnvelope(; input_bytes, input_lines, syntax_nodes, wall_seconds,
                       memory_bytes, tasks, stdout_bytes=65536, stderr_bytes=65536)

Limits for one operation. An omitted input or host limit is unrestricted.
Diagnostics always have byte limits. An executor must explicitly support each
requested wall-time, memory and task limit before it can accept the call.
"""
struct ResourceEnvelope
    input_bytes::Union{Nothing,Int}
    input_lines::Union{Nothing,Int}
    syntax_nodes::Union{Nothing,Int}
    wall_seconds::Union{Nothing,Float64}
    memory_bytes::Union{Nothing,Int}
    tasks::Union{Nothing,Int}
    stdout_bytes::Int
    stderr_bytes::Int

    function ResourceEnvelope(; input_bytes=nothing, input_lines=nothing, syntax_nodes=nothing,
            wall_seconds=nothing, memory_bytes=nothing, tasks=nothing,
            stdout_bytes::Integer=65536, stderr_bytes::Integer=65536)
        for (name, limit) in pairs((; input_bytes, input_lines, syntax_nodes, memory_bytes, tasks))
            isnothing(limit) || (limit isa Integer && 0 <= limit <= typemax(Int)) ||
                throw(ArgumentError("$name must be a nonnegative integer or nothing"))
        end
        for (name, limit) in pairs((; stdout_bytes, stderr_bytes))
            0 <= limit < typemax(Int) || throw(ArgumentError("$name is outside the supported byte range"))
        end
        wall = isnothing(wall_seconds) ? nothing : Float64(wall_seconds)
        isnothing(wall) || (isfinite(wall) && wall > 0) ||
            throw(ArgumentError("wall_seconds must be finite and positive"))
        new(input_bytes, input_lines, syntax_nodes, wall, memory_bytes, tasks, stdout_bytes, stderr_bytes)
    end
end

"""
    CapabilityPolicy(authorize; availability=context -> :available)

An operation's permission and readiness checks. `authorize(context)::Bool`
uses context supplied by the application. `availability(context)` reports
`:available`, `:saturated` or `:unavailable` for an authorized caller.
"""
struct CapabilityPolicy{A,R}
    authorize::A
    availability::R
end
CapabilityPolicy(authorize; availability=Returns(:available)) = CapabilityPolicy(authorize, availability)

const _EXECUTION_STATUSES = (:ok, :refused, :saturated, :unavailable, :timeout,
                             :output_limit, :failed, :signaled)
const _EXECUTION_HOST_LIMITS = (:wall_seconds, :memory_bytes, :tasks)

"""
    ExecutionResult(status=:ok; value=nothing, exit_code=nothing, signal=nothing, usage=(;), stdout="", stderr="")

An adapter's outcome. A signal or nonzero exit classifies an otherwise successful
outcome as `:signaled` or `:failed`. An explicit cause such as `:timeout` takes
precedence. Only success carries a value. After [`execute`](@ref), `stdout` and
`stderr` hold bounded text, `stdout_truncated` and `stderr_truncated` identify
overflow, and `elapsed` is the elapsed time in seconds.
"""
struct ExecutionResult{T,U}
    status::Symbol
    value::T
    exit_code::Union{Int,Nothing}
    signal::Union{Int,Nothing}
    usage::U
    stdout::String
    stderr::String
    stdout_truncated::Bool
    stderr_truncated::Bool
    elapsed::Float64
end

function ExecutionResult(status::Symbol=:ok; value=nothing, exit_code::Union{Int,Nothing}=nothing,
        signal::Union{Int,Nothing}=nothing, usage::NamedTuple=(;), stdout::String="", stderr::String="")
    status in _EXECUTION_STATUSES || throw(ArgumentError("unknown execution status $status"))
    if status === :ok
        if !iszero(something(signal, 0))
            status = :signaled
        elseif !iszero(something(exit_code, 0))
            status = :failed
        end
    end
    ExecutionResult(status, status === :ok ? value : nothing, exit_code, signal, usage, stdout, stderr, false, false, 0.0)
end

_execution_measure(input, dimension) = nothing
_execution_measure(source::AbstractString, ::Val{:input_bytes}) = sizeof(source)
_execution_measure(source::AbstractString, ::Val{:input_lines}) = count(==('\n'), source) + 1

"""
    Executor(adapter; concurrency=1, hard_limits=(), measure=...)

A process-local, shareable admission limit and adapter. Pass the same executor
as a fixed field to mounts that share capacity. Additional calls return
`:saturated` immediately. Use `@queued` for work that should wait its turn.

`adapter(input, envelope, stdout, stderr)` writes diagnostics to the supplied
bounded streams and returns an [`ExecutionResult`](@ref). The adapter owns its
process and any cleanup. Advertise only the `hard_limits` it enforces during
execution (`:wall_seconds`, `:memory_bytes`, `:tasks`). The default fits an
in-process callback. A host that shares capacity across processes enforces its
own admission as well.

`measure(input, Val(dimension))` returns a nonnegative integer or `nothing`
when unsupported. Only requested dimensions are measured, bytes before lines
before syntax nodes. By default text supplies its byte and line counts. Supply
an application measurement for other inputs or a syntax budget.
"""
struct Executor{A,M}
    adapter::A
    measure::M
    hard_limits::Tuple
    concurrency::Int
    lock::ReentrantLock
    running::Base.RefValue{Int}
end

function Executor(adapter; concurrency::Int=1, hard_limits=(), measure=_execution_measure)
    concurrency > 0 || throw(ArgumentError("concurrency must be positive"))
    limits = Tuple(hard_limits)
    all(in(_EXECUTION_HOST_LIMITS), limits) || throw(ArgumentError("unknown hard limit in $limits"))
    Executor(adapter, measure, limits, concurrency, ReentrantLock(), Ref(0))
end

function _execution_admission(executor, capability, envelope, context, reserve)
    capability.authorize(context)::Bool || return :refused
    ready = capability.availability(context)
    ready in (:available, :saturated, :unavailable) ||
        throw(ArgumentError("unknown execution availability $(repr(ready))"))
    ready === :available || return ready
    for name in _EXECUTION_HOST_LIMITS
        !isnothing(getproperty(envelope, name)) && !(name in executor.hard_limits) && return :unavailable
    end
    lock(executor.lock) do
        executor.running[] < executor.concurrency || return :saturated
        reserve && (executor.running[] += 1)
        :available
    end
end

"""
    execution_availability(executor; capability, context, envelope=ResourceEnvelope())

Read the current access, adapter support and capacity for a mounted operation
without executing it. A subsequent call to [`execute`](@ref) checks again and
reserves its slot atomically.
"""
function execution_availability(executor::Executor; capability::CapabilityPolicy, context,
        envelope::ResourceEnvelope=ResourceEnvelope())
    _execution_admission(executor, capability, envelope, context, false)
end

function _execution_input_status(executor, input, envelope)
    for dimension in (:input_bytes, :input_lines, :syntax_nodes)
        limit = getproperty(envelope, dimension)
        isnothing(limit) && continue
        measured = executor.measure(input, Val(dimension))
        isnothing(measured) && return (:unavailable, "No input measurement for $dimension")
        measured isa Integer && measured >= 0 ||
            throw(ArgumentError("invalid measurement for $dimension: $(repr(measured))"))
        measured <= limit || return (:refused, "Input exceeds $dimension limit ($limit)")
    end
    (:available, "")
end

# Keep complete text characters within the byte budget, even if a stream filled
# partway through a multibyte sequence. The extra byte detects overflow.
_diagnostic_buffer(limit) = IOBuffer(UInt8[]; write=true, maxsize=limit + 1)

function _execution_text(buffer, suffix, limit)
    # A child process may have closed the supplied write side after draining
    # its pipe. Take ownership of those bytes before appending adapter text.
    bytes = take!(buffer)
    if !isempty(suffix) && length(bytes) <= limit
        combined = IOBuffer(bytes; write=true, append=true, maxsize=limit + 1)
        write(combined, suffix)
        bytes = take!(combined)
    end
    overflow = length(bytes) > limit
    raw = String(bytes)
    isvalid(raw) && !overflow && return (raw, false)
    output = IOBuffer()
    for char in raw
        char = isvalid(char) ? char : '?'
        position(output) + ncodeunits(char) <= limit || break
        print(output, char)
    end
    (String(take!(output)), overflow)
end

"""
    execute(executor, input; capability, context, envelope=ResourceEnvelope())

Check permission, capacity and input limits on the actual call, then run the
adapter. Diagnostic overflow returns `:output_limit` and discards the value.
Measurement and adapter exceptions return `:failed` with bounded diagnostics. Interrupts
propagate. The slot is released for every outcome.
"""
function execute(executor::Executor, input; capability::CapabilityPolicy, context,
        envelope::ResourceEnvelope=ResourceEnvelope())
    ready = _execution_admission(executor, capability, envelope, context, true)
    ready === :available || return ExecutionResult(ready)
    try
        start = time_ns()
        output = _diagnostic_buffer(envelope.stdout_bytes)
        errors = _diagnostic_buffer(envelope.stderr_bytes)
        result = try
            status, message = _execution_input_status(executor, input, envelope)
            if status === :available
                executor.adapter(input, envelope, output, errors)
            else
                print(errors, message)
                ExecutionResult(status)
            end
        catch e
            e isa InterruptException && rethrow()
            diagnostic = _diagnostic_buffer(envelope.stderr_bytes)
            showerror(diagnostic, e)
            ExecutionResult(:failed; stderr=String(take!(diagnostic)))
        end
        result isa ExecutionResult || throw(ArgumentError("execution adapter must return ExecutionResult"))
        stdout, clipped_out = _execution_text(output, result.stdout, envelope.stdout_bytes)
        stderr, clipped_err = _execution_text(errors, result.stderr, envelope.stderr_bytes)
        elapsed = (time_ns() - start) / 1e9
        status = result.status
        stdout_truncated = result.stdout_truncated || clipped_out
        stderr_truncated = result.stderr_truncated || clipped_err
        if status === :ok
            if stdout_truncated || stderr_truncated
                status = :output_limit
            elseif !isnothing(envelope.wall_seconds) && elapsed > envelope.wall_seconds
                status = :timeout
            end
        end
        ExecutionResult(status, status === :ok ? result.value : nothing, result.exit_code,
            result.signal, result.usage, stdout, stderr, stdout_truncated, stderr_truncated, elapsed)
    finally
        lock(executor.lock) do
            executor.running[] -= 1
        end
    end
end

"""
    ApplicationWorkload(operation, args...; kwargs=(;), expected_status=:ok, check=Returns(true))

One representative call to an indexed graph property, with its expected status
and optional predicate on the result. Declare it as a fixed field or a scalar
property typed as `ApplicationWorkload` on the object that owns the operation.
The invoking tool supplies caller context.
"""
struct ApplicationWorkload{A,K,C}
    operation::Symbol
    args::A
    kwargs::K
    expected_status::Symbol
    check::C
    function ApplicationWorkload(operation::Symbol, args...; kwargs::NamedTuple=(;),
            expected_status::Symbol=:ok, check=Returns(true))
        expected_status in _EXECUTION_STATUSES || throw(ArgumentError("unknown workload status $expected_status"))
        haskey(kwargs, :context) && throw(ArgumentError("workload context is supplied by its caller"))
        new{typeof(args),typeof(kwargs),typeof(check)}(operation, args, kwargs, expected_status, check)
    end
end

"""
    application_workloads(object)

Read this mount's fixed workload values and scalar properties explicitly
typed as `ApplicationWorkload`. Discovery uses the existing declaration
descriptors and evaluates only the selected workload properties. Call on a
mounted child to read its examples.
"""
function application_workloads(object)
    workloads = Pair{Symbol,ApplicationWorkload}[]
    for property in _shared_property_descriptors(typeof(object))
        property.indexed && continue
        T = property.output.type
        declared = T isa Type && T <: ApplicationWorkload
        stored = property.fixed && getfield(object, property.name) isa ApplicationWorkload
        if declared || stored
            push!(workloads, property.name => getproperty(object, property.name))
        end
    end
    (; workloads...)
end

"""
    run_workload(object, workload; context)

Call the declared graph property on this object with the supplied caller
context. Return its result after checking status and predicate. A mismatch
throws so that build, canary and acceptance drivers observe a failure.
"""
function run_workload(object, workload::ApplicationWorkload; context)
    operation = getproperty(object, workload.operation)
    result = operation(workload.args...; workload.kwargs..., context)
    result isa ExecutionResult || throw(ArgumentError("workload $(workload.operation) must return ExecutionResult"))
    result.status === workload.expected_status || error(
        "Workload $(workload.operation) expected $(workload.expected_status), got $(result.status): $(result.stderr)")
    workload.check(result)::Bool || error("Workload $(workload.operation) failed its result check")
    result
end

# Fixed protocol values are server-owned configuration. Keep their graph edges
# in reflection while excluding them from generated forms and request binding.
function _execution_configuration(input)
    T = get(input, :type, nothing)
    T isa Type && T <: Union{Executor,CapabilityPolicy,ResourceEnvelope,ApplicationWorkload}
end
