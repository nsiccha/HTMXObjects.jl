using TestItemRunner

# Syntax highlighting: every `<code class="language-…">` on an `htmx()` page,
# such as a `SemanticCode` or a Markdown fence naming its language, is
# highlighted by the shell's `syntax_script` with PrismJS, which it loads on
# demand from the `prism_version` template (CDN or the vendor mount). Snag
# `syntax-highlight-d62ced15` (reporter VerkehrsStrukturdaten:ux): code showed
# monochrome unless an app added `htmxo_syntax_head()`, which loaded PrismJS
# from jsdelivr only and never highlighted code swapped in later.

@testmodule SyntaxSiteFixture begin
    using HTMXObjects
    import HTMXObjects: h
    export SyntaxSiteApp

    @htmx struct SyntaxSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked)
        @get index() = h.div(SemanticCode(:stan, "real y;"),
            h.div(; hx_get=__self__ / "syntax_part", hx_trigger="load"))
        @get syntax_part() = SemanticCode(:julia, "f(x) = x")
    end
end

@testitem "the shell names PrismJS for the syntax runtime" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _runtime_text
    page(; kw...) = repr("text/html", htmx(SemanticCode(:julia, "x = 1"); kw...))
    template(s) = (m = match(r"<template id=\"htmxo-prism\">(.*?)</template>"s, s); isnothing(m) ? nothing : m[1])
    files(dir, q="") = "<script src=\"$dir/components/prism-core.min.js$q\"></script>" *
        "<script src=\"$dir/plugins/autoloader/prism-autoloader.min.js$q\"></script>"

    # The template is inert; the runtime adds its files once the page shows code.
    @test template(page()) == files("https://cdn.jsdelivr.net/npm/prismjs@$(HTMXObjects._PRISM_VERSION)")
    @test template(page(; assets=:vendor)) == files("/vendor/prism")
    @test template(page(; assets="assets/vendor")) == files("assets/vendor/prism")
    @test template(page(; assets=:vendor, runtime=:linked)) ==
        files("/vendor/prism", "?v=$(HTMXObjects._PRISM_VERSION)")
    @test template(page(; prism_version="1.29.0")) == files("https://cdn.jsdelivr.net/npm/prismjs@1.29.0")
    @test isnothing(template(page(; prism_version=nothing)))
    # Vendor mode serves PrismJS only at its pin.
    err = try
        page(; assets=:vendor, prism_version="1.29.0"); nothing
    catch e
        sprint(showerror, e)
    end
    @test contains(err, "vendored prism is pinned at $(HTMXObjects._PRISM_VERSION)")

    # Every shell carries the runtime, inline or linked; it is inert without code.
    for kw in ((;), (; prism_version=nothing))
        s = page(; kw...)
        @test contains(s, _runtime_text(:syntax_script)) && contains(s, _runtime_text(:syntax_styles))
    end
    linked = page(; assets=:vendor, runtime=:linked)
    @test contains(linked, "data-htmxo-runtime=\"syntax_script\"") &&
        contains(linked, "data-htmxo-runtime=\"syntax_styles\"")
    @test syntax_script() isa Node && syntax_styles() isa Node
    # The code itself is unchanged: a language class on plain text.
    @test contains(page(), "<pre><code class=\"language-julia\">x = 1</code></pre>")

    # The page's Markdown leaves the template and runtime out.
    @test !contains(HTMXObjects.to_markdown_string(htmx(h.p("x"))), "prism")
end

@testitem "htmxo_syntax_head is the shell's own runtime, carried once" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _runtime_text
    @test repr.("text/html", htmxo_syntax_head()) == repr.("text/html", (syntax_styles(), syntax_script()))
    # An app that still lists it in `extra_head` ships each block once.
    for kw in ((;), (; assets=:vendor, runtime=:linked))
        s = repr("text/html", htmx(h.p("x"); extra_head=(htmxo_syntax_head()...,), kw...))
        plain = repr("text/html", htmx(h.p("x"); kw...))
        @test s == plain
    end
end

