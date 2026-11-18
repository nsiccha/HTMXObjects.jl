# --- Development mode: `serve(; dev=true)` --------------------------------------
#
# A saved source edit shows in the open page without a restart (user decision
# `14xfxqy`, todo `074575c`). Measured in the test's fresh process: a request
# with nothing to apply costs about 7 ms, the first applied edit about 13 s
# (Revise compiles itself), the next one about 5 s (the edited package is
# re-read and the edited struct's routes recompile). Development only: deployed
# apps never load Revise (user rules `no_revise`, `revise_only_if_reliable`).
#
# - Before every request, `_dev_rescan!` looks for changed source files of the
#   packages Revise tracks under the dev roots, and applies a changed package
#   with `Revise.revise(mod; force=false)`, which re-reads all of its files.
#   That is the method dev-reference §13.1 measured applying 70 of 70 agent
#   edits; Revise's file watcher, which `serve(; revise=:lazy|:eager)` waits
#   on, missed 26 of 70. A file counts as changed when its size or mtime
#   changed (checked on every request, about 0.5 ms for HTMXObjects' own
#   source), or its content did (hashed at most once a second, about 7 ms), so
#   an edit that keeps both size and mtime is still applied within a second.
# - The dev roots default to every package Revise tracks that is not installed
#   from a registry (under a depot's `packages/`) or the standard library: the
#   app's own package and every `Pkg.develop`ed one.
# - A full page answer carries `_dev_page_script`: it asks the page's own
#   address with `__htmxo_dev` once a second, which `_dev_middleware` answers
#   before routing with the process's boot id, the source generation and the
#   edits Revise could not apply. When the generation or boot id moved, the
#   page reloads at its scroll position; unapplied edits show as a notice at
#   the bottom of the page. Every non-fragment HTML answer carries the script,
#   error answers included, so a page an edit broke comes back by itself once
#   the edit is fixed or the server restarts. A struct whose fields change
#   cannot be redefined in a running process (Julia 1.10): Revise applies such
#   an edit only in part, so routes of that struct can fail until the restart,
#   and the notice names the edit meanwhile.
# - `_check_revise_errors!` stands aside while dev mode serves: its
#   request-blocking exceptions are the notice's job here.

mutable struct _DevMode
    const lock::ReentrantLock
    const roots::Union{Nothing,Vector{String}}
    const boot::String
    generation::Int
    stats::Dict{String,Tuple{Int64,Float64}}
    hashes::Dict{String,UInt64}
    hashed_at::Float64
    errors::Vector{String}
end

_DevMode(; roots=nothing) = _DevMode(ReentrantLock(),
    roots === nothing ? nothing : [_dev_dir(r) for r in roots],
    string(rand(Random.RandomDevice(), UInt64); base=16), 0,
    Dict{String,Tuple{Int64,Float64}}(), Dict{String,UInt64}(), 0.0, String[])

# The dev mode `serve` runs, or `nothing`.
const _DEV_MODE = Ref{Union{Nothing,_DevMode}}(nothing)

const _DEV_HASH_INTERVAL = 1.0
const _DEV_FLAG = "__htmxo_dev"

_dev_dir(path::AbstractString) = rstrip(abspath(path), '/') * "/"

function _dev_registry_root(base::AbstractString)
    dir = _dev_dir(base)
    startswith(dir, _dev_dir(Sys.STDLIB)) && return true
    any(depot -> startswith(dir, _dev_dir(joinpath(depot, "packages"))), DEPOT_PATH)
end

_dev_in_roots(base::AbstractString, ::Nothing) = !_dev_registry_root(base)
_dev_in_roots(base::AbstractString, roots::Vector{String}) =
    any(root -> startswith(_dev_dir(base), root), roots)

