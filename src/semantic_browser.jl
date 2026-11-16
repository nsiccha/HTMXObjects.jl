# Browser computation for semantic pages: `@browser`, `browser_module`, `bound`.
#
# A `semantic_app(…; presentation=:tabs)` page asks the server again for a
# result when an input it reads changes. A property declared
# `@browser(name) = browser_module(file, entry)` has a browser twin: an ES module
# (what `ReactiveKernels.js_source` emits) computing the same value from the
# page's inputs. A result that shows that property only through `bound(...)`
# marks is computed and redrawn in the browser instead, with no request, so a
# static export keeps following its inputs offline. The lowering of `@browser`
# and `bound` lives beside `@help` in HTMXObjects.jl; this file holds the
# values, the page regions, their runtime and the export's checks.

"""
    BrowserModule

An ES module a page runs in the browser, made by [`browser_module`](@ref):
its source text, the name of the exported function to call, and its
arguments as the module's `INPUTS` list names them (`(name, Julia type)`, in
order).
"""
struct BrowserModule
    source::String
    entry::String
    inputs::Vector{Tuple{String,String}}
end

const _BROWSER_ENTRY = r"^[A-Za-z_$][A-Za-z0-9_$]*$"
const _BROWSER_INPUTS = r"export\s+const\s+INPUTS\s*=\s*\[(.*?)\]\s*;?"s
const _BROWSER_INPUT = r"\{\s*\"?name\"?\s*:\s*\"([^\"]+)\"\s*,\s*\"?type\"?\s*:\s*\"([^\"]+)\"\s*\}"

function BrowserModule(source::AbstractString, entry)
    src = String(source)
    name = String(string(entry))
    occursin(_BROWSER_ENTRY, name) || throw(ArgumentError(
        "browser_module: the entry $(repr(name)) is not a JavaScript name"))
    occursin(r"</script"i, src) && throw(ArgumentError(
        "browser_module: the module text contains `</script`, which cannot be embedded in a page"))
    exported = Regex(string("export\\s+(?:async\\s+)?function\\s*\\*?\\s*", name, "\\s*\\(|",
                            "export\\s+(?:const|let|var)\\s+", name, "\\b|",
                            "export\\s*\\{[^}]*\\b", name, "\\b[^}]*\\}"))
    occursin(exported, src) || throw(ArgumentError(
        "browser_module: the module exports no function `$name`"))
    m = match(_BROWSER_INPUTS, src)
    m === nothing && throw(ArgumentError(string(
        "browser_module: the module exports no `INPUTS` list naming its arguments in order ",
        "(`export const INPUTS = [{ name: \"x\", type: \"Float64\" }, …]`, as ",
        "`ReactiveKernels.js_source` writes it)")))
    inputs = Tuple{String,String}[(String(x[1]), String(x[2])) for x in eachmatch(_BROWSER_INPUT, m[1])]
    BrowserModule(src, name, inputs)
end

const _BROWSER_FILES = Dict{Tuple{String,String},Tuple{Float64,BrowserModule}}()
const _BROWSER_FILES_LOCK = ReentrantLock()

"""
    browser_module(path, entry) -> BrowserModule
    browser_module(; source, entry) -> BrowserModule

The ES module a `@browser` declaration computes its property with, read from
the file `path` (relative to the working directory, read again when it
changes) or given as `source` text, such as the string
`ReactiveKernels.js_source` returns.

```julia
prediction = PREDICT(water, attenuation, density)
@browser(prediction) = browser_module("assets/shielding.mjs", :shielding)
```

The module is the one `ReactiveKernels.js_source` emits, and any other that
keeps its contract: it exports the function `entry`, which takes positional
arguments, and `INPUTS`, the list of their names and Julia types in that order
(`export const INPUTS = [{ name: "water", type: "Vector{Float64}" }, …]`).
`entry` returns the property's value: an object of named outputs for a named
tuple, or a number or array. An error it throws is shown in the result, under
its `name` (`DomainError`, …). The page passes each argument by its name: a
`@param` from its control (`Float64`, `Int64`, `Bool` and vectors of them, or
text), any other from the property of that name, which must not read an input;
its value goes into the page as data, `Inf`, `NaN` and `-0.0` included: a
number, a `Bool`, text, or a vector or matrix of them. A matrix is the array of
its rows, `m[i][j]` holding Julia's `m[i+1, j+1]`, as
`ReactiveKernels.js_source` modules take it; one without rows is an empty array
whose `cols` is its column count (`zeros(0, 3)` arrives as
`Object.assign([], { cols: 3 })`). The module is embedded in the page, so it
must be one self-contained file. The page imports it from an in-memory `blob:`
address, once, on its first computation: a browser's request log lists that
address, though nothing leaves the page.
"""
function browser_module(path::AbstractString, entry)
    full = abspath(path)
    isfile(full) || throw(ArgumentError(
        "browser_module: no file $(repr(path)) (looked at $full)"))
    changed = mtime(full)
    key = (full, string(entry))
    lock(_BROWSER_FILES_LOCK) do
        cached = get(_BROWSER_FILES, key, nothing)
        cached !== nothing && cached[1] == changed && return cached[2]
        m = BrowserModule(read(full, String), entry)
        _BROWSER_FILES[key] = (changed, m)
        m
    end
end
browser_module(; source::AbstractString, entry) = BrowserModule(source, entry)

# --- `bound`: where a browser value shows in a view ---

"""
    bound(x)
    bound(x.field)
    bound(x.field[i])
    bound(x; digits=nothing, sigdigits=nothing, percent=false, texts=table_texts(), unit=nothing)
    bound(x; date=:long, texts=table_texts())
    bound(x; labels=[value => text, …])
    bound(x; columns=(:a, :b, …))

Inside an `@htmx` struct, marks where a route's view shows a value the browser
computes: a property declared `@browser`, one of its outputs or their elements
(`i` an integer literal), or a `@param`. A page that computes the property in
the browser rewrites it there after each change, as the server wrote it.

A number is written as [`format_number`](@ref) writes it, with the same
keywords, in the language of `texts` (a [`TableTexts`](@ref)): `digits=3`
writes exactly three decimals (`0.120`), `digits=0` a whole number (`45`),
`sigdigits=k` `k` significant digits, `percent=true` the share 0.45 as `45%`
(`45 %` with `table_texts(:de)`, which also writes `0,120`). Without them a
float keeps every digit, `2.0` writes `2` and `3.81e-5` writes `3.81·10⁻⁵`, and
an integer takes the thousands separator (`1,234`). The value in the graph is
never rounded. A `Bool` writes `true` or `false`, and text is shown as it is.

A module that returns numbers only says "no value" with `NaN`, so a `NaN`
writes `–`, as `missing` and `nothing` do (`format_number` itself writes
`NaN`); `Inf` writes `∞`. `unit = "years"` follows a number with a no-break
space (`12.3 years`), never a label, a day, a `Bool`, text or `–`.

`date = :long`, `:short` or `:month` writes a day, as [`format_date`](@ref)
writes it in the language of `texts`: `16 November 2019`, `16 Nov 2019` or
`Nov 2019` (`16. November 2019` with `table_texts(:de)`). The value is a
number of milliseconds since 1 January 1970, UTC, as JavaScript dates and a
plot's temporal axis count them, or a `Dates.Date`; its day is the UTC
calendar day of that instant. No day (`NaN`, `±Inf`, `missing`, `nothing`)
writes `–`. A table's days are its `ColumnSpec(label; date)`.

`labels` writes the value as the text a table names for it, a list of
`value => text` pairs or a `Dict`, so a level or a category the module
computes reads as words: `bound(rules.level; labels = [0 => "No dose", 3 =>
"200 mg (level 3)"])` writes `No dose` for 0, on the server, in the page's
Markdown and in the browser after each change. A key is a number, which names
the same number (`3` also names the module's `3.0`), a `Bool`, or text; a
page in another language passes its own texts. A value the table does not
name is an error, never a silent fallback: the server throws an
`ArgumentError` naming the value and the keys, and the browser shows the same
message in the result, as it shows a module's error, until the next
computation. No value writes `–`. With `digits`, `sigdigits` or `percent`,
labels name exceptions instead: other numbers use that number format.
For example, `bound(fit.half; digits = 1, unit = "years", labels = [Inf =>
"No finite halving time"])` writes `12.3 years` or `No finite halving time`.
`Inf` and `-Inf` are distinct keys; `NaN` is still no value. Without a number
format, labels must name every value. `labels` takes no `date`; a table's
column of such values is its `ColumnSpec(label; labels)` with the same
optional number format.

With `columns` it is the property's equal-length vector outputs as a Tables.jl
table, or its single-value outputs (a number, a Boolean, text) as a table of
one row, for a mark at a value such as a rule; one table does not mix the two.
It is for a plot's `data(...)`, whose element takes
[`bound_columns_attrs`](@ref), or for [`render_table`](@ref), which the page
then writes again after each computation (*A table the browser computes* in
its docstring). The table is its own `Tables.columns`, so a plotting package
that keeps the columns of its data, as AlgebraOfGraphics' `data(...)` does,
still holds it.

The `@htmx` macro recognizes `bound(...)` calls in its struct and records which
value each names, so `bound` needs no import there; it has no meaning outside
one.
"""
bound(_x...; _kw...) = throw(ArgumentError(string(
    "`bound` marks a value inside an `@htmx` struct's routes and properties, where ",
    "the macro records which property or `@param` it names; it has no meaning outside one")))

