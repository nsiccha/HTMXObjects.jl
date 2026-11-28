using TestItemRunner

# `formparams` and `formdata` read a form's text fields in either form
# encoding (snag `formparams-ignor-9e11e246`). Before, a multipart body gave
# `formparams` an empty dict, so a route body reading it saw no fields once its
# form gained a file input, and `formdata` parsed the multipart framing (or a
# JSON body) as urlencoded, throwing `ArgumentError` on a `%` in it.
@testitem "formparams and formdata read a multipart form's text fields" tags=[:unit] begin
    using HTMXObjects
    HTTP = HTMXObjects.HTTP

    boundary = "htmxoFormReaders"
    function multipart(parts)
        io = IOBuffer()
        for (name, value) in parts
            print(io, "--", boundary, "\r\n")
            if value isa Tuple
                print(io, "Content-Disposition: form-data; name=\"", name, "\"; filename=\"", value[1],
                      "\"\r\nContent-Type: ", value[3], "\r\n\r\n", value[2], "\r\n")
            else
                print(io, "Content-Disposition: form-data; name=\"", name, "\"\r\n\r\n", value, "\r\n")
            end
        end
        print(io, "--", boundary, "--\r\n")
        take!(io)
    end
    req(content_type, payload) = HTTP.Request("POST", "/p",
        content_type === nothing ? Pair{String,String}[] : ["Content-Type" => content_type],
        Vector{UInt8}(payload))
    mp(parts; content_type = "multipart/form-data; boundary=$(boundary)") =
        req(content_type, multipart(parts))
    form(payload) = req("application/x-www-form-urlencoded", payload)

    parts = ["dose" => "10", "tag" => "a", "tag" => "b", "note" => "50% off",
             "data" => ("obs.csv", "t,c\n0,1\n", "text/csv")]
    fields = formparams(mp(parts))
    @test fields isa Dict{String, Union{String, Vector{String}}}
    # The same fields sent urlencoded read the same; the file part is left out.
    @test fields == formparams(form("dose=10&tag=a&tag=b&note=50%25+off"))
    @test fields == Dict("dose" => "10", "tag" => ["a", "b"], "note" => "50% off")
    @test fields["tag"] isa Vector{String}
    last_values = formdata(mp(parts))
    @test last_values isa Dict{String, String}
    @test last_values == Dict("dose" => "10", "tag" => "b", "note" => "50% off")
    @test last_values == formdata(form("dose=10&tag=a&tag=b&note=50%25+off"))

    # A name sent both as text and as a file keeps only its text value.
    @test formparams(mp(["doc" => "draft", "doc" => ("a.txt", "x", "text/plain")])) ==
        Dict("doc" => "draft")
    # A file input left empty (`filename=""`) is a blank text field, exactly as
    # `multipartparams` reads it.
    empty_file = mp(["file" => ("", "", "application/octet-stream")])
    @test multipartparams(empty_file)["file"] == ""
    @test formparams(empty_file) == Dict("file" => "")
    # Reading leaves the body to the route.
    kept = mp(parts)
    formparams(kept)
    formdata(kept)
    @test multipartparams(kept)["data"].filename == "obs.csv"

    # No boundary: nothing to read. A body that does not parse under its
    # boundary is the caller's 400, as for `multipartparams`.
    @test isempty(formparams(mp(parts; content_type = "multipart/form-data")))
    unparseable = mp(parts; content_type = "multipart/form-data; boundary=other")
    @test_throws HTMXObjects.UnreadableBody formparams(unparseable)
    @test_throws HTMXObjects.UnreadableBody formdata(unparseable)

    # JSON and other bodies are not forms: an empty dict, never a urlencoded
    # parse of their bytes. `bodyparams` reads the JSON fields.
    json = req("application/json", "{\"note\": \"50% off\"}")
    @test isempty(formparams(json))
    @test isempty(formdata(json))
    @test bodyparams(json)["note"] == "50% off"
    @test isempty(formdata(req("application/octet-stream", "a=1&b=%zz")))
    # A body without a Content-Type still reads as urlencoded, and a bad
    # escape stays literal.
    headerless = req(nothing, "a=1&b=%zz&b=2")
    @test formparams(headerless) == Dict("a" => "1", "b" => ["%zz", "2"])
    @test formdata(headerless) == Dict("a" => "1", "b" => "2")
end

@testitem "a route body reading formparams sees a multipart form's fields" tags=[:unit] begin
    using HTMXObjects
    HTTP = HTMXObjects.HTTP

    # The pattern of a route that checks for fields beyond its keywords (an
    # unknown-field guard, a sent-or-not check).
    @htmx struct FormReaderRoutes
        @post submit(; note::String = "") =
            string("note=", note, " fields=", join(sort!(collect(keys(formparams(__req__)))), ","))
    end
    route!(FormReaderRoutes(); operation_policy=:blocking)
    body(r) = String(r.body)

    boundary = "htmxoFormRoute"
    payload = string(
        "--", boundary, "\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\nhi\r\n",
        "--", boundary, "\r\nContent-Disposition: form-data; name=\"bogus_field\"\r\n\r\n1\r\n",
        "--", boundary, "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n",
        "Content-Type: text/plain\r\n\r\nx\r\n--", boundary, "--\r\n")
    multipart = dispatch(:POST, "/submit?plain=1";
        headers=["Content-Type" => "multipart/form-data; boundary=$(boundary)"], body=payload)
    @test multipart.status == 200
    @test body(multipart) == "note=hi fields=bogus_field,note"
    urlencoded = dispatch(:POST, "/submit?plain=1";
        headers=["Content-Type" => "application/x-www-form-urlencoded"], body="note=hi&bogus_field=1")
    @test urlencoded.status == 200
    @test body(urlencoded) == "note=hi fields=bogus_field,note"
end