# `(module, files)` for each package Revise tracks under the dev roots,
# extensions included (each has its own record, rooted at its parent's
# checkout).
function _dev_tracked(rev, roots)
    out = Tuple{Module,Vector{String}}[]
    pkgdatas = getfield(rev, :pkgdatas)
    lock(getfield(rev, :revise_lock)) do
        for (id, pkgdata) in pkgdatas
            mod = get(Base.loaded_modules, id, nothing)
            mod isa Module || continue
            base = String(Base.invokelatest(getfield(rev, :basedir), pkgdata))
            isempty(base) && continue
            _dev_in_roots(base, roots) || continue
            files = [joinpath(base, f) for f in Base.invokelatest(getfield(rev, :srcfiles), pkgdata)]
            push!(out, (mod, files))
        end
    end
    out
end

_dev_hash(file::AbstractString) = isfile(file) ? hash(read(file)) : UInt64(0)

function _dev_stat(file::AbstractString)
    st = stat(file)
    (Int64(st.size), Float64(st.mtime))
end

# Whether `file` changed since the last scan; records what it saw. A file seen
# for the first time is the baseline: Revise parsed it when its package loaded.
function _dev_changed!(dev::_DevMode, file::String, hash_now::Bool)
    key = _dev_stat(file)
    old = get(dev.stats, file, nothing)
    dev.stats[file] = key
    if old === nothing
        dev.hashes[file] = _dev_hash(file)
        return false
    elseif old != key
        dev.hashes[file] = _dev_hash(file)
        return true
    elseif hash_now
        h = _dev_hash(file)
        changed = get(dev.hashes, file, h) != h
        dev.hashes[file] = h
        return changed
    end
    false
end

"""
    _dev_rescan!(dev) -> Bool

Apply the source edits made since the last scan to the packages under the dev
roots; `true` when it applied (or tried to apply) any. Serialized: concurrent
requests wait for one scan instead of revising twice.
"""
function _dev_rescan!(dev::_DevMode; force_hash::Bool=false)
    rev = _revise_module()
    rev === nothing && return false
    lock(dev.lock) do
        now = time()
        hash_now = force_hash || now - dev.hashed_at >= _DEV_HASH_INTERVAL
        changed = Module[]
        for (mod, files) in _dev_tracked(rev, dev.roots)
            any_changed = false
            for file in files
                _dev_changed!(dev, file, hash_now) && (any_changed = true)
            end
            any_changed && push!(changed, mod)
        end
        hash_now && (dev.hashed_at = now)
        isempty(changed) && return false
        failures = String[]
        for mod in changed
            try
                Base.invokelatest(getfield(rev, :revise), mod; force=false)
            catch err
                push!(failures, string(mod, ": ", _dev_error_line(err)))
            end
        end
        dev.errors = vcat(failures, _dev_queue_errors(rev, dev.roots))
        dev.generation += 1
        isempty(dev.errors) ?
            (@info "Development mode applied edits to $(join(changed, ", "))" _group=:dev) :
            (@warn "Development mode could not apply every edit; restart the server to load them" errors=dev.errors _group=:dev)
        true
    end
end

_dev_error_line(err) = let text = try sprint(showerror, err) catch; string(typeof(err)) end
    line = strip(first(split(text, '\n')))
    length(line) > 400 ? first(line, 399) * "…" : String(line)
end

# The edits Revise queued but could not apply, under the dev roots.
function _dev_queue_errors(rev, roots)
    qe = try getfield(rev, :queue_errors) catch; return String[] end
    out = String[]
    lock(getfield(rev, :revise_lock)) do
        for (key, val) in qe
            pkgdata, file = key
            base = String(Base.invokelatest(getfield(rev, :basedir), pkgdata))
            _dev_in_roots(base, roots) || continue
            err, _ = _qe_err_bt(val)
            push!(out, string(joinpath(base, file), ": ", _dev_error_line(err)))
        end
    end
    sort!(out)
end

# --- the middleware, the status answer and the page script -------------------------

function _dev_middleware(handler, dev::_DevMode)
    function (req::HTTP.Request)
        _runtime_guarded(() -> _dev_rescan!(dev), "development rescan")
        _dev_poll(req) && return _dev_status_response(dev)
        response = Base.invokelatest(handler, req)
        response isa HTTP.Response || return response
        something(_runtime_guarded(() -> _dev_page_response(req, response, dev),
                                   "development page script"), response)
    end
