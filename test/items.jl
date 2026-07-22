using TestItemRunner

# Shared imports are evaluated independently inside every test item.
@testsnippet HTMXOTestImports begin
    using Random, HTMXObjects, HTTP, Tables
    import HTMXObjects: _convert_param
end

# Route fixtures are evaluated once per TestItemRunner process and imported by
# each item. Test bodies remain independent while avoiding repeated macro work.
@testmodule HTMXOTestFixtures begin
using HTMXObjects

export TestApp, IndexApp, AllDefaultsApp, PostApp, TypedApp,
    NothingDefaultApp, RecordApp, ParamApp, ParamBlockApp,
    ParamRequiredApp, ParamPostApp, MountSubRoutes, MountRootApp,
    AppDataApp, AppDataSingletonApp, PrefixDefaultApp, HeaderApp,
    TestUIHost, ProviderApp, SemanticApp, SemanticAutoApp, IndexedSemanticAutoApp,
    ZeroConfigSemanticApp, ZeroConfigSemanticChild, ZeroConfigSemanticHost,
    PolicyApp, MultiVerbPolicyApp,
    StackedSemanticRoute, ContextSemanticApp, ExternalContextApp, ExternalContextChild, JobScopedApp,
    ParamlessHostApp, ParamlessHostChild,
    BareExternalApp, InlineContextApp,
    _SINGLETON_APPDATA

@htmx struct TestApp
    title = "Test"
    @get index() = h.h1(title)
    @get item(id) = h.p("Item: $id")
end

@htmx struct IndexApp
    @get index() = h.h1("home")
end

@htmx struct AllDefaultsApp
    @get viz(; pn="") = h.p("Viz: $(isempty(pn) ? "all" : pn)")
end

@htmx struct PostApp
    @post submit(; name="") = h.p("Hello $name")
end

@htmx struct TypedApp
    @get typed(n::Int) = h.p("N=$n")
end

@htmx struct NothingDefaultApp
    @get filtered(; filter=nothing) = h.p("filter=$(repr(filter))")
end

@htmx struct RecordApp
    @get index() = h.h1("Home")
    @get post(id) = h.p("Post $id")
end

@htmx struct ParamApp
    @param vessels::Vector{String} = ["Tablet-20"]
    @param n_bootstrap::String = "10"
    @param note = "default-note"
    @get index() = h.div("vessels=$(join(vessels, ",")) n=$n_bootstrap note=$note")
    child = struct ChildView
        @get show() = h.p("child sees: $(join(vessels, ",")) / $n_bootstrap")
    end
end

@htmx struct ParamBlockApp
    @param begin
        a::Int = 1
        b::String = "x"
    end
    @get index() = h.p("a=$a b=$b")
end

@htmx struct ParamRequiredApp
    @param fit_key::String
    @get index() = h.p("fit=$fit_key")
end

@htmx struct ParamPostApp
    @param name::String = "anon"
    @post submit() = h.p("submit $name")
end

# For __self__/"path" + __appdata__ smoke tests
@htmx struct MountSubRoutes
    @get show() = h.p("sub show: $(__self__/"x")")
end

@htmx struct MountRootApp
    @get index() = h.p("root index: $(__self__/"foo")")
    @include sub = MountSubRoutes()
end

@htmx struct AppDataApp
    @get index() = h.p("appdata=$(repr(__appdata__))")
    @include sub = MountSubRoutes()
end

# Module-level singleton pattern: struct body sets __appdata__ default
const _SINGLETON_APPDATA = (; counter=Ref(7), label="singleton")

@htmx struct AppDataSingletonApp
    __appdata__ = _SINGLETON_APPDATA
    @get index() = h.p("appdata=$(repr(__appdata__))")
    @include sub = MountSubRoutes()
end

# Struct-body-default __prefix__ — must survive route!() with no explicit
# `prefix=` kwarg. The conditional-prefix logic in _register_routes is what
# keeps the struct's own default from being clobbered by an empty mount_prefix.
@htmx struct PrefixDefaultApp
    __prefix__ = "/baked-in"
    @get index() = h.p("root: $(__self__/"foo")")
    @include sub = MountSubRoutes()
end

@htmx struct HeaderApp
    @header x_test_agent::String = ""
    @header x_count::Int = 0

    @get probe() = "agent=$(x_test_agent) count=$(x_count)"
end

@htmx struct TestUIHost
    @include tests = TestRoutes(; project=pkgdir(HTMXObjects))
end

@htmx struct ProviderApp
    label::String

    @get index() = h.p("root $(label)")
    @include nested = begin
        @get show(; count::Int) = h.p("$(label):$(count):$(__route__)")
        @ws stream(id::Int; suffix::String) = "$(label):$(id):$(suffix):$(__route__)"
    end
end

@htmx struct SemanticApp
    choices(cohort::Symbol) = cohort === :north ? (
        (value=:n1, label="North 1", group="North"),
        (value=:n2, label="North 2", disabled=true),
    ) : (:s1,)

    @semantic (inputs=(
        dataset=(domain=dynamic_domain(:choices; dependencies=(:cohort,)),),
        mode=(domain=static_domain((
            (value=:fast, label="Fast"),
            (value=:safe, label="Safe", help="Full checks"),
            (value=:unsafe, label="Unsafe", disabled=true),
        )),),
    ),) @get run(; dataset::Symbol, cohort::Symbol=:north,
                    mode::Symbol=:fast, count::Int=1) =
        h.p("$(dataset):$(cohort):$(mode):$(count)")

    @include nested = begin
        @semantic (inputs=(quality=(domain=static_domain((:quick, :full)),),),) @post execute(; quality::Symbol=:quick) =
            h.p("nested:$(quality)")
    end
end

# The graph is the only operation registry: adding another route inside this
# mounted child is enough for `semantic_app` to discover, render, and execute
# it. The enclosing selection is declared once and inherited as hidden context.
@htmx struct SemanticAutoApp
    @param study::Symbol = :alpha

    @include models = begin
        @semantic (inputs=(model=(domain=static_domain((:base, :full)),),),) @get fit(; model::Symbol=:base) =
            h.p("fit:$(study):$(model)")

        @semantic (inputs=(draws=(domain=static_domain((10, 20)),),),) @post predict(; draws::Int=10) =
            h.p("predict:$(study):$(draws)")
    end
end

@htmx struct IndexedSemanticAutoApp
    @include models(model::Symbol) = begin
        @semantic (inputs=(mode=(domain=static_domain((:quick, :full)),),),) @get run(; mode::Symbol=:quick) =
            h.p("$(model):$(mode)")
    end
end

@htmx struct ZeroConfigSemanticApp
    @semantic (inputs=(study=(domain=static_domain((:north, :south)),),),) study::Symbol
    @semantic (inputs=(dose=(domain=static_domain((50, 100)),),),) dose::Int

    unrelated = Ref("survives")

    @get fit() = h.p("fit:$(study):$(dose):$(objectid(unrelated))")
    @post predict() = h.p("predict:$(study):$(dose):$(objectid(unrelated))")
end


@htmx struct ZeroConfigSemanticChild
    @semantic (inputs=(study=(domain=static_domain((:north, :south)),),),) study::Symbol
    @semantic (inputs=(dose=(domain=static_domain((50, 100)),),),) dose::Int

    unrelated = Ref("mounted-survives")

    @post predict() = h.p("mounted:$(study):$(dose):$(objectid(unrelated))")
end


@htmx struct ZeroConfigSemanticHost
    @include models = ZeroConfigSemanticChild(:north, 50)
end

@htmx struct ContextSemanticApp
    @param fit_key::String

    @include analysis = begin
        model_options(study::Symbol) = study === :alpha ? (
            (value=:a1, label="Alpha 1"),
            (value=:a2, label="Alpha 2"),
        ) : (
            (value=:b1, label="Beta 1"),
            (value=:b2, label="Beta 2"),
        )

        @semantic (inputs=(
            study=(domain=static_domain((
                (value=:alpha, label="Alpha"),
                (value=:beta, label="Beta"),
            )),),
            model=(domain=dynamic_domain(:model_options;
                                         dependencies=(:study,)),),
        ),) @get analyze(; study::Symbol=:alpha, model::Symbol) =
            h.p("$(fit_key):$(study):$(model)")

        @get raw_context(; count::Int=1)::MIMEResponse =
            MIMEResponse("text/plain", "$(fit_key):$(count)")
    end
end

# A separately declared child that also *reads* the enclosing `@param` in its
# own route body needs the delegation line: `operation_form` carries the
# enclosing value as hidden context for either include shape, but only an
# inline child inherits the parent's `@param` as a property. Without the
# delegation, `fit_key` here is an unbound name and the route throws
# `UndefVarError` the first time it is actually executed.
@htmx struct ExternalContextChild
    @param (; fit_key) = __parent__
    @semantic (inputs=(value=(domain=static_domain((:ok, :alt)),),),) @get analyze(; value::Symbol=:ok) =
        h.p("$(fit_key):$(value)")
    @get structured(; value::Symbol=:ok) =
        (summary=h.p("structured:$(value)"), status="ready")
end

@htmx struct ExternalContextApp
    @param fit_key::String
    @include models = ExternalContextChild()
end

# A parent that declares NO params: its @include child stays renderable
# standalone, since there is no inherited context to lose.
@htmx struct ParamlessHostChild
    @semantic (inputs=(value=(domain=static_domain((:ok, :alt)),),),) @get analyze(; value::Symbol=:ok) =
        h.p("paramless:$(value)")
end

@htmx struct ParamlessHostApp
    @include kid = ParamlessHostChild()
    @get index() = h.div("host")
end

# Job-scoped root provider fixture: an @param the root reads, plus a mounted
# external child whose generated form must carry the *current* request's value.
@htmx struct JobScopedApp
    payload = "none"
    @param fit_key::String
    @include models = ExternalContextChild()
    @get index() = h.div(h.span(fit_key), h.span(payload),
                         operation_form(models, :analyze; target_id="#job"))
end

# The same mount without the delegation — the form still carries the context,
# but the child owns no `fit_key` property.
@htmx struct BareExternalChild
    @get probe(; note::String="hi") = h.p("bare:$(note)")
end

@htmx struct BareExternalApp
    @param fit_key::String
    @include models = BareExternalChild()
end

@htmx struct InlineContextApp
    @param fit_key::String
    @include models = begin
        @get probe(; note::String="hi") = h.p("inline:$(note)")
    end
end

@htmx struct PolicyApp
    @get html(; count::Int=1) = h.p("html:$(count)")
    @get raw(; count::Int=1)::MIMEResponse =
        MIMEResponse("text/plain", "raw:$(count)")
    @get response(; count::Int=1)::HTTP.Response =
        HTTP.Response(202, ["Content-Type" => "application/json"];
                      body="{\"count\":$(count)}")
    @ws stream(; count::Int=1) = "ws:$(count)"
end

@htmx struct MultiVerbPolicyApp
    @semantic (inputs=(mode=(domain=static_domain((:raw, :json)),),),) @get exchange(; mode::Symbol=:raw)::MIMEResponse =
        MIMEResponse("text/plain", "get:$(mode)")
    @semantic (inputs=(count=(domain=static_domain((1, 2)),),),) @post exchange(; count::Int=1) =
        h.p("post:$(count)")
end

# One declaration owns its semantic input, route, disk materialization, and
# progress policy. The typed call LHS exercises the route-return annotation
# parser while leaving the annotation visible to DynamicObjects.
@htmx struct StackedSemanticRoute
    __cache_base__ = tempdir()
    @semantic (inputs=(count=(domain=static_domain((1, 2, 3)),),),) @get @mmap @progress model(; count::Int=2)::Vector{Float64} =
        collect(1.0:count)
end

end # @testmodule HTMXOTestFixtures

# --- Tests ---

"""
Checks the core HTML conversion contract for nodes, arrays, literal HTML, and
out-of-band swap pairs. These are the values route handlers most commonly
return to the response pipeline.
"""
@testitem "auto - HTML rendering" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    result = auto(h.div("hello"); wrap=identity)
    @test contains(result, "<div>")
    @test contains(result, "hello")
    @test auto("<p>test</p>"; wrap=identity) == "<p>test</p>"
    result = auto([h.p("a"), h.p("b")]; wrap=identity)
    @test contains(result, "<p>a</p>")
    @test contains(result, "<p>b</p>")
    result = auto(h.span("new") => "my-id"; wrap=identity)
    @test contains(result, "id=\"my-id\"")
    @test contains(result, "hx-swap-oob")
    @test contains(result, "new")
