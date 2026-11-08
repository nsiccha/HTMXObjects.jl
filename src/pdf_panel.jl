# --- PDF panel: a document beside the text, its quoted passages marked ---
#
# A side panel that shows a PDF (every page one below the other, each drawn by
# PDF.js as it comes into view) or an HTML document (a fragment the app serves,
# loaded with an htmx GET) beside the content that quotes it. The references in
# the content (`pdf_ref`) name the document, the page or anchor and the quoted
# words; each reference's passage is marked in the document, in the
# reference's colour. Every reference and mark is always lightly highlighted; pointing at
# one shows it and its counterpart more strongly without moving anything; only
# a click moves: a reference's click opens the panel at its passage, a mark's
# click goes to its reference. References, marks and any linked table rows
# share one hover-link group (`htmxo:link`).

"""
    PdfPanelTexts

The words of a [`pdf_panel`](@ref): its accessible name and
[`pdf_toggle`](@ref)'s text (`label`), the document chooser's name
(`documents`) and, for a long list of documents, its search field (`search`,
and `no_match` when no document matches), the page line (`page`, with
`{page}` and `{pages}`), the bar's buttons (`previous_page`, `next_page`,
`colours`, `colours_help`, `open_file`, `close`), the status line
(`loading`, `failed`, `not_found` on a PDF's page, `not_in_document` in an
HTML document, `empty`), and where the panel stands: the placement switch
(`placement`, with `beside`, `right` and `bottom`), the edge that resizes it
(`resize`) and the tab a closed panel leaves (`reopen`).
Build one with [`pdf_panel_texts`](@ref).
"""
struct PdfPanelTexts
    label::String           # the panel's accessible name; pdf_toggle's text
    documents::String       # the document chooser's accessible name
    search::String          # a long chooser's search field
    no_match::String        # ... when no document matches the search
    page::String            # the page line: "{page}" of "{pages}"
    previous_page::String
    next_page::String
    colours::String         # the switch that colours every passage
    colours_help::String
    open_file::String       # the link that opens the file itself
    close::String
    loading::String         # status: the file is loading
    failed::String          # status: the file could not be shown (the error follows)
    not_found::String       # status: the quoted words are not on the page
    not_in_document::String # status: the quoted words are not in the HTML document
    empty::String           # status: the panel opened before any reference
    placement::String       # the placement switch's accessible name
    beside::String          # ... pinned beside the text
    right::String           # ... over the page, on the right
    bottom::String          # ... over the page, below
    resize::String          # the edge that resizes the panel
    reopen::String          # the tab a closed panel leaves on its edge
end

const _PDF_TEXT_PLACEHOLDERS = (page = (:page, :pages),)

const _PDF_TEXT_LOCALES = (
    en = (
        label = "Document",
        documents = "Documents",
        search = "Search…",
        no_match = "No matching document",
        page = "page {page} of {pages}",
        previous_page = "Previous page",
        next_page = "Next page",
        colours = "Colours",
        colours_help = "Each reference and its passage in a colour of its own",
        open_file = "Open file",
        close = "Close",
        loading = "Loading the document …",
        failed = "The file could not be shown",
        not_found = "The quoted words were not found on this page",
        not_in_document = "The quoted words were not found in this document",
        empty = "No document yet: a reference opens its document here.",
        placement = "Where the document stands",
        beside = "Beside the text",
        right = "Over the page, on the right",
        bottom = "Over the page, below",
        resize = "Size of the document",
        reopen = "Show the document again",
    ),
    de = (
        label = "Dokument",
        documents = "Dokumente",
        search = "Suchen…",
        no_match = "Kein passendes Dokument",
        page = "Seite {page} von {pages}",
        previous_page = "Vorige Seite",
        next_page = "Nächste Seite",
        colours = "Farben",
        colours_help = "Jeder Verweis und seine Stelle in einer eigenen Farbe",
        open_file = "Datei öffnen",
        close = "Schließen",
        loading = "Dokument wird geladen …",
        failed = "Die Datei konnte nicht angezeigt werden",
        not_found = "Die zitierten Worte stehen nicht auf dieser Seite",
        not_in_document = "Die zitierten Worte stehen nicht in diesem Dokument",
        empty = "Noch kein Dokument: Ein Verweis öffnet sein Dokument hier.",
        placement = "Wo das Dokument steht",
        beside = "Neben dem Text",
        right = "Über der Seite, rechts",
        bottom = "Über der Seite, unten",
        resize = "Größe des Dokuments",
        reopen = "Dokument wieder zeigen",
    ),
)

"""
    pdf_panel_texts(locale::Symbol=:en; texts...)

The [`PdfPanelTexts`](@ref) for `locale` (`:en` or `:de`), with any of its
texts replaced by keyword:

```julia
pdf_panel(docs; id="originals", texts=pdf_panel_texts(:de; label="Originale"))
```

Without `texts=`, [`pdf_panel`](@ref) and [`pdf_toggle`](@ref) write in the
page's language ([`HTMXObjects.page_lang`](@ref): German under `__lang__ = "de"`,
English for any other and outside a route). An unknown locale or text name,
or a placeholder the text does not take, throws an `ArgumentError`.
"""
pdf_panel_texts(locale::Symbol=:en; texts...) =
    _locale_texts(PdfPanelTexts, :pdf_panel_texts, _PDF_TEXT_LOCALES, _PDF_TEXT_PLACEHOLDERS, locale; texts...)

# The texts of the page's language: German under `__lang__ = "de"`, else English.
_pdf_texts(::Nothing) = pdf_panel_texts(_lang_locale(_PDF_TEXT_LOCALES, page_lang()))
_pdf_texts(texts::PdfPanelTexts) = texts
_pdf_texts(texts) = throw(ArgumentError("pdf_panel: `texts` takes a PdfPanelTexts (pdf_panel_texts(…)), got $(repr(texts))"))

# PDF.js, loaded from jsDelivr the first time a panel shows a file.
const _PDFJS_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/"

# A file's address without its fragment: a reference's `#page=` is its own.
_pdf_url(url::AbstractString) = String(first(split(url, '#'; limit=2)))

# The name a file goes by when nothing names it: the `path=` of an address
# that serves a path (`/code/raw?path=docs/plan.pdf`), else its last segment.
function _pdf_file_name(url::AbstractString)
    uri = HTTP.URI(_pdf_url(url))
    path = get(HTTP.queryparams(uri), "path", HTTP.unescapeuri(uri.path))
    name = last(split(rstrip(path, '/'), '/'))
    isempty(name) ? String(url) : String(name)
end

# What a document is: a PDF, drawn by PDF.js, or an HTML document, a fragment
# the panel loads with an htmx GET. LOCKSTEP: `kindOf` in the script, and the
# static export's `_static_panel_url` in HTMXObjects.jl.
const _PDF_KINDS = (:pdf, :html)
const _PDF_KIND_ATTR = Symbol("data-htmxo-pdf-kind")
_pdf_kind(fname, kind) = kind in _PDF_KINDS ? kind : throw(ArgumentError(
    "$fname: `kind` is :pdf or :html, got $(repr(kind))"))
# An element the static export reads as one that loads an HTML document.
_pdf_html(attrs) = get(attrs, _PDF_KIND_ATTR, "") == "html"

# A document of the panel as (title, address, kind).
_pdf_document(url::AbstractString) = (_pdf_file_name(url), _pdf_url(url), :pdf)
_pdf_document(d::Pair{<:AbstractString,<:AbstractString}) = (String(first(d)), _pdf_url(last(d)), :pdf)
function _pdf_document(d::NamedTuple)
    haskey(d, :url) && d.url isa AbstractString && !isempty(d.url) && all(in((:url, :title, :kind)), keys(d)) ||
        throw(ArgumentError("pdf_panel: a document record is `(; url, title, kind)` with a non-empty `url`, got $(repr(d))"))
    title = get(d, :title, nothing)
    title === nothing || title isa AbstractString || throw(ArgumentError(
        "pdf_panel: a document's `title` is a string, got $(repr(title))"))
    (title === nothing ? _pdf_file_name(d.url) : String(title), _pdf_url(d.url),
     _pdf_kind("pdf_panel", get(d, :kind, :pdf)))
end
_pdf_document(d) = throw(ArgumentError(
    "pdf_panel: a document is its address, `title => address` or `(; url, title, kind)`, got $(repr(d))"))

"""
    pdf_panel(documents=(); id, link=id, texts=nothing, pdfjs, class="", assets=true)

A side panel that shows a document beside the content that quotes it, with
the passage of every [`pdf_ref`](@ref) to it marked in the reference's colour.
A PDF is every page of the file one below the other, each drawn as it comes
into view (PDF.js, loaded from jsDelivr the first time the panel shows a PDF),
each passage marked on its page. An HTML document (`kind=:html`) is the
fragment its address answers to an htmx GET, as an [`htmx`](@ref) page would
swap it in: its code is highlighted as the page highlights code, and each
passage is marked over its words without changing the fragment.
It starts closed. A reference's click opens it at its passage, a
[`pdf_toggle`](@ref) shows and hides it, and its bar has the document chooser,
the page line with previous and next page, "Colours" (each passage in its own
colour, or only the passages pointed at and gone to), a link that opens the
file itself and a close button. [`pdf_beside`](@ref) places it beside the
content, pinned while the content scrolls by; [`pdf_overlay`](@ref) floats it
over the page, on the right or below. Either can offer the reader a switch
between those placements, and the panel's inner edge resizes it.

- `documents`: the documents the chooser offers, PDFs and HTML documents
  together, each its address (a PDF named by its file name),
  `title => address` (a PDF), or a record `(; url, title, kind)` whose `kind`
  is `:pdf` (the default) or `:html`. A reference to a document not listed
  adds it.
- `id`: the panel's element id, which references and toggles name.
- `link`: the hover-link group (`htmxo:link`) of the references, their
  marks and any table rows showing the same items; defaults to `id`.
- `texts`: a [`pdf_panel_texts`](@ref); by default those of the page's
  language.
- `pdfjs`: the base address of PDF.js's `build/` directory.
- `assets=false` leaves out the panel's style and script, for a page that
  carries [`pdf_panel_assets`](@ref) itself.

**The document chooser** is never a native select box. One document is its
title, as text. Two to eight are a row of pills, one per document, the one
shown filled ([`radio_group`](@ref)'s look). More are a field showing the
document shown that opens a searchable list of them ([`choice_list`](@ref)).
A reference that adds a file draws it again in the form its new number of
documents takes. The chooser is the element marked `data-htmxo-pdf-document`;
each document in it is a radio whose value is the file's address (a browser
test checks it, or clicks its label), and the lone title carries the address
as `data-htmxo-pdf-url`. The pills and the list take their look and their
script from the page ([`htmxo_utility_styles`](@ref),
[`choice_list_script`](@ref)), which every [`htmx`](@ref) page carries.

**How it behaves** (the same for every reference and mark):

- every reference and its mark is always lightly highlighted, in its colour;
- pointing at a reference (or a linked table row) shows the reference and its
  mark more strongly, and pointing at a mark shows its references; nothing
  scrolls;
- a click on a reference opens the panel at its passage, scrolled a third of
  the way down, and marks it most strongly until another is clicked; a click
  on a mark goes to its reference;
- a document chosen in the chooser opens at its first page, whatever page
  the panel was at in the file before. The moment another file is chosen or
  referenced, the pages, the page line and the place of the one shown go,
  and the panel says it is loading until the new file is shown.

While the panel goes to a page, its pages (the element marked
`data-htmxo-pdf-pages`) carry `aria-busy="true"`: a browser test waits for
that to go before it reads the page line.

The passage is found where the page holds the quoted words, or the longest
beginning of them (at least 24 letters), comparing letters and digits only, so
line breaks, hyphenation and quotes in the PDF do not matter. Where neither
is on the page, the panel goes to the page's top and says so.

**An HTML document** has no pages: a reference names its place as the
address's `#anchor` (an element id in the fragment, such as a heading's), and
the panel opens there, or at the passage when the reference quotes words.
The quoted words are looked for from the anchor on, then in the whole
document, compared as for a PDF; where they are not there, the panel goes to
the anchor (else the top) and says so. The page line and its buttons are
hidden while an HTML document is shown. Its passages are boxes over the
words, as on a PDF's page, and follow them when the panel's width changes or
a script changes the fragment (code highlighted after it arrived). Its
address answers the htmx GET (`HX-Request: true`) with a fragment, as an
[`htmx`](@ref) route does; a failed answer is shown as the panel's failure.

Script hooks: `window.htmxoPdf.show(panel, {url, page, key, kind, anchor})` and
`window.htmxoPdf.toggle(panel, open)` (`panel` an element or its id). The
panel dispatches `htmxo:pdf-toggle` (detail `{open}`) when it opens or
closes, and a cancelable `htmxo:pdf-goto` (detail `{key, group}`) before a
mark's click goes to its reference: call `preventDefault()` to go there
yourself (to open the collapsed group a table row sits in, say).

The panel is HTML only: a Markdown answer leaves it out.

**In a static export** ([`export_site`](@ref), a [`StaticExport`](@ref)
`dispatch`, `record!`) every file the panel and its references load is
rewritten as their links are: each reference's file, the lone document's and
each chooser document's address. The panel therefore shows the file the
export wrote, served from the bundle's root or a subdirectory, and
`export_site` follows every one of them. An HTML document's address is
rewritten as an `hx-get` is, to the fragment the export writes below `hx/`,
while a reference's link names the page. A document keeps the title the live
page gives it. PDF.js still comes from `pdfjs` (by default jsDelivr), which is
not rewritten.

```julia
@get bericht() = pdf_beside(
    h.article(h.p("Der Träger sichert den Kinderschutz ",
        pdf_ref("(Konzept, S. 12)", "/files/konzept.pdf"; page=12, panel="originale",
                quoted="Kinderschutz ist Aufgabe aller Träger"), ".",
        " Gemeldet wird binnen eines Tages ",
        pdf_ref("(Verfahren)", "/verfahren#meldung"; kind=:html, panel="originale",
                quoted="binnen eines Tages an das Jugendamt"), ".")),
    pdf_panel(["Konzept" => "/files/konzept.pdf",
               (title="Verfahren", url="/verfahren", kind=:html)]; id="originale"))
```
"""
function pdf_panel(documents=(); id::AbstractString, link::AbstractString=id, texts=nothing,
                   pdfjs::AbstractString=_PDFJS_URL, class::AbstractString="", assets::Bool=true)
    isempty(id) && throw(ArgumentError("pdf_panel: `id` must not be empty"))
    isempty(link) && throw(ArgumentError("pdf_panel: `link` must not be empty"))
    t = _pdf_texts(texts)
    docs = [_pdf_document(d) for d in (documents isa Union{AbstractString,Pair,NamedTuple} ? (documents,) : documents)]
    urls = [url for (_, url, _) in docs]
    length(unique(urls)) == length(docs) || throw(ArgumentError(
        "pdf_panel: a document is listed twice: $(join(unique(filter(u -> count(==(u), urls) > 1, urls)), ", "))"))
    first_url = isempty(docs) ? nothing : first(urls)
    panel = h.aside(; id, class=isempty(class) ? "htmxo-pdf-panel" : "htmxo-pdf-panel " * class,
                    hidden=true, aria_label=t.label, data_htmxo_pdf_viewer="", data_htmxo_pdf_link=link,
                    data_htmxo_pdfjs=endswith(pdfjs, '/') ? pdfjs : pdfjs * "/",
                    data_htmxo_pdf_hues="on",
                    data_text_page=t.page, data_text_loading=t.loading, data_text_failed=t.failed,
                    data_text_not_found=t.not_found, data_text_not_in_document=t.not_in_document, data_text_empty=t.empty,
                    data_text_documents=t.documents, data_text_search=t.search, data_text_no_match=t.no_match,
                    data_text_resize=t.resize, data_text_reopen=t.reopen)(
        (assets ? pdf_panel_assets() : ())...,
        h.div(; class="htmxo-pdf-bar")(
            _pdf_chooser(id, docs, t),
            # The controls stay together, the page line between its buttons:
            # a long title or many pills take a line of their own instead.
            h.div(; class="htmxo-pdf-controls")(
                h.span(; class="htmxo-pdf-pager")(
                    h.button(; type="button", data_htmxo_pdf_step="-1", aria_label=t.previous_page, title=t.previous_page)("‹"),
                    h.span(; class="htmxo-pdf-page-info", data_htmxo_pdf_page_info="")(),
                    h.button(; type="button", data_htmxo_pdf_step="1", aria_label=t.next_page, title=t.next_page)("›")),
                h.button(; type="button", data_htmxo_pdf_colours="", aria_pressed="true", title=t.colours_help)(t.colours),
                h.a(; data_htmxo_pdf_file="", href=first_url, target="_blank", rel="noopener")(t.open_file * " ↗"),
                _pdf_place_switch(t),
                h.button(; type="button", data_htmxo_pdf_close="", aria_label=t.close, title=t.close)("✕"))),
        h.p(; class="htmxo-pdf-note", data_htmxo_pdf_note="", role="status")(),
        h.div(; class="htmxo-pdf-pages", data_htmxo_pdf_pages="")())
    html_only(panel)
