@testmodule SortKeyFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export ZONES, zone_text, employees, zone_table, valued, pick

    # Cells that carry sort values (the header's list of names starts `[&quot;`).
    valued(html) = length(collect(eachmatch(r"data-htmxo-sort-keys=\"\[[-0-9n]", html)))
    # The menu's button for order `k` ("1:desc").
    pick(th, k) = match(Regex("<button[^>]*data-htmxo-sort-pick=\"$k\"[^>]*>"), th).match

    # One estimate with its interval per zone. Delta's estimate is 0 (no
    # relative width) and Eps has no lower bound (no width either).
    const ZONES = [
        (; id="a", name="Alpha", grp="X", mean=22000.0, lo=13000.0, hi=34000.0),
        (; id="b", name="Beta", grp="Y", mean=5000.0, lo=4000.0, hi=6500.0),
        (; id="c", name="Gamma", grp="X", mean=30000.0, lo=10000.0, hi=33000.0),
        (; id="d", name="Delta", grp="Y", mean=0.0, lo=-1000.0, hi=1000.0),
        (; id="e", name="Eps", grp="X", mean=8000.0, lo=missing, hi=9000.0),
    ]
    zone_text(z) = string(round(Int, z.mean / 1000), " Tsd. (", z.lo === missing ? "?" : round(Int, z.lo / 1000),
        "–", round(Int, z.hi / 1000), " Tsd.)")
    employees(; texts=table_texts()) = ColumnSpec("Employees"; help="Estimate with its 95 % interval",
        sort_keys=interval_sort_keys(z -> z.mean, z -> z.lo, z -> z.hi; texts))
    zone_table(; texts=table_texts(), kw...) = master_detail_table(["Name", employees(; texts), "Group"], ZONES;
        key=z -> z.id, master=z -> (h.td(z.name), h.td(zone_text(z)), h.td(z.grp)),
        detail=z -> h.p("Zone ", z.name), texts, kw...)
end

