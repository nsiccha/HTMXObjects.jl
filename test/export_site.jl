using TestItemRunner

# `export_site`: the whole app as a static site, built on the per-response
# export (`dispatch(...; static=StaticExport(...))`). Snag
# `static-site-expo-b42a738b` (reporter VerkehrsStrukturdaten): ODLPlaus,
# AvHPreise and Portfolio each wrote their own crawler around that primitive.

@testmodule ExportSiteFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw
    export ExportSiteApp, BrokenSiteApp, CollidingSiteApp, PlacedSiteApp, PLACED_CALLS,
        InlineSiteApp, BigInlineSiteApp, QueriedSiteApp, StationSiteApp, TypedSiteApp, ParallelSiteApp, MOST_RENDERING,
        BundleSiteApp, finished_bundle, plain_folder,
        bundle_files, bundle_tree, subdirectory_misses, SectionSiteApp, SECTION_OLD_CALLS, served_at

    const KS = (3.0, 4.0)
    # The mount prefix the apps' links start from (they are mounted at the root).
    const base = ""

    @htmx struct ExportSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.h1("Start"),
            h.a("Bericht"; href=base * "/site_bericht"),
            # One address as a page (href) and as the fragment a click loads.
            hx_link(base * "/site_teil"; hx_target="#inhalt")("Teil"),
            h.div(; id="inhalt"),
            h.div(; hx_get=base * "/site_zelle?vb_nr=1", hx_trigger="load"),
            h.a("PDF"; href=base * "/site_datei/bericht_1.pdf", download="bericht_1.pdf"),
            h.a("Person"; href=base * "/site_person/A1"),
            h.a("Oben"; href="#oben"), h.a("Extern"; href="https://example.org/x"),
            h.button("Neu"; id="neu", hx_post=base * "/site_neu"),
            h.div(; id="k", hx_get=base * "/site_k", hx_trigger="none",
                  url_params(k = 3.0; values = (k = KS,))...)("k=3.0"),
            h.script(Raw("window.raster = " * repr(static_url(__req__, base * "/site_raster")) * ";")))
        @get site_bericht() = h.div(h.p("Bericht"), h.a("Start"; href=base * "/"))
        @get site_teil() = h.p("Teil")
        @get site_zelle(; vb_nr::Int=0) = h.div(h.p("Zelle $vb_nr"), h.a("Person"; href=base * "/site_person/A1"))
        @get site_person(id::String) = h.div(h.p("Person $id"), h.a("Bericht"; href="../site_bericht"))
        @get site_k(; k::Float64=3.0) = h.p("k=$k")
        @post site_neu() = h.p("neu")
        @direct @get site_datei(name::String) = MIMEResponse("application/pdf", "%PDF-1.7 $name")
        @direct @get site_raster() = MIMEResponse("application/geo+json", "{\"type\":\"FeatureCollection\",\"features\":[]}")
    end

    @htmx struct BrokenSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.div(; hx_get=base * "/broken_part", hx_trigger="load"),
            h.a("Nirgends"; href=base * "/broken_nowhere"),
            h.a("Gut"; href=base * "/broken_fine"),
            # Markup the walk never sees keeps its live address, as does a
            # script's Vega url not passed to static_url.
            Raw("<a href=\"/broken_raw\">raw</a>"),
            h.script(Raw("var spec = {\"data\":{\"url\":\"/broken_vega\"}};")))
        @get broken_part() = error("the part failed")
        @get broken_fine() = h.p("fine")
    end

    @htmx struct CollidingSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.a("1"; href=base * "/coll/a_b"), h.a("2"; href=base * "/coll/a%20b"))
        @get coll(id::String) = h.p("coll $id")
    end

    # The default shell inlines the runtime, whose styles carry a CSS comment
    # naming `href="…"` (snag `export-site-of-a-8d3b76a9`).
    @htmx struct InlineSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.a("Bericht"; href=base * "/inline_bericht"),
            Raw("<!-- <a href=\"/inline_nowhere\">alt</a> -->"),
            h.script(Raw("var spec = {\"data\":{\"url\":" *
                         repr(static_url(__req__, base * "/inline_raster")) * "}};")))
        @get inline_bericht() = h.p("Bericht")
        @direct @get inline_raster() = MIMEResponse("application/geo+json", "{\"type\":\"FeatureCollection\",\"features\":[]}")
    end

    # A page and a fragment that carry their data inline, as a region map
    # does, in a 50 MB script: more than PCRE matches a pattern across (snag
    # `odlplaus-s-stati-cff9ee9c`). The script names a file, so the export
    # rewrites it.
    big_inline_script(req) = h.script(Raw("var data = [" * "1.25,"^10_000_000 * "0];\nvar spec = {\"data\":{\"url\":" *
                                          repr(static_url(req, base * "/big_raster")) * "}};"))
    @htmx struct BigInlineSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(hx_link(base * "/big_teil"; hx_target="#inhalt")("Teil"), h.div(; id="inhalt"),
                             big_inline_script(__req__))
        @get big_teil() = h.div(h.a("Start"; href=base * "/"), big_inline_script(__req__))
        @direct @get big_raster() = MIMEResponse("application/geo+json", "{\"type\":\"FeatureCollection\",\"features\":[]}")
    end

    # Counted with an atomic: an export renders pages on several threads.
    const PLACED_CALLS = Threads.Atomic{Int}(0)
    @htmx struct PlacedSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.div(; hx_get=base * "/placed_probe?kenn=a&ort=karte", hx_trigger="load"),
            h.div(; hx_get=base * "/placed_probe?kenn=a&ort=liste", hx_trigger="load"),
            h.a("3"; href=base * "/placed_page"), h.a("4"; href=base * "/placed_page?k=4"))
        @get placed_probe(; kenn::String="", ort::String="") =
            (Threads.atomic_add!(PLACED_CALLS, 1); h.p("probe $kenn"))
        @get placed_page(; k::Int=3) = (Threads.atomic_add!(PLACED_CALLS, 10); h.p("k=$k"))
    end

    # A page that applies its address in the browser, as a region explorer's
    # does: its frame declares the level and the measure, and zoom links name
    # page addresses with a query (snag `export-site-need-5ad5b8cd`).
    const REGIONS = ("a", "b", "c", "a b")
    const MEASURES = ("x", "y")
    queried_frame(region, measure) =
        h.div(; id="frame", hx_get=base * "/queried_region?key=$region&measure=$measure",
              hx_trigger="none", hx_swap="outerHTML",
              url_params(region = region => :key, measure = measure;
                         values = (region = REGIONS, measure = MEASURES))...)(
            queried_level(region, measure))
    queried_level(region, measure) = h.div(
        h.p("level $region $measure"),
        h.a("Start"; href=base * "/"),
        (h.a(r; href=base * "/?region=$r&measure=$measure") for r in ("b", "c"))...)
    @htmx struct QueriedSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index(; region::String="a", measure::String="x", hinweis::String="") = h.div(
            h.p("asked $region $hinweis"),
            queried_frame(region in REGIONS ? region : "a", measure),
            h.a("y"; href=base * "/?region=b&measure=y"),
            h.a("Karte"; href=base * "/?region=c#karte"),
            h.a("a b"; href=base * "/?region=a+b"),
            # A value outside the declared ones, a parameter none declares.
            h.a("zz"; href=base * "/?region=zz"),
            h.a("hinweis"; href=base * "/?region=b&hinweis=1"),
            # A page that declares nothing, one that is not in the bundle itself.
            h.a("other"; href=base * "/queried_other?k=1"),
            h.a("lone"; href=base * "/queried_lone?k=2"),
            h.script(Raw("window.zoom = " * repr(static_url(__req__, base * "/?region=c&measure=y")) * ";")))
        @get queried_region(; key::String="a", measure::String="x") = queried_frame(key, measure)
        @get queried_other(; k::Int=0) = h.p("other $k")
        @get queried_lone(; k::String="1") = h.div(; hx_get=base * "/queried_other?k=$k", hx_trigger="none",
            url_params(k = k; values = (k = ("1", "2"),))...)("lone $k")
    end

    # A page whose own address has a query, as a probe's page has its `kenn`:
    # its frame declares the view it was opened from, and the links that open
    # it in a view name that address with the view's parameters added (snag
    # `odlplaus-static-02f57da3`, reporter ODLPlaus:review:ux).
    const STATION_REGIONS = ("de", "land")
    const STATION_LAYERS = ("x", "y")
    const STATION_SIZES = ("k40", "cs137")
    netz_frame(kenn, region, ebene) =
        h.div(; id="kontext", hx_get=base * "/station_netz?kenn=$kenn", hx_trigger="none", hx_swap="outerHTML",
              url_params(region = region, ebene = ebene;
                         values = (region = STATION_REGIONS, ebene = STATION_LAYERS))...)(
            h.p("netz $kenn $region $ebene"))
    insitu_frame(kenn, region, groesse) =
        h.div(; id="kontext", hx_get=base * "/station_insitu?kenn=$kenn", hx_trigger="none", hx_swap="outerHTML",
              url_params(region = region, groesse = groesse;
                         values = (region = STATION_REGIONS, groesse = STATION_SIZES))...)(
            h.p("insitu $kenn $region $groesse"))
    @htmx struct StationSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.p("Start"),
            # The views a probe's page opens in, linked before the page itself.
            (h.a("$k $r $e"; href=base * "/station?kenn=$k&region=$r&ebene=$e")
             for k in ("a", "b"), r in STATION_REGIONS, e in STATION_LAYERS)...,
            h.a("a insitu cs137"; href=base * "/station?kenn=a&ansicht=insitu&region=land&groesse=cs137"),
            # A value outside the declared ones; a probe whose page is not in the bundle.
            h.a("a mars"; href=base * "/station?kenn=a&region=mars"),
            h.a("c de"; href=base * "/station?kenn=c&region=de"),
            h.a("a"; href=base * "/station?kenn=a"), h.a("b"; href=base * "/station?kenn=b"),
            h.a("a insitu"; href=base * "/station?kenn=a&ansicht=insitu"))
        @get station(; kenn::String="", ansicht::String="netz", region::String="de", ebene::String="x",
                     groesse::String="k40") = h.div(
            h.p("asked $kenn $region"),
            (r = region in STATION_REGIONS ? region : "de";
             ansicht == "insitu" ? insitu_frame(kenn, r, groesse) : netz_frame(kenn, r, ebene)))
        @get station_netz(; kenn::String="", region::String="de", ebene::String="x") = netz_frame(kenn, region, ebene)
        @get station_insitu(; kenn::String="", region::String="de", groesse::String="k40") =
            insitu_frame(kenn, region, groesse)
    end

    # Extensionless downloads whose Content-Type the export's own table does
    # not name: one the media-type database lists (an Xfig sketch), one it
    # does not, and one the table names differently from the database
    # (snag `export-custom-mi-904ff844`, reporter ODLPlaus:review).
    @htmx struct TypedSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.a("Skizze"; href=base * "/typed_skizze?zone=nah&kenn=a", download="skizze.fig"),
            h.a("Eigen"; href=base * "/typed_eigen?kenn=a"),
            h.a("Foto"; href=base * "/typed_foto"))
        @direct @get typed_skizze(; kenn::String="", zone::String="") =
            MIMEResponse("application/x-xfig", "#FIG 3.2 $kenn $zone")
        @direct @get typed_eigen(; kenn::String="") = MIMEResponse("application/vnd.htmxo-test", "eigen $kenn")
        @direct @get typed_foto() = MIMEResponse("image/jpeg", "jpeg")
    end

    # Pages whose renders overlap when the export runs them concurrently: each
    # waits a moment while it is counted, so the highest count is how many
    # rendered at once (also on one thread, where the waits interleave them).
    const RENDERING = Threads.Atomic{Int}(0)
    const MOST_RENDERING = Threads.Atomic{Int}(0)
    function rendering(f)
        Threads.atomic_max!(MOST_RENDERING, Threads.atomic_add!(RENDERING, 1) + 1)
        try
            sleep(0.02)
            f()
        finally
            Threads.atomic_sub!(RENDERING, 1)
        end
    end
    const PARALLEL_PAGES = 1:12
    @htmx struct ParallelSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div((h.a("Seite $k"; href=base * "/parallel_page/$k") for k in PARALLEL_PAGES)...)
        @get parallel_page(k::Int) = rendering() do
            h.div(h.p("Seite $k"),
                  h.a("weiter"; href=base * "/parallel_page/$(mod1(k + 1, length(PARALLEL_PAGES)))"),
                  h.div(; hx_get=base * "/parallel_part?k=$k", hx_trigger="load"))
        end
        @get parallel_part(; k::Int=0) = rendering(() -> h.p("Teil $k"))
    end

    # A finished bundle another process wrote (snag `private-prebuilt-1136df2c`:
    # ODLPlaus serves BRM's exported model view from /modelldefinition): its
    # pages link their styles and scripts relatively, a stylesheet loads a font,
    # and a script loads a file no markup names.
    function finished_bundle()
        dir = mktempdir()
        mkpath(joinpath(dir, "assets")); mkpath(joinpath(dir, "teil"))
        write(joinpath(dir, "model.html"), "<!doctype html><html><head>" *
              "<link rel=\"stylesheet\" href=\"assets/style.css\"><script src=\"assets/tabs.js\"></script>" *
              "</head><body><a href=\"teil/index.html\">Teil</a></body></html>")
        write(joinpath(dir, "assets", "style.css"), "@font-face { src: url(font.woff2); }")
        write(joinpath(dir, "assets", "font.woff2"), "wOF2")
        write(joinpath(dir, "assets", "tabs.js"), "fetch('assets/tabs.json');")
        write(joinpath(dir, "assets", "tabs.json"), "{}")
        write(joinpath(dir, "teil", "index.html"), "<!doctype html><html><head>" *
              "<link rel=\"stylesheet\" href=\"../assets/style.css\"></head><body>Teil</body></html>")
        dir
    end
    # An ordinary folder whose page names a file the folder lacks, by a name
    # the export's root happens to hold (the app's own vendor mount).
    function plain_folder()
        dir = mktempdir()
        write(joinpath(dir, "seite.html"), "<!doctype html><html><head>" *
              "<script src=\"vendor/htmx.min.js\"></script></head><body>Seite</body></html>")
        dir
    end
    @htmx struct BundleSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.h1("Start"),
            h.a("Modell"; href=base * "/bundle_ansicht/model.html"),
            h.a("Teil"; href=base * "/bundle_ansicht/teil"))
    end

    # A section exported on its own, served beside a site published before it
    # (snag `native-static-re-756c2710`, reporter ODLPlaus:ux): the routes of
    # that site's pages count every render, which an alias to its files must
    # never cause.
    const SECTION_OLD_CALLS = Threads.Atomic{Int}(0)
    @htmx struct SectionSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.h1("Gemeinsamer Fit"),
            h.a("Alt"; href=base * "/section_old"),
            h.a("Station"; href=base * "/section_station?kenn=K1#karte"),
            h.a("Ort"; href=base * "/section_station?kenn=K2&ort=b%20x"),
            h.a("Detail"; href=base * "/section_detail"),
            h.div(; hx_get=base * "/section_teil", hx_trigger="load"))
        @get section_detail() = h.div(h.p("Detail"), h.a("Start"; href=base * "/"))
        @get section_teil() = h.div(h.p("Teil"), h.a("Detail"; href=base * "/section_detail"),
            h.a("Alt"; href=base * "/section_old"))
        @get section_old() = (Threads.atomic_add!(SECTION_OLD_CALLS, 1); h.p("alt"))
        @get section_station(; kenn::String="") = (Threads.atomic_add!(SECTION_OLD_CALLS, 1); h.p("station $kenn"))
    end

    # Where a browser finds each reference of each HTML file of the bundle in
    # `dir`, with the bundle served at `http://host/site/fit/`: a path on that
    # host, decoded, or another site's URL. A fragment (a file in an `hx/`
    # folder) shows in the `index.html` of the folder above its `hx/`.
    function served_at(dir)
        found = Dict{String,Vector{String}}()
        for file in bundle_files(dir)
            endswith(file, ".html") || continue
            parts = split(file, '/')
            k = findlast(==("hx"), parts)
            page = isnothing(k) ? file : join([parts[1:k-1]; "index.html"], '/')
            found[file] = map(filter(a -> !isempty(a) && !startswith(a, '#') && a != "true" && a != "false",
                                     HTMXObjects._site_references(read(joinpath(dir, file), String)))) do a
                uri = HTTP.URIs.resolvereference(HTTP.URI("http://host/site/fit/" * page), a)
                uri.host == "host" ? HTTP.URIs.unescapeuri(uri.path) : string(uri)
            end
        end
        found
    end

    # Every file of the bundle, relative to its root, with `/` between
    # directories (as a static server addresses it, also on Windows).
    bundle_files(dir) = sort!([replace(relpath(joinpath(d, f), dir), '\\' => '/')
                               for (d, _, fs) in walkdir(dir) for f in fs])
    # Every file of the bundle with its bytes.
    bundle_tree(dir) = Dict(f => read(joinpath(dir, f)) for f in bundle_files(dir))

    # Each reference in the bundle's HTML (as export_site reads them) that a
    # browser, with the bundle served from `/repo/`, would not find: resolved
    # as the browser resolves it (a fragment's links against the page that
    # loads it, a page in the root), then looked up as a static server does,
    # after decoding.
    function subdirectory_misses(dir)
        misses = String[]
        for file in bundle_files(dir)
            endswith(file, ".html") || continue
            page = startswith(file, "hx/") ? "index.html" : file
            html = read(joinpath(dir, file), String)
            for address in HTMXObjects._site_references(html)
                (isempty(address) || startswith(address, '#') || startswith(address, "https:")) && continue
                uri = HTTP.URIs.resolvereference(HTTP.URI("http://host/repo/" * page), address)
                path = HTTP.URIs.unescapeuri(uri.path)
                startswith(path, "/repo/") && isfile(joinpath(dir, path[7:end])) ||
                    push!(misses, "$file: $address")
            end
        end
        misses
    end