end

# Where a panel can stand (`pdf_beside`, `pdf_overlay`): pinned beside the
# content, or over the page on the right or below. LOCKSTEP: `PLACES` in the
# script.
const _PDF_PLACEMENTS = (:beside, :right, :bottom)

# The placement switch: one button per placement, all hidden until the script
# shows those the panel's place offers (two or more). Each icon draws the
# window, the panel filled.
const _PDF_PLACE_ICONS = (
    beside = """<rect x="1" y="2.75" width="8" height="10.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="10.5" y="2" width="4.5" height="12" rx="1.25" fill="currentColor"/>""",
    right = """<rect x="1" y="2.75" width="14" height="10.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="8.5" y="2" width="6.5" height="12" rx="1.25" fill="currentColor"/>""",
    bottom = """<rect x="1" y="2.75" width="14" height="10.5" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="1" y="7.5" width="14" height="6.5" rx="1.25" fill="currentColor"/>""",
)
_pdf_place_switch(t::PdfPanelTexts) =
    h.span(; class="htmxo-pdf-places", role="group", aria_label=t.placement, data_htmxo_pdf_places="", hidden=true)(
        (h.button(; type="button", data_htmxo_pdf_place=string(p), aria_pressed="false", aria_label=getfield(t, p),
                  title=getfield(t, p), hidden=true)(
            Raw("""<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false">""" *
                getfield(_PDF_PLACE_ICONS, p) * "</svg>"))
         for p in _PDF_PLACEMENTS)...)

# The placements a `pdf_beside` or `pdf_overlay` offers (`allowed` of them),
# as given, and the one it starts in.
function _pdf_placements(fname, placements, placement, allowed)
    list = placements isa Symbol ? [placements] : collect(placements)
    isempty(list) && throw(ArgumentError("$fname: `placements` names at least one of $(join(repr.(allowed), ", "))"))
    for p in list
        p in allowed || throw(ArgumentError("$fname: a placement is one of $(join(repr.(allowed), ", ")), got $(repr(p))"))
    end
    allunique(list) || throw(ArgumentError("$fname: a placement is named twice in $(repr(placements))"))
    placement = something(placement, first(list))
    placement in list || throw(ArgumentError("$fname: `placement` is one of `placements` ($(join(repr.(list), ", "))), got $(repr(placement))"))
    (join(string.(list), ' '), string(placement))
end

# The radios of a panel's chooser share a name of their own, so two panels
# never uncheck each other's documents. LOCKSTEP: `redraw` in the script.
_pdf_choice_name(id::AbstractString) = "htmxo-pdf-document-" * id

# The document chooser, never a native select box (the user's rule, decision
# `VerkehrsStrukturdaten:ux/19mny0l`): one document is its title, a few a row
# of pills (`radio_group`), a long list a searchable list (`_choice_list`, past
# `_RADIO_MAX` as for generated forms). The first document is the one chosen.
# The script draws it again in these forms when a reference adds a file
# (`redraw`), reading the threshold from `data-htmxo-pdf-pills`.
#
# An HTML document's title or radio says so (`data-htmxo-pdf-kind="html"`), so
# the script loads it as one and a static export maps its address as a
# fragment's.
function _pdf_chooser(id::AbstractString, docs, t::PdfPanelTexts)
    name, n = _pdf_choice_name(id), length(docs)
    first_url = n == 0 ? nothing : docs[1][2]
    kind(k) = k === :html ? "html" : nothing
    form = n == 0 ? () :
        n == 1 ? (h.span(docs[1][1]; class="htmxo-pdf-title", data_htmxo_pdf_url=first_url,
                         data_htmxo_pdf_kind=kind(docs[1][3])),) :
        n <= _RADIO_MAX ? (radio_group(name, [url => title for (title, url, _) in docs]; label=t.documents, value=first_url),) :
        (_choice_list(name, t.documents, [(; value=url, label=title) for (title, url, _) in docs], first_url;
                      texts=error_texts(:en; choice_search=t.search, choice_no_match=t.no_match)),)
    html = Set(url for (_, url, k) in docs if k === :html)
    n > 1 && !isempty(html) && (form = map(node -> _pdf_mark_html(node, html), form))
    h.div(; class="htmxo-pdf-documents", data_htmxo_pdf_document="", data_htmxo_pdf_pills=string(_RADIO_MAX))(form...)
end

# The chooser's radios of the HTML documents `html` (their addresses) marked
# as such; everything else as it is.
_pdf_mark_html(x, html) = x
_pdf_mark_html(xs::AbstractVector, html) = Any[_pdf_mark_html(x, html) for x in xs]
function _pdf_mark_html(node::Node, html::Set{String})
    attrs = HTMX.attrs(node)
    if HTMX.tag(node) === :input && get(attrs, :type, "") == "radio" && get(attrs, :value, nothing) in html
        attrs = copy(attrs)
        attrs[_PDF_KIND_ATTR] = "html"
    end
    Node(HTMX.tag(node), attrs, Any[_pdf_mark_html(child, html) for child in HTMX.children(node)])
end

"""
    pdf_ref(text, url; page=nothing, panel, quoted=nothing, key=nothing, hue=nothing,
            document=nothing, kind=:pdf, attrs...)

A reference to a passage of a document: a link to `url` at `page`
(`url#page=12`), or for an HTML document (`kind=:html`) to `url` as given,
that, on a page with the [`pdf_panel`](@ref) `panel`, opens that panel at the
passage instead, marked. It is a chip: always lightly highlighted in its
colour, more strongly while pointed at, most strongly once clicked. A
modified click (new tab, new window) and a page without the panel open the
document itself. Its Markdown is the link, `[text](url#page=12)`.

- `page`: the page of a PDF the passage stands on, counted from 1 as a PDF
  viewer counts, not the number printed on the page; 1 when not given. An
  HTML document has no pages and refuses one.
- `kind`: `:pdf` (the default) or `:html`, an HTML document the panel loads
  with an htmx GET. The `#anchor` of its address (`/methodik#annahmen`) names
  the element the passage stands in (a section's heading, say): the panel
  opens there, and looks for the quoted words from there on first.
- `quoted`: the quoted words. Every reference with a quote marks its passage
  (on its page of a PDF); one without opens the page's top (the anchor, else
  the top, of an HTML document) and marks nothing.
- `key`: the passage's key in the panel's hover-link group. References with
  one key share one mark (the same passage quoted twice), and a table row
  keyed alike (`link=`, **Hover linking**) lights it too. It defaults to a
  digest of `url`, `page` (or anchor) and `quoted`.
- `hue`: the colour, 1 to 8, of HTMXObjects' categorical palette
  (`--htmxo-category-1` …); by default one picked from `key`, so a passage
  keeps its colour wherever it is quoted. Give neighbouring references
  different hues (`hue=mod1(i, 8)`) where they stand in a list.
- `document`: the document's title in the panel's chooser when the panel does
  not list it; by default its file name (as `url` names it, so a static export
  that gives the file another address titles it alike).
- `attrs` go on the link (`class`, `title`, `id`, …).

A reference inside a table row of the panel's link group takes the row's key:
the row announces its key when pointed at, so give the reference the row's
link key.

```julia
pdf_ref("(Annahmen)", "/methodik#annahmen"; kind=:html, panel="quellen",
        quoted="die Fahrten je Zone folgen einer Poisson-Verteilung")
```
"""
function pdf_ref(text, url::AbstractString; page=nothing, panel::AbstractString, quoted=nothing,
                 key=nothing, hue=nothing, document=nothing, kind::Symbol=:pdf, attrs...)
    isempty(url) && throw(ArgumentError("pdf_ref: `url` must not be empty"))
    isempty(panel) && throw(ArgumentError("pdf_ref: `panel` must name the pdf_panel's id"))
    _pdf_kind("pdf_ref", kind)
    html = kind === :html
    html && page !== nothing && throw(ArgumentError(
        "pdf_ref: an HTML document has no pages; name the passage's place as the address's `#anchor`, got page=$(repr(page))"))
    page = something(page, 1)
    page isa Integer && page >= 1 || throw(ArgumentError("pdf_ref: `page` counts from 1, got $(repr(page))"))
    quoted === nothing || quoted isa AbstractString || throw(ArgumentError(
        "pdf_ref: `quoted` is the quoted words as a string, got $(repr(quoted))"))
    quoted isa AbstractString && isempty(strip(quoted)) && (quoted = nothing)
    hue === nothing || (hue isa Integer && 1 <= hue <= _TALLY_PALETTE) || throw(ArgumentError(
        "pdf_ref: `hue` is a colour of the categorical palette, 1 to $_TALLY_PALETTE, got $(repr(hue))"))
    file = _pdf_url(url)
    # An HTML document's place is its address's own fragment; a PDF's is its page.
    anchor = html ? _pdf_anchor(url) : nothing
    place = html ? (anchor === nothing ? "" : "#" * anchor) : string("#page=", page)
    key = key === nothing ? (quoted === nothing ? nothing : _thread_digest(string(file, place, "\n", quoted))) :
        string(key)
    hue = hue === nothing ? (key === nothing ? nothing : Int(_fnv1a(key) % _TALLY_PALETTE) + 1) : Int(hue)
    # The title is named here, from the address the app serves, so a static
    # export (which gives the file another address) titles it as the live page.
    h.a(; href=string(file, place), data_htmxo_pdf_ref="", data_htmxo_pdf_panel=panel,
        data_htmxo_pdf_url=file, data_htmxo_pdf_page=html ? nothing : string(page),
        data_htmxo_pdf_kind=html ? "html" : nothing, data_htmxo_pdf_anchor=anchor, data_htmxo_pdf_quote=quoted,
        data_htmxo_pdf_key=key, data_htmxo_pdf_hue=hue === nothing ? nothing : string(hue),
        data_htmxo_pdf_document=document === nothing ? _pdf_file_name(file) : string(document),
        aria_controls=panel, attrs...)(text)
end

# The fragment of an address (`/methodik#annahmen` → "annahmen"), or nothing.
function _pdf_anchor(url::AbstractString)
    parts = split(url, '#'; limit=2)
    length(parts) == 2 && !isempty(parts[2]) ? String(parts[2]) : nothing
end

"""
    pdf_toggle(panel, label=nothing; texts=nothing, attrs...)

A button that shows and hides the [`pdf_panel`](@ref) `panel` (its id),
pressed while the panel is open. Opened before any reference was clicked,
the panel shows its first document at page 1. `label` defaults to the
panel's `texts.label` in the page's language. HTML only.
"""
pdf_toggle(panel::AbstractString, label=nothing; texts=nothing, attrs...) =
    html_only(h.button(; type="button", data_htmxo_pdf_toggle=panel, aria_controls=panel,
                       aria_pressed="false", attrs...)(something(label, _pdf_texts(texts).label)))

"""
    pdf_beside(content, panel; placements=(:beside,), placement=first(placements), class="")

`content` with the [`pdf_panel`](@ref) `panel` beside it: while the panel is
open the two share the width (the panel 40 %, at least 22rem; set
`--htmxo-pdf-width` to change it) and the panel stays in view while the
content scrolls by, below a page's own sticky header (`--htmxo-sticky-top`).
Closed, the content has the whole width. Opening or closing it keeps the
reference clicked last (else the content at the top of the window, below
a table's sticky header) where it was on screen while the content wraps
anew.

- `placements`: where the reader can have the panel, of `:beside` (pinned
  beside the content, which narrows), `:right` and `:bottom` (floating over
  the page, as [`pdf_overlay`](@ref) floats it, the content keeping its
  width). With two or more, the panel's bar has a switch between them.
- `placement`: the one it opens in until the reader picks another.

The divider between the content and the panel resizes it (drag it, or focus
it and use the arrow keys). On a narrow screen (48rem or less) the open panel
lies over the lower part of the window whatever the placement. See
[`pdf_overlay`](@ref) for what the reader's choices keep, the tab a closed
panel leaves, and a panel opened from a modal dialog.
"""
function pdf_beside(content, panel; placements=(:beside,), placement=nothing, class::AbstractString="")
    list, start = _pdf_placements("pdf_beside", placements, placement, _PDF_PLACEMENTS)
    h.div(; class=isempty(class) ? "htmxo-pdf-beside" : "htmxo-pdf-beside " * class, data_htmxo_pdf_beside="",
          data_htmxo_pdf_placements=list, data_htmxo_pdf_placement=start, data_htmxo_pdf_default=start)(
        h.div(; class="htmxo-pdf-beside-content")(content), panel)