end

@testitem "to_response" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    resp = to_response(h.div("hello"))
    @test resp.status == 200
    @test contains(String(resp.body), "<div>")
    @test any(p.first == "Content-Type" && contains(p.second, "text/html")
              for p in resp.headers)
    resp = to_response("<p>test</p>")
    @test resp.status == 200
    @test String(resp.body) == "<p>test</p>"
    resp = to_response([h.p("a"), h.p("b")])
    @test contains(String(resp.body), "<p>a</p>")
    orig = HTTP.Response(201; body="custom")
    @test to_response(orig) === orig
end

@testitem "HTMX request header inspection" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    htmx_req = HTTP.Request("GET", "/",
        ["HX-Request" => "true", "HX-Target" => "#result",
         "HX-Trigger" => "btn", "HX-Current-URL" => "http://localhost/",
         "HX-Boosted" => "true", "HX-Prompt" => "yes"])
    @test is_htmx(htmx_req)
    @test hx_target(htmx_req) == "#result"
    @test hx_trigger(htmx_req) == "btn"
    @test hx_current_url(htmx_req) == "http://localhost/"
    @test hx_boosted(htmx_req)
    @test hx_prompt(htmx_req) == "yes"
    plain_req = HTTP.Request("GET", "/")
    @test !is_htmx(plain_req)
    @test hx_target(plain_req) == ""
    @test !hx_boosted(plain_req)
end

@testitem "hx_response headers" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    base = h.div("content")
    resp = hx_response(base; trigger="myEvent")
    @test any(p.first == "HX-Trigger" && p.second == "myEvent"
              for p in resp.headers)
    resp = hx_response(base; push_url="/new-path")
    @test any(p.first == "HX-Push-Url" && p.second == "/new-path"
              for p in resp.headers)
    resp = hx_response(base; replace_url="/replaced")
    @test any(p.first == "HX-Replace-Url" for p in resp.headers)
    resp = hx_response(base; redirect="/other")
    @test any(p.first == "HX-Redirect" for p in resp.headers)
    resp = hx_response(base; refresh=true)
    @test any(p.first == "HX-Refresh" && p.second == "true"
              for p in resp.headers)
    resp = hx_response(base; retarget="#foo", reswap="outerHTML")
    @test any(p.first == "HX-Retarget" && p.second == "#foo" for p in resp.headers)
    @test any(p.first == "HX-Reswap" && p.second == "outerHTML" for p in resp.headers)
    @test contains(String(resp.body), "<div>")
    resp0 = hx_response(base)
    @test !any(startswith(p.first, "HX-") for p in resp0.headers)
end

@testitem "@htmx struct - property access" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    app = TestApp()
    @test app.title == "Test"
    html = repr("text/html", app.index(Verb{:GET}()))
    @test contains(html, "Test")
    html = repr("text/html", app.item(Verb{:GET}(), "foo"))
    @test contains(html, "foo")
    @test Symbol("@get") in DynamicObjects.metafirst(TestApp, :index).macros
    @test !(Symbol("@get") in DynamicObjects.metafirst(TestApp, :title).macros)
end

@testitem "root provider and shared operation runner" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _base_segments, _operation_target, _run_operation

    seen = OperationContext[]
    provider = RootProvider(
        (RootT, context) -> begin
            push!(seen, context)
            RootT(String(context.key); __req__=context.request,
                  __route__=context.route, __prefix__=context.prefix)
        end;
        scope=:session,
        key=req -> HTTP.header(req, "X-Session", "missing"),
    )

    route!(ProviderApp("registered"); root_provider=provider)
    req = HTTP.Request("GET", "/nested/show?count=7", ["X-Session" => "session-a"])
    handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))
    resp = handler(req)
    @test resp.status == 200
    @test contains(String(resp.body), "session-a:7:/nested/show")
    @test only(seen).scope === :session
    @test only(seen).key == "session-a"
    @test only(seen).transport === :http

    bad_req = HTTP.Request("GET", "/nested/show?count=not-an-int",
                           ["X-Session" => "session-a"])
    bad_handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, bad_req))
    @test bad_handler(bad_req).status == 500

    ws_req = HTTP.Request("GET", "/nested/stream/4?suffix=ok", ["X-Session" => "session-b"])
    chain_info = DynamicObjects.metafirst(ProviderApp, :nested)
    NestedT = DynamicObjects._nested_struct_type(ProviderApp, Val(:nested))
    nested_prefix, step = HTMXObjects._nested_prefix_and_step(ProviderApp, :nested, chain_info, "")
    target = _operation_target(provider, ProviderApp, [step], ws_req, "", 0, :websocket)
    operation = _run_operation(target, NestedT, :stream, Verb{:WEBSOCKET}(),
                               ws_req, _base_segments("/nested/stream/{id}", 1), 1)
    @test operation.value(nothing) == "session-b:4:ok:/nested/stream/4"
    @test last(seen).transport === :websocket
    @test nested_prefix == "nested"

    @test_throws ArgumentError RootProvider(identity; scope=:pod)
    @test_throws ArgumentError RootProvider(identity; scope=:job)
end

@testitem "semantic descriptor, generated controls, and domain validation" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    descriptor = semantic_descriptor(SemanticApp)
    @test descriptor.type === SemanticApp
    @test only(descriptor.graph.children).name === :nested
    @test any(property -> property.name === :choices, descriptor.graph.properties)

    route = only(filter(route -> route.owner === SemanticApp &&
                                 route.name === :run && route.verb === :GET,
                        descriptor.routes))
    @test route.property.semantics.pending
    dataset = only(filter(param -> param.name === :dataset, route.params))
    mode = only(filter(param -> param.name === :mode, route.params))
    @test dataset.domain.kind === :dynamic
    @test dataset.domain.provider === :choices
    @test dataset.domain.dependencies == [:cohort]
    @test mode.domain.kind === :static
    @test mode.domain.cardinality == 3
    @test mode.default === :fast

    # The pre-existing reflection API remains byte-shape compatible.
    reflected = only(filter(route -> route.name === :run, HTMXObjects.reflect(SemanticApp)))
    @test keys(reflected) == (:verb, :path, :name, :doc, :params)

    app = SemanticApp()
    html = repr("text/html", operation_form(app, :run; values=(cohort=:north,),
                                             target_id="#semantic-result"))
    @test contains(html, "hx-get=\"/run\"")
    @test contains(html, "hx-target=\"#semantic-result\"")
    @test contains(html, "North 1")
    @test contains(html, "North 2")
    @test contains(html, "disabled=\"true\"")
    @test contains(html, "type=\"number\"")
    @test contains(html, "name=\"count\"")

    route!(app)
    good = HTTP.Request("GET", "/run?dataset=n1&cohort=north&mode=fast&count=2")
    good_handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, good))
    good_response = good_handler(good)
    @test good_response.status == 200
    @test contains(String(good_response.body), "n1:north:fast:2")

    disabled = HTTP.Request("GET", "/run?dataset=n2&cohort=north&mode=fast&count=2")
    disabled_handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, disabled))
    disabled_response = disabled_handler(disabled)
    @test disabled_response.status == 400
    @test contains(String(disabled_response.body), "Bad Request")

    tampered = HTTP.Request("GET", "/run?dataset=n1&cohort=north&mode=turbo&count=2")
    tampered_handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, tampered))
    tampered_response = tampered_handler(tampered)
    @test tampered_response.status == 400
end

@testitem "semantic app compiles one mounted graph without an operation registry" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _is_semantic_root_provider, _operation_context,
                        _root_providers

    app = SemanticAutoApp(; __cache_base__=mktempdir())
    descriptor = semantic_descriptor(app)
    @test [(route.verb, route.path) for route in descriptor.routes] ==
          [(:GET, "/models/fit"), (:POST, "/models/predict")]

    rendered = semantic_app(
        app;
        title="Model operations",
        submit=entry -> entry.name === :fit ? "Fit" : "Predict",
    )
    html = repr("text/html", rendered)
    @test contains(html, "Model operations")
    @test contains(html, "GET /models/fit")
    @test contains(html, "POST /models/predict")
    @test contains(html, "hx-get=\"/models/fit\"")
    @test contains(html, "hx-post=\"/models/predict\"")
    @test contains(html, ">Fit</button>")
    @test contains(html, ">Predict</button>")
    @test contains(html, "type=\"hidden\" name=\"study\" value=\"alpha\"")
    @test count("class=\"htmxo-semantic-operation\"", html) == 2
    @test count("class=\"htmxo-semantic-operation-result\"", html) == 2
    @test findfirst("GET /models/fit", html) < findfirst("POST /models/predict", html)

    # Rendering the semantic graph is the existing declaration that selects a
    # managed provider. No key callback, Dict, lock, factory, or explicit
    # RootProvider is application code, and a later route! preserves the
    # compiler-selected provider.
    provider = _root_providers[SemanticAutoApp]
    @test _is_semantic_root_provider(provider)
    @test provider.factory.entries[(SemanticAutoApp, "")].value === app
    route!(app)
    @test _root_providers[SemanticAutoApp] === provider
    registered = _operation_context(
        provider, HTTP.Request("GET", "/semantic/models/fit"),
        "/semantic", :http)
    @test registered.prefix == "/semantic"
    @test registered.key == "/semantic"
    forwarded = _operation_context(
        provider,
        HTTP.Request("GET", "/models/fit", ["X-Forwarded-Prefix" => "/p/sbpmx/"]),
        "", :http)
    @test forwarded.prefix == "/p/sbpmx"
    @test forwarded.key == "/p/sbpmx"

    fit = HTTP.Request("GET", "/models/fit?study=alpha&model=full")
    fit_handler = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, fit))
    fit_response = fit_handler(fit)
    @test fit_response.status == 200
    @test contains(String(fit_response.body), "fit:alpha:full")

    predict = HTTP.Request("POST", "/models/predict",
        ["Content-Type" => "application/x-www-form-urlencoded"],
        "study=alpha&draws=20")
    predict_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, predict))
    predict_response = predict_handler(predict)
    @test predict_response.status == 200
    @test contains(String(predict_response.body), "predict:alpha:20")
    @test length(provider.factory.entries) == 1
    @test haskey(provider.factory.entries, (SemanticAutoApp, ""))

    # A request-bound graph rendered on the first page is seeded directly;
    # later operation requests remount this rooted source rather than building
    # a parallel application-owned store.
    _root_providers[SemanticAutoApp] = RootProvider()
    seed_req = HTTP.Request("GET", "/", ["X-Forwarded-Prefix" => "/p/seed"])
    seeded_root = SemanticAutoApp(; __req__=seed_req, __prefix__="/p/seed",
                                  __cache_base__=mktempdir())
    semantic_app(seeded_root)
    seeded_provider = _root_providers[SemanticAutoApp]
    @test seeded_provider.factory.entries[(SemanticAutoApp, "/p/seed")].value ===
          seeded_root

    custom = RootProvider((RootT, context) -> RootT(
        ; __req__=context.request, __route__=context.route,
          __prefix__=context.prefix))
    _root_providers[SemanticAutoApp] = custom
    semantic_app(seeded_root)
    @test _root_providers[SemanticAutoApp] === custom

    indexed_error = try
        semantic_app(IndexedSemanticAutoApp())
        nothing
    catch err
        err
    end
    @test indexed_error isa ArgumentError
    @test contains(indexed_error.msg, "Indexed `@include` children need a selected index")

    selected_html = repr("text/html", semantic_app(IndexedSemanticAutoApp().models(:one)))
    @test contains(selected_html, "hx-get=\"/models/one/run\"")
end

