# --- A `semantic_app(…; presentation=:tabs)` page's results in its Markdown ---
#
# The page shows each result in its tab, asked from the result's own address
# by the browser (or drawn once by the server, for a result computed in the
# browser) and kept beside the inputs it reads. Its Markdown (`?plain`, a
# report, `pdf_report`) has no browser to ask and no controls to read, so each
# tab writes what its result's address answers as Markdown at the page's
# inputs, after a line that states those inputs (`shown_at`), and in a report
# once more for each state the app declares (`report_states`).

# The inputs a result is shown at, as the page's controls show them: the
# object and route whose controls draw them, the inputs in order, and their
# values. Its text is made when the Markdown is written, so an HTML read of
# the page resolves no domain for it.
struct _ShownAt
    object::Any
    route::Any
    params::Vector{Any}
    values::Any
end

# A declared state of a report: its caption, or `nothing`, and the values it
# gives the inputs it names.
struct _ReportState
    caption::Union{Nothing,String}
    values::Dict{Symbol,Any}
end

# One rendering of a tab's result in the page's Markdown: its address with the
# inputs, the line stating them, and the state it shows (`nothing`: the page's
# own inputs).
struct _ResultRendering
    url::String
    shown::_ShownAt
    state::Union{Nothing,_ReportState}
end

# A tab's result in the page's Markdown. HTML and HXML show nothing of it: the
# page shows the result where the browser puts it.
struct _TabResultMarkdown
    renderings::Vector{_ResultRendering}   # the page's inputs first, then each declared state
    static::Any                            # the page's `StaticExport`, or `nothing`
    # The result's HTML the page draws (`_MarkedHtml`, a result the browser
    # computes), whose numbers its Markdown continues; `nothing` for a result
    # the browser loads later, which takes none.
    view::Any
end
_TabResultMarkdown(renderings, static) = _TabResultMarkdown(renderings, static, nothing)

Base.show(::IO, ::MIME"text/html", ::_TabResultMarkdown) = nothing
Base.show(::IO, ::MIME"application/vnd.hyperview+xml", ::_TabResultMarkdown) = nothing
Base.show(::IO, ::MIME"text/plain", ::_TabResultMarkdown) = nothing
_semantic_show_leaf(::IO, ::MIME"text/plain", ::_TabResultMarkdown) = nothing
HTMX.markdown_block(::_TabResultMarkdown) = true
# The page's HTML holds none of it, so a tabset's default id does not either.
_tabset_key(::_TabResultMarkdown, h::UInt) = h

function Base.show(io::IO, m::MIME"text/markdown", r::_TabResultMarkdown)
    parts = String[]
    for (i, rendering) in enumerate(r.renderings)
        isnothing(rendering.state) || page_report() || continue
        append!(parts, _result_rendering_markdown(rendering, r.static, r.view, i - 1))
    end
    print(io, join(filter(!isempty, parts), "\n\n"))
    nothing
end

# A report's copy of a result at a declared state repeats the result's element
# ids, and a PDF refuses a label it finds twice once `ref` cites it. The copy's
# ids take its state's number (`fig-curve` → `fig-curve-state-1`), so an id
# cites the result at the page's inputs, as on the page. Fenced code is left
# as written.
function _state_copy_ids(markdown::AbstractString, n::Integer)
    fence = nothing
    lines = String[]
    for line in eachsplit(markdown, '\n')
        m = match(r"^ {0,3}(`{3,}|~{3,})", line)
        if !isnothing(fence)
            !isnothing(m) && startswith(m.captures[1], fence) && (fence = nothing)
        elseif !isnothing(m)
            fence = m.captures[1]
        else
            line = replace(line, r"\{#([^\s}]+)" => SubstitutionString("{#\\1-state-$n"))
        end
        push!(lines, line)
    end
    join(lines, '\n')
end

