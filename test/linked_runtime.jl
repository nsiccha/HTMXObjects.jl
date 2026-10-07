using TestItemRunner

# `htmx(...; runtime=:linked)`: the shell links its own CSS/JS runtime from the
# vendor mount instead of inlining it, so a browser caches it across page loads.

@testitem "htmx() runtime=:linked links each runtime block from the vendor mount" setup=[HTMXOTestImports] tags=[:unit] begin
    using Treebars  # the poll assets join the runtime while the extension is loaded
    import HTMXObjects: _runtime_text, _runtime_blocks
    kw = (; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION)
    inline = repr("text/html", htmx(h.p("x"); kw...))
    linked = repr("text/html", htmx(h.p("x"); kw..., runtime=:linked))

    # Inline stays the default.
    @test repr("text/html", htmx(h.p("x"); kw..., runtime=:inline)) == inline

    # Nothing of the runtime is left in the page.
    @test !contains(linked, "<style")
    @test all(isempty(m.captures[1]) for m in eachmatch(r"<script\b[^>]*>(.*?)</script>"s, linked))
    @test ncodeunits(linked) < ncodeunits(inline) ÷ 20

    # Every inline block is linked, in the same order, from a URL carrying
    # its content version — and the file holds exactly the inline text.
    names = Symbol.(m.captures[1] for m in eachmatch(r"data-htmxo-runtime=\"([a-z_]+)\"", linked))
    @test :treebars_script in names && :live_region in names && :pico_bridge in names
    inline_blocks = [m.captures[1] for m in eachmatch(r"<(?:style|script)>(.*?)</(?:style|script)>"s, inline)]
    @test inline_blocks == [_runtime_text(name) for name in names]
    for name in names
        ext = first(getfield(_runtime_blocks(), name))
        @test contains(linked, "/vendor/htmxo/$name.$ext?v=$(HTMXObjects._runtime_version(_runtime_text(name)))")
    end
    @test HTMXObjects._runtime_version("a") != HTMXObjects._runtime_version("b")

    # The vendored libraries gain their pins, so the whole head is cacheable.
    @test contains(linked, "src=\"/vendor/htmx.min.js?v=$(HTMXObjects._HTMX_VERSION)\"")
    @test contains(linked, "href=\"/vendor/pico.min.css?v=$(HTMXObjects._PICO_VERSION)\"")
    @test !contains(inline, "?v=")

    # Shell switches still decide which blocks a page carries.
    bare = repr("text/html", htmx(h.p("x"); assets=:vendor, runtime=:linked,
        feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing))
    @test !contains(bare, "request_feedback") && !contains(bare, "treebars") && !contains(bare, "preload")
    @test contains(bare, "data-htmxo-runtime=\"live_region\"")

    # The mount follows `assets`, so a proxied root page passes its prefix once.
    proxied = repr("text/html", htmx(h.p("x"); assets="/p/app/vendor/", runtime=:linked))
    @test contains(proxied, "src=\"/p/app/vendor/htmxo/live_region.js?v=")
    @test contains(proxied, "src=\"/p/app/vendor/htmx.min.js?v=")
    @test contains(repr("text/html", HTMXObjects.pico_page(h.p("x"); assets=:vendor,
        pico_version=HTMXObjects._PICO_VERSION, runtime=:linked)), "/vendor/htmxo/theme.css?v=")

    # Linking needs a same-origin mount; unknown modes fail loudly.
    @test_throws ErrorException htmx(h.p("x"); runtime=:linked)
    @test_throws ErrorException htmx(h.p("x"); assets=:vendor, runtime=:external)
end

