# Tabs app demonstrating:
#   - tab navigation via @get tab[id]
#   - OOB swap: updating both the panel content and the active-tab indicator
#     in a single response (no full-page reload, nav stays in sync)
#   - hx_response with push_url to keep the browser URL in sync with the active tab
#
# Run with:  julia examples/tabs.jl
# Then open: http://localhost:8080

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
using HTMXObjects

const TABS = [
    (id="home",    label="Home",    body="Welcome! This is the home tab."),
    (id="about",   label="About",   body="HTMXObjects.jl makes server-side Julia web apps easy."),
    (id="contact", label="Contact", body="Reach us at hello@example.com."),
]

# Nav bar wrapped in an `id` so it can be targeted by the OOB swap.
# The active tab gets the `aria-current` attribute for styling.
function tab_nav(active_id)
    h.nav(id="tab-nav")(
        h.ul([
            let extra = t.id == active_id ? (aria_current="page",) : (;)
                h.li(hx_link("/tab/$(t.id)"; hx_target="#panel", extra...)(t.label))
            end
            for t in TABS
        ])
    )
end

# Panel wrapped in an `id` so HTMX can swap it in as the primary target.
tab_panel(t) = h.div(id="panel")(
    h.h2(t.label),
    h.p(t.body),
)

@htmx struct TabsApp
    @get index = htmx(;
        pico_version="2",
        extra_head=(h.style("nav a[aria-current] { font-weight: bold; }"),),
    )(
        h.main(class="container")(
            tab_nav("home"),
            tab_panel(TABS[1]),
        )
    )

    # Returns the updated panel as the primary swap target (#panel),
    # plus the updated nav as an OOB swap (replaces #tab-nav in-place)
    # so the active-tab highlight stays accurate without a full reload.
    @get tab[id] = let t = TABS[findfirst(t -> t.id == id, TABS)]
        hx_response(
            [tab_panel(t), tab_nav(id) => "tab-nav"];
            push_url="/tab/$id",
        )
    end
end

app = TabsApp()
route!(app)
serve()
