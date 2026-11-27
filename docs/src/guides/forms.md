# Forms

Bind typed query, form, and JSON values to a route, and give a form an explicit endpoint
and result target.

## Parameters

```@example forms
using HTMXObjects
@enum Stage queued active complete

@htmx struct StageRoutes
    @get choose(; stage::Stage=queued) = string(stage)
    @post choose(; stage::Stage=queued) = string(stage)
end
route!(StageRoutes(); prefix="/stages", operation_policy=:blocking);

get_response = dispatch(:GET, "/stages/choose?stage=active");
post_response = dispatch(:POST, "/stages/choose";
    headers=["Content-Type" => "application/x-www-form-urlencoded"],
    body="stage=complete");
results = (get=String(get_response.body), post=String(post_response.body))
@assert results == (get="active", post="complete") # hide
foreach(println, pairs(results))
```

GET keywords come from the query string; POST keywords can come from the form
body. Enum parameters use their named wire values. A string such as `active`
selects that enum instance; its integer storage code is not the form value.

A positional argument belongs to the route path. A keyword argument belongs to
the request parameters, and a default makes it optional. Use a type annotation
when the route needs a parsed value rather than a string. Declare `@param`
inside an object when several of its routes share the same request parameter.

## JSON requests

POST, PUT, and PATCH keywords and `@param` also bind fields from an
`application/json` object automatically. The same declaration accepts a form
submission or JSON; send the corresponding `Content-Type`.

```@example forms
@htmx struct JsonInputs
    @post item(; name::String, value::Float64) = "$name: $value"
end
route!(JsonInputs(); prefix="/json-inputs", operation_policy=:blocking);
response = dispatch(:POST, "/json-inputs/item";
    headers=["Content-Type" => "application/json"],
    body="""{"name":"demo","value":3.0}""");
@assert response.status == 200 # hide
result = String(response.body)
@assert result == "demo: 3.0" # hide
println(result)
```

JSON fields retain their native values. Typed fields use JSON.jl's conversion,
including arrays, dictionaries, and records; send numbers as JSON numbers.
Missing fields fall back to the query string, then to the declared default, or
answer 400 when required. Explicit `null`, `""`, and `[]` are supplied values:
they override query fallback and defaults. To accept null, declare a nullable
type such as `Union{Nothing,Float64}` (or leave the field untyped).

Malformed JSON, a non-object body, and values the declared type rejects answer
400. A route without bound inputs can still read its raw body itself. Keyword
splats retain native JSON values, and `__undeclared_params__` checks JSON field
names too. OpenAPI advertises both JSON and form request bodies.

## Controls

```@example forms
material = "plasma";
field = linput((; material); label="Material");
form = get_form("/samples/", field;
    label="Filter", hx_target="#results", hx_swap="innerHTML");
markup = repr(MIME"text/html"(), form);
checks = (
    named_input=occursin("name=\"material\"", markup),
    endpoint=occursin("hx-get=\"/samples/\"", markup),
    target=occursin("hx-target=\"#results\"", markup),
)
@assert all(checks) # hide
foreach(println, pairs(checks))
```

`linput` supplies the label, input name and value. It does not infer an HTTP
endpoint from that name. Here `get_form` owns the request and targets an element
whose ID is `results`; the containing page must provide that element and the
HTMX runtime, for example through its `htmx` page shell.

Pass visible controls as positional children of `get_form` or `post_form`.
They appear before the submit button. Extra non-attribute keyword arguments
become hidden inputs; attributes such as `hx_target` configure the form.
Use `obj=__self__` to forward an object's set `@param` values, with `skip` for
parameters already supplied by visible controls.

## Refreshing a tab

Committing a valid edit (for example, on blur) refreshes the visible tab on the
next browser turn once dependent controls settle. Results ready within the
default 100 ms return inline. Otherwise, progress appears beside the previous
result and replaces it after `progress_after` seconds (default 3). With
Treebars 0.1.5 or later, ordinary HTML arrives on the page stream.
The browser fetches responses carrying htmx headers or recorded errors over HTTP.

## Opening a result after a mutation

Return [`open_tab`](@ref) from an upload to select its new fit and open Time course.

```@example forms
name = "new-fit"
answer = hx_response(open_tab("timecourse"; fit=name); toast="Added the fit")
println(String(to_response(answer).body))
```