end

@testitem "static_file_name names pages, fragments and files" tags=[:unit] begin
    using HTMXObjects
    @test static_file_name("/") == "index.html"
    @test static_file_name("") == "index.html"
    @test static_file_name("/bericht") == "bericht.html"
    @test static_file_name("/bericht/") == "bericht.html"
    @test static_file_name("/rohdaten/personen") == "rohdaten-personen.html"
    # Query parameters fold into the name, in alphabetical order of the keys.
    @test static_file_name("/voralarme?k=3") == "voralarme-k-3.html"
    @test static_file_name("/x?b=2&a=1") == static_file_name("/x?a=1&b=2") == "x-a-1-b-2.html"
    @test static_file_name("/zelle?vb_nr=12"; fragment=true) == "hx/zelle-vb_nr-12.html"
    @test static_file_name("/api/v1/anomalien?p_min=0.9"; ext=".json") == "api-v1-anomalien-p_min-0.9.json"
    # A static server decodes an address before it looks the file up, so the
    # name carries no escape and no character a link would have to escape.
    @test static_file_name("/ap?pfad=%2Fap1%2Fk40") == "ap-pfad-_ap1_k40.html"
    @test static_file_name("/lf?ortsteil=Sch%C3%B6neberg") == "lf-ortsteil-Sch_neberg.html"
    @test static_file_name("/lf?ortsteil=Alt-Treptow#karte") == "lf-ortsteil-Alt-Treptow.html"
    # An address with a file extension keeps its path; its query names no file.
    @test static_file_name("/datei/bericht_1.pdf") == "datei/bericht_1.pdf"
    @test static_file_name("/vendor/htmx.min.js?v=2.0.8") == "vendor/htmx.min.js"
    @test static_file_name("/datei/a%20b.zip") == "datei/a b.zip"
    # A dot inside a name is not a file extension.
    @test static_file_name("/person/A1.5") == "person-A1.5.html"
