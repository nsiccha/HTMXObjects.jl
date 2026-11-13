# World-keyed memo for shared, read-only metadata. DO rebuilds every descriptor from `meta(T)` source
# metadata — signature parsing, `Core.eval` of each argument type, per-property
# dependency closures — so one build of a large route type costs milliseconds,
# and the request path used to pay it twice per request (snag
# `per-request-prop-096b23ad`). A type-level reflection result depends only on
# `T` and on the method table, never on the request, so it is keyed on the
# world counter: any (re)definition — a Revise edit, a struct redefinition —
# rebuilds on the next read. The counter is read BEFORE the build, so a
# definition racing a build stamps the entry stale rather than fresh. The
# cached value is shared: callers must not mutate it, and anything handed to a
# consumer gets its own outer container. Runtime assets also use this memo,
# with their extension provider as the key instead of an application type.
struct _WorldMemo{V}
    entries::IdDict{Any,Tuple{UInt,V}}
    lock::ReentrantLock
end
_WorldMemo{V}() where {V} = _WorldMemo{V}(IdDict{Any,Tuple{UInt,V}}(), ReentrantLock())

function _world_memo!(build, memo::_WorldMemo, T)
    world = Base.get_world_counter()
    cached = lock(() -> get(memo.entries, T, nothing), memo.lock)
    cached !== nothing && first(cached) == world && return last(cached)
    value = build()
    lock(() -> memo.entries[T] = (world, value), memo.lock)
    value
end
