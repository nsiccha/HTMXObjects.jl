# --- Live thread: keyed, bottom-anchored, infinitely scrolling list ---
#
# A chat-style list that (a) lazily pages older items in when the viewer
# scrolls towards the top, (b) keeps its live tail up to date by polling a
# version-gated route (or on demand), and (c) never re-renders what did not
# change: every item carries a stable key and a content digest, the client
# reconciles by key, leaves identical items untouched, and holds the viewer's
# scroll position with its own anchoring (so it behaves the same in browsers
# without native `overflow-anchor`).

"""
    live_thread(items; older_url=nothing, tail_url=nothing, cursor=nothing,
                since="", version="", poll="10s", focus=nothing,
                height=nothing, empty=nothing, id=nothing, class="")

A chat-style, bottom-anchored list that loads older items as the viewer scrolls
up and keeps its newest items live, without flicker or scroll jumps.

`items` is an iterable of `key => content` pairs, **oldest first**. Keys are
stable, unique identifiers (converted with `string`); content is anything
renderable. Each item is wrapped in a `div.htmxo-thread-item` carrying its key
and a digest of its rendered HTML, which is what lets the client skip items
that did not change.

Keyword arguments:

- `older_url`: route answering `GET older_url?before=<cursor>` with a
  [`live_thread_page`](@ref). Omit it for a thread without older pages.
- `cursor`: the opaque cursor for the page before the rendered items (usually
  the oldest rendered key); `nothing` means there is nothing older.
- `tail_url`: route answering `GET tail_url?since=<since>&v=<version>` with a
  [`live_thread_tail`](@ref) or [`live_thread_unchanged`](@ref). Omit it for a
  static thread.
- `since`: key of the newest **final** item among `items` (see the tail
  contract below); `""` when none is final yet.
- `version`: opaque token for the state rendered here; echoed back as `v`.
- `poll`: tail refresh interval (`"10s"`, `"500ms"`, a number of seconds) or
  `nothing` to refresh only on demand. Polling pauses while the tab is hidden.
- `focus`: key of an item to centre and briefly highlight on first render
  instead of starting at the bottom.
- `height`: CSS length for the scroll box's maximum height (default `60vh`, or
  set `--htmxo-thread-height` from a stylesheet).
- `empty`: text shown while the list has no items.

# Tail contract

The client asks for `since` and `version` exactly as last given. The route
answers with one of:

- [`live_thread_unchanged`](@ref) (HTTP 204) when `v` is still current — nothing
  is rendered on the server or touched in the browser;
- `live_thread_tail(items; since, version)` with **every item after the `since`
  key** (all items when `since == ""`), in order. The client reconciles the part
  of its list after `since` to exactly these items: identical items are left
  alone, changed ones are morphed in place (with idiomorph when it is loaded,
  keeping `<details>` open state), new ones are inserted, missing ones removed.
  The new `since` must name an item the client holds afterwards; every item up
  to it must be final, because the client never revisits it;
- `live_thread_tail(items; reset=true, cursor, ...)` when the route cannot honour
  `since`: the client reconciles its **whole** list to `items` (still by key)
  and restarts older paging at `cursor`.

A thread whose rendered window contains no final item passes `since=""`; its
tail route should then answer with `reset=true`.

# Client behaviour

- starts at the bottom and stays there while the viewer is at the bottom;
- when the viewer has scrolled up, updates keep the visible item in place and
  a "↓ N new" pill counts what arrived below;
- older pages load before the viewer reaches the top (and fill a short thread),
  inserted above without moving the viewport;
- one tail request at a time, a 30 s timeout, exponential back-off on failure;
  failures show in a status line (never a silent retry loop); a route that
  answers with an interim Treebars poller is reported as such (declare tail and
  older routes `@fresh @get`);
- new items get htmx processing, their scripts run and `htmx:load` fires, as
  after an htmx swap; the root emits `htmxo:thread-updated` after each change;
- `htmxo:thread-refresh` (e.g. via [`live_thread_refresh`](@ref) in an
  `HX-Trigger` header) or `window.htmxoThread.refresh(target, {bottom})` asks
  for the tail immediately.

Requires [`live_thread_assets`](@ref), which [`htmx`](@ref) includes by default
(`thread=true`).

All three routes are `@fresh`: a memoized index would keep serving its first
render, and a slow tail/older render under the default `:auto` operation policy
would come back as an interim poller.

```julia
@fresh @get index() = live_thread(latest_items(); id="chat",
    older_url=__self__/"older", tail_url=__self__/"tail",
    cursor=oldest_key(), since=last_final_key(), version=current_version())
@fresh @get older(; before::String) =
    live_thread_page(page_before(before); cursor=oldest_key_or_nothing())
@fresh @get tail(; since::String="", v::String="") =
    v == current_version() ? live_thread_unchanged() :
        live_thread_tail(items_after(since); since=last_final_key(), version=current_version())
```

`examples/chat.jl` is a complete, runnable app.
"""
function live_thread(items; older_url=nothing, tail_url=nothing, cursor=nothing,
                     since="", version="", poll="10s", focus=nothing,
                     height=nothing, empty=nothing, id=nothing, class="")
    nodes = _thread_item_nodes(items)
    has_older = !isnothing(older_url) && !isnothing(cursor)
    h.div(; id,
          class=isempty(class) ? "htmxo-thread" : "htmxo-thread " * class,
          data_htmxo_thread="",
          data_older_url=older_url, data_tail_url=tail_url,
          data_since=string(since), data_version=string(version),
          data_poll=_thread_poll_ms(poll),
          data_focus=isnothing(focus) ? nothing : string(focus),
          style=isnothing(height) ? nothing : "--htmxo-thread-height: $height")(
        h.div(class="htmxo-thread-viewport")(
            h.div(class="htmxo-thread-scroll")(
                h.div(class="htmxo-thread-older",
                      data_cursor=has_older ? string(cursor) : nothing,
                      data_done=!has_older),
                h.div(class="htmxo-thread-items", data_empty=empty)(nodes...),
            ),
            h.button(type="button", class="htmxo-thread-new", hidden=true),
        ),
        h.div(class="htmxo-thread-status", role="status", hidden=true),
    )