"""
    BoundValue

What `bound(x)` is on the server: the value, shown as text, the path that
tells a browser page where its value comes from, and how a number is written
(`format_number`'s rounding, `percent` and language), with `date` the day it
names (`format_date`'s style), or with `labels` the text its table names.
"""
struct BoundValue{T}
    path::Vector{Any}
    value::T
    rounding::Union{Nothing,_FixedDigits,_SigDigits}
    percent::Bool
    texts::TableTexts
    date::Union{Nothing,Symbol}
    labels::Union{Nothing,_Labels}
    unit::Union{Nothing,String}
end

"""
    BoundColumns

What `bound(x; columns)` is on the server: the property's chosen equal-length
vector outputs as a Tables.jl table, or its chosen single-value outputs as a
table of one row (`Tables.getcolumn` gives `[v]`), and the path a browser page
reads them from. It is its own `Tables.columns`, so what a plotting package
keeps of its data (the `Layer.data` of AlgebraOfGraphics' `data(b)`) is still
`b`, and the element drawing it can take [`bound_columns_attrs`](@ref)`(b)`.
Its columns are the chosen outputs only; the property's other outputs are not
part of the table.
"""
struct BoundColumns{T}
    path::Vector{Any}
    value::T
    columns::Vector{Symbol}
end

function _bound(path::Tuple, value; digits=nothing, sigdigits=nothing, percent::Bool=false,
                texts::TableTexts=_EN_TABLE_TEXTS, columns=nothing, date=nothing, labels=nothing,
                unit::Union{Nothing,AbstractString}=nothing)
    if columns !== nothing
        digits === sigdigits === date === labels === unit === nothing && !percent && texts === _EN_TABLE_TEXTS || throw(ArgumentError(string(
            "bound(…; columns) is a table; say how a column's numbers, days or labels are written in the ",
            "`ColumnSpec` of `render_table`'s `columns` (`ColumnSpec(label; digits, sigdigits, percent)`, ",
            "`ColumnSpec(label; date)`, `ColumnSpec(label; labels)`) and its language with `render_table(…; texts)`")))
        return _bound_columns(Any[path...], value, columns)
    end
    for (name, k) in (("digits", digits), ("sigdigits", sigdigits))
        k === nothing || k isa Integer || throw(ArgumentError("bound: `$name` must be an integer, got $(repr(k))"))
    end
    date === nothing || date isa Symbol || throw(ArgumentError(
        "bound: `date` is :long, :short or :month (the styles of format_date); got $(repr(date))"))
    _date_style(date, "bound", digits, sigdigits, percent)
    table = _labels_format(labels, string("bound(", _bound_label(path), "; labels)"), digits, sigdigits, percent, date)
    b = BoundValue(Any[path...], value, _number_rounding(digits, sigdigits, "bound"), percent, texts, date, table,
        isnothing(unit) ? nothing : String(unit))
    # A value that is no day, or that its labels do not name, is refused here, not in the page.
    isnothing(date) && isnothing(table) || _bound_text(b)
    b
end

# An output a table shows as its one row: what the browser's module returns as
# a number, a Boolean or text, not a list.
const _BoundSingle = Union{Number,AbstractString,Symbol}
_bound_column(output::AbstractVector) = output
_bound_column(output) = [output]

function _bound_columns(path, value, columns)
    names = Symbol[Symbol(c) for c in (columns isa Union{Tuple,AbstractVector} ? columns : (columns,))]
    isempty(names) && throw(ArgumentError("bound(…; columns): name at least one column"))
    label = _bound_label(path)
    outputs = map(names) do c
        hasproperty(value, c) || throw(ArgumentError(
            "bound(…; columns): $label has no output `$c`"))
        output = getproperty(value, c)
        output isa Union{AbstractVector,_BoundSingle} || throw(ArgumentError(string(
            "bound(…; columns): ", label, ".", c, " is a ", typeof(output),
            ", neither a vector nor a single number or text")))
        output
    end
    single = [o isa _BoundSingle for o in outputs]
    any(single) && !all(single) && throw(ArgumentError(string(
        "bound(…; columns): the outputs ", _bound_names(names[single]), " (single values) and ",
        _bound_names(names[.!single]), " (vectors) of ", label, " cannot share a table: its ",
        "columns are vectors of one length, or single values (one row). Bind the single values ",
        "in a table of their own: bound(", label, "; columns = (",
        join((string(":", c) for c in names[single]), ", "), count(single) == 1 ? ",))" : "))")))
    lengths = map(o -> o isa AbstractVector ? length(o) : 1, outputs)
    allequal(lengths) || throw(ArgumentError(string(
        "bound(…; columns): the columns of ", label, " differ in length (",
        join((string(c, " ", n) for (c, n) in zip(names, lengths)), ", "), ")")))
    BoundColumns(path, value, names)
end
_bound_names(cs) = join((string("`", c, "`") for c in cs), ", ")

# The lowering's path holds symbols (`(:line, :x)`); a `QuoteNode` is taken too.
_bound_label(path) = join((p isa Integer ? string("[", p, "]") :
                           string(i == 1 ? "" : ".", p isa QuoteNode ? p.value : p)
                           for (i, p) in enumerate(path)), "")
_bound_wire(path) = Any[p isa QuoteNode ? string(p.value) : p for p in path]

Tables.istable(::Type{<:BoundColumns}) = true
Tables.columnaccess(::Type{<:BoundColumns}) = true
# Its own columns, so the path survives `Tables.columns` (a plot's `data(...)`).
# Not a `Tables.AbstractColumns`: that would make `b.path` a column lookup.
Tables.columns(b::BoundColumns) = b
Tables.columnnames(b::BoundColumns) = Tuple(b.columns)
Tables.getcolumn(b::BoundColumns, i::Int) = _bound_column(getproperty(b.value, b.columns[i]))
function Tables.getcolumn(b::BoundColumns, c::Symbol)
    c in b.columns || throw(ArgumentError(string(
        "bound(…; columns): the table of ", _bound_label(b.path), " has the columns ",
        join(b.columns, ", "), ", not `", c, "`; name it in `columns`")))
    _bound_column(getproperty(b.value, c))
end
Tables.schema(b::BoundColumns) = Tables.Schema(Tuple(b.columns),
    Tuple(eltype(_bound_column(getproperty(b.value, c))) for c in b.columns))

"""
    bound_columns_attrs(b::BoundColumns; dataset="source_0") -> NamedTuple

The attributes of the element that shows the table `bound(x; columns)` made,
such as the element of a plot drawn from it. Since `Tables.columns(b) === b`,
what a plotting package kept of the table's columns is `b` too. After the
browser computes the property again, a page calls
`AoV.updateData(id, rows, dataset)` for an element with an `id`
(AlgebraOfVega's runtime) and raises `htmxo:bound-columns` on it with the new
columns in `event.detail`. Each column is an array, one value long for a
single-value output, and `n` is the number of rows.
"""
bound_columns_attrs(b::BoundColumns; dataset::AbstractString="source_0") =
    (; data_htmxo_bound_columns=JSON.json(Dict("path" => _bound_wire(b.path),
        "columns" => string.(b.columns), "dataset" => String(dataset))))

