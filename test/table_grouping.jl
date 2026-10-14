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
    @test contains(page, "data-htmxo-lazy-rows=\"/rows?key=Acme\"") && contains(page, "data-htmxo-lazy-count=\"3\"")
    # Unloaded rows count toward the total: 4 groups + 4 eager leaves + 3 lazy.
    @test contains(page, "4 of 11 rows shown")
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
    lazy_url = (k, ms) -> length(ms) > 1 ? "/rows?key=$k" : nothing
    lazy = html(grouped(group_by="party", group_rows_url=lazy_url, initially_open=t -> t.id == "p1"))
    @test !contains(tr(lazy, "row-group--Acme"), "data-htmxo-lazy-rows") &&
        contains(tr(lazy, "row-group--Acme"), "data-htmxo-tree-open=\"true\"")
    @test all(contains(lazy, "id=\"row-group--Acme--$id\"") for id in ("p1", "p2", "p7"))
    @test contains(tr(lazy, "row-group--Bakery"), "data-htmxo-lazy-rows=\"/rows?key=Bakery\"")
    # `true` keeps its meaning: every rendered group open, lazy groups lazy.
    all_open = html(grouped(group_by="party", group_rows_url=lazy_url, initially_open=true))
    @test contains(tr(all_open, "row-group--Acme"), "data-htmxo-lazy-rows=\"/rows?key=Acme\"")
    @test contains(tr(all_open, "row-group--Acme--Prime"), "data-htmxo-tree-open=\"true\"")
    # A predicate that opens nothing changes nothing.
    @test html(grouped(group_by="party", group_rows_url=lazy_url, initially_open=_ -> false)) ==
        html(grouped(group_by="party", group_rows_url=lazy_url))
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
    @test !contains(html(grouped(group_by="none")), "data-htmxo-leaf")
    # A leaf update: each copy of the leaf in the active grouping, identical to
    # the full table's, with its detail, plus the summary row of each group it
    # is in (computed over all members).
    upd = html(grouped(group_by="rule", selectable="tx", id="g", update_rows="p3"))
    @test startswith(upd, "<tbody data-htmxo-row-update=\"g\" data-htmxo-grouped=\"rule\" data-htmxo-update-leaves=\"[&quot;p3&quot;]\"")
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
    @test contains(upd, "id=\"row-group--Shops\"") && contains(upd, "<strong>Shops</strong> <small>(6)</small>")
    @test !contains(upd, "--p1\"") && count("<tr", upd) == 6
    # A group update: the group row and all its rows; a lazy group's row keeps
    # its lazy marks for a table that has not loaded it.
    lazy_url = (k, ms) -> length(ms) > 2 ? "/rows?key=$k" : nothing
    acme = html(grouped(group_by="party", id="g", group_rows_url=lazy_url, update_groups="Acme"))
    @test contains(acme, "data-htmxo-update-groups=\"[&quot;row-group--Acme&quot;]\"")
    # A run of listed siblings names the neighbours of its first row only;
    # the others follow the row before them in the update.
    @test places(acme) == "{'row-group--Acme':['','row-group--Acme--Prime'],'row-group--Acme--p1':['','row-group--Acme--p2']}"
    @test contains(acme, "data-htmxo-lazy-rows=\"/rows?key=Acme\"") && contains(acme, "data-htmxo-lazy-count=\"3\"")
    @test all(contains(acme, "id=\"row-group--Acme--$id\"") for id in ("p1", "p2", "p7"))
    @test !contains(acme, "Bakery")
    # Several keys at once; a group that no longer exists is in the scope with no rows.
    both = html(grouped(group_by="party", update_rows=["p4", "p1"], update_groups=("Gone",)))
    @test contains(both, "data-htmxo-update-leaves=\"[&quot;p4&quot;,&quot;p1&quot;]\"") &&
        contains(both, "data-htmxo-update-groups=\"[&quot;row-group--Gone&quot;]\"")
    @test contains(both, "id=\"row-group--Acme--p1\"") && contains(both, "id=\"row-group--Bakery--p4\"") &&
        !contains(both, "id=\"row-group--Bakery--p6\"")
    @test html(grouped(group_by="party", update_groups="Gone", id="g")) ==
        "<tbody data-htmxo-row-update=\"g\" data-htmxo-grouped=\"party\" data-htmxo-update-groups=\"[&quot;row-group--Gone&quot;]\"></tbody>"
    # The flat view names its rows by id; it has no groups to update.
    flat = html(grouped(group_by="none", selectable="tx", update_rows=["p1", "gone"], update_groups="Acme"))
    @test contains(flat, "data-htmxo-grouped=\"none\"") &&
        contains(flat, "data-htmxo-update-ids=\"[&quot;row-p1&quot;,&quot;row-gone&quot;]\"")
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
    @test_throws ArgumentError grouped(group_by="party", group_rows="Acme", update_rows="p1")
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
    @test contains(acme, "<strong>Acme</strong> <small>(3)</small>")
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
    @test contains(pills, "hx-get=\"/table\" hx-trigger=\"htmxo-regroup\" hx-target=\"closest [data-htmxo-grouped]\" hx-swap=\"outerHTML\"")
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
        !contains(flat, "data-htmxo-group=\"\"") && count("aria-pressed=\"false\"", flat) == 3
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
    @test_throws ArgumentError grouped(group_by="")
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
    # "Shops" (6) loads lazily; its rows count toward the total as if loaded:
    # 2 groups, Media's 2 subgroups and 2 leaves, Shops' 3 subgroups and 6 leaves.
    shops = row(page, "row-group--Shops")
    @test contains(shops, "data-htmxo-lazy-count=\"9\"") && contains(page, "2 of 15 rows shown")
    @test contains(shops, "data-htmxo-lazy-rows=\"/rows?key=%5B%22Shops%22%5D\"")
    # Search reaches the unloaded rows and the keys of the levels below.
    @test contains(shops, "data-htmxo-search-members=\"Acme DE01 -10.0 Acme DE02 -20.0 Acme Prime DE01 -30.0 Bakery DE03 -40.0 Bakery DE03 -60.0 Acme DE01 -70.0 Acme Acme Prime Bakery\"")
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
    @test !contains(rows, "id=\"row-group--Shops\"") && !contains(rows, "Media")
    inner = html(grouped(group_by=by, group_rows_url=lazy_url, selectable="tx", group_rows="[\"Shops\",\"Acme\"]", initially_open=true))
    @test startswith(inner, "<tbody data-htmxo-group-rows=\"[&quot;Shops&quot;,&quot;Acme&quot;]\"><tr data-htmxo-leaf=\"p1\"")
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
    @test contains(row(upd, "row-group--Shops"), "<strong>Shops</strong> <small>(6)</small>")
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
    @test contains(row(lz, "row-group--Shops"), "data-htmxo-lazy-count=\"9\"") && contains(lz, "id=\"row-group--Shops--Acme--p1\"")
    # The flat view of an ordered grouping names its rows by id.
    @test contains(html(grouped(group_by=String[], update_rows="p1", id="g")), "data-htmxo-grouped=\"[]\" data-htmxo-update-ids=")
    @test_throws ArgumentError grouped(group_by=by, update_groups="[]")
    @test_throws ArgumentError grouped(group_by=by, update_groups="Shops")
