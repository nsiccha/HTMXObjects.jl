@testitem "the Pico bridge keeps text at 16 px and widens the container" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", pico_bridge())
    @test occursin(r":root \{[^}]*--pico-font-size: 100%;"s, css)
    @test occursin(r"@media \(min-width: 1280px\) \{\s*\.container \{\s*max-width: min\(var\(--htmxo-container-max-width, 1600px\),\s*calc\(100% - 2 \* var\(--htmxo-container-gutter, 2rem\)\)\);"s, css)
    # Pico's own rules have the same specificity, so the bridge must follow
    # Pico's stylesheet to win.
    page = repr("text/html", htmx(h.p("x"); pico_version="2"))
    pico = findfirst("pico.min.css", page)
    font = findfirst("--pico-font-size: 100%", page)
    @test !isnothing(pico) && !isnothing(font) && first(pico) < first(font)
    @test occursin("--pico-font-size: 100%", repr("text/html", HTMXObjects.pico_page(h.p("x"))))
    # A page without Pico carries no Pico rules.
    @test !occursin("--pico-font-size", repr("text/html", htmx(h.p("x"))))
end

@testitem "Pico pages keep 16 px text and fill wide windows in Chrome" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const main = document.querySelector('main.container');
            const box = main.getBoundingClientRect();
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = [document.documentElement.clientWidth,
                getComputedStyle(main.querySelector('p')).fontSize,
                Math.round(box.width), Math.round(box.left)].join(' ');
            document.body.appendChild(result);
        });
        """))
        shell(extra_head) = repr("text/html", htmx(h.main(; class="container")(h.p("Body text.")), driver;
            assets=:vendor, pico_version=HTMXObjects._PICO_VERSION, htmx_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false, extra_head))
        pages = Dict(
            "/" => shell(()),
            # An app's own stylesheet after the shell's still sets both.
            "/override" => shell((h.style(Raw(":root { --pico-font-size: 112.5%; " *
                "--htmxo-container-max-width: 1000px; }")),)),
            "/vendor/pico.min.css" => read(HTMXObjects._vendor_file(:pico), String),
        )
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) || return HTTP.Response(404)
            type = endswith(path, ".css") ? "text/css" : "text/html"
            HTTP.Response(200, ["Content-Type" => type], pages[path])
        end
        measure(path, width) = mktempdir() do profile
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=$width,900 --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? nothing : checks[1]
        end
        try
            # "<window> <text size> <container width> <left margin>". Pico alone
            # gives 19 px text at 1100 px, 20 px and a 1200 px container at
            # 1280 and 1400 px, and 21 px and 1450 px at 1600 and 1920 px.
            @test measure("/", 375) == "375 16px 375 0"
            @test measure("/", 1100) == "1100 16px 950 75"
            @test measure("/", 1280) == "1280 16px 1216 32"
            @test measure("/", 1400) == "1400 16px 1336 32"
            @test measure("/", 1600) == "1600 16px 1536 32"
            @test measure("/", 1920) == "1920 16px 1600 160"
            @test measure("/override", 1400) == "1400 18px 1000 200"
        finally
            close(server)
        end
    end
end

@testitem "the Pico bridge gives unstyled buttons Pico's slate outline" tags=[:unit] begin
    using HTMXObjects
    css = repr("text/html", pico_bridge())
    plain = ":is(button, [type=submit], [type=button], [role=button]):not(.secondary, .contrast)"
    @test occursin(plain * " {\n    --pico-background-color: transparent;\n    --pico-color: var(--pico-secondary);\n    --pico-border-color: var(--pico-secondary);", css)
    @test occursin("--pico-color: var(--pico-secondary-hover);", css)
    @test occursin("var(--pico-secondary-focus);", css)
    # Pico reads these three variables on the button itself, so the bridge
    # sets them there; it never reads them, which would see Pico's rewrite.
    @test !occursin("var(--pico-background-color)", replace(css, "var(--pico-background-color, Canvas)" => ""))
    @test !occursin(r"[^-]var\(--pico-color\)", css)
    # With no azure fill, the active tab of `htmx_tabset` is told apart by
    # Pico's contrast outline, as `nav_sidebar` marks its active item.
    tabs = repr("text/html", htmx_tabset(["A" => "/a", "B" => "/b"]; active="A"))
    @test occursin("class=\"contrast outline btn-xs\"", tabs)
    @test occursin("class=\"secondary outline btn-xs\"", tabs)
end

@testitem "Pico buttons without a colour class look like Pico's secondary outline in Chrome" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        ids = ["plain", "submit", "link", "outline", "busy", "secout", "secondary", "contrast"]
        # Headless Chrome applies no :hover or :focus, so the page and Pico's
        # stylesheet name those states as attributes of the same specificity
        # (`[data-focus]` for `:focus`), and transitions are off so the read
        # sees the settled state. An attribute may not follow a pseudo-element,
        # so Pico's file-input button (not under test) is renamed first: a
        # `::file-selector-button[data-focus]` would void each whole rule it
        # sits in, Pico's focus rings included.
        states(css) = foldl((s, st) -> replace(s, Regex(":$st(?![-\\w])") => "[data-$st]"),
            ("hover", "focus", "active");
            init=replace(css, "[type=file]::file-selector-button" => "[data-htmxo-unmatched]"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const ids = ['plain', 'submit', 'link', 'outline', 'busy', 'secout', 'secondary', 'contrast'];
            const look = (id) => { const c = getComputedStyle(document.getElementById(id));
                return [c.backgroundColor, c.color, c.borderTopColor, c.boxShadow].join(' / '); };
            const out = ids.map(id => id + ' rest: ' + look(id));
            for (const id of ids) {
                const e = document.getElementById(id);
                e.setAttribute('data-focus', ''); out.push(id + ' focus: ' + look(id)); e.removeAttribute('data-focus');
            }
            document.getElementById('gbtn').setAttribute('data-focus', '');
            out.push('group focus: ' + getComputedStyle(document.getElementById('group')).boxShadow);
            out.push('busy spinner: ' + getComputedStyle(document.getElementById('busy'), '::before').filter);
            out.push('summary chevron: ' + getComputedStyle(document.getElementById('summary'), '::after').filter);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = out.join('\n');
            document.body.appendChild(result);
        });
        """))
        content = h.main(; class="container")(
            h.button("Plain"; id="plain"), h.input(; type="submit", value="Submit", id="submit"),
            h.a("Link"; href="#", role="button", id="link"), h.button("Outline"; class="outline", id="outline"),
            h.button("Busy"; aria_busy="true", id="busy"),
            h.button("Secondary outline"; class="secondary outline", id="secout"),
            h.button("Secondary"; class="secondary", id="secondary"), h.button("Contrast"; class="contrast", id="contrast"),
            h.details(; class="dropdown")(h.summary("Menu"; role="button", id="summary"), h.ul(h.li("a"))),
            h.fieldset(; role="group", id="group")(h.input(; name="q"), h.button("Go"; id="gbtn")))
        page = repr("text/html", htmx(content, driver; assets=:vendor, pico_version=HTMXObjects._PICO_VERSION,
            htmx_version=nothing, hyperscript_version=nothing, feedback=false, compose=false, overlay=false,
            extra_head=(h.style(Raw("*, *::before, *::after { transition: none !important; }")),)))
        pages = Dict(
            "/light" => states(page),
            "/dark" => replace(states(page), "<html" => "<html data-theme=\"dark\""; count=1),
            "/vendor/pico.min.css" => states(read(HTMXObjects._vendor_file(:pico), String)),
        )
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => endswith(path, ".css") ? "text/css" : "text/html"], pages[path])
        end
        measure(path) = mktempdir() do profile
            dom = dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port$path`)
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            isnothing(checks) ? Dict{String,String}() :
                Dict(String(k) => String(v) for (k, v) in (split(l, ": "; limit=2) for l in split(checks[1], '\n')))
        end
        azure = "rgb(1, 114, 173)"
        try
            for path in ("/light", "/dark")
                looks = measure(path)
                @test length(looks) == 2 * length(ids) + 3
                for id in ("plain", "submit", "link", "outline", "busy"), state in ("rest", "focus")
                    @test get(looks, "$id $state", "") == looks["secout $state"]
                end
                for id in ids, state in ("rest", "focus")
                    @test !occursin(azure, get(looks, "$id $state", azure))
                end
                @test startswith(looks["plain rest"], "rgba(0, 0, 0, 0) / ")
                @test looks["plain focus"] != looks["plain rest"]
                @test occursin("rgb(82, 95, 122) / rgb(255, 255, 255)", looks["secondary rest"])
                @test looks["contrast rest"] != looks["plain rest"]
                @test !occursin("rgba(2, 154, 232", looks["group focus"]) && occursin("0px 0px 0px 2px", looks["group focus"])
                @test looks["busy spinner"] == "none"
                @test looks["summary chevron"] == "none"
            end
        finally
            close(server)
        end
    end
end