# `render_table(bound(x; columns))`: the description of the rows the page
# writes again after each browser computation, as the `<table>`'s
# `data-htmxo-bound-table` (the browser runtime's `boundTable`): where it comes from, and
# for each column its name, what its values are (`kind`), how its numbers are
# written (`ColumnSpec` digits, sigdigits, percent), its cells' alignment and
# where an empty cell sits; and the column whose value keys a row's hover link.
# The browser runs no Julia, so the table's functions are refused.
function _bound_table_attrs(b::BoundColumns, cols, headers, formats, empty_aligns; cell, search_text, link_key, kwargs)
    refuse(what, instead) = throw(ArgumentError(string("render_table: the table of ", _bound_label(b.path),
        " is written again in the browser, which runs no Julia, so it takes no ", what, "; ", instead)))
    isnothing(cell) || refuse("`cell` function",
        "say how a column's numbers are written with `columns = [name => ColumnSpec(label; digits, sigdigits, percent)]`")
    isnothing(search_text) || refuse("`search_text` function", "the search reads the cells' text")
    link_key isa Union{Nothing,Symbol} || refuse("`link_key` function",
        "name the column whose value keys each row (`link_key = :$(first(cols))`)")
    isnothing(get(kwargs, :selectable, nothing)) || refuse("`selectable`", "its rows change with each computation")
    for hdr in headers
        _computed_sort_keys(hdr) && refuse("sort keys computed by functions (column $(repr(_header_label(hdr))))",
            "it sorts by each cell's value")
    end
    columns = map(enumerate(cols)) do (j, c)
        values = Tables.getcolumn(b, c)
        known = findfirst(v -> !(v === nothing || v === missing), values)
        column = Dict{String,Any}("name" => string(c),
            "kind" => isnothing(known) ? "float" : _bound_kind(values[known]))
        format = formats[j]
        if format isa _Labels
            column["labels"] = _labels_wire(format)
            format = format.format
        end
        if format isa _DateColumn
            column["date"] = _date_words(get(kwargs, :texts, _EN_TABLE_TEXTS), format.style)
        elseif !isnothing(format)
            isnothing(format.digits) || (column["digits"] = format.digits)
            isnothing(format.sigdigits) || (column["sigdigits"] = format.sigdigits)
            format.percent && (column["percent"] = true)
        end
        align = _header_align(headers[j])
        isnothing(align) || (column["align"] = String(align))
        isnothing(empty_aligns[j]) || (column["empty"] = empty_aligns[j])
        column
    end
    (; data_htmxo_bound_table=JSON.json(Dict("path" => _bound_wire(b.path), "columns" => columns,
        "link_key" => isnothing(link_key) ? nothing : string(link_key))))
end

# A table of browser outputs writes a NaN as no value, `–`, as the page does
# after each computation (`boundCell`): a module that returns numbers only
# says "none" with it.
_render_value(::BoundColumns, value::AbstractFloat) = isnan(value) ? nothing : value

_bound_kind(::Bool) = "bool"
_bound_kind(::Integer) = "int"
_bound_kind(::Real) = "float"
_bound_kind(_) = "text"
# A number as `format_number` writes it, NaN as no value (`–`: a module that
# returns numbers only says "none" with it); a day as `format_date` writes
# it; a value with `labels` as the text they name (`–` for no value); a Bool
# and text as `string` does.
_bound_text(b::BoundValue) = !isnothing(b.labels) ? _bound_text(_label_text(b.labels, b.value), b) :
    isnothing(b.date) ? _bound_text(b.value, b) :
    _format_date(_date_day(b.value), b.texts, _date_layout(b.texts, b.date))
_bound_text(x::Bool, b) = string(x)
_bound_text(x::Real, b) = x isa AbstractFloat && isnan(x) ? _format_number(nothing, b.texts, b.rounding, b.percent) :
    _format_number(_number_value(x), b.texts, b.rounding, b.percent) * (isnothing(b.unit) || isempty(b.unit) ? "" : "\u00a0" * b.unit)
_bound_text(x::Union{Nothing,Missing}, b) = _format_number(nothing, b.texts, b.rounding, b.percent)
_bound_text(x, b) = string(x)

# How the browser writes the value again: the rounding, `percent` and the
# language's number texts (`htmxoNumberText`), left out where they are the
# defaults (no rounding, English); for a day, the layout and month names of
# its style (`htmxoDateText`); or the labels' table (`labelText`).
function _bound_format(b::BoundValue)
    fields = Dict{String,Any}()
    isnothing(b.labels) || (fields["labels"] = _labels_wire(b.labels))
    isnothing(b.date) || return (; data_htmxo_format=JSON.json(Dict("date" => _date_words(b.texts, b.date))))
    b.rounding === nothing || merge!(fields, Dict(string(k) => v for (k, v) in pairs(_summary_rounding_fields(b.rounding))))
    b.percent && (fields["percent"] = true)
    isnothing(b.unit) || (fields["unit"] = b.unit)
    b.texts === _EN_TABLE_TEXTS || b.texts == _EN_TABLE_TEXTS ||
        (fields["texts"] = Dict(string(n) => getfield(b.texts, n) for n in (:decimal, :thousands, :minus, :percent)))
    isempty(fields) ? (;) : (; data_htmxo_format=JSON.json(fields))
end

_bound_node(b::BoundValue) = h.span(_bound_text(b);
    data_htmxo_bound=JSON.json(_bound_wire(b.path)), data_htmxo_kind=_bound_node_kind(b),
    _bound_format(b)...)
# What the browser reads the value as; a value with labels that the server
# computed as no value (`missing`, `nothing`) is of the kind of its keys.
_bound_node_kind(b::BoundValue) = !isnothing(b.labels) && (b.value === nothing || b.value === missing) ?
    _bound_kind(first(b.labels.keys)) : _bound_kind(b.value)

Base.show(io::IO, m::MIME"text/html", b::BoundValue) = show(io, m, _bound_node(b))
Base.show(io::IO, ::MIME"text/markdown", b::BoundValue) = print(io, _bound_text(b))
Base.show(io::IO, ::MIME"text/plain", b::BoundValue) = print(io, _bound_text(b))
Base.print(io::IO, b::BoundValue) = print(io, _bound_text(b))

# --- The regions of a page whose results the browser computes ---

# What one `semantic_app(…; presentation=:tabs)` render has emitted of its
# browser parts, so each binding, module and the runtime go into the page once,
# and what a static export of it cannot serve.
struct _BrowserPage
    id::String
    static::Any                      # the request's `StaticExport`, or `nothing`
    bindings::Dict{Symbol,String}    # property => its binding's element id
    payloads::Dict{String,Any}       # binding element id => what it says
    modules::Dict{String,String}     # module source => its element id
    written::Set{String}             # element ids already in the page
    runtime::Base.RefValue{Bool}
    problems::Vector{String}
end
_BrowserPage(id, static) = _BrowserPage(id, static, Dict{Symbol,String}(), Dict{String,Any}(),
    Dict{String,String}(), Set{String}(), Ref(false), String[])

_browser_static(obj) = (req = _req_of(obj); req isa HTTP.Request ?
    get(req.context, :htmxo_static_export, nothing) : nothing)

# The `@browser` properties the operation `name` of `obj` reads.
function _browser_reads(obj, name::Symbol)
    T = typeof(obj)
    declared = Base.invokelatest(_browser_properties, T)
    isempty(declared) && return Symbol[]
    found = _operation_reads(T, name)
    Symbol[p for p in declared if p in found.names]
end

# The values a finite input takes, as the page's controls offer them; `nothing`
# for a continuous or free input.
function _browser_finite_values(obj, route, param, current)
    T = param.type
    T === Bool && return Any[false, true]
    T isa Type && T <: Enum && return Any[instances(T)...]
    domain = try
        _resolved_input_domain(obj, typeof(obj), param, current)
    catch
        nothing
    end
    domain === nothing && return nothing
    get(domain, :multiple, false) && return nothing
    options = get(domain, :options, nothing)
    options === nothing || isempty(options) ? nothing :
        Any[o.value for o in options if !get(o, :disabled, false)]
