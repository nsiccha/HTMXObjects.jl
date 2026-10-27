@testmodule TableTextFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export marked, english_words, table_variants, without_texts_attr

    # Every text replaced by a marker that keeps its placeholders, so a
    # rendered table shows which texts reached it ("⟨count 3 7⟩").
    marked() = table_texts(:en; (n => string("⟨", n,
        join((" {$p}" for p in get(HTMXObjects._TABLE_TEXT_PLACEHOLDERS, n, ())), ""), "⟩")
        for n in fieldnames(TableTexts))...)

    # Fragments of the English texts that no fixture's own content contains.
    english_words = ["Search", "rows shown", "No matching rows", "0 selected", "Select all shown",
        "Clear", "Expand all", "Collapse all", "Toggle child rows", "Details", "Group by",
        "grouping", "Move ", "Loading", "CSV", "More", "Sort by", "Lower bound", "Relative width"]

    items = [(id="k$i", name="Item $i", grp=isodd(i) ? "A" : "B", party=i % 3 == 0 ? "X" : "Y",
              kids=i <= 2 ? [(id="c$i$j", name="Child $i.$j", grp="A", party="X", kids=[]) for j in 1:2] : [])
             for i in 1:6]
    cells(it) = (h.td(it.name), h.td(it.grp))
    linked(it) = (h.td(h.a(it.name; href="#$(it.id)")), h.td(it.grp))
    rows = Any[h.tr(h.td("r$i"), h.td(string(i)); data_htmxo_select_key="r$i") for i in 1:4]
    groupings = ["None" => nothing, "Group" => it -> it.grp, "Party" => it -> it.party]
    grouped(; kw...) = master_detail_table(["N", "G"], items; key=it -> it.id, master=cells,
        detail=it -> h.p("d"), groupings, group_by_url="/t", id="g", kw...)

    # One render per path that writes a built-in text.
    table_variants(texts) = Dict(
        "search" => sortable_table(["A", "B"], rows; id="t", searchable=true, texts),
        "select" => sortable_table(["A", "B"], rows; id="t", searchable=true, selectable="s", select_form="f", texts),
        "csv" => sortable_table(["A", "B"], rows; id="t", download=true, texts),
        "caption" => sortable_table(["A", "B"], rows; id="t", download=true, texts,
            caption=CaptionSpec(; title="T", short="s", long="l")),
        "render_table" => render_table((a=[1, 2], b=["x", "y"]); searchable=true, texts),
        "flat_lazy" => master_detail_table(["N", "G"], items; key=it -> it.id, master=cells,
            detail_url=it -> "/d/$(it.id)", searchable=true, id="m", texts),
        "tree" => master_detail_table(["N", "G"], items; key=it -> it.id, master=linked,
            children=it -> it.kids, detail_url=it -> "/d/$(it.id)", expand_controls=true,
            searchable=true, selectable="s", id="m", texts),
        "group_search" => grouped(; group_by=["Group"], searchable=true, texts),
        "pills_none" => grouped(; group_by=["None"], texts),
        "pills_one" => grouped(; group_by=["Group"], texts),
        "pills_two" => grouped(; group_by=["Group", "Party"], texts),
        "pills_kept" => master_detail_table(["N", "G"], items; key=it -> it.id, master=cells,
            detail=it -> h.p("d"), groupings=groupings[2:end], group_by=["Group"], group_by_url="/t", id="g", texts),
        "sort_keys" => master_detail_table([ColumnSpec("N"; sort_keys=interval_sort_keys(it -> 2.0, it -> 1.0, it -> 3.0; texts)), "G"],
            items; key=it -> it.id, master=cells, detail=it -> h.p("d"), id="k", texts),
    )

    without_texts_attr(html) = replace(html, r" data-htmxo-texts=\"[^\"]*\"" => "")
end

