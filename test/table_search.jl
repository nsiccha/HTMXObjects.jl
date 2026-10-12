@testitem "sortable_table searchable renders the shared search scaffold" tags=[:unit] begin
    using HTMXObjects, Tables
    import HTMXObjects: to_markdown_string
    rows = [h.tr(h.td("Alpha"), h.td("1"); id="row-a"), h.tr(h.td("detail"); id="detail-a"),
            h.tr(h.td("Beta"), h.td("2"); id="row-b", data_htmxo_search="beta extra"),
            h.tr(h.td("Gamma"), h.td("3"); hidden=true)]
    html = repr("text/html", sortable_table(["Name", "N"], rows; searchable=true, id="t"))
    @test contains(html, "class=\"htmxo-searchable-table\"")
    @test contains(html, "type=\"search\"")
    @test contains(html, "aria-label=\"Search\"")
    # Detail companions are not counted; a row rendered hidden is not shown.
    @test contains(html, "<small data-htmxo-table-count=\"\" role=\"status\" aria-live=\"polite\">2 of 3 rows shown</small>")
    @test contains(html, "No matching rows")
    @test contains(html, "data-htmxo-search=\"beta extra\"")
    # The count is the live region; the empty state is not a second one.
    @test count("role=\"status\"", html) == 1
    md = to_markdown_string(sortable_table(["Name", "N"], rows[[1, 3]]; searchable=true))
    @test startswith(md, "| Name | N |\n| --- | --- |\n")
    @test !contains(md, "Search") && !contains(md, "rows shown") && !contains(md, "No matching rows")
    # Off by default: no scaffold.
    @test !contains(repr("text/html", sortable_table(["Name"], rows[1:1])), "htmxo-searchable-table")
    # The search wraps the captioned/downloadable frame, not the bare table.
    framed = repr("text/html", sortable_table(["Name"], rows[1:1]; searchable=true, download=true))
    @test findfirst("type=\"search\"", framed)[1] < findfirst("<figure", framed)[1]
    # render_table forwards `searchable` and stamps `search_text(row)`.
    rt = repr("text/html", render_table((name=["x", "y"], n=[1, 2]); download=false,
        searchable=true, search_text=row -> "item $(row.name)"))
    @test contains(rt, "data-htmxo-search=\"item x\"") && contains(rt, "2 of 2 rows shown")
end

@testitem "master_detail_table search shares the count" tags=[:unit] begin
    using HTMXObjects
    leaf(k) = (; key=k, children=())
    roots = [(; key="g", children=(leaf("l1"), leaf("l2"))), leaf("solo")]
    tree(; kw...) = repr("text/html", master_detail_table(["Name"], roots;
        key=x -> x.key, master=x -> (h.td(x.key),), children=x -> x.children,
        detail_url=x -> "/d/$(x.key)", kw...))
    # Collapsed children are rendered hidden, so the first paint counts them out.
    @test contains(tree(searchable=true), "2 of 4 rows shown")
    @test contains(tree(searchable=true, initially_open=true), "4 of 4 rows shown")
    # Without `searchable`, a hierarchy keeps a hidden scaffold for its toggles.
    @test contains(tree(), "<label hidden")
    flat = repr("text/html", master_detail_table(["Name"], ["a", "b", "c"];
        key=identity, master=x -> (h.td(x),), detail=x -> h.p(x), searchable=true))
    @test contains(flat, "3 of 3 rows shown")
end

