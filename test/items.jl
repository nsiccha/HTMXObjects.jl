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
    PolicyApp, SlowPolicyApp, SlowPagePolicyApp, SlowRecordApp,
    MultiVerbPolicyApp, reset_slow_page!, release_slow_page!, slow_page_runs,
    StackedSemanticRoute, ContextSemanticApp, ExternalContextApp, ExternalContextChild, JobScopedApp,
    ParamlessHostApp, ParamlessHostChild,
    BareExternalApp, BareExternalChild, InlineContextApp,
    _SINGLETON_APPDATA,
    # Navigation / reflection-graph, Resource and page-wrapper fixtures. A
    # `@testmodule` is an ordinary module, so an item only sees what is
    # exported here — an unexported fixture is `UndefVarError` at the item,
    # not a load failure, which is why the omission survived every selective
    # run and only a full suite exposed it.
    NavLeaf, NavSection, NavRoot, NavPlainRoot,
    NavChainChild, NavChainRoot, NavSlurpRoot,
    SwapView, SwapSection, SwapRoot,
    NoteDraft, InertCollection, NOTE_STORE, _reset_note_store!, ResourceApp,
    MockPage, BluntPage, ValuePageLeaf, ValuePageRoot, BluntPageRoot,
    IndexedMountChild, IndexedMountRoot,
    DomainNode, DomainChild, StageChild, DomainRoot, BoolPropRoot

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
    # `dataset`'s domain depends on `cohort`, so `cohort` is a FIELD: a declared
    # domain reads the node it is evaluated against, and the framework remakes
    # that node with the submitted value before asking. `run` never declares
    # `cohort` — reading it in the body is enough for the `dependson` walk to
    # promote it to a `:context` input, and DO infers the domain's dependency
    # from the same walk, so there is no `dependencies=` to keep in sync by hand.
    @options cohort = (:north, :south)
    cohort::Symbol

    choices(key::Symbol) = key === :north ? (
        (value=:n1, label="North 1", group="North"),
        (value=:n2, label="North 2", disabled=true),
    ) : (:s1,)

    @options dataset = choices(cohort)
    @options mode = (
        (value=:fast, label="Fast"),
        (value=:safe, label="Safe", help="Full checks"),
        (value=:unsafe, label="Unsafe", disabled=true),
    )
    @get run(; dataset::Symbol, mode::Symbol=:fast, count::Int=1) =
        h.p("$(dataset):$(cohort):$(mode):$(count)")

    @include nested = begin
        @options quality = (:quick, :full)
        @post execute(; quality::Symbol=:quick) =
            h.p("nested:$(quality)")
    end
end

# The graph is the only operation registry: adding another route inside this
# mounted child is enough for `semantic_app` to discover, render, and execute
# it. The enclosing selection is declared once and inherited as hidden context.
@htmx struct SemanticAutoApp
    @param study::Symbol = :alpha

    @include models = begin
        @options model = (:base, :full)
        @get fit(; model::Symbol=:base) =
            h.p("fit:$(study):$(model)")

        @options draws = (10, 20)
        @post predict(; draws::Int=10) =
            h.p("predict:$(study):$(draws)")
    end
end

@htmx struct IndexedSemanticAutoApp
    @include models(model::Symbol) = begin
        @options mode = (:quick, :full)
        @get run(; mode::Symbol=:quick) =
            h.p("$(model):$(mode)")
    end
end

@htmx struct ZeroConfigSemanticApp
    @options study = (:north, :south)
    study::Symbol
    @options dose = (50, 100)
    dose::Int

    unrelated = Ref("survives")

    @get fit() = h.p("fit:$(study):$(dose):$(objectid(unrelated))")
    @post predict() = h.p("predict:$(study):$(dose):$(objectid(unrelated))")
end


@htmx struct ZeroConfigSemanticChild
    @options study = (:north, :south)
    study::Symbol
    @options dose = (50, 100)
    dose::Int

    unrelated = Ref("mounted-survives")

    @post predict() = h.p("mounted:$(study):$(dose):$(objectid(unrelated))")
end


@htmx struct ZeroConfigSemanticHost
    @include models = ZeroConfigSemanticChild(:north, 50)
end

# `model`'s domain depends on `study`, so `study` is a field of the node the
# domain is evaluated against — not another argument of `analyze`. That makes
# the child an external one: an inline `@include … = begin … end` is constructed
# with no arguments and so cannot carry a required field. `fit_key` still comes
# from the enclosing `@param` by delegation, and is carried as hidden context
# rather than generated as a control.
@htmx struct ContextAnalysisChild
    @param (; fit_key) = __parent__

    model_options(key::Symbol) = key === :alpha ? (
        (value=:a1, label="Alpha 1"),
        (value=:a2, label="Alpha 2"),
    ) : (
        (value=:b1, label="Beta 1"),
        (value=:b2, label="Beta 2"),
    )

    @options study = (
        (value=:alpha, label="Alpha"),
        (value=:beta, label="Beta"),
    )
    study::Symbol

    @options model = model_options(study)
    @get analyze(; model::Symbol) =
        h.p("$(fit_key):$(study):$(model)")

    @get raw_context(; count::Int=1)::MIMEResponse =
        MIMEResponse("text/plain", "$(fit_key):$(count)")
end

@htmx struct ContextSemanticApp
    @param fit_key::String
    @include analysis = ContextAnalysisChild(:alpha)
end

# A separately declared child that also *reads* the enclosing `@param` in its
# own route body needs the delegation line: `operation_form` carries the
# enclosing value as hidden context for either include shape, but only an
# inline child inherits the parent's `@param` as a property. Without the
# delegation, `fit_key` here is an unbound name and the route throws
# `UndefVarError` the first time it is actually executed.
@htmx struct ExternalContextChild
    @param (; fit_key) = __parent__
    @options value = (:ok, :alt)
    @get analyze(; value::Symbol=:ok) =
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
    @options value = (:ok, :alt)
    @get analyze(; value::Symbol=:ok) =
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

# A route whose body is slow enough that "did the request task run it to
# completion?" is observable. `PolicyApp`'s bodies are instant, so they cannot
# distinguish a genuine non-blocking start from a blocking one.
@htmx struct SlowPolicyApp
    @get slow(; count::Int=1) = (sleep(3.0); h.p("slow:$(count)"))
end

const slow_page_gate = Ref{Base.Event}(Base.Event())
const slow_page_runs = Ref(0)

function reset_slow_page!()
    slow_page_gate[] = Base.Event()
    slow_page_runs[] = 0
    nothing
end

release_slow_page!() = notify(slow_page_gate[])

function slow_page_work(count)
    slow_page_runs[] += 1
    wait(slow_page_gate[])
    h.p("terminal:$(count)"; id="slow-page-terminal")
end

function slow_page_driver()
    h.script(Raw(raw"""
    (function() {
      var phaseKey = 'htmxo-direct-page-phase';
      var phase = sessionStorage.getItem(phaseKey) || 'first';

      document.addEventListener('DOMContentLoaded', function() {
        if (document.getElementById('slow-page-shell') &&
            document.querySelector('[data-htmxo-operation-load]')) {
          document.body.dataset[phase === 'first' ? 'firstShell' : 'secondShell'] = '1';
        }
      });

      document.body.addEventListener('htmx:afterSwap', function() {
        if (document.querySelector('[hx-trigger*="every"]')) {
          document.body.dataset[phase === 'first' ? 'firstPoller' : 'secondPoller'] = '1';
        }
        if (!document.getElementById('slow-page-terminal')) return;

        if (phase === 'first') {
          sessionStorage.setItem('htmxo-saw-first-shell', document.body.dataset.firstShell || '');
          sessionStorage.setItem('htmxo-saw-first-poller', document.body.dataset.firstPoller || '');
          sessionStorage.setItem(phaseKey, 'second');
          setTimeout(function() { location.reload(); }, 50);
        } else {
          document.body.dataset.firstShell = sessionStorage.getItem('htmxo-saw-first-shell') || '';
          document.body.dataset.firstPoller = sessionStorage.getItem('htmxo-saw-first-poller') || '';
          document.body.dataset.terminal = '1';
          document.body.dataset.secondDirectTerminal =
            document.body.dataset.secondPoller === '1' ? '0' : '1';
        }
      });
    })();
    """))
end

@htmx struct SlowPagePolicyApp
    __page__(content) = htmx(
        h.main(h.h1("DIRECT PAGE SHELL"), content; id="slow-page-shell"),
        slow_page_driver(); hyperscript_version=nothing, feedback=false,
        compose=false, overlay=false)
    @get @progress slow(; count::Int=1) = slow_page_work(count)
