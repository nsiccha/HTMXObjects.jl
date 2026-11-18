# The reference pages show the opening contract and, when present, its signature.
# The full docstring remains available in Julia help.
const BANNED_PROSE = r"\b(seamless|robust|powerful|leverage|delve|crucial|comprehensive|unlock|simply)\b|it's worth noting"i

reference_blocks(md::Markdown.MD) = reduce(vcat,
    [block isa Markdown.MD ? reference_blocks(block) : Any[block] for block in md.content]; init=Any[])

function reference_summary(binding, original::Markdown.MD)
    content = reference_blocks(original)
    paragraph = findfirst(block -> block isa Markdown.Paragraph, content)
    isnothing(paragraph) && error("No reference summary for $binding")
    summary = content[paragraph]
    prose = sprint(show, MIME"text/plain"(), Markdown.MD(Any[summary]))
    occursin(BANNED_PROSE, prose) && error("Banned prose in reference summary for $binding")
    endswith(strip(prose), ":") && error("Unfinished reference summary for $binding")

    blocks = Any[]
    if first(content) isa Markdown.Code
        push!(blocks, Markdown.Paragraph(Any[Markdown.Code("", first(content).code)]))
    end
    push!(blocks, summary)
    Markdown.MD(blocks, copy(original.meta))
end

function reference_summaries()
    summaries = IdDict{Base.Docs.DocStr,Markdown.MD}()
    exported = names(HTMXObjects)
    for (binding, multidoc) in Base.Docs.meta(HTMXObjects)
        (binding.var in exported || binding.var === :SchemaInherited) || continue
        for doc in values(multidoc.docs)
            haskey(summaries, doc) && continue
            # parsedoc caches its result on the DocStr. Keep the shared help entry intact.
            original = Base.Docs.parsedoc(Base.Docs.DocStr(doc.text, doc.object, doc.data))
            original isa Markdown.MD || continue
            summaries[doc] = reference_summary(binding, original)
        end
    end
    summaries
end
