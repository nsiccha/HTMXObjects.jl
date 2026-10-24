# --- Python service: a FastAPI package generated from an app's OpenAPI document ---
#
# `python_service(T, dir; …)` writes a standalone Python package serving the
# operations `openapi(T)` describes (user decision `1iheds0`): pydantic models
# from `components.schemas`, one FastAPI endpoint per operation, and a
# `Backend` class with one method per operation that computes the answers. The
# document is the single source: the package ships it as `openapi.json`, serves
# it verbatim, and its contract test checks that the generated code still
# matches it. The `OpenAPIRoutes`/`SwaggerRoutes` mounts become FastAPI's own
# document and Swagger page at the same paths.

const _PY_WIDTH = 79       # PEP 8 line length
const _PY_DOC_WIDTH = 72   # PEP 8 docstring and comment length

const _PY_LICENSES = ("GPL-3.0-or-later", "GPL-3.0-only", "MIT")
const _PY_GPL_TEXT = joinpath(dirname(@__DIR__), "assets", "licenses", "GPL-3.0.txt")

const _PY_KEYWORDS = Set(["False", "None", "True", "and", "as", "assert", "async",
    "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
    "finally", "for", "from", "global", "if", "import", "in", "is", "lambda",
    "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with",
    "yield"])

# `BaseModel` attributes a field must not shadow (besides the `model_` prefix).
const _PY_MODEL_ATTRIBUTES = Set(["construct", "copy", "dict", "from_orm", "json",
    "parse_file", "parse_obj", "parse_raw", "schema", "schema_json",
    "update_forward_refs", "validate"])

# Names the generated modules import or define themselves.
const _PY_MODULE_NAMES = Set(["Any", "Annotated", "BaseModel", "ConfigDict", "Field",
    "Literal", "date", "datetime", "Backend", "CallerFault", "FastAPI", "Form",
    "JSONResponse", "Path", "Query", "Request"])

# Locals of `create_app` an endpoint function must not shadow.
const _PY_APP_LOCALS = Set(["app", "backend", "shipped", "served_document",
    "caller_fault", "unimplemented"])

const _PY_METHOD_ORDER = ("get", "post", "put", "patch", "delete")

# Where each name of a type expression is imported from.
const _PY_TYPE_IMPORTS = Dict("Annotated" => "typing", "Any" => "typing",
                              "Literal" => "typing", "date" => "datetime",
                              "datetime" => "datetime")
const _PY_BUILTIN_TYPES = Set(["list", "dict", "str", "int", "float", "bool", "None"])

# The model classes among the names a file's types use.
_py_model_names(names) =
    sort!([n for n in names if !haskey(_PY_TYPE_IMPORTS, n) && !(n in _PY_BUILTIN_TYPES)])

# --- Reading the document ---
#
# `openapi` mixes NamedTuples (Symbol keys, declared order) and Dicts (String
# keys); these read either by its string key.
_pyget(x::NamedTuple, key::AbstractString, default=nothing) = get(x, Symbol(key), default)
_pyget(x::AbstractDict, key::AbstractString, default=nothing) = get(x, key, default)
_pyentries(x::NamedTuple) = [(String(k), v) for (k, v) in pairs(x)]
_pyentries(x::AbstractDict) = sort!([(String(k), v) for (k, v) in x]; by=first)

# --- Python source: expressions laid out within the line length ---
#
# Generated code is PEP 8 by construction: an expression is written on one
# line when it fits, otherwise broken inside its brackets, one item per line.

# A string literal, split into implicitly concatenated pieces when too long.
struct _PyStr
    text::String
end

# A type expression: a name (`str`, `ApiHour`), a subscript (`list[…]`,
# `Literal[…]`) or, with `union`, the alternatives `A | B`. A `Literal`'s
# arguments are source text.
struct _PyType
    head::String
    args::Vector{Any}
    union::Bool
end
_pyname(head) = _PyType(head, Any[], false)
_pysub(head, args...) = _PyType(head, Any[args...], false)
function _pyunion(alternatives)
    flat = Any[]
    for t in alternatives
        t isa _PyType && t.union ? append!(flat, t.args) : push!(flat, t)
    end
    unique!(_py_one, flat)
    # `None` last, as written by hand.
    sort!(flat; by=t -> _py_one(t) == "None")
    length(flat) == 1 ? only(flat) : _PyType("|", flat, true)
end

# A call `head(args…)`; an argument with an empty key is positional.
struct _PyCall
    head::String
    args::Vector{Pair{String,Any}}
end

# A keyword argument inside a broken call.
struct _PyKw
    key::String
    value::Any
end

function _py_escape(s::AbstractString)
    io = IOBuffer()
    for c in s
        if c == '\\'
            print(io, "\\\\")
        elseif c == '"'
            print(io, "\\\"")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif iscntrl(c) || c in ('\u2028', '\u2029')
            print(io, "\\u", string(UInt32(c); base=16, pad=4))
        else
            print(io, c)
        end
    end
    String(take!(io))
end
_py_literal(s::AbstractString) = "\"" * _py_escape(s) * "\""

# `text` as string literals of at most `width` characters each, broken after
# spaces and newlines where it can be.
function _py_str_chunks(text::AbstractString, width::Integer)
    room = max(width - 2, 8)
    chunks, current = String[], ""
    flush!() = (isempty(current) || push!(chunks, _py_literal(current)); current = "")
    for word in eachmatch(r"[^ \n]*[ \n]*", text)
        piece = word.match
        isempty(piece) && continue
        if length(_py_escape(current * piece)) <= room
            current *= piece
            continue
        end
        flush!()
        while length(_py_escape(piece)) > room
            cut = 0
            for (i, c) in enumerate(piece)
                length(_py_escape(first(piece, i))) > room && break
                cut = i
            end
            current = first(piece, cut)
            flush!()
            piece = chop(piece; head=cut, tail=0)
        end
        current = piece
    end
    flush!()
    isempty(chunks) ? [_py_literal("")] : chunks
end

_py_one(x::AbstractString) = x
_py_one(x::_PyStr) = _py_literal(x.text)
_py_one(x::_PyKw) = x.key * "=" * _py_one(x.value)
function _py_one(x::_PyType)
    x.union && return join(map(_py_one, x.args), " | ")
    isempty(x.args) ? x.head : x.head * "[" * join(map(_py_one, x.args), ", ") * "]"
