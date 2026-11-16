# --- Numbered documents: section, figure and table numbers, a contents list, cross-references ---
#
# `numbered(content...)` gives the sections, captioned figures and captioned
# tables inside it their numbers, and `contents()` and `ref(id)` read them. The
# numbers are text in every form the content renders to, so the page, its
# Markdown and the `pdf_report` PDF made from that Markdown read the same.
#
# How the numbers are given. A numbered document renders its content twice:
# first as HTML into nothing, which hands out the numbers in reading order and
# collects the contents list and the targets of `ref`; then in the form asked
# for, where each element takes the number the first pass gave it. The first
# pass is HTML whatever the second is, because HTML puts a caption above its
# figure and so reads captions in the order a reader meets them; Markdown
# writes a caption after its figure's content (Quarto reads the last paragraph
# of a figure as its caption), which would number a caption inside a captioned
# figure before the figure's own. A caption is found again by identity: each
# `render_caption` makes a slot object of its own, which every walk of the
# tree passes on unchanged. A section is found again by identity too, so the
# second pass may show it more than once (HTMX writes a document's Markdown a
# second time when a link in it points at an element id the first write did
# not know of) and it keeps its number; a section built anew for this render
# is found by its place in the reading order, checked against its title, so a
# section only one form shows never takes the next section's number.
#
# Content that only one form shows (`html_only`, an alternative's collapsed
# views) is not numbered, so both forms number the same elements.

"""
    NumberingTexts

The words a numbered document writes: `contents` heads its contents list, and
`section`, `figure` and `table` name a numbered element, `{number}` standing
for its number ("Figure {number}" writes "Figure 3"). A caption's number reads
as that name followed by a colon ("Figure 3: …"), and a [`ref`](@ref) as the
name alone. Build one with [`numbering_texts`](@ref).
"""
struct NumberingTexts
    contents::String  # the title of the contents list
    section::String   # a section cited by `ref`: "Section {number}"
    figure::String    # a captioned figure: "Figure {number}"
    table::String     # a captioned table: "Table {number}"
end

const _NUMBERING_TEXT_LOCALES = (
    en = (contents = "Contents", section = "Section {number}",
          figure = "Figure {number}", table = "Table {number}"),
    de = (contents = "Inhalt", section = "Abschnitt {number}",
          figure = "Abbildung {number}", table = "Tabelle {number}"),
)
const _NUMBERING_TEXT_PLACEHOLDERS = (section = (:number,), figure = (:number,), table = (:number,))

"""
    numbering_texts(locale::Symbol=:en; texts...)

The [`NumberingTexts`](@ref) for `locale` (`:en` or `:de`), with any of its
texts replaced by keyword.

```julia
numbered(report; texts=numbering_texts(:de))                         # "Abbildung 3", "Inhalt"
numbered(report; texts=numbering_texts(:de; figure="Abb. {number}"))  # the report's own word
```

An unknown locale or text name, or a placeholder other than `{number}`, throws
an `ArgumentError`.
"""
numbering_texts(locale::Symbol=:en; texts...) =
    _locale_texts(NumberingTexts, :numbering_texts, _NUMBERING_TEXT_LOCALES,
                  _NUMBERING_TEXT_PLACEHOLDERS, locale; texts...)

# Without `texts=`, a numbered document writes the words of the page's language
# (`page_lang`, which `pdf_report` and `to_markdown_string(…; lang)` set too).
function _numbering_page_texts()
    lang = page_lang()
    !isnothing(lang) && startswith(lowercase(lang), "de") ? numbering_texts(:de) : numbering_texts(:en)
end

struct _Numbered <: SemanticNode
    children::Vector{Any}
    sections::Bool
    figures::Bool
    tables::Bool
    texts::Union{Nothing,NumberingTexts}
end

