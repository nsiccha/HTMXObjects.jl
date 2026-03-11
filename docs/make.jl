using Documenter, DocumenterVitepress, HTMXObjects

makedocs(
    sitename = "HTMXObjects.jl",
    modules  = [HTMXObjects],
    format   = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/nsiccha/HTMXObjects.jl",
        devurl = "dev",
    ),
    pages = [
        "Home" => "index.md",
        "API"  => "api.md",
    ],
    checkdocs = :none,
    warnonly = true,
)

# Root redirect for when no stable version exists
let redirect = joinpath(@__DIR__, "build", "index.html")
    isfile(redirect) || write(redirect, """
    <!DOCTYPE html>
    <html><head>
    <meta http-equiv="refresh" content="0; url=dev/">
    </head><body>Redirecting to <a href="dev/">dev</a>...</body></html>
    """)
end

DocumenterVitepress.deploydocs(
    repo = "github.com/nsiccha/HTMXObjects.jl",
    devbranch = "main",
    push_preview = true,
)
