using TestItemRunner

# A route whose form fields come from data (one control per entry of a
# template's metadata) cannot list them as keywords. A keyword splat receives
# them under their own names (snag `a-route-that-sub-2c871b63`, user decision
# `1mx9fxc`).
@testitem "A route's keyword splat receives the submitted fields it does not declare" tags=[:unit] begin
    using HTMXObjects
    HTTP = HTMXObjects.HTTP

    # `show` of the splat, one `name=value` per field in the order received.
    shown(fields) = join(["$(k)=$(repr(v))" for (k, v) in pairs(fields)], " ")

    @htmx struct RestFieldOps
        @param lang::String = "en"
        "Create report"
        @post create(; template::String, fields...) = string("template=", template, " | ", shown(fields))
        "Rows"
        @get rows(; sort::String = "", filters...) = string("sort=", sort, " | ", shown(filters))
        "Declared only"
        @post declared(; template::String) = "template=$template"
        "Upload"
        @post upload(; template::String, fields...) =
            join(["$(k)=$(v isa Upload ? "Upload($(v.filename))" : repr(v))" for (k, v) in pairs(fields)], " ")
        @get index() = string(route_url(__self__, :rows; sort = "name", region = "09"), " ",
                              route_url(__self__, :rows; tag = ["a", "b"]))
    end
    @htmx struct RestFieldHost
        @include ops = RestFieldOps()
    end

    app = RestFieldHost()
    route!(app; operation_policy=:blocking)
    form = ["Content-Type" => "application/x-www-form-urlencoded"]
    body(r) = String(r.body)

    # Every undeclared field arrives under its own name: a repeated one as a
    # vector, a declared keyword and the struct's `@param` not at all, an
    # empty value (a blank text field) not at all, an unchecked checkbox
    # (never submitted) not at all.
    posted = dispatch(:POST, "/ops/create?plain=1"; headers=form,
        body="template=pk1&dose=10&route=oral&tag=a&tag=b&covariates_on=on&note=&lang=de")
    @test posted.status == 200
    @test body(posted) ==
        "template=pk1 | covariates_on=\"on\" dose=\"10\" route=\"oral\" tag=[\"a\", \"b\"]"

    # A field the query string carries and the body does not is read from the
    # query string, as for a declared keyword; the body wins a name in both.
    # Framework names (`plain`, `__htmxo_*`) are never fields.
    merged = dispatch(:POST, "/ops/create?plain=1&cohort=adult&dose=99&__htmxo_x=1";
        headers=form, body="template=pk2&dose=5")
    @test merged.status == 200
    @test body(merged) == "template=pk2 | cohort=\"adult\" dose=\"5\""

    # Only framework fields besides the declared one: the splat is empty, and
    # it is never required.
    bare = dispatch(:POST, "/ops/create?plain=1"; headers=form, body="template=pk3")
    @test bare.status == 200
    @test body(bare) == "template=pk3 | "
    # The declared keyword stays required.
    @test dispatch(:POST, "/ops/create"; headers=form, body="dose=1").status == 400

    # GET reads the query string, without the `?plain` projection flag.
    got = dispatch(:GET, "/ops/rows?plain=1&sort=name&region=09&year=2024")
    @test got.status == 200
    @test body(got) == "sort=name | region=\"09\" year=\"2024\""

    # A route without a splat still ignores what it does not declare.
    declared = dispatch(:POST, "/ops/declared?plain=1"; headers=form, body="template=pk1&dose=10")
    @test declared.status == 200
    @test body(declared) == "template=pk1"

    # A multipart file part arrives as an `Upload`.
    boundary = "htmxoRestBoundary"
    mp = IOBuffer()
    for (name, value) in ("template" => "pk1", "dose" => "10", "data" => ("obs.csv", "t,c\n0,1\n"))
        print(mp, "--", boundary, "\r\n")
        if value isa Tuple
            print(mp, "Content-Disposition: form-data; name=\"", name, "\"; filename=\"", value[1],
                  "\"\r\nContent-Type: text/csv\r\n\r\n", value[2], "\r\n")
        else
            print(mp, "Content-Disposition: form-data; name=\"", name, "\"\r\n\r\n", value, "\r\n")
        end
    end
    print(mp, "--", boundary, "--\r\n")
    uploaded = dispatch(:POST, "/ops/upload?plain=1";
        headers=["Content-Type" => "multipart/form-data; boundary=$(boundary)"], body=take!(mp))
    @test uploaded.status == 200
    @test body(uploaded) == "data=Upload(obs.csv) dose=\"10\""

    # A generated form renders the declared keywords and no control for the
    # splat; reflection lists no `fields` parameter.
    html = repr("text/html", semantic_app(app))
    @test occursin(r"<input[^>]*name=\"template\"", html)
    @test !occursin(r"name=\"fields\"", html)
    @test !occursin(r"name=\"filters\"", html)
    create = only(r for r in reflect(app) if r.name === :create && r.verb === :POST)
    @test [p.name for p in create.params] == [:template, :lang]

    # `route_url` accepts keywords a splat route does not declare, still
    # checks the declared ones, and still refuses an unknown keyword on a
    # route without a splat.
    index = dispatch(:GET, "/ops?plain=1")
    @test index.status == 200
    @test body(index) == "/ops/rows?sort=name&region=09 /ops/rows?tag=a&tag=b"
    ops = app.ops
    @test_throws ArgumentError route_url(ops, :index; region = "09")
end