"""
    numbered(content...; sections=true, figures=true, tables=true, texts=nothing)

Content whose sections, captioned figures and captioned tables are numbered,
with the same numbers in the HTML page, the Markdown (`?plain`,
`to_markdown_string`) and a [`pdf_report`](@ref) made from it.

- a [`SemanticSection`](@ref) shows its number before its title: `1`, `2`,
  `2.1`, … by how the sections nest. A section at `level=1` is the document's
  title and has none; the sections inside it count from `1`.
- a caption from [`with_caption`](@ref) (and AlgebraOfVega's
  `with_plot_caption`) starts with "Figure 3:", and the caption of
  [`render_table`](@ref), [`sortable_table`](@ref) or
  [`master_detail_table`](@ref) with "Table 1:". Figures and tables are
  counted separately, straight through the document.

Place [`contents`](@ref) inside it for a list of its numbered sections, and
cite a numbered element with [`ref`](@ref):

```julia
numbered(
    contents(),
    SemanticSection("Results",
        h.p("The posterior is in ", ref("fig-posterior"), "."),
        with_caption("Posterior", plot; id="fig-posterior")),
    SemanticSection("Model", …; anchor="model"))
```

`sections`, `figures` and `tables` switch each kind of number off. `texts` (a
[`NumberingTexts`](@ref)) holds the words; without it they follow the page's
language (`HTMXObjects.page_lang`): German on a German page or report, English
otherwise.

A section without an `anchor` gets the id `section-2-1` from its number, so the
contents list can link it. The numbers follow the reader: a public reader's page
or PDF leaves private sections out and numbers what remains without gaps.

What the browser loads later (a lazy tab, a detail row fetched on opening) is
not part of the document when it is numbered, so it has no number and is not
in the contents list. Nor is content only one form shows (`html_only`, a
`SemanticAlternatives` view after the first). In a `pdf_report`, Quarto's and
Typst's own figure and table numbers are switched off for the whole document,
so nothing is numbered twice; `metadata=(number_sections=true,)` is refused.
"""
numbered(children...; sections::Bool=true, figures::Bool=true, tables::Bool=true,
         texts::Union{Nothing,NumberingTexts}=nothing) =
    _Numbered(Any[children...], sections, figures, tables, texts)

_numbered_like(doc::_Numbered, children) =
    _Numbered(Any[children...], doc.sections, doc.figures, doc.tables, doc.texts)

# One numbered section, as the first pass met it.
struct _SectionEntry
    title::String
    number::String
    anchor::String
    depth::Int   # 1 for a top section, 2 for one inside it, …
    level::Int   # its heading level (2 for `##`), for the PDF's outline
end

# One numbered caption.
struct _CaptionEntry
    kind::Symbol
    words::String  # "Figure 3"
end

mutable struct _NumberingState
    doc::_Numbered
    texts::NumberingTexts
    collecting::Bool
    # Whether the second pass renders as the first did (HTML, Hyperview, a
    # static export), so an element the first pass met is met again in order.
    in_order::Bool
    sections::Vector{_SectionEntry}
    section_index::IdDict{Any,Vector{Int}}  # a section => its entries, in reading order
    captions::Vector{_CaptionEntry}
    caption_index::IdDict{Any,Int}
    anchors::Dict{String,String}  # an id `ref` may cite => its words
    depth::Int
    counters::Vector{Int}
    figures::Int
    tables::Int
    section_at::Int
    caption_at::Int
end

_NumberingState(doc::_Numbered, texts::NumberingTexts) = _NumberingState(doc, texts, true, true,
    _SectionEntry[], IdDict{Any,Vector{Int}}(), _CaptionEntry[], IdDict{Any,Int}(), Dict{String,String}(),
    0, Int[], 0, 0, 0, 0)

# The numbered document being rendered, and whether its numbers are paused for
# content that only one form shows.
const _NUMBERING = ScopedValues.ScopedValue{Union{Nothing,_NumberingState}}(nothing)
const _NUMBERING_PAUSED = ScopedValues.ScopedValue{Bool}(false)

# The document whose numbers an element takes here, or `nothing`.
_numbering() = _NUMBERING_PAUSED[] ? nothing : _NUMBERING[]

# Runs `f` with numbering paused: what it renders takes no number.
_unnumbered(f) = isnothing(_NUMBERING[]) ? f() : ScopedValues.with(f, _NUMBERING_PAUSED => true)

# The first pass: renders the document's content as HTML into nothing, as the
# reader of this render, and returns what it numbered.
function _numbering_collect(doc::_Numbered)
    state = _NumberingState(doc, something(doc.texts, _numbering_page_texts()))
    ScopedValues.with(_NUMBERING => state, _NUMBERING_PAUSED => false) do
        show(devnull, MIME"text/html"(), _numbered_html_node(doc))
    end
    state.collecting = false
    state.depth = 0
    state
end

# Runs `f` (the second pass) with the numbers of `doc`.
function _with_numbers(f, doc::_Numbered; in_order::Bool)
    state = _numbering_collect(doc)
    state.in_order = in_order
    ScopedValues.with(f, _NUMBERING => state, _NUMBERING_PAUSED => false)
end

# --- Sections ---

