using TestItemRunner

# Snag user-selectable-19e5cf8d: a reader could not choose which of a wide
# table's columns it shows. The design (user decision 1xs0167, recommended
# options): a *Columns* menu on every table of four or more columns, the
# reader's choice kept in the browser, the ⬇ CSV writing the shown columns
# and Markdown/PDF the columns the table opens with.
@testitem "hidden_columns: opening view, the menu's place, Markdown and refusals" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    md(x) = repr("text/markdown", x)
    rows = [h.tr(h.td("a$i"), h.td("b$i"), h.td("c$i"), h.td("d$i")) for i in 1:2]
    four = ["A", "B", "C", "D"]

    # Four or more columns: a menu, in a toolbar of its own when the table
    # has no other controls; three: none, unless asked for.
    @test occursin("htmxo-column-menu-toggle", html(sortable_table(four, rows)))
    three = [h.tr(h.td("a"), h.td("b"), h.td("c"))]
    @test !occursin("htmxo-column-menu", html(sortable_table(["A", "B", "C"], three)))
    @test occursin("htmxo-column-table", html(sortable_table(["A", "B", "C"], three; column_menu=true)))
    @test !occursin("htmxo-column-menu", html(sortable_table(four, rows; column_menu=false)))
    # It joins the search field's toolbar, once.
    searched = html(sortable_table(four, rows; searchable=true))
    @test count("htmxo-column-menu-toggle", searched) == 1 && !occursin("htmxo-column-table", searched)

    # The opening view is written hidden: header and cells, by label or position.
    s = html(sortable_table(four, rows; id="t", hidden_columns=["C", 2]))
    @test occursin("data-htmxo-hidden-columns=\"[2,3]\"", s)
    @test occursin("data-htmxo-columns-applied=\"2,3\"", s)
    @test count("data-htmxo-column-hidden", s) == 2 + 2 * 2
    @test count("data-htmxo-cols=\"2,3\"", s) == 2
    # Markdown leaves them out; the menu writes nothing there.
    m = md(sortable_table(four, rows; hidden_columns=["C", 2]))
    @test occursin("| A | D |", m) && occursin("| a1 | d1 |", m) && !occursin("b1", m) && !occursin("c1", m)
    @test md(sortable_table(four, rows)) == md(sortable_table(four, rows; column_menu=false))

    # A spanning cell spans its shown columns and keeps the count it covers;
    # a heading over hidden columns narrows, Markdown names "Group / Leaf".
    grows = Any[h.tr(h.td("n$i"), h.td("x$i"), h.td("y$i"), h.td("z$i"); id="row-k$i") for i in 1:2]
    push!(grows, h.tr(h.td("detail"; colspan="4"); id="detail-k1"))
    g = sortable_table(["Name", "X", "Y", "Z"], grows; header_groups=["G" => 2:3], hidden_columns=["G / X"])
    sg = html(g)
    @test occursin("<td colspan=\"3\" data-htmxo-span=\"4\">detail</td>", sg)
    @test occursin("<th colspan=\"1\" scope=\"colgroup\" data-htmxo-span=\"2\">G</th>", sg)
    @test occursin("| Name | G / Y | Z |", md(g))
    gone = html(sortable_table(["Name", "X", "Y", "Z"], grows; header_groups=["G" => 2:3], hidden_columns=[2, 3]))
    heading = match(r"<th [^>]*scope=\"colgroup\"[^>]*>G</th>", gone).match
    @test occursin("data-htmxo-column-hidden", heading) && occursin("data-htmxo-span=\"2\"", heading)

    # Refused: the first column, an unknown or ambiguous name, a position out
    # of range, hidden columns without the menu that shows them again.
    @test_throws ArgumentError sortable_table(four, rows; hidden_columns=["A"])
    @test_throws ArgumentError sortable_table(four, rows; hidden_columns=["Q"])
    @test_throws ArgumentError sortable_table(four, rows; hidden_columns=[9])
    @test_throws ArgumentError sortable_table(four, rows; hidden_columns=["B"], column_menu=false)
    five = [h.tr(h.td("n"), h.td("r"), h.td("s"), h.td("r"), h.td("s"))]
    groups = ["P" => 2:3, "G" => 4:5]
    @test_throws ArgumentError sortable_table(["N", "R", "S", "R", "S"], five; header_groups=groups,
        hidden_columns=["R"], default_sort=1)
    @test occursin("data-htmxo-hidden-columns=\"[4]\"", html(sortable_table(["N", "R", "S", "R", "S"], five;
        header_groups=groups, hidden_columns=["G / R"], default_sort=1)))

    # master_detail_table places one menu in whichever toolbar it has, and
    # its details span the shown columns.
    items = [(; id="i$i", a="a$i", b=string(i), c="c$i", d="d$i", g=isodd(i) ? "odd" : "even") for i in 1:4]
    cells(x) = (h.td(x.a), h.td(x.b), h.td(x.c), h.td(x.d))
    mdt(; kw...) = html(master_detail_table(four, items; key=x -> x.id, master=cells, detail=x -> h.p("d " * x.id), kw...))
    flat = mdt(; hidden_columns=["C"], id="m")
    @test count("htmxo-column-menu-toggle", flat) == 1 && occursin("htmxo-column-table", flat)
    @test occursin("data-htmxo-span=\"4\"", flat)
    @test count("htmxo-column-menu-toggle", mdt(; selectable="sel")) == 1
    grouped = mdt(; groupings=["None" => nothing, "G" => x -> x.g], group_by=["G"], searchable=true, hidden_columns=[4], id="g")
    @test count("htmxo-column-menu-toggle", grouped) == 1 && occursin("data-htmxo-hidden-columns=\"[4]\"", grouped)
    @test !occursin("htmxo-column-menu", mdt(; column_menu=false))

    # render_table forwards them; the menu speaks the table's language.
    rt = render_table((a=[1, 2], b=[3, 4], c=["x", "y"], d=[5.5, 6.5]); hidden_columns=["c"], texts=table_texts(:de))
    @test occursin(">Spalten</button>", html(rt)) && occursin(">Zurücksetzen</button>", html(rt))
    @test !occursin("| x", md(rt)) && occursin("| a | b | d |", md(rt))