end
_py_one(x::_PyCall) = x.head * "(" * join(map(_py_one, _py_call_items(x)), ", ") * ")"
_py_call_items(x::_PyCall) = Any[isempty(k) ? v : _PyKw(k, v) for (k, v) in x.args]

# `x` as source lines: the first continues a line with `avail` characters left
# (`tail` more follow `x` on its last line); later lines carry their own
# indentation, based on the statement's `indent`.
function _py_lines(x, indent::Integer, avail::Integer, tail::Integer=0)
    one = _py_one(x)
    length(one) + tail <= avail ? [one] : _py_break(x, indent, tail)
end

_py_break(x::AbstractString, indent, tail) = [x]
function _py_break(x::_PyStr, indent, tail)
    pad = " "^(indent + 4)
    ["("; [pad * c for c in _py_str_chunks(x.text, _PY_WIDTH - indent - 4)]; " "^indent * ")"]
end
function _py_break(x::_PyKw, indent, tail)
    lines = _py_lines(x.value, indent, _PY_WIDTH - indent - length(x.key) - 1, tail)
    lines[1] = x.key * "=" * lines[1]
    lines
end
function _py_break(x::_PyType, indent, tail)
    isempty(x.args) && return [_py_one(x)]
    x.union ? _py_block("(", ")", x.args, indent; separator="| ") :
              _py_block(x.head * "[", "]", x.args, indent)
end
_py_break(x::_PyCall, indent, tail) = _py_block(x.head * "(", ")", _py_call_items(x), indent)

function _py_block(open, close, items, indent; separator="")
    pad = indent + 4
    lines = [open]
    for (i, item) in enumerate(items)
        prefix = i > 1 ? separator : ""
        suffix = isempty(separator) ? "," : ""
        sub = _py_lines(item, pad, _PY_WIDTH - pad - length(prefix), length(suffix))
        sub[1] = " "^pad * prefix * sub[1]
        sub[end] *= suffix
        append!(lines, sub)
    end
    push!(lines, " "^indent * close)
    lines
end

# Append `x` to the last of `lines`, which is indented by `indent`.
function _py_append!(lines, x, indent; tail=0)
    sub = _py_lines(x, indent, _PY_WIDTH - length(lines[end]), tail)
    lines[end] *= sub[1]
    append!(lines, sub[2:end])
    lines
end

# A docstring at `indent`: wrapped at word boundaries, keeping the text's own
# lines and list indentation. Text with a word too long to wrap is written as
# concatenated literals instead, so no line exceeds the limit.
function _py_docstring(text::AbstractString, indent::Integer)
    body = strip(replace(text, "\\" => "\\\\", "\"\"\"" => "\\\"\\\"\\\""))
    endswith(body, "\"") && (body = chop(body) * "\\\"")
    pad = " "^indent
    one = pad * "\"\"\"" * body * "\"\"\""
    !occursin('\n', body) && length(one) <= _PY_WIDTH && return [one]
    wrapped = String[]
    for line in _py_reflow(body)
        append!(wrapped, _py_wrap_line(line, _PY_DOC_WIDTH - indent))
    end
    lines = [pad * "\"\"\"" * wrapped[1]; [isempty(l) ? "" : pad * l for l in wrapped[2:end]];
             pad * "\"\"\""]
    all(l -> length(l) <= _PY_WIDTH, lines) && return lines
    sub = _py_lines(_PyStr(text), indent, _PY_WIDTH - indent)
    [pad * sub[1]; sub[2:end]]
end

# Markdown `text` as logical lines: a paragraph's (or list item's) soft line
# breaks are joined, so it can be wrapped anew; blank lines, headings, quotes,
# tables and code keep their lines.
function _py_reflow(text::AbstractString)
    lines = String[]
    fenced, joinable = false, false
    for line in split(text, '\n')
        if startswith(lstrip(line), "```")
            fenced = !fenced
            push!(lines, line)
            joinable = false
        elseif fenced || isempty(strip(line)) || occursin(r"^(?: {4}|\t)", line) ||
               occursin(r"^\s*(?:#|>|\|)", line)
            push!(lines, line)
            joinable = false
        elseif !joinable || occursin(r"^\s*[-*+] ", line) ||
               # Inside a paragraph only `1.` starts an ordered list (CommonMark).
               occursin(r"^\s*1[.)] ", line)
            push!(lines, line)
            joinable = true
        else
            lines[end] = rstrip(lines[end]) * " " * strip(line)
        end
    end
    lines
end

function _py_wrap_line(line::AbstractString, width::Integer)
    length(line) <= width && return [rstrip(line)]
    lead = match(r"^\s*(?:[-*+] |\d+[.)] )?", line).match
    hang = " "^length(lead)
    out, current = String[], ""
    for word in split(line[nextind(line, 0, length(lead) + 1):end], ' '; keepempty=false)
        candidate = isempty(current) ? word : current * " " * word
        if !isempty(current) && length((isempty(out) ? lead : hang) * candidate) > width
            push!(out, (isempty(out) ? lead : hang) * current)
            current = word
        else
            current = candidate
        end
    end
    push!(out, (isempty(out) ? lead : hang) * current)
    out
end

# Python source of a JSON value (a parameter default).
_py_value(x::Nothing) = "None"
_py_value(x::Bool) = x ? "True" : "False"
_py_value(x::Integer) = string(x)
_py_value(x::AbstractFloat) = isnan(x) ? "float(\"nan\")" : isinf(x) ?
    (x > 0 ? "float(\"inf\")" : "-float(\"inf\")") : repr(Float64(x))
_py_value(x::AbstractString) = _py_literal(x)
_py_value(x::Symbol) = _py_literal(string(x))
_py_value(x::AbstractVector) = "[" * join(map(_py_value, x), ", ") * "]"
_py_value(x::NamedTuple) = "{" * join([_py_literal(string(k)) * ": " * _py_value(v) for (k, v) in pairs(x)], ", ") * "}"
_py_value(x::AbstractDict) = "{" * join([_py_literal(string(k)) * ": " * _py_value(v) for (k, v) in _pyentries(x)], ", ") * "}"