# Runs `f(number, anchor)` for `section` opening at heading `level`: its number
# (`nothing` when it has none) and the id it is written with.
function _numbered_section(f, section::SemanticSection, level::Integer)
    state = _numbering()
    (isnothing(state) || !state.doc.sections || level == 1) && return f(nothing, section.anchor)
    entry = state.collecting ? _collect_section!(state, section, level) : _find_section!(state, section)
    isnothing(entry) && return f(nothing, section.anchor)
    state.depth += 1
    try
        f(entry.number, entry.anchor)
    finally
        state.depth -= 1
    end
end

function _collect_section!(state::_NumberingState, section::SemanticSection, level::Integer)
    depth = state.depth + 1
    length(state.counters) < depth && push!(state.counters, 0)
    resize!(state.counters, depth)
    state.counters[depth] += 1
    number = join(state.counters, ".")
    anchor = isempty(section.anchor) ? "section-" * join(state.counters, "-") : section.anchor
    entry = _SectionEntry(section.title, number, anchor, depth, level)
    push!(state.sections, entry)
    push!(get!(Vector{Int}, state.section_index, section), length(state.sections))
    state.anchors[anchor] = _fill_text(state.texts.section; number)
    entry
end

# The entry the first pass gave this section. HTMX may call a section's `show`
# more than once for one place in the document: when it writes the document a
# second time (`_NumberingStart`), and inside a `<header>`, whose layout it
# probes first. So a section the first pass met is found by identity, and gets
# the same entry however often it is shown; one placed twice takes its next
# entry in reading order. A section built anew for this render (a function's
# private content) is found by its title: the next entry in reading order, or a
# later one with its title when the first pass met a section this render does
# not show. A section the first pass never met has none.
function _find_section!(state::_NumberingState, section::SemanticSection)
    entries = get(state.section_index, section, nothing)
    i = if isnothing(entries)
        something(findnext(e -> e.title == section.title, state.sections, state.section_at + 1), 0)
    elseif length(entries) == 1
        only(entries)
    else
        entries[something(findfirst(>(state.section_at), entries), 1)]
    end
    i == 0 && return nothing
    state.section_at = i
    state.sections[i]
end

# HTMX writes a document's Markdown a second time when a link in a value's
# output (a `ref` inside a section) points at an element id the first write met
# without writing it, such as a captioned figure's. Each write then reads the
# numbers from the start: this value, the first in the document's body, writes
# nothing and starts the reading order again.
struct _NumberingStart
    state::_NumberingState
end
function Base.show(io::IO, ::MIME"text/markdown", start::_NumberingStart)
    start.state.section_at = 0
    start.state.caption_at = 0
    nothing
end
HTMX.markdown_block(::_NumberingStart) = false

# The heading's number, then a space, before its title.
_section_number_nodes(::Nothing) = ()
_section_number_nodes(number::AbstractString) = (h.span(number; class="htmxo-section-number"), " ")
_section_number_text(::Nothing) = ""
_section_number_text(number::AbstractString) = number * " "

# --- Captions ---

# Where a caption's number goes: `render_caption` puts one at the start of its
# title. It writes nothing outside a numbered document. Mutable, so that each
# caption is an object of its own however its tree is copied.
mutable struct _CaptionNumber
    kind::Symbol      # :figure or :table
    anchor::String    # the id of the figure it labels, which `ref` cites
    bold::Bool        # a caption without a title: the number is its bold label
end
_CaptionNumber(kind::Symbol, anchor::AbstractString) = _CaptionNumber(kind, String(anchor), false)

function _caption_kind(kind)
    kind in (:figure, :table) && return kind
    throw(ArgumentError("a caption's `kind` is :figure or :table, or `nothing` for no number; got $(repr(kind))"))
end

_numbers_kind(state::_NumberingState, kind::Symbol) =
    kind === :figure ? state.doc.figures : state.doc.tables

# The words of the caption's number ("Figure 3"), or `nothing`.
function _caption_words(slot::_CaptionNumber)
    state = _numbering()
    (isnothing(state) || !_numbers_kind(state, slot.kind)) && return nothing
    if state.collecting
        i = get(state.caption_index, slot, 0)
        if i == 0
            n = slot.kind === :figure ? (state.figures += 1) : (state.tables += 1)
            words = _fill_text(slot.kind === :figure ? state.texts.figure : state.texts.table; number=n)
            push!(state.captions, _CaptionEntry(slot.kind, words))
            i = state.caption_index[slot] = length(state.captions)
            isempty(slot.anchor) || (state.anchors[slot.anchor] = words)
        end
        return state.captions[i].words
    end
    i = get(state.caption_index, slot, 0)
    if i == 0 && state.in_order
        # Content built anew for this render (a `private` function's result)
        # holds slots of its own; met in order, it is the next of its kind.
        i = something(findnext(e -> e.kind === slot.kind, state.captions, state.caption_at + 1), 0)
    end
    i == 0 && return nothing
    state.caption_at = i
    state.captions[i].words
