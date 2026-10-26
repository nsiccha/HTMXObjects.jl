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
    # A table's own rows, without the template row the browser builds groups from.
    table_rows(html) = replace(html, r"<template data-htmxo-group-template.*?</template>"s => "")
    export table_rows

    export OUTLINE, OUTLINE_GROUPINGS, outline_children, outline_key, outline_master, outline_table, plain_outline

    # An offer's outline: nested sections, each with its own cells and detail,
    # over the clauses they cover (the leaves). Clause c2 is covered by
    # sections 1.1 and 2, so it has a row under each saying how that section
    # covers it; section 3 covers none. The clauses' own order (`order`) is
    # not the tree's.
    oclause(section, id, status, points, order) = (; kind=:clause, section, id, status, points, order, note="$id in $section")
    osection(id, title, children...) = (; kind=:section, id, title, children=Any[children...])
    const OUTLINE = [
        osection("1", "Approach", oclause("1", "c1", "shown", 2.0, 2),
                osection("1.1", "Data", oclause("1.1", "c2", "described", 3.0, 3), oclause("1.1", "c3", "shown", 5.0, 4))),
        osection("2", "Operation", oclause("2", "c2", "described", 3.0, 3), oclause("2", "c4", "open", 1.0, 1)),
        osection("3", "Training")]
    const OUTLINE_GROUPINGS = ["Outline" => :children, "None" => nothing, "Status" => r -> r.status]
    outline_children(r) = r.kind === :section ? r.children : Any[]
    # Row ids are page-wide: a second table on the page takes a prefix.
    outline_key(prefix) = r -> r.kind === :section ? "$(prefix)s$(r.id)" : "$(prefix)c$(r.section)-$(r.id)"
    outline_master(r) = r.kind === :section ? (h.td(r.title), h.td(""), h.td("")) :
        (h.td(r.note), h.td(r.status), h.td(string(r.points); data_sort_value=string(r.points)))
    outline_detail(r) = h.p("about " * (r.kind === :section ? r.title : r.note))
    outline_table(; prefix="", groupings=OUTLINE_GROUPINGS, leaf_key=r -> r.kind === :clause ? prefix * r.id : nothing,
                  leaf_order=r -> r.order, kw...) =
        master_detail_table(["Item", "Status", "Points"], OUTLINE; key=outline_key(prefix), children=outline_children,
            master=outline_master, detail=outline_detail, groupings, leaf_key, leaf_order,
            group_summary=["Points" => ColumnSummary(:sum, r -> r.points)], kw...)
    # The same tree without `groupings`.
    plain_outline(; prefix="", kw...) = master_detail_table(["Item", "Status", "Points"], OUTLINE;
        key=outline_key(prefix), children=outline_children, master=outline_master, detail=outline_detail, kw...)

    export MEDIA, SUMMARY, regroup_table, regroup_driver_prelude

    # "media" lists only the two Prime payments: the others wait beside the table.
    const MEDIA = [GROUPINGS..., "media" => t -> occursin("Prime", t.party) ? "Prime" : nothing]
    const SUMMARY = ["Amount" => ColumnSummary(:sum, t -> t.amount; digits=1), "IBAN" => ColumnSummary(:count)]
    # Row ids are page-wide: a second table on the page takes other keys.
    regroup_table(; items=TX, key=t -> t.id, kw...) = master_detail_table(["Party", "IBAN", "Amount"], items; key,
        master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount); data_sort_value=string(t.amount))),
        detail=t -> h.p(t.memo), groupings=MEDIA, group_summary=SUMMARY, kw...)
    # The page side of a browser check: `check(name, ok)` (ok === true, or a
    # note saying what differed), and `parity(wrapper, url)`, which compares
    # the table's rows with the server's render of `url`, attribute for
    # attribute, ignoring only what the runtime manages on rows it has seen:
    # the filter's mark and the selection's roving tabindex.
    regroup_driver_prelude() = raw"""
        const checks = [];
        const check = (name, ok) => checks.push(name + ':' + (ok === true ? 'true' : 'false ' + String(ok).slice(0, 600)));
        const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
        const norm = el => el.nodeType === 3 ? el.textContent : el.nodeType !== 1 ? '' :
            '<' + el.tagName.toLowerCase() + ' ' + Array.from(el.attributes).filter(a => a.name !== 'data-htmxo-filtered' && a.name !== 'tabindex')
                .map(a => ['hidden', 'disabled', 'selected', 'checked'].includes(a.name) ? a.name : a.name + '=' + a.value).sort().join(' ') +
            '>' + Array.from(el.childNodes).map(norm).join('') + '</' + el.tagName.toLowerCase() + '>';
        const rowsOf = root => Array.from(root.querySelector('table').tBodies[0].rows).map(norm);
        const parity = async (wrapper, url, pills) => {
            const t = document.createElement('template');
            t.innerHTML = await (await fetch(url)).text();
            const server = rowsOf(t.content), page = rowsOf(wrapper);
            const at = server.findIndex((r, i) => r !== page[i]);
            if (server.length !== page.length || at >= 0) {
                const a = page[at] || '', b = server[at] || '';
                let k = 0; while (k < a.length && a[k] === b[k]) k++;
                return 'rows ' + page.length + '/' + server.length + ' at ' + at + ' char ' + k + ': ' +
                    a.slice(Math.max(0, k - 60), k + 140) + ' VS ' + b.slice(Math.max(0, k - 60), k + 140);
            }
            if (!pills) return true;
            const a = norm(wrapper.querySelector('.htmxo-group-pills')), b = norm(t.content.querySelector('.htmxo-group-pills'));
            return a === b || 'pills: ' + a + ' VS ' + b;
        };
        const finish = () => {
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.join('\n');
            document.body.appendChild(result);
        };
    """
end

@testitem "regroupable master_detail_table renders groups over the same leaves" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    html(x) = repr("text/html", x)
    party = html(grouped(group_by=["party"], selectable="tx", select_form="bulk", id="g",
        group_by_url="/table", searchable=true, search_query="acme"))
    @test contains(party, "data-htmxo-grouped=\"[&quot;party&quot;]\"")
    @test contains(party, "id=\"row-group--Acme\"") && contains(party, "data-htmxo-group=\"\"")
    @test count("data-htmxo-group=\"\"", table_rows(party)) == 4
    # Leaves keep their own selection key and value; group rows submit their path under <name>_group.
    @test contains(party, "data-htmxo-select-key=\"p1\"") && contains(party, "data-htmxo-select-value=\"p1\"")
    @test occursin(r"<tr[^>]*data-htmxo-select-key=\"group:Acme\"[^>]*>", party) &&
        contains(match(r"<tr[^>]*data-htmxo-select-key=\"group:Acme\"[^>]*>", party).match, "data-htmxo-select-value=\"[&quot;Acme&quot;]\"") &&
        contains(party, "data-htmxo-select-name=\"tx_group\"")
    @test contains(party, "data-htmxo-parent=\"row-group--Acme\"")
    # The Group by control: a pill per grouping, the active one pressed, the
    # grouping posted with the bulk form; no select. It regroups in the
    # browser; the server is asked only for what needs it.
    pills_tag(page) = match(r"<span class=\"htmxo-group-pills\"[^>]*>", page).match
    @test contains(party, "id=\"g-group-party\" aria-pressed=\"true\"") &&
        contains(party, "id=\"g-group-iban\" aria-pressed=\"false\"") && contains(party, "id=\"g-group-rule\" aria-pressed=\"false\"")
    @test contains(party, "<input type=\"hidden\" name=\"group_by\" value=\"party\" form=\"bulk\">") && !contains(party, "<select")
    @test !contains(party, "hx-get=\"/table\"") && contains(party, "&quot;refresh&quot;:false")
    # Group rows from `group_master` come from the server after a browser
    # regroup, through a hidden element: the control itself stays request-free,
    # so a recording (which strips that request) keeps it live.
    master_rows = html(grouped(group_by=["party"], group_by_url="/table", group_master=(k, ms) -> (h.td(k), h.td(""), h.td(""))))
    @test !contains(pills_tag(master_rows), "hx-get")
    @test occursin(r"<span hidden=\"true\" data-htmxo-group-refresh=\"\" hx-get=\"/table\" hx-trigger=\"htmxo-regroup\"[^>]* hx-vals=\"js:\{group_by: htmxoGroupBy\(this\), q: htmxoGroupedQuery\(this\)\}\"", master_rows)
    @test contains(master_rows, "&quot;refresh&quot;:true") && !contains(party, "data-htmxo-group-refresh")
    lazy = html(grouped(group_by=["party"], group_by_url="/table", group_rows_url=(k, ms) -> "/rows"))
    @test contains(pills_tag(lazy), "hx-get=\"/table\"") && !contains(lazy, "data-htmxo-regroup")
    # Without a server to ask, lazy groups cannot regroup: no control.
    @test !contains(html(grouped(group_by=["party"], group_rows_url=(k, ms) -> "/rows")), "<span class=\"htmxo-group-pills\"")
    @test occursin(r"class=\"htmxo-tree-controls\"><span class=\"htmxo-group-pills\"", party)
    @test contains(party, "type=\"search\"") && contains(party, "value=\"acme\"")
    # Overlapping membership: one leaf, two rows, two ids, one selection key.
    rule = html(grouped(group_by="rule", selectable="tx"))
    @test count("data-htmxo-select-key=\"p3\"", rule) == 2
    @test contains(rule, "id=\"row-group--Shops--p3\"") && contains(rule, "id=\"row-group--Media--p3\"")
    # The flat grouping renders the leaves themselves, keyed the same way, as
    # the first level of the same tree, so the browser can group them again.
    flat = html(grouped(group_by=["none"], selectable="tx", group_by_url="/table"))
    @test !contains(table_rows(flat), "data-htmxo-group=\"\"") && contains(flat, "data-htmxo-hierarchy=\"\"")
    @test count("data-htmxo-select-key=\"p", flat) == length(TX)
    @test count("aria-pressed=\"false\"", flat) == 3 && !contains(flat, "aria-pressed=\"true\"")
    @test html(grouped()) == html(grouped(group_by="none")) == html(grouped(group_by=["none"]))
    # A single name is a one-name list: the same table, pills and path keys included.
    @test html(grouped(group_by="rule", selectable="tx", searchable=true, id="g")) ==
        html(grouped(group_by=["rule"], selectable="tx", searchable=true, id="g"))
    @test html(grouped(group_by="")) == html(grouped(group_by=[""])) == html(grouped(group_by=String[]))
    # A custom group summary, and caller master_attrs winning over the helper's.
    custom = html(grouped(group_by=["iban"], group_master=(k, ms) -> (h.td("IBAN $(last(HTMXObjects.group_path(k)))"),
        h.td(string(length(ms))), h.td("")), master_attrs=t -> (; data_kind="tx")))
    @test contains(custom, "IBAN DE01") && contains(custom, "data-kind=\"tx\"")
    # The control and the hidden search scaffold are HTML-only.
    md = to_markdown_string(grouped(group_by=["party"], group_by_url="/table"))
    @test !contains(md, "Group by") && contains(md, "Acme Prime")
    @test_throws ArgumentError grouped(group_by="nope")
    # refused: a single group_by name (or none) beside a hook that gives the
    # grouping and group keys to app code, which gets them as a list and as
    # paths, so code written for the old plain keys must be told (decision
    # HTMXObjects:snag.regroupable-tabl-3c35de85/decisions/2026-10-26T13-44-03-693-1cmvukh)
    for hook in ((; group_master=(k, ms) -> (h.td(k), h.td(""), h.td(""))), (; group_by_url="/table"), (; group_rows_url=(k, ms) -> nothing),
                 (; select_form="bulk", selectable="tx"), (; group_rows="[\"Acme\"]"), (; update_groups="[\"Acme\"]"))
        @test_throws ArgumentError grouped(; group_by="party", hook...)
        @test_throws ArgumentError grouped(; hook...)
        @test grouped(; group_by=["party"], hook...) isa Any
    end
    err = try grouped(group_by="party", group_master=(k, ms) -> (), select_form="bulk"); nothing catch e; e end
    @test err isa ArgumentError && contains(err.msg, "group_master, select_form give the grouping") &&
        contains(err.msg, "group_by=[\"party\"]") && contains(err.msg, "group_by::Vector{String}")
    @test_throws ArgumentError grouped(children=t -> ())
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", group_by="party")
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", groupings=["a" => nothing, "a" => nothing])
end

@testitem "lazy groups: placeholders carry search text and selection keys" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    lazy_url = (k, ms) -> length(ms) > 2 ? "/rows?key=$(last(HTMXObjects.group_path(k)))" : nothing
    page = html(grouped(group_by=["party"], selectable="tx", group_rows_url=lazy_url,
        select_submit=t -> t.id != "p7"))
    # "Acme" (3 rows) loads lazily; "Bakery" (2 rows) is eager.
    @test contains(page, "data-htmxo-lazy-rows=\"/rows?key=Acme\"")
    # The count is of items: 4 eager leaves + 3 not loaded yet; group rows are none.
    @test contains(page, "7 of 7 rows shown")
    @test !contains(page, "id=\"row-group--Acme--p1\"") && contains(page, "id=\"row-group--Bakery--p4\"")
    @test contains(page, "data-htmxo-lazy-leaves=\"[[&quot;p1&quot;,&quot;Acme DE01 -10.0&quot;],[&quot;p2&quot;,&quot;Acme DE02 -20.0&quot;],[&quot;p7&quot;,&quot;Acme DE01 -70.0&quot;]]\"")
    @test contains(page, "data-htmxo-select-members=\"{&quot;p1&quot;:&quot;p1&quot;,&quot;p2&quot;:&quot;p2&quot;,&quot;p7&quot;:null}\"")
    # A lazy group starts collapsed and names no child rows yet.
    acme = match(r"<tr[^>]*id=\"row-group--Acme\"[^>]*>.*?</tr>"s, page).match
    @test contains(acme, "data-htmxo-tree-open=\"false\"") && !contains(acme, "aria-controls")
    # The lazy-load response: exactly the rows an eager render gives that group.
    rows = html(grouped(group_by=["party"], selectable="tx", group_rows_url=lazy_url,
        select_submit=t -> t.id != "p7", group_rows="[\"Acme\"]", initially_open=true))
    @test startswith(rows, "<tbody data-htmxo-group-rows=\"[&quot;Acme&quot;]\">")
    eager = html(grouped(group_by="party", selectable="tx", select_submit=t -> t.id != "p7",
        initially_open=true))
    for id in ("p1", "p2", "p7")
        tr = match(Regex("<tr[^>]*id=\"row-group--Acme--$id\"[^>]*>.*?</tr>", "s"), rows).match
        @test contains(eager, tr)
    end
    @test !contains(rows, "id=\"row-group--Acme\"") && !contains(rows, "Bakery")
    @test contains(rows, "id=\"detail-group--Acme--p1\"")
    @test_throws ArgumentError grouped(group_by=["none"], group_rows="[\"Acme\"]")
    # Search text from `search_text` when given.
    custom = html(grouped(group_by=["party"], group_rows_url=lazy_url, search_text=t -> "tx $(t.id)"))
    @test contains(custom, "data-htmxo-lazy-leaves=\"[[&quot;p1&quot;,&quot;tx p1&quot;],[&quot;p2&quot;,&quot;tx p2&quot;],[&quot;p7&quot;,&quot;tx p7&quot;]]\"")
end

@testitem "the search count counts items, not group rows" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    count_line(page) = match(r"data-htmxo-table-count=\"\"[^>]*>([^<]*)<", page)[1]
    # "rule" lists p3 under Shops and under Media: 2 group rows and 8 leaf rows are 7 items.
    rule = html(grouped(group_by="rule", searchable=true))
    @test count("data-htmxo-leaf=\"p3\"", table_rows(rule)) == 2
    @test count_line(rule) == "7 of 7 rows shown"
    # Collapsed groups hide their leaves; the leaves still count as shown.
    party = html(grouped(group_by="party", searchable=true))
    @test occursin(r" hidden(=\"true\")?[ >]", match(r"<tr[^>]*data-htmxo-leaf=\"p1\"[^>]*>", table_rows(party)).match)
    @test count_line(party) == "7 of 7 rows shown"
    # An item-named count, as htmxo-master-detail recommends, reads the items
    # at every level.
    de = table_texts(:de; count="{shown} von {total} Zahlungen")
    @test count_line(html(grouped(group_by=["rule", "party"], searchable=true, texts=de))) == "7 von 7 Zahlungen"
    @test count_line(html(grouped(group_by="none", searchable=true))) == "7 of 7 rows shown"
end

