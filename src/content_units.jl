# --- Content units: one identity, separately written layers, any depth ---
#
# A document made of units: a paragraph, an equation, a table or a heading over
# other units. Each unit has a stable id, layers its author wrote separately
# (an offer's wording, a short and a deep explanation) and children at any
# depth. `unit_tree` lowers them to the ordinary vocabulary (`SemanticSection`,
# `private`, a `<details>` per layer), so every peer, an export and a PDF reach
# them through the paths they already have, and a public reader's branch is
# built from public layers alone rather than filtered afterwards.

"""
    SemanticUnitLayer(name, label; public=false, standalone=false)

One layer of the units of a [`SemanticUnits`](@ref) document: its `name` (a
`Symbol`, the key in each unit's `layers`), the `label` a reader sees.

- `public`: whether the layer reaches a public reader. Layers are private unless
  they say otherwise, so a layer nobody thought about stays out of a public
  export.
- `standalone`: whether the layer's wording is all there is when it is read on
  its own: no unit title above it and no line of references below it. An offer's
  paragraph is what was approved, so it passes `standalone=true`; an explanation
  read alone needs to say what it explains. A group's heading stays either way.
"""
struct SemanticUnitLayer
    name::Symbol
    label::String
    public::Bool
    standalone::Bool
    function SemanticUnitLayer(name, label; public::Bool=false, standalone::Bool=false)
        layer = Symbol(name)
        _unit_layer_name_ok(layer) || throw(ArgumentError(
            "SemanticUnitLayer: a layer name is lower-case letters, digits, `_` or single `-`, " *
            "and not `all`; got $(repr(layer))"))
        new(layer, String(label), public, standalone)
    end
end

_unit_layer_name_ok(name::Symbol) = name !== :all &&
    occursin(r"^[a-z0-9_]+(-[a-z0-9_]+)*$", String(name))

"""
    SemanticUnit(id; title="", public_title=title, layers=(;), children=[], references=[], meta=nothing, open=nothing)

One unit of a [`SemanticUnits`](@ref) document: an independently meaningful
paragraph, equation, table or code block, or a heading over other units.

- `id`: its stable identity, the address of its links (`#<id>`). Letters,
  digits, `_`, `.`, `:` and single `-`.
- `title`, `public_title`: the unit's heading. `title` is what a public reader
  sees too wherever the unit reaches them; `public_title` gives them other
  wording.
- `layers`: what each layer says, by layer name (`(; offer=…, short=…, deep=…)`).
  Each is any content: a `String` is Markdown ([`SemanticProse`](@ref), so math
  and tables work), any other value renders as it does elsewhere. A unit without
  layers is a group: a heading over its children.
- `children`: the units below it, in order, to any depth.
- `references`: other units it refers to, by id. `"x--deep"` names layer `deep`
  of unit `x`. `"x" => "y"` names `y` for a reader who cannot reach `x`.
  Each becomes a link, never a copy of the text.
- `meta`: anything only private readers see beside it (a status, sources).
- `open`: whether its children start shown. By default a group's do and a
  content unit's sit closed under a control.
"""
struct SemanticUnit
    id::String
    title::String
    public_title::String
    layers::Dict{Symbol,Any}
    children::Vector{SemanticUnit}
    references::Vector{Pair{String,String}}
    meta::Any
    open::Union{Nothing,Bool}
    function SemanticUnit(id; title="", public_title=title, layers=(;), children=SemanticUnit[],
                          references=String[], meta=nothing, open::Union{Nothing,Bool}=nothing)
        unit_id = String(id)
        occursin(r"^[\p{L}\p{N}_.:]+(-[\p{L}\p{N}_.:]+)*$", unit_id) || throw(ArgumentError(
            "SemanticUnit: an id is letters, digits, `_`, `.`, `:` and single `-` " *
            "(`--` separates a layer in a link); got $(repr(unit_id))"))
        kids = SemanticUnit[]
        for child in children
            child isa SemanticUnit || throw(ArgumentError(
                "SemanticUnit $(repr(unit_id)): children are SemanticUnits, not $(typeof(child))"))
            push!(kids, child)
        end
        new(unit_id, String(title), String(public_title), _unit_layers(layers), kids,
            Pair{String,String}[_unit_reference_pair(r) for r in references], meta, open)
    end
end

# `nothing` is an absent layer, so a consumer can pass an optional one as it is.
function _unit_layers(layers)
    out = Dict{Symbol,Any}()
    for (name, content) in pairs(layers)
        isnothing(content) || (out[Symbol(name)] = content)
    end
    out
end

_unit_reference_pair(target::AbstractString) = String(target) => ""
_unit_reference_pair(target::Pair) = String(first(target)) => String(last(target))
_unit_reference_pair(target) = throw(ArgumentError(
    "SemanticUnit: a reference is an id or `id => fallback id`, not $(repr(target))"))

# "x--deep" is layer `deep` of unit `x`; a unit id cannot contain `--`.
function _unit_target(target::AbstractString)
    at = findfirst("--", target)
    isnothing(at) ? (String(target), nothing) :
        (String(target[begin:prevind(target, first(at))]), Symbol(target[nextind(target, last(at)):end]))
end