end

"""
    live_thread_page(items; cursor=nothing)

Response fragment for a [`live_thread`](@ref)'s `older_url`: the page of
`key => content` items (oldest first) directly before the requested cursor,
plus the `cursor` of the page before this one — `nothing` once the start of the
thread is reached. Items whose keys the client already holds are skipped, so
overlapping (inclusive) cursors are fine; a page that neither adds items nor
advances the cursor is reported as an error rather than retried forever.
"""
live_thread_page(items; cursor=nothing) =
    h.div(class="htmxo-thread-page",
          data_cursor=isnothing(cursor) ? nothing : string(cursor),
          data_done=isnothing(cursor))(_thread_item_nodes(items)...)

"""
    live_thread_tail(items; since, version, reset=false, cursor=nothing)

Response fragment for a [`live_thread`](@ref)'s `tail_url`: every item after
the `since` key the client sent, in order, with the new `since` (key of the
newest final item) and `version`. With `reset=true` the client reconciles its
whole list to `items` and restarts older paging at `cursor` (`nothing`: no
older items). See the tail contract in [`live_thread`](@ref).
"""
live_thread_tail(items; since, version, reset::Bool=false, cursor=nothing) =
    h.div(class="htmxo-thread-tail",
          data_since=string(since), data_version=string(version),
          data_reset=reset,
          data_cursor=reset && !isnothing(cursor) ? string(cursor) : nothing,
          data_done=reset && isnothing(cursor))(_thread_item_nodes(items)...)

"""
    live_thread_unchanged()

The tail route's answer when the client's version is current: an empty
`204 No Content`, which the client treats as "nothing to do".
"""
live_thread_unchanged() = HTTP.Response(204)

"""
    live_thread_refresh(target=nothing; bottom=true) -> String

`HX-Trigger` header value asking [`live_thread`](@ref)s to fetch their tail
now — e.g. from the POST that sent a message:

```julia
@post send(; text::String) = (append!(text);
    hx_response(""; trigger=live_thread_refresh("#chat")))
```

`target` is a CSS selector (all threads on the page when `nothing`); `bottom`
scrolls the thread to its newest item, as a chat does after you send.
"""
function live_thread_refresh(target=nothing; bottom::Bool=true)
    fields = String["\"bottom\":$(bottom)"]
    isnothing(target) || push!(fields, "\"target\":" * _json_string(string(target)))
    "{\"htmxo:thread-refresh\":{" * join(fields, ",") * "}}"
