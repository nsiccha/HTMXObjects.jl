using TestItemRunner

@testitem "JSON.jl preserves response and browser attribute values" tags=[:unit] begin
    using HTMXObjects, JSON, Dates

    # These values cross several independent HTTP/HTML boundaries. Test their
    # meaning, not the equivalent short versus Unicode spellings of escapes.
    text = "quotes \" slash \\ controls " * String(Char.(0:31)) * " ä 😀"
    payload = (; text, ignored="not declared", values=[Inf, -Inf, NaN, 1.5])
    T = @NamedTuple{text::String, values::Vector{Float64}, absent::Union{Nothing,Int}}
    response = to_response(JSONResponse{T}(payload))
    decoded = JSON.parse(response.body)
    @test collect(keys(decoded)) == ["text", "values", "absent"]
    @test decoded["text"] == text
    @test decoded["values"] == [nothing, nothing, nothing, 1.5]
    @test decoded["absent"] === nothing
    @test payload.ignored == "not declared"
    @test isequal(payload.values, [Inf, -Inf, NaN, 1.5])

    fields = (text=[text], values=[[1.5]], ignored=["extra column"])
    @test JSON.parse(to_response(JSONResponse{Vector{T}}(fields)).body) ==
        [JSON.Object("text" => text, "values" => [1.5], "absent" => nothing)]

    attrs = url_params(; key=text, values=(; key=[text, "other"]))
    params = HTMXObjects._url_params_decode(attrs.data_htmxo_url_params)
    @test only(params).value == text
    @test only(params).values == [text, "other"]
    @test HTMXObjects.group_path(JSON.json([text, "tail"])) == [text, "tail"]
    @test_throws ArgumentError HTMXObjects._url_params_decode("[[\"k\",\"k\",\"\\ud83d\",null]]")
    @test_throws ArgumentError HTMXObjects._url_params_decode("[[\"k\",\"k\",null,null],]")
    @test HTMXObjects._sort_values_count("[\"a,b\",null,1]") == 3
    @test HTMXObjects._sort_values_count("[1,]") == -1
    trigger = JSON.parse(live_thread_refresh(text; bottom=false))["htmxo:thread-refresh"]
    @test trigger == JSON.Object("bottom" => false, "target" => text)
    @test JSON.parse(sort_values(text, true, missing, NaN).data_htmxo_sort_keys) ==
        [text, 1, nothing, nothing]

    # Reflection deliberately describes Julia types and option pairs as
    # display strings and two-element arrays, rather than generic structs.
    schema = HTMXObjects._schema_json((; type=Vector{String},
        options=[:one => (; text)], absent=nothing, nonfinite=Inf))
    @test JSON.parse(schema) == JSON.Object("type" => "Vector{String}",
        "options" => [["one", JSON.Object("text" => text)]],
        "absent" => nothing, "nonfinite" => nothing)
end
