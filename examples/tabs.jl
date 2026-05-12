# Tabs app demonstrating:
#   - tab navigation via @get tab(id)
#   - OOB swap: updating both the panel content and the active-tab indicator
#     in a single response (no full-page reload, nav stays in sync)
#   - hx_response with push_url to keep the browser URL in sync

module Tabs

using HTMXObjects

@htmx struct App
    tabs = [
        (id="home",    label="Home",    body="Welcome! This is the home tab."),
        (id="about",   label="About",   body="HTMXObjects.jl makes server-side Julia web apps easy."),
        (id="contact", label="Contact", body="Reach us at hello@example.com."),
    ]

    tab_nav(active_id) = h.nav(id="tab-nav")(
        h.ul([
            let extra = t.id == active_id ? (aria_current="page",) : (;)
                h.li(hx_link("/tab/$(t.id)"; hx_target="#panel", extra...)(t.label))
            end
            for t in tabs
        ])
    )

    tab_panel(t) = h.div(id="panel")(
        h.h2(t.label),
        h.p(t.body),
    )

    __page__(content) = htmx(;
        pico_version="2",
        extra_head=(h.style("nav a[aria-current] { font-weight: bold; }"),),
    )(h.main(class="container")(content))

    @get index() = h.div(tab_nav("home"), tab_panel(tabs[1]))

    @get tab(id) = let t = tabs[findfirst(t -> t.id == id, tabs)]
        hx_response(
            [tab_panel(t), tab_nav(id) => "tab-nav"];
            push_url="/tab/$id",
        )
    end
end

gallery_paths() = ["/", "/tab/home", "/tab/about", "/tab/contact"]

function main(; record=false, record_dir="site", port=8080, record_base="")
    record ? route!(App(); record_dir, record_base) : route!(App())
    serve(; port)
end

end # module Tabs

if abspath(PROGRAM_FILE) == @__FILE__
    record      = length(ARGS) >= 1 && ARGS[1] == "record"
    record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
    port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
    record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""
    Tabs.main(; record, record_dir, port, record_base)
end
