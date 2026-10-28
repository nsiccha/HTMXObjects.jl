using TestItemRunner

# Snag master-detail-ta-244b9573: a table's columns jumped to new widths when
# a row's detail opened, a lazy detail loaded, a group or branch expanded,
# lazy group rows arrived or a search hid rows. Each scenario runs twice: on
# the table as rendered, and on a control copy without the column hold
# (`data-htmxo-columns` renamed) whose detail content sizes the columns again,
# as before the fix. The control must move, so the content is wide enough to
# move the columns at all.
@testitem "a table's columns keep their widths while its rows open, load and filter" tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        long = "Rechnung Nr. 2026-0003 über Wartungsarbeiten an der Heizungsanlage im Erdgeschoss " *
            join(fill("Leistungsbeschreibung", 3), " ")
        items = [(; id="t$i", date="2026-10-$(10 + i)",
                  party=isodd(i) ? "Stadtwerke Musterstadt GmbH" : "Kanzlei Beispiel",
                  desc=i == 3 ? long : "Rechnung $i", amount=string(100 * i),
                  status=i == 5 ? "Wartet auf Freigabe durch die Buchhaltung" : "offen")
                 for i in 1:8]
        headers = ["Datum", "Gegenpartei", "Beschreibung", "Betrag", "Status"]
        cells(t) = (h.td(t.date), h.td(t.party), h.td(t.desc), h.td(t.amount), h.td(t.status))
        # A detail as Invoices' supplier documents have one: a paragraph, an
        # unbreakable line and a wide form field.
        detail(t) = h.div(
            h.p(repeat("Ein langer Absatz im Detail, der die Spalten nicht verschieben darf. ", 6)),
            h.pre("DE89370400440532013000-Verwendungszweck-Rechnung-2026-0001-Wartungsarbeiten-Heizung"),
            h.form(h.label("Notiz", h.input(type="text", name="note", style="width: 40rem"))))
        groupings = ["Keine" => nothing, "Gegenpartei" => t -> t.party]
        branches = [(; id="b1", date="", party="Ordner A", desc="", amount="", status="", children=items[1:4]),
                    (; id="b2", date="", party="Ordner B", desc="", amount="", status="", children=items[5:8])]
        lazygroups(p; kw...) = master_detail_table(headers, items; key=t -> p * "lg-" * t.id, master=cells,
            detail, groupings, group_by=["Gegenpartei"], id=p * "lazygroups", group_by_url="/regroup",
            group_rows_url=(k, ms) -> "/rows/" * p * "?key=" * HTTP.escapeuri(k), kw...)
        tables(p) = (
            master_detail_table(headers, items; key=t -> p * "flat-" * t.id, master=cells, detail, id=p * "flat"),
            master_detail_table(headers, items; key=t -> p * "lazy-" * t.id, master=cells,
                detail_url=t -> "/detail/" * t.id, id=p * "lazy"),
            master_detail_table(headers, items; key=t -> p * "grp-" * t.id, master=cells, detail,
                groupings, group_by="Gegenpartei", id=p * "grouped"),
            lazygroups(p),
            master_detail_table(headers, branches; key=t -> p * "tree-" * t.id, master=cells,
                children=t -> hasproperty(t, :children) ? t.children : (),
                detail=t -> hasproperty(t, :children) ? nothing : detail(t), id=p * "tree"),
            master_detail_table(headers, items; key=t -> p * "s-" * t.id, master=cells, detail,
                searchable=true, id=p * "search"))
        unheld(x) = replace(repr("text/html", x), "data-htmxo-columns" => "data-control-columns")
        # Snag held-table-colum-cdf2c38e: a table in a zoomed tile (Bruno's
        # report viewer scales each tile with `transform: scale()`) was held at
        # the zoom times its widths. One that fills its room (shares) and one
        # wider than its room (pixels: an unbreakable description), each also
        # in a tile at half and at 0.37 of its size.
        wide = [(; t..., desc=t.id == "t3" ? repeat("Verwendungszweck", 12) : t.desc) for t in items]
        zoomable(p) = (
            master_detail_table(headers, items; key=t -> p * "zf-" * t.id, master=cells, detail, id=p * "zfill"),
            master_detail_table(headers, wide; key=t -> p * "zw-" * t.id, master=cells, detail, id=p * "zwide"))
        tile(p, scale) = h.div(; id=p * "tile", style="transform: scale($scale); transform-origin: 0 0")(zoomable(p)...)
        driver = h.script(Raw(raw"""
        const pause = ms => new Promise(r => setTimeout(r, ms));
        // A lazy load lands, or the step reports that it never did.
        const until = async (ready, what) => {
          for (let t = 0; !ready(); t += 50) {
            if (t > 10000) throw new Error(what + ' did not happen within 10 s');
            await pause(50);
          }
          await pause(300);
        };
        const report = body => fetch('/complete', {method: 'POST', body});
        window.addEventListener('error', e => report('error ' + e.message));
        // Each column's left edge and width, from its header cell.
        const columns = id => Array.from(document.getElementById(id).closest('table').tHead.rows[0].cells)
          .map(c => { const r = c.getBoundingClientRect(); return [r.left, r.width]; });
        const moved = (a, b) => Math.max(...a.map((x, i) => Math.max(Math.abs(x[0] - b[i][0]), Math.abs(x[1] - b[i][1]))));
        const shown = tb => Array.from(tb.querySelectorAll(':scope > tr[id^="row-"]:not([hidden])'));
        const branch = tb => shown(tb)[0].querySelector('[data-htmxo-tree-toggle]');
        // Each action, and what shows that it is done.
        const actions = {
          flat: tb => { shown(tb)[2].click(); return pause(300); },
          lazy: tb => { const row = shown(tb)[2]; row.click();
            return until(() => document.getElementById(row.id.replace('row-', 'detail-slot-')).querySelector('pre'), 'the lazy detail'); },
          grouped: tb => { branch(tb).click(); return pause(300); },
          lazygroups: tb => { const row = shown(tb)[0]; branch(tb).click();
            return until(() => !('htmxoLazyRows' in row.dataset), 'the lazy group rows'); },
          tree: tb => { branch(tb).click(); return pause(300); },
          search: tb => { htmxoTableSearch(tb, 'Kanzlei'); return pause(300); },
        };
        // The width a table holds and the widths of its columns, the same at
        // any zoom; 1e9 where a unit differs (shares against pixels).
        const holding = id => { const t = document.getElementById(id).closest('table');
          return [t.style.width, ...Array.from(t.querySelectorAll(':scope > colgroup > col')).map(c => c.style.width)]; };
        const apart = (a, b) => a.length !== b.length || a.length < 2 ? 1e9 : Math.max(...a.map((x, i) =>
          x.replace(/[-\d.]/g, '') === b[i].replace(/[-\d.]/g, '') ? Math.abs(parseFloat(x) - parseFloat(b[i])) : 1e9));
        window.addEventListener('load', async () => {
          await pause(300);
          const out = {}, atLoad = columns('grouped');
          out.fills = holding('zfill')[0] === '100%' ? 0 : 1;
          out.overflows = holding('zwide')[0].endsWith('px') ? 0 : 1;
          for (const p of ['half-', 'tiny-']) for (const t of ['zfill', 'zwide']) out[p + t] = apart(holding(t), holding(p + t));
          // Sized again at another zoom (as a regroup sizes it), the same widths.
          const tile = document.getElementById('half-tile');
          tile.style.transform = 'scale(0.8)';
          tile.querySelectorAll('table[data-htmxo-columns]').forEach(t => htmxoColumnsMeasure(t, true));
          for (const t of ['zfill', 'zwide']) out['rezoomed-' + t] = apart(holding(t), holding('half-' + t));
          for (const prefix of ['', 'c-']) for (const [name, act] of Object.entries(actions)) {
            const id = prefix + name;
            try {
              const before = columns(id);
              await act(document.getElementById(id));
              out[id] = moved(before, columns(id));
            } catch (e) { return report('error ' + id + ': ' + e.message); }
          }
          // The held widths are those of every row shown: the control with
          // all its groups open.
          const control = document.getElementById('c-grouped');
          shown(control).map(r => r.querySelector('[data-htmxo-tree-toggle][aria-expanded="false"]'))
            .forEach(b => b && b.click());
          await pause(300);
          out.fit = moved(atLoad, columns('c-grouped'));
          // A morph to the server's markup drops the colgroup and the marks
          // (the search table, whose hidden rows sized it); the next swap
          // puts the held widths back.
          const searched = document.getElementById('search').closest('table'), held = columns('search');
          searched.querySelector(':scope > colgroup[data-htmxo-columns]').remove();
          searched.removeAttribute('style');
          searched.dataset.htmxoColumns = '';
          out.stripped = moved(held, columns('search'));
          const ping = document.getElementById('ping');
          htmx.trigger(ping, 'ping');
          await until(() => ping.textContent === 'pong', 'the swap');
          out.morph = moved(held, columns('search'));
          // A scrollbar's worth of room keeps the widths; a resize sizes them again.
          const widths = id => Array.from(document.getElementById(id).closest('table')
            .querySelectorAll(':scope > colgroup > col')).map(c => c.style.width).join(' ');
          const main = document.querySelector('main'), first = widths('flat');
          main.style.paddingRight = '30px';
          await pause(500);
          out.narrowed = widths('flat') === first ? 0 : 1;
          main.style.paddingRight = '500px';
          await pause(500);
          out.resized = widths('flat') === first ? 0 : 1;
          report(Object.entries(out).map(([k, v]) => k + ' ' + v).join('\n'));
        });
        """))
        vendor = Dict(HTMXObjects._vendor_files(:htmx)..., HTMXObjects._vendor_files(:pico)...)
        # The controls also let their detail content size the columns, as
        # before the fix.
        control = h.div(; class="control")(h.style(Raw(".control tr[id^=\"detail-\"] > td > * { contain: none; }")),
            Raw(join(unheld.(tables("c-")))))
        # Any swap on the page puts a dropped hold back.
        ping = h.div(; id="ping", hx_get="/ping", hx_trigger="ping", hx_swap="innerHTML")
        content = h.main(; class="container-fluid")(tables("")..., control, zoomable("")...,
            tile("half-", 0.5), tile("tiny-", 0.37), ping, driver)
        page = repr("text/html", htmx(content; assets="/vendor", pico_version=HTMXObjects._PICO_VERSION,
            sse_version=nothing, ws_version=nothing, hyperscript_version=nothing, preload_version=nothing,
            katex_version=nothing))
        html(s) = HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], s)
        result = Channel{String}(1)
        served = String[]
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            uri = HTTP.URI(req.target)
            path = uri.path
            push!(served, req.target)
            path == "/" && return html(page)
            if startswith(path, "/vendor/") && haskey(vendor, path[9:end])
                type = endswith(path, ".css") ? "text/css" : "application/javascript"
                return HTTP.Response(200, ["Content-Type" => type], read(vendor[path[9:end]]))
            end
            startswith(path, "/detail/") &&
                return html(repr("text/html", detail(items[findfirst(t -> "/detail/" * t.id == path, items)])))
            if startswith(path, "/rows/")
                p = path[7:end]
                rows = lazygroups(p; group_rows=HTTP.queryparams(uri)["key"])
                return html(isempty(p) ? repr("text/html", rows) : unheld(rows))
            end
            path == "/ping" && return html("pong")
            path == "/complete" && (isready(result) || put!(result, String(req.body)); return HTTP.Response(204))
            HTTP.Response(404)
        end
        moved = try
            mktempdir() do profile
                log = joinpath(profile, "browser.log")
                browser = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --enable-logging=stderr --v=0 --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=log); wait=false)
                try
                    timedwait(() -> isready(result) || process_exited(browser), 60; pollint=0.1)
                    isready(result) || error("the page reported nothing; requests: " * join(served, ", ") *
                        "\nbrowser log:\n" * read(log, String))
                    body = take!(result)
                    startswith(body, "error ") && error("the page failed: " * body[7:end] *
                        "\nrequests: " * join(served, ", "))
                    Dict(first(kv) => parse(Float64, last(kv)) for kv in split.(split(body, '\n')))
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
        finally
            close(server)
        end
        @info "Column movement (px) per scenario" moved
        for name in ("flat", "lazy", "grouped", "lazygroups", "tree", "search")
            @test moved[name] <= 0.5
            @test moved["c-" * name] > 2
        end
        # The leaves of collapsed groups took part in sizing the columns.
        @test moved["fit"] <= 1
        # A morph's dropped hold moves the columns until the swap restores it.
        @test moved["stripped"] > 2
        @test moved["morph"] <= 0.5
        @test moved["narrowed"] == 0
        @test moved["resized"] == 1
        # A zoomed tile holds the widths the unzoomed table holds, up to the
        # last digit Chrome writes in a style length (six significant digits:
        # 0.01 px past 1000 px).
        @test moved["fills"] == 0
        @test moved["overflows"] == 0
        for p in ("half-", "tiny-", "rezoomed-"), t in ("zfill", "zwide")
            @test moved[p * t] <= 0.011
        end
    end
end
