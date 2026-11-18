using TestItemRunner

# Snag build-a-master-d-31c79059 (reporter RKPPLBench:ux.wren): a reader of a
# benchmark table could not choose which engine column the others are divided
# by. Design `1exoqn6` (user: no preference → option A): `relative_to =
# RelativeTo(columns; default, sigdigits, suffix, comparable)` on the shared
# tables, a toolbar *Relative to* control, the projection in the browser.
@testitem "relative_to: control, opening view, pairs, Markdown and refusals" tags=[:unit] begin
    using HTMXObjects
    html(x) = repr("text/html", x)
    md(x) = repr("text/markdown", x)
    num(x; kw...) = h.td(string(x); data_htmxo_number=string(x), kw...)
    # The reporter's case: one row of times 2, 4, 8 under one heading.
    headers = ["Model", "A", "B", "C"]
    rows = [h.tr(h.td("m1"), num(2.0), num(4.0), num(8.0); id="row-m1"),
            h.tr(h.td("m2"), num(3.0), num(1.0), h.td("failed"); id="row-m2")]

    # The control and what the runtime reads; the cells stay absolute.
    t = html(sortable_table(headers, rows; id="t", relative_to=RelativeTo(["A", "B", "C"])))
    @test occursin("data-htmxo-relative-to=", t)
    @test occursin("<span class=\"htmxo-relative-control\"><label>Relative to<select", t)
    @test occursin("<option value=\"\" selected=\"true\">Absolute values</option>", t)
    @test occursin("<option value=\"B\">B</option>", t)
    @test count("data-htmxo-relative-select", t) == 1
    @test !occursin("data-htmxo-relative=", t) && !occursin("data-htmxo-relative-shown", t)
    spec = HTMXObjects._relative_spec(RelativeTo(["A", "B", "C"]), headers, nothing)
    @test spec.columns == [2, 3, 4] && spec.names == ["A", "B", "C"]
    @test spec.choices[2].of == Dict("2" => 3, "3" => 3, "4" => 3)
    # It joins the search toolbar before the *Columns* menu, once.
    s = html(sortable_table(headers, rows; searchable=true, relative_to=RelativeTo(2:4)))
    @test count("htmxo-relative-control", s) == 1 && count("htmxo-column-menu-toggle", s) == 1
    @test findfirst("htmxo-relative-control", s)[1] < findfirst("htmxo-column-menu-holder", s)[1]

    # Opening relative to B: 2, 4, 8 against 4 read 0.5×, 1×, 2×, each cell
    # keeping what it replaces; a text cell stays; a row whose reference is
    # 1 divides by it.
    o = sortable_table(headers, rows; id="o", relative_to=RelativeTo(["A", "B", "C"]; default="B"))
    so = html(o)
    @test occursin("data-htmxo-relative-shown=\"B\"", so) && occursin("data-htmxo-relative-cols=\"2,3,4\"", so)
    @test occursin("<option value=\"B\" selected=\"true\">B</option>", so)
    for (abs, ratio, text) in (("2.0", "0.5", "0.5×"), ("4.0", "1", "1×"), ("8.0", "2", "2×"))
        @test occursin("data-htmxo-number=\"$ratio\"", so) && occursin("data-htmxo-relative=\"$ratio\"", so)
        @test occursin("data-htmxo-absolute-number=\"$abs\"", so)
        @test occursin("<template data-htmxo-absolute=\"\">$abs</template>$text</td>", so)
    end
    @test occursin("<td>failed</td>", so)
    @test occursin(">3×</td>", so) && occursin(">1×</td>", so)
    # Markdown shows the table as it opens and says what the ratios are of.
    mo = md(o)
    @test occursin("| Model | A relative to B | B relative to B | C relative to B |", mo)
    @test occursin("| m1 | 0.5× | 1× | 2× |", mo) && !occursin("2.0", mo)

    # Under headings each heading divides by its own column of the label.
    g6 = ["Model", "A", "B", "A", "B", "C"]
    grows = [h.tr(h.td("m"), num(2.0), num(4.0), num(10.0), num(5.0), num(1.0); id="row-m")]
    gs = HTMXObjects._relative_spec(RelativeTo(2:6), g6, ["P" => 2:3, "G" => 4:6])
    @test gs.names == ["A", "B", "C"] && gs.full[4] == "G / A"
    @test gs.choices[2].of == Dict("2" => 3, "3" => 3, "4" => 5, "5" => 5, "6" => 5)
    @test gs.choices[3].of == Dict("4" => 6, "5" => 6, "6" => 6)   # P has no C: it stays absolute
    gm = sortable_table(g6, grows; header_groups=["P" => 2:3, "G" => 4:6],
        relative_to=RelativeTo(2:6; default="B"))
    @test occursin("| m | 0.5× | 1× | 2× | 1× | 0.2× |", md(gm))
    @test occursin("| Model | P / A relative to B | P / B relative to B | G / A relative to B |", md(gm))
    gc = sortable_table(g6, grows; header_groups=["P" => 2:3, "G" => 4:6], relative_to=RelativeTo(2:6; default="C"))
    @test occursin("| m | 2.0 | 4.0 | 10× | 5× | 1× |", md(gc))

    # Pairs: different keys, an incomparable cell, a reference of 0 or none:
    # `–`, no number, sorting last in either direction.
    prow(name, a, b; ka=nothing, kb=nothing, ia=false) = h.tr(h.td(name),
        num(a; (isnothing(ka) ? (;) : (; data_htmxo_compare=ka))..., (ia ? (; data_htmxo_incomparable="") : (;))...),
        num(b; (isnothing(kb) ? (;) : (; data_htmxo_compare=kb))...); id="row-" * name)
    prows = [prow("same", 6.0, 3.0; ka="x", kb="x"), prow("other", 6.0, 3.0; ka="x", kb="y"),
             prow("inc", 6.0, 3.0; ia=true), prow("zero", 6.0, 0.0), prow("any", 9.0, 3.0; ka="x"),
             prow("low", 1.0, 4.0)]
    rel = RelativeTo(["A", "B"]; default="B")
    p = html(sortable_table(["Name", "A", "B"], prows; relative_to=rel))
    @test occursin("data-htmxo-compare=\"x\"", p)
    # other's and inc's A; zero's A and B (0 / 0).
    @test count("data-htmxo-missing", p) == 4
    @test count(">–</td>", p) == 4
    order(ds) = [m.captures[1] for m in eachmatch(r"id=\"row-([a-z]+)\"", html(sortable_table(["Name", "A", "B"], prows;
        relative_to=rel, default_sort=ds)))]
    @test order(2 => :asc) == ["low", "same", "any", "other", "inc", "zero"]
    @test order(2 => :desc) == ["any", "same", "low", "other", "inc", "zero"]

    # master_detail_table: `comparable(item, column)` keys each item's cells
    # by the column's CSV name; group rows get none; one control.
    items = [(; id="i$i", g=isodd(i) ? "odd" : "even", a=Float64(i), b=2.0, env=i == 3 ? "slow" : "fast") for i in 1:4]
    seen = Set{String}()
    cmp(x, col) = (push!(seen, col); col == "A" ? x.env : "fast")
    mdt(; kw...) = master_detail_table(["Name", "A", "B"], items; key=x -> x.id,
        master=x -> (h.td(x.id), x.a, x.b), detail=x -> h.p("d " * x.id), kw...)
    m = html(mdt(; id="m", relative_to=RelativeTo(["A", "B"]; comparable=cmp)))
    @test seen == Set(["A", "B"])
    @test count("data-htmxo-compare=\"slow\"", m) == 1 && count("data-htmxo-compare=\"fast\"", m) == 7
    @test count("htmxo-relative-control", m) == 1
    md_open = mdt(; id="m", relative_to=RelativeTo(["A", "B"]; default="B", comparable=cmp))
    @test occursin("| i1 | 0.5× | 1× |", md(md_open)) && occursin("| i3 | – | 1× |", md(md_open))
    @test occursin("| i4 | 2× | 1× |", md(md_open))
    grouped = mdt(; id="gr", groupings=["None" => nothing, "G" => x -> x.g], group_by=["G"],
        group_summary=["A" => ColumnSummary(:sum, x -> x.a), "B" => ColumnSummary(:sum, x -> x.b)],
        relative_to=RelativeTo(["A", "B"]; default="B", comparable=cmp))
    gmd = md(grouped)
    @test occursin("1.5×", gmd)    # the "even" group row: (2 + 4) / (2 + 2), its own cells
    @test count("htmxo-relative-control", html(grouped)) == 1
    # The rows a row update renders are absolute: the browser writes them.
    upd = html(mdt(; id="m", update_rows="i1", relative_to=RelativeTo(["A", "B"]; default="B")))
    @test !occursin("data-htmxo-relative=", upd)

    # render_table: `comparable(row, column)` by the column's name.
    r = render_table((name=["x", "y"], a=[2.0, 6.0], b=[4.0, 3.0]);
        relative_to=RelativeTo(["a", "b"]; default="b", comparable=(row, col) -> row.name == "y" && col == "a" ? missing : 1))
    @test occursin("| x | 0.5× | 1× |", md(r)) && occursin("| y | – | 1× |", md(r))
    @test occursin("data-htmxo-incomparable", html(r))

    # The language of the table: words and number marks.
    de = html(sortable_table(headers, rows; texts=table_texts(:de),
        relative_to=RelativeTo(["A", "B", "C"]; default="C", sigdigits=2, suffix=" ×")))
    @test occursin(">Relativ zu<select", de) && occursin(">Absolute Werte</option>", de)
    @test occursin(">0,25 ×</td>", de) && occursin(">0,5 ×</td>", de)
    @test table_texts(:de).relative_column == "{name} relativ zu {reference}"
    @test_throws ArgumentError table_texts(; relative_column="{name} vs {other}")

    # Refused: too few columns, the first column, an unknown or ambiguous
    # name, a default that is no label, two compared columns of one label
    # under one heading, a value that is no RelativeTo.
    @test_throws ArgumentError RelativeTo(["A"])
    @test_throws ArgumentError RelativeTo(["A", "B"]; sigdigits=0)
    @test_throws ArgumentError RelativeTo(["A", "B"]; comparable=1)
    @test_throws ArgumentError sortable_table(headers, rows; relative_to=RelativeTo(["Model", "A"]))
    @test_throws ArgumentError sortable_table(headers, rows; relative_to=RelativeTo(["A", "Q"]))
    @test_throws ArgumentError sortable_table(headers, rows; relative_to=RelativeTo(["A", "A"]))
    @test_throws ArgumentError sortable_table(headers, rows; relative_to=RelativeTo(["A", "B"]; default="C"))
    @test_throws ArgumentError sortable_table(g6, grows; relative_to=RelativeTo(2:6))
    @test_throws ArgumentError sortable_table(g6, grows; header_groups=["P" => 2:3, "G" => 4:6], relative_to=RelativeTo(["A", "B"]))
    @test_throws ArgumentError sortable_table(headers, rows; relative_to=["A", "B"])