# --- Names ---

function _py_unique(base::AbstractString, taken)
    name, n = String(base), 1
    while name in taken
        n += 1
        name = base * "_" * string(n)
    end
    push!(taken, name)
    name
end

# `ApiHour`, `Main.JRAlarm_Int64` → `MainJRAlarmInt64`: PEP 8 CapWords.
function _py_capwords(name::AbstractString)
    parts = split(replace(name, r"[^A-Za-z0-9]+" => " "), ' '; keepempty=false)
    word = join(uppercasefirst.(parts))
    (isempty(word) || isdigit(first(word))) ? "Model" * word : word
end

function _py_class_name!(taken, raw::AbstractString)
    name = _py_capwords(raw)
    (name in _PY_KEYWORDS || name in _PY_MODULE_NAMES) && (name *= "Model")
    _py_unique(name, taken)
end

# A Python name for a JSON field or parameter; `alias` is the wire name when
# the two differ (a keyword, a non-ASCII or otherwise invalid identifier, or
# a name pydantic reserves).
function _py_member_name!(taken, wire::AbstractString; reserved=Set{String}())
    base = replace(wire, r"[^A-Za-z0-9_]" => "_")
    base = lstrip(base, '_')
    (isempty(base) || isdigit(first(base))) && (base = "field_" * base)
    (base in _PY_KEYWORDS || base in reserved || startswith(base, "model_")) && (base *= "_")
    name = _py_unique(base, taken)
    (name, name == wire ? nothing : String(wire))
end

function _py_function_name!(taken, operation_id::AbstractString)
    base = replace(operation_id, r"[^A-Za-z0-9_]" => "_")
    (isempty(base) || isdigit(first(base))) && (base = "operation_" * base)
    (base in _PY_KEYWORDS || base in _PY_APP_LOCALS || base in _PY_MODULE_NAMES) && (base *= "_")
    _py_unique(base, taken)
end

# --- JSON Schema → Python types ---
#
# `openapi` describes types with a small, fixed JSON-Schema vocabulary
# (`_openapi_type_schema`, `_openapi_response_schema`): `$ref`, objects with
# `properties`, maps (`additionalProperties`), arrays, string enums, nullable
# unions (`type` lists or `anyOf` with `null`), `date`/`date-time` strings and
# the empty schema (any value). Each is mapped here; anything else is refused.

struct _PyField
    name::String
    alias::Union{Nothing,String}
    type::_PyType
    required::Bool
    description::Union{Nothing,String}
end

struct _PyClass
    name::String
    description::Union{Nothing,String}
    fields::Vector{_PyField}
end

struct _PyContext
    components::Any
    component_classes::Dict{String,String}
    classes::Vector{_PyClass}       # in dependency order
    taken::Set{String}
end
_PyContext(components) = _PyContext(components, Dict{String,String}(), _PyClass[],
                                    Set{String}(_PY_MODULE_NAMES))

function _py_type(c::_PyContext, schema, hint::AbstractString)
    ref = _pyget(schema, "\$ref")
    ref !== nothing && return _pyname(_py_component_class!(c, ref))
    any_of = _pyget(schema, "anyOf")
    any_of !== nothing && return _pyunion([_py_type(c, s, hint) for s in any_of])
    t = _pyget(schema, "type")
    t === nothing && return _pyname("Any")
    t isa AbstractVector && return _pyunion([_py_type_of(c, schema, String(x), hint) for x in t])
    _py_type_of(c, schema, String(t), hint)
end

function _py_type_of(c::_PyContext, schema, t::AbstractString, hint)
    t == "null" && return _pyname("None")
    t == "boolean" && return _pyname("bool")
    t == "integer" && return _pyname("int")
    t == "number" && return _pyname("float")
    if t == "string"
        values = _pyget(schema, "enum")
        values !== nothing && return _PyType("Literal", Any[_py_literal(string(v)) for v in values], false)
        format = _pyget(schema, "format")
        format == "date-time" && return _pyname("datetime")
        format == "date" && return _pyname("date")
        return _pyname("str")
    end
    if t == "array"
        items = _pyget(schema, "items")
        return _pysub("list", items === nothing ? _pyname("Any") : _py_type(c, items, hint * "Item"))
    end
    if t == "object"
        _pyget(schema, "properties") !== nothing &&
            return _pyname(_py_class!(c, _py_class_name!(c.taken, hint), schema))
        values = _pyget(schema, "additionalProperties")
        return _pysub("dict", _pyname("str"),
                      values === nothing ? _pyname("Any") : _py_type(c, values, hint * "Value"))
    end
    throw(ArgumentError("python_service: no Python type for the JSON-schema type \"$t\""))
end

function _py_component_class!(c::_PyContext, ref::AbstractString)
    prefix = "#/components/schemas/"
    startswith(ref, prefix) ||
        throw(ArgumentError("python_service: cannot resolve the reference \"$ref\""))
    key = ref[length(prefix) + 1:end]
    name = get(c.component_classes, key, nothing)
    name === nothing || return name
    name = _py_class_name!(c.taken, key)
    # Named before it is built, so a recursive type refers to itself.
    c.component_classes[key] = name
    _py_class!(c, name, _pyget(c.components, key))
end

# Build the class `name` for an object schema; classes its fields need are
# built first, so `c.classes` lists dependencies before their users.
function _py_class!(c::_PyContext, name::AbstractString, schema)
    required = Set(String.(something(_pyget(schema, "required"), String[])))
    taken = Set{String}()
    fields = map(_pyentries(_pyget(schema, "properties"))) do (wire, field)
        pyname, alias = _py_member_name!(taken, wire; reserved=_PY_MODEL_ATTRIBUTES)
        T = _py_type(c, field, name * _py_capwords(wire))
        isrequired = wire in required
        isrequired || (T = _pyunion([T, _pyname("None")]))
        _PyField(pyname, alias, T, isrequired, _pyget(field, "description"))
    end
    push!(c.classes, _PyClass(name, _pyget(schema, "description"), fields))
    name
end

# --- Operations ---