end

const _BROWSER_VARIANTS_MAX = 64

# One rendering of a result's address, as the page loads it: the bare fragment,
# under the page's static export when there is one. Its captions write their
# numbers as markers, which the page's numbered document fills in
# (`_MarkedHtml`).
function _browser_render(url::AbstractString; static=nothing)
    resp = _asking_result_numbers(:marks) do
        dispatch(:GET, url; headers=["HX-Request" => "true"], static,
                 operation_policy=:blocking)
    end
    (; status=resp.status, body=String(_response_bytes(resp)),
       error=HTTP.header(resp, "X-HTMXO-Error-Id"))
end

_browser_json(x) = replace(JSON.json(x), "</" => "<\\/")

function _browser_variant_key(names, values)
    Dict{String,Any}(string(n) => _option_wire_string(values[n]) for n in names)
end

"""
    _browser_region(page, spec, route, current, target, sent, attrs) -> Node

The result region of an operation that reads `@browser` properties: its view
rendered for the page's current values and for each value of the finite inputs
it is sent, the bindings of those properties to their modules (once per page),
the modules and the runtime (once per page). Under a static export it also
records in `page.problems` what of the view would still need the server.
"""
function _browser_region(page::_BrowserPage, spec, route, current, target, sent, attrs, browser;
                         markdown=nothing)
    obj = spec.mounted
    T = typeof(obj)
    operation = spec.base_entry.name
    bindings = String[_browser_binding!(page, obj, p) for p in browser]
    finite = Pair{Symbol,Vector{Any}}[]
    for param in route.params
        param.source === :path && continue
        param.name in sent || continue
        values = _browser_finite_values(obj, route, param, current)
        values === nothing || push!(finite, param.name => values)
    end
    combos = Iterators.product((last(f) for f in finite)...)
    count = prod((length(last(f)) for f in finite); init=1)
    count <= _BROWSER_VARIANTS_MAX || throw(ArgumentError(string(
        "semantic_app: the result `", operation, "` computes in the browser and would need ",
        count, " views, one per value of its finite inputs ",
        join((string("`", first(f), "`") for f in finite), ", "), "; at most ",
        _BROWSER_VARIANTS_MAX, " are rendered. Read fewer of them in its view.")))
    names = Symbol[first(f) for f in finite]
    views = Tuple{String,String,Bool}[]   # variant key, markup, at the current values
    for combo in (isempty(finite) ? ((),) : combos)
        values = copy(current)
        for (n, v) in zip(names, combo)
            values[n] = v
        end
        # A finite input that follows its computed default would not be sent,
        # and every view would show the default's result: a view at another
        # value sends that value.
        _semantic_unfollow!(values, (n for n in names if !isequal(get(current, n, nothing), values[n])))
        at_current = all(n -> isequal(get(current, n, nothing), values[n]), names)
        url = _semantic_follow_url(target, obj, route, values, sent)
        rendered = _browser_render(url; static=page.static)
        # A fault shows its article as the page would; an address no route
        # answers would leave the view empty without a word.
        rendered.status == 200 || !isempty(rendered.error) ||
            throw(_unserved_result_error(obj, url, rendered.status))
        push!(views, (_browser_json(_browser_variant_key(names, values)), rendered.body, at_current))
    end
    # The current values may be none of the finite ones (a value the address
    # named that the domain no longer offers): show the first view then.
    shown = something(findfirst(last, views), 1)
    page.static === nothing ||
        _browser_check!(page, obj, route, current, target, sent, operation, names)
    # The page's Markdown holds the result's own Markdown (`markdown`), never
    # the view's HTML, which a Markdown reader or a PDF cannot carry. In a
    # numbered document the view's captions take the document's numbers, and
    # the Markdown continues from where the view's start.
    view = _marked_html(views[shown][2])
    nodes = Any[h.div(view; class="htmxo-browser-view", data_htmxo_variant=views[shown][1])]
    isnothing(markdown) || push!(nodes, _TabResultMarkdown(markdown.renderings, markdown.static, view))
    # Each view's markup as rendered, the shown one's too: the browser shows
    # a view again from its template, never from what the page made of it.
    # Every view's captions read the shown view's numbers.
    if length(views) > 1
        for (key, body, _) in views
            push!(nodes, h.template(_marked_html(body; like=view); data_htmxo_variant=key))
        end
    end
    # What an input sends when its control sends nothing (hidden, or not on
    # the page): its default, for the finite inputs' view and the bound values.
    defaults = Dict{String,Any}()
    for n in sent
        wire = try
            _browser_param_default(obj, n)
        catch
            nothing  # an input with no single wire value (a list of records)
        end
        wire === nothing || (defaults[string(n)] = wire)
    end
    append!(nodes, _browser_scripts!(page, bindings))
    if !page.runtime[]
        page.runtime[] = true
        push!(nodes, semantic_browser_script())
    end
    h.div(nodes...; attrs..., data_htmxo_browser=join(bindings, ' '),
          data_htmxo_browser_inputs=_browser_json(Dict("names" => string.(names),
                                                       "defaults" => defaults)))
end

# The wire values a `@param`'s control sends when the reader set nothing.
function _browser_param_default(obj, name::Symbol)
    source = something(_param_declaring_object(obj, name), obj)
    unbound = Base.invokelatest(getproperty(DynamicObjects, :remount), source;
                                __req__=nothing, __param_request__=nothing)
    _semantic_address_wire(getproperty(unbound, name))
end

# The binding of the `@browser` property `name` of `obj`: which module computes
# it and where each of the module's arguments comes from. Emitted once per page;
# returns its element id.
function _browser_binding!(page::_BrowserPage, obj, name::Symbol)
    haskey(page.bindings, name) && return page.bindings[name]
    T = typeof(obj)
    m = getproperty(obj, _browser_property(name))
    m isa BrowserModule || throw(ArgumentError(string(
        "`@browser(", name, ")` on ", T, " must be a `browser_module(file, entry)`, got ",
        typeof(m))))
    params = Set{Symbol}(Base.invokelatest(_param_names, T))
    inputs = Any[]
    for (input, type) in m.inputs
        sym = Symbol(input)
        if sym in params
            push!(inputs, Dict{String,Any}("name" => input, "type" => type, "param" => input,
                                           "default" => _browser_param_default(obj, sym)))
            continue
        end
        _browser_is_property(T, sym) || throw(ArgumentError(string(
            "the browser module for `", name, "` on ", T, " takes `", input, "`, which is ",
            "neither a `@param` nor a property of ", T, "; the page passes each argument ",
            "by its name")))
        found = _operation_reads(T, sym)
        changing = sort!(Symbol[n for n in found.names if n in params])
        (isempty(changing) && found.complete) || throw(ArgumentError(string(
            "the browser module for `", name, "` on ", T, " takes `", input, "`, which ",
            isempty(changing) ? "may read the page's inputs" :
                string("reads the input", length(changing) > 1 ? "s " : " ",
                       join((string("`", c, "`") for c in changing), ", ")),
            "; the page can pass a `@param` or fixed data, so compute it in the module")))
        push!(inputs, Dict{String,Any}("name" => input, "type" => type,
                                       "value" => _browser_data(getproperty(obj, sym), input)))
    end
    id = string(page.id, "-browser-", name)
    module_id = get!(page.modules, m.source) do
        string(page.id, "-browser-module-", length(page.modules) + 1)
    end
    page.bindings[name] = id
    page.payloads[id] = Dict{String,Any}("property" => string(name), "module" => module_id,
                                         "entry" => m.entry, "inputs" => inputs)
    id
end

_browser_is_property(T::Type, name::Symbol) = isdefined(DynamicObjects, :metafirst) &&
    Base.invokelatest(getproperty(DynamicObjects, :metafirst), T, name) !== nothing