@testitem "a column with several sort keys: header menu and cell values" setup=[SortKeyFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    html = repr("text/html", zone_table(; id="k"))
    th = match(r"<th[^>]*data-htmxo-sort-keys[^>]*>.*?</th>"s, html).match
    @test contains(th, "data-htmxo-sort-keys=\"[&quot;Estimate&quot;,&quot;Lower bound&quot;,&quot;Upper bound&quot;,&quot;Interval width&quot;,&quot;Relative width&quot;]\"")
    # The label keeps today's button; the ▾ and its menu follow it.
    @test contains(th, "onclick=\"sortTable(1, this)\"") && contains(th, "class=\"htmxo-sort-control\"")
    @test contains(th, "class=\"htmxo-sort-menu-toggle\"") && contains(th, "aria-label=\"Sort by\"") &&
        contains(th, "aria-expanded=\"false\"") && contains(th, "popover=\"manual\"")
    @test count("class=\"htmxo-sort-pick\"", th) == 10 && count("aria-pressed=\"false\"", th) == 10
    @test contains(th, "aria-label=\"Lower bound, descending\"") && contains(th, "data-htmxo-sort-pick=\"1:desc\"") &&
        contains(th, "onclick=\"htmxoSortPick(this,1,&#39;desc&#39;,event)\"")
    # Unsorted: no active key, no caret.
    @test !contains(th, "data-htmxo-sort-key=") && !contains(th, "htmxo-sort-caret")
    # Each row's cell carries the five values; missing ones are null.
    cell(id) = match(Regex("<tr[^>]*id=\"row-$id\"[^>]*>.*?</tr>", "s"), html).match
    @test contains(cell("a"), "data-htmxo-sort-keys=\"[22000.0,13000.0,34000.0,21000.0,$(21000.0 / 22000.0)]\"")
    @test contains(cell("d"), "data-htmxo-sort-keys=\"[0.0,-1000.0,1000.0,2000.0,null]\"")
    @test contains(cell("e"), "data-htmxo-sort-keys=\"[8000.0,null,9000.0,null,null]\"")
    # Only that column's cell: the name cell carries none.
    @test valued(html) == 5
    # The rows are otherwise those of the same table without sort keys.
    plain = repr("text/html", master_detail_table(["Name", "Employees", "Group"], ZONES;
        key=z -> z.id, master=z -> (h.td(z.name), h.td(zone_text(z)), h.td(z.grp)), detail=z -> h.p("Zone ", z.name), id="k"))
    rows_of(s) = replace(match(r"<tbody.*</tbody>"s, s).match, r" data-htmxo-sort-keys=\"[^\"]*\"" => "")
    @test rows_of(html) == rows_of(plain)
    # Markdown keeps the label and the cell text: no menu, no key names.
    md = to_markdown_string(zone_table())
    @test contains(md, "Employees") && contains(md, "22 Tsd. (13–34 Tsd.)")
    @test !contains(md, "Sort by") && !contains(md, "Lower bound") && !contains(md, "▾")
    @test md == to_markdown_string(master_detail_table(["Name", ColumnSpec("Employees"; help="Estimate with its 95 % interval"), "Group"], ZONES;
        key=z -> z.id, master=z -> (h.td(z.name), h.td(zone_text(z)), h.td(z.grp)), detail=z -> h.p("Zone ", z.name)))
    # German names come from the table's texts.
    de = repr("text/html", zone_table(; texts=table_texts(:de)))
    @test contains(de, "&quot;Schätzwert&quot;,&quot;Untergrenze&quot;,&quot;Obergrenze&quot;,&quot;Intervallbreite&quot;,&quot;Relative Breite&quot;")
    @test contains(de, "aria-label=\"Sortieren nach\"") && contains(de, "aria-label=\"Untergrenze, absteigend\"")
    # The values a hand-built cell carries are the ones the table computes.
    @test interval_sort_values(22000.0, 13000.0, 34000.0) ==
        sort_values(22000.0, 13000.0, 34000.0, 21000.0, 21000.0 / 22000.0)
    @test sort_values(1, "b", missing, NaN, Inf, nothing, true) == (; data_htmxo_sort_keys="[1,\"b\",null,null,null,null,1]")
    @test interval_sort_keys(; texts=table_texts(:de)) == ["Schätzwert", "Untergrenze", "Obergrenze", "Intervallbreite", "Relative Breite"]
end

@testitem "several sort keys: default_sort names the key; refusals" setup=[SortKeyFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    sorted = repr("text/html", zone_table(; default_sort=(col="Employees", key="Lower bound", dir=:desc)))
    th = match(r"<th[^>]*data-htmxo-sort-keys[^>]*>.*?</th>"s, sorted).match
    @test contains(th, "data-sort-dir=\"desc\"") && contains(th, "aria-sort=\"descending\"") &&
        contains(th, "data-htmxo-sort-key=\"1\"")
    @test contains(th, "<span class=\"htmxo-sort-caret\"> ▼<small class=\"htmxo-sort-key\"> Lower bound</small></span>")
    @test count("aria-pressed=\"true\"", th) == 1 && contains(pick(th, "1:desc"), "aria-pressed=\"true\"")
    # The first key is the default: no key attribute, a bare caret, as for any column.
    for ds in ("Employees" => :asc, (col=2,), (col="Employees", key="Estimate"), (col=2, key="", dir=:asc))
        th0 = match(r"<th[^>]*data-htmxo-sort-keys[^>]*>.*?</th>"s, repr("text/html", zone_table(; default_sort=ds))).match
        @test !contains(th0, "data-htmxo-sort-key=") && contains(th0, "<span class=\"htmxo-sort-caret\"> ▲</span>") &&
            contains(pick(th0, "0:asc"), "aria-pressed=\"true\"")
    end
    # refused: a key the column does not have, or a key for a one-order column,
    # would stamp a marker the rows do not follow (dev §1).
    @test_throws ErrorException zone_table(; default_sort=(col="Employees", key="Median"))
    @test_throws ErrorException zone_table(; default_sort=(col="Name", key="Estimate"))
    @test_throws ErrorException zone_table(; default_sort=(column="Employees",))
    # refused: a menu of one order is noise, the cell's data-sort-value is that order.
    @test_throws ArgumentError ColumnSpec("A"; sort_keys=["Only" => identity])
    # refused: two orders of one name cannot be told apart in the menu or the state.
    @test_throws ArgumentError ColumnSpec("A"; sort_keys=["x" => identity, "x" => identity])
    @test_throws ArgumentError ColumnSpec("A"; sort_keys=["x" => identity, "y"])
    @test_throws ArgumentError ColumnSpec("A"; sort_keys=["x" => 1, "y" => 2])
    @test_throws ArgumentError ColumnSpec("A"; sort_keys=["x", " "])
    # No keys: the String header, byte for byte.
    rows = [h.tr(h.td("2"), h.td("b")), h.tr(h.td("1"), h.td("a"))]
    @test repr("text/html", sortable_table([ColumnSpec("A"; sort_keys=()), "B"], rows; default_sort="A")) ==
        repr("text/html", sortable_table(["A", "B"], rows; default_sort="A"))
    # refused: the table writes the values, so a master cell may not write them too.
    @test_throws ArgumentError master_detail_table(["Name", employees(), "Group"], ZONES;
        key=z -> z.id, master=z -> (h.td(z.name), h.td(zone_text(z); sort_values(1, 2, 3, 4, 5)...), h.td(z.grp)),
        detail=z -> h.p("x"))
end

@testitem "several sort keys in sortable_table, render_table and regroupable tables" setup=[SortKeyFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    # sortable_table: the column names the keys, each cell carries its values.
    names = interval_sort_keys()
    rows = [h.tr(h.td(z.name), h.td(zone_text(z); interval_sort_values(z.mean, z.lo, z.hi)...)) for z in ZONES]
    html = repr("text/html", sortable_table(["Name", ColumnSpec("Employees"; sort_keys=names)], rows; id="s"))
    @test contains(html, "class=\"htmxo-sort-menu-toggle\"") &&
        contains(html, "data-htmxo-sort-keys=\"[0.0,-1000.0,1000.0,2000.0,null]\"")
    # refused: sortable_table's rows are built already, so it cannot call the functions.
    err = try sortable_table(["Name", employees()], rows); nothing catch e; e end
    @test err isa ArgumentError && contains(sprint(showerror, err), "sort_values")
    # refused: a cell with the wrong number of values would sort by the wrong one.
    short = [h.tr(h.td("x"), h.td("1"; sort_values(1, 2)...))]
    err = try sortable_table(["Name", ColumnSpec("Employees"; sort_keys=names)], short); nothing catch e; e end
    @test err isa ArgumentError && contains(sprint(showerror, err), "2 sort values for its 5 sort keys")
    # A cell without values sorts by its own text (a group row, a total).
    @test sortable_table(["Name", ColumnSpec("Employees"; sort_keys=names)], [h.tr(h.td("Total"), h.td("65 Tsd."))]) isa Any

    # render_table: `columns` gives a column its header; functions take the Tables.jl row.
    table = (name=[z.name for z in ZONES], mean=[z.mean for z in ZONES], lo=[z.lo for z in ZONES], hi=[z.hi for z in ZONES])
    spec = ColumnSpec("Employees"; sort_keys=interval_sort_keys(r -> r.mean, r -> r.lo, r -> r.hi))
    rt = repr("text/html", render_table(table; columns=["mean" => spec, :name => "Zone"]))
    @test contains(rt, ">Zone<") && contains(rt, ">Employees<") && count("class=\"htmxo-sort-menu-toggle\"", rt) == 1
    @test contains(rt, "data-htmxo-sort-keys=\"[0.0,-1000.0,1000.0,2000.0,null]\"")
    @test valued(rt) == 5
    @test contains(repr("text/html", render_table(table; columns=(mean=spec,))), "class=\"htmxo-sort-menu-toggle\"")
    # A ColumnSpec explains a render_table column too.
    @test contains(repr("text/html", render_table(table; columns=["lo" => ColumnSpec("Low"; help="Lower bound")])),
        "title=\"Lower bound\"")
    @test_throws ArgumentError render_table(table; columns=["median" => spec])
    @test_throws ArgumentError render_table(table; columns=["mean" => ColumnSpec("Employees"; sort_keys=names)])
    @test_throws ArgumentError render_table(table; columns=["mean" => 3])

    # Regroupable: leaves carry values, group rows (their summary) do not.
    grouped = repr("text/html", zone_table(; groupings=["None" => nothing, "Group" => z -> z.grp], group_by=["Group"],
        group_summary=["Employees" => ColumnSummary(:sum, z -> z.mean)], id="g"))
    group_row = match(r"<tr[^>]*id=\"row-g--group--X\"[^>]*>.*?</tr>"s, grouped).match
    @test !contains(group_row, "data-htmxo-sort-keys")
    @test valued(grouped) == 5
    # A row update renders the leaf's values as the table does.
    update = repr("text/html", zone_table(; groupings=["None" => nothing, "Group" => z -> z.grp], group_by=["Group"],
        update_rows="a", id="g"))
    @test contains(update, "data-htmxo-sort-keys=\"[22000.0,13000.0,34000.0,21000.0,")
end

@testitem "several sort keys sort, regroup, export and report their state browser" setup=[SortKeyFixtures, ChromeDump] tags=[:browser] begin
    using HTMXObjects
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const checks = [];
                const check = (name, ok) => checks.push(name + ':' + (ok === true ? 'true' : 'false ' + String(ok).slice(0, 300)));
                const css = e => getComputedStyle(e);
                const body = document.getElementById('k'), table = body.closest('table');
                const wrapper = table.closest('[data-htmxo-grouped]');
                const th = table.tHead.rows[0].cells[1], name = table.tHead.rows[0].cells[0];
                const toggle = th.querySelector('.htmxo-sort-menu-toggle'), menu = th.querySelector('.htmxo-sort-menu');
                const pick = k => th.querySelector('[data-htmxo-sort-pick="' + k + '"]');
                const leaves = (group = null) => Array.from(body.rows).filter(r => 'htmxoLeaf' in r.dataset &&
                    (group === null || r.dataset.htmxoParent === group)).map(r => r.dataset.htmxoLeaf).join(',');
                const caret = () => (th.querySelector(':scope > .htmxo-sort-caret') || {}).textContent;
                const pressed = () => Array.from(th.querySelectorAll('[aria-pressed="true"]')).map(b => b.dataset.htmxoSortPick).join(',');
                const open = () => menu.matches(':popover-open');
                // Under Pico the ▾ and the menu's buttons are no filled buttons.
                const plain = document.getElementById('plain');
                check('pico-pads-buttons', css(plain).paddingLeft !== '0px');
                check('toggle-plain', css(toggle).backgroundColor === 'rgba(0, 0, 0, 0)' && css(toggle).borderTopWidth === '0px' &&
                    css(toggle).color === css(th).color);
                check('initial', leaves() === 'a,b,c,d,e');
                // The label sorts by the column's first key, as any column.
                th.querySelector('.htmxo-sort-control').click();
                check('estimate-asc', leaves() === 'd,b,e,a,c' && caret() === ' ▲' && pressed() === '0:asc');
                th.querySelector('.htmxo-sort-control').click();
                check('estimate-desc', leaves() === 'c,a,e,b,d' && th.getAttribute('aria-sort') === 'descending');
                // ▾ opens the menu, focused on the order in force.
                toggle.click();
                check('menu-open', open() && toggle.getAttribute('aria-expanded') === 'true' &&
                    document.activeElement === pick('0:desc'));
                check('menu-plain', css(pick('1:asc')).backgroundColor === 'rgba(0, 0, 0, 0)' &&
                    css(pick('0:desc')).fontWeight === '700');
                const r = toggle.getBoundingClientRect(), m = menu.getBoundingClientRect();
                check('menu-below', Math.abs(m.top - r.bottom - 2) < 1.5 && m.width > 0);
                // A click inside the menu but on no button neither sorts nor closes it.
                menu.querySelector('.htmxo-sort-menu-title').click();
                check('menu-inside', open() && leaves() === 'c,a,e,b,d');
                pick('1:desc').click();
                check('lower-desc', leaves() === 'a,c,b,d,e' && !open() && toggle.getAttribute('aria-expanded') === 'false' &&
                    document.activeElement === toggle);
                check('lower-marked', th.dataset.htmxoSortKey === '1' && caret() === ' ▼ Lower bound' && pressed() === '1:desc');
                check('state', JSON.stringify(htmxoSortState('#k')) === '{"sort_col":2,"sort_dir":"desc","sort_key":"Lower bound"}');
                // The label flips the direction of the active key; a missing value stays last.
                th.querySelector('.htmxo-sort-control').click();
                check('lower-asc', leaves() === 'd,b,c,a,e' && caret() === ' ▲ Lower bound' && pressed() === '1:asc');
                toggle.click(); pick('4:asc').click();
                check('relative-asc', leaves().startsWith('b,c,a,') && ['d,e', 'e,d'].includes(leaves().slice(6)));
                toggle.click(); pick('4:desc').click();
                check('relative-desc', leaves().startsWith('a,c,b,') && ['d,e', 'e,d'].includes(leaves().slice(6)));
                toggle.click(); pick('3:asc').click();
                check('width-asc', leaves() === 'd,b,a,c,e');
                // Escape closes the menu and hands the focus back; so does a click elsewhere.
                toggle.click();
                document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
                check('escape', !open() && document.activeElement === toggle);
                toggle.click();
                document.body.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}));
                check('outside', !open() && toggle.getAttribute('aria-expanded') === 'false');
                toggle.click(); toggle.click();
                check('toggle-closes', !open());
                // Regrouping keeps the key and direction: interval width, ascending.
                htmxoGroupRequest(wrapper.querySelector('.htmxo-group-pills'), ['Group'], null);
                check('regrouped', leaves('row-k--group--X') === 'a,c,e' && leaves('row-k--group--Y') === 'd,b' &&
                    caret() === ' ▲ Interval width');
                htmxoGroupRequest(wrapper.querySelector('.htmxo-group-pills'), [], null);
                check('flat-again', leaves() === 'd,b,a,c,e');
                // Another column clears the marks; its own sort is unchanged.
                name.querySelector('.htmxo-sort-control').click();
                check('other-column', leaves() === 'a,b,d,e,c' && pressed() === '' && !th.hasAttribute('aria-sort') &&
                    JSON.stringify(htmxoSortState('#k')) === '{"sort_col":1,"sort_dir":"asc"}');
                // CSV: the column's name alone, the cells as they show.
                const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
                let blob = null;
                URL.createObjectURL = b => { blob = b; return 'blob:test'; };
                HTMLAnchorElement.prototype.click = function() {};
                try { downloadTableCsv(body, 'k.csv'); } finally {
                    URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
                }
                const csv = blob ? (await blob.text()).split('\n') : [];
                check('csv', csv[0] === 'Name,Employees,Group' && csv[1] === 'Alpha,22 Tsd. (13–34 Tsd.),X');
                // A sortable_table whose cells carry their values sorts the same way.
                const s = document.getElementById('s').closest('table').tHead.rows[0].cells[1];
                s.querySelector('.htmxo-sort-menu-toggle').click();
                s.querySelector('[data-htmxo-sort-pick="2:desc"]').click();
                check('hand-built', Array.from(document.getElementById('s').rows).map(r => r.cells[0].textContent).join(',') ===
                    'Alpha,Gamma,Eps,Beta,Delta');
                const result = document.createElement('pre'); result.id = 'checks';
                result.textContent = checks.join('\n');
                document.body.appendChild(result);
            });
            """))
        names = interval_sort_keys()
        hand = sortable_table(["Name", ColumnSpec("Employees"; sort_keys=names)],
            [h.tr(h.td(z.name), h.td(zone_text(z); interval_sort_values(z.mean, z.lo, z.hi)...)) for z in ZONES]; id="s")
        content = h.main(; class="container")(
            zone_table(; id="k", groupings=["None" => nothing, "Group" => z -> z.grp], group_by=["None"],
                group_summary=["Employees" => ColumnSummary(:sum, z -> z.mean)]),
            hand, h.button("Plain"; type="button", id="plain"), driver)
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            # The page shell as an app builds it: Pico from the vendor copy, the
            # table runtime and styles from the shell itself.
            write(fixture, repr("text/html", htmx(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
                hyperscript_version=nothing, preload_version=nothing)))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=4000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        result = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
        @test !isnothing(result)
        lines = isnothing(result) ? String[] : split(result.captures[1], '\n')
        @test length(lines) == 24
        for line in lines
            @test endswith(line, ":true")
        end
    end
end
