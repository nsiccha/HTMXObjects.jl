# The `htmx()` shell carries HTMXObjects' own CSS/JS runtime, plus the
# Treebars poll assets while that extension is loaded. Each block has a
# stable name and a producer returning ONE attribute-free `<style>`/`<script>`
# of `Raw` text, so the same bytes ship either inline (the default) or as the
# file `vendorfiles` serves at `<mount>/htmxo/<name>.<ext>`. The shell decides
# which blocks a page carries; this table only names them. Producers resolve
# at call time, so the file may name functions defined further down.
_runtime_blocks() = (
    preload_runtime = (:js, preload_runtime_js),
    theme = (:css, htmxo_theme),
    pico_bridge = (:css, pico_bridge),
    request_feedback_style = (:css, request_feedback_style),
    request_feedback_script = (:js, request_feedback_script),
    compose_box_styles = (:css, compose_box_styles),
    compose_box_script = (:js, compose_box_script),
    toast_styles = (:css, toast_styles),
    toast_script = (:js, toast_script),
    live_thread_styles = (:css, live_thread_styles),
    live_thread_script = (:js, live_thread_script),
    utility_styles = (:css, htmxo_utility_styles),
    tabset_styles = (:css, tabset_styles),
    tabset_script = (:js, tabset_script),
    comparison_styles = (:css, comparison_styles),
    editor_styles = (:css, editor_styles),
    comparison = (:js, comparison_js),
    stream_probe = (:js, stream_probe_script),
    redirect_history = (:js, redirect_history_script),
    modifier_click = (:js, modifier_click_script),
    live_region = (:js, live_region_script),
    treebars_styles = (:css, () -> _polling_page_asset(1)),
    treebars_script = (:js, () -> _polling_page_asset(2)),
    live_refresh = (:js, live_refresh_script),
    auto_terminal = (:js, auto_terminal_script),
    mutation_poll = (:js, mutation_poll_script),
    operation_stream = (:js, operation_stream_script),
    sent_ahead = (:js, sent_ahead_script),
    semantic_refresh = (:js, semantic_refresh_script),
    semantic_follow = (:js, semantic_follow_script),
    show_when = (:js, show_when_script),
    choice_list = (:js, choice_list_script),
    url_params = (:js, url_params_script),
    url_anchor = (:js, url_anchor_script),
    instance_scope = (:js, instance_scope_script),
    glossary = (:js, glossary_script),
    unit_styles = (:css, unit_styles),
    unit_script = (:js, unit_script),
    math_styles = (:css, math_styles),
    math_script = (:js, math_script),
    syntax_styles = (:css, syntax_styles),
    syntax_script = (:js, syntax_script),
    # The table runtime. `htmx(...; tables=true)` carries it together with
    # `sortable_table_styles`, `caption_style` and `download_table` below.
    table_runtime = (:js, _table_runtime_js),
    # Page helpers an app may place itself, usually in `extra_head`. The
    # shell leaves out a copy whose code it already carries and links the
    # rest (`_shell_extra_head`).
    sortable_table = (:js, sortable_table_js),
    sortable_table_styles = (:css, sortable_table_styles),
    caption_style = (:css, caption_style),
    master_detail = (:js, master_detail_js),
    download_table = (:js, download_table_js),
    gallery_styles = (:css, htmxo_gallery_styles),
    # Component assets: what `pdf_panel_assets()` and `card_deck_assets()`
    # return, for a page that mounts the component with `assets=false`.
    pdf_panel_styles = (:css, pdf_panel_styles),
    pdf_panel_script = (:js, pdf_panel_script),
    card_deck_styles = (:css, card_deck_styles),
    card_deck_script = (:js, card_deck_script),
)

# The blocks whose text exists in this process: the Treebars poll assets only
# while that extension is loaded.
_runtime_source_names() = isempty(_polling_page_assets()) ?
    filter(name -> !(name in (:treebars_styles, :treebars_script)), keys(_runtime_blocks())) :
    keys(_runtime_blocks())

_runtime_file(name::Symbol) = string(name, '.', first(getfield(_runtime_blocks(), name)))

_runtime_tag(::Val{:css}) = :style
_runtime_tag(::Val{:js}) = :script

# The block's text — exactly what the inline element holds. Any other shape
# would render differently inline than linked, so it is refused loudly.
function _build_runtime_asset(name::Symbol)
    ext, produce = getfield(_runtime_blocks(), name)
    node = produce()
    expected = _runtime_tag(Val(ext))
    node isa Node && HTMX.tag(node) === expected && isempty(HTMX.attrs(node)) &&
        all(child -> child isa Raw, HTMX.children(node)) || throw(ArgumentError(
            "page runtime block $(repr(name)) must be an attribute-free <$expected> of Raw text; got $(repr(MIME"text/html"(), node))"))
    text = join(String(child) for child in HTMX.children(node))
    _RuntimeAsset(ext, _runtime_file(name), text, _runtime_version(text))
