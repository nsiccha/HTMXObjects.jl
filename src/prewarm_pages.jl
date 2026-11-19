# State private to the temporary workload listener. Only its marked navigation
# and follow-ups carry it. The operation lock also protects access by a late
# handler when the driver times out and closes the workload.
mutable struct _WarmPages
    key::String
    selected::Union{Nothing,Set{String}}
    tokens::Dict{String,String}  # token => concrete GET address
    remaining::Int
    closed::Bool
end

_WarmPages(fragments::Symbol) = _WarmPages(bytes2hex(rand(Random.RandomDevice(), UInt8, 24)),
    fragments === :selected ? Set{String}() : nothing, Dict{String,String}(), 0, false)

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

function _reset_warm_pages!(pages::_WarmPages; close=false)
    dropped = _OperationPollEntry[]
    lock(_operation_poll_lock) do
        pages.closed = close
        pages.remaining = close ? 0 : _PRESTART_LIMIT
        for token in keys(pages.tokens)
            entry = pop!(_operation_polls, token, nothing)
            entry === nothing || push!(dropped, entry)
            delete!(_pushed_answers, token)
        end
        empty!(pages.tokens)
    end
    _record_operation_ends!(dropped, :abandoned)
end

function _warm_linked_pages!(pages, base, routes, urls, timeout, stream)
    gets = [r.url for r in routes if r.verb === :GET && r.transport === :plain]
    if pages.selected !== nothing
        for url in Iterators.flatten((gets, (r.url for r in urls)))
            startswith(url, base * "/") && push!(pages.selected, chop(url; head=length(base), tail=0))
        end
    end
    for url in unique(gets)
        _reset_warm_pages!(pages)
        _warm_navigation!(pages, base, url, timeout, stream)
    end
end

# Follow the addresses serve actually returned for operations this navigation
# owns. A page can contain several; a single regex match misses its siblings.
function _warm_followups(pages, html)
    found = String[]
    occursin("__htmxo_operation=", html) || return found
    for m in eachmatch(r"\shx-get=\"(/[^\"\s]*)\"", html)
        target = _site_attribute_text(m[1])
        startswith(target, "//") && continue
        uri = HTTP.URI(target)
        query = HTTP.queryparams(uri)
        token = get(query, "__htmxo_operation", "")
        owned = lock(_operation_poll_lock) do
            get(pages.tokens, token, nothing) == _operation_unmarked_url(target)
        end
        owned && !haskey(query, "__htmxo_verb") && push!(found, target)
    end
    unique!(found)
end

function _warm_page_get(url, headers, timeout, clock)
    spent = _prewarm_elapsed(clock)
    remaining = timeout - spent.busy
    remaining > 0 || error("prewarm_workload!: GET $url " *
        _prewarm_overrun("did not finish", timeout, spent))
    r = _prewarm_request(:GET, url, remaining; headers, browser=true)
    # The strict route checks already validated redirects. A redirect itself
    # has no fragments and this browser pass stays on the workload listener.
    r.error === nothing && r.status in (301, 302, 303, 307, 308) && return ""
    _prewarm_ok(r) || error("prewarm_workload!: browser GET $url failed: " *
        (r.error === nothing ? "HTTP $(r.status)" : r.error))
    String(r.body)
end

function _warm_navigation!(pages, base, url, timeout, stream)
    clock = _prewarm_clock()
    headers = ["HTMXO-Warm-Page" => pages.key, "Accept" => "text/html"]
    body = _warm_page_get(url, headers, timeout, clock)
    pending = _warm_followups(pages, body)
    headers = ["HTMXO-Warm-Page" => pages.key, "HX-Request" => "true",
               "HX-Current-URL" => url]
    streamed = Set{String}()
    while !isempty(pending)
        next = popfirst!(pending)
        query = HTTP.queryparams(HTTP.URI(next))
        token = query["__htmxo_operation"]
        if haskey(query, "__htmxo_poll")
            if stream && !(token in streamed)
                push!(streamed, token)
                events = _operation_marker_url(url, _OPERATION_STREAM_PARAM, token)
                _warm_page_get(events * "&__htmxo_push=1",
                    ["HTMXO-Warm-Page" => pages.key, "Accept" => "text/event-stream",
                     "Accept-Encoding" => "gzip", "Referer" => url], timeout, clock)
            else
                sleep(0.05)
            end
        end
        answer = _warm_page_get(base * next, headers, timeout, clock)
        append!(pending, _warm_followups(pages, answer))
    end
    nothing
end
