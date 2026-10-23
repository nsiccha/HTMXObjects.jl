using TestItemRunner

# TeX math in Markdown: `render_markdown` marks each formula, the shell's
# `math_script` typesets it with KaTeX, which it loads on demand from the
# `katex_version` template (CDN or the vendor mount).

@testitem "render_markdown marks TeX math and keeps money as text" tags=[:unit] begin
    using HTMXObjects
    html(md; kw...) = repr("text/html", render_markdown(md; kw...))
    inline(tex) = "<span class=\"htmxo-math\" data-htmxo-math=\"inline\">$tex</span>"
    display(tex) = "<span class=\"htmxo-math htmxo-math-display\" data-htmxo-math=\"display\">$tex</span>"
    block(tex) = "<div class=\"htmxo-math htmxo-math-display\" data-htmxo-math=\"display\">$tex</div>"

    # The TeX is kept byte for byte: CommonMark's escapes would turn `\_` into
    # `_` and `\\` into `\` (BRM writes `log\_theta`).
    @test html(raw"rate $\log\_\theta = a\_b$ here") ==
        "<div><p>rate " * inline(raw"\log\_\theta = a\_b") * " here</p></div>"
    @test html(raw"a $$x\\y$$ b") == "<div><p>a " * display(raw"x\\y") * " b</p></div>"
    @test html(raw"LaTeX \(a+b\) and \[c\]") ==
        "<div><p>LaTeX " * inline("a+b") * " and " * display("c") * "</p></div>"
    @test html(raw"$\alpha_1$, $x$ and $a$ $b$") ==
        "<div><p>" * inline(raw"\alpha_1") * ", " * inline("x") * " and " *
        inline("a") * " " * inline("b") * "</p></div>"

    # A paragraph that is one display formula, and a math fence, are blocks.
    @test html("Before\n\n\$\$\n\\sigma \\sim \\mathrm{N}(0, 1)\n\$\$\n\nafter") ==
        "<div><p>Before</p>" * block(raw"\sigma \sim \mathrm{N}(0, 1)") * "<p>after</p></div>"
    @test html("\\[\n\\int_0^1 f\n\\]") == "<div>" * block(raw"\int_0^1 f") * "</div>"
    @test html("```math\nE = mc^2\n```") == "<div>" * block("E = mc^2") * "</div>"
    # Two formulas in one paragraph stay inline.
    @test html(raw"$$a$$ and $$b$$") == "<div><p>" * display("a") * " and " * display("b") * "</p></div>"

    # Pandoc's dollar rules keep money and stray dollars as text.
    for text in (raw"costs $5 and $10.", raw"$1,234.00/$56.00", raw"from $ 5 to $ 7",
                 raw"a $ b", raw"US$5 and US$10", raw"just $$ here", raw"price: \$5")
        @test html(text) == "<div><p>" * replace(text, "\\\$" => "\$") * "</p></div>"
    end
    @test html(raw"x $5 (see `y$`) z") == "<div><p>x \$5 (see <code>y\$</code>) z</p></div>"
    # Code spans and fences never become math, and a lone `\(` is an escape.
    @test html(raw"`$x$` and \( alone") == "<div><p><code>\$x\$</code> and ( alone</p></div>"
    @test html("```\n\$x\$ \\(y\\)\n```") == "<div><pre><code>\$x\$ \\(y\\)\n</code></pre></div>"

    # Math is HTML-escaped once, never markup, and the URL rule never runs in it.
    @test html(raw"$a<b \text{https://x.y}$") ==
        "<div><p>" * inline(raw"a&lt;b \text{https://x.y}") * "</p></div>"

    # Table cells, lists and emphasis carry math too.
    @test contains(html("| a | b |\n|---|---|\n| \$\\sigma\$ | \$|x|\$ |"),
        "<td style=\"text-align: left\">" * inline("|x|") * "</td>")
    @test html(raw"- *$x$* item") == "<div><ul><li><em>" * inline("x") * "</em> item</li></ul></div>"

    # `math=false` parses no math, exactly as before.
    @test html(raw"$x$ and \(y\)"; math=false) == "<div><p>\$x\$ and (y)</p></div>"
    @test html(raw"a\_b $x$"; math=false) == "<div><p>a_b \$x\$</p></div>"
    # The parser alone, for the AST entry point.
    @test any(n.t isa HTMXObjects.CommonMark.Math for (n, entering) in markdown_parser()(raw"$x$"))
    @test !any(n.t isa HTMXObjects.CommonMark.Math for (n, entering) in markdown_parser(; math=false)(raw"$x$"))
