# `compose_box(...; submit)` chooses the key that sends (snag
# compose-box-subm-c3dcec32): `:enter` keeps Enter-sends / Shift+Enter-new-line,
# `:modifier` makes Enter a new line and Ctrl/Cmd+Enter the send key.

@testitem "compose_box chooses its send key with submit" tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    html(x) = repr("text/html", x)
    # The default adds nothing: a box renders exactly as it did before `submit`.
    @test html(compose_box("message")) ==
        html(h.textarea(""; name="message", rows=1, placeholder="", class="htmxo-compose-textarea"))
    @test html(compose_box("message"; draft_key="k", submit=:enter)) ==
        html(h.textarea(""; name="message", rows=1, placeholder="",
                        class="htmxo-compose-textarea htmxo-compose-draft", data_draft_key="k"))
    @test !contains(html(compose_box("message")), "data-htmxo-submit")
    modifier = html(compose_box("message"; draft_key="k", class="wide", submit=:modifier))
    @test contains(modifier, "data-htmxo-submit=\"modifier\"")
    @test contains(modifier, "data-draft-key=\"k\"")
    @test contains(modifier, "class=\"htmxo-compose-textarea htmxo-compose-draft wide\"")
    @test_throws ArgumentError compose_box("message"; submit=:ctrl)
    @test_throws ArgumentError compose_box("message"; submit="modifier")
    err = try
        compose_box("message"; submit=:ctrl)
    catch e
        e
    end
    @test contains(sprint(showerror, err), ":enter or :modifier")
    @test contains(html(compose_box_script()), "data-htmxo-submit")
end

