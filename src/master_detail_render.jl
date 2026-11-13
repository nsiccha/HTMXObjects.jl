# Keep the rendering engine independent of each caller's lambda types. The
# small callback itself still dispatches on the concrete item type, while the
# large table walk and its recursive closures share this one callable type.
struct _MDCallback <: Function
    callback::Any
end
(f::_MDCallback)(args...; kwargs...) = f.callback(args...; kwargs...)
_md_callback(f) = _MDCallback(f)
_md_callback(::Nothing) = nothing
_md_callback(f::_MDCallback) = f
_md_function(f::Function) = _md_callback(f)
_md_function(f) = f

function _master_detail_table(headers, items;
                             key, master, detail=nothing,
                             detail_url=nothing,
                             detail_instance::Bool=false,
                             master_attrs=nothing,
                             master_class=nothing,
                             detail_class=nothing,
                             initially_open::Union{Bool,Function}=false,
                             initially_open_detail::Union{Nothing,Bool,Function}=nothing,
                             children=nothing,
                             branches_collapsible::Bool=true,
                             detail_toggle::Symbol=:button,
                             searchable::Bool=false,
                             search_text=nothing,
                             selectable=nothing,
                             select_form=nothing,
                             select_value=nothing,
                             select_submit=nothing,
                             expand_controls::Bool=false,
                             search_query::AbstractString="",
                             groupings=nothing,
                             group_by=nothing,
                             group_master=nothing,
                             group_by_url=nothing,
                             group_rows_url=nothing,
                             group_rows=nothing,
                             group_summary=nothing,
                             group_order=nothing,
                             group_masters::Bool=false,
                             leaf_key=nothing,
                             leaf_order=nothing,
                             update_rows=nothing,
                             update_groups=nothing,
                             link=nothing,
                             link_key=nothing,
                             sticky::Bool=true,
                             _rows_only::Bool=false,
                             _sort_item=identity,
                             _toolbar=(),
                             _level_marks::Bool=false,
                             _max_level::Int=0,
                             _update_scope=nothing,
                             _detail_key=key,
                             texts::TableTexts=_EN_TABLE_TEXTS,
                             kwargs...)
    # Refused: a link key with no link group would highlight nothing.
    isnothing(link) && !isnothing(link_key) && throw(ArgumentError(
        "master_detail_table: `link_key(item)` keys the rows of the link group `link`; give `link` too"))
    # `id=nothing` is no id: no element is named after it, and the names a
    # table without an id makes for itself are not overridden by it.
    get(kwargs, :id, missing) === nothing && (kwargs = pairs(Base.structdiff(values(kwargs), NamedTuple{(:id,)})))
    if !isnothing(groupings)
        # A `name => :children` grouping regroups the leaves of the tree
        # `children` builds: the other groupings list each leaf once.
        tree = _md_tree_grouping(groupings, items, key, children, leaf_key, leaf_order)
        return _grouped_master_detail_table(headers, isnothing(tree) ? items : tree.leaves;
            key = isnothing(tree) ? key : tree.leaf, master, detail, detail_url, detail_instance, master_attrs, master_class, detail_class,
            initially_open, initially_open_detail, outline=tree, branches_collapsible, detail_toggle, searchable,
            search_text, selectable, select_form, select_value, select_submit,
            expand_controls, search_query, groupings, group_by, group_master, group_by_url,
            group_rows_url, group_rows, group_summary, group_order, group_masters, update_rows, update_groups, link, link_key, sticky, texts, kwargs...)
    end
    !group_masters && all(isnothing, (group_by, group_master, group_by_url, group_rows_url, group_rows, group_summary, group_order, update_groups,
                    leaf_key, leaf_order)) || throw(ArgumentError(
        "master_detail_table: group_by/group_master/group_by_url/group_rows_url/group_rows/group_summary/group_order/group_masters/update_groups/leaf_key/leaf_order require `groupings`"))
    detail_toggle in (:button, :label) || throw(ArgumentError(
        "master_detail_table: detail_toggle must be :button or :label"))
    # Refused: without collapsible branches there is nothing to expand.
    expand_controls && (isnothing(children) || !branches_collapsible) && throw(ArgumentError(
        "master_detail_table: expand_controls needs `children` with collapsible branches"))
    selecting = !isnothing(selectable)
    selecting || all(isnothing, (select_form, select_value, select_submit)) || throw(ArgumentError(
        "master_detail_table: select_form/select_value/select_submit require selectable=<input name>"))
    ncols = length(headers)
    (!isnothing(children) || !isnothing(detail_url) || !isnothing(detail)) || throw(ArgumentError(
        "master_detail_table: supply `detail` (eager body) or `detail_url` (lazy URL)"))
    # Refused: only content swapped in gets ids of its own, and an eager
    # detail is rendered with the table.
    detail_instance && isnothing(detail_url) && throw(ArgumentError(
        "master_detail_table: `detail_instance=true` names the place of each row's lazy detail; give `detail_url`"))
    # `detail_url` may be a per-item `item -> url` callback or a bare String
    # (same URL for every row — unusual, but supported).
    _url = detail_url isa Union{Nothing,Function} ? detail_url : (_ -> detail_url)
    rows = Any[]
    # Columns whose sort keys the table computes: (column, functions).
    sort_columns = [(i, Any[last(k) for k in hdr.sort_keys])
                    for (i, hdr) in enumerate(headers) if _computed_sort_keys(hdr)]
    _open = initially_open isa Function ? initially_open : (_ -> initially_open)
    _open_detail = initially_open_detail isa Bool ? (_ -> initially_open_detail) : initially_open_detail
    seen = Set{String}()
    max_level = Ref(1)
    # `update_rows`: render only these items' rows (see `_md_row_update`); the
    # walk still visits every item, so levels, parents and each row's place
    # among its siblings (`placed`) stay those of the full table.
    update_keys = _md_update_keys(update_rows)
    update = isnothing(update_rows) ? nothing : Set(update_keys)
    placed = Pair{String,Tuple{String,String}}[]
    # The leaves of lazy branches, which the search count counts unloaded.
    pending = String[]
    # The eager details Markdown writes after the table, each item's once
    # (`_detail_key`: a leaf listed under several groups is one item).
    details = Pair{Vector{Any},Any}[]
    detail_rows = String[]      # the id of each detail's master row
    detailed = Set{String}()
    function visit(item, parent, level, ancestors_open)
        item_key = key(item)
        descendants = isnothing(children) ? () : children(item)
        # A branch whose rows load on first expand (see `group_rows_url`).
        lazy_rows = descendants isa _MDLazyRows ? descendants : nothing
        descendants = isnothing(lazy_rows) ? collect(descendants) : ()
        branch = !isnothing(lazy_rows) || !isempty(descendants)
        open = isnothing(lazy_rows) && _open(item)
        branch_open = branch && (!branches_collapsible || open)
        safe = _md_safe_key(item_key)
        if !isnothing(children)
            safe in seen && throw(ArgumentError(
                "master_detail_table: hierarchy keys must be unique after sanitisation; repeated $(repr(item_key))"))
            push!(seen, safe)
        end
        isnothing(update) || string(item_key) in update ||
            return visit_children(descendants, safe, level, ancestors_open && branch_open)
        attrs = Dict{Symbol,Any}(Symbol(k) => v
                                 for (k, v) in pairs(isnothing(master_attrs) ? (;) : master_attrs(item)))
        # `link`: the row's item key for hover linking, `link_key(item)` else
        # its `key` (a group row has none).
        item_link = isnothing(link) ? nothing : something(link_key, key)(item)
        if !isnothing(item_link)
            any(k -> _md_attr_name(k) === Symbol("data-htmxo-link-key"), keys(attrs)) && throw(ArgumentError(
                "master_detail_table: with `link`, a row's `data-htmxo-link-key` is its `link_key` (default: its `key`); `master_attrs` may not set it"))
            attrs[Symbol("data-htmxo-link-key")] = string(item_link)
        end
        if !isnothing(children)
            attrs[:data_htmxo_parent] = parent
            attrs[:aria_level] = string(level)
            ancestors_open || (attrs[:hidden] = true)
            if branch && branches_collapsible
                attrs[:data_htmxo_tree_open] = string(open)
                attrs[:aria_expanded] = string(open)
            end
            if !isnothing(lazy_rows)
                attrs[:data_htmxo_lazy_rows] = lazy_rows.url
                append!(pending, lazy_rows.leaves)
            end
            max_level[] = max(max_level[], level)
        end
        isnothing(search_text) || (attrs[:data_htmxo_search] = string(search_text(item)))
        # In lazy mode `detail(item)` (if given) is the per-row placeholder.
        body = isnothing(detail) ? nothing : detail(item)
        url  = isnothing(_url) ? nothing : _url(item)
        has_detail = isnothing(children) || !isnothing(body) || !isnothing(url)
        # `initially_open` opens what a click on the row opens, so a
        # collapsible branch shows its child rows and keeps its own detail
        # closed; `initially_open_detail`, when given, decides every detail.
        detail_open = has_detail && (isnothing(_open_detail) ?
            open && !(branch && branches_collapsible) : _open_detail(item))
        cells, row_attrs = _md_master_row(master(item), texts)
        # A group row (`_sort_item` gives `nothing`) sorts by its own value.
        sort_item = isempty(sort_columns) ? nothing : _sort_item(item)
        isnothing(sort_item) || _md_sort_values!(cells, sort_columns, sort_item, headers)
        _md_merge_row_attrs!(attrs, row_attrs, master_class)
        if branch && branches_collapsible && !selecting && !haskey(attrs, :onclick)
            attrs[:onclick] = "htmxoTreeRow(this,event)"
            attrs[:data_htmxo_tree_row_toggle] = ""
        end
        if selecting
            # `master_attrs` or the master <tr> may preselect a row or give its
            # value. The submitted value defaults to the caller's own key, not
            # the sanitised row id the runtime keys its state by.
            given = Set(_md_attr_name(k) for k in keys(attrs))
            Symbol("aria-selected") in given || (attrs[Symbol("aria-selected")] = "false")
            attrs[:tabindex] = "-1"
            value = Symbol("data-htmxo-select-value")
            if !isnothing(select_value)
                attrs[value] = string(select_value(item))
            elseif !(value in given)
                attrs[value] = string(item_key)
            end
            isnothing(select_submit) || select_submit(item) ||
                (attrs[Symbol("data-htmxo-select-submit")] = "false")
        end
        # Every expandable row carries a native detail control in its first
        # cell, so keyboard and screen-reader users reach the detail too (the
        # row click is a pointer-only shortcut). Sorting, search and CSV read
        # the cell's own content from the `data-htmxo-row-label` span.
        isempty(cells) && throw(ArgumentError("master_detail_table: rows require at least one cell"))
        first_cell = first(cells)
        first_cell isa Node || throw(ArgumentError(string("master_detail_table: the first ",
            "master cell must be a <td> node, got ", typeof(first_cell))))
        controls = Any[]
        trailing_controls = Any[]
        label = Any[HTMX.children(first_cell)...]
        if !isnothing(body) && isnothing(url) && !(string(_detail_key(item)) in detailed)
            push!(detailed, string(_detail_key(item)))
            push!(details, label => body)
            push!(detail_rows, "row-$safe")
        end
        if branch && branches_collapsible
            # An update names the child rows it renders; the runtime then
            # recomputes the list from the rows on the page.
            child_ids = join(("row-$(_md_safe_key(key(child)))" for child in descendants
                              if isnothing(update) || string(key(child)) in update), " ")
            branch_attrs = (; type="button", data_htmxo_tree_toggle="",
                (isempty(child_ids) ? (;) : (; aria_controls=child_ids))...,
                aria_expanded=string(open),
                onclick="htmxoTreeToggle(this); event.stopPropagation()")
            if !(has_detail && detail_toggle === :label) && !any(_md_interactive_label, label)
                label = Any[_LabelledControl(h.button(label...; branch_attrs...,
                    data_htmxo_tree_label="", data_htmxo_label=""))]
            else
                push!(controls, h.button(_md_disclosure_glyph(open); branch_attrs...,
                    aria_label=texts.toggle_children))
            end
        end
        if has_detail
            attrs[:data_htmxo_detail_open] = string(detail_open)
            # Plain hierarchy leaves use their label as the keyboard detail
            # control. Linked leaves and branches with their own details keep
            # a separate icon, so links and child-row expansion remain distinct.
            # Flat tables retain their compact disclosure control by default.
            # `:label` makes every plain label the control; a label holding a
            # control keeps the separate one in any mode (`_md_interactive_label`).
            label_detail = !any(_md_interactive_label, label) &&
                (detail_toggle === :label || (!isnothing(children) && !branch))
            toggle_label, label_attrs =
                label_detail ? (label, (; data_htmxo_label="")) :
                isnothing(children) ? (Any[_md_disclosure_glyph(detail_open)],
                                       (; data_htmxo_disclosure="", aria_label=texts.details)) :
                (Any["ⓘ"], (; aria_label=texts.details, title=texts.details))
            toggle = h.button(toggle_label...; type="button",
                data_htmxo_detail_toggle="", label_attrs..., aria_controls="detail-$safe",
                aria_expanded=string(detail_open), onclick="htmxoMdControl(this,event)")
            if label_detail
                label = Any[_LabelledControl(toggle)]
            else
                push!(isnothing(children) ? controls : trailing_controls, toggle)
            end
        end
        # Markdown has no indentation: with several grouping levels, a mark
        # per level keeps the nesting readable there.
        marks = _level_marks && level > 1 ? (markdown_only("› "^(level - 1)),) : ()
        cells[1] = Node(HTMX.tag(first_cell), copy(HTMX.attrs(first_cell)),
            Any[controls..., marks..., h.span(; data_htmxo_row_label="")(label...), trailing_controls...])
        if !isnothing(children) && isnothing(body) && isnothing(url)
            # Group rows need no placeholder or detail request. Their children
            # are ordinary rows in this same tbody, visible from first paint.
            isnothing(master_class) || (attrs[:class] = master_class)
            push!(rows, h.tr(; id="row-$safe", attrs...)(cells...))
        else
            (m, d) = master_detail_pair(item_key, cells, body, ncols;
                                    master_class, detail_class, master_attrs=attrs,
                                    initially_open=detail_open && ancestors_open, detail_url=url, detail_instance,
                                    row_toggle=!selecting, texts, _row_expanded=!isnothing(children))
            push!(rows, m, d)
        end
        visit_children(descendants, safe, level, ancestors_open && branch_open)
    end
    visit_children(descendants, safe, level, open) =
        visit_siblings(descendants, "row-$safe", level + 1, open)
    function visit_siblings(siblings, parent, level, open)
        isnothing(update) || _md_record_places!(placed, [string(key(s)) for s in siblings], update)
        for item in siblings
            visit(item, parent, level, open)
        end
    end
    visit_siblings(items, "", 1, true)
    # Every row this call renders (a whole table, a row update, lazy rows, the
    # browser's group-row template) aligns the cells of an aligned column.
    rows = _aligned_rows(rows, headers)
    _rows_only && return rows
    isnothing(update) || return _md_row_update(rows, get(kwargs, :id, nothing);
        something(_update_scope, (; ids=["row-" * _md_safe_key(k) for k in update_keys]))...,
        places=placed)
    table_attrs = isnothing(children) ? (;) : (; data_htmxo_hierarchy="", role="treegrid")
    selecting && (table_attrs = (; table_attrs..., aria_multiselectable="true"))
    # The expand controls name the body they drive; a body without a caller id
    # gets one from its root keys, which are unique on the page.
    # Only expand controls need a generated target. Avoid walking all keys
    # and hashing a row-count-sized tuple when that target is never used.
    body_id = !expand_controls ? nothing : haskey(kwargs, :id) ? string(kwargs[:id]) :
        "htmxo-tree-" * string(hash(Tuple(_md_safe_key(key(item)) for item in items)); base=36)
    expand_controls && !haskey(kwargs, :id) && (table_attrs = (; table_attrs..., id=body_id))
    # The rows in the `default_sort` order, as `sortable_table` would write
    # them, and the details written after the table in the same order. A
    # column of interval cells has their five sort keys (`interval_cell`).
    table_headers = _interval_headers(headers, _interval_columns(rows), texts)
    ds = _resolve_default_sort(get(kwargs, :default_sort, nothing), table_headers)
    if !isnothing(ds)
        rows = _default_sort_rows(rows, ds, table_headers; hierarchy=haskey(table_attrs, :data_htmxo_hierarchy))
        position = Dict(_row_id(r) => i for (i, r) in enumerate(rows))
        perm = sortperm(detail_rows; by=id -> get(position, id, typemax(Int)), alg=MergeSort)
        permute!(details, perm)
    end
    table = sortable_table(map(_sort_key_names_only, table_headers), rows; table_attrs..., texts, link, sticky,
        _stamp_texts=false, _presorted=true, kwargs...)
    # Depth is semantic row metadata, not per-row inline styling. The
    # stylesheet covers the actual depth; its other rules style the row
    # controls every master/detail table now carries. A narrow first column
    # must not break between those controls and the label: the cell does not
    # wrap, only the label's text (or its label button's) does, and
    # `text-wrap-mode` leaves an app's `white-space` collapsing alone. Engines
    # disagree on which style governs a break beside an atomic button, so a
    # control after the label and a glyph before it are joined by U+2060.
    rules = """
    [data-htmxo-hierarchy] > tbody > tr > td:first-child > button[data-htmxo-tree-toggle] { width: auto; margin: 0 .35em 0 0; padding: 0; border: 0; border-radius: 0; background: transparent; box-shadow: none; color: inherit; font: inherit; line-height: inherit; vertical-align: baseline; }
    [data-htmxo-hierarchy] > tbody > tr > td:first-child > button[data-htmxo-tree-toggle]:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: .1em; }
    [data-htmxo-hierarchy] > tbody > tr > td:first-child > button[data-htmxo-detail-toggle] { width: auto; margin: 0 0 0 .5em; padding: 0; border: 0; border-radius: 0; background: transparent; box-shadow: none; color: var(--pico-muted-color, inherit); font: inherit; line-height: inherit; vertical-align: baseline; }
    [data-htmxo-hierarchy] > tbody > tr > td:first-child > button[data-htmxo-detail-toggle]:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: .1em; }
    [data-htmxo-hierarchy] > tbody > tr[hidden] { display: none !important; }
    .htmxo-tree-controls { display: flex; flex-wrap: wrap; gap: .5rem; margin: 0 0 calc(var(--pico-spacing, 1rem) / 2); }
    .htmxo-tree-controls > button { width: auto; margin: 0; padding: .15em .7em; font-size: .875em; }
    .htmxo-tree-controls > label { display: inline-flex; align-items: baseline; gap: .5rem; margin: 0 .5rem 0 0; font-size: .875em; }
    .htmxo-tree-controls > label > select { width: auto; margin: 0; padding-block: .15em; font-size: inherit; }
    .htmxo-tree-controls > .htmxo-group-pills[role="group"] { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .35rem; width: auto; margin: 0 .5rem 0 0; border-radius: 0; box-shadow: none; font-size: .875em; }
    .htmxo-group-pills[role="group"] > * { flex: none; margin: 0; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill { display: inline-flex; align-items: center; border: 1px solid var(--pico-muted-border-color, GrayText); border-radius: 1em; color: inherit; cursor: grab; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill[data-htmxo-group-level] { border-color: var(--pico-contrast-background, CanvasText); background: var(--pico-contrast-background, CanvasText); color: var(--pico-contrast-inverse, Canvas); }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button { width: auto; margin: 0; padding: .1em .65em; border: 0; border-radius: 1em; background: transparent; box-shadow: none; color: inherit; font: inherit; line-height: 1.5; cursor: pointer; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button.htmxo-group-move { padding-inline: .3em; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button.htmxo-group-move:last-child { padding-inline-end: .6em; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button:disabled { opacity: .35; cursor: default; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button[aria-disabled="true"] { cursor: default; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill > button:focus-visible { outline: 2px solid currentColor; outline-offset: -3px; }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill[data-htmxo-drop="before"] { box-shadow: -3px 0 0 var(--pico-contrast, CanvasText); }
    .htmxo-group-pills[role="group"] > .htmxo-group-pill[data-htmxo-drop="after"] { box-shadow: 3px 0 0 var(--pico-contrast, CanvasText); }
    .htmxo-group-pills .htmxo-group-level { margin-inline-end: .35em; font-size: .85em; opacity: .8; }
    [data-htmxo-group] > td:first-child { white-space: nowrap; }
    [data-htmxo-group] > td select { width: auto; margin: 0; padding-block: .15em; }
    tr[aria-busy="true"] [data-htmxo-tree-toggle] { cursor: progress; opacity: .6; }
    [data-htmxo-row-label] > [data-htmxo-tree-label] { width: auto; margin: 0; padding: 0; border: 0; border-radius: 0; background: transparent; box-shadow: none; color: inherit; text-align: start; white-space: normal; font: inherit; }
    [data-htmxo-row-label] > [data-htmxo-tree-label]::before { content: "▸\\2060"; margin-right: .35em; }
    [data-htmxo-row-label] > [data-htmxo-tree-label][aria-expanded="true"]::before { content: "▾\\2060"; }
    [data-htmxo-row-label] > [data-htmxo-tree-label]:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: .2em; }
    [data-htmxo-row-label] > [data-htmxo-detail-toggle] { width: auto; margin: 0; padding: 0; border: 0; border-radius: 0; background: transparent; box-shadow: none; color: var(--pico-primary, LinkText); text-align: start; text-decoration: underline; white-space: normal; }
    [data-htmxo-hierarchy] [data-htmxo-row-label] > [data-htmxo-detail-toggle] { color: inherit; text-decoration: none; font: inherit; }
    [data-htmxo-hierarchy] tr:not([data-htmxo-tree-open]) [data-htmxo-row-label] > [data-htmxo-detail-toggle]::before { content: "▸\\2060"; margin-right: .35em; }
    [data-htmxo-hierarchy] tr:not([data-htmxo-tree-open]) [data-htmxo-row-label] > [data-htmxo-detail-toggle][aria-expanded="true"]::before { content: "▾\\2060"; }
    [data-htmxo-row-label] > [data-htmxo-detail-toggle]:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: .2em; }
    td > button[data-htmxo-disclosure] { width: auto; margin: 0 .4em 0 0; padding: 0 .2em; border: 0; border-radius: 0; background: transparent; box-shadow: none; color: var(--pico-muted-color, inherit); font: inherit; line-height: inherit; vertical-align: baseline; }
    td > button[data-htmxo-disclosure]:hover { color: var(--pico-primary, LinkText); }
    td > button[data-htmxo-disclosure]:focus-visible { outline: 2px solid var(--pico-primary, Highlight); outline-offset: .1em; }
    td:has(> [data-htmxo-row-label]) { text-wrap-mode: nowrap; }
    td > [data-htmxo-row-label]:not(:has(> [data-htmxo-label])) { text-wrap-mode: wrap; }
    td > [data-htmxo-row-label]:has(+ button)::after { content: "\\2060"; }
    """ * join(("[data-htmxo-hierarchy] > tbody > tr[aria-level=\"$level\"] > td:first-child { padding-inline-start: calc(var(--pico-spacing, 1rem) / 2 + $(level - 1) * var(--htmxo-tree-indent, 1.25rem)); }"
                  for level in 2:max(max_level[], _max_level)), "\n")
    table = h.div(h.style(Raw(rules)), table, (isempty(details) ? () : (_MDDetailsMarkdown(details),))...)
    # A hierarchy always carries the (possibly hidden) search scaffold: its
    # branch toggles and the search share one visibility pass.
    tools = Any[_toolbar...]
    expand_controls && push!(tools,
        h.button(texts.expand_all; type="button", class="secondary outline", aria_controls=body_id,
            onclick="htmxoTreeAll(this, true)"),
        h.button(texts.collapse_all; type="button", class="secondary outline", aria_controls=body_id,
            onclick="htmxoTreeAll(this, false)"))
    controls = isempty(tools) ? nothing : h.p(; class="htmxo-tree-controls")(tools...)
    scaffold = searchable || !isnothing(children) || !isnothing(controls)
    # The selection bar joins the search toolbar when there is one.
    bar = selecting && scaffold ? _selection_bar(rows; texts) : nothing
    searched = scaffold ?
        _searchable_table(table, rows; field=searchable, controls, query=search_query, texts, pending,
            sticky, selection=bar) : table
    _with_table_texts(selecting ?
        _selectable_table(searched, rows, selectable; form=select_form, texts, sticky, toolbar=!scaffold) :
        searched, texts)
end
