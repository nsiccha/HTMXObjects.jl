# Flashcards as a card deck (`card_deck`):
#   - a grid of cards under their groups' headings, or one card at a time
#     (the carousel), switched by the "Grid" / "Carousel" pills
#   - the search filters the cards by their words (any order, no case, no
#     accents) and says how many are left; the group pills filter by group;
#     the carousel pages over what is left
#   - the view and the current card are kept in the address: copy it to link
#     to a card (`?view=carousel&card=indices`)
#   - in the carousel the arrow keys go to the previous and next card
#
# Run with:  julia --project examples/card_deck.jl
# Then open: http://localhost:8080

module CardDeckDemo

using HTMXObjects

# A deck to learn Julia's basics, each card a question, its answer and where to read more.
const CARDS = [
    (id="literals", group="Types", q="What type does the literal 1.0 have?", a="`Float64`: a literal with a decimal point is a double-precision float.",
     src="Manual: Integers and Floating-Point Numbers"),
    (id="abstract", group="Types", q="Can you create an instance of an abstract type?", a="No. Abstract types only organise concrete types in the type graph.",
     src="Manual: Types"),
    (id="union", group="Types", q="What is Union{Nothing, Int} for?", a="A value that is either `nothing` or an `Int`, such as an optional count.",
     src="Manual: Type Unions"),
    (id="dispatch", group="Functions", q="What chooses which method of a function runs?", a="The types of all its arguments: multiple dispatch.",
     src="Manual: Methods"),
    (id="bang", group="Functions", q="What does an exclamation mark at the end of a function name say?", a="By convention, that the function changes one of its arguments, such as `push!`.",
     src="Style guide"),
    (id="kwargs", group="Functions", q="How do you give a keyword argument a default?", a="After the semicolon: `f(x; scale=1) = scale * x`.",
     src="Manual: Keyword Arguments"),
    (id="indices", group="Arrays", q="Where does Julia start counting an array's indices?", a="At 1, unless the array says otherwise (`axes(A)`).",
     src="Manual: Multi-dimensional Arrays"),
    (id="broadcast", group="Arrays", q="What does the dot in sin.(x) do?", a="It applies `sin` to every element of `x`, fused with other dotted calls.",
     src="Manual: Dot Syntax for Vectorizing Functions"),
    (id="columns", group="Arrays", q="Is a Matrix stored by rows or by columns?", a="By columns, so loop over the first index innermost.",
     src="Performance tips"),
]

card(c) = h.div(
    h.p(h.small(c.group)),
    h.h3(c.q),
    render_markdown(c.a),
    h.p(h.small("Read: ", c.src)))

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2", title="Card deck")
    @get index() = h.div(
        h.hgroup(h.h1("Julia basics"), h.p("$(length(CARDS)) cards to learn from")),
        card_deck([(c.id, c.group, card(c)) for c in CARDS]; id="julia"))
end

function main(; port=8080)
    route!(App())
    serve(; port)
end

end # module CardDeckDemo

if abspath(PROGRAM_FILE) == @__FILE__
    CardDeckDemo.main()
end
