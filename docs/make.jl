using Documenter, DocumenterVitepress, HTMXObjects

makedocs(
    sitename = "HTMXObjects.jl",
    modules  = [HTMXObjects],
    format   = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/nsiccha/HTMXObjects.jl",
        devurl = "dev",
    ),
    pages = [
        "Home"     => "index.md",
        "Examples" => "examples.md",
        "API"      => "api.md",
    ],
    checkdocs = :none,
    warnonly = true,
)

# Copy recorded examples into the built output so they're served as static files.
# DocumenterVitepress puts the final site in build/<devurl>/ (e.g. build/1/).
let public_src = joinpath(@__DIR__, "public")
    # Find the actual output directory
    build_dir = joinpath(@__DIR__, "build")
    if isdir(public_src) && isdir(build_dir)
        for entry in readdir(build_dir)
            out = joinpath(build_dir, entry)
            isdir(out) || continue
            isfile(joinpath(out, "index.html")) || continue
            dst = joinpath(out, "examples")
            isdir(dst) && rm(dst; recursive=true)
            cp(joinpath(public_src, "examples"), dst)
            @info "Copied recorded examples to $dst"
        end
    end
end

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
