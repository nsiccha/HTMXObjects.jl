using TestItemRunner

# Caller faults (4xx) are answered, not recorded: no error log or `@error`
# line, no `X-HTMXO-Error-Id`, no `__on_error__` (user decision `1danmww`). A
# late poll of a mutation whose result the server no longer holds is one: a KB
# tab's restored poller polled a spent token after a deploy and its 410 woke
# the error triage (snag spent-mutation-p-80878aaf). A server fault in the same
# app is the control: it is still recorded.
@testitem "caller faults are answered, not recorded as errors" tags=[:unit, :server] begin
    using HTMXObjects, HTTP, Logging
    import HTMXObjects: h

    hooked = String[]
    @htmx struct CallerFaultApp
        __on_error__ = (err, uid, path) -> push!(hooked, uid)
        @get fault_needs(; n::Int) = h.p("n=$n")
        @get fault_boom() = error("server fault")
        @post fault_save() = h.p("saved")
    end
    route!(CallerFaultApp())
    hx = ["HX-Request" => "true"]
    old_dir = HTMXObjects.ERROR_DIR[]
    mktempdir() do dir
        HTMXObjects.ERROR_DIR[] = dir
        try
            missing_n = @test_logs min_level=Logging.Error dispatch(:GET, "/fault_needs")
            @test missing_n.status == 400
            @test contains(String(missing_n.body), "Bad Request")
            @test !HTTP.hasheader(missing_n, "X-HTMXO-Error-Id")
            fragment = @test_logs min_level=Logging.Error dispatch(:GET, "/fault_needs"; headers=hx)
            @test fragment.status == 200
            @test contains(String(fragment.body), "aria-invalid=\"true\"")
            @test !HTTP.hasheader(fragment, "X-HTMXO-Error-Id")
            spent = "/fault_save?__htmxo_poll=1&__htmxo_operation=$(repeat("0", 64))&__htmxo_verb=POST"
            gone = @test_logs min_level=Logging.Error dispatch(:GET, spent; headers=hx)
            @test gone.status == 286
            @test contains(String(gone.body), "Result unavailable")
            @test !HTTP.hasheader(gone, "X-HTMXO-Error-Id")
            @test dispatch(:GET, spent).status == 410
            @test isempty(readdir(dir))
            @test isempty(hooked)

            boom = dispatch(:GET, "/fault_boom")
            @test boom.status == 500
            uid = HTTP.header(boom, "X-HTMXO-Error-Id", "")
            @test !isempty(uid)
            @test readdir(dir) == ["$uid.log"]
            @test hooked == [uid]
        finally
            HTMXObjects.ERROR_DIR[] = old_dir
        end
    end
    # A caller fault whose type names no title reads under a plain one, not
    # the server-fault page that points at an error id.
    refused = repr("text/html", HTMXObjects._invoke_error_handler(
        nothing, HTMXObjects._ResourceRefused(409, "Conflict"), nothing, nothing))
    @test contains(refused, "Request refused")
    @test contains(refused, "resource operation refused (409): Conflict")
    @test !contains(refused, "Error ID")
end