end

@testitem "export_site writes every page, fragment and file a static server needs" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(ExportSiteApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    r = export_site(dir; pages=["/"])
    files = bundle_files(dir)

    # Pages in the root, fragments below hx/, files at their path, the
    # extension of an extensionless data address from its Content-Type.
    for f in ("index.html", "site_bericht.html", "site_teil.html", "hx/site_teil.html",
              "hx/site_zelle-vb_nr-1.html", "site_person-A1.html", "site_datei/bericht_1.pdf",
              "site_raster.geojson", "hx/site_k-k-3.0.html", "hx/site_k-k-4.0.html", ".nojekyll")
        @test f in files
    end
    @test r.files == length(files) - 1   # every file but .nojekyll
    @test r.bytes == sum(filesize(joinpath(dir, f)) for f in files)
    # The head's libraries and the linked runtime, fetched from vendorfiles.
    @test "vendor/htmx.min.js" in files && "vendor/pico.min.css" in files
    @test "vendor/htmxo/live_region.js" in files
    # The files a stylesheet loads, at the paths it names them by.
    katex = read(joinpath(dir, "vendor/katex/katex.min.css"), String)
    fonts = [m.captures[1] for m in eachmatch(r"url\(([^)]+\.woff2)\)", katex)]
    @test !isempty(fonts) && all(f -> isfile(joinpath(dir, "vendor/katex", f)), fonts)

    index = read(joinpath(dir, "index.html"), String)
    # Every link names its file relative to the bundle's root.
    @test occursin("href=\"site_bericht.html\"", index)
    @test occursin("href=\"site_teil.html\"", index) && occursin("hx-get=\"hx/site_teil.html\"", index)
    @test occursin("hx-get=\"hx/site_zelle-vb_nr-1.html\"", index)
    @test occursin("href=\"site_datei/bericht_1.pdf\"", index)
    @test occursin("src=\"vendor/htmx.min.js?v=$(HTMXObjects._HTMX_VERSION)\"", index)
    @test occursin("window.raster = \"site_raster.geojson\";", index)
    @test occursin("hx-get=\"hx/site_k-k-3.0.html\"", index)
    @test occursin("&quot;4.0&quot;:&quot;hx/site_k-k-4.0.html&quot;", index)
    # Anchors and other sites stay; a control the static site cannot serve is left out.
    @test occursin("href=\"#oben\"", index) && occursin("href=\"https://example.org/x\"", index)
    @test !occursin("site_neu", index) && !occursin("id=\"neu\"", index)
    # No stand-in for a file name is left anywhere.
    @test !occursin(r"htmxo[a-z]{12}f[0-9]+x", join(read.(joinpath.(dir, filter(endswith(".html"), files)), String)))

    # A page and the fragment of one address are different files.
    @test occursin("<html", read(joinpath(dir, "site_teil.html"), String))
    @test !occursin("<html", read(joinpath(dir, "hx/site_teil.html"), String))
    # A fragment's links resolve against the page that loads it, so they name
    # files of the root too; a relative link resolved against its own page.
    @test occursin("href=\"site_person-A1.html\"", read(joinpath(dir, "hx/site_zelle-vb_nr-1.html"), String))
    @test occursin("href=\"site_bericht.html\"", read(joinpath(dir, "site_person-A1.html"), String))
    # Finished answers are written as they answer.
    @test read(joinpath(dir, "site_datei/bericht_1.pdf"), String) == "%PDF-1.7 bericht_1.pdf"
    @test occursin("FeatureCollection", read(joinpath(dir, "site_raster.geojson"), String))

    # Served from a subdirectory, every reference finds its file.
    @test isempty(subdirectory_misses(dir))

    # Into a new or empty directory only; pages are addresses of the app.
    @test_throws ArgumentError export_site(dir; pages=["/"])
    @test_throws ArgumentError export_site(mktempdir(); pages=["bericht"])
    @test_throws ArgumentError export_site(mktempdir(); pages=["/"], controls=:hide)
    # Under controls=:disable the control stays, greyed out.
    kept = joinpath(mktempdir(), "kept")
    export_site(kept; pages=["/"], controls=:disable)
    @test occursin(r"<button[^>]*id=\"neu\"[^>]*disabled", read(joinpath(kept, "index.html"), String))
end

@testitem "a bundle mount is exported whole, and a private mount only for private readers" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    # Snag `private-prebuilt-1136df2c`: a finished offline bundle served from
    # a mount used to be exported as the one page a link named, without its
    # styles and scripts, and the reference check passed it because it looked
    # its relative links up in the root.
    using Treebars
    bundle = finished_bundle()
    staticfiles(bundle, "bundle_ansicht"; bundle=true, private=true)
    dynamicfiles(bundle, "bundle_dynamisch"; bundle=true, private=true)
    staticfiles(plain_folder(), "bundle_einfach")
    route!(BundleSiteApp())
    vendorfiles()

    # Live, a private reader gets the files; a public answer is a private page's.
    r = dispatch(:GET, "/bundle_ansicht/model.html"; audience=:private)
    @test r.status == 200 && r.body == read(joinpath(bundle, "model.html"))
    for mount in ("bundle_ansicht", "bundle_dynamisch")
        r = dispatch(:GET, "/$mount/model.html")
        @test r.status == 404 && HTTP.header(r, "X-HTMXO-Private") == "true" && isempty(r.body)
    end
    # A folder's address without its slash redirects, relative to itself, so
    # its page's relative links resolve in the folder; a public reader is not
    # told the folder exists.
    r = dispatch(:GET, "/bundle_ansicht/teil?x=1"; audience=:private)
    @test r.status == 308 && HTTP.header(r, "Location") == "teil/?x=1"
    r = dispatch(:GET, "/bundle_ansicht/teil/"; audience=:private)
    @test r.status == 200 && r.body == read(joinpath(bundle, "teil", "index.html"))
    @test dispatch(:GET, "/bundle_ansicht/teil").status == 404

    # A private export writes every file of the bundle at its path, byte for
    # byte, the one only its script loads included, and links the folder's
    # index.html; every reference resolves where a browser looks it up.
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"], audience=:private)
    files = bundle_files(dir)
    for f in bundle_files(bundle)
        @test "bundle_ansicht/" * f in files
        @test read(joinpath(dir, "bundle_ansicht", f)) == read(joinpath(bundle, f))
    end
    index = read(joinpath(dir, "index.html"), String)
    @test occursin("href=\"bundle_ansicht/model.html\"", index)
    @test occursin("href=\"bundle_ansicht/teil/index.html\"", index)
    @test isempty(subdirectory_misses(dir))

    # A public export writes none of it and leaves out the links to it.
    pub = joinpath(mktempdir(), "site")
    export_site(pub; pages=["/"])
    @test !any(startswith("bundle_ansicht/"), bundle_files(pub))
    @test !occursin("bundle_ansicht", read(joinpath(pub, "index.html"), String))

    # An ordinary mount's page is written as it answers, at its path, without
    # following its links, and the check looks them up where they point: the
    # root's vendor/htmx.min.js is not the bundle_einfach/vendor/htmx.min.js
    # the page loads.
    err = try
        export_site(joinpath(mktempdir(), "site"); pages=["/", "/bundle_einfach/seite.html"]); nothing
    catch e
        e
    end
    @test err isa StaticSiteIncomplete
    @test isempty(err.failed)
    @test err.unresolved == ["bundle_einfach/seite.html" => "vendor/htmx.min.js"]
end

@testitem "export_site links files outside the bundle without rendering them, and pages in a folder from there" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    # Snag `native-static-re-756c2710` (reporter ODLPlaus:ux): a section is
    # exported on its own and served beside a site published before it. Its
    # links to that site's pages name the published files (`aliases` to a file
    # outside the bundle), and nothing of that site is rendered, copied or
    # checked. A page that `file_name` puts in a folder links from that folder.
    using Treebars
    route!(SectionSiteApp())
    vendorfiles()
    old = "https://example.org/p/ODL/alt.html"
    inside(dir, path) = startswith(path, "/site/fit/") && isfile(joinpath(dir, path[11:end]))
    SECTION_OLD_CALLS[] = 0

    # A dictionary: another site's URL, and a path from the bundle's root that
    # leaves it. A link keeps its #id. A key matches whatever the order and
    # escaping of the address's parameters.
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"], aliases=Dict("/section_old" => old,
        "/section_station?kenn=K1" => "../station-kenn-K1.html",
        "/section_station?ort=b+x&kenn=K2" => "../station-kenn-K2.html"))
    @test SECTION_OLD_CALLS[] == 0
    @test !any(f -> startswith(f, "section_old") || startswith(f, "section_station"), bundle_files(dir))
    index = read(joinpath(dir, "index.html"), String)
    @test occursin("href=\"$old\"", index)
    @test occursin("href=\"../station-kenn-K1.html#karte\"", index)
    @test occursin("href=\"../station-kenn-K2.html\"", index)
    @test occursin("href=\"$old\"", read(joinpath(dir, "hx", "section_teil.html"), String))
    links = served_at(dir)
    @test "/site/station-kenn-K1.html" in links["index.html"] && old in links["index.html"]
    @test all(p -> p in (old, "/site/station-kenn-K1.html", "/site/station-kenn-K2.html") || inside(dir, p),
              reduce(vcat, values(links)))

    # A function, asked with each address and whether it loads as a fragment;
    # pages and fragments in a folder, the published site beside the bundle.
    asked = Set{Tuple{String,Bool}}()
    lk = ReentrantLock()
    alias(a; fragment) = (lock(() -> push!(asked, (a, fragment)), lk);
        startswith(a, "/section_old") || startswith(a, "/section_station") ?
            "../" * static_file_name(a; fragment) : nothing)
    in_folder(a; fragment=false, ext=".html") = "gemeinsamer-fit/" * static_file_name(a; fragment, ext)
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"], aliases=alias, file_name=in_folder)
    @test SECTION_OLD_CALLS[] == 0
    @test ("/section_teil", true) in asked && ("/section_detail", false) in asked
    @test all(startswith("gemeinsamer-fit/"), filter(!=(".nojekyll"), bundle_files(dir)))
    index = read(joinpath(dir, "gemeinsamer-fit", "index.html"), String)
    @test occursin("href=\"section_detail.html\"", index)
    @test occursin("hx-get=\"hx/section_teil.html\"", index)
    @test occursin("href=\"../../section_station-kenn-K1.html#karte\"", index)
    @test occursin("href=\"index.html\"", read(joinpath(dir, "gemeinsamer-fit", "section_detail.html"), String))
    teil = read(joinpath(dir, "gemeinsamer-fit", "hx", "section_teil.html"), String)
    @test occursin("href=\"section_detail.html\"", teil) && occursin("href=\"../../section_old.html\"", teil)
    links = served_at(dir)
    @test "/site/section_station-kenn-K1.html" in links["gemeinsamer-fit/index.html"]
    @test "/site/section_old.html" in links["gemeinsamer-fit/hx/section_teil.html"]
    @test all(p -> startswith(p, "/site/section_") || inside(dir, p), reduce(vcat, values(links)))

    # A fragment written for the root's pages that a page in a folder loads
    # is a failure: its links would not resolve there.
    flat_fragments(a; fragment=false, ext=".html") =
        fragment ? static_file_name(a; fragment, ext) : in_folder(a; fragment, ext)
    err = try
        export_site(joinpath(mktempdir(), "site"); pages=["/"], aliases=alias, file_name=flat_fragments); nothing
    catch e
        e
    end
    @test err isa StaticSiteIncomplete
    @test isempty(err.unresolved)
    @test only(err.failed) == ("hx/section_teil.html" =>
        "is a fragment whose links are written for the pages of the root, but " *
        "gemeinsamer-fit/index.html in gemeinsamer-fit/ loads it, where they would not resolve; " *
        "give it a file below gemeinsamer-fit/hx/ (file_name), or load it only from pages of the root")
    @test SECTION_OLD_CALLS[] == 0

    # A target that is neither an address of this app nor outside the bundle:
    # refused up front from a dictionary, a failure of its address from a
    # function (asked while a page renders), and never rendered either way.
    @test_throws ArgumentError export_site(joinpath(mktempdir(), "site"); pages=["/"],
        aliases=Dict("/section_old" => "alt.html"))
    @test_throws ArgumentError export_site(joinpath(mktempdir(), "site"); pages=["/"],
        aliases=Dict("section_old" => old))
    # Two keys that name one address, with different targets.
    @test_throws ArgumentError export_site(joinpath(mktempdir(), "site"); pages=["/"],
        aliases=Dict("/section_old?a=1&b=2" => "/", "/section_old?b=2&a=1" => old))
    err = try
        export_site(joinpath(mktempdir(), "site"); pages=["/"],
                    aliases=(a; fragment) -> a == "/section_old" ? "alt.html" :
                        startswith(a, "/section_station") ? "../station.html" : nothing); nothing
    catch e
        e
    end
    @test err isa StaticSiteIncomplete && isempty(err.unresolved)
    @test only(err.failed) == ("/section_old" => "aliases gives \"alt.html\" for \"/section_old\", " *
        "which is neither an address of this app (starting with `/`) nor a file outside the bundle " *
        "(another site's URL such as `https://…`, or a path from the bundle's root that leaves it, " *
        "starting with `../`)")
    @test SECTION_OLD_CALLS[] == 0
