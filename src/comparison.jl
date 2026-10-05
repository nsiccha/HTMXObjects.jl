"""
    comparison_view(panes::Pair...; id, presentation=:tabs, active=1, selected=(1, 2))

Selectable side-by-side comparison of two or more views. Checkboxes select any
subset of two or more panes, displayed side by side with independent
scrolling. Labels and bodies are preserved in full.

`presentation` chooses how the comparison is shown:

- `:tabs` (default): one inline tabbed view with a near-fullscreen Compare
  dialog holding the checkboxes and columns. Tabs support Arrow keys, Home and
  End; native buttons support Enter/Space, and Escape closes the dialog and
  returns focus to Compare. `active` is the initially shown tab.
- `:inline`: the checkboxes and selected columns are shown directly in the
  page, with no tabs and no dialog. The comparison is limited to the viewport
  height (`--htmxo-comparison-height`, default `100dvh`), so each column
  scrolls independently. `active` selects a tab and is refused here.

Each pair is `label => body` or `label => "/fragment/url"`. URL panes load
independently on first display, coalesce in-flight requests, retain loaded
DOM, and allow retry after failure. Selected panes display (and load) when
selected; moving between views reuses the same pane DOM and edited inputs.
`active` and `selected` are 1-based pane indices; `id` must be unique on the page.

URL panes GET the supplied address; they do not add generated operation-form
shared-context submission. For changing `semantic_app` context, supply node
bodies containing each generated `entry.form` and `entry.result`, and preserve
the compiler's shared context controls. Showing a node pane does not submit
its form or execute its operation.

`htmx` includes [`comparison_js`](@ref) and [`comparison_styles`](@ref) once.
Hand-built page heads must include both. URLs are ordinary HTMXObjects fragment
routes and keep the application's normal operation/error policy.
"""
function comparison_view(panes::Pair...; id, presentation::Symbol=:tabs, active=nothing, selected=(1, 2))
    length(panes) >= 2 || throw(ArgumentError("comparison_view: supply at least two panes"))
    selection = Set(selected)
    length(selection) >= 2 && all(i -> i isa Integer && i in eachindex(panes), selection) ||
        throw(ArgumentError("comparison_view: selected must contain at least two distinct pane indices in range"))
    safe = _md_safe_key(id)
    isempty(safe) && throw(ArgumentError("comparison_view: id must be nonempty"))
    _comparison_view(Val(presentation), panes, id, safe, active, selection)
end

_comparison_view(::Val{P}, panes, id, safe, active, selection) where {P} = throw(ArgumentError(
    "comparison_view: unknown presentation :$P; use :tabs or :inline"))

function _comparison_view(::Val{:tabs}, panes, id, safe, active, selection)
    active = something(active, 1)
    active isa Integer && active in eachindex(panes) ||
        throw(ArgumentError("comparison_view: active pane is out of range"))
    tab_id(i) = "comparison-$safe-tab-$i"
    h.div(; id, class="htmxo-comparison", data_htmxo_active=string(active))(
        h.nav(; aria_label="Views")(
            h.div(; role="tablist", aria_label="Views")(
                (h.button(string(label); type="button", id=tab_id(i), role="tab",
                    data_htmxo_tab=string(i), aria_controls=_comparison_pane_id(safe, i),
                    aria_selected=string(i == active), tabindex=i == active ? "0" : "-1",
                    onclick="htmxoComparisonTab(this)")
                 for (i, (label, _)) in enumerate(panes))...),
            h.button("Compare"; type="button", data_htmxo_compare_open="",
                onclick="htmxoComparisonOpen(this)")),
        h.div(; data_htmxo_compare_home="")(
            (_comparison_pane(safe, i, label, body, i == active;
                role="tabpanel", aria_labelledby=tab_id(i))
             for (i, (label, body)) in enumerate(panes))...),
        h.dialog(; aria_labelledby="comparison-$safe-title")(
            h.article(
                h.header(h.h2("Compare views"; id="comparison-$safe-title"),
                    h.button("Close"; type="button", autofocus=true,
                        onclick="htmxoComparisonClose(this)")),
                _comparison_choices(panes, selection)...,
                h.div(; data_htmxo_compare_grid=""))))
end

function _comparison_view(::Val{:inline}, panes, id, safe, active, selection)
    # refused: `active` names the initially shown tab; inline has no tabs.
    isnothing(active) || throw(ArgumentError(
        "comparison_view: active selects a tab and applies only to presentation=:tabs"))
    heading_id(i) = "comparison-$safe-heading-$i"
    h.div(; id, class="htmxo-comparison", data_htmxo_presentation="inline")(
        _comparison_choices(panes, selection)...,
        # Unselected panes stay in place, hidden, so their DOM is never moved.
        h.div(; data_htmxo_compare_grid="")(
            (_comparison_pane(safe, i, label, body, i in selection;
                aria_labelledby=heading_id(i), heading_id=heading_id(i))
             for (i, (label, body)) in enumerate(panes))...))
