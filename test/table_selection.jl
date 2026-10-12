@testitem "selectable tables render grid selection semantics" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    html(x) = repr("text/html", x)
    tags(name, markup) = [m.match for m in eachmatch(Regex("<$(name)\\b[^>]*>"), markup)]
    row_c = h.tr(h.td("C"); data_htmxo_select_key="c", aria_selected="true")
    before = html(row_c)
    rows = [h.tr(h.td("A"); id="row-a"), h.tr(h.td("detail"); id="detail-a"),
            h.tr(h.td("B"); data_htmxo_select_key="b", data_htmxo_select_value="b-1"),
            row_c, h.tr(h.td("sub-header"))]
    out = html(sortable_table(["Name"], rows; selectable="rows", select_form="bulk", searchable=true))
    @test html(row_c) == before   # the caller's row is not modified
    @test contains(out, "data-htmxo-select=\"rows\"") && contains(out, "data-htmxo-select-form=\"bulk\"")
    @test contains(only(tags("table", out)), "aria-multiselectable=\"true\"")
    trs = tags("tr", out)
    selectable = filter(t -> contains(t, "aria-selected"), trs)
    @test length(selectable) == 3   # keyed rows only: not the detail or the unkeyed row
    @test all(t -> contains(t, "tabindex=\"-1\""), selectable)
    @test count(t -> contains(t, "aria-selected=\"true\""), selectable) == 1
    @test contains(out, "<small data-htmxo-selection-count=\"\" role=\"status\" aria-live=\"polite\">1 selected</small>")
    @test contains(out, "data-htmxo-select-all") && contains(out, "data-htmxo-select-clear")
    @test contains(out, "data-htmxo-selection-inputs")
    # The search field sits inside the selectable wrapper.
    @test findfirst("data-htmxo-select=", out)[1] < findfirst("type=\"search\"", out)[1]
    md = to_markdown_string(sortable_table(["Name"], rows[[1, 3]]; selectable="rows"))
    @test startswith(md, "| Name |\n| --- |\n") && !contains(md, "selected") && !contains(md, "Clear")
    # Refused: inputs without a name cannot be submitted (an unnamed input is not successful).
    @test_throws ArgumentError sortable_table(["Name"], rows; selectable="")
    # Refused: a form without a selection has nothing to submit.
    @test_throws ArgumentError sortable_table(["Name"], rows; select_form="bulk")

    items = [(; id="x:1", dup=false), (; id="x:2", dup=true)]
    flat = html(master_detail_table(["Name"], items; key=x -> x.id, master=x -> (h.td(x.id),),
        detail=x -> h.p("more"), selectable="ids", select_submit=x -> !x.dup))
    masters = filter(t -> contains(t, "id=\"row-"), tags("tr", flat))
    @test length(masters) == 2
    # A row click selects, so flat rows get the native Details control instead.
    @test all(t -> !contains(t, "onclick"), masters)
    @test count("data-htmxo-detail-toggle=\"\"", flat) == 2
    @test contains(flat, "data-htmxo-select-value=\"x:1\"")
    @test count("data-htmxo-select-submit=\"false\"", flat) == 1
    @test contains(only(tags("table", flat)), "aria-multiselectable=\"true\"")
    tree = html(master_detail_table(["Name"], [(; id="g", kids=[(; id="l", kids=[])])];
        key=x -> x.id, master=x -> (h.td(x.id),), children=x -> x.kids,
        detail_url=x -> isempty(x.kids) ? "/d/$(x.id)" : nothing, selectable="ids", select_value=x -> "v-$(x.id)"))
    @test contains(tree, "role=\"treegrid\"") && contains(tree, "data-htmxo-select-value=\"v-l\"")
    @test count("aria-selected=\"false\"", tree) == 2
    # Refused: per-row selection settings without a selection would be ignored silently.
    @test_throws ArgumentError master_detail_table(["Name"], items; key=x -> x.id,
        master=x -> (h.td(x.id),), detail=x -> "", select_value=x -> x.id)
end

