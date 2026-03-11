# Blog app demonstrating:
#   - indexed routes (@get post[id])
#   - multi-element OOB swap (updating a sidebar while showing post content)
#   - recording to a static site
#
# Run with:  julia examples/blog.jl
# Then open: http://localhost:8080
#
# To record the site for static replay:
#   julia examples/blog.jl record
# Then serve the recorded output with e.g.:
#   python -m http.server 8000 --directory site/

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
using HTMXObjects

const POSTS = [
    (id="1", title="Getting Started",    body="Welcome to the blog!"),
    (id="2", title="HTMX is great",      body="Partial updates make pages feel instant."),
    (id="3", title="Julia + HTMX",       body="DynamicObjects makes server-side easy."),
]

nav() = h.nav(
    h.ul(h.li(h.strong("My Blog"))),
    h.ul(h.li(h.a(href="/")("Home"))),
)

post_list() = h.ul([
    h.li(hx_link("/post/$(p.id)"; hx_target="#content", hx_push_url="true")(p.title))
    for p in POSTS
])

post_view(p) = h.article(
    h.header(h.h2(p.title)),
    h.p(p.body),
)

@htmx struct BlogApp
    @get index = htmx(
        h.main(class="container")(
            nav(),
            h.aside()(post_list()),
            h.div(id="content")(
                h.p("Select a post from the list."),
            ),
        )
    )

    # Fragment: renders the post body into #content via hx-target.
    # The sidebar remains untouched — only #content is swapped.
    @get post[id] = post_view(POSTS[findfirst(p -> p.id == id, POSTS)])
end

record = length(ARGS) > 0 && ARGS[1] == "record"
app = BlogApp()
route!(app; record_dir=record ? "site" : nothing)
serve()
