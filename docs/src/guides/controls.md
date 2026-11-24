# Generated controls

Declare the values an input accepts; generated forms choose the corresponding
control. See [Forms](forms.md) for request binding, shared inputs and resets.

## Single choices in saved links

Suppose a link opens `/?fit=archived` after that fit was removed. A
`semantic_app(…; presentation=:tabs)` page selects the enabled declared default
and names both the requested fit and the one its results use. If no enabled
default exists, the notice says that no option is selected. Choosing another
fit clears the notice and updates the link. The same notice works in a static
snapshot. A direct request to an operation still validates its inputs.

## [Multiple choices](@id generated-multiple-choices)

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

## [On/off settings](@id generated-bool-controls)

A `Bool` input is drawn by the form it is in. Where a change applies at once,
with no button to send it, it is a switch: the sidebar of a
`semantic_app(…; presentation=:tabs)` page, the shared inputs `place=` puts in
its tabs, and a following tab's own inputs. In a form a button sends (an
operation card, `operation_form`, a `:tabs` mutation) it is a checkbox, which
does not promise an effect before the button is pressed. Both are the same
`<input type="checkbox" value="true">`; the switch adds `role="switch"`, which
Pico draws as a switch, and the `htmx` shell fills its "on" track in the text
colour. Submission, Reset, the page address and `?plain` read them alike.

To choose the control for one input in every generated form, declare it next
to the `@param`:

```@example controls
using HTMXObjects

@htmx struct Picture
    "Show the ploughed-soil difference"
    @param ploughed::Bool = true
    @param confirm::Bool = false
    @control(confirm) = :checkbox
    @get result() = h.p(ploughed, ": ", confirm)
    @get summary() = h.p("Settings: ", ploughed, ", ", confirm)
end
route!(Picture(); prefix="/picture", operation_policy=:blocking);
page = repr(MIME"text/html"(), semantic_app(Picture(); presentation=:tabs));
checks = (
    switch=occursin(r"<input(?=[^>]*name=\"ploughed\")(?=[^>]*role=\"switch\")", page),
    checkbox=occursin(r"<input(?=[^>]*name=\"confirm\")(?![^>]*role=\"switch\")", page),
)
@assert all(checks) # hide
foreach(println, pairs(checks))
```

`@control` takes `:switch` or `:checkbox` and names a `Bool` `@param` of the
struct; on any other input the page throws an `ArgumentError` naming it. A
hand-placed control is `cinput((; ploughed); switch=true)`.

## [Numbers from a range](@id generated-number-controls)

From 0.1.119, a number input declares the numbers it takes, and how a reader
picks one, in its `@options`:

```@example controls
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

In a semantic app's sidebar, each slider fills a row above its number field
and unit. Other generated forms keep them together when they fit, wrapping
the slider onto its own row in narrower columns. A long unit wraps below
the field. [`app_layout`](@ref)'s `--htmxo-sidebar-width` includes the right
padding and divider: `calc(20rem + 1px)` leaves `19rem` for controls (304 px
at the default 16 px root font).

A `log` domain spaces the slider evenly in ratio, for a
positive quantity spanning orders of magnitude. A slider value, like the
field's arrow keys, lies on the `step` grid counted from the lower bound;
without a step it keeps three significant digits. A typed number need only
lie in the interval, and moves the slider.

`digits` sets how many decimals the field shows while not being edited, as
`format_number(x; digits)` writes them: a fitted 0.003035586062774531 shows as
`0.0030`. The value itself stays exact for the form, browser results, the page
address and Reset; editing shows it in full.

A result computed in the browser (`@browser`) follows the field while
the slider moves, redrawn once an animation frame at most; a result asked of
the server and the page address follow it once the slider is released.
Without JavaScript, the field alone still submits.

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

## [Preset record cards](@id generated-preset-cards)

From 0.1.178, `presets` gives a `Records` input its starting cards in order.
Each preset supplies the fields it changes. Here the first card takes the
declared regimen, and the second starts switched off.

```@example controls
@htmx struct Comparison
    @param regimen::String = "100% q 24 x 14"
    @param scenarios::Records = Records(:regimen; label="Scenario", label_from=:regimen,
        presets=[(label="Daily 100 %",), (label="BID 50 %", regimen="50% q 12 x 14", on=false)])
    @get selected() = h.ul((h.li(s.label, " — ", s.regimen) for s in scenarios)...)
end
[s.label => s.regimen for s in Comparison().scenarios]
```

Add and Duplicate take their automatic name from `label_from`, using the
display label for a choice. Repeated names get a numbered suffix. A name the
reader types takes precedence, and clearing it restores automatic naming.
Omit `label_from` to keep numbered names and copy labels.

The Include box shows each enabled card's colour in order. A plot using the
page's default categorical palette and the same category order matches those
colours, including in dark mode or with a page-wide `--aov-category` palette.

### [Showing valid cards when another card has an error](@id generated-checked-cards)

Give the list a `check` property when its views share a check. The property
runs once per enabled card when the list is resolved. Here the summary uses its result
and names the cards it omitted.

```@example controls
@htmx struct Samples
    @param code::String = "A"
    @param samples::Records = Records(:code; label="Sample", check=:identifier)
    identifier = isempty(strip(code)) ?
        throw(CallerFault(400, "Enter a sample code"; param=:code)) : uppercase(strip(code))
    @get summary() = begin
        cards = samples
        rows = checked_records(cards)
        faults = record_faults(cards)
        isempty(rows) && !isempty(faults) && throw(first(faults).fault)
        h.div(h.ul((h.li(r.record.label, " — ", r.value) for r in rows)...),
              (h.p(f.record.label, ": ", f.fault.message) for f in faults)...)
    end
end
route!(Samples(); prefix="/checked-samples", operation_policy=:blocking);
response = dispatch(:GET, "/checked-samples/summary?samples.1.code=ab&samples.2.code=%20";
    headers=["HX-Request" => "true"]);
markup = String(response.body);
@assert response.status == 200 && occursin("Sample 1 — AB", markup) # hide
@assert occursin("Sample 2: Enter a sample code", markup) # hide
HTML(markup)
```

A field error keeps its card checked and editable. Its Include box uses no
series colour. Fixing the field restores its colour and checked value. The
one-based `index` in both lists counts unchecked cards too. Throwing a returned
`fault` addresses the original field (for example `samples.3.code`).

From 0.1.199, if the check needs a missing or invalid shared input, the
editor opens with the enabled cards coloured in order. `record_faults` is
empty and `checked_records` raises the original request error. A reader can
correct the shared input on the page. If a card field's default, options, or
relevance also need that input, the editor keeps its submitted value until
the field can be drawn again. Operations still require typed field values,
and unexpected exceptions still surface when the list is resolved.
