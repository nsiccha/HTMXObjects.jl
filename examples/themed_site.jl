# Serve with: julia --project examples/themed_site.jl
# Export with: julia --project examples/themed_site.jl export site
module ThemedSite

using HTMXObjects

@htmx struct App
    __lang__ = "en"
    __title__ = "Bayesian field notes"
    __page__(content) = let base = __prefix__
        HTMXObjects.pico_page(content; theme=:juliabayes,
            brand="Bayesian field notes" => base * "/",
            nav=["Overview" => base * "/", "Model" => base * "/model"],
            assets=base * "/vendor", runtime=:linked)
    end

    @get index() = h.section(
        h.header(; class="htmxo-masthead")(h.h1("Comparing two treatments"),
            h.p("Posterior estimates for a simulated two-arm study.")),
        h.div(; class="grid")(
            h.article(h.header(h.h2("Treatment effect")),
                h.p(h.strong("−2.4 points"), " median change relative to control."),
                h.p("The central 90% credible interval runs from −4.1 to −0.7 points.")),
            h.article(h.header(h.h2("Probability of benefit")),
                h.p(h.strong("98%"), " of posterior draws favour treatment."),
                h.p("Benefit means a lower symptom score than under control."))),
        h.p(h.a("Model and assumptions"; href=__prefix__ * "/model")))

    @get model() = h.section(
        h.header(h.h1("Model and assumptions"),
            h.p("Illustrative analysis of a continuous symptom score.")),
        h.article(h.h2("Outcome model"),
            h.p("Each arm has its own mean and shares a residual standard deviation. ",
                "The reported effect is the treatment mean minus the control mean.")),
        h.p(h.a("Back to estimates"; href=__prefix__ * "/")))
end

function main(args=ARGS)
    route!(App(); operation_policy=:blocking)
    vendorfiles()
    isempty(args) && return serve(; port=8080)
    length(args) == 2 && first(args) == "export" ||
        throw(ArgumentError("expected no arguments to serve, or export DIRECTORY"))
    export_site(last(args); pages=["/"])
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    ThemedSite.main()
end