@testitem "zero-config fixed semantic context remakes mounted targets" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _root_providers

    app = ZeroConfigSemanticApp(:north, 50; __cache_base__=mktempdir())
    unrelated = app.unrelated
    descriptor = semantic_descriptor(app)
    predict = only(filter(route -> route.name === :predict, descriptor.routes))

    # The executable route has no declared arguments. Effective fixed-field
    # dependencies are nevertheless first-class semantic context params; the
    # transport-only reflection surface remains unchanged.
    @test getproperty.(predict.params, :name) == [:study, :dose]
    @test all(param -> param.kind === :context, predict.params)
    @test isempty(only(filter(route -> route.name === :predict,
                              HTMXObjects.reflect(ZeroConfigSemanticApp))).params)

    html = repr("text/html", semantic_app(app; title="Zero configuration"))
    @test count("<legend>study</legend>", html) == 1
    @test count("<legend>dose</legend>", html) == 1
    @test count("class=\"htmxo-semantic-context\"", html) == 1
    @test count("hx-include=\"#htmxo-semantic-context-zeroconfigsemanticapp\"",
                html) == 2

    route!(app)
    request = HTTP.Request(
        "POST", "/predict",
        ["Content-Type" => "application/x-www-form-urlencoded"],
        "study=south&dose=100",
    )
    handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, request))
    response = handler(request)
    @test response.status == 200
    @test contains(String(response.body),
                   "predict:south:100:$(objectid(unrelated))")

    provider = _root_providers[ZeroConfigSemanticApp]
    source = provider.factory.entries[(ZeroConfigSemanticApp, "")].value
    @test source === app
    @test source.study === :north
    @test source.dose == 50
    @test source.unrelated === unrelated
    ownership = HTMXObjects.DynamicObjects.materialization_ownership(
        (; scope=:job, key="", retention=(; max_entries=128, ttl=nothing)),
        source,
    )
    @test ownership.state === :active
    @test ownership.scope === :job
    @test ownership.retention == (; max_entries=128, ttl=nothing)

    # The same contract holds for a fixed semantic bundle mounted externally:
    # remake the child selected by the registered chain, keep the retained root
    # as the governed owner, and preserve unrelated child cache identity.
    host = ZeroConfigSemanticHost(; __cache_base__=mktempdir())
    mounted_unrelated = host.models.unrelated
    mounted_html = repr("text/html", semantic_app(host))
    @test count("<legend>study</legend>", mounted_html) == 1
    @test count("<legend>dose</legend>", mounted_html) == 1
    @test count("class=\"htmxo-semantic-context\"", mounted_html) == 1
    @test count("hx-include=\"#htmxo-semantic-context-zeroconfigsemantichost\"",
                mounted_html) == 1

    route!(host)
    mounted_request = HTTP.Request(
        "POST", "/models/predict",
        ["Content-Type" => "application/x-www-form-urlencoded"],
        "study=south&dose=100",
    )
    mounted_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, mounted_request))
    mounted_response = mounted_handler(mounted_request)
    @test mounted_response.status == 200
    @test contains(String(mounted_response.body),
                   "mounted:south:100:$(objectid(mounted_unrelated))")
    retained_host = _root_providers[ZeroConfigSemanticHost].factory.entries[
        (ZeroConfigSemanticHost, "")].value
    @test retained_host === host
    @test retained_host.models.study === :north
    @test retained_host.models.dose == 50
    @test retained_host.models.unrelated === mounted_unrelated
end

@testitem "generated semantic form context and dependent refresh" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _operation_polling_impl, _run_operation

    app_req = HTTP.Request("GET", "/?fit_key=fit-17")
    app = ContextSemanticApp(; __req__=app_req)
    leaf = app.analysis
    html = repr("text/html", operation_form(
        leaf, :analyze; values=(study=:alpha,), target_id="#analysis",
        submit="Analyze", form_class="semantic-form"))

    # Root context is inferred from the request and carried, never exposed as
    # another generated operation control.
    @test contains(html, "type=\"hidden\" name=\"fit_key\" value=\"fit-17\"")
    @test !contains(html, ">fit key<")
    @test contains(html, "hx-get=\"/analysis/analyze?__htmxo_form=1\"")
    @test contains(html, "hx-include=\"closest form\"")
    @test contains(html, "hx-target=\"closest form\"")
    @test contains(html, "Alpha 1")
    @test contains(html, "name=\"__htmxo_target_id\" value=\"#analysis\"")

    # The same query context survives the automatic poll URL. The poll marker
    # is additive; typed operation inputs remain separate from root @params.
    poll_req = HTTP.Request(
        "GET", "/analysis/analyze?fit_key=fit-17&study=alpha&model=a1",
        ["HX-Request" => "true"],
    )
    poll_app = ContextSemanticApp(; __req__=poll_req)
    poll_leaf = poll_app.analysis
    transport = Ref{Any}()
    old_polling = _operation_polling_impl[]
    _operation_polling_impl[] =
        (_render, _started, _ip, _keys, call_kwargs, seen_transport) -> begin
            transport[] = (; call_kwargs, seen_transport)
            h.aside("polling")
        end
    try
        operation = _run_operation(
            (context=nothing, root=poll_app, leaf=poll_leaf),
            typeof(poll_leaf), :analyze, Verb{:GET}(), poll_req, 0, 0;
            operation_policy=OperationPolicy(:auto),
        )
        @test repr("text/html", operation.value) == "<aside>polling</aside>"
        @test transport[].call_kwargs == (study=:alpha, model=:a1)
        @test transport[].seen_transport.poll_url ==
              "/analysis/analyze?fit_key=fit-17&study=alpha&model=a1&__htmxo_poll=1"
        @test poll_leaf.fit_key == "fit-17"
    finally
        _operation_polling_impl[] = old_polling
    end

    route!(app; operation_policy=:auto)
    refresh = HTTP.Request(
        "GET",
        "/analysis/analyze?__htmxo_form=1&fit_key=fit-17&study=beta&" *
        "__htmxo_target_id=%23analysis&__htmxo_submit=Analyze&" *
        "__htmxo_form_class=semantic-form&__htmxo_swap=innerHTML&" *
        "__htmxo_radio_max=4",
        ["HX-Request" => "true"],
    )
    refresh_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, refresh))
    refreshed = refresh_handler(refresh)
    refreshed_html = String(refreshed.body)
    @test refreshed.status == 200
    @test contains(refreshed_html, "Beta 1")
    @test !contains(refreshed_html, "Alpha 1")
    @test contains(refreshed_html, "hx-target=\"#analysis\"")
    @test contains(refreshed_html, "class=\"semantic-form\"")
    @test contains(refreshed_html,
                   "type=\"hidden\" name=\"fit_key\" value=\"fit-17\"")

    good = HTTP.Request(
        "GET", "/analysis/analyze?fit_key=fit-17&study=beta&model=b1")
    good_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, good))
    good_response = good_handler(good)
    @test good_response.status == 200
    @test contains(String(good_response.body), "fit-17:beta:b1")

    forged = HTTP.Request(
        "GET", "/analysis/analyze?fit_key=fit-17&study=beta&model=a1")
    forged_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, forged))
    forged_response = forged_handler(forged)
    @test forged_response.status == 400

    raw = HTTP.Request(
        "GET", "/analysis/raw_context?fit_key=fit-17&count=3",
        ["HX-Request" => "true"],
    )
    raw_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, raw))
    raw_response = raw_handler(raw)
    @test raw_response.status == 200
    @test HTTP.header(raw_response, "Content-Type") == "text/plain"
    @test String(raw_response.body) == "fit-17:3"
end

@testitem "external mounted child preserves enclosing form context" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _param_names

    app = ExternalContextApp(; __req__=HTTP.Request("GET", "/?fit_key=external-fit"))
    child = app.models
    html = repr("text/html", operation_form(child, :analyze; target_id="#external"))
    @test contains(html, "type=\"hidden\" name=\"fit_key\" value=\"external-fit\"")
    @test contains(html, "hx-get=\"/models/analyze\"")
    @test contains(html, "name=\"value\"")

    route!(app)
    structured_req = HTTP.Request("GET", "/models/structured?fit_key=external-fit&value=alt",
                                  ["HX-Request" => "true"])
    structured_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, structured_req))
    structured_response = structured_handler(structured_req)
    @test structured_response.status == 200
    @test contains(String(structured_response.body), "structured:alt")
    @test contains(String(structured_response.body), "ready")

    # Executing the route is what distinguishes a child that merely *renders*
    # the enclosing context from one that can actually read it. The delegation
    # line on ExternalContextChild is what makes this work.
    @test _param_names(typeof(child)) == (:fit_key,)
    @test child.fit_key == "external-fit"
    @test repr("text/html", child.analyze(Verb{:GET}(); value=:alt)) ==
          "<p>external-fit:alt</p>"
end