@testitem "compose boxes send on the key their submit mode names, in a browser" setup=[ChromeDump] tags=[:browser, :integration] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        using HTMXObjects, HTTP, Sockets
        import HTMXObjects: h, Raw

        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        htmx_js = read(HTMXObjects._vendor_file(:htmx), String)
        # Each case presses one key on one box and reads back whether the box
        # took the key (prevented its default, so no new line is typed) and
        # how many requests its form sent. The `enter` box is the positive
        # control: Enter there must send, so a dead harness cannot pass.
        driver = h.script(Raw(raw"""
        window.addEventListener('load', async function () {
          const checks = [];
          const check = (name, ok) => checks.push([name, Boolean(ok)]);
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          const sent = {};
          document.addEventListener('htmx:beforeRequest', e => {
            const id = e.detail.elt && e.detail.elt.id;
            sent[id] = (sent[id] || 0) + 1;
          });
          const press = async (box, form, mods) => {
            const before = sent[form] || 0;
            const ev = new KeyboardEvent('keydown', Object.assign(
              {key: 'Enter', code: 'Enter', bubbles: true, cancelable: true}, mods));
            document.getElementById(box).dispatchEvent(ev);
            await sleep(150);
            return {took: ev.defaultPrevented, sent: (sent[form] || 0) - before};
          };
          const expect = async (name, box, form, mods, sends) => {
            const r = await press(box, form, mods);
            check(name + '-took', r.took === sends);
            check(name + '-sent', r.sent === (sends ? 1 : 0));
          };
          try {
            const bound = id => document.getElementById(id).dataset.htmxoTaBound === '1';
            check('bound', bound('enter-box') && bound('modifier-box') && bound('hand-box'));
            check('markup', document.getElementById('modifier-box').getAttribute('data-htmxo-submit') === 'modifier'
                            && !document.getElementById('enter-box').hasAttribute('data-htmxo-submit'));
            // submit=:enter (the default): unchanged.
            await expect('enter-enter', 'enter-box', 'enter-form', {}, true);
            await expect('enter-shift', 'enter-box', 'enter-form', {shiftKey: true}, false);
            await expect('enter-ctrl', 'enter-box', 'enter-form', {ctrlKey: true}, true);
            // submit=:modifier: Enter is a new line, Ctrl/Cmd+Enter sends.
            await expect('modifier-enter', 'modifier-box', 'modifier-form', {}, false);
            await expect('modifier-shift', 'modifier-box', 'modifier-form', {shiftKey: true}, false);
            await expect('modifier-alt', 'modifier-box', 'modifier-form', {altKey: true}, false);
            await expect('modifier-ctrl', 'modifier-box', 'modifier-form', {ctrlKey: true}, true);
            await expect('modifier-meta', 'modifier-box', 'modifier-form', {metaKey: true}, true);
            await expect('modifier-ctrl-shift', 'modifier-box', 'modifier-form', {ctrlKey: true, shiftKey: true}, true);
            // Another key is never the box's.
            const other = await press('modifier-box', 'modifier-form', {key: 'a', code: 'KeyA', ctrlKey: true});
            check('other-key', !other.took && other.sent === 0);
            // A hand-written box opts in with the attribute.
            await expect('hand-enter', 'hand-box', 'hand-form', {}, false);
            await expect('hand-ctrl', 'hand-box', 'hand-form', {ctrlKey: true}, true);
            // The form's button sends in either mode.
            const before = sent['modifier-form'] || 0;
            document.getElementById('modifier-send').click();
            await sleep(150);
            check('modifier-button', (sent['modifier-form'] || 0) - before === 1);
            // The mode is read on each press: switching it needs no rebind.
            document.getElementById('enter-box').setAttribute('data-htmxo-submit', 'modifier');
            await expect('switched-enter', 'enter-box', 'enter-form', {}, false);
            await expect('switched-ctrl', 'enter-box', 'enter-form', {ctrlKey: true}, true);
          } catch (err) {
            check('error: ' + String(err), false);
          }
          const result = document.createElement('pre'); result.id = 'checks';
          result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
          document.body.appendChild(result);
        });
        """))
        forms = (
            h.form(compose_box("text"; placeholder="Enter sends");
                id="enter-form", class="htmxo-compose-form", hx_post="/send", hx_swap="none"),
            h.form(compose_box("text"; placeholder="Ctrl+Enter sends", submit=:modifier),
                h.button("Send"; type="submit", id="modifier-send");
                id="modifier-form", class="htmxo-compose-form", hx_post="/send", hx_swap="none"),
            h.form(h.textarea(""; name="text", rows=1, class="htmxo-compose-textarea",
                              data_htmxo_submit="modifier");
                id="hand-form", class="htmxo-compose-form", hx_post="/send", hx_swap="none"),
        )
        # `compose_box` renders no id; give each box one for the driver.
        page = repr("text/html", htmx(h.main(forms..., driver);
            assets="/test-assets", sse_version=nothing, ws_version=nothing,
            preload_version=nothing, hyperscript_version=nothing,
            pico_version=nothing, feedback=false, overlay=false))
        page = replace(page, "placeholder=\"Enter sends\"" => "placeholder=\"Enter sends\" id=\"enter-box\"";
                       count=1)
        page = replace(page, "placeholder=\"Ctrl+Enter sends\"" =>
                       "placeholder=\"Ctrl+Enter sends\" id=\"modifier-box\""; count=1)
        page = replace(page, "<textarea name=\"text\" rows=\"1\" class=\"htmxo-compose-textarea\"" =>
                       "<textarea id=\"hand-box\" name=\"text\" rows=\"1\" class=\"htmxo-compose-textarea\""; count=1)
        @test count("id=\"enter-box\"", page) == 1
        @test count("id=\"modifier-box\"", page) == 1
        @test count("id=\"hand-box\"", page) == 1
        @test contains(page, "data-htmxo-submit")
        posts = Ref(0)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            path == "/" && return HTTP.Response(200, ["Content-Type" => "text/html"], page)
            path == "/test-assets/htmx.min.js" &&
                return HTTP.Response(200, ["Content-Type" => "application/javascript"], htmx_js)
            path == "/send" && req.method == "POST" && (posts[] += 1;
                return HTTP.Response(200, ["Content-Type" => "text/html"], ""))
            HTTP.Response(404)
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
                @test length(lines) == 30
                # Sends: enter-enter, enter-ctrl, modifier-ctrl, -meta,
                # -ctrl-shift, hand-ctrl, the button, switched-ctrl.
                @test posts[] == 8
                all(endswith(":true"), lines) && length(lines) == 30 && posts[] == 8 ||
                    @info "compose-keys browser run" checks=join(lines, "\n") posts=posts[]
            end
        finally
            close(server)
        end
    end
end
