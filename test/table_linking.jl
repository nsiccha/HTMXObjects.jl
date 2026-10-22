@testmodule LinkFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export PROBES, LINK_GROUPINGS, probe_cells, probe_table

    # Two Länder in two regions; "k:9" has a key that is not a CSS identifier.
    const PROBES = [(; id, land, region, value=i)
                    for (i, (id, land, region)) in enumerate([
                        ("k1", "Bayern", "Sued"), ("k2", "Hessen", "Mitte"), ("k3", "Bayern", "Sued"),
                        ("k4", "Hessen", "Mitte"), ("k5", "Sachsen", "Mitte"), ("k6", "Bayern", "Sued"),
                        ("k7", "Hessen", "Mitte"), ("k8", "Sachsen", "Mitte"), ("k:9", "Bayern", "Sued")])]
    const LINK_GROUPINGS = ["Keine" => nothing, "Land" => p -> p.land, "Region" => p -> p.region]
    probe_cells(p) = (h.td(p.id), h.td(p.land), h.td(string(p.value)))
    probe_table(; kw...) = master_detail_table(["Probe", "Land", "Wert"], PROBES;
        key=p -> p.id, master=probe_cells, detail=p -> h.p("detail $(p.id)"), kw...)
end

@testitem "linked tables render their link group and row keys" setup=[LinkFixtures] tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    tags(name, markup) = [m.match for m in eachmatch(Regex("<$(name)\\b[^>]*>"), markup)]
    keyed(markup) = [m[1] for m in eachmatch(r"<tr\b[^>]*data-htmxo-link-key=\"([^\"]*)\"", markup)]

    rows = [h.tr(h.td("A"); data_htmxo_link_key="a"), h.tr(h.td("B"); data_htmxo_select_key="b")]
    @test contains(only(tags("table", html(sortable_table(["N"], rows; link="probes")))), "data-htmxo-link=\"probes\"")
    @test contains(only(tags("table", html(sortable_table(["N"], rows; link=:probes, sortable=false)))), "data-htmxo-link=\"probes\"")
    # Tables that do not opt in render as before.
    @test !contains(html(sortable_table(["N"], rows)), "data-htmxo-link=")
    @test !contains(html(probe_table()), "data-htmxo-link")
    @test !contains(html(probe_table(; groupings=LINK_GROUPINGS, group_by="Land")), "data-htmxo-link")
    # Refused: the group name is what the hover event carries; an empty one names no group.
    @test_throws ArgumentError sortable_table(["N"], rows; link="")

    # render_table keys each row by `link_key(row)`.
    nt = (kenn=["072", "081"], wert=[1, 2])
    rt = html(render_table(nt; link="probes", link_key=r -> r.kenn, download=false))
    @test keyed(rt) == ["072", "081"] && contains(only(tags("table", rt)), "data-htmxo-link=\"probes\"")
    # Refused: a link group without row keys (or keys without a group) would highlight nothing.
    @test_throws ArgumentError render_table(nt; link="probes")
    @test_throws ArgumentError render_table(nt; link_key=r -> r.kenn)

    # A flat master/detail table keys its item rows by the caller's own key, not the row id.
    flat = html(probe_table(; link="probes"))
    @test keyed(flat) == [p.id for p in PROBES]
    @test contains(flat, "id=\"row-k--9\"") && contains(flat, "data-htmxo-link-key=\"k:9\"")
    @test !any(t -> contains(t, "id=\"detail-") && contains(t, "data-htmxo-link-key"), tags("tr", flat))

    # A tree keys branches and leaves alike.
    tree = html(master_detail_table(["Name"], [(; id="g", kids=[(; id="l", kids=[])])];
        key=x -> x.id, master=x -> (h.td(x.id),), children=x -> x.kids, link="probes"))
    @test keyed(tree) == ["g", "l"]

    # A regroupable table keys every copy of a leaf by the leaf's key; group rows carry none.
    grouped = html(probe_table(; groupings=[LINK_GROUPINGS..., "Both" => p -> [p.land, p.region]],
        group_by="Both", link="probes", id="g"))
    grows = filter(t -> contains(t, "data-htmxo-group="), tags("tr", grouped))
    @test !isempty(grows) && !any(t -> contains(t, "data-htmxo-link-key"), grows)
    # The group template keys its leaf too; each listed leaf appears under its Land and its region.
    @test count(==("k1"), keyed(grouped)) >= 2 && "k:9" in keyed(grouped)
    nested = html(probe_table(; groupings=LINK_GROUPINGS, group_by=["Region", "Land"], link="probes"))
    @test Set(keyed(nested)) == Set(p.id for p in PROBES)

    # A row update renders the same keys.
    update = html(probe_table(; groupings=LINK_GROUPINGS, group_by="Land", link="probes", id="g", update_rows="k3"))
    @test "k3" in keyed(update)

    # Refused: with `link` the helper writes the key; a second value would silently lose.
    @test_throws ArgumentError probe_table(; link="probes", master_attrs=p -> (; data_htmxo_link_key="x"))
    @test_throws ArgumentError probe_table(; link="probes",
        master=p -> h.tr(probe_cells(p)...; data_htmxo_link_key="x"))

    # `link_key`: tables of the same items on one page keep their own page-unique
    # `key` (row and detail ids) and name each item by one key in the link group.
    trend = html(probe_table(; key=p -> "trend-" * p.id, link="probes", link_key=p -> p.id))
    @test keyed(trend) == [p.id for p in PROBES]
    @test contains(trend, "id=\"row-trend-k1\"") && contains(trend, "id=\"detail-trend-k1\"")
    ttree = html(master_detail_table(["Name"], [(; id="g", kids=[(; id="l", kids=[])])];
        key=x -> "t-" * x.id, master=x -> (h.td(x.id),), children=x -> x.kids, link="probes", link_key=x -> x.id))
    @test keyed(ttree) == ["g", "l"] && contains(ttree, "id=\"row-t-l\"")
    tgrouped = html(probe_table(; key=p -> "trend-" * p.id, groupings=[LINK_GROUPINGS..., "Both" => p -> [p.land, p.region]],
        group_by="Both", link="probes", link_key=p -> p.id))
    @test count(==("k1"), keyed(tgrouped)) >= 2 && "k:9" in keyed(tgrouped) && !any(startswith("trend-"), keyed(tgrouped))
    tupdate = html(probe_table(; key=p -> "trend-" * p.id, groupings=LINK_GROUPINGS, group_by="Land",
        link="probes", link_key=p -> p.id, update_rows="trend-k3"))
    @test "k3" in keyed(tupdate)
    # A lazy group lists each unloaded leaf's link key after its key and search
    # text, so a hover lights the group; without `link_key` the entries stay pairs.
    lazy(; kw...) = html(probe_table(; groupings=LINK_GROUPINGS, group_by="Land",
        group_rows_url=(k, ms) -> "/rows?land=$k", link="probes", kw...))
    @test contains(lazy(; key=p -> "trend-" * p.id, link_key=p -> p.id),
        "data-htmxo-lazy-leaves=\"[[&quot;trend-k5&quot;,&quot;k5 Sachsen 5&quot;,&quot;k5&quot;],[&quot;trend-k8&quot;,&quot;k8 Sachsen 8&quot;,&quot;k8&quot;]]\"")
    @test contains(lazy(), "data-htmxo-lazy-leaves=\"[[&quot;k5&quot;,&quot;k5 Sachsen 5&quot;],[&quot;k8&quot;,&quot;k8 Sachsen 8&quot;]]\"")
    # Refused: a link key without a link group would highlight nothing.
    @test_throws ArgumentError probe_table(; link_key=p -> p.id)
    @test_throws ArgumentError probe_table(; groupings=LINK_GROUPINGS, link_key=p -> p.id)

    # The note on a row that holds the hovered item, in both built-in languages.
    @test table_texts().linked_inside == "↳ inside" && table_texts().linked_deep == "↳ {levels} levels down"
    @test table_texts(:de).linked_inside == "↳ darin" && table_texts(:de).linked_deep == "↳ {levels} Ebenen tiefer"
    @test_throws ArgumentError table_texts(; linked_deep="{depth} down")
