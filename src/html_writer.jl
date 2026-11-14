# HTML serialization without a doubling buffer.
#
# `repr(MIME"text/html"(), x)` writes into one `IOBuffer` that starts at 32
# bytes and doubles each time it fills. A page of n bytes therefore allocates
# 2n to 4n before the answer exists: 19 MB for a 5.2 MB page. Every
# `HTMLSnapshot` inside it is copied again at each doubling, although its bytes
# were serialized once already (snag `html-response-bu-1c2ff016`).
#
# `_HTMLWriter` is the sink that `_html_repr` writes into instead:
#
# - a `String` of `_HTML_RETAIN_BYTES` or more (a snapshot's stored bytes, a
#   `Raw` block, a long text run) is kept by reference; a string is immutable,
#   so the reference reads the same bytes when the answer is assembled;
# - every other write is copied into chunks that never move once allocated;
# - `_html_take!` assembles the pieces once, at the exact size.
#
# A page then allocates its own size once, plus the chunks that hold its newly
# generated markup. The bytes are those `repr` writes: the same `show` methods
# run in the same order, and only the destination differs.

const _HTML_RETAIN_BYTES = 512
const _HTML_FIRST_CHUNK = 256
const _HTML_MAX_CHUNK = 64 * 1024

mutable struct _HTMLWriter <: IO
    # Generated markup in write order. Every chunk but the last is full.
    chunks::Vector{Vector{UInt8}}
    used::Int      # bytes written into chunks[end]
    copied::Int    # bytes written into all chunks
    # Retained strings, each with the number of copied bytes written before it.
    retained::Vector{Pair{Int,Union{String,SubString{String}}}}
    size::Int      # bytes written in total
end

_HTMLWriter() = _HTMLWriter(Vector{UInt8}[], 0, 0, Pair{Int,Union{String,SubString{String}}}[], 0)

Base.iswritable(::_HTMLWriter) = true
Base.position(w::_HTMLWriter) = w.size

# The last chunk if it has room, or a new one. Chunks start small, so a short
# fragment stays cheap, and double up to `_HTML_MAX_CHUNK`, so a long page
# holds at most one partly empty chunk of that size.
function _html_room!(w::_HTMLWriter)
    if isempty(w.chunks) || w.used == length(w.chunks[end])
        n = isempty(w.chunks) ? _HTML_FIRST_CHUNK : min(2 * length(w.chunks[end]), _HTML_MAX_CHUNK)
        push!(w.chunks, Vector{UInt8}(undef, n))
        w.used = 0
    end
    return w.chunks[end]
end

function Base.unsafe_write(w::_HTMLWriter, p::Ptr{UInt8}, n::UInt)
    left = Int(n)
    while left > 0
        chunk = _html_room!(w)
        k = min(left, length(chunk) - w.used)
        GC.@preserve chunk unsafe_copyto!(pointer(chunk, w.used + 1), p, k)
        w.used += k
        p += k
        left -= k
    end
    w.copied += Int(n)
    w.size += Int(n)
    return n
end

function Base.write(w::_HTMLWriter, b::UInt8)
    chunk = _html_room!(w)
    @inbounds chunk[w.used+1] = b
    w.used += 1
    w.copied += 1
    w.size += 1
    return 1
end

function Base.write(w::_HTMLWriter, s::Union{String,SubString{String}})
    n = ncodeunits(s)
    n < _HTML_RETAIN_BYTES && return GC.@preserve s Int(unsafe_write(w, pointer(s), UInt(n)))
    push!(w.retained, w.copied => s)
    w.size += n
    return n
end

# Move the next `n` copied bytes, starting at chunk `ci`, offset `off`, to `out`.
function _html_copy_chunks!(out::IO, w::_HTMLWriter, ci::Int, off::Int, n::Int)
    while n > 0
        chunk = w.chunks[ci]
        if off == length(chunk)
            ci += 1
            off = 0
            continue
        end
        k = min(n, length(chunk) - off)
        GC.@preserve chunk unsafe_write(out, pointer(chunk, off + 1), UInt(k))
        off += k
        n -= k
    end
    return ci, off
end

# The written HTML as one `String`, allocated once at its exact size.
function _html_take!(w::_HTMLWriter)
    out = IOBuffer(; sizehint=w.size)
    ci, off, copied = 1, 0, 0
    for (at, s) in w.retained
        ci, off = _html_copy_chunks!(out, w, ci, off, at - copied)
        copied = at
        write(out, s)
    end
    _html_copy_chunks!(out, w, ci, off, w.copied - copied)
    return String(take!(out))
end

# `repr(MIME"text/html"(), x)`, written through an `_HTMLWriter`: the result is
# allocated once at its exact size, and a large retained string inside `x` (an
# `HTMLSnapshot`'s bytes) is copied once. Text passes through untouched, as
# `repr` passes it.
function _html_repr(x)
    w = _HTMLWriter()
    show(w, MIME"text/html"(), x)
    return _html_take!(w)
end
_html_repr(x::AbstractString) = repr(MIME"text/html"(), x)
