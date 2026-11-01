@testmodule DeckFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    # Six cards in three groups, in the order the KB's flashcards come: each a
    # title, a body and a sources line. The words the browser item searches
    # for are spread over them (accents included).
    const CARDS = [
        ("a1", "A · Die Stelle", h.div(h.h3("Aufgaben"), h.p("Bürgerservice und Meldewesen."), h.p("Quelle: Ausschreibung S. 2"))),
        ("a2", "A · Die Stelle", h.div(h.h3("Träger"), h.p("Stadt Neumünster, Fachdienst Bürgerdienste."))),
        ("b1", "B · Der Träger", h.div(h.h3("Leitbild"), h.p("Service für alle Bürgerinnen und Bürger."))),
        ("b2", "B · Der Träger", h.div(h.h3("Struktur"), h.p("Fünf Fachbereiche, ein Rathaus."))),
        ("b3", "B · Der Träger", h.div(h.h3("Haushalt"), h.p("Konsolidierung bis 2028."))),
        ("c1", "C · Gespräch", h.div(h.h3("Fragen"), h.p("Warum diese Stelle? Was reizt Sie am Service?")))]
    html(x) = repr("text/html", x)
    # The deck in an app, for its static export; one card links a route.
    @htmx struct DeckApp
        __page__(content) = htmx(h.main(content); hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        @get deck_karten() = card_deck(CARDS; id="karten")
        @get deck_links() = card_deck([("a", "G", h.p(h.a("Quelle"; href="/deck_quelle"))), ("b", "H", h.p("b"))]; id="k")
        @get deck_quelle() = h.p("Quelle")
    end
    export CARDS, html, DeckApp
end

@testitem "card_deck: the cards in their groups, the first one current, the controls HTML only" setup=[DeckFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    s = html(card_deck(CARDS; id="karten", assets=false))
    @test occursin(r"^<div id=\"karten\" class=\"htmxo-deck\" role=\"region\" aria-label=\"Cards\" data-htmxo-deck=\"\" data-htmxo-deck-view=\"grid\" data-htmxo-deck-view-param=\"view\" data-htmxo-deck-card-param=\"card\" data-text-position=\"\{position\} of \{count\}\" data-text-matches=\"Matches: \{shown\} of \{count\}\">", s)
    # each group a section under its heading, each card an article with its id, the first current
    @test occursin("<section class=\"htmxo-deck-group\" data-htmxo-deck-group=\"A · Die Stelle\"><h2 class=\"htmxo-deck-group-heading\">A · Die Stelle</h2><article id=\"a1\" class=\"htmxo-deck-card\" data-htmxo-deck-group=\"A · Die Stelle\" data-htmxo-deck-current=\"\"><div><h3>Aufgaben</h3>", s)
    @test occursin("<article id=\"b3\" class=\"htmxo-deck-card\" data-htmxo-deck-group=\"B · Der Träger\"><div><h3>Haushalt</h3>", s)
    @test count("<section class=\"htmxo-deck-group\"", s) == 3 && count("<article ", s) == 6 && count(r"<article [^>]*data-htmxo-deck-current=", s) == 1
    @test occursin("<div id=\"karten-cards\" class=\"htmxo-deck-cards\">", s)
    # the bar: the view pills, the search, the count, the group pills, the carousel's buttons
    @test occursin("<fieldset><legend>View</legend><label><input type=\"radio\" name=\"htmxo-deck-view-karten\" value=\"grid\" checked=\"true\">Grid</label><label><input type=\"radio\" name=\"htmxo-deck-view-karten\" value=\"carousel\">Carousel</label></fieldset>", s)
    @test occursin("<input type=\"search\" class=\"htmxo-deck-search\" placeholder=\"Search the cards…\" aria-label=\"Search the cards…\" autocomplete=\"off\" aria-controls=\"karten-cards\">", s)
    @test occursin("<span class=\"htmxo-deck-status\" data-htmxo-deck-status=\"\" role=\"status\"></span>", s)
    @test occursin("<div class=\"htmxo-deck-groups\"><fieldset><legend>Group</legend><label><input type=\"radio\" name=\"htmxo-deck-group-karten\" value=\"\" checked=\"true\">All</label><label><input type=\"radio\" name=\"htmxo-deck-group-karten\" value=\"A · Die Stelle\">A · Die Stelle</label>", s)
    @test occursin(r"<button type=\"button\" data-htmxo-deck-step=\"-1\" aria-label=\"Previous card\" title=\"Previous card\" disabled[^>]*>‹</button><span class=\"htmxo-deck-position\" data-htmxo-deck-position=\"\" aria-live=\"polite\">1 of 6</span><span class=\"htmxo-deck-current-group\" data-htmxo-deck-current-group=\"\">A · Die Stelle</span><button type=\"button\" data-htmxo-deck-step=\"1\" aria-label=\"Next card\" title=\"Next card\">›</button>", s)
    @test occursin("<p class=\"htmxo-deck-empty\" data-htmxo-deck-empty-note=\"\" hidden", s) && occursin(">No card matches the search.</p>", s)
    @test endswith(s, "<script>(window.htmxoDeck || (d => console.warn('card_deck: card_deck_script() is not on this page, so the deck has no controls')))(document.currentScript.parentElement)</script></div>")
    @test !occursin("window.htmxoDeck = init", s)                                                # assets=false
    @test !occursin("<select", s)
    # carried by default: the style and the script, inside the deck
    full = html(card_deck(CARDS; id="karten"))
    @test occursin("<div id=\"karten\"", full) && occursin("window.htmxoDeck = init", full) && occursin(".htmxo-deck-bar {", full)
    @test findfirst("<style>", full)[1] > findfirst("data-text-matches", full)[1]
    # Markdown: the group headings and the cards, nothing of the controls
    md = to_markdown_string(card_deck(CARDS; id="karten"))
    @test occursin("\n## A · Die Stelle\n", md) && occursin("\n## B · Der Träger\n", md) && occursin("\n## C · Gespräch\n", md)
    @test occursin("### Aufgaben", md) && occursin("Konsolidierung bis 2028.", md)
    for chrome in ("Grid", "Carousel", "Search", "Matches", "No card matches", "‹", "1 of 6", "htmxoDeck", "{")
        @test !occursin(chrome, md)
    end
    @test findfirst("Aufgaben", md)[1] < findfirst("Leitbild", md)[1] < findfirst("Fragen", md)[1]
end

@testitem "card_deck: views, controls, groups, address parameters and refusals" setup=[DeckFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    deck(cards=CARDS; kw...) = html(card_deck(cards; id="d", assets=false, kw...))
    # opening in the carousel
    c = deck(; view=:carousel)
    @test occursin("data-htmxo-deck-view=\"carousel\"", c) && occursin("value=\"carousel\" checked=\"true\">Carousel</label>", c)
    # without the search, without the group filter
    @test !occursin("htmxo-deck-search", deck(; search=false))
    @test !occursin("htmxo-deck-groups", deck(; group_filter=false))
    # one group, or none: no group filter; cards without a group have no heading
    @test !occursin("htmxo-deck-groups", deck([(id, "Eine", node) for (id, _, node) in CARDS]))
    plain = deck(["x" => h.p("X"), ("y", h.p("Y")), (; id="z", content=h.p("Z")), (; id="w", group=nothing, content=h.p("W"))])
    @test occursin("<section class=\"htmxo-deck-group\"><article id=\"x\" class=\"htmxo-deck-card\" data-htmxo-deck-current=\"\"><p>X</p></article><article id=\"y\" class=\"htmxo-deck-card\"><p>Y</p></article>", plain)
    @test !occursin("<h2", plain) && !occursin("htmxo-deck-groups", plain) && count("<article ", plain) == 4
    @test occursin("data-htmxo-deck-group=\"G\"", deck([(; id="n", group="G", content="n"), (; id="m", group="", content="m")]))
    # a group comes where its first card does; its cards follow it
    mixed = deck([("1", "B", "one"), ("2", "A", "two"), ("3", "B", "three")])
    @test occursin("<h2 class=\"htmxo-deck-group-heading\">B</h2><article id=\"1\"", mixed) &&
          occursin("<article id=\"3\" class=\"htmxo-deck-card\" data-htmxo-deck-group=\"B\">three</article></section><section", mixed)
    # more than seven groups: "All" and the groups in a searchable list
    many = deck([("k$i", "Group $i", "card $i") for i in 1:8])
    @test occursin("<fieldset class=\"htmxo-choice-list\" data-htmxo-choice-list=\"\"><legend>Group</legend>", many)
    @test occursin("<span class=\"htmxo-choice-current\">All</span>", many) && occursin("placeholder=\"Search the groups…\"", many) &&
          occursin(">No matching group</p>", many) && count("name=\"htmxo-deck-group-d\"", many) == 9
    @test occursin("<label><input type=\"radio\" name=\"htmxo-deck-group-d\"", deck([("k$i", "Group $i", "card $i") for i in 1:7]))
    # one card: no next; none: no position
    @test occursin(r"data-htmxo-deck-step=\"1\" aria-label=\"Next card\" title=\"Next card\" disabled", deck(["only" => "x"]))
    @test occursin("data-htmxo-deck-position=\"\" aria-live=\"polite\"></span>", deck([]))
    # a heading inside a section: one level deeper
    @test occursin("<h3 class=\"htmxo-deck-group-heading\">A · Die Stelle</h3>",
                   HTMXObjects._semantic_heading(_ -> deck(), 2))
    # address parameters of its own, or none
    own = deck(; view_param="ansicht", card_param="karte")
    @test occursin("data-htmxo-deck-view-param=\"ansicht\" data-htmxo-deck-card-param=\"karte\"", own)
    none = deck(; view_param=nothing, card_param=nothing)
    @test !occursin("-param=", none)
    @test occursin("data-htmxo-deck-card-param=\"card\"", deck(; view_param=nothing)) && !occursin("view-param", deck(; view_param=nothing))
    # the page's language, or texts of one's own
    de = HTMXObjects._with_page_lang(() -> deck(), "de-DE")
    @test occursin("aria-label=\"Karten\"", de) && occursin(">Übersicht</label>", de) && occursin(">Einzeln</label>", de) &&
          occursin("placeholder=\"Karten durchsuchen…\"", de) && occursin("data-text-matches=\"Treffer: {shown} von {count}\"", de) &&
          occursin(">1 von 6</span>", de) && occursin(">Alle</label>", de) && occursin(">Keine Karte passt zur Suche.</p>", de)
    @test occursin("aria-label=\"Cards\"", HTMXObjects._with_page_lang(() -> deck(), "fr"))
    mine = deck(; texts=card_deck_texts(:de; carousel="Karteikarten", position="Karte {position}/{count}"))
    @test occursin(">Karteikarten</label>", mine) && occursin(">Karte 1/6</span>", mine) && occursin(">Übersicht</label>", mine)
    @test card_deck_texts(:de).previous == "Vorige Karte" && card_deck_texts().next == "Next card"
    @test_throws ArgumentError card_deck_texts(:fr)
    @test_throws ArgumentError card_deck_texts(; position="{position} of {total}")
    @test_throws ArgumentError card_deck_texts(; matches="{shown} of {position}")
    @test_throws ArgumentError card_deck_texts(; labl="x")
    # refused
    @test_throws ArgumentError card_deck(CARDS; id="")
    @test_throws ArgumentError card_deck(CARDS; id="d", view=:list)
    @test_throws ArgumentError card_deck(["a" => "x", "a" => "y"]; id="d")                       # an id twice
    @test_throws ArgumentError card_deck(["" => "x"]; id="d")
    @test_throws ArgumentError card_deck(["d" => "x"]; id="d")                                   # the deck's own id
    @test_throws ArgumentError card_deck([42]; id="d")
    @test_throws ArgumentError card_deck([(; id="a", body="x")]; id="d")
    @test_throws ArgumentError card_deck(CARDS; id="d", texts=pdf_panel_texts())
    @test_throws ArgumentError card_deck(CARDS; id="d", view_param="")
    @test_throws ArgumentError card_deck(CARDS; id="d", card_param="")
end

@testitem "card_deck in a static export keeps its controls and its cards' links" setup=[DeckFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    route!(DeckApp())
    live = String(dispatch(:GET, "/deck_links").body)
    exported = String(dispatch(:GET, "/deck_links"; static=StaticExport(; record_base="/odl")).body)
    for s in (live, exported)
        @test occursin("window.htmxoDeck = init", s) && occursin("(document.currentScript.parentElement)</script></div>", s)
        @test occursin("data-htmxo-deck-view-param=\"view\"", s) && occursin("name=\"htmxo-deck-view-k\"", s)
    end
    @test occursin("href=\"/odl/deck_quelle\"", exported) && occursin("href=\"/deck_quelle\"", live)
end

@testitem "card_deck browser: search, groups, the carousel and the address" setup=[DeckFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
            const checks = [];
            const check = (name, ok, seen) => checks.push([ok ? name : name + ' ' + JSON.stringify(seen), Boolean(ok)]);
            const deck = document.getElementById('karten');
            const bar = deck.querySelector('.htmxo-deck-bar');
            const all = () => [...deck.querySelectorAll('.htmxo-deck-card')];
            const shownIds = () => all().filter(c => c.getClientRects().length > 0).map(c => c.id).join(',');
            const headings = () => [...deck.querySelectorAll('.htmxo-deck-group-heading')].filter(e => e.getClientRects().length > 0).length;
            const status = () => deck.querySelector('[data-htmxo-deck-status]').textContent;
            const position = () => deck.querySelector('[data-htmxo-deck-position]').textContent;
            const group = () => deck.querySelector('[data-htmxo-deck-current-group]').textContent;
            const note = () => deck.querySelector('[data-htmxo-deck-empty-note]');
            const nav = () => deck.querySelector('.htmxo-deck-nav');
            const prev = () => deck.querySelector('[data-htmxo-deck-step="-1"]');
            const next = () => deck.querySelector('[data-htmxo-deck-step="1"]');
            const search = deck.querySelector('.htmxo-deck-search');
            const type = words => { search.value = words; search.dispatchEvent(new Event('input', {bubbles: true})); };
            const pill = (box, value) => deck.querySelector('.htmxo-deck-' + box + ' input[value="' + value + '"]').closest('label');
            const param = k => new URL(location.href).searchParams.get(k);
            const key = (target, k) => target.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true}));
            const changes = [];
            deck.addEventListener('htmxo:deck-change', e => changes.push(e.detail.view + ':' + e.detail.card));
            const seen = () => ({shown: shownIds(), status: status(), position: position(), group: group(),
                                 view: deck.dataset.htmxoDeckView, url: location.search, headings: headings()});
            try {
                // htmx's history state survives the deck's address writes
                history.replaceState({htmx: true}, '', location.href);
                // the grid: every card, three headings, no carousel buttons, no count
                check('grid', shownIds() === 'a1,a2,b1,b2,b3,c1' && headings() === 3 && nav().getClientRects().length === 0 &&
                      status() === '' && note().hidden, seen());
                const cols = new Set(all().map(c => Math.round(c.getBoundingClientRect().left)));
                check('grid-columns', cols.size >= 2, [...cols]);
                const pageBg = () => getComputedStyle(document.documentElement).backgroundColor;
                const bg = getComputedStyle(bar).backgroundColor;
                check('bar-light', bg === pageBg() && bg === 'rgb(255, 255, 255)', [bg, pageBg()]);
                // the search: every word, any order, no case, no accents, the group too; the count follows
                type('BURGER service');
                check('search-words', shownIds() === 'a1,b1' && status() === 'Matches: 2 of 6' && headings() === 2, seen());
                type('gesprach');
                check('search-group', shownIds() === 'c1' && headings() === 1, seen());
                type('nichts dergleichen');
                check('search-none', shownIds() === '' && status() === 'Matches: 0 of 6' && !note().hidden &&
                      note().getClientRects().length > 0 && headings() === 0, seen());
                type('');
                check('search-cleared', shownIds() === 'a1,a2,b1,b2,b3,c1' && status() === '' && note().hidden, seen());
                // the group filter, with the search
                pill('groups', 'B · Der Träger').click();
                check('group', shownIds() === 'b1,b2,b3' && status() === 'Matches: 3 of 6' && headings() === 1, seen());
                type('service');
                check('group-and-search', shownIds() === 'b1' && status() === 'Matches: 1 of 6', seen());
                type('');
                pill('groups', '').click();
                check('group-all', shownIds() === 'a1,a2,b1,b2,b3,c1' && status() === '', seen());
                // the grid's filters move no current card and write no address
                check('no-address-yet', location.search === '' && changes.length === 0, [location.search, changes]);
                // the carousel: the current card alone, its position and group, the address follows
                pill('views', 'carousel').click();
                check('carousel', shownIds() === 'a1' && position() === '1 of 6' && group() === 'A · Die Stelle' &&
                      prev().disabled && !next().disabled && param('view') === 'carousel' && param('card') === 'a1' &&
                      headings() === 0, seen());
                const card = document.getElementById('a1');
                check('one-card-wide', card.getBoundingClientRect().width > 500 && card.scrollHeight <= card.clientHeight + 1,
                      [card.getBoundingClientRect().width, card.scrollHeight, card.clientHeight]);
                const navTop = next().getBoundingClientRect().top, scrollY = window.scrollY;
                next().click();
                check('next', shownIds() === 'a2' && position() === '2 of 6' && !prev().disabled && param('card') === 'a2' &&
                      param('view') === 'carousel', seen());
                next().click();
                check('next-group', shownIds() === 'b1' && group() === 'B · Der Träger', seen());
                check('buttons-stay', Math.abs(next().getBoundingClientRect().top - navTop) < 1 && window.scrollY === scrollY,
                      [navTop, next().getBoundingClientRect().top, scrollY, window.scrollY]);
                // the keys: in the deck, and with nothing focused
                key(next(), 'ArrowRight');
                check('arrow-right', shownIds() === 'b2' && param('card') === 'b2', seen());
                key(next(), 'End');
                check('end', shownIds() === 'c1' && next().disabled && position() === '6 of 6', seen());
                key(prev(), 'Home');
                check('home', shownIds() === 'a1' && prev().disabled, seen());
                document.activeElement.blur();
                key(document.body, 'ArrowRight');
                check('arrow-body', shownIds() === 'a2', seen());
                key(search, 'ArrowLeft');
                check('arrow-in-search-types', shownIds() === 'a2', seen());
                // the carousel pages over the matches; a current card left out gives way
                type('service');
                check('carousel-matches', shownIds() === 'b1' && position() === '2 of 3' && status() === 'Matches: 3 of 6' &&
                      param('card') === 'b1', seen());
                next().click();
                check('carousel-next-match', shownIds() === 'c1' && position() === '3 of 3' && next().disabled, seen());
                type('nichts');
                check('carousel-none', shownIds() === '' && position() === '' && !note().hidden && prev().disabled && next().disabled, seen());
                type('');
                check('carousel-back', shownIds() === 'c1' && position() === '6 of 6', seen());
                // back to the grid; a click on a card makes it the current card
                pill('views', 'grid').click();
                check('grid-again', shownIds() === 'a1,a2,b1,b2,b3,c1' && param('view') === 'grid', seen());
                document.querySelector('#b2 h3').click();
                check('grid-click', param('card') === 'b2', seen());
                pill('views', 'carousel').click();
                check('carousel-shows-clicked', shownIds() === 'b2' && position() === '4 of 6', seen());
                // the hooks
                window.htmxoDeck.show('karten', 'a1');
                check('hook-show', shownIds() === 'a1' && param('card') === 'a1', seen());
                window.htmxoDeck.view(deck, 'grid');
                check('hook-view', deck.dataset.htmxoDeckView === 'grid' && param('view') === 'grid', seen());
                check('history-state', history.state && history.state.htmx === true, history.state);
                check('events', changes[changes.length - 1] === 'grid:a1' && changes.includes('carousel:a2'), changes);
                // dark: the bar keeps the page's background
                document.documentElement.setAttribute('data-theme', 'dark');
                const dark = getComputedStyle(bar).backgroundColor;
                check('bar-dark', dark === pageBg() && dark !== bg, [dark, pageBg(), bg]);
            } catch (error) {
                check('error ' + error.message, false);
            }
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(; class="container")(h.h1("Karten"), card_deck(CARDS; id="karten")), driver;
            pico_version="2", hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=120)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                    endswith(line, ":true") || println("card_deck browser: ", line)
                end
                @test count(==('\n'), checks[1]) + 1 == 33
            end
        finally
            close(server)
        end
    end
end

@testitem "card_deck browser: a link opens the deck at its view and card, live and exported" setup=[DeckFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = raw"""<script>
        window.addEventListener('load', function () {
            const deck = document.getElementById('karten');
            const shown = [...deck.querySelectorAll('.htmxo-deck-card')].filter(c => c.getClientRects().length > 0).map(c => c.id).join(',');
            const result = document.createElement('pre');
            result.id = 'state';
            result.textContent = [deck.dataset.htmxoDeckView, shown,
                deck.querySelector('[data-htmxo-deck-position]').textContent,
                deck.querySelector('input[name="htmxo-deck-view-karten"]:checked').value].join('|');
            document.body.appendChild(result);
        });
        </script>"""
        route!(DeckApp())
        live = replace(String(dispatch(:GET, "/deck_karten").body), "</body>" => driver * "</body>")
        exported = replace(String(dispatch(:GET, "/deck_karten"; static=StaticExport()).body), "</body>" => driver * "</body>")
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], live) :
            path == "/index.html" ? HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], exported) : HTTP.Response(404)
        end
        state(target) = mktempdir() do profile
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1280,900 --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$target`; timeout=120)
            m = match(r"<pre id=\"state\">(.*?)</pre>"s, dom)
            isnothing(m) ? nothing : m[1]
        end
        try
            for page in ("/", "/index.html")
                @test state(page) == "grid|a1,a2,b1,b2,b3,c1|1 of 6|grid"                   # the position line shows in the carousel only
                @test state("$page?view=carousel&card=b2") == "carousel|b2|4 of 6|carousel"
                @test state("$page?view=carousel") == "carousel|a1|1 of 6|carousel"
                @test state("$page?view=carousel&card=nope") == "carousel|a1|1 of 6|carousel"  # unknown: the first card
                @test state("$page?view=list&card=c1") == "grid|a1,a2,b1,b2,b3,c1|6 of 6|grid"  # unknown view: the default, at the card
                @test state("$page?view=carousel#b3") == "carousel|b3|5 of 6|carousel"       # a card's #id
            end
        finally
            close(server)
        end
    end
end
