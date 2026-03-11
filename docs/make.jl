using Documenter, HTMXObjects

makedocs(
    sitename = "HTMXObjects.jl",
    modules  = [HTMXObjects],
    pages = [
        "Home"      => "index.md",
        "API"       => "api.md",
    ],
    format = Documenter.HTML(prettyurls = false),
)

deploydocs(
    repo = "github.com/nsiccha/HTMXObjects.jl",
)