@testitem "vendorfiles() serves the linked runtime, immutable at its version" setup=[HTMXOTestImports] tags=[:unit] begin
    using Treebars
    import HTMXObjects: _runtime_text
    vendorfiles()
    linked = repr("text/html", htmx(h.p("x"); assets=:vendor, runtime=:linked))
    urls = [m.captures[1] for m in eachmatch(r"(?:src|href)=\"(/vendor/htmxo/[^\"]+)\"", linked)]
    @test length(urls) >= 15
    for url in urls
        name = Symbol(match(r"/htmxo/([a-z_]+)\.", url).captures[1])
        r = dispatch(:GET, url)
        @test r.status == 200
        @test HTTP.header(r, "Content-Type") == (contains(url, ".css?") ?
            "text/css; charset=utf-8" : "text/javascript; charset=utf-8")
        @test String(r.body) == _runtime_text(name)
        @test HTTP.header(r, "Cache-Control") == "public, max-age=31536000, immutable"
        etag = HTTP.header(r, "ETag")
        @test etag == "\"" * split(url, "?v=")[2] * "\""
        # Any other version, or none, revalidates against the ETag.
        path = first(split(url, '?'))
        @test HTTP.header(dispatch(:GET, path), "Cache-Control") == "no-cache"
        @test HTTP.header(dispatch(:GET, path * "?v=stale"), "Cache-Control") == "no-cache"
        not_modified = dispatch(:GET, path; headers=["If-None-Match" => etag])
        @test not_modified.status == 304
        @test isempty(not_modified.body)
    end

    # The vendored libraries answer the same way at their pins.
    pinned = dispatch(:GET, "/vendor/htmx.min.js?v=$(HTMXObjects._HTMX_VERSION)")
    @test pinned.status == 200
    @test HTTP.header(pinned, "Cache-Control") == "public, max-age=31536000, immutable"
    @test HTTP.header(pinned, "ETag") == "\"$(HTMXObjects._HTMX_VERSION)\""
    @test HTTP.header(dispatch(:GET, "/vendor/htmx.min.js"), "Cache-Control") == "no-cache"
    @test dispatch(:GET, "/vendor/htmx.min.js";
        headers=["If-None-Match" => "W/\"other\", \"$(HTMXObjects._HTMX_VERSION)\""]).status == 304

    # A caller's own Cache-Control wins.
    vendorfiles("own-cache"; headers=["Cache-Control" => "max-age=5"])
    @test HTTP.header(dispatch(:GET, "/own-cache/htmxo/theme.css?v=x"), "Cache-Control") == "max-age=5"
    @test HTTP.header(dispatch(:GET, "/own-cache/sse.min.js"), "Cache-Control") == "max-age=5"
end

@testitem "static export puts a linked runtime back inline" setup=[HTMXOTestImports] tags=[:unit] begin
    using Treebars
    kw = (; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION)
    inline = htmx(h.p("x"); kw...)
    linked = htmx(h.p("x"); kw..., runtime=:linked)
    for transform in (val -> static_transform(val), val -> static_transform(val, StaticExport()))
        exported = repr("text/html", transform(linked))
        @test !contains(exported, "data-htmxo-runtime") && !contains(exported, "/htmxo/")
        # Exactly the inline export, apart from the pinned library URLs.
        @test replace(exported, r"\?v=[0-9.]+\"" => "\"") == repr("text/html", transform(inline))
    end
end

@testitem "a linked runtime runs and stays cached across page loads in a browser" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using Treebars, Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        # Each load reports what the linked runtime set up, then the first one
        # navigates to a second page that links the same files.
        driver = h.script(Raw(raw"""
        var htmxoErrors = [];
        window.addEventListener('error', function(e) { htmxoErrors.push(e.message || 'resource'); }, true);
        window.addEventListener('load', function() {
          var n = new URLSearchParams(location.search).get('n') || '1';
          var checks = [
            typeof htmx === 'object',
            typeof window.htmxoStreamProbe === 'object',
            typeof htmxoMdToggle === 'function',
            typeof window.htmxoThread === 'object',
            window.__htmxoMutationPolls === true,
            getComputedStyle(document.documentElement).getPropertyValue('--htmxo-accent').trim() !== '',
          ].map(function(ok) { return ok ? '1' : '0'; }).join('');
          fetch('/report?n=' + n + '&checks=' + checks + '&errors=' + encodeURIComponent(htmxoErrors.join('|')))
            .then(function() { if (n === '1') location.href = '/?n=2'; });
        });
        """))
        page = repr("text/html", htmx(h.main(h.p("linked")), driver; assets=:vendor,
            runtime=:linked, pico_version=HTMXObjects._PICO_VERSION))
        vendorfiles()
        runtime_requests = Ref(0)
        vendor_requests = Ref(0)
        reports = Channel{Tuple{String,Int,Int}}(2)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/favicon.ico" && return HTTP.Response(204)
            if path == "/report"
                q = HTTP.queryparams(uri)
                put!(reports, (q["n"] * ":" * q["checks"] * ":" * q["errors"],
                               runtime_requests[], vendor_requests[]))
                return HTTP.Response(204)
            end
            if startswith(path, "/vendor/")
                startswith(path, "/vendor/htmxo/") ? (runtime_requests[] += 1) : (vendor_requests[] += 1)
                return dispatch(:GET, req.target; headers=collect(req.headers))
            end
            HTTP.Response(404)
        end
        try
            mktempdir() do profile
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/`
                process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                try
                    @test timedwait(() -> Base.n_avail(reports) == 2 || process_exited(process), 90; pollint=0.05) === :ok
                    first_load = take!(reports)
                    @test first_load[1] == "1:111111:"
                    linked_files = count("data-htmxo-runtime", page)
                    @test first_load[2] == linked_files
                    second_load = take!(reports)
                    @test second_load[1] == "2:111111:"
                    # Nothing linked is fetched again: neither the runtime nor
                    # the pinned libraries.
                    @test second_load[2] == first_load[2]
                    @test second_load[3] == first_load[3]
                finally
                    process_exited(process) || kill(process)
                    wait(process)
                end
            end
        finally
            close(server)
        end
    end
end
