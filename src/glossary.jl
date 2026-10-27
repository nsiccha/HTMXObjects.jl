# --- Glossary: an app's terms, declared once, linked wherever they are used ---
#
# An app declares its technical terms once, as a `Glossary` on its root
# (`__glossary__`). Every answer under that root then links the uses of its
# terms to their entries (`link_terms`, run by `_resolve_response`), a sortable
# column named after a term explains it with the term's definition (ⓘ), and a
# `pdf_report` appends the entries of the terms the report uses. The glossary
# itself renders with `glossary_section`.

"""
    GlossaryTerm(term, definition; forms=String[], id=nothing, also=String[], see=String[], private=false)

One entry of a [`Glossary`](@ref): `term` as the glossary lists it and its
`definition`, a plain-text sentence or two. `forms` are the other spellings
that link to the entry where they appear in a page, such as a German plural or
an inflected phrase (`"Registerzellen"`, `"Modells vor dem Benchmarking"`); a
form also matches with its first letter capitalized, as at the start of a
sentence. `id` names the entry's address, `#term-<id>`; left out, it is built
from `term` (`"Teilverkehrszelle"` → `#term-teilverkehrszelle`).

`also` are the other names the term goes by, which its entry shows after the
definition (`Also: TVZ`, `Auch:` on a German page). A name can carry a note,
`"Verkehrsbezirk" => "so in der Leistungsbeschreibung"`, shown in parentheses
after it. An other name is shown, not matched: list it in `forms` too where a
page's use of it should link. `see` names related entries, by term or by id;
the entry ends with a line of links to them (`See also: KBA-Gebiet,
Verkehrszelle`).

`private=true` keeps the entry out of public answers (see [`private`](@ref)):
the glossary shows it to private readers, marked, and leaves it out of a
public answer, together with the links to it from the pages and from other
entries. A public reader sees a private term's uses as plain text, without a
link or a definition.

```julia
GlossaryTerm("Teilverkehrszelle", "Die Einheit der Schätzung …";
             forms=["Teilverkehrszellen", "TVZ"],
             also=["Verkehrsbezirk" => "so in der Leistungsbeschreibung", "TVZ"],
             see=["KBA-Gebiet", "Verkehrszelle"])
GlossaryTerm("R̂", "Vergleicht die Streuung innerhalb und zwischen den Ketten …";
             id="rhat", private=!SHOW_DIAGNOSTICS)
```

A blank term, form, other name, note, related entry or definition, and an `id`
that is not letters, digits, `-` and `_`, are an `ArgumentError`; so is a
related entry the glossary does not declare, when the [`Glossary`](@ref) is
built.
"""
struct GlossaryTerm
    term::String
    definition::String
    forms::Vector{String}
    id::String
    also::Vector{Pair{String,String}}   # name => note, "" for none
    see::Vector{String}                 # as written; a `Glossary` holds their ids
    private::Bool
end

function GlossaryTerm(term::AbstractString, definition::AbstractString;
                      forms=String[], id::Union{Nothing,AbstractString}=nothing,
                      also=String[], see=String[], private::Bool=false)
    name = _glossary_text(term, "term")
    text = _glossary_text(definition, "definition of $(repr(name))")
    spellings = unique!([name; [_glossary_text(f, "form of $(repr(name))") for f in forms]])
    names = unique!(Pair{String,String}[_glossary_name(a, name) for a in also])
    related = unique!(String[_glossary_text(s, "related entry of $(repr(name))") for s in see])
    GlossaryTerm(name, text, spellings, isnothing(id) ? _glossary_slug(name) : _glossary_id(id),
                 names, related, private)
end
GlossaryTerm(entry::Pair{<:AbstractString,<:AbstractString}) = GlossaryTerm(first(entry), last(entry))
GlossaryTerm(entry::GlossaryTerm) = entry

# One line of text: surrounding whitespace dropped, inner runs one space.
function _glossary_text(s::AbstractString, what)
    text = replace(strip(s), r"\s+" => " ")
    isempty(text) && throw(ArgumentError("GlossaryTerm: the $what is blank"))
    String(text)
end

_glossary_name(name::AbstractString, of) = _glossary_text(name, "other name of $(repr(of))") => ""
_glossary_name((name, note)::Pair, of) = let text = _glossary_text(name, "other name of $(repr(of))")
    text => _glossary_text(note, "note on $(repr(text))")
end

function _glossary_id(id::AbstractString)
    occursin(r"^[A-Za-z0-9][A-Za-z0-9_-]*$", id) || throw(ArgumentError(
        "GlossaryTerm: id must be letters, digits, `-` and `_`, starting with a letter or digit (got $(repr(id)))"))
    String(id)
end

const _GLOSSARY_FOLDS = ("ä" => "ae", "ö" => "oe", "ü" => "ue", "Ä" => "Ae", "Ö" => "Oe", "Ü" => "Ue", "ß" => "ss")

