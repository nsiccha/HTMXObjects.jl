@testitem "pico_page draws a site frame: header, nav, skip link, main and footer" tags=[:unit] begin
    using HTMXObjects
    page(x) = repr("text/html", x)
    body(x) = match(r"<body>(.*)</body>"s, page(x))[1]
    # Without a brand or nav the page is the old shorthand, byte for byte.
    @test page(HTMXObjects.pico_page(h.p("x"))) ==
        page(htmx(h.main(class="container")(h.p("x")); pico_version="2"))
    @test page(HTMXObjects.pico_page(h.p("x"); class="container-fluid", title="T")) ==
        page(htmx(h.main(class="container-fluid")(h.p("x")); pico_version="2", title="T"))

    framed = body(HTMXObjects.pico_page(h.p("x"); brand="Atlas" => "/",
        nav=["Karte" => "/", "Methodik" => "/modell", h.li(h.a("Extern"; href="https://example.org/"))],
        footer=h.small("Datenbasis")))
    @test framed == string(
        "<a href=\"#main\" class=\"htmxo-skip-link\">Skip to content</a>",
        "<header class=\"container\"><nav aria-label=\"Main navigation\">",
        "<ul><li><a href=\"/\"><strong>Atlas</strong></a></li></ul>",
        "<ul><li><a href=\"/\">Karte</a></li><li><a href=\"/modell\">Methodik</a></li>",
        "<li><a href=\"https://example.org/\">Extern</a></li></ul></nav></header>",
        "<main class=\"container\" id=\"main\"><p>x</p></main>",
        "<footer class=\"container\"><small>Datenbasis</small></footer>")

    # A brand alone is a header too; an element brand is placed as it is.
    @test contains(body(HTMXObjects.pico_page(h.p("x"); brand=h.a(h.img(src="/logo.svg", alt="Atlas"); href="/"))),
        "<nav aria-label=\"Main navigation\"><ul><li><a href=\"/\"><img src=\"/logo.svg\" alt=\"Atlas\"></a></li></ul></nav>")
    # A footer that is an h.footer is placed as it is; a class reaches every part.
    fluid = body(HTMXObjects.pico_page(h.p("x"); nav=["A" => "/a"], class="container-fluid",
        footer=h.footer(class="container app-footer")("F")))
    @test contains(fluid, "<header class=\"container-fluid\">")
    @test contains(fluid, "<main class=\"container-fluid\" id=\"main\">")
    @test endswith(fluid, "<footer class=\"container app-footer\">F</footer>")
    # A footer alone adds no header and no skip link.
    @test body(HTMXObjects.pico_page(h.p("x"); footer="F")) ==
        "<main class=\"container\"><p>x</p></main><footer class=\"container\">F</footer>"

    # The words follow the page's language; nav_label and a skip link text win.
    german = body(HTMXObjects.pico_page(h.p("x"); nav=["A" => "/a"], lang="de"))
    @test startswith(german, "<a href=\"#main\" class=\"htmxo-skip-link\">Zum Inhalt springen</a>")
    @test contains(german, "<nav aria-label=\"Hauptnavigation\">")
    own = body(HTMXObjects.pico_page(h.p("x"); nav=["A" => "/a"], nav_label="Sections", skip_link="Jump"))
    @test startswith(own, "<a href=\"#main\" class=\"htmxo-skip-link\">Jump</a>")
    @test contains(own, "<nav aria-label=\"Sections\">")
    no_skip = body(HTMXObjects.pico_page(h.p("x"); nav=["A" => "/a"], skip_link=false))
    @test startswith(no_skip, "<header") && contains(no_skip, "<main class=\"container\"><p>x</p></main>")

    # Outside a request no entry is marked.
    @test !contains(framed, "aria-current")
    # The shell's styles hide the skip link until it has focus and mark the
    # current entry.
    css = page(htmxo_utility_styles())
    @test contains(css, ".htmxo-skip-link:not(:focus, :focus-visible)")
    @test contains(css, "body > header nav a[aria-current=\"page\"] { font-weight: 600; }")
end

@testitem "pico_page takes Pico's pin under vendor assets and forwards htmx's keywords" tags=[:unit] begin
    using HTMXObjects
    page(x) = repr("text/html", x)
    pin = HTMXObjects._PICO_VERSION
    @test contains(page(HTMXObjects.pico_page(h.p("x"))), "https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css")
    @test contains(page(HTMXObjects.pico_page(h.p("x"); assets=:vendor)), "<link rel=\"stylesheet\" href=\"/vendor/pico.min.css\">")
    @test contains(page(HTMXObjects.pico_page(h.p("x"); assets="assets/vendor", runtime=:linked)),
        "href=\"assets/vendor/pico.min.css?v=$pin\"")
    # refused: vendor assets serve Pico only at its pin (no silent CDN fallback, dev §1)
    @test_throws ErrorException HTMXObjects.pico_page(h.p("x"); assets=:vendor, pico_version="2")
    # Every other keyword is htmx's.
    @test !contains(page(HTMXObjects.pico_page(h.p("x"); prism_version=nothing)), "<template id=\"htmxo-prism\">")
    @test page(HTMXObjects.pico_page(h.p("x"); extra_head=(h.meta(name="robots", content="noindex"),), tables=false)) ==
        page(htmx(h.main(class="container")(h.p("x")); pico_version="2",
            extra_head=(h.meta(name="robots", content="noindex"),), tables=false))
    @test_throws MethodError HTMXObjects.pico_page(h.p("x"); no_such_keyword=1)
end