@testitem "PrismJS is vendored as a directory in its npm layout" tags=[:unit] begin
    using HTMXObjects, HTTP
    import HTMXObjects: _vendor_files
    prism = _vendor_files(:prism)
    @test first.(prism[1:2]) == ["prism/components/prism-core.min.js",
                                 "prism/plugins/autoloader/prism-autoloader.min.js"]
    languages = first.(prism[3:end])
    @test length(languages) == 297 && all(startswith("prism/components/prism-"), languages)
    @test issorted(languages)
    for lang in ("julia", "stan", "python", "json", "toml", "r", "bash", "markup-templating")
        @test "prism/components/prism-$lang.min.js" in languages
    end
    @test !("prism/components/prism-core.min.js" in languages)
    # The autoloader finds the grammars in `components/` beside `plugins/`.
    @test contains(read(last(prism[2]), String), "components/")

    vendorfiles()
    for file in ("prism/components/prism-core.min.js",
                 "prism/plugins/autoloader/prism-autoloader.min.js",
                 "prism/components/prism-julia.min.js")
        r = HTMXObjects.dispatch(:GET, "/vendor/$file?v=$(HTMXObjects._PRISM_VERSION)")
        @test r.status == 200
        @test HTTP.header(r, "Content-Type") == "text/javascript; charset=utf-8"
        @test r.body == read(Dict(prism)[file])
        @test HTTP.header(r, "Cache-Control") == "public, max-age=31536000, immutable"
    end

    mktempdir() do dir
        written = copy_vendorfiles(dir; packages=(:prism,), runtime=false)
        @test written == [joinpath(dir, split(f, '/')...) for f in first.(prism)]
        @test read(joinpath(dir, "prism", "components", "prism-stan.min.js")) ==
            read(Dict(prism)["prism/components/prism-stan.min.js"])
    end

    # A hand-built head gets the same template from vendor_head.
    head = repr("text/html", h.head(vendor_head("assets/vendor"; packages=(:prism, :htmx))...))
    @test head == "<head><script src=\"assets/vendor/htmx.min.js\"></script>" *
        "<template id=\"htmxo-prism\"><script src=\"assets/vendor/prism/components/prism-core.min.js\"></script>" *
        "<script src=\"assets/vendor/prism/plugins/autoloader/prism-autoloader.min.js\"></script></template></head>"
end

@testitem "syntax_styles meets WCAG AA on Pico's code background in both themes" tags=[:unit] begin
    using HTMXObjects
    css = HTMXObjects._syntax_css()
    # Pico 2.1.1's `--pico-code-background-color`, light and dark.
    backgrounds = (light=(243, 244.5, 246.75), dark=(26, 30.5, 40.25))
    channel(c) = (c /= 255; c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)^2.4)
    luminance((r, g, b)) = 0.2126channel(r) + 0.7152channel(g) + 0.0722channel(b)
    contrast(a, b) = ((lo, hi) = extrema((luminance(a), luminance(b))); (hi + 0.05) / (lo + 0.05))
    rgb(hex) = Tuple(parse(Int, hex[i:i+1]; base=16) for i in (1, 3, 5))
    colors(block) = Dict(m[1] => rgb(m[2]) for m in
        eachmatch(r"--htmxo-syntax-([a-z]+):\s*#([0-9a-fA-F]{6})", block))
    light = colors(match(r":root \{(.*?)\}"s, css)[1])
    dark = colors(match(r"html\.dark, \[data-theme=\"dark\"\] \{(.*?)\}"s, css)[1])
    @test length(light) == 7 && length(dark) == 7
    for (name, color) in light
        @test contrast(color, backgrounds.light) >= 4.5
    end
    for (name, color) in dark
        @test contrast(color, backgrounds.dark) >= 4.5
    end
    # The system's dark mode uses the same dark colors.
    system = colors(match(r"@media \(prefers-color-scheme: dark\) \{(.*?)\}\s*\}"s, css)[1])
    @test system == dark
    # The shell scopes them under `@layer htmxo`, without the file's comments.
    styles = HTMXObjects._runtime_text(:syntax_styles)
    @test startswith(styles, "@layer htmxo {") && !contains(styles, "/*")
end