struct _PyParam
    name::String
    alias::Union{Nothing,String}
    marker::String               # "Path", "Query" or "Form"
    type::_PyType
    default::Union{Nothing,String}   # Python source; `nothing` = required
    description::Union{Nothing,String}
end

struct _PyOperation
    path::String
    method::String
    operation_id::String
    name::String
    summary::Union{Nothing,String}
    description::Union{Nothing,String}
    response_description::Union{Nothing,String}
    params::Vector{_PyParam}
    returns::_PyType
end

function _py_param(c::_PyContext, taken, wire, schema, marker, required, hint)
    name, alias = _py_member_name!(taken, wire)
    T = _py_type(c, schema, hint * _py_capwords(wire))
    default = _pyget(schema, "default")
    source = if required
        nothing
    elseif default === nothing
        T = _pyunion([T, _pyname("None")])
        "None"
    else
        _py_value(default)
    end
    _PyParam(name, alias, marker, T, source, _pyget(schema, "description"))
end

function _py_operation(c::_PyContext, functions, path, method, op)
    name = _py_function_name!(functions, _pyget(op, "operationId"))
    hint = _py_capwords(name)
    taken = Set{String}()
    params = _PyParam[]
    for p in something(_pyget(op, "parameters"), [])
        marker = _pyget(p, "in") == "path" ? "Path" : "Query"
        push!(params, _py_param(c, taken, _pyget(p, "name"), _pyget(p, "schema"), marker,
                                _pyget(p, "required"), hint))
    end
    body = _pyget(op, "requestBody")
    if body !== nothing
        for (media, content) in _pyentries(_pyget(body, "content"))
            media == "application/x-www-form-urlencoded" ||
                throw(ArgumentError("python_service: no form for request bodies of type $media"))
            schema = _pyget(content, "schema")
            required = Set(String.(something(_pyget(schema, "required"), String[])))
            for (wire, s) in _pyentries(_pyget(schema, "properties"))
                push!(params, _py_param(c, taken, wire, s, "Form", wire in required, hint))
            end
        end
    end
    ok = _pyget(_pyget(op, "responses"), "200")
    content = _pyget(ok, "content")
    json = content === nothing ? nothing : _pyget(content, "application/json")
    returns = json === nothing ? _pyname("Any") :
        _py_type(c, _pyget(json, "schema"), hint * "Response")
    _PyOperation(path, method, _pyget(op, "operationId"), name, _pyget(op, "summary"),
                 _pyget(op, "description"), _pyget(ok, "description"), params, returns)
end

# The paths `T` serves its own document and Swagger page at: an
# `OpenAPIRoutes` or `SwaggerRoutes` mount, else FastAPI's defaults when no
# operation uses them.
function _py_document_urls(::Type{T}, paths) where {T}
    mounts = Any[]
    hasmethod(DynamicObjects.meta, Tuple{Type{T}}) &&
        _reflect_walk!(mounts, T, ""; enrich=(owner, route, _parents) -> (owner, route))
    function url(type, default)
        mounted = [r.path for (o, r) in mounts if o <: type]
        isempty(mounted) || return first(mounted)
        default in paths ? nothing : default
    end
    url(OpenAPIRoutes, "/openapi.json"), url(SwaggerRoutes, "/docs")
end

# --- The files ---

function _py_header(license, copyright)
    lines = ["# SPDX-License-Identifier: " * license, "# Copyright (C) " * copyright]
    if license == "MIT"
        push!(lines, "#", "# Licensed under the MIT License; see LICENSE.")
    else
        later = license == "GPL-3.0-or-later"
        append!(lines, [
            "#",
            "# This program is free software: you can redistribute it and/or modify it",
            "# under the terms of the GNU General Public License as published by the Free",
            later ? "# Software Foundation, either version 3 of the License, or (at your option)" :
                    "# Software Foundation, version 3 of the License.",
            ])
        later && push!(lines, "# any later version.")
        append!(lines, [
            "#",
            "# This program is distributed in the hope that it will be useful, but WITHOUT",
            "# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or",
            "# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for",
            "# more details.",
            "#",
            "# You should have received a copy of the GNU General Public License along",
            "# with this program. If not, see <https://www.gnu.org/licenses/>.",
            ])
    end
    push!(lines, "#", "# Generated by HTMXObjects.python_service from the app's OpenAPI document;",
          "# regenerate it instead of editing this file.")
    lines
end

# Names a type expression uses, for the imports of the file it appears in.
_py_names!(acc, t) = acc
function _py_names!(acc, t::_PyType)
    t.union || push!(acc, t.head)
    foreach(a -> _py_names!(acc, a), t.args)
    acc
end

function _py_import_lines(_from::AbstractString, names)
    isempty(names) && return String[]
    names = sort!(collect(names))
    one = "from " * _from * " import " * join(names, ", ")
    length(one) <= _PY_WIDTH && return [one]
    ["from " * _from * " import ("; ["    " * n * "," for n in names]; ")"]
end

function _py_type_imports(names)
    lines = String[]
    for mod in ("datetime", "typing")
        append!(lines, _py_import_lines(mod, [n for n in names if get(_PY_TYPE_IMPORTS, n, "") == mod]))
    end
    lines
end

_py_type_names(types) = foldl(_py_names!, types; init=Set{String}())

function _py_models_file(c::_PyContext, header, title)
    names = _py_type_names(f.type for cls in c.classes for f in cls.fields)
    aliased = any(f -> f.alias !== nothing, (f for cls in c.classes for f in cls.fields))
    lines = [header; ""; _py_docstring("Response models of " * title * ".", 0)]
    push!(lines, "", "from __future__ import annotations", "")
    std = _py_type_imports(names)
    isempty(std) || append!(lines, [std; ""])
    append!(lines, _py_import_lines("pydantic", aliased ? ["BaseModel", "ConfigDict", "Field"] :
                                                          ["BaseModel", "Field"]))
    classes = Set(cls.name for cls in c.classes)
    defined, rebuild = Set{String}(), String[]
    for cls in c.classes
        push!(lines, "", "", "class " * cls.name * "(BaseModel):")
        body = String[]
        cls.description === nothing || append!(body, _py_docstring(cls.description, 4))
        if any(f -> f.alias !== nothing, cls.fields)
            isempty(body) || push!(body, "")
            push!(body, "    model_config = ConfigDict(populate_by_name=True)")
        end
        isempty(body) || isempty(cls.fields) || push!(body, "")
        foreach(f -> append!(body, _py_field_lines(f)), cls.fields)
        append!(lines, isempty(body) ? ["    pass"] : body)
        push!(defined, cls.name)
        # A class naming one defined further down resolves it once all exist.
        later = setdiff(intersect(_py_type_names(f.type for f in cls.fields), classes), defined)
        isempty(later) || push!(rebuild, cls.name)
    end
    isempty(rebuild) || append!(lines, vcat("", "", [n * ".model_rebuild()" for n in rebuild]))
    lines
