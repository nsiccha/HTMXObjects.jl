using TestItemRunner

@testitem "choice recovery uses only an enabled declared default" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    using HTMXObjects.DynamicObjects: option_domain

    @htmx struct RecoveryChoices
        @options(required_choice) = option_domain(["a", "b"])
        @options(literal_choice) = option_domain(["a", "b"])
        @options(unavailable_default) = option_domain(["a", "b"])
        @options(disabled_choice) = option_domain(["a", (; value="b", disabled=true)])
        @options(disabled_default) = option_domain(["a", (; value="b", disabled=true)])
        @options(number_choice) = [1, 3]
        @get required(; required_choice::String) = required_choice
        @get literal(; literal_choice::String="b") = literal_choice
        @get unavailable(; unavailable_default::String="gone") = unavailable_default
        @get disabled(; disabled_choice::String="a") = disabled_choice
        @get bad_default(; disabled_default::String="b") = disabled_default
        @get number(; number_choice::Int=1) = number_choice
    end
    app = RecoveryChoices()
    form(name; kwargs...) = repr("text/html", operation_form(app, name; kwargs...))
    selected(html) = [m.captures[1] for m in eachmatch(r"value=\"([^\"]*)\"[^>]* checked=\"true\"", html)]
    for kwargs in ((;), (; radio_max=0), (; presentation=:cards))
        @test isempty(selected(form(:required; values=(required_choice="gone",), kwargs...)))
        @test isempty(selected(form(:required; kwargs...)))
        @test selected(form(:literal; values=(literal_choice="gone",), kwargs...)) == ["b"]
        @test selected(form(:literal; values=(literal_choice="a",), kwargs...)) == ["a"]
        @test isempty(selected(form(:unavailable; values=(unavailable_default="gone",), kwargs...)))
        @test selected(form(:disabled; values=(disabled_choice="b",), kwargs...)) == ["a"]
        @test isempty(selected(form(:bad_default; values=(disabled_default="gone",), kwargs...)))
        @test selected(form(:number; values=(number_choice="03",), kwargs...)) == ["3"]
    end
end

@testitem "empty choices preserve typed defaults read by dependent relevance" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    using HTMXObjects.DynamicObjects: option_domain

    @htmx struct EmptyChoicesPage
        available::Vector{String}
        @param choice::String = isempty(available) ? "" : first(available)
        @options(choice) = option_domain([
            (; value=name, label=name, columns=(Name=name,)) for name in available])
        fields = isempty(choice) ? () : (:detail,)
        details = :detail in fields ? [choice * "-detail"] : String[]
        @param detail::String = isempty(details) ? "" : first(details)
        @options(detail) = option_domain([name => name for name in details])
        @relevant(detail) = :detail in fields
        @param direct::String = isempty(choice) ? "" : choice * "-direct"
        @options(direct) = option_domain(isempty(choice) ? String[] : [choice * "-direct"])
        @get result() = h.p("choice=", choice, ";detail=", detail, ";direct=", direct)
        @get index() = semantic_app(__self__; presentation=:tabs,
            select=entry -> entry.name !== :index)
    end

    for available in (String[], ["one"])
        app = EmptyChoicesPage(available)
        route!(app; operation_policy=:blocking)
        req = HTTP.Request("GET", "/")
        response = first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
        @test response.status == 200
        html = String(response.body)
        @test contains(html, "htmxo-semantic-page")
        @test !contains(html, "value=\"nothing\"")
        @test contains(html, "value=\"one\" checked=\"true\"") == !isempty(available)
        @test app.choice == (isempty(available) ? "" : "one")
        @test app.detail == (isempty(available) ? "" : "one-detail")
        @test app.direct == (isempty(available) ? "" : "one-direct")
        stale = dispatch(:GET, "/?choice=gone")
        @test stale.status == 200
        stale_form = String(stale.body)
        @test contains(stale_form, "htmxo-semantic-page")
        @test contains(stale_form, "value=\"one-detail\" checked=\"true\"") == !isempty(available)
        rejected = dispatch(:GET, "/result?choice=gone"; headers=["Accept" => "text/markdown"])
        @test rejected.status == 400
        @test HTTP.header(rejected, "X-HTMXO-Error-Param") == "choice"
        response = dispatch(:GET, "/result"; headers=["HX-Request" => "true"])
        @test response.status == 200
        @test contains(String(response.body), isempty(available) ?
            "choice=;detail=;direct=" : "choice=one;detail=one-detail;direct=one-direct")
    end