@testitem "static export rewrites the PrismJS template and carries every grammar" setup=[SyntaxSiteFixture] tags=[:unit] begin
    using HTMXObjects
    page = htmx(SemanticCode(:julia, "x = 1"); assets=:vendor)
    based = repr("text/html", static_transform(page, StaticExport(; record_base="/site")))
    @test contains(based, "src=\"/site/vendor/prism/components/prism-core.min.js\"")
    @test contains(based, "src=\"/site/vendor/prism/plugins/autoloader/prism-autoloader.min.js\"")
    # The runtime goes back inline in a standalone export.
    linked = htmx(SemanticCode(:julia, "x = 1"); assets=:vendor, runtime=:linked)
    @test contains(repr("text/html", static_transform(linked)), HTMXObjects._runtime_text(:syntax_script))

    route!(SyntaxSiteApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    r = export_site(dir; pages=["/"])
    @test isfile(joinpath(dir, "vendor", "prism", "components", "prism-core.min.js"))
    @test isfile(joinpath(dir, "vendor", "prism", "plugins", "autoloader", "prism-autoloader.min.js"))
    # Every grammar the autoloader can fetch, at the address it fetches it by.
    for f in HTMXObjects._prism_languages()
        @test isfile(joinpath(dir, "vendor", "prism", "components", f))
    end
    index = read(joinpath(dir, "index.html"), String)
    @test contains(index, "src=\"vendor/prism/plugins/autoloader/prism-autoloader.min.js?v=")
end

@testitem "a browser highlights code on load and after a swap, fetching PrismJS only for code" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        served = Dict(f => read(p) for pkg in keys(HTMXObjects._VENDOR_ASSETS)
                      for (f, p) in HTMXObjects._vendor_files(pkg))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function () {
          const checks = [];
          const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
          const wait = (ok, then, n) => ok() || n <= 0 ? then() : setTimeout(() => wait(ok, then, n - 1), 50);
          const tokens = sel => document.querySelectorAll(sel + ' .token').length > 0;
          wait(() => tokens('#julia') && tokens('#stan') && tokens('#fence'), function () {
            const keyword = document.querySelector('#julia .token.keyword');
            check('julia', keyword && keyword.textContent === 'function');
            check('stan', document.querySelector('#stan .token'));
            check('fence', document.querySelector('#fence .token'));
            check('text-kept', document.querySelector('#julia code').textContent === 'function f(x)\n    x + 1 # one\nend');
            check('plain-untouched', document.querySelector('#plain code').children.length === 0);
            check('markup-kept', document.querySelector('#markup a') !== null);
            check('light-color', getComputedStyle(keyword).color === 'rgb(163, 53, 165)');
            document.documentElement.setAttribute('data-theme', 'dark');
            check('dark-color', getComputedStyle(keyword).color === 'rgb(198, 120, 221)');
            document.getElementById('more').click();
            wait(() => tokens('#target'), function () {
              check('swap', document.querySelector('#target .token'));
              const result = document.createElement('pre'); result.id = 'checks';
              result.textContent = checks.join('\n');
              document.body.appendChild(result);
            }, 100);
          }, 100);
        });
        """))
        button = h.button("more"; id="more", hx_get="/fragment", hx_target="#target")
        shell(content...; kw...) = htmx(content...; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION,
            hyperscript_version=nothing, feedback=false, compose=false, kw...)
        pages = Dict(
            "/" => shell(
                h.div(SemanticCode(:julia, "function f(x)\n    x + 1 # one\nend"); id="julia"),
                h.div(SemanticCode(:stan, "parameters { real mu; }"); id="stan"),
                h.div(SemanticProse("```python\nprint(1)\n```"); id="fence"),
                h.div(h.pre(h.code("no language")); id="plain"),
                h.div(h.pre(h.code(h.a("linked"; href="#x"); class="language-julia")); id="markup"),
                button, h.div(; id="target"), driver),
            "/plain" => shell(h.p("No code here.")),
            "/off" => shell(SemanticCode(:julia, "x = 1"); prism_version=nothing))
        fragment = SemanticCode(:toml, "[deps]\nHTTP = \"1\"")
        requests = String[]
        lock = ReentrantLock()
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            Base.@lock lock push!(requests, path)
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"],
                repr("text/html", pages[path]))
            path == "/fragment" && return HTTP.Response(200, ["Content-Type" => "text/html"],
                repr("text/html", fragment))
            file = replace(path, r"^/vendor/" => "")
            haskey(served, file) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => HTMXObjects._static_content_type(file)], served[file])
        end
        visit(path) = mktempdir() do profile
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=10000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
        end
        prism_fetched() = Base.@lock lock any(startswith("/vendor/prism/"), requests)
        try
            dom = visit("/")
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                @test length(lines) == 9
                for line in lines
                    @test endswith(line, ":true")
                end
            end
            # The grammars of the languages shown, from the vendor mount.
            fetched = Base.@lock lock copy(requests)
            for lang in ("julia", "stan", "python", "toml")
                @test "/vendor/prism/components/prism-$lang.min.js" in fetched
            end

            # A page without code fetches nothing of PrismJS.
            Base.@lock lock empty!(requests)
            plain = visit("/plain")
            @test contains(plain, "No code here.")
            @test !prism_fetched()

            # Without the template, code stays plain and nothing is fetched.
            Base.@lock lock empty!(requests)
            off = visit("/off")
            @test contains(off, "<code class=\"language-julia\">x = 1</code>")
            @test !prism_fetched()
        finally
            close(server)
        end
    end
end