end

@testitem "math projects back to dollar Markdown" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    md(text; kw...) = to_markdown_string(render_markdown(text; kw...))

    @test md(raw"rate $\log\_\theta$ and $$x\\y$$ here") ==
        "rate \$\\log\\_\\theta\$ and \$\$x\\\\y\$\$ here\n\n"
    # LaTeX delimiters come back as dollars, which pandoc and Quarto read.
    @test md(raw"LaTeX \(a+b\) and \[c\]") == "LaTeX \$a+b\$ and \$\$c\$\$\n\n"
    # A display block is its own paragraph.
    @test md("Before\n\n\$\$\n\\sigma\n\$\$\n\nafter") == "Before\n\n\$\$\n\\sigma\n\$\$\n\nafter\n\n"
    @test md("```math\nE\n```") == "\$\$\nE\n\$\$"
    # Money stays as written.
    @test md(raw"costs $5 and $10.") == "costs \$5 and \$10.\n\n"
    # A table cell keeps its math on one row, with the cell's own `|` escape.
    @test md("| a |\n|---|\n| \$|x|\$ |") == "| a |\n| --- |\n| \$\\|x\\|\$ |\n\n"

    # The projection round-trips through the parser: same formulas again.
    for text in (raw"$\alpha$ and $$\beta$$", "\$\$\n\\gamma\n\$\$")
        @test repr("text/html", render_markdown(md(text))) == repr("text/html", render_markdown(text))
    end

    # SemanticProse projects its source, and typesets unless `math=false`.
    prose = SemanticProse(raw"Prose $x^2$")
    @test to_markdown_string(prose) == raw"Prose $x^2$"
    @test contains(repr("text/html", prose), "<span class=\"htmxo-math\" data-htmxo-math=\"inline\">x^2</span>")
    plain = SemanticProse(raw"Prose $x^2$"; math=false)
    @test !contains(repr("text/html", plain), "htmxo-math")
    @test to_markdown_string(plain) == raw"Prose $x^2$"
    @test SemanticProse("x").math && !plain.math
end

@testitem "the shell names KaTeX for the math runtime" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: _runtime_text
    page(; kw...) = repr("text/html", htmx(h.p("x"); kw...))
    template(s) = (m = match(r"<template id=\"htmxo-katex\">(.*?)</template>"s, s); isnothing(m) ? nothing : m[1])
    files(dir, q="") = "<link rel=\"stylesheet\" href=\"$dir/katex.min.css$q\">" *
        "<script src=\"$dir/katex.min.js$q\"></script>"

    # The template is inert; the runtime adds its files once the page shows math.
    cdn = "https://cdn.jsdelivr.net/npm/katex@$(HTMXObjects._KATEX_VERSION)/dist"
    @test template(page()) == files(cdn)
    @test template(page(; assets=:vendor)) == files("/vendor/katex")
    @test template(page(; assets="assets/vendor")) == files("assets/vendor/katex")
    @test template(page(; assets=:vendor, runtime=:linked)) ==
        files("/vendor/katex", "?v=$(HTMXObjects._KATEX_VERSION)")
    @test template(page(; katex_version="0.16.21")) == files("https://cdn.jsdelivr.net/npm/katex@0.16.21/dist")
    @test isnothing(template(page(; katex_version=nothing)))
    # Vendor mode serves KaTeX only at its pin.
    err = try
        page(; assets=:vendor, katex_version="0.16.21"); nothing
    catch e
        sprint(showerror, e)
    end
    @test contains(err, "vendored katex is pinned at $(HTMXObjects._KATEX_VERSION)")

    # Every shell carries the runtime, inline or linked; it is inert without math.
    for kw in ((;), (; katex_version=nothing))
        s = page(; kw...)
        @test contains(s, _runtime_text(:math_script)) && contains(s, _runtime_text(:math_styles))
    end
    linked = page(; assets=:vendor, runtime=:linked)
    @test contains(linked, "data-htmxo-runtime=\"math_script\"") &&
        contains(linked, "data-htmxo-runtime=\"math_styles\"")
    @test math_script() isa Node && math_styles() isa Node

    # The page's Markdown leaves the template and runtime out.
    @test !contains(HTMXObjects.to_markdown_string(htmx(h.p("x"))), "katex")