end

@testitem "export_site fails listing every failed answer and every unresolved reference" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(BrokenSiteApp())
    vendorfiles()
    dir = mktempdir()
    err = try
        export_site(dir; pages=["/"]); nothing
    catch e
        e
    end
    @test err isa StaticSiteIncomplete
    failed = Dict(err.failed)
    # A failed fragment answers 200 under htmx; its error header tells it apart.
    @test startswith(failed["/broken_part"], "error ")
    @test failed["/broken_nowhere"] == "HTTP 404"
    # The crawl carried on: the good page is written.
    @test isfile(joinpath(dir, "broken_fine.html"))
    # An address the walk never saw is reported, the failed ones are not again.
    @test err.unresolved == ["index.html" => "/broken_raw", "index.html" => "/broken_vega"]
    msg = sprint(showerror, err)
    @test occursin("2 addresses failed and 2 references", msg)
    @test occursin("failed: /broken_part", msg) && occursin("unresolved: /broken_raw in index.html", msg)
end

@testitem "export_site checks the elements of a page that inlines the runtime, not its style text" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(InlineSiteApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    r = export_site(dir; pages=["/"])
    @test r.files == length(bundle_files(dir)) - 1
    index = read(joinpath(dir, "index.html"), String)
    # The runtime is in the page, and so is the `href` its styles' comment
    # names; neither that nor an address inside an HTML comment is a link.
    @test !isfile(joinpath(dir, "vendor/htmxo/live_region.js"))
    @test occursin("htmxo-back-link\" href=\"…\"", index)
    @test occursin("<!-- <a href=\"/inline_nowhere\">alt</a> -->", index)
    @test !any(==("/inline_nowhere"), HTMXObjects._site_references(index))
    # A script's Vega url is followed, and read as a reference.
    @test occursin("\"url\":\"inline_raster.geojson\"", index)
    @test isfile(joinpath(dir, "inline_raster.geojson"))
    @test "inline_raster.geojson" in HTMXObjects._site_references(index)
    @test isfile(joinpath(dir, "inline_bericht.html"))
    @test isempty(subdirectory_misses(dir))
end

@testitem "export_site reads and rewrites a script, style or comment larger than PCRE matches across" tags=[:unit] begin
    import HTMXObjects
    # A pattern matched across a text of more than about ten million
    # characters stops with "PCRE.exec error: match limit exceeded" (snag
    # `odlplaus-s-stati-cff9ee9c`). Each text here is over 50 MB.
    data = "[1.25,2.5],"^4_600_000
    link(m) = "f.html?m=" * m * "&k=1"
    marker = r"mk[0-9]+x"
    for (open, close, script) in (("<script type=\"application/json\">", "</script>", true),
                                  ("<style media=\"all\">", "</STYLE >", false),
                                  ("<!--", "-->", false))
        html = "<a href=\"mk1x\">a</a>" * open * "{\"url\":\"mk2x\"} <a href=\"mk3x\">" * data * close *
               "<a href=\"mk4x\">b</a>"
        @test ncodeunits(html) > 50_000_000
        # Only a script's text is read, for its Vega urls; no text holds elements.
        @test HTMXObjects._site_references(html) == (script ? ["mk1x", "mk2x", "mk4x"] : ["mk1x", "mk4x"])
        @test isempty(HTMXObjects._site_url_params(html))
        # An address is escaped where it is an attribute's value, not inside the text.
        @test HTMXObjects._site_unmark(html, marker, link, true) ==
              "<a href=\"f.html?m=mk1x&amp;k=1\">a</a>" * open *
              "{\"url\":\"f.html?m=mk2x&k=1\"} <a href=\"f.html?m=mk3x&k=1\">" * data * close *
              "<a href=\"f.html?m=mk4x&amp;k=1\">b</a>"
    end
    # A tag nothing closes holds no text: the elements after it are read.
    @test HTMXObjects._site_references("<script><a href=\"x\">a</a><!-- <a href=\"y\"> --><style>") == ["x"]
end

@testitem "export_site writes a page and a fragment whose inline script is larger than PCRE matches across" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(BigInlineSiteApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    r = export_site(dir; pages=["/"])
    @test r.files == length(bundle_files(dir)) - 1
    for file in ("index.html", "big_teil.html", "hx/big_teil.html")
        html = read(joinpath(dir, file), String)
        @test ncodeunits(html) > 50_000_000
        @test occursin("var data = [" * "1.25,"^10_000_000 * "0];", html)
        @test occursin("\"url\":\"big_raster.geojson\"", html)
        @test "big_raster.geojson" in HTMXObjects._site_references(html)
    end
    @test occursin("hx-get=\"hx/big_teil.html\"", read(joinpath(dir, "index.html"), String))
    @test isfile(joinpath(dir, "big_raster.geojson"))
    @test isempty(subdirectory_misses(dir))
end

@testitem "export_site never puts two addresses into one file unasked" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(CollidingSiteApp())
    vendorfiles()
    err = try
        export_site(mktempdir(); pages=["/"]); nothing
    catch e
        e
    end
    @test err isa StaticSiteIncomplete
    @test only(err.failed) == ("/coll/a%20b" => "has the same file (coll-a_b.html) as /coll/a_b; " *
                               "pass export_site a file_name that tells them apart")

    # An app's own file_name may give several addresses one file on purpose:
    # a probe view rendered once, whatever its placement on the page.
    route!(PlacedSiteApp())
    PLACED_CALLS[] = 0
    # A page that reads its parameter in the browser can be one file whose
    # links keep the query.
    unplaced(a; kw...) = startswith(a, "/placed_page?") ? "placed_page.html?" * split(a, '?')[2] :
        static_file_name(replace(a, r"&ort=[a-z]+" => ""); kw...)
    dir = mktempdir()
    export_site(dir; pages=["/"], file_name=unplaced)
    @test PLACED_CALLS[] == 11
    @test isfile(joinpath(dir, "hx", "placed_probe-kenn-a.html"))
    index = read(joinpath(dir, "index.html"), String)
    @test count("hx-get=\"hx/placed_probe-kenn-a.html\"", index) == 2
    @test occursin("href=\"placed_page.html\"", index) && occursin("href=\"placed_page.html?k=4\"", index)
    @test occursin("k=3", read(joinpath(dir, "placed_page.html"), String))
    @test !any(f -> occursin('?', f), bundle_files(dir))
end

@testitem "export_site writes one file for a page that applies its address in the browser" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(QueriedSiteApp())
    vendorfiles()
    dir = joinpath(mktempdir(), "site")
    r = export_site(dir; pages=["/"])
    files = bundle_files(dir)
    @test r.files == length(files) - 1
    index = read(joinpath(dir, "index.html"), String)

    # Every view the frame declares is a fragment of its own.
    for region in ("a", "b", "c", "a_b"), measure in ("x", "y")
        @test "hx/queried_region-key-$region-measure-$measure.html" in files
    end
    # Addresses whose query the page applies link the page's file with it.
    @test occursin("href=\"index.html?region=b&amp;measure=y\"", index)
    @test occursin("href=\"index.html?region=b&amp;measure=x\"", index)
    @test occursin("href=\"index.html?region=c#karte\"", index)
    @test occursin("href=\"index.html?region=a+b\"", index)
    # A script's text keeps the query as it is.
    @test occursin("window.zoom = \"index.html?region=c&measure=y\";", index)
    # So do the links of the fragments the page loads.
    @test occursin("href=\"index.html?region=c&amp;measure=y\"",
                   read(joinpath(dir, "hx/queried_region-key-b-measure-y.html"), String))
    @test occursin("href=\"index.html\"", read(joinpath(dir, "hx/queried_region-key-b-measure-y.html"), String))
    # Every other page address with a query is a file of its own, rendered
    # with its query.
    @test filter(f -> startswith(f, "index"), files) == ["index-hinweis-1-region-b.html", "index-region-zz.html", "index.html"]
    @test occursin("href=\"index-region-zz.html\"", index) && occursin("href=\"index-hinweis-1-region-b.html\"", index)
    @test occursin("asked zz", read(joinpath(dir, "index-region-zz.html"), String))
    @test occursin("asked b 1", read(joinpath(dir, "index-hinweis-1-region-b.html"), String))
    @test occursin("href=\"queried_other-k-1.html\"", index) && "queried_other-k-1.html" in files
    @test occursin("href=\"queried_lone-k-2.html\"", index) && "queried_lone-k-2.html" in files
    @test isempty(subdirectory_misses(dir))

    # A query address listed before its page waits for it.
    listed = joinpath(mktempdir(), "site")
    export_site(listed; pages=["/?region=b&measure=y", "/"])
    @test filter(f -> startswith(f, "index"), bundle_files(listed)) ==
          ["index-hinweis-1-region-b.html", "index-region-zz.html", "index.html"]
    @test occursin("href=\"index.html?region=b&amp;measure=y\"", read(joinpath(listed, "index.html"), String))
end

@testitem "export_site shares the file of a page whose own address has a query" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(StationSiteApp())
    vendorfiles()
    stations(dir) = filter(f -> startswith(f, "station"), bundle_files(dir))
    # Linked from the start page only, or listed first (as the reporter's
    # export does), before the views that open them, or after: the same files.
    bundles = map((["/"], ["/station?kenn=a", "/station?kenn=b", "/station?kenn=a&ansicht=insitu", "/"],
                   ["/station?kenn=a&region=land&ebene=y", "/", "/station?kenn=b"])) do pages
        dir = joinpath(mktempdir(), "site")
        export_site(dir; pages)
        dir
    end
    dir = first(bundles)
    files = bundle_files(dir)
    # Each probe's page is one file per view; a view the page's frame
    # declares adds no page file of its own. One whose value the frame does
    # not declare, or whose page is not in the bundle, is a file of its own.
    @test stations(dir) == ["station-ansicht-insitu-kenn-a.html", "station-kenn-a-region-mars.html",
                            "station-kenn-a.html", "station-kenn-b.html", "station-kenn-c-region-de.html"]
    @test all(d -> stations(d) == stations(dir), bundles)
    # Every view the frames declare is a fragment of its own.
    for k in ("a", "b"), r in ("de", "land"), e in ("x", "y")
        @test "hx/station_netz-ebene-$e-kenn-$k-region-$r.html" in files
    end
    @test "hx/station_insitu-groesse-cs137-kenn-a-region-land.html" in files
    # Links to a view name the page's file with the view's parameters, and
    # nothing the page's own address already carries.
    for d in bundles
        index = read(joinpath(d, "index.html"), String)
        @test occursin("href=\"station-kenn-a.html?region=land&amp;ebene=y\"", index)
        @test occursin("href=\"station-kenn-b.html?region=de&amp;ebene=x\"", index)
        @test occursin("href=\"station-ansicht-insitu-kenn-a.html?region=land&amp;groesse=cs137\"", index)
        @test occursin("href=\"station-kenn-a-region-mars.html\"", index)
        @test occursin("href=\"station-kenn-c-region-de.html\"", index)
        @test occursin("href=\"station-kenn-a.html\"", index)
    end
    @test occursin("asked a mars", read(joinpath(dir, "station-kenn-a-region-mars.html"), String))
    @test isempty(subdirectory_misses(dir))
end

@testitem "export_site names the file of any Content-Type, and file_name one no database lists" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    route!(TypedSiteApp())
    vendorfiles()
    failure(f) = try
        f(); nothing
    catch e
        e
    end

    # The default names give a type the media-type database lists its
    # extension, keep the table's names, and fail on a type neither lists,
    # saying what to do.
    dir = mktempdir()
    err = failure(() -> export_site(dir; pages=["/"]))
    @test err isa StaticSiteIncomplete
    @test only(err.failed) == ("/typed_eigen?kenn=a" =>
        "no file extension for its Content-Type \"application/vnd.htmxo-test\"; give the address one, " *
        "or pass export_site a file_name that names its file with one (it is asked with ext=\"\")")
    @test isempty(err.unresolved)
    @test read(joinpath(dir, "typed_skizze-kenn-a-zone-nah.fig"), String) == "#FIG 3.2 a nah"
    @test read(joinpath(dir, "typed_foto.jpg"), String) == "jpeg"
    index = read(joinpath(dir, "index.html"), String)
    @test occursin("href=\"typed_skizze-kenn-a-zone-nah.fig\"", index)
    @test occursin("href=\"typed_foto.jpg\"", index)

    # An app's own file_name, asked with ext="", names the file with an
    # extension of its choosing; links name that file.
    named(a; fragment=false, ext=".html") =
        static_file_name(a; fragment, ext=startswith(a, "/typed_eigen") ? ".htmxo" : ext)
    dir = joinpath(mktempdir(), "site")
    export_site(dir; pages=["/"], file_name=named)
    @test read(joinpath(dir, "typed_eigen-kenn-a.htmxo"), String) == "eigen a"
    @test isfile(joinpath(dir, "typed_skizze-kenn-a-zone-nah.fig"))
    index = read(joinpath(dir, "index.html"), String)
    @test occursin("href=\"typed_eigen-kenn-a.htmxo\"", index)
    @test isempty(subdirectory_misses(dir))

    # One that passes the "" on gives a name without an extension: the answer
    # fails, naming the name it gave.
    err = failure(() -> export_site(mktempdir(); pages=["/"], file_name=(a; kw...) -> static_file_name(a; kw...)))
    @test err isa StaticSiteIncomplete
    @test only(err.failed) == ("/typed_eigen?kenn=a" =>
        "no file extension for its Content-Type \"application/vnd.htmxo-test\", and file_name, asked with " *
        "ext=\"\", named it \"typed_eigen-kenn-a\" without one (a `.` and up to 8 letters or digits, the " *
        "first a letter); give the address one, or have file_name name its file with one")
    # A longer suffix is not a file extension, as it is not in an address.
    err = failure(() -> export_site(mktempdir(); pages=["/"],
        file_name=(a; kw...) -> startswith(a, "/typed_eigen") ? "typed_eigen.htmxotest" : static_file_name(a; kw...)))
    @test occursin("named it \"typed_eigen.htmxotest\" without one (a `.` and up to 8", only(err.failed).second)
end

@testitem "export_site renders pages concurrently and writes what a one-page-at-a-time export writes" setup=[HTMXOTestImports, ExportSiteFixture] tags=[:unit] begin
    using Treebars
    vendorfiles()
    failure(f) = try
        f(); nothing
    catch e
        e
    end
    # The bundle an export writes, and how it failed (each failed route's
    # error is recorded under an id of its own).
    function exported(; kw...)
        dir = joinpath(mktempdir(), "site")
        err = failure(() -> export_site(dir; kw...))
        err isa Union{Nothing,StaticSiteIncomplete} || throw(err)
        failed = isnothing(err) ? nothing :
            ([a => replace(why, r"^error [0-9a-f]+ " => "error ") for (a, why) in err.failed], err.unresolved)
        (; tree=bundle_tree(dir), failed)
    end

    # With parallel=true as many renders overlap as the process has CPUs (its
    # default threads, or fewer under a CPU quota); never with parallel=false.
    route!(ParallelSiteApp())
    MOST_RENDERING[] = 0
    sequential = exported(; pages=["/"], parallel=false)
    @test MOST_RENDERING[] == 1
    MOST_RENDERING[] = 0
    parallel = exported(; pages=["/"], parallel=true)
    @test MOST_RENDERING[] == min(HTMXObjects._usable_cpus(), 12)
    @test count(f -> startswith(f, "parallel_page-"), keys(sequential.tree)) == 12
    @test count(f -> startswith(f, "hx/parallel_part-"), keys(sequential.tree)) == 12
    @test parallel == sequential

    # Byte for byte the same bundle, and the same failures: links, fragments,
    # files and url_params values; pages sharing a page's file; an app's own
    # file_name; failed answers and unresolved references. Two exports one
    # page at a time agree first, so the comparison can tell them apart.
    named(a; fragment=false, ext=".html") =
        static_file_name(a; fragment, ext=startswith(a, "/typed_eigen") ? ".htmxo" : ext)
    for (app, kw) in ((ExportSiteApp(), (; pages=["/"])), (QueriedSiteApp(), (; pages=["/"])),
                      (StationSiteApp(), (; pages=["/station?kenn=a&region=land&ebene=y", "/"])),
                      (TypedSiteApp(), (; pages=["/"], file_name=named)), (BrokenSiteApp(), (; pages=["/"])))
        route!(app)
        one = exported(; kw..., parallel=false)
        @test exported(; kw..., parallel=false) == one
        @test exported(; kw..., parallel=true) == one
        @test isnothing(one.failed) == !(app isa BrokenSiteApp)
    end
end

@testitem "export_site renders at most as many pages at once as a cgroup's CPU quota allows" tags=[:unit] begin
    import HTMXObjects: _cgroup_cpu_quota, _usable_cpus
    root = mktempdir()
    cgroup = joinpath(mktempdir(), "cgroup")
    scope = joinpath(root, "user.slice", "app.slice", "run-1.scope")
    mkpath(scope)
    write(cgroup, "0::/user.slice/app.slice/run-1.scope\n")
    if Sys.islinux()
        # No cpu.max, or one without a limit: no quota.
        @test isnothing(_cgroup_cpu_quota(; cgroup, root))
        write(joinpath(root, "user.slice", "cpu.max"), "max 100000\n")
        @test isnothing(_cgroup_cpu_quota(; cgroup, root))
        # A systemd scope with CPUQuota=200%: two CPUs; a tighter one above it wins.
        write(joinpath(scope, "cpu.max"), "200000 100000\n")
        @test _cgroup_cpu_quota(; cgroup, root) == 2.0
        write(joinpath(root, "user.slice", "cpu.max"), "150000 100000\n")
        @test _cgroup_cpu_quota(; cgroup, root) == 1.5
        # cgroup v1 names no unified hierarchy.
        write(cgroup, "4:cpu,cpuacct:/user.slice\n")
        @test isnothing(_cgroup_cpu_quota(; cgroup, root))
    else
        @test isnothing(_cgroup_cpu_quota(; cgroup, root))
    end
    @test 1 <= _usable_cpus() <= Threads.nthreads(:default)
end

@testitem "export_site renders concurrently by default only with no more threads than CPUs" tags=[:unit] begin
    import HTMXObjects: _parallel_pays
    # One thread has nothing to share; more threads than a quota's CPUs spend
    # it spinning (measured: 8 threads on 2 CPUs 1,706 s, 2 threads 1,122 s,
    # one page at a time 1,362 s).
    @test !_parallel_pays(1, nothing)
    @test _parallel_pays(2, 2.0) == (Sys.CPU_THREADS >= 2)
    @test _parallel_pays(2, 1.5) == (Sys.CPU_THREADS >= 2)
    @test !_parallel_pays(8, 2.0)
    @test !_parallel_pays(3, 2.0)
    @test _parallel_pays(2, nothing) == (Sys.CPU_THREADS >= 2)
    @test !_parallel_pays(Sys.CPU_THREADS + 1, nothing)
end
