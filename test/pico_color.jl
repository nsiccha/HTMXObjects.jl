using TestItemRunner

# Snag dbsvergleich-tod-35acaead (reporter DBSVergleich): an app that wanted
# another accent than Pico's azure redeclared Pico's `--pico-primary*`
# variables for light, dark and `[data-theme=dark]` in `extra_head` (40 lines),
# because the shell only ever loaded `css/pico.min.css`. Its copy missed
# `--pico-text-selection-color`. `pico_color` loads Pico's own colour build.

@testitem "pico_color names exactly the colour builds of the vendored Pico" tags=[:unit] begin
    using HTMXObjects
    dir = dirname(HTMXObjects._vendor_file(:pico))
    primary(file) = let m = match(r"--pico-primary:\s*([^;]+);", read(joinpath(dir, file), String))
        isnothing(m) ? nothing : m.captures[1]
    end
    azure = primary("pico.min.css")
    @test azure == "#0172ad"
    # A colour build is a `pico.<name>.min.css` with its own primary colour; the
    # layout variants (`classless`, `conditional`) keep azure, and the
    # `colors` utility sheet has none.
    builds = Set(m.captures[1] for m in (match(r"^pico\.([a-z]+)\.min\.css$", f) for f in readdir(dir))
                 if !isnothing(m) && primary(m.match) ∉ (nothing, azure))
    @test "classless" ∉ builds && "cyan" in builds
    @test length(HTMXObjects._PICO_COLORS) == 20
    # Azure is Pico's default build, `pico.min.css`; every other name has its file.
    @test Set(string.(HTMXObjects._PICO_COLORS)) == union(builds, Set(["azure"]))
    @test isfile(joinpath(dir, "pico.min.css")) && !isfile(joinpath(dir, "pico.azure.min.css"))
end

@testitem "pico_color loads Pico's colour build from the CDN and the vendor mount" tags=[:unit] begin
    using HTMXObjects
    page(x) = repr("text/html", x)
    pin = HTMXObjects._PICO_VERSION
    cyan = page(HTMXObjects.pico_page(h.p("x"); pico_color=:cyan))
    @test contains(cyan, "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.cyan.min.css\">")
    @test !contains(cyan, "pico.min.css")
    # Everything else on the page is unchanged: the bridge still follows Pico.
    @test replace(cyan, "pico.cyan.min.css" => "pico.min.css") == page(HTMXObjects.pico_page(h.p("x")))
    @test contains(page(htmx(h.p("x"); pico_version="2.1.1", pico_color=:jade)),
        "https://cdn.jsdelivr.net/npm/@picocss/pico@2.1.1/css/pico.jade.min.css")
    # A string names the same build.
    @test page(HTMXObjects.pico_page(h.p("x"); pico_color="cyan")) == cyan
    # Azure is Pico's default build, and leaving the keyword out keeps the page as it was.
    @test page(HTMXObjects.pico_page(h.p("x"); pico_color=:azure)) == page(HTMXObjects.pico_page(h.p("x")))
    @test page(htmx(h.p("x"); pico_version="2", pico_color=nothing)) == page(htmx(h.p("x"); pico_version="2"))
    # Vendor assets serve the build of the pinned release.
    @test contains(page(HTMXObjects.pico_page(h.p("x"); assets=:vendor, pico_color=:cyan)),
        "<link rel=\"stylesheet\" href=\"/vendor/pico.cyan.min.css\">")
    @test contains(page(HTMXObjects.pico_page(h.p("x"); assets="assets/vendor", runtime=:linked, pico_color=:cyan)),
        "href=\"assets/vendor/pico.cyan.min.css?v=$pin\"")
    # refused: a name Pico has no build for would load a stylesheet that 404s,
    # leaving the page unstyled (dev: no silent fallback)
    @test_throws ArgumentError HTMXObjects.pico_page(h.p("x"); pico_color=:petrol)
    @test_throws ArgumentError HTMXObjects.pico_page(h.p("x"); pico_color=1)
    # refused: a colour for a page without Pico would change nothing
    @test_throws ArgumentError htmx(h.p("x"); pico_color=:cyan)
end