end

function _py_field_lines(f::_PyField)
    args = Pair{String,Any}[]
    f.required || push!(args, "default" => "None")
    f.alias === nothing || push!(args, "alias" => _PyStr(f.alias))
    f.description === nothing || push!(args, "description" => _PyStr(f.description))
    lines = ["    " * f.name * ": "]
    isempty(args) && return _py_append!(lines, f.type, 4)
    _py_append!(lines, f.type, 4; tail=length(" = Field("))
    lines[end] *= " = "
    _py_append!(lines, _PyCall("Field", args), 4)
end

# `def <name>(…) -> <returns>:` at `indent`, with keyword-only `params`
# (name, type, default source) after `self` when `method`.
function _py_def_lines(name, params, returns, indent; method=false)
    head = " "^indent * "def " * name * "("
    lead = method ? ["self"] : String[]
    isempty(params) || push!(lead, "*")
    one_params = [n * ": " * _py_one(t) * (d === nothing ? "" : " = " * d) for (n, t, d) in params]
    one = head * join([lead; one_params], ", ") * ") -> "
    if length(one) + length(_py_one(returns)) + 1 <= _PY_WIDTH
        lines = [one]
    else
        lines = [head]
        foreach(l -> push!(lines, " "^(indent + 4) * l * ","), lead)
        for (n, t, d) in params
            sub = [" "^(indent + 4) * n * ": "]
            _py_append!(sub, t, indent + 4; tail=d === nothing ? 1 : length(d) + 4)
            sub[end] *= (d === nothing ? "" : " = " * d) * ","
            append!(lines, sub)
        end
        push!(lines, " "^indent * ") -> ")
    end
    _py_append!(lines, returns, indent; tail=1)
    lines[end] *= ":"
    lines
end

function _py_annotated(p::_PyParam)
    args = Pair{String,Any}[]
    p.alias === nothing || push!(args, "alias" => _PyStr(p.alias))
    p.description === nothing || push!(args, "description" => _PyStr(p.description))
    _PyType("Annotated", Any[p.type, _PyCall(p.marker, args)], false)
end

_py_operation_types(ops) = [t for op in ops for t in [op.returns; [p.type for p in op.params]]]

function _py_app_file(ops, header, title, version, openapi_url, docs_url, env)
    names = _py_type_names(_py_operation_types(ops))
    push!(names, "Any")
    isempty(ops) || all(op -> isempty(op.params), ops) || push!(names, "Annotated")
    markers = Set(p.marker for op in ops for p in op.params)
    lines = [header; ""; _py_docstring("FastAPI app of " * title * " " * version * ".", 0)]
    push!(lines, "", "import json", "from importlib import resources")
    append!(lines, _py_type_imports(names))
    push!(lines, "")
    append!(lines, _py_import_lines("fastapi", union(Set(["FastAPI", "Request"]), markers)))
    push!(lines, "from fastapi.responses import JSONResponse", "")
    append!(lines, _py_import_lines(".backend", ["Backend", "CallerFault", "load_backend"]))
    append!(lines, _py_import_lines(".models", _py_model_names(names)))
    url(u) = u === nothing ? "None" : _py_literal(u)
    push!(lines, "", "OPENAPI_URL = " * url(openapi_url), "DOCS_URL = " * url(docs_url), "", "")
    push!(lines, "def document() -> dict[str, Any]:")
    append!(lines, _py_docstring("The OpenAPI document the service was generated from.", 4))
    push!(lines, "    text = resources.files(__package__).joinpath(\"openapi.json\")",
          "    return json.loads(text.read_text(encoding=\"utf-8\"))", "", "")
    push!(lines, "def create_app(backend: Backend | None = None) -> FastAPI:")
    append!(lines, _py_docstring("""
        The service, answering through `backend`.

        Without a backend, the one the environment variable `$env` names
        (`module:object`) is loaded; without that, every operation answers
        501. The app serves its OpenAPI document as generated, at
        `OPENAPI_URL`.""", 4))
    push!(lines, "    if backend is None:", "        backend = load_backend()", "    app = ")
    _py_append!(lines, _PyCall("FastAPI", Pair{String,Any}[
        "title" => _PyStr(title), "version" => _PyStr(version),
        "openapi_url" => "OPENAPI_URL", "docs_url" => "DOCS_URL", "redoc_url" => "None"]), 4)
    append!(lines, [
        "    shipped = document()",
        "",
        "    def served_document() -> dict[str, Any]:",
        "        return shipped",
        "",
        "    app.openapi = served_document",
        "",
        "    @app.exception_handler(CallerFault)",
        "    async def caller_fault(",
        "        request: Request, fault: CallerFault",
        "    ) -> JSONResponse:",
        "        return JSONResponse({\"detail\": fault.message}, fault.status)",
        "",
        "    @app.exception_handler(NotImplementedError)",
        "    async def unimplemented(",
        "        request: Request, error: NotImplementedError",
        "    ) -> JSONResponse:",
        "        return JSONResponse({\"detail\": str(error)}, 501)",
        ])
    for op in ops
        args = Pair{String,Any}["" => _PyStr(op.path), "operation_id" => _PyStr(op.operation_id)]
        op.summary === nothing || push!(args, "summary" => _PyStr(op.summary))
        op.description === nothing || push!(args, "description" => _PyStr(op.description))
        op.response_description === nothing ||
            push!(args, "response_description" => _PyStr(op.response_description))
        push!(lines, "", "    @")
        _py_append!(lines, _PyCall("app." * op.method, args), 4)
        append!(lines, _py_def_lines(op.name, [(p.name, _py_annotated(p), p.default) for p in op.params],
                                     op.returns, 4))
        push!(lines, "        return ")
        _py_append!(lines, _PyCall("backend." * op.name,
                                   Pair{String,Any}[p.name => p.name for p in op.params]), 8)
    end
    push!(lines, "", "    return app")
    lines
