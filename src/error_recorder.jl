"""
    ErrorRecorder(; repo_root, state_dir, label="App", urls_env="", max_urls=1000)

Retain bounded error metadata and failing URLs for an application’s `__on_error__` hook.

Opt-in capture metadata and a bounded failing-URL index for an application's
`__on_error__` hook. Keep one recorder per app and use:

```julia
__on_error__ = (err, uid, path) -> record_error!(recorder, uid, path, __req__)
```

Each log gains the repository's current HEAD, clean/dirty status and UTC capture
time. This describes the files **at capture time**, not the code loaded when the
server started. Git failures appear explicitly in the metadata.

`state_dir/failing-urls.tsv` retains the most recently seen `max_urls` distinct
URLs, oldest first. Repeated URLs retain `first_seen` and refresh `last_seen`,
`verb` and `log`. Set `urls_env` to an environment-variable name to allow a
deployment to override the index path. This is a process-local writer: share
the recorder between tasks, and give separate processes separate state paths.
"""
struct ErrorRecorder
    repo_root::String
    state_dir::String
    label::String
    urls_env::String
    max_urls::Int
    lock::ReentrantLock
    function ErrorRecorder(; repo_root, state_dir, label="App", urls_env="", max_urls=1000)
        max_urls > 0 || throw(ArgumentError("max_urls must be positive"))
        new(abspath(repo_root), abspath(state_dir), String(label), String(urls_env),
            max_urls, ReentrantLock())
    end
end

function _capture_git(rec::ErrorRecorder, args...)
    try
        readchomp(pipeline(`git -C $(rec.repo_root) $args`; stderr=devnull))
    catch err
        "<git unavailable: $(sprint(showerror, err))>"
    end
end

_capture_time() = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS.sss") * "Z"
_capture_field(value) = replace(string(value), '\t' => "%09", '\r' => "%0D", '\n' => "%0A")
_capture_fields(line) = Dict{String,String}(key => value
    for (key, value) in (split(field, '='; limit=2) for field in split(line, '\t')))

function _record_failing_url(rec::ErrorRecorder, uid, req, timestamp)
    path = isempty(rec.urls_env) ? joinpath(rec.state_dir, "failing-urls.tsv") :
        get(ENV, rec.urls_env, joinpath(rec.state_dir, "failing-urls.tsv"))
    url = _capture_field(req.target)
    # Rewriting a bounded index keeps duplicate updates and retention in one
    # atomic replacement. A failed write leaves the previous index intact.
    rows = isfile(path) ? map(_capture_fields, readlines(path)) : Dict{String,String}[]
    i = findfirst(row -> row["url"] == url, rows)
    row = isnothing(i) ? Dict("url" => url, "first_seen" => timestamp) : popat!(rows, i)
    merge!(row, Dict("verb" => _capture_field(req.method), "log" => _capture_field(uid),
        "last_seen" => timestamp))
    push!(rows, row)
    mkpath(dirname(path))
    tmp, io = mktemp(dirname(path))
    try
        for r in @view rows[max(1, length(rows) - rec.max_urls + 1):end]
            println(io, join((key * "=" * r[key] for key in
                ("url", "verb", "log", "first_seen", "last_seen")), '\t'))
        end
        close(io)
        _rename_over!(tmp, path)
    finally
        isopen(io) && close(io)
        isfile(tmp) && rm(tmp)
    end
    nothing
end

"""
    record_error!(recorder::ErrorRecorder, uid, log_path, req)

Append capture metadata to an already recorded error, then update the recorder's
failing-URL index from the `HTTP.Request`. Pass `nothing` as `req` to append
metadata only. The error log and response remain owned by HTMXObjects; this
side-effect hook neither records another error nor changes the response.
Filesystem failures propagate to the framework's hook-failure logger.
"""
function record_error!(rec::ErrorRecorder, uid, log_path, req)
    lock(rec.lock) do
        head = _capture_git(rec, "rev-parse", "HEAD")
        status = _capture_git(rec, "status", "--porcelain")
        state = startswith(status, "<git unavailable:") ? status : isempty(status) ? "clean" : "dirty"
        timestamp = _capture_time()
        open(log_path, "a") do io
            println(io, "\n--- ", rec.label, " capture metadata ---")
            println(io, "git_head:     ", head)
            println(io, "worktree:     ", state)
            if state == "dirty"
                for line in split(status, '\n')
                    println(io, "  ", line)
                end
            end
            println(io, "capture_time: ", timestamp)
        end
        isnothing(req) || _record_failing_url(rec, uid, req, timestamp)
    end
    nothing
end
