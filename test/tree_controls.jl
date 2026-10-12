@testitem "expand_controls render Expand all / Collapse all for a hierarchy" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: to_markdown_string
    leaf(k) = (; key=k, kids=())
    roots = [(; key="g", kids=[(; key="s", kids=[leaf("l1")]), leaf("l2")])]
    tree(; kw...) = master_detail_table(["Name"], roots; key=x -> x.key, master=x -> (h.td(x.key),),
        children=x -> x.kids, detail_url=x -> isempty(x.kids) ? "/d/$(x.key)" : nothing, kw...)
    html = repr("text/html", tree(expand_controls=true, id="t"))
    @test contains(html, "<button type=\"button\" class=\"secondary outline\" aria-controls=\"t\" onclick=\"htmxoTreeAll(this, true)\">Expand all</button>")
    @test contains(html, "aria-controls=\"t\" onclick=\"htmxoTreeAll(this, false)\">Collapse all</button>")
    @test contains(html, "<tbody id=\"t\">")
    # Without a caller id the body gets a stable id the buttons name.
    derived = repr("text/html", tree(expand_controls=true))
    body_id = match(r"<tbody id=\"(htmxo-tree-[0-9a-z]+)\">", derived)
    @test !isnothing(body_id) && contains(derived, "aria-controls=\"$(body_id[1])\"")
    @test derived == repr("text/html", tree(expand_controls=true))
    @test !contains(repr("text/html", tree()), "Expand all")
    md = to_markdown_string(tree(expand_controls=true, searchable=true))
    @test !contains(md, "Expand all") && !contains(md, "Collapse all")
    # Refused: no collapsible branches means nothing for the buttons to drive.
    @test_throws ArgumentError master_detail_table(["Name"], ["a"]; key=identity,
        master=x -> (h.td(x),), detail=x -> "", expand_controls=true)
    @test_throws ArgumentError tree(expand_controls=true, branches_collapsible=false)
end

@testitem "expand_controls browser" tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        leaf(k, name) = (; key=k, name, kids=())
        group(k, name, kids) = (; key=k, name, kids)
        roots = [group("all", "All models", [
                    group("fam-a", "Alpha family", [group("grp-a", "Alpha group", [leaf("m1", "Model one"), leaf("m2", "Model two")])]),
                    group("fam-b", "Beta family", [leaf("m3", "Model three")])])]
        tree = master_detail_table(["Name"], roots; key=x -> x.key, master=x -> (h.td(x.name),),
            children=x -> x.kids, detail_url=x -> isempty(x.kids) ? "/detail/$(x.key)" : nothing,
            initially_open=x -> x.key == "all", searchable=true, expand_controls=true, id="tree")
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const row = k => document.getElementById('row-' + k);
            const root = document.getElementById('tree').closest('.htmxo-searchable-table');
            const button = label => Array.from(root.querySelectorAll('.htmxo-tree-controls > button')).find(b => b.textContent === label);
            const shown = () => Array.from(document.getElementById('tree').rows).filter(r => r.id.startsWith('row-') && !r.hidden).map(r => r.id.slice(4)).join(',');
            const input = root.querySelector('input[type="search"]');
            const filter = v => { input.value = v; input.dispatchEvent(new Event('input', {bubbles: true})); };
            check('initial', shown() === 'all,fam-a,fam-b');
            button('Expand all').click();
            check('expand-all', shown() === 'all,fam-a,grp-a,m1,m2,fam-b,m3');
            check('expand-glyphs', row('grp-a').querySelector('[data-htmxo-tree-toggle]').getAttribute('aria-expanded') === 'true');
            check('details-stay-closed', document.getElementById('detail-m1').hidden);
            await new Promise(r => setTimeout(r, 200));
            check('lazy-stays-lazy', !document.querySelector('[data-loaded="1"]'));
            button('Collapse all').click();
            check('collapse-all', shown() === 'all');
            // A user's own branch choice before searching...
            row('all').querySelector('[data-htmxo-tree-toggle]').click();
            row('fam-b').querySelector('[data-htmxo-tree-toggle]').click();
            check('user-state', shown() === 'all,fam-a,fam-b,m3');
            // ...while a search reveals every match below a matching group.
            filter('alpha');
            check('search-reveals', shown() === 'all,fam-a,grp-a,m1,m2');
            button('Collapse all').click();
            check('search-collapse-keeps-matches', shown() === 'all,fam-a,grp-a');
            check('search-collapse-glyph', row('grp-a').querySelector('[data-htmxo-tree-toggle]').textContent === '▸' &&
                row('fam-a').querySelector('[data-htmxo-tree-toggle]').textContent === '▾');
            check('count-follows', root.querySelector('[data-htmxo-table-count]').textContent === '3 of 7 rows shown');
            button('Expand all').click();
            check('search-expand', shown() === 'all,fam-a,grp-a,m1,m2');
            button('Collapse all').click();
            filter('');
            check('clear-restores-user-state', shown() === 'all,fam-a,fam-b,m3');
            filter('alpha');
            check('collapse-ends-with-search', shown() === 'all,fam-a,grp-a,m1,m2');
            filter('');
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
            document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(tree, driver;
            extra_head=(sortable_table_js(), sortable_table_styles()),
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false))
        requests = Ref(0)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            if path == "/"
                HTTP.Response(200, ["Content-Type" => "text/html"], page)
            elseif startswith(path, "/detail/")
                requests[] += 1
                HTTP.Response(200, ["Content-Type" => "text/html"], "<p>loaded</p>")
            else
                HTTP.Response(404)
            end
        end
        try
            dom = mktempdir() do profile
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; stderr=devnull), String)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                for line in split(checks[1], '\n')
                    @test endswith(line, ":true")
                end
                @test count(==('\n'), checks[1]) + 1 == 14
            end
            @test requests[] == 0
        finally
            close(server)
        end
    end
end
