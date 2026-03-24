using TestModules
using Random, HTMXObjects, HTTP, Tables

# --- Struct definitions at module scope ---

@htmx struct TestApp
    title = "Test"
    @get index = h.h1(title)
    @get item[id] = h.p("Item: $id")
end

@htmx struct IndexApp
    @get index = h.h1("home")
end

@htmx struct AllDefaultsApp
    @get viz[pn=""] = h.p("Viz: $(isempty(pn) ? "all" : pn)")
end

@htmx struct PostApp
    @post submit(; name="") = h.p("Hello $name")
end

@htmx struct TypedApp
    @get typed[n::Int] = h.p("N=$n")
end

@htmx struct NothingDefaultApp
    req = nothing
    @get filtered(; filter=nothing) = h.p("filter=$(repr(filter))")
end

@htmx struct RecordApp
    @get index = h.h1("Home")
    @get post[id] = h.p("Post $id")
end

# --- Tests ---

@testset "auto - HTML rendering" begin
    result = auto(h.div("hello"); wrap=identity)
    @test contains(result, "<div>")
    @test contains(result, "hello")
    @test auto("<p>test</p>"; wrap=identity) == "<p>test</p>"
    result = auto([h.p("a"), h.p("b")]; wrap=identity)
    @test contains(result, "<p>a</p>")
    @test contains(result, "<p>b</p>")
    result = auto(h.span("new") => "my-id"; wrap=identity)
    @test contains(result, "id=\"my-id\"")
    @test contains(result, "hx-swap-oob")
    @test contains(result, "new")
end

@testset "to_response" begin
    resp = to_response(h.div("hello"))
    @test resp.status == 200
    @test contains(String(resp.body), "<div>")
    @test any(p.first == "Content-Type" && contains(p.second, "text/html")
              for p in resp.headers)
    resp = to_response("<p>test</p>")
    @test resp.status == 200
    @test String(resp.body) == "<p>test</p>"
    resp = to_response([h.p("a"), h.p("b")])
    @test contains(String(resp.body), "<p>a</p>")
    orig = HTTP.Response(201; body="custom")
    @test to_response(orig) === orig
end

@testset "pathparams" begin
    @test pathparams(HTTP.Request("GET", "/post/42"), "/post/{id}") ==
          Dict("id" => "42")
    @test pathparams(HTTP.Request("GET", "/user/alice/post/1"), "/user/{name}/post/{id}") ==
          Dict("name" => "alice", "id" => "1")
    @test pathparams(HTTP.Request("GET", "/about?foo=bar"), "/about") ==
          Dict{String,String}()
    @test pathparams(HTTP.Request("GET", "/item/7?page=2"), "/item/{id}") ==
          Dict("id" => "7")
end

@testset "HTMX request header inspection" begin
    htmx_req = HTTP.Request("GET", "/",
        ["HX-Request" => "true", "HX-Target" => "#result",
         "HX-Trigger" => "btn", "HX-Current-URL" => "http://localhost/",
         "HX-Boosted" => "true", "HX-Prompt" => "yes"])
    @test is_htmx(htmx_req)
    @test hx_target(htmx_req) == "#result"
    @test hx_trigger(htmx_req) == "btn"
    @test hx_current_url(htmx_req) == "http://localhost/"
    @test hx_boosted(htmx_req)
    @test hx_prompt(htmx_req) == "yes"
    plain_req = HTTP.Request("GET", "/")
    @test !is_htmx(plain_req)
    @test hx_target(plain_req) == ""
    @test !hx_boosted(plain_req)
end

