# --- PDF panel: a document beside the text, its quoted passages marked ---
#
# A side panel that shows a PDF (every page one below the other, each drawn by
# PDF.js as it comes into view) beside the content that quotes it. The
# references in the content (`pdf_ref`) name the file, the page and the quoted
# words; each reference's passage is marked on its page, in the reference's
# colour. Every reference and mark is always lightly highlighted; pointing at
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
`colours`, `colours_help`, `open_file`, `close`) and the status line
(`loading`, `failed`, `not_found`, `empty`).
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
    empty::String           # status: the panel opened before any reference
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
        empty = "No document yet: a reference opens its document here.",
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
        empty = "Noch kein Dokument: Ein Verweis öffnet sein Dokument hier.",
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
_pdf_texts(::Nothing) = pdf_panel_texts(_pdf_locale(page_lang()))
_pdf_texts(texts::PdfPanelTexts) = texts
_pdf_texts(texts) = throw(ArgumentError("pdf_panel: `texts` takes a PdfPanelTexts (pdf_panel_texts(…)), got $(repr(texts))"))
_pdf_locale(::Nothing) = :en
function _pdf_locale(lang::AbstractString)
    primary = Symbol(lowercase(first(split(lang, '-'))))
    haskey(_PDF_TEXT_LOCALES, primary) ? primary : :en
end

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

_pdf_document(url::AbstractString) = (_pdf_file_name(url), _pdf_url(url))
_pdf_document(d::Pair{<:AbstractString,<:AbstractString}) = (String(first(d)), _pdf_url(last(d)))
_pdf_document(d) = throw(ArgumentError(
    "pdf_panel: a document is its address or `title => address`, got $(repr(d))"))

"""
    pdf_panel(documents=(); id, link=id, texts=nothing, pdfjs, class="", assets=true)

A side panel that shows a PDF beside the content that quotes it: every page of
the file one below the other, each drawn as it comes into view (PDF.js, loaded
from jsDelivr the first time the panel opens), with the passage of every
[`pdf_ref`](@ref) to the file marked on its page in the reference's colour.
It starts closed. A reference's click opens it at its passage, a
[`pdf_toggle`](@ref) shows and hides it, and its bar has the document chooser,
the page line with previous and next page, "Colours" (each passage in its own
colour, or only the passages pointed at and gone to), a link that opens the
file itself and a close button. [`pdf_beside`](@ref) places it beside the
content, pinned while the content scrolls by.

- `documents`: the files the chooser offers, each its address (named by its
  file name) or `title => address`. A reference to a file not listed adds it.
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

Script hooks: `window.htmxoPdf.show(panel, {url, page, key})` and
`window.htmxoPdf.toggle(panel, open)` (`panel` an element or its id). The
panel dispatches `htmxo:pdf-toggle` (detail `{open}`) when it opens or
closes, and a cancelable `htmxo:pdf-goto` (detail `{key, group}`) before a
mark's click goes to its reference: call `preventDefault()` to go there
yourself (to open the collapsed group a table row sits in, say).

The panel is HTML only: a Markdown answer leaves it out.

```julia
@get bericht() = pdf_beside(
    h.article(h.p("Der Träger sichert den Kinderschutz ",
        pdf_ref("(Konzept, S. 12)", "/files/konzept.pdf"; page=12, panel="originale",
                quoted="Kinderschutz ist Aufgabe aller Träger"), ".")),
    pdf_panel(["Konzept" => "/files/konzept.pdf"]; id="originale"))
```
"""
function pdf_panel(documents=(); id::AbstractString, link::AbstractString=id, texts=nothing,
                   pdfjs::AbstractString=_PDFJS_URL, class::AbstractString="", assets::Bool=true)
    isempty(id) && throw(ArgumentError("pdf_panel: `id` must not be empty"))
    isempty(link) && throw(ArgumentError("pdf_panel: `link` must not be empty"))
    t = _pdf_texts(texts)
    docs = [_pdf_document(d) for d in (documents isa Union{AbstractString,Pair} ? (documents,) : documents)]
    length(unique(last.(docs))) == length(docs) || throw(ArgumentError(
        "pdf_panel: a document is listed twice: $(join(unique(filter(u -> count(==(u), last.(docs)) > 1, last.(docs))), ", "))"))
    first_url = isempty(docs) ? nothing : last(first(docs))
    panel = h.aside(; id, class=isempty(class) ? "htmxo-pdf-panel" : "htmxo-pdf-panel " * class,
                    hidden=true, aria_label=t.label, data_htmxo_pdf_viewer="", data_htmxo_pdf_link=link,
                    data_htmxo_pdfjs=endswith(pdfjs, '/') ? pdfjs : pdfjs * "/",
                    data_htmxo_pdf_hues="on",
                    data_text_page=t.page, data_text_loading=t.loading, data_text_failed=t.failed,
                    data_text_not_found=t.not_found, data_text_empty=t.empty,
                    data_text_documents=t.documents, data_text_search=t.search, data_text_no_match=t.no_match)(
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
                h.button(; type="button", data_htmxo_pdf_close="", aria_label=t.close, title=t.close)("✕"))),
        h.p(; class="htmxo-pdf-note", data_htmxo_pdf_note="", role="status")(),
        h.div(; class="htmxo-pdf-pages", data_htmxo_pdf_pages="")())
    html_only(panel)
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
function _pdf_chooser(id::AbstractString, docs, t::PdfPanelTexts)
    name, n = _pdf_choice_name(id), length(docs)
    first_url = n == 0 ? nothing : last(first(docs))
    form = n == 0 ? () :
        n == 1 ? (h.span(first(only(docs)); class="htmxo-pdf-title", data_htmxo_pdf_url=first_url),) :
        n <= _RADIO_MAX ? (radio_group(name, [url => title for (title, url) in docs]; label=t.documents, value=first_url),) :
        (_choice_list(name, t.documents, [(; value=url, label=title) for (title, url) in docs], first_url;
                      texts=error_texts(:en; choice_search=t.search, choice_no_match=t.no_match)),)
    h.div(; class="htmxo-pdf-documents", data_htmxo_pdf_document="", data_htmxo_pdf_pills=string(_RADIO_MAX))(form...)
