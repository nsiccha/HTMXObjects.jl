# --- Card deck: a searchable deck of cards, as a grid or one card at a time ---
#
# A deck of cards (each one a node the app renders, in an `<article>` the deck
# makes) that the reader sees as a grid or as a carousel showing one card at a
# time, and switches between the two. A search box filters the cards by their
# text, a group filter by their group; the carousel pages over the cards left.
# The view and the current card ride the page address, so a link opens a deck
# at a card. Everything runs in the browser, so a static export works as live.

"""
    CardDeckTexts

The words of a [`card_deck`](@ref): its accessible name (`label`), the view
switch (`view`, `grid`, `carousel`), the search box (`search`) and its count
(`matches`, with `{shown}` and `{count}`), the note shown when no card is left
(`no_match`), the group filter (`groups`, `all`, and for a long list of groups
`group_search` and `group_no_match`), and the carousel's buttons (`previous`,
`next`) and position (`position`, with `{position}` and `{count}`).
Build one with [`card_deck_texts`](@ref).
"""
struct CardDeckTexts
    label::String           # the deck's accessible name
    view::String            # the view switch's accessible name
    grid::String            # the grid view
    carousel::String        # one card at a time
    search::String          # the search box's placeholder and accessible name
    matches::String         # the count while a search or group filters: "{shown}" of "{count}"
    no_match::String        # no card is left
    groups::String          # the group filter's accessible name
    all::String             # the group filter's "every group"
    group_search::String    # a long group list's search field
    group_no_match::String  # ... when no group matches it
    previous::String
    next::String
    position::String        # the carousel's position: "{position}" of "{count}"
end

const _DECK_TEXT_PLACEHOLDERS = (matches = (:shown, :count), position = (:position, :count))

const _DECK_TEXT_LOCALES = (
    en = (
        label = "Cards",
        view = "View",
        grid = "Grid",
        carousel = "Carousel",
        search = "Search the cards…",
        matches = "Matches: {shown} of {count}",
        no_match = "No card matches the search.",
        groups = "Group",
        all = "All",
        group_search = "Search the groups…",
        group_no_match = "No matching group",
        previous = "Previous card",
        next = "Next card",
        position = "{position} of {count}",
    ),
    de = (
        label = "Karten",
        view = "Ansicht",
        grid = "Übersicht",
        carousel = "Einzeln",
        search = "Karten durchsuchen…",
        matches = "Treffer: {shown} von {count}",
        no_match = "Keine Karte passt zur Suche.",
        groups = "Gruppe",
        all = "Alle",
        group_search = "Gruppen durchsuchen…",
        group_no_match = "Keine passende Gruppe",
        previous = "Vorige Karte",
        next = "Nächste Karte",
        position = "{position} von {count}",
    ),
)

"""
    card_deck_texts(locale::Symbol=:en; texts...)

The [`CardDeckTexts`](@ref) for `locale` (`:en` or `:de`), with any of its
texts replaced by keyword:

```julia
card_deck(cards; id="karten", texts=card_deck_texts(:de; carousel="Karteikarten"))
```

Without `texts=`, [`card_deck`](@ref) writes in the page's language
([`HTMXObjects.page_lang`](@ref): German under `__lang__ = "de"`, English for
any other and outside a route). An unknown locale or text name, or a
placeholder the text does not take, throws an `ArgumentError`.
"""
card_deck_texts(locale::Symbol=:en; texts...) =
    _locale_texts(CardDeckTexts, :card_deck_texts, _DECK_TEXT_LOCALES, _DECK_TEXT_PLACEHOLDERS, locale; texts...)

_deck_texts(::Nothing) = card_deck_texts(_lang_locale(_DECK_TEXT_LOCALES, page_lang()))
_deck_texts(texts::CardDeckTexts) = texts
_deck_texts(texts) = throw(ArgumentError("card_deck: `texts` takes a CardDeckTexts (card_deck_texts(…)), got $(repr(texts))"))

const _DECK_VIEWS = (:grid, :carousel)

