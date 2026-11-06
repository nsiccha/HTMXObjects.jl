# `live_thread(items; focus=key)` opens on an item (snag live-thread-focu-88da0c00):
# an item that fits the scroll box is centred, and an item taller than the box
# opens at its start, because a long message has to be read from the top.

@testitem "live_thread focus opens a tall item at its start and centres one that fits, in a browser" setup=[ChromeDump] tags=[:browser, :integration] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        # Every item has an exact height, so the expected offsets are exact.
        item(key, px) = key => h.div(key; style="height: $(px)px")
        tall = item("tall", 1500)
        short(keys...) = [item(k, 100) for k in keys]
        thread(id, items; kwargs...) = live_thread(items; id, height="300px", poll=nothing, kwargs...)
        threads = (
            # The report: a tall item with messages on both sides of it.
            thread("middle", [short("a", "b")..., tall, short("c", "d")...]; focus="tall"),
            # The newest message, the usual link target in a chat.
            thread("newest", [short("a", "b")..., tall]; focus="tall"),
            # The first rendered item: the box prefetches an older page at
            # startup, which lands above the item the reader is looking at.
            thread("paged", [tall, short("c")...]; focus="tall", older_url="/older", cursor="1"),
            # Taller than the box by less than the "at the bottom" margin, and
            # the newest: sticking to the bottom would cut off its first 20 px.
            thread("barely", [short("a", "b")..., item("tall", 320)]; focus="tall"),
            # A border on the scroll box: the item's start lies below it, not under it.
            thread("bordered", [short("a", "b")..., tall, short("c")...]; focus="tall"),
            # The positive controls: a fitting item stays centred, 100 px down,
            # and one that opens at the bottom still follows new messages.
            thread("fits", short("a", "b", "c", "d", "e", "f"); focus="c"),
            thread("end", short("a", "b", "c", "d"); focus="d"),
        )
        # Under `--virtual-time-budget` the resize observer's first callback, which
        # scrolls a stuck thread to its bottom, may or may not run (measured both
        # ways). `stuck` is asserted beside the offset, so a run without that
        # callback still catches a thread that would have scrolled.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          const R = document.body.dataset, wait = ms => new Promise(r => setTimeout(r, ms));
          const until = async f => { for (let i = 0; i < 400 && !f(); i++) await wait(25); return f(); };
          const root = id => document.getElementById(id);
          const keys = id => [...root(id).querySelectorAll('.htmxo-thread-item')].map(e => e.dataset.key);
          const ids = ['middle', 'newest', 'paged', 'barely', 'bordered', 'fits', 'end'];
          // `data-stage` names the step a run cut off by the budget was in.
          R.stage = 'startup';
          await until(() => ids.every(id => root(id).__htmxoThread));
          R.stage = 'older';
          await until(() => keys('paged')[0] === 'o1');
          await wait(200);
          R.stage = 'read';
          for (const id of ids) {
            const sc = root(id).querySelector('.htmxo-thread-scroll');
            const focused = root(id).querySelector('.htmxo-thread-focus');
            R[id + 'Key'] = focused ? focused.dataset.key : 'none';
            // Measured from where the box's content starts showing, inside its border.
            R[id + 'Top'] = focused ? String(Math.round(focused.getBoundingClientRect().top - sc.getBoundingClientRect().top - sc.clientTop)) : 'none';
            R[id + 'Box'] = String(sc.clientHeight);
            R[id + 'Stuck'] = String(root(id).__htmxoThread.stuck);
          }
          R.pagedFirst = keys('paged')[0];
          // A scroll event that moved nothing, as the opening scroll's own is
          // once `lastTop` has recorded it, does not stick the thread...
          const barely = root('barely').querySelector('.htmxo-thread-scroll');
          barely.dispatchEvent(new Event('scroll'));
          R.barelyStuckUnmoved = String(root('barely').__htmxoThread.stuck);
          // ...and a reader who scrolls on to the bottom does.
          barely.scrollTop += 5;
          barely.dispatchEvent(new Event('scroll'));
          R.barelyStuckMoved = String(root('barely').__htmxoThread.stuck);
          R.stage = 'done';
          R.done = 'true';
        });
        """))
        style = h.style(Raw("#bordered .htmxo-thread-scroll { border-top: 3px solid; }"))
        page = repr("text/html", htmx(h.main(style, threads..., driver);
            htmx_version=nothing, hyperscript_version=nothing, sse_version=nothing,
            ws_version=nothing, preload_version=nothing, pico_version=nothing,
            feedback=false, overlay=false))
        older = repr("text/html", live_thread_page(short("o1", "o2"); cursor=nothing))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/older" && return HTTP.Response(200, ["Content-Type" => "text/html"], older)
            HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            read_attr(name) = let m = match(Regex("data-$name=\"([^\"]*)\""), dom)
                isnothing(m) ? "missing" : m[1]
            end
            @test read_attr("stage") == "done"
            # The focus landed on the item asked for, in a box of the asked size.
            for id in ("middle", "newest", "paged", "barely", "bordered")
                @test read_attr("$id-key") == "tall"
                @test read_attr("$id-box") == "300"
                @test read_attr("$id-top") == "0"
            end
            # A tall newest message is being read, not followed.
            @test read_attr("newest-stuck") == "false"
            @test read_attr("barely-stuck") == "false"
            @test read_attr("barely-stuck-unmoved") == "false"
            @test read_attr("barely-stuck-moved") == "true"
            # The older page really landed above the focused item.
            @test read_attr("paged-first") == "o1"
            @test read_attr("fits-key") == "c"
            @test read_attr("fits-box") == "300"
            @test read_attr("fits-top") == "100"
            @test read_attr("fits-stuck") == "false"
            @test read_attr("end-key") == "d"
            @test read_attr("end-top") == "200"
            @test read_attr("end-stuck") == "true"
        finally
            close(server)
        end
    end
end
