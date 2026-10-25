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
