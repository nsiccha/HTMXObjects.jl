@testmodule GroupingFixtures begin
    using HTMXObjects
    import HTMXObjects: h
    export TX, GROUPINGS, grouped

    # Two payments match two rules each ("p3" and "p5"), so "rule" lists them twice.
    const TX = [(; id="p$i", party, iban, amount=-10.0 * i, memo="memo $i")
                for (i, (party, iban)) in enumerate([
                    ("Acme", "DE01"), ("Acme", "DE02"), ("Acme Prime", "DE01"), ("Bakery", "DE03"),
                    ("Prime Video", "DE04"), ("Bakery", "DE03"), ("Acme", "DE01")])]
    const GROUPINGS = [
        "none" => nothing,
        "party" => t -> t.party,
        "iban" => t -> t.iban,
        "rule" => t -> [name for (name, re) in ("Shops" => r"Acme|Bakery", "Media" => r"Prime")
                        if occursin(re, t.party)],
    ]

    grouped(; kw...) = master_detail_table(["Party", "IBAN", "Amount"], TX;
        key=t -> t.id, master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount))),
        detail=t -> h.p(t.memo), groupings=GROUPINGS, kw...)
end

@testitem "regroupable master_detail_table renders groups over the same leaves" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    html(x) = repr("text/html", x)
    party = html(grouped(group_by="party", selectable="tx", select_form="bulk", id="g",
        group_by_url="/table", searchable=true, search_query="acme"))
    @test contains(party, "data-htmxo-grouped=\"party\"")
    @test contains(party, "id=\"row-group--Acme\"") && contains(party, "data-htmxo-group=\"\"")
    @test count("data-htmxo-group=\"\"", party) == 4
    # Leaves keep their own selection key and value; group rows submit under <name>_group.
    @test contains(party, "data-htmxo-select-key=\"p1\"") && contains(party, "data-htmxo-select-value=\"p1\"")
    @test contains(party, "data-htmxo-select-key=\"group:Acme\"") && contains(party, "data-htmxo-select-name=\"tx_group\"")
    @test contains(party, "data-htmxo-parent=\"row-group--Acme\"")
    # The Group by control: every grouping, the active one selected, posted with the bulk form.
    @test contains(party, "<select name=\"group_by\" hx-get=\"/table\" hx-target=\"closest [data-htmxo-grouped]\"")
    @test contains(party, "form=\"bulk\"") && contains(party, "<option value=\"party\" selected=\"true\">party</option>")
    @test contains(party, "class=\"htmxo-tree-controls\"><label>Group by")
    @test contains(party, "type=\"search\"") && contains(party, "value=\"acme\"")
    # Overlapping membership: one leaf, two rows, two ids, one selection key.
    rule = html(grouped(group_by="rule", selectable="tx"))
    @test count("data-htmxo-select-key=\"p3\"", rule) == 2
    @test contains(rule, "id=\"row-group--Shops--p3\"") && contains(rule, "id=\"row-group--Media--p3\"")
    # The flat grouping renders the leaves themselves, keyed the same way.
    flat = html(grouped(group_by="none", selectable="tx", group_by_url="/table"))
    @test !contains(flat, "data-htmxo-group=\"\"") && !contains(flat, "data-htmxo-hierarchy=\"\"")
    @test count("data-htmxo-select-key=\"p", flat) == length(TX)
    @test contains(flat, "<option value=\"none\" selected=\"true\">none</option>")
    @test html(grouped()) == html(grouped(group_by="none"))
    # A custom group summary, and caller master_attrs winning over the helper's.
    custom = html(grouped(group_by="iban", group_master=(k, ms) -> (h.td("IBAN $k"), h.td(string(length(ms))), h.td("")),
        master_attrs=t -> (; data_kind="tx")))
    @test contains(custom, "IBAN DE01") && contains(custom, "data-kind=\"tx\"")
    # The control and the hidden search scaffold are HTML-only.
    md = to_markdown_string(grouped(group_by="party", group_by_url="/table"))
    @test !contains(md, "Group by") && contains(md, "Acme Prime")
    @test_throws ArgumentError grouped(group_by="nope")
    @test_throws ArgumentError grouped(children=t -> ())
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", group_by="party")
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", groupings=["a" => nothing, "a" => nothing])
end

