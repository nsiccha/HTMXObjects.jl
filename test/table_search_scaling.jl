@testitem "hierarchical search reads text once per row browser" setup=[ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        table = sortable_table(["Name"], Any[]; searchable=true, id="search-scaling")
        driver = h.script(Raw(raw"""
        window.addEventListener('error', event => {
            const error = document.createElement('pre'); error.id = 'driver-error';
            error.textContent = event.message; document.body.appendChild(error);
        });
        document.addEventListener('DOMContentLoaded', () => {
            const body = document.getElementById('search-scaling');
            const root = body.closest('.htmxo-searchable-table');
            const checks = [], rows = [];
            let reads = 0, count;
            root.addEventListener('htmxo:table-filtered', e => { count = e.detail; });
            const check = (name, ok) => checks.push(name + ':' + Boolean(ok));
            for (let i = 0; i < 1024; i++) {
                const row = document.createElement('tr');
                row.id = 'chain-' + i;
                row.dataset.htmxoParent = i ? 'chain-' + (i - 1) : '';
                row.dataset.htmxoTreeOpen = 'true';
                const cell = row.insertCell();
                const text = i % 2 ? 'beta' : 'alpha';
                cell.appendChild(document.createTextNode(text));
                Object.defineProperty(cell, 'textContent', {get() { reads++; return text; }});
                rows.push(row);
            }
            // A sort or row swap need not leave parents before children.
            rows.slice().reverse().forEach(row => body.appendChild(row));
            htmxoTableSearch(root, '');
            check('empty-query-no-text-reads', reads === 0 && count.shown === rows.length);
            reads = 0;
            htmxoTableSearch(root, 'ALPHA   beta');
            check('cross-ancestor-phrase', rows.every(row => !row.hidden) && count.shown === rows.length);
            check('one-text-read-per-row', reads === rows.length);
            reads = 0;
            htmxoTableSearch(root, 'absent');
            check('no-match', rows.every(row => row.hidden) && count.shown === 0);
            check('no-match-linear-reads', reads === rows.length);
            htmxoTableSearch(root, 'alpha beta');
            root.dataset.htmxoSearchCollapsed = '';
            htmxoFilterTable(root);
            check('collapse-requires-own-phrase', rows.every(row => row.hidden));
            htmxoTableSearch(root, '');
            rows[0].dataset.htmxoTreeOpen = 'false';
            htmxoFilterTable(root);
            check('collapsed-parent', !rows[0].hidden && rows.slice(1).every(row => row.hidden));
            rows[0].dataset.htmxoTreeOpen = 'true';
            reads = 0;
            htmxoTableFilter(root, 'search', (row, ctx) => ctx.text.includes('alpha beta'));
            check('custom-ancestor-text', rows.every(row => !row.hidden) && count.shown === rows.length);
            check('custom-reuses-row-text', reads === rows.length);
            const result = document.createElement('pre'); result.id = 'checks';
            result.textContent = checks.join('\n'); document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(table, driver; htmx_version=nothing,
            hyperscript_version=nothing, pico_version=nothing, feedback=false,
            compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ?
                HTTP.Response(200, ["Content-Type" => "text/html"], page) : HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            error = match(r"<pre id=\"driver-error\">(.*?)</pre>"s, dom)
            isnothing(error) || @info "Browser driver error" error=error[1]
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                @test length(lines) == 9
                for line in lines
                    @test endswith(line, ":true")
                end
            end
        finally
            close(server)
        end
    end
end