# The Markdown of one rendering: the state's caption, the line stating its
# inputs, and what the result's address answers as Markdown. The answer is the
# bare fragment the page loads into the tab, under the page's audience,
# language, report flag and static export; in a report it is the result's
# report view. In a `numbered` document the rendering at the page's inputs of
# a result the page draws (`view`) numbers its captions as the page does, from
# the counts the document had reached there; a declared state, which only the
# report shows, takes no number, so every number reads as on the page; its
# ids take its place `n` among the tab's renderings (`_state_copy_ids`).
function _result_rendering_markdown(rendering::_ResultRendering, static, view=nothing, n=0)
    state = rendering.state
    parts = String[]
    if !isnothing(state) && !isnothing(state.caption)
        push!(parts, _markdown_of(h.p(h.strong(state.caption))))
    end
    line = _shown_at_node(rendering.shown)
    isnothing(line) || push!(parts, _markdown_of(line))
    from = isnothing(state) ? _result_numbering_from(view) : nothing
    resp = _unnumbered() do
        _asking_result_numbers(from) do
            dispatch(:GET, rendering.url; headers=["HX-Request" => "true", "Accept" => "text/markdown"],
                     static, operation_policy=:blocking)
        end
    end
    body = String(_response_bytes(resp))
    # A fault answers the fragment with its article (`X-HTMXO-Error-Id`), as the
    # page shows it in the tab; a state the app declares must be one its inputs take.
    if !isnothing(state) && (resp.status != 200 || !isempty(HTTP.header(resp, "X-HTMXO-Error-Id")))
        throw(ArgumentError(string("semantic_app report_states: the state ",
            _report_state_name(state), " is refused at ", rendering.url, " (", resp.status, ")",
            isempty(strip(body)) ? "" : string(":\n", body))))
    end
    push!(parts, strip(isnothing(state) ? body : _state_copy_ids(body, n), '\n'))
    parts
end

_markdown_of(node) = strip(sprint(show, MIME"text/markdown"(), node), '\n')

_report_state_name(state::_ReportState) = isnothing(state.caption) ?
    string("(", join((string(k, " = ", repr(v)) for (k, v) in sort!(collect(state.values); by=first)), ", "), ")") :
    repr(state.caption)

# The line stating a result's inputs, "Shown at: Slope 0.20; Intercept 80
# units", or `nothing` for a result that reads none.
function _shown_at_node(shown::_ShownAt)
    pairs = String[]
    for param in shown.params
        text = _shown_value_text(shown.object, shown.route, param, shown.values)
        isnothing(text) && continue
        push!(pairs, string(_shown_label(param), " ", text))
    end
    isempty(pairs) && return nothing
    h.p(string(_error_texts(shown.object).shown_at, ": ", join(pairs, "; ")))
end

# An input's label, as its control writes it: its docstring's first paragraph,
# else its name.
function _shown_label(param)
    doc_label, _ = _doc_label_help(get(param, :doc, nothing))
    doc_label isa AbstractString ? String(doc_label) : Long(param.name)
end

# An input's value as its control shows it, or `nothing` for none to show.
function _shown_value_text(obj, route, param, values)
    value = get(values, param.name, nothing)
    if param.type isa Type && param.type <: Records
        value isa Records || (value = getproperty(
            something(_param_declaring_object(obj, param.name), obj), param.name))
        return _shown_records_text(obj, route, value, values)
    end
    (value === nothing || value === _NO_DEFAULT || value isa Upload) && return nothing
    value isa AbstractVector && any(v -> v isa Upload, value) && return nothing
    control_obj, ControlT = _semantic_control_owner(obj, route.owner, param)
    domains = get(values, _SEMANTIC_DOMAINS, (;))
    domain = haskey(domains, param.name) ? domains[param.name] :
        _resolved_input_domain(control_obj, ControlT,
                               (name=param.name, domain=get(param, :domain, nothing)), values)
    _shown_text(domain, value, _error_texts(obj))
end

function _shown_text(domain, value, texts::ErrorTexts)
    if domain !== nothing && get(domain, :kind, nothing) === :interval
        value isa AbstractVector && return _shown_list(v -> _shown_number(domain.number, v), value)
        return _shown_number(domain.number, value)
    elseif domain !== nothing && get(domain, :kind, :unrestricted) !== :unrestricted
        options = get(domain, :options, NamedTuple[])
        value isa AbstractVector && return _shown_list(v -> _shown_option(options, v), value)
        return _shown_option(options, value)
    end
    value isa AbstractVector && return _shown_list(v -> _shown_text(nothing, v, texts), value)
    value isa Bool && return value ? texts.shown_yes : texts.shown_no
    value isa AbstractFloat && return string(_number_control_value(value))
    string(value)
end

_shown_list(f, values) = isempty(values) ? nothing : join((f(v) for v in values), ", ")

