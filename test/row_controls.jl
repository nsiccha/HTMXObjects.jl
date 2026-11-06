@testitem "the row toggle, tree row and selection share one row-control check" tags=[:unit] begin
    using HTMXObjects
    runtime = repr("text/html", master_detail_js())
    @test contains(runtime, "function htmxoRowControl(row, target)")
    @test contains(runtime, "'a,button,input,textarea,select,label,form,details,[contenteditable]'")
    @test contains(runtime, "return control && row.contains(control) ? control : null;")
    @test contains(runtime, "if (htmxoRowControl(row, event.target)) return;")
    tables = repr("text/html", sortable_table_js())
    @test contains(tables, "function htmxoTreeRow(row, event) {\n    if (htmxoRowControl(row, event.target)) return;")
    @test contains(tables, "return htmxoRowControl(row, e.target) ? null : [root, row];")
    # No guard keeps its own copy of the list.
    @test count("closest('a,button", tables) == 1
    # A hierarchy leaf whose label holds a drop-out or a label keeps a separate
    # detail control: the label is not wrapped in the row's native button.
    leaf(label) = repr("text/html", master_detail_table(["Name"], [(; key="g", kids=[(; key="l", kids=())])];
        key=x -> x.key, master=x -> (h.td(isempty(x.kids) ? label : "Group"),), children=x -> x.kids,
        detail=x -> isempty(x.kids) ? h.p("about") : nothing))
    for label in (h.details(h.summary("menu"), h.p("panel")), h.label("pick ", h.input(type="checkbox")))
        @test contains(leaf(label), ">ⓘ</button>")
    end
    @test !contains(leaf(h.span("plain")), ">ⓘ</button>")
end

@testitem "a first cell holding a control is never wrapped in the row's detail button" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    items = [(; id="a", region="North"), (; id="b", region="South")]
    groupings = ["None" => nothing, "Region" => r -> r.region]
    # The three table shapes the report's cell can sit in, in both toggle modes.
    table(cell, shape; kw...) = shape === :tree ?
        master_detail_table(["Name", "Value"], [(; id="g", kids=items)];
            key=r -> "k-$(r.id)", master=r -> (h.td(cell(r)), h.td("1")),
            children=r -> get(r, :kids, ()),
            detail_url=r -> haskey(r, :kids) ? nothing : "/d/$(r.id)", kw...) :
        master_detail_table(["Name", "Value"], items;
            key=r -> "k-$(r.id)", master=r -> (h.td(cell(r)), h.td("1")), detail_url=r -> "/d/$(r.id)",
            (shape === :flat ? (;) : (; groupings, group_by=[shape === :grouped ? "Region" : "None"]))..., kw...)
    shapes = (:flat, :tree, :grouped, :grouped_flat_view)
    leaf(html, id) = match(Regex("<tr[^>]*id=\"[^\"]*row-[^\"]*k-$id\"[^>]*>.*?</td>", "s"), html).match
    # What HTML forbids: a control anywhere inside a <button>.
    nested(html) = any(m -> occursin(r"<(?:a|button|input|select|textarea|label|details)[\s/>]",
        m.captures[1]), eachmatch(r"<button\b[^>]*>(.*?)</button>"s, html))
    holding = (
        "a link" => r -> h.a("Name $(r.id)"; href="/s/$(r.id)"),
        "a link inside a span" => r -> h.span("see ", h.a("Name $(r.id)"; href="/s/$(r.id)")),
        "a SemanticLink" => r -> SemanticLink("Name $(r.id)", "/s/$(r.id)"),
        "Raw with a link" => r -> Raw("<A HREF=\"/s/$(r.id)\">Name $(r.id)</A>"),
        "a checkbox in a label" => r -> h.label(h.input(type="checkbox"), "Name $(r.id)"),
        "a drop-out" => r -> h.details(h.summary("Name $(r.id)"), h.p("panel")),
    )
    for (what, cell) in holding, shape in shapes, toggle in (:button, :label)
        html = repr("text/html", table(cell, shape; detail_toggle=toggle))
        row = leaf(html, "a")
        # Exactly one control opens the row's detail, written beside the label.
        @test !nested(row)
        @test count("data-htmxo-detail-toggle=", row) == 1
        @test contains(row, "aria-controls=\"detail-")
        @test contains(row, "aria-expanded=\"false\"")
        @test !contains(row, "data-htmxo-label=")
        if shape === :flat
            @test contains(row, ">▸</button><span data-htmxo-row-label=\"\">")
        else
            @test endswith(row, ">ⓘ</button></td>")
        end
    end
    # A plain label is still the control under `:label`, whatever writes it.
    plain = ("text" => r -> "Name $(r.id)", "a node" => r -> h.strong("Name $(r.id)"),
             "Raw" => r -> Raw("<b>Name $(r.id)</b>"), "Raw whose tag only starts like a control" => r -> Raw("<abbr title=\"x\">Name $(r.id)</abbr>"))
    for (what, cell) in plain, shape in shapes
        row = leaf(repr("text/html", table(cell, shape; detail_toggle=:label)), "a")
        @test !nested(row)
        @test contains(row, "data-htmxo-label=\"\"")
        @test !contains(row, "ⓘ") && !contains(row, "▸")
    end
    # Each row decides for itself: a plain row beside a linked one keeps its label button.
    mixed = repr("text/html", table(r -> r.id == "a" ? h.a("A"; href="/s/a") : "B", :flat; detail_toggle=:label))
    @test contains(leaf(mixed, "a"), ">▸</button>")
    @test contains(leaf(mixed, "b"), "data-htmxo-label=\"\"")
    # Markdown keeps the link: the separate control is chrome.
    for shape in shapes
        md = to_markdown_string(table(r -> h.a("Name $(r.id)"; href="/s/$(r.id)"), shape; detail_toggle=:label))
        @test contains(md, "[Name a](/s/a)")
        @test !contains(md, "ⓘ") && !contains(md, "▸")
    end
    # Sorting, search and CSV read the label's span, which holds the link alone.
    @test contains(leaf(repr("text/html", table(r -> h.a("Name $(r.id)"; href="/s/$(r.id)"), :grouped; detail_toggle=:label)), "a"),
        "<span data-htmxo-row-label=\"\"><a href=\"/s/a\">Name a</a></span>")
