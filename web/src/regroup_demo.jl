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

# Rules overlap on purpose: an "Acme Prime" payment matches two rules, so in
# "Group by: Rule" it is listed under each, and selecting it once selects both.
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

function _regroup_table(self, group_by, q; group_rows=nothing)
    master_detail_table(["Counterparty", "Date", "IBAN", "Category", "Amount"], _REGROUP_TX;
        key=t -> t.id,
        master=t -> (h.td(t.party), h.td(t.date), h.td(h.code(t.iban; style="white-space: nowrap")),
                     h.td(t.category), _regroup_amount(t.amount)),
        detail=t -> h.p(t.memo; style="margin: 0; padding: .5rem 1rem"), detail_toggle=:label,
        groupings=_REGROUP_GROUPINGS, group_by, group_by_url=self / "table",
        # Groups over 30 rows load their rows when first expanded.
        group_rows_url=(key, members) -> length(members) > 30 ?
            query_url(self / "rows"; group_by, key) : nothing,
        group_rows,
        # A group row hosts a caller control: changing it never toggles the group.
        group_master=(key, members) -> (
            h.td(h.strong(key), " ", h.small("($(length(members)))")), h.td(""), h.td(""),
            h.td(h.select(; name="mode", aria_label="Rule mode for $key",
                hx_post=query_url(self / "rule_mode"; group=key), hx_swap="none",
                data_htmxo_toast="body")(h.option("off"), h.option("suggest"), h.option("auto"))),
            _regroup_amount(sum(m.amount for m in members))),
        searchable=true, search_query=q, expand_controls=group_by != "None",
        selectable="rows", select_form="regroup-bulk", id="regroup")
end

@htmx struct RegroupDemoRoutes
    @get index() = h.div(
        h.h1("Regroupable Table Demo"),
        h.p("One set of $(length(_REGROUP_TX)) synthetic transactions, regrouped on the server by the ",
            h.em("Group by"), " control. Selection is keyed by transaction, so it survives regrouping; ",
            "search matches group and row text; in ", h.em("Rule"), " grouping one payment can belong ",
            "to several groups. Groups over 30 rows load when first expanded. Select group rows to act ",
            "on whole groups."),
        h.form(; id="regroup-bulk", hx_post=__self__ / "bulk", hx_swap="none", data_htmxo_toast="body")(
            h.fieldset(; role="group")(
                h.select(; name="category", aria_label="Category")(
                    h.option("Retail"), h.option("Food"), h.option("Travel")),
                h.button("Categorize selected"; data_htmxo_needs_selection="rows", disabled=true))),
        _regroup_table(__self__, "Counterparty", ""),
        sortable_table_js(), sortable_table_styles())

    @get table(; group_by::String="Counterparty", q::String="") = _regroup_table(__self__, group_by, q)

    @get rows(; group_by::String="Counterparty", key::String="") =
        _regroup_table(__self__, group_by, ""; group_rows=key)

    @post bulk(; category::String="", group_by::String="", rows::Vector{String}=String[],
               rows_group::Vector{String}=String[]) =
        string("Would categorize $(length(rows)) transaction(s)",
               isempty(rows_group) ? "" : " and $(length(rows_group)) $(lowercase(group_by)) group(s)",
               " as $category.")

    @post rule_mode(; group::String="", mode::String="") = "Rule mode for $group: $mode."
end