end

# Slower than `record!`'s grace period, fast enough to record in a test. Pins
# that static export keeps capturing the finished HTML now that the zero-config
# default is `:auto` — an `hx=true` recording is a synthesized HTMX request, so
# without the forced `:blocking` it would write a Treebars poller to disk.
@htmx struct SlowRecordApp
    @get index() = h.main(h.p("home"))
    @get slowrec() = (sleep(0.5); h.p("finished"))
end

@htmx struct MultiVerbPolicyApp
    @options mode = (:raw, :json)
    @get exchange(; mode::Symbol=:raw)::MIMEResponse =
        MIMEResponse("text/plain", "get:$(mode)")
    @options count = (1, 2)
    @post exchange(; count::Int=1) =
        h.p("post:$(count)")
end

# One declaration owns its semantic input, route, disk materialization, and
# progress policy. The typed call LHS exercises the route-return annotation
# parser while leaving the annotation visible to DynamicObjects.
@htmx struct StackedSemanticRoute
    __cache_base__ = tempdir()
    @options count = (1, 2, 3)
    @get @mmap @progress model(; count::Int=2)::Vector{Float64} =
        collect(1.0:count)
end

# --- Navigation / reflection-graph fixtures --------------------------------
#
# A three-level mount chain with a computed dependency at the leaf, one node
# whose `__page__` asks for navigation and one whose `__page__` does not. The
# pair is the point: the framework must thread navigation into the first and
# leave the second byte-identical.

@htmx struct NavLeaf
    """The number this leaf reports."""
    value::Int = 7
    doubled = 2 * value
    @get index() = string(doubled)
end

@htmx struct NavSection
    label::String = "sec"
    @include leaf = NavLeaf()
    @get index() = "section $label"
    @post act(; note="") = "acted $note"
end

"""An application root used for navigation and reflection tests."""
@htmx struct NavRoot
    @include section = NavSection()
    @include reflect = ReflectionRoutes(; root=NavRoot)
    @include schema = SchemaRoutes(; root=NavRoot)
    __page__(content; navigation=nothing) =
        h.div(h.nav(isnothing(navigation) ? "NONAV" : "NAV:" * navigation.current.path),
              content)
    @get index() = "root"
end

# Same shape, but the page wrapper never declared `navigation`. Nothing may be
# passed to it.
@htmx struct NavPlainRoot
    @include section = NavSection()
    __page__(content) = h.div(h.nav("PLAIN-SHELL"), content)
    @get index() = "plainroot"
end

# A two-level page chain. Both nodes wrap, and each must receive the navigation
# of ITS OWN node — the outer shell sees the root, the inner sees the child —
# rather than one record computed at the leaf and shared up the chain.
@htmx struct NavChainChild
    __page__(content; navigation=nothing) =
        h.section(h.span("INNER:" *
                         (isnothing(navigation) ? "none" : navigation.current.path)),
                  content)
    @get index() = "child-body"
end

@htmx struct NavChainRoot
    @include child = NavChainChild()
    __page__(content; navigation=nothing) =
        h.div(h.span("OUTER:" *
                     (isnothing(navigation) ? "none" : navigation.current.path)),
              content)
    @get index() = "root-body"
end

# A three-level page chain for PARTIAL swaps. Every level tags its own chrome,
# so a response body names exactly which wrappers it carries. The indexed mount
# is the sibling case: `/section/item/a` and `/section/item/b` are the same
# level but different mount prefixes, so switching between them brings new
# chrome even though nothing about the chain's shape changed.

@htmx struct SwapView
    key::String
    __page__(content) = h.div(h.nav("VIEW-CHROME:" * key), content)
    @get index() = "view-body"
    @get detail() = "detail-body"
end

@htmx struct SwapSection
    @include view = SwapView("v")
    @include item(key::String) = SwapView(key)
    __page__(content) = h.section(h.nav("SECTION-CHROME"), content)
    @get index() = "section-body"
end

@htmx struct SwapRoot
    @include section = SwapSection()
    __page__(content) = h.div(h.nav("ROOT-CHROME"), content)
    @get index() = "root-body"
end

# A page wrapper that slurps. It cannot error on an extra keyword, so the
# framework is free to pass navigation through.
@htmx struct NavSlurpRoot
    @include section = NavSection()
    __page__(content; kwargs...) =
        h.div(h.nav(haskey(kwargs, :navigation) ? "SLURP-GOT-NAV" : "SLURP-NONE"), content)
    @get index() = "slurproot"
end

# --- Resource fixtures ------------------------------------------------------

struct NoteDraft
    title::String
    body::String
end

# A real Base-shaped store, plus a deliberately inert value standing in for the
# stub-backed collections a mock uses. The inert one must survive construction
# and route registration untouched.
struct InertCollection end

# The store lives OUTSIDE the root. Under the default `:request` root scope the
# root is reconstructed per request, so a collection declared as a root property
# is a fresh object on every request and a write in one request is invisible to
# the next. That is root-lifetime semantics, not a `Resource` question — a
# `Resource` is a view over whatever collection it is handed, and it is the
# application's job to hand it one that outlives a request (a module-level
# store, a `RootProvider(...; scope=:session)`, a database handle, a directory).
const NOTE_STORE = Dict{String,NoteDraft}()

_reset_note_store!() = (empty!(NOTE_STORE);
                        NOTE_STORE["a"] = NoteDraft("A", "first"); NOTE_STORE)

@htmx struct ResourceApp
    notes = NOTE_STORE
    @include note = Resource(notes; input=NoteDraft, name="note",
                             policy=ResourcePolicy(; key=context -> context.draft.title))
    @include stub = Resource(InertCollection(); input=NoteDraft, name="stub")
    @get index() = "resource-root"
end


# --- Callable-value page wrapper --------------------------------------------
#
# The concise form an application actually writes: `__page__ = shell(...)`,
# whose VALUE is callable and takes `navigation`. The property itself declares
# no signature, so only the value can answer the question.

struct MockPage
    label::String
end
(page::MockPage)(content; navigation=nothing) =
    string(page.label, "|nav=", isnothing(navigation) ? "none" :
           join([child.name for child in navigation.descendants], ","), "|", content)

struct BluntPage end
(page::BluntPage)(content) = string("blunt|", content)

@htmx struct ValuePageLeaf
    @get index() = "leaf"
end

@htmx struct ValuePageRoot
    __page__ = MockPage("shell")
    @include section = ValuePageLeaf()
    @get index() = "value-root"
end

@htmx struct BluntPageRoot
    __page__ = BluntPage()
    @include section = ValuePageLeaf()
    @get index() = "blunt-root"
end

@htmx struct IndexedMountChild
    key::String
    @get index() = "child $key"
    @get extra() = "extra $key"
end

@htmx struct IndexedMountRoot
    @get index() = "indexed-root"
    @include item(key::String) = IndexedMountChild(key)
end

# --- Indexed selection by domain candidate ----------------------------------
#
# A node-valued mount and an enum-valued one. `string(::DomainNode)` is the
# stable serialized identity the URL segment carries — the application owns
# that, the framework only matches on it.

abstract type AbstractDomainNode end

struct DomainNode <: AbstractDomainNode
    key::Symbol
    payload::String
end
Base.string(node::DomainNode) = string(node.key)

@enum SelStage draft review final

@htmx struct DomainChild
    node::Any
    @get index() = string("node=", string(node), " payload=", node.payload)
end

@htmx struct StageChild
    stage::Any
    @get index() = string("stage=", stage, "::", typeof(stage))
end

@htmx struct DomainRoot
    catalogue = AbstractDomainNode[DomainNode(:synthetic_depot, "depot"),
                                   DomainNode(:real_survey, "survey")]
    @options(node) = catalogue
    @include dataset(node::AbstractDomainNode) = DomainChild(node)
    # No `@options`: the enum's instances ARE the domain.
    @include compilation(stage::SelStage) = StageChild(stage)
    @include chains(chain::Integer) = StageChild(chain)
    @get index() = "domain-root"
end

# A typed computed property whose type is an ordinary Julia type, not a node.
# `paginate::Bool = false` registers with DynamicObjects' analyzer hook, so a
# route walk reading that hook raw would try to descend into `Bool`.

@htmx struct BoolPropRoot
    paginate::Bool = false
    @get index() = string("paginate=", paginate)
end

end # @testmodule HTMXOTestFixtures

@testmodule HTMXOBoolRadioFixtures begin
using HTMXObjects

export BoolRadioApp

@htmx struct BoolRadioApp
    @get run(; flag::Bool=false) = string(flag)
