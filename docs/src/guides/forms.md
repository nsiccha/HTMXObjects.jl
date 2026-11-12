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
