# Tabsets with the same labels on one page: each has ids of its own and switches
# only its own panels (snag tabset-default-i-0abe876e).

@testitem "a tabset's default id comes from its labels and what its panels show" setup=[HTMXOTestImports] tags=[:unit] begin
    html(x) = repr("text/html", x)
    id(ts) = match(r"<div id=\"([^\"]+)\" class=\"tabset\"", html(ts))[1]
    two(a, b; kw...) = tabset("Eins" => a, "Zwei" => b; kw...)

    # Same labels, other content: another id, and with it other panels and tabs.
    a, b = two(h.p("a"), h.p("b")), two(h.p("a"), h.p("c"))
    @test id(a) != id(b)
    @test contains(html(b), "id=\"$(id(b))-tab-2\"") && contains(html(b), "aria-controls=\"$(id(b))-tab-2\"")
    @test id(two(h.p("a"), h.p("b"; class="x"))) != id(a)
    @test id(two(h.p("a"), h.div("b"))) != id(a)
    @test id(two("/a", "/b")) != id(two("/a", "/c"))
    @test id(two("/a", "/b")) != id(two(h.p("/a"), "/b"))
    # Other labels as before; a label that is not text is read too.
    @test id(tabset("Eins" => "/a")) != id(tabset("Zwei" => "/a"))
    @test id(tabset(h.span("Eins") => "/a")) != id(tabset(h.span("Zwei") => "/a"))
    # What sits in a nested tabset and in other values a panel holds counts too.
    @test id(two(tabset("I" => h.p("1")), "/b")) != id(two(tabset("I" => h.p("2")), "/b"))
    @test id(two(SemanticProse("x"), "/b")) != id(two(SemanticProse("y"), "/b"))
    @test id(two(SemanticGroup(SemanticProse("x")), "/b")) != id(two(SemanticGroup(SemanticProse("y")), "/b"))
    @test id(two([h.p("x"), h.p("y")], "/b")) != id(two([h.p("x"), h.p("z")], "/b"))
    @test id(two(Raw("<i>x</i>"), "/b")) != id(two(Raw("<i>y</i>"), "/b"))
    @test id(two(html_only(h.p("x")), "/b")) != id(two(html_only(h.p("y")), "/b"))

    # The same tabset built again has the same id, so a page renders to the same
    # bytes every time and in any order. A value holding a vector, or a node as
    # a label, would differ if an object's identity counted.
    same(f) = id(f()) == id(f())
    @test same(() -> two(h.p("a"), h.p("b")))
    @test same(() -> tabset(h.span("Eins") => h.p("a")))
    @test same(() -> two(SemanticGroup(SemanticProse("x"), SemanticFields(a=1)), "/b"))
    @test same(() -> two(tabset("I" => h.p("1")), "/b"))
    @test same(() -> two(private(h.p("a"); public=h.p("b")), "/b"))
    page() = html(htmx(h.main(two(h.p("a"), h.p("b")), two(h.p("a"), h.p("c"))); assets=:vendor))
    @test page() == page()

    # A value it cannot read counts by its type, never by what it holds or which
    # object it is: nothing runs to read it, and two of them still build alike.
    mutable struct OpaquePanel; text::String; end
    Base.show(io::IO, ::MIME"text/html", p::OpaquePanel) = print(io, "<p>", p.text, "</p>")
    @test same(() -> two(OpaquePanel("x"), "/b"))
    @test id(two(OpaquePanel("x"), "/b")) != id(two(h.p("x"), "/b"))
    @test contains(html(two(OpaquePanel("x"), "/b")), "<p>x</p>")

    # Private content leaves no trace in an id a public reader sees. A stand-in
    # is what that reader sees, so it counts.
    @test id(two(private(h.p("geheim 1")), "/b")) == id(two(private(h.p("geheim 2")), "/b"))
    @test id(two(h.div(private("geheim 1")), "/b")) == id(two(h.div(private("geheim 2")), "/b"))
    @test id(two(SemanticGroup(private(SemanticProse("geheim 1"))), "/b")) == id(two(SemanticGroup(private(SemanticProse("geheim 2"))), "/b"))
    @test id(two(private(h.p("x"); public=h.p("1")), "/b")) != id(two(private(h.p("x"); public=h.p("2")), "/b"))
    # Content a function builds when it is shown is not built for the id.
    built = Ref(0)
    deferred = two(private() do
        built[] += 1
        h.p("geheim")
    end, "/b")
    @test built[] == 0
    @test startswith(id(deferred), "tabset-")

    # An id the caller gives is the id.
    @test id(two(h.p("a"), h.p("b"); id="meine-tabs")) == "meine-tabs"
    # A lazy tab's link finds its panel from where it stands, so tabsets that
    # share an id still load into their own.
    @test contains(html(two(h.p("a"), "/b"; id="ts")), "hx-target=\"next #ts-tab-2\"")