@testitem "initially_open: a predicate opens the groups of the leaves it opens" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    tr(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>"), page).match
    calls = Any[]
    page = html(grouped(group_by="rule", initially_open=t -> (push!(calls, t); t.id == "p3")))
    # The predicate sees leaves only, never a group row.
    @test !isempty(calls) && all(c -> c in TX, calls)
    # p3 is in both rule groups: each opens, and each copy shows with its detail open.
    for g in ("Shops", "Media")
        @test contains(tr(page, "row-group--$g"), "data-htmxo-tree-open=\"true\"")
        @test contains(tr(page, "row-group--$g"), "aria-expanded=\"true\"")
        leaf = tr(page, "row-group--$g--p3")
        @test contains(leaf, "data-htmxo-detail-open=\"true\"") && !contains(leaf, "hidden")
        @test !contains(tr(page, "detail-group--$g--p3"), "hidden")
    end
    # Groups without an opened leaf stay closed, their rows hidden.
    party = html(grouped(group_by="party", initially_open=t -> t.id == "p1"))
    @test contains(tr(party, "row-group--Acme"), "data-htmxo-tree-open=\"true\"")
    @test !contains(tr(party, "row-group--Acme--p1"), "hidden") && !contains(tr(party, "detail-group--Acme--p1"), "hidden")
    # Its siblings show too, with their details closed.
    @test !contains(tr(party, "row-group--Acme--p2"), "hidden") && contains(tr(party, "detail-group--Acme--p2"), "hidden")
    @test contains(tr(party, "row-group--Bakery"), "data-htmxo-tree-open=\"false\"")
    @test contains(tr(party, "row-group--Bakery--p4"), "hidden")
    # A lazy group holding an opened leaf renders its rows eagerly; the others stay lazy.
    lazy_url = (k, ms) -> length(ms) > 1 ? "/rows?key=$(join(HTMXObjects.group_path(k), '/'))" : nothing
    lazy = html(grouped(group_by=["party"], group_rows_url=lazy_url, initially_open=t -> t.id == "p1"))
    @test !contains(tr(lazy, "row-group--Acme"), "data-htmxo-lazy-rows") &&
        contains(tr(lazy, "row-group--Acme"), "data-htmxo-tree-open=\"true\"")
    @test all(contains(lazy, "id=\"row-group--Acme--$id\"") for id in ("p1", "p2", "p7"))
    @test contains(tr(lazy, "row-group--Bakery"), "data-htmxo-lazy-rows=\"/rows?key=Bakery\"")
    # `true` keeps its meaning: every rendered group open, lazy groups lazy.
    all_open = html(grouped(group_by=["party"], group_rows_url=lazy_url, initially_open=true))
    @test contains(tr(all_open, "row-group--Acme"), "data-htmxo-lazy-rows=\"/rows?key=Acme\"")
    @test contains(tr(all_open, "row-group--Acme--Prime"), "data-htmxo-tree-open=\"true\"")
    # A predicate that opens nothing changes nothing.
    @test html(grouped(group_by=["party"], group_rows_url=lazy_url, initially_open=_ -> false)) ==
        html(grouped(group_by=["party"], group_rows_url=lazy_url))
    # Nested levels: every group on an opened leaf's path opens (eagerly), at every level.
    by = ["rule", "party"]
    nested = html(grouped(group_by=by, group_rows_url=lazy_url, initially_open=t -> t.id == "p1"))
    for g in ("Shops", "Shops--Acme")
        @test contains(tr(nested, "row-group--$g"), "data-htmxo-tree-open=\"true\"") &&
            !contains(tr(nested, "row-group--$g"), "data-htmxo-lazy-rows")
    end
    @test !contains(tr(nested, "row-group--Shops--Acme--p1"), "hidden") &&
        !contains(tr(nested, "detail-group--Shops--Acme--p1"), "hidden")
    # Groups off that path stay closed, and lazy ones lazy, inside an opened group too.
    @test contains(tr(nested, "row-group--Shops--Bakery"), "data-htmxo-tree-open=\"false\"") &&
        contains(tr(nested, "row-group--Shops--Bakery"), "data-htmxo-lazy-rows=")
    @test contains(tr(nested, "row-group--Media"), "data-htmxo-tree-open=\"false\"") &&
        contains(tr(nested, "row-group--Media"), "data-htmxo-lazy-rows=")
    @test html(grouped(group_by=by, group_rows_url=lazy_url, initially_open=_ -> false)) ==
        html(grouped(group_by=by, group_rows_url=lazy_url))
end

@testitem "row updates: the rows of a leaf or a group, as the table renders them" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    html(x) = repr("text/html", x)
    row(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>.*?</tr>", "s"), page).match
    # Every copy of a leaf names it, in full renders and lazy loads alike.
    full = html(grouped(group_by="rule", selectable="tx", id="g"))
    @test count("data-htmxo-leaf=\"p3\"", full) == 2
    @test count("data-htmxo-leaf=\"p3\"", html(grouped(group_by="none"))) == 1
    # A leaf update: each copy of the leaf in the active grouping, identical to
    # the full table's, with its detail, plus the summary row of each group it
    # is in (computed over all members).
    upd = html(grouped(group_by="rule", selectable="tx", id="g", update_rows="p3"))
    @test startswith(upd, "<tbody data-htmxo-row-update=\"g\" data-htmxo-grouped=\"[&quot;rule&quot;]\" data-htmxo-update-leaves=\"[&quot;p3&quot;]\"")
    for id in ("row-group--Shops--p3", "row-group--Media--p3", "detail-group--Shops--p3")
        @test row(upd, id) == row(full, id)
    end
    # A group row names the child rows the update renders (the runtime
    # recomputes the list from the page), not the group's other members.
    @test contains(row(upd, "row-group--Shops"), "aria-controls=\"row-group--Shops--p3\"")
    # Where each row sits in the full table: its neighbours among its siblings
    # ("" at either end), for a row that is new to the page or has moved.
    places(page) = replace(match(r"data-htmxo-update-places=\"([^\"]*)\"", page)[1], "&quot;" => "'")
    @test places(upd) == "{'row-group--Shops':['','row-group--Media']," *
        "'row-group--Shops--p3':['row-group--Shops--p2','row-group--Shops--p4']," *
        "'row-group--Media--p3':['','row-group--Media--p5']}"
    @test contains(upd, "id=\"row-group--Shops\"") && contains(upd, "<strong data-htmxo-group-label=\"\">Shops</strong> <small data-htmxo-group-count=\"\">(6)</small>")
    @test !contains(upd, "--p1\"") && count("<tr", upd) == 6
    # A group update: the group row and all its rows; a lazy group's row keeps
    # its lazy marks for a table that has not loaded it.
    lazy_url = (k, ms) -> length(ms) > 2 ? "/rows?key=$(last(HTMXObjects.group_path(k)))" : nothing
    acme = html(grouped(group_by=["party"], id="g", group_rows_url=lazy_url, update_groups="[\"Acme\"]"))
    @test contains(acme, "data-htmxo-update-groups=\"[&quot;row-group--Acme&quot;]\"")
    # A run of listed siblings names the neighbours of its first row only;
    # the others follow the row before them in the update.
    @test places(acme) == "{'row-group--Acme':['','row-group--Acme--Prime'],'row-group--Acme--p1':['','row-group--Acme--p2']}"
    @test contains(acme, "data-htmxo-lazy-rows=\"/rows?key=Acme\"") && contains(acme, "data-htmxo-lazy-leaves=\"[[&quot;p1&quot;,&quot;Acme DE01 -10.0&quot;],[&quot;p2&quot;,&quot;Acme DE02 -20.0&quot;],[&quot;p7&quot;,&quot;Acme DE01 -70.0&quot;]]\"")
    @test all(contains(acme, "id=\"row-group--Acme--$id\"") for id in ("p1", "p2", "p7"))
    @test !contains(acme, "Bakery")
    # Several keys at once; a group that no longer exists is in the scope with no rows.
    both = html(grouped(group_by=["party"], update_rows=["p4", "p1"], update_groups=("[\"Gone\"]",)))
    @test contains(both, "data-htmxo-update-leaves=\"[&quot;p4&quot;,&quot;p1&quot;]\"") &&
        contains(both, "data-htmxo-update-groups=\"[&quot;row-group--Gone&quot;]\"")
    @test contains(both, "id=\"row-group--Acme--p1\"") && contains(both, "id=\"row-group--Bakery--p4\"") &&
        !contains(both, "id=\"row-group--Bakery--p6\"")
    @test html(grouped(group_by=["party"], update_groups="[\"Gone\"]", id="g")) ==
        "<tbody data-htmxo-row-update=\"g\" data-htmxo-grouped=\"[&quot;party&quot;]\" data-htmxo-update-groups=\"[&quot;row-group--Gone&quot;]\"></tbody>"
    # The flat view names its leaves; it has no groups to update.
    flat = html(grouped(group_by=["none"], selectable="tx", update_rows=["p1", "gone"], update_groups="[\"Acme\"]"))
    @test contains(flat, "data-htmxo-grouped=\"[]\"") &&
        contains(flat, "data-htmxo-update-leaves=\"[&quot;p1&quot;,&quot;gone&quot;]\"") && !contains(flat, "data-htmxo-update-groups")
    @test row(flat, "row-p1") == row(html(grouped(group_by="none", selectable="tx")), "row-p1") && count("<tr", flat) == 2
    # Any master_detail_table: flat, and a tree whose update keeps the row's
    # place (parent and level) without rendering the other rows.
    plain = html(master_detail_table(["Party"], TX; key=t -> t.id, master=t -> (h.td(t.party),),
        detail=t -> h.p(t.memo), update_rows="p2", id="t"))
    @test startswith(plain, "<tbody data-htmxo-row-update=\"t\" data-htmxo-update-ids=\"[&quot;row-p2&quot;]\" " *
        "data-htmxo-update-places=\"{&quot;row-p2&quot;:[&quot;row-p1&quot;,&quot;row-p3&quot;]}\"><tr id=\"row-p2\"")
    @test places(html(master_detail_table(["Party"], TX; key=t -> t.id, master=t -> (h.td(t.party),),
        detail=t -> h.p(t.memo), update_rows=["p7", "p3", "p2"]))) ==
        "{'row-p2':['row-p1','row-p3'],'row-p7':['row-p6','']}"
    tree = [(; id="a", kids=[(; id="b", kids=[(; id="c", kids=[])])])]
    treeargs = (; key=n -> n.id, master=n -> (h.td(n.id),), children=n -> n.kids, detail=n -> "d")
    deep = html(master_detail_table(["Id"], tree; treeargs..., update_rows="c"))
    @test row(deep, "row-c") == row(html(master_detail_table(["Id"], tree; treeargs...)), "row-c")
    @test contains(deep, "data-htmxo-parent=\"row-b\"") && contains(deep, "aria-level=\"3\"") && count("<tr", deep) == 2
    @test places(deep) == "{'row-c':['','']}"
    wide = [(; id="a", kids=[(; id="b", kids=[]), (; id="c", kids=[])]), (; id="d", kids=[])]
    @test places(html(master_detail_table(["Id"], wide; treeargs..., update_rows=["c", "d"]))) ==
        "{'row-d':['row-a',''],'row-c':['row-b','']}"
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", update_groups="Acme")
    @test_throws ArgumentError grouped(group_by=["party"], group_rows="[\"Acme\"]", update_rows="p1")
end

@testitem "ordered grouping: nested levels, path keys and grouping pills" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string, group_path
    html(x) = repr("text/html", x)
    row(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>.*?</tr>", "s"), page).match
    attr(tr, name) = match(Regex("$name=\"([^\"]*)\""), match(r"<tr[^>]*>"s, tr).match)
    page = html(grouped(group_by=["rule", "party"], group_by_url="/table", selectable="tx", select_form="bulk", id="g"))
    # What the rows are grouped by, and what a request sends to render them again.
    @test contains(page, "data-htmxo-grouped=\"[&quot;rule&quot;,&quot;party&quot;]\" data-htmxo-group-by=\"[&quot;rule&quot;,&quot;party&quot;]\"")
    # Level 2 nests inside level 1; leaves sit at level 3 under their innermost group.
    acme = row(page, "row-group--Shops--Acme")
    @test attr(acme, "data-htmxo-parent")[1] == "row-group--Shops" && attr(acme, "aria-level")[1] == "2"
    @test contains(acme, "<strong data-htmxo-group-label=\"\">Acme</strong> <small data-htmxo-group-count=\"\">(3)</small>")
    leaf = row(page, "row-group--Shops--Acme--p1")
    @test attr(leaf, "data-htmxo-parent")[1] == "row-group--Shops--Acme" && attr(leaf, "aria-level")[1] == "3"
    @test attr(leaf, "data-htmxo-select-key")[1] == "p1" && attr(leaf, "data-htmxo-leaf")[1] == "p1"
    # Groups are named by their path, as a JSON array: their selection value and key.
    @test attr(acme, "data-htmxo-select-value")[1] == "[&quot;Shops&quot;,&quot;Acme&quot;]"
    @test attr(acme, "data-htmxo-select-key")[1] == "group:Shops/Acme"
    @test attr(row(page, "row-group--Shops"), "data-htmxo-select-value")[1] == "[&quot;Shops&quot;]"
    # A vector-valued grouping lists a leaf under each of its groups, at every level.
    @test count("data-htmxo-leaf=\"p3\"", page) == 2 &&
        contains(page, "id=\"row-group--Shops--Acme--Prime--p3\"") && contains(page, "id=\"row-group--Media--Acme--Prime--p3\"")
    by_party = html(grouped(group_by=["party", "rule"]))
    @test contains(by_party, "id=\"row-group--Acme--Prime--Shops--p3\"") && contains(by_party, "id=\"row-group--Acme--Prime--Media--p3\"")
    # The pills: active levels first, in order, each with ‹ › (disabled at the ends); then the rest.
    pills = match(r"<span class=\"htmxo-group-pills\".*?</p>"s, page).match
    @test !contains(page, "<select name=\"group_by\"")
    # They regroup in the browser; group rows from `group_master` also come
    # from the server afterwards.
    @test !contains(pills, "hx-get")
    served = html(grouped(group_by=["rule", "party"], group_by_url="/table", group_master=(k, ms) -> (h.td(k), h.td(""), h.td(""))))
    @test !contains(match(r"<span class=\"htmxo-group-pills\"[^>]*>"s, served).match, "hx-get") &&
        contains(served, "data-htmxo-group-refresh=\"\" hx-get=\"/table\"")
    # Lazy groups regroup through the server: the pills ask it.
    lazy_pills = match(r"<span class=\"htmxo-group-pills\"[^>]*>"s, html(grouped(group_by=["rule", "party"], group_by_url="/table",
        group_rows_url=(k, ms) -> "/rows"))).match
    @test contains(lazy_pills, "hx-get=\"/table\" hx-trigger=\"htmxo-regroup\" hx-target=\"closest [data-htmxo-grouped]\" hx-swap=\"outerHTML\"")
    @test contains(pills, "data-htmxo-group-flat=\"none\"")
    @test [m[1] for m in eachmatch(r"data-htmxo-group-name=\"([^\"]*)\"", pills)] == ["rule", "party", "iban"]
    @test contains(pills, "data-htmxo-group-name=\"rule\" data-htmxo-group-level=\"1\"") &&
        contains(pills, "data-htmxo-group-name=\"party\" data-htmxo-group-level=\"2\"") &&
        !contains(pills, "data-htmxo-group-name=\"iban\" data-htmxo-group-level")
    @test count("aria-pressed=\"true\"", pills) == 2 && count("aria-pressed=\"false\"", pills) == 1
    @test contains(pills, "id=\"g-group-rule-earlier\" class=\"htmxo-group-move\" aria-label=\"Move rule earlier\" onclick=\"htmxoGroupMove(this,-1)\" disabled=\"true\"")
    @test contains(pills, "id=\"g-group-party-later\" class=\"htmxo-group-move\" aria-label=\"Move party later\" onclick=\"htmxoGroupMove(this,1)\" disabled=\"true\"")
    @test count("<button type=\"button\" id=\"g-group-party-earlier\"", pills) == 1 && !contains(pills, "id=\"g-group-iban-earlier\"")
    # With a bulk form, the levels are submitted with it.
    @test contains(page, "<input type=\"hidden\" name=\"group_by\" value=\"rule\" form=\"bulk\"><input type=\"hidden\" name=\"group_by\" value=\"party\" form=\"bulk\">")
    # One level: no move buttons or level numbers; plain ordered keys are still paths.
    one = html(grouped(group_by=["party"], group_by_url="/table", id="g"))
    @test !contains(one, "class=\"htmxo-group-move\"") && !contains(one, "class=\"htmxo-group-level\"") &&
        contains(one, "data-htmxo-grouped=\"[&quot;party&quot;]\"")
    seen = String[]
    html(grouped(group_by=["rule", "party"], group_master=(k, ms) -> (push!(seen, k); (h.td(k), h.td(""), h.td("")))))
    @test seen[1:2] == ["[\"Shops\"]", "[\"Shops\",\"Acme\"]"] && all(k -> group_path(k)[1] in ("Shops", "Media"), seen)
    # The flat view, spelled any way, renders the leaves and asks for the flat grouping again.
    flat = html(grouped(group_by=String[], group_by_url="/table", id="g"))
    @test flat == html(grouped(group_by=[""], group_by_url="/table", id="g")) ==
        html(grouped(group_by=["none"], group_by_url="/table", id="g"))
    @test contains(flat, "data-htmxo-grouped=\"[]\" data-htmxo-group-by=\"[&quot;none&quot;]\"") &&
        !contains(table_rows(flat), "data-htmxo-group=\"\"") && count("aria-pressed=\"false\"", flat) == 3
    # Without a flat grouping the last level stays on (no request could ask
    # for none); rendered directly, an empty list is still the flat view.
    nonflat(group_by) = html(master_detail_table(["Party"], TX; key=t -> t.id, master=t -> (h.td(t.party),),
        detail=t -> "", groupings=GROUPINGS[2:end], group_by, group_by_url="/table", id="n"))
    @test contains(nonflat(String[]), "data-htmxo-group-by=\"[&quot;&quot;]\"") && !contains(nonflat(String[]), "data-htmxo-group-flat")
    @test contains(nonflat(["party"]), "id=\"n-group-party\" aria-pressed=\"true\" title=\"Grouped by party; add another grouping to change it\" aria-disabled=\"true\"")
    @test !contains(nonflat(["party", "iban"]), " aria-disabled=") && !contains(one, " aria-disabled=")
    # A member with no key at an inner level stays in its outer group, directly.
    gaps = html(master_detail_table(["Party"], TX; key=t -> t.id, master=t -> (h.td(t.party),), detail=t -> "",
        groupings=["party" => t -> t.party, "big" => t -> t.amount < -40 ? "big" : nothing], group_by=["party", "big"]))
    @test contains(gaps, "id=\"row-group--Bakery--big--p6\"") &&
        attr(row(gaps, "row-group--Bakery--p4"), "data-htmxo-parent")[1] == "row-group--Bakery"
    # Markdown has no indentation: a mark per level keeps the nesting readable.
    md = to_markdown_string(grouped(group_by=["rule", "party"], group_by_url="/table"))
    @test contains(md, "| **Shops** (6) |") && contains(md, "| › **Acme** (3) |") && contains(md, "| › › Acme | DE01 | -10.0 |")
    @test !contains(md, "Group by") && !contains(md, "‹")
    @test !contains(to_markdown_string(grouped(group_by=["party"])), "›")
    # Group keys: a JSON array of strings, escapes included.
    @test group_path("[\"Open\", \"a\\\"b\\\\c\\u00e9\\ud83d\\ude00\"]") == ["Open", "a\"b\\cé😀"]
    @test group_path(" [ ] ") == String[]
    for bad in ("Open", "[\"a\"", "[\"a\",]", "[1]", "[\"a\"] x", "[\"\\x\"]", "[\"\\ud83d\"]")
        @test_throws ArgumentError group_path(bad)
    end
    @test_throws ArgumentError grouped(group_by=["party", "party"])
    @test_throws ArgumentError grouped(group_by=["none", "party"])
    @test_throws ArgumentError grouped(group_by=["nope"])
    @test_throws ArgumentError grouped(group_by=["party"], group_rows="[\"Acme\",\"x\"]")
end

@testitem "ordered grouping: lazy nested groups and row updates" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, group_path
    html(x) = repr("text/html", x)
    row(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>.*?</tr>", "s"), page).match
    ids(page) = [m[1] for m in eachmatch(r"<tr[^>]*? id=\"(row-[^\"]*)\""s, replace(page, r"<tr id=" => "<tr  id="))]
    lazy_url = (k, ms) -> length(ms) > 2 ? "/rows?key=$(HTMXObjects.HTTP.escapeuri(k))" : nothing
    by = ["rule", "party"]
    page = html(grouped(group_by=by, group_rows_url=lazy_url, selectable="tx"))
    # "Shops" (6) loads lazily; its leaves count as if loaded, each once:
    # p3 is in Shops and in Media, so the 8 listings are 7 items.
    shops = row(page, "row-group--Shops")
    @test contains(page, "7 of 7 rows shown")
    @test contains(shops, "data-htmxo-lazy-rows=\"/rows?key=%5B%22Shops%22%5D\"")
    # Search reaches the unloaded leaves, each with its keys at the levels below.
    @test contains(shops, "data-htmxo-lazy-leaves=\"[[&quot;p1&quot;,&quot;Acme Acme DE01 -10.0&quot;],[&quot;p2&quot;,&quot;Acme Acme DE02 -20.0&quot;],[&quot;p3&quot;,&quot;Acme Prime Acme Prime DE01 -30.0&quot;],[&quot;p4&quot;,&quot;Bakery Bakery DE03 -40.0&quot;],[&quot;p6&quot;,&quot;Bakery Bakery DE03 -60.0&quot;],[&quot;p7&quot;,&quot;Acme Acme DE01 -70.0&quot;]]\"")
    @test !contains(page, "row-group--Shops--Acme\"")
    # The lazy load: the group's rows as an eager render gives them; a big
    # subgroup inside loads lazily in turn.
    rows = html(grouped(group_by=by, group_rows_url=lazy_url, selectable="tx", group_rows="[\"Shops\"]", initially_open=true))
    @test startswith(rows, "<tbody data-htmxo-group-rows=\"[&quot;Shops&quot;]\"><tr id=\"row-group--Shops--Acme\"")
    @test contains(row(rows, "row-group--Shops--Acme"), "data-htmxo-lazy-rows=\"/rows?key=%5B%22Shops%22%2C%22Acme%22%5D\"")
    eager = html(grouped(group_by=by, selectable="tx", initially_open=true))
    for id in ("row-group--Shops--Bakery", "row-group--Shops--Bakery--p4", "row-group--Shops--Acme--Prime--p3", "detail-group--Shops--Bakery--p6")
        @test row(rows, id) == row(eager, id)
    end
    @test !contains(rows, "id=\"row-group--Shops\"") && !contains(rows, "id=\"row-group--Media")
    inner = html(grouped(group_by=by, group_rows_url=lazy_url, selectable="tx", group_rows="[\"Shops\",\"Acme\"]", initially_open=true))
    @test startswith(inner, "<tbody data-htmxo-group-rows=\"[&quot;Shops&quot;,&quot;Acme&quot;]\"><tr ") &&
        contains(match(r"<tr [^>]*>", inner).match, "data-htmxo-leaf=\"p1\"")
    @test all(row(inner, "row-group--Shops--Acme--$id") == row(eager, "row-group--Shops--Acme--$id") for id in ("p1", "p2", "p7"))
    @test count("<tr", inner) == 6
    # A leaf update: every copy of the leaf, and the rows of every group it is in.
    full = html(grouped(group_by=by, id="g"))
    upd = html(grouped(group_by=by, id="g", update_rows="p3"))
    @test startswith(upd, "<tbody data-htmxo-row-update=\"g\" data-htmxo-grouped=\"[&quot;rule&quot;,&quot;party&quot;]\" data-htmxo-update-leaves=\"[&quot;p3&quot;]\"")
    # Places come from the full grouping at every level: Acme Prime follows
    # Acme in Shops, and comes first in Media.
    @test replace(match(r"data-htmxo-update-places=\"([^\"]*)\"", upd)[1], "&quot;" => "'") ==
        "{'row-group--Shops':['','row-group--Media']," *
        "'row-group--Shops--Acme--Prime':['row-group--Shops--Acme','row-group--Shops--Bakery']," *
        "'row-group--Shops--Acme--Prime--p3':['','']," *
        "'row-group--Media--Acme--Prime':['','row-group--Media--Prime--Video']," *
        "'row-group--Media--Acme--Prime--p3':['','']}"
    @test ids(upd) == ["row-group--Shops", "row-group--Shops--Acme--Prime", "row-group--Shops--Acme--Prime--p3",
        "row-group--Media", "row-group--Media--Acme--Prime", "row-group--Media--Acme--Prime--p3"]
    @test row(upd, "row-group--Media--Acme--Prime--p3") == row(full, "row-group--Media--Acme--Prime--p3")
    @test contains(row(upd, "row-group--Shops"), "<strong data-htmxo-group-label=\"\">Shops</strong> <small data-htmxo-group-count=\"\">(6)</small>")
    # A group update, by path: the group whole, with the rows on its path.
    bakery = html(grouped(group_by=by, id="g", update_groups="[\"Shops\",\"Bakery\"]"))
    @test contains(bakery, "data-htmxo-update-groups=\"[&quot;row-group--Shops--Bakery&quot;]\"")
    @test ids(bakery) == ["row-group--Shops", "row-group--Shops--Bakery", "row-group--Shops--Bakery--p4", "row-group--Shops--Bakery--p6"]
    # A named group that is gone: the outermost level of its path that no
    # longer exists leaves, and a group shown for its summary stays a branch.
    gone = html(grouped(group_by=by, id="g", update_groups=["[\"Shops\",\"Gone\"]", "[\"Nope\",\"x\"]"]))
    @test contains(gone, "data-htmxo-update-groups=\"[&quot;row-group--Shops--Gone&quot;,&quot;row-group--Nope&quot;]\"")
    @test ids(gone) == ["row-group--Shops"] && contains(gone, "data-htmxo-tree-toggle") &&
        contains(gone, "data-htmxo-tree-open=\"false\"") && !contains(gone, "aria-controls")
    # A lazy group in an update keeps its marks, and its rows come along.
    lz = html(grouped(group_by=by, id="g", group_rows_url=lazy_url, update_rows="p1"))
    @test contains(row(lz, "row-group--Shops"), "data-htmxo-lazy-leaves=\"[[&quot;p1&quot;,&quot;Acme Acme DE01 -10.0&quot;],[&quot;p2&quot;,&quot;Acme Acme DE02 -20.0&quot;],[&quot;p3&quot;,&quot;Acme Prime Acme Prime DE01 -30.0&quot;],[&quot;p4&quot;,&quot;Bakery Bakery DE03 -40.0&quot;],[&quot;p6&quot;,&quot;Bakery Bakery DE03 -60.0&quot;],[&quot;p7&quot;,&quot;Acme Acme DE01 -70.0&quot;]]\"") && contains(lz, "id=\"row-group--Shops--Acme--p1\"")
    # The flat view of an ordered grouping names its leaves.
    @test contains(html(grouped(group_by=String[], update_rows="p1", id="g")), "data-htmxo-grouped=\"[]\" data-htmxo-update-leaves=")
    @test_throws ArgumentError grouped(group_by=by, update_groups="[]")
    @test_throws ArgumentError grouped(group_by=by, update_groups="Shops")
end

@testitem "regroupable table browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        levels(uri) = [String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"]
        table(group_by, q="", group_rows=nothing) = grouped(; group_by, search_query=q, group_rows,
            group_by_url="/table", group_rows_url=(k, ms) -> length(ms) > 2 ?
                "/rows?$(join(("group_by=$g" for g in group_by), '&'))&key=$(HTTP.escapeuri(k))" : nothing,
            group_master=(k, ms) -> (h.td(h.strong(last(HTMXObjects.group_path(k)))),
                h.td(h.select(; name="mode", id="mode-$(last(HTMXObjects.group_path(k)))")(h.option("off"), h.option("on"))),
                h.td(string(sum(m.amount for m in ms)); data_sort_value=string(sum(m.amount for m in ms)))),
            selectable="tx", select_form="bulk", searchable=true, expand_controls=group_by != ["none"], id="g")
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
            // Group by one grouping alone (or none), as the pills ask for it.
            const regroup = async v => {
                const levels = v === 'none' ? [] : [v];
                htmxoGroupRequest(g().querySelector('.htmxo-group-pills'), levels, null);
                await wait(() => g().dataset.htmxoGrouped === JSON.stringify(levels));
                await new Promise(r => setTimeout(r, 50));
            };
            const total = () => g().querySelector('[data-htmxo-table-count]').textContent;
            check('initial', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video' && total() === '7 of 7 rows shown');
            check('lazy-placeholder', row('group--Acme').dataset.htmxoLazyRows && !row('group--Acme--p1'));
            // The count reaches the leaves of a group that has not loaded: only p2 is DE02.
            search('DE02');
            check('lazy-search-count', total() === '1 of 7 rows shown' && !row('group--Acme--p2'));
            search('');
            // Expanding a lazy group fetches its rows once and opens it.
            toggle('group--Acme');
            await wait(() => row('group--Acme--p1'));
            check('lazy-loaded', shown() === 'group--Acme,group--Acme--p1,group--Acme--p2,group--Acme--p7,group--Acme--Prime,group--Bakery,group--Prime--Video' &&
                row('group--Acme').getAttribute('aria-expanded') === 'true' && !('htmxoLazyRows' in row('group--Acme').dataset));
            check('lazy-count', total() === '7 of 7 rows shown');
            check('lazy-aria-controls', row('group--Acme').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-group--Acme--p1 row-group--Acme--p2 row-group--Acme--p7');
            click(row('group--Acme--p1').cells[2]);
            click(row('group--Acme--p2').cells[2], {ctrlKey: true});
            check('select-leaves', count() === '2 selected' && inputs() === 'p1,p2' && !document.getElementById('apply').disabled);
            // A caller control in a group row keeps its own behaviour.
            click(document.getElementById('mode-Bakery'));
            check('group-control-no-select', count() === '2 selected' && row('group--Bakery').getAttribute('aria-selected') === 'false');
            // Regroup by rule: p1/p2 sit in the lazy "Shops" group, not loaded.
            // (A re-render keeps the branches the user opened: close Acme first.)
            toggle('group--Acme');
            await regroup('rule');
            check('regroup-keeps-selection', count() === '2 selected (2 in collapsed groups)' && inputs() === 'p1,p2');
            check('rule-groups', shown() === 'group--Shops,group--Media');
            // p3 is listed in Shops (not loaded) and in Media: one item.
            check('rule-count-once', total() === '7 of 7 rows shown');
            // Selecting a whole group submits it under tx_group, with its grouping.
            click(row('group--Media').cells[2], {ctrlKey: true});
            check('group-selection', groups() === '["Media"]' && new FormData(document.getElementById('bulk')).get('group_by') === 'rule' &&
                count() === '3 selected (2 in collapsed groups)');
            // Media is eager: p3 and p5 are listed there and (lazily) in Shops too.
            toggle('group--Media');
            click(row('group--Media--p3').cells[2], {ctrlKey: true});
            check('copy-selected', count() === '4 selected (2 in collapsed groups)' && inputs() === 'p1,p2,p3');
            // Search reaches the rows of a group that has not loaded yet.
            search('bakery');
            check('search-lazy-members', shown() === 'group--Shops' && !row('group--Shops').querySelector('[data-htmxo-tree-toggle]').disabled);
            check('search-lazy-count', total() === '2 of 7 rows shown');
            toggle('group--Shops');
            await wait(() => row('group--Shops--p4'));
            check('search-after-load', shown() === 'group--Shops,group--Shops--p4,group--Shops--p6' && total() === '2 of 7 rows shown');
            check('both-copies-selected', row('group--Shops--p3').getAttribute('aria-selected') === 'true' &&
                row('group--Media--p3').getAttribute('aria-selected') === 'true');
            check('filter-wording', count() === '4 selected (4 hidden by the filter)' && inputs() === 'p1,p2,p3');
            search('');
            check('collapsed-wording', count() === '4 selected');
            toggle('group--Shops');
            toggle('group--Media');
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
            check('expand-all-loads', rows().filter(r => !r.hidden).length === rows().length && rows().length === 4 + 7 &&
                total() === '7 of 7 rows shown');
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
        page = repr("text/html", htmx(bulk, table(["party"]), driver;
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
                html(table(levels(uri), get(q, "q", "")))
            elseif uri.path == "/rows"
                html(table(levels(uri), "", q["key"]))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 25
            end
        finally
            close(server)
        end
    end
end

@testitem "regroupable table row updates browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Server state the row actions change: flags per payment, a mode per
        # group, and the payments themselves (moved between parties, deleted).
        data = collect(TX)
        flagged = Set{String}()
        modes = Dict{String,String}()
        esc = HTTP.escapeuri
        # The levels as a request sends them, and back; a group's path key.
        gbq(group_by) = join(("group_by=$(esc(g))" for g in group_by), '&')
        levels(uri) = [String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"]
        path(k) = "[\"$k\"]"
        table(group_by; q="", kw...) = master_detail_table(["Party", "IBAN", "Amount", "Flag"], data;
            key=t -> t.id,
            master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount)),
                h.td(h.span(t.id in flagged ? "flagged" : "-"; class="flag"),
                     h.button("flag"; type="button", data_flag=t.id,
                         hx_post="/flag?id=$(t.id)&$(gbq(group_by))", hx_target="closest tr", hx_swap="outerHTML"))),
            detail=t -> h.p("memo $(t.id) ", t.id in flagged ? "flagged" : "plain"),
            groupings=GROUPINGS, group_by, group_by_url="/table",
            group_rows_url=(k, ms) -> length(ms) > 2 ? "/rows?$(gbq(group_by))&key=$(esc(k))" : nothing,
            group_master=(k, ms) -> (h.td(h.strong(last(HTMXObjects.group_path(k))), " ", h.small("($(length(ms)))")),
                h.td(h.select(; name="mode", data_mode=k, hx_post="/mode?group=$(esc(k))&$(gbq(group_by))")(
                    h.option("off"; selected=get(modes, k, "off") == "off"), h.option("on"; selected=get(modes, k, "off") == "on"))),
                h.td(string(count(m -> m.id in flagged, ms), " flagged")), h.td(get(modes, k, "off"))),
            selectable="tx", select_form="bulk", searchable=true, search_query=q,
            expand_controls=group_by != ["none"], id="g", kw...)
        bulk = h.form(; id="bulk")(h.button("Apply"; id="apply", data_htmxo_needs_selection="tx", disabled=true))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const settle = () => new Promise(r => setTimeout(r, 50));
            const g = () => document.querySelector('[data-htmxo-grouped]');
            const body = () => g().querySelector('tbody');
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const rows = () => Array.from(body().rows).filter(r => !r.id.startsWith('detail-'));
            const order = () => Array.from(body().rows).map(r => r.id).join(',');
            const shown = () => rows().filter(r => !r.hidden).map(r => r.id.slice(4)).join(',');
            const under = id => rows().filter(r => r.dataset.htmxoParent === 'row-' + id).map(r => r.id.slice(4)).join(',');
            const count = () => g().querySelector('[data-htmxo-selection-count]').textContent;
            const inputs = () => new FormData(document.getElementById('bulk')).getAll('tx').sort().join(',');
            const click = (el, mods = {}) => el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ...mods}));
            const toggle = id => row(id).querySelector('[data-htmxo-tree-toggle]').click();
            const flagText = id => row(id).querySelector('.flag').textContent;
            const search = v => { const i = g().querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            // Group by one grouping alone (or none), as the pills ask for it.
            const regroup = async v => {
                const levels = v === 'none' ? [] : [v];
                htmxoGroupRequest(g().querySelector('.htmxo-group-pills'), levels, null);
                await wait(() => g().dataset.htmxoGrouped === JSON.stringify(levels));
                await settle();
            };
            const flag = async id => {
                const before = row(id), button = before.querySelector('[data-flag]');
                button.focus();
                button.click();
                await wait(() => row(id) !== before);
                await settle();
            };
            const post = async (url, source) => { await htmx.ajax('POST', url, {source, target: source, swap: 'outerHTML'}); await settle(); };
            const total = () => g().querySelector('[data-htmxo-table-count]').textContent;
            const leaked = () => document.querySelectorAll('tr tbody, tr tr, td > tbody').length;

            // A lazy group, an open detail and a selection to keep.
            toggle('group--Acme');
            await wait(() => row('group--Acme--p1'));
            row('group--Acme--p1').querySelector('[data-htmxo-detail-toggle]').click();
            click(row('group--Acme--p1').cells[2]);
            click(row('group--Acme--p2').cells[2], {ctrlKey: true});
            const layout = order(), counted = total();
            check('setup', count() === '2 selected' && !detail('group--Acme--p1').hidden);
            // The row's own button (hx-target="closest tr", outerHTML) gets a
            // row update back: the runtime puts it in place of every copy.
            const old = row('group--Acme--p1');
            await flag('group--Acme--p1');
            const p1 = row('group--Acme--p1');
            check('leaf-replaced', p1 !== old && !old.isConnected && flagText('group--Acme--p1') === 'flagged' && leaked() === 0);
            check('leaf-keeps-place', order() === layout && total() === counted);
            check('leaf-keeps-detail', !detail('group--Acme--p1').hidden && detail('group--Acme--p1').textContent.includes('flagged') &&
                p1.querySelector('[data-htmxo-detail-toggle]').getAttribute('aria-expanded') === 'true' && p1.dataset.htmxoDetailOpen === 'true');
            check('leaf-keeps-selection', count() === '2 selected' && inputs() === 'p1,p2' && p1.getAttribute('aria-selected') === 'true');
            check('leaf-keeps-focus', document.activeElement === p1.querySelector('[data-flag]'));
            check('group-summary', row('group--Acme').cells[2].textContent === '1 flagged' &&
                row('group--Acme').dataset.htmxoTreeOpen === 'true' && !('htmxoLazyRows' in row('group--Acme').dataset) && !p1.hidden);
            // The search and its predicates hold across an update.
            search('acme');
            const matching = shown();
            await flag('group--Acme--p2');
            check('leaf-keeps-search', shown() === matching && flagText('group--Acme--p2') === 'flagged' &&
                g().querySelector('input[type="search"]').value === 'acme');
            search('');
            // A group update: Bakery (eager, closed) changes mode in place and stays closed.
            const bakery = row('group--Bakery');
            const mode = bakery.querySelector('select[data-mode]');
            mode.value = 'on';
            mode.dispatchEvent(new Event('change', {bubbles: true}));
            await wait(() => row('group--Bakery') !== bakery);
            await settle();
            check('group-replaced', row('group--Bakery').cells[3].textContent === 'on' && row('group--Bakery').querySelector('select').value === 'on');
            check('group-stays-closed', row('group--Bakery').dataset.htmxoTreeOpen === 'false' && under('group--Bakery') === 'group--Bakery--p4,group--Bakery--p6' &&
                row('group--Bakery--p4').hidden && order() === layout);
            // A leaf that moves (update_rows + both groups): it leaves Acme and
            // joins Bakery where a full render has it (first: p2 comes before
            // p4 and p6), still selected; both summaries follow, and Bakery,
            // which p2 now opens, moves up behind Acme.
            await post('/move?id=p2&to=Bakery&group_by=party', row('group--Acme--p2'));
            check('moved', !row('group--Acme--p2') && !detail('group--Acme--p2') && under('group--Bakery') === 'group--Bakery--p2,group--Bakery--p4,group--Bakery--p6' &&
                row('group--Acme').cells[0].textContent.includes('(2)') && row('group--Bakery').cells[0].textContent.includes('(3)'));
            check('moved-selection', inputs() === 'p1,p2' && count() === '2 selected (1 in collapsed groups)');
            check('moved-controls', row('group--Acme').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-group--Acme--p1 row-group--Acme--p7' &&
                row('group--Bakery').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-group--Bakery--p2 row-group--Bakery--p4 row-group--Bakery--p6');
            // A deleted leaf leaves; a group that empties leaves; a new group
            // joins where a full render has it (here, last).
            await post('/delete?id=p7&group_by=party', row('group--Acme--p7'));
            check('deleted', !row('group--Acme--p7') && !detail('group--Acme--p7') && under('group--Acme') === 'group--Acme--p1');
            await post('/move?id=p5&to=Zed&group_by=party', row('group--Prime--Video'));
            const groups = rows().filter(r => 'htmxoGroup' in r.dataset).map(r => r.id.slice(4)).join(',');
            check('groups-follow', !row('group--Prime--Video') && !row('group--Prime--Video--p5') && row('group--Zed--p5') &&
                groups === 'group--Acme,group--Bakery,group--Acme--Prime,group--Zed');
            check('no-leaks', leaked() === 0 && document.querySelectorAll('tbody[data-htmxo-row-update]').length === 0);
            // Rows rendered for another grouping are refused, loudly, and change
            // nothing (htmx leaves an empty class on the row it sent the request from).
            // A request from inside the table sends the grouping it shows, so
            // this one comes from outside it.
            const markup = () => body().innerHTML.replace(/ class=""/g, '');
            const snapshot = markup();
            const stale = () => htmx.ajax('POST', '/flag?id=p1&group_by=iban', {source: document.body, target: row('group--Acme--p1'), swap: 'outerHTML'}).then(settle);
            await stale();
            check('wrong-grouping', markup() === snapshot &&
                /grouped by .*iban.* but the table by .*party/.test((document.querySelector('.htmxo-toast-error') || {}).textContent || ''));
            await stale();   // back to flagged on the server
            // Every copy of a leaf: p3 is listed under Shops and Media.
            toggle('group--Bakery');
            await regroup('rule');
            toggle('group--Shops');
            await wait(() => row('group--Shops--p3'));
            toggle('group--Media');
            await flag('group--Media--p3');
            check('copies', flagText('group--Shops--p3') === 'flagged' && flagText('group--Media--p3') === 'flagged' &&
                row('group--Shops').cells[2].textContent === '3 flagged' && row('group--Media').cells[2].textContent === '1 flagged');
            // A re-render keeps the branches the user opened: party again.
            await regroup('party');
            await wait(() => row('group--Bakery--p4') && !row('group--Bakery--p4').hidden);
            check('branches-kept', row('group--Acme').dataset.htmxoTreeOpen === 'true' && row('group--Bakery').dataset.htmxoTreeOpen === 'true' &&
                row('group--Zed').dataset.htmxoTreeOpen === 'false' && !row('group--Acme--p1').hidden && row('group--Zed--p5').hidden);
            // The flat view: rows by id, detail state kept; the leaf's label
            // is its detail control, as in a grouping.
            await regroup('none');
            row('p4').querySelector('[data-htmxo-detail-toggle]').click();
            await flag('p4');
            check('flat', flagText('p4') === 'flagged' && !detail('p4').hidden && detail('p4').textContent.includes('flagged') &&
                row('p4').querySelector('[data-htmxo-detail-toggle]').getAttribute('aria-expanded') === 'true' && order().split(',').length === 2 * 6);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(bulk, table(["party"]), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        party(id) = only(t.party for t in data if t.id == id)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            form = HTTP.queryparams(String(req.body))
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/table"
                html(table(levels(uri); q=get(q, "q", "")))
            elseif uri.path == "/rows"
                html(table(levels(uri); group_rows=q["key"]))
            elseif uri.path == "/flag"
                id = q["id"]
                id in flagged ? delete!(flagged, id) : push!(flagged, id)
                html(table(levels(uri); update_rows=id))
            elseif uri.path == "/mode"
                modes[q["group"]] = form["mode"]
                html(table(levels(uri); update_groups=q["group"]))
            elseif uri.path == "/move"
                id, from = q["id"], party(q["id"])
                data[findfirst(t -> t.id == id, data)] = (; only(t for t in data if t.id == id)..., party=q["to"])
                html(table(levels(uri); update_rows=id, update_groups=[path(from), path(q["to"])]))
            elseif uri.path == "/delete"
                id, from = q["id"], party(q["id"])
                filter!(t -> t.id != id, data)
                html(table(levels(uri); update_rows=id, update_groups=path(from)))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 20
            end
        finally
            close(server)
        end
    end
end

@testitem "grouping pills browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        esc = HTTP.escapeuri
        query(group_by) = join(("group_by=$(esc(g))" for g in group_by), "&")
        table(group_by, q="", group_rows=nothing) = grouped(; group_by, search_query=q, group_rows,
            group_by_url="/table",
            group_rows_url=(k, ms) -> length(ms) > 2 ? "/rows?$(query(group_by))&key=$(esc(k))" : nothing,
            selectable="tx", select_form="bulk", searchable=true, expand_controls=true, id="g")
        bulk = h.form(; id="bulk")(h.button("Apply"; id="apply", data_htmxo_needs_selection="tx", disabled=true))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const stage = name => { document.body.dataset.stage = name; };
            const wait = async cond => { for (let n = 0; n < 250 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const g = () => document.querySelector('[data-htmxo-grouped]');
            const row = id => document.getElementById('row-' + id);
            const rows = () => Array.from(g().querySelector('tbody').rows).filter(r => !r.id.startsWith('detail-'));
            const shown = () => rows().filter(r => !r.hidden).map(r => r.id.slice(4)).join(',');
            const pill = n => g().querySelector('.htmxo-group-pill[data-htmxo-group-name="' + n + '"]');
            const toggle = n => pill(n).querySelector('button');
            const levels = () => JSON.parse(g().dataset.htmxoGrouped);
            const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
            const regrouped = async want => { const ok = await wait(() => same(levels(), want)); await new Promise(r => setTimeout(r, 60)); return ok; };
            const pressed = () => Array.from(g().querySelectorAll('.htmxo-group-pill')).map(p =>
                p.dataset.htmxoGroupName + (p.querySelector('button').getAttribute('aria-pressed') === 'true' ? '+' : '-')).join(',');
            const form = name => new FormData(document.getElementById('bulk')).getAll(name).join(',');
            const click = (el, mods = {}) => el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ...mods}));
            const total = () => g().querySelector('[data-htmxo-table-count]').textContent;
            const key = (el, k) => el.dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true, cancelable: true}));
            const drag = (from, onto, after) => {
                const dt = new DataTransfer();
                pill(from).dispatchEvent(new DragEvent('dragstart', {bubbles: true, dataTransfer: dt}));
                const box = pill(onto).getBoundingClientRect();
                const at = {bubbles: true, cancelable: true, dataTransfer: dt,
                    clientX: after ? box.right - 2 : box.left + 2, clientY: box.top + box.height / 2};
                toggle(onto).dispatchEvent(new DragEvent('dragover', at));
                const marked = pill(onto).dataset.htmxoDrop;
                toggle(onto).dispatchEvent(new DragEvent('drop', at));
                pill(from).dispatchEvent(new DragEvent('dragend', {bubbles: true, dataTransfer: dt}));
                return marked;
            };
            stage('initial');
            check('initial', same(levels(), ['party']) && pressed() === 'party+,iban-,rule-' &&
                same(htmxoGroupBy('#g'), ['party']) && form('group_by') === 'party' && !g().querySelector('select[name="group_by"]'));
            // A pill adds its level as the innermost one; focus stays on it.
            stage('add-iban');
            toggle('iban').focus();
            toggle('iban').click();
            check('add-level', await regrouped(['party', 'iban']));
            check('add-pills', pressed() === 'party+,iban+,rule-' && document.activeElement && document.activeElement.id === 'g-group-iban');
            check('nested-rows', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video' && total() === '7 of 7 rows shown');
            row('group--Bakery').querySelector('[data-htmxo-tree-toggle]').click();
            row('group--Bakery--DE03').querySelector('[data-htmxo-tree-toggle]').click();
            check('open-nested', shown().includes('group--Bakery,group--Bakery--DE03,group--Bakery--DE03--p4,group--Bakery--DE03--p6') &&
                row('group--Bakery--DE03').getAttribute('aria-level') === '2' && row('group--Bakery--DE03--p4').getAttribute('aria-level') === '3');
            // ←/→ on a focused active pill reorders it, keeping the focus.
            stage('arrow');
            key(document.activeElement, 'ArrowLeft');
            check('arrow-reorder', await regrouped(['iban', 'party']));
            check('arrow-focus', document.activeElement && document.activeElement.id === 'g-group-iban' && pressed() === 'iban+,party+,rule-');
            // ‹ moves a level outward; at the end of the bar the focus moves to the pill itself.
            stage('move');
            const earlier = document.getElementById('g-group-party-earlier');
            earlier.focus();
            earlier.click();
            check('move-reorder', await regrouped(['party', 'iban']));
            check('move-focus', document.getElementById('g-group-party-earlier').disabled && document.activeElement &&
                document.activeElement.id === 'g-group-party');
            // Dragging an inactive pill before an active one adds it at that level.
            stage('drag-add');
            check('drag-marker', drag('rule', 'party', false) === 'before');
            check('drag-add', await regrouped(['rule', 'party', 'iban']) && !g().querySelector('[data-htmxo-drop]'));
            // Dragging an active pill after another reorders.
            stage('drag-move');
            check('drag-marker-after', drag('party', 'iban', true) === 'after');
            check('drag-move', await regrouped(['rule', 'iban', 'party']));
            check('three-levels', shown() === 'group--Shops,group--Media' && total() === '7 of 7 rows shown' &&
                'htmxoLazyRows' in row('group--Shops').dataset);
            // A selected nested group submits its path, with the grouping.
            stage('select');
            row('group--Media').querySelector('[data-htmxo-tree-toggle]').click();
            click(row('group--Media--DE01').cells[2], {ctrlKey: true});
            check('select-path', form('tx_group') === '["Media","DE01"]' && form('group_by') === 'rule,iban,party');
            click(row('group--Media').cells[2], {ctrlKey: true});
            check('select-outer-path', form('tx_group').split(',["').length === 2 && form('tx_group').includes('["Media"]'));
            // Expand all loads the lazy group and, inside it, its own lazy subgroup.
            stage('expand');
            g().querySelector('.htmxo-tree-controls > button').click();
            check('expand-nested-lazy', await wait(() => rows().length === 21 && !rows().some(r => 'htmxoLazyRows' in r.dataset)));
            await new Promise(r => setTimeout(r, 60));
            check('expand-all-open', rows().every(r => !r.hidden) && total() === '7 of 7 rows shown' &&
                row('group--Shops--DE01--Acme--p7').getAttribute('aria-level') === '4');
            // A regroup carries the search; removing a level keeps the others' order.
            stage('search');
            const input = g().querySelector('input[type="search"]');
            input.value = 'bakery';
            input.dispatchEvent(new Event('input', {bubbles: true}));
            toggle('iban').click();
            check('remove-level', await regrouped(['rule', 'party']));
            check('search-kept', g().querySelector('input[type="search"]').value === 'bakery' && same(htmxoGroupBy('#g'), ['rule', 'party']));
            // No pill is the flat view: the leaves, with the selection kept.
            stage('flat');
            input.value = '';
            g().querySelector('input[type="search"]').value = '';
            toggle('rule').click();
            await regrouped(['party']);
            toggle('party').click();
            check('flat', await regrouped([]));
            check('flat-rows', rows().length === 7 && same(htmxoGroupBy('#g'), ['none']) && pressed() === 'party-,iban-,rule-' &&
                form('group_by') === 'none');
            stage('done');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(bulk, table(["party"]), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        requests = String[]
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            pairs = HTTP.URIs.queryparampairs(uri)
            group_by = [v for (k, v) in pairs if k == "group_by"]
            param(name) = something((v for (k, v) in pairs if k == name)..., "")
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            uri.path == "/" || push!(requests, req.target)
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/table"
                html(table(group_by, param("q")))
            elseif uri.path == "/rows"
                html(table(group_by, "", param("key")))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if isnothing(checks)
                @info "grouping pills browser: no checks" stage=match(r"data-stage=\"([^\"]*)\"", dom) requests
            else
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 22
            end
            # The levels travel as repeated group_by values; none sends the flat grouping.
            @test any(startswith("/table?group_by=party&group_by=iban&q="), requests)
            @test any(startswith("/table?group_by=none&q="), requests)
            @test any(r -> startswith(r, "/rows?group_by=rule&group_by=iban&group_by=party&key=") &&
                contains(r, HTTP.escapeuri("[\"Shops\",\"DE01\"]")), requests)
        finally
            close(server)
        end
    end
end

@testitem "row updates put new and moved rows where the table renders them browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # A form in its own line order: a line shows once it has a value, and
        # two review groups follow the lines. Receipts sit under their line,
        # by date, or under "Needs a VAT treatment" until they have one.
        form = ["10", "81", "93", "46", "48", "49", "66"]
        values = Dict("81" => 100.0, "93" => 50.0, "66" => 20.0)
        receipts = [(; id="r1", line="93", date="2026-01-10"), (; id="r2", line="93", date="2026-03-01"),
                    (; id="r3", line="", date="2026-02-01")]
        node(id, label, kids) = (; id, label, kids)
        under(line) = [node(r.id, r.date, []) for r in sort(filter(r -> r.line == line, receipts); by=r -> r.date)]
        roots() = [[node("kz$c", "Kz $c", under(c)) for c in form if get(values, c, 0.0) != 0];
                   node("needs", "Needs a VAT treatment", under("")); node("none", "No VAT effect", [])]
        vat(; kw...) = master_detail_table(["Item", "Edit"], roots();
            key=n -> n.id, master=n -> (h.td(n.label), h.td(h.button("edit"; type="button", data_edit=n.id))),
            children=n -> n.kids, detail=n -> startswith(n.id, "r") ? h.p("receipt $(n.id)") : nothing,
            initially_open=n -> !startswith(n.id, "r"), id="vat", kw...)
        # A flat table, unsorted and then sorted by the reader.
        flat = [(; id="f1", amount=10.0), (; id="f2", amount=20.0), (; id="f3", amount=30.0)]
        flats(; kw...) = master_detail_table(["Name", "Amount"], flat; key=f -> f.id,
            master=f -> (h.td(f.id), h.td(string(f.amount))), detail=f -> h.p(f.id), id="flat", kw...)
        # Two grouping levels: n4 moves from B/y into A, where its new
        # subgroup y belongs between w and z.
        nest = [(; id="n1", cat="A", party="w"), (; id="n4", cat="B", party="y"),
                (; id="n2", cat="A", party="z"), (; id="n3", cat="B", party="x")]
        nested(; kw...) = master_detail_table(["Name"], nest; key=t -> t.id, master=t -> (h.td(t.id),),
            detail=t -> h.p(t.id), groupings=["cat" => t -> t.cat, "party" => t -> t.party],
            group_by=["cat", "party"], initially_open=true, id="nest", kw...)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const settle = () => new Promise(r => setTimeout(r, 50));
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const masters = body => Array.from(document.getElementById(body).rows).filter(r => !r.id.startsWith('detail-'));
            const kids = (parent = '') => masters('vat').filter(r => (r.dataset.htmxoParent || '') === (parent && 'row-' + parent)).map(r => r.id.slice(4)).join(',');
            const order = body => Array.from(document.getElementById(body).rows).map(r => r.id).join(',');
            const post = async (url, source) => { await htmx.ajax('POST', url, {source, target: source, swap: 'outerHTML'}); await settle(); };
            const paired = body => Array.from(document.getElementById(body).rows).every(r =>
                !r.id.startsWith('detail-') || (r.previousElementSibling && r.previousElementSibling.id === 'row-' + r.id.slice(7)));

            check('setup', kids() === 'kz81,kz93,kz66,needs,none' && kids('kz93') === 'r1,r2' && detail('r1').hidden);
            // A line that gains a value joins between its form neighbours, not
            // after the review groups.
            await post('/value?line=46&v=5', row('kz81'));
            check('form-order', kids() === 'kz81,kz93,kz46,kz66,needs,none');
            await post('/value?line=10&v=1', row('kz81'));
            check('first', kids() === 'kz10,kz81,kz93,kz46,kz66,needs,none');
            // Kz 48 shows on the server but its update never came: Kz 49 still
            // lands in order, before the line after it.
            await fetch('/value?line=48&v=1&quiet=1', {method: 'POST'});
            await post('/value?line=49&v=1', row('kz81'));
            check('before-next', kids() === 'kz10,kz81,kz93,kz46,kz49,kz66,needs,none');
            // A new receipt joins its line at its date.
            await post('/add?id=r9&line=93&date=2026-02-15', row('kz93'));
            check('child-date', kids('kz93') === 'r1,r9,r2' && paired('vat'));
            // An edited date moves the receipt, with its open detail and the focus.
            row('r1').querySelector('[data-htmxo-detail-toggle]').click();
            const edit = row('r1').querySelector('[data-edit]');
            edit.focus();
            const old = row('r1');
            await post('/date?id=r1&date=2026-04-01', edit);
            check('moved-child', row('r1') !== old && kids('kz93') === 'r9,r2,r1' && paired('vat') &&
                detail('r1').previousElementSibling === row('r1'));
            check('moved-keeps-detail', detail('r1').hidden === false && row('r1').querySelector('[data-htmxo-detail-toggle]').getAttribute('aria-expanded') === 'true');
            check('moved-keeps-focus', document.activeElement === row('r1').querySelector('[data-edit]'));
            // A receipt that gets its line moves there from the review group.
            await post('/line?id=r3&line=46', row('r3'));
            check('reparented', kids('kz46') === 'r3' && kids('needs') === '' && row('r3').previousElementSibling === row('kz46') &&
                kids() === 'kz10,kz81,kz93,kz46,kz49,kz66,needs,none' && paired('vat'));
            check('reparented-controls', row('kz46').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-r3' &&
                row('r3').getAttribute('aria-level') === '2');
            // A parent's key re-renders the parent row alone; a named child
            // that is gone leaves with its detail.
            const r9 = row('r9'), kz93 = row('kz93');
            await post('/value?line=93&v=60', row('kz93'));
            check('parent-only', row('kz93') !== kz93 && row('r9') === r9 && kids('kz93') === 'r9,r2,r1');
            await post('/delete?id=r9&line=93', row('r9'));
            check('child-deleted', !row('r9') && !detail('r9') && kids('kz93') === 'r2,r1' && paired('vat') &&
                row('kz93').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') === 'row-r2 row-r1');
            // A flat table: a new row joins at its place; once the reader
            // sorts, an update keeps the sort, for changed and new rows alike.
            await post('/flat?id=f5&amount=25&after=f2', row('f1'));
            check('flat-insert', order('flat') === 'row-f1,detail-f1,row-f2,detail-f2,row-f5,detail-f5,row-f3,detail-f3');
            sortTable(document.getElementById('flat').closest('table').querySelectorAll('thead th')[1]);
            await post('/flat?id=f2&amount=999', row('f2'));
            check('sorted-change', masters('flat').map(r => r.id.slice(4)).join(',') === 'f1,f5,f3,f2' && paired('flat'));
            await post('/flat?id=f9&amount=15', row('f1'));
            check('sorted-insert', masters('flat').map(r => r.id.slice(4)).join(',') === 'f1,f9,f5,f3,f2' && paired('flat'));
            // Nested groups: the new subgroup A/y lands between A/w and A/z,
            // and B/y, now empty, leaves.
            const nkids = parent => masters('nest').filter(r => r.dataset.htmxoParent === 'row-' + parent).map(r => r.id.slice(4)).join(',');
            check('nested-setup', nkids('group--A') === 'group--A--w,group--A--z' && nkids('group--B') === 'group--B--y,group--B--x');
            await post('/nmove?id=n4&cat=A', row('group--B--y--n4'));
            check('nested-place', nkids('group--A') === 'group--A--w,group--A--y,group--A--z' && nkids('group--A--y') === 'group--A--y--n4' &&
                nkids('group--B') === 'group--B--x' && !row('group--B--y') && paired('nest'));
            check('no-leaks', document.querySelectorAll('tbody[data-htmxo-row-update], tr tr').length === 0);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(vat(), flats(), nested(), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            replace_receipt!(id; kw...) = (i = findfirst(r -> r.id == id, receipts); receipts[i] = (; receipts[i]..., kw...))
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/value"
                values[q["line"]] = parse(Float64, q["v"])
                haskey(q, "quiet") ? HTTP.Response(204) : html(vat(; update_rows="kz" * q["line"]))
            elseif uri.path == "/add"
                push!(receipts, (; id=q["id"], line=q["line"], date=q["date"]))
                html(vat(; update_rows=[q["id"], "kz" * q["line"]]))
            elseif uri.path == "/date"
                replace_receipt!(q["id"]; date=q["date"])
                html(vat(; update_rows=q["id"]))
            elseif uri.path == "/delete"
                filter!(r -> r.id != q["id"], receipts)
                html(vat(; update_rows=[q["id"], "kz" * q["line"]]))
            elseif uri.path == "/line"
                replace_receipt!(q["id"]; line=q["line"])
                html(vat(; update_rows=[q["id"], "kz" * q["line"], "needs"]))
            elseif uri.path == "/nmove"
                i = findfirst(t -> t.id == q["id"], nest)
                old = nest[i]
                nest[i] = (; old..., cat=q["cat"])
                html(nested(; update_rows=old.id, update_groups=[
                    "[\"$(old.cat)\",\"$(old.party)\"]", "[\"$(q["cat"])\",\"$(old.party)\"]"]))
            elseif uri.path == "/flat"
                f = (; id=q["id"], amount=parse(Float64, q["amount"]))
                i = findfirst(x -> x.id == f.id, flat)
                if !isnothing(i)
                    flat[i] = f
                elseif haskey(q, "after")
                    insert!(flat, findfirst(x -> x.id == q["after"], flat) + 1, f)
                else
                    push!(flat, f)
                end
                html(flats(; update_rows=f.id))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
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

@testitem "initially_open groups browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # The reported shape: lazy details, label toggles, search, one leaf opened.
        table(group_by, open_id) = master_detail_table(["Party", "IBAN", "Amount"], TX;
            key=t -> t.id, master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount))),
            detail_url=t -> "/detail?id=$(t.id)", detail_toggle=:label, groupings=GROUPINGS, group_by=[group_by],
            group_rows_url=(k, ms) -> length(ms) > 2 ? "/rows?key=$(HTTP.escapeuri(k))" : nothing,
            initially_open=t -> t.id == open_id, searchable=true, id="g-$group_by")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            try {
            // The table `id` names its <tbody>.
            const shown = t => Array.from(document.getElementById(t).rows)
                .filter(r => !r.id.startsWith('detail-') && !r.hidden).map(r => r.id.slice(4)).join(',');
            // Rule grouping, p3 opened: it is in both groups, so both open.
            const rule = shown('g-rule');
            check('rule-shown ' + rule, rule === 'group--Shops,group--Shops--p1,group--Shops--p2,group--Shops--p3,group--Shops--p4,' +
                'group--Shops--p6,group--Shops--p7,group--Media,group--Media--p3,group--Media--p5');
            await wait(() => detail('group--Shops--p3').textContent.includes('memo 3') && detail('group--Media--p3').textContent.includes('memo 3'));
            check('rule-details', !detail('group--Shops--p3').hidden && detail('group--Shops--p3').textContent.includes('memo 3') &&
                !detail('group--Media--p3').hidden && detail('group--Media--p3').textContent.includes('memo 3'));
            check('rule-aria', row('group--Shops').getAttribute('aria-expanded') === 'true' &&
                row('group--Shops--p3').querySelector('[data-htmxo-detail-toggle]').getAttribute('aria-expanded') === 'true');
            check('rule-others-closed', detail('group--Shops--p1').hidden);
            // Party grouping, p1 opened: lazy-sized Acme renders eagerly and open.
            const party = shown('g-party');
            check('party-shown ' + party, party === 'group--Acme,group--Acme--p1,group--Acme--p2,group--Acme--p7,group--Acme--Prime,group--Bakery,group--Prime--Video');
            check('party-not-lazy', !('htmxoLazyRows' in row('group--Acme').dataset));
            await wait(() => detail('group--Acme--p1').textContent.includes('memo 1'));
            check('party-detail', !detail('group--Acme--p1').hidden && detail('group--Acme--p1').textContent.includes('memo 1'));
            // The user's own toggles still work on a group opened by the predicate.
            row('group--Acme').querySelector('[data-htmxo-tree-toggle]').click();
            const collapsed = shown('g-party');
            check('party-collapse ' + collapsed, collapsed === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video' &&
                detail('group--Acme--p1').hidden);
            } catch (e) { check('threw ' + e, false); }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(table("rule", "p3"), table("party", "p1"), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/detail"
                HTTP.Response(200, ["Content-Type" => "text/html"],
                    repr("text/html", h.p(only(t.memo for t in TX if t.id == q["id"]))))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 8
            end
        finally
            close(server)
        end
    end
end

@testitem "a row update keeps a moved leaf the reader has open in view browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        esc = HTTP.escapeuri
        # Documents under review: an action in a document's (lazy) detail or
        # row moves it to another stage, so its rows change groups.
        docs = [(; id="a1", stage="Review", kind="Invoice"), (; id="a2", stage="Review", kind="Receipt"),
                (; id="a3", stage="Review", kind="Invoice")]
        nest = [(; id="b1", stage="Todo", kind="Invoice"), (; id="b2", stage="Done", kind="Receipt")]
        stages = Dict(d.id => d.stage for d in [docs; nest])
        kinds = Dict(d.id => d.kind for d in [docs; nest])
        groupings = ["Stage" => d -> stages[d.id], "Kind" => d -> kinds[d.id], "None" => nothing]
        move_url(id, to, gb) = "/move?id=$id&to=$to&gb=$gb"
        # One level, eager groups, all closed at first.
        single(; kw...) = master_detail_table(["Document", "Act"], docs; key=d -> d.id,
            master=d -> (h.td(d.id), h.td(h.button("exclude"; type="button", data_exclude=d.id,
                hx_post=move_url(d.id, "Excluded", "single"), hx_target="closest tr", hx_swap="outerHTML"))),
            detail_url=d -> "/detail?id=$(d.id)&gb=single", detail_toggle=:label,
            groupings, group_by=["Stage"], searchable=true, id="docs", kw...)
        # Two levels, every group lazy.
        nested(; kw...) = master_detail_table(["Document"], nest; key=d -> d.id, master=d -> (h.td(d.id),),
            detail_url=d -> "/detail?id=$(d.id)&gb=nested", detail_toggle=:label,
            groupings, group_by=["Stage", "Kind"],
            group_rows_url=(k, ms) -> "/rows?key=$(esc(k))", searchable=true, id="nest", kw...)
        # A tree: a child moves to a closed parent.
        parents = Dict("c1" => "P1", "c2" => "P1", "c3" => "P2")
        roots() = [(; id=p, kids=[(; id=c, kids=[]) for c in sort([c for (c, q) in parents if q == p])]) for p in ("P1", "P2")]
        tree(; kw...) = master_detail_table(["Item"], roots(); key=n -> n.id, master=n -> (h.td(n.id),),
            children=n -> n.kids, initially_open=n -> n.id == "P1",
            detail=n -> startswith(n.id, "c") ? h.div(h.p("child $(n.id) of $(parents[n.id])"),
                h.button("move"; type="button", data_move=n.id, hx_post="/cmove?id=$(n.id)",
                    hx_target="closest tr", hx_swap="outerHTML")) : nothing,
            id="tree", kw...)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const settle = () => new Promise(r => setTimeout(r, 50));
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const toggle = id => row(id).querySelector('[data-htmxo-tree-toggle]').click();
            const control = id => row(id).querySelector('[data-htmxo-detail-toggle]');
            const openDetail = async id => { control(id).click(); await wait(() => detail(id).querySelector('[data-approve]')); };
            const act = async (button, gone) => { button.focus(); button.click(); await wait(() => !gone.isConnected); await settle(); };
            const shownOpen = id => row(id) && !row(id).hidden && !detail(id).hidden && control(id).getAttribute('aria-expanded') === 'true';
            try {
            // A document whose detail is open, the focus in it, moves to a
            // group the update creates: the group opens, the detail stays
            // open (and loads again), the focus goes to the row's control.
            toggle('group--Review');
            await openDetail('group--Review--a1');
            await act(detail('group--Review--a1').querySelector('[data-approve]'), row('group--Review--a1'));
            check('new-group-opens', row('group--Approved') && row('group--Approved').dataset.htmxoTreeOpen === 'true' &&
                row('group--Approved').getAttribute('aria-expanded') === 'true' && !row('group--Review--a1'));
            check('new-group-detail', shownOpen('group--Approved--a1'));
            check('new-group-focus', document.activeElement === control('group--Approved--a1'));
            await wait(() => detail('group--Approved--a1').textContent.includes('a1 Approved'));
            check('new-group-detail-loads', detail('group--Approved--a1').textContent.includes('a1 Approved'));
            // The same into a group the reader closed.
            toggle('group--Approved');
            await openDetail('group--Review--a2');
            await act(detail('group--Review--a2').querySelector('[data-approve]'), row('group--Review--a2'));
            check('closed-group-opens', row('group--Approved').dataset.htmxoTreeOpen === 'true' &&
                shownOpen('group--Approved--a2') && !row('group--Approved--a1').hidden);
            check('closed-group-focus', document.activeElement === control('group--Approved--a2'));
            // A document whose detail is closed: its new group stays as it
            // is, and the focus goes to the group row that now holds it.
            await act(row('group--Review--a3').querySelector('[data-exclude]'), row('group--Review--a3'));
            check('closed-detail-stays', row('group--Excluded').dataset.htmxoTreeOpen === 'false' && row('group--Excluded--a3').hidden &&
                detail('group--Excluded--a3').hidden);
            check('closed-detail-focus', document.activeElement === row('group--Excluded').querySelector('[data-htmxo-tree-toggle]'));
            // Two levels of lazy groups: Done and its new subgroup load and
            // open on the way to the document; Done's other subgroup stays as it is.
            toggle('group--Todo');
            await wait(() => row('group--Todo--Invoice'));
            toggle('group--Todo--Invoice');
            await wait(() => row('group--Todo--Invoice--b1'));
            await openDetail('group--Todo--Invoice--b1');
            check('lazy-setup', 'htmxoLazyRows' in row('group--Done').dataset && !row('group--Done--Invoice'));
            await act(detail('group--Todo--Invoice--b1').querySelector('[data-approve]'), row('group--Todo--Invoice--b1'));
            await wait(() => row('group--Done--Invoice--b1') && document.activeElement === control('group--Done--Invoice--b1'));
            check('lazy-groups-open', !row('group--Todo') && !('htmxoLazyRows' in row('group--Done').dataset) &&
                row('group--Done').dataset.htmxoTreeOpen === 'true' && row('group--Done--Invoice').dataset.htmxoTreeOpen === 'true' &&
                'htmxoLazyRows' in row('group--Done--Receipt').dataset);
            check('lazy-detail', shownOpen('group--Done--Invoice--b1'));
            check('lazy-focus', document.activeElement === control('group--Done--Invoice--b1'));
            // A tree: a child moves under a closed parent with its (eager)
            // detail open and the focus in it, which returns to the same control.
            control('c1').click();
            await act(detail('c1').querySelector('[data-move]'), row('c1'));
            check('tree-parent-opens', row('P2').dataset.htmxoTreeOpen === 'true' && row('c1').dataset.htmxoParent === 'row-P2' &&
                !row('c1').hidden && !detail('c1').hidden && detail('c1').textContent.includes('of P2'));
            check('tree-focus', document.activeElement === detail('c1').querySelector('[data-move]'));
            check('no-leaks', document.querySelectorAll('tbody[data-htmxo-row-update], tr tr').length === 0);
            } catch (e) { check('threw ' + e, false); }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(single(), nested(), tree(), driver;
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
            elseif uri.path == "/detail"
                id = q["id"]
                html(h.div(h.p("doc $id $(stages[id])"), h.button("approve"; type="button", data_approve=id,
                    hx_post=move_url(id, q["gb"] == "single" ? "Approved" : "Done", q["gb"]),
                    hx_target="closest tr", hx_swap="outerHTML")))
            elseif uri.path == "/rows"
                html(nested(; group_rows=q["key"]))
            elseif uri.path == "/move"
                id, from, to = q["id"], stages[q["id"]], q["to"]
                stages[id] = to
                html((q["gb"] == "single" ? single : nested)(; update_rows=id, update_groups=["[\"$from\"]", "[\"$to\"]"]))
            elseif uri.path == "/cmove"
                id = q["id"]
                from = parents[id]
                parents[id] = from == "P1" ? "P2" : "P1"
                html(tree(; update_rows=[id, from, parents[id]]))
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 15
            end
        finally
            close(server)
        end
    end
end

@testitem "a row update keeps the hx-preserve elements of its rows browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Invoices whose detail holds a disclosure that loads the invoice's
        # editor into itself when the reader opens it; saving in the editor
        # answers with a row update. `ed-*` disclosures are hx-preserve,
        # `plain-*` ones are not.
        hours = Dict(id => 0 for id in ("e1", "e2", "l1", "l2", "g1", "m1"))
        stage = Dict("g1" => "Open", "m1" => "Open")
        save_url(id, t) = "/save?id=$id&t=$t"
        disclosure(id, t; preserve=true) = h.details(; id=(preserve ? "ed-" : "plain-") * id,
            (preserve ? (; hx_preserve=true) : (;))...,
            hx_get="/editor?id=$id&t=$t", hx_trigger="toggle once", hx_target="find .ed", hx_swap="innerHTML")(
            h.summary("Edit $id"), h.div(; class="ed"))
        body(id, t) = h.div(h.p(; class="rev")("rev $(hours[id])"), disclosure(id, t),
            disclosure(id, t; preserve=false))
        cells(x) = (h.td(x.id), h.td(h.span(; class="hours")(string(hours[x.id]))),
            h.td(h.button("bump"; type="button", data_bump=x.id, hx_post=save_url(x.id, "bump"),
                hx_target="closest tr", hx_swap="outerHTML")))
        items(ids) = [(; id) for id in ids]
        eager(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], items(["e1", "e2"]);
            key=x -> x.id, master=cells, detail=x -> body(x.id, "eager"), id="eager", kw...)
        lazy(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], items(["l1", "l2"]);
            key=x -> x.id, master=cells, detail_url=x -> "/detail?id=$(x.id)", id="lazy", kw...)
        # Grouped by stage: saving moves the invoice to "Saved".
        grouped(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], items(["g1"]);
            key=x -> x.id, master=cells, detail=x -> body(x.id, "grouped"),
            groupings=["Stage" => x -> stage[x.id]], group_by=["Stage"], initially_open=true, id="grouped", kw...)
        moved(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], items(["m1"]);
            key=x -> x.id, master=cells, detail_url=x -> "/detail?id=$(x.id)",
            groupings=["Stage" => x -> stage[x.id]], group_by=["Stage"], initially_open=true, id="moved", kw...)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            const settle = () => new Promise(r => setTimeout(r, 50));
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const control = id => row(id).querySelector('[data-htmxo-detail-toggle]');
            const hoursOf = id => row(id).querySelector('.hours').textContent;
            const revOf = id => { const p = detail(id).querySelector('.rev'); return p && p.textContent; };
            // Open a row's detail, then its disclosure(s), and type into the
            // editors they load.
            const edit = async (rid, id, plain) => {
                if (detail(rid).hidden) control(rid).click();
                await wait(() => document.getElementById('ed-' + id));
                for (const d of plain ? ['ed-', 'plain-'] : ['ed-']) {
                    const el = document.getElementById(d + id);
                    el.open = true;
                    await wait(() => el.querySelector('.note'));
                    el.querySelector('.note').value = 'typed ' + d;
                }
                await settle();   // htmx binds the loaded editor as it settles
                const ed = document.getElementById('ed-' + id);
                ed.htmxoMark = 'kept';
                return ed;
            };
            const kept = (ed, id, rid) => document.getElementById('ed-' + id) === ed && ed.htmxoMark === 'kept' && ed.open &&
                ed.querySelector('.note').value === 'typed ed-' && detail(rid).contains(ed);
            const save = async (ed, rid, before) => {
                const b = ed.querySelector('[data-save]'); b.focus(); b.click();
                await wait(() => !row(rid) || hoursOf(rid) !== before); await settle();
                return b;
            };
            try {
            // An eager detail: the update replaces the detail's content, and the
            // disclosure marked hx-preserve stays as the reader left it.
            let ed = await edit('e1', 'e1', true);
            let b = await save(ed, 'e1', '0');
            check('eager-master', hoursOf('e1') === '1');
            check('eager-detail-open', !detail('e1').hidden && control('e1').getAttribute('aria-expanded') === 'true');
            check('eager-rest-refreshes', revOf('e1') === 'rev 1');
            check('eager-preserved', kept(ed, 'e1', 'e1'));
            check('eager-plain-replaced', !document.getElementById('plain-e1').open && !document.getElementById('plain-e1').querySelector('.note'));
            check('eager-focus', document.activeElement === b);
            // The kept editor still works: saving again updates the row again.
            await save(ed, 'e1', '1');
            check('eager-again', hoursOf('e1') === '2' && kept(ed, 'e1', 'e1'));
            // An update from a master cell keeps it as well.
            row('e1').querySelector('[data-bump]').click();
            await wait(() => hoursOf('e1') === '3'); await settle();
            check('eager-bump', kept(ed, 'e1', 'e1') && revOf('e1') === 'rev 3');
            // Without Element.prototype.moveBefore (browsers before it), the
            // same, and the focus returns to the same control.
            const moveBefore = Element.prototype.moveBefore;
            delete Element.prototype.moveBefore;
            try {
                ed = await edit('e2', 'e2');
                b = await save(ed, 'e2', '0');
                check('fallback-preserved', hoursOf('e2') === '1' && revOf('e2') === 'rev 1' && kept(ed, 'e2', 'e2'));
                check('fallback-focus', document.activeElement === b);
            } finally { if (moveBefore) Element.prototype.moveBefore = moveBefore; }
            // An open lazy detail loads again, and its reload keeps the
            // hx-preserve element of the content it had.
            ed = await edit('l1', 'l1');
            await save(ed, 'l1', '0');
            await wait(() => revOf('l1') === 'rev 1'); await settle();
            check('lazy-reloads', hoursOf('l1') === '1' && revOf('l1') === 'rev 1');
            check('lazy-preserved', kept(ed, 'l1', 'l1'));
            // A closed lazy detail: the editor waits for the next expand.
            ed = await edit('l2', 'l2');
            control('l2').click();
            row('l2').querySelector('[data-bump]').click();
            await wait(() => hoursOf('l2') === '1'); await settle();
            check('lazy-closed-waits', detail('l2').hidden && detail('l2').querySelector('[data-loaded]').dataset.loaded === '0');
            control('l2').click();
            await wait(() => revOf('l2') === 'rev 1'); await settle();
            check('lazy-closed-preserved', kept(ed, 'l2', 'l2'));
            // A leaf that moves to another group: its new copy has it.
            ed = await edit('group--Open--g1', 'g1');
            await save(ed, 'group--Open--g1', '0');
            await wait(() => row('group--Saved--g1')); await settle();
            check('moved-preserved', !row('group--Open--g1') && hoursOf('group--Saved--g1') === '1' &&
                revOf('group--Saved--g1') === 'rev 1' && kept(ed, 'g1', 'group--Saved--g1') && !detail('group--Saved--g1').hidden);
            // The same with a lazy detail, which loads again in the new copy.
            ed = await edit('group--Open--m1', 'm1');
            await save(ed, 'group--Open--m1', '0');
            await wait(() => row('group--Saved--m1') && revOf('group--Saved--m1') === 'rev 1'); await settle();
            check('moved-lazy-preserved', !row('group--Open--m1') && kept(ed, 'm1', 'group--Saved--m1'));
            check('no-leaks', document.querySelectorAll('[data-htmxo-preserved], tbody[data-htmxo-row-update]').length === 0 &&
                document.querySelectorAll('[id^="ed-"]').length === 6 && !document.body.nextElementSibling);
            } catch (e) { check('threw ' + e, false); }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(eager(), lazy(), grouped(), moved(), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            q = HTTP.queryparams(uri)
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            table(id) = id in ("e1", "e2") ? eager : id in ("l1", "l2") ? lazy : id == "g1" ? grouped : moved
            if uri.path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif uri.path == "/detail"
                html(body(q["id"], "lazy"))
            elseif uri.path == "/editor"
                id = q["id"]
                html(h.div(h.input(; name="note", class="note"), h.button("save"; type="button", data_save=id,
                    hx_post=save_url(id, q["t"]), hx_target="closest tr", hx_swap="outerHTML")))
            elseif uri.path == "/save"
                id = q["id"]
                hours[id] += 1
                if haskey(stage, id) && stage[id] == "Open"
                    stage[id] = "Saved"
                    html(table(id)(; update_rows=id, update_groups=["[\"Open\"]", "[\"Saved\"]"]))
                else
                    html(table(id)(; update_rows=id))
                end
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 17
            end
        finally
            close(server)
        end
    end
end

@testitem "a kept hx-preserve element holding a datalist moves without stopping Chrome browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Chrome (151) stopped the tab at the next style pass after moveBefore
        # moved a subtree whose datalist comes before the input listing it:
        # an invoice editor kept with hx-preserve through a row update, a
        # lazy detail's reload or a plain htmx swap.
        hours = Dict("d1" => 0, "l1" => 0)
        boxes = Ref(0)
        suggest(id) = h.datalist(; id="opts-$id")(h.option(; value="Groceries"), h.option(; value="Rent"))
        editor(id) = h.div(h.p(; class="rev")("rev $(hours[id])"),
            h.details(; id="ed-$id", hx_preserve=true, open=true)(h.summary("Edit $id"),
                suggest(id), h.input(; name="category", class="note", list="opts-$id")))
        cells(x) = (h.td(x.id), h.td(h.span(; class="hours")(string(hours[x.id]))),
            h.td(h.button("bump"; type="button", data_bump=x.id, hx_post="/save?id=$(x.id)",
                hx_target="closest tr", hx_swap="outerHTML")))
        eager(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], [(; id="d1")];
            key=x -> x.id, master=cells, detail=x -> editor(x.id), initially_open=true, id="eager", kw...)
        lazy(; kw...) = master_detail_table(["Invoice", "Hours", "Act"], [(; id="l1")];
            key=x -> x.id, master=cells, detail_url=x -> "/detail?id=$(x.id)", id="lazy", kw...)
        box() = h.div(; id="box", hx_get="/box", hx_trigger="refresh-box", hx_swap="outerHTML")(
            h.p(; class="rev")("box $(boxes[])"),
            h.div(; id="keep-box", hx_preserve=true)(suggest("box"), h.input(; class="note", list="opts-box")))
        direct = (h.div(; id="direct-from")(h.div(; id="direct")(suggest("direct"),
            h.input(; class="note", list="opts-direct"))), h.div(; id="direct-to"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await new Promise(r => setTimeout(r, 20)); return cond(); };
            // A forced style pass: where Chrome stopped. (No frames under
            // --virtual-time-budget, so no requestAnimationFrame.)
            const settle = () => { void document.body.offsetHeight; return new Promise(r => setTimeout(r, 50)); };
            const moves = 'moveBefore' in Element.prototype;
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const hoursOf = id => row(id).querySelector('.hours').textContent;
            const revOf = el => { const p = el && el.querySelector('.rev'); return p && p.textContent; };
            const type = (keep, text) => {
                const i = keep.querySelector('.note');
                i.value = text; i.focus(); i.setSelectionRange(1, 3);
                keep.htmxoMark = 'kept';
                return i;
            };
            const kept = (keep, id, text, inside) => {
                const i = keep.querySelector('.note');
                return document.getElementById(id) === keep && keep.htmxoMark === 'kept' && inside.contains(keep) &&
                    i.value === text && i.getAttribute('list') === 'opts-' + id.replace(/^(ed|keep)-/, '') &&
                    i.list === keep.querySelector('datalist');
            };
            // moveBefore keeps the focus and the selection; without it they go.
            const focused = i => !moves || (document.activeElement === i && i.selectionStart === 1 && i.selectionEnd === 3);
            try {
            // The page's moveBefore itself.
            const direct = document.getElementById('direct'), to = document.getElementById('direct-to');
            let i = type(direct, 'typed direct');
            (moves ? to.moveBefore : to.insertBefore).call(to, direct, null);
            await settle();
            check('direct-moved', kept(direct, 'direct', 'typed direct', to));
            check('direct-focus', focused(i));
            // A row update answering a request the editor sent itself.
            const ed = document.getElementById('ed-d1');
            i = type(ed, 'typed d1');
            htmx.ajax('POST', '/save?id=d1', {source: i, swap: 'none'});
            await wait(() => hoursOf('d1') === '1'); await settle();
            check('eager-update', revOf(detail('d1')) === 'rev 1' && !detail('d1').hidden);
            check('eager-preserved', kept(ed, 'ed-d1', 'typed d1', detail('d1')) && ed.open);
            check('eager-focus', focused(i));
            // An open lazy detail loads again; htmx's own swap puts the kept
            // editor back.
            row('l1').querySelector('[data-htmxo-detail-toggle]').click();
            await wait(() => document.getElementById('ed-l1')); await settle();
            const led = document.getElementById('ed-l1');
            type(led, 'typed l1');
            row('l1').querySelector('[data-bump]').click();
            await wait(() => hoursOf('l1') === '1' && revOf(detail('l1')) === 'rev 1'); await settle();
            check('lazy-preserved', kept(led, 'ed-l1', 'typed l1', detail('l1')));
            // A plain htmx swap keeping an hx-preserve element.
            const keep = document.getElementById('keep-box');
            type(keep, 'typed box');
            htmx.trigger('#box', 'refresh-box');
            await wait(() => revOf(document.getElementById('box')) === 'box 1'); await settle();
            check('swap-preserved', kept(keep, 'keep-box', 'typed box', document.getElementById('box')));
            } catch (e) { check('threw ' + e, false); }
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(direct..., eager(), lazy(), box(), driver;
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
            elseif uri.path == "/detail"
                html(editor(q["id"]))
            elseif uri.path == "/save"
                id = q["id"]
                hours[id] += 1
                html((id == "d1" ? eager : lazy)(; update_rows=id))
            elseif uri.path == "/box"
                boxes[] += 1
                html(box())
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=30000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 7
            end
        finally
            close(server)
        end
    end
end

@testitem "group summaries: ColumnSummary columns of a group row" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    html(x) = repr("text/html", x)
    row(page, id) = match(Regex("<tr[^>]*id=\"$id\"[^>]*>.*?</tr>", "s"), page).match
    summary(r, i) = match(Regex("<td(?=[^>]* data-htmxo-group-summary=\"$i\")[^>]*>([^<]*)</td>"), r)
    cell(r, i) = summary(r, i)[1]
    # What the ⬇ CSV writes for the cell: its decimals, a `.`, no grouping.
    number(r, i) = let m = match(r"data-htmxo-number=\"([^\"]*)\"", summary(r, i).match); isnothing(m) ? nothing : m[1] end
    # Acme holds p1, p2, p7 (-10, -20, -70); Bakery p4, p6; Prime Video p5.
    sums = html(grouped(group_by="party", group_summary=["Amount" => ColumnSummary(:sum, t -> t.amount; digits=1)]))
    @test cell(row(sums, "row-group--Acme"), 0) == "-100.0" && cell(row(sums, "row-group--Prime--Video"), 0) == "-50.0"
    @test number(row(sums, "row-group--Acme"), 0) == "-100.0"
    # The other columns stay blank; the first holds the key and count.
    @test contains(row(sums, "row-group--Acme"), "<small data-htmxo-group-count=\"\">(3)</small></button></span></td><td></td>")
    each = html(grouped(group_by="party", group_summary=[
        "IBAN" => ColumnSummary(:count),
        "Amount" => ColumnSummary(:mean, t -> t.amount)]))
    @test cell(row(each, "row-group--Acme"), 0) == "3" && cell(row(each, "row-group--Acme"), 1) == "-33"
    for (reduce, f, acme, bakery) in ((:min, t -> t.amount, "-70", "-60"), (:max, t -> t.amount, "-10", "-40"),
                                      (:sum, t -> t.id == "p1" ? nothing : t.amount, "-90", "-100"),
                                      (:sum, _ -> missing, "", ""))
        page = html(grouped(group_by="party", group_summary=["Amount" => ColumnSummary(reduce, f)]))
        @test cell(row(page, "row-group--Acme"), 0) == acme && cell(row(page, "row-group--Bakery"), 0) == bakery
    end
    # A ratio divides sums; a zero denominator leaves the cell empty.
    ratio = html(grouped(group_by="party", group_summary=["Amount" => ColumnSummary(:ratio,
        t -> t.amount, t -> t.party == "Bakery" ? 0 : 2.0; digits=2)]))
    @test cell(row(ratio, "row-group--Acme"), 0) == "-16.67" && cell(row(ratio, "row-group--Bakery"), 0) == ""
    @test number(row(ratio, "row-group--Acme"), 0) == "-16.67" && isnothing(number(row(ratio, "row-group--Bakery"), 0))
    # German texts write German numbers.
    de = html(grouped(group_by="rule", texts=table_texts(:de),
        group_summary=["Amount" => ColumnSummary(:sum, t -> t.amount * 100; digits=2)]))
    @test cell(row(de, "row-group--Shops"), 0) == "-23.000,00" && number(row(de, "row-group--Shops"), 0) == "-23000.00"
    # The cells' `format_number(x; digits)` writes the same text: test/number_format.jl.
    # Every leaf carries what the browser regroups it by, on every copy.
    leaf = match(r"<tr[^>]*id=\"row-group--Shops--p3\"[^>]*>", html(grouped(group_by="rule",
        group_summary=["Amount" => ColumnSummary(:ratio, t -> t.amount, t -> 1)]))).match
    @test contains(leaf, "data-htmxo-leaf-keys=\"{&quot;party&quot;:[&quot;Acme Prime&quot;],&quot;iban&quot;:[&quot;DE01&quot;],&quot;rule&quot;:[&quot;Shops&quot;,&quot;Media&quot;]}\"")
    @test contains(leaf, "data-htmxo-leaf-order=\"3\"") && contains(leaf, "data-htmxo-leaf-values=\"[[-30.0,1.0]]\"")
    # The wrapper: how to regroup, the template group row, and the leaves this
    # grouping leaves out.
    media = [GROUPINGS..., "media" => t -> occursin("Prime", t.party) ? "Prime" : nothing]
    page = html(master_detail_table(["Party", "IBAN", "Amount"], TX; key=t -> t.id,
        master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount))), detail=t -> h.p(t.memo),
        groupings=media, group_by="media", group_summary=["Amount" => ColumnSummary(:sum, t -> t.amount)]))
    @test contains(page, "data-htmxo-regroup=\"{&quot;names&quot;:[&quot;party&quot;,&quot;iban&quot;,&quot;rule&quot;,&quot;media&quot;]," *
        "&quot;flat&quot;:&quot;none&quot;,&quot;open&quot;:false,&quot;refresh&quot;:false," *
        "&quot;summary&quot;:[{&quot;reduce&quot;:&quot;sum&quot;,&quot;digits&quot;:0}]}\"")
    template = match(r"<template data-htmxo-group-template=\"\">(.*?)</template>"s, page)[1]
    @test startswith(template, "<tr ") && contains(template, "data-htmxo-group-summary=\"0\"") && count("<tr", template) == 1
    store = match(r"<template data-htmxo-unplaced=\"\">(.*?)</template>"s, page)[1]
    @test [m[1] for m in eachmatch(r"data-htmxo-leaf=\"([^\"]*)\"", store)] == ["p1", "p2", "p4", "p6", "p7"]
    @test contains(store, "id=\"row-p1\"") && contains(store, "id=\"detail-p1\"")
    @test !contains(table_rows(replace(page, store => "")), "data-htmxo-leaf=\"p1\"")
    # Deep enough indentation for every level the pills can nest, however
    # `group_by` is written.
    @test contains(html(grouped(group_by=["party"])), "tr[aria-level=\"4\"]") && contains(html(grouped(group_by="party")), "tr[aria-level=\"4\"]")
    # Markdown: the summaries, none of the browser's scaffolding. "Acme Prime"
    # names its group row, its leaf row and, after the table, that leaf's detail.
    md = to_markdown_string(grouped(group_by="party", group_summary=["Amount" => ColumnSummary(:sum, t -> t.amount)]))
    @test contains(md, "-100") && !contains(md, "template") && count("Acme Prime", md) == 3
    @test contains(md, "\n\n**Acme Prime**\n\nmemo 3\n\n")
    # Refused: an unknown reduce or digits, the wrong number of functions, a
    # column that is not a header or is the first, a column named twice,
    # something other than a ColumnSummary, a value that is not a number.
    @test_throws ArgumentError ColumnSummary(:median, identity)
    @test_throws ArgumentError ColumnSummary(:sum)
    @test_throws ArgumentError ColumnSummary(:ratio, identity)
    @test_throws ArgumentError ColumnSummary(:sum, identity; digits=11)
    @test_throws ArgumentError grouped(group_summary=["Nope" => ColumnSummary(:count)])
    @test_throws ArgumentError grouped(group_summary=["Party" => ColumnSummary(:count)])
    @test_throws ArgumentError grouped(group_summary=["Amount" => ColumnSummary(:count), "Amount" => ColumnSummary(:count)])
    @test_throws ArgumentError grouped(group_summary=["Amount" => :sum])
    @test_throws ArgumentError html(grouped(group_by="party", group_summary=["Amount" => ColumnSummary(:sum, t -> t.party)]))
    @test_throws ArgumentError master_detail_table(["A", "B"], TX; key=t -> t.id, master=t -> (h.td(t.id), h.td("")),
        detail=t -> "", group_summary=["B" => ColumnSummary(:count)])