_unit_layer_anchor(id::AbstractString, layer::Symbol) = string(id, "--", layer)

"""
    UnitTexts

The words a content-unit document adds of its own: `view` (the name of the layer
switch), `all_layers` (its choice that shows every layer), `references` (the
line naming a unit's references), `children` (the control over a unit's
children, `{count}` being how many) and `link` (the name of the link to a unit's
layer). Build one with [`unit_texts`](@ref) and pass it as `texts=`.
"""
struct UnitTexts
    view::String
    all_layers::String
    references::String
    children::String
    link::String
end

const _UNIT_TEXT_LOCALES = (
    en = (view = "Reading depth", all_layers = "All layers", references = "See also",
          children = "Subpoints ({count})", link = "Link to this place"),
    de = (view = "Lesetiefe", all_layers = "Alle Ebenen", references = "Siehe auch",
          children = "Unterpunkte ({count})", link = "Link zu dieser Stelle"),
)

"""
    unit_texts(locale::Symbol=:en; texts...)

The [`UnitTexts`](@ref) for `locale` (`:en` or `:de`), with any of its texts
replaced by keyword. An unknown locale or text name, or a placeholder a text does
not take, throws an `ArgumentError`.
"""
unit_texts(locale::Symbol=:en; texts...) =
    _locale_texts(UnitTexts, :unit_texts, _UNIT_TEXT_LOCALES, (; children=(:count,)), locale; texts...)

"""
    SemanticUnits(units; layers, texts=unit_texts())

A document of [`SemanticUnit`](@ref)s: their order, the layers they may have (a
vector of [`SemanticUnitLayer`](@ref), the first being what a reader sees before
opening anything) and every id. It is the one scope the document's parts share:
[`unit_tree`](@ref), [`unit_reference`](@ref) and [`unit_view_control`](@ref)
each take it, so parts rendered separately (a section at a time, say) still
resolve each other's references.

The constructor checks the whole tree: an id used twice, a layer not declared, a
reference to a unit the document lacks, or to a layer that unit lacks, and a unit
without its first layer and without a title (nothing would say what it is) are
each an `ArgumentError`.

A reference resolves against this document, not against what a page places. So
build the document from the units that one page or PDF places, or Typst refuses a
PDF's link to a unit placed nowhere in it.

Rendering a `SemanticUnits` or a `SemanticUnit` directly is an error: go through
[`unit_tree`](@ref), which knows the reader.
"""
struct SemanticUnits
    units::Vector{SemanticUnit}
    layers::Vector{SemanticUnitLayer}
    texts::UnitTexts
    index::Dict{String,SemanticUnit}
    # The units that show, for each reader and view: a unit whose own layer or
    # any descendant's does. One pass per pair when built, so a page asking
    # about a reference in every row stays linear.
    shows::Dict{Tuple{Symbol,Union{Nothing,Symbol}},Set{String}}
    function SemanticUnits(units; layers, texts::UnitTexts=unit_texts())
        roots = SemanticUnit[u for u in units]
        declared = SemanticUnitLayer[l for l in layers]
        isempty(declared) && throw(ArgumentError("SemanticUnits: declare at least one layer"))
        names = [l.name for l in declared]
        allunique(names) || throw(ArgumentError("SemanticUnits: a layer is declared twice: $(names)"))
        index = Dict{String,SemanticUnit}()
        foreach(u -> _unit_index!(index, u), roots)
        doc_layers = Set(names)
        for unit in values(index)
            _unit_check(unit, index, doc_layers, first(names))
        end
        shows = Dict{Tuple{Symbol,Union{Nothing,Symbol}},Set{String}}()
        for audience in (:public, :private), view in Union{Nothing,Symbol}[nothing, names...]
            set = Set{String}()
            foreach(u -> _unit_shows!(set, u, declared, audience, view), roots)
            shows[(audience, view)] = set
        end
        new(roots, declared, texts, index, shows)
    end
end

function _unit_index!(index, unit::SemanticUnit)
    haskey(index, unit.id) && throw(ArgumentError(
        "SemanticUnits: the id $(repr(unit.id)) is used twice; a unit has one place, and other places refer to it"))
    index[unit.id] = unit
    foreach(c -> _unit_index!(index, c), unit.children)
end

function _unit_check(unit::SemanticUnit, index, doc_layers, base::Symbol)
    who = "SemanticUnit $(repr(unit.id))"
    for name in keys(unit.layers)
        name in doc_layers || throw(ArgumentError(
            "$who: layer $(repr(name)) is not declared; the document declares $(join(repr.(sort!(collect(doc_layers))), ", "))"))
    end
    isempty(unit.layers) && isempty(unit.children) && throw(ArgumentError(
        "$who has no layers and no children, so it says nothing"))
    !isempty(unit.layers) && !haskey(unit.layers, base) && isempty(unit.title) && throw(ArgumentError(
        "$who lacks the first layer ($(repr(base))) and has no title, so nothing would say what it is"))
    for (target, fallback) in unit.references, name in (target, fallback)
        isempty(name) || _unit_check_target(who, name, index)
    end
end

