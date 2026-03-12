# Blog app demonstrating:
#   - derived properties for data and UI fragments
#   - indexed routes (@get post[id])
#   - recording to a static site
#
# Run with:  julia examples/blog.jl
# Then open: http://localhost:8080
#
# To record the site for static replay:
#   julia examples/blog.jl record
# Then serve the recorded output with e.g.:
#   python -m http.server 8000 --directory site/

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using HTMXObjects

@htmx struct BlogApp
    posts = [
        (id="1", title="Getting Started",    body="Welcome to the blog!"),
        (id="2", title="HTMX is great",      body="Partial updates make pages feel instant."),
        (id="3", title="Julia + HTMX",       body="DynamicObjects makes server-side easy."),
    ]

    nav = h.nav(
        h.ul(h.li(h.strong("My Blog"))),
        h.ul(h.li(h.a(href="/")("Home"))),
    )

    post_list = h.ul([
        h.li(hx_link("/post/$(p.id)"; hx_target="#content", hx_push_url="true")(p.title))
        for p in posts
    ])

    @get index = htmx(
        h.main(class="container")(
            nav,
            h.aside()(post_list),
            h.div(id="content")(
                h.p("Select a post from the list."),
            ),
        )
    )

    # Fragment: renders the post body into #content via hx-target.
    # The sidebar remains untouched — only #content is swapped.
    @get post[id] = let p = posts[findfirst(p -> p.id == id, posts)]
        h.article(
            h.header(h.h2(p.title)),
            h.p(p.body),
        )
    end
end

record = length(ARGS) > 0 && ARGS[1] == "record"
app = BlogApp()
route!(app; record_dir=record ? "site" : nothing)
serve()