@testitem "scoped root providers retain and remount roots" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _ManagedRootFactory, _managed_root_release_handler,
                        _operation_context, _provide_root

    job_key(req) = HTTP.header(req, "X-Job", "default")
    hit(target; job="job-a") = begin
        req = HTTP.Request("GET", target, ["X-Job" => job])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    @test !ismutabletype(JobScopedApp)
    @test RootRetention().max_entries == 128
    @test RootRetention(ttl=60).ttl == 60.0
    @test_throws ArgumentError RootRetention(max_entries=0)
    @test_throws ArgumentError RootRetention(ttl=0)
    @test_throws ArgumentError RootProvider(
        scope=:request, retention=RootRetention())
    @test_throws ArgumentError RootProvider(
        scope=:job, key=job_key, retention=:managed)

    # The custom factory adapter remains available for application/distributed
    # stores that retain their own payload rather than the routed root.
    builds = Ref(0)
    payloads = Dict{Any,String}()
    custom = RootProvider(; scope=:job, key=job_key) do RootT, context
        retained = get!(() -> (builds[] += 1; "payload-$(builds[])"),
                        payloads, context.key)
        RootT(; payload=retained, __req__=context.request, __route__=context.route,
              (isempty(context.prefix) ? (;) : (; __prefix__=context.prefix))...)
    end
    route!(JobScopedApp(); root_provider=custom)

    first_resp = hit("/?fit_key=first-key")
    second_resp = hit("/?fit_key=second-key")
    @test first_resp.status == 200
    @test second_resp.status == 200
    @test contains(String(first_resp.body), "payload-1")
    @test contains(String(second_resp.body), "payload-1")
    @test builds[] == 1
    @test contains(String(first_resp.body),
                   "type=\"hidden\" name=\"fit_key\" value=\"first-key\"")
    @test contains(String(second_resp.body),
                   "type=\"hidden\" name=\"fit_key\" value=\"second-key\"")

    # Managed retention replaces the common application-owned Dict + lock +
    # factory. The stored source root is stable while each request receives a
    # remounted view with current params, route, prefix, and mounted children.
    managed = RootProvider(
        scope=:job,
        key=job_key,
        retention=RootRetention(max_entries=2),
    )
    route!(JobScopedApp(); root_provider=managed)
    managed_first = hit("/?fit_key=managed-first")
    managed_second = hit("/?fit_key=managed-second")
    @test managed_first.status == 200
    @test managed_second.status == 200
    @test contains(String(managed_first.body),
                   "type=\"hidden\" name=\"fit_key\" value=\"managed-first\"")
    @test contains(String(managed_second.body),
                   "type=\"hidden\" name=\"fit_key\" value=\"managed-second\"")

    source_req = HTTP.Request("GET", "/?fit_key=source", ["X-Job" => "job-a"])
    source_context = _operation_context(managed, source_req, "", :http)
    source = managed.factory(JobScopedApp, source_context)
    @test source === managed.factory(JobScopedApp, source_context)
    mounted = _provide_root(managed, JobScopedApp, source_context)
    @test mounted.fit_key == "source"
    @test mounted.__route__ == "/"
    @test contains(repr("text/html", operation_form(mounted.models, :analyze;
                                                    target_id="#managed")),
                   "type=\"hidden\" name=\"fit_key\" value=\"source\"")
    retained_result = mounted.models.structured(Verb{:GET}(); value=:ok)
    next_req = HTTP.Request("GET", "/?fit_key=next", ["X-Job" => "job-a"])
    next_context = _operation_context(managed, next_req, "", :http)
    next_mounted = _provide_root(managed, JobScopedApp, next_context)
    @test next_mounted.fit_key == "next"
    @test next_mounted.models.structured(Verb{:GET}(); value=:ok) === retained_result

    # Custom scoped providers may retain the root itself now too: the same
    # remount seam refreshes it for both :job and :session scopes.
    roots = Dict{Any,JobScopedApp}()
    cached = RootProvider(; scope=:job, key=job_key) do RootT, context
        get!(() -> RootT(), roots, context.key)
    end
    route!(JobScopedApp(); root_provider=cached)
    @test hit("/?fit_key=cached-first").status == 200
    cached_second = hit("/?fit_key=cached-second")
    @test cached_second.status == 200
    @test contains(String(cached_second.body),
                   "type=\"hidden\" name=\"fit_key\" value=\"cached-second\"")

    session_key(req) = HTTP.header(req, "X-Session", "default")
    retained_session = Ref{Any}(nothing)
    session = RootProvider(; scope=:session, key=session_key) do RootT, _context
        isnothing(retained_session[]) && (retained_session[] = RootT())
        retained_session[]
    end
    session_req = HTTP.Request("GET", "/?fit_key=session-key",
                               ["X-Session" => "session-a"])
    session_context = _operation_context(session, session_req, "", :http)
    @test _provide_root(session, JobScopedApp, session_context).fit_key == "session-key"

    # Capacity is LRU and ttl is idle-time based. An injected monotonic clock
    # keeps cleanup tests exact without sleeps.
    tick = Ref(0.0)
    retention_factory = _ManagedRootFactory(
        RootRetention(max_entries=2, ttl=5); clock=() -> tick[])
    bounded = RootProvider(retention_factory; scope=:job, key=job_key)
    retained(job) = begin
        tick[] += 1
        req = HTTP.Request("GET", "/", ["X-Job" => job])
        retention_factory(JobScopedApp,
            _operation_context(bounded, req, "", :http))
    end
    a1 = retained("a")
    b1 = retained("b")
    @test retained("a") === a1
    retained("c")
    @test retained("b") !== b1
    ttl_a = retained("ttl")
    tick[] += 10
    @test retained("ttl") !== ttl_a

    # Managed eviction releases only the provider's reference. The internal
    # framework notification runs after the store lock is released and carries
    # enough identity for DynamicObjects to retire a lease without any
    # application-owned store or GC callback.
    release_tick = Ref(0.0)
    release_factory = _ManagedRootFactory(
        RootRetention(max_entries=1, ttl=5); clock=() -> release_tick[])
    release_provider = RootProvider(release_factory; scope=:job, key=job_key)
    release_events = Any[]
    lock_states = Bool[]
    old_release_handler = _managed_root_release_handler[]
    try
        _managed_root_release_handler[] = event -> begin
            push!(release_events, event)
            push!(lock_states, islocked(release_factory.lock))
        end
        release_root(job) = begin
            req = HTTP.Request("GET", "/", ["X-Job" => job])
            release_factory(JobScopedApp,
                _operation_context(release_provider, req, "", :http))
        end
        released_a = release_root("a")
        release_tick[] = 1
        released_b = release_root("b")
        release_tick[] = 7
        release_root("b")

        @test lock_states == [false, false]
        @test getproperty.(release_events, :reason) == [:lru, :ttl]
        @test getproperty.(release_events, :key) == ["a", "b"]
        @test all(event -> event.root_type === JobScopedApp, release_events)
        @test all(event -> event.scope === :job, release_events)
        @test release_events[1].root === released_a
        @test release_events[2].root === released_b
        @test all(event -> event.retention === release_factory.retention,
                  release_events)
    finally
        _managed_root_release_handler[] = old_release_handler
    end

    # Request-scoped custom providers still fail closed if they omit the
    # current request, since remounting is intentionally scoped-only.
    unbound = RootProvider((RootT, _context) -> RootT())
    unbound_req = HTTP.Request("GET", "/?fit_key=missing")
    unbound_context = _operation_context(unbound, unbound_req, "", :http)
    err = try
        _provide_root(unbound, JobScopedApp, unbound_context)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test contains(err.msg, "does not carry the current request")
    @test contains(err.msg, "RootRetention")

end

@testitem "a detached @include child refuses to render a form it cannot fill" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _detached_include_child_params

    # Registration is what records the child→parent link, so route! first.
    route!(ExternalContextApp(; __req__=HTTP.Request("GET", "/?fit_key=live")))
    route!(ParamlessHostApp())

    # Mounted: resolves through __parent__, renders the inherited hidden input.
    mounted = ExternalContextApp(; __req__=HTTP.Request("GET", "/?fit_key=live")).models
    @test isempty(_detached_include_child_params(mounted))
    @test contains(repr("text/html", operation_form(mounted, :analyze; target_id="#m")),
                   "type=\"hidden\" name=\"fit_key\" value=\"live\"")

    # Detached: the exact shape a custom job/session factory produces when it
    # retains the CHILD and injects it into a fresh root. Managed retention
    # keeps/remounts the rooted graph instead. This detached instance must still
    # fail closed rather than silently omit the inherited input.
    orphan = ExternalContextChild()
    @test _detached_include_child_params(orphan) == [:fit_key]
    err = try
        operation_form(orphan, :analyze; target_id="#o")
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test contains(err.msg, "cannot resolve :fit_key")
    @test contains(err.msg, "ExternalContextApp")
    @test contains(err.msg, "no `__parent__`")
    @test contains(err.msg, "not a payload")

    # A child of a param-less parent has no inherited context to lose, so
    # standalone rendering keeps working.
    @test isempty(_detached_include_child_params(ParamlessHostChild()))
    standalone = repr("text/html", operation_form(ParamlessHostChild(), :analyze; target_id="#s"))
    @test contains(standalone, "name=\"value\"")
end

@testitem "operation_form context: inline vs bare external mounted child" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _param_names

    req = HTTP.Request("GET", "/?fit_key=proof")
    form(RootT) = repr("text/html",
                       operation_form(RootT(; __req__=req).models, :probe))

    # `operation_form` resolves enclosing @param context from the runtime
    # __parent__ chain, so both include shapes emit the same hidden context.
    @test contains(form(InlineContextApp),
                   "type=\"hidden\" name=\"fit_key\" value=\"proof\"")
    @test contains(form(BareExternalApp),
                   "type=\"hidden\" name=\"fit_key\" value=\"proof\"")
    @test form(BareExternalApp) == form(InlineContextApp)

    # __parent__/__req__/__prefix__ thread to an external child either way …
    bare = BareExternalApp(; __req__=req).models
    @test bare.__req__ === req
    @test bare.__prefix__ == "/models"

    # … but @param *inheritance* is resolved at macro expansion, so only the
    # inline child owns the property. A bare external child must delegate
    # explicitly (see ExternalContextChild) before its body can read fit_key.
    @test _param_names(typeof(InlineContextApp(; __req__=req).models)) == (:fit_key,)
    @test _param_names(typeof(bare)) == ()
    @test_throws Exception bare.fit_key
end

@testitem "semantic operation execution policy and direct responses" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _operation_execution_mode, _operation_polling_impl,
        _property_descriptor, _run_operation, _resolve_operation_value
    import HTMXObjects.DynamicObjects

    @test OperationPolicy().mode === :blocking
    @test OperationPolicy(:polling; poll_interval="350ms", keep_progress=false) ==
          OperationPolicy(:polling, "350ms", false)
    @test_throws ArgumentError OperationPolicy(:background)

    html_descriptor = _property_descriptor(PolicyApp, :html)
    raw_descriptor = _property_descriptor(PolicyApp, :raw)
    response_descriptor = _property_descriptor(PolicyApp, :response)
    plain = HTTP.Request("GET", "/html?count=2")
    hx = HTTP.Request("GET", "/html?count=2", ["HX-Request" => "true"])
    @test _operation_execution_mode(OperationPolicy(:auto), html_descriptor,
                                    plain, Verb{:GET}()) === :blocking
    @test _operation_execution_mode(OperationPolicy(:auto), html_descriptor,
                                    hx, Verb{:GET}()) === :polling
    @test _operation_execution_mode(OperationPolicy(:polling), raw_descriptor,
                                    hx, Verb{:GET}()) === :blocking
    @test _operation_execution_mode(OperationPolicy(:polling), response_descriptor,
                                    hx, Verb{:GET}()) === :blocking
    @test _operation_execution_mode(OperationPolicy(:polling), html_descriptor,
                                    hx, Verb{:WEBSOCKET}()) === :blocking

    exchange = filter(route -> route.name === :exchange,
                      semantic_descriptor(MultiVerbPolicyApp).routes)
    get_exchange = only(filter(route -> route.verb === :GET, exchange))
    post_exchange = only(filter(route -> route.verb === :POST, exchange))
    @test get_exchange.property.output.type === MIMEResponse
    @test post_exchange.property.output.type === nothing
    @test only(filter(input -> input.name === :mode,
                      get_exchange.property.inputs)).domain.cardinality == 2
    @test only(filter(input -> input.name === :count,
                      post_exchange.property.inputs)).domain.cardinality == 2
    @test _operation_execution_mode(OperationPolicy(:polling),
                                    get_exchange.property, hx,
                                    Verb{:GET}()) === :blocking
    @test _operation_execution_mode(OperationPolicy(:polling),
                                    post_exchange.property, hx,
                                    Verb{:POST}()) === :blocking

    app = PolicyApp()
    target = (context=nothing, root=app, leaf=app)
    polls = NamedTuple[]
    old_polling = _operation_polling_impl[]
    _operation_polling_impl[] =
        (render_result, _started, ip, keys, call_kwargs, transport) -> begin
            push!(polls, (; keys, call_kwargs, transport))
            h.aside("polling")
        end
    try
        operation = _run_operation(target, PolicyApp, :html, Verb{:GET}(),
                                   hx, 0, 0;
                                   operation_policy=OperationPolicy(:auto))
        @test repr("text/html", operation.value) == "<aside>polling</aside>"
        @test length(polls) == 1
        @test only(polls).call_kwargs == (count=2,)
        @test only(polls).transport.poll_url ==
              "/html?count=2&__htmxo_poll=1"
        @test only(polls).transport.grace_period == 0.1

        poll_request = HTTP.Request(
            "GET", "/html?count=2&__htmxo_poll=1", ["HX-Request" => "true"])
        polled = _run_operation(target, PolicyApp, :html, Verb{:GET}(),
                                poll_request, 0, 0;
                                operation_policy=OperationPolicy(:auto))
        @test repr("text/html", polled.value) == "<aside>polling</aside>"
        @test length(polls) == 2
        @test last(polls).call_kwargs == (count=2,)
        @test last(polls).transport.poll_url ==
              "/html?count=2&__htmxo_poll=1"
        @test last(polls).transport.grace_period == 0.0

        raw = _run_operation(target, PolicyApp, :raw, Verb{:GET}(),
                             HTTP.Request("GET", "/raw?count=3"), 0, 0;
                             operation_policy=OperationPolicy(:polling))
        @test raw.value isa MIMEResponse
        @test raw.value.content_type == "text/plain"
        @test raw.value.body == "raw:3"

        response = _run_operation(target, PolicyApp, :response, Verb{:GET}(),
                                  HTTP.Request("GET", "/response?count=4"), 0, 0;
                                  operation_policy=OperationPolicy(:polling))
        @test response.value.status == 202
        @test String(response.value.body) == "{\"count\":4}"

        ws = _run_operation(target, PolicyApp, :stream, Verb{:WEBSOCKET}(),
                            HTTP.Request("GET", "/stream?count=5"), 0, 0;
                            operation_policy=OperationPolicy(:polling))
        @test ws.value(nothing) == "ws:5"
        @test length(polls) == 2

        route!(app; operation_policy=:polling)
        raw_req = HTTP.Request("GET", "/raw?count=6", ["HX-Request" => "true"])
        raw_handler = first(HTTP.Handlers.gethandler(
            HTMXObjects.CONTEXT[].service.router, raw_req))
        raw_response = raw_handler(raw_req)
        @test raw_response.status == 200
        @test HTTP.header(raw_response, "Content-Type") == "text/plain"
        @test String(raw_response.body) == "raw:6"

        response_req = HTTP.Request("GET", "/response?count=7",
                                    ["HX-Request" => "true"])
        response_handler = first(HTTP.Handlers.gethandler(
            HTMXObjects.CONTEXT[].service.router, response_req))
        final_response = response_handler(response_req)
        @test final_response.status == 202
        @test HTTP.header(final_response, "Content-Type") == "application/json"
        @test String(final_response.body) == "{\"count\":7}"
        @test length(polls) == 2
    finally
        _operation_polling_impl[] = old_polling
    end

    # A DO handle is control flow, never body content. Treebars' `_polling_resolve`
    # done path is a CATCH-ALL — it hands whatever DO returned straight to
    # `render_result` — so the guard has to live on the `render_result` we pass in.
    # Emulate that seam exactly and assert no DO internals reach the response.
    _operation_polling_impl[] =
        (render_result, started, _ip, _keys, _call_kwargs, _transport) ->
            h.div(string(render_result(started)))
    try
        resolved = _run_operation(target, PolicyApp, :html, Verb{:GET}(),
                                  hx, 0, 0;
                                  operation_policy=OperationPolicy(:auto))
        html = repr("text/html", resolved.value)
        @test !contains(html, "Pending")
        @test !contains(html, "ThreadsafeDict")
    finally
        _operation_polling_impl[] = old_polling
    end

    # The funnel itself: an unresolved handle resolves to its value, ordinary
    # values pass through untouched.
    let cache = DynamicObjects.ThreadsafeDict()
        pending = Base.get!(cache, :probe; fetch=identity) do _status
            7
        end
        @test pending isa DynamicObjects.Pending
        @test _resolve_operation_value(pending) == 7
    end
    @test _resolve_operation_value(42) === 42
    @test _resolve_operation_value("plain") == "plain"

    stacked = only(filter(route -> route.name === :model,
                          semantic_descriptor(StackedSemanticRoute).routes))
    @test stacked.path == "/model"
    @test stacked.property.output.type === Vector{Float64}
    @test stacked.property.semantics.mmap
    @test stacked.property.semantics.progress
    @test stacked.property.semantics.pending
    @test only(filter(input -> input.name === :count,
                      stacked.property.inputs)).domain.cardinality == 3