function _unit_check_target(who, target, index)
    id, layer = _unit_target(target)
    haskey(index, id) || throw(ArgumentError(
        "$who refers to $(repr(target)), which is not a unit of this document"))
    isnothing(layer) || haskey(index[id].layers, layer) || throw(ArgumentError(
        "$who refers to $(repr(target)), but unit $(repr(id)) has no layer $(repr(layer))"))
end

function _unit_shows!(set, unit::SemanticUnit, layers, audience, view)
    shown = !isempty(_unit_visible_layers(unit, layers, audience, view))
    for child in unit.children
        shown |= _unit_shows!(set, child, layers, audience, view)
    end
    shown && push!(set, unit.id)
    shown
end

_unit_visible(layer::SemanticUnitLayer, audience, view) =
    (audience !== :public || layer.public) && (isnothing(view) || view === layer.name)

_unit_visible_layers(unit::SemanticUnit, layers, audience, view) =
    SemanticUnitLayer[l for l in layers if haskey(unit.layers, l.name) && _unit_visible(l, audience, view)]

# A bare unit in a page would print its layers to every reader.
for T in (SemanticUnit, SemanticUnits)
    @eval Base.show(io::IO, value::$T) = print(io, nameof($T), "(",
        $T === SemanticUnit ? repr(getfield(value, :id)) : string(length(getfield(value, :index)), " units"), ")")
    for mime in (MIME"text/html", MIME"text/markdown", MIME"application/vnd.hyperview+xml")
        @eval Base.show(::IO, ::$mime, ::$T) = throw(ArgumentError(string(
            "a ", nameof($T), " has no rendering of its own: place unit_tree(doc, ids...), which knows the reader")))
    end
end

# One block of a unit: a `<div>`, or a `<details>` when it starts collapsed or
# open under a label. Text formats have nothing to collapse, so they write the
# whole body, under the label when `label_text` says so, in a fenced div when it
# has an anchor (`pdf_report` resolves a link to it).
struct _UnitPart <: SemanticNode
    children::Vector{Any}
    anchor::String
    class::String
    attrs::NamedTuple
    label::String
    label_text::Bool
    collapsed::Union{Nothing,Bool}
    link::Any
    _UnitPart(children; anchor="", class="", attrs=(;), label="", label_text=true, collapsed=nothing, link=nothing) =
        new(Any[c for c in children if !isnothing(c)], String(anchor), String(class), attrs,
            String(label), label_text, collapsed, link)
end

_unit_part_like(p::_UnitPart, children) = _UnitPart(children; anchor=p.anchor, class=p.class, attrs=p.attrs,
    label=p.label, label_text=p.label_text, collapsed=p.collapsed, link=p.link)

function _semantic_html_node(p::_UnitPart)
    _shows_nothing(p.children, _ambient_audience()) && return nothing
    shared = (; class=p.class, _semantic_anchor_attrs(p.anchor)..., p.attrs...)
    isnothing(p.collapsed) || return h.details(
        h.summary(p.label, (isnothing(p.link) ? () : (p.link,))...), p.children...;
        shared..., (p.collapsed ? (;) : (; open="true"))...)
    h.div((isnothing(p.link) ? () : (p.link,))...,
        (isempty(p.label) ? () : (h.small(p.label; class="htmxo-unit-label"),))...,
        p.children...; shared...)
end
for mime in (MIME"text/html", MIME"application/vnd.hyperview+xml")
    @eval Base.show(io::IO, mime::$mime, p::_UnitPart) =
        _show_semantic_peer(io, mime, _semantic_html_node(p))
end
function Base.show(io::IO, mime::MIME"text/markdown", p::_UnitPart)
    _shows_nothing(p.children, _ambient_audience()) && return
    isempty(p.anchor) || print(io, "::: ", _markdown_anchor_attr(p.anchor), "\n\n")
    p.label_text && !isempty(p.label) && print(io, "**", _markdown_plain_text(p.label), "**\n\n")
    _semantic_show_children(io, mime, p.children, "\n\n")
    isempty(p.anchor) || print(io, "\n\n:::")
end
function Base.show(io::IO, mime::MIME"text/plain", p::_UnitPart)
    _shows_nothing(p.children, _ambient_audience()) && return
    p.label_text && !isempty(p.label) && print(io, p.label, "\n\n")
    _semantic_show_children(io, mime, p.children, "\n\n")
end
HTMX.markdown_block(p::_UnitPart) = !_shows_nothing(p.children, _ambient_audience())
_shows_nothing(p::_UnitPart, audience) = _shows_nothing(p.children, audience)
function _strip_md_chrome(p::_UnitPart)
    children = _strip_md_chrome_children(p.children)
    _shows_nothing(children, _ambient_audience()) ? nothing : _unit_part_like(p, children)
end
function _static_walk(p::_UnitPart, rules::_StaticRules)
    peer = _static_peer(p, rules)
    isnothing(peer) ? _STATIC_REMOVED : _static_walk(peer, rules)
end
_link_terms(p::_UnitPart, w::_TermWalk) = _unit_part_like(p, _link_children(p.children, w))

# A control is a browser's: plain text has nothing to do with it (Markdown
# already writes nothing for `html_only`), and would print the wrapper.
_semantic_show_leaf(::IO, ::MIME"text/plain", ::HtmlOnly) = nothing