# The bindings `ids` and their modules, as the elements the page has not
# written yet: the first region that refers to one carries it.
function _browser_scripts!(page::_BrowserPage, ids)
    nodes = Any[]
    for id in ids
        id in page.written && continue
        push!(page.written, id)
        binding = page.payloads[id]
        module_id = binding["module"]
        if !(module_id in page.written)
            push!(page.written, module_id)
            source = only(s for (s, i) in page.modules if i == module_id)
            push!(nodes, h.script(Raw(source); type="text/plain", id=module_id,
                                  data_htmxo_browser_module=""))
        end
        push!(nodes, h.script(Raw(_browser_json(binding)); type="application/json", id=id,
                              data_htmxo_browser_binding=""))
    end
    nodes
end

# A module argument that is data, as JSON carries it. JSON has no Inf or NaN,
# and a reader's data may legitimately hold them (an unbounded limit is not a
# missing one), so a non-finite float travels as `{"$f": "Inf"}` and the
# runtime turns it back into the JavaScript number; -0.0 keeps its sign.
_browser_data(x::Bool, _) = x
_browser_data(x::Union{AbstractString,Symbol}, _) = string(x)
_browser_data(x::Real, _) = x
_browser_data(x::AbstractFloat, _) = isfinite(x) ? x :
    Dict("\$f" => isnan(x) ? "NaN" : x > 0 ? "Inf" : "-Inf")
_browser_data(x::AbstractVector, name) = Any[_browser_data(v, name) for v in x]
# A matrix is an array of its rows, `m[i][j]` holding Julia's `m[i+1, j+1]`,
# as a `ReactiveKernels.js_source` module takes it (RK decision `1r7ufgm`).
# One without rows keeps its column count, which an empty JSON array cannot
# carry: it travels as `{"$cols": n}`, and the runtime makes it
# `Object.assign([], {cols: n})`, as such a module reads it; `[]` is 0×0.
_browser_data(x::AbstractMatrix, name) = size(x, 1) == 0 && size(x, 2) > 0 ?
    Dict("\$cols" => size(x, 2)) :
    Any[Any[_browser_data(x[i, j], name) for j in axes(x, 2)] for i in axes(x, 1)]
_browser_data(x, name) = throw(ArgumentError(string(
    "the browser module argument `", name, "` is a ", typeof(x), "; the page passes numbers, ",
    "booleans, text, and vectors and matrices of them")))

# --- What a static export of a browser page cannot serve ---

# The markup of a result with the values it shows through `bound` taken out:
# the text of each bound value, everything inside an element that shows bound
# columns (a plot's data) or is a table of them (`render_table`), and a
# table's row count, which the page writes when it loads. What remains must
# not change with an input the browser computes from, or the static page would
# show it stale.
const _BOUND_SPAN = r"(<span data-htmxo-bound=\"[^\"]*\"[^>]*>)[^<]*(</span>)"
const _TABLE_COUNT = r"(<small data-htmxo-table-count=\"[^\"]*\"[^>]*>)[^<]*(</small>)"
const _BOUND_ELEMENT = r"data-htmxo-bound-(?:columns|table)="
function _browser_skeleton(html::AbstractString)
    s = replace(String(html), _BOUND_SPAN => s"\1\2", _TABLE_COUNT => s"\1\2")
    out = IOBuffer()
    i = firstindex(s)
    marker = _BOUND_ELEMENT
    while true
        j = findnext(marker, s, i)
        j === nothing && (write(out, SubString(s, i)); break)
        open_start = findprev('<', s, first(j))
        open_end = findnext('>', s, last(j))
        (open_start === nothing || open_end === nothing) && (write(out, SubString(s, i)); break)
        tag = match(r"^<([A-Za-z][A-Za-z0-9-]*)", SubString(s, open_start)).captures[1]
        write(out, SubString(s, i, open_end))
        close_at = _browser_closing(s, nextind(s, open_end), lowercase(tag))
        close_at === nothing && break
        i = close_at
    end
    String(take!(out))
end

# Where the element `tag` opened just before `i` closes (the index of its `</`),
# skipping script and style text; `nothing` when it never does.
function _browser_closing(s, i, tag)
    depth = 1
    while true
        j = findnext('<', s, i)
        j === nothing && return nothing
        rest = SubString(s, j)
        m = match(r"^<(/?)([A-Za-z][A-Za-z0-9-]*)", rest)
        if m === nothing
            i = nextind(s, j)
            continue
        end
        name = lowercase(m.captures[2])
        if m.captures[1] == "" && name in ("script", "style")
            k = findnext(Regex("</" * name * "\\s*>", "i"), s, j)
            k === nothing && return nothing
            i = nextind(s, last(k))
            continue
        end
        if name == tag
            depth += m.captures[1] == "/" ? -1 : 1
            depth == 0 && return j
        end
        i = nextind(s, j)
    end
end

# The probes of an input's value: changed values its route should accept.
_browser_probes(x::AbstractFloat) = isfinite(x) ?
    (x * 1.1 + 1e-3, x * 0.9 - 1e-3, x * 1.01, x * 0.99, x + 1, x - 1) : (0.0, 1.0, -1.0)
_browser_probes(x::Integer) = (x + 1, x - 1, x + 2)
_browser_probes(x::AbstractString) = (string(x, "x"), "")
_browser_probes(_) = ()

# Two renderings of one address can differ with no input changed: the
# definition of a linked glossary term carries an id that is new in every
# answer (`_TermWalk`), and a view may write an id or a time of its own. So a
# rendering with an input changed is compared piece by piece, leaving out the
# pieces that two renderings of the unchanged inputs differ in. A piece keeps
# such a value whole: a run between spaces, quotes, `<`, `>` and `=`, or one of
# those characters; the pieces joined are the skeleton again.
const _BROWSER_PIECE = r"[^\s\"'<>=]+|[\s\"'<>=]"
_browser_pieces(skeleton::String) =
    SubString{String}[m.match for m in eachmatch(_BROWSER_PIECE, skeleton)]

# The renderings of a result at its unchanged inputs: the pieces of the first
# and, for each, whether a later one differed there. Two that hold different
# numbers of pieces do not line up, so nothing compares with them: `unlike`
# is then the later one's pieces.
mutable struct _BrowserControl
    pieces::Vector{SubString{String}}
    varies::BitVector
    unlike::Union{Nothing,Vector{SubString{String}}}
end
_BrowserControl(skeleton::String) =
    (pieces = _browser_pieces(skeleton); _BrowserControl(pieces, falses(length(pieces)), nothing))

# One more rendering of the unchanged inputs; `nothing` (it did not render)
# teaches nothing.
_browser_learn!(control::_BrowserControl, ::Nothing) = control
function _browser_learn!(control::_BrowserControl, skeleton::String)
    pieces = _browser_pieces(skeleton)
    if length(pieces) != length(control.pieces)
        control.unlike = pieces
    else
        for i in eachindex(pieces)
            pieces[i] == control.pieces[i] || (control.varies[i] = true)
        end
    end
    control
end

# Whether `pieces` are the control's wherever its own renderings agree.
_browser_same(control::_BrowserControl, pieces) = length(pieces) == length(control.pieces) &&
    all(i -> control.varies[i] || pieces[i] == control.pieces[i], eachindex(pieces))

# How `changed`, the skeleton rendered with an input changed, compares with
# `skeleton`, the one of the unchanged inputs: `:same` when it differs only
# where two renderings of the unchanged inputs do (`again()` renders one more
# skeleton of them), `:changed` when it differs elsewhere, and `:unlike` when
# those renderings do not line up with each other. `ref` keeps the control for
# the result's other inputs.
function _browser_compare!(ref::Base.RefValue, skeleton::String, changed::String, again)
    made = ref[] === nothing
    made && (ref[] = _browser_learn!(_BrowserControl(skeleton), again()))
    control = ref[]::_BrowserControl
    pieces = _browser_pieces(changed)
    control.unlike === nothing || return :unlike
    _browser_same(control, pieces) && return :same
    # A place may differ only later (a clock): look once more before saying
    # the input changed it, unless the control was rendered just now.
    made && return :changed
    _browser_learn!(control, again())
    control.unlike === nothing || return :unlike
    _browser_same(control, pieces) ? :same : :changed
end