end

@testitem "KaTeX is vendored as a directory" tags=[:unit] begin
    using HTMXObjects, HTTP
    import HTMXObjects: _vendor_files
    katex = _vendor_files(:katex)
    @test first.(katex[1:2]) == ["katex/katex.min.css", "katex/katex.min.js"]
    fonts = first.(katex[3:end])
    @test length(fonts) == 60 && all(startswith("katex/fonts/KaTeX_"), fonts)
    @test "katex/fonts/KaTeX_Main-Regular.woff2" in fonts
    # The stylesheet finds the fonts beside it.
    @test contains(read(last(katex[1]), String), "url(fonts/KaTeX_Main-Regular.woff2)")

    vendorfiles()
    for (file, type) in ("katex/katex.min.css" => "text/css; charset=utf-8",
                         "katex/katex.min.js" => "text/javascript; charset=utf-8",
                         "katex/fonts/KaTeX_Main-Regular.woff2" => "font/woff2")
        r = HTMXObjects.dispatch(:GET, "/vendor/$file?v=$(HTMXObjects._KATEX_VERSION)")
        @test r.status == 200
        @test HTTP.header(r, "Content-Type") == type
        @test r.body == read(Dict(katex)[file])
        @test HTTP.header(r, "Cache-Control") == "public, max-age=31536000, immutable"
    end

    mktempdir() do dir
        written = copy_vendorfiles(dir; packages=(:katex,), runtime=false)
        @test written == [joinpath(dir, split(f, '/')...) for f in first.(katex)]
        @test read(joinpath(dir, "katex", "fonts", "KaTeX_Main-Regular.woff2")) ==
            read(Dict(katex)["katex/fonts/KaTeX_Main-Regular.woff2"])
    end

    # A hand-built head gets the same template from vendor_head.
    head = repr("text/html", h.head(vendor_head("assets/vendor"; packages=(:katex, :htmx))...))
    @test head == "<head><script src=\"assets/vendor/htmx.min.js\"></script>" *
        "<template id=\"htmxo-katex\"><link rel=\"stylesheet\" href=\"assets/vendor/katex/katex.min.css\">" *
        "<script src=\"assets/vendor/katex/katex.min.js\"></script></template></head>"
end

@testitem "static export rewrites the KaTeX template like any address" tags=[:unit] begin
    using HTMXObjects
    page = htmx(SemanticProse(raw"$x$"); assets=:vendor)
    based = repr("text/html", static_transform(page, StaticExport(; record_base="/site")))
    @test contains(based, "href=\"/site/vendor/katex/katex.min.css\"")
    @test contains(based, "src=\"/site/vendor/katex/katex.min.js\"")
    @test contains(based, "<span class=\"htmxo-math\" data-htmxo-math=\"inline\">x</span>")
    to_bundle(url) = startswith(url, "/vendor/") ? "assets" * url : nothing
    mapped = repr("text/html", static_transform(page, StaticExport(; url_map=to_bundle)))
    @test contains(mapped, "href=\"assets/vendor/katex/katex.min.css\"")
    # The runtime goes back inline in a standalone export.
    linked = htmx(SemanticProse(raw"$x$"); assets=:vendor, runtime=:linked)
    exported = repr("text/html", static_transform(linked))
    @test contains(exported, HTMXObjects._runtime_text(:math_script))