# One reader's view of the document: who reads, which layer alone (`nothing`
# for every layer they can reach), and whether this tree carries a mark of its
# own, which then is the only one.
struct _UnitView
    doc::SemanticUnits
    audience::Symbol
    layer::Union{Nothing,Symbol}
    base::Union{Nothing,Symbol}
    # Whether this reader has more than one layer to go between: otherwise
    # there is nothing to drill into, and what is below a unit is simply shown.
    drills::Bool
end

function _unit_view(doc::SemanticUnits, audience::Symbol, layer)
    visible = [l.name for l in doc.layers if _unit_visible(l, audience, nothing)]
    _UnitView(doc, audience, layer, isempty(visible) ? nothing : first(visible),
              isnothing(layer) && length(visible) > 1)
end

_unit_title(unit::SemanticUnit, audience) = audience === :public ? unit.public_title : unit.title

# Whether a link target exists for this reader and view, and where it points.
function _unit_anchor_for(doc::SemanticUnits, target::AbstractString, audience, view)
    id, layer = _unit_target(target)
    unit = get(doc.index, id, nothing)
    isnothing(unit) && return nothing
    id in doc.shows[(audience, view)] || return nothing
    isnothing(layer) && return id
    declared = findfirst(l -> l.name === layer, doc.layers)
    !isnothing(declared) && haskey(unit.layers, layer) && _unit_visible(doc.layers[declared], audience, view) ?
        _unit_layer_anchor(id, layer) : id
end

# A Markdown link inside a layer to a unit this reader cannot reach keeps its
# words: the address would name a private unit, and Typst refuses a link to a
# label that is not in the document. Any other link is left as written.
function _unit_prose_links(v::_UnitView, markdown::AbstractString)
    replace(markdown, r"\[([^\]]*)\]\(#([^)\s]+)\)" => function (link)
        m = match(r"^\[([^\]]*)\]\(#([^)\s]+)\)$", link)
        id, _ = _unit_target(m[2])
        haskey(v.doc.index, id) || return link
        anchor = _unit_anchor_for(v.doc, m[2], v.audience, v.layer)
        isnothing(anchor) ? String(m[1]) : string("[", m[1], "](#", anchor, ")")
    end)
end

_unit_content(v::_UnitView, x) = x
_unit_content(v::_UnitView, x::AbstractString) = SemanticProse(_unit_prose_links(v, x))
_unit_content(v::_UnitView, x::SemanticProse) = SemanticProse(_unit_prose_links(v, x.markdown); math=x.math)
_unit_content(v::_UnitView, x::AbstractVector) = Any[_unit_content(v, c) for c in x]

_unit_as_children(x::AbstractVector) = x
_unit_as_children(x) = Any[x]

function _unit_link_node(doc, anchor::AbstractString, label::AbstractString)
    SemanticLink(label, string("#", anchor))
end

function _unit_link_label(doc::SemanticUnits, anchor::AbstractString, audience)
    id, layer = _unit_target(anchor)
    title = _unit_title(doc.index[id], audience)
    isempty(title) && (audience === :public ? (return "") : (title = id))
    isnothing(layer) && return title
    at = findfirst(l -> l.name === layer, doc.layers)
    string(title, " (", doc.layers[at].label, ")")
end

function _unit_references(v::_UnitView, unit::SemanticUnit)
    links = Any[]
    seen = Set{String}([unit.id])  # a reference that came down to the unit itself says nothing
    for (target, fallback) in unit.references
        anchor = _unit_anchor_for(v.doc, target, v.audience, v.layer)
        isnothing(anchor) && !isempty(fallback) &&
            (anchor = _unit_anchor_for(v.doc, fallback, v.audience, v.layer))
        isnothing(anchor) && continue
        anchor in seen && continue
        push!(seen, anchor)
        label = _unit_link_label(v.doc, anchor, v.audience)
        isempty(label) && continue
        isempty(links) || push!(links, ", ")
        push!(links, _unit_link_node(v.doc, anchor, label))
    end
    isempty(links) && return nothing
    _UnitPart(Any[h.p(h.strong(v.doc.texts.references, ":"), " ", links...)]; class="htmxo-unit-refs")
end

function _unit_permalink(v::_UnitView, anchor)
    label = v.doc.texts.link
    h.a("#"; href=string("#", anchor), class="htmxo-unit-link", title=label, aria_label=label)
end

# One layer of a unit. Read alone it is just its content. Among other layers the
# first is shown under its label and the others open under theirs; what a public
# export leaves out says so inside, where a closed control does not repeat it.
function _unit_panel(v::_UnitView, unit::SemanticUnit, layer::SemanticUnitLayer, count)
    content = _unit_as_children(_unit_content(v, unit.layers[layer.name]))
    anchor = _unit_layer_anchor(unit.id, layer.name)
    attrs = (; data_htmxo_unit_layer=String(layer.name))
    class = "htmxo-unit-layer"
    isnothing(v.layer) || return _UnitPart(content; anchor, class, attrs)
    marked = v.audience !== :public && !layer.public
    body = marked ? Any[private(content)] : content
    label = count > 1 || layer.name !== v.base ? layer.label : ""
    collapsed = layer.name === v.base ? nothing : true
    _UnitPart(body; anchor, class, attrs, label, collapsed, link=_unit_permalink(v, anchor))