end

end # @testmodule HTMXOBoolRadioFixtures

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
    # Reflection reports the DECLARATION, never its value: `@options` lowers to
    # a lazily computed property, so describing a type runs nothing and the
    # option list is empty here by construction. What the declaration reads is
    # inferred, not authored — `choices` (the property) and `cohort` (the field
    # it is called with) both come from the one `dependson` walk.
    @test dataset.domain.kind === :declared
    @test dataset.domain.options == NamedTuple[]
    @test dataset.domain.cardinality === nothing
    @test dataset.domain.declaration.expression_string == "choices(cohort)"
    @test dataset.domain.declaration.dependencies == [:choices, :cohort]
    @test !dataset.domain.declaration.static
    @test mode.domain.kind === :declared
    @test mode.domain.declaration.static
    @test mode.default === :fast

    # `cohort` is not declared by `run`; the body reads it, so it arrives as a
    # `:context` input carrying the field's own declared domain.
    cohort = only(filter(param -> param.name === :cohort, route.params))
    @test cohort.kind === :context
    @test cohort.domain.kind === :declared

    # The pre-existing reflection API remains byte-shape compatible.
    reflected = only(filter(route -> route.name === :run, HTMXObjects.reflect(SemanticApp)))
    @test keys(reflected) == (:verb, :path, :name, :doc, :params)

    app = SemanticApp(:north)

    # Evaluating the same declarations against an object is the object-level
    # half of the contract, and it is what the generated controls below read.
    @test HTMXObjects.DynamicObjects.static_domain(
        HTMXObjects.DynamicObjects.property_options(app, :mode)).cardinality == 3
    @test [option.value for option in HTMXObjects.DynamicObjects.static_domain(
        HTMXObjects.DynamicObjects.property_options(app, :dataset)).options] == [:n1, :n2]
    @test HTMXObjects.DynamicObjects.property_options(
        HTMXObjects.DynamicObjects.remake(app; cohort=:south), :dataset) == (:s1,)
    html = repr("text/html", operation_form(app, :run; values=(cohort=:north,),
                                             target_id="#semantic-result"))
    @test contains(html, "hx-get=\"/run\"")
    @test contains(html, "hx-target=\"#semantic-result\"")
    @test contains(html, "North 1")
    @test contains(html, "North 2")
    @test contains(html, "disabled=\"true\"")
    @test contains(html, "type=\"number\"")
    @test contains(html, "name=\"count\"")

    # A domain dependency has to be object state, and object state that is
    # REQUIRED has no zero-argument root for the default factory to rebuild per
    # request — so the instance is what gets served. `semantic_app` installs an
    # equivalent provider on its own; here the provider is explicit because this
    # item drives the raw route, not the compiled surface.
    route!(app; root_provider=RootProvider() do _RootT, context
        HTMXObjects.DynamicObjects.remount(app; __req__=context.request,
                                           __route__=context.route)
    end)
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
        # `study` is node state now, not a declared argument of `analyze`: it is
        # bound as context and the node is remade with it, so only `model`
        # reaches the call.
        @test transport[].call_kwargs == (model=:a1,)
        @test startswith(transport[].seen_transport.poll_url,
            "/analysis/analyze?fit_key=fit-17&study=alpha&model=a1&" *
            "__htmxo_poll=1&__htmxo_operation=")
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
    import HTMXObjects: _clear_operation_polls!, _operation_execution_mode,
        _operation_polling_impl, _property_descriptor, _run_operation,
        _resolve_operation_value
    import HTMXObjects.DynamicObjects

    # `:auto` is the default so an ordinary route gets the live progress tree
    # with no `route!(…; operation_policy=…)` registration. It stays conditional
    # (GET + HTMX + a pending-capable descriptor), which the `plain` vs `hx`
    # cases below pin — nothing that was direct becomes a poller by default.
    @test OperationPolicy().mode === :auto
    @test OperationPolicy(:blocking).mode === :blocking
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
    # The descriptor carries the DECLARATION; the option list is an object
    # question and stays empty until something evaluates it.
    @test only(filter(input -> input.name === :mode,
                      get_exchange.property.inputs)).domain.kind === :declared
    @test only(filter(input -> input.name === :count,
                      post_exchange.property.inputs)).domain.kind === :declared
    multi = MultiVerbPolicyApp()
    @test length(HTMXObjects.DynamicObjects.static_domain(
        HTMXObjects.DynamicObjects.property_options(multi, :mode)).options) == 2
    @test length(HTMXObjects.DynamicObjects.static_domain(
        HTMXObjects.DynamicObjects.property_options(multi, :count)).options) == 2
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
            transport.retain()
            h.aside("polling")
        end
    try
        operation = _run_operation(target, PolicyApp, :html, Verb{:GET}(),
                                   hx, 0, 0;
                                   operation_policy=OperationPolicy(:auto))
        @test repr("text/html", operation.value) == "<aside>polling</aside>"
        @test length(polls) == 1
        @test only(polls).call_kwargs == (count=2,)
        poll_url = only(polls).transport.poll_url
        @test startswith(poll_url,
            "/html?count=2&__htmxo_poll=1&__htmxo_operation=")
        @test only(polls).transport.grace_period == 0.1

        poll_request = HTTP.Request(
            "GET", poll_url, ["HX-Request" => "true"])
        polled = _run_operation(target, PolicyApp, :html, Verb{:GET}(),
                                poll_request, 0, 0;
                                operation_policy=OperationPolicy(:auto))
        @test repr("text/html", polled.value) == "<aside>polling</aside>"
        @test length(polls) == 2
        @test last(polls).call_kwargs == (count=2,)
        @test last(polls).transport.poll_url == poll_url
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
        _clear_operation_polls!()
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
                      stacked.property.inputs)).domain.kind === :declared
    @test length(HTMXObjects.DynamicObjects.static_domain(
        HTMXObjects.DynamicObjects.property_options(
            StackedSemanticRoute(), :count)).options) == 3
end

# A browser navigation has page chrome available before its slow operation does.
# `:auto` therefore returns that shell immediately and lets one load-triggered
# HX request enter the ordinary grace/poll transport. The proxy prefix must
# survive BOTH generated hops: the initial load URL and every capability poll.
@testitem "direct rich pages load async and preserve their external prefix" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _clear_operation_polls!, _operation_polling_impl

    reset_slow_page!()
    _clear_operation_polls!()
    provider = RootProvider(
        scope=:job,
        key=_req -> "direct-page-unit",
        retention=RootRetention(max_entries=2),
    )
    route!(SlowPagePolicyApp(); root_provider=provider)
    router = HTMXObjects.CONTEXT[].service.router

    drive(target, headers=Pair{String,String}[]) = begin
        request = HTTP.Request("GET", target, headers, UInt8[])
        handler = first(HTTP.Handlers.gethandler(router, request))
        @test handler !== HTTP.Handlers.default404
        handler(request)
    end

    direct_headers = [
        "Accept" => "text/html,application/xhtml+xml",
        "X-Forwarded-Prefix" => "/p/SbPMX/",
    ]
    # Exclude first-call Julia compilation from the latency assertion. The
    # behavior under test is that an already-loaded route never waits for the
    # slow operation before returning its shell.
    warm = drive("/slow?count=4", direct_headers)
    @test warm.status == 200
    @test slow_page_runs[] == 0
    elapsed = @elapsed direct = drive("/slow?count=4", direct_headers)
    body = String(direct.body)
    @test elapsed < 1.0
    @test direct.status == 200
    @test contains(body, "DIRECT PAGE SHELL")
    @test contains(body, "data-htmxo-operation-load")
    @test contains(body, "hx-get=\"/p/SbPMX/slow?count=4\"")
    @test contains(body, "hx-trigger=\"load\"")
    @test contains(body, "hx-target=\"this\"")
    @test contains(body, "hx-swap=\"outerHTML\"")
    @test slow_page_runs[] == 0

    transports = Any[]
    old_polling = _operation_polling_impl[]
    _operation_polling_impl[] =
        (_render, _started, _ip, _keys, _call_kwargs, transport) -> begin
            push!(transports, transport)
            transport.retain()
            h.aside("polling")
        end
    try
        hx_headers = [
            "Accept" => "text/html",
            "HX-Request" => "true",
            "X-Forwarded-Prefix" => "/p/SbPMX",
        ]
        started = drive("/slow?count=4", hx_headers)
        @test String(started.body) == "<aside>polling</aside>"
        @test timedwait(() -> slow_page_runs[] == 1, 5.0;
                        pollint=0.01) === :ok
        poll_url = only(transports).poll_url
        @test startswith(poll_url,
            "/p/SbPMX/slow?count=4&__htmxo_poll=1&__htmxo_operation=")

        internal_poll_url = replace(poll_url, "/p/SbPMX" => ""; count=1)
        polled = drive(internal_poll_url, hx_headers)
        @test String(polled.body) == "<aside>polling</aside>"
        @test last(transports).poll_url == poll_url
    finally
        release_slow_page!()
        _operation_polling_impl[] = old_polling
        _clear_operation_polls!()
    end