@testitem "sortable_table search browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        items = [("zeta", "Zeta Corp", "Unassigned", 30), ("alpha", "Alpha GmbH", "Rent", 10),
                 ("beta", "Beta Ltd", "Unassigned", 20), ("gamma", "Gamma AG", "Travel", 5)]
        rows = Any[]
        for (k, name, tac, n) in items
            push!(rows, h.tr(h.td(name), h.td(tac), h.td(string(n)); id="row-$k", data_tac=tac,
                onclick="this.nextElementSibling.hidden = !this.nextElementSibling.hidden"))
            push!(rows, h.tr(h.td(h.p("detail $k"); colspan=3); id="detail-$k", hidden=true))
        end
        push!(rows, h.tr(h.td("Delta"), h.td("Rent"), h.td("1"); data_htmxo_search="hidden-keyword"))
        flat = sortable_table(["Name", "TAC", "N"], rows; searchable=true, id="flat")
        md = master_detail_table(["Name"], ["Red", "Green", "Blue"];
            key=x -> "md-$x", master=x -> (h.td(x),), detail=x -> h.p(x), searchable=true, id="md")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const tbody = document.getElementById('flat');
            const root = tbody.closest('.htmxo-searchable-table');
            const input = root.querySelector('input[type="search"]');
            const count = () => root.querySelector('[data-htmxo-table-count]').textContent;
            const row = k => document.getElementById('row-' + k);
            const filter = v => { input.value = v; input.dispatchEvent(new Event('input', {bubbles: true})); };
            const shown = () => Array.from(tbody.rows).filter(r => !r.hidden && !r.id.startsWith('detail-'));
            const events = [];
            document.addEventListener('htmxo:table-filtered', e => events.push(e.detail));
            check('initial-count', count() === '5 of 5 rows shown');
            row('beta').click();
            check('detail-open', !document.getElementById('detail-beta').hidden);
            filter('  ALPHA   gmbh ');
            check('phrase-match', shown().length === 1 && !row('alpha').hidden && row('zeta').hidden);
            check('count-updates', count() === '1 of 5 rows shown');
            check('detail-hides-with-master', document.getElementById('detail-beta').hidden);
            check('empty-hidden', root.querySelector('[data-htmxo-table-empty]').hidden);
            filter('hidden-keyword');
            check('search-attribute', shown().length === 1 && shown()[0].cells[0].textContent === 'Delta');
            filter('nothing-matches');
            check('empty-state', !root.querySelector('[data-htmxo-table-empty]').hidden && count() === '0 of 5 rows shown');
            filter('unassigned');
            const header = tbody.closest('table').tHead.rows[0].cells[2];
            header.querySelector('.htmxo-sort-control').click();
            const order = Array.from(tbody.rows).map(r => r.id).filter(Boolean).join(',');
            check('sort-keeps-pairs', order === 'row-gamma,detail-gamma,row-alpha,detail-alpha,row-beta,detail-beta,row-zeta,detail-zeta');
            check('sort-keeps-filter', count() === '2 of 5 rows shown' && shown().length === 2 && row('alpha').hidden);
            filter('');
            check('clear-restores-detail', !document.getElementById('detail-beta').hidden);
            // App predicates compose with the phrase search.
            htmxoTableFilter(tbody, 'unassigned', r => r.dataset.tac === 'Unassigned');
            check('predicate', shown().length === 2 && !row('zeta').hidden && !row('beta').hidden);
            filter('beta');
            check('predicate-and-phrase', shown().length === 1 && !row('beta').hidden);
            filter('');
            const last = events[events.length - 1];
            check('event-detail', last.shown === 2 && last.total === 5 && last.query === '' && last.hiddenBy.unassigned === 3);
            // A listener's notes ride the count line.
            const note = e => { const n = e.detail.hiddenBy.unassigned; if (n) e.detail.notes.push(n + ' categorized hidden'); };
            document.addEventListener('htmxo:table-filtered', note);
            htmxoFilterTable(input);
            check('notes', count() === '2 of 5 rows shown · 3 categorized hidden');
            document.removeEventListener('htmxo:table-filtered', note);
            htmxoTableFilter('#flat', 'unassigned', null);
            check('predicate-removed', shown().length === 5 && count() === '5 of 5 rows shown');
            // Registering 'search' replaces the phrase match, e.g. a regex mode.
            htmxoTableFilter(root, 'search', (r, ctx) => !ctx.input || new RegExp(ctx.input, 'i').test(ctx.text));
            filter('^(zeta|gamma)\\b');
            check('replace-search', shown().length === 2 && !row('zeta').hidden && !row('gamma').hidden);
            check('replace-hidden-by', events[events.length - 1].hiddenBy.search === 3);
            htmxoTableFilter(root, 'search', null);
            filter('zeta');
            check('restored-phrase', shown().length === 1);
            filter('');
            // master_detail_table shares the same scaffold and count.
            const mdRoot = document.getElementById('md').closest('.htmxo-searchable-table');
            const mdInput = mdRoot.querySelector('input[type="search"]');
            mdInput.value = 're'; mdInput.dispatchEvent(new Event('input'));
            check('md-count', mdRoot.querySelector('[data-htmxo-table-count]').textContent === '2 of 3 rows shown');
            check('md-label-name', mdInput.labels[0].textContent.startsWith('Search') && mdInput.getAttribute('aria-label') === 'Search');
            let threw = false;
            try { htmxoTableFilter('#no-such-table', 'x', () => true); } catch (_) { threw = true; }
            check('missing-target-throws', threw);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(flat, md, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()), pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ?
                HTTP.Response(200, ["Content-Type" => "text/html"], page) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
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

