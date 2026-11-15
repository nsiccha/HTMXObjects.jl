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

## Results computed in the browser

A `presentation=:tabs` page asks the server again for a result when an input it
reads changes. A property can instead have a browser twin: an ES module that
computes the same value from the inputs, such as the one
`ReactiveKernels.js_source` emits from the kernel the property calls. A result
that shows that property only through `bound(...)` is then computed and redrawn
in the browser, with no request, so the page keeps following its inputs as a
static export (`export_site`) and offline:

```@example forms
const LINE_JS = """
export function line(grid, a, b) {
  return { y: grid.map(x => a * x + b), total: a + b };
}
export const INPUTS = [{ name: "grid", type: "Vector{Float64}" },
  { name: "a", type: "Float64" }, { name: "b", type: "Float64" }];
"""
@htmx struct Line
    "Slope"
    @param a::Float64 = 2.0
    "Intercept"
    @param b::Float64 = 1.0
    grid = [0.0, 1.0, 2.0]
    fit = (; y = a .* grid .+ b, total = a + b)
    @browser(fit) = browser_module(; source = LINE_JS, entry = :line)
    "Line"
    @get result() = h.p("total ", bound(fit.total), " at slope ", bound(a))
    @get index() = semantic_app(__self__; presentation=:tabs,
        select=entry -> entry.name !== :index)
end
route!(Line(); prefix="/line", operation_policy=:blocking);
response = dispatch(:GET, "/line/result?a=3"; headers=["HX-Request" => "true"]);
@assert response.status == 200 # hide
println(String(response.body))
```

- **The module** is read from a file with `browser_module(path, entry)` or
  given as text with `browser_module(; source, entry)`. It exports the function
  `entry`, which takes positional arguments, and `INPUTS`, naming them and their
  Julia types in order. The page passes each by name: a `@param` from its
  control (numbers, `Bool`, text and vectors of them), any other from the
  property of that name, which must not read an input (`grid` above); its value
  goes into the page. A named tuple comes back as an object of named outputs.
- **`bound`** marks where a view shows a browser value: the property, one of its
  outputs (`bound(fit.total)`), an element of one (`bound(fit.y[2])`, the index
  an integer literal) or a `@param` (`bound(a)`), rounded with `digits=`. The server shows
  the value as Julia's `string` writes it, and so does the browser after each
  change. `bound(fit; columns=(:x, :y))` is the outputs' table for a plot's
  `data(...)`; give the element that draws it `bound_columns_attrs(...)`, and
  the browser hands it the new rows through AlgebraOfVega's `AoV.updateData`
  and an `htmxo:bound-columns` event.
- **Finite inputs** (a `Bool`, an enum, `@options`) that a result reads are
  views of their own: the page carries the result rendered for each value (at
  most 64) and shows the one the inputs select.
- **An error** the module throws is shown in the result under its name
  (`DomainError: …`), which keeps its last answer faded until the next one.
- **The page address**: a page applies the inputs its address names to its
  controls when it loads, so a static page's shared link reopens them.
- **`@relevant`** conditions with arithmetic of inputs (`a * b > 10`) are
  evaluated in the browser, like comparisons with literals.

`export_site` refuses a page with a browser result that would show something
stale, naming each part: a view that shows an input outside `bound` (the export
renders it with each continuous input changed and compares everything else), a
result that reads inputs but computes nothing in the browser, and a control the
server draws again (`@options`, `@help`, a computed default or a condition the
browser cannot evaluate). Bind it, compute it in the module, or leave that
operation out of the page with `semantic_app(…; select=…)`.

## Multiple choices

A vector input with `@options` uses checkbox pills for at most `radio_max`
options (8 by default). Larger domains use a searchable checkbox popover.
The closed field shows the count and every selected label; labels wrap.
Click or press Enter to toggle an option while keeping the popover open.
Search filters the visible choices without changing the selection.

For a hand-placed control, use `choice_list((; quantities), options;
multiple=true)`, where `quantities` is a vector. Option records can supply
`label`, `help`, `group` and `disabled`; disabled options cannot be submitted.
Pass `required=true` to require at least one selection. The `htmx` shell
supplies the styles and runtime, including native keyboard operation.

Selections submit repeated names, such as `quantities=auc&quantities=maximum`.
Clearing the group submits `quantities=`: an explicit empty vector, preserved
on refresh and reload. Omitting `quantities` still uses its declared default.
The same blank-versus-omitted distinction applies to typed vector query/form
inputs; scalar blanks retain their default behavior. Markdown reads show all
selected labels. Records vector fields and `set_inputs` use the same selection
semantics.

## Numbers from a range

From 0.1.119, a number input declares the numbers it takes, and how a reader
picks one, in its `@options`:

```@example forms
@htmx struct Shielding
    "Attenuation per mm of snow water"
    @param attenuation::Float64 = 0.004
    @options(attenuation) = number_domain(0.001, 0.015; log=true, digits=4)
    "Snow density"
    @param density::Float64 = 300.0
    @options(density) = number_domain(50, 600; step=10, unit="kg/m³")
    @get curve() = h.p(attenuation, " per mm at ", density, " kg/m³")
    @get index() = semantic_app(__self__; presentation=:tabs,
        select=entry -> entry.name !== :index)
end
route!(Shielding(); prefix="/shielding", operation_policy=:blocking);
refused = dispatch(:GET, "/shielding/curve?attenuation=0.5");
@assert refused.status == 400 # hide
println(refused.status)
println(number_record(number_domain(0.001, 0.015; log=true, digits=4)))
```

The generated form draws each as a slider with a number field beside it,
followed by the unit. A `log` domain spaces the slider evenly in ratio, for a
positive quantity spanning orders of magnitude. A slider value lies on the
`step` grid counted from the lower bound; without a step it keeps `digits`
decimal places, or three significant digits. Typing in the field moves the
slider. Results and the page address follow the field once the slider is
released. Without JavaScript, the field alone still submits.

A number outside the interval answers 400 at its field, for `@param`s,
operation arguments and JSON bodies alike, as a value outside a finite
`@options` list does. A bare interval, `@options(share) = 0 .. 1` (any
IntervalSets interval of numbers, open ends included), is the same domain with
no other settings. An interval with an infinite end gets a field without a
slider. Ranges are never listed as choices.

`number_record(domain)` returns the domain as plain data. Each generated
control also carries it as JSON in its label's `data-htmxo-number`, so a page
script computing in the browser reads the bounds, scale, step, decimal places
and unit from the page, and follows the value through the field's `input`
events. Place the same control by hand with
`ninput((; attenuation); domain=number_domain(…))`.

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
