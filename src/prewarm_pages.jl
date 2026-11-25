# One selected page and the work it starts. Late handlers retain their own
# closed navigation even after the recorder has moved on to another page.
mutable struct _WarmPages
    key::String
    selected::Union{Nothing,Set{String}}
    tokens::Dict{String,String}  # token => concrete GET address
    caller_faults::Set{String}  # recorded ids of application-declared 4xx answers
    initial_views::Union{Nothing,Dict{String,String}}  # rendered semantic GET => region id
    remaining::Int
    closed::Bool
end

const _warm_pages = Dict{String,_WarmPages}()

function _open_warm_page(selected, fresh_views)
    key = bytes2hex(rand(Random.RandomDevice(), UInt8, 24))
    pages = _WarmPages(key, selected, Dict{String,String}(), Set{String}(),
                       fresh_views ? Dict{String,String}() : nothing, _PRESTART_LIMIT, false)
    lock(() -> _warm_pages[key] = pages, _operation_poll_lock)
    pages
end

# Keep the same concrete URL used by the initially open semantic tab's lazy
# element. Only follow it if that element appears in the served response.
function _warm_initial_view!(req, url, id)
    req isa HTTP.Request || return
    pages = get(req.context, :htmxo_warm_page, nothing)
    (pages === nothing || pages.initial_views === nothing) && return
    startswith(url, "/") && !startswith(url, "//") || return
    lock(_operation_poll_lock) do
        if !pages.closed && length(pages.initial_views) < _PRESTART_LIMIT
            pages.initial_views[url] = id
        end
    end
end

# A page can legitimately display an empty-state panel, e.g. when its app has
# no data installed while building the image. htmx swaps that answer with a
# successful HTTP status, just as it does for an unexpected server exception.
function _note_route_fault!(req, err, uid)
    _runtime_note_error!(req, err, uid)
    pages = req isa HTTP.Request ? get(req.context, :htmxo_warm_page, nothing) : nothing
    if pages !== nothing && unwrap_error(err) isa CallerFault
        lock(_operation_poll_lock) do
            pages.closed || push!(pages.caller_faults, uid)
        end
    end
    nothing
end

_warm_caller_fault(pages::_WarmPages, uid) = lock(_operation_poll_lock) do
    uid in pages.caller_faults
end

function _warm_fragment_allowed!(pages::_WarmPages, route)
    lock(_operation_poll_lock) do
        (pages.closed || pages.remaining == 0) && return false
        pages.selected === nothing || route in pages.selected || return false
        pages.remaining -= 1
        true
    end
end

function _warm_retained!(pages::_WarmPages, entry)
    closed = lock(_operation_poll_lock) do
        if !pages.closed
            pages.tokens[entry.token] = _operation_unmarked_url(entry.request.target)
        end
        pages.closed
    end
    closed && _end_operation_poll!(entry.token, :abandoned)
end

function _close_warm_page!(pages::_WarmPages)
    dropped = _OperationPollEntry[]
    lock(_operation_poll_lock) do
        delete!(_warm_pages, pages.key)
        pages.closed = true
        pages.remaining = 0
        for token in keys(pages.tokens)
            entry = pop!(_operation_polls, token, nothing)
            entry === nothing || push!(dropped, entry)
            delete!(_pushed_answers, token)
        end
        empty!(pages.tokens)
        empty!(pages.caller_faults)
    end
    _record_operation_ends!(dropped, :abandoned)
end

# Standalone warm-up can join operations only on this process's own listener.
function _local_warm_base(base)
    server = _SERVER[]
    server === nothing && return false
    uri = HTTP.URI(base)
    uri.scheme == "http" && uri.host in ("localhost", "127.0.0.1", "::1", "[::1]") &&
        isempty(uri.userinfo) && isopen(server) &&
        string(HTTP.port(server)) == (isempty(uri.port) ? "80" : uri.port)
end

function _warm_linked_pages(base, routes, selected, timeout; workload=false)
    rows = NamedTuple[]
    _local_warm_base(base) || return rows
    seen = Set{String}()
    for row in routes
        row.verb === :GET && get(row, :transport, :plain) === :plain || continue
        _prewarm_ok(row) && (row.url == base || startswith(row.url, base * "/")) || continue
        row.url in seen && continue
        push!(seen, row.url)
        pages = _open_warm_page(selected, !workload)
        try
            _warm_navigation!(rows, pages, row, timeout)
            if workload
                # Strict plain checks already followed redirects. This pass
                # stops at the redirect to stay on the workload listener.
                last_row = last(rows)
                last_row.status in (301, 302, 303, 307, 308) ||
                    _require_prewarm_success((last_row,), "browser GET")
            end
        finally
            _close_warm_page!(pages)
        end
    end
    rows