end

# Content-addressed: any change to a block's text changes its URL.
_runtime_version(text::AbstractString) = string(hash(text); base=16)

# Text and metadata are immutable; Nodes are always built for their caller.
# One catalog serves inline pages, linked heads, vendor responses and exports.
struct _RuntimeAsset
    ext::Symbol
    file::String
    text::String
    version::String
end

struct _RuntimeCatalog
    names::Tuple{Vararg{Symbol}}
    assets::Dict{Symbol,_RuntimeAsset}
    texts::Dict{Tuple{Symbol,String},Symbol}
end

const _runtime_catalog_memo = _WorldMemo{_RuntimeCatalog}()

function _build_runtime_catalog()
    names = _runtime_source_names()
    assets = Dict(name => _build_runtime_asset(name) for name in names)
    # Preserve registry order when two producers have identical text: the
    # last registered name wins, as it did in the per-page reverse lookup.
    texts = Dict((_runtime_tag(Val(assets[name].ext)), assets[name].text) => name
                 for name in names)
    _RuntimeCatalog(names, assets, texts)
end

function _runtime_catalog()
    # The extension installs this provider in __init__, which need not move
    # the method world. Keying on it also notices assets loaded after a page
    # or vendor route was first constructed. World changes cover source edits.
    _world_memo!(_runtime_catalog_memo, _polling_page_assets_impl[]) do
        Base.invokelatest(_build_runtime_catalog)
    end
end

_available_runtime_names() = _runtime_catalog().names
function _runtime_asset(name::Symbol)
    get(_runtime_catalog().assets, name) do
        # Preserve the useful extension-absent error for a directly requested
        # Treebars asset; vendor routes may be installed before its extension.
        _build_runtime_asset(name)
    end
end
_runtime_text(name::Symbol) = _runtime_asset(name).text
_runtime_inline(::Val{:css}, text) = h.style(Raw(text))
_runtime_inline(::Val{:js}, text) = h.script(Raw(text))
function _runtime_block(name::Symbol)
    asset = _runtime_asset(name)
    _runtime_inline(Val(asset.ext), asset.text)
end

# One block as the shell carries it: the element itself (inline), or a link
# to its versioned file on the vendor mount. The marker lets a static export
# put the element back (`_static_walk`), so exported pages stay standalone.
_runtime_head(name::Symbol, ::Nothing) = _runtime_block(name)
function _runtime_head(name::Symbol, mount::AbstractString)
    asset = _runtime_asset(name)
    src = string(mount, "/htmxo/", asset.file, "?v=", asset.version)
    _runtime_link(Val(asset.ext), src, name)
end
_runtime_link(::Val{:css}, src, name) = h.link(rel="stylesheet", href=src, data_htmxo_runtime=string(name))
_runtime_link(::Val{:js}, src, name) = h.script(src=src, data_htmxo_runtime=string(name))

_runtime_heads(mount, names...) = map(name -> _runtime_head(name, mount), names)

# The named runtime block an element is exactly — an attribute-free
# `<style>`/`<script>` whose `Raw` text equals that block's — or `nothing`.
_runtime_block_name(node, texts) = nothing
function _runtime_block_name(node::Node, texts)
    HTMX.tag(node) in (:style, :script) && isempty(HTMX.attrs(node)) &&
        all(child -> child isa Raw, HTMX.children(node)) || return nothing
    get(texts, (HTMX.tag(node), join(String(child) for child in HTMX.children(node))), nothing)
end

# The shell blocks whose code a runtime block consists of: the block itself,
# or for a page helper that bundles shell code, those blocks.
_runtime_parts(name::Symbol) = _runtime_parts(Val(name))
_runtime_parts(::Val{name}) where {name} = (name,)
_runtime_parts(::Val{:sortable_table}) = (:table_runtime, :comparison)
_runtime_parts(::Val{:master_detail}) = (:comparison,)

# `extra_head` as the shell carries it. An element that is exactly a named
# runtime block — an app's own `sortable_table_js()`, say — is left out when
# the shell already carries its code (`carried`, the shell's block names);
# otherwise, linked, it becomes its link in the same place, like the shell's
# blocks. Anything else stays as given.
function _shell_extra_head(extra_head, mount, carried)
    texts = nothing
    filter(!isnothing, map(extra_head) do node
        node isa Node && HTMX.tag(node) in (:style, :script) &&
            isempty(HTMX.attrs(node)) && all(child -> child isa Raw, HTMX.children(node)) || return node
        # Built once, and only for a head that has a candidate element.
        isnothing(texts) && (texts = _runtime_catalog().texts)
        name = _runtime_block_name(node, texts)
        isnothing(name) ? node :
            all(in(carried), _runtime_parts(name)) ? nothing :
            isnothing(mount) ? node : _runtime_head(name, mount)
    end)
end