end

@testitem "a browser typesets math on load and after a swap, fetching KaTeX only for math" setup=[ChromeDump] tags=[:browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        served = Dict(f => read(p) for pkg in keys(HTMXObjects._VENDOR_ASSETS)
                      for (f, p) in HTMXObjects._vendor_files(pkg))
        prose = SemanticProse("""
            The scale \$\\log\\_\\sigma\$ costs \$5 and \$10; `\$code\$` stays.

            \$\$
            y_i \\sim \\mathrm{Normal}\\left(\\mu_i, \\sigma\\right)
            \$\$
            """)
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function () {
          const checks = [];
          const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
          const done = () => document.querySelectorAll('.htmxo-math[data-htmxo-math-done]').length;
          const wait = (ok, then, n) => ok() || n <= 0 ? then() : setTimeout(() => wait(ok, then, n - 1), 50);
          // A face that really loaded: `document.fonts.check` is also true
          // when no face matches at all.
          const font = () => Array.from(document.fonts).some(f =>
            f.family.replace(/["']/g, '') === 'KaTeX_Main' && f.status === 'loaded');
          wait(() => done() === 2 && font(), function () {
            const inline = document.querySelector('[data-htmxo-math="inline"]');
            const block = document.querySelector('div[data-htmxo-math="display"]');
            check('inline-typeset', inline.querySelector('.katex') && !inline.querySelector('.katex-display'));
            check('inline-source-kept', inline.getAttribute('data-htmxo-tex') === '\\log\\_\\sigma');
            check('display-typeset', block.querySelector('.katex-display'));
            check('money-text', document.body.textContent.includes('costs $5 and $10'));
            check('code-literal', document.querySelector('code').textContent === '$code$');
            check('stylesheet', document.querySelector('link[href="/vendor/katex/katex.min.css"]'));
            check('font', font());
            document.getElementById('more').click();
            wait(() => done() === 3, function () {
              check('swap-typeset', document.querySelector('#target .katex'));
              const result = document.createElement('pre'); result.id = 'checks';
              result.textContent = checks.join('\n');
              document.body.appendChild(result);
            }, 100);
          }, 100);
        });
        """))
        button = h.button("more"; id="more", hx_get="/fragment", hx_target="#target")
        pages = Dict(
            "/" => htmx(prose, button, h.div(; id="target"), driver; assets=:vendor,
                hyperscript_version=nothing, feedback=false, compose=false),
            "/plain" => htmx(h.p("No formulas, \$5."); assets=:vendor,
                hyperscript_version=nothing, feedback=false, compose=false),
            "/source" => htmx(SemanticProse(raw"Only $x^2$."); assets=:vendor, katex_version=nothing,
                hyperscript_version=nothing, feedback=false, compose=false))
        fragment = render_markdown(raw"Swapped in: $\frac{a}{b}$")
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
        katex_fetched() = Base.@lock lock any(startswith("/vendor/katex/"), requests)
        try
            dom = visit("/")
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                @test length(lines) == 8
                for line in lines
                    @test endswith(line, ":true")
                end
            end
            @test katex_fetched()
            @test Base.@lock lock any(endswith(".woff2"), requests)

            # A page without math fetches nothing of KaTeX.
            Base.@lock lock empty!(requests)
            plain = visit("/plain")
            @test contains(plain, "No formulas, \$5.")
            @test !katex_fetched()

            # Without the template, math shows its source and nothing is fetched.
            Base.@lock lock empty!(requests)
            source = visit("/source")
            @test contains(source, "<span class=\"htmxo-math\" data-htmxo-math=\"inline\">x^2</span>")
            @test !contains(source, "class=\"katex\"")
            @test !katex_fetched()
        finally
            close(server)
        end
    end
end
