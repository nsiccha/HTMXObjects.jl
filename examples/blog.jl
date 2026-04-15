# Blog app demonstrating:
#   - derived properties for data and UI fragments
#   - indexed routes (@get post(id))
#   - mutable state with @cached and @persist
#   - @post for adding new posts via a form
#   - recording to a static site (non-GET actions greyed out)
#
# Run with:  julia --project examples/blog.jl
# Then open: http://localhost:8080
#
# To record the site for static replay:
#   julia --project examples/blog.jl record
# Then serve the recorded output with e.g.:
#   python -m http.server 8000 --directory site/

using HTMXObjects

@htmx struct BlogApp
    req = nothing
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

    @get index = __page__(h.p("Select a post from the list."))

    # Fragment: renders the post body into #content via hx-target.
    # The sidebar remains untouched — only #content is swapped.
    @get post(id) = let p = posts[findfirst(p -> p.id == id, posts)]
        fragment = h.article(
            h.header(h.h2(p.title)),
            h.p(p.body),
        )
        if is_htmx(req)
            fragment
        else
            __page__(fragment)
        end
    end

    # Add a new post via form submission. Returns updated sidebar.
    @post add(; title="", body="") = begin
        id = string(length(posts) + 1)
        posts = vcat(posts, [(; id, title, body)])
        @persist posts
        post_list
    end
end

record     = length(ARGS) >= 1 && ARGS[1] == "record"
record_dir = record && length(ARGS) >= 2 ? ARGS[2] : "site"
port       = record && length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 8080

function __init__()
    route!(BlogApp(); record_dir=record ? record_dir : nothing)
end

__init__()
serve(; port)
