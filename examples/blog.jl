# Blog app demonstrating:
#   - derived properties for data and UI fragments
#   - indexed routes (@get post(id))
#   - mutable state with @cached and @persist
#   - @post for adding new posts via a form
#   - recording to a static site (non-GET actions greyed out)

module Blog

using HTMXObjects

@htmx struct App
    cache_path = joinpath(@__DIR__, "cache")

    @cached posts = [
        (id="1", title="Getting Started",    body="Welcome to the blog!"),
        (id="2", title="HTMX is great",      body="Partial updates make pages feel instant."),
        (id="3", title="Julia + HTMX",       body="DynamicObjects makes server-side easy."),
    ]

    nav = h.nav(
        h.ul(h.li(h.strong("My Blog"))),
        h.ul(h.li(h.a(href="/")("Home"))),
    )

    post_list = h.div(id="sidebar")(
        h.ul([
            h.li(hx_link("/post/$(p.id)"; hx_target="#content", hx_push_url="true")(p.title))
            for p in posts
        ]),
        h.hr(),
        h.form(hx_post="/add", hx_target="#sidebar", hx_swap="outerHTML")(
            h.input(name="title", type="text", placeholder="Post title…", required="true"),
            h.textarea(name="body", placeholder="Write something…", rows="3", required="true")(""),
            h.button(type="submit")("Add Post"),
        ),
    )

    __page__(content) = htmx(
        h.main(class="container")(
            nav,
            h.div(class="grid")(
                h.aside()(post_list),
                h.div(id="content")(content),
            ),
        );
        pico_version="2",
    )

    @get index() = h.p("Select a post from the list.")

    @get post(id) = let p = posts[findfirst(p -> p.id == id, posts)]
        h.article(h.header(h.h2(p.title)), h.p(p.body))
    end

    # NOTE: writing back to a `@cached` property currently trips a
    # shadow-check in DynamicObjects; disabled until that pattern is settled.
    @post add(; title="", body="") = post_list
end

gallery_paths() = ["/", "/post/1", "/post/2", "/post/3"]

function main(; record=false, record_dir="site", port=8080, record_base="")
    record ? route!(App(); record_dir, record_base) : route!(App())
    serve(; port)
end

end # module Blog

if abspath(PROGRAM_FILE) == @__FILE__
    record      = length(ARGS) >= 1 && ARGS[1] == "record"
    record_dir  = record && length(ARGS) >= 2 ? ARGS[2] : "site"
    port        = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080
    record_base = record && length(ARGS) >= 4 ? ARGS[4] : ""
    Blog.main(; record, record_dir, port, record_base)
end