@testitem "lazy groups: placeholders carry search text and selection keys" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    lazy_url = (k, ms) -> length(ms) > 2 ? "/rows?key=$k" : nothing
    page = html(grouped(group_by="party", selectable="tx", group_rows_url=lazy_url,
        select_submit=t -> t.id != "p7"))
    # "Acme" (3 rows) loads lazily; "Bakery" (2 rows) is eager.
    @test contains(page, "data-htmxo-lazy-rows=\"/rows?key=Acme\"")
    @test !contains(page, "id=\"row-group--Acme--p1\"") && contains(page, "id=\"row-group--Bakery--p4\"")
    @test contains(page, "data-htmxo-search-members=\"Acme DE01 -10.0 Acme DE02 -20.0 Acme DE01 -70.0\"")
    @test contains(page, "data-htmxo-select-members=\"{&quot;p1&quot;:&quot;p1&quot;,&quot;p2&quot;:&quot;p2&quot;,&quot;p7&quot;:null}\"")
    # A lazy group starts collapsed and names no child rows yet.
    acme = match(r"<tr[^>]*id=\"row-group--Acme\"[^>]*>.*?</tr>"s, page).match
    @test contains(acme, "data-htmxo-tree-open=\"false\"") && !contains(acme, "aria-controls")
    # The lazy-load response: exactly the rows an eager render gives that group.
    rows = html(grouped(group_by="party", selectable="tx", group_rows_url=lazy_url,
        select_submit=t -> t.id != "p7", group_rows="Acme", initially_open=true))
    @test startswith(rows, "<tbody data-htmxo-group-rows=\"Acme\">")
    eager = html(grouped(group_by="party", selectable="tx", select_submit=t -> t.id != "p7",
        initially_open=true))
    for id in ("p1", "p2", "p7")
        tr = match(Regex("<tr[^>]*id=\"row-group--Acme--$id\"[^>]*>.*?</tr>", "s"), rows).match
        @test contains(eager, tr)
    end
    @test !contains(rows, "id=\"row-group--Acme\"") && !contains(rows, "Bakery")
    @test contains(rows, "id=\"detail-group--Acme--p1\"")
    @test_throws ArgumentError grouped(group_by="none", group_rows="Acme")
    # Search text from `search_text` when given.
    custom = html(grouped(group_by="party", group_rows_url=lazy_url, search_text=t -> "tx $(t.id)"))
    @test contains(custom, "data-htmxo-search-members=\"tx p1 tx p2 tx p7\"")
end

