# Julia documentation is parsed data, not a CommonMark string. Normalize only
# this explicit input form, then use the same prose projections as authored text.
function SemanticProse(doc::Markdown.MD; references::AbstractDict=Dict{String,String}(),
                       math::Bool=true)
    SemanticProse(string(_documentation_node(doc, references)); math)
end

# Every changed container is fresh. Leaves and metadata may be shared, but are
# never written: Base.Docs can return the same document to several consumers.
_documentation_node(x, references) = x
_documentation_node(xs::AbstractVector, references) =
    map(x -> _documentation_node(x, references), xs)
_documentation_node(doc::Markdown.MD, references) =
    Markdown.MD(_documentation_node(doc.content, references), copy(doc.meta))
_documentation_node(x::Union{Markdown.Paragraph,Markdown.BlockQuote}, references) =
    typeof(x)(_documentation_node(x.content, references))
_documentation_node(x::Union{Markdown.Bold,Markdown.Italic,Markdown.Header}, references) =
    typeof(x)(_documentation_node(x.text, references))
_documentation_node(x::Markdown.List, references) =
    Markdown.List(_documentation_node(x.items, references), x.ordered, x.loose)
_documentation_node(x::Markdown.Admonition, references) =
    Markdown.Admonition(x.category, x.title, _documentation_node(x.content, references))
_documentation_node(x::Markdown.Footnote, references) =
    Markdown.Footnote(x.id, _documentation_node(x.text, references))
_documentation_node(x::Markdown.Table, references) =
    Markdown.Table(_documentation_node(x.rows, references), copy(x.align))
_documentation_node(x::Markdown.Code, references) =
    Markdown.Code(_is_jldoctest(x.language) ? "julia" : x.language, x.code)

function _documentation_node(link::Markdown.Link, references)
    label = _documentation_node(link.text, references)
    ref = match(r"^@ref(?:\s+(.*))?$"s, strip(link.url))
    isnothing(ref) && return Markdown.Link(label, link.url)
    name = isnothing(ref[1]) ? _documentation_label(link.text) : _documentation_target(ref[1])
    destination = get(references, strip(name), nothing)
    isnothing(destination) && return label
    destination isa AbstractString && !isempty(strip(destination)) &&
        !occursin(r"^@ref(?:\s|$)", strip(destination)) ||
        throw(ArgumentError("documentation reference $(repr(name)) needs a nonempty destination URL, not an @ref"))
    Markdown.Link(label, String(destination))
end

_documentation_label(x::AbstractString) = x
_documentation_label(xs::AbstractVector) = join(_documentation_label(x) for x in xs)
_documentation_label(x::Markdown.Code) = x.code
_documentation_label(x::Union{Markdown.Bold,Markdown.Italic}) = _documentation_label(x.text)
_documentation_label(::Markdown.LineBreak) = " "
_documentation_label(x) = sprint(show, MIME"text/plain"(), x)

function _documentation_target(target)
    name = strip(target)
    # Documenter accepts a quoted heading or backticked binding as well as the
    # legacy unquoted name. These are labels: never parse/evaluate Julia here.
    quoted = match(r"^(?:\"(.*)\"|(`+)(.*?)\2)$"s, name)
    isnothing(quoted) ? name : something(quoted[1], quoted[3])
end

# A doctest's info string may carry a name and options. Its contents include
# expected output, but its syntax grammar is Julia, not a Prism component named
# jldoctest. Keep authored string Markdown intact; alias only its HTML language.
_is_jldoctest(info) = occursin(r"^jldoctest(?:[;\s]|$)", lowercase(strip(String(info))))
function _syntax_language(info)
    text = strip(String(info))
    isempty(text) && return ""
    _is_jldoctest(text) ? "julia" : lowercase(first(split(text)))
end