end

@testitem ":index -> / routing" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    app = IndexApp()
    info = DynamicObjects.metafirst(IndexApp, :index)
    @test info !== nothing
    @test Symbol("@get") in info.macros
end

@testitem "indexed property with all-default indices" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    app = AllDefaultsApp()
    html = repr("text/html", app.viz(Verb{:GET}(); pn="test"))
    @test contains(html, "Viz: test")
    html = repr("text/html", app.viz(Verb{:GET}(); pn=""))
    @test contains(html, "Viz: all")
end

@testitem "htmx() full-page template" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    page = htmx(h.main("content"))
    html = repr("text/html", page)
    @test contains(html, "htmx.org")
    @test contains(html, "hyperscript.org")
    @test contains(html, "<html")
    @test contains(html, "content")
    @test !contains(html, "@picocss/pico@")
    html_pico = repr("text/html", htmx(h.main(); pico_version="2"))
    @test contains(html_pico, "@picocss/pico@2")
    html_bare = repr("text/html", htmx(h.main(); htmx_version=nothing))
    @test !contains(html_bare, "htmx.org")
    html_extra = repr("text/html", htmx(h.main(); extra_head=(h.style("body{margin:0}"),)))
    @test contains(html_extra, "body{margin:0}")
end

@testitem "save_response" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    mktempdir() do dir
        resp = HTTP.Response(200, ["Content-Type" => "text/html"]; body="<p>hi</p>")
        dest = save_response(dir, "/", resp)
        @test isfile(dest)
        @test endswith(dest, "index.html")
        @test read(dest, String) == "<p>hi</p>"
        dest2 = save_response(dir, "/post/42", resp)
        @test isfile(dest2)
        @test basename(dest2) == "42.html"
        @test basename(dirname(dest2)) == "post"
    end
end

"""
Starts a real HTTP server and verifies that live responses are recorded at the
same route-shaped paths used by static output. Tagged `integration`/`server`
because it binds a port and mutates Oxygen's process-global route context.
"""
@testitem "recording - end-to-end" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :server] begin
    mktempdir() do dir
        app = RecordApp()
        route!(app; record_dir=dir)
        port = 8099
        serve(; port, async=true)
        try
            r1 = HTTP.get("http://127.0.0.1:$port/")
            @test r1.status == 200
            @test contains(String(r1.body), "Home")
            index_file = joinpath(dir, "index.html")
            @test isfile(index_file)
            @test contains(read(index_file, String), "Home")
            r2 = HTTP.get("http://127.0.0.1:$port/post/42")
            @test r2.status == 200
            @test contains(String(r2.body), "Post 42")
            post_file = joinpath(dir, "post", "42.html")
            @test isfile(post_file)
            @test contains(read(post_file, String), "Post 42")
            r3 = HTTP.get("http://127.0.0.1:$port/post/7")
            @test r3.status == 200
            post_file2 = joinpath(dir, "post", "7.html")
            @test isfile(post_file2)
            @test contains(read(post_file2, String), "Post 7")
        finally
            terminate()
        end
    end
end

@testitem "hx_link helper" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    link = hx_link("/about")
    html = repr("text/html", link)
    @test contains(html, "href=\"/about\"")
    @test contains(html, "hx-get=\"/about\"")
    @test contains(html, "<a")
    link2 = hx_link("/search"; hx_target="#main", class="nav-link")
    html2 = repr("text/html", link2)
    @test contains(html2, "href=\"/search\"")
    @test contains(html2, "hx-get=\"/search\"")
    @test contains(html2, "hx-target=\"#main\"")
    @test contains(html2, "class=\"nav-link\"")
end

@testitem "htmx_or helper" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    fragment = h.p("partial content")
    htmx_req = HTTP.Request("GET", "/", ["HX-Request" => "true"])
    resp = htmx_or(htmx_req, fragment) do
        htmx(h.main(fragment))
    end
    body = String(resp.body)
    @test contains(body, "partial content")
    @test !contains(body, "<html")
    plain_req = HTTP.Request("GET", "/")
    resp2 = htmx_or(plain_req, fragment) do
        htmx(h.main(fragment))
    end
    body2 = String(resp2.body)
    @test contains(body2, "partial content")
    @test contains(body2, "<html")
    @test contains(body2, "htmx.org")
end

@testitem "static_transform" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    btn = h.button("Toggle"; hx_post="/toggle")
    transformed = static_transform(btn)
    html = repr("text/html", transformed)
    @test !contains(html, "hx-post")
    @test contains(html, "data-static-disabled")
    link = h.a("About"; hx_get="/about")
    transformed_link = static_transform(link)
    html_link = repr("text/html", transformed_link)
    @test contains(html_link, "hx-get=\"/about\"")
    @test !contains(html_link, "data-static-disabled")
    del_btn = h.button("Delete"; hx_delete="/item/1")
    transformed_del = static_transform(del_btn)
    html_del = repr("text/html", transformed_del)
    @test contains(html_del, "data-static-disabled")
    @test !contains(html_del, "hx-delete")
    head_node = h.head(h.title("Test"))
    transformed_head = static_transform(head_node)
    html_head = repr("text/html", transformed_head)
    @test contains(html_head, "data-static-disabled")  || contains(html_head, "pointer-events")
    @test contains(html_head, "pointer-events:none")
end

@testitem "@post route verb metadata" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    info = DynamicObjects.metafirst(PostApp, :submit)
    @test info !== nothing
    @test Symbol("@post") in info.macros
    @test !(Symbol("@get") in info.macros)
end

@testitem "type conversion in indexed routes" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    app = TypedApp()
    html = repr("text/html", app.typed(Verb{:GET}(), 42))
    @test contains(html, "N=42")
    info = DynamicObjects.metafirst(TypedApp, :typed)
    @test info !== nothing
    @test Symbol("@get") in info.macros
end

@testitem "hx_response with location" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    resp = hx_response(h.div("content"); location="/new")
    @test any(p.first == "HX-Location" && p.second == "/new"
              for p in resp.headers)
    @test contains(String(resp.body), "<div>")
end

@testitem "queryparams - multi-value support" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req = HTTP.Request("GET", "/search?q=hello&page=1")
    qp = queryparams(req)
    @test qp["q"] == "hello"
    @test qp["page"] == "1"
    req_multi = HTTP.Request("GET", "/filter?tag=a&tag=b&tag=c")
    qp_multi = queryparams(req_multi)
    @test qp_multi["tag"] isa Vector{String}
    @test qp_multi["tag"] == ["a", "b", "c"]
    req_mixed = HTTP.Request("GET", "/x?solo=1&dup=a&dup=b")
    qp_mixed = queryparams(req_mixed)
    @test qp_mixed["solo"] == "1"
    @test qp_mixed["dup"] isa Vector{String}
    @test qp_mixed["dup"] == ["a", "b"]
    req_empty = HTTP.Request("GET", "/nothing")
    qp_empty = queryparams(req_empty)
    @test isempty(qp_empty)
    @test qp_empty isa Dict{String, Union{String, Vector{String}}}
    req_enc = HTTP.Request("GET", "/s?q=hello%20world&name=a%26b")
    qp_enc = queryparams(req_enc)
    @test qp_enc["q"] == "hello world"
    @test qp_enc["name"] == "a&b"
    req_noval = HTTP.Request("GET", "/x?flag")
    qp_noval = queryparams(req_noval)
    @test qp_noval["flag"] == ""
end

@testitem "nothing default in kwargs route" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :server] begin
    route!(NothingDefaultApp())
    serve(; port=8098, async=true)
    try
        r = HTTP.get("http://127.0.0.1:8098/filtered")
        body = String(r.body)
        @test contains(body, "filter=nothing")
        @test !contains(body, "filter=:nothing")
        r2 = HTTP.get("http://127.0.0.1:8098/filtered?filter=active")
        body2 = String(r2.body)
        @test contains(body2, "filter=\"active\"") || contains(body2, "filter=&quot;active&quot;")
    finally
        terminate()
    end
end

@testitem "wants_markdown" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req_md = HTTP.Request("GET", "/", ["Accept" => "text/markdown"])
    @test wants_markdown(req_md)
    req_plain = HTTP.Request("GET", "/", ["Accept" => "text/plain"])
    @test wants_markdown(req_plain)
    req_qp_md = HTTP.Request("GET", "/page?markdown")
    @test wants_markdown(req_qp_md)
    req_qp = HTTP.Request("GET", "/page?plain")
    @test wants_markdown(req_qp)
    req_html = HTTP.Request("GET", "/", ["Accept" => "text/html"])
    @test !wants_markdown(req_html)
    req_none = HTTP.Request("GET", "/")
    @test !wants_markdown(req_none)
end

@testitem "markdown_response" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    resp = markdown_response("# Hello\n\nworld")
    @test resp.status == 200
    @test String(resp.body) == "# Hello\n\nworld"
    @test any(p.first == "Content-Type" && contains(p.second, "text/markdown")
              for p in resp.headers)
end

@testitem "render_table" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    tbl = (; name=["Alice", "Bob", "Charlie"], score=[95, 87, 92])
    node = render_table(tbl)
    html = repr("text/html", node)
    @test contains(html, "<table")
    @test contains(html, "<thead")
    @test contains(html, "<tbody")
    @test contains(html, "Alice")
    @test contains(html, "87")
    @test contains(html, "name")
    @test contains(html, "score")
    @test contains(html, "sortTable")
    @test contains(html, "class=\"u-pointer\"")
    node_ns = render_table(tbl; sortable=false)
    html_ns = repr("text/html", node_ns)
    @test contains(html_ns, "Alice")
    @test !contains(html_ns, "sortTable")
    @test !contains(html_ns, "class=\"u-pointer\"")
    node_cell = render_table(tbl; cell=(v, col, ri) -> col == :score ? "**$(v)**" : string(v))
    html_cell = repr("text/html", node_cell)
    @test contains(html_cell, "**95**")
    @test contains(html_cell, "Alice")
    node_id = render_table(tbl; id="my-table")
    html_id = repr("text/html", node_id)
    @test contains(html_id, "my-table")
    node_kw = render_table(tbl; class="custom", id="t1")
    html_kw = repr("text/html", node_kw)
    @test contains(html_kw, "class=\"custom htmxo-sortable-table\"")