@testitem "regroupable table browser" setup=[GroupingFixtures] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        table(group_by, q="", group_rows=nothing) = grouped(; group_by, search_query=q, group_rows,
            group_by_url="/table", group_rows_url=(k, ms) -> length(ms) > 2 ? "/rows?group_by=$group_by&key=$(HTTP.escapeuri(k))" : nothing,
            group_master=(k, ms) -> (h.td(h.strong(k)), h.td(h.select(; name="mode", id="mode-$k")(h.option("off"), h.option("on"))),
                h.td(string(sum(m.amount for m in ms)); data_sort_value=string(sum(m.amount for m in ms)))),
            selectable="tx", select_form="bulk", searchable=true, expand_controls=group_by != "none", id="g")
        bulk = h.form(; id="bulk")(h.button("Apply"; id="apply", data_htmxo_needs_selection="tx", disabled=true))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const g = () => document.querySelector('[data-htmxo-grouped]');
            const row = id => document.getElementById('row-' + id);
            const rows = () => Array.from(g().querySelector('tbody').rows).filter(r => !r.id.startsWith('detail-'));
            const shown = () => rows().filter(r => !r.hidden).map(r => r.id.slice(4)).join(',');
            const count = () => g().querySelector('[data-htmxo-selection-count]').textContent;
            const inputs = () => new FormData(document.getElementById('bulk')).getAll('tx').sort().join(',');
            const groups = () => new FormData(document.getElementById('bulk')).getAll('tx_group').join(',');
            const click = (el, mods = {}) => el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ...mods}));
            const toggle = id => row(id).querySelector('[data-htmxo-tree-toggle]').click();
            const search = v => { const i = g().querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            const regroup = async v => {
                const select = g().querySelector('select[name="group_by"]');
                select.value = v; select.dispatchEvent(new Event('change', {bubbles: true}));
                await wait(() => g().dataset.htmxoGrouped === v);
                await new Promise(r => setTimeout(r, 50));
            };
            check('initial', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video');
            check('lazy-placeholder', row('group--Acme').dataset.htmxoLazyRows && !row('group--Acme--p1'));
            // Expanding a lazy group fetches its rows once and opens it.
            toggle('group--Acme');
            await wait(() => row('group--Acme--p1'));
            check('lazy-loaded', shown() === 'group--Acme,group--Acme--p1,group--Acme--p2,group--Acme--p7,group--Acme--Prime,group--Bakery,group--Prime--Video' &&
                row('group--Acme').getAttribute('aria-expanded') === 'true' && !('htmxoLazyRows' in row('group--Acme').dataset));
            check('lazy-aria-controls', row('group--Acme').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-group--Acme--p1 row-group--Acme--p2 row-group--Acme--p7');
            click(row('group--Acme--p1').cells[2]);
            click(row('group--Acme--p2').cells[2], {ctrlKey: true});
            check('select-leaves', count() === '2 selected' && inputs() === 'p1,p2' && !document.getElementById('apply').disabled);
            // A caller control in a group row keeps its own behaviour.
            click(document.getElementById('mode-Bakery'));
            check('group-control-no-select', count() === '2 selected' && row('group--Bakery').getAttribute('aria-selected') === 'false');
            // Regroup by rule: p1/p2 sit in the lazy "Shops" group, not loaded.
            await regroup('rule');
            check('regroup-keeps-selection', count() === '2 selected (2 in collapsed groups)' && inputs() === 'p1,p2');
            check('rule-groups', shown() === 'group--Shops,group--Media');
            // Selecting a whole group submits it under tx_group, with its grouping.
            click(row('group--Media').cells[2], {ctrlKey: true});
            check('group-selection', groups() === 'Media' && new FormData(document.getElementById('bulk')).get('group_by') === 'rule' &&
                count() === '3 selected (2 in collapsed groups)');
            // Media is eager: p3 and p5 are listed there and (lazily) in Shops too.
            toggle('group--Media');
            click(row('group--Media--p3').cells[2], {ctrlKey: true});
            check('copy-selected', count() === '4 selected (2 in collapsed groups)' && inputs() === 'p1,p2,p3');
            // Search reaches the rows of a group that has not loaded yet.
            search('bakery');
            check('search-lazy-members', shown() === 'group--Shops' && !row('group--Shops').querySelector('[data-htmxo-tree-toggle]').disabled);
            toggle('group--Shops');
            await wait(() => row('group--Shops--p4'));
            check('search-after-load', shown() === 'group--Shops,group--Shops--p4,group--Shops--p6');
            check('both-copies-selected', row('group--Shops--p3').getAttribute('aria-selected') === 'true' &&
                row('group--Media--p3').getAttribute('aria-selected') === 'true');
            check('filter-wording', count() === '4 selected (4 hidden by the filter)' && inputs() === 'p1,p2,p3');
            search('');
            check('collapsed-wording', count() === '4 selected');
            // Sorting by amount applies to rows that load later.
            await regroup('party');
            check('party-again', count() === '3 selected (3 in collapsed groups)' && inputs() === 'p1,p2,p3');
            g().querySelectorAll('thead th')[2].click();
            toggle('group--Acme');
            await wait(() => row('group--Acme--p1'));
            const order = rows().filter(r => r.dataset.htmxoParent === 'row-group--Acme').map(r => r.id.slice(-2)).join(',');
            check('sorted-after-load', order === 'p7,p2,p1');
            // Expand all loads every lazy group.
            await regroup('iban');
            g().querySelector('.htmxo-tree-controls > button').click();
            await wait(() => !rows().some(r => 'htmxoLazyRows' in r.dataset));
            check('expand-all-loads', rows().filter(r => !r.hidden).length === rows().length && rows().length === 4 + 7);
            // Flat view: the same leaves, still selected; the query rides along.
            search('acme');
            await regroup('none');
            check('flat', rows().length === 7 && count() === '3 selected' && inputs() === 'p1,p2,p3' &&
                g().querySelector('input[type="search"]').value === 'acme' && shown() === 'p1,p2,p3,p7');
            // j/k move across group and leaf rows alike.
            search('');
            await regroup('rule');
            toggle('group--Media');
            const press = (el, k) => el.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true}));
            row('group--Media').focus();
            press(row('group--Media'), 'j');
            check('j-group-to-leaf', document.activeElement === row('group--Media--p3') && htmxoSelectedKeys('#g').join(',') === 'p3');
            press(document.activeElement, 'k');
            press(document.activeElement, 'k');
            check('k-leaf-to-groups', document.activeElement === row('group--Shops') && htmxoSelectedKeys('#g').join(',') === 'group:Shops');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(bulk, table("party"), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/table"
                html(table(q["group_by"], get(q, "q", "")))
            elseif uri.path == "/rows"
                html(table(q["group_by"], "", q["key"]))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 21
            end
        finally
            close(server)
        end
    end
end