@testset "hx_response headers" begin
    base = h.div("content")
    resp = hx_response(base; trigger="myEvent")
    @test any(p.first == "HX-Trigger" && p.second == "myEvent"
              for p in resp.headers)
    resp = hx_response(base; push_url="/new-path")
    @test any(p.first == "HX-Push-Url" && p.second == "/new-path"
              for p in resp.headers)
    resp = hx_response(base; replace_url="/replaced")
    @test any(p.first == "HX-Replace-Url" for p in resp.headers)
    resp = hx_response(base; redirect="/other")
    @test any(p.first == "HX-Redirect" for p in resp.headers)
    resp = hx_response(base; refresh=true)
    @test any(p.first == "HX-Refresh" && p.second == "true"
              for p in resp.headers)
    resp = hx_response(base; retarget="#foo", reswap="outerHTML")
    @test any(p.first == "HX-Retarget" && p.second == "#foo" for p in resp.headers)
    @test any(p.first == "HX-Reswap" && p.second == "outerHTML" for p in resp.headers)
    @test contains(String(resp.body), "<div>")
    resp0 = hx_response(base)
    @test !any(startswith(p.first, "HX-") for p in resp0.headers)
end

@testset "@htmx struct - property access" begin
    app = TestApp()
    @test app.title == "Test"
    html = repr("text/html", app.index)
    @test contains(html, "Test")
    html = repr("text/html", app.item["foo"])
    @test contains(html, "foo")
    props = DynamicObjects.meta(TestApp)
    @test Symbol("@get") in props[:index].macros
    @test !(Symbol("@get") in props[:title].macros)
end

@testset ":index -> / routing" begin
    app = IndexApp()
    props = DynamicObjects.meta(IndexApp)
    @test haskey(props, :index)
    @test Symbol("@get") in props[:index].macros
end

@testset "indexed property with all-default indices" begin
    app = AllDefaultsApp()
    html = repr("text/html", app.viz["test"])
    @test contains(html, "Viz: test")
    html = repr("text/html", app.viz[""])
    @test contains(html, "Viz: all")
    ip = app.viz
    @test ip isa DynamicObjects.IndexableProperty
end

@testset "htmx() full-page template" begin
    page = htmx(h.main("content"))
    html = repr("text/html", page)
    @test contains(html, "htmx.org")
    @test contains(html, "hyperscript.org")
    @test contains(html, "<html")
    @test contains(html, "content")
    @test !contains(html, "pico")
    html_pico = repr("text/html", htmx(h.main(); pico_version="2"))
    @test contains(html_pico, "pico")
    html_bare = repr("text/html", htmx(h.main(); htmx_version=nothing))
    @test !contains(html_bare, "htmx.org")
    html_extra = repr("text/html", htmx(h.main(); extra_head=(h.style("body{margin:0}"),)))
    @test contains(html_extra, "body{margin:0}")
end

@testset "save_response" begin
    mktempdir() do dir
        resp = HTTP.Response(200, ["Content-Type" => "text/html"]; body="<p>hi</p>")
        dest = save_response(dir, "/", resp)
        @test isfile(dest)
        @test endswith(dest, "index.html")
        @test read(dest, String) == "<p>hi</p>"
        dest2 = save_response(dir, "/post/42", resp)
        @test isfile(dest2)
        @test basename(dest2) == "42.html"
        @test basename(dirname(dest2)) == "post"
    end
end

@testset "recording - end-to-end" begin
    mktempdir() do dir
        app = RecordApp()
        route!(app; record_dir=dir)
        port = 8099
        serve(; port, async=true)
        try
            r1 = HTTP.get("http://127.0.0.1:$port/")
            @test r1.status == 200
            @test contains(String(r1.body), "Home")
            index_file = joinpath(dir, "index.html")
            @test isfile(index_file)
            @test contains(read(index_file, String), "Home")
            r2 = HTTP.get("http://127.0.0.1:$port/post/42")
            @test r2.status == 200
            @test contains(String(r2.body), "Post 42")
            post_file = joinpath(dir, "post", "42.html")
            @test isfile(post_file)
            @test contains(read(post_file, String), "Post 42")
            r3 = HTTP.get("http://127.0.0.1:$port/post/7")
            @test r3.status == 200
            post_file2 = joinpath(dir, "post", "7.html")
            @test isfile(post_file2)
            @test contains(read(post_file2, String), "Post 7")
        finally
            terminate()
        end
    end
