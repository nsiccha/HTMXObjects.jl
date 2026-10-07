@testitem "hierarchical master detail rendering" tags=[:unit] begin
    using HTMXObjects
    leaf = (; key="leaf:a", name="A long complete leaf label", children=())
    group = (; key="group", name="Group", children=(leaf,))
    shared_cell = h.td("Original"; data_sort_value="kept")
    before = repr("text/html", shared_cell)
    node = master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> (shared_cell,), children=x -> x.children,
        detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing,
        initially_open=x -> x.key == "group", searchable=true, id="tree")
    html = repr("text/html", node)
    @test repr("text/html", shared_cell) == before
    @test contains(html, "role=\"treegrid\"")
    @test contains(html, "data-htmxo-parent=\"row-group\"")
    @test contains(html, "aria-level=\"2\"")
    @test contains(html, "data-htmxo-tree-open=\"true\"")
    @test contains(html, "data-htmxo-detail-open=\"false\"")
    @test contains(html, "aria-controls=\"row-leaf--a\"")
    @test contains(html, "aria-controls=\"detail-leaf--a\"")
    @test contains(html, "data-sort-value=\"kept\"")
    @test contains(html, "hx-get=\"/detail/leaf:a\"")
    @test !contains(html, "id=\"detail-group\"")
    @test !contains(html, "style=\"")
    @test contains(html, "type=\"button\"")
    @test contains(html, "type=\"search\"")
    @test contains(html, "class=\"htmxo-sort-control\"")
    @test contains(html, "No matching rows")
    @test !contains(html, "htmxo-md-load consume, load")
    pure = master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children)
    @test contains(repr("text/html", pure), "A long complete leaf label")
    # Refused: repeated DOM keys make parent identity and detail targets ambiguous.
    @test_throws ArgumentError master_detail_table(["Name"], [group, group];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children)
end

@testitem "master/detail rows keep the attributes of a <tr> from master" tags=[:unit] begin
    using HTMXObjects
    html(value) = repr("text/html", value)
    tags(name, markup) = [m.match for m in eachmatch(Regex("<$(name)\\b[^>]*>"), markup)]
    master_tag(markup) = only(t for t in tags("tr", markup) if contains(t, " id=\"row-"))

    # A row computed together with its cells keeps its attributes on the
    # master row the helper builds, beside the helper's own.
    row = h.tr(h.td("Alpha"), h.td("ok"); hx_target="#out", data_status="ok")
    before = html(row)
    master, detail = master_detail_pair("a", row, "body", 2; master_attrs=(; data_kind="leaf"))
    tag = master_tag(html(master))
    for attr in ("id=\"row-a\"", "aria-expanded=\"false\"", "onclick=", "hx-target=\"#out\"",
                 "data-status=\"ok\"", "data-kind=\"leaf\"")
        @test contains(tag, attr)
    end
    @test count("<td>", html(master)) == 2
    group = (; key="g", name="Group", children=((; key="l", name="Leaf", children=()),))
    tree = html(master_detail_table(["Name", "State"], [group];
        key=x -> x.key, master=x -> h.tr(h.td(x.name), h.td("ok"); data_status=x.key),
        children=x -> x.children, detail_url=x -> "/detail/$(x.key)",
        detail_toggle=:label, master_class="item", searchable=true))
    leaf = only(t for t in tags("tr", tree) if contains(t, " id=\"row-l\""))
    for attr in ("data-status=\"l\"", "data-htmxo-parent=\"row-g\"", "aria-level=\"2\"",
                 "class=\"item\"")
        @test contains(leaf, attr)
    end
    @test contains(tree, "data-htmxo-label")
    # The helper rebuilt the first cell for its label toggle from its own copy.
    @test html(row) == before

    # Refused: an attribute set twice for one row would silently keep
    # whichever was applied last (dev §1, no silent swallowing) — the helper's
    # pairing id and toggle, `master_class`, or `master_attrs` against the row.
    @test_throws "the master row's `id` is the helper's" master_detail_pair("a",
        h.tr(h.td("x"); id="mine"), "body", 1)
    @test_throws "`aria-level` is the helper's" master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> h.tr(h.td(x.name); aria_level="9"),
        children=x -> x.children)
    @test_throws "both `master_attrs` and the <tr> from `master` set the row's `data-status`" master_detail_table(
        ["Name"], [group]; key=x -> x.key, master=x -> h.tr(h.td(x.name); data_status="a"),
        master_attrs=x -> (; data_status="b"), detail=x -> "body")
    @test_throws "both `master_class` and the <tr> from `master` set the row's class" master_detail_pair(
        "a", h.tr(h.td("x"); class="mine"), "body", 1; master_class="item")
    # Refused: the master row is the helper's <tr>; another element in its
    # place has no cells to keep.
    @test_throws "must be the row's cells or one <tr>, got <td>" master_detail_pair(
        "a", h.td("x"), "body", 1)