end

function _unit_node(v::_UnitView, unit::SemanticUnit)
    unit.id in v.doc.shows[(v.audience, v.layer)] || return nothing
    layers = _unit_visible_layers(unit, v.doc.layers, v.audience, v.layer)
    kids = Any[_unit_node(v, child) for child in unit.children]
    filter!(!isnothing, kids)
    group = isempty(unit.layers)
    body = Any[]
    !isnothing(unit.meta) && v.audience !== :public && isnothing(v.layer) &&
        push!(body, _UnitPart(Any[private(unit.meta)]; class="htmxo-unit-meta"))
    foreach(l -> push!(body, _unit_panel(v, unit, l, length(layers))), layers)
    # A layer that stands alone (an offer's approved wording) gets nothing added.
    annotated = isempty(layers) || any(l -> !l.standalone, layers)
    annotated && push!(body, _unit_references(v, unit))
    if !isempty(kids)
        shown = !v.drills || something(unit.open, group)
        push!(body, shown ? _UnitPart(kids; class="htmxo-unit-children") :
            _UnitPart(kids; class="htmxo-unit-children", collapsed=true, label_text=false,
                label=replace(v.doc.texts.children, "{count}" => string(length(kids)))))
    end
    filter!(!isnothing, body)
    title = _unit_title(unit, v.audience)
    titled = !isempty(title) && annotated
    attrs = (; data_htmxo_unit=unit.id)
    class = group ? "htmxo-unit htmxo-unit-group" : "htmxo-unit htmxo-unit-content"
    block = titled ? _UnitPart(Any[SemanticSection(title, body; anchor=unit.id)]; class, attrs) :
        _UnitPart(body; anchor=unit.id, class, attrs)
    # A unit with nothing public is not public as a whole; its parts are then
    # not marked again.
    v.audience !== :public && isnothing(v.layer) && !(unit.id in v.doc.shows[(:public, nothing)]) ?
        private(block) : block
end

function _unit_roots(doc::SemanticUnits, ids)
    isempty(ids) && return doc.units
    SemanticUnit[get(() -> throw(ArgumentError(
        "$(repr(id)) is not a unit of this document")), doc.index, String(id)) for id in ids]
end

function _unit_layer_arg(doc::SemanticUnits, layer, who)
    isnothing(layer) && return nothing
    name = Symbol(layer)
    any(l -> l.name === name, doc.layers) || throw(ArgumentError(string(who, ": ", repr(name),
        " is not a layer of this document; it declares ", join(repr.(getfield.(doc.layers, :name)), ", "))))
    name
end

"""
    unit_tree(doc, ids...; layer=nothing, control=true)

The units `ids` of a [`SemanticUnits`](@ref) document with everything below them,
or the whole document without `ids`, as ordinary content to place in a page,
a section or an answer. This is where a unit lives on a page: give each unit one
such place, and use [`unit_reference`](@ref) wherever else it comes up.

Headings follow the [`SemanticSection`](@ref) nesting where it is placed.

**`layer=nothing`** gives every layer the reader may read. A browser shows the
first layer of each unit and opens the others in place under their labels.
Markdown, plain text and a PDF write them one after the other, each under its
label. **`layer=:short`** gives that one layer alone: complete and in order, with
no labels or controls and without the units that lack it (and their groups, when
nothing below them has it). This is the read and export of one layer.

**Who reads it** is the page's audience ([`private`](@ref)), separate from the
layer. Only layers declared `public=true` reach a public reader: the other
layers, their labels, and the ids and titles of units with nothing public exist
in the private branch only, so they are absent from a public page, its Markdown,
its PDF and its static export. Asking a public reader for a private layer gives
nothing. A private reader sees the parts a public export would leave out marked
as such: inside each closed layer, or once over a tree that is one private layer.

Each unit's element has the id `<id>`, each layer's `<id>--<layer>`, in HTML and
in Markdown. A link to either opens the `<details>` holding it
([`unit_script`](@ref)). `control=false` leaves out the layer switch
([`unit_view_control`](@ref)), for a page that places it once itself.
"""
function unit_tree(doc::SemanticUnits, ids...; layer=nothing, control::Bool=true)
    view = _unit_layer_arg(doc, layer, "unit_tree")
    roots = _unit_roots(doc, ids)
    tree(audience) = begin
        v = _unit_view(doc, audience, view)
        nodes = Any[_unit_node(v, root) for root in roots]
        filter!(!isnothing, nodes)
        isempty(nodes) ? nothing : _UnitPart(nodes; class="htmxo-units-body")
    end
    # One layer read on its own is all one thing, private or not, so it needs
    # one mark at most. Among several layers the marks are the parts' own.
    declared = isnothing(view) ? nothing : doc.layers[findfirst(l -> l.name === view, doc.layers)]
    mark = !isnothing(declared) && !declared.public
    content = Private(tree(:private), tree(:public), mark)
    _UnitPart(control && isnothing(view) ? Any[unit_view_control(doc), content] : Any[content]; class="htmxo-units")
end