# `Modell vor Benchmarking` → `modell-vor-benchmarking`, `R̂` → `r`.
function _glossary_slug(term::AbstractString)
    ascii = Base.Unicode.normalize(replace(term, _GLOSSARY_FOLDS...); stripmark=true)
    slug = strip(replace(lowercase(ascii), r"[^a-z0-9]+" => "-"), '-')
    isempty(slug) && throw(ArgumentError(
        "GlossaryTerm: no id can be built from $(repr(term)); pass `id=`"))
    String(slug)
end

"""
    Glossary(terms; href="", title="Glossary")
    Glossary(["topic" => terms, …]; href="", title="Glossary")

An app's glossary: its [`GlossaryTerm`](@ref)s (a `"term" => "definition"`
pair stands for a term without other forms) and `href`, the address of the
page that shows it with [`glossary_section`](@ref). A term's link is
`href * "#term-<id>"`; with the default `href=""` the links point into the
page they are on, for a glossary on the same page. `title` heads the glossary
section and the glossary a [`pdf_report`](@ref) appends; write it in the app's
language (`"Glossar"`).

Without topics the glossary lists its terms alphabetically. Given as
`"topic" => terms` pairs, it lists each topic under its own heading, topics
and terms in the order written, so a reader meets a term before the terms
defined through it:

```julia
Glossary(["Raum" => [GlossaryTerm("Teilverkehrszelle", …), GlossaryTerm("KBA-Gebiet", …)],
          "Daten" => [GlossaryTerm("SvB", …), …]]; href="/glossar", title="Glossar")
```

Declare it once, on the app's root, as `__glossary__`:

```julia
const GLOSSAR = Glossary([
    GlossaryTerm("Registerzelle", "Ein Bezirk × Wirtschaftsabschnitt, für den das Unternehmensregister einen Wert hat.";
                 forms=["Registerzellen"]),
    "Realisierungsfaktor" => "SvB am Standort je gemeldete beschäftigte Person eines IHK-Betriebs.",
]; href="/glossar", title="Glossar")

@htmx struct App
    __glossary__ = GLOSSAR
    @get glossar() = glossary_section(__glossary__)
    …
end
```

Every answer under that root (a page, a fragment, an [`hx_response`](@ref), its
`?plain` Markdown, a static export of it) then links the uses of the terms to their entries
([`link_terms`](@ref)), and a sortable column whose header is a term explains
it with the term's definition. A subtree declares its own `__glossary__`; the
innermost declaration holds. Behind a path-stripping proxy, build `href` from
`__prefix__`.

Two terms with the same id, one spelling claimed by two terms, a related entry
the glossary does not declare, and terms given partly with and partly without
a topic, are an `ArgumentError`.
"""
struct Glossary
    terms::Vector{GlossaryTerm}                          # alphabetically
    topics::Vector{Pair{String,Vector{GlossaryTerm}}}    # as written; none without topics
    href::String
    title::String
    pattern::Regex
    lookup::Dict{String,GlossaryTerm}
end

function Glossary(items::AbstractVector; href::AbstractString="", title::AbstractString="Glossary")
    isempty(items) && throw(ArgumentError("Glossary: no terms"))
    topics = _glossary_topics(items)
    written = isempty(topics) ? GlossaryTerm[GlossaryTerm(t) for t in items] : reduce(vcat, last.(topics))
    _glossary_unique(written)
    lookup = _glossary_lookup(written)
    # Related entries are held by their ids, so an entry links them however they were named.
    related = Dict(t.id => _glossary_related_ids(t, lookup, written) for t in written)
    resolved(t) = GlossaryTerm(t.term, t.definition, t.forms, t.id, t.also, related[t.id], t.private)
    entries = map(resolved, written)
    topics = [topic => map(resolved, terms) for (topic, terms) in topics]
    lookup = _glossary_lookup(entries)
    heading = strip(title)
    isempty(heading) && throw(ArgumentError("Glossary: the title is blank"))
    sort!(entries; by=t -> lowercase(Base.Unicode.normalize(replace(t.term, _GLOSSARY_FOLDS...); stripmark=true)))
    Glossary(entries, topics, String(href), String(heading), _glossary_pattern(keys(lookup)), lookup)
end

function _glossary_lookup(entries)
    lookup = Dict{String,GlossaryTerm}()
    for t in entries, form in t.forms, spelling in unique([form, uppercasefirst(form)])
        lookup[spelling] = t
    end
    lookup
end

# The topics of a glossary given as `"topic" => terms` pairs, in the order
# written; none for a glossary given as terms. A pair is read by its values: in
# a list that mixes kinds, each pair is a `Pair{String,Any}`.
_glossary_topic(item) = nothing
_glossary_topic((topic, terms)::Pair) = _glossary_topic(topic, terms)
_glossary_topic(topic, terms) = nothing
_glossary_topic(topic::AbstractString, terms::AbstractVector) =
    _glossary_topic_name(topic) => GlossaryTerm[GlossaryTerm(t) for t in terms]
