_page_theme_heads(::Nothing, mount) = ()

function _page_theme_heads(name::Symbol, mount)
    name in (:juliabayes, :nsiccha) || throw(ArgumentError(
        "unknown page theme $(repr(name)); use :juliabayes, :nsiccha, CSS text, a style element or stylesheet link, or nothing"))
    (_runtime_head(name, mount),)
end

function _page_theme_heads(node::Node, mount)
    HTMX.tag(node) === :style && return (node,)
    rel = get(HTMX.attrs(node), :rel, "")
    HTMX.tag(node) === :link && "stylesheet" in split(lowercase(string(rel))) ||
        throw(ArgumentError("a page theme element must be a style element or a stylesheet link"))
    (node,)
end

function _page_theme_heads(css::AbstractString, mount)
    # Keep a literal HTML end tag in a CSS string or comment inside <style>.
    text = replace(css, r"<(?=/style[\t\n\f\r />])"i => "\\3c ")
    (h.style(Raw(text)),)
end

# The font and its licence travel with the stylesheet in both single-page
# snapshots and the content-versioned vendor asset. Source: Fontsource's
# @fontsource-variable/ibm-plex-sans 5.3.0, unmodified Latin weight subset.
const _JULIABAYES_CSS = let assets = joinpath(@__DIR__, "..", "assets")
    css = joinpath(assets, "themes", "juliabayes.css")
    font = joinpath(assets, "themes", "ibm-plex-sans-latin-wght-normal.woff2")
    licence = joinpath(assets, "licenses", "IBM-Plex-Sans-OFL.txt")
    foreach(Base.include_dependency, (css, font, licence))
    string("/*\n", read(licence, String), "\n*/\n",
        replace(read(css, String), basename(font) => "data:font/woff2;base64," * Base64.base64encode(read(font))))
end

_juliabayes_styles() = h.style(Raw(_JULIABAYES_CSS))

const _NSICCHA_CSS = let path = joinpath(@__DIR__, "..", "assets", "themes", "nsiccha.css")
    Base.include_dependency(path)
    read(path, String)
end
_nsiccha_styles() = h.style(Raw(_NSICCHA_CSS))