end

@testitem "group_order: a grouping's groups in an order of its own" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h, to_markdown_string
    html(x) = repr("text/html", x)
    # The group rows' ids, in the order the table renders them.
    groups(page) = [match(r"id=\"row-group--([^\"]*)\"", m.match)[1]
                    for m in eachmatch(r"<tr[^>]*data-htmxo-group=\"\"[^>]*>", table_rows(page))]
    regroup_config(page) = match(r"data-htmxo-regroup=\"([^\"]*)\"", page)[1]
    # Bakery and Prime Video before the Acmes, ties in first-appearance order;
    # DE04 and DE03 first, then the others as they appear; Media first.
    ORDER = ["party" => k -> startswith(k, "Acme") ? 1 : 0, "iban" => ["DE04", "DE03"], "rule" => ["Media", "Shops"]]
    @test groups(html(grouped(group_by="party"))) == ["Acme", "Acme--Prime", "Bakery", "Prime--Video"]
    @test groups(html(grouped(group_by="party", group_order=ORDER))) == ["Bakery", "Prime--Video", "Acme", "Acme--Prime"]
    @test groups(html(grouped(group_by="iban", group_order=ORDER))) == ["DE04", "DE03", "DE01", "DE02"]
    # A listed key no item has makes no group, and keeps its place in the list.
    absent = html(grouped(group_by="iban", group_order=["iban" => ["DE09", "DE04"]]))
    @test groups(absent) == ["DE04", "DE01", "DE02", "DE03"]
    @test contains(regroup_config(absent), "&quot;order&quot;:{&quot;iban&quot;:[&quot;DE09&quot;,&quot;DE04&quot;,&quot;DE01&quot;,&quot;DE02&quot;,&quot;DE03&quot;]}")
    # Every level nested by a list follows its own grouping's order.
    nested = html(grouped(group_by=["rule", "party"], group_order=ORDER))
    @test groups(nested) == ["Media", "Media--Prime--Video", "Media--Acme--Prime",
                             "Shops", "Shops--Bakery", "Shops--Acme", "Shops--Acme--Prime"]
    # A grouping without an order keeps first appearance; leaves keep the
    # order of `items` in their group.
    @test groups(html(grouped(group_by=["rule", "iban"], group_order=["rule" => ["Media", "Shops"]]))) ==
        ["Media", "Media--DE01", "Media--DE04", "Shops", "Shops--DE01", "Shops--DE02", "Shops--DE03"]
    leaves = [m[1] for m in eachmatch(r"data-htmxo-leaf=\"([^\"]*)\"", table_rows(html(grouped(group_by="party", group_order=ORDER))))]
    @test leaves == ["p4", "p6", "p5", "p1", "p2", "p7", "p3"]
    # The browser regroups by the same ranked lists, every grouping's, whichever
    # is active; a table without `group_order` writes none.
    @test endswith(regroup_config(html(grouped(group_by="none", group_order=ORDER))),
        "&quot;order&quot;:{&quot;party&quot;:[&quot;Bakery&quot;,&quot;Prime Video&quot;,&quot;Acme&quot;,&quot;Acme Prime&quot;]," *
        "&quot;iban&quot;:[&quot;DE04&quot;,&quot;DE03&quot;,&quot;DE01&quot;,&quot;DE02&quot;]," *
        "&quot;rule&quot;:[&quot;Media&quot;,&quot;Shops&quot;]}}")
    @test !contains(regroup_config(html(grouped(group_by="party"))), "&quot;order&quot;")
    # A row update brings the lists again, ranked with its change; a table that
    # regroups through the server (lazy groups) has none to keep.
    update = html(grouped(group_by="party", group_order=ORDER, update_rows="p1"))
    @test contains(update, "data-htmxo-group-order=\"{&quot;party&quot;:[&quot;Bakery&quot;,")
    @test !contains(html(grouped(group_by="party", update_rows="p1")), "data-htmxo-group-order")
    lazy = (; group_by=["party"], group_order=ORDER, group_by_url="/table", group_rows_url=(k, ms) -> "/rows")
    @test !contains(html(grouped(; lazy..., update_rows="p1")), "data-htmxo-group-order")
    @test groups(html(grouped(; lazy..., initially_open=true))) == ["Bakery", "Prime--Video", "Acme", "Acme--Prime"]
    # Markdown and PDFs list the groups in the same order.
    md = to_markdown_string(grouped(group_by="party", group_order=ORDER))
    at(s) = first(findfirst(s, md))
    @test at("Bakery") < at("Prime Video") < at("Acme")
    # refused: an order for a name that is no grouping would order nothing (a typo; dev §1, no silent no-op)
    @test_throws ArgumentError html(grouped(group_order=["nope" => ["a"]]))
    # refused: the flat view has no groups to order
    @test_throws ArgumentError html(grouped(group_order=["none" => ["a"]]))
    # refused: two orders for one grouping, or one key at two places, leave the order undefined
    @test_throws ArgumentError html(grouped(group_order=["party" => ["Acme"], "party" => ["Bakery"]]))
    @test_throws ArgumentError html(grouped(group_order=["party" => ["Acme", "Acme"]]))
    # refused: an order is a list of keys or a function `key -> sort key`
    @test_throws ArgumentError html(grouped(group_order=["party" => :alphabetical]))
    @test_throws ArgumentError html(grouped(group_order=[("party", ["Acme"])]))
    # refused: without `groupings` there are no groups to order
    @test_throws ArgumentError master_detail_table(["A"], TX; key=t -> t.id, master=t -> (h.td(t.id),),
        detail=t -> "", group_order=["party" => ["Acme"]])