end

_json_string(s::AbstractString) = "\"" * escape_string(s, "\"") * "\""

# `key => content` → the keyed item wrapper. The digest covers the rendered
# content only, so the client can tell an unchanged item without comparing
# (browser-reserialized, possibly client-mutated) DOM.
_thread_item_node(item::Pair) =
    let content = h.div(item.second)
        h.div(class="htmxo-thread-item", data_key=string(item.first),
              data_digest=_thread_digest(sprint(show, MIME"text/html"(), content)))(
            HTMX.children(content)...)
    end
_thread_item_node(item) = throw(ArgumentError(
    "live thread items must be `key => content` pairs, got $(typeof(item))"))

function _thread_item_nodes(items)
    nodes = Node[_thread_item_node(item) for item in items]
    seen = Set{String}()
    for node in nodes
        key = HTMX.attrs(node)[Symbol("data-key")]
        key in seen && throw(ArgumentError("live thread item key $(repr(key)) is not unique"))
        push!(seen, key)
    end
    nodes
end

# FNV-1a (64-bit): stable across processes and Julia versions, unlike `hash`.
function _thread_digest(s::AbstractString)
    d = 0xcbf29ce484222325
    for b in codeunits(s)
        d = (d ⊻ b) * 0x00000100000001b3
    end
    string(d; base=36)
end

_thread_poll_ms(::Nothing) = 0
_thread_poll_ms(seconds::Real) = seconds > 0 ? round(Int, 1000seconds) :
    throw(ArgumentError("live thread poll interval must be positive, got $seconds"))
function _thread_poll_ms(spec::AbstractString)
    m = match(r"^\s*(\d+(?:\.\d+)?)\s*(ms|s|m)\s*$", spec)
    isnothing(m) && throw(ArgumentError(
        "live thread poll interval $(repr(spec)) is not like \"10s\", \"500ms\" or \"1m\""))
    _thread_poll_ms(parse(Float64, m[1]) * Dict("ms" => 0.001, "s" => 1.0, "m" => 60.0)[m[2]])
end

"""
    live_thread_styles()

CSS for [`live_thread`](@ref). Layout rules sit inside `@layer htmxo` so host
styles win; the "new messages" pill is styled **unlayered** (like
[`compose_box_styles`](@ref)) because Pico styles `<button>` unlayered, which
would otherwise beat every layered rule and blow the pill up to a full button.
Size the scroll box with `--htmxo-thread-height` (default `60vh`) and the item
gap with `--htmxo-thread-gap`. Native scroll anchoring is off on the scroll box
(the client anchors explicitly; both at once would double-correct), and the
older-items sentinel has a fixed height so its label changes cannot shift the
list.
"""
live_thread_styles() = h.style(Raw(raw"""
@layer htmxo {
.htmxo-thread { display: flex; flex-direction: column; min-height: 0; }
.htmxo-thread-viewport { position: relative; min-height: 0; }
.htmxo-thread-scroll {
    max-height: var(--htmxo-thread-height, 60vh);
    overflow-y: auto; overflow-anchor: none; overscroll-behavior: contain;
}
.htmxo-thread-items { display: flex; flex-direction: column; gap: var(--htmxo-thread-gap, 0.5rem); }
.htmxo-thread-items:empty::before {
    content: attr(data-empty); display: block; padding: 1rem 0;
    text-align: center; font-size: 0.875em; color: var(--htmxo-muted);
}
.htmxo-thread-item { min-width: 0; }
.htmxo-thread-older {
    display: flex; align-items: center; justify-content: center;
    height: 2rem; overflow: hidden; font-size: 0.8em; color: var(--htmxo-muted);
}
.htmxo-thread-older:empty { height: 0; }
.htmxo-thread-older [role="button"] { cursor: pointer; text-decoration: underline dotted; }
.htmxo-thread-status { padding: 0.25rem 0; font-size: 0.8em; color: var(--htmxo-error); }
.htmxo-thread-status details { color: var(--htmxo-muted); }
.htmxo-thread-status[hidden] { display: none; }
.htmxo-thread-focus { animation: htmxo-thread-focus 2.5s ease-out; border-radius: 0.25rem; }
@keyframes htmxo-thread-focus {
    from { background-color: color-mix(in srgb, var(--htmxo-accent) 25%, transparent); }
    to   { background-color: transparent; }
}
@media (prefers-reduced-motion: reduce) {
    .htmxo-thread-focus { animation: none; outline: 2px solid var(--htmxo-accent); }
}
}
.htmxo-thread-viewport > .htmxo-thread-new {
    position: absolute; left: 50%; bottom: 0.75rem; transform: translateX(-50%);
    width: auto; margin: 0; padding: 0.2rem 0.75rem; border-radius: 999px;
    font-size: 0.8rem; line-height: 1.4; cursor: pointer;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
}
.htmxo-thread-viewport > .htmxo-thread-new[hidden] { display: none; }
"""))