"""
    unit_reference(doc, target; label=nothing, layer=nothing, fallback=nothing)

A link to a unit of a [`SemanticUnits`](@ref) document, for a place that mentions
the unit without being where it lives: a table's row, a summary, another page
part. `target` is its id, or `"id--deep"` for one of its layers. It is the unit's
title (with the layer's label) unless `label` says otherwise.

A reader the target does not show for gets the `fallback` target instead, or
nothing at all, never an address to something that is not there. Pass the same
`layer` as the [`unit_tree`](@ref) of the same view, so a reference to a unit
without that layer goes too. An id the document lacks is an `ArgumentError`.
"""
function unit_reference(doc::SemanticUnits, target::AbstractString; label=nothing, layer=nothing, fallback=nothing)
    who = "unit_reference"
    _unit_check_target(who, target, doc.index)
    isnothing(fallback) || _unit_check_target(who, fallback, doc.index)
    view = _unit_layer_arg(doc, layer, who)
    link(audience) = begin
        anchor = _unit_anchor_for(doc, target, audience, view)
        isnothing(anchor) && !isnothing(fallback) && (anchor = _unit_anchor_for(doc, fallback, audience, view))
        isnothing(anchor) && return nothing
        text = isnothing(label) ? _unit_link_label(doc, anchor, audience) : String(label)
        isempty(text) ? nothing : _unit_link_node(doc, anchor, text)
    end
    Private(link(:private), link(:public), false)
end

"""
    unit_ids(doc, ids...)

The ids [`unit_tree`](@ref)`(doc, ids...)` places, in document order: `ids` with
every unit below them, or the whole document without `ids`. A caller placing
several trees on one page checks with it that no unit is placed twice, which
would repeat its element ids. An id the document lacks is an `ArgumentError`.
"""
function unit_ids(doc::SemanticUnits, ids...)
    out = String[]
    walk(unit) = (push!(out, unit.id); foreach(walk, unit.children))
    foreach(walk, _unit_roots(doc, ids))
    out
end

"""
    unit_view_control(doc; param="layer", id=nothing)

The switch that reads a page at one layer: "all layers" (the default) or one
layer alone, for every unit of the page, in the browser and with no request. The
choice stays in the page address (`?layer=short`), so a link, a reload and a
static export keep it. Radios, so the arrow keys choose.

[`unit_tree`](@ref) places one by default; a page holding several trees of one
document passes them `control=false` and places this once. A reader who can reach
only one layer has nothing to switch and gets nothing, so a public page has none.
It is HTML only, absent from Markdown, plain text and a PDF.

It governs the whole page unless an ancestor carries `data-htmxo-unit-scope`: then
it governs only the units directly in that element, and not those in a scope nested
inside it. Documents side by side each take a scope and a `param` of their own.
"""
function unit_view_control(doc::SemanticUnits; param::AbstractString="layer", id=nothing)
    control(audience) = begin
        layers = SemanticUnitLayer[l for l in doc.layers if _unit_visible(l, audience, nothing)]
        length(layers) > 1 || return nothing
        radio(value, label, checked) = h.label(h.input(; type="radio", name=string("htmxo-unit-view-", param),
            value, (checked ? (; checked="true") : (;))...), label)
        html_only(h.fieldset(h.legend(doc.texts.view), radio("all", doc.texts.all_layers, true),
            [radio(String(l.name), l.label, false) for l in layers]...;
            class="htmxo-unit-view", data_htmxo_unit_view=String(param),
            (isnothing(id) ? (;) : (; id=String(id)))...))
    end
    Private(control(:private), control(:public), false)
end

