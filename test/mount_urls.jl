using TestItemRunner

# Behind a proxy that serves an app under a mount prefix (`X-Forwarded-Prefix`,
# the KB's `/p/<slug>`), a root-absolute address (`/foo`) reaches the proxy's
# root instead of the app. `@htmx` warned only about a literal on `href`,
# `src`, `action`, `formaction`, `hx-get`…`hx-delete` and `sse-connect`: not on
# `ws-connect`, `hx-push-url` or `hx-replace-url`, and never about a literal an
# app's helper function puts on an attribute (snag `relied-on-the-ht-e42acfbb`:
# a Treebars demo's WebSocket and nine helper-built buttons left the mount
# unreported). The macro now covers every address attribute, and `serve` checks
# what a browser receives under a mount.
@testmodule MountUrlFixtures begin
    using HTMXObjects, HTTP, Logging, Test
    import HTMXObjects: h

    export MountApp, MountShellApp, served, mount_warnings, reset_mount_log!,
        lint_warnings

    # An app's own helpers: the address reaches the attribute through an
    # argument, where the `@htmx` macro cannot see it.
    run_button(label, url) = h.button(label; hx_get=url, hx_target="#out")
    socket(url) = h.div(; hx_ext="ws", ws_connect=url)
    link(url) = h.a("link"; href=url)

    @htmx struct MountApp
        "A page whose addresses arrive every way"
        @get mount_page() = h.section(
            run_button("Run", "/mount_run"),
            run_button("Again", "/mount_run?n=2"),   # same address, other query
            socket("/mount_ws"),
            link("/p/apple"),                        # shares only a prefix's letters
            link("/p/app/mount_run"),                # inside the mount
            link("/p/app"),
            link("/p/app?x=1"),
            link("https://example.org/x"),
            link("//cdn.example.org/x"),
            link("#top"),
            link("mount_run"),
            h.a("built"; href=__self__/"mount_run"),
            h.a("built"; href=string(__self__/"mount_run")),
            h.div(; hx_get=query_url(__self__/"mount_run"; n=3)),
        )
        "A target"
        @get mount_run(; n::Int=1) = h.p("run $n")
    end

    @htmx struct MountShellApp
        __page__(body) = htmx(h.main(body); overlay=true)
        "A full page in the standard shell, with the KB's overlay bar"
        @get mount_shell() = h.p("shell")
    end

    body_text(response) = String(HTMXObjects._message_body_bytes(response))

    # A request as `serve` hands it to its pipeline.
    function served(target, headers::Pair{String,String}...)
        req = HTTP.Request("GET", target, collect(headers), UInt8[])
        req.context[:htmxo_served] = true
        HTMXObjects._fallback_middleware(HTMXObjects.ROUTER)(req)
    end

    reset_mount_log!() = lock(() -> empty!(HTMXObjects._MOUNT_ESCAPES_LOGGED),
                              HTMXObjects._MOUNT_ESCAPES_LOCK)

    # The mount warnings `f` logs, and its result.
    function mount_warnings(f)
        logger = Test.TestLogger(min_level=Logging.Warn)
        result = Logging.with_logger(f, logger)
        [string(r.message) for r in logger.logs if r.group === :mount_url], result
    end

    # The warnings `@htmx`'s macro-time lint gives a struct whose body is `ex`.
    function lint_warnings(ex)
        logger = Test.TestLogger(min_level=Logging.Warn)
        Logging.with_logger(logger) do
            HTMXObjects._warn_hardcoded_url_in_attrs!(
                Expr(:struct, false, :LintApp, Expr(:block, ex)))
        end
        [string(r.message) for r in logger.logs]
    end
end

@testitem "@htmx warns about a root-absolute literal on every address attribute" setup=[MountUrlFixtures] tags=[:unit] begin
    using HTMXObjects, Logging, Test

    for attr in (:href, :src, :action, :formaction, :hx_get, :hx_post, :hx_put,
                 :hx_patch, :hx_delete, :hx_push_url, :hx_replace_url,
                 :ws_connect, :sse_connect)
        warnings = lint_warnings(:(h.div(; $attr = "/websockets/ws")))
        @test length(warnings) == 1
        @test contains(only(warnings),
            "hardcoded root-absolute URL `\"/websockets/ws\"` on `$attr`")
        @test contains(only(warnings), "`$attr=__self__/\"<rest>\"`")
    end
    # An interpolated literal is seen too.
    @test length(lint_warnings(:(h.div(; ws_connect = "/ws/$(id)")))) == 1
    # Not an address, not root-absolute, or another server's.
    @test isempty(lint_warnings(:(h.div(; hx_target = "/x", hx_ext = "ws",
        ws_send = "", hx_push_url = "true", href = "//cdn.example.org/x",
        src = "https://example.org/x", ws_connect = "wss://example.org/ws"))))
    # Through `@htmx` itself, inside a route body.
    logger = Test.TestLogger(min_level=Logging.Warn)
    Logging.with_logger(logger) do
        macroexpand(@__MODULE__, :(@htmx struct LintMacroApp
            "A page"
            @get lint_page() = h.div(; hx_ext = "ws", ws_connect = "/lint_ws")
        end))
    end
    @test any(r -> contains(string(r.message), "`\"/lint_ws\"` on `ws_connect`"), logger.logs)