@testitem "table_texts: locale sets, overrides and refusals" setup=[TableTextFixtures] tags=[:unit] begin
    using HTMXObjects
    en = table_texts()
    @test en isa TableTexts && en == table_texts(:en)
    @test en.search == "Search" && en.count == "{shown} of {total} rows shown" && en.empty == "No matching rows"
    de = table_texts(:de; search="Einrichtungen filtern", count="{shown} von {total} Einrichtungen")
    @test de.search == "Einrichtungen filtern" && de.empty == "Keine passenden Zeilen"
    @test HTMXObjects._table_text(de, :count; shown=3, total=42) == "3 von 42 Einrichtungen"
    # A table's caption toggle takes the caption set's own word.
    @test en.more == caption_texts().more && table_texts(:de).more == caption_texts(:de).more == "Mehr"
    @test HTMXObjects._table_text(table_texts(:de), :group_level; level=2, name="Ort") ==
        "Ebene 2: nicht mehr nach Ort gruppieren; ziehen oder ←/→ drücken, um die Reihenfolge zu ändern"
    # Every locale names every text, with no placeholder its text does not take.
    for locale in keys(HTMXObjects._TABLE_TEXT_LOCALES)
        @test Set(keys(getfield(HTMXObjects._TABLE_TEXT_LOCALES, locale))) == Set(fieldnames(TableTexts))
        @test table_texts(locale) isa TableTexts
    end
    # Braces that are no placeholder stay literal.
    @test HTMXObjects._table_text(table_texts(; empty="{ }"), :empty) == "{ }"
    # refused: a misspelt locale, text or placeholder would otherwise show
    # English or a raw "{shwon}" without a word (dev §1, never swallow errors).
    @test_throws ArgumentError table_texts(:xx)
    @test_throws ArgumentError table_texts(:de; serch="Suche")
    @test_throws ArgumentError table_texts(:de; count="{shwon} von {total}")
    @test_throws ArgumentError table_texts(; search="Suche {name}")
    err = try table_texts(; count="{shwon}"); nothing catch e; sprint(showerror, e) end
    @test contains(err, "{shwon}") && contains(err, "{shown}, {total}")
end