@testitem "selectable table browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        records = [("a", "Alpha", 3), ("b", "Bravo", 1), ("c", "Charlie", 4), ("d", "Delta", 2), ("e", "Echo", 5)]
        row(k, name, n; selected=false) = h.tr(h.td(name), h.td(string(n)),
            h.td(k == "b" ? h.button("Act"; type="button", id="act-b") : "");
            id="row-$k", data_htmxo_select_key=k, data_htmxo_select_value="v-$k",
            (k == "e" ? (; data_htmxo_select_submit="false") : (;))...,
            (selected ? (; aria_selected="true") : (;))...)
        table(recs) = sortable_table(["Name", "N", ""], [row(r...; selected=r[1] == "c") for r in recs];
            id="sel", selectable="rows", select_form="bulk", searchable=true)
        md = master_detail_table(["Item"], ["one", "two"]; key=x -> "md-$x", master=x -> (h.td(x),),
            detail=x -> h.p("detail $x"), selectable="items")
        bulk = h.form(; id="bulk", hx_post="/bulk", hx_target="#bulk-out", hx_swap="innerHTML")(
            h.button("Archive"; id="archive", data_htmxo_needs_selection="rows", disabled=true))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const root = () => document.getElementById('sel').closest('[data-htmxo-select]');
            const row = k => document.getElementById('row-' + k);
            const selected = () => htmxoSelectedKeys('#sel').slice().sort().join(',');
            const inputs = () => Array.from(root().querySelectorAll('[data-htmxo-selection-inputs] > input')).map(i => i.value + '@' + i.getAttribute('form')).sort().join(',');
            const count = () => root().querySelector('[data-htmxo-selection-count]').textContent;
            const click = (el, mods = {}) => el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ...mods}));
            const key = (el, k, mods = {}) => el.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true, ...mods}));
            const events = [];
            document.addEventListener('htmxo:selection-changed', e => { if (e.detail.name === 'rows') events.push(e.detail); });
            await wait(() => inputs() !== '');
            check('initial-from-server', selected() === 'c' && count() === '1 selected' && inputs() === 'v-c@bulk');
            check('needs-selection-enabled', !document.getElementById('archive').disabled);
            check('roving-tabindex', root().querySelectorAll('tr[tabindex="0"]').length === 1);
            click(row('a').cells[0]);
            check('plain-click', selected() === 'a' && row('a').hasAttribute('data-htmxo-active'));
            check('click-focuses', document.activeElement === row('a'));
            click(row('c').cells[0], {ctrlKey: true});
            check('ctrl-toggle-add', selected() === 'a,c');
            click(row('a').cells[1], {metaKey: true});
            check('meta-toggle-remove', selected() === 'c');
            click(row('c').cells[0]);   // re-anchor on c
            click(row('e').cells[0], {shiftKey: true});
            check('shift-range', selected() === 'c,d,e');
            check('non-submit-row', inputs() === 'v-c@bulk,v-d@bulk' && count() === '3 selected');
            const down = new MouseEvent('mousedown', {bubbles: true, cancelable: true, shiftKey: true});
            row('d').cells[0].dispatchEvent(down);
            check('shift-mousedown-no-text-select', down.defaultPrevented);
            click(document.getElementById('act-b'));
            check('row-control-keeps-behaviour', selected() === 'c,d,e');
            // Keyboard on the focused row.
            row('a').focus();
            key(row('a'), 'ArrowDown');
            check('arrow-moves', selected() === 'b' && document.activeElement === row('b'));
            key(row('b'), 'ArrowDown', {shiftKey: true});
            check('shift-arrow-range', selected() === 'b,c');
            // j/k alias ↓/↑; Shift extends whatever the letter's case.
            key(row('c'), 'k');
            check('k-moves', selected() === 'b' && document.activeElement === row('b'));
            key(row('b'), 'j');
            check('j-moves', selected() === 'c' && document.activeElement === row('c'));
            key(row('c'), 'J', {shiftKey: true});
            check('shift-j-range', selected() === 'c,d' && document.activeElement === row('d'));
            key(row('d'), 'K', {shiftKey: true});
            key(row('c'), 'K', {shiftKey: true});
            check('shift-k-range', selected() === 'b,c' && document.activeElement === row('b'));
            key(row('b'), 'J');
            check('caps-lock-j-moves', selected() === 'c');
            key(row('c'), 'j', {ctrlKey: true});
            check('ctrl-j-ignored', selected() === 'c' && document.activeElement === row('c'));
            key(row('c'), 'a', {ctrlKey: true});
            check('ctrl-a-all-shown', selected() === 'a,b,c,d,e');
            key(row('c'), 'Escape');
            check('escape-collapses', selected() === 'c');
            key(row('c'), ' ');
            check('space-toggles-off', selected() === '' && count() === '0 selected');
            check('needs-selection-disabled', document.getElementById('archive').disabled);
            key(row('c'), 'Enter');
            check('enter-toggles-on', selected() === 'c');
            // Filter: "shown" excludes rows the search hides.
            root().querySelector('[data-htmxo-select-all]').click();
            const input = root().querySelector('input[type="search"]');
            input.value = 'arl'; input.dispatchEvent(new Event('input', {bubbles: true}));
            check('filtered-count', count() === '5 selected (4 hidden by the filter)');
            key(row('c'), 'a', {ctrlKey: true});
            check('ctrl-a-respects-filter', selected() === 'c');
            input.value = ''; input.dispatchEvent(new Event('input', {bubbles: true}));
            root().querySelector('[data-htmxo-select-clear]').click();
            check('clear', selected() === '');
            // Sorting keeps the keyed selection.
            htmxoSelectRows('#sel', ['a', 'd']);
            document.getElementById('sel').closest('table').tHead.rows[0].cells[1].querySelector('.htmxo-sort-control').click();
            const order = Array.from(document.getElementById('sel').rows).map(r => r.id).join(',');
            check('sorted', order === 'row-b,row-d,row-a,row-c,row-e');
            check('sort-keeps-selection', selected() === 'a,d' && row('a').getAttribute('aria-selected') === 'true');
            click(row('d').cells[0]);
            click(row('c').cells[0], {shiftKey: true});
            check('range-follows-sorted-order', selected() === 'a,c,d');
            const last = events[events.length - 1];
            check('event-detail', last.keys.slice().sort().join(',') === 'a,c,d' && last.submitted.length === 3 && last.hidden === 0);
            // The bulk form posts the inputs it owns through the form attribute.
            document.getElementById('archive').click();
            await wait(() => document.getElementById('bulk-out').textContent !== '');
            check('bulk-submit', document.getElementById('bulk-out').textContent === 'rows=v-a,v-c,v-d');
            // A row swapped by outerHTML keeps its selection.
            htmx.ajax('GET', '/row/a', {target: '#row-a', swap: 'outerHTML'});
            await wait(() => row('a') && row('a').cells[0].textContent === 'Alpha (new)');
            await wait(() => row('a').getAttribute('aria-selected') === 'true');
            check('row-swap-keeps-selection', row('a').getAttribute('aria-selected') === 'true' && selected() === 'a,c,d');
            // A table re-render keeps keys still present and drops the rest.
            htmx.ajax('GET', '/table', {target: root(), swap: 'outerHTML'});
            await wait(() => !row('d'));
            await wait(() => inputs() === 'v-a@bulk,v-c@bulk');
            check('rerender-keeps-present', selected() === 'a,c' && count() === '2 selected');
            // master_detail_table: row click selects, Details opens without selecting.
            const mdRow = document.getElementById('row-md-two');
            click(mdRow.cells[0]);
            check('md-row-selects', htmxoSelectedKeys(mdRow).join(',') === 'row-md-two' && document.getElementById('detail-md-two').hidden);
            mdRow.querySelector('[data-htmxo-detail-toggle]').click();
            check('md-details-button', !document.getElementById('detail-md-two').hidden && htmxoSelectedKeys(mdRow).join(',') === 'row-md-two');
            check('md-submits-key', mdRow.closest('[data-htmxo-select]').querySelector('[data-htmxo-selection-inputs] > input').value === 'md-two');
            check('separate-selections', selected() === 'a,c');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(bulk, h.div(; id="bulk-out"), table(records), md, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif path == "/bulk"
                form = HTTP.URIs.queryparampairs(String(req.body))
                HTTP.Response(200, ["Content-Type" => "text/html"],
                    "rows=" * join(sort([v for (k, v) in form if k == "rows"]), ","))
            elseif path == "/row/a"
                html(h.tr(h.td("Alpha (new)"), h.td("3"), h.td(""); id="row-a",
                    data_htmxo_select_key="a", data_htmxo_select_value="v-a", aria_selected="false", tabindex="-1"))
            elseif path == "/table"
                html(table(filter(r -> r[1] != "d", records)))
            else
                HTTP.Response(404)
            end
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
                @test count(==('\n'), checks[1]) + 1 == 38
            end
        finally
            close(server)
        end
    end
end