end

@testitem "linked tables browser" setup=[LinkFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        grouped = probe_table(; groupings=LINK_GROUPINGS, group_by="Land", searchable=true,
            link="probes", id="grouped", texts=table_texts(:de))
        nested = probe_table(; groupings=LINK_GROUPINGS, group_by=["Region", "Land"], link="probes", id="nested")
        # A flat table in its own scroll box, keyed by hand.
        flat = h.div(; id="box", style="max-height: 7rem; overflow: auto")(
            sortable_table(["Probe", "Wert"], [h.tr(h.td(p.id), h.td(string(p.value)); data_htmxo_link_key=p.id) for p in PROBES];
                link="probes", id="flat"))
        other = sortable_table(["Probe"], [h.tr(h.td(p.id); data_htmxo_link_key=p.id) for p in PROBES];
            link="other", id="other")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const events = [];
            document.addEventListener('htmxo:link', e => events.push(e.detail.group + ':' + e.detail.key));
            const last = () => events[events.length - 1];
            const body = id => document.getElementById(id).closest('table').tBodies[0];
            const lit = id => Array.from(body(id).rows).filter(r => 'htmxoLinked' in r.dataset)
                .map(r => r.id + '=' + (r.dataset.htmxoLinked || 'row') + (r.cells[0].dataset.htmxoLinkedNote ? '[' + r.cells[0].dataset.htmxoLinkedNote + ']' : '')).join(',');
            const flatRow = k => Array.from(body('flat').rows).find(r => r.dataset.htmxoLinkKey === k);
            const over = (to, from) => (to || document.body).dispatchEvent(new PointerEvent('pointerover', {bubbles: true, relatedTarget: from || null}));
            const out = from => from.dispatchEvent(new PointerEvent('pointerout', {bubbles: true, relatedTarget: null}));
            const row = id => document.getElementById('row-' + id);

            // A hovered row announces its key; every table of the group lights its match.
            over(flatRow('k3').cells[0]);
            check('hover-announces', last() === 'probes:k3');
            check('hover-lights-itself', lit('flat') === '=row');
            // k3 sits in the collapsed Bayern group: that row lights up, with a note, and nothing opens.
            check('collapsed-group-noted', lit('grouped') === 'row-group--Bayern=inside[↳ darin]');
            check('nothing-opens', row('group--Bayern').getAttribute('aria-expanded') === 'false');
            check('two-levels-down', lit('nested') === 'row-group--Sued=inside[↳ 2 levels down]');
            check('other-group-untouched', lit('other') === '');
            // Moving to another row hands over without an end in between.
            const before = events.length;
            over(flatRow('k5').cells[1], flatRow('k3').cells[0]);
            check('row-to-row', events.slice(before).join(',') === 'probes:k5' && lit('grouped') === 'row-group--Sachsen=inside[↳ darin]');
            // Leaving the rows ends the hover.
            over(document.body, flatRow('k5').cells[1]);
            check('leave-ends', last() === 'probes:null' && lit('grouped') === '' && lit('flat') === '' && lit('nested') === '');
            over(flatRow('k5').cells[0]);
            out(flatRow('k5').cells[0]);
            check('leave-window-ends', last() === 'probes:null');

            // A plot announces k8: the flat table scrolls it into view inside its box, never the page.
            const box = document.getElementById('box');
            htmxoLink('probes', 'k8', document.getElementById('plot'));
            const r = flatRow('k8').getBoundingClientRect(), b = box.getBoundingClientRect();
            check('reveal-in-box', box.scrollTop > 0 && r.top >= b.top && r.bottom <= b.bottom + 1);
            check('page-not-scrolled', window.scrollY === 0);
            // Opening the group shows the leaf itself lit, the group row no longer.
            row('group--Sachsen').querySelector('[data-htmxo-tree-toggle]').click();
            await wait(() => lit('grouped') === 'row-group--Sachsen--k8=row');
            check('opened-group-lights-leaf', lit('grouped') === 'row-group--Sachsen--k8=row');
            // A row the search hides lights up nothing.
            const search = v => { const i = document.querySelector('#grouped').closest('.htmxo-searchable-table').querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            search('k1');
            check('search-hidden-unlit', lit('grouped') === '');
            search('');
            check('search-cleared-relit', lit('grouped') === 'row-group--Sachsen--k8=row');
            // Regrouping keeps the highlight.
            const select = document.querySelector('#grouped').closest('[data-htmxo-grouped]').querySelector('select[name="group_by"]');
            select.value = 'Region'; select.dispatchEvent(new Event('change', {bubbles: true}));
            await wait(() => lit('grouped') === 'row-group--Mitte=inside[↳ darin]');
            check('regroup-relit', lit('grouped') === 'row-group--Mitte=inside[↳ darin]');
            // A group row has no key: moving onto it from a leaf ends the leaf's hover.
            htmxoLink('probes', null);
            row('group--Mitte').querySelector('[data-htmxo-tree-toggle]').click();
            await wait(() => row('group--Mitte--k2') && !row('group--Mitte--k2').hidden);
            over(row('group--Mitte--k2').cells[1]);
            check('leaf-hover', last() === 'probes:k2' && lit('grouped') === 'row-group--Mitte--k2=row');
            over(row('group--Mitte').cells[1], row('group--Mitte--k2').cells[1]);
            check('group-row-no-key', last() === 'probes:null' && lit('grouped') === '');
            // A detail row stands for its master, the focus for the pointer.
            const toggle = row('group--Mitte--k2').querySelector('[data-htmxo-detail-toggle]');
            toggle.click();
            const detail = document.getElementById('detail-group--Mitte--k2');
            await wait(() => !detail.hidden);
            over(detail.querySelector('p'));
            check('detail-is-master', last() === 'probes:k2' && lit('grouped').includes('row-group--Mitte--k2=row'));
            over(document.body, detail.querySelector('p'));
            toggle.dispatchEvent(new FocusEvent('focusin', {bubbles: true, relatedTarget: null}));
            check('focus-announces', last() === 'probes:k2');
            toggle.dispatchEvent(new FocusEvent('focusout', {bubbles: true, relatedTarget: null}));
            check('blur-ends', last() === 'probes:null');
            // A key that is not a CSS identifier works; page script clears.
            htmxoLink('probes', 'k:9');
            check('any-key', lit('flat') === '=row' && flatRow('k:9').dataset.htmxoLinked === '');
            htmxoLink('probes', null);
            check('cleared', lit('flat') === '' && lit('grouped') === '' && lit('nested') === '');
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.div(; id="plot")("plot"), grouped, nested, flat, other,
            h.div(; style="height: 3000px"), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html"], page) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 22
            end
        finally
            close(server)
        end
    end
end

@testitem "linked tables keyed by link_key browser" setup=[LinkFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Three tables of the same probes on one page: each keeps its own row
        # and detail ids, and all three name a probe by its id in the group.
        main = probe_table(; link="probes", id="main")
        trend = probe_table(; key=p -> "trend-" * p.id, link="probes", link_key=p -> p.id, id="trend")
        lazy = probe_table(; key=p -> "lz-" * p.id, groupings=LINK_GROUPINGS, group_by="Land",
            group_rows_url=(k, ms) -> "/rows?land=$k", link="probes", link_key=p -> p.id, id="lazy")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const events = [];
            document.addEventListener('htmxo:link', e => events.push(e.detail.group + ':' + e.detail.key));
            const last = () => events[events.length - 1];
            const body = id => document.getElementById(id).closest('table').tBodies[0];
            const lit = id => Array.from(body(id).rows).filter(r => 'htmxoLinked' in r.dataset)
                .map(r => r.id + '=' + (r.dataset.htmxoLinked || 'row') + (r.cells[0].dataset.htmxoLinkedNote ? '[' + r.cells[0].dataset.htmxoLinkedNote + ']' : '')).join(',');
            const over = (to, from) => (to || document.body).dispatchEvent(new PointerEvent('pointerover', {bubbles: true, relatedTarget: from || null}));
            const row = id => document.getElementById('row-' + id);

            // A row of the second table announces the probe's own key and lights the
            // probe in the other tables, the lazy group around it included.
            over(row('trend-k3').cells[1]);
            check('announces-link-key', last() === 'probes:k3');
            check('lights-itself', lit('trend') === 'row-trend-k3=row');
            check('lights-other-table', lit('main') === 'row-k3=row');
            check('lights-lazy-group', lit('lazy') === 'row-group--Bayern=inside[↳ inside]');
            // A row of the first table lights the second table's row.
            over(row('k8').cells[1], row('trend-k3').cells[1]);
            check('row-to-row', last() === 'probes:k8' && lit('trend') === 'row-trend-k8=row' && lit('lazy') === 'row-group--Sachsen=inside[↳ inside]');
            over(document.body, row('k8').cells[1]);
            check('leave-ends', last() === 'probes:null' && lit('main') === '' && lit('trend') === '' && lit('lazy') === '');
            // Each table's detail is its own: the ids do not collide.
            row('trend-k5').querySelector('[data-htmxo-detail-toggle]').click();
            await wait(() => !document.getElementById('detail-trend-k5').hidden);
            check('own-detail', !document.getElementById('detail-trend-k5').hidden && document.getElementById('detail-k5').hidden);
            // Page script announces a key that is not a CSS identifier.
            htmxoLink('probes', 'k:9');
            check('any-key', lit('trend') === 'row-trend-k--9=row' && lit('main') === 'row-k--9=row' && lit('lazy') === 'row-group--Bayern=inside[↳ inside]');
            htmxoLink('probes', null);
            check('cleared', lit('main') === '' && lit('trend') === '' && lit('lazy') === '');
            const result = document.createElement('pre');
            result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(main, trend, lazy, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html"], page) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 9
            end
        finally
            close(server)
        end
    end
end