@testitem "texts= reaches every built-in table text" setup=[TableTextFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    texts = marked()
    html = Dict(k => repr("text/html", v) for (k, v) in table_variants(texts))
    shown = join(without_texts_attr.(values(html)), "\n")
    for word in english_words
        @test !contains(shown, word)
    end
    # Server-rendered texts, filled in where they take values.
    for marker in ["⟨search⟩", "⟨count 4 4⟩", "⟨empty⟩", "⟨selected 0⟩", "⟨select_all⟩",
                   "⟨clear_selection⟩", "⟨expand_all⟩", "⟨collapse_all⟩", "⟨toggle_children⟩",
                   "⟨details⟩", "⟨group_by⟩", "⟨group_add Group⟩", "⟨group_add_inner Party⟩",
                   "⟨group_level 2 Party⟩", "⟨group_earlier Party⟩", "⟨group_later Group⟩",
                   "⟨group_stop Group⟩", "⟨group_kept Group⟩", "⟨loading⟩", "⟨csv⟩",
                   "<summary>⟨more⟩</summary>", "⟨sort_by⟩", "⟨sort_ascending ⟨sort_estimate⟩⟩",
                   "⟨sort_descending ⟨sort_lower⟩⟩", "⟨sort_upper⟩", "⟨sort_width⟩", "⟨sort_relative_width⟩"]
        @test contains(shown, marker)
    end
    # The browser's texts ride on the outermost element, once per table.
    json = HTMXObjects._table_texts_json(texts)
    for (name, h) in html
        @test count("data-htmxo-texts=", h) == 1
        # A regroupable table's own wrapper holds the table that carries them.
        startswith(name, "group") || startswith(name, "pills") ||
            @test !isnothing(match(r"^<[^>]* data-htmxo-texts=", h))
    end
    @test contains(html["search"], "data-htmxo-texts=\"" * replace(json, '"' => "&quot;") * "\"")
    # English (the default) writes no attribute and matches table_texts().
    english = Dict(k => repr("text/html", v) for (k, v) in table_variants(table_texts()))
    for (name, h) in english
        @test !contains(h, "data-htmxo-texts")
    end
    @test contains(english["search"], ">4 of 4 rows shown<") && contains(english["csv"], "⬇ CSV")
    # Markdown drops these controls, so it does not change. A lazy detail's
    # placeholder is not content there either: its detail row writes nothing
    # (user pick 1mu8842, snag master-detail-ma-e63263bb).
    for name in ("search", "select", "csv", "pills_two", "flat_lazy", "sort_keys")
        @test to_markdown_string(table_variants(texts)[name]) == to_markdown_string(table_variants(table_texts())[name])
    end
    @test !contains(to_markdown_string(table_variants(texts)["flat_lazy"]), "⟨loading⟩")
end

@testitem "a captioned table's long-text toggle follows its texts" tags=[:unit] begin
    using HTMXObjects
    cap = CaptionSpec(; title="Kapazität", short="Plätze je Kreis", long="Stand: Oktober 2026.")
    table(; kw...) = repr("text/html", render_table((kreis=["Kiel"], plaetze=[3]); caption=cap, kw...))
    @test contains(table(texts=table_texts(:de)), "<summary>Mehr</summary>")
    @test contains(table(texts=table_texts(:de; more="Erläuterung")), "<summary>Erläuterung</summary>")
    @test contains(table(), "<summary>More</summary>") && !contains(table(), "data-htmxo-texts")
end

@testitem "row updates, lazy rows and pairs render their texts without the attribute" setup=[TableTextFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    texts = marked()
    items = [(id="k$i", name="Item $i", grp=isodd(i) ? "A" : "B") for i in 1:4]
    base(; kw...) = master_detail_table(["N", "G"], items; key=it -> it.id,
        master=it -> (h.td(it.name), h.td(it.grp)), detail_url=it -> "/d/$(it.id)", id="m", texts, kw...)
    update = repr("text/html", base(; update_rows="k2"))
    @test contains(update, "data-htmxo-row-update") && contains(update, "⟨details⟩") &&
        contains(update, "⟨loading⟩") && !contains(update, "data-htmxo-texts")
    lazy = repr("text/html", base(; groupings=["Group" => it -> it.grp], group_by=["Group"],
        group_rows_url=(k, ms) -> "/rows?k=$k", group_rows="[\"A\"]"))
    @test contains(lazy, "data-htmxo-group-rows") && contains(lazy, "⟨loading⟩") && !contains(lazy, "data-htmxo-texts")
    m, d = master_detail_pair("a", (h.td("x"),), nothing, 1; detail_url="/d", texts)
    @test contains(repr("text/html", d), ">⟨loading⟩<")
    @test contains(repr("text/html", master_detail_pair("a", (h.td("x"),), nothing, 1; detail_url="/d")[2]), ">Loading…<")
end

@testitem "the browser runtime's default texts are table_texts()" tags=[:unit] begin
    using HTMXObjects
    js = repr("text/html", sortable_table_js())
    @test contains(js, "var htmxoTableTextsDefault = " * HTMXObjects._table_texts_json(table_texts()) * ";")
    @test contains(repr("text/html", master_detail_js()), "function htmxoText(")
    # The runtime builds no English text of its own any more.
    for literal in ["' rows shown'", "' selected'", "' hidden by the filter'", "' in collapsed groups'",
                    "'Loading…'", "'Connection lost — retrying…'", "'Failed to load — click to retry'",
                    "'Loading rows failed"]
        @test !contains(js, literal)
    end
end

@testitem "German table texts browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        de = table_texts(:de; search="Einrichtungen filtern", count="{shown} von {total} Einrichtungen")
        places = [(id="kiel", name="Kiel Nord", ort="Kiel"), (id="luebeck", name="Lübeck Süd", ort="Lübeck"),
                  (id="flensburg", name="Flensburg", ort="Flensburg"), (id="husum", name="Husum", ort="Husum")]
        german = master_detail_table(["Name", "Ort"], places; key=p -> p.id,
            master=p -> (h.td(p.name), h.td(p.ort)),
            detail_url=p -> p.id == "kiel" ? "/detail/flaky" : "/detail/missing",
            searchable=true, selectable="ids", id="de", texts=de)
        groups = master_detail_table(["Name", "Ort"], places; key=p -> p.id,
            master=p -> (h.td(p.name), h.td(p.ort)), detail=p -> h.p(p.name),
            groupings=["Ort" => p -> p.ort == "Kiel" ? "Nord" : "Rest"], group_by=["Ort"],
            group_rows_url=(k, ms) -> "/rows?k=$(HTTP.escapeuri(k))", id="gr", texts=table_texts(:de))
        english = sortable_table(["Name"], [h.tr(h.td(n)) for n in ("Alpha", "Beta")]; searchable=true, id="en")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async (cond, n = 200) => { for (let i = 0; i < n && !cond(); i++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const toasts = [];
            window.htmxoToast = message => toasts.push(message);
            const root = id => document.getElementById(id).closest('.htmxo-searchable-table');
            const search = (id, v) => { const i = root(id).querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            const count = id => root(id).querySelector('[data-htmxo-table-count]').textContent;
            const selection = () => document.getElementById('de').closest('.htmxo-selectable-table').querySelector('[data-htmxo-selection-count]').textContent;
            const status = key => document.getElementById('detail-slot-' + key).querySelector('[data-status]').textContent;
            check('placeholder', status('luebeck') === 'Wird geladen…');
            check('initial-count', count('de') === '4 von 4 Einrichtungen');
            check('label', root('de').querySelector('label').textContent.startsWith('Einrichtungen filtern'));
            search('de', 'süd');
            check('count-updates', count('de') === '1 von 4 Einrichtungen');
            search('de', 'nichts');
            check('empty-state', count('de') === '0 von 4 Einrichtungen' && !root('de').querySelector('[data-htmxo-table-empty]').hidden &&
                root('de').querySelector('[data-htmxo-table-empty]').textContent === 'Keine passenden Zeilen');
            search('de', '');
            document.getElementById('row-husum').cells[1].click();
            check('selected', selection() === '1 ausgewählt');
            search('de', 'kiel');
            check('selected-filtered', selection() === '1 ausgewählt (1 durch den Filter ausgeblendet)');
            search('de', '');
            // A 404 detail fails for good; a 503 retries first.
            document.querySelector('#row-luebeck [data-htmxo-detail-toggle]').click();
            check('load-failed', await wait(() => status('luebeck') === 'Laden fehlgeschlagen — zum Wiederholen klicken'));
            document.querySelector('#row-kiel [data-htmxo-detail-toggle]').click();
            check('retrying', await wait(() => status('kiel') === 'Verbindung unterbrochen — neuer Versuch…'));
            check('retry-gives-up', await wait(() => status('kiel') === 'Laden fehlgeschlagen — zum Wiederholen klicken', 400));
            // A lazy group's failed rows raise a German toast.
            document.querySelector('#row-gr--group--Rest [data-htmxo-tree-toggle]').click();
            check('rows-failed', await wait(() => toasts.includes('Laden der Zeilen fehlgeschlagen (500)')));
            check('group-count', count('gr') === '4 von 4 Zeilen angezeigt');
            // A table without texts= keeps English on the same page.
            search('en', 'alp');
            check('english-default', count('en') === '1 of 2 rows shown');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(german, groups, english, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()), pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html"], page) :
            path == "/detail/flaky" ? HTTP.Response(503) :
            path == "/rows" ? HTTP.Response(500) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 13
            end
        finally
            close(server)
        end
    end
end
