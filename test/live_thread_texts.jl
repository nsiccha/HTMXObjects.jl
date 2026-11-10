# The words a `live_thread` writes itself follow the page's language and can be
# replaced (snag rendered-the-kb-38730db8, todo 1rzfc1s): before 0.1.92 the
# client wrote fixed English ("Loading earlier messages…", "Start of thread",
# "↓ N new", "Refreshing failed: …") among a German app's German messages.

@testitem "live_thread writes its own words in the page's language, or in the app's texts=" tags=[:unit] begin
    using HTMXObjects, JSON
    import HTMXObjects: h

    items = ["a" => h.p("eins"), "b" => "zwei"]
    thread(; kw...) = repr("text/html", live_thread(items; id="t", older_url="/older", cursor="a",
                                                    tail_url="/tail", since="a", version="1", kw...))
    unescape(s) = replace(s, "&quot;" => "\"", "&#39;" => "'", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&")
    stamped(html) = let m = match(r"data-htmxo-thread-texts=\"([^\"]*)\"", html)
        isnothing(m) ? nothing : JSON.parse(unescape(m[1]))
    end
    as_dict(t::LiveThreadTexts) = Dict(String(n) => getfield(t, n) for n in fieldnames(LiveThreadTexts))

    # English: no attribute, whatever asks for it, so an English thread renders
    # as it did before texts existed (the runtime holds the English words).
    en = thread()
    @test isnothing(stamped(en))
    @test thread(; texts=live_thread_texts()) == en
    @test thread(; texts=live_thread_texts(:en)) == en
    @test HTMXObjects._with_page_lang(() -> thread(), "fr") == en
    @test HTMXObjects._with_page_lang(() -> thread(), "en-GB") == en
    # Byte-identical to 0.1.91's rendering of the same call.
    @test repr("text/html", live_thread(["a" => "x"]; id="t", poll=nothing)) ==
        "<div id=\"t\" class=\"htmxo-thread\" data-htmxo-thread=\"\" data-since=\"\" data-version=\"\" data-poll=\"0\">" *
        "<div class=\"htmxo-thread-viewport\"><div class=\"htmxo-thread-scroll\">" *
        "<div class=\"htmxo-thread-older\" data-done=\"true\"></div><div class=\"htmxo-thread-items\">" *
        "<div class=\"htmxo-thread-item\" data-key=\"a\" data-digest=\"$(HTMXObjects._thread_digest("<div>x</div>"))\">x</div>" *
        "</div></div><button type=\"button\" class=\"htmxo-thread-new\" hidden=\"true\"></button></div>" *
        "<div class=\"htmxo-thread-status\" role=\"status\" hidden=\"true\"></div></div>"

    # The page's language: German under `__lang__ = "de"` (any region).
    de = HTMXObjects._with_page_lang(() -> thread(), "de-DE")
    @test stamped(de) == as_dict(live_thread_texts(:de))
    @test stamped(de)["start"] == "Anfang des Verlaufs" && stamped(de)["unseen"] == "↓ {count} neue"
    @test stamped(de)["older_loading"] == "Ältere Nachrichten werden geladen…"
    # the attribute is the only difference
    @test replace(de, r" data-htmxo-thread-texts=\"[^\"]*\"" => "") == en
    # `texts=` wins over the page's language, English included.
    @test HTMXObjects._with_page_lang(() -> thread(; texts=live_thread_texts(:en)), "de") == en
    mine = live_thread_texts(:de; start="Anfang des Chats", unseen="{count} ungelesen ↓")
    got = stamped(thread(; texts=mine))
    @test got["start"] == "Anfang des Chats" && got["unseen"] == "{count} ungelesen ↓" && got["latest"] == "↓ Neueste"
    @test stamped(thread(; texts=live_thread_texts(; start="Beginning"))) == merge(as_dict(live_thread_texts()), Dict("start" => "Beginning"))

    @test live_thread_texts().older_failed == "Loading earlier messages failed: {error}"
    @test live_thread_texts(:de).network_error == "Netzwerkfehler"
    @test_throws ArgumentError live_thread_texts(:fr)
    @test_throws ArgumentError live_thread_texts(; begin_="x")
    @test_throws ArgumentError live_thread_texts(; unseen="{n} new")
    @test_throws ArgumentError live_thread_texts(; start="{count}")
    @test_throws ArgumentError live_thread_texts(; refresh_failed="{count} failed")
    @test_throws ArgumentError live_thread(items; texts=card_deck_texts())
    @test_throws ArgumentError live_thread(items; texts=(; start="x"))

    # The runtime's English words are `live_thread_texts()`, written in once.
    script = repr("text/html", live_thread_script())
    @test occursin("var TEXTS = " * JSON.json(live_thread_texts()) * ";", script)
    @test !occursin("HTMXO_THREAD_TEXTS", script)
    for word in ("Earlier messages", "Loading earlier messages…", "Start of thread", "↓ Latest",
                 "request timed out", "network error", "Refreshing failed")
        @test length(findall(word, script)) == 1
    end
end

@testitem "a German live_thread shows its own words in German in a browser, an English one in English" setup=[ChromeDump] tags=[:browser, :integration] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        free_port() = let s = listen(Sockets.localhost, 0)
            p = Int(getsockname(s)[2]); close(s); p
        end
        closed = free_port()   # nothing listens here: a request to it fails as a network error
        item(key) = key => h.div(key; style="height: 100px")
        de = live_thread_texts(:de)
        thread(id, keys; kw...) = live_thread(item.(keys); id, height="300px", poll=nothing, kw...)
        threads = (
            # older paging to its start: the idle, loading and start labels
            thread("destart", ["a"]; texts=de, older_url="/older", cursor="c"),
            # the positive control: no texts, no page language, English
            thread("enstart", ["a"]; older_url="/older", cursor="c"),
            # an older page the server fails: the retry label, the status line, its disclosure
            thread("defail", ["a"]; texts=de, older_url="/fail", cursor="c"),
            # an older page no server answers: the network error
            thread("denet", ["a"]; texts=de, older_url="http://127.0.0.1:$closed/older", cursor="c"),
            # a refresh the server fails
            thread("derefresh", ["a"]; texts=de, tail_url="/fail", since="a", version="1"),
            # the pill, German from the page's language rather than texts=
            HTMXObjects._with_page_lang("de") do
                thread("depill", ["i$k" for k in 1:10]; tail_url="/tail", since="i10", version="1")
            end,
        )
        # Attached while the page parses, before the runtime starts the threads,
        # so it sees every label `destart` shows on its way to the start.
        recorder = h.script(Raw(raw"""
        (function () {
          const o = document.querySelector('#destart .htmxo-thread-older'), seen = window.__olderSeen = [];
          new MutationObserver(() => seen.push(o.textContent)).observe(o, { childList: true, subtree: true, characterData: true });
        })();
        """))
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          const R = document.body.dataset, wait = ms => new Promise(r => setTimeout(r, ms));
          const until = async (f, n = 400) => { for (let i = 0; i < n && !f(); i++) await wait(25); return f(); };
          const root = id => document.getElementById(id), st = id => root(id).__htmxoThread;
          const older = id => root(id).querySelector('.htmxo-thread-older').textContent;
          const status = id => root(id).querySelector('.htmxo-thread-status');
          // `data-stage` names the step a run cut off by the budget was in.
          R.stage = 'startup';
          await until(() => ['destart', 'enstart', 'defail', 'denet', 'derefresh', 'depill'].every(id => st(id)));
          R.stage = 'older';
          // The observer starts an older page when the control comes near; on a
          // loaded machine its first callback can come late, so start any page
          // not yet started the way a reader does, with a click on the control.
          for (const id of ['destart', 'enstart', 'defail', 'denet']) {
            const s = st(id), b = root(id).querySelector('.htmxo-thread-older [role="button"]');
            if (b && !s.olderBusy && !s.olderDone && !s.olderError) b.click();
          }
          await until(() => st('destart').olderDone && st('enstart').olderDone && st('defail').olderError && st('denet').olderError, 1200);
          for (const id of ['destart', 'enstart', 'defail', 'denet']) R[id + 'Older'] = older(id);
          R.destartSeen = window.__olderSeen.join(' | ');
          R.defailStatus = status('defail').firstChild ? status('defail').firstChild.textContent : 'none';
          const summary = status('defail').querySelector('summary');
          R.defailSummary = summary ? summary.textContent : 'none';
          R.denetStatus = status('denet').textContent;
          R.stage = 'refresh';
          window.htmxoThread.refresh('#derefresh');
          await until(() => !status('derefresh').hidden);
          R.derefreshStatus = status('derefresh').firstChild ? status('derefresh').firstChild.textContent : 'none';
          R.stage = 'pill';
          const p = root('depill'), sc = p.querySelector('.htmxo-thread-scroll'), pill = p.querySelector('.htmxo-thread-new');
          sc.scrollTop = 0;
          sc.dispatchEvent(new Event('scroll'));
          R.depillLatest = pill.hidden ? 'hidden' : pill.textContent;
          window.htmxoThread.refresh('#depill', { bottom: false });
          await until(() => p.querySelectorAll('.htmxo-thread-item').length === 12);
          R.depillUnseen = pill.hidden ? 'hidden' : pill.textContent;
          R.stage = 'done';
        });
        """))
        page = repr("text/html", htmx(h.main(threads..., recorder, driver);
            htmx_version=nothing, hyperscript_version=nothing, sse_version=nothing,
            ws_version=nothing, preload_version=nothing, pico_version=nothing,
            feedback=false, overlay=false))
        older = repr("text/html", live_thread_page([item("o1")]; cursor=nothing))
        tail = repr("text/html", live_thread_tail(item.(["n1", "n2"]); since="n2", version="2"))
        port = free_port()
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            html(body) = HTTP.Response(200, ["Content-Type" => "text/html"], body)
            path == "/" && return html(page)
            path == "/older" && return html(older)
            path == "/tail" && return html(tail)
            path == "/fail" && return HTTP.Response(500, ["Content-Type" => "text/html"], "<p>kaputt</p>")
            HTTP.Response(404)
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=60000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`; timeout=180)
            end
            read_attr(name) = let m = match(Regex("data-$name=\"([^\"]*)\""), dom)
                isnothing(m) ? "missing" : m[1]
            end
            @test read_attr("stage") == "done"
            # idle, loading, start: every label of the control, in German
            @test read_attr("destart-seen") == "Ältere Nachrichten | Ältere Nachrichten werden geladen… | Anfang des Verlaufs"
            @test read_attr("destart-older") == "Anfang des Verlaufs"
            @test read_attr("enstart-older") == "Start of thread"
            @test read_attr("defail-older") == "Ältere Nachrichten konnten nicht geladen werden – erneut versuchen"
            @test read_attr("defail-status") == "Laden älterer Nachrichten fehlgeschlagen: HTTP 500"
            @test read_attr("defail-summary") == "Antwort"
            @test read_attr("denet-status") == "Laden älterer Nachrichten fehlgeschlagen: Netzwerkfehler"
            @test read_attr("derefresh-status") == "Aktualisieren fehlgeschlagen: HTTP 500"
            @test read_attr("depill-latest") == "↓ Neueste"
            @test read_attr("depill-unseen") == "↓ 2 neue"
        finally
            close(server)
        end
    end
end