end

@testitem "a reader shows a table relative to a column it picks" tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Times of three engines in two headings; m3's C was measured
        # elsewhere (another key), m4 has no B.
        items = [(; id="m1", p=(2.0, 4.0, 8.0), g=(20.0, 10.0, 5.0), env="x", kind="small"),
                 (; id="m2", p=(9.0, 3.0, 6.0), g=(4.0, 8.0, 2.0), env="x", kind="small"),
                 (; id="m3", p=(1.0, 2.0, 3.0), g=(6.0, 3.0, 9.0), env="y", kind="big"),
                 (; id="m4", p=(5.0, NaN, 1.0), g=(7.0, 7.0, 7.0), env="x", kind="big")]
        headers = ["Model", "Size", "A", "B", "C", "A", "B", "C"]
        cells(m) = (h.td(m.id), h.td(m.kind), (isnan(x) ? h.td("—") : h.td(h.strong(string(x), " s");
            data_htmxo_number=string(x), data_sort_value=string(x)) for x in (m.p..., m.g...))...)
        relative(; kw...) = RelativeTo(3:8; comparable=(m, col) -> !startswith(col, "Primal") ? nothing :
            m.id == "m3" && col == "Primal / C" ? "y" : "x", kw...)
        groups = ["Primal" => 3:5, "Gradient" => 6:8]
        flat(; kw...) = master_detail_table(headers, items; key=m -> "f-" * m.id, master=cells, id="flat",
            detail_url=m -> "/detail?id=" * m.id, header_groups=groups, hidden_columns=["Size"],
            relative_to=relative(), searchable=true, kw...)
        opened() = master_detail_table(headers, items; key=m -> "o-" * m.id, master=cells, id="opened",
            detail=m -> h.p("Detail " * m.id), header_groups=groups, relative_to=relative(; default="B"))
        grouped() = master_detail_table(headers, items; key=m -> "g-" * m.id, master=cells, id="grp",
            detail=m -> h.p("Detail " * m.id), header_groups=groups, relative_to=relative(),
            groupings=["None" => nothing, "Size" => m -> m.kind], group_by=["Size"],
            group_summary=["A" => ColumnSummary(:sum, m -> m.p[1]), "B" => ColumnSummary(:sum, m -> m.p[2])])
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
        const row = (id, key) => document.getElementById('row-' + key);
        // A master row's shown texts from column `from` on.
        // A leaf of a grouped table carries its group's path in its id.
        const texts = (key, from = 3) => {
          const r = document.getElementById('row-' + key) || document.querySelector('tr[id^="row-group--"][id$="--' + key + '"]');
          return r ? Array.from(r.cells).slice(from - 1).map(c => c.textContent.trim()).join('|') :
            'no row ' + key + ' among ' + Array.from(document.querySelectorAll('tr[id]')).map(x => x.id).join(',');
        };
        const order = id => Array.from(document.getElementById(id).rows).filter(r => !r.id.startsWith('detail-'))
          .map(r => r.id.replace(/^row-[a-z]-/, '')).join(',');
        const select = id => {
          let el = tableOf(id);
          while (el && !el.querySelector(':scope > .htmxo-table-toolbar')) el = el.parentElement;
          return el.querySelector(':scope > .htmxo-table-toolbar select[data-htmxo-relative-select]');
        };
        const pick = async (id, value) => { const s = select(id); s.value = value; s.dispatchEvent(new Event('change', {bubbles: true})); await pause(200); };
        const sortBy = async (id, col) => { htmxoColumnCells(tableOf(id)).find(c => Number(c.dataset.htmxoSortCol) === col)
          .querySelector('.htmxo-sort-control').click(); await pause(200); };
        let events = [];
        document.addEventListener('htmxo:relative-changed', e => events.push(String(e.detail.reference)));
        const csvOf = async id => {
          let csv = null;
          const create = URL.createObjectURL, click = HTMLAnchorElement.prototype.click;
          URL.createObjectURL = b => { b.text().then(t => { csv = t; }); return 'blob:none'; };
          HTMLAnchorElement.prototype.click = function() {};
          downloadTableCsv(tableOf(id), id + '.csv');
          await until(() => csv !== null, 'the CSV');
          URL.createObjectURL = create;
          HTMLAnchorElement.prototype.click = click;
          return csv.trim().split('\n');
        };
        async function phase1() {
          const out = {};
          out.options = Array.from(select('flat').options).map(o => o.textContent).join('|');
          out.open_m1 = texts('f-m1');
          // Open m1's lazy detail, then pick B: the detail stays open and loaded.
          row('flat', 'f-m1').click();
          await until(() => document.querySelector('#detail-f-m1 [data-loaded="1"], #detail-f-m1 .loaded'), 'the lazy detail');
          const detailNode = document.querySelector('#detail-f-m1 .loaded');
          await pick('flat', 'B');
          out.picked_m1 = texts('f-m1');
          out.picked_m2 = texts('f-m2');
          out.picked_m3 = texts('f-m3');
          out.picked_m4 = texts('f-m4');
          out.detail_kept = document.querySelector('#detail-f-m1 .loaded') === detailNode && !document.getElementById('detail-f-m1').hidden ? 1 : 0;
          out.size_hidden = row('flat', 'f-m1').cells[1].hasAttribute('data-htmxo-column-hidden') ? 1 : 0;
          out.numbers = Array.from(row('flat', 'f-m1').cells).slice(2).map(c => c.dataset.htmxoNumber ?? '-').join('|');
          out.stored = localStorage.getItem('htmxo-relative|flat|/');
          // Sorting Primal / A orders by the ratios; a cell without one is last both ways.
          await sortBy('flat', 3);
          out.asc = order('flat');
          await sortBy('flat', 3);
          out.desc = order('flat');
          // The ⬇ CSV writes the ratios and names the divided columns.
          const csv = await csvOf('flat');
          out.csv_head = csv[0];
          out.csv_m1 = csv.find(l => l.startsWith('m1,'));
          // Search still finds rows; the count is unchanged.
          // Another pick keeps the sort; back to absolute values puts the cells back, markup included.
          await pick('flat', 'C');
          out.c_m1 = texts('f-m1');
          out.c_sorted = order('flat');
          await pick('flat', '');
          out.abs_m1 = texts('f-m1');
          out.abs_markup = row('flat', 'f-m1').cells[2].innerHTML;
          out.abs_marks = row('flat', 'f-m1').querySelectorAll('[data-htmxo-relative], [data-htmxo-absolute-number], [data-htmxo-missing]').length;
          out.events = events.join(',');
          // A script reads and sets the pick.
          out.api = htmxoTableRelative('#flat');
          htmxoTableRelative('#flat', 'A');
          await pause(200);
          out.api_m2 = texts('f-m2');
          // A row update arrives absolute and is written for the pick.
          const stale = document.getElementById('row-f-m2');
          htmxoUpdateRows(await (await fetch('/update')).text());
          await until(() => document.getElementById('row-f-m2') && document.getElementById('row-f-m2') !== stale, 'the row update');
          out.update_m2 = texts('f-m2');
          // A table that opens relative to B (the server wrote it) goes back to absolute values.
          out.opened_m1 = texts('o-m1');
          await pick('opened', '');
          out.opened_abs = texts('o-m1');
          out.opened_markup = row('opened', 'o-m1').cells[2].innerHTML;
          await pick('opened', 'C');
          out.opened_c = texts('o-m1');
          // Group sums divide too, and again after a regroup.
          await pick('grp', 'B');
          const sum = () => Array.from(document.getElementById('grp').rows).find(r => r.dataset.htmxoGroup !== undefined && r.textContent.includes('small'));
          out.group_sum = Array.from(sum().cells).slice(2, 4).map(c => c.textContent.trim()).join('|');
          const pill = name => Array.from(tableOf('grp').closest('[data-htmxo-grouped]').querySelectorAll('.htmxo-group-pill > button'))
            .find(b => b.textContent.trim().endsWith(name));
          pill('Size').click();
          await pause(300);
          pill('Size').click();
          await pause(300);
          out.regroup_sum = Array.from(sum().cells).slice(2, 4).map(c => c.textContent.trim()).join('|');
          out.regroup_m1 = texts('g-m1');
          return out;
        }
        async function phase2(out) {
          // After a reload the reader's pick is back.
          out.reloaded = htmxoTableRelative('#flat');
          out.reloaded_m2 = texts('f-m2');
          out.reloaded_select = select('flat').value;
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
        content = h.main(; class="container")(flat(), opened(), grouped(), driver)
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
            path == "/detail" && return html(repr("text/html", h.p("Loaded " * HTTP.queryparams(uri)["id"]; class="loaded")))
            path == "/update" && return html(repr("text/html", flat(; update_rows="f-m2")))
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
        @info "Relative columns in the browser\n" * join((k * " => " * v for (k, v) in sort!(collect(got))), "\n")
        @test got["options"] == "Absolute values|A|B|C"
        @test got["open_m1"] == "2.0 s|4.0 s|8.0 s|20.0 s|10.0 s|5.0 s"
        # The reporter's case: 2, 4, 8 against 4.
        @test got["picked_m1"] == "0.5×|1×|2×|2×|1×|0.5×"
        @test got["picked_m2"] == "3×|1×|2×|0.5×|1×|0.25×"
        @test got["picked_m3"] == "0.5×|1×|–|2×|1×|3×"        # Primal / C measured elsewhere
        @test got["picked_m4"] == "–|—|–|1×|1×|1×"            # no Primal / B
        @test got["detail_kept"] == "1"
        @test got["size_hidden"] == "1"
        @test got["numbers"] == "0.5|1|2|2|1|0.5"
        @test got["stored"] == "\"B\""
        @test got["asc"] == "m1,m3,m2,m4" && got["desc"] == "m2,m1,m3,m4"
        @test got["csv_head"] == "Model,Primal / A relative to B,Primal / B relative to B,Primal / C relative to B," *
            "Gradient / A relative to B,Gradient / B relative to B,Gradient / C relative to B"
        @test got["csv_m1"] == "m1,0.5,1,2,2,1,0.5"
        @test got["c_m1"] == "0.25×|0.5×|1×|4×|2×|1×"
        @test got["c_sorted"] == "m4,m2,m1,m3"                 # still descending by Primal / A
        @test got["abs_m1"] == "2.0 s|4.0 s|8.0 s|20.0 s|10.0 s|5.0 s"
        @test got["abs_markup"] == "<strong>2.0 s</strong>"
        @test got["abs_marks"] == "0"
        @test got["events"] == "B,C,null"
        @test got["api"] == "" && got["api_m2"] == "1×|0.333×|0.667×|1×|2×|0.5×"
        @test got["update_m2"] == "1×|0.333×|0.667×|1×|2×|0.5×"
        @test got["opened_m1"] == "0.5×|1×|2×|2×|1×|0.5×"
        @test got["opened_abs"] == "2.0 s|4.0 s|8.0 s|20.0 s|10.0 s|5.0 s"
        @test got["opened_markup"] == "<strong>2.0 s</strong>"
        @test got["opened_c"] == "0.25×|0.5×|1×|4×|2×|1×"
        @test got["group_sum"] == "1.57×|1×"                   # small: (2 + 9) / (4 + 3)
        @test got["regroup_sum"] == got["group_sum"] && got["regroup_m1"] == "0.5×|1×|2×|2×|1×|0.5×"
        @test got["reloaded"] == "A" && got["reloaded_select"] == "A"
        @test got["reloaded_m2"] == "1×|0.333×|0.667×|1×|2×|0.5×"
    end
end