The tab waits for the refreshed choice, then shows its progress. Other inputs
keep their values. Omit `fit` to open the tab with the current selection.

## Several apps on one page

A generated tabbed app places its tab bar above its shared-input sidebar
and selected result. The bar uses the width of that app, including when
embedded in an article. Labels wrap onto another row when the space runs out.

A `presentation=:tabs` page keeps the inputs the reader set and its open tab in
the page address (`?rate=5&tab=other`), so a reload or a shared link reopens
it. A page can show several such apps, each a mounted object:

```@example forms
@htmx struct Melt
    @param rate::Int = 3
    @get snow() = h.p("Snow: ", rate)
    @get other() = h.p("Other: ", rate)
end
@htmx struct Rain
    @param rate::Int = 7
    @get result() = h.p("Rain: ", rate)
end
@htmx struct Article
    @include melt = Melt()
    @include rain = Rain()
    @get index() = h.main(
        h.section(semantic_app(melt; presentation=:tabs)),
        h.section(semantic_app(rain; presentation=:tabs)))
end
route!(Article(); operation_policy=:blocking);
response = dispatch(:GET, "/?melt.rate=5&rain.rate=9&melt.tab=snow";
    headers=["HX-Request" => "true"]);
page = String(response.body);
input_values = [m.captures[1] for m in
    eachmatch(r"<input[^>]* name=\"rate\"[^>]* value=\"([^\"]*)\"", page)];
checks = (
    success=response.status == 200,
    independent_values=input_values == ["5", "9"],
)
@assert all(checks) # hide
foreach(println, pairs(checks))
```

From 0.1.150 each app keeps its inputs and its open tab under its address name,
its mount path with dots, so inputs of one name in two apps stay apart:
`?melt.rate=5&rain.rate=9&melt.tab=snow`. A page that shows one app, the app's
own page `/melt/` included, keeps the plain names. The root object's own app has
no name and keeps plain names beside the others. A list of records keeps its
fields below the app's name (`melt.scenarios.1.label`).

An app reads its own name first, else the plain name. A link written with plain
names, such as one shared before the page gained its second app, opens as it
did, with every app taking the plain value, and the next change writes each app
under its own name. Nothing needs configuring: the browser chooses the names,
since it sees the whole page, and the server reads the same names when it
renders the page. A custom `layout(parts)` that draws its own `tabset` passes
`url_scope=parts.url_scope` to keep its tab the same way.

## Preset record cards

Use `presets` to set the starting cards and `label_from` to name them.
See [Preset record cards](@ref generated-preset-cards) for an example.

### Showing valid cards when another card has an error

Declare a shared `check` on the list. Plot the values from `checked_records`
and use `record_faults` to name omissions. The [checked cards example](@ref generated-checked-cards)
shows a successful value and the error from another card in the same response.

## Resetting every input

From 0.1.127, a `presentation=:tabs` page has a Reset button. It returns every
input, in the sidebar and in each tab, to what the page shows when its address
names nothing: its `values=` entry or its declared default. An input with a
computed default, or one with `@resets` (next section), follows its default
again, and a list of records goes back to its presets or its single default card. The open tab
stays.

```@example forms
@htmx struct Probe
    "Attenuation"
    @param attenuation::Float64 = 0.004
    @options(attenuation) = number_domain(0.001, 0.015; log=true, digits=4)
    "Density"
    @param density::Float64 = 300.0
    @get reading() = h.p(attenuation, " at ", density)
    @get index() = semantic_app(__self__; presentation=:tabs,
        select=entry -> entry.name !== :index)
end
route!(Probe(); prefix="/probe", operation_policy=:blocking);
page = String(dispatch(:GET, "/probe"; headers=["HX-Request" => "true"]).body);
reset = match(r"<button[^>]*data-htmxo-reset[^>]*>[^<]*</button>", page);
@assert reset !== nothing # hide
println(reset.match)
```

The browser sets the controls, and the results, bound values, sliders and page
address follow as after the reader's own change. A page from `export_site`
therefore resets offline, with no request. Only a default computed from other
inputs is drawn by the server, as when one of those inputs changes.

The button ends the sidebar; a page without one draws it under each tab's
inputs, as here. A custom `layout(parts)` places `parts.reset`, a custom
`render_operation(entry)` places `entry.reset` (`nothing` where the default
draws none), and `semantic_app(…; reset=false)` draws none. Its label is the
`reset_inputs` text of `__error_texts__`. Files and fixed fields shown as
inputs keep their values, as the page address does not keep them either.

