using TestItemRunner

# Hand-placed choices take the option records a generated control reads
# (snag in-brunopkpd-s-r-c614c7ec, reporter Bruno:reports:ux): an option can be
# shown but unavailable, carry help, and sit in a group, without hand-building
# the control's markup.

@testitem "a hand-placed choice renders option records as a generated control does" tags=[:unit] begin
    using HTMXObjects
    using HTMXObjects.DynamicObjects: option_domain

    html(x) = repr("text/html", x)
    # Each `_choice_list` numbers its popover; compare the markup without it.
    unnumbered(s) = replace(s, r"htmxo-choice-\d+" => "htmxo-choice-N")
    records = [(; value="v1", label="Bundle 1"),
               (; value="v2", label="Bundle 2", disabled=true, help="Its files are not on this host"),
               (; value="v3", label="Bundle 3", group="Archived")]
    domain = (; options=[merge((; group=nothing, help=nothing, disabled=false), r) for r in records])

    # Pills: the unavailable option is a disabled radio with its help after the label.
    pills = html(radio_group((; bundle="v1"), records; label="Bundle"))
    @test contains(pills, "<label><input type=\"radio\" name=\"bundle\" value=\"v2\" disabled=\"true\">Bundle 2 — Its files are not on this host</label>")
    @test contains(pills, "<label><input type=\"radio\" name=\"bundle\" value=\"v1\" checked=\"true\">Bundle 1</label>")
    @test pills == html(HTMXObjects._semantic_radio(:bundle, "Bundle", domain, "v1"))

    # The searchable list: a disabled row, help as its second line, a group heading.
    list = html(choice_list((; bundle="v1"), records; label="Bundle"))
    @test contains(list, "<label class=\"htmxo-choice-option\"><input type=\"radio\" name=\"bundle\" value=\"v2\" disabled=\"true\"><span class=\"htmxo-choice-label\">Bundle 2</span><small>Its files are not on this host</small></label>")
    @test contains(list, "<div class=\"htmxo-choice-group\"><div class=\"htmxo-choice-heading\">Archived</div><label class=\"htmxo-choice-option\"><input type=\"radio\" name=\"bundle\" value=\"v3\">")
    @test unnumbered(list) == unnumbered(html(HTMXObjects._semantic_choice_list(:bundle, "Bundle", domain, "v1")))

    # The native select: a disabled option with its help as the tooltip, an optgroup.
    select = html(sinput((; bundle="v1"), records; label="Bundle"))
    @test contains(select, "<option value=\"v2\" disabled=\"true\" title=\"Its files are not on this host\">Bundle 2</option>")
    @test contains(select, "<optgroup label=\"Archived\"><option value=\"v3\">Bundle 3</option></optgroup>")
    @test contains(select, "<option value=\"v1\" selected=\"true\">Bundle 1</option>")
    @test select == html(HTMXObjects._semantic_select(:bundle, "Bundle", domain, "v1"))
    @test html(soption(records[2])) == "<option value=\"v2\" disabled=\"true\" title=\"Its files are not on this host\">Bundle 2</option>"
    @test html(soption((; value="v1"); selected_value="v1")) == "<option value=\"v1\" selected=\"true\">v1</option>"

    # With a free-text box: the disabled option stays disabled, a chosen value
    # outside the options is still added, and typing a disabled option's value
    # does not choose it.
    custom = html(sinput_custom((; bundle="v9"), records; label="Bundle"))
    @test contains(custom, "<option value=\"v2\" disabled=\"true\" title=\"Its files are not on this host\">Bundle 2</option>")
    @test contains(custom, "<option value=\"v9\" selected=\"true\">v9</option>")
    @test contains(custom, "if(sel.options[i].disabled)return;")

    # An `option_domain`, as an `@options` declaration writes it, passed whole
    # keeps its labels and records (iterating it yields only the values).
    declared = option_domain(["v1" => "Bundle 1", (; value="v2", label="Bundle 2", disabled=true)])
    @test contains(html(radio_group("bundle", declared)), "value=\"v2\" disabled=\"true\">Bundle 2</label>")
    @test contains(html(choice_list("bundle", declared)), "<span class=\"htmxo-choice-label\">Bundle 1</span>")
    @test contains(html(sinput("bundle", declared)), "<option value=\"v2\" disabled=\"true\">Bundle 2</option>")
end

@testitem "the earlier option spellings render as before" tags=[:unit] begin
    using HTMXObjects

    html(x) = repr("text/html", x)
    # Plain values, `value => label` pairs and `(value, label)` tuples.
    @test html(sinput("color", ["red", "green"]; value="green")) ==
          "<label>color<select name=\"color\" aria-label=\"color\"><option value=\"red\">red</option><option value=\"green\" selected=\"true\">green</option></select></label>"
    @test html(sinput("m", ["A" => "Method A", ("B", "Method B")]; value="B")) ==
          "<label>m<select name=\"m\" aria-label=\"m\"><option value=\"A\">Method A</option><option value=\"B\" selected=\"true\">Method B</option></select></label>"
    @test html(radio_group((; m="B"), ["A" => "Method A", ("B", "Method B"), "C"])) ==
          "<fieldset><legend>m</legend><label><input type=\"radio\" name=\"m\" value=\"A\">Method A</label><label><input type=\"radio\" name=\"m\" value=\"B\" checked=\"true\">Method B</label><label><input type=\"radio\" name=\"m\" value=\"C\">C</label></fieldset>"
    @test contains(html(choice_list((; m="B"), [("B", "Method B")])), "<span class=\"htmxo-choice-label\">Method B</span>")
    # A radio is checked by its wire spelling, so 1 matches "1" as before, and
    # `kwargs` still go on each radio.
    @test contains(html(radio_group((; n="1"), [1, 2]; hx_get="/x")), "value=\"1\" checked=\"true\" hx-get=\"/x\"")
    # Bool options keep their string values.
    @test contains(html(radio_group((; flag=false), (false, true))), "name=\"flag\" value=\"false\" checked=\"true\">false</label>")
    # A NamedTuple without a `value` field is still a plain option value: an
    # option object identified by its `key`.
    keyed = (; key="k1", title="One")
    @test contains(html(radio_group("pick", [keyed]; value=keyed)), "<input type=\"radio\" name=\"pick\" value=\"k1\" checked=\"true\">")
    @test startswith(html(soption(keyed)), "<option value=\"k1\">")
    @test contains(html(choice_list("pick", [keyed])), "value=\"k1\"")
    @test contains(html(sinput_custom((; level="info"), ["info", "warn"])), "<option value=\"info\" selected=\"true\">info</option><option value=\"warn\">warn</option>")
end
