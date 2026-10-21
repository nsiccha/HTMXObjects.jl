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
