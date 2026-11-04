using TestItemRunner

# A row update slower than the grace period answers first with a poller, in the
# requester's `hx-target`. Its final answer goes to the table, and no swap
# replaces the poller, so the poller stayed on the page for good, its running
# tree showing and its badge going stale (snag `slow-row-update-fcaf4181`). The
# page must end as a direct answer leaves it: rows updated, the target as it
# was.
@testmodule RowUpdatePollFixtures begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: h, Raw

    export RowPollApp, reset_rows!, release!, report_of, reported, offers_push

    const rows_lock = ReentrantLock()
    const gates = Dict{String,Base.Event}()
    const cells = Dict{String,String}()
    const BEACONS = String[]

    function reset_rows!()
        lock(rows_lock) do
            foreach(notify, values(gates))   # free what an earlier run left waiting
            empty!(gates)
            empty!(BEACONS)
            merge!(empty!(cells), Dict(k => "old-$k" for k in ("a", "b", "c", "d")))
        end
        HTMXObjects._clear_operation_polls!()
        nothing
    end

    gate(name) = lock(() -> get!(Base.Event, gates, name), rows_lock)
    release!(name) = notify(gate(name))
    reported(prefix) = lock(() -> findfirst(startswith(prefix), BEACONS), rows_lock)
    report_of(prefix) = lock(() -> BEACONS[findfirst(startswith(prefix), BEACONS)], rows_lock)

    # Whether this Treebars offers a pushed answer to `htmx:beforeSwap` (0.1.5).
    # Without that a pushed answer skips the table's listener altogether, which
    # is Treebars' to fix and says nothing about the poller.
    offers_push() = contains(repr("text/html", Treebars.htmx_treebar_script()), "treebarPushed")

    # What the driver saw. It clicks every control, reports that the pollers
    # stand, waits for the rows the test releases, then keeps watching for
    # longer than a poll interval and Treebars' five seconds without news.
    const DRIVER = h.script(Raw(raw"""
    (function () {
    const seen = { errors: [], offers: { pushed: 0, polled: 0 }, toasts: 0, replaced: null, replacedOffers: 0 };
    new MutationObserver(records => records.forEach(record => record.addedNodes.forEach(node => {
      if (node.nodeType === 1 && (node.matches('.htmxo-toast') || node.querySelector('.htmxo-toast'))) seen.toasts++;
    }))).observe(document.documentElement, { childList: true, subtree: true });
    const error = console.error;
    console.error = function () {
      seen.errors.push(Array.from(arguments).map(String).join(' '));
      return error.apply(console, arguments);
    };
    window.addEventListener('error', e => seen.errors.push(String(e.message)));
    document.addEventListener('htmx:beforeSwap', function (e) {
      if (String(e.detail.serverResponse).indexOf('data-htmxo-row-update') < 0) return;
      seen.offers[e.detail.treebarPushed ? 'pushed' : 'polled']++;
      const path = String((e.detail.requestConfig || {}).path);
      if (seen.replaced && path.indexOf(seen.replaced) !== -1) seen.replacedOffers++;
    }, true);
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const beacon = text => fetch('/row_poll_beacon?text=' + encodeURIComponent(text));
    const text = id => { const el = document.getElementById(id); return el ? el.textContent : null; };
    const html = id => document.getElementById(id).innerHTML.replace(/\s+/g, ' ').trim();
    async function until(predicate, tries) {
      for (let n = 0; n < tries; n++) {
        if (predicate()) return true;
        await sleep(25);
      }
      return false;
    }
    window.addEventListener('load', async function () {
      const standing = () => document.querySelectorAll('.treebar-poller-inner[hx-get]').length;
      document.getElementById('ask-a').click();
      document.getElementById('ask-b').click();
      document.getElementById('ask-c').click();
      document.getElementById('ask-d1').click();
      const four = await until(() => standing() === 4, 1600);
      // The second request of `d` replaces the poller of the first, whose
      // answer must then never be applied.
      seen.replaced = /__htmxo_operation=([^&#]+)/.exec(
        document.querySelector('#status-d .treebar-poller-inner').getAttribute('hx-get'))[1];
      document.getElementById('ask-d2').click();
      const replaced = await until(() =>
        (document.querySelector('#status-d .treebar-poller-inner') || { getAttribute() { return ''; } })
          .getAttribute('hx-get').indexOf('version=2') !== -1, 1600);
      await beacon(four && replaced ? 'polling' : 'no-poller:' + standing());
      await until(() => ['a', 'b', 'c'].every(k => text('cell-' + k) === 'new-' + k) &&
                        text('cell-d') === 'new-d-2', 1600);
      await sleep(7000);
      const statuses = ['a', 'c', 'd'].map(k => html('status-' + k));
      const control = document.getElementById('status-a-control');
      if (control) control.click();
      const answered = await until(() => text('status-a-answer') === 'still live', 400);
      await beacon('report:' + JSON.stringify({
        cells: ['a', 'b', 'c', 'd'].map(k => text('cell-' + k)),
        statuses,
        rows: Array.from(document.querySelectorAll('#rows-table tr[id^="row-"]')).map(r => r.id),
        rowsOutside: document.querySelectorAll('tr[id^="row-"]').length,
        answered,
        pollers: document.querySelectorAll('.treebar-poller, .treebar-terminal').length,
        toasts: seen.toasts,
        errors: seen.errors, offers: seen.offers, replacedOffers: seen.replacedOffers }));
    });
    })();
    """))

    const KEYS = ["a", "b", "c", "d"]

    # The controls in a row: `b` targets its own row, as a row action does.
    rows_table(self; kw...) = master_detail_table(["Row", "Action"], KEYS;
        key=identity,
        master=k -> (h.td(h.span(lock(() -> cells[k], rows_lock); id="cell-$k")),
                     h.td(k == "b" ?
                          h.button("ask"; id="ask-b", hx_post=query_url(self / "row_slow_post"; key="b"),
                                   hx_target="closest tr", hx_swap="outerHTML") : "")),
        detail=k -> h.p("about $k"), id="rows", kw...)

    set_cell!(key, value) = lock(() -> (cells[key] = value), rows_lock)

    @htmx struct RowPollApp
        __page__(body) = htmx(h.main(body); assets=:vendor, pico_version=nothing,
            hyperscript_version=nothing)
        "The page"
        @get row_poll_page() = h.section(
            h.div(rows_table(__self__); id="rows-table"),
            h.button("ask"; id="ask-a", hx_get=query_url(__self__ / "row_slow"; key="a"), hx_target="#status-a", hx_swap="innerHTML"),
            h.div(; id="status-a")(h.em("idle-a"),
                h.button("control"; id="status-a-control", hx_get=__self__ / "row_poll_control",
                         hx_target="#status-a-answer", hx_swap="innerHTML")),
            h.div(; id="status-a-answer"),
            h.button("ask"; id="ask-c", hx_post=query_url(__self__ / "row_slow_toast"; key="c"), hx_target="#status-c", hx_swap="innerHTML"),
            h.div(; id="status-c")("idle-c"),
            h.button("ask"; id="ask-d1", hx_get=query_url(__self__ / "row_slow_version"; version=1), hx_target="#status-d", hx_swap="innerHTML"),
            h.button("ask"; id="ask-d2", hx_get=query_url(__self__ / "row_slow_version"; version=2), hx_target="#status-d", hx_swap="innerHTML"),
            h.div(; id="status-d")("idle-d"),
            DRIVER)
        "A slow row update, asked for beside the table"
        @get row_slow(; key::String) =
            (wait(gate("rows")); set_cell!(key, "new-$key"); rows_table(__self__; update_rows=key))
        "A slow row update, asked for from its own row"
        @post row_slow_post(; key::String) =
            (wait(gate("rows")); set_cell!(key, "new-$key"); rows_table(__self__; update_rows=key))
        "A slow row update with a success toast, so its final answer has a header to act on"
        @post row_slow_toast(; key::String) =
            (wait(gate("rows")); set_cell!(key, "new-$key");
             hx_response(rows_table(__self__; update_rows=key); toast="Saved $key"))
        "A slow row update whose poller a later request replaces"
        @get row_slow_version(; version::Int) =
            (wait(gate("rows")); version == 2 && set_cell!("d", "new-d-2"); rows_table(__self__; update_rows="d"))
        "What the content a poller displaced still asks for"
        @get row_poll_control() = h.span("still live")
        "Where the driver reports"
        @get row_poll_beacon(; text::String="") =
            (lock(() -> push!(BEACONS, text), rows_lock); h.p("ok"))
    end
