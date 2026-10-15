@testmodule RedirectFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h
    export RedirectApp, redirect_gate, hx_get, body_text, running, poll_url, settle_response

    const redirect_gate = Ref(Base.Event())

    @htmx struct RedirectApp
        __page__(content) = htmx(h.main(content))
        "Old address of the review page"
        @direct @get transactions() = redirect_to(__req__, __self__/"transaction_review_all")
        "Old address that names its own year"
        @get legacy() = redirect_to(__req__, __self__/"transaction_review_all?year=1999")
        "Old address that drops the query"
        @get bare() = redirect_to(__req__, __self__/"transaction_review_all"; query=false)
        "Slow old address"
        @get slow_moved() = (wait(redirect_gate[]);
            redirect_to(__req__, __self__/"transaction_review_all"))
        "Review"
        @get transaction_review_all(; year::Int=2024) =
            h.p("review $year hx=$(is_htmx(__req__))"; class="review")
    end

    const hx = ["HX-Request" => "true"]
    hx_get(target; headers=[]) = dispatch(:GET, target; headers=[hx; headers])
    body_text(response) = String(HTMXObjects._message_body_bytes(response))
    running(body) = contains(body, "hx-trigger=\"every ")
    function poll_url(body)
        found = match(Regex("hx-get=\"([^\"]*__htmxo_poll=1[^\"]*)\""), body)
        found === nothing && error("no poll URL in response:\n" * body)
        replace(only(found.captures), "&amp;" => "&")
    end
    function settle_response(target; headers=[])
        for _ in 1:200
            response = hx_get(target; headers)
            running(body_text(response)) || return response
            sleep(0.025)
        end
        error("operation never settled: $target")
    end
end

@testitem "redirect_to: status, Location and query carry-over" tags=[:unit] begin
    using HTMXObjects, HTTP
    req(target) = HTTP.Request("GET", target)
    moved = redirect_to(req("/transactions?year=2025&plain=1"), "/p/App/review")
    @test moved.status == 303
    @test HTTP.header(moved, "Location") == "/p/App/review?year=2025&plain=1"
    @test HTTP.header(moved, "Content-Type") == "text/plain; charset=utf-8"
    @test String(HTMXObjects._message_body_bytes(moved)) == "Moved to /p/App/review?year=2025&plain=1\n"
    # No query: the location as given.
    @test HTTP.header(redirect_to(req("/old"), "/new"), "Location") == "/new"
    # The location's own parameters win; encoding is kept byte for byte.
    @test HTTP.header(redirect_to(req("/old?year=2025&q=a%20b&tag=x&tag=y"), "/new?year=1999"),
                      "Location") == "/new?year=1999&q=a%20b&tag=x&tag=y"
    @test HTTP.header(redirect_to(req("/old?a=1"), "/new?"), "Location") == "/new?a=1"
    @test HTTP.header(redirect_to(req("/old?a=1"), "/new?b=2&"), "Location") == "/new?b=2&a=1"
    # Names compare decoded.
    @test HTTP.header(redirect_to(req("/old?my%20key=1&x=2"), "/new?my+key=0"),
                      "Location") == "/new?my+key=0&x=2"
    # A fragment stays last.
    @test HTTP.header(redirect_to(req("/old?a=1"), "/new#top"), "Location") == "/new?a=1#top"
    @test HTTP.header(redirect_to(req("/old?a=1"), "/new?b=2#top"), "Location") == "/new?b=2&a=1#top"
    @test HTTP.header(redirect_to(req("/old?a=1"), "/new"; query=false), "Location") == "/new"
    @test HTTP.header(redirect_to(req("/old?a=1"), "https://example.org/x"), "Location") ==
          "https://example.org/x?a=1"
    for status in (301, 302, 303, 307, 308)
        @test redirect_to(req("/old"), "/new"; status).status == status
    end
    @test_throws ArgumentError redirect_to(req("/old"), "/new"; status=200)
    @test_throws ArgumentError redirect_to(req("/old"), "/new"; status=304)
    @test_throws ArgumentError redirect_to(req("/old"), "")
    # A header value never carries a line break.
    @test_throws ArgumentError redirect_to(req("/old"), "/new\r\nSet-Cookie: x=1")