end

# Accept only addresses for operations retained by this navigation or for the
# initial semantic view that was actually rendered. The latter also receives a
# fresh htmx GET, exercising the request that starts an operation from its form.
function _warm_followups(pages, html)
    found = Tuple{String,String}[]
    if !occursin("__htmxo_operation=", html)
        has_views = lock(() -> pages.initial_views !== nothing && !isempty(pages.initial_views),
                         _operation_poll_lock)
        has_views || return found
    end
    for m in eachmatch(r"\shx-get=\"(/[^\"\s]*)\"", html)
        target = _site_attribute_text(m[1])
        startswith(target, "//") && continue
        query = HTTP.queryparams(HTTP.URI(target))
        haskey(query, "__htmxo_verb") && continue
        url = _operation_unmarked_url(target)
        token = get(query, "__htmxo_operation", "")
        lock(_operation_poll_lock) do
            if !isempty(token) && get(pages.tokens, token, nothing) == url
                push!(found, (target, ""))
            end
            id = pages.initial_views === nothing ? nothing : pop!(pages.initial_views, url, nothing)
            if id !== nothing && _warm_fragment_allowed!(pages, url)
                push!(found, (url, id))
            end
        end
    end
    unique!(found)
end

# Each extra row corresponds to a request attempted by this navigation.
function _warm_page_get!(rows, row, url, transport, headers, pages, timeout, clock; fragment=false)
    spent = _prewarm_elapsed(clock)
    remaining = timeout - spent.busy
    if remaining <= 0
        error = _prewarm_overrun("navigation did not finish", timeout, spent)
        push!(rows, merge(row, (; url, transport=:browser, requests=0, status=nothing, error)))
        return nothing
    end
    r = _prewarm_request(:GET, url, remaining; headers, browser=true,
                         fragment_pages=fragment ? pages : nothing)
    push!(rows, merge(row, (; url, transport, requests=1, r.status, r.error)))
    _prewarm_ok(r) ? String(r.body) : nothing
end

# The built-in SSE encoder writes one data line per line of HTML. A ready
# event asks htmx to poll (e.g. for response headers); a result is the answer.
function _warm_stream_terminal(frames, token)
    for m in eachmatch(r"(?m)^event: (ready|result)\ndata: ([^\n]+)\n((?:data: [^\n]*\n)*)\n", frames)
        m[2] == token || continue
        html = join((chop(line; head=6, tail=0) for line in split(chomp(m[3]), '\n'; keepempty=false)), "\n")
        return (; result=m[1] == "result", html)
    end
    nothing
end

function _warm_navigation!(rows, pages, row, timeout)
    url = row.url
    clock = _prewarm_clock()
    marker = "HTMXO-Warm-Page" => pages.key
    body = _warm_page_get!(rows, row, url, :browser, [marker, "Accept" => "text/html"],
                           pages, timeout, clock)
    body === nothing && return
    pending = _warm_followups(pages, body)
    headers = [marker, "HX-Request" => "true", "HX-Current-URL" => url, "Referer" => url]
    streamed = Set{String}()
    while !isempty(pending)
        next, id = popfirst!(pending)
        query = HTTP.queryparams(HTTP.URI(next))
        if haskey(query, "__htmxo_poll")
            token = query["__htmxo_operation"]
            if _OPERATION_STREAM[] && !(token in streamed)
                push!(streamed, token)
                # EventSource uses location.pathname, without the page query.
                events = _prewarm_resolve(url, _url_path_only(url)) *
                         "?__htmxo_operations=" * token * "&__htmxo_push=1"
                frames = _warm_page_get!(rows, row, events, :stream,
                    [marker, "Accept" => "text/event-stream", "Accept-Encoding" => "gzip",
                     "Referer" => url], pages, timeout, clock)
                frames === nothing && return
                terminal = _warm_stream_terminal(frames, token)
                if terminal === nothing
                    rows[end] = merge(last(rows), (; error="operation stream ended without its terminal event"))
                    return
                elseif terminal.result
                    append!(pending, _warm_followups(pages, terminal.html))
                    continue
                end
            else
                sleep(0.05)
            end
        end
        context = isempty(id) ? headers : [headers; "HX-Trigger" => id; "HX-Target" => id]
        answer = _warm_page_get!(rows, row, _prewarm_resolve(url, next), :browser,
                                 context, pages, timeout, clock; fragment=true)
        answer === nothing && return
        append!(pending, _warm_followups(pages, answer))
    end
end