function _glossary_topic_name(topic)
    name = replace(strip(topic), r"\s+" => " ")
    isempty(name) && throw(ArgumentError("Glossary: a topic's name is blank"))
    String(name)
end
function _glossary_topics(items)
    topics = map(_glossary_topic, items)
    all(isnothing, topics) && return Pair{String,Vector{GlossaryTerm}}[]
    any(isnothing, topics) && throw(ArgumentError(
        "Glossary: give every term under a topic (`\"topic\" => [terms…]`), or none"))
    for (topic, terms) in topics
        isempty(terms) && throw(ArgumentError("Glossary: the topic $(repr(topic)) has no terms"))
        count(t -> first(t) == topic, topics) > 1 && throw(ArgumentError("Glossary: the topic $(repr(topic)) is given twice"))
    end
    Pair{String,Vector{GlossaryTerm}}[topics...]
end

# A related entry is named by one of its spellings or by its id.
function _glossary_related_ids(t::GlossaryTerm, lookup, entries)
    map(t.see) do name
        entry = get(lookup, name, nothing)
        isnothing(entry) && (i = findfirst(e -> e.id == name, entries); entry = isnothing(i) ? nothing : entries[i])
        isnothing(entry) && throw(ArgumentError(
            "Glossary: $(repr(t.term)) names $(repr(name)) as a related entry, which the glossary does not declare"))
        entry.id == t.id && throw(ArgumentError("Glossary: $(repr(t.term)) names itself as a related entry"))
        entry.id
    end |> unique!
end

_glossary_by_id(g::Glossary, id) = g.terms[findfirst(t -> t.id == id, g.terms)]

function _glossary_unique(entries)
    ids = Dict{String,String}()
    owners = Dict{String,String}()
    for t in entries
        other = get!(ids, t.id, t.term)
        other == t.term || throw(ArgumentError(
            "Glossary: $(repr(other)) and $(repr(t.term)) both have the id $(repr(t.id)); give one an `id=`"))
        for form in t.forms
            owner = get!(owners, form, t.term)
            owner == t.term || throw(ArgumentError(
                "Glossary: $(repr(form)) is a spelling of both $(repr(owner)) and $(repr(t.term))"))
        end
    end
end

# One regex for every spelling: longest first, so a phrase wins over a term it
# contains ("Modell vor Benchmarking" over "Modell"); whole words only, so
# "Registerzelle" is not found inside "Registerzellen"; any whitespace run
# matches the single space of a spelling, as text written across lines does.
const _GLOSSARY_WORD = "[\\p{L}\\p{N}\\p{M}_]"
_glossary_regex_text(s) = join((isspace(c) ? "\\s+" : occursin(c, "\\^\$.|?*+()[]{}/") ? "\\" * c : string(c))
                               for c in replace(s, r"\s+" => " "))
_glossary_pattern(spellings) = Regex(string("(?<!", _GLOSSARY_WORD, ")(?:",
    join((_glossary_regex_text(s) for s in sort!(collect(spellings); by=s -> (-length(s), s))), "|"),
    ")(?!", _GLOSSARY_WORD, ")"))

_glossary_entry(g::Glossary, text::AbstractString) = get(g.lookup, replace(text, r"\s+" => " "), nothing)

# The address of a term's entry; `""` in a PDF, whose glossary is appended.
_glossary_href(g::Glossary, t::GlossaryTerm) = string(g.href, "#term-", t.id)

"""
    glossary_section(g::Glossary)

The glossary as a section headed `g.title`: each term with its definition, at
its address `#term-<id>`, alphabetically, or for a glossary given by topic,
each topic as a section of its own, in the order written. An entry shows the
term's other names (`also`) and ends with links to its related entries
(`see`), labelled in the page's language (`Also:` / `See also:`, `Auch:` /
`Siehe auch:` under `__lang__ = "de"`). A link that opens an entry highlights
it. A private entry is marked for a private reader and left out of a public
answer; so is a topic whose terms are all private, its heading included.

In HTML the entries are a definition list (`dl.htmxo-glossary`, each `dt`
holding the term as a `dfn`); in Markdown each entry is a paragraph opening
with the term as a span carrying its address
(`[**Registerzelle**]{#term-registerzelle} — …`), which Pandoc reads, so links
to it resolve in a [`pdf_report`](@ref) too. Its text links no terms.
"""
glossary_section(g::Glossary) = isempty(g.topics) ?
    SemanticSection(g.title, _GlossaryEntries(g, g.terms)) :
    SemanticSection(g.title, Any[_glossary_topic_section(g, topic, terms) for (topic, terms) in g.topics])

_glossary_topic_section(g, topic, terms) = let section = SemanticSection(topic, _GlossaryEntries(g, terms))
    all(t -> t.private, terms) ? private(section) : section