end

@testitem "regrouping in the browser builds the server's rows browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        flat(group_by; kw...) = regroup_table(; group_by, selectable="tx", select_form="bulk", searchable=true,
            expand_controls=true, id="g", kw...)
        nested(group_by) = regroup_table(; group_by, id="n", key=t -> "n" * t.id, texts=table_texts(:de))
        bulk = h.form(; id="bulk")(h.button("Apply"; id="apply", data_htmxo_needs_selection="tx", disabled=true))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            let requests = 0;
            document.body.addEventListener('htmx:beforeRequest', () => requests++);
            const g = () => document.getElementById('g').closest('[data-htmxo-grouped]');
            const n = () => document.getElementById('n').closest('[data-htmxo-grouped]');
            const row = id => document.getElementById('row-' + id);
            const rows = w => Array.from(w.querySelector('tbody').rows).filter(r => !r.id.startsWith('detail-'));
            const shown = w => rows(w).filter(r => !r.hidden).map(r => r.id.slice(4)).join(',');
            const count = () => g().querySelector('[data-htmxo-selection-count]').textContent;
            const inputs = () => new FormData(document.getElementById('bulk')).getAll('tx').sort().join(',');
            const click = (el, mods = {}) => el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, ...mods}));
            const toggle = id => row(id).querySelector('[data-htmxo-tree-toggle]').click();
            const search = v => { const i = g().querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            // Group by one grouping alone (or none), as the pills ask for it.
            const levels = v => v === 'none' ? [] : [v];
            const regroup = v => htmxoGroupRequest(g().querySelector('.htmxo-group-pills'), levels(v), null);
            const summary = (id, i) => row(id).querySelector('[data-htmxo-group-summary="' + i + '"]').textContent;
            // Every grouping: the rows the server would render, built in the browser.
            for (const v of ['iban', 'rule', 'media', 'none', 'party']) {
                regroup(v);
                check('parity-' + v, g().dataset.htmxoGrouped === JSON.stringify(levels(v)) && await parity(g(), '/flat?group_by=' + v));
            }
            regroup('rule');
            check('summary', summary('group--Shops', 0) === '-230.0' && summary('group--Shops', 1) === '6' && summary('group--Media', 0) === '-80.0');
            // A row update the server renders for this grouping fits the rows the browser built.
            htmxoUpdateRows(await (await fetch('/flat?group_by=rule&update=p3')).text());
            check('row-update', await parity(g(), '/flat?group_by=rule'));
            check('unplaced', (regroup('media'), shown(g())) === 'group--Prime' &&
                g().querySelector('template[data-htmxo-unplaced]').content.querySelectorAll('tr[data-htmxo-leaf]').length === 5);
            regroup('party');
            check('unplaced-back', g().querySelector('template[data-htmxo-unplaced]').content.children.length === 0 &&
                rows(g()).filter(r => 'htmxoLeaf' in r.dataset).length === 7);
            // Selection is per leaf: it survives regrouping, and both copies of p3 show it.
            toggle('group--Acme');
            click(row('group--Acme--p1').cells[2]);
            regroup('rule');
            toggle('group--Shops'); toggle('group--Media');
            click(row('group--Media--p3').cells[2], {ctrlKey: true});
            check('select-copies', inputs() === 'p1,p3' && row('group--Shops--p3').getAttribute('aria-selected') === 'true' &&
                count().startsWith('2 selected'));
            // Branches the reader opened stay open by id; others start closed.
            regroup('party');
            check('remembered-open', row('group--Acme').dataset.htmxoTreeOpen === 'true' && row('group--Bakery').dataset.htmxoTreeOpen === 'false');
            // An open detail moves with its leaf, and opens the groups above it.
            row('group--Acme--p2').querySelector('[data-htmxo-detail-toggle]').click();
            regroup('iban');
            check('detail-moves', !row('group--DE02--p2').hidden && !document.getElementById('detail-group--DE02--p2').hidden &&
                row('group--DE02').dataset.htmxoTreeOpen === 'true');
            // The search applies to the new rows; the sort to the new siblings.
            search('bakery');
            regroup('party');
            check('search', shown(g()) === 'group--Bakery,group--Bakery--p4,group--Bakery--p6');
            search('');
            g().querySelectorAll('thead th')[2].click();
            regroup('rule');
            const order = rows(g()).filter(r => r.dataset.htmxoParent === 'row-group--Shops').map(r => r.id.slice(-2)).join(',');
            check('sorted', order === 'p7,p6,p4,p3,p2,p1');
            // Pills: nested levels, built like the server's rows and pills, in
            // German, on a table whose `group_by` is a single name.
            const pill = name => n().querySelector('[data-htmxo-group-name="' + name + '"] > button');
            pill('iban').click();
            check('pills-add', await parity(n(), '/nested?group_by=party&group_by=iban', true));
            check('german', row('group--Acme--DE01').querySelector('[data-htmxo-group-summary="0"]').textContent === '-80,0' &&
                row('group--Acme--DE01--np1').dataset.htmxoLeaf === 'np1');
            document.getElementById('n-group-iban-earlier').click();
            check('pills-move', n().dataset.htmxoGrouped === '["iban","party"]' && await parity(n(), '/nested?group_by=iban&group_by=party', true));
            check('focus-handed-on', document.activeElement && document.activeElement.id === 'n-group-iban');
            pill('party').click();
            check('pills-remove', await parity(n(), '/nested?group_by=iban', true));
            pill('iban').click();
            check('pills-flat', n().dataset.htmxoGroupBy === '["none"]' && await parity(n(), '/nested?group_by=none', true));
            check('no-requests', requests === 0);
            finish();
        });
        """))
        page = repr("text/html", htmx(bulk, flat(["party"]), nested("party"), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            levels = [String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"]
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            q = HTTP.queryparams(uri)
            uri.path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html"], page) :
            uri.path == "/flat" ? html(haskey(q, "update") ? flat(levels; update_rows=q["update"]) : flat(levels)) :
            uri.path == "/nested" ? html(nested(levels)) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
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

@testitem "group_order: the browser regroups in the server's order browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Bakery and Prime Video before the Acmes, DE04 and DE03 first, Media first.
        ORDER = ["party" => k -> startswith(k, "Acme") ? 1 : 0, "iban" => ["DE04", "DE03"], "rule" => ["Media", "Shops"]]
        # After an action p1 has a party new to the page, which sorts first.
        moved = [t.id == "p1" ? merge(t, (; party="Zeta")) : t for t in TX]
        flat(group_by; items=TX, kw...) = regroup_table(; items, group_by, group_order=ORDER, id="o", kw...)
        nested(group_by) = regroup_table(; group_by, group_order=ORDER, id="on", key=t -> "n" * t.id)
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            let requests = 0;
            document.body.addEventListener('htmx:beforeRequest', () => requests++);
            const o = () => document.getElementById('o').closest('[data-htmxo-grouped]');
            const n = () => document.getElementById('on').closest('[data-htmxo-grouped]');
            const groups = w => Array.from(w.querySelector('tbody').rows).filter(r => 'htmxoGroup' in r.dataset).map(r => r.id.slice(4)).join(',');
            // Group by one grouping alone (or none), as the pills ask for it.
            const regroup = v => htmxoGroupRequest(o().querySelector('.htmxo-group-pills'), v === 'none' ? [] : [v], null);
            // Every grouping, regrouped in the browser: the server's rows, in its order.
            for (const v of ['iban', 'rule', 'media', 'none', 'party']) {
                regroup(v);
                check('parity-' + v, await parity(o(), '/flat?group_by=' + v));
            }
            regroup('iban');
            check('listed-first', groups(o()) === 'group--DE04,group--DE03,group--DE01,group--DE02');
            regroup('party');
            check('sorted', groups(o()) === 'group--Bakery,group--Prime--Video,group--Acme,group--Acme--Prime');
            // Nested pills: each level in its own grouping's order.
            const pill = name => n().querySelector('[data-htmxo-group-name="' + name + '"] > button');
            pill('rule').click();
            check('nested', await parity(n(), '/nested?group_by=party&group_by=rule', true));
            document.getElementById('on-group-rule-earlier').click();
            check('nested-moved', await parity(n(), '/nested?group_by=rule&group_by=party', true) && groups(n()) ===
                'group--Media,group--Media--Prime--Video,group--Media--Acme--Prime,group--Shops,group--Shops--Bakery,group--Shops--Acme,group--Shops--Acme--Prime');
            check('no-requests', requests === 0);
            // A row update brings a group key new to the page: the next regroup
            // in the browser puts it where the server does.
            htmxoUpdateRows(await (await fetch('/flat?group_by=party&moved=1&update=p1')).text());
            regroup('iban');
            regroup('party');
            check('update-order', groups(o()).startsWith('group--Zeta,group--Bakery') && await parity(o(), '/flat?group_by=party&moved=1'));
            finish();
        });
        """))
        page = repr("text/html", htmx(flat("party"), nested(["party"]), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            levels = [String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"]
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            q = HTTP.queryparams(uri)
            items = haskey(q, "moved") ? moved : TX
            # p1 leaves Acme for Zeta: the update names both groups.
            uri.path == "/" ? HTTP.Response(200, ["Content-Type" => "text/html"], page) :
            uri.path == "/flat" ? html(haskey(q, "update") ?
                flat(levels; items, update_rows=q["update"], update_groups=["[\"Acme\"]", "[\"Zeta\"]"]) : flat(levels; items)) :
            uri.path == "/nested" ? html(nested(levels)) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 11
            end
        finally
            close(server)
        end
    end
end

@testitem "group_master rows come from the server after a browser regroup browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        served = Ref(0)
        custom(group_by) = regroup_table(; group_by, id="c", group_by_url="/custom",
            group_master=(k, ms) -> (h.td(h.strong("G " * last(HTMXObjects.group_path(k)))), h.td(""), h.td(string(length(ms)))))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            const c = () => document.getElementById('c').closest('[data-htmxo-grouped]');
            // Group by iban alone, in one change, as the pills ask for it.
            htmxoGroupRequest(c().querySelector('.htmxo-group-pills'), ['iban'], null);
            // At once: the browser's rows, default group rows included.
            check('browser-first', c().dataset.htmxoGrouped === '["iban"]' &&
                document.getElementById('row-group--DE01').querySelector('[data-htmxo-group-label]').textContent === 'DE01');
            // Then the server's own render, with its group rows.
            check('server-after', await wait(() => document.getElementById('row-group--DE01').textContent.includes('G DE01')));
            check('same-rows', await parity(c(), '/custom?group_by=iban'));
            finish();
        });
        """))
        page = repr("text/html", htmx(custom(["party"]), driver; extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            uri.path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            uri.path == "/custom" || return HTTP.Response(404)
            served[] += 1
            HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html",
                custom([String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"])))
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 3
            end
            # One request for the group rows of the new grouping, one from the parity check.
            @test served[] == 2
        finally
            close(server)
        end
    end
end

@testitem "a recorded regroupable table regroups with no server browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            const w = () => document.querySelector('[data-htmxo-grouped]');
            const shown = () => Array.from(w().querySelector('tbody').rows).filter(r => !r.hidden && !r.id.startsWith('detail-')).map(r => r.id.slice(4)).join(',');
            const pill = name => w().querySelector('[data-htmxo-group-name="' + name + '"] > button');
            check('recorded', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video');
            pill('party').click();
            pill('rule').click();
            check('regrouped', w().dataset.htmxoGrouped === '["rule"]' && shown() === 'group--Shops,group--Media' &&
                document.getElementById('row-group--Shops').querySelector('[data-htmxo-group-summary="0"]').textContent === '-230.0');
            pill('iban').click();
            check('nested', w().dataset.htmxoGrouped === '["rule","iban"]' &&
                document.getElementById('row-group--Shops').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-controls') ===
                    'row-group--Shops--DE01 row-group--Shops--DE02 row-group--Shops--DE03');
            finish();
        });
        """))
        @htmx struct RecordedRegroupApp
            @get index() = htmx(regroup_table(; group_by="party", id="r"), driver;
                extra_head=(sortable_table_js(), sortable_table_styles()),
                hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        end
        mktempdir() do dir
            record!(RecordedRegroupApp(); record_dir=dir, paths=["/"], hx=false, markdown=false)
            recorded = read(joinpath(dir, "index.html"), String)
            # The pills survive recording as live controls.
            @test contains(recorded, "data-htmxo-regroup=") && contains(recorded, "onclick=\"htmxoGroupToggle(this)\"") &&
                !occursin(r"<button[^>]*data-static-disabled", recorded)
            # A plain file server: anything but the page is a request a static
            # bundle could not answer.
            other = Ref(0)
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2]); close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
                HTTP.URI(req.target).path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], recorded)
                other[] += 1
                HTTP.Response(404)
            end
            try
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                if !isnothing(checks)
                    for line in split(checks[1], '\n')
                        @test endswith(line, ":true")
                    end
                    @test count(==('\n'), checks[1]) + 1 == 3
                end
                @test other[] <= 1   # at most the browser's own favicon request
            finally
                close(server)
            end
        end
    end