end

@testitem "tabsets with one set of labels switch only their own panels, in a real browser" setup=[HTMXOTestImports, TabsetBrowser] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        form(kind, mode) = h.form(; id="$kind-$mode")(h.select(; name="profile")(h.option("$kind $mode")))
        composer(kind) = h.div(; id="kind-$kind")(tabset("One report" => form(kind, "one"), "Several reports" => form(kind, "several");
            names=["one", "several"], url_param="reports"))
        kinds = tabset("Alpha" => composer("alpha"), "Beta" => composer("beta"), "Gamma" => composer("gamma");
            names=["alpha", "beta", "gamma"], url_param="new", id="kinds")
        # Tabsets with nothing to tell them apart: the labels and the panels are
        # the same, so they share an id. They still work, eager and lazy.
        twin(id, ts...; kw...) = h.div(; id)(tabset(ts...; kw...))
        body = h.main(; id="main")(kinds,
            twin("twin-1", "A" => h.p("same a"), "B" => h.p("same b"); url_param=nothing),
            twin("twin-2", "A" => h.p("same a"), "B" => h.p("same b"); url_param=nothing),
            twin("lazy-1", "A" => "/lazy/a", "B" => "/lazy/b"; url_param="lz"),
            twin("lazy-2", "A" => "/lazy/a", "B" => "/lazy/b"; url_param="lz"),
            h.div(; id="late", hx_get="/fragment", hx_trigger="load", hx_swap="innerHTML"))
        fragment = repr("text/html", composer("delta"))
        shell(; kw...) = htmx(body; assets=:vendor, feedback=false, compose=false, thread=false,
            treebars_assets=false, preload_version=nothing, kw...)
        page = repr("text/html", shell(; pico_version=HTMXObjects._PICO_VERSION))
        exported = repr("text/html", static_transform(shell(; runtime=:linked), StaticExport()))
        vendorfiles()
        pages = Dict("/" => page, "/export" => exported)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"], pages[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/fragment" && return HTTP.Response(200, ["Content-Type" => "text/html"], fragment)
            startswith(path, "/lazy/") && return HTTP.Response(200, ["Content-Type" => "text/html"], "<p class=\"loaded\">$(basename(path))</p>")
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        base = "http://127.0.0.1:$port"
        mktempdir() do profile
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1200,4000 --remote-debugging-port=0 '--remote-allow-origins=*' --user-data-dir=$profile about:blank`
            process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
            try
                active = joinpath(profile, "DevToolsActivePort")
                @test timedwait(() -> isfile(active) && countlines(active) >= 2, 30; pollint=0.05) === :ok
                debug_port = strip(first(readlines(active)))
                targets = String(HTTP.get("http://127.0.0.1:$debug_port/json/list").body)
                target = match(r"\"webSocketDebuggerUrl\"\s*:\s*\"(ws://[^\"]*/page/[^\"]*)\"", targets)[1]
                HTTP.WebSockets.open(target; suppress_close_error=true) do ws
                    b = Browser(ws, Ref(0))
                    click(sel) = evaluate(b, "document.querySelector('$sel').click(); ''")
                    seen(sel) = evaluate(b, "String(document.querySelector('$sel').checkVisibility())") == "true"
                    # The element ids of the tabsets inside `sel`, and those of them used twice.
                    repeated(sel) = evaluate(b, "(ids => ids.filter((x, i) => ids.indexOf(x) !== i).join(','))(" *
                        "Array.from(document.querySelectorAll('$sel .tabset, $sel .tabset > nav [role=tab], $sel .tabset > .tab-panel')).map(e => e.id))")
                    # Each tab of the tabsets inside `sel` names a panel of its own tabset.
                    crossed(sel) = evaluate(b, "Array.from(document.querySelectorAll('$sel .tabset > nav [role=tab]')).filter(t => " *
                        "document.getElementById(t.getAttribute('aria-controls')).parentElement !== t.closest('.tabset') || " *
                        "document.getElementById(document.getElementById(t.getAttribute('aria-controls')).getAttribute('aria-labelledby')) !== t).map(t => t.id).join(',')")
                    tab(kind, mode) = "#kind-$kind a[data-tab-name=$mode]"
                    panel(root, n) = "#$root .tab-panel[data-panel=tab-$n]"
                    tabof(root, n) = "#$root a[data-panel=tab-$n]"
                    settled() = sleep(0.3)
                    # Everything on the page but the twins, who share their ids by design.
                    OWN = "#main > :not([id^=twin]):not([id^=lazy])"

                    for path in ("/", "/export")
                        @test open_page(b, base * path)
                        @test repeated("#kinds") == ""
                        @test crossed("#kinds") == ""

                        # The second kind's own pair works, there and back.
                        @test seen("#alpha-one") && !seen("#beta-one")
                        click("#kinds > nav a[data-tab-name=beta]")
                        @test wait_for(b, "document.getElementById('beta-one').checkVisibility()")
                        click(tab("beta", "several"))
                        @test wait_for(b, "document.getElementById('beta-several').checkVisibility()")
                        @test !seen("#beta-one")
                        click(tab("beta", "one"))
                        @test wait_for(b, "document.getElementById('beta-one').checkVisibility()")
                        @test !seen("#beta-several")
                        click(tab("beta", "several"))
                        @test wait_for(b, "document.getElementById('beta-several').checkVisibility()")

                        # The other kinds keep what they showed.
                        click("#kinds > nav a[data-tab-name=alpha]")
                        @test wait_for(b, "document.getElementById('alpha-one').checkVisibility()")
                        @test !seen("#alpha-several")
                        @test evaluate(b, "document.querySelector('$(tab("gamma", "one"))').getAttribute('aria-selected')") == "true"

                        # Tabsets with nothing to tell them apart keep to themselves.
                        @test seen(panel("twin-1", 1)) && seen(panel("twin-2", 1))
                        click(tabof("twin-2", 2))
                        @test wait_for(b, "document.querySelector('$(panel("twin-2", 2))').checkVisibility()")
                        @test !seen(panel("twin-2", 1))
                        @test seen(panel("twin-1", 1)) && !seen(panel("twin-1", 2))
                        click(tabof("twin-2", 1))
                        @test wait_for(b, "document.querySelector('$(panel("twin-2", 1))').checkVisibility()")
                        @test seen(panel("twin-1", 1)) && !seen(panel("twin-1", 2))
                    end

                    # A fragment that arrives later with the same labels is no different.
                    @test open_page(b, "$base/")
                    @test wait_for(b, "document.getElementById('delta-one')")
                    @test repeated(OWN) == ""
                    @test crossed(OWN) == ""
                    click(tab("delta", "several"))
                    @test wait_for(b, "document.getElementById('delta-several').checkVisibility()")
                    @test !seen("#delta-one") && seen("#alpha-one") && !seen("#alpha-several")

                    # A shared parameter opens the named tab of every tabset that has it.
                    @test open_page(b, "$base/?new=beta&reports=several")
                    @test seen("#beta-several") && !seen("#beta-one")
                    for kind in ("alpha", "gamma")
                        @test evaluate(b, "document.querySelector('$(tab(kind, "several"))').getAttribute('aria-selected')") == "true"
                    end

                    # A lazy tab loads into its own panel: from its first click, the
                    # shown tab by itself, and a default tab the URL hid.
                    loaded(root, n) = "document.querySelector('$(panel(root, n)) .loaded')"
                    @test open_page(b, "$base/")
                    @test wait_for(b, "$(loaded("lazy-1", 1)) && $(loaded("lazy-2", 1))")
                    click(tabof("lazy-2", 2))
                    @test wait_for(b, loaded("lazy-2", 2))
                    @test seen(panel("lazy-2", 2)) && !seen(panel("lazy-2", 1))
                    settled()
                    @test evaluate(b, "String(Boolean($(loaded("lazy-1", 2))))") == "false"
                    @test seen(panel("lazy-1", 1)) && !seen(panel("lazy-1", 2))

                    @test open_page(b, "$base/?lz=b")
                    @test wait_for(b, "$(loaded("lazy-1", 2)) && $(loaded("lazy-2", 2))")
                    click(tabof("lazy-2", 1))
                    @test wait_for(b, loaded("lazy-2", 1))
                    @test seen(panel("lazy-2", 1)) && !seen(panel("lazy-2", 2))
                    settled()
                    @test evaluate(b, "String(Boolean($(loaded("lazy-1", 1))))") == "false"
                    @test seen(panel("lazy-1", 2))
                end
            finally
                kill(process)
                timedwait(() -> process_exited(process), 5; pollint=0.05) === :ok || kill(process, Base.SIGKILL)
            end
        end
        close(server)
    end
end