end

"""
    pdf_overlay(panel; placements=(:right, :bottom), placement=first(placements), class="")

The [`pdf_panel`](@ref) `panel` floating over the page while it is open, so
the page keeps its width and layout: on the right (`:right`, 40 % of the
window, at least 22rem, below a page's own sticky header
`--htmxo-sticky-top`; `--htmxo-pdf-width`), or below (`:bottom`, the whole
width, half the window high; `--htmxo-pdf-sheet-height`). `placements` are
those the reader can choose between, with a switch in the panel's bar when
there are two; `placement` is the one it opens in until the reader picks
another. Mount it once, outside the region htmx swaps, with an empty
document list, and every [`pdf_ref`](@ref) naming its id opens it, also one
a later swap brings and one inside an open modal dialog:

```julia
__page__(content) = htmx(h.main(content, pdf_overlay(pdf_panel(; id="quellen"))))
```

**What the reader's choices keep.** The placement picked last and each
placement's size are kept in the browser (`localStorage`, under
`htmxo-pdf-placement` and `htmxo-pdf-size-<placement>`), for every panel
that offers that placement; where the browser keeps nothing, the panel opens
as the app says. The panel's inner edge resizes it: drag it (mouse, pen or
touch), or focus it and use the arrow keys (Home and End for the smallest
and largest size).

**Closing it leaves a tab on its edge** once it has shown a document; the
tab reopens it at the same document and place. [`pdf_toggle`](@ref) works as
beside the content.

**The clicked reference stays in view**: a reference that the panel below
would cover is scrolled up just above it, and the page gains the room below
its end to do so. (A panel on the right lies over the right of the page; a
reference there stays under it.)

**From a modal dialog** (`dialog.showModal()`, whose top layer makes the
rest of the page inert): a reference inside it opens the panel inside the
dialog, floating above it and usable there (on the right, or below, as the
reader chose), and the panel goes back to its place on the page, still
open, when the dialog closes. Something that replaces the dialog's content
leaves the panel in it.

On a narrow screen (48rem or less) the open panel lies over the lower part
of the window whatever the placement, and the switch is hidden. HTML only:
a Markdown answer leaves it out.
"""
function pdf_overlay(panel; placements=(:right, :bottom), placement=nothing, class::AbstractString="")
    list, start = _pdf_placements("pdf_overlay", placements, placement, (:right, :bottom))
    html_only(h.div(; class=isempty(class) ? "htmxo-pdf-float" : "htmxo-pdf-float " * class, data_htmxo_pdf_float="",
                    data_htmxo_pdf_placements=list, data_htmxo_pdf_placement=start, data_htmxo_pdf_default=start)(panel))
end

"""
    pdf_panel_styles()

CSS for [`pdf_panel`](@ref), [`pdf_ref`](@ref), [`pdf_beside`](@ref) and
[`pdf_overlay`](@ref).
Layout sits inside `@layer htmxo`; the references, marks and the bar's
controls are unlayered, because Pico styles links and buttons unlayered.
"""
pdf_panel_styles() = h.style(Raw(raw"""
@layer htmxo {
.htmxo-pdf-panel {
    box-sizing: border-box; overflow: auto; overscroll-behavior: contain; scrollbar-gutter: stable;
    max-height: var(--htmxo-pdf-height, 80vh); padding: 0 .5rem .5rem; font-size: .875rem;
    border: 1px solid var(--pico-muted-border-color, color-mix(in srgb, currentColor 20%, transparent));
    border-radius: var(--pico-border-radius, .25rem); background: var(--pico-background-color, Canvas);
}
.htmxo-pdf-panel[hidden] { display: none; }
.htmxo-pdf-bar {
    position: sticky; top: 0; z-index: 1; display: flex; flex-wrap: wrap; align-items: center; gap: .35rem;
    padding: .5rem 0; background: var(--pico-background-color, Canvas);
}
/* The chooser stays beside the controls while all of it fits there, else it
   takes a line of its own, where pills flow and a title too long for the line
   wraps rather than being cut off; the controls stay together, the page line
   between its buttons. */
.htmxo-pdf-documents { flex: 1 1 auto; min-width: 0; }
.htmxo-pdf-title { display: block; font-weight: 600; overflow-wrap: anywhere; }
.htmxo-pdf-controls { display: flex; flex-wrap: wrap; align-items: center; gap: .35rem; margin-left: auto; }
.htmxo-pdf-pager { display: inline-flex; align-items: center; gap: .35rem; white-space: nowrap; }
.htmxo-pdf-page-info { white-space: nowrap; }
.htmxo-pdf-note { margin: 0 0 .35rem; color: var(--htmxo-muted, GrayText); }
.htmxo-pdf-note:empty { display: none; }
.htmxo-pdf-pages { display: grid; gap: .5rem; justify-content: start; }
.htmxo-pdf-page { position: relative; background: #fff; box-shadow: 0 0 0 1px var(--pico-muted-border-color, #ccc); }
.htmxo-pdf-page canvas { display: block; }
.htmxo-pdf-marks { position: absolute; inset: 0; pointer-events: none; }
/* An HTML document: the fragment at the panel's width in the page's text
   size, its passages boxes over its words in a layer of their own; no page
   line. */
.htmxo-pdf-panel[data-htmxo-pdf-kind="html"] .htmxo-pdf-pages { display: block; }
.htmxo-pdf-panel[data-htmxo-pdf-kind="html"] .htmxo-pdf-pager { display: none; }
.htmxo-pdf-doc { position: relative; display: flow-root; font-size: 1rem; }   /* its content's margins stay inside it */
.htmxo-pdf-html { overflow-wrap: anywhere; }
/* Where the panel stands (pdf_beside, pdf_overlay, and the carrier a modal
   dialog holds it in): the wrapper says which placement is shown
   (`data-htmxo-pdf-placement`). Its cell is the panel, or the private wrapper
   around it (which carries its "not public" mark). The reader's size, set on
   the wrapper by the resize edge, wins over the app's; the spans are the
   panel's width on the right and its height below. */
[data-htmxo-pdf-placements] {
    --htmxo-pdf-surface: var(--pico-background-color, Canvas); --htmxo-pdf-ink: var(--pico-color, CanvasText);
    --htmxo-pdf-span: min(100%, max(var(--htmxo-pdf-reader-width, 22rem), var(--htmxo-pdf-reader-width, var(--htmxo-pdf-width, 40%))));
    --htmxo-pdf-rise: min(calc(100% - var(--htmxo-sticky-top, 0px) - 2.5rem), var(--htmxo-pdf-reader-height, var(--htmxo-pdf-sheet-height, 50dvh)));
}
/* Beside: the content, the divider that resizes the panel, the panel. */
.htmxo-pdf-beside[data-htmxo-pdf-open][data-htmxo-pdf-placement="beside"] {
    display: grid; gap: 0; align-items: start;
    grid-template-columns: minmax(0, 1fr) 1rem
        minmax(min(var(--htmxo-pdf-reader-width, 22rem), 100%), var(--htmxo-pdf-reader-width, var(--htmxo-pdf-width, 40%)));
}
/* Closed after showing a document, its tab stands at the content's edge. */
.htmxo-pdf-beside[data-htmxo-pdf-placement="beside"]:not([data-htmxo-pdf-open]):has(> .htmxo-pdf-tab:not([hidden])) {
    display: grid; gap: .5rem; align-items: start; grid-template-columns: minmax(0, 1fr) auto;
}
.htmxo-pdf-beside > .htmxo-pdf-beside-content { min-width: 0; grid-column: 1; grid-row: 1; }
/* What sticks is the grid's cell: the panel, or the private wrapper around
   it, so it never scrolls away in a box no taller than itself. */
[data-htmxo-pdf-placement="beside"] > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
    grid-column: 3; grid-row: 1;
    position: sticky; top: calc(var(--htmxo-sticky-top, 0px) + .5rem);
    max-height: calc(100vh - var(--htmxo-sticky-top, 0px) - 1rem);
    max-height: calc(100dvh - var(--htmxo-sticky-top, 0px) - 1rem);
}
[data-htmxo-pdf-placements] > .htmxo-private:has(> .htmxo-pdf-panel) { display: flex; flex-direction: column; align-items: flex-start; }
[data-htmxo-pdf-placements] > .htmxo-private > .htmxo-pdf-panel { align-self: stretch; flex: 1 1 auto; min-height: 0; max-height: none; }
[data-htmxo-pdf-placements] > .htmxo-private:has(> .htmxo-pdf-panel[hidden]) { display: none; }
/* Floating over the page, which keeps its width and layout: on the right,
   below the page's own sticky header, or below, the whole width. */
[data-htmxo-pdf-placement="right"] > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)),
[data-htmxo-pdf-placement="bottom"] > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
    position: fixed; z-index: var(--htmxo-pdf-layer, 30); box-sizing: border-box; margin: 0; max-height: none;
    background: var(--pico-background-color, Canvas);
}
[data-htmxo-pdf-placement="right"] > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
    top: var(--htmxo-sticky-top, 0px); right: 0; bottom: 0; width: var(--htmxo-pdf-span);
    border-radius: var(--pico-border-radius, .25rem) 0 0 var(--pico-border-radius, .25rem);
    box-shadow: -6px 0 18px rgba(0, 0, 0, .2);
}
[data-htmxo-pdf-placement="bottom"] > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
    left: 0; right: 0; bottom: 0; height: var(--htmxo-pdf-rise);
    border-radius: var(--pico-border-radius, .25rem) var(--pico-border-radius, .25rem) 0 0;
    box-shadow: 0 -6px 18px rgba(0, 0, 0, .2);
}
/* Below, the pages (and an HTML document's lines) keep a reading width. */
[data-htmxo-pdf-placement="bottom"] .htmxo-pdf-pages { max-width: var(--htmxo-pdf-page-width, 56rem); margin-inline: auto; }
/* The edge that resizes the panel: the divider beside the content, the
   panel's left edge on the right, its top edge below. Wide enough for a
   finger; its grip is the line drawn in it. */
.htmxo-pdf-resize {
    box-sizing: border-box; display: flex; align-items: center; justify-content: center;
    touch-action: none; user-select: none; -webkit-user-select: none; z-index: calc(var(--htmxo-pdf-layer, 30) + 1);
}
.htmxo-pdf-resize::before {
    content: ""; border-radius: 999px; transition: background-color .12s;
    background: color-mix(in srgb, var(--pico-color, CanvasText) 30%, transparent);
}
.htmxo-pdf-resize:is(:hover, :focus-visible, [data-htmxo-pdf-dragging])::before { background: var(--pico-primary, Highlight); }
.htmxo-pdf-resize:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: -2px; }
[data-htmxo-pdf-placements]:not([data-htmxo-pdf-open]) > .htmxo-pdf-resize { display: none; }
[data-htmxo-pdf-placement="beside"] > .htmxo-pdf-resize {
    grid-column: 2; grid-row: 1; position: sticky; top: calc(var(--htmxo-sticky-top, 0px) + .5rem); cursor: col-resize;
    height: calc(100vh - var(--htmxo-sticky-top, 0px) - 1rem); height: calc(100dvh - var(--htmxo-sticky-top, 0px) - 1rem);
}
[data-htmxo-pdf-placement="right"] > .htmxo-pdf-resize {
    position: fixed; top: var(--htmxo-sticky-top, 0px); bottom: 0; width: 1rem; right: calc(var(--htmxo-pdf-span) - .5rem); cursor: col-resize;
}
[data-htmxo-pdf-placement="bottom"] > .htmxo-pdf-resize {
    position: fixed; left: 0; right: 0; height: 1rem; bottom: calc(var(--htmxo-pdf-rise) - .5rem); cursor: row-resize;
}
:is([data-htmxo-pdf-placement="beside"], [data-htmxo-pdf-placement="right"]) > .htmxo-pdf-resize::before { width: 4px; height: 2.5rem; }
[data-htmxo-pdf-placement="bottom"] > .htmxo-pdf-resize::before { width: 2.5rem; height: 4px; }
/* The tab a closed panel leaves on its edge. */
.htmxo-pdf-tab { z-index: var(--htmxo-pdf-layer, 30); }
.htmxo-pdf-tab[hidden] { display: none; }
[data-htmxo-pdf-placement="beside"] > .htmxo-pdf-tab {
    grid-column: 2; grid-row: 1; position: sticky; top: calc(var(--htmxo-sticky-top, 0px) + 40vh);
}
[data-htmxo-pdf-placement="right"] > .htmxo-pdf-tab { position: fixed; right: 0; top: 50%; transform: translateY(-50%); }
[data-htmxo-pdf-placement="bottom"] > .htmxo-pdf-tab { position: fixed; right: 1.5rem; bottom: 0; }
/* Room below the page's end, so a reference there can stand above the panel below. */
.htmxo-pdf-room { pointer-events: none; }
}
.htmxo-pdf-controls button { width: auto; margin: 0; padding: .15rem .55rem; font-size: inherit; line-height: 1.4; }
.htmxo-pdf-controls [data-htmxo-pdf-close] { margin-left: auto; }
/* The placement switch: joined buttons (Pico's group look) of their own
   size, not the bar's whole width; hidden on a narrow screen, where every
   placement lies below. */
.htmxo-pdf-controls > .htmxo-pdf-places[role="group"] { display: inline-flex; width: auto; margin: 0; vertical-align: middle; }
.htmxo-pdf-controls > .htmxo-pdf-places[role="group"] > button { flex: 0 0 auto; }
.htmxo-pdf-controls > .htmxo-pdf-places[hidden], .htmxo-pdf-controls > .htmxo-pdf-places > [hidden] { display: none; }
@media (max-width: 48rem) { .htmxo-pdf-controls > .htmxo-pdf-places[role="group"] { display: none; } }
.htmxo-pdf-controls [data-htmxo-pdf-place] { padding: .15rem .35rem; }
.htmxo-pdf-controls [data-htmxo-pdf-place] > svg { display: block; width: 1.1em; height: 1.1em; }
.htmxo-pdf-bar [data-htmxo-pdf-place][aria-pressed="true"] {
    --pico-background-color: var(--pico-secondary-background); --pico-color: var(--pico-secondary-inverse);
}
/* The tab: the panel's name, upright on a side edge, flat on the lower one. */
button.htmxo-pdf-tab {
    width: auto; margin: 0; padding: .7rem .3rem; font-size: .8125rem; line-height: 1.2; writing-mode: vertical-rl;
    color: var(--htmxo-pdf-ink); background-color: var(--htmxo-pdf-surface);
    border: 1px solid var(--pico-muted-border-color, color-mix(in srgb, currentColor 25%, transparent));
    border-radius: .45rem 0 0 .45rem; box-shadow: 0 2px 10px rgba(0, 0, 0, .25);
}
button.htmxo-pdf-tab:is(:hover, :focus-visible) { background-color: color-mix(in srgb, var(--htmxo-pdf-ink) 8%, var(--htmxo-pdf-surface)); }
[data-htmxo-pdf-placement="beside"] > button.htmxo-pdf-tab { border-radius: .45rem; }
[data-htmxo-pdf-placement="bottom"] > button.htmxo-pdf-tab {
    writing-mode: horizontal-tb; padding: .3rem .9rem; border-radius: .45rem .45rem 0 0;
}
/* The chooser's pills and list (the page's own look for them) sized to the
   bar; its name is for assistive technology only. */
.htmxo-pdf-documents > fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
.htmxo-pdf-documents > fieldset > legend {
    position: absolute; width: 1px; height: 1px; margin: 0; padding: 0; border: 0;
    overflow: hidden; clip-path: inset(50%); white-space: nowrap;
}
.htmxo-pdf-documents > fieldset:not([role]) > label:has(> input[type="radio"]) {
    max-width: 100%; margin: .1rem .3rem .1rem 0; padding: .1em .7em; line-height: 1.4;
}
.htmxo-pdf-bar .htmxo-pdf-documents .htmxo-choice-field { padding: .15rem .55rem; line-height: 1.4; }
.htmxo-pdf-bar [data-htmxo-pdf-colours][aria-pressed="true"] {
    --pico-background-color: var(--pico-secondary-background); --pico-color: var(--pico-secondary-inverse);
}
/* A passage and its references share a colour of the categorical palette. */
[data-htmxo-pdf-hue="1"] { --htmxo-pdf-hue: var(--htmxo-category-1, #2a78d6); }
[data-htmxo-pdf-hue="2"] { --htmxo-pdf-hue: var(--htmxo-category-2, #eb6834); }
[data-htmxo-pdf-hue="3"] { --htmxo-pdf-hue: var(--htmxo-category-3, #1baf7a); }
[data-htmxo-pdf-hue="4"] { --htmxo-pdf-hue: var(--htmxo-category-4, #eda100); }
[data-htmxo-pdf-hue="5"] { --htmxo-pdf-hue: var(--htmxo-category-5, #e87ba4); }
[data-htmxo-pdf-hue="6"] { --htmxo-pdf-hue: var(--htmxo-category-6, #008300); }
[data-htmxo-pdf-hue="7"] { --htmxo-pdf-hue: var(--htmxo-category-7, #6250d6); }
[data-htmxo-pdf-hue="8"] { --htmxo-pdf-hue: var(--htmxo-category-8, #e34948); }
/* A reference: always lightly highlighted, more while pointed at (here or at
   its mark), most once clicked. */
a[data-htmxo-pdf-ref] {
    color: inherit; text-decoration: none; border-radius: .2rem; padding: 0 .15em;
    background-color: color-mix(in srgb, var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88)) 16%, transparent);
    box-shadow: inset 0 -2px 0 color-mix(in srgb, var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88)) 60%, transparent);
    transition: background-color .12s, box-shadow .12s;
}
a[data-htmxo-pdf-ref]:is(:hover, :focus-visible, [data-htmxo-pdf-lit], [data-htmxo-pdf-active]) {
    background-color: color-mix(in srgb, var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88)) 34%, transparent);
    box-shadow: inset 0 -2px 0 var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88));
}
a[data-htmxo-pdf-ref][data-htmxo-pdf-active] { outline: 2px solid var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88)); outline-offset: 1px; }
a[data-htmxo-pdf-ref][data-htmxo-pdf-flash] { animation: htmxo-pdf-flash 1.6s ease-out; }
@keyframes htmxo-pdf-flash {
    from { outline: 4px solid var(--htmxo-pdf-hue, var(--htmxo-category-other, #8f8e88)); outline-offset: 2px; }
}
@media (prefers-reduced-motion: reduce) { a[data-htmxo-pdf-ref][data-htmxo-pdf-flash] { animation: none; } }
/* A passage on its page: the same three steps. The page stays white. */
.htmxo-pdf-hit {
    position: absolute; border-radius: 2px; pointer-events: auto; cursor: pointer; mix-blend-mode: multiply;
    background: color-mix(in srgb, var(--htmxo-pdf-hue, #ffc400) 28%, transparent);
}
.htmxo-pdf-hit[data-htmxo-pdf-lit] {
    background: color-mix(in srgb, var(--htmxo-pdf-hue, #ffc400) 48%, transparent);
    outline: 1px solid var(--htmxo-pdf-hue, #ffc400);
}
.htmxo-pdf-hit[data-htmxo-pdf-active] {
    background: color-mix(in srgb, var(--htmxo-pdf-hue, #ffc400) 55%, transparent);
    outline: 2px solid var(--htmxo-pdf-hue, #ffc400); outline-offset: 1px;
}
/* Code in an HTML document wraps at the panel's width rather than scrolling
   sideways under its marks (unlayered: highlighters set it unlayered). Over a
   dark page a mark lightens what it covers, as it darkens it over a light one. */
.htmxo-pdf-html pre, .htmxo-pdf-html pre > code, .htmxo-pdf-html pre[class*="language-"], .htmxo-pdf-html code[class*="language-"] {
    white-space: pre-wrap; overflow-wrap: anywhere;
}
[data-theme="dark"] .htmxo-pdf-doc .htmxo-pdf-hit { mix-blend-mode: screen; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .htmxo-pdf-doc .htmxo-pdf-hit { mix-blend-mode: screen; } }
/* Colours off: only the passages pointed at and gone to, in a marker's yellow. */
.htmxo-pdf-panel[data-htmxo-pdf-hues="off"] .htmxo-pdf-hit { visibility: hidden; --htmxo-pdf-hue: #ffc400; }
.htmxo-pdf-panel[data-htmxo-pdf-hues="off"] .htmxo-pdf-hit:is([data-htmxo-pdf-lit], [data-htmxo-pdf-active]) { visibility: visible; }
"""))