end

@testitem "mounted direct-page polling completes in a real browser" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:browser, :semantic] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using Sockets
        import HTMXObjects: _clear_operation_polls!

        chrome = Sys.which("google-chrome")
        isnothing(chrome) && (chrome = Sys.which("chromium"))
        isnothing(chrome) && error(
            "HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        reset_slow_page!()
        _clear_operation_polls!()
        provider = RootProvider(
            scope=:job,
            key=_req -> "direct-page-browser",
            retention=RootRetention(max_entries=2),
        )
        route!(SlowPagePolicyApp(); root_provider=provider)
        router = HTMXObjects.CONTEXT[].service.router
        prefix = "/p/SbPMX"
        forwarded_targets = String[]
        released = Ref(false)

        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!(Sockets.localhost, port; verbose=false) do outer
            external_target = String(outer.target)
            path = HTTP.URI(external_target).path
            startswith(path, prefix * "/") || return HTTP.Response(404)
            push!(forwarded_targets, external_target)

            internal_target = external_target[length(prefix) + 1:end]
            headers = Pair{String,String}[
                String(key) => String(value) for (key, value) in outer.headers
                if lowercase(String(key)) != "x-forwarded-prefix"
            ]
            push!(headers, "X-Forwarded-Prefix" => prefix)
            inner = HTTP.Request(String(outer.method), internal_target,
                                 headers, outer.body)
            handler = first(HTTP.Handlers.gethandler(router, inner))
            handler === HTTP.Handlers.default404 && return HTTP.Response(404)
            response = handler(inner)
            body = String(response.body)
            if !released[] && contains(body, "hx-trigger=\"every ")
                released[] = true
                @async begin
                    sleep(0.4)
                    release_slow_page!()
                end
            end
            response
        end

        try
            dom = mktempdir() do profile
                url = "http://127.0.0.1:$port$prefix/slow?count=9"
                cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=12000 --dump-dom --user-data-dir=$profile $url`
                read(pipeline(cmd; stderr=devnull), String)
            end
            @test contains(dom, "data-first-shell=\"1\"")
            @test contains(dom, "data-first-poller=\"1\"")
            @test contains(dom, "data-second-shell=\"1\"")
            @test contains(dom, "data-terminal=\"1\"")
            @test contains(dom, "data-second-direct-terminal=\"1\"")
            @test !contains(dom, "data-second-poller=\"1\"")
            @test contains(dom, "id=\"slow-page-terminal\"")
            @test contains(dom, "terminal:9")
            @test slow_page_runs[] == 1
            @test length(forwarded_targets) >= 5
            @test all(target -> startswith(target, prefix * "/slow"),
                      forwarded_targets)
            @test any(target -> contains(target, "__htmxo_poll=1"),
                      forwarded_targets)
        finally
            released[] || release_slow_page!()
            close(server)
            _clear_operation_polls!()
        end
    end
end

# Polling transport is only real if the value is started NON-BLOCKINGLY. Every
# other policy test stubs `_operation_polling_impl` and asserts the poller was
# *reached* — which a fully-blocking start also satisfies, because the wrapper
# still runs, just over an already-finished value. So those tests pass whether
# or not the transport does anything, and the regression they miss is total:
# `:auto`/`:polling` degrading to `:blocking` for every route. Pin the actual
# contract — what reaches the seam is an in-flight handle, not a finished value.
@testitem "polling transport starts the operation without blocking" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _operation_polling_impl, _run_operation
    import HTMXObjects.DynamicObjects

    app = SlowPolicyApp()
    target = (context=nothing, root=app, leaf=app)
    starts = Any[]
    old_polling = _operation_polling_impl[]
    _operation_polling_impl[] =
        (render_result, started, _ip, _keys, _call_kwargs, _transport) -> begin
            push!(starts, started)
            h.aside("polling")
        end
    try
        # Warm the path on its own key first — a cold `_run_operation` compiles
        # for seconds, which would swamp the wall-clock assertion below.
        warm = HTTP.Request("GET", "/slow?count=0", ["HX-Request" => "true"])
        _run_operation(target, SlowPolicyApp, :slow, Verb{:GET}(), warm, 0, 0;
                       operation_policy=OperationPolicy(:auto))
        @test only(starts) isa DynamicObjects.Pending

        empty!(starts)
        hx = HTTP.Request("GET", "/slow?count=1", ["HX-Request" => "true"])
        elapsed = @elapsed _run_operation(target, SlowPolicyApp, :slow,
                                          Verb{:GET}(), hx, 0, 0;
                                          operation_policy=OperationPolicy(:auto))
        # The 3s body must NOT have run to completion on the request task.
        @test elapsed < 1.0
        @test only(starts) isa DynamicObjects.Pending

        # `:blocking` is unchanged: the value is fully computed, never a handle.
        empty!(starts)
        plain = HTTP.Request("GET", "/slow?count=2")
        blocking = _run_operation(target, SlowPolicyApp, :slow, Verb{:GET}(),
                                  plain, 0, 0;
                                  operation_policy=OperationPolicy(:blocking))
        @test isempty(starts)
        @test !(blocking.value isa DynamicObjects.Pending)
        @test repr("text/html", blocking.value) == "<p>slow:2</p>"
    finally
        _operation_polling_impl[] = old_polling
    end
end

# The whole point of the default is that the consumer who writes the LEAST
# config gets the good behaviour. Every other policy test passes an explicit
# `operation_policy=`, so none of them can tell whether an app that declares
# nothing gets `:auto` or `:blocking` — which is exactly the question a
# consumer cannot answer from the code either. Pin it from the registry AND
# through a real route registration, so a future change to `route!`'s kwarg
# default cannot silently put long routes back on the request task.
@testitem "zero-config apps default to :auto" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _operation_policies, _operation_polling_impl,
        _run_operation
    import HTMXObjects.DynamicObjects

    @test OperationPolicy().mode === :auto

    # `route!` with no `operation_policy` at all — the SbPMX `__init__` shape.
    route!(SlowPolicyApp())
    policy = _operation_policies[SlowPolicyApp]
    @test policy.mode === :auto

    app = SlowPolicyApp()
    target = (context=nothing, root=app, leaf=app)
    starts = Any[]
    old_polling = _operation_polling_impl[]
    _operation_polling_impl[] =
        (_render, started, _ip, _keys, _call_kwargs, _transport) -> begin
            push!(starts, started)
            h.aside("polling")
        end
    try
        # Warm on its own key: a cold `_run_operation` compiles for seconds,
        # which would swamp the wall-clock assertion below.
        warm = HTTP.Request("GET", "/slow?count=100", ["HX-Request" => "true"])
        _run_operation(target, SlowPolicyApp, :slow, Verb{:GET}(), warm, 0, 0;
                       operation_policy=policy)
        empty!(starts)

        hx = HTTP.Request("GET", "/slow?count=101", ["HX-Request" => "true"])
        elapsed = @elapsed _run_operation(target, SlowPolicyApp, :slow,
                                          Verb{:GET}(), hx, 0, 0;
                                          operation_policy=policy)
        @test elapsed < 1.0
        @test only(starts) isa DynamicObjects.Pending
    finally
        _operation_polling_impl[] = old_polling
    end
end

# `record!` is the one caller that must NOT inherit the `:auto` default: its
# `hx=true` variant synthesizes an HTMX request, so an unforced policy would
# write a Treebars poller to disk instead of the finished fragment. Measured
# before the force was added: `hx/slowrec.html` was a `treebar-poller` div.
@testitem "record! forces blocking transport" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :server] begin
    import HTMXObjects: _operation_policies

    mktempdir() do dir
        record!(SlowRecordApp(); record_dir=dir, paths=["/", "/slowrec"],
                full=false, hx=true, markdown=false)
        @test _operation_policies[SlowRecordApp].mode === :blocking
        recorded = read(joinpath(dir, "hx", "slowrec.html"), String)
        @test contains(recorded, "<p>finished</p>")
        @test !contains(recorded, "treebar-poller")
    end
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

@testitem "htmx() emits a doctype (standards mode)" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit] begin
    # A page without `<!DOCTYPE html>` renders in quirks mode, which some
    # browser libraries refuse to run in at all (KaTeX's `katex.render` throws
    # "KaTeX doesn't work in quirks mode", and `throwOnError: false` does not
    # suppress it). The doctype must be the very first thing in the bytes.
    page = htmx(h.main("content"))
    @test page isa HTMLDocument
    html = repr("text/html", page)
    @test startswith(html, "<!DOCTYPE html>\n<html")
    @test count("<!DOCTYPE", html) == 1

    # …and it survives the response pipeline, which is what a browser sees.
    body = String(to_response(page).body)
    @test startswith(body, "<!DOCTYPE html>\n<html")

    # Fragments are not documents: an HX swap must NOT carry a doctype.
    @test !contains(String(to_response(h.div("fragment")).body), "<!DOCTYPE")

    # The static-recording walkers must still reach inside the document:
    # `_disable_for_static` strips non-GET hx attributes and
    # `_inject_static_style` appends the disabled-element style to `<head>`.
    with_post = htmx(h.main(h.button("go"; hx_post="/act")))
    @test contains(repr("text/html", with_post), "hx-post=\"/act\"")
    recorded = repr("text/html", HTMXObjects.static_transform(with_post))
    @test startswith(recorded, "<!DOCTYPE html>\n<html")
    @test !contains(recorded, "hx-post=\"/act\"")
    @test contains(recorded, "data-static-disabled")
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

@testitem "Bool radio values render and validate" setup=[HTMXOBoolRadioFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    # Raw Bool attributes are treated as boolean attributes by the HTML
    # renderer. Form values must be strings so `false` is not omitted.
    @test contains(repr("text/html", soption(false)), "value=\"false\"")
    group_html = repr("text/html", radio_group((; flag=false), (false, true)))
    @test contains(group_html, "name=\"flag\" value=\"false\" checked=\"true\"")
    @test contains(group_html, "name=\"flag\" value=\"true\"")

    app = BoolRadioApp()
    form_html = repr("text/html", operation_form(app, :run))
    @test contains(form_html, "name=\"flag\" value=\"false\" checked=\"true\"")
    @test contains(form_html, "name=\"flag\" value=\"true\"")

    route!(app)
    submitted = HTTP.Request("GET", "/run?flag=false")
    submitted_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, submitted))
    submitted_response = submitted_handler(submitted)
    @test submitted_response.status == 200
    @test String(submitted_response.body) == "false"

    tampered = HTTP.Request("GET", "/run?flag=on")
    tampered_handler = first(HTTP.Handlers.gethandler(
        HTMXObjects.CONTEXT[].service.router, tampered))
    tampered_response = tampered_handler(tampered)
    @test tampered_response.status == 400
    @test contains(String(tampered_response.body), "Bad Request")
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

`TestUIHost` declares no `operation_policy`, so it runs on the zero-config
`:auto` default — and scanning the catalog takes longer than the grace period.
An HTMX GET therefore answers with a poller and the content arrives on a
subsequent poll. Following that round trip is the point: it proves the default
transport actually *delivers*, not merely that it engages.
"""
@testitem "web-included test routes" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:integration, :test_ui] begin
    route!(TestUIHost())
    router = HTMXObjects.CONTEXT[].service.router

    function drive(target)
        request = HTTP.Request("GET", target, ["HX-Request" => "true"], UInt8[])
        handler = first(HTTP.Handlers.gethandler(router, request))
        @test handler !== HTTP.Handlers.default404
        response = handler(request)
        @test response.status == 200
        String(response.body)
    end

    # Either the catalog scan beat the grace period, or we get a poller whose
    # own `hx-get` settles to the same content. Bounded so a genuinely stuck
    # operation fails the test instead of hanging it.
    function settle()
        body = drive("/tests")
        for _ in 1:100
            contains(body, "hx-trigger=\"every ") || return body
            found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""),
                          body)
            @test !isnothing(found)
            poll_target = replace(only(found.captures), "&amp;" => "&")
            @test startswith(poll_target,
                "/tests?__htmxo_poll=1&__htmxo_operation=")
            sleep(0.05)
            body = drive(poll_target)
        end
        body
    end

    get_body = settle()
    @test !contains(get_body, "hx-trigger=\"every ")
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

# --- Navigation and the semantic reflection graph ---------------------------

@testitem "navigation reports current node, ancestors and configurable descendants" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: navigation

    route!(NavRoot())
    nav = navigation(NavRoot())

    # The root is its own current node and has no ancestors.
    @test nav.current.path == "/"
    @test nav.current.name === :NavRoot
    @test isempty(nav.ancestors)

    # Descendants stop at `depth`, which is what makes the scope configurable
    # rather than "the whole tree, always".
    section = only(filter(child -> child.name === :section, nav.descendants))
    @test section.path == "/section"
    @test isempty(section.children)
    @test :leaf in [c.name for c in only(filter(
        child -> child.name === :section,
        navigation(NavRoot(); depth=2).descendants)).children]

    # Routes are reported per node and are mount-resolved, not root-relative.
    @test any(route -> route.verb === :POST && route.path == "/section/act", section.routes)
    @test any(route -> route.verb === :GET && route.path == "/", nav.current.routes)

    # A framework-supplied bundle is distinguishable from application nodes.
    @test only(filter(c -> c.name === :reflect, nav.descendants)).origin === :framework
    @test section.origin === :declared

    # Labels are derived, docs are not invented.
    @test section.label == "Section"
    @test nav.request.mode === :none
end

@testitem "navigation is threaded through page wrappers only when asked for" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path, headers=Pair{String,String}[]) = begin
        req = HTTP.Request("GET", path, headers, UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    # `__page__(content; navigation=nothing)` receives it.
    route!(NavRoot())
    full = drive("/")
    @test full.status == 200
    @test contains(String(full.body), "NAV:/")
    @test contains(String(full.body), "root")

    # HTMX and markdown requests never apply a page wrapper, so chrome is
    # stripped exactly as before this feature existed.
    @test !contains(String(drive("/", ["HX-Request" => "true"]).body), "NAV:")
    @test !contains(String(drive("/", ["Accept" => "text/markdown"]).body), "NAV:")

    # A wrapper that never declared `navigation` is called with one argument.
    route!(NavPlainRoot())
    plain = drive("/")
    @test plain.status == 200
    @test contains(String(plain.body), "PLAIN-SHELL")
    @test contains(String(plain.body), "plainroot")

    # A slurping wrapper cannot error on an extra keyword, so it is passed.
    route!(NavSlurpRoot())
    slurp = drive("/")
    @test slurp.status == 200
    @test contains(String(slurp.body), "SLURP-GOT-NAV")
end

@testitem "recursively nested page wrappers each receive their own node" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path, headers=Pair{String,String}[]) = begin
        req = HTTP.Request("GET", path, headers, UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    route!(NavChainRoot())

    # Both wrappers in the chain run, innermost first, and neither sees the
    # other's navigation: the outer shell reports the root, the inner reports
    # the child. A single record computed at the leaf would print the same path
    # twice, so the two distinct paths are the real assertion here.
    nested = drive("/child")
    @test nested.status == 200
    body = String(nested.body)
    @test contains(body, "OUTER:/")
    @test contains(body, "INNER:/child")
    @test contains(body, "child-body")
    @test !contains(body, "INNER:/\"") && !contains(body, "OUTER:/child")

    # The root's own request still nests exactly one wrapper.
    root_body = String(drive("/").body)
    @test contains(root_body, "OUTER:/")
    @test contains(root_body, "root-body")
    @test !contains(root_body, "INNER:")

    # A swap that cannot say where it came from still gets a bare fragment, and
    # markdown never carries chrome at all.
    @test !contains(String(drive("/child", ["HX-Request" => "true"]).body), "OUTER:")
    @test !contains(String(drive("/child", ["HX-Request" => "true"]).body), "INNER:")
    @test !contains(String(drive("/child", ["Accept" => "text/markdown"]).body), "OUTER:")
end

@testitem "a partial swap carries the chrome below the swap target" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path, headers=Pair{String,String}[]) = begin
        req = HTTP.Request("GET", path, headers, UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end
    swap(path, from) = String(drive(path, ["HX-Request" => "true",
                                           "HX-Current-URL" => from]).body)

    route!(SwapRoot())

    # A direct visit is unchanged: every level of the chain wraps, innermost
    # first. This is the reference the partial cases are measured against.
    direct = String(drive("/section/view/detail").body)
    @test contains(direct, "ROOT-CHROME") && contains(direct, "SECTION-CHROME") &&
          contains(direct, "VIEW-CHROME:v") && contains(direct, "detail-body")

    # THE FIX. Swapping from the section into one of its views: the root and
    # section shells are on screen already, so re-sending them would duplicate
    # chrome — but the view's own nav is NOT, and sending the bare fragment is
    # what left the user one level in with nothing further to click.
    from_section = swap("/section/view/detail", "http://host/section")
    @test contains(from_section, "VIEW-CHROME:v")
    @test !contains(from_section, "SECTION-CHROME")
    @test !contains(from_section, "ROOT-CHROME")
    @test contains(from_section, "detail-body")

    # Deeper in, the view's chrome is on screen too, so the swap is bare — the
    # endpoint the old behaviour got right, reached by the same rule.
    within_view = swap("/section/view/detail", "http://host/section/view")
    @test !contains(within_view, "CHROME")
    @test contains(within_view, "detail-body")

    # From the root, two levels are new and both are sent.
    from_root = swap("/section/view/detail", "http://host/")
    @test contains(from_root, "SECTION-CHROME") && contains(from_root, "VIEW-CHROME:v")
    @test !contains(from_root, "ROOT-CHROME")

    # Sibling switch under an indexed mount: same level, different mount prefix,
    # so the incoming item's chrome is new. A prefix comparison that stopped at
    # the level rather than the path would wrongly call this already-on-screen.
    sibling = swap("/section/item/b/detail", "http://host/section/item/a")
    @test contains(sibling, "VIEW-CHROME:b")
    @test !contains(sibling, "SECTION-CHROME")
    # …while staying inside one item is bare, and the key it reports is its own.
    @test !contains(swap("/section/item/a/detail", "http://host/section/item/a"), "CHROME")

    # `/section` must not be read as covering `/sectionless` — the comparison is
    # segment-wise, not `startswith`.
    sectionless = swap("/section/view/detail", "http://host/sectionless")
    @test contains(sectionless, "SECTION-CHROME") && !contains(sectionless, "ROOT-CHROME")
    @test !HTMXObjects._path_covers("/section", "/sectionless")
    @test HTMXObjects._path_covers("/section", "/section/view")
    @test HTMXObjects._path_covers("", "/anything")
    # An encoded segment is the same segment, whichever side carries the escape.
    @test HTMXObjects._path_covers("/item/a b", "/item/a%20b/detail")

    # No `HX-Current-URL` (a hand-rolled fetch) — position unknown, so bare.
    @test !contains(String(drive("/section/view/detail",
                                 ["HX-Request" => "true"]).body), "CHROME")

    # The root's own shell is a whole document, so it is never injected into a
    # swap — not even from a location this chain does not cover.
    @test !contains(swap("/section/view/detail", "http://host/elsewhere/deep"),
                    "ROOT-CHROME")

    # The explicit overrides, both directions.
    @test !contains(String(drive("/section/view/detail?__chrome__=none").body), "CHROME")
    forced = swap("/section/view/detail?__chrome__=full", "http://host/section/view")
    @test contains(forced, "ROOT-CHROME") && contains(forced, "SECTION-CHROME") &&
          contains(forced, "VIEW-CHROME:v")

    # A misspelled override is an error, not a silent fallback.
    @test drive("/section/view/detail?__chrome__=partial").status >= 400
end

@testitem "the semantic graph carries containment, dependency and route edges" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    graph = semantic_descriptor(NavRoot).graph

    # Containment: mount edges, with paths from the registrar's own pair.
    @test graph.path == "/"
    section = only(filter(child -> child.name === :section, graph.children))
    leaf = only(filter(child -> child.name === :leaf, section.children))
    @test section.path == "/section"
    @test leaf.path == "/section/leaf"

    # Routes belong to the node that declares them, at their mounted path.
    @test any(route -> route.verb === :GET && route.path == "/section/leaf", leaf.routes)
    @test any(route -> route.verb === :POST && route.path == "/section/act", section.routes)

    # A declared computation dependency — the edge a route table cannot show.
    doubled = only(filter(p -> p.name === :doubled, leaf.properties))
    @test :value in doubled.dependencies

    # Human labels and docs, carried not invented.
    @test leaf.label == "Leaf"
    @test only(filter(p -> p.name === :value, leaf.properties)).description ==
          "The number this leaf reports."

    # Every node has the same shape, root included.
    for node in (graph, section, leaf)
        @test haskey(node, :properties) && haskey(node, :children) &&
              haskey(node, :routes) && haskey(node, :resources) &&
              haskey(node, :selection) && haskey(node, :indexed)
    end

    # The flat transport view is unchanged by any of this.
    reflected = only(filter(route -> route.name === :act, HTMXObjects.reflect(NavRoot)))
    @test keys(reflected) == (:verb, :path, :name, :doc, :params)
end

@testitem "ReflectionRoutes serves a human-readable graph without disturbing /schema" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path, headers=Pair{String,String}[]) = begin
        req = HTTP.Request("GET", path, headers, UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    route!(NavRoot())

    # Human-readable: structure and semantics, not a route dump.
    reflect_response = drive("/reflect")
    @test reflect_response.status == 200
    body = String(reflect_response.body)
    @test contains(body, "Leaf")               # node label
    @test contains(body, "/section/leaf")      # mount-resolved path
    @test contains(body, "doubled")            # a property, not a route
    @test contains(body, "The number this leaf reports.")

    # Same graph as JSON for tooling.
    graph_response = drive("/reflect/graph")
    @test graph_response.status == 200
    @test contains(String(graph_response.body), "\"children\"")

    # /schema keeps serving the flat route index it always did.
    schema_response = drive("/schema")
    @test schema_response.status == 200
    schema_body = String(schema_response.body)
    @test contains(schema_body, "\"verb\"")
    @test contains(schema_body, "\"params\"")
    @test !contains(schema_body, "\"children\"")
end

@testitem "Resource mounts a Base-shaped collection surface" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(verb, path, body="") = begin
        req = HTTP.Request(verb, path, ["Content-Type" => "application/x-www-form-urlencoded"],
                           Vector{UInt8}(body))
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    _reset_note_store!()
    route!(ResourceApp())

    # The collection half registers at the URL the `:index` collapse rule
    # dictates, for both verbs, with no second routing scheme.
    paths = [(route.verb, route.path) for route in HTMXObjects.reflect(ResourceApp)]
    @test (:GET, "/note") in paths
    @test (:POST, "/note") in paths

    @test drive("GET", "/note").status == 200

    # Create goes through the policy's key derivation and lands in the store the
    # mount was handed — asserted on `NOTE_STORE`, not on a root instance: the
    # default root scope rebuilds the root per request, so no root instance is
    # the one the handler ran against.
    @test drive("POST", "/note", "title=B&body=second").status == 200
    @test haskey(NOTE_STORE, "B")
    @test NOTE_STORE["B"].body == "second"
end

@testitem "Resource never forces its collection during construction or registration" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: resource_descriptor

    # `InertCollection` supports none of `keys`/`haskey`/`getindex`. Building the
    # app and registering its routes must not touch it — several real mounts are
    # backed by an unresolved stub, and describing a route surface is not a
    # reason to make one exist.
    _reset_note_store!()
    app = ResourceApp()
    route!(app)
    @test_throws MethodError keys(InertCollection())

    # Reflection probes rather than forces: it reports `nothing` for the facts a
    # non-store cannot answer, instead of throwing or inventing them.
    descriptor = resource_descriptor(app.stub)
    @test descriptor.inspectable === false
    @test descriptor.count === nothing
    @test descriptor.key_type === nothing
    @test descriptor.input === NoteDraft
    # `fields` carries the type alongside the name — a form builder needs both.
    @test (name=:title, type=String) in descriptor.fields

    # The same descriptor over a real store does answer.
    live = resource_descriptor(app.note)
    @test live.inspectable === true
    @test live.count == 1
    @test live.key_type === String

    # The stub-backed mount still registers its collection surface.
    paths = [(route.verb, route.path) for route in HTMXObjects.reflect(ResourceApp)]
    @test (:GET, "/stub") in paths
    @test (:POST, "/stub") in paths
end

@testitem "Resource item routes register for a call-form indexed mount" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    _reset_note_store!()
    route!(ResourceApp())
    paths = [(route.verb, route.path) for route in HTMXObjects.reflect(ResourceApp)]
    for verb in (:GET, :PUT, :PATCH, :DELETE)
        @test (verb, "/note/{key}") in paths
    end

    drive(verb, path, body="") = begin
        req = HTTP.Request(verb, path, ["Content-Type" => "application/x-www-form-urlencoded"],
                           Vector{UInt8}(body))
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    # The item half addresses the same store the collection half writes to.
    @test drive("GET", "/note/a").status == 200
    @test drive("PATCH", "/note/a", "body=edited").status == 200
    @test NOTE_STORE["a"].body == "edited"
    @test NOTE_STORE["a"].title == "A"      # PATCH merges, it does not replace.
    @test drive("DELETE", "/note/a").status == 200
    @test !haskey(NOTE_STORE, "a")
    @test drive("GET", "/note/a").status == 404
end

@testitem "a callable page-wrapper VALUE receives navigation" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path) = begin
        req = HTTP.Request("GET", path, Pair{String,String}[], UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    # `__page__ = MockPage(...)` declares no signature of its own — the value is
    # what takes `navigation`. Reading the empty property signature as a refusal
    # is what previously rendered a literal `nothing` in place of the chrome.
    route!(ValuePageRoot())
    body = String(drive("/").body)
    @test contains(body, "shell|")
    @test contains(body, "value-root")
    # Navigation actually arrived, and carries this node's descendants.
    @test contains(body, "nav=section")
    @test !contains(body, "nav=none")
    @test !contains(body, "nothing")

    # A callable value that does NOT accept the keyword is still called without
    # it, rather than throwing on every full-page response.
    route!(BluntPageRoot())
    blunt = String(drive("/").body)
    @test contains(blunt, "blunt|")
    @test contains(blunt, "blunt-root")
end

@testitem "an indexed @include registers its child's routes" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    # `@include mount(idx) = Child(idx)` is a short-form function definition, so
    # the parser wraps its body in a block. Missing that unwrap made every
    # indexed mount invisible to route registration — silently: the struct
    # compiled, and only the child's routes went missing.
    paths = [(route.verb, route.path) for route in HTMXObjects.reflect(IndexedMountRoot)]
    @test (:GET, "/") in paths
    @test (:GET, "/item/{key}") in paths
    @test (:GET, "/item/{key}/extra") in paths

    route!(IndexedMountRoot())
    req = HTTP.Request("GET", "/item/abc", Pair{String,String}[], UInt8[])
    response = first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    @test response.status == 200
    @test contains(String(response.body), "abc")
end

@testitem "an indexed mount selects the domain candidate, not its label" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    drive(path) = begin
        req = HTTP.Request("GET", path, Pair{String,String}[], UInt8[])
        first(HTTP.Handlers.gethandler(HTMXObjects.CONTEXT[].service.router, req))(req)
    end

    route!(DomainRoot())

    # A declared object domain: the segment matches a candidate's serialized
    # identity, and the CANDIDATE ITSELF reaches the child — `payload` is only
    # reachable from the node, never from the string.
    response = drive("/dataset/synthetic_depot")
    @test response.status == 200
    body = String(response.body)
    @test contains(body, "node=synthetic_depot")
    @test contains(body, "payload=depot")

    @test contains(String(drive("/dataset/real_survey").body), "payload=survey")

    # An inferred enum domain needs no declaration, and the child receives the
    # enum instance rather than a parsed name.
    stage = String(drive("/compilation/review").body)
    @test contains(stage, "stage=review")
    @test contains(stage, "SelStage")

    # A value outside a closed domain is rejected, not parsed into existence.
    @test drive("/dataset/no_such_node").status >= 400
    @test drive("/compilation/no_such_stage").status >= 400

    # A scalar mount with no domain keeps the ordinary parse path.
    @test contains(String(drive("/chains/3").body), "stage=3")
end

@testitem "a typed computed property is not a mount, and its domain is proven" setup=[HTMXOTestFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: semantic_descriptor, semantic_graph_view

    # The guard: `paginate::Bool = false` is a property, not a child to descend
    # into. Registering it as a mount would put `Bool`'s (nonexistent) routes
    # under `/paginate`.
    paths = [route.path for route in HTMXObjects.reflect(BoolPropRoot)]
    @test paths == ["/"]
    @test !any(path -> contains(path, "paginate"), paths)

    graph = semantic_descriptor(BoolPropRoot).graph
    @test isempty(graph.children)

    # It still appears as a PROPERTY, with a domain DynamicObjects proved
    # rather than one anybody declared — a real two-option control, not
    # "unrestricted".
    descriptor = only(filter(p -> p.name === :paginate, graph.properties))
    domain = get(descriptor, :domain, nothing)
    @test !isnothing(domain)
    @test domain.kind === :static
    # Options are RECORDS, not bare values: each carries the value plus the
    # label a control renders. Both halves matter — the value is what selects,
    # the label is what a human reads.
    @test Set(option.value for option in domain.options) == Set([false, true])
    @test Set(option.label for option in domain.options) == Set(["false", "true"])

    rendered = repr("text/html", semantic_graph_view(BoolPropRoot))
    @test contains(rendered, "paginate")
    @test contains(rendered, "static")
end

# ── Automatic progress over the generic operation path ───────────────────────
# An ordinary `@get` route whose body reads a slow nested DynamicObjects indexed
# property. There is no `@progress`, no `@fetch!`, no `polling_fetchindex`, no
# `route!(…; operation_policy=…)` and no JavaScript anywhere in these fixtures:
# `:auto` is the default transport, and source-visible property reads/calls in
# generated bodies carry the caller's progress node explicitly. Ordinary Julia
# calls remain ordinary; there is no ambient or task-local progress context.
@testmodule HTMXOPropertyScopedFixtures begin
using HTMXObjects

export PropertyScopedRoute, PropertyScopedFastRoute, PropertyScopedFailRoute,
    property_gate, progress_descendants

# The leaf blocks on this until the test releases it, so "the request came back
# with the work still in flight" is asserted deterministically rather than by
# racing a `sleep` against JIT compilation. Only the gated item touches it —
# the other items use routes that never wait, so items stay independent even
# when TestItemRunner runs them in one process.
const property_gate = Ref(Base.Event())

@htmx struct PropertyScopedDeep
    "Deep leaf work"
    deep(k) = (wait(property_gate[]); 10k)
end

@htmx struct PropertyScopedMiddle
    @include deep_child = PropertyScopedDeep()
    "Middle work"
    middle(k) = deep_child.deep(k) + 1
end

@htmx struct PropertyScopedRoute
    @include mid = PropertyScopedMiddle()
    "Slow page"
    @get slow(k::Int) = h.p(string(mid.middle(k)))
end

# Same shape, no gate: used where the test needs the work to finish.
@htmx struct PropertyScopedFastDeep
    "Deep leaf work"
    deep(k) = 10k
end

@htmx struct PropertyScopedFastMiddle
    @include deep_child = PropertyScopedFastDeep()
    "Middle work"
    middle(k) = deep_child.deep(k) + 1
end

@htmx struct PropertyScopedFastRoute
    @include mid = PropertyScopedFastMiddle()
    "Slow page"
    @get slow(k::Int) = h.p(string(mid.middle(k)))
end

@htmx struct PropertyScopedFailRoute
    "Failing leaf"
    boom(k) = error("nested boom $k")
    "Failing page"
    @get bad(k::Int) = h.p(string(boom(k)))
end

function progress_descendants(node, acc=String[])
    for child in node.children
        push!(acc, child.impl.description)
        progress_descendants(child, acc)
    end
    acc
end
end # @testmodule HTMXOPropertyScopedFixtures

@testmodule HTMXOPollIdentityFixtures begin
using HTMXObjects

export PollIdentityRoute, reset_poll_identity!, poll_identity_count,
    release_poll_identity!

const poll_identity_lock = ReentrantLock()
const poll_identity_gates = Base.Event[]

function reset_poll_identity!()
    lock(poll_identity_lock)
    try
        empty!(poll_identity_gates)
    finally
        unlock(poll_identity_lock)
    end
end

poll_identity_count() = lock(poll_identity_lock) do
    length(poll_identity_gates)
end

function release_poll_identity!(index)
    gate = lock(poll_identity_lock) do
        poll_identity_gates[index]
    end
    notify(gate)
end

function poll_identity_work(id)
    gate, sequence = lock(poll_identity_lock) do
        gate = Base.Event()
        push!(poll_identity_gates, gate)
        gate, length(poll_identity_gates)
    end
    wait(gate)
    h.p("poll:$id:$sequence")
end

@htmx struct PollIdentityRoute
    @get poll_identity(id::Int) = poll_identity_work(id)
end
end # @testmodule HTMXOPollIdentityFixtures

@testitem "polling operation identity survives fresh roots and stays bounded" setup=[HTMXOPollIdentityFixtures, HTMXOTestImports] tags=[:integration, :semantic] begin
    import HTMXObjects: _OperationPollEntry, _OPERATION_POLL_LIMIT,
        _OPERATION_POLL_TTL, _clear_operation_polls!,
        _new_operation_poll_token, _operation_poll_now, _operation_poll_snapshot,
        _retain_operation_poll!

    function drive(target; session="session-a")
        request = HTTP.Request("GET", target,
            ["HX-Request" => "true", "X-Session" => session], UInt8[])
        handler = first(HTTP.Handlers.gethandler(
            HTMXObjects.CONTEXT[].service.router, request))
        @test handler !== HTTP.Handlers.default404
        response = handler(request)
        @test response.status == 200
        String(response.body)
    end

    running(body) = contains(body, "hx-trigger=\"every ")
    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""),
                      body)
        @test !isnothing(found)
        replace(only(found.captures), "&amp;" => "&")
    end
    function poll_token(target)
        found = match(r"__htmxo_operation=([^&]+)", target)
        @test !isnothing(found)
        only(found.captures)
    end
    function settle(target; session="session-a")
        body = drive(target; session)
        for _ in 1:100
            running(body) || return body
            sleep(0.05)
            body = drive(target; session)
        end
        body
    end

    _clear_operation_polls!()
    reset_poll_identity!()
    try
        # A session key is part of the retained operation's identity, while the
        # opaque token keeps two same-route, same-argument runs independent.
        provider = RootProvider(
            scope=:session,
            key=req -> HTTP.header(req, "X-Session", ""),
        )
        route!(PollIdentityRoute(); root_provider=provider)

        first_body = drive("/poll_identity/7")
        second_body = drive("/poll_identity/7")
        @test running(first_body)
        @test running(second_body)
        first_url = poll_url(first_body)
        second_url = poll_url(second_body)
        @test first_url != second_url
        first_token = poll_token(first_url)
        second_token = poll_token(second_url)
        @test occursin(r"^[0-9a-f]{64}$", first_token)
        @test occursin(r"^[0-9a-f]{64}$", second_token)

        # Each bearer capability comes directly from OS randomness. A
        # process-wide nonce plus a visible counter would share this prefix and
        # let the first client enumerate every later operation.
        sample = [_new_operation_poll_token() for _ in 1:32]
        @test length(unique(sample)) == length(sample)
        @test all(token -> occursin(r"^[0-9a-f]{64}$", token), sample)
        @test length(unique(first(token, 32) for token in sample)) ==
              length(sample)
        @test timedwait(() -> poll_identity_count() == 2, 10.0;
                        pollint=0.01) === :ok
        @test length(_operation_poll_snapshot()) == 2

        # A token is a capability, not the identity by itself. Route arguments
        # and provider scope/key are checked before the retained IP is exposed.
        wrong_arg = replace(first_url, "/poll_identity/7?" => "/poll_identity/8?")
        @test contains(drive(wrong_arg), "aria-invalid=\"true\"")
        @test contains(drive(first_url; session="session-b"),
                       "aria-invalid=\"true\"")
        @test length(_operation_poll_snapshot()) == 2

        release_poll_identity!(1)
        first_done = settle(first_url)
        @test !running(first_done)
        @test contains(first_done, "poll:7:1")
        @test length(_operation_poll_snapshot()) == 1
        @test running(drive(second_url))

        release_poll_identity!(2)
        second_done = settle(second_url)
        @test !running(second_done)
        @test contains(second_done, "poll:7:2")
        @test isempty(_operation_poll_snapshot())

        # An abandoned operation expires even if its producer is still alive.
        reset_poll_identity!()
        abandoned = drive("/poll_identity/9")
        abandoned_url = poll_url(abandoned)
        @test timedwait(() -> poll_identity_count() == 1, 10.0;
                        pollint=0.01) === :ok
        future = _operation_poll_now() + _OPERATION_POLL_TTL + 1
        @test isempty(_operation_poll_snapshot(; now=future))
        expired = drive(abandoned_url)
        @test !running(expired)
        @test contains(expired, "aria-invalid=\"true\"")
        release_poll_identity!(1)

        # Capacity is an LRU bound, independent of TTL cleanup.
        _clear_operation_polls!()
        now = _operation_poll_now()
        request = HTTP.Request("GET", "/capacity")
        for index in 1:(_OPERATION_POLL_LIMIT + 1)
            token = "capacity-$index"
            touched = now + index / 1000
            entry = _OperationPollEntry(
                token, (; index), nothing, (), (;), nothing, nothing,
                request, touched, touched)
            _retain_operation_poll!(entry; now=touched)
        end
        retained = _operation_poll_snapshot()
        @test length(retained) == _OPERATION_POLL_LIMIT
        @test !haskey(retained, "capacity-1")
        @test haskey(retained, "capacity-$(_OPERATION_POLL_LIMIT + 1)")
    finally
        for index in 1:poll_identity_count()
            try
                release_poll_identity!(index)
            catch
            end
        end
        _clear_operation_polls!()
    end
end

@testitem "automatic progress — property-scoped route calls poll and nest without annotations" setup=[HTMXOPropertyScopedFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _run_operation, _operation_polling_impl, Verb
    import HTMXObjects.DynamicObjects
    const TBNode = DynamicObjects.Treebars.ProgressNode

    app = PropertyScopedRoute()
    target = (context=nothing, root=app, leaf=app)
    hx = HTTP.Request("GET", "/slow/2", ["HX-Request" => "true"])

    property_gate[] = Base.Event()         # closed: the leaf cannot finish yet
    seen = Ref{Any}(nothing)
    old = _operation_polling_impl[]
    _operation_polling_impl[] =
        (render_result, started, ip, keys, call_kwargs, transport) -> begin
            seen[] = (; started, keys, transport)
            h.aside("polling")
        end
    node = try
        # No `operation_policy=` kwarg anywhere — this is the DEFAULT path.
        operation = _run_operation(target, PropertyScopedRoute, :slow, Verb{:GET}(),
                                   hx, 1, 1)
        @test repr("text/html", operation.value) == "<aside>polling</aside>"
        # The request returned while the leaf is still parked on the gate, so an
        # in-flight handle — not a finished value — reached the polling seam.
        # A fully blocking start would satisfy "the poller was reached" too,
        # which is exactly the trap this assertion exists to close.
        @test seen[].started isa DynamicObjects.Pending
        @test startswith(seen[].transport.poll_url,
                         "/slow/2?__htmxo_poll=1&__htmxo_operation=")
        DynamicObjects.getstatus(app.slow, seen[].keys...)
    finally
        _operation_polling_impl[] = old
    end

    # The tree fills itself in WHILE the work runs — three levels, discovered
    # from execution nesting alone.
    @test node isa TBNode
    @test node.impl.description == "Slow page"
    @test timedwait(10.0; pollint=0.05) do
        "Deep leaf work" in progress_descendants(node)
    end === :ok
    descendants = progress_descendants(node)
    @test "Middle work" in descendants
    @test "Deep leaf work" in descendants

    # And the final value still arrives once the leaf is released.
    notify(property_gate[])
    @test repr("text/html", app.slow(Verb{:GET}(), 2)) == "<p>21</p>"
end

@testitem "automatic progress — property-scoped direct requests and failures stay visible" setup=[HTMXOPropertyScopedFixtures, HTMXOTestImports] tags=[:unit, :semantic] begin
    import HTMXObjects: _run_operation, Verb
    import HTMXObjects.DynamicObjects
    const TBNode = DynamicObjects.Treebars.ProgressNode

    # `:auto` is the default, but it stays conditional: a non-HTMX request (a
    # browser hard load, `?plain`, curl, an API client) still gets the finished
    # value in one response rather than a poller.
    @test OperationPolicy().mode === :auto

    app = PropertyScopedFastRoute()
    target = (context=nothing, root=app, leaf=app)
    direct = _run_operation(target, PropertyScopedFastRoute, :slow, Verb{:GET}(),
                            HTTP.Request("GET", "/slow/3"), 1, 1)
    @test repr("text/html", direct.value) == "<p>31</p>"
    @test !(direct.value isa DynamicObjects.Pending)

    # A nested failure surfaces as a pinned node, so the tree still shows WHICH
    # step failed rather than collapsing to a bare error.
    bad_app = PropertyScopedFailRoute()
    @test_throws DynamicObjects.PropertyComputationError bad_app.bad(Verb{:GET}(), 1)
    bad_node = DynamicObjects.getstatus(bad_app.bad, Verb{:GET}(), 1)
    @test bad_node isa TBNode
    @test "Failing leaf" in progress_descendants(bad_node)
end
