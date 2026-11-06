using TestItemRunner

@testitem "Julia documentation references are explicit, shared projections without mutation" tags=[:unit] begin
    using HTMXObjects, Markdown

    doc = Markdown.parse(raw"""
    # Documentation

    See [`reduce`](@ref), [**named label**](@ref target),
    [a heading](@ref "A heading"), [a binding](@ref `Base.sum`),
    and [ordinary](https://example.com/manual).

    > Nested [*unknown*](@ref).

    - A [known item](@ref target).

    | Column |
    | ------ |
    | [`missing`](@ref) |

    !!! note "References"
        See [`reduce`](@ref).

    Literal `[literal](@ref)` and code:

    ```jldoctest named; output = false
    julia> sum([1, 2])
    3
    # [literal](@ref)
    ```
    """)
    before = string(doc)
    references = Dict("reduce" => "/reduce", "target" => "/target",
                      "A heading" => "https://example.com/heading", "Base.sum" => "/sum")
    prose = SemanticProse(doc; references)
    html = repr("text/html", prose)
    source = repr("text/markdown", prose)
    @test string(doc) == before
    @test repr("text/plain", prose) == source
    @test occursin("[`reduce`](/reduce)", source)
    @test occursin("[**named label**](/target)", source)
    @test occursin("[a heading](https://example.com/heading)", source)
    @test occursin("[a binding](/sum)", source)
    @test occursin("[ordinary](https://example.com/manual)", source)
    @test occursin("<em>unknown</em>", html)
    @test occursin("<code>missing</code>", html)
    @test !occursin("href=\"@ref", html)
    @test occursin("<code>[literal](@ref)</code>", html)
    @test occursin("# [literal](@ref)", html)
    @test occursin("```julia\n", source)
    @test occursin("julia&gt; sum([1, 2])\n3\n# [literal](@ref)", html)
    @test occursin("class=\"language-julia\"", html)
    @test !occursin("language-jldoctest", html)
    @test !SemanticProse(doc; math=false).math

    # Real Base docs have multiple merged Markdown.MD blocks and doctests.
    sumdoc = @doc(sum)
    original = string(sumdoc)
    sumprose = SemanticProse(sumdoc)
    @test string(sumdoc) == original
    @test !occursin("href=\"@ref", repr("text/html", sumprose))
    @test !occursin("language-jldoctest", repr("text/html", sumprose))
    @test occursin("`reduce`", repr("text/markdown", sumprose))

    # Authored strings retain their source contract, including literal @ref.
    authored = SemanticProse(before)
    @test repr("text/markdown", authored) == before
    @test occursin("href=\"@ref\"", repr("text/html", authored))
    @test repr("text/markdown", SemanticProse("[x](@reference)")) == "[x](@reference)"
    @test occursin("href=\"@reference\"", repr("text/html", SemanticProse(Markdown.parse("[x](@reference)"))))

    for bad in ("", "@ref", "@ref other", 42)
        @test_throws ArgumentError SemanticProse(Markdown.parse("[x](@ref)"); references=Dict("x" => bad))
    end
end

@testitem "@doc gives a binding's whole documentation in a process without a REPL session" tags=[:unit] begin
    # On Julia 1.11 or later, `@doc` needs REPL loaded for this. A fresh process,
    # since anything that ran in this one (`using Pkg`) may have loaded it already.
    code = """
    using HTMXObjects, Markdown
    print(typeof(@doc(sum)), " ", occursin("`reduce`", repr("text/markdown", SemanticProse(@doc(sum)))))
    """
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    @test read(cmd, String) == "Markdown.MD true"
end

@testitem "A stored Julia docstring renders alone, and is not written to" tags=[:unit] begin
    using HTMXObjects, Markdown
    references = Dict("reduce" => "/reduce")
    data() = Dict{Symbol,Any}(:module => @__MODULE__, :path => "doc.jl", :linenumber => 1)

    unparsed = Base.Docs.docstr("""
        Uses [`reduce`](@ref) and [`unknown`](@ref).

        ```jldoctest named
        julia> 1 + 1
        2
        ```
        """, data())
    prose = SemanticProse(unparsed; references, math=false)
    source = repr("text/markdown", prose)
    html = repr("text/html", prose)
    @test unparsed.object === nothing
    @test !prose.math
    @test occursin("[`reduce`](/reduce)", source)
    @test !occursin("@ref", source)
    @test occursin("<code>unknown</code>", html)
    @test occursin("```julia\njulia> 1 + 1\n2\n```", source)
    @test occursin("class=\"language-julia\"", html)

    parsed = Base.Docs.docstr(md"Parsed already, with [`reduce`](@ref).", data())
    @test occursin("[`reduce`](/reduce)", repr("text/markdown", SemanticProse(parsed; references)))
    @test parsed.object isa Markdown.MD

    # A real binding: each stored docstring is its own prose, and `@doc` holds them all.
    stored = Base.Docs.meta(Base)[Base.Docs.Binding(Base, :sum)]
    each = [repr("text/markdown", SemanticProse(stored.docs[sig])) for sig in stored.order]
    @test length(each) > 1
    @test allunique(each)
    whole = repr("text/markdown", SemanticProse(@doc(sum)))
    @test all(text -> occursin(first(split(text, '\n')), whole), each)
end

@testitem "doctests use Julia highlighting without changing authored source or code" tags=[:unit] begin
    using HTMXObjects
    for info in ("jldoctest", "jldoctest named", "jldoctest; output = false", "JLDOCtest named; filter = f")
        text = "```$info\njulia> 1 + 1\n2\n```"
        prose = SemanticProse(text)
        @test repr("text/markdown", prose) == text
        @test occursin("class=\"language-julia\"", repr("text/html", prose))
    end
    code = SemanticCode(:jldoctest, "julia> 1 + 1\n2")
    @test occursin("class=\"language-julia\"", repr("text/html", code))
    @test occursin("```jldoctest", repr("text/markdown", code))
    @test occursin("language-jldoctest-extra", repr("text/html", SemanticProse("```jldoctest-extra\nx\n```")))
end

@testmodule DocumentationSiteFixture begin
    using HTMXObjects, Markdown
    export DocumentationSiteApp
    @htmx struct DocumentationSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked)
        @get documentation() = SemanticSection("Julia documentation",
            SemanticProse(@doc(sum); references=Dict("reduce" => "/documentation_target")))
        @get documentation_target() = h.p("Reference destination")
    end
end

@testitem "Julia documentation exports without unresolved routes" setup=[DocumentationSiteFixture] tags=[:unit] begin
    using HTMXObjects
    route!(DocumentationSiteApp())
    vendorfiles()
    mktempdir() do dir
        export_site(dir; pages=["/documentation"], parallel=false)
        html = read(joinpath(dir, "documentation.html"), String)
        @test !occursin("href=\"@ref", html)
        @test occursin("href=\"documentation_target.html\"", html)
        @test isfile(joinpath(dir, "documentation_target.html"))
        @test occursin("language-julia", html)
        @test !occursin("language-jldoctest", html)
        @test isfile(joinpath(dir, "vendor/prism/components/prism-julia.min.js"))
    end
end
