# Chat app demonstrating `live_thread`:
#   - infinite scroll: older messages page in as you scroll up
#   - a live tail refreshed by a version-gated poll (204 when nothing changed)
#   - in-place updates without flicker: the bot's "typing…" message becomes its
#     reply, and "edit" rewrites a recent message, both morphed by key
#   - your own sends jump to the bottom; arrivals while you read history only
#     raise a "↓ N new" pill
#
# Run with:  julia --project examples/chat.jl
# Then open: http://localhost:8080

module Chat

using HTMXObjects

mutable struct Message
    id::Int
    author::String
    text::String
    final::Bool     # false while the bot is still "typing"
end

const LOCK = ReentrantLock()
const MESSAGES = Message[]
const VERSION = Ref(0)
const PAGE = 20     # messages per page (initial window and each older page)
const LIVE = 5      # the newest messages stay editable (the live tail)

const WORDS = split("lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua")
lorem(i) = join((WORDS[mod1(i * k, length(WORDS))] for k in 1:(3 + i % 17)), " ")

function seed!(n=200)
    lock(LOCK) do
        empty!(MESSAGES)
        for i in 1:n
            push!(MESSAGES, Message(i, isodd(i) ? "alice" : "bob", "#$i " * lorem(i), true))
        end
        VERSION[] += 1
    end
end

post!(author, text; final=true) = lock(LOCK) do
    m = Message(isempty(MESSAGES) ? 1 : MESSAGES[end].id + 1, author, text, final)
    push!(MESSAGES, m)
    VERSION[] += 1
    m
end
changed!(f, m) = lock(LOCK) do
    f(m)
    VERSION[] += 1
end

# The newest message that is final and has only final messages before it,
# held back by `LIVE` so recent messages can still be edited.
function since_index()
    first_open = findfirst(m -> !m.final, MESSAGES)
    stop = isnothing(first_open) ? length(MESSAGES) : first_open - 1
    min(stop, length(MESSAGES) - LIVE)
end

key(m) = string(m.id)
item(m) = key(m) => h.div(class="chat-msg" * (m.author == "you" ? " chat-you" : ""))(
    h.small(h.strong(m.author)),
    m.final ? h.p(m.text) : h.p(h.em("typing…")),
)
index_of(k) = findfirst(m -> key(m) == k, MESSAGES)
since_key(i, lo) = i >= lo ? key(MESSAGES[i]) : ""   # only keys the client holds
cursor_at(lo) = lo > 1 ? key(MESSAGES[lo]) : nothing

# The latest window, as rendered on first load and after a reset.
function window()
    lo = max(1, length(MESSAGES) - PAGE + 1)
    (; items=item.(MESSAGES[lo:end]), cursor=cursor_at(lo),
       since=since_key(since_index(), lo), version=string(VERSION[]))
end

const CSS = """
.chat-msg { padding: 0.4rem 0.75rem; border-radius: 0.75rem; max-width: 80%;
            background: color-mix(in srgb, currentColor 8%, transparent); }
.chat-msg p { margin: 0; }
.chat-you { margin-left: auto; background: color-mix(in srgb, var(--pico-primary, #4a90d9) 22%, transparent); }
.chat-compose { display: flex; gap: 0.5rem; align-items: flex-end; margin-top: 0.75rem; }
.chat-compose textarea { margin: 0; }
.chat-compose button { width: auto; margin: 0; }
.chat-sim { display: flex; gap: 0.5rem; flex-wrap: wrap; }
.chat-sim button { width: auto; }
"""

const SIMULATIONS = Dict(
    "incoming" => () -> post!("alice", lorem(rand(1:100))),
    "burst"    => () -> foreach(i -> post!(isodd(i) ? "alice" : "bob", lorem(rand(1:100))), 1:5),
    "edit"     => () -> changed!(m -> (m.text *= " (edited)"), lock(() -> MESSAGES[max(1, end - 2)], LOCK)),
)

@htmx struct App
    __page__(content) = htmx(h.main(class="container")(content);
        pico_version="2",
        extra_head=(h.style(CSS),
                    h.script(src="https://cdn.jsdelivr.net/npm/idiomorph@0.7.3/dist/idiomorph.min.js")))

    @fresh @get index() = let w = lock(window, LOCK)
        h.div(
            h.h1("Live thread"),
            live_thread(w.items; id="chat", older_url=__self__/"older", tail_url=__self__/"tail",
                        cursor=w.cursor, since=w.since, version=w.version, poll="2s",
                        empty="No messages yet"),
            h.form(class="htmxo-compose-form chat-compose", hx_post=__self__/"send", hx_swap="none")(
                compose_box("text"; placeholder="Message…", draft_key="chat-draft"),
                h.button(type="submit")("Send"),
            ),
            h.div(class="chat-sim")(
                h.small("Simulate:"),
                (h.button(type="button", class="secondary outline", hx_post=__self__/"simulate",
                          hx_vals="{\"kind\": \"$kind\"}", hx_swap="none")(label)
                 for (kind, label) in (("incoming", "incoming message"), ("burst", "burst of 5"),
                                       ("edit", "edit a recent message")))...,
            ),
        )
    end

    @fresh @get older(; before::String) = lock(LOCK) do
        hi = something(index_of(before), 0) - 1
        hi < 0 && throw(ArgumentError("unknown cursor $(repr(before))"))
        lo = max(1, hi - PAGE + 1)
        live_thread_page(item.(MESSAGES[lo:hi]); cursor=cursor_at(lo))
    end

    @fresh @get tail(; since::String="", v::String="") = lock(LOCK) do
        v == string(VERSION[]) && return live_thread_unchanged()
        i = isempty(since) ? nothing : index_of(since)
        if isnothing(i)
            w = window()
            return live_thread_tail(w.items; since=w.since, version=w.version,
                                    reset=true, cursor=w.cursor)
        end
        live_thread_tail(item.(MESSAGES[i+1:end]); since=key(MESSAGES[max(i, since_index())]),
                         version=string(VERSION[]))
    end

    @post send(; text::String="") = begin
        if !isempty(strip(text))
            post!("you", strip(text))
            @async begin
                sleep(0.8)
                reply = post!("bot", ""; final=false)
                sleep(1.5)
                changed!(m -> (m.text = "You said: “$(strip(text))”"; m.final = true), reply)
            end
        end
        hx_response(""; trigger=live_thread_refresh("#chat"))
    end

    @post simulate(; kind::String) = begin
        get(() -> throw(ArgumentError("unknown simulation $(repr(kind))")), SIMULATIONS, kind)()
        hx_response(""; trigger=live_thread_refresh("#chat"; bottom=false))
    end
end

function main(; port=8080)
    seed!()
    route!(App())
    serve(; port)
end

end # module Chat

if abspath(PROGRAM_FILE) == @__FILE__
    Chat.main()
end