"""
    live_thread_script()

Client runtime for [`live_thread`](@ref): initializes every
`[data-htmxo-thread]` element however it reaches the DOM (page load, htmx swap,
`innerHTML`, morph), stops a thread's polling once it leaves the DOM, and
exposes `window.htmxoThread.refresh(target, {bottom})` /
`window.htmxoThread.init(el)`. Safe to include more than once.
"""
live_thread_script() = h.script(Raw(raw"""
(function () {
  'use strict';
  if (window.htmxoThread) return;
  var STICK_PX = 48;       // this close to the bottom counts as "at the bottom"
  var PREFETCH_PX = 600;   // start loading older pages this far above the top
  var TIMEOUT_MS = 30000;
  var MAX_BACKOFF = 8;
  var ITEM = 'htmxo-thread-item';
  var MORPH = {
    morphStyle: 'outerHTML',
    ignoreActiveValue: true,
    callbacks: {
      // A viewer's own <details> open/closed choice survives item updates.
      beforeAttributeUpdated: function (name, node) {
        if (name === 'open' && node.tagName === 'DETAILS') return false;
      }
    }
  };

  function withParams(url, params) {
    var u = new URL(url, window.location.href);
    Object.keys(params).forEach(function (k) { u.searchParams.set(k, params[k]); });
    return u.toString();
  }

  function fetchFragment(url) {
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, TIMEOUT_MS);
    return fetch(url, {
      headers: { 'HX-Request': 'true', 'Accept': 'text/html' },
      credentials: 'same-origin', cache: 'no-store', signal: ctrl.signal
    }).then(function (r) {
      return r.text().then(function (text) {
        return { status: r.status, ok: r.ok, errorId: r.headers.get('X-HTMXO-Error-Id'), text: text };
      });
    }, function (err) {
      throw { message: err && err.name === 'AbortError' ? 'request timed out' : 'network error' };
    }).finally(function () { clearTimeout(timer); });
  }

  // The response's `.cls` wrapper, or a thrown {message, html} describing why not.
  function expect(res, cls) {
    if (!res.ok || res.errorId) {
      throw { message: 'HTTP ' + res.status + (res.errorId ? ' (error ' + res.errorId + ')' : ''), html: res.text };
    }
    var t = document.createElement('template');
    t.innerHTML = res.text;
    var frag = t.content.querySelector('.' + cls);
    if (!frag) {
      throw {
        message: /treebar-poller/.test(res.text)
          ? 'the route answered with an interim poller; declare it `@fresh @get`'
          : 'unexpected response (no .' + cls + ')',
        html: res.text
      };
    }
    return frag;
  }

  function childItems(parent) {
    return Array.prototype.filter.call(parent.children, function (el) { return el.classList.contains(ITEM); });
  }
  function findKey(s, key) {
    var list = s.items.children;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].getAttribute('data-key') === key) return list[i];
    }
    return null;
  }

  // Treat inserted content like an htmx swap would: fresh copies of scripts
  // (parsed ones never run), htmx attributes processed, `htmx:load` fired.
  function processNew(node) {
    var scripts = !(window.htmx && htmx.config && htmx.config.allowScriptTags === false);
    node.querySelectorAll('script').forEach(function (old) {
      if (!scripts) { old.remove(); return; }
      var type = (old.getAttribute('type') || '').toLowerCase();
      if (type && type !== 'module' && type.indexOf('javascript') < 0) return;
      var fresh = document.createElement('script');
      Array.prototype.forEach.call(old.attributes, function (a) { fresh.setAttribute(a.name, a.value); });
      fresh.textContent = old.textContent;
      old.replaceWith(fresh);
    });
    if (window.htmx) { htmx.process(node); htmx.trigger(node, 'htmx:load'); }
  }

  function updateItem(cur, fresh) {
    if (window.Idiomorph && Idiomorph.morph) {
      Idiomorph.morph(cur, fresh, MORPH);
      if (window.htmx) htmx.process(cur);
      return cur;
    }
    cur.replaceWith(fresh);
    processNew(fresh);
    return fresh;
  }

  // Reconcile the items after `after` (the whole list when null) to `fresh`,
  // by key: identical digests are left alone, the rest morphed / inserted /
  // moved / removed.
  function reconcile(s, after, fresh) {
    var box = s.items, region = [], outside = new Set(), inRegion = !after;
    for (var el = box.firstElementChild; el; el = el.nextElementSibling) {
      if (inRegion) region.push(el); else outside.add(el.getAttribute('data-key'));
      if (el === after) inRegion = true;
    }
    var byKey = new Map(), kept = new Set(), inserted = [];
    var stats = { added: 0, changed: 0, removed: 0 };
    region.forEach(function (el) { byKey.set(el.getAttribute('data-key'), el); });
    var prev = after;
    fresh.forEach(function (f) {
      var key = f.getAttribute('data-key');
      if (outside.has(key) || kept.has(key)) {
        console.warn('htmxo thread: ignoring item with duplicate key', key);
        return;
      }
      kept.add(key);
      var next = prev ? prev.nextElementSibling : box.firstElementChild;
      var cur = byKey.get(key);
      if (cur) {
        if (cur !== next) box.insertBefore(cur, next);
        if (cur.getAttribute('data-digest') !== f.getAttribute('data-digest')) {
          cur = updateItem(cur, f);
          stats.changed++;
        }
        prev = cur;
      } else {
        box.insertBefore(f, next);
        inserted.push(f);
        stats.added++;
        prev = f;
      }
    });
    region.forEach(function (el) {
      if (!kept.has(el.getAttribute('data-key'))) { el.remove(); stats.removed++; }
    });
    inserted.forEach(processNew);
    return stats;
  }

  // --- scroll anchoring -------------------------------------------------
  function distance(s) {
    var sc = s.scroller;
    return sc.scrollHeight - sc.scrollTop - sc.clientHeight;
  }
  function stickBottom(s) { s.scroller.scrollTop = s.scroller.scrollHeight; }
  // Up to three items from the first one visible at the top, with offsets.
  function captureAnchors(s) {
    var list = s.items.children, n = list.length, out = [];
    if (!n) return out;
    var top = s.scroller.getBoundingClientRect().top, lo = 0, hi = n - 1, first = n;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (list[mid].getBoundingClientRect().bottom > top) { first = mid; hi = mid - 1; } else lo = mid + 1;
    }
    for (var i = first; i < n && out.length < 3; i++) {
      out.push({ el: list[i], off: list[i].getBoundingClientRect().top - top });
    }
    return out;
  }
  function restoreAnchors(s, anchors) {
    if (!anchors) return;
    var top = s.scroller.getBoundingClientRect().top;
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      if (a.el.parentNode !== s.items) continue;
      var d = a.el.getBoundingClientRect().top - top - a.off;
      if (d) s.scroller.scrollTop += d;
      return;
    }
  }
  // Run a DOM change without moving what the viewer is looking at.
  function mutate(s, change) {
    var anchors = s.stuck ? null : captureAnchors(s);
    var out = change();
    if (s.stuck) stickBottom(s); else restoreAnchors(s, anchors);
    s.anchors = s.stuck ? null : captureAnchors(s);
    return out;
  }
  function onScroll(s) {
    var sc = s.scroller;
    if (distance(s) <= STICK_PX) { s.stuck = true; s.unseen = 0; }
    else if (sc.scrollTop < s.lastTop - 1) s.stuck = false;   // the viewer moved up
    s.lastTop = sc.scrollTop;
    s.anchors = s.stuck ? null : captureAnchors(s);
    updatePill(s);
  }
  // Layout changes nobody announced (images loading, <details> toggled,
  // the box resized): keep the bottom, or keep the anchor.
  function onResize(s) {
    if (s.dead) return;
    if (s.stuck) stickBottom(s); else restoreAnchors(s, s.anchors);
    updatePill(s);
  }
  function updatePill(s) {
    var show = !s.stuck && (s.unseen > 0 || distance(s) > s.scroller.clientHeight);
    s.pill.hidden = !show;
    if (show) s.pill.textContent = s.unseen > 0 ? '↓ ' + s.unseen + ' new' : '↓ Latest';
  }

  // --- status -----------------------------------------------------------
  function report(s, what, err) {
    console.error('htmxo thread: ' + what + ' failed: ' + err.message, err.html || '');
    var st = s.status;
    st.textContent = '';
    st.appendChild(document.createTextNode(what + ' failed: ' + err.message));
    if (err.html) {
      var d = document.createElement('details'), sm = document.createElement('summary'), body = document.createElement('div');
      sm.textContent = 'response';
      body.innerHTML = err.html;
      d.appendChild(sm); d.appendChild(body); st.appendChild(d);
    }
    st.hidden = false;
  }
  function clearStatus(s) { if (!s.status.hidden) { s.status.hidden = true; s.status.textContent = ''; } }

  // --- older pages --------------------------------------------------------
  function setOlder(s, cursor, done) {
    s.olderCursor = cursor;
    s.olderDone = done || cursor == null;
    if (cursor == null) s.older.removeAttribute('data-cursor'); else s.older.setAttribute('data-cursor', cursor);
    s.older.toggleAttribute('data-done', s.olderDone);
    olderLabel(s);
  }
  function olderLabel(s) {
    var o = s.older;
    o.textContent = '';
    if (!s.olderUrl) return;
    if (s.olderBusy) { o.textContent = 'Loading earlier messages…'; return; }
    if (s.olderDone) { o.textContent = 'Start of thread'; return; }
    var b = document.createElement('span');
    b.setAttribute('role', 'button');
    b.tabIndex = 0;
    b.textContent = s.olderError ? 'Couldn’t load earlier messages — retry' : 'Earlier messages';
    o.appendChild(b);
  }
  function loadOlder(s) {
    if (s.dead || s.olderBusy || s.olderDone || s.olderError || !s.olderUrl) return;
    s.olderBusy = true;
    olderLabel(s);
    var gen = s.gen, before = s.olderCursor;
    // A reset while this page was in flight made it stale: drop it and look
    // again with the new cursor (the observer will not re-fire by itself).
    function stale() {
      if (s.dead || gen === s.gen) return false;
      olderLabel(s);
      requestAnimationFrame(function () { maybeLoadOlder(s); });
      return true;
    }
    fetchFragment(withParams(s.olderUrl, { before: before })).then(function (res) {
      s.olderBusy = false;
      if (s.dead || stale()) return;
      var frag = expect(res, 'htmxo-thread-page');
      var cursor = frag.getAttribute('data-cursor'), done = frag.hasAttribute('data-done');
      var added = mutate(s, function () {
        var first = s.items.firstElementChild, inserted = [];
        childItems(frag).forEach(function (f) {
          if (findKey(s, f.getAttribute('data-key'))) return;   // overlapping cursor
          s.items.insertBefore(f, first);
          inserted.push(f);
        });
        inserted.forEach(processNew);
        return inserted.length;
      });
      if (!added && !done && cursor === before) {
        throw { message: 'the older page added nothing and did not advance its cursor' };
      }
      setOlder(s, cursor, done);
      emit(s, { older: added });
      requestAnimationFrame(function () { maybeLoadOlder(s); });
    }).catch(function (err) {
      s.olderBusy = false;
      if (s.dead || stale()) return;
      s.olderError = true;
      olderLabel(s);
      report(s, 'Loading earlier messages', err);
    });
  }
  // The observer only reports changes; after a page lands, keep filling while
  // the top is still within reach.
  function maybeLoadOlder(s) {
    if (s.dead || s.olderBusy || s.olderDone || s.olderError || !s.olderUrl) return;
    if (!s.scroller.clientHeight) return;   // not rendered (collapsed, hidden)
    if (s.older.getBoundingClientRect().bottom >= s.scroller.getBoundingClientRect().top - PREFETCH_PX) loadOlder(s);
  }

  // --- live tail ------------------------------------------------------------
  function applyTail(s, frag, sentSince) {
    var reset = frag.hasAttribute('data-reset'), after = null;
    if (!reset && sentSince) {
      after = findKey(s, sentSince);
      if (!after) {
        s.since = ''; s.version = '';
        throw { message: 'the list no longer holds the `since` item "' + sentSince + '"; asking for a full tail next' };
      }
    }
    var stats = mutate(s, function () {
      if (reset) {
        s.gen++;   // older pages in flight belong to the old list
        s.olderError = false;
        setOlder(s, frag.getAttribute('data-cursor'), frag.hasAttribute('data-done'));
      }
      return reconcile(s, after, childItems(frag));
    });
    s.since = frag.getAttribute('data-since') || '';
    s.version = frag.getAttribute('data-version') || '';
    s.root.setAttribute('data-since', s.since);
    s.root.setAttribute('data-version', s.version);
    if (!s.stuck) s.unseen += stats.added;
    updatePill(s);
    stats.reset = reset;
    if (stats.added || stats.changed || stats.removed || reset) emit(s, stats);
    if (reset) requestAnimationFrame(function () { maybeLoadOlder(s); });
  }
  function refresh(s, opts) {
    if (s.dead) return;
    if (opts && opts.bottom) { s.stuck = true; s.unseen = 0; stickBottom(s); updatePill(s); }
    if (!s.tailUrl) return;
    if (s.tailBusy) { s.tailAgain = true; return; }
    clearTimeout(s.timer);
    s.timer = null;
    s.tailBusy = true;
    var sentSince = s.since;
    fetchFragment(withParams(s.tailUrl, { since: sentSince, v: s.version })).then(function (res) {
      if (s.dead) return;
      if (res.status !== 204 || res.errorId) applyTail(s, expect(res, 'htmxo-thread-tail'), sentSince);
      s.failures = 0;
      clearStatus(s);
    }).catch(function (err) {
      if (s.dead) return;
      s.failures++;
      report(s, 'Refreshing', err);
    }).then(function () {
      s.tailBusy = false;
      if (s.dead) return;
      if (s.tailAgain) { s.tailAgain = false; refresh(s); } else schedule(s);
    });
  }
  function schedule(s) {
    clearTimeout(s.timer);
    s.timer = null;
    if (s.dead || !s.tailUrl || !(s.pollMs > 0)) return;
    var delay = s.pollMs * Math.min(Math.pow(2, s.failures), MAX_BACKOFF);
    s.timer = setTimeout(function () {
      s.timer = null;
      if (!s.root.isConnected) { destroy(s); return; }
      if (document.hidden) { s.hiddenPaused = true; return; }
      refresh(s);
    }, delay);
  }

  function emit(s, detail) {
    s.root.dispatchEvent(new CustomEvent('htmxo:thread-updated', { bubbles: true, detail: detail }));
  }

  function destroy(s) {
    s.dead = true;
    clearTimeout(s.timer);
    if (s.io) s.io.disconnect();
    if (s.ro) s.ro.disconnect();
    delete s.root.__htmxoThread;
  }

  function init(root) {
    if (root.__htmxoThread) return root.__htmxoThread;
    var s = {
      root: root,
      scroller: root.querySelector('.htmxo-thread-scroll'),
      items: root.querySelector('.htmxo-thread-items'),
      older: root.querySelector('.htmxo-thread-older'),
      pill: root.querySelector('.htmxo-thread-new'),
      status: root.querySelector('.htmxo-thread-status'),
      olderUrl: root.getAttribute('data-older-url'),
      tailUrl: root.getAttribute('data-tail-url'),
      pollMs: parseInt(root.getAttribute('data-poll') || '0', 10),
      since: root.getAttribute('data-since') || '',
      version: root.getAttribute('data-version') || '',
      stuck: true, unseen: 0, lastTop: 0, anchors: null, gen: 0, failures: 0,
      tailBusy: false, tailAgain: false, olderBusy: false, olderError: false,
      timer: null, dead: false, hiddenPaused: false
    };
    root.__htmxoThread = s;
    setOlder(s, s.older.getAttribute('data-cursor'), s.older.hasAttribute('data-done'));
    s.scroller.addEventListener('scroll', function () { onScroll(s); }, { passive: true });
    s.pill.addEventListener('click', function () {
      s.stuck = true;
      s.unseen = 0;
      s.scroller.scrollTo({ top: s.scroller.scrollHeight, behavior: 'smooth' });
      updatePill(s);
    });
    function retryOlder(e) {
      if (!e.target.closest('[role="button"]')) return;
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
      e.preventDefault();
      s.olderError = false;
      clearStatus(s);
      loadOlder(s);
    }
    s.older.addEventListener('click', retryOlder);
    s.older.addEventListener('keydown', retryOlder);
    var focus = root.getAttribute('data-focus'), target = focus && findKey(s, focus);
    if (target) {
      s.stuck = false;
      var sr = s.scroller.getBoundingClientRect(), tr = target.getBoundingClientRect();
      s.scroller.scrollTop += tr.top - sr.top - (s.scroller.clientHeight - tr.height) / 2;
      target.classList.add('htmxo-thread-focus');
      s.stuck = distance(s) <= STICK_PX;
    } else {
      stickBottom(s);
    }
    s.lastTop = s.scroller.scrollTop;
    s.anchors = s.stuck ? null : captureAnchors(s);
    s.ro = new ResizeObserver(function () { onResize(s); });
    s.ro.observe(s.items);
    s.ro.observe(s.scroller);
    s.io = new IntersectionObserver(function (entries) {
      if (entries.some(function (e) { return e.isIntersecting; })) loadOlder(s);
    }, { root: s.scroller, rootMargin: PREFETCH_PX + 'px 0px 0px 0px' });
    s.io.observe(s.older);
    updatePill(s);
    schedule(s);
    return s;
  }

  function threadsFor(target) {
    if (!target) return Array.prototype.slice.call(document.querySelectorAll('[data-htmxo-thread]'));
    var els = typeof target === 'string' ? document.querySelectorAll(target) : [target], out = [];
    Array.prototype.forEach.call(els, function (el) {
      var root = el.closest('[data-htmxo-thread]');
      if (root) out.push(root);
      else el.querySelectorAll('[data-htmxo-thread]').forEach(function (r) { out.push(r); });
    });
    return out;
  }

  window.htmxoThread = {
    init: init,
    refresh: function (target, opts) {
      threadsFor(target).forEach(function (root) { refresh(init(root), opts || {}); });
    }
  };

  function scan(node) {
    if (node.nodeType !== 1) return;
    if (node.hasAttribute('data-htmxo-thread')) init(node);
    if (node.firstElementChild) node.querySelectorAll('[data-htmxo-thread]').forEach(init);
  }
  function boot() {
    scan(document.body);
    new MutationObserver(function (records) {
      records.forEach(function (r) { r.addedNodes.forEach(scan); });
    }).observe(document.body, { childList: true, subtree: true });
    document.addEventListener('htmxo:thread-refresh', function (e) {
      var d = e.detail || {};
      window.htmxoThread.refresh(d.target || d.value || null, { bottom: !!d.bottom });
    });
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) return;
      threadsFor(null).forEach(function (root) {
        var s = root.__htmxoThread;
        if (s && s.hiddenPaused) { s.hiddenPaused = false; refresh(s); }
      });
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
"""))

"""
    live_thread_assets()

Style + script for [`live_thread`](@ref). Injected into the page head by
[`htmx`](@ref) when `thread=true` (the default); add it yourself to pages built
without `htmx(...)`.
"""
live_thread_assets() = (live_thread_styles(), live_thread_script())