@testitem "pico_page marks the nav entry of the page being read" tags=[:integration, :server] begin
    using HTMXObjects
    @htmx struct SiteFrameApp
        __lang__ = "de"
        __page__(content) = let base = __prefix__
            HTMXObjects.pico_page(content; brand="Atlas" => base * "/",
                nav=["Karte" => base * "/", "PLZ" => base * "/plz", "PLZ-Liste" => base * "/plz/liste",
                     "Glossar" => base * "/glossar?suche=", "Abschnitt" => base * "/#karte",
                     "München" => base * "/plz/karte/München",
                     private("Angebot" => base * "/angebot"; public=h.li("Angebot folgt"))])
        end
        @get index() = h.p("Start")
        @include plz = begin
            @get index() = h.p("PLZ")
            @get liste() = h.p("Liste")
            @get karte(code::String) = h.p(code)
        end
        @get glossar() = h.p("Glossar")
        @get angebot() = h.p("Angebot")
        @get impressum() = h.p("Impressum")
    end
    route!(SiteFrameApp())
    # A dispatch outside a request answers for the public; the live app shows
    # private content.
    page(path; headers=[], audience=:private) =
        String(dispatch(:GET, path; headers=["Accept" => "text/html", headers...], audience).body)
    current(html) = [m[1] for m in eachmatch(r"<a href=\"[^\"]*\" aria-current=\"page\">([^<]*)</a>", html)]
    @test current(page("/")) == ["Karte"]
    @test current(page("/plz")) == ["PLZ"]
    # Below an entry, the longest entry above the page.
    @test current(page("/plz/karte/0815")) == ["PLZ"]
    @test current(page("/plz/liste")) == ["PLZ-Liste"]
    # Its query is not part of an entry's address; a #fragment entry is never marked.
    @test current(page("/glossar")) == ["Glossar"]
    @test current(page("/glossar?suche=Gemeinde")) == ["Glossar"]
    # An address the browser percent-encodes names the same page.
    @test current(page("/plz/karte/M%C3%BCnchen")) == ["München"]
    # The home entry names only itself: an unlisted page marks nothing.
    @test current(page("/impressum")) == []
    # The live app shows the private entry, marked where it is read.
    @test occursin(r"<li class=\"htmxo-private\"[^>]*><a href=\"/angebot\">Angebot</a></li>", page("/"))
    @test current(page("/angebot")) == ["Angebot"]
    # The page's language names the nav and the skip link.
    @test contains(page("/plz"), "<nav aria-label=\"Hauptnavigation\">")
    @test contains(page("/plz"), ">Zum Inhalt springen</a>")
    # Behind a proxy that strips its prefix, the entries carry the prefix the
    # app reads from `__prefix__`, and the request's address is compared with it.
    proxied = ["X-Forwarded-Prefix" => "/p/atlas"]
    @test current(page("/"; headers=proxied)) == ["Karte"]
    @test contains(page("/"; headers=proxied), "<a href=\"/p/atlas/\" aria-current=\"page\">Karte</a>")
    @test current(page("/plz/liste"; headers=proxied)) == ["PLZ-Liste"]
    @test current(page("/impressum"; headers=proxied)) == []
    # A public export leaves the private entry out, its stand-in in place, and
    # keeps the mark.
    exported = String(dispatch(:GET, "/plz"; static=StaticExport()).body)
    @test !contains(exported, "/angebot") && contains(exported, "<li>Angebot folgt</li>")
    @test current(exported) == ["PLZ"]
    # An answer HTMX swaps in carries no frame.
    fragment = String(dispatch(:GET, "/plz"; headers=["HX-Request" => "true"]).body)
    @test !contains(fragment, "<nav") && !contains(fragment, "htmxo-skip-link")
end

@testitem "the skip link shows when it has focus and the current entry is bold in Chrome" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const skip = document.querySelector('.htmxo-skip-link');
            const size = () => { const r = skip.getBoundingClientRect(); return Math.round(r.width) + 'x' + Math.round(r.height); };
            const hidden = size();
            const top = () => Math.round(document.querySelector('body > header').getBoundingClientRect().top);
            const header = top();
            skip.focus();
            const shown = skip.getBoundingClientRect();
            const weight = a => getComputedStyle(a).fontWeight;
            const links = [...document.querySelectorAll('body > header nav li a')];
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = [hidden, shown.width > 50 && shown.height > 10, header, top() > shown.bottom - 1,
                links.map(a => (a.getAttribute('aria-current') || '-') + ':' + weight(a)).join(',')].join(' ');
            document.body.appendChild(result);
        });
        """))
        # Built as the request for /modell builds it.
        html = HTMXObjects._with_page_meta((; HTMXObjects._NO_PAGE_META..., route="/modell", prefix="")) do
            repr("text/html", HTMXObjects.pico_page(h.p("Body text."); assets=:vendor, extra_head=(driver,),
                brand="Atlas" => "/", nav=["Karte" => "/", "Methodik" => "/modell"],
                htmx_version=nothing, hyperscript_version=nothing, feedback=false, compose=false))
        end
        pages = Dict("/modell" => html, "/vendor/pico.min.css" => read(HTMXObjects._vendor_file(:pico), String))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) || return HTTP.Response(404)
            HTTP.Response(200, ["Content-Type" => endswith(path, ".css") ? "text/css" : "text/html"], pages[path])
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1280,900 --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/modell`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            parts = split(checks[1], ' ')
            # Out of sight (1×1 px, clipped) until it has focus; then a link of
            # its own size above the header, which moves down to make room.
            @test parts[1] == "1x1"
            @test parts[2] == "true"
            @test parts[4] == "true"
            # The brand is bold (strong); of the entries only the current one is.
            @test parts[5] == "-:400,-:400,page:600"
        finally
            close(server)
        end
    end
end