end

_comparison_pane_id(safe, i) = "comparison-$safe-panel-$i"

_comparison_pane(safe, i, label, body, shown; role=nothing, aria_labelledby, heading_id=nothing) =
    h.section(; id=_comparison_pane_id(safe, i), role, tabindex="0",
        data_htmxo_pane=string(i), aria_labelledby, hidden=!shown)(
        h.h3(string(label); id=heading_id),
        _comparison_body(body, "$safe-$i", shown))

_comparison_choices(panes, selection) = (
    h.fieldset(
        h.legend("Select at least two views"),
        (h.label(h.input(; type="checkbox", value=string(i),
            data_htmxo_compare_choice="", checked=i in selection,
            onchange="htmxoComparisonChoice(this)"), string(label))
         for (i, (label, _)) in enumerate(panes))...),
    h.p(""; role="status", data_htmxo_compare_status=""))

_comparison_body(body, key, shown) = body
_comparison_body(url::AbstractString, key, shown) =
    _md_lazy_slot("comparison-$key", url, nothing; also_load=shown)

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
function htmxoComparisonPart(root, name) {
    return Array.from(root.querySelectorAll('[data-htmxo-compare-' + name + ']')).find(e => e.closest('.htmxo-comparison') === root);
}
function htmxoComparisonSelected(root) {
    return Array.from(root.querySelectorAll('[data-htmxo-compare-choice]:checked'))
        .filter(c => c.closest('.htmxo-comparison') === root).map(c => c.value);
}
function htmxoComparisonArrange(root) {
    // Tabs move panels between their home and the dialog grid; inline panels never move.
    const home = htmxoComparisonPart(root, 'home');
    const grid = htmxoComparisonPart(root, 'grid');
    const selected = htmxoComparisonSelected(root);
    htmxoComparisonPanels(root).sort((a,b) => Number(a.dataset.htmxoPane) - Number(b.dataset.htmxoPane)).forEach(panel => {
        const show = selected.includes(panel.dataset.htmxoPane);
        if (home) (show ? grid : home).appendChild(panel);
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
    const status = htmxoComparisonPart(root, 'status');
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

Scoped styles for both [`comparison_view`](@ref) presentations: inline tabs
with a near-fullscreen dialog, or inline columns limited to the viewport height
(`--htmxo-comparison-height`, default `100dvh`). Included by `htmx`. Selected
columns scroll independently and remain side by side, with horizontal
scrolling when their complete contents exceed the available width
(`--htmxo-comparison-pane-width`, default `20rem`, is each column's minimum).
"""
comparison_styles() = h.style(Raw(raw"""
.htmxo-comparison > nav, .htmxo-comparison [role=tablist] { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
.htmxo-comparison > nav button { width: auto; margin: 0; }
.htmxo-comparison [role=tab][aria-selected=true] { text-decoration: underline; }
.htmxo-comparison > [data-htmxo-compare-home] > section[hidden], .htmxo-comparison > [data-htmxo-compare-grid] > section[hidden] { display: none !important; }
.htmxo-comparison > dialog > article { width: 96vw; max-width: 96vw; height: 94vh; max-height: 94vh; display: flex; flex-direction: column; }
.htmxo-comparison > dialog > article > header { display: flex; flex-wrap: wrap; gap: 1rem; justify-content: space-between; align-items: center; }
.htmxo-comparison > dialog fieldset, .htmxo-comparison > fieldset { display: flex; flex-wrap: wrap; gap: .5rem 1rem; }
.htmxo-comparison > dialog fieldset label, .htmxo-comparison > fieldset label { width: auto; }
.htmxo-comparison[data-htmxo-presentation=inline] { display: flex; flex-direction: column; max-height: var(--htmxo-comparison-height, 100dvh); }
.htmxo-comparison > dialog [data-htmxo-compare-grid], .htmxo-comparison > [data-htmxo-compare-grid] { display: flex; flex: 1; min-height: 0; gap: 1rem; overflow: auto; }
.htmxo-comparison[data-htmxo-presentation=inline] > [data-htmxo-compare-grid] { flex: 1 1 auto; }
.htmxo-comparison > dialog [data-htmxo-compare-grid] > section, .htmxo-comparison > [data-htmxo-compare-grid] > section { flex: 1 0 var(--htmxo-comparison-pane-width, 20rem); min-width: var(--htmxo-comparison-pane-width, 20rem); overflow: auto; }
.htmxo-comparison section { overflow-wrap: anywhere; }
"""))