end

@testset "hx_link helper" begin
    link = hx_link("/about")
    html = repr("text/html", link)
    @test contains(html, "href=\"/about\"")
    @test contains(html, "hx-get=\"/about\"")
    @test contains(html, "<a")
    link2 = hx_link("/search"; hx_target="#main", class="nav-link")
    html2 = repr("text/html", link2)
    @test contains(html2, "href=\"/search\"")
    @test contains(html2, "hx-get=\"/search\"")
    @test contains(html2, "hx-target=\"#main\"")
    @test contains(html2, "class=\"nav-link\"")
end

@testset "queryparam helper" begin
    req_with_q = HTTP.Request("GET", "/search?q=hello")
    @test queryparam(req_with_q, "q", "default") == "hello"
    req_without_q = HTTP.Request("GET", "/search")
    @test queryparam(req_without_q, "q", "default") == "default"
    @test queryparam(req_without_q, "q") == ""
end

@testset "htmx_or helper" begin
    fragment = h.p("partial content")
    htmx_req = HTTP.Request("GET", "/", ["HX-Request" => "true"])
    resp = htmx_or(htmx_req, fragment) do
        htmx(h.main(fragment))
    end
    body = String(resp.body)
    @test contains(body, "partial content")
    @test !contains(body, "<html")
    plain_req = HTTP.Request("GET", "/")
    resp2 = htmx_or(plain_req, fragment) do
        htmx(h.main(fragment))
    end
    body2 = String(resp2.body)
    @test contains(body2, "partial content")
    @test contains(body2, "<html")
    @test contains(body2, "htmx.org")
end

@testset "static_transform" begin
    btn = h.button("Toggle"; hx_post="/toggle")
    transformed = static_transform(btn)
    html = repr("text/html", transformed)
    @test !contains(html, "hx-post")
    @test contains(html, "data-static-disabled")
    link = h.a("About"; hx_get="/about")
    transformed_link = static_transform(link)
    html_link = repr("text/html", transformed_link)
    @test contains(html_link, "hx-get=\"/about\"")
    @test !contains(html_link, "data-static-disabled")
    del_btn = h.button("Delete"; hx_delete="/item/1")
    transformed_del = static_transform(del_btn)
    html_del = repr("text/html", transformed_del)
    @test contains(html_del, "data-static-disabled")
    @test !contains(html_del, "hx-delete")
    head_node = h.head(h.title("Test"))
    transformed_head = static_transform(head_node)
    html_head = repr("text/html", transformed_head)
    @test contains(html_head, "data-static-disabled")  || contains(html_head, "pointer-events")
    @test contains(html_head, "pointer-events:none")
end

@testset "@post route verb metadata" begin
    props = DynamicObjects.meta(PostApp)
    @test haskey(props, :submit)
    @test Symbol("@post") in props[:submit].macros
    @test !(Symbol("@get") in props[:submit].macros)
end

@testset "type conversion in indexed routes" begin
    app = TypedApp()
    html = repr("text/html", app.typed[42])
    @test contains(html, "N=42")
    props = DynamicObjects.meta(TypedApp)
    @test haskey(props, :typed)
    @test Symbol("@get") in props[:typed].macros
end

@testset "hx_response with location" begin
    resp = hx_response(h.div("content"); location="/new")
    @test any(p.first == "HX-Location" && p.second == "/new"
              for p in resp.headers)
    @test contains(String(resp.body), "<div>")
end

