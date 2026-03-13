using Test, HTMXObjects, HTTP

# Define test structs at module scope (Julia requires structs outside local scopes)
@htmx struct TestApp
    title = "Test"
    @get index = h.h1(title)
    @get item[id] = h.p("Item: $id")
end

@htmx struct IndexApp
    @get index = h.h1("home")
end

# Previously caused "Method definition compute_property overwritten" error
# when all indices had defaults (zero-arg conflict with IndexableProperty).
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

@testset "HTMXObjects.jl" begin

    @testset "auto - HTML rendering" begin
        # Node renders to HTML string
        result = auto(h.div("hello"); wrap=identity)
        @test contains(result, "<div>")
        @test contains(result, "hello")

        # Plain string passes through unchanged
        @test auto("<p>test</p>"; wrap=identity) == "<p>test</p>"

        # Array: fragments are joined
        result = auto([h.p("a"), h.p("b")]; wrap=identity)
        @test contains(result, "<p>a</p>")
        @test contains(result, "<p>b</p>")

        # Pair: out-of-band swap — wraps content with id + hx-swap-oob="true"
        result = auto(h.span("new") => "my-id"; wrap=identity)
        @test contains(result, "id=\"my-id\"")
        @test contains(result, "hx-swap-oob")
        @test contains(result, "new")
    end

    @testset "to_response" begin
        # Node → 200 HTML response
        resp = to_response(h.div("hello"))
        @test resp.status == 200
        @test contains(String(resp.body), "<div>")
        @test any(p.first == "Content-Type" && contains(p.second, "text/html")
                  for p in resp.headers)

        # Plain string → 200 HTML response
        resp = to_response("<p>test</p>")
        @test resp.status == 200
        @test String(resp.body) == "<p>test</p>"

        # Array → joined fragments
        resp = to_response([h.p("a"), h.p("b")])
        @test contains(String(resp.body), "<p>a</p>")

        # HTTP.Response → passthrough (not wrapped)
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

        # Query string is stripped before matching
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

        # Body is preserved
        @test contains(String(resp.body), "<div>")

        # No extra headers when nothing set
        resp0 = hx_response(base)
        @test !any(startswith(p.first, "HX-") for p in resp0.headers)
    end

    @testset "@htmx struct — property access" begin
        app = TestApp()

        # Non-route property
        @test app.title == "Test"

        # @get property: non-indexed
        html = repr("text/html", app.index)
        @test contains(html, "Test")

        # @get property: indexed
        html = repr("text/html", app.item["foo"])
        @test contains(html, "foo")

        # Only @get properties are marked
        props = DynamicObjects.meta(TestApp)
        @test Symbol("@get") in props[:index].macros
        @test !(Symbol("@get") in props[:title].macros)
    end

    @testset ":index → / routing" begin
        app = IndexApp()
        props = DynamicObjects.meta(IndexApp)
        @test haskey(props, :index)
        @test Symbol("@get") in props[:index].macros
    end

    @testset "indexed property with all-default indices" begin
        app = AllDefaultsApp()

        # Accessing via IndexableProperty (zero args) should work
        html = repr("text/html", app.viz["test"])
        @test contains(html, "Viz: test")

        # Default value should work
        html = repr("text/html", app.viz[""])
        @test contains(html, "Viz: all")

        # The IndexableProperty wrapper itself should be obtainable
        ip = app.viz
        @test ip isa DynamicObjects.IndexableProperty
    end

    @testset "htmx() full-page template" begin
        page = htmx(h.main("content"))
        html = repr("text/html", page)
        @test contains(html, "htmx.org")          # HTMX included by default
        @test contains(html, "hyperscript.org")   # Hyperscript included by default
        @test contains(html, "<html")
        @test contains(html, "content")
        @test !contains(html, "pico")             # PicoCSS off by default

        # Opt in to PicoCSS
        html_pico = repr("text/html", htmx(h.main(); pico_version="2"))
        @test contains(html_pico, "pico")

        # Disable HTMX script
        html_bare = repr("text/html", htmx(h.main(); htmx_version=nothing))
        @test !contains(html_bare, "htmx.org")

        # extra_head injects arbitrary head content
        html_extra = repr("text/html", htmx(h.main(); extra_head=(h.style("body{margin:0}"),)))
        @test contains(html_extra, "body{margin:0}")
    end

    @testset "save_response" begin
        mktempdir() do dir
            resp = HTTP.Response(200, ["Content-Type" => "text/html"]; body="<p>hi</p>")

            # Root URL → index.html
            dest = save_response(dir, "/", resp)
            @test isfile(dest)
            @test endswith(dest, "index.html")
            @test read(dest, String) == "<p>hi</p>"

            # Nested URL → mirrored path
            dest2 = save_response(dir, "/post/42", resp)
            @test isfile(dest2)
            @test basename(dest2) == "42.html"
            @test basename(dirname(dest2)) == "post"
        end
    end

    @testset "recording — end-to-end" begin
        # Define a small app with an index and an indexed route
        @htmx struct RecordApp
            @get index = h.h1("Home")
            @get post[id] = h.p("Post $id")
        end

        mktempdir() do dir
            app = RecordApp()
            route!(app; record_dir=dir)

            # Start the server on a random port
            port = 8099
            serve(; port, async=true)
            try
                # Hit the index route
                r1 = HTTP.get("http://127.0.0.1:$port/")
                @test r1.status == 200
                @test contains(String(r1.body), "Home")

                # Check that index was recorded
                index_file = joinpath(dir, "index.html")
                @test isfile(index_file)
                @test contains(read(index_file, String), "Home")

                # Hit an indexed route
                r2 = HTTP.get("http://127.0.0.1:$port/post/42")
                @test r2.status == 200
                @test contains(String(r2.body), "Post 42")

                # Check that the indexed route was recorded
                post_file = joinpath(dir, "post", "42.html")
                @test isfile(post_file)
                @test contains(read(post_file, String), "Post 42")

                # Hit another indexed route — should create a new file
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
        # Basic usage — produces <a> with both href and hx-get
        link = hx_link("/about")
        html = repr("text/html", link)
        @test contains(html, "href=\"/about\"")
        @test contains(html, "hx-get=\"/about\"")
        @test contains(html, "<a")

        # With extra kwargs
        link2 = hx_link("/search"; hx_target="#main", class="nav-link")
        html2 = repr("text/html", link2)
        @test contains(html2, "href=\"/search\"")
        @test contains(html2, "hx-get=\"/search\"")
        @test contains(html2, "hx-target=\"#main\"")
        @test contains(html2, "class=\"nav-link\"")
    end

    @testset "queryparam helper" begin
        # Request with query param present
        req_with_q = HTTP.Request("GET", "/search?q=hello")
        @test queryparam(req_with_q, "q", "default") == "hello"

        # Request without the query param — returns default
        req_without_q = HTTP.Request("GET", "/search")
        @test queryparam(req_without_q, "q", "default") == "default"

        # Default default is ""
        @test queryparam(req_without_q, "q") == ""
    end

    @testset "htmx_or helper" begin
        fragment = h.p("partial content")

        # HTMX request — returns the fragment directly
        htmx_req = HTTP.Request("GET", "/", ["HX-Request" => "true"])
        resp = htmx_or(htmx_req, fragment) do
            htmx(h.main(fragment))
        end
        body = String(resp.body)
        @test contains(body, "partial content")
        # Should NOT contain full page wrapper for HTMX requests
        @test !contains(body, "<html")

        # Non-HTMX request — calls the full_page_fn
        plain_req = HTTP.Request("GET", "/")
        resp2 = htmx_or(plain_req, fragment) do
            htmx(h.main(fragment))
        end
        body2 = String(resp2.body)
        @test contains(body2, "partial content")
        # Should contain full page wrapper
        @test contains(body2, "<html")
        @test contains(body2, "htmx.org")
    end

    @testset "static_transform" begin
        # hx-post is stripped (non-GET verb)
        btn = h.button("Toggle"; hx_post="/toggle")
        transformed = static_transform(btn)
        html = repr("text/html", transformed)
        @test !contains(html, "hx-post")
        @test contains(html, "data-static-disabled")

        # hx-get to a path route is preserved
        link = h.a("About"; hx_get="/about")
        transformed_link = static_transform(link)
        html_link = repr("text/html", transformed_link)
        @test contains(html_link, "hx-get=\"/about\"")
        @test !contains(html_link, "data-static-disabled")

        # Disabled elements get data-static-disabled attribute
        del_btn = h.button("Delete"; hx_delete="/item/1")
        transformed_del = static_transform(del_btn)
        html_del = repr("text/html", transformed_del)
        @test contains(html_del, "data-static-disabled")
        @test !contains(html_del, "hx-delete")

        # A <head> element gets the injected style
        head_node = h.head(h.title("Test"))
        transformed_head = static_transform(head_node)
        html_head = repr("text/html", transformed_head)
        @test contains(html_head, "data-static-disabled")  || contains(html_head, "pointer-events")
        # The style block for disabled elements should be injected
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
        # Accessing via property with Int index should work
        html = repr("text/html", app.typed[42])
        @test contains(html, "N=42")

        # Metadata should have @get and Int type info
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

    @testset "queryparams — multi-value support" begin
        # Single value per key
        req = HTTP.Request("GET", "/search?q=hello&page=1")
        qp = queryparams(req)
        @test qp["q"] == "hello"
        @test qp["page"] == "1"

        # Duplicate keys → Vector{String}
        req_multi = HTTP.Request("GET", "/filter?tag=a&tag=b&tag=c")
        qp_multi = queryparams(req_multi)
        @test qp_multi["tag"] isa Vector{String}
        @test qp_multi["tag"] == ["a", "b", "c"]

        # Mixed: some single, some multi
        req_mixed = HTTP.Request("GET", "/x?solo=1&dup=a&dup=b")
        qp_mixed = queryparams(req_mixed)
        @test qp_mixed["solo"] == "1"
        @test qp_mixed["dup"] isa Vector{String}
        @test qp_mixed["dup"] == ["a", "b"]

        # Empty query string → empty dict
        req_empty = HTTP.Request("GET", "/nothing")
        qp_empty = queryparams(req_empty)
        @test isempty(qp_empty)
        @test qp_empty isa Dict{String, Union{String, Vector{String}}}

        # URL-encoded values are decoded
        req_enc = HTTP.Request("GET", "/s?q=hello%20world&name=a%26b")
        qp_enc = queryparams(req_enc)
        @test qp_enc["q"] == "hello world"
        @test qp_enc["name"] == "a&b"

        # Key without value gets empty string
        req_noval = HTTP.Request("GET", "/x?flag")
        qp_noval = queryparams(req_noval)
        @test qp_noval["flag"] == ""
    end

    @testset "queryparams_all" begin
        # Single value → wrapped in vector
        req = HTTP.Request("GET", "/x?color=red")
        @test queryparams_all(req, "color") == ["red"]

        # Multiple values → all returned
        req_multi = HTTP.Request("GET", "/x?id=1&id=2&id=3")
        @test queryparams_all(req_multi, "id") == ["1", "2", "3"]

        # Missing parameter → empty vector
        req_miss = HTTP.Request("GET", "/x?other=yes")
        @test queryparams_all(req_miss, "missing") == String[]
    end

    @testset "queryparam — multi-value behaviour" begin
        # Single value returned as-is
        req = HTTP.Request("GET", "/x?name=alice")
        @test queryparam(req, "name", "default") == "alice"

        # Multi-value returns first
        req_multi = HTTP.Request("GET", "/x?v=first&v=second")
        @test queryparam(req_multi, "v", "default") == "first"

        # Missing returns default
        req_miss = HTTP.Request("GET", "/x")
        @test queryparam(req_miss, "absent", "fallback") == "fallback"

        # Missing with default default ("")
        @test queryparam(req_miss, "absent") == ""
    end

    @testset "nothing default in kwargs route" begin
        # Register the app with nothing-default kwarg
        route!(NothingDefaultApp())
        serve(; port=8098, async=true)
        try
            # No filter param → should get actual nothing, not :nothing
            r = HTTP.get("http://127.0.0.1:8098/filtered")
            body = String(r.body)
            @test contains(body, "filter=nothing")
            @test !contains(body, "filter=:nothing")

            # With filter param → should get the string value
            r2 = HTTP.get("http://127.0.0.1:8098/filtered?filter=active")
            body2 = String(r2.body)
            @test contains(body2, "filter=\"active\"") || contains(body2, "filter=&quot;active&quot;")
        finally
            terminate()
        end
    end

    @testset "_convert_param with vectors" begin
        cp = HTMXObjects._convert_param

        # Untyped vector stays as vector
        v = ["a", "b", "c"]
        @test cp(v, nothing) === v

        # Typed as String → unwraps to first element
        @test cp(["first", "second"], String) == "first"

        # Typed as Int → parses first element
        @test cp(["42", "99"], Int) == 42

        # Typed as Float64 → parses first element
        @test cp(["3.14", "2.72"], Float64) == 3.14

        # Single-element vector also works
        @test cp(["only"], String) == "only"
        @test cp(["7"], Int) == 7
    end

end