# A card as the deck keeps it: its id, its group (`nothing` for none) and its
# content. A card is `(id, group, content)`, `(id, content)`, `id => content`
# or a NamedTuple with `id`, `content` and optionally `group`.
_deck_group(::Nothing) = nothing
_deck_group(group) = let g = string(group); isempty(g) ? nothing : g end
_deck_card(c::Tuple{Any,Any,Any}) = (string(c[1]), _deck_group(c[2]), c[3])
_deck_card(c::Tuple{Any,Any}) = (string(c[1]), nothing, c[2])
_deck_card(c::Pair) = (string(first(c)), nothing, last(c))
function _deck_card(c::NamedTuple)
    (haskey(c, :id) && haskey(c, :content)) || throw(ArgumentError(
        "card_deck: a card NamedTuple needs `id` and `content` (and may have `group`), got $(repr(keys(c)))"))
    (string(c.id), _deck_group(get(c, :group, nothing)), c.content)
end
_deck_card(c) = throw(ArgumentError(
    "card_deck: a card is (id, group, content), (id, content), id => content or (; id, group, content), got $(repr(c))"))

_deck_param(::Nothing, what) = (;)
function _deck_param(name::AbstractString, what)
    isempty(name) && throw(ArgumentError("card_deck: `$(what)_param` is empty; pass `nothing` to keep the $what out of the address"))
    (; Symbol(:data_htmxo_deck_, what, :_param) => String(name))
end

# The radios of a deck's controls share names of their own, so two decks never
# uncheck each other's choices.
_deck_choice_name(id, what) = string("htmxo-deck-", what, "-", id)

# The group filter: "All" and one choice per group, as pills while they are
# few and as a searchable list past `_RADIO_MAX` (the rule of generated forms
# and of `pdf_panel`'s chooser).
function _deck_group_filter(id, groups, t::CardDeckTexts)
    name = _deck_choice_name(id, "group")
    options = [(; value="", label=t.all); [(; value=g, label=g) for g in groups]]
    control = length(options) <= _RADIO_MAX ?
        radio_group(name, [o.value => o.label for o in options]; label=t.groups, value="") :
        _choice_list(name, t.groups, options, "";
                     texts=error_texts(:en; choice_search=t.group_search, choice_no_match=t.group_no_match))
    h.div(; class="htmxo-deck-groups")(control)
end

