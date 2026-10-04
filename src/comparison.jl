"""
    comparison_view(panes::Pair...; id, active=1, selected=(1, 2))

One inline tabbed view with a near-fullscreen Compare dialog. Checkboxes select
any subset of two or more panes, displayed side by side with independent
scrolling. Labels and bodies are preserved in full. Tabs support Arrow keys,
Home and End; native buttons support Enter/Space, and Escape closes the dialog
and returns focus to Compare.

Each pair is `label => body` or `label => "/fragment/url"`. URL panes load
independently on first activation, coalesce in-flight requests, retain loaded
DOM, and allow retry after failure. Opening Compare activates every selected
pane. Moving between inline and dialog views reuses the same pane DOM.
`active` and `selected` are 1-based pane indices; `id` must be unique on the page.

`htmx` includes [`comparison_js`](@ref) and [`comparison_styles`](@ref) once.
Hand-built page heads must include both. URLs are ordinary HTMXObjects fragment
routes and keep the application's normal operation/error policy.
"""
function comparison_view(panes::Pair...; id, active::Integer=1, selected=(1, 2))
    length(panes) >= 2 || throw(ArgumentError("comparison_view: supply at least two panes"))
    active in eachindex(panes) || throw(ArgumentError("comparison_view: active pane is out of range"))
    selection = Set(selected)
    length(selection) >= 2 && all(i -> i isa Integer && i in eachindex(panes), selection) ||
        throw(ArgumentError("comparison_view: selected must contain at least two distinct pane indices in range"))
    safe = _md_safe_key(id)
    isempty(safe) && throw(ArgumentError("comparison_view: id must be nonempty"))
    pane_id(i) = "comparison-$safe-panel-$i"
    tab_id(i) = "comparison-$safe-tab-$i"
    h.div(; id, class="htmxo-comparison", data_htmxo_active=string(active))(
        h.nav(; aria_label="Views")(
            h.div(; role="tablist", aria_label="Views")(
                (h.button(string(label); type="button", id=tab_id(i), role="tab",
                    data_htmxo_tab=string(i), aria_controls=pane_id(i),
                    aria_selected=string(i == active), tabindex=i == active ? "0" : "-1",
                    onclick="htmxoComparisonTab(this)")
                 for (i, (label, _)) in enumerate(panes))...),
            h.button("Compare"; type="button", data_htmxo_compare_open="",
                onclick="htmxoComparisonOpen(this)")),
        h.div(; data_htmxo_compare_home="")(
            (h.section(; id=pane_id(i), role="tabpanel", tabindex="0",
                data_htmxo_pane=string(i), aria_labelledby=tab_id(i), hidden=i != active)(
                h.h3(string(label)),
                _comparison_body(body, "$safe-$i", i == active))
             for (i, (label, body)) in enumerate(panes))...),
        h.dialog(; aria_labelledby="comparison-$safe-title")(
            h.article(
                h.header(h.h2("Compare views"; id="comparison-$safe-title"),
                    h.button("Close"; type="button", autofocus=true,
                        onclick="htmxoComparisonClose(this)")),
                h.fieldset(
                    h.legend("Select at least two views"),
                    (h.label(h.input(; type="checkbox", value=string(i),
                        data_htmxo_compare_choice="", checked=i in selection,
                        onchange="htmxoComparisonChoice(this)"), string(label))
                     for (i, (label, _)) in enumerate(panes))...),
                h.p(""; role="status", data_htmxo_compare_status=""),
                h.div(; data_htmxo_compare_grid=""))))
end

_comparison_body(body, key, active) = body
_comparison_body(url::AbstractString, key, active) =
    _md_lazy_slot("comparison-$key", url, nothing; also_load=active)