end

# A section's list of entries, written by each format in its own form; plain
# text is the Markdown form without its markup. The walk leaves it alone (no
# `_link_terms` method), so its text links no terms. In a report's appended
# glossary, a related entry links into the report when the report lists it.
struct _GlossaryEntries <: SemanticNode
    glossary::Glossary
    terms::Vector{GlossaryTerm}
    report::Bool
end
_GlossaryEntries(g::Glossary, terms) = _GlossaryEntries(g, terms, false)

const _GLOSSARY_LABELS = (en = (also = "Also", see = "See also"), de = (also = "Auch", see = "Siehe auch"))

# What a reader of `audience` sees of an entry.
_glossary_shown(t::GlossaryTerm, audience) = !t.private || audience !== :public

_glossary_also_text(t::GlossaryTerm) =
    join((isempty(note) ? name : "$name ($note)" for (name, note) in t.also), ", ")

# The related entries a reader of `audience` sees, each with the address its
# link opens: `nothing` in a report that does not list it.
function _glossary_related(entries::_GlossaryEntries, t::GlossaryTerm, audience)
    related = (_glossary_by_id(entries.glossary, id) for id in t.see)
    [r => _glossary_related_href(entries, r) for r in related if _glossary_shown(r, audience)]
end
_glossary_related_href(entries::_GlossaryEntries, r::GlossaryTerm) = !entries.report ?
    _glossary_href(entries.glossary, r) : any(t -> t.id == r.id, entries.terms) ? "#term-" * r.id : nothing

function _semantic_html_node(entries::_GlossaryEntries)
    audience = _ambient_audience()
    labels = _lang_entry(_GLOSSARY_LABELS, page_lang())
    h.dl((x for t in entries.terms if _glossary_shown(t, audience)
            for x in _glossary_entry_html(entries, t, audience, labels))...;
         class="htmxo-glossary", data_htmxo_no_terms="")
end

# The entry's term and definition; a private entry's each carry the private mark.
function _glossary_entry_html(entries, t, audience, labels)
    names = isempty(t.also) ? () : (h.small(labels.also, ": ", _glossary_also_text(t)),)
    related = _glossary_related(entries, t, audience)
    links = Any[]
    for (i, (r, href)) in enumerate(related)
        i > 1 && push!(links, ", ")
        link = isnothing(href) ? r.term : h.a(r.term; href)
        push!(links, r.private ? private(link; mark=false) : link)
    end
    see = isempty(links) ? () : (h.small(labels.see, ": ", links...),)
    entry = Any[h.dt(h.dfn(t.term); id="term-" * t.id), h.dd(t.definition, names..., see...)]
    t.private ? Any[private(entry)] : entry
end

Base.show(io::IO, mime::MIME"text/html", entries::_GlossaryEntries) = show(io, mime, _semantic_html_node(entries))
Base.show(io::IO, mime::MIME"application/vnd.hyperview+xml", entries::_GlossaryEntries) =
    show(io, mime, _semantic_html_node(entries))
Base.show(io::IO, ::MIME"text/markdown", entries::_GlossaryEntries) = print(io, _glossary_markdown(entries))
Base.show(io::IO, ::MIME"text/plain", entries::_GlossaryEntries) = print(io, _glossary_plain(entries))

# Markdown and plain text write the entry's lines as hard line breaks of one
# paragraph. A private entry opens with the label, as an element marked in
# place does (`_private_md_labelled`), unless it is inside marked content.
function _glossary_markdown(entries::_GlossaryEntries)
    audience = _ambient_audience()
    labels = _lang_entry(_GLOSSARY_LABELS, page_lang())
    join((_glossary_entry_markdown(entries, t, audience, labels)
          for t in entries.terms if _glossary_shown(t, audience)), "\n\n")
end
function _glossary_entry_markdown(entries, t, audience, labels)
    lines = ["[**$(_md_escape_text(t.term))**]{#term-$(t.id)} — $(_md_escape_text(t.definition))"]
    isempty(t.also) || push!(lines, "*$(labels.also):* $(_md_escape_text(_glossary_also_text(t)))")
    related = _glossary_related(entries, t, audience)
    isempty(related) || push!(lines, "*$(labels.see):* " * join((isnothing(href) ? _md_escape_text(r.term) :
        "[$(_md_escape_text(r.term))]($href)" for (r, href) in related), ", "))
    _glossary_private_label(t, "*$(_private_label(page_lang())):* ") * join(lines, "\\\n")
end
function _glossary_plain(entries::_GlossaryEntries)
    audience = _ambient_audience()
    labels = _lang_entry(_GLOSSARY_LABELS, page_lang())
    join((_glossary_entry_plain(entries, t, audience, labels)
          for t in entries.terms if _glossary_shown(t, audience)), "\n\n")
