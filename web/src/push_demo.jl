@dynamicstruct struct PushDemoData end

# One revision counter per key: each rebuild bumps it, so a pushed refresh is
# visibly new data rather than a re-render of the same state.
const _PUSH_DEMO_LOCK = ReentrantLock()
const _PUSH_DEMO_REVS = Dict{String,Int}()
const _PUSH_DEMO_CACHE = BackgroundCache{String,Any}(
    key -> lock(_PUSH_DEMO_LOCK) do
        rev = get(_PUSH_DEMO_REVS, key, 0) + 1
        _PUSH_DEMO_REVS[key] = rev
        (; state=rev % 2 == 1 ? "open" : "closed", title="Demo item $key", rev)
    end; ttl=600.0, unbuilt=nothing)

const _PUSH_DEMO_SUBS = KeySubscriptions()
const _PUSH_DEMO_KEYS = ("demo#12", "demo#34")

function _push_demo_body(key)
    entry = _PUSH_DEMO_CACHE[key]
    isnothing(entry) && return h.span("state: loading… (refreshing in background)")
    h.span("state: $(entry.state) · rev $(entry.rev) · $(entry.title)")
end

function _push_demo_card(self, key)
    live_fragment(key, _push_demo_body(key);
        fragment_url=query_url(self/"card"; key=key),
        events_url=query_url(self/"key_events"; key=key))
end

@htmx struct PushDemoRoutes
    @get index() = begin
        h.div(
            h.h1("Server-Push Refresh Demo"),
            h.p("Each card subscribes to its key over its own event stream. ",
                "Bumping a key refreshes its data and pushes a refresh: the ",
                "card re-fetches in place, no reload. The other card stays put."),
            h.div(_push_demo_card(__self__, _PUSH_DEMO_KEYS[1]),
                h.button("Bump $(_PUSH_DEMO_KEYS[1])";
                    hx_post=query_url(__self__/"bump"; key=_PUSH_DEMO_KEYS[1]),
                    hx_swap="none")),
            h.div(_push_demo_card(__self__, _PUSH_DEMO_KEYS[2]),
                h.button("Bump $(_PUSH_DEMO_KEYS[2])";
                    hx_post=query_url(__self__/"bump"; key=_PUSH_DEMO_KEYS[2]),
                    hx_swap="none")),
            h.p("Append ", h.code("?plain"), " for the stable projection."),
        )
    end

    @get card(; key::String="") = _push_demo_card(__self__, key)

    @sse key_events(; key::String="") = serve_key_feed!(__sse__, _PUSH_DEMO_SUBS, key)

    # The two-phase refresh an app wires around the push half: drop the
    # settled value and push at once (fragments re-fetch plain and kick the
    # rebuild), then push again once the rebuild lands so they show it.
    @post bump(; key::String="") = begin
        invalidate!(_PUSH_DEMO_CACHE, key)
        invalidate_key!(_PUSH_DEMO_SUBS, key)
        @async begin
            t0 = time()
            while time() - t0 < 10
                _PUSH_DEMO_CACHE[key] === nothing || break
                sleep(0.02)
            end
            invalidate_key!(_PUSH_DEMO_SUBS, key)
        end
        "bumped $key"
    end
end
