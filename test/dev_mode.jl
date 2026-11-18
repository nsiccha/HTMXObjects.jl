using TestItemRunner

# `serve(; dev=true)`: development mode applies a saved source edit before the
# next request (Revise's `revise(mod; force=false)` on the changed package) and
# reloads the open page through a page script (user decision `14xfxqy`, todo
# `074575c`).

@testitem "development mode answers its page's poll and scripts only full pages" tags=[:unit] begin
    using HTMXObjects, HTTP, JSON, Test
    import HTMXObjects: h

    @htmx struct DevScriptApp
        @get devs_page() = htmx(h.p("page"))
        @get devs_fragment() = h.p("fragment")
    end
    route!(DevScriptApp())
    dev = HTMXObjects._DevMode()
    app = HTMXObjects._request_pipeline([], nothing, nothing; dev)
    plain = HTMXObjects._request_pipeline([], nothing, nothing)
    get(a, t; headers=Pair{String,String}[]) = a(HTTP.Request("GET", t, headers, UInt8[]))
    body(r) = String(copy(HTMXObjects._message_body_bytes(r)))

    # The poll is answered before routing, from the page's own address.
    poll = get(app, "/devs_fragment?__htmxo_dev=0")
    @test poll.status == 200
    @test HTTP.header(poll, "Cache-Control") == "no-store"
    status = JSON.parse(body(poll))
    @test status["boot"] == dev.boot
    @test status["generation"] == 0
    @test isempty(status["errors"])
    # A full page carries the script, after its <body> tag, with its boot id and generation.
    page = body(get(app, "/devs_page"))
    @test occursin(r"<body[^>]*><script data-htmxo-dev>", page)
    @test contains(page, "var boot=\"$(dev.boot)\",gen=0")
    @test replace(page, HTMXObjects._dev_page_script(dev.boot, 0) => "") == body(get(plain, "/devs_page"))
    # A navigation to a bare fragment gets it appended (browsers put it in the
    # body); an htmx swap, and every answer without dev mode, carry none.
    @test body(get(app, "/devs_fragment")) ==
          "<p>fragment</p>" * HTMXObjects._dev_page_script(dev.boot, 0)
    @test !contains(body(get(app, "/devs_fragment"; headers=["HX-Request" => "true"])), "data-htmxo-dev")
    @test !contains(body(get(app, "/devs_page"; headers=["HX-Request" => "true"])), "data-htmxo-dev")
    @test !contains(body(get(plain, "/devs_page")), "data-htmxo-dev")
    @test get(plain, "/devs_fragment?__htmxo_dev=0").status == 200
    @test body(get(plain, "/devs_fragment?__htmxo_dev=0")) == "<p>fragment</p>"
end

@testitem "development mode's keywords are checked and it needs Revise" tags=[:unit] begin
    using HTMXObjects, Test
    @test HTMXObjects._dev_mode(false, nothing, nothing) === nothing
    @test_throws ArgumentError HTMXObjects._dev_mode(false, ["/tmp"], nothing)
    @test_throws ArgumentError HTMXObjects._dev_mode(true, nothing, :lazy)
    if HTMXObjects._revise_module() === nothing
        @test_throws ErrorException HTMXObjects._dev_mode(true, nothing, nothing)
        @test_throws ErrorException serve(; dev=true)
    end
    # Registry and standard-library packages are not dev roots by default.
    @test !HTMXObjects._dev_in_roots(joinpath(first(DEPOT_PATH), "packages", "X", "abc"), nothing)
    @test !HTMXObjects._dev_in_roots(joinpath(Sys.STDLIB, "Dates"), nothing)
    @test HTMXObjects._dev_in_roots(mktempdir(), nothing)
    @test HTMXObjects._dev_in_roots("/a/b/c", ["/a/b/"])
    @test !HTMXObjects._dev_in_roots("/a/bc", ["/a/b/"])
end

@testitem "development mode sees an edit by size, modification time or content" tags=[:unit] begin
    using HTMXObjects, Test
    dev = HTMXObjects._DevMode()
    file = joinpath(mktempdir(), "src.jl")
    write(file, "f() = 1\n")
    @test !HTMXObjects._dev_changed!(dev, file, true)      # first sight: the baseline
    @test !HTMXObjects._dev_changed!(dev, file, true)
    write(file, "f() = 10\n")                              # size changed
    @test HTMXObjects._dev_changed!(dev, file, false)
    @test !HTMXObjects._dev_changed!(dev, file, true)
    if !Sys.iswindows()
        # Same size and modification time, other content: only the hash sees it.
        stamp = joinpath(dirname(file), "stamp")
        cp(file, stamp; force=true)
        run(`touch -r $file $stamp`)
        write(file, "f() = 20\n")
        run(`touch -r $stamp $file`)
        @test !HTMXObjects._dev_changed!(dev, file, false)  # stat alone cannot tell
        @test HTMXObjects._dev_changed!(dev, file, true)    # the content hash does
    end