# For a message: the text of a skeleton from where its piece `i` and `other`'s
# first differ, with a little of what precedes it; `…` where the view goes on.
function _browser_excerpt(pieces, other, i)
    i > length(pieces) && return "the end of the view"
    piece = pieces[i]
    s = piece.string
    at = piece.offset + 1
    if i <= length(other)
        for (x, y) in zip(piece, other[i])
            x == y || break
            at += ncodeunits(x)
        end
    end
    at = thisind(s, min(at, lastindex(s)))
    lo, hi = at, at
    for _ in 1:40
        lo > firstindex(s) || break
        lo = prevind(s, lo)
    end
    for _ in 1:40
        hi < lastindex(s) || break
        hi = nextind(s, hi)
    end
    string(lo > firstindex(s) ? "…" : "", replace(s[lo:hi], r"\s+" => " "), hi < lastindex(s) ? "…" : "")
end

# Where `pieces` and `other` differ, as the text of each around that place:
# the first place where `varies` does not say that renderings differ anyway.
# Two that do not line up (`varies === nothing`) may differ in a value (an id)
# well ahead of where they part, so there the first place where one of the
# two is markup (a space, a quote, `<`, `>` or `=`) is preferred.
function _browser_difference(pieces, other, varies)
    n = min(length(pieces), length(other))
    differs(k) = pieces[k] != other[k]
    mark(p) = (c = first(p); isspace(c) || c in ('"', '\'', '<', '>', '='))
    i = varies === nothing ?
        something(findfirst(k -> differs(k) && (mark(pieces[k]) || mark(other[k])), 1:n),
                  findfirst(differs, 1:n), n + 1) :
        something(findfirst(k -> !varies[k] && differs(k), 1:n), n + 1)
    _browser_excerpt(pieces, other, i), _browser_excerpt(other, pieces, i)
end

# Under a static export, what in the view of `operation` changes with an input
# outside its bound values, which a static page would show stale. Each
# continuous input it is sent is changed in turn; finite inputs are views of
# their own.
function _browser_check!(page::_BrowserPage, obj, route, current, target, sent, operation, finite)
    render(values) = _browser_render(_semantic_follow_url(target, obj, route, values, sent))
    skeleton = _browser_skeleton(render(current).body)
    again() = (r = render(current); r.status == 200 && isempty(r.error) ? _browser_skeleton(r.body) : nothing)
    control = Ref{Union{Nothing,_BrowserControl}}(nothing)
    for param in route.params
        param.source === :path && continue
        name = param.name
        name in sent && !(name in finite) || continue
        value = get(current, name, nothing)
        tried = String[]
        checked = false
        for probe in _browser_probes(value)
            changed = copy(current)
            changed[name] = probe
            _semantic_unfollow!(changed, (name,))
            rendered = render(changed)
            if rendered.status != 200 || !isempty(rendered.error)
                push!(tried, string(repr(probe), " → HTTP ", rendered.status))
                continue
            end
            checked = true
            changed_skeleton = _browser_skeleton(rendered.body)
            changed_skeleton == skeleton && break
            verdict = _browser_compare!(control, skeleton, changed_skeleton, again)
            verdict === :same && break
            if verdict === :unlike
                once, later = _browser_difference(control[].pieces, control[].unlike, nothing)
                push!(page.problems, string(
                    "the export could not check the result `", operation, "`: with the same inputs ",
                    "its view reads `", once, "` one time and `", later, "` the next, which do not ",
                    "line up, so neither compares with the view of a changed input; write the same ",
                    "markup for the same inputs or leave `", operation,
                    "` out with `semantic_app(…; select=…)`"))
                return nothing
            end
            before, after = _browser_difference(control[].pieces, _browser_pieces(changed_skeleton), control[].varies)
            push!(page.problems, string(
                "the result `", operation, "` shows `", name, "` outside `bound`: its view ",
                "changes when `", name, "` does (`", before, "` becomes `", after, "` with `", name, "` = ",
                repr(probe), "), so a static page would show it stale; ",
                "show the value with `bound(...)` or leave `", operation,
                "` out with `semantic_app(…; select=…)`"))
            break
        end
        checked || push!(page.problems, string(
            "the export could not check the result `", operation, "` with `", name,
            "` changed (", isempty(tried) ? "no value to try" : join(tried, ", "), ")"))
    end
end

# Under a static export of a page with a browser region, what else on it needs
# the server: a result that reads inputs and computes nothing in the browser,
# and a control that the server draws again when other inputs change.
function _browser_server_parts!(page::_BrowserPage, specs, routes, follows, browser_regions, reads, complete)
    for (i, spec) in enumerate(specs)
        follows[i] && !browser_regions[i] || continue
        operation = spec.base_entry.name
        sent = sort!(collect(reads[i]))
        (isempty(sent) && complete[i]) && continue
        push!(page.problems, string(
            "the result `", operation, "` ", isempty(sent) ? "may read the page's inputs" :
                string("reads ", join((string("`", n, "`") for n in sent), ", ")),
            " but computes nothing in the browser, so a static page would show it stale; ",
            "declare `@browser` for what it shows or leave it out with `semantic_app(…; select=…)`"))
    end
    # What a page's controls can change: an `@options` domain that reads only
    # fixed fields and what is computed from them is the same while it is used.
    inputs = Set{Symbol}(param.name for route in routes for param in route.params
                         if param.source !== :path)
    seen = Set{Symbol}()
    for route in routes, param in route.params
        param.name in seen && continue
        push!(seen, param.name)
        get(param, :kind, nothing) === nothing && continue
        reasons = String[]
        domain = _semantic_domain_reads(param, inputs)
        isempty(domain) || push!(reasons, string(
            "its `@options` read ", join((string("`", n, "`") for n in domain), ", ")))
        relevance = get(param, :relevance, nothing)
        isnothing(relevance) || isempty(relevance.dependencies) || push!(reasons,
            "its `@relevant` condition is not one the browser evaluates (comparisons and arithmetic of `@param`s)")
        help = get(param, :help, nothing)
        isnothing(help) || isempty(help.dependencies) || push!(reasons, "its `@help` text reads other inputs")
        defaulted = get(param, :default_reads, nothing)
        isnothing(defaulted) || isempty(defaulted) || push!(reasons, string(
            "its default reads ", join((string("`", n, "`") for n in defaulted), ", ")))
        isempty(reasons) && continue
        push!(page.problems, string("the server draws the control of `", param.name,
            "` again when other inputs change (", join(reasons, "; "),
            "), which a static page cannot"))
    end
end

# Hand the problems to the export: `export_site` lists them as this page's
# failure; any other static render fails with them.
function _browser_report!(page::_BrowserPage)
    isempty(page.problems) && return nothing
    spec = page.static
    if spec isa StaticExport && spec.url_map isa _SiteMap
        log = spec.url_map.log
        lock(() -> append!(log.problems, page.problems), log.lock)
        return nothing
    end
    throw(ArgumentError(string("semantic_app: this page computes results in the browser, ",
        "but a static export of it would show some stale:\n  ", join(unique(page.problems), "\n  "))))
end