end

"""
    pdf_ref(text, url; page=1, panel, quoted=nothing, key=nothing, hue=nothing,
            document=nothing, attrs...)

A reference to a passage of a PDF: a link to `url` at `page` (`url#page=12`)
that, on a page with the [`pdf_panel`](@ref) `panel`, opens that panel at the
passage instead, marked. It is a chip: always lightly highlighted in its
colour, more strongly while pointed at, most strongly once clicked. A
modified click (new tab, new window) and a page without the panel open the
file itself. Its Markdown is the link, `[text](url#page=12)`.

- `page`: the page the passage stands on, counted from 1 as a PDF viewer
  counts, not the number printed on the page.
- `quoted`: the quoted words. Every reference with a quote marks its passage
  on its page; one without opens the page's top and marks nothing.
- `key`: the passage's key in the panel's hover-link group. References with
  one key share one mark (the same passage quoted twice), and a table row
  keyed alike (`link=`, **Hover linking**) lights it too. It defaults to a
  digest of `url`, `page` and `quoted`.
- `hue`: the colour, 1 to 8, of HTMXObjects' categorical palette
  (`--htmxo-category-1` …); by default one picked from `key`, so a passage
  keeps its colour wherever it is quoted. Give neighbouring references
  different hues (`hue=mod1(i, 8)`) where they stand in a list.
- `document`: the file's title in the panel's chooser when the panel does not
  list it; by default its file name.
- `attrs` go on the link (`class`, `title`, `id`, …).

A reference inside a table row of the panel's link group takes the row's key:
the row announces its key when pointed at, so give the reference the row's
link key.
"""
function pdf_ref(text, url::AbstractString; page::Integer=1, panel::AbstractString, quoted=nothing,
                 key=nothing, hue=nothing, document=nothing, attrs...)
    isempty(url) && throw(ArgumentError("pdf_ref: `url` must not be empty"))
    isempty(panel) && throw(ArgumentError("pdf_ref: `panel` must name the pdf_panel's id"))
    page >= 1 || throw(ArgumentError("pdf_ref: `page` counts from 1, got $page"))
    quoted === nothing || quoted isa AbstractString || throw(ArgumentError(
        "pdf_ref: `quoted` is the quoted words as a string, got $(repr(quoted))"))
    quoted isa AbstractString && isempty(strip(quoted)) && (quoted = nothing)
    hue === nothing || (hue isa Integer && 1 <= hue <= _TALLY_PALETTE) || throw(ArgumentError(
        "pdf_ref: `hue` is a colour of the categorical palette, 1 to $_TALLY_PALETTE, got $(repr(hue))"))
    file = _pdf_url(url)
    key = key === nothing ? (quoted === nothing ? nothing : _thread_digest(string(file, "#page=", page, "\n", quoted))) :
        string(key)
    hue = hue === nothing ? (key === nothing ? nothing : Int(_fnv1a(key) % _TALLY_PALETTE) + 1) : Int(hue)
    h.a(; href=string(file, "#page=", page), data_htmxo_pdf_ref="", data_htmxo_pdf_panel=panel,
        data_htmxo_pdf_url=file, data_htmxo_pdf_page=string(page), data_htmxo_pdf_quote=quoted,
        data_htmxo_pdf_key=key, data_htmxo_pdf_hue=hue === nothing ? nothing : string(hue),
        data_htmxo_pdf_document=document === nothing ? nothing : string(document),
        aria_controls=panel, attrs...)(text)
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
    pdf_beside(content, panel; class="")

