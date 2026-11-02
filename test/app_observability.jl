using TestItemRunner

@testitem "error captures retain metadata and a bounded URL index" tags=[:unit] begin
    using HTMXObjects, HTTP

    mktempdir() do dir
        repo = joinpath(dir, "repo")
        mkpath(repo)
        run(pipeline(`git -C $repo init -q`; stdout=devnull, stderr=devnull))
        run(pipeline(`git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m initial`;
            stdout=devnull, stderr=devnull))
        head = readchomp(`git -C $repo rev-parse HEAD`)
        rec = ErrorRecorder(; repo_root=repo, state_dir=joinpath(dir, "state"), max_urls=3)
        log_path = joinpath(dir, "error.log")
        write(log_path, "original error\n")
        record_error!(rec, "first", log_path, HTTP.Request("GET", "/a?x=1"))
        log = read(log_path, String)
        @test startswith(log, "original error\n")
        @test contains(log, "git_head:     $head\n")
        @test contains(log, "worktree:     clean\n")
        @test occursin(r"capture_time: \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z", log)
        index = joinpath(rec.state_dir, "failing-urls.tsv")
        rows() = HTMXObjects._capture_fields.(readlines(index))
        original = only(rows())["first_seen"]
        record_error!(rec, "second", log_path, HTTP.Request("POST", "/a?x=1"))
        @test length(rows()) == 1
        @test only(rows())["first_seen"] == original
        @test only(rows())["log"] == "second"
        @test only(rows())["verb"] == "POST"
        for url in ["/b", "/c", "/a?x=1", "/d"]
            record_error!(rec, url, log_path, HTTP.Request("GET", url))
        end
        @test getindex.(rows(), "url") == ["/c", "/a?x=1", "/d"]
        @test rows()[2]["first_seen"] == original
        write(joinpath(repo, "new.txt"), "changed")
        write(log_path, "")
        record_error!(rec, "dirty", log_path, nothing)
        @test contains(read(log_path, String), "worktree:     dirty\n  ?? new.txt")
        @test length(rows()) == 3
        withenv("HTMXO_TEST_CAPTURE_URLS" => joinpath(dir, "override.tsv")) do
            override = ErrorRecorder(; repo_root=repo, state_dir=rec.state_dir,
                urls_env="HTMXO_TEST_CAPTURE_URLS")
            record_error!(override, "override", log_path, HTTP.Request("GET", "/override"))
            @test contains(read(ENV["HTMXO_TEST_CAPTURE_URLS"], String), "url=/override")
        end
        # The same recorder serializes updates by concurrent request tasks.
        @sync for i in 1:6
            Threads.@spawn record_error!(rec, string(i), log_path, HTTP.Request("GET", "/parallel/$i"))
        end
        @test length(rows()) == 3
        @test all(row -> startswith(row["url"], "/parallel/"), rows())
        @test readdir(rec.state_dir) == ["failing-urls.tsv"]
    end
end

@testitem "error capture failures are visible and preserve the prior index" tags=[:unit] begin
    using HTMXObjects, HTTP

    mktempdir() do dir
        rec = ErrorRecorder(; repo_root=joinpath(dir, "missing"), state_dir=dir)
        log_path = joinpath(dir, "error.log")
        write(log_path, "original error\n")
        record_error!(rec, "u1", log_path, nothing)
        @test contains(read(log_path, String), "git_head:     <git unavailable:")
        @test contains(read(log_path, String), "worktree:     <git unavailable:")
        # Malformed persisted state must surface; silently resetting would lose
        # the user's failure history (dev's explicit error-visibility contract).
        index = joinpath(dir, "failing-urls.tsv")
        write(index, "malformed\n")
        @test_throws Exception record_error!(rec, "u2", log_path, HTTP.Request("GET", "/x"))
        @test read(index, String) == "malformed\n"
    end
end