@testset "queryparams - multi-value support" begin
    req = HTTP.Request("GET", "/search?q=hello&page=1")
    qp = queryparams(req)
    @test qp["q"] == "hello"
    @test qp["page"] == "1"
    req_multi = HTTP.Request("GET", "/filter?tag=a&tag=b&tag=c")
    qp_multi = queryparams(req_multi)
    @test qp_multi["tag"] isa Vector{String}
    @test qp_multi["tag"] == ["a", "b", "c"]
    req_mixed = HTTP.Request("GET", "/x?solo=1&dup=a&dup=b")
    qp_mixed = queryparams(req_mixed)
    @test qp_mixed["solo"] == "1"
    @test qp_mixed["dup"] isa Vector{String}
    @test qp_mixed["dup"] == ["a", "b"]
    req_empty = HTTP.Request("GET", "/nothing")
    qp_empty = queryparams(req_empty)
    @test isempty(qp_empty)
    @test qp_empty isa Dict{String, Union{String, Vector{String}}}
    req_enc = HTTP.Request("GET", "/s?q=hello%20world&name=a%26b")
    qp_enc = queryparams(req_enc)
    @test qp_enc["q"] == "hello world"
    @test qp_enc["name"] == "a&b"
    req_noval = HTTP.Request("GET", "/x?flag")
    qp_noval = queryparams(req_noval)
    @test qp_noval["flag"] == ""
end

@testset "queryparams_all" begin
    req = HTTP.Request("GET", "/x?color=red")
    @test queryparams_all(req, "color") == ["red"]
    req_multi = HTTP.Request("GET", "/x?id=1&id=2&id=3")
    @test queryparams_all(req_multi, "id") == ["1", "2", "3"]
    req_miss = HTTP.Request("GET", "/x?other=yes")
    @test queryparams_all(req_miss, "missing") == String[]
end

@testset "queryparam - multi-value behaviour" begin
    req = HTTP.Request("GET", "/x?name=alice")
    @test queryparam(req, "name", "default") == "alice"
    req_multi = HTTP.Request("GET", "/x?v=first&v=second")
    @test queryparam(req_multi, "v", "default") == "first"
    req_miss = HTTP.Request("GET", "/x")
    @test queryparam(req_miss, "absent", "fallback") == "fallback"
    @test queryparam(req_miss, "absent") == ""
end

@testset "nothing default in kwargs route" begin
    route!(NothingDefaultApp())
    serve(; port=8098, async=true)
    try
        r = HTTP.get("http://127.0.0.1:8098/filtered")
        body = String(r.body)
        @test contains(body, "filter=nothing")
        @test !contains(body, "filter=:nothing")
        r2 = HTTP.get("http://127.0.0.1:8098/filtered?filter=active")
        body2 = String(r2.body)
        @test contains(body2, "filter=\"active\"") || contains(body2, "filter=&quot;active&quot;")
    finally
        terminate()
    end
end

@testset "wants_markdown" begin
    req_md = HTTP.Request("GET", "/", ["Accept" => "text/markdown"])
    @test wants_markdown(req_md)
    req_plain = HTTP.Request("GET", "/", ["Accept" => "text/plain"])
    @test wants_markdown(req_plain)
    req_qp_md = HTTP.Request("GET", "/page?markdown")
    @test wants_markdown(req_qp_md)
    req_qp = HTTP.Request("GET", "/page?plain")
    @test wants_markdown(req_qp)
    req_html = HTTP.Request("GET", "/", ["Accept" => "text/html"])
    @test !wants_markdown(req_html)
    req_none = HTTP.Request("GET", "/")
    @test !wants_markdown(req_none)
end

@testset "markdown_response" begin
    resp = markdown_response("# Hello\n\nworld")
    @test resp.status == 200
    @test String(resp.body) == "# Hello\n\nworld"
    @test any(p.first == "Content-Type" && contains(p.second, "text/markdown")
              for p in resp.headers)
end