"""
    card_deck(cards; id, view=:grid, search=true, group_filter=true,
              view_param="view", card_param="card", texts=nothing, class="", assets=true)

A deck of cards that the reader sees either as a grid or as a carousel (one
card at a time, with previous and next), and switches between the two. A
search box filters the cards by their words, a group filter by their group,
and the carousel pages over the cards they leave. The view and the current
card are kept in the page address, so a link opens the deck at a card.

- `cards`: each card is `(id, group, content)`, `(id, content)`,
  `id => content` or `(; id, group, content)`. The deck puts each card's
  `content` in an `<article>` whose element `id` is the card's id, so the ids
  must be unique on the page. A card's `group` (a text; `nothing` for none)
  puts it under that group's heading; the groups appear in the order their
  first cards come, each card under its group.
- `id`: the deck's element id.
- `view`: the view it opens in, `:grid` or `:carousel`.
- `search`: whether it has the search box.
- `group_filter`: whether it has the group filter, shown when the cards have
  two groups or more.
- `view_param`, `card_param`: the address's parameters for the view
  (`?view=carousel`) and the current card (`?card=<id>`). `nothing` keeps
  that one out of the address. Two decks on one page need different names.
- `texts`: a [`card_deck_texts`](@ref); by default those of the page's
  language.
- `assets=false` leaves out the deck's style and script, for a page that
  carries [`card_deck_assets`](@ref) itself.

**How it behaves:**

- The grid lays the cards out in columns as wide as `--htmxo-deck-card-width`
  (default `18rem`) allows, each group under its heading. The carousel shows
  the current card alone, at most `--htmxo-deck-carousel-width` (default
  `46rem`) wide, with the previous and next buttons and its position
  ("3 of 49") above it, so the buttons stay where they are from card to card.
- The search matches every word typed, in any order, ignoring case and
  accents, against a card's text and its group. While the search or the group
  filter leaves cards out, the count beside the search says how many are left
  ("Matches: 7 of 49"), and a note says so when none is left. A group whose
  cards are all left out drops its heading.
- The current card is the one the carousel shows. In the grid a click on a
  card makes it the current card, so switching to the carousel shows the card
  just read; switching to the grid brings the current card into view. In the
  carousel, when the search or the group filter leaves the current card out,
  the next card left takes its place; while none is left the current card
  keeps its place, so clearing the search returns to it.
- In the carousel the left and right arrow keys go to the previous and next
  card while the focus is in the deck (outside its search box and choices) or
  nowhere on a page with one carousel; Home and End, in the deck, go to the
  first and last.
- The bar holding the controls stays at the top of the window while the deck
  scrolls by (below `--htmxo-sticky-top`).
- A choice of view or card replaces the page's history entry (no entry per
  card) and keeps htmx's history state, as [`tabset`](@ref) does with its tab.
  A page opened at `?card=<id>`, or at `#<id>` without that parameter, opens
  at that card; an unknown view or card keeps the default and logs a console
  warning. Inside `.htmxo-embed` the deck neither reads nor writes the address.

Script hooks: `window.htmxoDeck.show(deck, id)` makes card `id` the current
card, `window.htmxoDeck.view(deck, view)` switches the view (`deck` an element
or its id). The deck dispatches `htmxo:deck-change` (detail `{view, card}`,
the card's id) when the reader changes either.

In Markdown (`?plain`) the controls are left out: the group headings and the
cards remain, every card in the order of the grid.

```julia
@get karten() = card_deck([(c.id, c.gruppe, karte(c)) for c in KARTEN]; id="karten")
```
"""
function card_deck(cards; id::AbstractString, view::Symbol=:grid, search::Bool=true, group_filter::Bool=true,
                   view_param::Union{Nothing,AbstractString}="view", card_param::Union{Nothing,AbstractString}="card",
                   texts=nothing, class::AbstractString="", assets::Bool=true)
    isempty(id) && throw(ArgumentError("card_deck: `id` must not be empty"))
    view in _DECK_VIEWS || throw(ArgumentError(
        "card_deck: `view` is :grid or :carousel, got $(repr(view))"))
    t = _deck_texts(texts)
    deck = [_deck_card(c) for c in cards]
    for (i, (cid, _, _)) in enumerate(deck)
        isempty(cid) && throw(ArgumentError("card_deck: card $i has an empty id"))
        cid == id && throw(ArgumentError("card_deck: card $i has the deck's own id \"$id\""))
        j = findfirst(c -> first(c) == cid, deck)
        j == i || throw(ArgumentError("card_deck: cards $j and $i both have the id \"$cid\""))
    end
    order = Union{Nothing,String}[]
    members = Dict{Union{Nothing,String},Vector{Int}}()
    for (i, (_, group, _)) in enumerate(deck)
        haskey(members, group) || (push!(order, group); members[group] = Int[])
        push!(members[group], i)
    end
    named = filter(!isnothing, order)
    level = _semantic_heading_level()
    first_card = isempty(deck) ? 0 : first(members[first(order)])
    card_node(i) = let (cid, group, content) = deck[i]
        h.article(content; id=cid, class="htmxo-deck-card",
                  (isnothing(group) ? (;) : (; data_htmxo_deck_group=group))...,
                  (i == first_card ? (; data_htmxo_deck_current="") : (;))...)
    end
    sections = map(order) do group
        h.section(; class="htmxo-deck-group", (isnothing(group) ? (;) : (; data_htmxo_deck_group=group))...)(
            (isnothing(group) ? () :
                (h(_semantic_heading_tag(level), group; class="htmxo-deck-group-heading"),))...,
            (card_node(i) for i in members[group])...)
    end
    bar = h.div(; class="htmxo-deck-bar")(
        h.div(; class="htmxo-deck-views")(
            radio_group(_deck_choice_name(id, "view"), [String(v) => getfield(t, v) for v in _DECK_VIEWS];
                        label=t.view, value=String(view))),
        (search ? (h.input(; type="search", class="htmxo-deck-search", placeholder=t.search, aria_label=t.search,
                           autocomplete="off", aria_controls=id * "-cards"),) : ())...,
        h.span(; class="htmxo-deck-status", data_htmxo_deck_status="", role="status")(),
        (group_filter && length(named) >= 2 ? (_deck_group_filter(id, named, t),) : ())...,
        h.div(; class="htmxo-deck-nav")(
            h.button(; type="button", data_htmxo_deck_step="-1", aria_label=t.previous, title=t.previous,
                     disabled=true)("‹"),
            h.span(; class="htmxo-deck-position", data_htmxo_deck_position="", aria_live="polite")(
                isempty(deck) ? "" : _fill_text(t.position; position=1, count=length(deck))),
            h.span(; class="htmxo-deck-current-group", data_htmxo_deck_current_group="")(
                first_card == 0 ? "" : something(deck[first_card][2], "")),
            h.button(; type="button", data_htmxo_deck_step="1", aria_label=t.next, title=t.next,
                     (length(deck) <= 1 ? (; disabled=true) : (;))...)("›")))
    h.div(; id, class=isempty(class) ? "htmxo-deck" : "htmxo-deck " * class, role="region", aria_label=t.label,
          data_htmxo_deck="", data_htmxo_deck_view=String(view),
          _deck_param(view_param, :view)..., _deck_param(card_param, :card)...,
          data_text_position=t.position, data_text_matches=t.matches)(
        (assets ? html_only.(card_deck_assets()) : ())...,
        html_only(bar),
        html_only(h.p(; class="htmxo-deck-empty", data_htmxo_deck_empty_note="", hidden=true)(t.no_match)),
        h.div(; id=id * "-cards", class="htmxo-deck-cards")(sections...),
        html_only(h.script(Raw(_DECK_INIT))))