end

@testitem "requests from a browser-regrouped table carry its current grouping browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    import HTMXObjects: h
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        esc = HTTP.escapeuri
        gbq(group_by) = join(("group_by=$(esc(g))" for g in group_by), '&')
        flagged, noted = Set{String}(), Set{String}()
        # (path, id, group_by in the URL, group_by in the body) of each request.
        seen = Tuple{String,String,Vector{String},Vector{String}}[]
        # Table a writes the grouping of its render into its action URL, its
        # `detail_url` and the form of each detail; neither table has a
        # `group_by_url`, so the browser alone regroups it.
        table_a(group_by; kw...) = master_detail_table(["Party", "IBAN", "Amount", "State"], TX; key=t -> t.id,
            master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount)),
                h.td(h.span(t.id in flagged ? "flagged" : "-"; class="flag"), " ",
                     h.span(t.id in noted ? "noted" : "-"; class="note"), " ",
                     h.button("flag"; type="button", data_flag=t.id,
                         hx_post="/flag?id=$(t.id)&$(gbq(group_by))", hx_target="closest tr", hx_swap="outerHTML"))),
            detail_url=t -> "/detail?id=$(t.id)&$(gbq(group_by))", groupings=GROUPINGS, group_by, id="a", kw...)
        # Table b also sends the grouping through an ancestor's hx-vals, as
        # htmxo-master-detail describes: its detail requests name it twice.
        b_groupings = ["none" => nothing, "party" => t -> "b-" * t.party, "iban" => t -> "b-" * t.iban]
        table_b(group_by) = master_detail_table(["Party", "IBAN", "Amount"], TX; key=t -> "b" * t.id,
            master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount))),
            detail_url=t -> "/detail?id=b$(t.id)&$(gbq(group_by))", groupings=b_groupings, group_by, id="b")
        detail(id, group_by) = h.div(h.span(join(group_by, ","); data_seen=""),
            h.form(; hx_post="/note", data_note=id)(h.input(; type="hidden", name="id", value=id),
                (h.input(; type="hidden", name="group_by", value=g) for g in group_by)...,
                h.button("note"; type="submit")))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            const errors = [];
            window.addEventListener('error', e => errors.push(e.message));
            const wrap = id => document.getElementById(id).closest('[data-htmxo-grouped]');
            const pills = id => wrap(id).querySelector('.htmxo-group-pills');
            const row = id => document.getElementById('row-' + id);
            const detail = id => document.getElementById('detail-' + id);
            const text = (id, sel) => { const r = row(id), el = r && r.querySelector(sel); return el ? el.textContent : null; };
            htmxoGroupRequest(pills('a'), ['iban'], null);
            check('regrouped', wrap('a').dataset.htmxoGrouped === '["iban"]' && row('group--DE01--p1') !== null);
            // An action URL written for "party" sends "iban".
            row('group--DE01--p1').querySelector('[data-flag]').click();
            check('flag-update', await wait(() => text('group--DE01--p1', '.flag') === 'flagged') || errors.join('; '));
            // So does a lazy detail URL; its form is rendered for "iban".
            row('group--DE02--p2').querySelector('[data-htmxo-detail-toggle]').click();
            await wait(() => detail('group--DE02--p2').querySelector('[data-note]'));
            const seenAs = id => { const s = detail(id) && detail(id).querySelector('[data-seen]'); return s ? s.textContent : null; };
            check('detail-url', seenAs('group--DE02--p2') === 'iban' || seenAs('group--DE02--p2'));
            // Regrouped again, the loaded form's hidden inputs send "rule".
            htmxoGroupRequest(pills('a'), ['rule'], null);
            const form = detail('group--Shops--p2').querySelector('form[data-note]');
            form.requestSubmit();
            check('form-update', await wait(() => text('group--Shops--p2', '.note') === 'noted') || errors.join('; '));
            // URL and hx-vals together send the grouping once.
            htmxoGroupRequest(pills('b'), ['iban'], null);
            row('group--b-DE01--bp3').querySelector('[data-htmxo-detail-toggle]').click();
            await wait(() => detail('group--b-DE01--bp3').querySelector('[data-note]'));
            check('one-copy', seenAs('group--b-DE01--bp3') === 'iban' || seenAs('group--b-DE01--bp3'));
            check('no-errors', errors.length === 0 || errors.join('; '));
            finish();
        });
        """))
        page = repr("text/html", htmx(table_a(["party"]), h.div(; hx_vals="js:{group_by: htmxoGroupBy(this)}")(table_b(["party"])), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            uri.path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            body = HTTP.queryparampairs(String(req.body))
            levels_in(pairs) = [String(last(p)) for p in pairs if first(p) == "group_by"]
            url_levels, body_levels = levels_in(HTTP.queryparampairs(uri)), levels_in(body)
            # As an HTMXObjects route reads them: the body first, then the URL.
            group_by = isempty(body_levels) ? url_levels : body_levels
            id = get(HTTP.queryparams(uri), "id", get(Dict(body), "id", ""))
            push!(seen, (uri.path, id, url_levels, body_levels))
            html(x) = HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", x))
            if uri.path == "/flag"
                push!(flagged, id)
                html(table_a(group_by; update_rows=id))
            elseif uri.path == "/note"
                push!(noted, id)
                html(table_a(group_by; update_rows=id))
            elseif uri.path == "/detail"
                html(detail(id, group_by))
            else
                HTTP.Response(404)
            end
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
                @test count(==('\n'), checks[1]) + 1 == 6
            end
            # Each request carried the grouping the table showed, once, where
            # its element put it.
            sent(path, id) = (i = findfirst(s -> s[1] == path && s[2] == id, seen); isnothing(i) ? nothing : seen[i][3:4])
            @test sent("/flag", "p1") == (["iban"], String[])
            @test sent("/detail", "p2") == (["iban"], String[])
            @test sent("/note", "p2") == (String[], ["rule"])
            @test sent("/detail", "bp3") == (["iban"], String[])
        finally
            close(server)
        end
    end
end

@testitem "a tree grouping: the children tree as one grouping over its leaves" setup=[GroupingFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    html(x) = repr("text/html", x)
    tbody(page) = match(r"<tbody[^>]*>.*?</tbody>"s, page).match
    ids(rows) = [m[1] for m in eachmatch(r"<tr\b[^>]*?\sid=\"row-([^\"]+)\"", rows)]
    # A tag's attributes in a fixed order, without the ones a tree grouping adds.
    marks = r" data-htmxo-(leaf|leaf-keys|leaf-order|leaf-values|branch)=\"[^\"]*\""
    norm(s) = replace(replace(s, marks => ""), r"<[a-z]+(?: [^\s=>]+=\"[^\"]*\")+>" => tag ->
        "<" * match(r"^<([a-z]+)", tag)[1] * " " * join(sort([m.match for m in eachmatch(r"[^\s=>]+=\"[^\"]*\"", tag)]), " ") * ">")
    tree = html(outline_table(searchable=true, id="o"))
    # It opens as the tree, row for row the tree without `groupings`, with
    # what the browser regroups the leaves by.
    @test norm(tbody(tree)) == norm(tbody(html(plain_outline(searchable=true, id="o"))))
    @test count("data-htmxo-leaf=\"c2\"", tree) == 2 && count("data-htmxo-branch=\"\"", tree) == 4
    # Both rows of c2 carry its first row's data: its place in leaf order
    # (c4, c1, c2, c3) and its keys under the other groupings.
    @test count("data-htmxo-leaf-order=\"3\"", tree) == 2 &&
        count("data-htmxo-leaf-keys=\"{&quot;Status&quot;:[&quot;described&quot;]}\"", tree) == 2
    # The search count counts the clauses, each once, not the sections.
    @test contains(tree, "4 of 4 rows shown")
    @test contains(tree, "data-htmxo-grouped=\"[&quot;Outline&quot;]\"") && contains(tree, "&quot;tree&quot;:&quot;Outline&quot;") &&
        contains(tree, "<template data-htmxo-tree=\"\"></template>")
    # The tree's pill stands alone: another pill replaces it.
    @test contains(tree, "data-htmxo-group-tree=\"Outline\"") && contains(tree, "id=\"o-group-Outline\" aria-pressed=\"true\"") &&
        contains(tree, "id=\"o-group-Status\" aria-pressed=\"false\" title=\"Group by Status\"")
    # Another grouping lists each leaf once, with its first row in the tree
    # (c2 as section 1.1 covers it), in leaf order; the tree waits beside it.
    status = html(outline_table(group_by=["Status"], searchable=true, id="o"))
    @test ids(tbody(status)) == ["group--open", "group--open--c4", "group--shown", "group--shown--c1", "group--shown--c3",
                                 "group--described", "group--described--c2"]
    @test contains(tbody(status), "c2 in 1.1") && !contains(tbody(status), "c2 in 2") && contains(status, "4 of 4 rows shown")
    stash = match(r"<template data-htmxo-tree=\"\">.*?</template>"s, status).match
    @test ids(stash) == ids(tbody(tree)) && contains(stash, "c2 in 2")
    @test contains(status, "id=\"o-group-Outline\" aria-pressed=\"false\" title=\"Group by Outline\"")
    @test ids(tbody(html(outline_table(group_by=["None"], id="o")))) == ["c4", "c1", "c2", "c3"]
    # Markdown reads the tree as the tree without `groupings` does.
    @test to_markdown_string(outline_table()) == to_markdown_string(plain_outline())
    # A leaf's rows select and link as one item; a section by its own key.
    sel = html(outline_table(selectable="req", link="o"))
    @test count("data-htmxo-select-key=\"c2\"", sel) == 2 && count("data-htmxo-link-key=\"c2\"", sel) == 2 &&
        contains(sel, "data-htmxo-link-key=\"s1\"")
    # Without leaf_key a leaf is each row without children, under its own key:
    # section 3 too (so the groupings here read no clause field).
    default = html(master_detail_table(["Item", "Status", "Points"], OUTLINE; key=outline_key(""),
        children=outline_children, master=outline_master, detail=r -> h.p("x"),
        groupings=["Outline" => :children, "None" => nothing, "Kind" => r -> string(r.kind)]))
    @test contains(default, "data-htmxo-leaf=\"s3\"") && contains(default, "data-htmxo-leaf=\"c2-c2\"") &&
        count("data-htmxo-branch=\"\"", default) == 3
    # A table without collapsible branches keeps its groups open, with no
    # toggle: no master row is hidden (detail rows start hidden as always).
    open_groups = tbody(html(outline_table(group_by=["Status"], branches_collapsible=false)))
    masters = [m.match for m in eachmatch(r"<tr\b[^>]*\sid=\"row-[^>]*>", open_groups)]
    @test length(masters) == 7 && !any(contains(" hidden="), masters) && !contains(open_groups, "data-htmxo-tree-toggle")
    # refused: `=> :children` shows the tree `children` builds, and there is none
    @test_throws ArgumentError master_detail_table(["Item"], OUTLINE; key=outline_key(""), master=r -> (h.td(""),),
        detail=r -> "", groupings=OUTLINE_GROUPINGS)
    # refused: two groupings of one tree are one view twice
    @test_throws ArgumentError outline_table(groupings=[OUTLINE_GROUPINGS..., "Again" => :children])
    # refused: a symbol other than :children names no grouping
    @test_throws ArgumentError outline_table(groupings=["Outline" => :parents, "None" => nothing])
    # refused: leaf_key and leaf_order name the leaves of a tree grouping
    @test_throws ArgumentError grouped(leaf_key=t -> t.id)
    @test_throws ArgumentError master_detail_table(["Item"], OUTLINE; key=outline_key(""), children=outline_children,
        master=r -> (h.td(""),), detail=r -> "", leaf_order=r -> 1)
    # refused: the other groupings list a leaf alone, so a leaf has no children
    @test_throws ArgumentError outline_table(leaf_key=r -> r.id)
    # refused: a tree's branches keep the tree's order
    @test_throws ArgumentError outline_table(group_order=["Outline" => ["1"]])
    # Not built yet (decision HTMXObjects:snag.tenderviews-tend-7a5a0baa/decisions/2026-10-26T15-39-47-852-0dwgr77
    # left them for later): levels nested in the tree, and the hooks that ask
    # the server for group rows or update rows.
    @test_broken (outline_table(group_by=["Outline", "Status"]); true)
    for hook in ((; group_master=(k, ms) -> (h.td(k), h.td(""), h.td(""))), (; group_by_url="/t"),
                 (; group_rows_url=(k, ms) -> nothing), (; group_rows="[\"shown\"]"), (; update_rows="c1"),
                 (; update_groups="[\"shown\"]"))
        @test_broken (outline_table(; group_by=["Status"], hook...); true)
    end
end

@testitem "a tree grouping regroups in the browser and comes back browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # o opens as the tree; p opens grouped by Status, its tree waiting
        # beside it; q keeps its branches and groups open.
        tables = Dict("o" => levels -> outline_table(; group_by=levels, searchable=true, id="o"),
                      "p" => levels -> outline_table(; prefix="p", group_by=levels, id="p"),
                      "q" => levels -> outline_table(; prefix="q", group_by=levels, branches_collapsible=false, id="q"))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            let requests = 0;
            document.body.addEventListener('htmx:beforeRequest', () => requests++);
            const w = id => document.getElementById(id).closest('[data-htmxo-grouped]');
            const el = (id, rid) => w(id).querySelector('[id="' + rid + '"]');
            const pill = (id, name) => w(id).querySelector('[data-htmxo-group-name="' + name + '"] > button');
            const rows = id => Array.from(w(id).querySelector('tbody').rows);
            const shown = id => rows(id).filter(r => !r.hidden && !r.id.startsWith('detail-')).map(r => r.id.slice(4)).join(',');
            const count = id => w(id).querySelector('[data-htmxo-table-count]').textContent;
            const search = v => { const i = w('o').querySelector('input[type="search"]'); i.value = v; i.dispatchEvent(new Event('input', {bubbles: true})); };
            const first = rows('o').map(norm).join('\n');
            check('first-paint', await parity(w('o'), '/o?group_by=Outline', true));
            // Another pill leaves the tree; it builds the server's rows.
            pill('o', 'Status').click();
            check('to-status', w('o').dataset.htmxoGrouped === '["Status"]' && await parity(w('o'), '/o?group_by=Status', true) &&
                count('o') === '4 of 4 rows shown');
            pill('o', 'Status').click();
            check('to-flat', w('o').dataset.htmxoGroupBy === '["None"]' && await parity(w('o'), '/o?group_by=None', true));
            // The tree comes back as it was.
            pill('o', 'Outline').click();
            check('back', w('o').dataset.htmxoGrouped === '["Outline"]' && rows('o').map(norm).join('\n') === first &&
                w('o').querySelector('template[data-htmxo-tree]').content.children.length === 0 &&
                await parity(w('o'), '/o?group_by=Outline', true));
            // An open detail goes along with the leaf's first row, and comes back.
            el('o', 'row-s1').querySelector('[data-htmxo-tree-toggle]').click();
            el('o', 'row-s1--1').querySelector('[data-htmxo-tree-toggle]').click();
            el('o', 'row-c1--1-c2').querySelector('[data-htmxo-detail-toggle]').click();
            pill('o', 'Status').click();
            check('detail-goes-along', !el('o', 'detail-group--described--c2').hidden && el('o', 'row-group--described').dataset.htmxoTreeOpen === 'true');
            pill('o', 'Outline').click();
            check('tree-as-left', !el('o', 'detail-c1--1-c2').hidden && el('o', 'detail-c2-c2').hidden &&
                shown('o') === 's1,c1-c1,s1--1,c1--1-c2,c1--1-c3,s2,s3');
            // The search applies to the tree and to the groups, counting clauses.
            search('c3');
            check('search-tree', count('o') === '1 of 4 rows shown' && shown('o') === 's1,s1--1,c1--1-c3');
            pill('o', 'Status').click();
            check('search-status', shown('o') === 'group--shown,group--shown--c3' && count('o') === '1 of 4 rows shown');
            search('');
            // A table that opens grouped: its tree comes from the page.
            check('p-first', await parity(w('p'), '/p?group_by=Status', true));
            pill('p', 'Outline').click();
            check('p-tree', w('p').dataset.htmxoGrouped === '["Outline"]' && await parity(w('p'), '/p?group_by=Outline', true));
            pill('p', 'Status').click();
            check('p-status', await parity(w('p'), '/p?group_by=Status', true));
            // Branches and groups that do not collapse.
            pill('q', 'Status').click();
            check('q-status', await parity(w('q'), '/q?group_by=Status', true));
            pill('q', 'Outline').click();
            check('q-tree', await parity(w('q'), '/q?group_by=Outline', true));
            check('no-requests', requests === 0);
            finish();
        });
        """))
        page = repr("text/html", htmx(tables["o"](["Outline"]), tables["p"](["Status"]), tables["q"](["Outline"]), driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            levels = [String(last(p)) for p in HTTP.queryparampairs(uri) if first(p) == "group_by"]
            uri.path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            table = get(tables, lstrip(uri.path, '/'), nothing)
            isnothing(table) ? HTTP.Response(404) : HTTP.Response(200, ["Content-Type" => "text/html"], repr("text/html", table(levels)))
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 14
            end
        finally
            close(server)
        end
    end
end

@testitem "a recorded tree grouping regroups with no server browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(regroup_driver_prelude() * raw"""
        window.addEventListener('load', async function() {
            const w = () => document.querySelector('[data-htmxo-grouped]');
            const shown = () => Array.from(w().querySelector('tbody').rows).filter(r => !r.hidden && !r.id.startsWith('detail-')).map(r => r.id.slice(4)).join(',');
            const pill = name => w().querySelector('[data-htmxo-group-name="' + name + '"] > button');
            check('recorded', shown() === 's1,s2,s3');
            pill('Status').click();
            check('regrouped', w().dataset.htmxoGrouped === '["Status"]' && shown() === 'group--open,group--shown,group--described' &&
                document.getElementById('row-group--shown').querySelector('[data-htmxo-group-summary="0"]').textContent === '7');
            pill('Outline').click();
            check('tree-back', w().dataset.htmxoGrouped === '["Outline"]' && shown() === 's1,s2,s3');
            finish();
        });
        """))
        @htmx struct RecordedTreeGroupingApp
            @get index() = htmx(outline_table(; id="r", searchable=true), driver;
                extra_head=(sortable_table_js(), sortable_table_styles()),
                hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        end
        mktempdir() do dir
            record!(RecordedTreeGroupingApp(); record_dir=dir, paths=["/"], hx=false, markdown=false)
            recorded = read(joinpath(dir, "index.html"), String)
            @test contains(recorded, "<template data-htmxo-tree") && contains(recorded, "data-htmxo-group-tree=\"Outline\"")
            other = Ref(0)
            socket = listen(Sockets.localhost, 0)
            port = Int(getsockname(socket)[2]); close(socket)
            server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
                HTTP.URI(req.target).path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], recorded)
                other[] += 1
                HTTP.Response(404)
            end
            try
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                if !isnothing(checks)
                    for line in split(checks[1], '\n')
                        @test endswith(line, ":true")
                    end
                    @test count(==('\n'), checks[1]) + 1 == 3
                end
                @test other[] <= 1   # at most the browser's own favicon request
            finally
                close(server)
            end
        end
    end
end
