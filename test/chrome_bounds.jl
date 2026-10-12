@testmodule ChromeDump begin
    include(joinpath(@__DIR__, "support", "chrome.jl"))
end

@testitem "browser items bound their headless Chrome runs" setup=[ChromeDump] tags=[:unit, :browser] begin
    using Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        flags = `--headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --dump-dom`
        # A listener that never accepts or answers: the page never loads.
        stalled = listen(Sockets.localhost, 0)
        port = Int(getsockname(stalled)[2])
        url = "http://127.0.0.1:$port/"
        started = time()
        failure = try
            mktempdir() do profile
                dump_dom(`$chrome $flags --user-data-dir=$profile $url`; timeout=5)
            end
            nothing
        catch err
            err
        finally
            close(stalled)
        end
        elapsed = time() - started
        @test failure isa ErrorException
        message = sprint(showerror, failure)
        @test contains(message, "did not finish $url within") && contains(message, "(timeout 5 s)")
        @test elapsed < 30
        # A page that finishes still returns its DOM.
        dom = mktempdir() do dir
            page = joinpath(dir, "page.html")
            write(page, "<p id=\"probe\">loaded</p>")
            dump_dom(`$chrome $flags --user-data-dir=$(joinpath(dir, "profile")) file://$page`)
        end
        @test contains(dom, "<p id=\"probe\">loaded</p>")
    end
end
