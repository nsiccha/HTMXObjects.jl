using TestItemRunner

# `export_site`: the whole app as a static site, built on the per-response
# export (`dispatch(...; static=StaticExport(...))`). Snag
# `static-site-expo-b42a738b` (reporter VerkehrsStrukturdaten): ODLPlaus,
# AvHPreise and Portfolio each wrote their own crawler around that primitive.

@testmodule ExportSiteFixture begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, Raw
    export ExportSiteApp, BrokenSiteApp, CollidingSiteApp, PlacedSiteApp, PLACED_CALLS,
        bundle_files, subdirectory_misses

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
            # Markup the walk never sees keeps its live address.
            Raw("<a href=\"/broken_raw\">raw</a>"))
        @get broken_part() = error("the part failed")
        @get broken_fine() = h.p("fine")
    end

    @htmx struct CollidingSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.a("1"; href=base * "/coll/a_b"), h.a("2"; href=base * "/coll/a%20b"))
        @get coll(id::String) = h.p("coll $id")
    end

    const PLACED_CALLS = Ref(0)
    @htmx struct PlacedSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(
            h.div(; hx_get=base * "/placed_probe?kenn=a&ort=karte", hx_trigger="load"),
            h.div(; hx_get=base * "/placed_probe?kenn=a&ort=liste", hx_trigger="load"))
        @get placed_probe(; kenn::String="", ort::String="") = (PLACED_CALLS[] += 1; h.p("probe $kenn"))
    end

    # Every file of the bundle, relative to its root.
    bundle_files(dir) = sort!([relpath(joinpath(d, f), dir) for (d, _, fs) in walkdir(dir) for f in fs])

    # Each reference in the bundle's HTML that a browser, with the bundle
    # served from `/repo/`, would not find: resolved as the browser resolves it
    # (a fragment's links against the page that loads it, a page in the root),
    # then looked up as a static server does, after decoding.
    function subdirectory_misses(dir)
        misses = String[]
        for file in bundle_files(dir)
            endswith(file, ".html") || continue
            page = startswith(file, "hx/") ? "index.html" : file
            html = read(joinpath(dir, file), String)
            for m in eachmatch(r"\b(?:href|src|hx-get|hx-push-url)=\"([^\"]*)\"|\"url\":\"([^\"]*)\"", html)
                address = replace(something(m[1], m[2]), "&amp;" => "&")
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
    @test err.unresolved == ["index.html" => "/broken_raw"]
    msg = sprint(showerror, err)
    @test occursin("2 addresses failed and 1 references", msg)
    @test occursin("failed: /broken_part", msg) && occursin("unresolved: /broken_raw in index.html", msg)
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
    unplaced(a; kw...) = static_file_name(replace(a, r"&ort=[a-z]+" => ""); kw...)
    dir = mktempdir()
    export_site(dir; pages=["/"], file_name=unplaced)
    @test PLACED_CALLS[] == 1
    @test isfile(joinpath(dir, "hx", "placed_probe-kenn-a.html"))
    @test count("hx-get=\"hx/placed_probe-kenn-a.html\"", read(joinpath(dir, "index.html"), String)) == 2
end