end

@testitem "serve(; dev=true) applies a saved edit on the next request, inside @htmx structs too" tags=[:integration, :dev] begin
    using HTMXObjects, Test
    # Revise must load before the app it tracks, and loading it here would
    # change every later item in this process: run it in a fresh one.
    root = mktempdir()
    src = joinpath(root, "DevModeApp", "src")
    mkpath(src)
    write(joinpath(src, "DevModeApp.jl"), """
    module DevModeApp
    using HTMXObjects
    import HTMXObjects: h
    greeting() = "hello"
    @htmx struct DevApp
        label = "v1"
        @get dev_page() = h.p(greeting(), " ", label)
        @get dev_shell() = htmx(h.p("shell"))
    end
    end
    """)
    script = joinpath(root, "drive.jl")
    write(script, raw"""
    using Revise
    const ROOT = ARGS[1]
    push!(LOAD_PATH, ROOT)
    using HTTP, HTMXObjects
    using DevModeApp
    const FILE = joinpath(ROOT, "DevModeApp", "src", "DevModeApp.jl")
    route!(DevModeApp.DevApp())
    dev = HTMXObjects._dev_mode(true, [joinpath(ROOT, "DevModeApp")], nothing)
    app = HTMXObjects._request_pipeline([], nothing, nothing; dev)
    # As htmx asks for a fragment (a navigation would carry the page script).
    body(t; h=["HX-Request" => "true"]) =
        String(copy(HTMXObjects._message_body_bytes(app(HTTP.Request("GET", t, h, UInt8[])))))
    edit(f) = write(FILE, f(read(FILE, String)))
    println("R1=", body("/dev_page"))
    edit(s -> replace(s, repr("hello") => repr("hi there")))   # a helper, another size
    t = @elapsed r2 = body("/dev_page")
    println("R2=", r2)
    println("T2=", t)
    sleep(1.1)                                                   # the content-hash interval
    edit(s -> replace(s, repr("v1") => repr("v2")))             # inside the @htmx struct, same size
    sleep(1.1)
    t = @elapsed r3 = body("/dev_page")
    println("R3=", r3)
    println("T3=", t)
    println("S3=", body("/dev_page?__htmxo_dev=0"))
    t = @elapsed body("/dev_page")
    println("T0=", t)
    println("P=", occursin("data-htmxo-dev", body("/dev_shell"; h=Pair{String,String}[])))
    edit(s -> replace(s, "    label = " * repr("v2") => "    label = " * repr("v2") * "\n    extra::Int"))   # a new field
    println("R4=", body("/dev_page"; h=Pair{String,String}[]))
    println("S4=", body("/dev_page?__htmxo_dev=0"))
    """)
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $script $root`
    errlog = joinpath(root, "stderr.log")
    out = read(pipeline(ignorestatus(cmd); stderr=errlog), String)
    lines = Dict(String(m[1]) => String(m[2]) for m in eachmatch(r"^([A-Z]\d?)=(.*)$"m, out))
    haskey(lines, "S4") || println(stderr, "development-mode driver output:\n", out,
                                   "\nstderr:\n", read(errlog, String))
    @test lines["R1"] == "<p>hello v1</p>"
    # A helper the route calls: applied on the very next request.
    @test lines["R2"] == "<p>hi there v1</p>"
    # A property body inside the `@htmx struct` (same size: found by its content).
    @test lines["R3"] == "<p>hi there v2</p>"
    @test occursin("\"generation\":2", lines["S3"])
    @test occursin("\"errors\":[]", lines["S3"])
    @test lines["P"] == "true"
    # A new field cannot be redefined in a running Julia 1.10/1.11 process:
    # Revise applies it only in part, the poll names the edit, and the page it
    # broke still carries the script, so it comes back by itself after the
    # restart.
    if VERSION < v"1.12"
        @test occursin("DevModeApp.jl", lines["S4"])
        @test !occursin("\"errors\":[]", lines["S4"])
        @test occursin("data-htmxo-dev", lines["R4"])
    end
    # Measured: the request that applies an edit, and one with nothing to apply.
    @info "development mode timings" first_apply_s=parse(Float64, lines["T2"]) second_apply_s=parse(Float64, lines["T3"]) unchanged_s=parse(Float64, lines["T0"])
    @test parse(Float64, lines["T0"]) < 0.5
end