end

@testitem "a moved route redirects every request kind to its prefixed address" setup=[RedirectFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP
    route!(RedirectApp())
    # This route declares inline transport so a cold HTML navigation still
    # returns the redirect status instead of an :auto page-load shell.
    direct = dispatch(:GET, "/transactions?year=2025"; headers=["Accept" => "text/html"])
    @test direct.status == 303
    @test HTTP.header(direct, "Location") == "/transaction_review_all?year=2025"
    # No `__page__` wrap around the redirect body.
    @test !contains(body_text(direct), "<html")
    # Behind the KB's `/p/<App>` proxy the location keeps the mount prefix.
    proxied = dispatch(:GET, "/transactions?year=2025";
        headers=["X-Forwarded-Prefix" => "/p/Invoices"])
    @test proxied.status == 303
    @test HTTP.header(proxied, "Location") == "/p/Invoices/transaction_review_all?year=2025"
    # An htmx request gets the same redirect; its XHR follows it.
    swapped = hx_get("/transactions?year=2025"; headers=["X-Forwarded-Prefix" => "/p/Invoices/"])
    @test swapped.status == 303
    @test HTTP.header(swapped, "Location") == "/p/Invoices/transaction_review_all?year=2025"
    @test !HTTP.hasheader(swapped, "HX-Location") && !HTTP.hasheader(swapped, "HX-Redirect")
    # Markdown peers keep `?plain`.
    plain = dispatch(:GET, "/transactions?plain=1&year=2025")
    @test plain.status == 303
    @test HTTP.header(plain, "Location") == "/transaction_review_all?plain=1&year=2025"
    @test HTTP.header(dispatch(:GET, "/legacy?year=2025&x=1"), "Location") ==
          "/transaction_review_all?year=1999&x=1"
    @test HTTP.header(dispatch(:GET, "/bare?year=2025"), "Location") == "/transaction_review_all"
    # The destination answers the carried query.
    landed = hx_get(HTTP.header(direct, "Location"))
    @test landed.status == 200
    @test contains(body_text(landed), "review 2025 hx=true")
end

@testitem "a redirect reaching an auto poller navigates with HX-Redirect" setup=[RedirectFixtures] tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP, Treebars
    import HTMXObjects: _clear_operation_polls!
    _clear_operation_polls!()
    route!(RedirectApp())
    redirect_gate[] = Base.Event()
    # Behind a path-stripping proxy: the poll URL carries the external prefix.
    proxy = ["X-Forwarded-Prefix" => "/p/Invoices"]
    started = hx_get("/slow_moved?year=2025"; headers=proxy)
    body = body_text(started)
    @test running(body)
    target = poll_url(body)
    @test startswith(target, "/p/Invoices/slow_moved?")
    notify(redirect_gate[])
    terminal = settle_response(chopprefix(target, "/p/Invoices"); headers=proxy)
    @test terminal.status == 286
    @test HTTP.header(terminal, "HX-Redirect") == "/p/Invoices/transaction_review_all?year=2025"
    @test !HTTP.hasheader(terminal, "Location")
    @test HTTP.header(terminal, "Content-Type") == "text/html; charset=utf-8"
    text = body_text(terminal)
    @test contains(text, "data-htmxo-auto-terminal")
    @test contains(text, "href=\"/p/Invoices/transaction_review_all?year=2025\"")
    @test !contains(text, "aria-invalid")
    # Any other non-2xx answer keeps its error article.
    failed = HTMXObjects._operation_finalized_terminal(HTTP.Response(409, "nope"))
    @test contains(body_text(failed), "aria-invalid") && !HTTP.hasheader(failed, "HX-Redirect")
    # A redirect status without a Location is not a redirect.
    @test HTMXObjects._redirect_location(HTTP.Response(303)) === nothing
end

@testitem "the shell carries the redirect history runtime" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    page = repr("text/html", htmx(h.p("x")))
    @test count("window.htmxoRedirectHistory = true", page) == 1
    @test contains(page, "htmx:beforeHistoryUpdate")
    @test contains(repr("text/html", redirect_history_script()), "window.htmxoRedirectHistory")
end

@testitem "moved routes in a real browser" setup=[RedirectFixtures, ChromeDump] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        route!(RedirectApp())
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        requests = String[]
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          const checks = [];
          const check = (name, ok) => checks.push([name, Boolean(ok)]);
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          const wait = async cond => { for (let n = 0; n < 200 && !cond(); n++) await sleep(20); return cond(); };
          const here = () => location.pathname + location.search;
          const content = () => document.getElementById('content').textContent;
          const click = async (id, expected) => {
            document.getElementById(id).click();
            await wait(() => content().includes(expected));
            await sleep(50);
          };
          try {
            // A lazily loaded fragment swaps in place and records nothing.
            await wait(() => document.querySelector('#lazy-slot .review'));
            check('lazy-swapped', document.querySelector('#lazy-slot .review').textContent === 'review 2027 hx=true');
            check('lazy-no-history', here() === '/');
            await click('nav', 'review 2025');
            check('nav-content', content() === 'review 2025 hx=true');
            check('nav-history', here() === '/transaction_review_all?year=2025');
            await click('nav-bare', 'review 2026');
            check('bare-content', content() === 'review 2026 hx=true');
            check('bare-history', here() === '/transaction_review_all');
            await click('other', 'review 2028');
            check('other-history', here() === '/elsewhere');
            await click('follow', 'review 2029');
            check('follow-history', here() === '/transaction_review_all?year=2029');
            const r = await fetch('/transactions?year=2030');
            check('fetch-follows', r.redirected && new URL(r.url).pathname === '/transaction_review_all' &&
                  (await r.text()).includes('review 2030'));
          } catch (err) {
            check('error: ' + String(err), false);
          }
          const result = document.createElement('pre'); result.id = 'checks';
          result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
          document.body.appendChild(result);
        });
        """))
        page = repr("text/html", htmx(h.main(
            h.a("Nav"; id="nav", href="#", hx_get="/transactions?year=2025",
                hx_target="#content", hx_push_url="/transactions?year=2025"),
            h.a("Bare"; id="nav-bare", href="#", hx_get="/transactions",
                hx_vals="{\"year\": \"2026\"}", hx_target="#content",
                hx_push_url="/transactions"),
            h.a("Other"; id="other", href="#", hx_get="/transactions?year=2028",
                hx_target="#content", hx_push_url="/elsewhere"),
            h.a("Follow"; id="follow", href="#", hx_get="/transactions?year=2029",
                hx_target="#content", hx_push_url="true"),
            h.div(; id="content"),
            h.div(h.div(; hx_get="/transactions?year=2027", hx_trigger="load",
                        hx_swap="outerHTML"); id="lazy-slot"),
            driver);
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, compose=false, overlay=false))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/favicon.ico" && return HTTP.Response(204)
            push!(requests, string(req.method, " ", req.target, " hx=", HTTP.header(req, "HX-Request", "")))
            dispatch(req.method, String(req.target); headers=collect(req.headers))
        end
        try
            dom = mktempdir() do profile
                dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=20000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/`)
            end
            checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
            @test !isnothing(checks)
            if !isnothing(checks)
                lines = split(checks[1], '\n')
                for line in lines
                    @test endswith(line, ":true")
                end
                @test length(lines) == 9
                all(endswith(":true"), lines) || @info "Browser requests" requests=join(requests, "\n")
            end
            # htmx's followed request keeps `HX-Request`, so the destination
            # answers a fragment.
            @test "GET /transaction_review_all?year=2025 hx=true" in requests
        finally
            close(server)
        end
    end
end
