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