end

function _caption_number_node(slot::_CaptionNumber)
    words = _caption_words(slot)
    isnothing(words) && return ""
    number = h.span(words, ":"; class="htmxo-caption-number")
    h.span(slot.bold ? h.strong(number) : number, " ")
end

for mime in (MIME"text/html", MIME"application/vnd.hyperview+xml", MIME"text/markdown")
    @eval Base.show(io::IO, mime::$mime, slot::_CaptionNumber) = let node = _caption_number_node(slot)
        node isa Node && show(io, mime, node)
        nothing
    end
end
Base.show(io::IO, ::MIME"text/plain", slot::_CaptionNumber) = let words = _caption_words(slot)
    isnothing(words) || print(io, words, ": ")
    nothing
end
# Any text path writes what plain text does: the number, or nothing.
Base.show(io::IO, slot::_CaptionNumber) = show(io, MIME"text/plain"(), slot)
_static_walk(slot::_CaptionNumber, rules::_StaticRules) = _caption_number_node(slot)
_static_walk_child(slot::_CaptionNumber, rules) = _static_walk(slot, rules)

# --- Cross-references ---

struct _NumberRef
    anchor::String
end

"""
    ref(id)

A link to the numbered section, figure or table with the id `id` in the
[`numbered`](@ref) document it stands in, reading as its number: "Figure 3",
"Table 1", "Section 2.1" ("Abbildung 3", "Tabelle 1", "Abschnitt 2.1" in
German; see [`numbering_texts`](@ref)). It reads the same in the page, the
Markdown and the PDF.

The id is a section's `anchor`, or the `id` of [`with_caption`](@ref) or of a
captioned table (`render_table(…; id="doses")` gives the table the id
`"tbl-doses"`). An id that nothing numbered in the document carries, and a
`ref` outside a numbered document, throw an `ArgumentError` when it renders,
as a link to nothing would fail the PDF.
"""
ref(anchor::AbstractString) = isempty(anchor) ?
    throw(ArgumentError("ref: the id is empty")) : _NumberRef(String(anchor))

function _ref_node(r::_NumberRef)
    state = _NUMBERING[]
    isnothing(state) && throw(ArgumentError(
        "ref($(repr(r.anchor))) stands outside a numbered document; wrap the document in `numbered(…)`"))
    state.collecting && return ""
    words = get(state.anchors, r.anchor, nothing)
    isnothing(words) && throw(ArgumentError(string("ref: nothing numbered in this document has the id ",
        repr(r.anchor), isempty(state.anchors) ? "" :
        "; numbered ids: " * join(sort!(collect(keys(state.anchors))), ", "))))
    h.a(words; href="#" * r.anchor, class="htmxo-ref")
end

for mime in (MIME"text/html", MIME"application/vnd.hyperview+xml", MIME"text/markdown")
    @eval Base.show(io::IO, mime::$mime, r::_NumberRef) = let node = _ref_node(r)
        node isa Node && show(io, mime, node)
        nothing
    end
end
Base.show(io::IO, ::MIME"text/plain", r::_NumberRef) = let node = _ref_node(r)
    node isa Node && print(io, only(HTMX.children(node)))
    nothing
end
Base.show(io::IO, r::_NumberRef) = print(io, "ref(", repr(r.anchor), ")")
_static_walk(r::_NumberRef, rules::_StaticRules) = let node = _ref_node(r)
    node isa Node ? _static_walk(node, rules) : node
end
_static_walk_child(r::_NumberRef, rules) = _static_walk(r, rules)
_tabset_key(r::_NumberRef, h::UInt) = hash(r.anchor, hash("ref", h))

# --- The contents list ---

struct _Contents
    depth::Int
end