end

# Runs while the deck is inserted — during parsing, or on an htmx swap — so the
# address's view and card show from the start.
const _DECK_INIT = "(window.htmxoDeck || (d => console.warn('card_deck: card_deck_script() is not on this page, " *
    "so the deck has no controls')))(document.currentScript.parentElement)"

"""
    card_deck_styles()

CSS for [`card_deck`](@ref). Layout sits inside `@layer htmxo`; the cards,
the bar's controls and the rules that hide cards are unlayered, because Pico
styles `article`, inputs and buttons unlayered.
"""
card_deck_styles() = h.style(Raw(raw"""
@layer htmxo {
.htmxo-deck { scroll-margin-top: calc(var(--htmxo-sticky-top, 0px) + .5rem); }
.htmxo-deck-bar {
    position: sticky; top: var(--htmxo-sticky-top, 0px); z-index: 2;
    display: flex; flex-wrap: wrap; align-items: center; gap: .35rem .75rem;
    margin-bottom: .75rem; padding: .5rem 0; background: var(--pico-background-color, Canvas);
}
.htmxo-deck-status { color: var(--htmxo-muted, GrayText); font-size: .875em; white-space: nowrap; }
.htmxo-deck-status:empty { display: none; }
.htmxo-deck-groups { flex: 1 1 100%; min-width: 0; }
.htmxo-deck-nav { flex: 1 1 100%; align-items: center; justify-content: center; gap: .6rem; }
.htmxo-deck-position { font-variant-numeric: tabular-nums; white-space: nowrap; }
.htmxo-deck-current-group { color: var(--htmxo-muted, GrayText); font-size: .875em; }
.htmxo-deck-current-group:empty { display: none; }
.htmxo-deck-empty { color: var(--htmxo-muted, GrayText); }
.htmxo-deck-group {
    display: grid; gap: var(--htmxo-deck-gap, 1rem); align-items: start; margin-bottom: 1.25rem;
    grid-template-columns: repeat(auto-fill, minmax(min(var(--htmxo-deck-card-width, 18rem), 100%), 1fr));
}
.htmxo-deck-group-heading { grid-column: 1 / -1; margin: .25rem 0 0; }
}
.htmxo-deck-bar .htmxo-deck-search { flex: 1 1 14rem; width: auto; min-width: 0; margin: 0; }
.htmxo-deck-bar fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
.htmxo-deck-bar fieldset > legend {
    position: absolute; width: 1px; height: 1px; margin: 0; padding: 0; border: 0;
    overflow: hidden; clip-path: inset(50%); white-space: nowrap;
}
.htmxo-deck-bar fieldset:not([role]) > label:has(> input[type="radio"]) {
    max-width: 100%; margin: .1rem .3rem .1rem 0; padding: .1em .7em; line-height: 1.4;
}
.htmxo-deck-bar .htmxo-choice-field { padding: .15rem .55rem; line-height: 1.4; }
.htmxo-deck-nav button { width: auto; margin: 0; padding: .15rem .7rem; font-size: inherit; line-height: 1.4; }
.htmxo-deck-card {
    box-sizing: border-box; min-width: 0; margin: 0; padding: var(--pico-block-spacing-vertical, 1rem) var(--pico-block-spacing-horizontal, 1rem);
    border: 1px solid var(--pico-muted-border-color, color-mix(in srgb, currentColor 20%, transparent));
    border-radius: var(--pico-border-radius, .5rem); background: var(--pico-card-background-color, Canvas);
    box-shadow: none; overflow-wrap: anywhere; scroll-margin-top: calc(var(--htmxo-sticky-top, 0px) + var(--htmxo-deck-bar-h, 0px) + .5rem);
}
.htmxo-deck-card > :last-child { margin-bottom: 0; }
/* What the controls left out, and the views. */
.htmxo-deck-card[data-htmxo-deck-out], .htmxo-deck-group[data-htmxo-deck-empty], .htmxo-deck-empty[hidden] { display: none; }
.htmxo-deck:not([data-htmxo-deck-view="carousel"]) .htmxo-deck-nav { display: none; }
.htmxo-deck[data-htmxo-deck-view="carousel"] .htmxo-deck-nav { display: flex; }
.htmxo-deck[data-htmxo-deck-view="carousel"] > .htmxo-deck-cards > .htmxo-deck-group { display: block; margin: 0; }
.htmxo-deck[data-htmxo-deck-view="carousel"] > .htmxo-deck-cards > .htmxo-deck-group > .htmxo-deck-group-heading,
.htmxo-deck[data-htmxo-deck-view="carousel"] > .htmxo-deck-cards > .htmxo-deck-group > .htmxo-deck-card:not([data-htmxo-deck-current]) { display: none; }
.htmxo-deck[data-htmxo-deck-view="carousel"] > .htmxo-deck-cards > .htmxo-deck-group > .htmxo-deck-card {
    max-width: var(--htmxo-deck-carousel-width, 46rem); margin-inline: auto;
}
"""))