end

@testitem "a first-cell link and the row's detail control each do their own thing" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        items = [(; id="a", region="North"), (; id="b", region="North")]
        cell(prefix) = r -> h.a("Name $(r.id)"; href="#went-$(r.id)", id="$prefix-$(r.id)")
        content = h.div(
            master_detail_table(["Name", "Value"], items; key=r -> "g-$(r.id)",
                master=r -> (h.td(cell("glink")(r)), h.td("1")), detail=r -> h.p("About $(r.id)"),
                groupings=["None" => nothing, "Region" => r -> r.region], group_by="Region",
                initially_open=true, initially_open_detail=false, detail_toggle=:label, id="grouped"),
            master_detail_table(["Name", "Value"], items; key=r -> "f-$(r.id)",
                master=r -> (h.td(cell("flink")(r)), h.td("1")), detail=r -> h.p("About $(r.id)"),
                detail_toggle=:label, id="flat"),
            h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const checks = [];
                const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
                const $ = id => document.getElementById(id);
                for (const prefix of ['glink', 'flink']) {
                    const link = $(prefix + '-a'), row = link.closest('tr');
                    const control = row.querySelector('[data-htmxo-detail-toggle]');
                    const detail = document.getElementById(control.getAttribute('aria-controls'));
                    check(prefix + '-link-outside-control', !control.contains(link) && !link.closest('button'));
                    // What a tap at the control's centre lands on: the report's `hit=a`.
                    control.scrollIntoView({block: 'center'});
                    const box = control.getBoundingClientRect();
                    const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
                    check(prefix + '-tap-hits-control', hit === control);
                    const hash = location.hash;
                    control.click();
                    check(prefix + '-control-opens', !detail.hidden && control.getAttribute('aria-expanded') === 'true');
                    check(prefix + '-control-stays-on-page', location.hash === hash);
                    control.click();
                    check(prefix + '-control-closes', detail.hidden);
                    link.click();
                    check(prefix + '-link-follows', location.hash === '#went-a');
                    check(prefix + '-link-keeps-detail-closed', detail.hidden);
                    history.replaceState(null, '', location.pathname);
                    row.cells[1].click();
                    check(prefix + '-row-click-opens', !detail.hidden);
                    row.cells[1].click();
                }
                const result = document.createElement('pre'); result.id = 'checks';
                result.textContent = checks.join('\n');
                document.body.appendChild(result);
            });
            """)))
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", HTMXObjects.pico_page(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION)))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
        @test !isnothing(checks)
        if !isnothing(checks)
            lines = split(checks[1], '\n')
            for line in lines
                @test endswith(line, ":true")
            end
            @test length(lines) == 16
        end
    end
end

@testitem "a click on a row's own control neither toggles nor selects the row" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # The reported shape: a <details> drop-out (the KB For-You 🔍 menu) in a
        # master row, beside a label and editable text.
        menu(k) = h.details(id="menu-$k")(h.summary(id="sum-$k")("🔍"), h.span(id="panel-$k")("Review on …"))
        cells(k) = (h.td("Item $k"), h.td(menu(k)),
            h.td(h.label(id="label-$k")("Pin ", h.input(type="checkbox", id="check-$k"))),
            h.td(h.span(id="edit-$k", contenteditable="true")("note")))
        flat(keys, id) = master_detail_table(["Name", "Menu", "Pin", "Note"], keys;
            key=identity, master=cells, detail=k -> h.p("About $k"), id)
        tree = master_detail_table(["Name", "Menu"], [(; key="g", kids=[(; key="l", kids=())])];
            key=x -> x.key, master=x -> (h.td("Node $(x.key)"), h.td(menu(x.key))),
            children=x -> x.kids, detail=x -> isempty(x.kids) ? h.p("About $(x.key)") : nothing, id="tree")
        selectable = master_detail_table(["Name", "Menu"], ["s"]; key=identity,
            master=k -> (h.td("Item $k"), h.td(menu(k))), detail=k -> h.p("About $k"),
            selectable="ids", id="sel")
        content = h.div(
            flat(["a"], "flat"),
            # Only controls inside the row count: a table inside a form or a
            # <details> still toggles, and so does a tree inside a form.
            h.form(id="outer-form")(flat(["f"], "in-form"), tree),
            h.details(open=true)(h.summary("Table"), flat(["d"], "in-details")),
            selectable,
            h.script(Raw(raw"""
            window.addEventListener('load', function() {
                const checks = [];
                const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
                const $ = id => document.getElementById(id);
                // Each check compares one click's effect with the state just
                // before it, so an earlier failure cannot make a later one pass.
                const changes = (state, click) => { const before = state(); click(); return state() !== before; };
                const open = k => () => !$('detail-' + k).hidden;
                const shown = k => () => !$('row-' + k).hidden;
                const selected = k => () => $('row-' + k).getAttribute('aria-selected') === 'true';
                check('summary-keeps-detail', !changes(open('a'), () => $('sum-a').click()));
                check('summary-opens-menu', $('menu-a').open);
                check('panel-keeps-detail', !changes(open('a'), () => $('panel-a').click()));
                check('label-keeps-detail', !changes(open('a'), () => $('label-a').click()));
                check('label-checks', $('check-a').checked);
                check('editable-keeps-detail', !changes(open('a'), () => $('edit-a').click()));
                check('row-click-toggles', changes(open('a'), () => $('row-a').cells[0].click()));
                check('in-form-toggles', changes(open('f'), () => $('row-f').cells[0].click()));
                check('in-form-detail-control', changes(open('f'),
                    () => $('row-f').querySelector('[data-htmxo-detail-toggle]').click()));
                check('in-details-toggles', changes(open('d'), () => $('row-d').cells[0].click()));
                check('tree-summary-keeps-children', !changes(shown('l'), () => $('sum-g').click()));
                check('tree-row-in-form-toggles', changes(shown('l'), () => $('row-g').cells[1].click()));
                check('tree-leaf-summary-keeps-detail', !changes(open('l'), () => $('sum-l').click()));
                check('selection-skips-menu', !changes(selected('s'), () => { $('sum-s').click(); $('panel-s').click(); }));
                check('row-click-selects', changes(selected('s'), () => $('row-s').cells[0].click()));
                const result = document.createElement('pre'); result.id = 'checks';
                result.textContent = checks.join('\n');
                document.body.appendChild(result);
            });
            """)))
        dom = mktempdir() do directory
            copy_vendorfiles(joinpath(directory, "vendor"))
            fixture = joinpath(directory, "page.html")
            write(fixture, repr("text/html", HTMXObjects.pico_page(content; assets="vendor",
                pico_version=HTMXObjects._PICO_VERSION)))
            profile = joinpath(directory, "profile")
            dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile file://$fixture`)
        end
        checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
        @test !isnothing(checks)
        if !isnothing(checks)
            lines = split(checks[1], '\n')
            for line in lines
                @test endswith(line, ":true")
            end
            @test length(lines) == 15
        end
    end
end