end
function _glossary_entry_plain(entries, t, audience, labels)
    lines = ["$(t.term) — $(t.definition)"]
    isempty(t.also) || push!(lines, "$(labels.also): $(_glossary_also_text(t))")
    related = _glossary_related(entries, t, audience)
    isempty(related) || push!(lines, "$(labels.see): " * join((first(r).term for r in related), ", "))
    _glossary_private_label(t, "[$(_private_label(page_lang()))] ") * join(lines, "\n")
end
_glossary_private_label(t::GlossaryTerm, label) = t.private && !_in_private_mark() ? label : ""

_md_escape_text(s) = replace(s, r"([\\`*_\[\]<>])" => s"\\\1")

"""
    term(text; of=nothing)

A use of a glossary term that the automatic linking cannot see: an inflected
form that no [`GlossaryTerm`](@ref) lists, or a mention whose term is `of`
(the term's name or id). Where the answer's [`Glossary`](@ref) is in force it
always links, wherever it stands; elsewhere it is `text`. A `term` whose term
the glossary does not declare is an `ArgumentError`.

```julia
h.p("Die ", term("Realisierungsfaktoren"; of="Realisierungsfaktor"), " je Abschnitt …")
```
"""
term(text::AbstractString; of::Union{Nothing,AbstractString}=nothing) = TermUse(String(text), of)

struct TermUse
    text::String
    of::Union{Nothing,String}
end
Base.show(io::IO, m::MIME"text/html", t::TermUse) = show(io, m, h.span(t.text))
Base.show(io::IO, m::MIME"text/markdown", t::TermUse) = show(io, m, h.span(t.text))
Base.show(io::IO, ::MIME"text/plain", t::TermUse) = print(io, t.text)
HTMX.markdown_block(::TermUse) = false

function _glossary_entry(g::Glossary, use::TermUse)
    key = something(use.of, use.text)
    entry = _glossary_entry(g, key)
    isnothing(entry) && (i = findfirst(t -> t.id == key, g.terms); entry = isnothing(i) ? nothing : g.terms[i])
    isnothing(entry) && throw(ArgumentError(
        "term($(repr(use.text))$(isnothing(use.of) ? "" : "; of=$(repr(use.of))")): the glossary declares no term $(repr(key)); " *
        "declared: $(join((repr(t.term) for t in g.terms), ", "))"))
    entry
end

# --- Linking: one walk over an answer, in document order ---

# Elements whose text is never linked: links and controls (a link inside one
# is invalid or steals its click), code, headings (labels, not prose), the
# glossary itself, and markup that is not text. Table headers are labels too:
# a column named after a term is explained through its ⓘ instead.
const _TERM_SKIP = Set{Symbol}([:a, :button, :select, :option, :optgroup, :textarea, :input, :label, :summary,
    :code, :pre, :kbd, :samp, :var, :dfn, :abbr, :h1, :h2, :h3, :h4, :h5, :h6,
    :head, :title, :script, :style, :template, :noscript, :svg, :math, :canvas, :iframe, :object,
    :video, :audio, :nav])
# Elements that start a fresh run: in each, a term's first use links again.
const _TERM_SCOPES = Set{Symbol}([:section, :article, :aside, :table, :figure, :figcaption, :caption,
    :details, :dialog])
const _TERM_HEADINGS = Set{Symbol}([:h1, :h2, :h3, :h4, :h5, :h6])

mutable struct _TermWalk
    glossary::Glossary
    seen::Set{String}       # terms linked in the current run
    token::String           # keeps the definitions' ids unique across fragments
    count::Int
end
_TermWalk(g::Glossary) = _TermWalk(g, Set{String}(), string(rand(UInt32); base=36), 0)

"""
    link_terms(value, glossary::Glossary)

`value` with the uses of `glossary`'s terms linked to their entries: in each
section of a page (a heading, `section` or `SemanticSection` starts one), and
again in each table, figure, caption and disclosure, the first use of a term
becomes a link to `glossary.href * "#term-<id>"`. Hovering it or focusing it
shows the term's definition beside it, and screen readers read the definition
as the link's description. A [`term`](@ref) always links. Markdown writes the
link as `[text](href#term-<id>)`.

The answers of a root that declares `__glossary__` are linked this way before
they are sent, so an app rarely calls it. It walks HTML nodes, the semantic
containers and [`SemanticProse`](@ref); it leaves alone links, controls, code,
headings, table headers, the text of an element marked `data-htmxo-no-terms`,
attribute values (a `title` tooltip), and what is already rendered (`Raw`, an
[`HTMLSnapshot`](@ref), a plot's own titles).
"""
link_terms(value, g::Glossary) = _link_terms(value, _TermWalk(g))