end

@testitem "sortable_table_js" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = sortable_table_js()
    html = repr("text/html", node)
    @test contains(html, "<script>")
    @test contains(html, "sortTable")
    @test contains(html, "closest")
    # Sort-state read surface: `sortTable` mirrors `data-sort-dir` into the
    # standard `aria-sort` (and clears both from siblings); `htmxoSortState`
    # is the documented accessor consumers spread into `hx-vals`.
    @test contains(html, "function htmxoSortState")
    @test contains(html, "setAttribute('aria-sort'")
    @test contains(html, "removeAttribute('aria-sort')")
    @test contains(html, "thead th[data-sort-dir]")
end

@testitem "sortable_table default_sort" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    rows = [h.tr(h.td("a"), h.td("1"))]
    plain = repr("text/html", sortable_table(["Name", "Score"], rows))
    @test !contains(plain, "data-sort-dir")
    @test !contains(plain, "aria-sort")
    @test !contains(plain, "htmxo-sort-caret")

    # `col => dir`, stamped on exactly one <th>, matching what sortTable sets.
    desc = repr("text/html", sortable_table(["Name", "Score"], rows; default_sort=2 => :desc))
    @test contains(desc, "data-sort-dir=\"desc\"")
    @test contains(desc, "aria-sort=\"descending\"")
    @test contains(desc, "htmxo-sort-caret")
    @test length(collect(eachmatch(r"data-sort-dir", desc))) == 1
    @test length(collect(eachmatch(r"aria-sort", desc))) == 1

    # Bare column (defaults to :asc), and a String header label.
    @test contains(repr("text/html", sortable_table(["Name", "Score"], rows; default_sort=1)),
                   "data-sort-dir=\"asc\"")
    @test contains(repr("text/html", sortable_table(["Name", "Score"], rows; default_sort="Score")),
                   "aria-sort=\"ascending\"")

    # Forwarded through render_table's kwargs..., not leaked as a <table> attr.
    rt = repr("text/html", render_table((name=["a"], score=[1]); default_sort=2 => :desc, download=false))
    @test contains(rt, "data-sort-dir=\"desc\"")
    @test !contains(rt, "default_sort")

    @test_throws ErrorException sortable_table(["A"], rows; default_sort=1 => :sideways)
    @test_throws ErrorException sortable_table(["A"], rows; default_sort=5)
    @test_throws ErrorException sortable_table(["A"], rows; default_sort="Nope")
    @test_throws ErrorException sortable_table(["A"], rows; default_sort=1, sortable=false)
    # Only auto-wired String headers can be stamped.
    @test_throws ErrorException sortable_table([h.th("A")], rows; default_sort=1)
end

@testitem "nested lazy master/detail events stay scoped" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    inner = master_detail_table(["Inner"], [1];
        key=identity,
        master=_ -> (h.td("inner"),),
        detail_url=_ -> "/inner",
        id="inner-table")
    nested = master_detail_table(["Outer"], [1];
        key=_ -> "outer",
        master=_ -> (h.td("outer"),),
        detail=_ -> inner,
        detail_url=_ -> "/outer",
        id="outer-table")
    html = repr("text/html", nested)

    # This is the post-load nesting shape that exposed the regression: the
    # inner lazy slot is a descendant of the still-live outer lazy slot.
    # htmx's `consume` trigger modifier prevents the inner custom event from
    # triggering another request on that ancestor.
    @test length(collect(eachmatch(r"hx-trigger=\"htmxo-md-load consume\"", html))) == 2
    @test !contains(html, "hx-trigger=\"htmxo-md-load\"")
    @test contains(html, "id=\"detail-slot-outer\"")
    @test contains(html, "id=\"detail-slot-1\"")

    open_pair = master_detail_pair("open", (h.td("open"),), nothing, 1;
        initially_open=true, detail_url="/open")
    open_html = repr("text/html", h.div(open_pair...))
    @test contains(open_html, "hx-trigger=\"htmxo-md-load consume, load\"")
end