"""
    unit_script()

Client runtime of [`unit_tree`](@ref), carried by every [`htmx`](@ref) page and
kept by static exports, inert on a page without units. It needs no server.

An address naming a unit or a layer (`#id`, `#id--deep`) opens every `<details>`
around it: on load, on a link's click, on Back and Forward, and when an htmx swap
brings it later. Opening or closing a layer writes it into the address, so a
reload keeps it. The layer switch ([`unit_view_control`](@ref)) reads and writes
its parameter.

Two synchronous events let a page holding units in something else (a table's
rows) make way, both with `detail = {id, layer}`:

- `htmxo:unit-before-reveal` on `document`, before the runtime looks the target
  up, for every address and in-page link it handles, so a handler can put the
  target back into the page. It fires for any `#…`, so a handler checks the id.
- `htmxo:unit-reveal`, bubbling, on the target element once it exists, before the
  runtime opens anything, so a handler can show a collapsed row around it.

`window.htmxoUnits.reveal(x)` does the same for an anchor or an element.

Include it yourself only on pages built without the shell.
"""
unit_script() = h.script(Raw(raw"""
(function () {
  'use strict';
  if (window.htmxoUnits) return;
  function all(q, scope) { return Array.prototype.slice.call((scope || document).querySelectorAll(q)); }
  function embedded(el) { return !!(el && el.closest && el.closest('.htmxo-embed')); }
  function hashAnchor() {
    var id = location.hash.slice(1);
    if (!id) return null;
    try { id = decodeURIComponent(id); } catch (e) {}
    return id;
  }
  function parsed(anchor) {
    var at = anchor.indexOf('--');
    return at < 0 ? { id: anchor, layer: null } : { id: anchor.slice(0, at), layer: anchor.slice(at + 2) };
  }
  // A page may hold the target somewhere it can bring back; it does so here.
  function beforeReveal(anchor) {
    document.dispatchEvent(new CustomEvent('htmxo:unit-before-reveal', { detail: parsed(anchor) }));
  }
  function unitElement(anchor) {
    var el = document.getElementById(anchor);
    return el && el.closest('[data-htmxo-unit]') ? el : null;
  }
  // A view belongs to a scope: the nearest `data-htmxo-unit-scope`, else the
  // page. Only what is directly in a scope follows its control.
  function scopeOf(el) { return el.closest('[data-htmxo-unit-scope]') || document; }
  function own(q, scope) { return all(q, scope).filter(function (el) { return scopeOf(el) === scope; }); }
  function controlOf(scope) { return own('[data-htmxo-unit-view]', scope)[0] || null; }
  // One control per scope reads the address; one in an embed leaves it alone.
  function addressed() {
    var seen = [];
    return all('[data-htmxo-unit-view]').filter(function (c) {
      var scope = scopeOf(c);
      if (embedded(c) || seen.indexOf(scope) >= 0) return false;
      seen.push(scope);
      return true;
    });
  }
  function viewFromAddress(c) {
    if (!c) return null;
    var value = new URLSearchParams(location.search).get(c.getAttribute('data-htmxo-unit-view'));
    if (!value || value === 'all') return null;
    var known = all('input[type="radio"]', c).some(function (r) { return r.value === value; });
    if (!known) console.warn('unit_view_control: this page has no layer "' + value + '"');
    return known ? value : null;
  }
  var views = new WeakMap();
  function viewOf(scope) { return views.get(scope) || null; }
  // Opened by a view rather than by the reader, so leaving the view closes it.
  function autoOpen(d) {
    if (d.open) return;
    d.open = true;
    d.setAttribute('data-htmxo-unit-auto', '');
  }
  function apply(scope, next) {
    views.set(scope, next);
    own('[data-htmxo-unit-view] input[type="radio"]', scope).forEach(function (r) {
      r.checked = r.value === (next || 'all');
    });
    var units = own('[data-htmxo-unit]', scope), layers = own('[data-htmxo-unit-layer]', scope);
    if (!next) {
      units.concat(layers).forEach(function (el) { el.hidden = false; });
      own('details[data-htmxo-unit-auto]', scope).forEach(function (d) {
        d.open = false;
        d.removeAttribute('data-htmxo-unit-auto');
      });
      return;
    }
    units.forEach(function (u) { u.hidden = true; });
    layers.forEach(function (l) {
      var match = l.getAttribute('data-htmxo-unit-layer') === next;
      l.hidden = !match;
      if (!match) return;
      if (l.tagName === 'DETAILS') autoOpen(l);
      // Up to the first unit already shown, so this stays linear in the page.
      for (var u = l.closest('[data-htmxo-unit]'); u && u.hidden; u = u.parentElement && u.parentElement.closest('[data-htmxo-unit]')) {
        u.hidden = false;
      }
    });
    own('details.htmxo-unit-children', scope).forEach(autoOpen);
  }
  // Every scope as its address says. A scope with nothing in its address that
  // shows nothing chosen is left as it is, so a swap costs a page without a
  // chosen layer nothing.
  function applyAddress(force) {
    addressed().forEach(function (c) {
      var scope = scopeOf(c), v = viewFromAddress(c);
      if (v || force || viewOf(scope)) apply(scope, v);
    });
  }
  function writeView(c, next) {
    if (embedded(c)) return;
    var url = new URL(location.href), name = c.getAttribute('data-htmxo-unit-view');
    if (next) url.searchParams.set(name, next); else url.searchParams.delete(name);
    history.replaceState(history.state, '', url.pathname + url.search + url.hash);
    try { sessionStorage.setItem('htmx-current-path-for-history', url.pathname + url.search); } catch (e) {}
  }
  function detailOf(el) {
    var unit = el.closest('[data-htmxo-unit]'), panel = el.closest('[data-htmxo-unit-layer]');
    return { id: unit ? unit.getAttribute('data-htmxo-unit') : null,
             layer: panel ? panel.getAttribute('data-htmxo-unit-layer') : null };
  }
  function reveal(x) {
    var el = x;
    if (typeof x === 'string') {
      beforeReveal(x);
      el = unitElement(x);
    }
    if (!el || !el.closest('[data-htmxo-unit]')) return null;
    el.dispatchEvent(new CustomEvent('htmxo:unit-reveal', { bubbles: true, detail: detailOf(el) }));
    // A link to what the chosen layer hides leaves that layer.
    var scope = scopeOf(el);
    if (viewOf(scope) && el.closest('[hidden]')) {
      var c = controlOf(scope);
      apply(scope, null);
      if (c) writeView(c, null);
    }
    for (var d = el; d; d = d.parentElement) {
      if (d.tagName === 'DETAILS' && !d.open) {
        d.open = true;
        d.removeAttribute('data-htmxo-unit-auto');
      }
    }
    return el;
  }
  function land(scroll) {
    var anchor = hashAnchor();
    if (!anchor) return;
    var el = reveal(anchor);
    if (el && scroll) requestAnimationFrame(function () { el.scrollIntoView(); });
  }
  function setHash(id) {
    history.replaceState(history.state, '', location.pathname + location.search + '#' + id);
  }
  // Writes the address for what the reader opens or closes. A click is the one
  // signal that it was the reader: a `toggle` event also follows a script.
  function recordSummary(summary) {
    var d = summary.parentElement;
    if (!d || d.tagName !== 'DETAILS' || !d.id || !d.hasAttribute('data-htmxo-unit-layer') || embedded(d)) return;
    var unit = d.closest('[data-htmxo-unit]');
    if (!d.open) setHash(d.id);
    else if (location.hash.slice(1) === d.id && unit) setHash(unit.getAttribute('data-htmxo-unit'));
  }
  document.addEventListener('click', function (e) {
    var t = e.target;
    if (!t || !t.closest) return;
    var summary = t.closest('summary');
    if (summary) { recordSummary(summary); return; }
    var a = t.closest('a[href^="#"]');
    if (a && a.getAttribute('href').length > 1) {
      var id = a.getAttribute('href').slice(1);
      try { id = decodeURIComponent(id); } catch (err) {}
      reveal(id);
    }
  }, true);
  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t || !t.matches || !t.matches('[data-htmxo-unit-view] input[type="radio"]')) return;
    var c = t.closest('[data-htmxo-unit-view]');
    var next = t.value === 'all' ? null : t.value;
    apply(scopeOf(c), next);
    writeView(c, next);
  });
  window.addEventListener('hashchange', function () { land(true); });
  function start() {
    applyAddress(false);
    // A reload or Back restores its own scroll position, as for any `#id`.
    var nav = window.performance && performance.getEntriesByType ? performance.getEntriesByType('navigation')[0] : null;
    land(!nav || nav.type === 'navigate');
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
  document.addEventListener('htmx:load', function (e) {
    var scope = e.target;
    if (!scope || !scope.querySelector) return;
    var hasUnits = scope.matches('[data-htmxo-unit]') || scope.querySelector('[data-htmxo-unit]');
    if (!hasUnits && !scope.matches('[data-htmxo-unit-view]') && !scope.querySelector('[data-htmxo-unit-view]')) return;
    applyAddress(false);
    var anchor = hashAnchor(), el = hasUnits && anchor && unitElement(anchor);
    // `url_anchor_script` holds an address's target in view through swaps.
    if (el && scope.contains(el)) reveal(el);
  });
  // A snapshot keeps the attributes a view set, but not a radio's choice.
  document.addEventListener('htmx:historyRestore', function () { applyAddress(true); land(false); });
  window.htmxoUnits = { reveal: reveal, view: function (el) { return viewOf(el ? scopeOf(el) : document); } };
})();
"""))