"""
    semantic_browser_script()

The runtime of the results a `semantic_app` page computes in the browser
(`@browser`): it loads each property's module once, calls it with the page's
inputs, shows the view of the finite inputs' values and writes the bound
values into it, numbers as `format_number` writes them and values with
`labels` as the texts they name, and the rows of each `render_table` of bound
columns. [`semantic_follow_script`](@ref) calls it on each `input`
event of an input the result reads, at most once an animation frame, so the
result moves with a slider held down. A page that has such a result carries
it in that result; nothing to add by hand.
"""
semantic_browser_script() = h.script(Raw(raw"""
(function() {
  if (window.__htmxoSemanticBrowser) return;
  window.__htmxoSemanticBrowser = true;
  var style = document.createElement('style');
  style.textContent = '.htmxo-browser-view[data-htmxo-stale]{opacity:.45}' +
    '.htmxo-browser-fault{color:var(--pico-del-color,#c62828)}';
  document.head.appendChild(style);
  var has = function(o, k) { return Object.prototype.hasOwnProperty.call(o, k); };
  // Each module once per page, from the text the page embeds.
  var modules = new Map();
  function moduleOf(id) {
    var found = modules.get(id);
    if (found) return found;
    var el = document.getElementById(id);
    if (!el) return Promise.reject(new Error('the page has no browser module ' + id));
    found = import(URL.createObjectURL(new Blob([el.textContent], {type: 'text/javascript'})));
    modules.set(id, found);
    return found;
  }
  function parsed(el) {
    return el.__htmxoParsed || (el.__htmxoParsed = JSON.parse(el.textContent));
  }
  function bindingOf(id) {
    var el = document.getElementById(id);
    if (!el) throw new Error('the page has no browser binding ' + id);
    return parsed(el);
  }
  // A module argument from the wire strings a control sends, by its Julia type.
  // Julia writes non-finite floats `Inf`, `-Inf` and `NaN`.
  var NONFINITE = {'Inf': Infinity, '+Inf': Infinity, '-Inf': -Infinity, 'NaN': NaN,
                   'Infinity': Infinity, '+Infinity': Infinity, '-Infinity': -Infinity};
  function scalar(type, s) {
    if (/^(Float16|Float32|Float64|AbstractFloat|Real|Number|U?Int(8|16|32|64|128)?|Integer)$/.test(type))
      return s === '' ? NaN : has(NONFINITE, s) ? NONFINITE[s] : Number(s);
    if (type === 'Bool') return s === 'true';
    return s;
  }
  // Embedded data: a non-finite float arrives as `{"$f": "Inf"}` (JSON has none),
  // a matrix as its rows, and one without rows as `{"$cols": n}`: the empty
  // array that keeps its column count as `cols`, as a module reads it.
  function decoded(v) {
    if (Array.isArray(v)) return v.map(decoded);
    if (v !== null && typeof v === 'object' && has(v, '$f')) return NONFINITE[v.$f];
    if (v !== null && typeof v === 'object' && has(v, '$cols')) return Object.assign([], {cols: v.$cols});
    return v;
  }
  function argument(input, values) {
    if (has(input, 'value')) return decoded(input.value);
    var given = values[input.param];
    var strings = given && given.length ? given : (input['default'] || []);
    var vector = /^(?:Abstract)?Vector\{(.+)\}$/.exec(input.type);
    if (vector) return strings.filter(function(s) { return s !== ''; })
      .map(function(s) { return scalar(vector[1], s); });
    return scalar(input.type, strings.length ? strings[0] : '');
  }
  // `bound(x.field[i])`: the path's parts after its root, indices 1-based.
  function at(value, path) {
    for (var i = 1; i < path.length; i++) {
      if (value === null || value === undefined) return undefined;
      var k = path[i];
      value = typeof k === 'number' ? value[k - 1] : value[k];
    }
    return value;
  }
  // Julia's `string(::Float64)`: the exact value a number cell sorts by and
  // the ⬇ CSV writes (`_number_key`).
  function juliaFloat(x) {
    if (x !== x) return 'NaN';
    if (x === Infinity) return 'Inf';
    if (x === -Infinity) return '-Inf';
    if (x === 0) return 1 / x < 0 ? '-0.0' : '0.0';
    var m = /^(-?)(\d)(?:\.(\d+))?e([+-]\d+)$/.exec(x.toExponential());
    var sign = m[1], digits = m[2] + (m[3] || ''), e = Number(m[4]);
    if (e > -5 && e < 6) {
      if (e < 0) return sign + '0.' + '0'.repeat(-e - 1) + digits;
      var whole = digits.length > e + 1 ? digits.slice(0, e + 1) : digits + '0'.repeat(e + 1 - digits.length);
      return sign + whole + '.' + (digits.slice(e + 1) || '0');
    }
    return sign + digits[0] + '.' + (digits.slice(1) || '0') + 'e' + e;
  }
  window.__htmxoJuliaFloat = juliaFloat;
  function numberKey(x, integer) {
    if (integer) return String(x);
    return x === Infinity ? 'Infinity' : x === -Infinity ? '-Infinity' : juliaFloat(x);
  }
  // A number from the module, or from a control's wire text.
  function number(value) {
    return typeof value === 'number' ? value : has(NONFINITE, value) ? NONFINITE[value] : Number(value);
  }
  // `_label_text`: the text a value's labels name (`bound(x; labels)`,
  // `ColumnSpec(…; labels)`), read as the value's `kind` (a number key names
  // the same number, a Bool key a Bool, a text key the same text); null for
  // no value (null, NaN); for a value they do not name, the server's
  // `ArgumentError`, which the region shows as it shows a module's error.
  function labelText(value, kind, labels) {
    var v, shown;
    if (value === null) return null;
    if (kind === 'bool') {
      v = value === true || value === 'true';
      shown = String(v);
    } else if (kind === 'int' || kind === 'float') {
      v = value === null ? null : number(value);
      if (v === null || v !== v) return null;
      shown = kind === 'int' && Number.isInteger(v) ? String(v) : juliaFloat(v);
    } else {
      if (value === null) return null;
      v = String(value);
      shown = JSON.stringify(v);
    }
    for (var i = 0; i < labels.pairs.length; i++) {
      var k = labels.pairs[i][0];
      if (k && typeof k === 'object' && k.infinite) k = k.infinite * Infinity;
      if (typeof k === typeof v && k === v) return labels.pairs[i][1];
    }
    if (labels.numeric && typeof v === 'number') return undefined;
    var error = new Error(labels.what + ': ' + shown + ' is not a value its labels name (' + labels.named + ')');
    error.name = 'ArgumentError';
    throw error;
  }
  // A bound value as the server wrote it (`_bound_text`): a number as
  // `format_number` writes it, with the span's rounding, percent and language,
  // NaN as no value (`–`); with `date`, the day as `format_date` writes it;
  // with `labels`, the text they name.
  function text(value, kind, format) {
    var numeric = kind === 'float' || kind === 'int';
    if (value === undefined) return null;
    if (format.labels) {
      var label = labelText(value, kind, format.labels);
      if (label !== undefined) return label === null ? '–' : label;
    }
    if (format.date) return htmxoDateText(value === null ? null : number(value), format.date);
    if (value === null && !numeric) return null;
    if (kind === 'bool') return String(value === true || value === 'true');
    if (numeric) {
      var x = value === null ? null : number(value);
      return htmxoNumberText(x !== x ? null : x, format, kind === 'int') +
        (format.unit && x !== null && x === x ? '\u00a0' + format.unit : '');
    }
    return String(value);
  }
  function formatOf(el) {
    return el.__htmxoFormat || (el.__htmxoFormat = JSON.parse(el.getAttribute('data-htmxo-format') || '{}'));
  }
  // A cell of a bound table as `render_table` writes it (`_render_table_cell`):
  // a number cell (its value the sort value and the ⬇ CSV's) for a float, or
  // for any number of a column whose `ColumnSpec` says how its numbers are
  // written; in a column of days (`ColumnSpec(…; date)`, `_date_cell`) the
  // day, sorted by its number, its ISO day the ⬇ CSV's; in a column of labels
  // (`ColumnSpec(…; labels)`, `_label_cell`) the label, sorted by the value;
  // an empty number cell for no value (NaN too, and no day); else the value's text.
  function boundCell(v, c, texts) {
    var td = document.createElement('td'), integer = c.kind === 'int';
    var formatted = c.digits !== undefined || c.sigdigits !== undefined || c.percent;
    var label = c.labels && v !== undefined ? labelText(v, c.kind, c.labels) : null;
    if (label !== null && label !== undefined) {
      td.setAttribute('data-sort-value', c.kind === 'bool' ? (v === true || v === 'true' ? '1' : '0') :
        c.kind === 'int' || c.kind === 'float' ? numberKey(number(v), integer) : String(v));
      td.textContent = label;
      if (c.align) td.setAttribute('data-htmxo-align', c.align);
      return td;
    }
    var x = c.date && v !== null && v !== undefined ? number(v) : v;
    var day = c.date ? htmxoDateKey(x) : null;
    if (v === null || v === undefined || (typeof v === 'number' && v !== v) || (c.date && day === null)) {
      td.setAttribute('data-htmxo-number', '');
      if (c.empty) td.setAttribute('data-htmxo-align', c.empty);
      td.textContent = '–';
    } else if (c.date) {
      td.setAttribute('data-sort-value', numberKey(x, integer));
      td.setAttribute('data-htmxo-number', day);
      td.textContent = htmxoDateText(x, c.date);
    } else if (typeof v === 'number' && (c.kind === 'float' || (integer && formatted))) {
      var key = numberKey(v, integer);
      td.setAttribute('data-sort-value', key);
      td.setAttribute('data-htmxo-number', key);
      td.textContent = htmxoNumberText(v, {digits: c.digits, sigdigits: c.sigdigits, percent: c.percent, texts: texts}, integer);
    } else td.textContent = String(v);
    if (c.align && !td.hasAttribute('data-htmxo-align')) td.setAttribute('data-htmxo-align', c.align);
    return td;
  }
  // One column of `bound(x; columns)`: a single value (a number, a Boolean,
  // text) is the table's one row.
  function boundColumn(value) {
    var single = value !== undefined && typeof value !== 'object';
    return single ? [value] : Array.from(value);
  }
  // `render_table(bound(x; columns))`: its rows written again from the new
  // columns, then the reader's sort, search and hover links applied to them.
  function boundTable(table, results) {
    var spec = table.__htmxoBound || (table.__htmxoBound = JSON.parse(table.getAttribute('data-htmxo-bound-table')));
    if (!has(results, spec.path[0])) return;
    var data = at(results[spec.path[0]], spec.path);
    if (data === null || data === undefined) return;
    var columns = spec.columns.map(function(c) { return boundColumn(data[c.name]); });
    var n = columns.reduce(function(m, c) { return Math.max(m, c.length); }, 0);
    var keyed = spec.columns.findIndex(function(c) { return c.name === spec.link_key; });
    var texts = htmxoTexts(table), rows = [];
    for (var i = 0; i < n; i++) {
      var tr = document.createElement('tr');
      spec.columns.forEach(function(c, j) { tr.appendChild(boundCell(columns[j][i], c, texts)); });
      // As AlgebraOfVega keys a plot's marks by the same column (`_link_key_text`).
      if (keyed >= 0) tr.setAttribute('data-htmxo-link-key', String(columns[keyed][i]));
      rows.push(tr);
    }
    var body = table.tBodies[0];
    body.replaceChildren.apply(body, rows);
    // A numeric result can become words: size label columns for their new
    // text before holding their widths through sorting and searching again.
    if (spec.columns.some(function(c) { return c.labels; }) && typeof htmxoColumnsMeasure === 'function')
      htmxoColumnsMeasure(table, true);
    if (typeof htmxoResort === 'function') htmxoResort(table);
    if (typeof htmxoFilterTable === 'function' && table.closest('.htmxo-searchable-table')) htmxoFilterTable(table);
    if (typeof htmxoLinkApply === 'function' && table.dataset.htmxoLink) htmxoLinkApply(table, false);
  }
  // Writes every bound value and table it can; a value its labels do not
  // name keeps its old text (a table its old rows), and the first such error
  // is thrown once the rest is written, for the region to show.
  function patch(view, results, values, defaults) {
    var failed = null;
    view.querySelectorAll('[data-htmxo-bound]').forEach(function(el) {
      var path = JSON.parse(el.getAttribute('data-htmxo-bound')), root = path[0], value, shown;
      if (has(results, root)) value = at(results[root], path);
      else {
        var wire = values[root] && values[root].length ? values[root] : defaults[root];
        value = wire && wire.length ? wire[0] : undefined;
      }
      try { shown = text(value, el.getAttribute('data-htmxo-kind'), formatOf(el)); }
      catch (error) { failed = failed || error; return; }
      if (shown !== null && el.textContent !== shown) el.textContent = shown;
    });
    view.querySelectorAll('table[data-htmxo-bound-table]').forEach(function(table) {
      try { boundTable(table, results); } catch (error) { failed = failed || error; }
    });
    view.querySelectorAll('[data-htmxo-bound-columns]').forEach(function(el) {
      var spec = JSON.parse(el.getAttribute('data-htmxo-bound-columns'));
      if (!has(results, spec.path[0])) return;
      var table = at(results[spec.path[0]], spec.path), columns = {}, n = 0;
      spec.columns.forEach(function(c) {
        var column = boundColumn(table[c]);
        columns[c] = column;
        n = column.length;
      });
      if (el.id && window.AoV && typeof window.AoV.updateData === 'function')
        window.AoV.updateData(el.id, {n: n, columns: columns}, spec.dataset);
      el.dispatchEvent(new CustomEvent('htmxo:bound-columns',
        {bubbles: true, detail: {path: spec.path, columns: columns, n: n}}));
    });
    if (failed) throw failed;
  }
  function sameKey(a, b) {
    var ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && ka.every(function(k) { return a[k] === b[k]; });
  }
  // The view rendered for the finite inputs' current values; the shown one
  // is replaced by its template when they change.
  function viewFor(region, values, inputs) {
    var key = {};
    inputs.names.forEach(function(name) {
      var wire = values[name] && values[name].length ? values[name] : inputs.defaults[name];
      key[name] = wire && wire.length ? wire[0] : '';
    });
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (!view || sameKey(JSON.parse(view.getAttribute('data-htmxo-variant')), key)) return view;
    var template = Array.prototype.find.call(region.querySelectorAll(':scope > template[data-htmxo-variant]'),
      function(t) { return sameKey(JSON.parse(t.getAttribute('data-htmxo-variant')), key); });
    if (!template) return null;
    view.setAttribute('data-htmxo-variant', template.getAttribute('data-htmxo-variant'));
    if (window.htmx && typeof window.htmx.swap === 'function')
      window.htmx.swap(view, template.innerHTML, {swapStyle: 'innerHTML'});
    else view.innerHTML = template.innerHTML;
    return view;
  }
  function fault(region, error) {
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (view) view.setAttribute('data-htmxo-stale', '');
    var note = region.querySelector(':scope > .htmxo-browser-fault');
    if (!note) {
      note = document.createElement('p');
      note.className = 'htmxo-browser-fault';
      note.setAttribute('role', 'alert');
      region.insertBefore(note, region.firstChild);
    }
    note.textContent = (error && error.name ? error.name + ': ' : '') +
      (error && error.message !== undefined ? error.message : String(error));
  }
  function clear(region) {
    var view = region.querySelector(':scope > .htmxo-browser-view');
    if (view) view.removeAttribute('data-htmxo-stale');
    var note = region.querySelector(':scope > .htmxo-browser-fault');
    if (note) note.remove();
  }
  var latest = new WeakMap();
  // Called by `semantic_follow_script` in place of a request, with the values
  // the region's request would carry. The newest call wins.
  window.__htmxoBrowserCompute = function(region, pairs) {
    var token = {};
    latest.set(region, token);
    var values = {};
    pairs.forEach(function(p) { (values[p[0]] = values[p[0]] || []).push(p[1]); });
    var inputs = JSON.parse(region.getAttribute('data-htmxo-browser-inputs') || '{"names":[],"defaults":{}}');
    var results = {};
    var work = (region.getAttribute('data-htmxo-browser') || '').split(' ').filter(Boolean).map(function(id) {
      var binding = bindingOf(id);
      return moduleOf(binding.module).then(function(mod) {
        var f = mod[binding.entry];
        if (typeof f !== 'function') throw new Error('the browser module exports no function ' + binding.entry);
        return f.apply(null, binding.inputs.map(function(i) { return argument(i, values); }));
      }).then(function(value) { results[binding.property] = value; });
    });
    return Promise.all(work).then(function() {
      if (latest.get(region) !== token) return;
      var view = viewFor(region, values, inputs);
      if (!view) throw new Error('no view of this result was rendered for these values');
      patch(view, results, values, inputs.defaults);
      clear(region);
      region.dispatchEvent(new CustomEvent('htmxo:browser-computed', {bubbles: true, detail: {results: results}}));
    }).catch(function(error) {
      if (latest.get(region) !== token) return;
      fault(region, error);
      if (window.console) console.error(error);
    });
  };
})();
"""))
