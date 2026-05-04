@dynamicstruct struct DemoData end

@htmx struct DemoRoutes
    @get index = h.div(
        h.h1("Request Feedback Demo"),
        h.section(
            h.h2("Slow load (3s)"),
            h.button(hx_get=__prefix__ * "/slow_load", hx_target="#slow-result", hx_swap="outerHTML")("Load something slow"),
            h.div(id="slow-result")(),
        ),
        h.section(
            h.h2("Instant success"),
            h.button(hx_get=__prefix__ * "/instant_ok", hx_target="#instant-result", hx_swap="innerHTML")("Instant OK"),
            h.div(id="instant-result")(),
        ),
        h.section(
            h.h2("Server error"),
            h.button(hx_get=__prefix__ * "/will_fail", hx_target="#error-result", hx_swap="innerHTML")("Trigger error"),
            h.div(id="error-result")(),
        ),
    )

    @get slow_load = begin
        sleep(3)
        h.div(id="slow-result")(h.p("Loaded after 3 seconds!"))
    end

    @get instant_ok = h.p("Done instantly!")

    @get will_fail = error("Intentional error for demo")
end