_comparison_runtime_js() = raw"""
function htmxoComparisonPanels(root) {
    return Array.from(root.querySelectorAll('[data-htmxo-pane]')).filter(p => p.closest('.htmxo-comparison') === root);
}
function htmxoComparisonLoad(panel) {
    htmxoLoadSlot(panel.querySelector(':scope > [data-loaded]'));
}
function htmxoComparisonTab(button) {
    const root = button.closest('.htmxo-comparison');
    root.dataset.htmxoActive = button.dataset.htmxoTab;
    root.querySelectorAll('[data-htmxo-tab]').forEach(tab => {
        if (tab.closest('.htmxo-comparison') !== root) return;
        const active = tab === button;
        tab.setAttribute('aria-selected', active); tab.tabIndex = active ? 0 : -1;
    });
    htmxoComparisonPanels(root).forEach(panel => {
        panel.hidden = panel.dataset.htmxoPane !== root.dataset.htmxoActive;
        if (!panel.hidden) htmxoComparisonLoad(panel);
    });
}
function htmxoComparisonSelected(root) {
    return Array.from(root.querySelector(':scope > dialog').querySelectorAll('[data-htmxo-compare-choice]:checked'))
        .filter(c => c.closest('.htmxo-comparison') === root).map(c => c.value);
}
function htmxoComparisonArrange(root) {
    const home = root.querySelector(':scope > [data-htmxo-compare-home]');
    const dialog = root.querySelector(':scope > dialog');
    const grid = dialog.querySelector('[data-htmxo-compare-grid]');
    const selected = htmxoComparisonSelected(root);
    htmxoComparisonPanels(root).sort((a,b) => Number(a.dataset.htmxoPane) - Number(b.dataset.htmxoPane)).forEach(panel => {
        const show = selected.includes(panel.dataset.htmxoPane);
        (show ? grid : home).appendChild(panel);
        panel.hidden = !show;
        if (show) htmxoComparisonLoad(panel);
    });
}
function htmxoComparisonOpen(button) {
    const root = button.closest('.htmxo-comparison');
    root.htmxoCompareReturnFocus = button;
    htmxoComparisonArrange(root);
    root.querySelector(':scope > dialog').showModal();
}
function htmxoComparisonChoice(input) {
    const root = input.closest('.htmxo-comparison');
    const status = root.querySelector(':scope > dialog [data-htmxo-compare-status]');
    if (htmxoComparisonSelected(root).length < 2) {
        input.checked = true; status.textContent = 'Select at least two views'; return;
    }
    status.textContent = '';
    htmxoComparisonArrange(root);
}
function htmxoComparisonRestore(root) {
    const home = root.querySelector(':scope > [data-htmxo-compare-home]');
    htmxoComparisonPanels(root).sort((a,b) => Number(a.dataset.htmxoPane) - Number(b.dataset.htmxoPane)).forEach(panel => {
        home.appendChild(panel);
        panel.hidden = panel.dataset.htmxoPane !== root.dataset.htmxoActive;
    });
    if (root.htmxoCompareReturnFocus) root.htmxoCompareReturnFocus.focus();
    root.htmxoCompareReturnFocus = null;
}
function htmxoComparisonClose(button) {
    const root = button.closest('.htmxo-comparison');
    root.querySelector(':scope > dialog').close();
    htmxoComparisonRestore(root);
}
if (!window.htmxoComparisonInstalled) {
    window.htmxoComparisonInstalled = true;
    document.addEventListener('close', function(event) {
        const dialog = event.target;
        if (dialog.tagName !== 'DIALOG' || dialog.open || !dialog.parentElement?.classList.contains('htmxo-comparison')) return;
        htmxoComparisonRestore(dialog.parentElement);
    }, true);
    document.addEventListener('keydown', function(event) {
        const tab = event.target.closest('[data-htmxo-tab]');
        if (!tab || !['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
        const tabs = Array.from(tab.parentElement.querySelectorAll('[data-htmxo-tab]'));
        let index = tabs.indexOf(tab);
        if (event.key === 'Home') index = 0;
        else if (event.key === 'End') index = tabs.length - 1;
        else index = (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
        event.preventDefault(); tabs[index].click(); tabs[index].focus();
    });
}
"""

"""
    comparison_js()

Shared runtime for [`comparison_view`](@ref), including the master/detail
single-flight lazy loader. Automatically included by `htmx`.
"""
comparison_js() = h.script(Raw(_md_runtime_js() * _comparison_runtime_js()))

"""
    comparison_styles()

Scoped inline-tab and near-fullscreen comparison-dialog styles. Included by
`htmx`. Selected columns scroll independently and remain side by side, with
horizontal scrolling when their complete contents exceed the viewport.
"""
comparison_styles() = h.style(Raw(raw"""
.htmxo-comparison > nav, .htmxo-comparison [role=tablist] { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
.htmxo-comparison > nav button { width: auto; margin: 0; }
.htmxo-comparison [role=tab][aria-selected=true] { text-decoration: underline; }
.htmxo-comparison > [data-htmxo-compare-home] > section[hidden] { display: none !important; }
.htmxo-comparison > dialog > article { width: 96vw; max-width: 96vw; height: 94vh; max-height: 94vh; display: flex; flex-direction: column; }
.htmxo-comparison > dialog > article > header { display: flex; flex-wrap: wrap; gap: 1rem; justify-content: space-between; align-items: center; }
.htmxo-comparison > dialog fieldset { display: flex; flex-wrap: wrap; gap: .5rem 1rem; }
.htmxo-comparison > dialog fieldset label { width: auto; }
.htmxo-comparison > dialog [data-htmxo-compare-grid] { display: flex; flex: 1; min-height: 0; gap: 1rem; overflow: auto; }
.htmxo-comparison > dialog [data-htmxo-compare-grid] > section { flex: 1 0 var(--htmxo-comparison-pane-width, 20rem); min-width: var(--htmxo-comparison-pane-width, 20rem); overflow: auto; }
.htmxo-comparison section { overflow-wrap: anywhere; }
"""))
