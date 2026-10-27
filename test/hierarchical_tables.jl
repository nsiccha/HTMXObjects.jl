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
    @test contains(html, "onclick=\"htmxoTreeRow(this,event)\"")
    @test contains(html, "data-htmxo-tree-label=\"\"")
    @test !contains(html, "aria-label=\"Toggle child rows\"")
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
    linked_group = (; key="linked", name="Group link", children=(leaf,))
    linked = repr("text/html", master_detail_table(["Name"], [linked_group];
        key=x -> x.key, master=x -> (h.td(x.key == "linked" ? h.a(x.name; href="/group") : x.name),),
        children=x -> x.children, detail_url=x -> isempty(x.children) ? "/detail/$(x.key)" : nothing))
    @test contains(linked, "aria-label=\"Toggle child rows\"")
    @test !contains(linked, "data-htmxo-tree-label=\"\"")
    @test contains(linked, "onclick=\"htmxoTreeRow(this,event)\"")
    pure = master_detail_table(["Name"], [group];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children)
    @test contains(repr("text/html", pure), "A long complete leaf label")
    # Refused: repeated DOM keys make parent identity and detail targets ambiguous.
    @test_throws ArgumentError master_detail_table(["Name"], [group, group];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children)
end

@testitem "initially_open opens a branch's child rows, not its own detail" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    tr(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>"), page).match
    control(page, key) = match(Regex("<button[^>]*aria-controls=\"detail-$key\"[^>]*>"), page).match
    leaf = (; key="clause", name="Clause", children=())
    branch = (; key="section", name="Section", children=(leaf,))
    tree(; kw...) = html(master_detail_table(["Name"], [branch];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail=x -> h.p("detail of $(x.key)"), id="tree", kw...))
    # A section that starts expanded shows its clauses; its own detail (a live
    # demo, say) stays closed, as after a click on its row or Expand all.
    page = tree(initially_open=x -> x.key == "section")
    @test contains(tr(page, "row-section"), "data-htmxo-tree-open=\"true\"")
    @test contains(tr(page, "row-section"), "aria-expanded=\"true\"")
    @test contains(tr(page, "row-section"), "data-htmxo-detail-open=\"false\"")
    @test contains(control(page, "section"), "aria-expanded=\"false\"")
    @test contains(tr(page, "detail-section"), "hidden")
    @test !contains(tr(page, "row-clause"), "hidden") && contains(tr(page, "detail-clause"), "hidden")
    # A leaf has nothing else to open: initially_open opens its detail.
    every = tree(initially_open=true)
    @test contains(tr(every, "detail-section"), "hidden")
    @test contains(tr(every, "row-clause"), "data-htmxo-detail-open=\"true\"")
    @test !contains(tr(every, "detail-clause"), "hidden")
    # Branches that cannot collapse open their detail, which a click on their row opens.
    fixed = tree(branches_collapsible=false, initially_open=x -> x.key == "section")
    @test contains(tr(fixed, "row-section"), "data-htmxo-detail-open=\"true\"")
    @test !contains(tr(fixed, "detail-section"), "hidden")
    # A lazy branch detail loads only when asked for.
    lazy = html(master_detail_table(["Name"], [branch];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail_url=x -> isempty(x.children) ? nothing : "/demo/$(x.key)", initially_open=true))
    @test contains(lazy, "hx-get=\"/demo/section\"") && !contains(lazy, "htmxo-md-load consume, load")
    @test contains(tr(lazy, "detail-section"), "hidden")
    # A flat table opens its rows' details as before.
    flat = html(master_detail_table(["Name"], ["a", "b"];
        key=identity, master=x -> (h.td(x),), detail=x -> h.p(x), initially_open=x -> x == "a"))
    @test !contains(tr(flat, "detail-a"), "hidden") && contains(tr(flat, "detail-b"), "hidden")
end

@testitem "initially_open_detail opens details apart from branches" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    tr(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>"), page).match
    leaf = (; key="clause", name="Clause", children=())
    branch = (; key="section", name="Section", children=(leaf,))
    tree(; kw...) = html(master_detail_table(["Name"], [branch];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail=x -> h.p("detail of $(x.key)"), id="tree", kw...))
    # Every combination of a branch's child rows and its own detail.
    for rows_open in (false, true), detail_open in (false, true)
        page = tree(initially_open=x -> rows_open && x.key == "section",
                    initially_open_detail=x -> detail_open && x.key == "section")
        @test contains(tr(page, "row-section"), "data-htmxo-tree-open=\"$rows_open\"")
        @test contains(tr(page, "row-section"), "data-htmxo-detail-open=\"$detail_open\"")
        @test contains(tr(page, "detail-section"), "hidden") == !detail_open
        @test contains(tr(page, "row-clause"), "hidden") == !rows_open
    end
    # Given, it decides every row's detail: a leaf that initially_open reveals keeps its detail closed.
    shown = tree(initially_open=true, initially_open_detail=false)
    @test !contains(tr(shown, "row-clause"), "hidden")
    @test contains(tr(shown, "row-clause"), "data-htmxo-detail-open=\"false\"")
    @test contains(tr(shown, "detail-clause"), "hidden")
    # A Boolean opens every detail, a lazy one loading on first paint.
    lazy = html(master_detail_table(["Name"], [branch];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail_url=x -> "/demo/$(x.key)", initially_open_detail=true))
    @test !contains(tr(lazy, "detail-section"), "hidden") && contains(lazy, "htmxo-md-load consume, load")
    # The predicate is asked only about rows with a detail.
    asked = Any[]
    html(master_detail_table(["Name"], [branch];
        key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
        detail=x -> isempty(x.children) ? h.p("clause") : nothing,
        initially_open_detail=x -> (push!(asked, x.key); false)))
    @test asked == ["clause"]
    # Flat tables take it too.
    flat = html(master_detail_table(["Name"], ["a", "b"];
        key=identity, master=x -> (h.td(x),), detail=x -> h.p(x), initially_open_detail=x -> x == "b"))
    @test contains(tr(flat, "detail-a"), "hidden") && !contains(tr(flat, "detail-b"), "hidden")
end

@testitem "multilevel table headers" tags=[:unit] begin
    using HTMXObjects
    headers = ["Model", "Ratio", "Wren", "RKPPL", "Ratio", "Wren", "RKPPL"]
    rows = [h.tr((h.td(string(i)) for i in 1:7)...)]
    grouped = sortable_table(headers, rows;
        header_groups=["Primal" => 2:4, "Gradient" => 5:7],
        default_sort=3 => :asc)
    html = repr("text/html", grouped)
    @test contains(html, "rowspan=\"2\"")
    @test contains(html, "colspan=\"3\"")
    @test contains(html, "scope=\"colgroup\"")
    @test contains(html, "data-htmxo-sort-col=\"3\"")
    @test contains(html, "data-sort-dir=\"asc\"")
    @test contains(repr("text/markdown", grouped),
        "| Model | Primal / Ratio | Primal / Wren | Primal / RKPPL | Gradient / Ratio |")
    @test_throws ArgumentError sortable_table(headers, rows;
        header_groups=["Primal" => 2:4, "Overlap" => 4:6])
    @test_throws ArgumentError sortable_table(headers, rows;
        header_groups=["Invalid" => 2:2])
    @test_throws ErrorException sortable_table(headers, rows;
        header_groups=["Primal" => 2:4, "Gradient" => 5:7], default_sort="Ratio")
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

@testitem "hierarchical master detail browser" setup=[ChromeDump] tags=[:unit, :browser] begin
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
            key=x -> x.key, master=x -> (h.td(x.key == "root-a" ? h.a(x.name; href="#family") : x.name), h.td(x.score)),
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
        dual = master_detail_table(["Name"], [group("dual-parent", "Parent", (leaf("dual-child", "Child", 1),))];
            key=x -> x.key, master=x -> (h.td(x.name),), children=x -> x.children,
            detail=x -> h.p("Detail $(x.name)"), id="dual")
        # A flat table whose first cell is a link, with a caller's extension
        # concatenated onto the row toggle.
        linked = master_detail_table(["Invoice", "Amount"], ["B", "A"];
            key=x -> "linked-$x", master=x -> (h.td(h.a("$x-link"; href="#inv-$x")), h.td(x == "A" ? "1" : "2")),
            detail=x -> h.p("detail $x"), initially_open=x -> x == "A",
            master_attrs=x -> (; onclick=HTMXObjects.master_detail_toggle_js("linked-$x") *
                "window.__ext=(window.__ext||0)+1;"),
            id="linked", download=true)
        grouped = sortable_table(["Model", "Ratio", "Wren", "RKPPL",
                                  "Ratio", "Wren", "RKPPL"],
            [h.tr(h.td("B"), h.td("0.8"), h.td("4"), h.td("5"), h.td("0.7"), h.td("9"), h.td("2")),
             h.tr(h.td("A"), h.td("0.7"), h.td("3"), h.td("4"), h.td("0.6"), h.td("8"), h.td("1"))];
            id="grouped", download=true,
            header_groups=["Primal" => 2:4, "Gradient" => 5:7])
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
            check('initial-branch', !row('builder-z').hidden && row('leaf-z').hidden);
            row('root-a').querySelector('a').click();
            check('branch-link-keeps-children', !row('leaf-c').hidden &&
                row('root-a').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-expanded') === 'true');
            check('branch-label-control', row('builder-z').querySelector('[data-htmxo-tree-toggle]').textContent === 'Z builder' &&
                row('builder-z').querySelectorAll('[data-htmxo-tree-toggle]').length === 1);
            const leafControl = row('leaf-a').querySelector('[data-htmxo-detail-toggle]');
            check('leaf-label-control', leafControl.textContent === 'A leaf' &&
                leafControl.closest('[data-htmxo-row-label]') !== null &&
                row('leaf-a').querySelectorAll('[data-htmxo-detail-toggle]').length === 1);
            check('leaf-label-unfilled', getComputedStyle(leafControl).backgroundColor === 'rgba(0, 0, 0, 0)' &&
                getComputedStyle(leafControl).borderTopWidth === '0px');
            check('initial-lazy', !document.querySelector('[data-loaded="1"]'));
            row('builder-z').click();
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
            row('builder-z').click();
            check('collapse-hides-open-detail', row('leaf-a').hidden && document.getElementById('detail-leaf-a').hidden);
            row('builder-z').click();
            check('reopen-restores-detail', !document.getElementById('detail-leaf-a').hidden && document.getElementById('detail-slot-leaf-a') === slot);
            filter('no-such-row');
            check('empty-state', !tree.closest('.htmxo-searchable-table').querySelector('[data-htmxo-table-empty]').hidden);
            filter('');
            const flat = document.getElementById('flat');
            flat.closest('table').tHead.rows[0].cells[0].click();
            check('flat-pair-sort', Array.from(flat.rows).map(r=>r.id).join(',') === 'row-flat-A,detail-flat-A,row-flat-Z,detail-flat-Z');
            const linked = document.getElementById('linked');
            const detailB = document.getElementById('detail-linked-B');
            const control = row('linked-B').querySelector('[data-htmxo-detail-toggle]');
            check('linked-controls', linked.querySelectorAll('[aria-controls]').length === 2);
            check('linked-open-glyph', row('linked-A').querySelector('[data-htmxo-detail-toggle]').textContent === '▾');
            // An open row's ▾ must not reorder it: the sort key is the cell's content.
            linked.closest('table').tHead.rows[0].cells[0].querySelector('.htmxo-sort-control').click();
            check('linked-sort-label', Array.from(linked.rows).map(r=>r.id).join(',') === 'row-linked-A,detail-linked-A,row-linked-B,detail-linked-B');
            control.focus();
            check('linked-control-focus', document.activeElement === control && control.tabIndex === 0 && control.tagName === 'BUTTON');
            check('linked-control-closed', detailB.hidden && control.getAttribute('aria-expanded') === 'false' && control.textContent === '▸');
            control.click();
            check('linked-control-opens', !detailB.hidden && control.getAttribute('aria-expanded') === 'true' && row('linked-B').getAttribute('aria-expanded') === 'true' && control.textContent === '▾');
            check('linked-control-extension', window.__ext === 1);
            row('linked-B').querySelector('a').click();
            check('linked-link-keeps-detail', !detailB.hidden && window.__ext === 1);
            row('linked-B').click();
            check('linked-row-click', detailB.hidden && control.getAttribute('aria-expanded') === 'false' && control.textContent === '▸' && window.__ext === 2);
            const createURL = URL.createObjectURL, anchorClick = HTMLAnchorElement.prototype.click;
            let blob = null;
            URL.createObjectURL = b => { blob = b; return 'blob:test'; };
            HTMLAnchorElement.prototype.click = function() {};
            try { downloadTableCsv(linked, 'linked.csv'); } finally {
                URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick;
            }
            const csv = blob ? await blob.text() : '';
            check('linked-csv-content', csv.split('\n').slice(1).join('|') === 'A-link,1|B-link,2');
            const grouped = document.getElementById('grouped').closest('table');
            check('grouped-header-layout', grouped.tHead.rows.length === 2 &&
                grouped.tHead.rows[0].cells[0].rowSpan === 2 &&
                grouped.tHead.rows[0].cells[1].colSpan === 3 &&
                grouped.tHead.rows[0].cells[2].colSpan === 3);
            grouped.querySelector('thead th[data-htmxo-sort-col="6"] .htmxo-sort-control').click();
            check('grouped-sort-column', grouped.tBodies[0].rows[0].cells[0].textContent === 'A' &&
                htmxoSortState(grouped).sort_col === 6);
            blob = null;
            URL.createObjectURL = b => { blob = b; return 'blob:test'; };
            HTMLAnchorElement.prototype.click = function() {};
            try { downloadTableCsv(grouped.closest('figure').querySelector('.caption-action'), 'grouped.csv'); }
            finally { URL.createObjectURL = createURL; HTMLAnchorElement.prototype.click = anchorClick; }
            const groupedCsv = blob ? await blob.text() : '';
            check('grouped-csv-leaves', groupedCsv.split('\n')[0] ===
                'Model,Primal / Ratio,Primal / Wren,Primal / RKPPL,Gradient / Ratio,Gradient / Wren,Gradient / RKPPL');
            check('sort-state', htmxoSortState(tree).sort_col === 2 && htmxoSortState(tree).sort_dir === 'desc');
            const parent = row('dual-parent'), child = row('dual-child');
            const parentDetail = document.getElementById('detail-dual-parent');
            const detailAction = parent.querySelector('[data-htmxo-detail-toggle]');
            check('dual-detail-after-label', detailAction.previousElementSibling.hasAttribute('data-htmxo-row-label'));
            check('dual-detail-icon', detailAction.textContent === 'ⓘ' && detailAction.getAttribute('aria-label') === 'Details');
            check('dual-detail-unfilled', getComputedStyle(detailAction).backgroundColor === 'rgba(0, 0, 0, 0)' &&
                getComputedStyle(detailAction).borderTopWidth === '0px');
            parent.click();
            check('dual-row-opens-children', !child.hidden && parentDetail.hidden);
            parent.querySelector('[data-htmxo-detail-toggle]').click();
            check('dual-detail-separate', !child.hidden && !parentDetail.hidden);
            parent.querySelector('[data-htmxo-tree-toggle]').click();
            check('dual-label-closes-children', child.hidden && !parentDetail.hidden);
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
        page = repr("text/html", htmx(tree, plain, flat, dual, linked, grouped, driver;
            extra_head=(sortable_table_js(), sortable_table_styles(), download_table_js()),
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
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
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