_link_terms(value, w::_TermWalk) = value
_link_terms(xs::AbstractVector, w::_TermWalk) = Any[_link_child(x, w) for x in xs]
_link_terms(xs::Tuple, w::_TermWalk) = map(x -> _link_child(x, w), xs)
_link_terms((content, id)::Pair, w::_TermWalk) = _link_terms(content, w) => id
_link_terms(doc::HTMLDocument, w::_TermWalk) = HTMLDocument(_link_terms(doc.root, w))
_link_terms(x::HtmlOnly, w::_TermWalk) = HtmlOnly(_link_terms(x.content, w))
_link_terms(r::HXResponse, w::_TermWalk) = HXResponse(_link_terms(r.value, w), r.headers)
_link_terms(use::TermUse, w::_TermWalk) = _term_link(w, use.text, _glossary_entry(w.glossary, use))

# Text that is a value of its own (a container's child, not a node's) keeps its
# place as one inline element.
_link_child(x, w::_TermWalk) = _link_terms(x, w)
function _link_child(s::AbstractString, w::_TermWalk)
    pieces = _link_text(s, w)
    pieces isa AbstractString ? pieces : h.span(pieces...)
end

function _link_terms(node::Node, w::_TermWalk)
    t = HTMX.tag(node)
    attrs = HTMX.attrs(node)
    t in _TERM_HEADINGS && empty!(w.seen)
    t === :th && return _explained_th(node, w.glossary)
    (t in _TERM_SKIP || haskey(attrs, Symbol("data-htmxo-no-terms")) ||
     haskey(attrs, Symbol("data-htmxo-math")) || _is_term_link(attrs)) && return node
    _term_scope(w, t in _TERM_SCOPES) do
        children = Any[]
        changed = false
        for c in HTMX.children(node)
            linked = c isa AbstractString ? _link_text(c, w) : _link_terms(c, w)
            changed |= linked !== c
            linked isa AbstractVector && c isa AbstractString ? append!(children, linked) : push!(children, linked)
        end
        changed ? Node(t, copy(attrs), children) : node
    end
end

_is_term_link(attrs) = (c = get(attrs, :class, nothing); c isa AbstractString && "htmxo-term" in split(c))

# A fresh run of first uses for the walk inside `f`; the outer run continues
# after it as it was.
function _term_scope(f, w::_TermWalk, fresh::Bool)
    fresh || return f()
    outer = w.seen
    w.seen = Set{String}()
    try
        f()
    finally
        w.seen = outer
    end
end

# `text` as itself, or as its pieces with the first use of each term linked.
function _link_text(text::AbstractString, w::_TermWalk)
    pieces = Any[]
    last = firstindex(text)
    for m in eachmatch(w.glossary.pattern, text)
        entry = _glossary_entry(w.glossary, m.match)
        (isnothing(entry) || entry.id in w.seen) && continue
        m.offset > last && push!(pieces, text[last:prevind(text, m.offset)])
        push!(pieces, _term_link(w, m.match, entry))
        last = m.offset + ncodeunits(m.match)
    end
    isempty(pieces) && return text
    last <= lastindex(text) && push!(pieces, text[last:end])
    pieces
end

# A private term links for a private reader only; a public one reads the text.
function _term_link(w::_TermWalk, text::AbstractString, entry::GlossaryTerm)
    push!(w.seen, entry.id)
    w.count += 1
    id = string("htmxo-term-", entry.id, "-", w.token, "-", w.count)
    link = h.span(h.a(String(text); href=_glossary_href(w.glossary, entry), aria_describedby=id),
                  html_only(h.span(entry.definition; id, class="htmxo-term-def", role="tooltip"));
                  class="htmxo-term")
    entry.private ? private(link; public=String(text), mark=false) : link
end

# Semantic containers keep their peers: rebuilt with linked children. A card,
# section and disclosure start a fresh run (their titles are labels and stay
# as they are).
_link_children(children, w) = Any[_link_child(c, w) for c in children]
_link_terms(card::SemanticCard, w::_TermWalk) =
    _term_scope(() -> SemanticCard(card.title, _link_children(card.children, w); anchor=card.anchor), w, true)
_link_terms(section::SemanticSection, w::_TermWalk) =
    _term_scope(() -> SemanticSection(section.title, _link_children(section.children, w); anchor=section.anchor), w, true)
_link_terms(group::SemanticGroup, w::_TermWalk) = SemanticGroup(_link_children(group.children, w))
_link_terms(disclosure::SemanticDisclosure, w::_TermWalk) =
    _term_scope(() -> SemanticDisclosure(disclosure.summary, _link_children(disclosure.children, w)), w, true)
_link_terms(alt::SemanticAlternatives, w::_TermWalk) = SemanticAlternatives(Any[
    _link_child(first(alt.views), w),
    (first(v) => _term_scope(() -> _link_child(last(v), w), w, true) for v in alt.views[2:end])...])

# Private content is linked as each reader sees it: a reader sees the content
# or its stand-in, so each continues the run as it was, and the run goes on
# with the terms either linked. Content a function builds is built when shown,
# so it is linked then, as a run of its own.
function _link_terms(p::Private, w::_TermWalk)
    before = copy(w.seen)
    content = _link_private(p.content, w)
    shown = w.seen
    w.seen = before
    public = _link_terms(p.public, w)
    union!(w.seen, shown)
    Private(content, public, p.mark)
