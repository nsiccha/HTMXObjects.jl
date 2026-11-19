# Response views

Return one content value from a route and distinguish a complete page from an
HTMX fragment without duplicating the route body.

## Page and fragment

```@example views
using HTMXObjects
@htmx struct ViewRoutes
    __page__(content) = h.main(; id="page-shell")(content)
    @get index() = h.p(; id="answer")("Ready")
end
route!(ViewRoutes(); prefix="/views", operation_policy=:blocking);
page = String(dispatch(:GET, "/views/").body);
fragment = String(dispatch(:GET, "/views/";
    headers=["HX-Request" => "true"]).body);
comparison = (
    page_has_shell=occursin("page-shell", page),
    fragment_has_shell=occursin("page-shell", fragment),
    both_have_answer=all(x -> occursin("Ready", x), (page, fragment)),
)
@assert comparison == (page_has_shell=true, fragment_has_shell=false,
                       both_have_answer=true) # hide
foreach(println, pairs(comparison))
```

The response pipeline applies `__page__` to ordinary browser navigation and
returns route content for an HTMX request. A real page shell can use `htmx` to
include the document structure, browser runtime and styling. The small shell
above makes the wrapper distinction visible without loading browser assets.

## Style an app and its HTML snapshots

Choose the design once in the root `__page__`. The live app and
`export_site` render that same shell. Fragments swapped into a live page
inherit its styles. For the bundled JuliaBayes design, use
`HTMXObjects.pico_page(content; theme=:juliabayes)`. It includes IBM Plex
Sans, light and dark palettes and Julia-coloured article borders. The preset
styles the headings, navigation and articles your app already renders.
Add `class="htmxo-masthead"` to the introductory header for the site's
multicolour density curve.

For the style of [Nikolas Siccha's portfolio](https://nsiccha.github.io/),
set `theme=:nsiccha` in the same shell. It uses Pico's light and dark palettes,
ruled section headings and softly outlined article cards. Put sibling articles
in `h.div(; class="grid")` to use the portfolio's responsive card grid.

```@example views
lab_css = ":root { --htmxo-container-max-width: 80rem } main h1 { font-family: Georgia, serif }";
themed_shell(content) = HTMXObjects.pico_page(content; theme=:juliabayes,
    brand="Field notes" => "/", extra_head=(h.style(Raw(lab_css)),));
page_html = repr(MIME"text/html"(), themed_shell(h.article(h.h1("Estimates"))));
@assert occursin("IBM Plex Sans", page_html) && occursin(lab_css, page_html) # hide
nothing # hide
```

For a design of your own, read an app-owned CSS file once and pass its text
as `theme`. Here `app_dir` is the directory containing `lab.css`. Use
`@__DIR__` when the stylesheet is alongside your Julia source file.
You can style semantic elements (`nav`, `article`, `table`),
states such as `[aria-current="page"]`, HTMXObjects variables such as
`--htmxo-accent`, and Pico's `--pico-*` variables. Theme CSS comes after
the shell's defaults. `extra_head` comes last for app-specific overrides.

If the design has a light palette only, pass `html_attrs=(; data_theme="light")`.
This writes `data-theme="light"` on the document root, so Pico keeps its light
form controls even when the reader prefers dark mode. You can include other
root attributes in the same named tuple.

```@example views
app_dir = mktempdir(); # hide
write(joinpath(app_dir, "lab.css"), lab_css); # hide
const LAB_THEME = read(joinpath(app_dir, "lab.css"), String);

@htmx struct LabApp
    __page__(content) = HTMXObjects.pico_page(content; theme=LAB_THEME,
        html_attrs=(; data_theme="light"))
    @get index() = h.article(h.h1("Estimates"))
end
route!(LabApp(); prefix="/lab", operation_policy=:blocking);
response = dispatch(:GET, "/lab/");
lab_page = String(response.body);
@assert response.status == 200 && occursin(LAB_THEME, lab_page)
@assert occursin("data-theme=\"light\"", match(r"<html[^>]*>", lab_page).match)
```

If your design also changes the **page structure**, build the landmarks
yourself, for example `htmx(h.header(nav), h.main(content), h.footer(credits);
theme=LAB_THEME)`. This gives you the HTMXObjects runtime with your own
markup and CSS. Inline theme text travels with each HTML page. For a shared
stylesheet with relative font or image URLs, mount its directory once with
`staticfiles(joinpath(@__DIR__, "branding"), "branding")`. The page wrapper
can then pass `theme=h.link(rel="stylesheet", href=__prefix__ * "/branding/lab.css")`.
`export_site` copies the linked local CSS and follows its local `url(...)`
references. Use `assets=:vendor, runtime=:linked` and mount `vendorfiles()`
to keep the built-in assets, including the JuliaBayes preset, local and
shared across pages.

The [themed site example](https://github.com/nsiccha/HTMXObjects.jl/blob/devibe/examples/themed_site.jl)
serves a two-page app or writes the same pages to an empty directory:

```sh
julia --project examples/themed_site.jl
julia --project examples/themed_site.jl export site
```

## Tables and captions

```@example views
rows = [(sample="S-A", material="plasma"),
        (sample="S-B", material="serum")];
caption = CaptionSpec(title="Stored samples",
    short="Each identifier is paired with its material.");
table = with_caption(caption,
    render_table(rows; sortable=false, download=false));
Base.HTML(repr(MIME"text/html"(), table))
```

`CaptionSpec` precedes the content in `with_caption`. A caption's `short` text
states what the reader should see. Keep essential results visible; reserve its
optional longer disclosure for supplementary explanation.

Tables accept Tables.jl-compatible inputs. Use `ColumnSpec` for column-specific
labels and formatting, and `IntervalEstimate` when a cell represents an interval
rather than a preformatted string. The [table reference](../reference/tables.md)
defines sorting keys and the distinction between display and numeric values.

## Representations

```@example views
markdown = dispatch(:GET, "/views/";
    headers=["Accept" => "text/markdown"]);
@assert markdown.status == 200 # hide
println(String(markdown.body))
```

A Markdown request asks for the route value's Markdown view. Semantic content
types such as `SemanticTable`, `SemanticCode` and `SemanticSection` express
content that has several representations. Prefer those values when HTML and
exported documents must preserve the same meaning. `html_only` and
`markdown_only` deliberately restrict content to one representation.

`Raw` marks trusted markup; ordinary text nodes escape their contents. Avoid
using `Raw` to bypass escaping for user-supplied strings. Public static exports
also enforce the audience contract of `private` content; see the
[files reference](../reference/files.md) before exporting application data.

The [sample browser](../examples/sample-browser.md) renders its actual response
as a figure and checks that the visible rows match the requested filter.