end

function _py_backend_file(ops, header, title, env)
    names = _py_type_names(_py_operation_types(ops))
    lines = [header; ""; _py_docstring("The backend of " * title * ": one method per operation.", 0)]
    push!(lines, "", "import importlib", "import os")
    append!(lines, _py_type_imports(names))
    models = _py_model_names(names)
    isempty(models) || append!(lines, [""; _py_import_lines(".models", models)])
    push!(lines, "", "ENVIRONMENT_VARIABLE = " * _py_literal(env), "", "")
    push!(lines, "class CallerFault(Exception):")
    append!(lines, _py_docstring("A request the caller got wrong, answered with `status`.", 4))
    append!(lines, [
        "",
        "    def __init__(self, status: int, message: str) -> None:",
        "        super().__init__(message)",
        "        self.status = status",
        "        self.message = message",
        "",
        "",
        "def unimplemented(name: str) -> NotImplementedError:",
        ])
    append!(lines, _py_docstring("The error of an operation no backend implements (501).", 4))
    append!(lines, [
        "    return NotImplementedError(",
        "        f\"The backend does not implement {name}; set \"",
        "        f\"{ENVIRONMENT_VARIABLE} to module:object naming one that does.\"",
        "    )",
        "",
        "",
        "class Backend:",
        ])
    append!(lines, _py_docstring("""
        Computes the answer of each operation of the service.

        Subclass it and override the methods of the operations you serve;
        the others answer 501. A method returns its declared type: model
        instances, or dicts and lists that validate against them.""", 4))
    for op in ops
        push!(lines, "")
        append!(lines, _py_def_lines(op.name, [(p.name, p.type, p.default) for p in op.params],
                                     op.returns, 4; method=true))
        append!(lines, _py_docstring(something(op.summary, "The answer of `" * op.operation_id * "`."), 8))
        push!(lines, "        raise ")
        _py_append!(lines, _PyCall("unimplemented", Pair{String,Any}["" => _PyStr(op.name)]), 8)
    end
    push!(lines, "", "", "def load_backend() -> Backend:")
    append!(lines, _py_docstring("""
        The backend `$env` names, as `module:object`.

        A class is instantiated; any other object is used as it is. Without
        the variable, every operation answers 501.""", 4))
    append!(lines, [
        "    spec = os.environ.get(ENVIRONMENT_VARIABLE, \"\")",
        "    if not spec:",
        "        return Backend()",
        "    module_name, _, attribute = spec.partition(\":\")",
        "    if not attribute:",
        "        raise ValueError(",
        "            f\"{ENVIRONMENT_VARIABLE} must read module:object, not {spec!r}.\"",
        "        )",
        "    target = getattr(importlib.import_module(module_name), attribute)",
        "    return target() if isinstance(target, type) else target",
        ])
    lines
end

# The generated contract test: FastAPI's own description of the generated
# code, compared with the shipped document after normalizing what FastAPI
# adds or spells differently (titles, descriptions, `422` responses,
# `anyOf` with `null`, `additionalProperties: true`, `items: {}`, `$ref`s).
function _py_contract_test(header, package)
    lines = [header; ""; _py_docstring("Contract test: the generated code matches the document it serves.", 0)]
    append!(lines, [
        "",
        "from fastapi.openapi.utils import get_openapi",
        "from fastapi.testclient import TestClient",
        "",
        "from $package.app import DOCS_URL, OPENAPI_URL, create_app, document",
        "",
        "SKIPPED = {OPENAPI_URL, DOCS_URL}",
        "",
        "",
        "def canonical(schema, components, seen=()):",
        ])
    append!(lines, _py_docstring("`schema` with its references inlined, in a comparable form.", 4))
    append!(lines, [
        "    if isinstance(schema, list):",
        "        return [canonical(item, components, seen) for item in schema]",
        "    if not isinstance(schema, dict):",
        "        return schema",
        "    ref = schema.get(\"\$ref\")",
        "    if ref is not None:",
        "        name = ref.rsplit(\"/\", 1)[-1]",
        "        if name in seen:",
        "            return {\"recursive\": True}",
        "        return canonical(components[name], components, seen + (name,))",
        "    out = {}",
        "    for key, value in schema.items():",
        "        if key in (\"title\", \"description\"):",
        "            continue",
        "        if key == \"properties\":",
        "            value = {",
        "                k: canonical(v, components, seen) for k, v in value.items()",
        "            }",
        "        elif key == \"required\":",
        "            value = sorted(value)",
        "        else:",
        "            value = canonical(value, components, seen)",
        "        out[key] = value",
        "    if out.get(\"required\") == []:",
        "        del out[\"required\"]",
        "    if out.get(\"additionalProperties\") is True:",
        "        del out[\"additionalProperties\"]",
        "    if out.get(\"items\") == {}:",
        "        del out[\"items\"]",
        "    alternatives = out.pop(\"anyOf\", None)",
        "    if alternatives is not None:",
        "        others = [a for a in alternatives if a != {\"type\": \"null\"}]",
        "        if len(others) == 1 and len(others) < len(alternatives):",
        "            merged = dict(others[0])",
        "            kind = merged.get(\"type\", [])",
        "            kind = kind if isinstance(kind, list) else [kind]",
        "            merged[\"type\"] = kind + [\"null\"]",
        "            out.update(merged)",
        "        else:",
        "            out[\"anyOf\"] = alternatives",
        "    if isinstance(out.get(\"type\"), list):",
        "        out[\"type\"] = sorted(set(out[\"type\"]))",
        "    return out",
        "",
        "",
        "def operations(doc):",
        ])
    append!(lines, _py_docstring("Each operation of `doc`, in the form `canonical` compares.", 4))
    append!(lines, [
        "    components = doc.get(\"components\", {}).get(\"schemas\", {})",
        "    found = {}",
        "    for path, item in doc[\"paths\"].items():",
        "        if path in SKIPPED:",
        "            continue",
        "        for method, operation in item.items():",
        "            parameters = {",
        "                (p[\"in\"], p[\"name\"]): (",
        "                    p.get(\"required\", False),",
        "                    canonical(p[\"schema\"], components),",
        "                )",
        "                for p in operation.get(\"parameters\", [])",
        "            }",
        "            body = operation.get(\"requestBody\")",
        "            if body is not None:",
        "                body = {",
        "                    media: canonical(content[\"schema\"], components)",
        "                    for media, content in body[\"content\"].items()",
        "                }",
        "            ok = operation[\"responses\"][\"200\"].get(\"content\", {})",
        "            schema = ok.get(\"application/json\", {}).get(\"schema\", {})",
        "            found[(path, method)] = {",
        "                \"operationId\": operation[\"operationId\"],",
        "                \"parameters\": parameters,",
        "                \"requestBody\": body,",
        "                \"response\": canonical(schema, components),",
        "            }",
        "    return found",
        "",
        "",
        "def test_code_matches_document():",
        "    app = create_app()",
        "    generated = get_openapi(",
        "        title=app.title, version=app.version, routes=app.routes",
        "    )",
        "    assert operations(generated) == operations(document())",
        "",
        "",
        "def test_document_is_served():",
        "    if OPENAPI_URL is not None:",
        "        client = TestClient(create_app())",
        "        assert client.get(OPENAPI_URL).json() == document()",
        ])
    lines