@testset "render_table" begin
    tbl = (; name=["Alice", "Bob", "Charlie"], score=[95, 87, 92])
    node = render_table(tbl)
    html = repr("text/html", node)
    @test contains(html, "<table")
    @test contains(html, "<thead")
    @test contains(html, "<tbody")
    @test contains(html, "Alice")
    @test contains(html, "87")
    @test contains(html, "name")
    @test contains(html, "score")
    @test contains(html, "sortTable")
    @test contains(html, "cursor:pointer")
    node_ns = render_table(tbl; sortable=false)
    html_ns = repr("text/html", node_ns)
    @test contains(html_ns, "Alice")
    @test !contains(html_ns, "sortTable")
    @test !contains(html_ns, "cursor:pointer")
    node_cell = render_table(tbl; cell=(v, col, ri) -> col == :score ? "**$(v)**" : string(v))
    html_cell = repr("text/html", node_cell)
    @test contains(html_cell, "**95**")
    @test contains(html_cell, "Alice")
    node_id = render_table(tbl; id="my-table")
    html_id = repr("text/html", node_id)
    @test contains(html_id, "my-table")
    node_kw = render_table(tbl; class="custom", id="t1")
    html_kw = repr("text/html", node_kw)
    @test contains(html_kw, "class=\"custom\"")
end

@testset "sortable_table_js" begin
    node = sortable_table_js()
    html = repr("text/html", node)
    @test contains(html, "<script>")
    @test contains(html, "sortTable")
    @test contains(html, "closest")
end

@testset "_convert_param with vectors" begin
    cp = HTMXObjects._convert_param
    v = ["a", "b", "c"]
    @test cp(v, nothing) === v
    @test cp(["first", "second"], String) == "first"
    @test cp(["42", "99"], Int) == 42
    @test cp(["3.14", "2.72"], Float64) == 3.14
    @test cp(["only"], String) == "only"
    @test cp(["7"], Int) == 7
end

@testset "fmt_time" begin
    @test fmt_time(1.5e-9) == "1.5ns"
    @test fmt_time(4.56e-6) == "4.6μs"
    @test fmt_time(0.0789) == "79.0ms"
    @test fmt_time(1.23) == "1.2s"
    @test fmt_time(90.0) == "1.5min"
    @test fmt_time(7200.0) == "2.0hr"
    @test fmt_time(-0.001) == "-1.0ms"
end

@testset "fmt_bytes" begin
    @test fmt_bytes(512) == "512 B"
    @test fmt_bytes(1536) == "1.5 KB"
    @test fmt_bytes(2 * 1024^2) == "2.0 MB"
    @test fmt_bytes(3.5 * 1024^3) == "3.5 GB"
    @test fmt_bytes(1.0 * 1024^4) == "1.0 TB"
end

@testset "fmt_number" begin
    @test fmt_number(0) == "0"
    @test fmt_number(42.0) == "42.0"
    @test fmt_number(1500.0) == "1.5K"
    @test fmt_number(2.5e6) == "2.5M"
    @test fmt_number(1e9) == "1.0B"
    @test fmt_number(3.0e12) == "3.0T"
    @test fmt_number(NaN) == "NaN"
    @test fmt_number(Inf) == "∞"
    @test fmt_number(-Inf) == "-∞"
    @test fmt_number(-2500.0) == "-2.5K"
end

@testset "Long" begin
    @test Long("study_cohort") == "study cohort"
    @test Long(:hello_world) == "hello world"
    @test Long("single") == "single"
end

@testset "sinput" begin
    node = sinput("color", ["red", "green", "blue"]; value="green")
    html = repr("text/html", node)
    @test contains(html, "<label>")
    @test contains(html, "<select")
    @test contains(html, "name=\"color\"")
    # selected option: HTMX.jl renders boolean `selected` as bare attr (not selected="true")
    @test contains(html, "<option value=\"green\" selected>")
    @test !contains(html, "<option value=\"red\" selected")
end

@testset "soption" begin
    # plain value
    node = soption("apple")
    html = repr("text/html", node)
    @test contains(html, "<option")
    @test contains(html, "apple")
    # Pair: value => label
    node2 = soption("us" => "United States")
    html2 = repr("text/html", node2)
    @test contains(html2, "value=\"us\"")
    @test contains(html2, "United States")
    # selected
    node3 = soption("x"; selected_value="x")
    html3 = repr("text/html", node3)
    @test contains(html3, "selected>")