## Resetting dependent inputs

From 0.1.109, a generated form can discard an edited input when one of its
named source inputs changes:

```@example forms
@htmx struct Comparison
    @param measure::String = "distance"
    @options(measure) = ["distance", "duration"]
    @param threshold::Float64 = measure == "distance" ? 10.0 : 30.0
    @resets(threshold) = measure
    @get result() = h.p(measure, ": ", threshold)
    @get index() = semantic_app(__self__; presentation=:tabs,
        select=entry -> entry.name !== :index)
end
route!(Comparison(); prefix="/comparison", operation_policy=:blocking);
response = dispatch(:GET, "/comparison/result?measure=duration";
    headers=["HX-Request" => "true"]);
@assert response.status == 200 # hide
println(String(response.body))
```

After the reader sets a threshold, changing `measure` restores the new
measure's default. The input follows that default again until the next reader
edit. The refreshed control, result and page address agree; reloading the
address reproduces that state. An input without `@resets` keeps an edited
value when other inputs change.

Use a tuple for several sources: `@resets(threshold) = (measure, reference)`.
The right side names `@param` inputs, not a computed expression, and the reset
input must have a default. Repeated events with the same source value and
changes to unrelated inputs leave the edit intact. The declaration applies to
`semantic_app` and `operation_form`, including controls placed with `place=`.

Explicit values in an opened URL remain intentional. A direct request also
honors its explicit parameters: resetting is a transition in the generated
form, which knows the previous source value.

## Multiple choices

See [Multiple choices](@ref generated-multiple-choices) for generated checkbox
pills, searchable lists and vector submission.

## On/off settings

See [On/off settings](@ref generated-bool-controls) for generated Boolean
switches, checkboxes and the `@control` override.

## Numbers from a range

See [Numbers from a range](@ref generated-number-controls) for sliders,
number fields and `number_domain` declarations.

## Options loaded from an address

A list with thousands of options, or one that several forms on a page share,
need not travel with every page. Give `choice_list` the address of a route that
answers with `choice_options` instead of the options themselves:

```@example forms
@htmx struct Policies
    @param agent::String = "Claude:ux"
    @get agent_options() = choice_options(["Claude", "Claude:ux", "HTMXObjects"])
    @get policy() = post_form("/policy",
        choice_list((; agent), route_url(__self__, :agent_options); label="Agent"))
end
route!(Policies(); prefix="/policies", operation_policy=:blocking);
fragment(path) = String(dispatch(:GET, path; headers=["HX-Request" => "true"]).body);
form, answer = fragment("/policies/policy"), fragment("/policies/agent_options");
rows(markup) = count("class=\"htmxo-choice-option\"", markup);
checks = (
    loads_from_route=occursin("hx-get=\"/policies/agent_options\"", form),
    page_holds_chosen_only=rows(form) == 1,
    answer_holds_every_option=rows(answer) == 3,
)
@assert all(checks) # hide
foreach(println, pairs(checks))
```

The page carries only the chosen option, drawn as a row of the list, so the
field shows its label, submits, validates and reads in Markdown before any
request. Pass `value=agent => label` (or a record) when the label is not the
value itself. The list asks the address the first time the reader points at or
focuses it, at the latest when it opens. Every list on the page naming the same
address shares one request and one parsed answer, and each copies the rows in
when it first opens. From then on it is the inline list: the same search,
keyboard and filled chosen row, single or `multiple=true`. A `required` list
with nothing chosen still refuses an empty submit and opens. If the address
fails, the list says so where its options would be and asks again the next
time it opens.

The request is an ordinary htmx GET that inherits no values, so a static export
maps the address as it maps any fragment, and `export_site` writes its answer.
It swaps nothing, so a slow options route answers it with the finished options
under the default `:auto` policy too, never with a progress poller; the route
needs no `@direct`.

## URLs

```@example forms
println(query_url("/samples/"; material="whole blood", location="Freezer A"))
```

`query_url` encodes values for a query string. Keep HTML escaping, URL encoding
and typed parameter conversion as separate operations; manually concatenating a
user value into a URL conflates them.

The [sample browser](../examples/sample-browser.md) provides the `/samples/`
endpoint used by this form and verifies its filtering independently of the
browser controls.