end

_toml_string(s) = "\"" * _py_escape(s) * "\""

function _py_pyproject(package, distribution, title, version, license, forms)
    dependencies = ["fastapi>=0.115", "pydantic>=2.7", "uvicorn>=0.30"]
    forms && push!(dependencies, "python-multipart>=0.0.9")
    lines = [
        "# SPDX-License-Identifier: " * license,
        "# Generated by HTMXObjects.python_service; regenerate it instead of editing.",
        "",
        "[build-system]",
        "requires = [\"setuptools>=77\"]",
        "build-backend = \"setuptools.build_meta\"",
        "",
        "[project]",
        "name = " * _toml_string(distribution),
        "version = " * _toml_string(version),
        "description = " * _toml_string(title),
        "readme = \"README.md\"",
        "license = " * _toml_string(license),
        "license-files = [\"LICENSE\"]",
        "requires-python = \">=3.10\"",
        "dependencies = [",
        ["    " * _toml_string(d) * "," for d in dependencies]...,
        "]",
        "",
        "[project.optional-dependencies]",
        "test = [\"httpx>=0.27\", \"pycodestyle>=2.11\", \"pytest>=8\"]",
        "",
        "[tool.setuptools]",
        "packages = [" * _toml_string(package) * "]",
        "",
        "[tool.setuptools.package-data]",
        package * " = [\"openapi.json\"]",
        ]
    lines
end

function _py_dockerfile(package, license, python)
    [
        "# SPDX-License-Identifier: " * license,
        "# Generated by HTMXObjects.python_service; regenerate it instead of editing.",
        "FROM python:" * python * "-slim",
        "COPY pyproject.toml README.md LICENSE /tmp/service/",
        "COPY " * package * " /tmp/service/" * package,
        "# The copies keep the build host's file modes; the installed package runs,",
        "# readable by the unprivileged user.",
        "RUN chmod -R a+rX /tmp/service \\",
        "    && pip install --no-cache-dir /tmp/service \\",
        "    && rm -rf /tmp/service \\",
        "    && useradd --create-home --uid 10001 service",
        "USER service",
        "WORKDIR /home/service",
        "EXPOSE 8000",
        "CMD [\"uvicorn\", \"--factory\", \"" * package * ".app:create_app\", \"--host\", \"0.0.0.0\", \"--port\", \"8000\"]",
    ]
end

function _py_readme(title, version, package, distribution, env, license, copyright, ops, openapi_url, docs_url)
    licensed = license == "MIT" ? "the MIT License" :
        license == "GPL-3.0-only" ? "the GNU General Public License, version 3" :
        "the GNU General Public License, version 3 or (at your option) any later version"
    rows = ["| `$(uppercase(op.method)) $(op.path)` | `$(op.name)` | " *
            replace(something(op.summary, ""), "|" => "\\|") * " |" for op in ops]
    [
        "<!-- SPDX-License-Identifier: $license -->",
        "<!-- Generated by HTMXObjects.python_service; regenerate it instead of editing. -->",
        "",
        "# $title",
        "",
        "A FastAPI service for version $version of the interface, generated from its OpenAPI",
        "document (`$package/openapi.json`" *
            (openapi_url === nothing ? "" : ", served at `$openapi_url`") *
            (docs_url === nothing ? ")." : ", with a Swagger page at `$docs_url`)."),
        "",
        "## Run it",
        "",
        "```sh",
        "pip install .",
        "uvicorn --factory $package.app:create_app",
        "```",
        "",
        "or in a container:",
        "",
        "```sh",
        "docker build -t $distribution .",
        "docker run -p 8000:8000 $distribution",
        "```",
        "",
        "## Plug in a backend",
        "",
        "Each operation calls the method of the same name on a backend object. Subclass",
        "`$package.backend.Backend`, override the methods of the operations you serve (the",
        "others answer 501), and name your class in `$env` as `module:object`:",
        "",
        "```sh",
        "$env=my_models:Models uvicorn --factory $package.app:create_app",
        "```",
        "",
        "In a container, install the module into an image built on this one and set",
        "`$env` there. A method returns its declared type: model instances from",
        "`$package.models`, or dicts and lists that validate against them. Raise",
        "`$package.backend.CallerFault(status, message)` to answer the caller with an error.",
        "Tests and other Python code can pass a backend directly: `create_app(Models())`.",
        "",
        "| Operation | Method | Summary |",
        "|---|---|---|",
        rows...,
        "",
        "## Test it",
        "",
        "```sh",
        "pip install '.[test]'",
        "pycodestyle $package tests",
        "pytest",
        "```",
        "",
        "`tests/test_contract.py` checks that the code still matches `openapi.json`.",
        "",
        "## License",
        "",
        "Copyright (C) $copyright. Licensed under $licensed; see `LICENSE`.",
    ]
