@dynamicstruct struct RegroupDemoData end

# Synthetic bank transactions: deterministic, no real parties or accounts.
# Weights make some counterparties frequent (large groups load lazily) and
# others rare.
const _REGROUP_PARTIES = [
    (party="Acme Online GmbH", iban="DE11 0000 0000 0000 0000 01", category="Retail", weight=9),
    (party="Acme Online GmbH", iban="DE11 0000 0000 0000 0000 02", category="Retail", weight=4),
    (party="Acme Prime", iban="DE11 0000 0000 0000 0000 01", category="Subscriptions", weight=3),
    (party="Streamly", iban="LU22 0000 0000 0000 0003", category="Subscriptions", weight=3),
    (party="Tuneful AB", iban="SE33 0000 0000 0000 0000 04", category="Subscriptions", weight=2),
    (party="City Power", iban="DE44 0000 0000 0000 0000 05", category="Utilities", weight=2),
    (party="Corner Bakery", iban="DE55 0000 0000 0000 0000 06", category="Food", weight=7),
    (party="Railway Co", iban="DE66 0000 0000 0000 0000 07", category="Travel", weight=3),
    (party="Harbour Books", iban="NL77 0000 0000 0000 08", category="Retail", weight=1),
    (party="Night Taxi", iban="DE88 0000 0000 0000 0000 09", category="Travel", weight=1),
]

# Rules overlap on purpose: an "Acme Prime" payment matches two rules, so
# grouped by Rule it is listed under each, and selecting it once selects both.
const _REGROUP_RULES = [
    "Online retail" => r"Acme|Books",
    "Subscriptions" => r"Streamly|Tuneful|Prime",
    "Household" => r"Power|Bakery",
    "Transport" => r"Railway|Taxi",
]

const _REGROUP_TX = let picks = reduce(vcat, [fill(p, p.weight) for p in _REGROUP_PARTIES])
    [let p = picks[mod1(i * 13, length(picks))]
        (; id=string("t", lpad(i, 3, '0')), date=string("2026-09-", lpad(mod1(i * 11, 28), 2, '0')),
           p.party, p.iban, p.category, amount=-(5 + mod(i * 37, 240)) - mod(i, 7) / 10,
           memo="Synthetic transaction $i for $(p.party).")
    end for i in 1:360]
end

const _REGROUP_GROUPINGS = [
    "None" => nothing,
    "Counterparty" => t -> t.party,
    "IBAN" => t -> t.iban,
    "Category" => t -> t.category,
    "Rule" => t -> [name for (name, re) in _REGROUP_RULES if occursin(re, t.party)],
]

_regroup_amount(x) = h.td(string(round(x; digits=2)); data_sort_value=string(x))

# What the row and group actions change, in this process only: a review mark
# per transaction and a rule mode per group of a grouping.
const _REGROUP_REVIEWED = Set{String}()
const _REGROUP_MODES = Dict{Tuple{Vector{String},String},String}()

# `group_by` is the ordered list of grouping levels (outermost first). Group
# keys are then paths (`["Retail","Corner Bakery"]`); a group row shows its
# own level's key.
function _regroup_table(self, group_by, q; kw...)
    master_detail_table(["Counterparty", "Date", "IBAN", "Category", "Amount", "Review"], _REGROUP_TX;
        key=t -> t.id,
        master=t -> (h.td(t.party), h.td(t.date), h.td(h.code(t.iban; style="white-space: nowrap")),
                     h.td(t.category), _regroup_amount(t.amount),
                     # A row action: the route answers with this row's copies
                     # and their groups' summaries (`update_rows`).
                     h.td(h.button(t.id in _REGROUP_REVIEWED ? "✓ reviewed" : "mark reviewed"; type="button",
                         class="secondary outline", hx_post=query_url(self / "review"; id=t.id, group_by),
                         hx_target="closest tr", hx_swap="outerHTML"))),
        detail=t -> h.p(t.memo; style="margin: 0; padding: .5rem 1rem"), detail_toggle=:label,
        groupings=_REGROUP_GROUPINGS, group_by, group_by_url=self / "table",
        # Groups over 30 rows load their rows when first expanded.
        group_rows_url=(key, members) -> length(members) > 30 ?
            query_url(self / "rows"; group_by, key) : nothing,
        # A group row hosts a caller control: changing it never toggles the
        # group, and its route answers with the group's rows (`update_groups`).
        group_master=(key, members) -> (
            h.td(h.strong(last(HTMXObjects.group_path(key))), " ", h.small("($(length(members)))")), h.td(""), h.td(""),
            h.td(h.select(; name="mode", aria_label="Rule mode for $(last(HTMXObjects.group_path(key)))",
                hx_post=query_url(self / "rule_mode"; group=key, group_by))(
                (h.option(m; selected=m == get(_REGROUP_MODES, (group_by, key), "off"))
                 for m in ("off", "suggest", "auto"))...)),
            _regroup_amount(sum(m.amount for m in members)),
            h.td(h.small("$(count(m -> m.id in _REGROUP_REVIEWED, members)) of $(length(members)) reviewed"))),
        searchable=true, search_query=q, expand_controls=true,
        selectable="rows", select_form="regroup-bulk", id="regroup", kw...)
