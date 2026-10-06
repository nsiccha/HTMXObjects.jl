using TestItemRunner

@testmodule UrlSegmentFixtures begin
    using HTMXObjects
    export SegRow, SegHost, SegDataset, SEG_DATASETS, SEG_STORE

    struct SegDataset
        key::String
        label::String
    end

    const SEG_DATASETS = [SegDataset("study/1", "Study one"), SegDataset("plain", "Plain")]
    const SEG_STORE = Dict{String,String}()

    @htmx struct SegRow
        key::String
        @get source(; note::String="n") = h.p("source:" * key * ":" * note)
        @post write(; note::String="n") = h.p("write:" * key * ":" * note)
    end

    @htmx struct SegHost
        @include rows(key::String) = SegRow(key)
        @include inline(key::String) = begin
            @get source() = h.p("inline:" * key)
        end
        @options dataset = SEG_DATASETS
        @include external_dataset(dataset::SegDataset) = SegRow(dataset.key)
        @include inline_dataset(dataset::SegDataset) = begin
            @get source() = h.p("inline-dataset:" * dataset.key)
        end
        @get item(key::String) = h.p("item:" * key)
        @get item_link(; key::String) = h.p(string(@query_url item(key)))
        @include store = Resource(SEG_STORE; input=String, name="store")
    end
end

@testitem "indexed mount values round-trip as one encoded path segment" setup=[UrlSegmentFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP

    route!(SegHost(); operation_policy=:blocking)
    app = SegHost()
    body(url) = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
    status(url) = dispatch(:GET, url; headers=["HX-Request" => "true"]).status
    # Route bodies render as HTML text, so compare against the escaped value and
    # read the `@query_url` result back out of its escaped text.
    esc(s) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&#39;")
    unesc(s) = replace(s, "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&#39;" => "'", "&amp;" => "&")
    item_url(key) = unesc(only(match(r"<p>(.*)</p>", body("/item_link?key=" * HTTP.escapeuri(key))).captures))

    # Bytes that end, split or reinterpret a segment are encoded. Each value must
    # come back unchanged through the external mount, the inline mount and
    # `@query_url`; before `_url_segment` a `/`, `?` or `#` 404ed, a space threw
    # in URI parsing, and a literal `a%20b` reached the child as `a b`.
    encoded = ["group_1/model_7" => "group_1%2Fmodel_7", "a?b" => "a%3Fb",
               "a#b" => "a%23b", "a b" => "a%20b", "a%20b" => "a%2520b",
               "50%" => "50%25", "a\\b" => "a%5Cb", "a\tb" => "a%09b"]
    for (key, segment) in encoded
        @test app.rows(key).__prefix__ == "/rows/" * segment
        @test app.inline(key).__prefix__ == "/inline/" * segment
        @test app.rows(key) / "source" == "/rows/" * segment * "/source"
        @test body(app.rows(key) / "source") == "<p>source:" * esc(key) * ":n</p>"
        @test body(app.inline(key) / "source") == "<p>inline:" * esc(key) * "</p>"
        @test item_url(key) == "/item/" * segment
        @test body(item_url(key)) == "<p>item:" * esc(key) * "</p>"
    end

    # Every other byte stays literal, so a value that routed before keeps the
    # byte-identical URL (and with it the semantic target id and the static
    # recording file name).
    for key in ["plain", "a:b", "a@b", "a+b", "a,b;c=d", "a(b)!*'\$&", "aüb", "a\"b", "a~b.c-d_e"]
        @test app.rows(key).__prefix__ == "/rows/" * key
        @test app.inline(key).__prefix__ == "/inline/" * key
        @test item_url(key) == "/item/" * key
        @test body(app.rows(key) / "source") == "<p>source:" * esc(key) * ":n</p>"
    end
end

@testitem "node-valued indexed mounts use the option wire identity" setup=[UrlSegmentFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP

    route!(SegHost(); operation_policy=:blocking)
    app = SegHost()
    body(url) = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)

    # The inline form used `string(dataset)` — the node's Julia repr — which the
    # request side could never resolve against the `@options` domain.
    for dataset in SEG_DATASETS
        segment = replace(dataset.key, "/" => "%2F")
        external = app.external_dataset(dataset)
        inline = app.inline_dataset(dataset)
        @test external.__prefix__ == "/external_dataset/" * segment
        @test inline.__prefix__ == "/inline_dataset/" * segment
        @test body(external / "source") == "<p>source:" * dataset.key * ":n</p>"
        @test body(inline / "source") == "<p>inline-dataset:" * dataset.key * "</p>"
    end
end

@testitem "semantic surfaces under an encoded mount route back to the same child" setup=[UrlSegmentFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    route!(SegHost(); operation_policy=:blocking)
    app = SegHost()
    row = app.rows("group_1/model_7")

    html = repr("text/html", semantic_app(row))
    @test contains(html, "hx-get=\"/rows/group_1%2Fmodel_7/source\"")
    @test contains(html, "hx-post=\"/rows/group_1%2Fmodel_7/write\"")
    get_response = dispatch(:GET, "/rows/group_1%2Fmodel_7/source?note=x"; headers=["HX-Request" => "true"])
    @test get_response.status == 200
    @test String(get_response.body) == "<p>source:group_1/model_7:x</p>"
    post_response = dispatch(:POST, "/rows/group_1%2Fmodel_7/write";
        headers=["HX-Request" => "true", "Content-Type" => "application/x-www-form-urlencoded"],
        body="note=y")
    @test post_response.status == 200
    @test String(post_response.body) == "<p>write:group_1/model_7:y</p>"

    form = repr("text/html", operation_form(row, :source))
    @test contains(form, "\"/rows/group_1%2Fmodel_7/source\"")
    @test !contains(form, "/rows/group_1/model_7")

    # The mount-scoped result target encodes the full mount, so the value's `/`
    # cannot collide with a deeper mount `/rows/group_1` + `/model_7`.
    @test contains(html, "mount-" * bytes2hex(codeunits("/rows/group_1%2Fmodel_7")))
    @test navigation(row).current.path == "/rows/group_1%2Fmodel_7"
end

@testitem "Resource list links encode their keys" setup=[UrlSegmentFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP

    empty!(SEG_STORE)
    SEG_STORE["group/1"] = "slashed"
    SEG_STORE["plain"] = "plain"
    route!(SegHost(); operation_policy=:blocking)

    list = String(dispatch(:GET, "/store"; headers=["HX-Request" => "true"]).body)
    @test contains(list, "href=\"/store/group%2F1\"")
    @test contains(list, "href=\"/store/plain\"")
    shown = dispatch(:GET, "/store/group%2F1"; headers=["HX-Request" => "true"])
    @test shown.status == 200
    @test contains(String(shown.body), "slashed")
end