end
_link_private(content, w) = _link_terms(content, w)
_link_private(build::Function, w) = () -> _term_scope(() -> _link_terms(build(), w), w, true)
_link_terms(x::_PrivateMark, w::_TermWalk) = _PrivateMark(_link_terms(x.content, w))

# A master/detail table's detail rows and their Markdown after the table: each
# detail is opened on its own, so it links as a run of its own.
_link_terms(c::_MDCompanionRow, w::_TermWalk) = _MDCompanionRow(_term_scope(() -> _link_terms(c.row, w), w, true))
_link_terms(d::_MDDetailsMarkdown, w::_TermWalk) = _MDDetailsMarkdown(Pair{Vector{Any},Any}[
    label => _term_scope(() -> _link_child(body, w), w, true) for (label, body) in d.details])

# A tab's panel is read on its own, as a disclosure is: its HTML and its
# Markdown (the label and the content it opens) each link as a run of their own.
# A lazy tab's Markdown is a link already written as Markdown text, left as is.
_link_terms(p::_TabsetPart, w::_TermWalk) = _TabsetPart(
    _term_scope(() -> _link_terms(p.node, w), w, true), _term_scope(() -> _link_terms(p.markdown, w), w, true))

# Prose renders its Markdown to nodes, which are linked like any others. Linked
# prose keeps that HTML and writes its Markdown from it; prose that links
# nothing is left as it was.
struct _LinkedProse <: SemanticNode
    node::Node
    markdown::String
end
_semantic_html_node(prose::_LinkedProse) = prose.node
Base.show(io::IO, mime::MIME"text/html", prose::_LinkedProse) = show(io, mime, prose.node)
Base.show(io::IO, mime::MIME"application/vnd.hyperview+xml", prose::_LinkedProse) = show(io, mime, prose.node)
Base.show(io::IO, ::MIME"text/markdown", prose::_LinkedProse) = print(io, prose.markdown)
Base.show(io::IO, ::MIME"text/plain", prose::_LinkedProse) = print(io, prose.markdown)

function _link_terms(prose::SemanticProse, w::_TermWalk)
    before = w.count
    node = _link_terms(_semantic_prose_node(prose), w)
    w.count == before ? prose : _LinkedProse(node, strip(to_markdown_string(_md_escaped(node))))
end

# The rendered prose writes its text verbatim into Markdown, where a character
# its source had escaped (`\*`, `\$`) would turn into markup again; escaped
# here, outside code and math, whose text Markdown keeps as it is.
_md_escaped(x) = x
_md_escaped(s::AbstractString) = replace(_md_escape_text(s), '$' => "\\\$")
_md_escaped(node::Node) = HTMX.tag(node) in (:code, :pre) || haskey(HTMX.attrs(node), Symbol("data-htmxo-math")) ? node :
    Node(HTMX.tag(node), copy(HTMX.attrs(node)), Any[_md_escaped(c) for c in HTMX.children(node)])

# --- Where a glossary is in force ---

# `__glossary__` is read with the page's other declarations (`_page_meta_of`).
_page_glossary_value(obj, g::Glossary) = g
_page_glossary_value(obj, value) = _page_declaration_error(obj, :__glossary__, "a `Glossary`", value)

_page_glossary() = get(_page_meta(), :glossary, nothing)

# An answer under a root that declares a glossary is sent with its terms linked.
_glossary_answer(val) = _glossary_answer(val, _page_glossary())
_glossary_answer(val, ::Nothing) = val
_glossary_answer(val, g::Glossary) = link_terms(val, g)

# A column whose header is a term, and which has no explanation of its own,
# is explained by the definition, as a `ColumnSpec`'s `help` is: the `title`
# of its sort button (or of the `<th>` of a table that does not sort) and the
# ⓘ after its label. Only a header whose whole label is the term qualifies; a
# private term's only in an answer for a private reader (an attribute cannot
# hold private content, so the walk asks the answer's audience).
function _explained_th(th::Node, g::Glossary)
    kids = HTMX.children(th)
    i = findfirst(c -> c isa _LabelledControl, kids)
    if isnothing(i)
        explained = _explained_header(th, g)
        return isnothing(explained) ? th : explained
    end
    button = _explained_header(kids[i].control, g)
    isnothing(button) && return th
    Node(:th, copy(HTMX.attrs(th)), Any[k == i ? _LabelledControl(button) : c for (k, c) in enumerate(kids)])
end
function _explained_header(node::Node, g::Glossary)
    attrs = HTMX.attrs(node)
    kids = HTMX.children(node)
    (haskey(attrs, :title) || length(kids) != 1 || !(only(kids) isa AbstractString)) && return nothing
    entry = _glossary_entry(g, only(kids))
    (isnothing(entry) || !_glossary_shown(entry, _ambient_audience())) && return nothing
    explained = copy(attrs)
    explained[:title] = entry.definition
    Node(HTMX.tag(node), explained, collect(Any, _header_content(ColumnSpec(only(kids); help=entry.definition))))