end

# The menu in a browser: hide and show, the first column fixed, a heading's
# columns together; hidden columns stay hidden through sorting, an open
# detail, regrouping, lazy group rows, a row update and a re-render; the
# columns hold their widths over the shown ones; the ⬇ CSV writes the shown
# columns; the choice comes back after a reload, and Reset and
# `htmxoTableColumns` work. `consistent` checks every body row: its shown
# cells cover exactly the shown columns.
@testitem "a reader hides and shows a table's columns" tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        items = [(; id="t$i", a="Name $i", b=string(10 * i), c="C$i", d="D$i", e=string(100 - i),
                  g=isodd(i) ? "odd" : "even") for i in 1:6]
        headers = ["Name", "B", "C", "D", "E"]
        cells(t) = (h.td(t.a), h.td(t.b; data_sort_value=t.b), h.td(t.c), h.td(t.d), h.td(t.e; data_sort_value=t.e))
        detail(t) = h.p("Detail " * t.id)
        groupings = ["Keine" => nothing, "Art" => t -> t.g]
        flat(; kw...) = master_detail_table(headers, items; key=t -> "f-" * t.id, master=cells, detail,
            id="flat", hidden_columns=["C"], kw...)
        grouped() = master_detail_table(headers, items; key=t -> "g-" * t.id, master=cells, detail, id="grp",
            header_groups=["Werte" => 3:4], hidden_columns=["Werte / C"], groupings, group_by=["Art"],
            group_summary=["E" => ColumnSummary(:sum, t -> parse(Int, t.e))], searchable=true)
        lazy(; kw...) = master_detail_table(headers, items; key=t -> "l-" * t.id, master=cells, detail, id="lazy",
            hidden_columns=[4], groupings, group_by=["Art"], group_by_url="/regroup",
            group_rows_url=(k, ms) -> "/rows?key=" * HTTP.escapeuri(k), kw...)
        driver = h.script(Raw(raw"""
        const pause = ms => new Promise(r => setTimeout(r, ms));
        const until = async (ready, what) => {
          for (let t = 0; !ready(); t += 50) {
            if (t > 10000) throw new Error(what + ' did not happen within 10 s');
            await pause(50);
          }
          await pause(200);
        };
        const report = body => fetch('/complete', {method: 'POST', body});
        window.addEventListener('error', e => report('error ' + e.message));
        const tableOf = id => document.getElementById(id).closest('table');
        const shown = id => JSON.stringify(htmxoTableColumns('#' + id));
        // Rows whose shown cells do not cover exactly the shown columns.
        const consistent = id => {
          const t = tableOf(id), n = htmxoTableColumns('#' + id).length, bad = [];
          Array.from(t.tBodies[0].rows).forEach(r => {
            const cover = Array.from(r.cells).filter(c => getComputedStyle(c).display !== 'none')
              .reduce((s, c) => s + c.colSpan, 0);
            if (cover !== n) bad.push(r.id + ':' + cover);
          });
          const heads = htmxoColumnCells(t);
          if (heads.length !== n || heads.some(c => getComputedStyle(c).display === 'none')) bad.push('head');
          return bad.length;
        };
        // How far a shown master row's cells sit from their header cells.
        const misaligned = id => {
          const t = tableOf(id), heads = htmxoColumnCells(t);
          const shownCells = r => Array.from(r.cells).filter(c => getComputedStyle(c).display !== 'none');
          const row = Array.from(t.tBodies[0].rows).find(r => getComputedStyle(r).display !== 'none' &&
            shownCells(r).length === heads.length);
          if (!row) return 999;
          const cells = shownCells(row);
          return Math.max(...cells.map((c, i) => Math.abs(c.getBoundingClientRect().left - heads[i].getBoundingClientRect().left)));
        };
        const menuOf = id => {
          const t = tableOf(id);
          let el = t;
          while (el && !el.querySelector(':scope > .htmxo-table-toolbar')) el = el.parentElement;
          return el.querySelector(':scope > .htmxo-table-toolbar .htmxo-column-menu-toggle');
        };
        const openMenu = async id => { const b = menuOf(id); b.click(); await pause(100); return b.nextElementSibling; };
        const boxes = menu => Array.from(menu.querySelectorAll('input[type="checkbox"]'));
        let changes = 0;
        document.addEventListener('htmxo:columns-changed', () => changes++);
        async function phase1() {
          const out = {};
          // The opening view.
          out.open_flat = shown('flat');
          out.open_bad = consistent('flat');
          out.open_detail_span = document.querySelector('#flat > tr[id^="detail-"] > td').colSpan;
          // The menu: a box per column, the first fixed, C unticked; show C, hide D.
          let menu = await openMenu('flat');
          out.menu_open = menu.matches(':popover-open') ? 1 : 0;
          out.menu_boxes = boxes(menu).length;
          out.menu_first_disabled = boxes(menu)[0].disabled ? 1 : 0;
          out.menu_c_ticked = boxes(menu)[2].checked ? 1 : 0;
          boxes(menu)[2].click();
          boxes(menu)[3].click();
          await pause(200);
          out.picked = shown('flat');
          out.picked_bad = consistent('flat');
          out.picked_misaligned = misaligned('flat');
          out.held_cols = tableOf('flat').querySelectorAll(':scope > colgroup > col').length;
          out.stored = localStorage.getItem('htmxo-columns|flat|/');
          out.changes = changes;
          document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
          await pause(100);
          out.menu_closed = menu.matches(':popover-open') ? 0 : 1;
          // Sorting by E (column 5) orders the rows by it; details stay with their rows.
          htmxoColumnCells(tableOf('flat'))[3].querySelector('.htmxo-sort-control').click();
          await pause(200);
          const rows = Array.from(document.getElementById('flat').rows);
          out.sorted_first = rows[0].id;
          out.sorted_pairs = rows.every((r, i) => i % 2 === 1 || rows[i + 1].id === r.id.replace('row-', 'detail-')) ? 1 : 0;
          // An open detail spans the table's width.
          rows[0].click();
          await pause(200);
          const td = rows[1].cells[0];
          out.detail_width = Math.abs(td.getBoundingClientRect().width - tableOf('flat').getBoundingClientRect().width);
          // The ⬇ CSV writes the shown columns.
          let csv = null;
          const create = URL.createObjectURL, click = HTMLAnchorElement.prototype.click;
          URL.createObjectURL = b => { b.text().then(t => { csv = t; }); return 'blob:none'; };
          HTMLAnchorElement.prototype.click = function() {};
          downloadTableCsv(tableOf('flat'), 'flat.csv');
          await until(() => csv !== null, 'the CSV');
          URL.createObjectURL = create;
          HTMLAnchorElement.prototype.click = click;
          out.csv_head = csv.split('\n')[0];
          out.csv_row = csv.split('\n')[1];
          // A row update arrives written for the hidden columns.
          htmxoUpdateRows(await (await fetch('/update')).text());
          await pause(200);
          out.update_bad = consistent('flat');
          out.update_hidden = document.getElementById('row-f-t2').querySelectorAll('[data-htmxo-column-hidden]').length;
          // A re-render keeps the reader's choice.
          const before = tableOf('flat');
          await htmx.ajax('GET', '/flat', {target: before.closest('.htmxo-column-table'), swap: 'outerHTML'});
          await until(() => tableOf('flat') !== before, 'the re-render');
          out.rerendered = shown('flat');
          out.rerendered_bad = consistent('flat');

          // A heading's columns: its box is mixed while one of them hides.
          out.grp_open = shown('grp');
          out.grp_bad = consistent('grp');
          const heading = tableOf('grp').tHead.querySelector('th[scope="colgroup"]');
          out.grp_heading_span = heading.colSpan;
          menu = await openMenu('grp');
          const head = menu.querySelector('legend input');
          out.grp_mixed = head.indeterminate ? 1 : 0;
          head.click();
          await pause(200);
          out.grp_all = shown('grp');
          out.grp_heading_all = heading.colSpan;
          head.click();
          await pause(200);
          out.grp_none = shown('grp');
          out.grp_heading_gone = getComputedStyle(heading).display === 'none' ? 1 : 0;
          out.grp_none_bad = consistent('grp');
          document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
          // Regrouping in the browser, to the flat view and back.
          const pill = name => Array.from(tableOf('grp').closest('[data-htmxo-grouped]').querySelectorAll('.htmxo-group-pill > button'))
            .find(b => b.textContent.trim().endsWith(name));
          pill('Art').click();
          await pause(300);
          out.regroup_flat_bad = consistent('grp');
          pill('Art').click();
          await pause(300);
          out.regroup_back_bad = consistent('grp');
          out.regroup_misaligned = misaligned('grp');

          // Lazy group rows arrive written for the hidden columns.
          out.lazy_open = shown('lazy');
          const group = tableOf('lazy').tBodies[0].querySelector(':scope > tr[data-htmxo-lazy-rows]');
          group.querySelector('[data-htmxo-tree-toggle]').click();
          await until(() => !('htmxoLazyRows' in group.dataset), 'the lazy group rows');
          out.lazy_bad = consistent('lazy');
          return out;
        }
        async function phase2(out) {
          // After a reload the reader's choice is back.
          out.reloaded = shown('flat');
          out.reloaded_bad = consistent('flat');
          // Reset: the columns the table opens with, the choice forgotten.
          const menu = await openMenu('flat');
          menu.querySelector('.htmxo-column-reset').click();
          await pause(200);
          out.reset = shown('flat');
          out.reset_stored = localStorage.getItem('htmxo-columns|flat|/') === null ? 1 : 0;
          out.reset_ticks = boxes(menu).map(b => b.checked ? 1 : 0).join('');
          // A script shows exactly some columns.
          htmxoTableColumns('#flat', [1, 5]);
          await pause(200);
          out.scripted = shown('flat');
          out.scripted_bad = consistent('flat');
          return out;
        }
        window.addEventListener('load', async () => {
          await pause(300);
          try {
            if (location.search !== '?phase=2') {
              sessionStorage.setItem('phase1', JSON.stringify(await phase1()));
              location.href = '/?phase=2';
            } else {
              const out = await phase2(JSON.parse(sessionStorage.getItem('phase1')));
              report(Object.entries(out).map(([k, v]) => k + ' ' + v).join('\n'));
            }
          } catch (e) { report('error ' + e.message + '\n' + e.stack); }
        });
        """))
        vendor = Dict(HTMXObjects._vendor_files(:htmx)..., HTMXObjects._vendor_files(:pico)...)
        content = h.main(; class="container")(flat(), grouped(), lazy(), driver)
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
            path == "/rows" && return html(repr("text/html", lazy(; group_rows=HTTP.queryparams(uri)["key"])))
            path == "/update" && return html(repr("text/html", flat(; update_rows="f-t2")))
            path == "/flat" && return html(repr("text/html", flat()))
            path == "/complete" && (isready(result) || put!(result, String(req.body)); return HTTP.Response(204))
            HTTP.Response(404)
        end
        got = try
            mktempdir() do profile
                log = joinpath(profile, "browser.log")
                browser = run(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --window-size=1400,1000 --enable-logging=stderr --v=0 --user-data-dir=$profile http://127.0.0.1:$port/`;
                    stdout=devnull, stderr=log); wait=false)
                try
                    timedwait(() -> isready(result) || process_exited(browser), 90; pollint=0.1)
                    isready(result) || error("the page reported nothing; requests: " * join(served, ", ") *
                        "\nbrowser log:\n" * read(log, String))
                    body = take!(result)
                    startswith(body, "error ") && error("the page failed: " * body[7:end] *
                        "\nrequests: " * join(served, ", "))
                    Dict(String(first(kv)) => String(last(kv)) for kv in split.(split(body, '\n'), ' '; limit=2))
                finally
                    process_exited(browser) || kill(browser)
                    wait(browser)
                end
            end
        finally
            close(server)
        end
        @info "Column menu in the browser" got
        num(k) = parse(Float64, got[k])
        @test got["open_flat"] == "[1,2,4,5]"
        @test num("open_bad") == 0
        @test num("open_detail_span") == 4
        @test num("menu_open") == 1 && num("menu_boxes") == 5 && num("menu_first_disabled") == 1
        @test num("menu_c_ticked") == 0
        @test got["picked"] == "[1,2,3,5]"
        @test num("picked_bad") == 0
        @test num("picked_misaligned") <= 1
        @test num("held_cols") == 4
        @test got["stored"] == "{\"hidden\":[\"D\"],\"shown\":[\"B\",\"C\",\"E\"]}"
        @test num("changes") == 2
        @test num("menu_closed") == 1
        @test got["sorted_first"] == "row-f-t6"
        @test num("sorted_pairs") == 1
        @test num("detail_width") <= 1
        @test got["csv_head"] == "Name,B,C,E"
        @test got["csv_row"] == "Name 6,60,C6,94"
        @test num("update_bad") == 0 && num("update_hidden") == 1
        @test got["rerendered"] == "[1,2,3,5]" && num("rerendered_bad") == 0
        @test got["grp_open"] == "[1,2,4,5]" && num("grp_bad") == 0
        @test num("grp_heading_span") == 1 && num("grp_mixed") == 1
        @test got["grp_all"] == "[1,2,3,4,5]" && num("grp_heading_all") == 2
        @test got["grp_none"] == "[1,2,5]" && num("grp_heading_gone") == 1 && num("grp_none_bad") == 0
        @test num("regroup_flat_bad") == 0 && num("regroup_back_bad") == 0
        @test num("regroup_misaligned") <= 1
        @test got["lazy_open"] == "[1,2,3,5]" && num("lazy_bad") == 0
        @test got["reloaded"] == "[1,2,3,5]" && num("reloaded_bad") == 0
        @test got["reset"] == "[1,2,4,5]" && num("reset_stored") == 1 && got["reset_ticks"] == "11011"
        @test got["scripted"] == "[1,5]" && num("scripted_bad") == 0
    end
end
