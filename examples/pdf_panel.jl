# A report that quotes a PDF, with the PDF beside it (`pdf_panel`):
#   - each reference (`pdf_ref`) is a chip, always lightly highlighted in its
#     colour; its passage is marked in the same colour on its page
#   - pointing at a reference, a requirement's row or a marked passage shows
#     its counterparts more strongly; nothing scrolls
#   - a click on a reference opens the panel at its passage; a click on a
#     passage goes to its reference
#   - the table's rows and the references share one hover-link group, so a
#     row lights the passage its requirement quotes
#
# Run with:  julia --project examples/pdf_panel.jl
# Then open: http://localhost:8080

module PdfPanelDemo

using HTMXObjects

const PDF = read(joinpath(@__DIR__, "pdf_panel.pdf"))

# The requirements the report answers, each quoting the plan.
const REQUIREMENTS = [
    (id="r1", page=2, quoted="extended criminal record certificate before the first day of work"),
    (id="r2", page=2, quoted="All staff take part in a training on child protection once a year"),
    (id="r3", page=3, quoted="reported to the youth office within one day")]

# A reference to the plan, opening the panel `plan`.
cite(plan, text, page, quoted; kw...) = pdf_ref(text, plan; page, quoted, panel="plan", kw...)

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2", title="PDF panel")
    @get index() = report(__self__ / "plan")
    @get plan() = HTTP.Response(200, ["Content-Type" => "application/pdf"], PDF)
end

report(plan) = h.article(
    h.hgroup(h.h1("Child protection: our answers"), h.p(pdf_toggle("plan", "Show the plan"))),
    pdf_beside(
        h.div(
            h.p("The plan applies to everyone working with children ",
                cite(plan, "(plan, p. 1)", 1, "Child protection is the task of every provider and of everyone"),
                ". New staff show a criminal record certificate before they start ",
                cite(plan, "(p. 2)", 2, "extended criminal record certificate before the first day of work"; key="r1"),
                ", and every member of staff is trained once a year ",
                cite(plan, "(p. 2)", 2, "All staff take part in a training on child protection once a year"; key="r2"), "."),
            h.p("A suspicion reaches the youth office within a day ",
                cite(plan, "(p. 3)", 3, "reported to the youth office within one day"; key="r3"),
                ", and the parents are told unless that puts the child at risk ",
                cite(plan, "(p. 3)", 3, "The lead informs the parents unless this would put the child at risk"), "."),
            h.h2("Requirements"),
            sortable_table(["Requirement", "Where the plan says so"],
                [h.tr(h.td(r.id), h.td(cite(plan, "page $(r.page)", r.page, r.quoted; key=r.id));
                      data_htmxo_link_key=r.id)
                 for r in REQUIREMENTS]; link="plan")),
        pdf_panel(["Child protection plan" => plan]; id="plan")))

function main(; port=8080)
    route!(App())
    serve(; port)
end

end # module PdfPanelDemo

if abspath(PROGRAM_FILE) == @__FILE__
    PdfPanelDemo.main()
end
