# Bounded one-shot headless Chrome for the browser test items. A page that
# never finishes (a stalled host, a request nobody answers) fails the item
# within `timeout` seconds, naming the URL, instead of hanging the run.
# Included by the `ChromeDump` test module (test/chrome_bounds.jl) and by
# fixture modules that drive Chrome themselves.
export dump_dom

"""
    dump_dom(cmd::Cmd; timeout=60) -> String

Run a headless-Chrome `--dump-dom` command and return its standard output.
Throws when Chrome does not exit within `timeout` seconds (after stopping it)
or exits unsuccessfully.
"""
function dump_dom(cmd::Cmd; timeout::Real=60)
    out = tempname()
    started = time()
    process = run(pipeline(cmd; stdout=out, stderr=devnull); wait=false)
    try
        finished = timedwait(() -> process_exited(process), timeout; pollint=0.05) === :ok
        finished || error(string("headless Chrome did not finish ", last(cmd.exec), " within ",
            round(time() - started; digits=1), " s (timeout ", timeout, " s)"))
        success(process) || error(string("headless Chrome exited with status ",
            process.exitcode, " for ", last(cmd.exec)))
        read(out, String)
    finally
        if !process_exited(process)
            kill(process)
            timedwait(() -> process_exited(process), 5; pollint=0.05) === :ok ||
                kill(process, Base.SIGKILL)
            wait(process)
        end
        rm(out; force=true)
    end
end