end

@testitem "regroupable table browser" setup=[GroupingFixtures, ChromeDump] tags=[:unit, :browser] begin
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
            const total = () => g().querySelector('[data-htmxo-table-count]').textContent;
            check('initial', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video' && total() === '4 of 11 rows shown');
            check('lazy-placeholder', row('group--Acme').dataset.htmxoLazyRows && !row('group--Acme--p1'));
            // Expanding a lazy group fetches its rows once and opens it.
            toggle('group--Acme');
            await wait(() => row('group--Acme--p1'));
            check('lazy-loaded', shown() === 'group--Acme,group--Acme--p1,group--Acme--p2,group--Acme--p7,group--Acme--Prime,group--Bakery,group--Prime--Video' &&
                row('group--Acme').getAttribute('aria-expanded') === 'true' && !('htmxoLazyRows' in row('group--Acme').dataset));
            check('lazy-count', total() === '7 of 11 rows shown');
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
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=15000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
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
        table(group_by; q="", kw...) = master_detail_table(["Party", "IBAN", "Amount", "Flag"], data;
            key=t -> t.id,
            master=t -> (h.td(t.party), h.td(t.iban), h.td(string(t.amount)),
                h.td(h.span(t.id in flagged ? "flagged" : "-"; class="flag"),
                     h.button("flag"; type="button", data_flag=t.id,
                         hx_post="/flag?id=$(t.id)&group_by=$group_by", hx_target="closest tr", hx_swap="outerHTML"))),
            detail=t -> h.p("memo $(t.id) ", t.id in flagged ? "flagged" : "plain"),
            groupings=GROUPINGS, group_by, group_by_url="/table",
            group_rows_url=(k, ms) -> length(ms) > 2 ? "/rows?group_by=$group_by&key=$(esc(k))" : nothing,
            group_master=(k, ms) -> (h.td(h.strong(k), " ", h.small("($(length(ms)))")),
                h.td(h.select(; name="mode", data_mode=k, hx_post="/mode?group=$(esc(k))&group_by=$group_by")(
                    h.option("off"; selected=get(modes, k, "off") == "off"), h.option("on"; selected=get(modes, k, "off") == "on"))),
                h.td(string(count(m -> m.id in flagged, ms), " flagged")), h.td(get(modes, k, "off"))),
            selectable="tx", select_form="bulk", searchable=true, search_query=q,
            expand_controls=group_by != "none", id="g", kw...)
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
            const regroup = async v => {
                const select = g().querySelector('select[name="group_by"]');
                select.value = v; select.dispatchEvent(new Event('change', {bubbles: true}));
                await wait(() => g().dataset.htmxoGrouped === v);
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
            const markup = () => body().innerHTML.replace(/ class=""/g, '');
            const snapshot = markup();
            await post('/flag?id=p1&group_by=iban', row('group--Acme--p1'));
            check('wrong-grouping', markup() === snapshot &&
                /grouped by "iban" but the table by "party"/.test((document.querySelector('.htmxo-toast-error') || {}).textContent || ''));
            await post('/flag?id=p1&group_by=iban', row('group--Acme--p1'));   // back to flagged on the server
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
            // The flat view: rows by id, detail state kept.
            await regroup('none');
            row('p4').querySelector('[data-htmxo-detail-toggle]').click();
            await flag('p4');
            check('flat', flagText('p4') === 'flagged' && !detail('p4').hidden && detail('p4').textContent.includes('flagged') &&
                row('p4').querySelector('[data-htmxo-disclosure]').textContent === '▾' && order().split(',').length === 2 * 6);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(bulk, table("party"), driver;
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
                html(table(q["group_by"]; q=get(q, "q", "")))
            elseif uri.path == "/rows"
                html(table(q["group_by"]; group_rows=q["key"]))
            elseif uri.path == "/flag"
                id = q["id"]
                id in flagged ? delete!(flagged, id) : push!(flagged, id)
                html(table(q["group_by"]; update_rows=id))
            elseif uri.path == "/mode"
                modes[q["group"]] = form["mode"]
                html(table(q["group_by"]; update_groups=q["group"]))
            elseif uri.path == "/move"
                id, from = q["id"], party(q["id"])
                data[findfirst(t -> t.id == id, data)] = (; only(t for t in data if t.id == id)..., party=q["to"])
                html(table(q["group_by"]; update_rows=id, update_groups=[from, q["to"]]))
            elseif uri.path == "/delete"
                id, from = q["id"], party(q["id"])
                filter!(t -> t.id != id, data)
                html(table(q["group_by"]; update_rows=id, update_groups=from))
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
            check('nested-rows', shown() === 'group--Acme,group--Acme--Prime,group--Bakery,group--Prime--Video' && total() === '4 of 16 rows shown');
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
            check('three-levels', shown() === 'group--Shops,group--Media' && total() === '2 of 21 rows shown' &&
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
            check('expand-all-open', rows().every(r => !r.hidden) && total() === '21 of 21 rows shown' &&
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
            detail_url=t -> "/detail?id=$(t.id)", detail_toggle=:label, groupings=GROUPINGS, group_by,
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
            groupings, group_by="Stage", searchable=true, id="docs", kw...)
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
                html(q["gb"] == "single" ? single(; update_rows=id, update_groups=[from, to]) :
                    nested(; update_rows=id, update_groups=["[\"$from\"]", "[\"$to\"]"]))
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