"""
    card_deck_script()

Client runtime for [`card_deck`](@ref): delegated listeners that serve every
deck however it reaches the page (page load, htmx swap), and
`window.htmxoDeck`. Safe to include more than once.
"""
card_deck_script() = h.script(Raw(raw"""
(function () {
  if (window.htmxoDeck) return;
  var VIEWS = ['grid', 'carousel'];
  // Words compared as the search compares them: no case, no accents.
  function fold(s) {
    return String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/ß/g, 'ss').toLowerCase();
  }
  function element(deck) { return typeof deck === 'string' ? document.getElementById(deck) : deck; }
  function cards(deck) {
    return Array.prototype.slice.call(deck.querySelectorAll(':scope > .htmxo-deck-cards > .htmxo-deck-group > .htmxo-deck-card'));
  }
  function left(card) { return !card.hasAttribute('data-htmxo-deck-out'); }
  function current(deck) {
    return deck.querySelector(':scope > .htmxo-deck-cards > .htmxo-deck-group > .htmxo-deck-card[data-htmxo-deck-current]');
  }
  function part(deck, selector) { return deck.querySelector(':scope > .htmxo-deck-bar ' + selector); }
  function bar(deck) { return deck.querySelector(':scope > .htmxo-deck-bar'); }
  function text(deck, name) { return deck.dataset['text' + name] || ''; }
  function fill(words, values) {
    return words.replace(/\{(\w+)\}/g, function (m, k) { return k in values ? String(values[k]) : m; });
  }
  function visible(el) { return el.getClientRects().length > 0; }
  function view(deck) { return deck.dataset.htmxoDeckView === 'carousel' ? 'carousel' : 'grid'; }

  // --- The address: `?<view param>=` and `?<card param>=`. A choice replaces
  // the history entry and keeps its state: htmx 2 restores an entry on
  // Back/Forward only when that state says `htmx`, and files its snapshot of
  // the page under the path it keeps in sessionStorage, which follows too.
  function recording(deck) { return !deck.closest('.htmxo-embed'); }
  function param(deck, what) { return deck.dataset['htmxoDeck' + what + 'Param'] || null; }
  function write(deck, what, value) {
    var key = param(deck, what);
    if (!key || !recording(deck) || value == null) return;
    var url = new URL(location.href);
    url.searchParams.set(key, value);
    if (url.href === location.href) return;
    history.replaceState(history.state, '', url);
    if (window.htmx) try { sessionStorage.setItem('htmx-current-path-for-history', url.pathname + url.search); } catch (_) {}
  }
  function announce(deck) {
    var card = current(deck);
    deck.dispatchEvent(new CustomEvent('htmxo:deck-change', {bubbles: true,
      detail: {view: view(deck), card: card ? card.id : null}}));
  }

  function mark(deck, card) {
    cards(deck).forEach(function (c) { if (c !== card) c.removeAttribute('data-htmxo-deck-current'); });
    if (card) card.setAttribute('data-htmxo-deck-current', '');
  }
  // The carousel's card is always one the controls leave: the next one left
  // after the current card, else the one before it. With none left the
  // current card keeps its place (hidden), so clearing the search returns to it.
  function settle(deck) {
    var all = cards(deck), card = current(deck);
    if (card && left(card)) return card;
    var i = card ? all.indexOf(card) : -1;
    var pick = all.slice(i + 1).concat(all.slice(0, Math.max(i, 0)).reverse()).filter(left)[0] || null;
    if (pick) mark(deck, pick);
    return pick;
  }
  function render(deck) {
    var shown = cards(deck).filter(left), card = current(deck), i = card ? shown.indexOf(card) : -1;
    deck.querySelectorAll(':scope > .htmxo-deck-bar .htmxo-deck-views input[type="radio"]').forEach(function (r) {
      r.checked = r.value === view(deck);
    });
    var position = part(deck, '[data-htmxo-deck-position]'), group = part(deck, '[data-htmxo-deck-current-group]');
    if (position) position.textContent = i < 0 ? '' : fill(text(deck, 'Position'), {position: i + 1, count: shown.length});
    if (group) group.textContent = card && card.dataset.htmxoDeckGroup || '';
    var previous = part(deck, '[data-htmxo-deck-step="-1"]'), next = part(deck, '[data-htmxo-deck-step="1"]');
    if (previous) previous.disabled = i <= 0;
    if (next) next.disabled = i < 0 || i >= shown.length - 1;
  }
  function query(deck) { var input = part(deck, '.htmxo-deck-search'); return input ? input.value : ''; }
  function group(deck) {
    var radio = part(deck, '.htmxo-deck-groups input[type="radio"]:checked');
    return radio ? radio.value : '';
  }
  // Marks the cards the search and the group filter leave out, and the groups
  // with none left; the count and the note follow.
  function filter(deck) {
    var words = fold(query(deck)).split(/\s+/).filter(Boolean), g = group(deck), all = cards(deck), n = 0;
    all.forEach(function (card) {
      var mine = card.dataset.htmxoDeckGroup || '', haystack = words.length ? fold(card.textContent + ' ' + mine) : '';
      var out = (g !== '' && mine !== g) || !words.every(function (w) { return haystack.indexOf(w) >= 0; });
      card.toggleAttribute('data-htmxo-deck-out', out);
      if (!out) n++;
    });
    deck.querySelectorAll(':scope > .htmxo-deck-cards > .htmxo-deck-group').forEach(function (section) {
      section.toggleAttribute('data-htmxo-deck-empty', !section.querySelector(':scope > .htmxo-deck-card:not([data-htmxo-deck-out])'));
    });
    var status = part(deck, '[data-htmxo-deck-status]');
    if (status) status.textContent = words.length || g !== '' ? fill(text(deck, 'Matches'), {shown: n, count: all.length}) : '';
    var note = deck.querySelector(':scope > [data-htmxo-deck-empty-note]');
    if (note) note.hidden = n > 0 || all.length === 0;
    if (view(deck) === 'carousel') settle(deck);
    render(deck);
  }
  // Refilters after the reader changed the search or the group. In the
  // carousel a current card they left out gives way, and the address follows;
  // the grid keeps its current card (the one clicked last) as it is.
  function refilter(deck) {
    var before = current(deck);
    filter(deck);
    var after = current(deck);
    if (after === before) return;
    write(deck, 'Card', after.id);
    announce(deck);
  }
  // Brings a card's top into view when the bar covers it or it is below the window.
  function reveal(deck, card) {
    var top = card.getBoundingClientRect().top, b = bar(deck);
    if (top < (b ? b.getBoundingClientRect().bottom : 0) || top > window.innerHeight) card.scrollIntoView({block: 'start'});
  }
  function go(deck, card) {
    if (!card || card === current(deck)) return;
    mark(deck, card);
    render(deck);
    write(deck, 'Card', card.id);
    if (view(deck) === 'carousel') reveal(deck, card);
    announce(deck);
  }
  function step(deck, by) {
    var shown = cards(deck).filter(left), i = shown.indexOf(current(deck));
    var j = by === -Infinity ? 0 : by === Infinity ? shown.length - 1 : i + by;
    if (j >= 0 && j < shown.length) go(deck, shown[j]);
  }
  function switchTo(deck, v) {
    if (VIEWS.indexOf(v) < 0 || v === view(deck)) { render(deck); return; }
    deck.dataset.htmxoDeckView = v;
    var card = v === 'carousel' ? settle(deck) : current(deck);
    render(deck);
    write(deck, 'View', v);
    if (v === 'carousel') {
      if (card) write(deck, 'Card', card.id);
      if (deck.getBoundingClientRect().top < 0) deck.scrollIntoView({block: 'start'});
    } else if (card && left(card)) card.scrollIntoView({block: 'nearest'});
    announce(deck);
  }

  // Sets a deck up from its attributes and the address; again on every call.
  function init(deck) {
    deck = element(deck);
    if (!deck || !deck.hasAttribute('data-htmxo-deck')) return;
    if (recording(deck)) {
      var params = new URLSearchParams(location.search), vk = param(deck, 'View'), ck = param(deck, 'Card');
      var v = vk ? params.get(vk) : null;
      if (v) {
        if (VIEWS.indexOf(v) >= 0) deck.dataset.htmxoDeckView = v;
        else console.warn('card_deck: no view is named "' + v + '" (?' + vk + '=); showing the ' + view(deck));
      }
      var id = ck ? params.get(ck) : null, hash = false;
      if (!id && location.hash.length > 1) { try { id = decodeURIComponent(location.hash.slice(1)); } catch (_) { id = null; } hash = true; }
      if (id) {
        var named = cards(deck).filter(function (c) { return c.id === id; })[0];
        if (named) mark(deck, named);
        else if (!hash) console.warn('card_deck: no card is named "' + id + '" (?' + ck + '=); showing the first card');
      }
    }
    if (!current(deck)) mark(deck, cards(deck)[0] || null);
    filter(deck);
    var b = bar(deck);
    if (b && window.ResizeObserver && !deck.htmxoDeckObserved) {
      deck.htmxoDeckObserved = true;
      new ResizeObserver(function () { deck.style.setProperty('--htmxo-deck-bar-h', b.offsetHeight + 'px'); }).observe(b);
    }
  }
  window.htmxoDeck = init;
  init.show = function (deck, id) {
    deck = element(deck);
    var card = deck && cards(deck).filter(function (c) { return c.id === String(id); })[0];
    if (!card) return false;
    if (!left(card)) {
      var input = part(deck, '.htmxo-deck-search'), all = part(deck, '.htmxo-deck-groups input[type="radio"][value=""]');
      if (input) input.value = '';
      if (all) all.checked = true;
      filter(deck);
    }
    go(deck, card);
    return true;
  };
  init.view = function (deck, v) { deck = element(deck); if (deck) switchTo(deck, v); };

  function deckOf(el) { return el instanceof Element ? el.closest('[data-htmxo-deck]') : null; }
  document.addEventListener('change', function (event) {
    var t = event.target;
    if (!(t instanceof HTMLInputElement) || t.type !== 'radio') return;
    var deck = deckOf(t);
    if (!deck || !bar(deck) || !bar(deck).contains(t)) return;
    if (t.closest('.htmxo-deck-views')) switchTo(deck, t.value);
    else if (t.closest('.htmxo-deck-groups')) refilter(deck);
  });
  document.addEventListener('input', function (event) {
    var t = event.target;
    if (!(t instanceof Element) || !t.matches('.htmxo-deck-search')) return;
    var deck = deckOf(t);
    if (deck) refilter(deck);
  });
  document.addEventListener('click', function (event) {
    var t = event.target instanceof Element ? event.target : null;
    if (!t) return;
    var button = t.closest('[data-htmxo-deck-step]'), deck = deckOf(button);
    if (button && deck) { step(deck, Number(button.dataset.htmxoDeckStep)); return; }
    var card = t.closest('.htmxo-deck-card');
    deck = deckOf(card);
    if (card && deck && view(deck) === 'grid' && cards(deck).indexOf(card) >= 0) go(deck, card);
  });
  var KEYS = {ArrowLeft: -1, ArrowRight: 1, Home: -Infinity, End: Infinity};
  document.addEventListener('keydown', function (event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || !(event.key in KEYS)) return;
    var t = event.target instanceof Element ? event.target : null;
    if (t && t.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"]), .htmxo-choice-panel')) return;
    var deck = deckOf(t);
    if (!deck) {
      // Nothing focused: the arrows serve the page's one carousel.
      if (t && t !== document.body && t !== document.documentElement) return;
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      var carousels = Array.prototype.slice.call(document.querySelectorAll('[data-htmxo-deck][data-htmxo-deck-view="carousel"]')).filter(visible);
      if (carousels.length !== 1) return;
      deck = carousels[0];
    }
    if (view(deck) !== 'carousel') return;
    event.preventDefault();
    step(deck, KEYS[event.key]);
  });
})();
"""))

"""
    card_deck_assets()

The style and script of [`card_deck`](@ref) ([`card_deck_styles`](@ref),
[`card_deck_script`](@ref)), for a page that carries them once itself and
passes `assets=false` to its decks. Both are inline elements, so a deck needs
no route of its own. In the `extra_head` of an [`htmx`](@ref) shell with
`runtime=:linked`, they become two browser-cached files on the vendor mount
([`vendorfiles`](@ref)), `<mount>/htmxo/card_deck_styles.css?v=…` and
`…/card_deck_script.js?v=…`.
"""
card_deck_assets() = (card_deck_styles(), card_deck_script())