@testitem "table search survives a re-render browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        recs = [("rewe", "REWE Markt", "Groceries"), ("aldi", "ALDI Süd", "Groceries"),
                ("db", "Deutsche Bahn", "Travel"), ("ikea", "IKEA", "Home")]
        row(k, name, cat) = h.tr(h.td(name), h.td(cat); id="row-$k", data_htmxo_select_key=k, data_cat=cat)
        rules(; script=nothing) = h.div(; id="rules-panel")(
            sortable_table(["Name", "Category"], [row(r...) for r in recs];
                id="rules", searchable=true, selectable="selected_rules"),
            (isnothing(script) ? () : (h.script(Raw(script)),))...)
        anon() = h.div(; id="anon-panel")(sortable_table(["Name", "Category"], [row("a" * r[1], r[2], r[3]) for r in recs]; searchable=true))
        tree() = master_detail_table(["Name"], ["Groceries", "Travel"]; key=x -> "g-$x",
            master=x -> (h.td(x),), children=x -> x == "Groceries" ? ["REWE", "ALDI"] : x == "Travel" ? ["DB"] : String[],
            searchable=true, id="tree")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const root = id => document.getElementById(id).closest('.htmxo-searchable-table');
            const input = id => root(id).querySelector('input[type="search"]');
            const count = id => root(id).querySelector('[data-htmxo-table-count]').textContent;
            const shown = id => Array.from(document.getElementById(id).rows).filter(r => !r.hidden).map(r => r.id).join(',');
            const type = (id, v) => { input(id).value = v; input(id).dispatchEvent(new Event('input', {bubbles: true})); };
            const rerender = async (url, target, id) => {
                const old = document.getElementById(id);
                htmx.ajax('GET', url, {target, swap: 'outerHTML'});
                await wait(() => document.getElementById(id) && document.getElementById(id) !== old);
                await new Promise(r => setTimeout(r, 50));
            };
            // The user's query survives the re-render, as the selection does.
            type('rules', 'rewe');
            htmxoSelectRows('#rules', ['rewe', 'db']);
            check('typed', shown('rules') === 'row-rewe' && count('rules') === '1 of 4 rows shown');
            await rerender('/rules', '#rules-panel', 'rules');
            check('query-restored', input('rules').value === 'rewe');
            check('filter-reapplied', shown('rules') === 'row-rewe' && count('rules') === '1 of 4 rows shown');
            check('selection-with-filter', htmxoSelectedKeys('#rules').join(',') === 'rewe,db' &&
                root('rules').closest('[data-htmxo-select]').querySelector('[data-htmxo-selection-count]').textContent === '2 selected (1 hidden by the filter)');
            // An app predicate registered outside the swapped region survives too.
            type('rules', '');
            htmxoTableFilter('#rules', 'cat', r => r.dataset.cat === 'Groceries');
            check('predicate', shown('rules') === 'row-rewe,row-aldi');
            await rerender('/rules', '#rules-panel', 'rules');
            check('predicate-restored', input('rules').value === '' && shown('rules') === 'row-rewe,row-aldi' && count('rules') === '2 of 4 rows shown');
            // Content that registers the same name when swapped in replaces it.
            await rerender('/rules?script=1', '#rules-panel', 'rules');
            check('reregister-replaces', shown('rules') === 'row-db');
            htmxoTableFilter('#rules', 'cat', null);
            check('predicate-removed', shown('rules') === 'row-rewe,row-aldi,row-db,row-ikea');
            // A value the re-rendered field already holds wins over the stored query.
            type('rules', 'ikea');
            await rerender('/rules?value=aldi', '#rules-panel', 'rules');
            check('rendered-value-wins', input('rules').value === 'aldi' && shown('rules') === 'row-aldi');
            await rerender('/rules', '#rules-panel', 'rules');
            check('rendered-value-stored', input('rules').value === 'aldi');
            // Clearing the field clears what a re-render restores.
            type('rules', '');
            await rerender('/rules', '#rules-panel', 'rules');
            check('cleared-stays-clear', input('rules').value === '' && count('rules') === '4 of 4 rows shown');
            // htmxoTableSearch sets the query; swapped-in content can use it to start over.
            htmxoTableSearch('#rules', 'deutsche');
            check('set-query', input('rules').value === 'deutsche' && shown('rules') === 'row-db');
            await rerender('/rules?clear=1', '#rules-panel', 'rules');
            check('swapped-in-clear', input('rules').value === '' && count('rules') === '4 of 4 rows shown');
            await rerender('/rules', '#rules-panel', 'rules');
            check('clear-stored', input('rules').value === '');
            // A table without an id keeps the state on its wrapper: a swap drops it.
            const anonInput = () => document.querySelector('#anon-panel input[type="search"]');
            anonInput().value = 'rewe'; anonInput().dispatchEvent(new Event('input', {bubbles: true}));
            const oldAnon = document.querySelector('#anon-panel table');
            htmx.ajax('GET', '/anon', {target: '#anon-panel', swap: 'outerHTML'});
            await wait(() => document.querySelector('#anon-panel table') !== oldAnon);
            await new Promise(r => setTimeout(r, 50));
            check('no-id-not-kept', anonInput().value === '');
            // A hierarchy keeps its query and matching path.
            type('tree', 'aldi');
            check('tree-typed', shown('tree') === 'row-g-Groceries,row-g-ALDI');
            await rerender('/tree', root('tree'), 'tree');
            check('tree-restored', input('tree').value === 'aldi' && shown('tree') === 'row-g-Groceries,row-g-ALDI');
            // The state is per page path.
            type('rules', 'rewe');
            history.replaceState(null, '', '/elsewhere');
            await rerender('/rules', '#rules-panel', 'rules');
            check('other-path-fresh', input('rules').value === '' && count('rules') === '4 of 4 rows shown');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(rules(), anon(), tree(), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], x isa String ? x : repr("text/html", x))
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/rules"
                body = repr("text/html", rules(; script=haskey(q, "script") ?
                    "htmxoTableFilter('#rules', 'cat', r => r.dataset.cat === 'Travel');" :
                    haskey(q, "clear") ? "htmxoTableSearch('#rules', '');" : nothing))
                html(haskey(q, "value") ? replace(body, "<input type=\"search\"" => "<input type=\"search\" value=\"$(q["value"])\"") : body)
            elseif uri.path == "/anon"
                html(anon())
            elseif uri.path == "/tree"
                html(tree())
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 18
            end
        finally
            close(server)
        end
    end
end
