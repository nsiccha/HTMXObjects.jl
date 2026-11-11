module DocSupport

using HTMXObjects, Markdown, TOML, Documenter

const GROUPS = TOML.parsefile(joinpath(@__DIR__, "reference_groups.toml"))
const EXPORTS = Dict(Symbol(group) => Symbol.(data["names"]) for (group, data) in GROUPS)

function check_exports()
    listed = reduce(vcat, values(EXPORTS))
    length(listed) == length(unique(listed)) || error("An export has two reference homes")
    actual = Set(names(HTMXObjects))
    documented = Set(listed)
    actual == documented || error("Reference coverage changed: missing=$(setdiff(actual, documented)); retired=$(setdiff(documented, actual))")
end

belongs(value, group) = any(EXPORTS[group]) do name
    isdefined(HTMXObjects, name) && getfield(HTMXObjects, name) === value
end

function export_index(group)
    rows = ["| Export | Definition |", "| --- | --- |"]
    docs = Base.Docs.meta(HTMXObjects)
    for name in EXPORTS[group]
        binding = Base.Docs.Binding(HTMXObjects, name)
        label = "`$name`"
        if !isdefined(HTMXObjects, name)
            definition = "Unbound in this revision; do not call."
        elseif haskey(docs, binding) && group !== :objects
            signature = first(docs[binding].order)
            object = Documenter.Object(binding, signature)
            anchor = replace(string(object), r"[\[\]\(\)*]" => "")
            label = "[`$name`](#$(HTTP.escapeuri(anchor)))"
            definition = "HTMXObjects"
        else
            definition = "`$(binding.mod)`"
        end
        push!(rows, "| $label | $definition |")
    end
    Markdown.parse(join(rows, '\n'))
end

# The website is a task index, not a second copy of the full help-mode manual.
# Documenter still sees canonical docstrings and checks every exported binding.
# Keep each source's opening contract and render its signature as inline syntax;
# executable workflows belong to the @example pages. Full help stays in source.
function reference_summaries!()
    for (binding, multidoc) in Base.Docs.meta(HTMXObjects)
        (binding.var in names(HTMXObjects) || binding.var === :SchemaInherited) || continue
        for doc in values(multidoc.docs)
            original = Base.Docs.parsedoc(doc)
            original isa Markdown.MD || continue
            blocks = Any[]
            if !isempty(original.content) && first(original.content) isa Markdown.Code
                signature = first(original.content).code
                push!(blocks, Markdown.Paragraph(Any[Markdown.Code("", signature)]))
            end
            paragraph = findfirst(block -> block isa Markdown.Paragraph, original.content)
            if !isnothing(paragraph)
                push!(blocks, original.content[paragraph])
            end
            isempty(blocks) && error("No reference summary for $binding")
            doc.object = Markdown.MD(blocks, copy(original.meta))
        end
    end
end

function receipt()
    revision = readchomp(`git -C $(@__DIR__) rev-parse HEAD`)
    dirty = !isempty(readchomp(`git -C $(@__DIR__) status --porcelain --untracked-files=no`))
    Markdown.parse("""
    | Build input | Value |
    | --- | --- |
    | Source revision | `$revision` |
    | Tracked working-tree changes | `$dirty` |
    | Julia | `$VERSION` |
    | HTMXObjects | `$(Base.pkgversion(HTMXObjects))` |
    | DynamicObjects | `$(Base.pkgversion(DynamicObjects))` |
    """)
end

function lint(pages)
    first.(pages) == ["Start", "Guides", "Examples", "Reference"] ||
        error("Navigation must be Start, Guides, Examples, Reference")
    listed = String[last(page) for group in pages for page in last(group)]
    root = joinpath(@__DIR__, "src")
    actual = sort!([relpath(joinpath(dir, file), root) for (dir, _, files) in walkdir(root)
                    for file in files if endswith(file, ".md")])
    sort(listed) == actual || error("Every Markdown page needs exactly one navigation home")
    for path in listed
        text = read(joinpath(root, path), String)
        occursin(r"(?m)^```(?:julia|jldoctest|python|javascript|js)(?:\s|$)", text) &&
            error("Static runnable fence in $path")
        occursin(r"\b(seamless|robust|powerful|leverage|delve|crucial|comprehensive|unlock|simply)\b|it's worth noting"i, text) &&
            error("Banned prose in $path")
        prose = replace(text, r"(?ms)^```.*?^```\s*$" => "")
        words = length(split(prose))
        startswith(path, "guides/") && words >= 1500 && error("Guide too long: $path ($words words)")
        if startswith(path, "examples/")
            800 <= words <= 1500 || error("Example length: $path ($words words; expected 800–1500)")
            occursin("```@example", text) || error("No executed example: $path")
            occursin("<figure", text) || error("No generated figure: $path")
            occursin("<summary>Reproduce</summary>", text) || error("No Reproduce footer: $path")
        end
        @info "Docs lint" page=path prose_words=words
    end
    check_exports()
end

end