end

@testitem "an address leaves the mount when it is root-absolute and outside the prefix" tags=[:unit] begin
    using HTMXObjects, Test

    leaves = HTMXObjects._mount_escape
    @test leaves("/x", "/p/app")
    @test leaves("/p/apple", "/p/app")
    @test leaves("/p", "/p/app")
    for inside in ("/p/app", "/p/app/", "/p/app/x", "/p/app?x=1", "/p/app#top")
        @test !leaves(inside, "/p/app")
    end
    for other in ("//cdn.example.org/x", "https://example.org/x", "x/y", "#top", "", "?x=1")
        @test !leaves(other, "/p/app")
    end
end

@testitem "a page served under a mount prefix logs each address that leaves it, once" setup=[MountUrlFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP, Test

    route!(MountApp())
    reset_mount_log!()
    nav = ("Accept" => "text/html", "X-Forwarded-Prefix" => "/p/app")
    warnings, response = mount_warnings(() -> served("/mount_page", nav...))
    @test response.status == 200
    @test length(warnings) == 3
    @test any(contains("`hx-get=\"/mount_run\"`"), warnings)
    @test any(contains("`ws-connect=\"/mount_ws\"`"), warnings)
    @test any(contains("`href=\"/p/apple\"`"), warnings)
    @test all(contains("GET /p/app/mount_page was served under the mount prefix `/p/app`"), warnings)
    @test all(contains("`__self__/\"…\"`"), warnings)
    # The page itself is unchanged.
    @test contains(String(HTMXObjects._message_body_bytes(response)), "ws-connect=\"/mount_ws\"")

    # Each address once per process.
    warnings, _ = mount_warnings(() -> served("/mount_page", nav...))
    @test isempty(warnings)

    # An htmx request is a browser's too, with prestarts on or off.
    for prestart in (false, true)
        reset_mount_log!()
        previous = HTMXObjects._PRESTART_APP[]
        prestart && (HTMXObjects._PRESTART_APP[] = HTMXObjects._prestart_pipeline([]))
        try
            found, _ = mount_warnings(() -> served("/mount_page", "HX-Request" => "true",
                "X-Forwarded-Prefix" => "/p/app/"))
            @test length(found) == 3
        finally
            HTMXObjects._PRESTART_APP[] = previous
        end
    end

    # No mount, or not a browser: nothing to report.
    reset_mount_log!()
    @test isempty(first(mount_warnings(() -> served("/mount_page", "Accept" => "text/html"))))
    @test isempty(first(mount_warnings(() -> served("/mount_page", "X-Forwarded-Prefix" => "/p/app"))))
    req = HTTP.Request("GET", "/mount_page", ["Accept" => "text/html", "X-Forwarded-Prefix" => "/p/app"])
    @test isempty(first(mount_warnings(() -> HTMXObjects._fallback_middleware(HTMXObjects.ROUTER)(req))))
    reset_mount_log!()
end

@testitem "the standard page shell leaves nothing outside the mount, the overlay bar's address aside" setup=[MountUrlFixtures] tags=[:unit] begin
    using HTMXObjects, Test

    route!(MountShellApp())
    reset_mount_log!()
    warnings, response = mount_warnings(() -> served("/mount_shell",
        "Accept" => "text/html", "X-Forwarded-Prefix" => "/p/app"))
    @test response.status == 200
    page = String(HTMXObjects._message_body_bytes(response))
    @test contains(page, "src=\"/overlay/bar.js\"")
    @test isempty(warnings)
    reset_mount_log!()
end

@testitem "the mount log stops after its limit" tags=[:unit] begin
    using HTMXObjects, Test

    logged = HTMXObjects._MOUNT_ESCAPES_LOGGED
    limit = HTMXObjects._MOUNT_ESCAPE_LOG_LIMIT
    first! = HTMXObjects._mount_escape_first!
    lock(() -> empty!(logged), HTMXObjects._MOUNT_ESCAPES_LOCK)
    @test all(i -> first!((:href, "/item/$i")) === :new, 1:limit)
    @test first!((:href, "/item/1")) === :seen
    @test first!((:href, "/item/$(limit + 1)")) === :limit
    @test first!((:href, "/item/$(limit + 2)")) === :seen
    @test length(logged) == limit + 1
    lock(() -> empty!(logged), HTMXObjects._MOUNT_ESCAPES_LOCK)
end