"""
    contents(; depth=3)

The contents list of the [`numbered`](@ref) document it stands in: its
numbered sections down to `depth` levels, each line its number and its title
linking to the section, under the title "Contents" ("Inhalt" in German; see
[`numbering_texts`](@ref)).

On the page it is a bordered box where it stands: the numbers in a column of
their own, deeper levels indented, no list markers. In a [`pdf_report`](@ref)
it becomes Typst's contents list at the same place, which shows the same
numbered sections with their page numbers (do not also pass
`metadata=(toc=true,)`, which `pdf_report` then refuses). It lists no other
heading: an article's header or a plain `h.h2` in the content stays a heading
of the PDF's body, out of its contents list. A [`SemanticSection`](@ref)
written outside the numbered document, such as a closing section a report
appends after it, is listed too, without a number. Its Markdown is a list of
links in a `::: {.htmxo-contents}` block; in a report's Markdown each listed
section's heading also carries the class `htmxo-contents-entry`, which the
PDF's contents list follows.
"""
contents(; depth::Integer=3) = depth >= 1 ? _Contents(Int(depth)) :
    throw(ArgumentError("contents: depth must be at least 1, not $depth"))

function _contents_state(c::_Contents)
    state = _NUMBERING[]
    isnothing(state) && throw(ArgumentError(
        "contents() stands outside a numbered document; wrap the document in `numbered(…)`"))
    state
end

function _contents_node(c::_Contents)
    state = _contents_state(c)
    state.collecting && return ""
    listed = [e for e in state.sections if e.depth <= c.depth]
    isempty(listed) && return ""
    h.nav(h.p(state.texts.contents; class="htmxo-contents-title"), _contents_ol(listed);
          class="htmxo-contents", aria_label=state.texts.contents)
end

# The entries of `listed`, each with those nested in it, as nested ordered lists.
function _contents_ol(listed::Vector{_SectionEntry})
    items = Any[]
    i = 1
    while i <= length(listed)
        e = listed[i]
        j = i + 1
        while j <= length(listed) && listed[j].depth > e.depth
            j += 1
        end
        inner = listed[i+1:j-1]
        link = h.a(h.span(e.number; class="htmxo-section-number"), " ", h.span(e.title); href="#" * e.anchor)
        push!(items, isempty(inner) ? h.li(link) : h.li(link, _contents_ol(inner)))
        i = j
    end
    h.ol(items...)
end

for mime in (MIME"text/html", MIME"application/vnd.hyperview+xml")
    @eval Base.show(io::IO, mime::$mime, c::_Contents) = let node = _contents_node(c)
        node isa Node && show(io, mime, node)
        nothing
    end
end

# Markdown: the links as a list in a block `pdf_report` replaces with Typst's
# outline, which needs the deepest heading level to list.
function Base.show(io::IO, ::MIME"text/markdown", c::_Contents)
    state = _contents_state(c)
    state.collecting && return
    listed = [e for e in state.sections if e.depth <= c.depth]
    isempty(listed) && return
    print(io, "::: {.htmxo-contents title=\"", _markdown_attr_value(state.texts.contents),
        "\" depth=\"", maximum(e -> e.level, listed), "\"}\n",
        "**", _markdown_plain_text(state.texts.contents), "**\n\n")
    for e in listed
        print(io, "    "^(e.depth - 1), "- [", _markdown_plain_text(e.number * " " * e.title), "](#", e.anchor, ")\n")
    end
    print(io, "\n:::")
end
function Base.show(io::IO, ::MIME"text/plain", c::_Contents)
    state = _contents_state(c)
    state.collecting && return
    listed = [e for e in state.sections if e.depth <= c.depth]
    isempty(listed) && return
    print(io, state.texts.contents)
    for e in listed
        print(io, "\n", "  "^(e.depth - 1), e.number, " ", e.title)
    end
end
Base.show(io::IO, c::_Contents) = print(io, "contents(; depth=", c.depth, ")")
HTMX.markdown_block(::_Contents) = true
_static_walk(c::_Contents, rules::_StaticRules) = let node = _contents_node(c)
    node isa Node ? _static_walk(node, rules) : _STATIC_REMOVED
end
_static_walk_child(c::_Contents, rules) = _static_walk(c, rules)
_tabset_key(c::_Contents, h::UInt) = hash(c.depth, hash("contents", h))

# Typst's outline would list every heading of the PDF: an article's header, a
# plain `h.h2` in a view, once per state of a `semantic_app`'s report (snag
# pdf-contents-lis-087ca53a). So a report's Markdown marks the headings it
# lists with this class, and `pdf-report-contents.lua` points the outline at
# them alone: the sections `contents()` lists, which have a number, and a
# section written outside any numbered document, such as a closing "About this
# document" a report appends to its numbered body. Not marked: the document's
# title (`level=1`), and a section inside a numbered document that took no
# number, such as one in a view the document's numbering never met. Only a
# report's Markdown carries the class; a `?plain` reader has no outline.
const _CONTENTS_ENTRY_CLASS = "htmxo-contents-entry"
_contents_entry_class(number, level::Integer) =
    page_report() && level >= 2 && (!isnothing(number) || isnothing(_NUMBERING[])) ?
        _CONTENTS_ENTRY_CLASS : ""

