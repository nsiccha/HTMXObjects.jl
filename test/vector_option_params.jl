using TestItemRunner

@testitem "a vector @param keeps its shape with one option submitted" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, JSON
    using HTMXObjects.DynamicObjects: option_domain

    @htmx struct VectorOptionParams
        @param drawn_quantities::Vector{String} = ["auc", "min_change"]
        @options(drawn_quantities) = option_domain([
            "auc" => "Area", "min_change" => "Minimum change",
            (; value="disabled", label="Unavailable", disabled=true)])
        @param doses::Vector{Int} = [1, 2]
        @options(doses) = [1, 2, 3]
        @param tags::Vector{Symbol} = [:auc]
        @options(tags) = [:auc, :min_change]
        @param plain::Vector{String} = ["default"]
        @param scalar::String = "auc"
        @options(scalar) = ["auc", "min_change"]
        result = HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json((;
            drawn_quantities, doses, tags, plain, scalar,
            minimum_selected=:min_change in Symbol.(drawn_quantities),
            typed=drawn_quantities isa Vector{String} && doses isa Vector{Int} &&
                  tags isa Vector{Symbol} && plain isa Vector{String} && scalar isa String)))
        @get index() = result
        @post index() = result
    end

    route!(VectorOptionParams(); operation_policy=:blocking)
    function request(query; method="GET", fallback="")
        req = method == "GET" ? HTTP.Request("GET", "/?" * query) :
              HTTP.Request("POST", "/" * fallback,
                  ["Content-Type" => "application/x-www-form-urlencoded"], query)
        first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
    end

    for method in ("GET", "POST")
        response = request("drawn_quantities=min_change&doses=3&tags=min_change&plain=one&scalar=min_change"; method)
        @test response.status == 200
        if response.status == 200
            value = JSON.parse(response.body)
            @test value["drawn_quantities"] == ["min_change"]
            @test value["doses"] == [3]
            @test value["tags"] == ["min_change"]
            @test value["plain"] == ["one"]
            @test value["scalar"] == "min_change"
            @test value["minimum_selected"] === true
            @test value["typed"] === true
        end
        response = request("drawn_quantities=auc&drawn_quantities=min_change&doses=3&doses=1&tags=auc&tags=min_change"; method)
        @test response.status == 200
        if response.status == 200
            value = JSON.parse(response.body)
            @test value["drawn_quantities"] == ["auc", "min_change"]
            @test value["doses"] == [3, 1]
            @test value["tags"] == ["auc", "min_change"]
            @test value["typed"] === true
        end
        for (query, expected) in (("", ["auc", "min_change"]), ("drawn_quantities=", String[]))
            response = request(query; method)
            @test response.status == 200
            @test JSON.parse(response.body)["drawn_quantities"] == expected
        end
        response = request("drawn_quantities=&doses=&tags=&plain=&scalar="; method,
                           fallback="?drawn_quantities=auc&doses=1")
        @test response.status == 200
        value = JSON.parse(response.body)
        @test all(isempty(value[name]) for name in ("drawn_quantities", "doses", "tags", "plain"))
        @test value["scalar"] == "auc"
        @test value["typed"] === true
        for query in ("drawn_quantities=unknown", "drawn_quantities=disabled",
                      "drawn_quantities=auc&drawn_quantities=unknown",
                      "drawn_quantities=auc&drawn_quantities=disabled", "doses=4")
            @testset "$method $query" begin
                @test request(query; method).status == 400
            end
        end
    end
    response = request(""; method="POST", fallback="?drawn_quantities=min_change")
    @test response.status == 200
    if response.status == 200
        @test JSON.parse(response.body)["drawn_quantities"] == ["min_change"]
    end
end

@testitem "vector options resolve live objects and preserve their container type" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    using HTMXObjects.DynamicObjects: option_domain

    abstract type Choice end
    struct NamedChoice <: Choice
        key::Symbol
    end
    first_choice, second_choice = NamedChoice(:first), NamedChoice(:second)
    choices = [first_choice, second_choice]
    options(_name) = option_domain(choices)
    extract(query, T) = HTMXObjects._extract_option_param(options,
        HTTP.Request("GET", "/?" * query), :selected, T)

    for T in (Vector{NamedChoice}, Vector{Choice}, AbstractVector{Choice}, Vector, AbstractVector)
        one = extract("selected=first", T)
        @test one isa T
        @test only(one) === first_choice
        many = extract("selected=second&selected=first&selected=second", T)
        @test many isa T
        @test many == [second_choice, first_choice, second_choice]
    end
    # An old form is checked against the domain for this request.
    current_options(_name) = option_domain([second_choice])
    @test_throws HTMXObjects.InvalidDomainValue HTMXObjects._extract_option_param(
        current_options, HTTP.Request("GET", "/?selected=first"), :selected, Vector{Choice})

    numeric_options(_name) = option_domain([1, 3])
    @test HTMXObjects._extract_option_param(numeric_options,
        HTTP.Request("GET", "/?selected=03"), :selected, Vector{Int}) == [3]
    @test choices == [first_choice, second_choice]
end