function _shown_number(domain::NumberDomain, value)
    x = value isa AbstractString ? tryparse(Float64, value) : value
    text = x isa Real && isfinite(x) && domain.digits !== nothing ?
        format_number(x; digits=domain.digits) :
        x isa Real ? string(_number_control_value(x)) : string(value)
    domain.unit === nothing ? text : string(text, " ", domain.unit)
end

function _shown_option(options, value)
    i = findfirst(o -> isequal(o.value, value), options)
    i === nothing && return _option_wire_string(value)
    label = options[i].label
    label isa AbstractString ? String(label) : _md_label_text(Any[label])
end

# A list of records, as its cards show it: each switched-on record's label and
# its fields' values.
function _shown_records_text(obj, route, records::Records, values)
    entries = [entry for entry in records.entries if entry.on]
    isempty(entries) && return nothing
    params = Dict{Symbol,Any}(param.name => param for param in route.params)
    join(map(entries) do entry
        fields = String[]
        for field in records.fields
            param = get(params, field, nothing)
            isnothing(param) && continue
            record_values = merge(Dict{Symbol,Any}(values), Dict{Symbol,Any}(field => getfield(entry, field)))
            text = _shown_value_text(obj, route, param, record_values)
            isnothing(text) || push!(fields, string(_shown_label(param), " ", text))
        end
        isempty(fields) ? entry.label : string(entry.label, " (", join(fields, ", "), ")")
    end, ", ")
end
_shown_records_text(obj, route, records, values) = nothing

# `report_states` of `semantic_app`: a vector of states, each the values it
# gives the page's inputs as a NamedTuple (or a dictionary), or a caption
# `=>` those values.
_report_states(::Nothing) = _ReportState[]
function _report_states(states)
    states isa Union{AbstractVector,Tuple} || throw(ArgumentError(string(
        "semantic_app report_states must be a vector of states, each a NamedTuple of input ",
        "values or `\"caption\" => (; …)`; got ", repr(states))))
    map(_report_state, collect(states))
end
_report_state(state::Pair{<:AbstractString}) = let s = _report_state(state.second)
    isempty(strip(state.first)) && throw(ArgumentError(
        "semantic_app report_states: a state's caption must not be empty"))
    _ReportState(String(state.first), s.values)
end
_report_state(values::Union{NamedTuple,AbstractDict}) = let dict = Dict{Symbol,Any}(Symbol(k) => v for (k, v) in pairs(values))
    isempty(dict) && throw(ArgumentError(
        "semantic_app report_states: a state must name at least one input"))
    _ReportState(nothing, dict)
end
_report_state(state) = throw(ArgumentError(string(
    "semantic_app report_states: each state is a NamedTuple of input values or ",
    "`\"caption\" => (; …)`; got ", repr(state))))

# The states a page declares name its inputs, and nothing else.
function _check_report_states(states::Vector{_ReportState}, inputs)
    for state in states, name in keys(state.values)
        name in inputs || throw(ArgumentError(string(
            "semantic_app report_states: the state ", _report_state_name(state), " names ",
            repr(name), ", which no operation of the surface takes; its inputs are ",
            join(repr.(sort!(collect(inputs))), ", "))))
    end
    states
end

# The Markdown of a following tab's result: at the page's inputs, then at each
# declared state that names an input the result reads.
function _tab_result_markdown(obj, route, current, target, sent, shown_names, states, static)
    params = Any[param for param in route.params if param.name in shown_names &&
                 param.source !== :path && get(param, :kind, nothing) !== nothing &&
                 _param_relevant(obj, param.name)]
    renderings = [_ResultRendering(_semantic_follow_url(target, obj, route, current, sent),
                                   _ShownAt(obj, route, params, current), nothing)]
    reads = Set{Symbol}(param.name for param in params)
    for state in states
        any(in(reads), keys(state.values)) || continue
        values = copy(current)
        # An input the state names no longer follows its computed default.
        values[_SEMANTIC_FOLLOWS] = setdiff(Set{Symbol}(_semantic_follows(current)), keys(state.values))
        for (name, value) in state.values
            name in sent && (values[name] = value)
        end
        push!(renderings, _ResultRendering(_semantic_follow_url(target, obj, route, values, sent),
                                           _ShownAt(obj, route, params, values), state))
    end
    _TabResultMarkdown(renderings, static)
end
