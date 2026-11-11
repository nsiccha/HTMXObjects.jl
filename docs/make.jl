using Documenter, DocumenterVitepress, HTMXObjects
include("support.jl")

pages = [
    "Start" => ["HTMXObjects.jl" => "index.md"],
    "Guides" => [
        "Objects and routes" => "guides/objects.md",
        "Forms" => "guides/forms.md",
        "Response views" => "guides/views.md",
        "Operations" => "guides/operations.md",
        "Service slices" => "guides/service-slices.md",
        "Testing" => "guides/testing.md",
    ],
    "Examples" => ["Sample browser" => "examples/sample-browser.md"],
    "Reference" => [
        "Routes and requests" => "reference/routes.md",
        "Response values" => "reference/responses.md",
        "Forms and URLs" => "reference/forms.md",
        "Tables and captions" => "reference/tables.md",
        "Layout and navigation" => "reference/layout.md",
        "Runtime and operations" => "reference/runtime.md",
        "Files and exports" => "reference/files.md",
        "Testing" => "reference/testing.md",
        "Re-exported interfaces" => "reference/objects.md",
    ],
]
DocSupport.lint(pages)
DocSupport.reference_summaries!()

makedocs(
    sitename = "HTMXObjects.jl",
    modules = [HTMXObjects],
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/nsiccha/HTMXObjects.jl",
        devurl = "dev",
        devbranch = "devibe",
    ),
    pages = pages,
    checkdocs = :exports,
    warnonly = false,
)

write(joinpath(@__DIR__, "build", "index.html"), """
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=dev/"><title>HTMXObjects.jl</title>
</head><body><a href="dev/">HTMXObjects documentation</a></body></html>
""")

DocumenterVitepress.deploydocs(
    repo = "github.com/nsiccha/HTMXObjects.jl",
    devbranch = "devibe",
    push_preview = true,
)