@testitem "the vendor mount and copy_vendorfiles carry every Pico colour build" tags=[:unit] begin
    using HTMXObjects
    files = HTMXObjects._vendor_files(:pico)
    dir = dirname(HTMXObjects._vendor_file(:pico))
    # The default build first, then one file per other colour, each the artifact's own bytes.
    @test first(files) == ("pico.min.css" => HTMXObjects._vendor_file(:pico))
    @test length(files) == length(HTMXObjects._PICO_COLORS)
    @test Dict(files)["pico.cyan.min.css"] == joinpath(dir, "pico.cyan.min.css")
    @test all(isfile, last.(files))
    mktempdir() do target
        written = copy_vendorfiles(target; packages=(:pico,), runtime=false)
        @test basename.(written) == first.(files)
        @test read(joinpath(target, "pico.cyan.min.css")) == read(joinpath(dir, "pico.cyan.min.css"))
    end
end

@testitem "pico_color gives Pico's own accent in light and dark, buttons stay neutral" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    import HTMXObjects: Raw
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const root = document.documentElement, out = [];
            const read = () => {
                const css = getComputedStyle(root), probe = document.getElementById('accent');
                return [css.getPropertyValue('--pico-primary').trim(),
                        css.getPropertyValue('--pico-text-selection-color').trim(),
                        getComputedStyle(document.getElementById('link')).color,
                        getComputedStyle(probe).color,
                        getComputedStyle(document.getElementById('button')).backgroundColor].join('|');
            };
            out.push('system dark: ' + matchMedia('(prefers-color-scheme: dark)').matches);
            out.push('system: ' + read());
            root.dataset.theme = 'light'; out.push('light: ' + read());
            root.dataset.theme = 'dark'; out.push('dark: ' + read());
            const result = document.createElement('pre'); result.id = 'checks'; result.textContent = out.join('\n');
            document.body.appendChild(result);
        });
        """))
        content = h.div(h.p(h.a("A link"; href="#", id="link")),
            h.p(h.span("Accent"; id="accent", class="htmxo-accent-probe")),
            h.button("A button"; id="button"), driver)
        probe = h.style(Raw(".htmxo-accent-probe { color: var(--htmxo-accent); } " *
                            "*, *::before, *::after { transition: none !important; }"))
        checks(color, scheme) = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"); packages=(:pico,))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", HTMXObjects.pico_page(content; assets="vendor", pico_color=color,
                htmx_version=nothing, hyperscript_version=nothing, preload_version=nothing, extra_head=(probe,))))
            profile = joinpath(directory, "profile")
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1200,800 --virtual-time-budget=2000 --blink-settings=preferredColorScheme=$scheme --dump-dom --user-data-dir=$profile file://$fixture`)
            Dict(Pair(split(line, ": "; limit=2)...) for line in
                eachsplit(something(match(r"<pre id=\"checks\">(.*?)</pre>"s, dom), (; captures=[""])).captures[1], '\n')
                if contains(line, ": "))
        end
        field(c, key, i) = split(c[key], '|')[i]
        # preferredColorScheme: 1 is light, 0 dark.
        cyan, cyan_dark, azure = checks(:cyan, 1), checks(:cyan, 0), checks(nothing, 1)
        @test cyan["system dark"] == "false" && cyan_dark["system dark"] == "true"
        # Pico's cyan build, light and dark: by system setting and by `data-theme`.
        light = ("#047878", "rgba(5, 162, 162, 0.25)", "rgb(4, 120, 120)")
        dark = ("#0ab1b1", "rgba(10, 177, 177, 0.1875)", "rgb(10, 177, 177)")
        for (c, key, (primary, selection, link)) in ((cyan, "system", light), (cyan, "light", light),
                (cyan, "dark", dark), (cyan_dark, "system", dark), (cyan_dark, "light", light))
            @test (key, field(c, key, 1)) == (key, primary)
            # Text selection is part of the build too (the app's copy had missed it).
            @test (key, field(c, key, 2)) == (key, selection)
            # Links and HTMXObjects' accent follow it.
            @test (key, field(c, key, 3), field(c, key, 4)) == (key, link, link)
        end
        # Positive control: the default page is Pico's azure.
        @test field(azure, "light", 1) == "#0172ad" && field(azure, "dark", 1) == "#01aaff"
        @test field(azure, "light", 2) == "rgba(2, 154, 232, 0.25)"
        # The bridge's neutral button is the same on both builds: no cyan fill.
        for key in ("light", "dark")
            @test (key, field(cyan, key, 5)) == (key, field(azure, key, 5))
            @test field(cyan, key, 5) != "rgb(4, 120, 120)" && field(cyan, key, 5) != "rgb(10, 177, 177)"
        end
    end
end