end

@testitem "choice recovery resolves object options and supplied dependencies" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP
    using HTMXObjects.DynamicObjects: option_domain, remount

    mutable struct Selection
        key::String
    end
    @htmx struct ObjectChoices
        @param group::String="a"
        @options(group) = ["a", "b"]
        choices = [Selection(group * "1"), Selection(group * "2")]
        current_choice = first(choices)
        @param pick::Selection = current_choice
        @options(pick) = option_domain([Selection(group * "1"), Selection(group * "2")])
        @get result() = h.p(group, ":", pick.key)
    end
    app = ObjectChoices()
    html = repr("text/html", operation_form(app, :result;
        values=(group="b", pick="a2")))
    @test contains(html, "value=\"b1\" checked=\"true\" data-htmxo-follows=\"\"")
    @test !contains(html, "value=\"a2\"")

    # The request body wins over its query fallback; resolving a choice does
    # not erase the other supplied inputs used by its computed default.
    req = HTTP.Request("POST", "/?group=a", ["Content-Type" => "application/x-www-form-urlencoded"],
                       "group=b&pick=a2")
    mounted = remount(app; __req__=req, __param_request__=HTMXObjects._param_request(req))
    html = repr("text/html", operation_form(mounted, :result))
    @test contains(html, "value=\"b1\" checked=\"true\" data-htmxo-follows=\"\"")
    kept = repr("text/html", operation_form(mounted, :result; values=(pick="b2",)))
    @test contains(kept, "value=\"b2\" checked=\"true\">")
end

@testitem "a range or default reads a typed input declared after it as the value it shows" tags=[:unit, :semantic] begin
    using HTMXObjects

    # A `:tabs` page draws its controls again when `b` changes. That request
    # sends each input as text, and an input with a range keeps its text until
    # its range is drawn. `a`'s range and `c`'s default read `b`, declared
    # after both, so they read `b` once it is drawn: before, `2b` was
    # `2 * "0.9"` and the reply was an error (snag `options-param-re-3392079f`).
    @htmx struct LaterRange
        "A"
        @param a::Float64 = 1.0
        @options(a) = number_domain(0.0, 2b; digits=3)
        "B"
        @param b::Float64 = 0.5
        @options(b) = number_domain(0.0, 1.0; digits=3)
        "Result"
        @get result() = h.p(a + b)
        @get index() = semantic_app(__self__; presentation=:tabs,
                                    select=entry -> entry.name !== :index)
    end
    @htmx struct LaterDefault
        "C"
        @param c::Float64 = 2b
        @options(c) = number_domain(0.0, 2.0; digits=3)
        "B"
        @param b::Float64 = 0.5
        @options(b) = number_domain(0.0, 1.0; digits=3)
        "Result"
        @get result() = h.p(b + c)
        @get index() = semantic_app(__self__; presentation=:tabs,
                                    select=entry -> entry.name !== :index)
    end
    # The controls the page asks for when `b` changes, sent with `query`.
    function redrawn(app, query)
        route!(app; operation_policy=:blocking)
        page = String(dispatch(:GET, "/").body)
        m = match(r"<div[^>]*hx-get=\"([^\"]*__htmxo_controls=1[^\"]*)\"[^>]*hx-trigger=\"change\"[^>]*>(?:(?!</div>).)*?name=\"b\""s, page)
        @test m !== nothing
        url = replace(m.captures[1], "&amp;" => "&") * "&" * query
        reply = String(dispatch(:GET, url; headers=["HX-Request" => "true"]).body)
        @test !contains(reply, "aria-invalid=\"true\"><header>Error")
        reply
    end

    # `a`'s range is drawn for the `b` the page sends.
    @test contains(redrawn(LaterRange(), "a=1.0&b=0.9"),
                   r"<input type=\"number\" name=\"a\" value=\"1\" min=\"0\" max=\"1\.8\"")
    # `c = 5.0` is outside its range, so `c` takes its default for that `b`,
    # and follows it.
    @test contains(redrawn(LaterDefault(), "c=5.0&b=0.9"),
                   r"<input type=\"number\" name=\"c\" value=\"1\.8\"[^>]*data-htmxo-follows=\"\"")
end