end

# The same transactions regrouped in the browser alone: no routes, group rows
# from declared column summaries, so a copy of this page recorded with
# `record!` and served as plain files regroups too.
_regroup_browser_table() = master_detail_table(["Counterparty", "Date", "IBAN", "Category", "Amount"], _REGROUP_TX;
    key=t -> t.id,
    master=t -> (h.td(t.party), h.td(t.date), h.td(h.code(t.iban; style="white-space: nowrap")),
                 h.td(t.category), _regroup_amount(t.amount)),
    detail=t -> h.p(t.memo; style="margin: 0; padding: .5rem 1rem"), detail_toggle=:label,
    groupings=_REGROUP_GROUPINGS, group_by=["Category", "Counterparty"],
    group_summary=["Amount" => ColumnSummary(:sum, t -> t.amount; digits=2)],
    searchable=true, expand_controls=true, id="regroup-browser")

@htmx struct RegroupDemoRoutes
    @get index() = h.div(
        h.h1("Regroupable Table Demo"),
        h.p("One set of $(length(_REGROUP_TX)) synthetic transactions, regrouped by the ",
            h.em("Group by"), " pills: click a pill to add or remove its level, and drag the active ones ",
            "(or use their ‹ › buttons, or ←/→) to change the nesting. This table's group rows hold a ",
            "rule-mode control and its big groups load lazily, so the server renders each grouping; ",
            h.a("the same rows regrouped in the browser alone"; href=__self__ / "browser"),
            " need no server at all. Selection is keyed by transaction, ",
            "so it survives regrouping; search matches group and row text; grouped by ", h.em("Rule"),
            ", one payment can belong to several groups. Groups over 30 rows load when first expanded, ",
            "at any level. Select group rows to act on whole groups. Marking a row reviewed or changing ",
            "a group's rule mode re-renders only the rows it changed, keeping the open groups, the ",
            "selection and the search."),
        h.form(; id="regroup-bulk", hx_post=__self__ / "bulk", hx_swap="none", data_htmxo_toast="body")(
            h.fieldset(; role="group")(
                h.select(; name="category", aria_label="Category")(
                    h.option("Retail"), h.option("Food"), h.option("Travel")),
                h.button("Categorize selected"; data_htmxo_needs_selection="rows", disabled=true))),
        _regroup_table(__self__, ["Category", "Counterparty"], ""),
        sortable_table_js(), sortable_table_styles())

    @get browser() = h.div(
        h.h1("Regrouped in the Browser"),
        h.p("The same $(length(_REGROUP_TX)) transactions with no table routes: the pills regroup the rows ",
            "in the page, and each group row sums its rows' amounts there. A copy of this page recorded with ",
            h.code("record!"), " and served as plain files works the same."),
        _regroup_browser_table(),
        sortable_table_js(), sortable_table_styles())

    @get table(; group_by::Vector{String}=["Category", "Counterparty"], q::String="") =
        _regroup_table(__self__, group_by, q)

    @get rows(; group_by::Vector{String}=["Category", "Counterparty"], key::String="") =
        _regroup_table(__self__, group_by, ""; group_rows=key)

    @direct @post review(; id::String="", group_by::Vector{String}=["Category", "Counterparty"]) =
        (id in _REGROUP_REVIEWED ? delete!(_REGROUP_REVIEWED, id) : push!(_REGROUP_REVIEWED, id);
         _regroup_table(__self__, group_by, ""; update_rows=id))

    @post bulk(; category::String="", group_by::Vector{String}=String[], rows::Vector{String}=String[],
               rows_group::Vector{String}=String[]) =
        string("Would categorize $(length(rows)) transaction(s)",
               isempty(rows_group) ? "" : string(" and the group(s) ",
                   join((join(HTMXObjects.group_path(g), " › ") for g in rows_group), ", ")),
               " as $category.")

    @direct @post rule_mode(; group::String="", mode::String="",
                           group_by::Vector{String}=["Category", "Counterparty"]) =
        (_REGROUP_MODES[(group_by, group)] = mode;
         hx_response(_regroup_table(__self__, group_by, ""; update_groups=group);
                     toast="Rule mode for $(join(HTMXObjects.group_path(group), " › ")): $mode."))
end
