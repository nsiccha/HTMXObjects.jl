# A synthetic inventory report with references into generated PDF and HTML views.
# Run: julia --project examples/pdf_panel.jl
# Open: http://localhost:8080
module PdfPanelDemo
using HTMXObjects

function tiny_pdf(pages::Vector{Vector{String}})
    esc(s) = replace(s, '\\' => "\\\\", '(' => "\\(", ')' => "\\)")
    n = length(pages)
    kids = [4 + 2(i - 1) for i in 1:n]
    objs = String["<< /Type /Catalog /Pages 2 0 R >>",
                  "<< /Type /Pages /Kids [$(join(("$k 0 R" for k in kids), " "))] /Count $n >>",
                  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
    for (i, lines) in enumerate(pages)
        content = "BT /F1 14 Tf 72 720 Td 20 TL " * join(("(" * esc(l) * ") Tj T*" for l in lines), " ") * " ET"
        push!(objs, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " *
                    "/Resources << /Font << /F1 3 0 R >> >> /Contents $(kids[i] + 1) 0 R >>")
        push!(objs, "<< /Length $(sizeof(content)) >>\nstream\n$content\nendstream")
    end
    io = IOBuffer()
    write(io, "%PDF-1.4\n")
    offsets = Int[]
    for (i, o) in enumerate(objs)
        push!(offsets, position(io))
        write(io, "$i 0 obj\n$o\nendobj\n")
    end
    xref = position(io)
    write(io, "xref\n0 $(length(objs) + 1)\n0000000000 65535 f \n")
    for off in offsets
        write(io, lpad(off, 10, '0'), " 00000 n \n")
    end
    write(io, "trailer\n<< /Size $(length(objs) + 1) /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
    take!(io)
end

# Written for this example; the PDF is generated in memory and never committed.
const PDF = tiny_pdf([
    ["Sample inventory", "Every sample has a unique identifier.",
     "Identifiers link the sample to its material and collection."],
    ["Sample records", "Every record names the material and storage shelf.",
     "New samples enter the catalog within one day."],
    ["Storage", "Samples remain in the collection for two weeks.",
     "This is a synthetic example, not a laboratory protocol."]])
const REQUIREMENTS = [
    (id="r1", page=1, quoted="Every sample has a unique identifier"),
    (id="r2", page=2, quoted="Every record names the material and storage shelf"),
    (id="r3", page=3, quoted="Samples remain in the collection for two weeks")]

cite(plan, text, page, quoted; kw...) = pdf_ref(text, plan; page, quoted, panel="plan", kw...)
cite_html(procedure, text, anchor, quoted) =
    pdf_ref(text, string(procedure, "#", anchor); kind=:html, quoted, panel="plan")

const RULE = """
using Dates
catalog_deadline(collected_at) = collected_at + Day(1)
"""

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content); pico_version="2", title="PDF panel")
    @get index() = report(__self__ / "plan", __self__ / "procedure")
    @get plan() = HTTP.Response(200, ["Content-Type" => "application/pdf"], PDF)
    @get procedure() = h.article(
        h.h2("Catalog entries"; id="handling"),
        h.p("Enter the identifier, material and storage shelf for each sample."),
        h.h2("The deadline as code"; id="deadline"),
        h.pre(h.code(RULE; class="language-julia")))
end

report(plan, procedure) = h.article(
    h.hgroup(h.h1("Sample inventory"), h.p(pdf_toggle("plan", "Show the notes"))),
    pdf_beside(
        h.div(
            h.p("Each sample has an identifier ",
                cite(plan, "(p. 1)", 1, REQUIREMENTS[1].quoted; key="r1"),
                ". Its record names the material and shelf ",
                cite(plan, "(p. 2)", 2, REQUIREMENTS[2].quoted; key="r2"), "."),
            h.p("The synthetic storage interval is two weeks ",
                cite(plan, "(p. 3)", 3, REQUIREMENTS[3].quoted; key="r3"), "."),
            h.p("The entry fields are listed in the HTML view ",
                cite_html(procedure, "(fields)", "handling", "identifier, material and storage shelf"),
                ". The catalog deadline appears as code ",
                cite_html(procedure, "(code)", "deadline", "collected_at + Day(1)"), "."),
            h.p(h.button(; type="button", onclick="document.getElementById('note').showModal()")("Open a note")),
            h.dialog(; id="note")(h.article(
                h.h3("Sample note"),
                h.p("A reference also works inside a dialog ",
                    cite(plan, "(p. 1)", 1, REQUIREMENTS[1].quoted), "."),
                h.footer(h.button(; type="button", onclick="this.closest('dialog').close()")("Close")))),
            h.h2("Conventions"),
            sortable_table(["Identifier", "Passage"],
                [h.tr(h.td(r.id), h.td(cite(plan, "page $(r.page)", r.page, r.quoted; key=r.id));
                      data_htmxo_link_key=r.id) for r in REQUIREMENTS]; link="plan")),
        pdf_panel(["Inventory notes" => plan, (title="Catalog entries", url=procedure, kind=:html)]; id="plan");
        placements=(:beside, :right, :bottom)))

function main(; port=8080)
    route!(App())
    serve(; port)
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    PdfPanelDemo.main()
end