# A Pandoc attribute value in double quotes.
_markdown_attr_value(s) = replace(s, '\\' => "\\\\", '"' => "\\\"")

# --- The numbered document ---

# Its Markdown starts with this line, which tells `pdf_report` to switch off
# Quarto's and Typst's own figure and table numbers. A comment, so a reader of
# the Markdown sees nothing and Pandoc drops it.
const _NUMBERED_MARKER = "<!-- htmxo:numbered -->"

_numbered_html_node(doc::_Numbered) = h.div(doc.children...; class="htmxo-numbered")
_semantic_html_node(doc::_Numbered) = _numbered_html_node(doc)
_semantic_hxml_node(doc::_Numbered) = _with_numbers(doc; in_order=true) do
    h.div(map(_semantic_hxml_child, doc.children)...; class="htmxo-numbered")
end

Base.show(io::IO, mime::MIME"text/html", doc::_Numbered) =
    _with_numbers(() -> show(io, mime, _numbered_html_node(doc)), doc; in_order=true)
Base.show(io::IO, mime::MIME"application/vnd.hyperview+xml", doc::_Numbered) =
    _with_numbers(doc; in_order=true) do
        show(io, mime, h.div(map(_semantic_hxml_child, doc.children)...; class="htmxo-numbered"))
    end
# HTMX writes a node that another value's `show` prints later, after that
# `show` has returned: it first records the value's output to find the links
# in it. A node inside the document would then be written outside its numbers.
# So the document writes all of its Markdown to text while they hold, as one
# node, so that HTMX still pairs a link in one child with its target in another.
# HTMX may write that node twice; each write starts at `_NumberingStart`.
function Base.show(io::IO, mime::MIME"text/markdown", doc::_Numbered)
    _shows_nothing(doc.children, _ambient_audience()) && return
    text = _with_numbers(doc; in_order=false) do
        strip(sprint(show, mime, h.div(_NumberingStart(_NUMBERING[]), doc.children...)), '\n')
    end
    print(io, _NUMBERED_MARKER, "\n\n", text)
end
function Base.show(io::IO, mime::MIME"text/plain", doc::_Numbered)
    _with_numbers(() -> _semantic_show_children(io, mime, doc.children, "\n\n"), doc; in_order=false)
end
HTMX.markdown_block(doc::_Numbered) = !_shows_nothing(doc.children, _ambient_audience())
_shows_nothing(doc::_Numbered, audience) = _shows_nothing(doc.children, audience)
function _strip_md_chrome(doc::_Numbered)
    children = _strip_md_chrome_children(doc.children)
    _shows_nothing(children, _ambient_audience()) ? nothing : _numbered_like(doc, children)
end
_link_terms(doc::_Numbered, w::_TermWalk) = _numbered_like(doc, _link_children(doc.children, w))
# An export is HTML: its numbers are given as the export's reader reads it.
function _static_walk(doc::_Numbered, rules::_StaticRules)
    _with_audience(rules.spec.audience) do
        _with_numbers(() -> _static_walk(_numbered_html_node(doc), rules), doc; in_order=true)
    end
end
_static_walk_child(doc::_Numbered, rules) = _static_walk(doc, rules)

# Whether a report's Markdown holds a numbered document: the marker on a line
# of its own, outside fenced code.
_markdown_numbered(markdown) = _markdown_has_line(markdown, _NUMBERED_MARKER)
# Whether it holds a contents list.
_markdown_contents(markdown) = _markdown_has_line(markdown, r"^::: \{\.htmxo-contents[ }]")

function _markdown_has_line(markdown, pattern)
    fence = nothing
    for line in eachsplit(markdown, '\n')
        m = match(r"^ {0,3}(`{3,}|~{3,})", line)
        if !isnothing(fence)
            !isnothing(m) && startswith(m.captures[1], fence) && (fence = nothing)
        elseif !isnothing(m)
            fence = m.captures[1]
        elseif pattern isa Regex ? occursin(pattern, line) : rstrip(line) == pattern
            return true
        end
    end
    false
end