end

@testitem "a slow row update leaves no poller behind, polled or pushed" setup=[RowUpdatePollFixtures, HTMXOTestPorts] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, JSON, Test
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        route!(RowPollApp())
        vendorfiles()
        operation_log = HTMXObjects.OPERATION_LOG[]
        for stream in (false, true)
            if stream && !offers_push()
                @test_skip "this Treebars does not offer a pushed answer to htmx:beforeSwap"
                continue
            end
            reset_rows!()
            port = free_port()
            serve(; port, async=true, access_log=nothing, operation_log=nothing, operation_stream=stream)
            try
                HTTP.get("http://127.0.0.1:$port/row_poll_page"; retry=false)
                mktempdir() do profile
                    cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=$profile http://127.0.0.1:$port/row_poll_page`
                    proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
                    try
                        @test timedwait(() -> reported("polling") !== nothing || reported("no-poller") !== nothing,
                                        120.0; pollint=0.05) === :ok
                        @test reported("polling") !== nothing
                        # Longer than the stream's one second to its first answer.
                        sleep(2.0)
                        release!("rows")
                        @test timedwait(() -> reported("report:") !== nothing, 90.0; pollint=0.05) === :ok
                    finally
                        process_exited(proc) || kill(proc)
                        wait(proc)
                    end
                end
                r = JSON.parse(chopprefix(report_of("report:"), "report:"))
                @test r["errors"] == []
                # Every row took its answer: the row asked for from inside
                # itself too, replaced once and not added beside the one its
                # poller displaced, and the second request's answer on `d`.
                @test r["cells"] == ["new-a", "new-b", "new-c", "new-d-2"]
                @test r["rows"] == ["row-a", "row-b", "row-c", "row-d"]
                @test r["rowsOutside"] == 4
                # No poller left, and each target as it was. What a poller
                # displaced is live again, and a poller the next one replaced
                # did not come back.
                @test r["pollers"] == 0
                @test r["statuses"][1] == """<em>idle-a</em><button id="status-a-control" hx-get="/row_poll_control" hx-target="#status-a-answer" hx-swap="innerHTML">control</button>"""
                @test r["statuses"][2:3] == ["idle-c", "idle-d"]
                @test r["replacedOffers"] == 0
                @test r["answered"] === true
                # The route's toast shows once: leaving does not make htmx run
                # the response's listeners a second time.
                @test r["toasts"] == 1
                offers = r["offers"]
                if stream
                    # The toast keeps `c` on the poll path; the others were pushed.
                    @test offers["pushed"] >= 1 && offers["polled"] >= 1
                else
                    @test offers["pushed"] == 0 && offers["polled"] >= 4
                end
            finally
                release!("rows")
                terminate()
                HTMXObjects.OPERATION_LOG[] = operation_log
            end
        end
    end
end