`content` with the [`pdf_panel`](@ref) `panel` beside it: while the panel is
open the two share the width (the panel 40 %, at least 22rem; set
`--htmxo-pdf-width` to change it) and the panel stays in view while the
content scrolls by, below a page's own sticky header (`--htmxo-sticky-top`).
Closed, the content has the whole width. On a narrow screen the open panel
lies over the lower part of the window. Opening or closing it keeps the
reference clicked last (else the content at the top of the window, below
a table's sticky header) where it was on screen while the content wraps
anew.
"""
pdf_beside(content, panel; class::AbstractString="") =
    h.div(; class=isempty(class) ? "htmxo-pdf-beside" : "htmxo-pdf-beside " * class, data_htmxo_pdf_beside="")(
        h.div(; class="htmxo-pdf-beside-content")(content), panel)

"""
    pdf_panel_styles()

CSS for [`pdf_panel`](@ref), [`pdf_ref`](@ref) and [`pdf_beside`](@ref).
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
.htmxo-pdf-beside[data-htmxo-pdf-open] {
    display: grid; gap: 1rem; align-items: start;
    grid-template-columns: minmax(0, 1fr) minmax(min(22rem, 100%), var(--htmxo-pdf-width, 40%));
}
.htmxo-pdf-beside > .htmxo-pdf-beside-content { min-width: 0; }
/* What sticks is the grid's cell: the panel, or the private wrapper around it
   (which carries its "not public" mark), so it never scrolls away in a box no
   taller than itself. */
.htmxo-pdf-beside > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
    position: sticky; top: calc(var(--htmxo-sticky-top, 0px) + .5rem);
    max-height: calc(100vh - var(--htmxo-sticky-top, 0px) - 1rem);
    max-height: calc(100dvh - var(--htmxo-sticky-top, 0px) - 1rem);
}
.htmxo-pdf-beside > .htmxo-private:has(> .htmxo-pdf-panel) { display: flex; flex-direction: column; align-items: flex-start; }
.htmxo-pdf-beside > .htmxo-private > .htmxo-pdf-panel { align-self: stretch; min-height: 0; max-height: none; }
.htmxo-pdf-beside > .htmxo-private:has(> .htmxo-pdf-panel[hidden]) { display: none; }
@media (max-width: 48rem) {
    .htmxo-pdf-beside[data-htmxo-pdf-open] { display: block; }
    .htmxo-pdf-beside > :is(.htmxo-pdf-panel, .htmxo-private:has(> .htmxo-pdf-panel)) {
        position: fixed; inset: auto .5rem .5rem .5rem; top: auto; z-index: 20; max-height: 60vh; max-height: 60dvh;
        box-shadow: 0 4px 16px rgba(0, 0, 0, .25);
    }
}
}
.htmxo-pdf-controls button { width: auto; margin: 0; padding: .15rem .55rem; font-size: inherit; line-height: 1.4; }
.htmxo-pdf-controls [data-htmxo-pdf-close] { margin-left: auto; }
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
/* Colours off: only the passages pointed at and gone to, in a marker's yellow. */
.htmxo-pdf-panel[data-htmxo-pdf-hues="off"] .htmxo-pdf-hit { visibility: hidden; --htmxo-pdf-hue: #ffc400; }
.htmxo-pdf-panel[data-htmxo-pdf-hues="off"] .htmxo-pdf-hit:is([data-htmxo-pdf-lit], [data-htmxo-pdf-active]) { visibility: visible; }
"""))

"""
    pdf_panel_script()

Client runtime for [`pdf_panel`](@ref), [`pdf_ref`](@ref),
[`pdf_toggle`](@ref) and [`pdf_beside`](@ref): delegated listeners that serve
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
    var aside = document.getElementById(el.dataset.htmxoPdfPanel || el.dataset.htmxoPdfToggle || '');
    return aside && aside.hasAttribute('data-htmxo-pdf-viewer') ? aside : null;
  }
  function group(aside) { return aside.dataset.htmxoPdfLink || aside.id; }
  function refs(aside) {
    return Array.prototype.slice.call(document.querySelectorAll(
      '[data-htmxo-pdf-ref][data-htmxo-pdf-panel="' + CSS.escape(aside.id) + '"]'));
  }
  function beside(aside) { return aside.closest('[data-htmxo-pdf-beside]'); }
  function content(aside) {
    var wrap = beside(aside);
    return wrap ? wrap.querySelector(':scope > .htmxo-pdf-beside-content') : null;
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
    var observer = new ResizeObserver(function () {
      var moved = el.getBoundingClientRect().top - top;
      if (Math.abs(moved) >= 0.5) window.scrollBy(0, moved);
    });
    var timer = setTimeout(stop, 1000);
    function stop() {
      observer.disconnect();
      clearTimeout(timer);
      STOPS.forEach(function (name) { window.removeEventListener(name, stop, true); });
      if (aside.htmxoPdfHold === stop) aside.htmxoPdfHold = null;
    }
    STOPS.forEach(function (name) { window.addEventListener(name, stop, true); });
    observer.observe(box);
    aside.htmxoPdfHold = stop;
  }
  function open(aside, state, ref) {
    if (ref) aside.htmxoPdfRef = aside.htmxoPdfKeep = ref;
    if (state !== aside.hidden) return;
    // Closing keeps the reference clicked last while the panel was open.
    var keep = state ? ref : aside.htmxoPdfKeep;
    if (state && !ref) aside.htmxoPdfKeep = null;
    var wrap = beside(aside), held = anchor(aside, keep), top = held && held.getBoundingClientRect().top;
    aside.hidden = !state;
    if (wrap) wrap.toggleAttribute('data-htmxo-pdf-open', state);
    document.querySelectorAll('[data-htmxo-pdf-toggle="' + CSS.escape(aside.id) + '"]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(state));
    });
    if (!state) light(aside);
    if (held) {
      var moved = held.getBoundingClientRect().top - top;
      if (moved) window.scrollBy(0, moved);
      hold(aside, held, top);
    }
    aside.dispatchEvent(new CustomEvent('htmxo:pdf-toggle', {bubbles: true, detail: {open: state}}));
  }
  function toggle(aside, state) {
    if (state == null) state = aside.hidden;
    if (!state) return open(aside, false);
    if (aside.htmxoPdfFile) { open(aside, true); refresh(aside); return; }
    var url = chosen(aside);
    if (url) show(aside, {url: url, page: 1});
    else { open(aside, true); note(aside, text(aside, 'Empty')); }
  }

  // --- The document chooser, as pdf_panel's `_pdf_chooser` draws it, never a
  // native select box: one document is its title, a few a row of pills
  // (radio_group's markup), a long list a searchable list (choice_list's
  // markup, which the page's choice_list script drives). Each document is a
  // radio whose value is its address; the lone title carries its address.
  function chooser(aside) { return aside.querySelector('[data-htmxo-pdf-document]'); }
  function choiceTitle(radio) {
    var label = radio.closest('label'), name = label.querySelector('.htmxo-choice-label');
    return (name || label).textContent.trim();
  }
  function documents(box) {
    var one = box.querySelector('[data-htmxo-pdf-url]');
    if (one) return [{url: one.dataset.htmxoPdfUrl, title: one.textContent}];
    return Array.prototype.map.call(box.querySelectorAll('input[type="radio"]'), function (radio) {
      return {url: radio.value, title: choiceTitle(radio)};
    });
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
    function radio(d) {
      var input = make('input', d.url === url ? {type: 'radio', name: name, value: d.url, checked: ''} :
                                                {type: 'radio', name: name, value: d.url});
      input.checked = d.url === url;
      return input;
    }
    var title = (docs.filter(function (d) { return d.url === url; })[0] || {title: ''}).title, form;
    if (docs.length === 1) form = make('span', {'class': 'htmxo-pdf-title', 'data-htmxo-pdf-url': docs[0].url}, [docs[0].title]);
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
  // The chooser names file `url` as the one shown, adding it (titled `title`,
  // else by its file name) when it is not listed. No event is sent: the
  // chooser's own change is the reader's choice.
  function pick(aside, url, title) {
    var box = chooser(aside), docs = documents(box);
    if (!docs.some(function (d) { return d.url === url; })) {
      docs.push({url: url, title: title || fileName(url)});
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
      file.boxes.forEach(function (entry, i) { release(file, i + 1); });
    }
    aside.htmxoPdfFile = null;
    aside.htmxoPdfPinned = null;
    aside.querySelector('[data-htmxo-pdf-pages]').replaceChildren();
    aside.querySelector('[data-htmxo-pdf-page-info]').textContent = '';
    aside.scrollTop = 0;
  }
  // The file's pages laid out at the panel's width, a box of its final size
  // each, so nothing moves as they are drawn; each drawn once it comes near
  // the panel's view and let go again far from it.
  function layout(aside, url) {
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    var width = Math.max(200, view.clientWidth), file = aside.htmxoPdfFile;
    if (file && file.url === url && file.width === width) return file.ready;
    if (file && file.url !== url) { clear(aside); width = Math.max(200, view.clientWidth); }
    else if (file && file.observer) file.observer.disconnect();
    file = {url: url, width: width, boxes: []};
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
      if (!key || !quote || seen[key] || ref.dataset.htmxoPdfUrl !== url || (Number(ref.dataset.htmxoPdfPage) || 1) !== n) return;
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
  // Scroll the panel to a passage, a third of the way down, or to a page's top.
  function reach(aside, target, smooth) {
    var bar = aside.querySelector('.htmxo-pdf-bar').offsetHeight;
    var top = aside.scrollTop + target.getBoundingClientRect().top - aside.getBoundingClientRect().top;
    top -= target.classList.contains('htmxo-pdf-hit') ? aside.clientHeight / 3 : bar + 8;
    aside.scrollTo({top: Math.max(0, top), behavior: smooth ? 'smooth' : 'instant'});
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
    aside.addEventListener('scroll', function () { requestAnimationFrame(function () { info(aside); }); }, {passive: true});
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
    ref.removeAttribute('data-htmxo-pdf-flash');
    void ref.offsetWidth;
    ref.setAttribute('data-htmxo-pdf-flash', '');
    setTimeout(function () { ref.removeAttribute('data-htmxo-pdf-flash'); }, 1600);
  }
  // Show file `url` at the passage `key` on page `page`, or at the page's top
  // without one, opening the panel. Until it is there, the pages are marked
  // `aria-busy`.
  function show(aside, o) {
    if (!o || !o.url) return;
    wire(aside);
    pick(aside, o.url, o.title);
    open(aside, true, o.ref || null);
    var page = Math.max(1, Number(o.page) || 1), key = o.key == null ? null : String(o.key);
    aside.querySelector('[data-htmxo-pdf-file]').href = o.url + '#page=' + page;
    aside.htmxoPdfActive = key;
    light(aside);
    var token = (aside.htmxoPdfToken || 0) + 1;
    aside.htmxoPdfToken = token;
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    view.setAttribute('aria-busy', 'true');
    function done() { if (token === aside.htmxoPdfToken) view.removeAttribute('aria-busy'); }
    var file = aside.htmxoPdfFile;
    if (!file || file.url !== o.url || !file.boxes.length) note(aside, text(aside, 'Loading'));
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
    if (aside.hidden || !file) return;
    var view = aside.querySelector('[data-htmxo-pdf-pages]');
    if (Math.max(200, view.clientWidth) === file.width) return;
    var share = aside.scrollTop / Math.max(1, aside.scrollHeight);
    layout(aside, file.url).then(function () {
      aside.scrollTo({top: share * aside.scrollHeight, behavior: 'instant'});
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
      '[data-htmxo-pdf-step], [data-htmxo-pdf-close], [data-htmxo-pdf-colours]');
    if (!target) return;
    if (target.hasAttribute('data-htmxo-pdf-ref')) {
      // a modified click opens the file itself, as does a page without the panel
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      var panel = panelOf(target);
      if (!panel) return;
      event.preventDefault();
      event.stopPropagation();
      show(panel, {url: target.dataset.htmxoPdfUrl, page: target.dataset.htmxoPdfPage, key: target.dataset.htmxoPdfKey,
                   title: target.dataset.htmxoPdfDocument, ref: target});
      return;
    }
    if (target.hasAttribute('data-htmxo-pdf-toggle')) {
      var toggled = panelOf(target);
      if (!toggled) return;
      event.stopPropagation();
      toggle(toggled);
      return;
    }
    var aside = target.closest('[data-htmxo-pdf-viewer]');
    if (!aside) return;
    event.stopPropagation();
    if (target.hasAttribute('data-htmxo-pdf-step')) step(aside, Number(target.dataset.htmxoPdfStep));
    else if (target.hasAttribute('data-htmxo-pdf-close')) open(aside, false);
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
    if (aside) show(aside, {url: radio.value, page: 1});
  });
  // New content (an htmx swap, a thread's new item) may bring references:
  // mark their passages on the pages drawn, and show them lit or gone to.
  function renew() {
    document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(function (aside) {
      var file = aside.htmxoPdfFile;
      if (file && !aside.hidden) file.boxes.forEach(function (entry, i) {
        if (entry.task) marks(aside, file, i + 1).catch(function (error) { failed(aside, error); });
      });
      light(aside);
    });
  }
  document.addEventListener('htmx:load', renew);
  document.addEventListener('htmxo:thread-updated', renew);
  // The pages are drawn to the panel's width: lay them out again when that changes.
  var pending = null;
  window.addEventListener('resize', function () {
    clearTimeout(pending);
    pending = setTimeout(function () { document.querySelectorAll('[data-htmxo-pdf-viewer]').forEach(refresh); }, 200);
  });
  window.htmxoPdf = {
    show: function (panel, o) { var aside = element(panel); if (aside) show(aside, o); },
    toggle: function (panel, state) { var aside = element(panel); if (aside) toggle(aside, state); }
  };
})();
"""))

"""
    pdf_panel_assets()

Style and script for [`pdf_panel`](@ref), [`pdf_ref`](@ref),
[`pdf_toggle`](@ref) and [`pdf_beside`](@ref). A `pdf_panel` carries them
itself unless built with `assets=false`; put them in the head of a page that
builds its panel so.
"""
pdf_panel_assets() = (pdf_panel_styles(), pdf_panel_script())