end

@testset "linput" begin
    node = linput("email")
    html = repr("text/html", node)
    @test contains(html, "<label>")
    @test contains(html, "<input")
    @test contains(html, "name=\"email\"")
    @test contains(html, "placeholder=\"email\"")
end

@testset "loading_indicator_script" begin
    node = loading_indicator_script()
    @test node isa Node
    html = repr("text/html", node)
    @test contains(html, "<script>")
    @test contains(html, "htmx:beforeRequest")
    @test contains(html, "aria-busy")
end

@testset "tabset" begin
    node = tabset("Tab A" => h.p("Content A"), "Tab B" => h.p("Content B"))
    html = repr("text/html", node)
    @test contains(html, "Tab A")
    @test contains(html, "Tab B")
    @test contains(html, "Content A")
    @test contains(html, "Content B")
    # first tab active by default
    @test contains(html, "class=\"contrast\"")
    @test contains(html, "class=\"secondary\"")
    # tab panels
    @test contains(html, "tab-panel")
    @test contains(html, "display:none")
    # lazy tabs: string content → hx-get with revealed trigger
    lazy = tabset("Eager" => h.p("here"), "Lazy" => "/api/lazy")
    lhtml = repr("text/html", lazy)
    @test contains(lhtml, "here")           # eager content rendered
    @test !contains(lhtml, "/api/lazy\">")  # URL not rendered as text
    @test contains(lhtml, "hx-get=\"/api/lazy\"")
    @test contains(lhtml, "revealed once")
    # all-lazy
    lazy2 = tabset("A" => "/a", "B" => "/b")
    lhtml2 = repr("text/html", lazy2)
    @test contains(lhtml2, "hx-get=\"/a\"")
    @test contains(lhtml2, "hx-get=\"/b\"")
end

@testset "status_badge" begin
    node = status_badge(:running)
    html = repr("text/html", node)
    @test contains(html, "Running")
    @test contains(html, "color:orange")

    node2 = status_badge(:done)
    html2 = repr("text/html", node2)
    @test contains(html2, "Done")
    @test contains(html2, "color:green")

    node3 = status_badge(:failed; label="Error!")
    html3 = repr("text/html", node3)
    @test contains(html3, "Error!")
    @test contains(html3, "color:red")

    # unknown state falls back to inherit
    node4 = status_badge(:unknown)
    html4 = repr("text/html", node4)
    @test contains(html4, "color:inherit")
end

@testset "nav_sidebar" begin
    node = nav_sidebar(["Home" => "/", "About" => "/about"]; prefix="/app")
    html = repr("text/html", node)
    @test contains(html, "<aside>")
    @test contains(html, "<nav>")
    @test contains(html, "href=\"/app/\"")
    @test contains(html, "href=\"/app/about\"")
    @test contains(html, "hx-get=\"/app/\"")
    @test contains(html, "hx-push-url=\"/app/about\"")
    @test contains(html, "hx-target=\"#content\"")

    # tuple form
    node2 = nav_sidebar(("X" => "/x",))
    html2 = repr("text/html", node2)
    @test contains(html2, "href=\"/x\"")
end

@testset "@query_url" begin
    # bare symbol
    @test (@query_url index) == "/"
    @test (@query_url fit) == "/fit"
    # kwargs only
    @test (@query_url fit(; dataset="foo", model="bar")) == "/fit?dataset=foo&model=bar"
    # positional args
    @test (@query_url item(42)) == "/item/42"
    @test (@query_url item("hello")) == "/item/hello"
    # positional + kwargs
    @test (@query_url item(42; format="json")) == "/item/42?format=json"
    # variable interpolation
    let id = 99, ds = "mydata"
        @test (@query_url item(id)) == "/item/99"
        @test (@query_url fit(; dataset=ds)) == "/fit?dataset=mydata"
    end
end