end

_check_glossary(g::Union{Nothing,Glossary}, who) = g
_check_glossary(g, who) = throw(ArgumentError("$who: glossary must be a `Glossary` or nothing (got $(repr(g)))"))

# A report's term links point into the report, whose end lists the terms it
# uses (those it does not list itself already), for the report's audience and
# in its language. A related entry links only where the report lists it, so
# every link inside the PDF has a target.
_glossary_report(markdown::AbstractString, ::Nothing; audience=:public, lang=nothing) = markdown
function _glossary_report(markdown::AbstractString, g::Glossary; audience=:public, lang=nothing)
    used = String[]
    linked = replace(markdown, Regex(string("\\]\\(", _glossary_regex_text(g.href), "#term-([A-Za-z0-9_-]+)\\)")) => function (link)
        id = match(r"#term-([A-Za-z0-9_-]+)\)$", link).captures[1]
        any(t -> t.id == id && _glossary_shown(t, audience), g.terms) || return link
        id in used || push!(used, id)
        "](#term-$id)"
    end)
    entries = [t for t in g.terms if t.id in used && !occursin("{#term-$(t.id)}", linked)]
    isempty(entries) && return linked
    appended = _with_page_lang(lang) do
        _with_audience(() -> _glossary_markdown(_GlossaryEntries(g, entries, true)), audience)
    end
    string(rstrip(linked), "\n\n## ", _md_escape_text(g.title), "\n\n", appended, "\n")
end

"""
    glossary_script()

Client runtime of the term links [`link_terms`](@ref) writes. Hovering a term
or focusing its link opens the term's definition beside it; the runtime places
the box below the term (above it when there is no room below), inside the
window, and outside any scrolling container such as a wide table's, which
would otherwise clip it, and keeps it there while the page scrolls. Escape
closes it until the pointer or the focus leaves the term. Without the runtime,
the stylesheet ([`htmxo_utility_styles`](@ref)) still opens the box below the
term.

Safe to include more than once. Auto-included by [`htmx`](@ref); include it
yourself only on pages built without the shell.
"""
glossary_script() = h.script(Raw(raw"""
(function () {
  'use strict';
  if (window.htmxoGlossary) return;
  window.htmxoGlossary = true;
  document.documentElement.classList.add('htmxo-terms');
  var MARGIN = 8, open = new Set();
  var termOf = function (node) { return node instanceof Element ? node.closest('.htmxo-term') : null; };
  var parts = function (term) {
    return {link: term.querySelector(':scope > a'), box: term.querySelector(':scope > .htmxo-term-def')};
  };
  function place(term) {
    var p = parts(term);
    if (!p.link || !p.box) return;
    term.setAttribute('data-htmxo-term-open', '');
    open.add(term);
    // Measured at its own width first, then moved where it fits.
    p.box.style.left = '0px';
    p.box.style.top = '0px';
    var r = p.link.getBoundingClientRect(), b = p.box.getBoundingClientRect();
    var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
    var left = Math.max(MARGIN, Math.min(r.left, vw - b.width - MARGIN));
    var top = r.bottom + b.height > vh - MARGIN && r.top - b.height >= MARGIN ? r.top - b.height : r.bottom;
    p.box.style.left = left + 'px';
    p.box.style.top = top + 'px';
  }
  function close(term) {
    term.removeAttribute('data-htmxo-term-open');
    var box = parts(term).box;
    if (box) { box.style.left = ''; box.style.top = ''; }
    open.delete(term);
  }
  function enter(e) {
    var term = termOf(e.target);
    if (term && !open.has(term) && !term.hasAttribute('data-htmxo-term-dismissed')) place(term);
  }
  function leave(e, stays) {
    var term = termOf(e.target);
    if (!term || term.contains(e.relatedTarget)) return;
    term.removeAttribute('data-htmxo-term-dismissed');
    if (!stays(term)) close(term);
  }
  document.addEventListener('mouseover', enter);
  document.addEventListener('focusin', enter);
  document.addEventListener('mouseout', function (e) {
    leave(e, function (term) { return term.contains(document.activeElement); });
  });
  document.addEventListener('focusout', function (e) {
    leave(e, function (term) { return term.matches(':hover'); });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape' || !open.size) return;
    open.forEach(function (term) { term.setAttribute('data-htmxo-term-dismissed', ''); close(term); });
  });
  // An open box follows its term when the page or a container scrolls.
  var follow = function () {
    open.forEach(function (term) { term.isConnected ? place(term) : open.delete(term); });
  };
  document.addEventListener('scroll', follow, true);
  window.addEventListener('resize', follow);
})();
"""))