end

_dev_poll(req::HTTP.Request) = req.method == "GET" && occursin(_DEV_FLAG, req.target) &&
    haskey(something(_runtime_guarded(() -> queryparams(req), "development flag"),
                     Dict{String,String}()), _DEV_FLAG)

function _dev_status_response(dev::_DevMode)
    status = lock(dev.lock) do
        (; boot=dev.boot, generation=dev.generation, errors=copy(dev.errors))
    end
    HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8",
                        "Cache-Control" => "no-store"], JSON.json(status))
end

# Any status: an error page must come back by itself too. A navigation to a
# bare fragment (no `<body>` tag) gets the script appended; browsers place it
# in the body.
function _dev_page_response(req::HTTP.Request, response::HTTP.Response, dev::_DevMode)
    _hx_partial_swap(req) && return response
    occursin("text/html", lowercase(HTTP.header(response, "Content-Type", ""))) || return response
    script = lock(() -> _dev_page_script(dev.boot, dev.generation), dev.lock)
    body = _inject_after_body(response.body, script)
    if body === nothing
        bytes = _buffered_bytes(response.body)
        bytes === nothing && return response
        body = string(String(copy(bytes)), script)
    end
    headers = Pair{String,String}[String(k) => String(v) for (k, v) in response.headers
                                  if lowercase(k) != "content-length"]
    HTTP.Response(response.status, headers, body; request=response.request)
end

# Asks the page's own address (so a path prefix a proxy adds still reaches this
# server) once a second; reloads at the same scroll position when the source
# generation or the process moved; shows the edits that could not be applied.
_dev_page_script(boot::AbstractString, generation::Integer) = """<script data-htmxo-dev>(function(){var boot="$(boot)",gen=$(generation),key="htmxo-dev-scroll:"+location.pathname+location.search,bar=null;try{var y=sessionStorage.getItem(key);if(y!==null){sessionStorage.removeItem(key);addEventListener("load",function(){scrollTo(0,+y)})}}catch(_){}function notice(errors){if(!errors.length){if(bar){bar.remove();bar=null}return}if(!bar){bar=document.createElement("pre");bar.setAttribute("role","status");bar.setAttribute("data-htmxo-dev-notice","");bar.style.cssText="position:fixed;left:0;right:0;bottom:0;z-index:2147483647;max-height:40vh;overflow:auto;margin:0;padding:.5rem 1rem;font:13px/1.4 monospace;white-space:pre-wrap;background:#7f1d1d;color:#fff";document.body.appendChild(bar)}bar.textContent="Development mode: these edits could not be applied; restart the server to load them.\\n"+errors.join("\\n")}function poll(){var u=new URL(location.href);u.searchParams.set("$(_DEV_FLAG)",String(gen));fetch(u,{cache:"no-store",headers:{"Accept":"application/json"}}).then(function(r){return r.json()}).then(function(s){notice(s.errors||[]);if(s.boot!==boot||s.generation!==gen){try{sessionStorage.setItem(key,String(scrollY))}catch(_){}location.reload();return}setTimeout(poll,1000)},function(){setTimeout(poll,1000)})}setTimeout(poll,1000)})();</script>"""

# `serve(; dev, dev_roots)`: the dev mode to install, or `nothing`.
function _dev_mode(dev::Bool, dev_roots, revise)
    dev || (dev_roots === nothing || throw(ArgumentError(
        "`dev_roots` needs `dev=true`")); return nothing)
    revise === nothing || throw(ArgumentError(
        "`dev=true` applies edits itself; leave `revise` unset"))
    _revise_module() === nothing && error(
        "`serve(; dev=true)` needs Revise: run `using Revise` before loading the app.")
    mode = _DevMode(; roots=dev_roots)
    # The baseline: what each file holds now, as its package was loaded with it.
    _dev_rescan!(mode; force_hash=true)
    mode
end