end

@testitem "hierarchical master detail browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        leaf(k, name, score) = (; key=k, name, score, children=())
        group(k, name, children) = (; key=k, name, score=0, children)
        roots = [group("root-z", "Z family", (
                    group("builder-z", "Z builder", (leaf("leaf-z", "Z leaf", 20), leaf("leaf-a", "A leaf", 3))),
                    group("builder-a", "A builder", (leaf("leaf-b", "B leaf", 8),)))),
                 group("root-a", "A family", (leaf("leaf-c", "C leaf", 2),))]
        tree = master_detail_table(["Name", "Score"], roots;
            key=x -> x.key, master=x -> (h.td(x.name), h.td(x.score)),
            children=x -> x.children, searchable=true,
            initially_open=x -> startswith(x.key, "root-"),
            detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing,
            id="tree")
        plain = master_detail_table(["Name", "Score"], roots;
            key=x -> "plain-$(x.key)", master=x -> (h.td(x.name), h.td(x.score)),
            children=x -> x.children, searchable=true,
            branches_collapsible=false, detail_toggle=:label,
            detail_url=x -> isempty(x.children) ? "/detail/plain-$(x.key)" : nothing,
            id="plain")
        flat = master_detail_table(["Name"], ["Z", "A"];
            key=x -> "flat-$x", master=x -> (h.td(x),), detail=x -> h.p(x), id="flat")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const row = key => document.getElementById('row-' + key);
            const tree = document.getElementById('tree');
            const input = tree.closest('.htmxo-searchable-table').querySelector('input');
            const filter = value => { input.value = value; input.dispatchEvent(new Event('input', {bubbles:true})); };
            const ids = () => Array.from(tree.rows).map(r => r.id).join(',');
            const sort = col => tree.closest('table').tHead.rows[0].cells[col].querySelector('.htmxo-sort-control').click();
            const toggle = key => row(key).querySelector('[data-htmxo-tree-toggle]').click();
            check('initial-branch', !row('builder-z').hidden && row('leaf-z').hidden);
            check('initial-lazy', !document.querySelector('[data-loaded="1"]'));
            toggle('builder-z');
            check('branch-open', !row('leaf-z').hidden);
            row('leaf-a').querySelector('[data-htmxo-detail-toggle]').click();
            // Wait for the real lazy HTTP result, independent of wall-clock JIT.
            for (let n=0; n<100 && !document.getElementById('loaded-leaf-a'); n++)
                await new Promise(resolve => setTimeout(resolve, 20));
            check('lazy-loaded', !!document.getElementById('loaded-leaf-a'));
            const slot = document.getElementById('detail-slot-leaf-a');
            sort(0);
            check('sort-button-once', tree.closest('table').tHead.rows[0].cells[0].getAttribute('aria-sort') === 'ascending');
            check('preorder-sort', ids() === 'row-root-a,row-leaf-c,detail-leaf-c,row-root-z,row-builder-a,row-leaf-b,detail-leaf-b,row-builder-z,row-leaf-a,detail-leaf-a,row-leaf-z,detail-leaf-z');
            check('paired-after-sort', row('leaf-a').nextElementSibling.id === 'detail-leaf-a');
            check('dom-preserved', document.getElementById('detail-slot-leaf-a') === slot);
            sort(1);
            check('numeric-siblings', row('leaf-a').nextElementSibling.nextElementSibling === row('leaf-z'));
            sort(1);
            check('descending-siblings', row('leaf-z').nextElementSibling.nextElementSibling === row('leaf-a'));
            filter('B LEAF');
            check('search-ancestors', !row('root-z').hidden && !row('builder-a').hidden && !row('leaf-b').hidden);
            check('search-omits-other', row('leaf-a').hidden && row('root-a').hidden);
            check('search-hides-detail', document.getElementById('detail-leaf-a').hidden);
            row('leaf-b').querySelector('[data-htmxo-detail-toggle]').click();
            for (let n=0; n<100 && !document.getElementById('loaded-leaf-b'); n++)
                await new Promise(resolve => setTimeout(resolve, 20));
            check('expand-after-filter', !document.getElementById('detail-leaf-b').hidden && !!document.getElementById('loaded-leaf-b'));
            filter('Z family');
            check('group-search', !row('leaf-a').hidden && !row('leaf-b').hidden && row('root-a').hidden);
            filter('');
            check('clear-restores-branches', row('leaf-b').hidden && !row('leaf-a').hidden);
            check('clear-restores-detail', !document.getElementById('detail-leaf-a').hidden);
            toggle('builder-z');
            check('collapse-hides-open-detail', row('leaf-a').hidden && document.getElementById('detail-leaf-a').hidden);
            toggle('builder-z');
            check('reopen-restores-detail', !document.getElementById('detail-leaf-a').hidden && document.getElementById('detail-slot-leaf-a') === slot);
            filter('no-such-row');
            check('empty-state', !tree.closest('.htmxo-searchable-table').querySelector('[data-htmxo-table-empty]').hidden);
            filter('');
            const flat = document.getElementById('flat');
            flat.closest('table').tHead.rows[0].cells[0].click();
            check('flat-pair-sort', Array.from(flat.rows).map(r=>r.id).join(',') === 'row-flat-A,detail-flat-A,row-flat-Z,detail-flat-Z');
            check('sort-state', htmxoSortState(tree).sort_col === 2 && htmxoSortState(tree).sort_dir === 'desc');
            const plain = document.getElementById('plain');
            const masters = Array.from(plain.rows).filter(r=>r.id.startsWith('row-'));
            check('plain-all-branches-expanded', masters.every(r=>!r.hidden));
            check('plain-no-disclosure', !plain.querySelector('[data-htmxo-tree-toggle]'));
            check('plain-no-group-details', !document.getElementById('detail-plain-root-z'));
            const label = row('plain-leaf-a').querySelector('[data-htmxo-detail-toggle]');
            check('plain-native-label', label.tagName==='BUTTON' && label.textContent==='A leaf' && label.getAttribute('aria-expanded')==='false');
            label.click();
            for (let n=0; n<100 && !document.getElementById('loaded-plain-leaf-a'); n++)
                await new Promise(resolve=>setTimeout(resolve,20));
            const loaded = document.getElementById('loaded-plain-leaf-a');
            check('plain-label-loads', !!loaded && label.getAttribute('aria-expanded')==='true');
            label.click();
            check('plain-label-collapses', document.getElementById('detail-plain-leaf-a').hidden && label.getAttribute('aria-expanded')==='false');
            label.click();
            check('plain-reopen-keeps-dom', document.getElementById('loaded-plain-leaf-a')===loaded && !document.getElementById('detail-plain-leaf-a').hidden);
            plain.closest('table').tHead.rows[0].cells[0].querySelector('.htmxo-sort-control').click();
            check('plain-sort-keeps-companion', row('plain-leaf-a').nextElementSibling.id==='detail-plain-leaf-a' && document.getElementById('loaded-plain-leaf-a')===loaded);
            const plainInput = plain.closest('.htmxo-searchable-table').querySelector('input');
            plainInput.value='B leaf'; plainInput.dispatchEvent(new Event('input'));
            check('plain-search-hides-detail', row('plain-leaf-a').hidden && document.getElementById('detail-plain-leaf-a').hidden && !row('plain-leaf-b').hidden);
            plainInput.value=''; plainInput.dispatchEvent(new Event('input'));
            check('plain-clear-restores-all', masters.every(r=>!r.hidden) && !document.getElementById('detail-plain-leaf-a').hidden && document.getElementById('loaded-plain-leaf-a')===loaded);
            const result = document.createElement('pre'); result.id='checks';
            result.textContent = checks.map(([name,ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(tree, plain, flat, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        requests = Dict{String,Int}()
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif startswith(path, "/detail/")
                requests[path] = get(requests, path, 0) + 1
                key = split(path, '/')[end]
                HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"loaded-$key\">loaded</p>")
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
            end
            @test get(requests, "/detail/leaf-a", 0) == 1
            @test get(requests, "/detail/leaf-b", 0) == 1
            @test get(requests, "/detail/leaf-z", 0) == 0
            @test get(requests, "/detail/leaf-c", 0) == 0
            @test get(requests, "/detail/plain-leaf-a", 0) == 1
            @test get(requests, "/detail/plain-leaf-b", 0) == 0
        finally
            close(server)
        end
    end
end