"""
    unit_styles()

The look of [`unit_tree`](@ref): a content unit's heading no larger than its
text, each first layer's label, the link to a layer, and the line of references.
Carried by every [`htmx`](@ref) page and kept by static exports.
"""
unit_styles() = h.style(Raw("""
@layer htmxo {
  .htmxo-units { --htmxo-unit-gap: 0.75rem; }
  .htmxo-unit { margin-block-end: var(--htmxo-unit-gap); }
  .htmxo-unit-content > .htmxo-semantic-section > :is(h1, h2, h3, h4, h5, h6) {
    margin-block-end: 0.35rem; font-size: 1em; font-weight: 600;
  }
  .htmxo-unit-group > .htmxo-semantic-section > :is(h1, h2, h3, h4, h5, h6) { margin-block-end: 0.5rem; }
  .htmxo-unit-layer { margin-block-end: 0.5rem; }
  div.htmxo-unit-layer:has(> .htmxo-unit-link) { position: relative; padding-inline-end: 1.75rem; }
  .htmxo-unit-layer > :last-child, .htmxo-unit-layer .htmxo-semantic-prose > :last-child { margin-block-end: 0; }
  .htmxo-unit-label { display: block; margin-block-end: 0.15rem; font-size: 0.8em; color: var(--htmxo-muted, inherit); }
  .htmxo-unit-link {
    padding-inline: 0.3rem; font-weight: 400;
    color: var(--htmxo-muted, inherit); text-decoration: none;
  }
  div.htmxo-unit-layer > .htmxo-unit-link { position: absolute; inset-block-start: 0; inset-inline-end: 0; }
  summary > .htmxo-unit-link { float: inline-end; }
  .htmxo-unit-link:hover, .htmxo-unit-link:focus-visible { text-decoration: underline; }
  @media (hover: hover) {
    .htmxo-unit-link { opacity: 0; }
    .htmxo-unit-layer:hover > .htmxo-unit-link, .htmxo-unit-link:focus-visible { opacity: 1; }
  }
  .htmxo-unit-refs { font-size: 0.875em; margin-block-end: 0.5rem; }
  .htmxo-unit-refs > p { margin-block-end: 0; }
  .htmxo-unit-children { margin-block-start: 0.5rem; }
  .htmxo-unit-meta { margin-block-end: 0.5rem; }
  .htmxo-unit-view { margin-block-end: 1rem; }
}
"""))