end

function _py_license_text(license, copyright)
    license == "MIT" || return read(_PY_GPL_TEXT, String)
    """
    MIT License

    Copyright (c) $copyright

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
end

"""
    python_service(T::Type, dir; package, copyright, license="GPL-3.0-or-later",
                   title="", version="1.0.0", description=nothing, servers=[],
                   python="3.12") -> Vector{String}

Write a standalone Python service for the JSON routes of the `@htmx` app type
`T` into the directory `dir`: a FastAPI app with pydantic models, generated from
[`openapi`](@ref)`(T; title, version, description, servers)`. Returns the paths
it wrote. It rewrites only those files.

```julia
python_service(ApiV1, "odl-service"; package = "odl_service",
               copyright = "2026 Jane Doe", title = "ODL API", version = "1.4.0")
```

- `<package>/models.py`: one pydantic model per struct the document describes
  (`components.schemas`, a `JSONResponse{T}` route's `T`), with field
  docstrings as `Field(description=…)` and nullable fields as `X | None`. A
  `NamedTuple` type becomes a model named after where it appears.
- `<package>/app.py`: `create_app(backend=None)`, one endpoint per operation of
  the document with its path, `operationId`, summary and description. Path
  and query parameters keep their types, defaults and descriptions, form
  parameters become `Form(…)`, and a route's `JSONResponse{T}` becomes its
  return type. A route without one answers any JSON. The app serves the
  shipped document as it is, at the path where `T` mounts
  [`OpenAPIRoutes`](@ref) (else `/openapi.json`), with Swagger UI where `T`
  mounts [`SwaggerRoutes`](@ref) (else `/docs`); those mounts' own
  operations are left to FastAPI.
- `<package>/backend.py`: `class Backend`, one keyword-only method per
  operation with the endpoint's typed parameters. Every method of the base
  class raises `NotImplementedError`, which the app answers with `501`.
  A subclass overrides the methods it serves. `load_backend()` reads
  `<PACKAGE>_BACKEND=module:object` (instantiating a class), else returns the
  base class. `CallerFault(status, message)` answers the caller with `status`
  and `{"detail": message}`.
- `<package>/openapi.json`, `pyproject.toml`, `Dockerfile` (`python:<python>-slim`,
  uvicorn on port 8000), `.dockerignore`, `README.md` and `LICENSE` (the full
  license text).
- `tests/test_contract.py`: checks with pytest that FastAPI's description of
  the generated code matches the shipped document (paths, `operationId`s,
  parameters, request bodies and response schemas).

Every Python file starts with the license notice for `license`
(`"GPL-3.0-or-later"`, `"GPL-3.0-only"` or `"MIT"`) and `Copyright (C)
<copyright>`. The code is PEP 8: lines of at most 79 characters, broken inside
brackets.

`package` must be a lowercase Python identifier; the distribution name is the
same with `-` for `_`. Choose `T` as the root of the JSON interface: every
operation `openapi(T)` lists is served, so a page route under it would become
an endpoint answering JSON. `@ws` and `@sse` routes are left out, as in
`openapi`.
"""
function python_service(T::Type, dir::AbstractString; package::AbstractString,
        copyright::AbstractString, license::AbstractString="GPL-3.0-or-later",
        title::AbstractString="", version::AbstractString="1.0.0",
        description=nothing, servers=[], python::AbstractString="3.12")
    occursin(r"^[a-z_][a-z0-9_]*$", package) && !(package in _PY_KEYWORDS) ||
        throw(ArgumentError("python_service: package must be a lowercase Python identifier, not \"$package\""))
    license in _PY_LICENSES ||
        throw(ArgumentError("python_service: license must be one of $(join(_PY_LICENSES, ", ")), not \"$license\""))
    isempty(strip(copyright)) &&
        throw(ArgumentError("python_service: copyright names the holder, e.g. \"2026 Jane Doe\""))
    doc = openapi(T; title, version, description, servers)
    paths = Set(keys(doc.paths))
    openapi_url, docs_url = _py_document_urls(T, paths)
    c = _PyContext(haskey(doc, :components) ? doc.components.schemas : Dict{String,Any}())
    functions = Set{String}()
    ops = _PyOperation[]
    for path in sort!(collect(paths))
        path in (openapi_url, docs_url) && continue
        item = doc.paths[path]
        for method in _PY_METHOD_ORDER
            op = get(item, method, nothing)
            op === nothing || push!(ops, _py_operation(c, functions, path, method, op))
        end
    end
    # Components no operation reached still become models.
    for name in sort!(collect(keys(c.components)))
        _py_component_class!(c, "#/components/schemas/" * name)
    end
    distribution = replace(package, '_' => '-')
    env = uppercase(package) * "_BACKEND"
    header = _py_header(license, copyright)
    name = doc.info.title
    forms = any(p -> p.marker == "Form", (p for op in ops for p in op.params))
    files = [
        joinpath(package, "__init__.py") => [header; ""; _py_docstring(name * " " * version * ", a generated FastAPI service.", 0)],
        joinpath(package, "models.py") => _py_models_file(c, header, name),
        joinpath(package, "backend.py") => _py_backend_file(ops, header, name, env),
        joinpath(package, "app.py") => _py_app_file(ops, header, name, version, openapi_url, docs_url, env),
        joinpath("tests", "test_contract.py") => _py_contract_test(header, package),
        "pyproject.toml" => _py_pyproject(package, distribution, name, version, license, forms),
        "Dockerfile" => _py_dockerfile(package, license, python),
        ".dockerignore" => ["tests", "**/__pycache__"],
        "README.md" => _py_readme(name, version, package, distribution, env, license, copyright,
                                  ops, openapi_url, docs_url),
    ]
    written = String[]
    for (relative, lines) in files
        path = joinpath(dir, relative)
        mkpath(dirname(path))
        write(path, join(lines, '\n') * '\n')
        push!(written, path)
    end
    path = joinpath(dir, package, "openapi.json")
    write(path, _schema_json_encode(doc) * '\n')
    push!(written, path)
    path = joinpath(dir, "LICENSE")
    write(path, _py_license_text(license, copyright))
    push!(written, path)
    written
end