@testitem "nested lazy master/detail browser requests stay isolated" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using Sockets

        chrome = Sys.which("google-chrome")
        isnothing(chrome) && (chrome = Sys.which("chromium"))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        outer_requests = Ref(0)
        inner_requests = Ref(0)
        inner = master_detail_table(["Inner"], [1];
            key=_ -> "inner",
            master=_ -> (h.td("inner"),),
            detail_url=_ -> "/inner",
            id="inner-table")
        outer = master_detail_table(["Outer"], [1];
            key=_ -> "outer",
            master=_ -> (h.td("outer"),),
            detail_url=_ -> "/outer",
            id="outer-table")
        driver = h.script(Raw("""
            document.body.addEventListener('htmx:afterSettle', function(event) {
                if (event.detail.target.id === 'detail-slot-outer' && !window.innerClickStarted) {
                    window.innerClickStarted = true;
                    setTimeout(function() {
                        document.getElementById('row-inner').click();
                    }, 10);
                } else if (event.detail.target.id === 'detail-slot-inner') {
                    document.body.dataset.nestedDone = '1';
                }
            });
            window.addEventListener('load', function() {
                setTimeout(function() {
                    document.getElementById('row-outer').click();
                }, 50);
            });
            """))
        page = repr("text/html", htmx(outer, driver;
            hyperscript_version=nothing,
            feedback=false,
            compose=false,
            overlay=false))
        inner_html = repr("text/html", inner)

        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!(Sockets.localhost, port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif path == "/outer"
                outer_requests[] += 1
                HTTP.Response(200, ["Content-Type" => "text/html"], inner_html)
            elseif path == "/inner"
                inner_requests[] += 1
                HTTP.Response(200, ["Content-Type" => "text/html"], "<p id=\"inner-loaded\">loaded</p>")
            else
                HTTP.Response(404)
            end
        end

        try
            dom = mktempdir() do profile
                url = "http://127.0.0.1:$port/"
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile $url`
                read(pipeline(cmd; stderr=devnull), String)
            end
            @test contains(dom, "data-nested-done=\"1\"")
            @test contains(dom, "id=\"inner-loaded\"")
            @test outer_requests[] == 1
            @test inner_requests[] == 1
        finally
            close(server)
        end
    end
end

"""
Documents repeated query/form value conversion: untyped or vector-typed
parameters retain repeated values, while a vector cannot silently collapse
into a scalar parameter.
"""
@testitem "_convert_param with vectors" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    cp = HTMXObjects._convert_param
    v = ["a", "b", "c"]
    @test cp(v, nothing) === v
    @test cp(v, Vector{String}) === v
    @test cp("only", Vector{String}) == ["only"]
    @test isempty(cp("", Vector{String}))
    @test_throws ErrorException cp(["first", "second"], String)
    @test_throws ErrorException cp(["42"], Int)
end

@testitem "_convert_param for Symbol" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    cp = HTMXObjects._convert_param
    @test cp("done", Symbol) === :done
    @test cp("", Symbol) === Symbol("")
end

@testitem "fmt_time" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    @test fmt_time(1.5e-9) == "1.5ns"
    @test fmt_time(4.56e-6) == "4.6μs"
    @test fmt_time(0.0789) == "79.0ms"
    @test fmt_time(1.23) == "1.2s"
    @test fmt_time(90.0) == "1.5min"
    @test fmt_time(7200.0) == "2.0hr"
    @test fmt_time(-0.001) == "-1.0ms"
end

@testitem "fmt_bytes" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    @test fmt_bytes(512) == "512 B"
    @test fmt_bytes(1536) == "1.5 KB"
    @test fmt_bytes(2 * 1024^2) == "2.0 MB"
    @test fmt_bytes(3.5 * 1024^3) == "3.5 GB"
    @test fmt_bytes(1.0 * 1024^4) == "1.0 TB"
end

@testitem "fmt_number" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    @test fmt_number(0) == "0"
    @test fmt_number(42.0) == "42.0"
    @test fmt_number(1500.0) == "1.5K"
    @test fmt_number(2.5e6) == "2.5M"
    @test fmt_number(1e9) == "1.0B"
    @test fmt_number(3.0e12) == "3.0T"
    @test fmt_number(NaN) == "NaN"
    @test fmt_number(Inf) == "∞"
    @test fmt_number(-Inf) == "-∞"
    @test fmt_number(-2500.0) == "-2.5K"
end

@testitem "Long" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    @test Long("study_cohort") == "study cohort"
    @test Long(:hello_world) == "hello world"
    @test Long("single") == "single"
end

@testitem "sinput" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = sinput("color", ["red", "green", "blue"]; value="green")
    html = repr("text/html", node)
    @test contains(html, "<label>")
    @test contains(html, "<select")
    @test contains(html, "name=\"color\"")
    @test contains(html, "<option value=\"green\" selected=\"true\">")
    @test !contains(html, "<option value=\"red\" selected")
end

@testitem "soption" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # plain value
    node = soption("apple")
    html = repr("text/html", node)
    @test contains(html, "<option")
    @test contains(html, "apple")
    # Pair: value => label
    node2 = soption("us" => "United States")
    html2 = repr("text/html", node2)
    @test contains(html2, "value=\"us\"")
    @test contains(html2, "United States")
    # selected
    node3 = soption("x"; selected_value="x")
    html3 = repr("text/html", node3)
    @test contains(html3, "selected=\"true\">")
end

@testitem "linput" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = linput("email")
    html = repr("text/html", node)
    @test contains(html, "<label>")
    @test contains(html, "<input")
    @test contains(html, "name=\"email\"")
    @test contains(html, "placeholder=\"email\"")
end

@testitem "loading_indicator_script" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = loading_indicator_script()
    @test node isa Node
    html = repr("text/html", node)
    @test contains(html, "<script>")
    @test contains(html, "htmx:beforeRequest")
    @test contains(html, "aria-busy")
end

@testitem "tabset" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = tabset("Tab A" => h.p("Content A"), "Tab B" => h.p("Content B"))
    html = repr("text/html", node)
    @test contains(html, "Tab A")
    @test contains(html, "Tab B")
    @test contains(html, "Content A")
    @test contains(html, "Content B")
    # first tab active by default
    @test contains(html, "class=\"contrast\"")
    @test contains(html, "class=\"secondary\"")
    # tab panels
    @test contains(html, "tab-panel")
    @test contains(html, "tab-panel u-w-full u-hidden")
    # lazy tabs: string content → hx-get with revealed trigger
    lazy = tabset("Eager" => h.p("here"), "Lazy" => "/api/lazy")
    lhtml = repr("text/html", lazy)
    @test contains(lhtml, "here")           # eager content rendered
    @test !contains(lhtml, "/api/lazy\">")  # URL not rendered as text
    @test contains(lhtml, "hx-get=\"/api/lazy\"")
    @test contains(lhtml, "revealed once")
    # all-lazy
    lazy2 = tabset("A" => "/a", "B" => "/b")
    lhtml2 = repr("text/html", lazy2)
    @test contains(lhtml2, "hx-get=\"/a\"")
    @test contains(lhtml2, "hx-get=\"/b\"")
end

@testitem "status_badge" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = status_badge(:running)
    html = repr("text/html", node)
    @test contains(html, "Running")
    @test contains(html, "u-text-warning")

    node2 = status_badge(:done)
    html2 = repr("text/html", node2)
    @test contains(html2, "Done")
    @test contains(html2, "u-text-success")

    node3 = status_badge(:failed; label="Error!")
    html3 = repr("text/html", node3)
    @test contains(html3, "Error!")
    @test contains(html3, "u-text-error")

    # unknown state falls back to muted
    node4 = status_badge(:unknown)
    html4 = repr("text/html", node4)
    @test contains(html4, "u-text-muted")

    # remap via `classes=`
    node5 = status_badge(:custom; classes=Dict(:custom => "u-text-accent"))
    html5 = repr("text/html", node5)
    @test contains(html5, "u-text-accent")
end

@testitem "nav_sidebar" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    node = nav_sidebar(["Home" => "/", "About" => "/about"]; prefix="/app")
    html = repr("text/html", node)
    @test contains(html, "<aside>")
    @test contains(html, "<nav>")
    @test contains(html, "href=\"/app/\"")
    @test contains(html, "href=\"/app/about\"")
    @test contains(html, "hx-get=\"/app/\"")
    @test contains(html, "hx-push-url=\"/app/about\"")
    @test contains(html, "hx-target=\"#content\"")

    # tuple form
    node2 = nav_sidebar(("X" => "/x",))
    html2 = repr("text/html", node2)
    @test contains(html2, "href=\"/x\"")
end

"""
Exercises the complete `@param` precedence chain: struct defaults, query
values, explicit constructor overrides, and generated route metadata.
"""
@testitem "@param — basic" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Defaults when request has nothing
    req = HTTP.Request("GET", "/")
    app = ParamApp(; __req__=req)
    @test app.vessels == ["Tablet-20"]
    @test app.n_bootstrap == "10"
    @test app.note == "default-note"

    # Typed vector param with repeated key
    req = HTTP.Request("GET", "/?vessels=A&vessels=B&n_bootstrap=42")
    app = ParamApp(; __req__=req)
    @test app.vessels == ["A", "B"]
    @test app.n_bootstrap == "42"
    @test app.note == "default-note"

    # Single value promoted to vector for Vector{String} type
    req = HTTP.Request("GET", "/?vessels=solo")
    app = ParamApp(; __req__=req)
    @test app.vessels == ["solo"]
end

@testitem "@param — inline child inherits params" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req = HTTP.Request("GET", "/?vessels=X&vessels=Y&n_bootstrap=5")
    app = ParamApp(; __req__=req)
    @test app.child.vessels == ["X", "Y"]
    @test app.child.n_bootstrap == "5"
end

@testitem "@param — block form" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req = HTTP.Request("GET", "/?a=42&b=hello")
    app = ParamBlockApp(; __req__=req)
    @test app.a == 42
    @test app.b == "hello"

    req = HTTP.Request("GET", "/")
    app = ParamBlockApp(; __req__=req)
    @test app.a == 1
    @test app.b == "x"
end

@testitem "@param — required throws on miss" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req = HTTP.Request("GET", "/")
    app = ParamRequiredApp(; __req__=req)
    err = try
        app.fit_key
        nothing
    catch caught
        caught
    end
    @test err isa PropertyComputationError
    @test unwrap_error(err) isa HTMXObjects.MissingRequiredParam

    req = HTTP.Request("GET", "/?fit_key=abc")
    app = ParamRequiredApp(; __req__=req)
    @test app.fit_key == "abc"
end

@testitem "@param — POST reads formdata" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req = HTTP.Request("POST", "/submit",
        ["Content-Type" => "application/x-www-form-urlencoded"],
        "name=bob")
    app = ParamPostApp(; __req__=req)
    @test app.name == "bob"

    req = HTTP.Request("POST", "/submit",
        ["Content-Type" => "application/x-www-form-urlencoded"], "")
    app = ParamPostApp(; __req__=req)
    @test app.name == "anon"
end

@testitem "@include ExternalStruct emits _nested_struct_type" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Regression: `@include sub = MountSubRoutes()` (call form, not begin-block)
    # must still emit `_nested_struct_type(MountRootApp, Val(:sub)) = MountSubRoutes`
    # so `_register_routes` recognizes the nested struct and mounts its routes.
    # _convert_include_to_struct! strips the @include wrapper for call forms;
    # _find_include_externals must run BEFORE that conversion.
    @test HTMXObjects._nested_struct_type(MountRootApp, Val(:sub)) === MountSubRoutes
    @test HTMXObjects._nested_struct_type(AppDataApp, Val(:sub)) === MountSubRoutes
    @test HTMXObjects._nested_struct_type(PrefixDefaultApp, Val(:sub)) === MountSubRoutes
end

@testitem "_param_names emission" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    @test HTMXObjects._param_names(ParamApp) == (:vessels, :n_bootstrap, :note)
    # Inline child inherits parent's param names
    child_type = HTMXObjects._nested_struct_type(ParamApp, Val(:child))
    @test HTMXObjects._param_names(child_type) == (:vessels, :n_bootstrap, :note)
    # Structs without any @param get the default empty tuple
    @test HTMXObjects._param_names(TestApp) == ()
end

@testitem "query_url(path, obj)" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Only params actually present in the request are emitted
    req = HTTP.Request("GET", "/?vessels=A&vessels=B")
    app = ParamApp(; __req__=req)
    url = query_url("/plot", app)
    @test contains(url, "vessels=A")
    @test contains(url, "vessels=B")
    @test !contains(url, "n_bootstrap")
    @test !contains(url, "note")

    # Nothing present → bare path
    req = HTTP.Request("GET", "/")
    app = ParamApp(; __req__=req)
    @test query_url("/plot", app) == "/plot"

    # Overrides always win, even when absent from request
    req = HTTP.Request("GET", "/")
    app = ParamApp(; __req__=req)
    url = query_url("/plot", app; note="forced")
    @test contains(url, "note=forced")

    # Override replaces a present value
    req = HTTP.Request("GET", "/?n_bootstrap=10")
    app = ParamApp(; __req__=req)
    url = query_url("/plot", app; n_bootstrap="99")
    @test contains(url, "n_bootstrap=99")
    @test !contains(url, "n_bootstrap=10")
end

@testitem "__self__/\"path\" mount-prefix operator" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Default construction: no parent, no prefix
    app = MountRootApp()
    @test app / "foo" == "/foo"
    @test app.sub / "bar" == "/sub/bar"  # @include desugar still appends "/sub"

    # Threaded prefix: as the route handler constructs it
    rooted = MountRootApp(; __prefix__="/proxy/8000")
    @test rooted / "foo" == "/proxy/8000/foo"
    @test rooted / "/leading" == "/proxy/8000/leading"
    @test rooted.sub / "bar" == "/proxy/8000/sub/bar"
    # Route bodies see the qualified path via __self__
    @test contains(repr("text/html", rooted.index(Verb{:GET}())), "/proxy/8000/foo")
    @test contains(repr("text/html", rooted.sub.show(Verb{:GET}())), "/proxy/8000/sub/x")
end

@testitem "__appdata__ injection via __parent__ chain" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Default: no appdata → __appdata__ is nothing
    app0 = AppDataApp()
    @test app0.__appdata__ === nothing
    @test app0.sub.__appdata__ === nothing
    @test contains(repr("text/html", app0.index(Verb{:GET}())), "nothing")

    # Construct with appdata: child sees it via __parent__ chain
    appdata = (; counter=Ref(42), label="hello")
    app = AppDataApp(; __appdata__=appdata)
    @test app.__appdata__ === appdata
    @test app.sub.__appdata__ === appdata
    @test app.sub.__parent__ === app
end

@testitem "__prefix__ struct-body default survives route!() with no prefix kwarg" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # Direct construction: default obviously applies.
    app = PrefixDefaultApp()
    @test app.__prefix__ == "/baked-in"
    @test app / "foo" == "/baked-in/foo"
    @test app.sub / "bar" == "/baked-in/sub/bar"

    # After route!() with no prefix=, the struct's own default must survive
    # request-time construction. Mimic the handler's call shape:
    rebuilt = PrefixDefaultApp(; __req__=nothing)   # NO __prefix__ kwarg
    @test rebuilt.__prefix__ == "/baked-in"
    @test rebuilt / "foo" == "/baked-in/foo"
    @test rebuilt.sub / "bar" == "/baked-in/sub/bar"

    # An explicit prefix= still wins over the struct default.
    overridden = PrefixDefaultApp(; __prefix__="/override")
    @test overridden / "foo" == "/override/foo"
    @test overridden.sub / "bar" == "/override/sub/bar"
end

@testitem "__appdata__ singleton via struct-body default" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # The conventional pattern: struct sets `__appdata__ = SOME_CONST` so
    # every constructed instance (including those built per-request by route
    # handlers) sees the singleton, with no `appdata` kwarg on `route!`.
    app = AppDataSingletonApp()
    @test app.__appdata__ === _SINGLETON_APPDATA
    @test app.sub.__appdata__ === _SINGLETON_APPDATA
    @test contains(repr("text/html", app.index(Verb{:GET}())), "singleton")
end

@testitem "@query_url" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # bare symbol
    @test (@query_url index) == "/"
    @test (@query_url fit) == "/fit"
    # kwargs only
    @test (@query_url fit(; dataset="foo", model="bar")) == "/fit?dataset=foo&model=bar"
    # positional args
    @test (@query_url item(42)) == "/item/42"
    @test (@query_url item("hello")) == "/item/hello"
    # positional + kwargs
    @test (@query_url item(42; format="json")) == "/item/42?format=json"
    # variable interpolation
    let id = 99, ds = "mydata"
        @test (@query_url item(id)) == "/item/99"
        @test (@query_url fit(; dataset=ds)) == "/fit?dataset=mydata"
    end
end

"""
Verifies that typed `@header` fields bind case-insensitive HTTP headers and
fall back to declared defaults when a request omits them.
"""
@testitem "@header kwarg binding" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    req_with = HTTP.Request("GET", "/probe",
        ["X-Test-Agent" => "bot42", "X-Count" => "7"])
    req_without = HTTP.Request("GET", "/probe")

    app_with = HeaderApp(; __req__=req_with)
    @test app_with.x_test_agent == "bot42"
    @test app_with.x_count == 7

    app_without = HeaderApp(; __req__=req_without)
    @test app_without.x_test_agent == ""
    @test app_without.x_count == 0
end

"""
Proves that the web catalog discovers TestItems metadata without importing the
test package, including adjacent Markdown documentation and stable source keys.
"""
@testitem "documented test item discovery" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :test_ui] begin
    mktempdir() do project
        mkpath(joinpath(project, "test"))
        write(joinpath(project, "Project.toml"), "name = \"CatalogFixture\"\n")
        write(joinpath(project, "test", "items.jl"), """
        \"\"\"
        Explains the **documented contract**.

        Longer details remain Markdown.
        \"\"\"
        @testitem \"documented contract\" tags=[:unit, :documented] begin
            @test true
        end

        @testitem \"plain contract\" begin
            @test true
        end
        """)

        catalog = discover_test_items(project)
        @test isempty(catalog.errors)
        @test length(catalog.items) == 2
        documented = only(filter(item -> item.name == "documented contract", catalog.items))
        @test documented.key == "test/items.jl::documented contract"
        @test documented.file == "test/items.jl"
        @test documented.tags == [:unit, :documented]
        @test contains(documented.description, "**documented contract**")
        @test length(documented.id) == 16

        html = repr("text/html", test_list(project))
        @test contains(html, "documented contract")
        @test contains(html, "Longer details remain Markdown")
        @test contains(html, "#documented")
        @test contains(html, "/run_tag/documented")
    end
end

@testitem "test catalog parse errors stay in the UI" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :test_ui] begin
    mktempdir() do project
        write(joinpath(project, "broken.jl"), "function definitely_broken(\n")
        catalog = discover_test_items(project)
        @test isempty(catalog.items)
        @test length(catalog.errors) == 1
        html = repr("text/html", test_list(project))
        @test contains(html, "Catalog errors")
        @test contains(html, "broken.jl")
    end
end

"""
Mounts `TestRoutes` through the normal `@include` registrar and drives both a
catalog GET and a rejected selective POST through the in-process HTTP router.
"""
@testitem "web-included test routes" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :test_ui] begin
    route!(TestUIHost())
    router = HTMXObjects.CONTEXT[].service.router

    get_request = HTTP.Request("GET", "/tests", ["HX-Request" => "true"], UInt8[])
    get_handler = first(HTTP.Handlers.gethandler(router, get_request))
    @test get_handler !== HTTP.Handlers.default404
    get_response = get_handler(get_request)
    @test get_response.status == 200
    get_body = String(get_response.body)
    @test contains(get_body, "documented test item discovery")
    @test contains(get_body, "Run selected")
    @test contains(get_body, "/tests/run_tag/unit")

    post_request = HTTP.Request("POST", "/tests/run/not-a-catalog-id",
        ["HX-Request" => "true"], UInt8[])
    post_handler = first(HTTP.Handlers.gethandler(router, post_request))
    @test post_handler !== HTTP.Handlers.default404
    post_response = post_handler(post_request)
    @test post_response.status == 200
    @test contains(String(post_response.body), "Unknown test selection")
end

"""
Exercises the isolated runner as the web UI uses it: a checked subset can
produce and safely render output, a failing child cannot take down the host,
and child-process side effects remain explicit rather than mutating host state.
"""
@testitem "isolated web test jobs" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :test_ui] begin
    mktempdir() do project
        mkpath(joinpath(project, "src"))
        mkpath(joinpath(project, "test"))
        write(joinpath(project, "Project.toml"), """
        name = "HTMXOTestJobFixture"
        uuid = "9726e4dc-e091-4eb3-85fa-a7f7d0ae98c4"
        version = "0.1.0"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]
        """)
        write(joinpath(project, "src", "HTMXOTestJobFixture.jl"),
            "module HTMXOTestJobFixture\nend\n")
        write(joinpath(project, "test", "items.jl"), """
        \"\"\"A passing fixture with output.\"\"\"
        @testitem "pass" tags=[:fixture] begin end
        @testitem "mutate" tags=[:fixture] begin end
        @testitem "fail" tags=[:fixture] begin end
        """)
        write(joinpath(project, "test", "runtests.jl"), """
        using Test
        prefix = "--htmxo-test="
        selectors = [arg[length(prefix) + 1:end] for arg in ARGS if startswith(arg, prefix)]
        isempty(selectors) && error("fixture requires an exact selection")
        for selector in selectors
            name = split(selector, "::"; limit=2)[2]
            println("fixture output <unsafe> for ", name)
            @testset "fixture selection" begin
                if name == "pass"
                    @test true
                elseif name == "mutate"
                    write(joinpath(@__DIR__, "..", "child-marker.txt"), "child process")
                    @test true
                elseif name == "fail"
                    @test false
                else
                    error("unknown fixture selection: " * name)
                end
            end
        end
        """)

        catalog = discover_test_items(project)
        @test isempty(catalog.errors)
        @test length(catalog.items) == 3
        by_name = Dict(item.name => item for item in catalog.items)

        function await_job(count; timeout=60.0)
            deadline = time() + timeout
            while time() < deadline
                jobs = HTMXObjects._test_job_snapshot(project)
                if length(jobs) >= count && !(jobs[1].status in (:queued, :running))
                    return jobs[1]
                end
                sleep(0.05)
            end
            error("timed out waiting for isolated test job")
        end

        test_run_batch!(project, [by_name["pass"].id, by_name["mutate"].id])
        passing = await_job(1)
        @test passing.status == :passed
        @test passing.exitcode == 0
        @test isfile(joinpath(project, "child-marker.txt"))
        @test contains(HTMXObjects._read_test_log(passing), "fixture output <unsafe>")

        rendered = repr("text/html", test_list(project))
        @test contains(rendered, "fixture output &lt;unsafe&gt;")
        @test !contains(rendered, "fixture output <unsafe>")

        complete_marker = "complete-output-begins-here"
        bounded_log = joinpath(project, "bounded-output.log")
        write(bounded_log, complete_marker * "\n" * repeat("x", HTMXObjects._TEST_LOG_LIMIT + 1))
        bounded_job = HTMXObjects.TestRunJob("bounded-fixture", String[], ["bounded"], :passed,
            time(), time(), time(), 0, bounded_log, nothing, "")
        store = HTMXObjects._test_store(project)
        lock(store.lock)
        try
            pushfirst!(store.jobs, bounded_job)
        finally
            unlock(store.lock)
        end
        preview = repr("text/html", HTMXObjects._test_job_view(bounded_job; prefix="/tests"))
        @test !contains(preview, complete_marker)
        @test contains(preview, "Open complete output")
        @test contains(preview, "/tests/output/bounded-fixture")
        complete = repr("text/html", test_output(project, bounded_job.id; prefix="/tests"))
        @test contains(complete, complete_marker)

        test_run!(project, by_name["fail"].id)
        failing = await_job(2)
        @test failing.status == :failed
        @test failing.exitcode != 0
        @test contains(HTMXObjects._read_test_log(failing), "Test Failed")
        @test contains(repr("text/html", test_list(project)), "failed")

        before_unknown = length(HTMXObjects._test_job_snapshot(project))
        unknown = repr("text/html", test_run!(project, "not-a-catalog-id"))
        @test contains(unknown, "Unknown test selection")
        @test length(HTMXObjects._test_job_snapshot(project)) == before_unknown

        bad_log = joinpath(project, "missing", "log.txt")
        error_job = HTMXObjects.TestRunJob("error-fixture", String[], String[], :queued,
            time(), nothing, nothing, nothing, bad_log, nothing, "")
        error_store = HTMXObjects.TestRunStore(ReentrantLock(), [error_job])
        HTMXObjects._execute_test_job!(error_store, project, error_job)
        @test error_job.status == :error
        @test !isempty(error_job.error)

        test_clear_cache!(project)
        @test isempty(HTMXObjects._test_job_snapshot(project))
    end
end

"""
A route returning ordinary structured data (a `NamedTuple` of results) must
render in HTML/HX mode, not raise `MethodError: no method matching
show(::IO, ::MIME"text/html", ::NamedTuple)` and degrade into a recorded
error article. Regression for the semantic-app snag: `?plain` markdown mode
already rendered any value, so the HTML side was the asymmetry.
"""
@testitem "generic_html - structured results render in HTML/HX mode" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: generic_html, to_response, _html_value

    # The reported shape: a plain NamedTuple result.
    body = String(to_response((accepted=3, rejected=1, note="ok")).body)
    @test contains(body, "<dl>")
    @test contains(body, "accepted")
    @test contains(body, "3")
    @test contains(body, "note")
    @test contains(body, "ok")

    # Dicts take the same mapping shape.
    @test contains(repr("text/html", generic_html(Dict(:a => 1))), "<dl>")

    # Equal-length vector columns render as a table instead.
    tbl = repr("text/html", generic_html((name=["a", "b"], score=[1, 2])))
    @test contains(tbl, "<table>")
    @test contains(tbl, "<th>name</th>")
    @test contains(tbl, "<td>b</td>")

    # Scalars, `nothing`, and multi-line values all have a representation.
    @test contains(repr("text/html", generic_html(42)), "42")
    @test generic_html(nothing) == ""
    # A matrix is a first-class grid shape, not the multi-line text fallback.
    @test contains(repr("text/html", generic_html([1 2; 3 4])), "<table>")
    # Values with no dedicated shape still take the multi-line `<pre>` fallback
    # — including arrays of three or more dimensions, which are out of scope.
    @test contains(repr("text/html", generic_html(zeros(2, 2, 2))), "<pre>")

    # Values are escaped — data must never reach the client as trusted HTML.
    escaped = String(to_response((danger="<script>x</script>",)).body)
    @test !contains(escaped, "<script>")
    @test contains(escaped, "&lt;script&gt;")

    # Existing behavior is untouched: Nodes, top-level strings, array
    # fragments, and OOB-swap Pairs all still pass straight through.
    @test _html_value(h.p("hi")) isa HTMXObjects.Node
    @test _html_value("<b>raw</b>") == "<b>raw</b>"
    @test String(to_response([h.p("a"), h.p("b")]).body) == "<p>a</p>\n<p>b</p>"
    @test contains(String(to_response(h.p("x") => "slot").body), "hx-swap-oob")
end

"""
End-to-end counterpart: a live `@get` returning a `NamedTuple` must answer an
HX request with the result itself — status 200 *and* the data — rather than
200 with an error article and an `X-HTMXO-Error-Id` header.
"""
@testitem "generic_html - live @get returning a NamedTuple" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    @htmx struct StructuredResultApp
        __page__(content) = h.html(h.body(content))
        @get summary() = (accepted=3, rejected=1)
    end
    route!(StructuredResultApp())
    port = 8101
    serve(; port, async=true)
    try
        r = HTTP.get("http://127.0.0.1:$port/summary";
                     headers=["HX-Request" => "true"], status_exception=false)
        @test r.status == 200
        @test HTTP.header(r, "X-HTMXO-Error-Id", "") == ""
        body = String(r.body)
        @test contains(body, "<dl>")
        @test contains(body, "accepted")
        @test !contains(body, "Something went wrong")

        # Full-page navigation renders the same structure inside `__page__`,
        # not `show(::MIME"text/plain")` text.
        page = String(HTTP.get("http://127.0.0.1:$port/summary").body)
        @test contains(page, "<html><body><dl>")
        @test contains(page, "accepted")

        # `?plain` markdown mode is untouched.
        md = String(HTTP.get("http://127.0.0.1:$port/summary?plain=1").body)
        @test contains(md, "accepted = 3")
    finally
        terminate()
    end
end

"""
A route returning a `Matrix` must render as a grid. The generic normalizer
treats arrays element-wise, which for a 2-D array flattened the cells into
column-major order with the shape gone — a `Matrix{Float64}` result reached
the client as an unlabelled, mis-ordered run of numbers. Regression for the
semantic-app matrix snag.
"""
@testitem "generic_html - matrices render as grids, not flattened" setup=[HTMXOTestImports] tags=[:unit] begin
    import HTMXObjects: generic_html, to_response, _html_value

    # The reported shape: a materialized numeric grid.
    body = String(to_response([1.0 2.0 3.0; 4.0 5.0 6.0]).body)
    @test contains(body, "<table>")
    # Row-major reading order, one `tr` per matrix row — the flattening bug
    # emitted 1.0, 4.0, 2.0, … instead.
    @test contains(body, "<tr><td>1.0</td><td>2.0</td><td>3.0</td></tr>")
    @test contains(body, "<tr><td>4.0</td><td>5.0</td><td>6.0</td></tr>")

    # Cell values are escaped, exactly like every other generic shape.
    escaped = String(to_response(["<script>x" "b"; "c" "d"]).body)
    @test !contains(escaped, "<script>")
    @test contains(escaped, "&lt;script&gt;")

    # A matrix holding renderable values keeps the element-wise fragment
    # behavior — this only adds rendering where there was none.
    @test String(to_response([h.p("a") h.p("b")]).body) == "<p>a</p>\n<p>b</p>"

    # Vectors are unchanged: still an element-wise fragment.
    @test String(to_response([1.0, 2.0]).body) == "<span>1.0</span>\n<span>2.0</span>"

    # Degenerate shapes have a representation rather than raising.
    @test contains(repr("text/html", generic_html(zeros(0, 0))), "<table>")
    @test contains(repr("text/html", generic_html(reshape([7.0], 1, 1))), "<td>7.0</td>")
end

"""
End-to-end counterpart: a live `@get` returning a `Matrix{Float64}` must
answer an HX request with the grid itself — status 200 *and* the data — not
200 with an error article and an `X-HTMXO-Error-Id` header, which is how the
`MethodError` from `repr("text/html", ::Float64)` surfaced to the reporter.
"""
@testitem "generic_html - live @get returning a Matrix" setup=[HTMXOTestImports] tags=[:integration, :server] begin
    @htmx struct MatrixResultApp
        __page__(content) = h.html(h.body(content))
        @get prediction_grid() = [1.0 2.0; 3.0 4.0]
    end
    route!(MatrixResultApp())
    port = 8102
    serve(; port, async=true)
    try
        r = HTTP.get("http://127.0.0.1:$port/prediction_grid";
                     headers=["HX-Request" => "true"], status_exception=false)
        @test r.status == 200
        @test HTTP.header(r, "X-HTMXO-Error-Id", "") == ""
        body = String(r.body)
        @test contains(body, "<tr><td>1.0</td><td>2.0</td></tr>")
        @test contains(body, "<tr><td>3.0</td><td>4.0</td></tr>")
        @test !contains(body, "Something went wrong")

        # Full-page navigation renders the same grid inside `__page__`.
        page = String(HTTP.get("http://127.0.0.1:$port/prediction_grid").body)
        @test contains(page, "<html><body><table>")

        # `?plain` markdown mode is untouched.
        md = String(HTTP.get("http://127.0.0.1:$port/prediction_grid?plain=1").body)
        @test !isempty(md)
    finally
        terminate()
    end
end
