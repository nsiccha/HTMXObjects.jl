# A report that quotes a PDF and an HTML document, with them beside it
# (`pdf_panel`):
#   - each reference (`pdf_ref`) is a chip, always lightly highlighted in its
#     colour; its passage is marked in the same colour on its page of the PDF,
#     or over its words in the HTML document (the procedure, a route of this
#     app that answers htmx with a fragment; its code highlighted)
#   - pointing at a reference, a requirement's row or a marked passage shows
#     its counterparts more strongly; nothing scrolls
#   - a click on a reference opens the panel at its passage; a click on a
#     passage goes to its reference
#   - the table's rows and the references share one hover-link group, so a
#     row lights the passage its requirement quotes
#   - the panel's pills switch between the plan and the procedure
#   - the panel opens beside the report; the switch in its bar floats it over
#     the page instead, on the right or below, and its inner edge resizes it
#     (both kept for the next visit); closed, it leaves a tab on its edge
#   - a reference inside the note (a modal dialog) opens the panel above the
#     dialog; closing the note leaves the panel open beside the report
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
# A reference to a place (`#anchor`) of the procedure, an HTML document.
cite_html(procedure, text, anchor, quoted) =
    pdf_ref(text, string(procedure, "#", anchor); kind=:html, quoted, panel="plan")

const RULE = """
function deadline(reported_at)
    reported_at + Day(1)   # the youth office hears of it within one day
end"""

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2", title="PDF panel")
    @get index() = report(__self__ / "plan", __self__ / "procedure")
    @get plan() = HTTP.Response(200, ["Content-Type" => "application/pdf"], PDF)
    # The procedure: under htmx (the panel) its fragment, else a page of its own.
    @get procedure() = h.article(
        h.h2("How a suspicion is handled"; id="handling"),
        h.p("Whoever notices something tells the lead. The lead checks every report on the same day ",
            "and decides on the next steps together with a second specialist."),
        h.h2("The deadline as code"; id="deadline"),
        h.pre(h.code(RULE; class="language-julia")))
end

report(plan, procedure) = h.article(
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
            h.p("Two people decide what happens next ",
                cite_html(procedure, "(procedure)", "handling", "decides on the next steps together with a second specialist"),
                ", and the deadline is computed, not guessed ",
                cite_html(procedure, "(code)", "deadline", "reported_at + Day(1)"), "."),
            h.p(h.button(; type="button", class="secondary", onclick="document.getElementById('note').showModal()")(
                "Read the note on reporting")),
            h.dialog(; id="note")(h.article(
                h.h3("Reporting"),
                h.p("Whoever suspects that a child is at risk reports it, and the report reaches the youth office within a day ",
                    cite(plan, "(p. 3)", 3, "reported to the youth office within one day"), "."),
                h.footer(h.button(; type="button", onclick="this.closest('dialog').close()")("Close")))),
            h.h2("Requirements"),
            sortable_table(["Requirement", "Where the plan says so"],
                [h.tr(h.td(r.id), h.td(cite(plan, "page $(r.page)", r.page, r.quoted; key=r.id));
                      data_htmxo_link_key=r.id)
                 for r in REQUIREMENTS]; link="plan")),
        pdf_panel(["Child protection plan" => plan, (title="Our procedure", url=procedure, kind=:html)]; id="plan");
        placements=(:beside, :right, :bottom)))

function main(; port=8080)
    route!(App())
    serve(; port)
end

end # module PdfPanelDemo

if abspath(PROGRAM_FILE) == @__FILE__
    PdfPanelDemo.main()
end