"""
    pdf_panel_script()

Client runtime for [`pdf_panel`](@ref), [`pdf_ref`](@ref),
[`pdf_toggle`](@ref), [`pdf_beside`](@ref) and [`pdf_overlay`](@ref): delegated listeners that serve
every panel and reference however it reaches the page (page load, htmx swap,
a [`live_thread`](@ref) item), and `window.htmxoPdf`. Safe to include more than
once.
"""
pdf_panel_script() = h.script(Raw(raw"""
(function () {
  if (window.htmxoPdf) return;
  var libraries = {}, files = {};
  function pdfjs(base) {
    if (!libraries[base]) {
      libraries[base] = import(base + 'pdf.min.mjs').then(function (lib) {
        lib.GlobalWorkerOptions.workerSrc = base + 'pdf.worker.min.mjs';
        return lib;
      });
      libraries[base].catch(function () { delete libraries[base]; });
    }
    return libraries[base];
  }
  function load(base, url) {
    var id = base + '\n' + url;
    if (!files[id]) {
      files[id] = pdfjs(base).then(function (lib) {
        return lib.getDocument({url: url}).promise.then(function (doc) { return {lib: lib, doc: doc}; });
      });
      files[id].catch(function () { delete files[id]; });
    }
    return files[id];
  }

  function element(panel) { return typeof panel === 'string' ? document.getElementById(panel) : panel; }
  function panelOf(el) {
    var aside = document.getElementById(el.dataset.htmxoPdfPanel || el.dataset.htmxoPdfToggle || el.dataset.htmxoPdfTab || '');
    return aside && aside.hasAttribute('data-htmxo-pdf-viewer') ? aside : null;
  }
  function group(aside) { return aside.dataset.htmxoPdfLink || aside.id; }
  function refs(aside) {
    return Array.prototype.slice.call(document.querySelectorAll(
      '[data-htmxo-pdf-ref][data-htmxo-pdf-panel="' + CSS.escape(aside.id) + '"]'));
  }
  // The panel's cell (the panel, or the private wrapper around it), and the
  // wrapper that places it: pdf_beside's, pdf_overlay's, or the carrier a
  // modal dialog holds it in.
  function cellOf(aside) { var up = aside.parentElement; return up && up.classList.contains('htmxo-private') ? up : aside; }
  function wrapOf(aside) {
    var up = cellOf(aside).parentElement;
    return up && (up.hasAttribute('data-htmxo-pdf-beside') || up.hasAttribute('data-htmxo-pdf-float')) ? up : null;
  }
  function content(aside) {
    var wrap = wrapOf(aside);
    return wrap && wrap.hasAttribute('data-htmxo-pdf-beside') ? wrap.querySelector(':scope > .htmxo-pdf-beside-content') : null;
  }
  function visible(el) { return el.getClientRects().length > 0; }
  function text(aside, name) { return aside.dataset['text' + name] || ''; }
  function note(aside, words) { aside.querySelector('[data-htmxo-pdf-note]').textContent = words; }
  function failed(aside, error) { note(aside, text(aside, 'Failed') + ': ' + (error && error.message || error)); }

  // --- The hover-link group: references, marks and linked table rows name
  // their items in `htmxo:link` events (detail {group, key, keys, source}).
  var shown = {};
  function announce(g, keys, source) {
    document.dispatchEvent(new CustomEvent('htmxo:link', {detail: {group: g,
      key: keys.length === 1 ? keys[0] : null, keys: keys, source: source || null}}));
  }
  // The passages and references of the items pointed at (`lit`), and of the
  // passage the reader went to last (`active`), shown more strongly.
  function light(aside) {
    var lit = aside.htmxoPdfLit || [], active = aside.hidden ? null : aside.htmxoPdfActive;
    aside.querySelectorAll('.htmxo-pdf-hit').forEach(function (hit) {
      hit.toggleAttribute('data-htmxo-pdf-lit', lit.indexOf(hit.dataset.htmxoPdfKey) >= 0);
      hit.toggleAttribute('data-htmxo-pdf-active', hit.dataset.htmxoPdfKey === active);
    });
    refs(aside).forEach(function (ref) {
      var key = ref.dataset.htmxoPdfKey;
      ref.toggleAttribute('data-htmxo-pdf-lit', key != null && lit.indexOf(key) >= 0);
      ref.toggleAttribute('data-htmxo-pdf-active', key != null && key === active);
    });
  }
  document.addEventListener('htmxo:link', function (event) {
    var d = event.detail || {};
    if (d.group == null) return;
    var g = String(d.group);
    var keys = Array.isArray(d.keys) ? d.keys.map(String) : d.key == null ? [] : [String(d.key)];
    shown[g] = {keys: keys, source: d.source || null};
    document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(function (aside) {
      if (group(aside) !== g) return;
      aside.htmxoPdfLit = keys;
      light(aside);
    });
  });
  // A reference pointed at or focused names its passage, unless it sits in a
  // linked table row of the group, which names its item itself.
  function refAt(el) { return el && el.closest ? el.closest('[data-htmxo-pdf-ref][data-htmxo-pdf-key]') : null; }
  function speaks(ref) {
    var aside = panelOf(ref);
    if (!aside) return null;
    var table = ref.closest('table[data-htmxo-link]');
    return window.htmxoLinkBound && table && table.dataset.htmxoLink === group(aside) ? null : aside;
  }
  function refMove(to, from) {
    var left = refAt(from), entered = refAt(to);
    if (left === entered) return;
    var leftPanel = left && speaks(left), enteredPanel = entered && speaks(entered);
    if (leftPanel) {
      var g = group(leftPanel), state = shown[g];
      var own = state && (state.source === left || !(state.source && state.source.isConnected));
      if (own && state.keys.length && !(enteredPanel && group(enteredPanel) === g)) announce(g, [], left);
    }
    if (enteredPanel) announce(group(enteredPanel), [entered.dataset.htmxoPdfKey], entered);
  }
  document.addEventListener('pointerover', function (e) { refMove(e.target, e.relatedTarget); });
  document.addEventListener('pointerout', function (e) { if (!e.relatedTarget) refMove(null, e.target); });
  document.addEventListener('focusin', function (e) { refMove(e.target, e.relatedTarget); });
  document.addEventListener('focusout', function (e) { if (!e.relatedTarget) refMove(null, e.target); });

  // --- Opening and closing. The content beside the panel narrows or widens
  // and wraps anew; the reference clicked (else the content at the top of the
  // window) is scrolled back to where it was on screen.
  function stickyTop() {
    var v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--htmxo-sticky-top'));
    return isNaN(v) ? 0 : v;
  }
  function onScreen(el) {
    if (!el || !el.isConnected || !visible(el)) return false;
    var r = el.getBoundingClientRect();
    return r.bottom > 0 && r.top < window.innerHeight;
  }
  // The sticky or fixed element `el` sits in, inside `box`: it stays where it
  // is on screen whatever the scroll, so it cannot hold the content in place.
  function pinned(el, box) {
    for (; el && el !== box; el = el.parentElement) {
      var p = getComputedStyle(el).position;
      if (p === 'sticky' || p === 'fixed') return el;
    }
    return null;
  }
  // The reference, else the first content at the top of the window below
  // what stays in view there (a table's sticky control line and header).
  function anchor(aside, ref) {
    var box = content(aside);
    if (!box) return null;
    if (ref && box.contains(ref) && onScreen(ref)) return ref;
    var r = box.getBoundingClientRect(), x = r.left + Math.min(24, r.width / 2), y = Math.max(r.top, stickyTop()) + 4;
    for (var i = 0; i < 8 && y < Math.min(r.bottom, window.innerHeight); i++) {
      var at = document.elementFromPoint(x, y);
      if (!at || at === box || !box.contains(at)) return null;
      var over = pinned(at, box);
      if (!over) return at;
      y = Math.max(y, over.getBoundingClientRect().bottom) + 4;
    }
    return null;
  }
  // The content is sized again in the tasks after the change (tables measure
  // their columns anew): keep the anchor in place while it settles, at most a
  // second, and never once the reader scrolls or types.
  var STOPS = ['wheel', 'touchmove', 'keydown'];
  function hold(aside, el, top) {
    if (aside.htmxoPdfHold) aside.htmxoPdfHold();
    var box = content(aside);
    if (!box || typeof ResizeObserver !== 'function') return;
    // where to hold it: `reveal` lifts it above a panel below
    var target = aside.htmxoPdfHeld = {el: el, top: top};
    var observer = new ResizeObserver(function () {
      var moved = target.el.getBoundingClientRect().top - target.top;
      if (Math.abs(moved) >= 0.5) window.scrollBy(0, moved);
    });
    var timer = setTimeout(stop, 1000);
    function stop() {
      observer.disconnect();
      clearTimeout(timer);
      STOPS.forEach(function (name) { window.removeEventListener(name, stop, true); });
      if (aside.htmxoPdfHold === stop) aside.htmxoPdfHold = null;
      if (aside.htmxoPdfHeld === target) aside.htmxoPdfHeld = null;
    }
    STOPS.forEach(function (name) { window.addEventListener(name, stop, true); });
    observer.observe(box);
    aside.htmxoPdfHold = stop;
  }
  // The anchor back where it was on screen while the content wraps anew.
  function settle(aside, held, top) {
    if (!held) return;
    var moved = held.getBoundingClientRect().top - top;
    if (moved) window.scrollBy(0, moved);
    hold(aside, held, top);
  }
  // Open or close the panel. `ref` is the reference clicked, `from` the
  // element that asked (a toggle, the tab), which may stand in a modal dialog.
  function open(aside, state, ref, from) {
    if (ref) aside.htmxoPdfRef = aside.htmxoPdfKeep = ref;
    if (state) {
      var dialog = modalOf(ref || from);
      if (dialog) carry(aside, dialog);
      furnish(aside);
    }
    if (state !== aside.hidden) { if (state && ref) reveal(aside, ref); return; }
    // Closing keeps the reference clicked last while the panel was open.
    var keep = state ? ref : aside.htmxoPdfKeep;
    if (state && !ref) aside.htmxoPdfKeep = null;
    var wrap = wrapOf(aside), held = anchor(aside, keep), top = held && held.getBoundingClientRect().top;
    if (!state) aside.htmxoPdfScrolled = aside.scrollTop;
    if (state && wrap) place(aside, preferred(wrap, aside));
    aside.hidden = !state;
    if (wrap) wrap.toggleAttribute('data-htmxo-pdf-open', state);
    document.querySelectorAll('[data-htmxo-pdf-toggle="' + CSS.escape(aside.id) + '"]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(state));
    });
    tab(aside);
    if (!state) light(aside);
    else {
      // reopened at the place it was at
      if (aside.htmxoPdfFile && aside.htmxoPdfScrolled && Math.abs(aside.scrollTop - aside.htmxoPdfScrolled) > 1) aside.scrollTop = aside.htmxoPdfScrolled;
      if (wrap) resize(aside, null);
    }
    room(aside);
    settle(aside, held, top);
    if (state && ref) reveal(aside, ref);
    aside.dispatchEvent(new CustomEvent('htmxo:pdf-toggle', {bubbles: true, detail: {open: state}}));
  }
  function toggle(aside, state, from) {
    if (state == null) state = aside.hidden;
    if (!state) return open(aside, false);
    if (aside.htmxoPdfFile) { open(aside, true, null, from); refresh(aside); return; }
    var url = chosen(aside);
    if (url) show(aside, {url: url, page: 1, from: from});
    else { open(aside, true, null, from); note(aside, text(aside, 'Empty')); }
  }

  // --- Where the panel stands. Its wrapper offers placements
  // (`data-htmxo-pdf-placements`): pinned beside the content, or floating over
  // the page on the right or below; the one shown is its
  // `data-htmxo-pdf-placement`. The reader's last choice and each placement's
  // size are kept in the browser, where it keeps anything. LOCKSTEP:
  // `_PDF_PLACEMENTS`.
  var PLACES = ['beside', 'right', 'bottom'];
  var narrow = typeof window.matchMedia === 'function' ? window.matchMedia('(max-width: 48rem)') : null;
  function stored(name) { try { return window.localStorage.getItem(name); } catch (e) { return null; } }
  function store(name, value) { try { window.localStorage.setItem(name, value); } catch (e) {} }
  function offered(wrap) {
    var beside = wrap.hasAttribute('data-htmxo-pdf-beside');
    var list = (wrap.dataset.htmxoPdfPlacements || '').split(/\s+/).filter(function (p) {
      return PLACES.indexOf(p) >= 0 && (beside || p !== 'beside');
    });
    return list.length ? list : [beside ? 'beside' : 'right'];
  }
  // The placement the reader picked last, where the wrapper offers it (as
  // the browser keeps it, else as this panel was shown); else the app's.
  function preferred(wrap, aside) {
    var list = offered(wrap), choices = [stored('htmxo-pdf-placement'), aside && aside.htmxoPdfPlace, wrap.dataset.htmxoPdfDefault];
    for (var i = 0; i < choices.length; i++) if (list.indexOf(choices[i]) >= 0) return choices[i];
    return list[0];
  }
  function shownAt(wrap) { return wrap.getAttribute('data-htmxo-pdf-placement'); }
  // Show the panel in placement `wanted`; on a narrow screen it lies below.
  function place(aside, wanted) {
    var wrap = wrapOf(aside);
    if (!wrap) return;
    var list = offered(wrap);
    if (list.indexOf(wanted) < 0) wanted = preferred(wrap, aside);
    aside.htmxoPdfPlace = wanted;
    wrap.setAttribute('data-htmxo-pdf-placement', narrow && narrow.matches ? 'bottom' : wanted);
    var group = aside.querySelector('[data-htmxo-pdf-places]');
    if (group) {
      group.hidden = list.length < 2;
      group.querySelectorAll('[data-htmxo-pdf-place]').forEach(function (b) {
        b.hidden = list.indexOf(b.dataset.htmxoPdfPlace) < 0;
        b.setAttribute('aria-pressed', String(b.dataset.htmxoPdfPlace === wanted));
      });
    }
    resize(aside, null);
    room(aside);
  }
  // The reader's pick in the switch: kept, and shown, the content held in
  // place while it wraps anew, the clicked reference kept in view.
  function choose(aside, wanted) {
    store('htmxo-pdf-placement', wanted);
    var held = anchor(aside, aside.htmxoPdfKeep), top = held && held.getBoundingClientRect().top;
    place(aside, wanted);
    settle(aside, held, top);
    refresh(aside);
    reveal(aside, aside.htmxoPdfKeep);
  }

  // The panel's size: its width beside the content and on the right, its
  // height below, within bounds that leave the page usable.
  function bounds(wrap, at) {
    if (at === 'bottom') return [120, Math.max(120, window.innerHeight - stickyTop() - 40)];
    var room = at === 'beside' ? wrap.getBoundingClientRect().width - 16 : window.innerWidth, least = Math.min(240, room);
    return [least, Math.max(least, room - (at === 'beside' ? 240 : 160))];
  }
  function sizeOf(aside) {
    var wrap = wrapOf(aside), r = cellOf(aside).getBoundingClientRect();
    return wrap && shownAt(wrap) === 'bottom' ? r.height : r.width;
  }
  // Size the panel where it is shown: `px`, else the size the reader left it
  // at there, else the app's; `save` keeps it.
  function resize(aside, px, save) {
    var wrap = wrapOf(aside);
    if (!wrap) return;
    var at = shownAt(wrap), name = at === 'bottom' ? '--htmxo-pdf-reader-height' : '--htmxo-pdf-reader-width';
    wrap.style.removeProperty(at === 'bottom' ? '--htmxo-pdf-reader-width' : '--htmxo-pdf-reader-height');
    if (px == null) { var was = Number(stored('htmxo-pdf-size-' + at)); px = was > 0 ? was : null; }
    if (px == null) wrap.style.removeProperty(name);
    else {
      var b = bounds(wrap, at);
      px = Math.round(Math.min(Math.max(px, b[0]), b[1]));
      wrap.style.setProperty(name, px + 'px');
      if (save) store('htmxo-pdf-size-' + at, String(px));
    }
    edge(aside);
  }
  // The resize edge as a separator: its orientation, and the panel's share
  // of the window (of the content and panel beside it), in per cent.
  function edge(aside) {
    var handle = aside.htmxoPdfEdge, wrap = wrapOf(aside);
    if (!handle || !wrap || aside.hidden) return;
    var at = shownAt(wrap), b = bounds(wrap, at);
    var whole = at === 'bottom' ? window.innerHeight : at === 'beside' ? wrap.getBoundingClientRect().width : window.innerWidth;
    function share(px) { return String(Math.round(100 * px / Math.max(1, whole))); }
    handle.setAttribute('aria-orientation', at === 'bottom' ? 'horizontal' : 'vertical');
    handle.setAttribute('aria-valuemin', share(b[0]));
    handle.setAttribute('aria-valuemax', share(b[1]));
    handle.setAttribute('aria-valuenow', share(sizeOf(aside)));
  }
  // Dragged (mouse, pen or touch), the panel follows the pointer.
  function drag(aside, e) {
    var wrap = wrapOf(aside), handle = aside.htmxoPdfEdge;
    if (!wrap || e.button !== 0) return;
    e.preventDefault();
    var at = shownAt(wrap), start = sizeOf(aside), x0 = e.clientX, y0 = e.clientY, last = null;
    var held = at === 'beside' ? anchor(aside, aside.htmxoPdfKeep) : null, top = held && held.getBoundingClientRect().top;
    try { handle.setPointerCapture(e.pointerId); } catch (error) {}
    handle.setAttribute('data-htmxo-pdf-dragging', '');
    function move(ev) {
      if (ev.pointerId !== e.pointerId) return;
      last = at === 'bottom' ? start + (y0 - ev.clientY) : start + (x0 - ev.clientX);
      resize(aside, last);
      if (held) { var moved = held.getBoundingClientRect().top - top; if (Math.abs(moved) >= 0.5) window.scrollBy(0, moved); }
    }
    function end(ev) {
      if (ev.pointerId !== e.pointerId) return;
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', end);
      document.removeEventListener('pointercancel', end);
      handle.removeAttribute('data-htmxo-pdf-dragging');
      if (last != null) resize(aside, last, true);
      room(aside);
      settle(aside, held, top);
      refresh(aside);
    }
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', end);
    document.addEventListener('pointercancel', end);
  }
  // Focused, the arrow keys move the edge (Shift: in larger steps), Home and
  // End give the smallest and largest size.
  function nudge(aside, e) {
    var wrap = wrapOf(aside);
    if (!wrap) return;
    var at = shownAt(wrap), b = bounds(wrap, at), step = e.shiftKey ? 64 : 16, size = sizeOf(aside), to;
    if (e.key === (at === 'bottom' ? 'ArrowUp' : 'ArrowLeft')) to = size + step;
    else if (e.key === (at === 'bottom' ? 'ArrowDown' : 'ArrowRight')) to = size - step;
    else if (e.key === 'Home') to = b[0];
    else if (e.key === 'End') to = b[1];
    else return;
    e.preventDefault();
    var held = at === 'beside' ? anchor(aside, aside.htmxoPdfKeep) : null, top = held && held.getBoundingClientRect().top;
    resize(aside, to, true);
    room(aside);
    settle(aside, held, top);
    clearTimeout(aside.htmxoPdfRelayout);
    aside.htmxoPdfRelayout = setTimeout(function () { refresh(aside); }, 200);
  }
  // The resize edge and the tab a closed panel leaves, in the panel's wrapper.
  function furnish(aside) {
    var wrap = wrapOf(aside);
    if (!wrap) return;
    if (!aside.htmxoPdfEdge) {
      var handle = aside.htmxoPdfEdge = make('div', {'class': 'htmxo-pdf-resize', role: 'separator', tabindex: '0',
        'aria-controls': aside.id, 'aria-label': text(aside, 'Resize'), title: text(aside, 'Resize'), 'data-htmxo-pdf-resize': aside.id});
      handle.addEventListener('pointerdown', function (e) { drag(aside, e); });
      handle.addEventListener('keydown', function (e) { nudge(aside, e); });
    }
    if (!aside.htmxoPdfTab) aside.htmxoPdfTab = make('button', {type: 'button', 'class': 'htmxo-pdf-tab', 'data-htmxo-pdf-tab': aside.id,
      'aria-controls': aside.id, title: text(aside, 'Reopen'), hidden: ''}, [aside.getAttribute('aria-label') || '']);
    if (aside.htmxoPdfEdge.parentNode !== wrap) wrap.insertBefore(aside.htmxoPdfEdge, cellOf(aside));
    if (aside.htmxoPdfTab.parentNode !== wrap) wrap.appendChild(aside.htmxoPdfTab);
  }
  // Closed after showing a document, the panel leaves its tab.
  function tab(aside) { if (aside.htmxoPdfTab) aside.htmxoPdfTab.hidden = !aside.hidden || !aside.htmxoPdfShown; }
  // Room below the page's end while the panel lies below, so that a
  // reference there can stand above it.
  function room(aside) {
    var wrap = wrapOf(aside), spacer = aside.htmxoPdfRoom;
    if (!(wrap && !aside.hidden && aside.isConnected && !wrap.hasAttribute('data-htmxo-pdf-carrier') && shownAt(wrap) === 'bottom')) {
      if (spacer) spacer.remove();
      return;
    }
    if (!spacer) spacer = aside.htmxoPdfRoom = make('div', {'class': 'htmxo-pdf-room', 'aria-hidden': 'true'});
    spacer.style.height = Math.ceil(cellOf(aside).getBoundingClientRect().height) + 'px';
    if (spacer.parentNode !== document.body) document.body.appendChild(spacer);
  }
  // A reference the panel below covers is lifted just above it, as little as
  // that takes and never under a sticky header: the boxes around it that
  // scroll first, then the window (not behind a modal dialog). A panel on the
  // right lies over the right of the page: nothing scrolls sideways.
  function reveal(aside, ref) {
    var wrap = wrapOf(aside);
    if (!ref || !ref.isConnected || !visible(ref) || aside.hidden || !wrap || shownAt(wrap) !== 'bottom') return;
    room(aside);
    var edgeTop = cellOf(aside).getBoundingClientRect().top - 8, r = ref.getBoundingClientRect();
    if (r.bottom <= edgeTop || r.top >= window.innerHeight) return;
    var by = Math.min(r.bottom - edgeTop, r.top - stickyTop() - 8);
    for (var box = ref.parentElement; box && by > 0.5 && box !== document.body && box !== document.documentElement; box = box.parentElement) {
      if (box.scrollHeight <= box.clientHeight || !/auto|scroll/.test(getComputedStyle(box).overflowY)) continue;
      var before = box.scrollTop;
      box.scrollTop = before + Math.min(by, ref.getBoundingClientRect().top - box.getBoundingClientRect().top - 8);
      by -= box.scrollTop - before;
    }
    var modal = false;
    try { modal = !!ref.closest('dialog:modal'); } catch (e) {}
    if (by > 0.5 && !modal) window.scrollBy(0, by);
    if (aside.htmxoPdfHeld && aside.htmxoPdfHeld.el === ref) aside.htmxoPdfHeld.top = ref.getBoundingClientRect().top;
  }

  // --- A modal dialog (`showModal()`) puts itself in the top layer and the
  // rest of the page out of reach, a popover too. Opened from one, the panel
  // goes into it, floating above its content in a carrier of its own, and
  // goes back to its place, still open, when the dialog closes or goes; a
  // comment marks that place meanwhile. Something that replaces the dialog's
  // content leaves the panel in it.
  function modalOf(el) {
    try {
      for (var d = el && el.closest ? el.closest('dialog') : null; d; d = d.parentElement && d.parentElement.closest('dialog'))
        if (d.matches(':modal')) return d;
      var all = document.querySelectorAll('dialog:modal');
      return all.length ? all[all.length - 1] : null;
    } catch (e) { return null; }
  }
  // Move `el` keeping its state where the browser can (moveBefore), and the
  // panel's place in its document.
  function moveTo(parent, el, next) {
    if (typeof parent.moveBefore === 'function' && el.isConnected && parent.isConnected) {
      try { parent.moveBefore(el, next || null); return; } catch (e) {}
    }
    parent.insertBefore(el, next || null);
  }
  // The place the panel is at, as it is shown (else as it was last shown:
  // a detached or hidden panel has none), kept across `act`.
  function keepPlace(aside, act) {
    var at = aside.isConnected && !aside.hidden ? aside.scrollTop : aside.htmxoPdfScrolled;
    act();
    if (at != null && !aside.hidden && Math.abs(aside.scrollTop - at) > 1) aside.scrollTop = at;
  }
  function carry(aside, dialog) {
    var cell = cellOf(aside);
    if (dialog.contains(cell)) return;
    var home = aside.htmxoPdfHome, carrier = aside.htmxoPdfCarrier;
    if (!home) {
      var wrap = wrapOf(aside), mark = document.createComment(' htmxo-pdf-panel ' + aside.id + ' ');
      cell.parentNode.insertBefore(mark, cell);
      home = aside.htmxoPdfHome = {wrap: wrap, mark: mark};
      if (wrap) wrap.removeAttribute('data-htmxo-pdf-open');
      var floating = wrap ? offered(wrap).filter(function (p) { return p !== 'beside'; }) : [];
      if (!floating.length) floating = ['right'];
      var app = wrap && floating.indexOf(wrap.dataset.htmxoPdfDefault) >= 0 ? wrap.dataset.htmxoPdfDefault : floating[0];
      carrier = aside.htmxoPdfCarrier = make('div', {'class': 'htmxo-pdf-float', 'data-htmxo-pdf-float': '',
        'data-htmxo-pdf-carrier': aside.id, 'data-htmxo-pdf-placements': floating.join(' '),
        'data-htmxo-pdf-default': app, 'data-htmxo-pdf-placement': app});
    }
    aside.htmxoPdfDialog = dialog;
    keepPlace(aside, function () {
      moveTo(dialog, carrier, null);
      moveTo(carrier, cell, null);
    });
    if (!aside.hidden) { carrier.setAttribute('data-htmxo-pdf-open', ''); place(aside, preferred(carrier, aside)); refresh(aside); }
    furnish(aside);
    watchDialog(aside);
  }
  function watchDialog(aside) {
    if (aside.htmxoPdfWatch || typeof MutationObserver !== 'function') return;
    var observer = new MutationObserver(function () {
      var dialog = aside.htmxoPdfDialog, carrier = aside.htmxoPdfCarrier, modal = false;
      if (!aside.htmxoPdfHome) return;
      try { modal = dialog.isConnected && dialog.matches(':modal'); } catch (e) {}
      if (modal) {
        if (carrier.parentNode !== dialog) keepPlace(aside, function () { moveTo(dialog, carrier, null); });
        return;
      }
      var other = modalOf(null);
      if (other) carry(aside, other); else goHome(aside);
    });
    observer.observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['open']});
    aside.htmxoPdfWatch = function () { observer.disconnect(); aside.htmxoPdfWatch = null; };
  }
  function goHome(aside) {
    var home = aside.htmxoPdfHome, carrier = aside.htmxoPdfCarrier, cell = cellOf(aside);
    if (aside.htmxoPdfWatch) aside.htmxoPdfWatch();
    aside.htmxoPdfHome = aside.htmxoPdfDialog = null;
    if (!home.mark.isConnected) {
      // its place went with the content around it: a new panel of its id
      // took it, or the panel floats from the page's end
      aside.htmxoPdfCarrier = null;
      var twin = Array.prototype.some.call(document.querySelectorAll('[id="' + CSS.escape(aside.id) + '"]'),
                                           function (el) { return el !== aside; });
      if (twin) { carrier.remove(); return; }
      carrier.removeAttribute('data-htmxo-pdf-carrier');
      keepPlace(aside, function () { moveTo(document.body, carrier, null); });
      room(aside);
      return;
    }
    keepPlace(aside, function () {
      moveTo(home.mark.parentNode, cell, home.mark);
      home.mark.remove();
      furnish(aside);
      carrier.remove();
    });
    if (home.wrap) {
      home.wrap.toggleAttribute('data-htmxo-pdf-open', !aside.hidden);
      if (!aside.hidden) place(aside, preferred(home.wrap, aside));
    }
    tab(aside);
    refresh(aside);
  }
  // Content an htmx swap replaces keeps no panel: the panel steps out first,
  // and goes back into its dialog once the new content is in.
  document.addEventListener('htmx:beforeSwap', function (event) {
    var target = event.detail && event.detail.target;
    if (!target) return;
    document.querySelectorAll('[data-htmxo-pdf-carrier]').forEach(function (carrier) {
      if (target.contains(carrier)) {
        var aside = document.getElementById(carrier.dataset.htmxoPdfCarrier);
        if (aside) keepPlace(aside, function () { moveTo(document.body, carrier, null); });
      }
    });
  });

  // --- The document chooser, as pdf_panel's `_pdf_chooser` draws it, never a
  // native select box: one document is its title, a few a row of pills
  // (radio_group's markup), a long list a searchable list (choice_list's
  // markup, which the page's choice_list script drives). Each document is a
  // radio whose value is its address; the lone title carries its address.
  // An HTML document's title or radio says so (`data-htmxo-pdf-kind`).
  function chooser(aside) { return aside.querySelector('[data-htmxo-pdf-document]'); }
  function choiceTitle(radio) {
    var label = radio.closest('label'), name = label.querySelector('.htmxo-choice-label');
    return (name || label).textContent.trim();
  }
  function documents(box) {
    var one = box.querySelector('[data-htmxo-pdf-url]');
    if (one) return [{url: one.dataset.htmxoPdfUrl, title: one.textContent, kind: one.dataset.htmxoPdfKind || 'pdf'}];
    return Array.prototype.map.call(box.querySelectorAll('input[type="radio"]'), function (radio) {
      return {url: radio.value, title: choiceTitle(radio), kind: radio.dataset.htmxoPdfKind || 'pdf'};
    });
  }
  // Whether the document at `url` is a PDF or an HTML document: as the
  // chooser says, else a reference to it. LOCKSTEP: `_pdf_kind`.
  function kindOf(aside, url) {
    var listed = documents(chooser(aside)).filter(function (d) { return d.url === url; })[0];
    if (listed) return listed.kind;
    var ref = refs(aside).filter(function (r) { return r.dataset.htmxoPdfUrl === url; })[0];
    return ref && ref.dataset.htmxoPdfKind === 'html' ? 'html' : 'pdf';
  }
  // The document chosen: the lone one, the radio checked, else the first.
  function chosen(aside) {
    var box = chooser(aside), one = box.querySelector('[data-htmxo-pdf-url]');
    var radio = box.querySelector('input[type="radio"]:checked') || box.querySelector('input[type="radio"]');
    return one ? one.dataset.htmxoPdfUrl : radio ? radio.value : null;
  }
  function make(tag, attrs, children) {
    var el = document.createElement(tag);
    Object.keys(attrs).forEach(function (name) { el.setAttribute(name, attrs[name]); });
    (children || []).forEach(function (child) { el.append(child); });
    return el;
  }
  // The chooser drawn again for `docs`, `url` chosen, in the form their
  // number takes. LOCKSTEP: `_pdf_chooser`, `_pdf_choice_name`, and
  // `_choice_list`'s markup in HTMXObjects.jl.
  function redraw(aside, docs, url) {
    var box = chooser(aside), name = 'htmxo-pdf-document-' + aside.id, label = text(aside, 'Documents');
    function kinded(d, attrs) { if (d.kind === 'html') attrs['data-htmxo-pdf-kind'] = 'html'; return attrs; }
    function radio(d) {
      var input = make('input', kinded(d, d.url === url ? {type: 'radio', name: name, value: d.url, checked: ''} :
                                                          {type: 'radio', name: name, value: d.url}));
      input.checked = d.url === url;
      return input;
    }
    var title = (docs.filter(function (d) { return d.url === url; })[0] || {title: ''}).title, form;
    if (docs.length === 1) form = make('span', kinded(docs[0], {'class': 'htmxo-pdf-title', 'data-htmxo-pdf-url': docs[0].url}), [docs[0].title]);
    else if (docs.length <= Number(box.dataset.htmxoPdfPills)) form = make('fieldset', {},
      [make('legend', {}, [label])].concat(docs.map(function (d) { return make('label', {}, [radio(d), d.title]); })));
    else {
      var list = name + '-list', search = text(aside, 'Search');
      form = make('fieldset', {'class': 'htmxo-choice-list', 'data-htmxo-choice-list': ''}, [
        make('legend', {}, [label]),
        make('button', {type: 'button', 'class': 'htmxo-choice-field', popovertarget: list,
                        'aria-haspopup': 'dialog', 'aria-expanded': 'false', title: title}, [
          make('span', {'class': 'htmxo-choice-current'}, [title]),
          make('span', {'class': 'htmxo-choice-caret', 'aria-hidden': 'true'}, ['▾'])]),
        make('div', {id: list, 'class': 'htmxo-choice-panel', popover: 'auto', role: 'dialog', 'aria-label': label}, [
          make('input', {type: 'search', 'class': 'htmxo-choice-search', placeholder: search, 'aria-label': search,
                         autocomplete: 'off', spellcheck: 'false',
                         oninput: 'htmxoChoiceFilter(this);event.stopPropagation()', onchange: 'event.stopPropagation()'}),
          make('div', {'class': 'htmxo-choice-options'}, docs.map(function (d) {
            return make('label', {'class': 'htmxo-choice-option'}, [radio(d), make('span', {'class': 'htmxo-choice-label'}, [d.title])]);
          })),
          make('p', {'class': 'htmxo-choice-empty', hidden: ''}, [text(aside, 'NoMatch')])])]);
    }
    box.replaceChildren(form);
  }
  // The chooser names document `url` (of `kind`) as the one shown, adding it
  // (titled `title`, else by its file name) when it is not listed. No event is
  // sent: the chooser's own change is the reader's choice.
  function pick(aside, url, title, kind) {
    var box = chooser(aside), docs = documents(box);
    if (!docs.some(function (d) { return d.url === url; })) {
      docs.push({url: url, title: title || fileName(url), kind: kind});
      return redraw(aside, docs, url);
    }
    box.querySelectorAll('input[type="radio"]').forEach(function (radio) { if (radio.value === url) radio.checked = true; });
    var current = box.querySelector('.htmxo-choice-current');
    if (current) {
      var shown = docs.filter(function (d) { return d.url === url; })[0].title;
      current.textContent = shown;
      current.parentNode.title = shown;
    }
  }

  // --- The pages. Letters and digits only, lower case: a quote matches its
  // page whatever the PDF did to spaces, line breaks, hyphenation and quotes.
  function letters(words) {
    return words.normalize('NFKC').toLowerCase().replace(/­/g, '').replace(/[^\p{L}\p{N}]+/gu, '');
  }
  // Where a quote stands in a page's letters: all of it, else the longest
  // beginning of it the page holds (at least 24 letters), as [start, length].
  function found(page, wanted) {
    if (wanted.length < 8) return null;
    var start = page.indexOf(wanted);
    if (start >= 0) return [start, wanted.length];
    var low = 24, high = wanted.length - 1, best = null;
    while (low <= high) {
      var middle = (low + high) >> 1, at = page.indexOf(wanted.slice(0, middle));
      if (at >= 0) { best = [at, middle]; low = middle + 1; } else high = middle - 1;
    }
    return best;
  }
  function fileName(url) {
    try {
      var u = new URL(url, location.href), path = u.searchParams.get('path') || decodeURIComponent(u.pathname);
      return path.replace(/\/+$/, '').split('/').pop() || url;
    } catch (e) { return url; }
  }
  // Another file is to be shown: the pages, the page line and the place of
  // the one shown go at once, so the panel never shows one file's pages
  // under another's name while the other loads.
  function clear(aside) {
    var file = aside.htmxoPdfFile;
    if (file) {
      if (file.observer) file.observer.disconnect();
      if (file.stop) file.stop();
      file.boxes.forEach(function (entry, i) { release(file, i + 1); });
    }
    aside.htmxoPdfFile = null;
    aside.htmxoPdfPinned = null;
    aside.querySelector('[data-htmxo-pdf-pages]').replaceChildren();
    aside.querySelector('[data-htmxo-pdf-page-info]').textContent = '';
    scrollPanel(aside, 0);
  }
  // The file's pages laid out at the panel's width, a box of its final size
  // each, so nothing moves as they are drawn; each drawn once it comes near
  // the panel's view and let go again far from it.
  function layout(aside, url) {
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    var width = Math.max(200, view.clientWidth), file = aside.htmxoPdfFile;
    if (file && file.kind === 'pdf' && file.url === url && file.width === width) return file.ready;
    if (file && (file.url !== url || file.kind !== 'pdf')) { clear(aside); width = Math.max(200, view.clientWidth); }
    else if (file && file.observer) file.observer.disconnect();
    file = {url: url, kind: 'pdf', width: width, boxes: []};
    aside.htmxoPdfFile = file;
    file.ready = load(aside.dataset.htmxoPdfjs, url).then(function (loaded) {
      file.lib = loaded.lib;
      var pages = [];
      for (var n = 1; n <= loaded.doc.numPages; n++) pages.push(loaded.doc.getPage(n));
      return Promise.all(pages);
    }).then(function (pages) {
      if (aside.htmxoPdfFile !== file) return file;
      view.replaceChildren();
      file.observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          var n = Number(entry.target.dataset.htmxoPdfPage);
          if (entry.isIntersecting) draw(aside, file, n); else release(file, n);
        });
      }, {root: aside, rootMargin: '100% 0px'});
      pages.forEach(function (page, i) {
        var viewport = page.getViewport({scale: width / page.getViewport({scale: 1}).width});
        var box = document.createElement('div'), layer = document.createElement('div');
        box.className = 'htmxo-pdf-page';
        box.dataset.htmxoPdfPage = String(i + 1);
        box.style.width = viewport.width + 'px';
        box.style.height = viewport.height + 'px';
        layer.className = 'htmxo-pdf-marks';
        box.append(document.createElement('canvas'), layer);
        view.append(box);
        file.boxes.push({box: box, page: page, viewport: viewport, drawn: {}});
        file.observer.observe(box);
      });
      return file;
    }, function (error) {
      if (aside.htmxoPdfFile === file) aside.htmxoPdfFile = null;   // asked for again, it loads anew
      throw error;
    });
    return file.ready;
  }
  function draw(aside, file, n) {
    var entry = file.boxes[n - 1];
    if (!entry || entry.task) return;
    var canvas = entry.box.querySelector('canvas'), viewport = entry.viewport, ratio = window.devicePixelRatio || 1;
    canvas.width = Math.floor(viewport.width * ratio);
    canvas.height = Math.floor(viewport.height * ratio);
    canvas.style.width = viewport.width + 'px';
    canvas.style.height = viewport.height + 'px';
    entry.task = entry.page.render({canvasContext: canvas.getContext('2d'), viewport: viewport,
                                    transform: ratio === 1 ? null : [ratio, 0, 0, ratio, 0, 0]});
    entry.task.promise.then(function () { entry.box.setAttribute('data-htmxo-pdf-drawn', ''); }, function (error) {
      if (!(error && error.name === 'RenderingCancelledException')) failed(aside, error);
    });
    marks(aside, file, n).catch(function (error) { failed(aside, error); });
  }
  function release(file, n) {
    var entry = file.boxes[n - 1];
    if (!entry || !entry.task) return;
    entry.task.cancel();
    entry.task = null;
    entry.box.removeAttribute('data-htmxo-pdf-drawn');
    var canvas = entry.box.querySelector('canvas');
    canvas.width = 0;
    canvas.height = 0;
  }
  // The passages quoted from page n of the file, once each (references with
  // one key share one passage), from the references on the page now, so a
  // reference that arrives later (a new message) is marked too.
  function passages(aside, url, n) {
    var seen = {}, out = [];
    refs(aside).forEach(function (ref) {
      var key = ref.dataset.htmxoPdfKey, quote = ref.dataset.htmxoPdfQuote;
      if (!key || !quote || seen[key] || ref.dataset.htmxoPdfUrl !== url || ref.dataset.htmxoPdfKind === 'html' ||
          (Number(ref.dataset.htmxoPdfPage) || 1) !== n) return;
      seen[key] = true;
      out.push({key: key, quote: quote, hue: ref.dataset.htmxoPdfHue || '', label: ref.textContent.trim()});
    });
    return out;
  }
  // Mark the passages on page n not marked yet: each as the text runs its
  // words cover there, the first and last run cut to the part they cover.
  function marks(aside, file, n) {
    var entry = file.boxes[n - 1];
    if (!entry) return Promise.resolve();
    if (!entry.text) {
      entry.text = entry.page.getTextContent().then(function (content) {
        var all = '', starts = [], lengths = [], owner = [];
        content.items.forEach(function (item, i) {
          var part = letters(item.str || '');
          starts.push(all.length);
          lengths.push(part.length);
          for (var k = 0; k < part.length; k++) owner.push(i);
          all += part;
        });
        return {items: content.items, letters: all, starts: starts, lengths: lengths, owner: owner};
      });
      entry.text.catch(function () { entry.text = null; });
    }
    return entry.text.then(function (page) {
      if (aside.htmxoPdfFile !== file) return;
      var layer = entry.box.querySelector('.htmxo-pdf-marks');
      passages(aside, file.url, n).forEach(function (passage) {
        if (entry.drawn[passage.key]) return;
        entry.drawn[passage.key] = true;
        var at = found(page.letters, letters(passage.quote));
        if (!at) return;
        var from = at[0], to = at[0] + at[1], items = [];
        page.owner.slice(from, to).forEach(function (i) { if (items.indexOf(i) < 0) items.push(i); });
        items.forEach(function (i) {
          var item = page.items[i], length = page.lengths[i] || 1;
          var a = Math.max(0, from - page.starts[i]) / length, b = Math.min(length, to - page.starts[i]) / length;
          var place = file.lib.Util.transform(entry.viewport.transform, item.transform);
          var height = Math.hypot(place[2], place[3]), width = item.width * entry.viewport.scale;
          var hit = document.createElement('div');
          hit.className = 'htmxo-pdf-hit';
          hit.dataset.htmxoPdfKey = passage.key;
          if (passage.hue) hit.dataset.htmxoPdfHue = passage.hue;
          hit.title = passage.label;
          hit.style.left = (place[4] + a * width) + 'px';
          hit.style.top = (place[5] - height) + 'px';
          hit.style.width = Math.max(2, (b - a) * width) + 'px';
          hit.style.height = (height * 1.2) + 'px';
          layer.appendChild(hit);
        });
      });
      light(aside);
    });
  }
  // --- An HTML document: the fragment its address answers an htmx GET with,
  // swapped in as htmx swaps (so the page's scripts, its code highlighting
  // among them, see it as any swapped content), its passages boxes over their
  // words in a layer above it, as on a PDF's page. Nothing is written into the
  // fragment, so a highlighter that redraws a code block (PrismJS leaves code
  // that holds elements plain) keeps working, and the boxes follow it.
  function fetchHtml(url, body) {
    return fetch(url, {headers: {'HX-Request': 'true', 'HX-Current-URL': location.href}, credentials: 'same-origin'})
      .then(function (response) {
        if (!response.ok) throw new Error(response.status + ' ' + response.statusText);
        var error = response.headers.get('X-HTMXO-Error-Id');
        return response.text().then(function (html) {
          if (window.htmx && typeof window.htmx.swap === 'function') window.htmx.swap(body, html, {swapStyle: 'innerHTML'});
          else {
            body.innerHTML = html;
            if (window.htmx) { window.htmx.process(body); window.htmx.trigger(body, 'htmx:load'); }
          }
          if (window.htmxoSyntax) window.htmxoSyntax.highlight(body);
          // a failed fragment answers with its error, shown as htmx shows it
          if (error) throw new Error('error ' + error);
        });
      });
  }
  // The document `url` laid out in the panel (an empty one at once, its
  // fragment once it arrives), and its passages kept over their words while
  // the panel's width or the fragment changes.
  function htmlDocument(aside, url) {
    var file = aside.htmxoPdfFile;
    if (file && file.kind === 'html' && file.url === url) return file.ready;
    clear(aside);
    file = {url: url, kind: 'html', boxes: []};
    file.body = make('div', {'class': 'htmxo-pdf-html'});
    file.layer = make('div', {'class': 'htmxo-pdf-marks'});
    file.doc = make('div', {'class': 'htmxo-pdf-doc'}, [file.body, file.layer]);
    aside.htmxoPdfFile = file;
    aside.querySelector('[data-htmxo-pdf-pages]').replaceChildren(file.doc);
    file.ready = fetchHtml(url, file.body).then(function () {
      if (aside.htmxoPdfFile !== file) return file;
      file.loaded = true;
      watch(aside, file);
      return file;
    }, function (error) {
      if (aside.htmxoPdfFile === file) aside.htmxoPdfFile = null;   // asked for again, it loads anew
      throw error;
    });
    return file.ready;
  }
  function watch(aside, file) {
    var queued = false;
    function again(changed) {
      if (changed) file.model = null;
      if (queued) return;
      queued = true;
      requestAnimationFrame(function () { queued = false; placeAll(aside, file); });
    }
    var resized = typeof ResizeObserver === 'function' ? new ResizeObserver(function () { again(false); }) : null;
    var changed = typeof MutationObserver === 'function' ? new MutationObserver(function () { again(true); }) : null;
    if (resized) resized.observe(file.doc);
    if (changed) changed.observe(file.body, {childList: true, subtree: true, characterData: true});
    // a box in the fragment that scrolls (a wide table) carries its words along
    function scrolled() { again(false); }
    file.body.addEventListener('scroll', scrolled, true);
    file.stop = function () {
      if (resized) resized.disconnect();
      if (changed) changed.disconnect();
      file.body.removeEventListener('scroll', scrolled, true);
    };
  }
  // Letters as `letters` reads them, one character at a time, so that each
  // letter knows the character it came from.
  function letter(c) {
    if (c.length === 1 && c.charCodeAt(0) < 128) return /[0-9A-Za-z]/.test(c) ? c.toLowerCase() : '';
    return letters(c);
  }
  function lettersOf(words) { var out = ''; for (var c of words) out += letter(c); return out; }
  // The fragment's letters, in order, and where each came from: its text node
  // (`owner`) and the characters it spans there (`from`, `to`). Scripts and
  // styles hold no text.
  function textOf(body) {
    var model = {letters: '', nodes: [], starts: [], owner: [], from: [], to: []};
    var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {acceptNode: function (node) {
      return node.parentElement.closest('script, style, noscript') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    }});
    var all = [];
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      var n = model.nodes.length, at = 0;
      model.nodes.push(node);
      model.starts.push(model.owner.length);
      for (var c of node.data) {
        var part = letter(c);
        for (var k = 0; k < part.length; k++) { model.owner.push(n); model.from.push(at); model.to.push(at + c.length); }
        all.push(part);
        at += c.length;
      }
    }
    model.letters = all.join('');
    return model;
  }
  // The element a reference's `#anchor` names in the fragment, if any.
  function anchorIn(body, anchor) {
    if (!anchor) return null;
    var id = anchor;
    try { id = decodeURIComponent(anchor); } catch (e) {}
    return body.querySelector('[id="' + CSS.escape(id) + '"]') || body.querySelector('[name="' + CSS.escape(id) + '"]');
  }
  // The first letter at or after element `el`.
  function after(model, el) {
    for (var n = 0; n < model.nodes.length; n++) {
      var node = model.nodes[n];
      if (el.contains(node) || el.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) return model.starts[n];
    }
    return model.letters.length;
  }
  // The passages quoted from the document `url`, once each.
  function htmlPassages(aside, url) {
    var seen = {}, out = [];
    refs(aside).forEach(function (ref) {
      var key = ref.dataset.htmxoPdfKey, quote = ref.dataset.htmxoPdfQuote;
      if (!key || !quote || seen[key] || ref.dataset.htmxoPdfUrl !== url || ref.dataset.htmxoPdfKind !== 'html') return;
      seen[key] = true;
      out.push({key: key, quote: quote, anchor: ref.dataset.htmxoPdfAnchor || '', hue: ref.dataset.htmxoPdfHue || '',
                label: ref.textContent.trim()});
    });
    return out;
  }
  // Where the boxes the fragment's scroll boxes around `el` let show.
  function clipOf(el, doc) {
    var clip = {left: -Infinity, top: -Infinity, right: Infinity, bottom: Infinity};
    for (; el && el !== doc; el = el.parentElement) {
      var style = getComputedStyle(el);
      if (style.overflowX === 'visible' && style.overflowY === 'visible') continue;
      var r = el.getBoundingClientRect();
      clip = {left: Math.max(clip.left, r.left), top: Math.max(clip.top, r.top),
              right: Math.min(clip.right, r.right), bottom: Math.min(clip.bottom, r.bottom)};
    }
    return clip;
  }
  // Boxes on one line that touch, joined into one (the words of a line, set
  // in several elements).
  function lines(rects) {
    var out = [];
    rects.forEach(function (r) {
      var line = out.filter(function (o) {
        var shared = Math.min(o.bottom, r.bottom) - Math.max(o.top, r.top);
        return shared > 0.5 * Math.min(o.bottom - o.top, r.bottom - r.top) && r.left <= o.right + 2 && r.right >= o.left - 2;
      })[0];
      if (!line) return out.push({left: r.left, right: r.right, top: r.top, bottom: r.bottom});
      line.left = Math.min(line.left, r.left);
      line.right = Math.max(line.right, r.right);
      line.top = Math.min(line.top, r.top);
      line.bottom = Math.max(line.bottom, r.bottom);
    });
    return out;
  }
  // Mark every passage of the document anew: each found from its anchor on,
  // else anywhere, as the boxes its words take on screen, line by line.
  function placeAll(aside, file) {
    if (aside.htmxoPdfFile !== file || !file.loaded) return;
    var model = file.model || (file.model = textOf(file.body)), box = file.doc.getBoundingClientRect();
    var located = {};
    file.layer.replaceChildren();
    htmlPassages(aside, file.url).forEach(function (passage) {
      var wanted = lettersOf(passage.quote), el = anchorIn(file.body, passage.anchor), at = null;
      if (el) {
        var start = after(model, el);
        at = found(model.letters.slice(start), wanted);
        if (at) at = [at[0] + start, at[1]];
      }
      at = at || found(model.letters, wanted);
      located[passage.key] = !!at;
      if (!at) return;
      // Every text node from the passage's first letter to its last, the
      // spaces and punctuation between them too (a code token of its own),
      // as one box per line.
      var first = model.owner[at[0]], last = model.owner[at[0] + at[1] - 1], rects = [];
      for (var n = first; n <= last; n++) {
        var node = model.nodes[n], range = document.createRange();
        range.setStart(node, n === first ? model.from[at[0]] : 0);
        range.setEnd(node, n === last ? model.to[at[0] + at[1] - 1] : node.length);
        var clip = clipOf(node.parentElement, file.doc);
        Array.prototype.forEach.call(range.getClientRects(), function (r) {
          var cut = {left: Math.max(r.left, clip.left), right: Math.min(r.right, clip.right),
                     top: Math.max(r.top, clip.top), bottom: Math.min(r.bottom, clip.bottom)};
          if (cut.right - cut.left >= 1 && cut.bottom - cut.top >= 1) rects.push(cut);
        });
      }
      lines(rects).forEach(function (r) {
        var hit = document.createElement('div');
        hit.className = 'htmxo-pdf-hit';
        hit.dataset.htmxoPdfKey = passage.key;
        if (passage.hue) hit.dataset.htmxoPdfHue = passage.hue;
        hit.title = passage.label;
        hit.style.left = (r.left - box.left) + 'px';
        hit.style.top = (r.top - box.top) + 'px';
        hit.style.width = (r.right - r.left) + 'px';
        hit.style.height = (r.bottom - r.top) + 'px';
        file.layer.appendChild(hit);
      });
    });
    file.found = located;
    light(aside);
  }

  // Scroll the panel to `top`, and note where it goes: the place it comes
  // back to after a move, without waiting for its scroll event.
  function scrollPanel(aside, top, smooth) {
    top = Math.max(0, Math.min(top, aside.scrollHeight - aside.clientHeight));
    aside.scrollTo({top: top, behavior: smooth ? 'smooth' : 'instant'});
    aside.htmxoPdfScrolled = top;
  }
  // Scroll the panel to a passage, a third of the way down, or to a page's top.
  function reach(aside, target, smooth) {
    var bar = aside.querySelector('.htmxo-pdf-bar').offsetHeight;
    var top = aside.scrollTop + target.getBoundingClientRect().top - aside.getBoundingClientRect().top;
    top -= target.classList.contains('htmxo-pdf-hit') ? aside.clientHeight / 3 : bar + 8;
    scrollPanel(aside, top, smooth);
  }
  // The page shown: the one the panel went to last, until the reader scrolls
  // it; then the one at the panel's upper third.
  function current(aside) {
    if (aside.htmxoPdfPinned) return aside.htmxoPdfPinned;
    var line = aside.getBoundingClientRect().top + aside.clientHeight / 3, n = 1;
    aside.htmxoPdfFile.boxes.forEach(function (entry, i) { if (entry.box.getBoundingClientRect().top <= line) n = i + 1; });
    return n;
  }
  function info(aside) {
    var file = aside.htmxoPdfFile;
    if (!file || !file.boxes.length) return;
    aside.querySelector('[data-htmxo-pdf-page-info]').textContent =
      text(aside, 'Page').replace('{page}', current(aside)).replace('{pages}', file.boxes.length);
  }
  function wire(aside) {
    if (aside.htmxoPdfWired) return;
    aside.htmxoPdfWired = true;
    var at = null;
    aside.addEventListener('scroll', function () {
      // the place it is at, to come back to after closing or moving it
      if (!aside.hidden && aside.isConnected) aside.htmxoPdfScrolled = aside.scrollTop;
      requestAnimationFrame(function () { info(aside); });
    }, {passive: true});
    ['wheel', 'touchstart', 'keydown', 'pointerdown'].forEach(function (name) {
      aside.addEventListener(name, function () { aside.htmxoPdfPinned = null; }, {passive: true});
    });
    // Pointing at a passage names it in the group (lighting its references),
    // without moving anything; a click on it goes to its reference.
    function point(hit) {
      var key = hit ? hit.dataset.htmxoPdfKey : null;
      if (key === at) return;
      at = key;
      announce(group(aside), key == null ? [] : [key], hit || aside);
    }
    aside.addEventListener('mouseover', function (e) { point(e.target.closest('.htmxo-pdf-hit')); });
    aside.addEventListener('mouseleave', function () { point(null); });
    aside.addEventListener('click', function (e) {
      var hit = e.target.closest('.htmxo-pdf-hit');
      if (hit) goTo(aside, hit.dataset.htmxoPdfKey);
    });
  }
  // Whether all of `el` is in view: in the window below a sticky header, and
  // inside every scroll box around it.
  function whole(el) {
    var r = el.getBoundingClientRect();
    if (r.top < stickyTop() || r.bottom > window.innerHeight) return false;
    for (var box = el.parentElement; box && box !== document.body; box = box.parentElement) {
      if (box.scrollHeight <= box.clientHeight || !/auto|scroll/.test(getComputedStyle(box).overflowY)) continue;
      var b = box.getBoundingClientRect();
      if (r.top < b.top || r.bottom > b.bottom) return false;
    }
    return true;
  }
  // Go to a passage's reference: the one clicked last when it is shown, else
  // the first one shown, flashed; scrolled to the middle of its scroll box
  // only when it is not all in view, so the panel stays under the pointer.
  function goTo(aside, key) {
    aside.htmxoPdfActive = key;
    light(aside);
    var event = new CustomEvent('htmxo:pdf-goto', {bubbles: true, cancelable: true, detail: {key: key, group: group(aside)}});
    if (!aside.dispatchEvent(event)) return;
    var list = refs(aside).filter(function (r) { return r.dataset.htmxoPdfKey === key; });
    var last = aside.htmxoPdfRef, ref = last && list.indexOf(last) >= 0 && visible(last) ? last : list.filter(visible)[0];
    if (!ref) return;
    if (!whole(ref)) ref.scrollIntoView({block: 'center'});
    reveal(aside, ref);   // not under the panel below
    ref.removeAttribute('data-htmxo-pdf-flash');
    void ref.offsetWidth;
    ref.setAttribute('data-htmxo-pdf-flash', '');
    setTimeout(function () { ref.removeAttribute('data-htmxo-pdf-flash'); }, 1600);
  }
  // Show document `url` at the passage `key` on page `page` (of a PDF) or from
  // `anchor` on (of an HTML document), or at the page's top (the anchor, else
  // the top) without one, opening the panel. Until it is there, the pages are
  // marked `aria-busy`.
  function show(aside, o) {
    if (!o || !o.url) return;
    wire(aside);
    var kind = o.kind === 'html' || o.kind === 'pdf' ? o.kind : kindOf(aside, o.url), anchor = o.anchor ? String(o.anchor) : '';
    pick(aside, o.url, o.title, kind);
    aside.htmxoPdfShown = true;
    open(aside, true, o.ref || null, o.from || null);
    var page = Math.max(1, Number(o.page) || 1), key = o.key == null ? null : String(o.key);
    aside.querySelector('[data-htmxo-pdf-file]').href = kind === 'html' ? o.url + (anchor ? '#' + anchor : '') : o.url + '#page=' + page;
    aside.htmxoPdfActive = key;
    light(aside);
    var token = (aside.htmxoPdfToken || 0) + 1;
    aside.htmxoPdfToken = token;
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    view.setAttribute('aria-busy', 'true');
    function done() { if (token === aside.htmxoPdfToken) view.removeAttribute('aria-busy'); }
    var file = aside.htmxoPdfFile;
    var shown = file && file.kind === kind && file.url === o.url && (kind === 'html' ? file.loaded : file.boxes.length > 0);
    // another document: the one shown goes at once (a failed one too)
    if (!(file && file.kind === kind && file.url === o.url)) clear(aside);
    aside.setAttribute('data-htmxo-pdf-kind', kind);
    if (!shown) note(aside, text(aside, 'Loading'));
    if (kind === 'html') {
      htmlDocument(aside, o.url).then(function (file) {
        if (token !== aside.htmxoPdfToken) return;
        placeAll(aside, file);
        var hit = key ? file.layer.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-key="' + CSS.escape(key) + '"]') : null;
        var quoted = key != null && Object.prototype.hasOwnProperty.call(file.found || {}, key);
        note(aside, quoted && !file.found[key] ? text(aside, 'NotInDocument') : '');
        var place = hit || anchorIn(file.body, anchor);
        if (place) reach(aside, place, o.smooth);
        else scrollPanel(aside, 0, o.smooth);   // the document's top
        done();
      }).catch(function (error) { if (token === aside.htmxoPdfToken) { failed(aside, error); done(); } });
      return;
    }
    layout(aside, o.url).then(function (file) {
      if (token !== aside.htmxoPdfToken) return;
      var n = Math.min(page, file.boxes.length);
      return marks(aside, file, n).then(function () {
        if (token !== aside.htmxoPdfToken) return;
        var box = file.boxes[n - 1].box;
        var hit = key ? box.querySelector('.htmxo-pdf-hit[data-htmxo-pdf-key="' + CSS.escape(key) + '"]') : null;
        var quoted = key && refs(aside).some(function (r) { return r.dataset.htmxoPdfKey === key && r.dataset.htmxoPdfQuote; });
        note(aside, quoted && !hit ? text(aside, 'NotFound') : '');
        aside.htmxoPdfPinned = n;
        reach(aside, hit || box, o.smooth);
        info(aside);
        done();
      });
    }).catch(function (error) { if (token === aside.htmxoPdfToken) { failed(aside, error); done(); } });
  }
  // Lay the pages out again at the panel's new width, at the same place.
  function refresh(aside) {
    var file = aside.htmxoPdfFile;
    if (aside.hidden || !file || file.kind !== 'pdf') return;   // an HTML document's marks follow it themselves
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    if (Math.max(200, view.clientWidth) === file.width) return;
    var share = aside.scrollTop / Math.max(1, aside.scrollHeight);
    layout(aside, file.url).then(function () {
      scrollPanel(aside, share * aside.scrollHeight);
      info(aside);
    }).catch(function (error) { failed(aside, error); });
  }
  function step(aside, by) {
    var file = aside.htmxoPdfFile;
    if (!file || !file.boxes.length) return;
    var n = Math.min(Math.max(1, current(aside) + by), file.boxes.length);
    aside.htmxoPdfPinned = n;
    reach(aside, file.boxes[n - 1].box, true);
    info(aside);
  }

  // Capture, so a reference in a table row never also opens or closes the row.
  document.addEventListener('click', function (event) {
    var target = event.target.closest && event.target.closest('[data-htmxo-pdf-ref], [data-htmxo-pdf-toggle], ' +
      '[data-htmxo-pdf-tab], [data-htmxo-pdf-step], [data-htmxo-pdf-close], [data-htmxo-pdf-colours], [data-htmxo-pdf-place]');
    if (!target) return;
    if (target.hasAttribute('data-htmxo-pdf-ref')) {
      // a modified click opens the file itself, as does a page without the panel
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      var panel = panelOf(target);
      if (!panel) return;
      event.preventDefault();
      event.stopPropagation();
      show(panel, {url: target.dataset.htmxoPdfUrl, page: target.dataset.htmxoPdfPage, key: target.dataset.htmxoPdfKey,
                   kind: target.dataset.htmxoPdfKind === 'html' ? 'html' : 'pdf', anchor: target.dataset.htmxoPdfAnchor,
                   title: target.dataset.htmxoPdfDocument, ref: target});
      return;
    }
    if (target.hasAttribute('data-htmxo-pdf-toggle') || target.hasAttribute('data-htmxo-pdf-tab')) {
      var toggled = panelOf(target);
      if (!toggled) return;
      event.stopPropagation();
      toggle(toggled, target.hasAttribute('data-htmxo-pdf-tab') ? true : null, target);
      return;
    }
    var aside = target.closest('[data-htmxo-pdf-viewer]');
    if (!aside) return;
    event.stopPropagation();
    if (target.hasAttribute('data-htmxo-pdf-step')) step(aside, Number(target.dataset.htmxoPdfStep));
    else if (target.hasAttribute('data-htmxo-pdf-close')) open(aside, false);
    else if (target.hasAttribute('data-htmxo-pdf-place')) choose(aside, target.dataset.htmxoPdfPlace);
    else if (target.hasAttribute('data-htmxo-pdf-colours')) {
      var on = target.getAttribute('aria-pressed') !== 'true';
      target.setAttribute('aria-pressed', String(on));
      aside.dataset.htmxoPdfHues = on ? 'on' : 'off';
    }
  }, true);
  // A document chosen in the chooser (a pill, or a row of the list) is shown
  // from its first page.
  document.addEventListener('change', function (event) {
    var radio = event.target;
    if (!(radio && radio.type === 'radio' && radio.checked && radio.closest)) return;
    var box = radio.closest('[data-htmxo-pdf-document]'), aside = box && box.closest('[data-htmxo-pdf-viewer]');
    if (aside) show(aside, {url: radio.value, page: 1, kind: radio.dataset.htmxoPdfKind === 'html' ? 'html' : 'pdf'});
  });
  // New content (an htmx swap, a thread's new item) may bring references:
  // mark their passages on the pages drawn (in the HTML document shown), and
  // show them lit or gone to.
  function renew() {
    document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(function (aside) {
      var file = aside.htmxoPdfFile;
      if (file && !aside.hidden && file.kind === 'html') placeAll(aside, file);
      else if (file && !aside.hidden) file.boxes.forEach(function (entry, i) {
        if (entry.task) marks(aside, file, i + 1).catch(function (error) { failed(aside, error); });
      });
      light(aside);
    });
  }
  document.addEventListener('htmx:load', renew);
  document.addEventListener('htmxo:thread-updated', renew);
  // The pages are drawn to the panel's width: lay them out again when that
  // changes; the panel's size stays within its bounds.
  var pending = null;
  window.addEventListener('resize', function () {
    clearTimeout(pending);
    pending = setTimeout(function () {
      document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(function (aside) {
        if (!aside.hidden && wrapOf(aside)) { resize(aside, null); room(aside); }
        refresh(aside);
      });
    }, 200);
  });
  // A narrow screen shows every placement below; a wide one, the reader's.
  if (narrow && typeof narrow.addEventListener === 'function') narrow.addEventListener('change', function () {
    document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(function (aside) {
      if (!aside.hidden && wrapOf(aside)) { place(aside, aside.htmxoPdfPlace); refresh(aside); }
    });
  });
  window.htmxoPdf = {
    show: function (panel, o) { var aside = element(panel); if (aside) show(aside, o); },
    toggle: function (panel, state) { var aside = element(panel); if (aside) toggle(aside, state); },
    place: function (panel, placement) { var aside = element(panel); if (aside && wrapOf(aside)) choose(aside, placement); }
  };
})();
"""))

"""
    pdf_panel_assets()

Style and script for [`pdf_panel`](@ref), [`pdf_ref`](@ref),
[`pdf_toggle`](@ref), [`pdf_beside`](@ref) and [`pdf_overlay`](@ref). A `pdf_panel` carries them
itself unless built with `assets=false`; put them in the head of a page that
builds its panel so.
"""
pdf_panel_assets() = (pdf_panel_styles(), pdf_panel_script())