@testitem "error recorder runs on the real route hook without changing the error response" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging

    capture_recorder = Ref{Any}()
    @htmx struct CapturedErrorApp
        __on_error__ = (err, uid, path) -> record_error!(capture_recorder[], uid, path, __req__)
        @get capture_boom() = error("fixture failure")
    end
    route!(CapturedErrorApp())
    mktempdir() do dir
        capture_recorder[] = ErrorRecorder(; repo_root=dir, state_dir=joinpath(dir, "state"))
        old = ERROR_DIR[]
        ERROR_DIR[] = dir
        try
            response = with_logger(NullLogger()) do
                dispatch(:GET, "/capture_boom")
            end
            uid = HTTP.header(response, "X-HTMXO-Error-Id", "")
            @test response.status == 500
            @test !isempty(uid)
            @test contains(String(response.body), uid)
            log = read(joinpath(dir, uid * ".log"), String)
            @test contains(log, "fixture failure")
            @test contains(log, "capture_time:")
            row = only(HTMXObjects._capture_fields.(readlines(joinpath(dir, "state", "failing-urls.tsv"))))
            @test row["url"] == "/capture_boom" && row["log"] == uid
            @test length(filter(name -> endswith(name, ".log"), readdir(dir))) == 1
        finally
            ERROR_DIR[] = old
        end
    end
end

@testitem "runtime panels poll without collecting and collection is explicit" tags=[:unit, :server] begin
    using HTMXObjects

    before = last_memory_collection()
    @test poll_trigger("5s") == "every 5s [!document.hidden]"
    p = runtime_snapshot().process
    @test p.rss_bytes > 0 && p.total_memory > 0 && p.live_bytes >= 0
    @test length(p.load_average) == 3 && all(isfinite, p.load_average)
    @test process_rss_bytes() > 0
    load = repr("text/html", system_load_panel("/load"; interval="5s", id="test-load"))
    @test contains(load, "hx-get=\"/load\"") && contains(load, "every 5s [!document.hidden]")
    @test contains(load, "id=\"test-load\"") && contains(load, "Process RSS")
    action = repr("text/html", memory_collect_panel("/collect"))
    @test contains(action, "hx-post=\"/collect\"")
    @test !contains(action, "hx-get") && !contains(action, "hx-trigger")
    @test last_memory_collection() === before

    @htmx struct MemoryPanelsApp
        @fresh @direct @get test_memory_load() = system_load_panel("/test_memory_load")
        @direct @post test_memory_collect() = memory_collect_panel("/test_memory_collect";
            measurement=collect_and_measure!())
    end
    route!(MemoryPanelsApp())
    @test dispatch(:GET, "/test_memory_load").status == 200
    @test last_memory_collection() === before
    response = dispatch(:POST, "/test_memory_collect")
    @test response.status == 200
    @test contains(String(response.body), "Retained Julia heap")
    m = last_memory_collection()
    @test m !== before && m.seconds >= 0 && m.at > 0
    @test m.rss_before > 0 && m.rss_after > 0
    @test m.heap_before >= 0 && m.heap_after >= 0
    # GC can allocate or leave resident pages behind: no monotonic RSS claim.
    @test contains(repr("text/html", runtime_dashboard()), "RSS ")
end

@testitem "standard projections cover screen-only table configuration and disclosures" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string

    table = render_table([(name="sample", count=3)])
    content = SemanticGroup(table,
        html_only(SemanticDisclosure("Full configuration — screen only", h.p("private-config-token"))))
    html = repr("text/html", content)
    @test contains(html, "sample") && contains(html, "private-config-token")
    markdown = to_markdown_string(content)
    @test contains(markdown, "name") && contains(markdown, "count") && contains(markdown, "sample")
    @test !contains(markdown, "private-config-token") && !contains(markdown, "screen only")
    @test strip(markdown) == strip(to_markdown_string(table))
    @htmx struct ProjectionRecipeApp
        @get projection_recipe() = content
    end
    route!(ProjectionRecipeApp())
    plain = dispatch(:GET, "/projection_recipe"; headers=["Accept" => "text/plain"])
    @test plain.status == 200
    @test strip(String(plain.body)) == strip(markdown)
    eager = SemanticDisclosure("Optional detail", h.p("the full body"))
    @test contains(repr("text/html", eager), "<details")
    @test contains(to_markdown_string(eager), "the full body")
    deferred = h.details(h.summary("Optional detail"), lazy("/detail"; hx_trigger="intersect once"))
    deferred_html = repr("text/html", deferred)
    @test contains(deferred_html, "hx-trigger=\"intersect once\"")
    @test !contains(deferred_html, "hx-trigger=\"load\"")
end
