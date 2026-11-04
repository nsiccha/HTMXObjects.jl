# One reading per letter in the text layer of a PDF that Typst wrote.
#
# A letter with a combining mark and no precomposed form (R̂, x̄) is one cluster
# of two glyphs, the letter and the mark. Typst's layout starts a new text item
# whenever the vertical offset changes (`ShapedText::build` in
# typst-layout/src/inline/shaping.rs), and a mark the font raises sits at another
# offset, so each glyph becomes a text item that carries the whole cluster's text.
# The PDF writer then maps both glyphs to that text in the font's ToUnicode table,
# or wraps a glyph in an ActualText span when the table already says something
# else for it. Either way an extractor or a screen reader gets "R̂R̂" from a page
# that shows "R̂". veraPDF and PAC pass such a file. Upstream: typst/typst#8767,
# measured on Typst 0.15.1 with every font tried, with and without `ua-1`.
#
# The repair changes what such a cluster reads and nothing it draws:
#
# - The cluster's first glyph is wrapped in an ActualText span with the cluster's
#   text, and every other glyph in an empty one. A reader that honours ActualText
#   (Poppler, Acrobat, Chrome) gets the text once. A code point of the mark's own
#   would not do for it: Poppler orders a lone mark by where it is drawn, and in
#   some fonts that is before the letter (`̂R`) or after a gap (`R ̂`).
# - Each glyph gets its own code point in ToUnicode (the letter `R`, the mark
#   U+0302), for a reader that ignores ActualText (Firefox, Preview). Only in a
#   script written left to right, where the glyphs follow the code points.
#
# A report without such a cluster is left byte for byte as Typst wrote it. When
# Typst fixes this upstream, no cluster matches any more and the repair does
# nothing. Only a base followed by nonspacing marks counts; Typst's other clusters
# (a ligature, an Indic vowel drawn before its consonant) stay as they are.

const _PDF_RTL_BLOCKS = (0x0590:0x08FF, 0xFB1D:0xFDFF, 0xFE70:0xFEFF, 0x10800:0x10FFF, 0x1E800:0x1EFFF)

_pdf_is_mark(c::Char) = Base.Unicode.category_code(c) in
    (Base.Unicode.UTF8PROC_CATEGORY_MN, Base.Unicode.UTF8PROC_CATEGORY_ME)
_pdf_is_rtl(c::Char) = any(block -> UInt32(c) in block, _PDF_RTL_BLOCKS)

# The code points of a cluster this repair handles, or `nothing`.
function _pdf_cluster_codepoints(text::AbstractString)
    codepoints = collect(text)
    length(codepoints) >= 2 || return nothing
    _pdf_is_mark(first(codepoints)) && return nothing
    all(_pdf_is_mark, @view codepoints[2:end]) || return nothing
    return codepoints
end

# --- The file's objects ---

struct _PdfFile
    bytes::Vector{UInt8}
    ranges::Dict{Int,UnitRange{Int}}  # object number => its bytes, `n 0 obj` to the next object
    xref::Int                         # where the cross-reference table starts
    trailer::UnitRange{Int}           # `trailer` up to `startxref`
end

# Typst writes one cross-reference table of consecutive objects, no object
# streams and no earlier revisions. Any other layout answers `nothing`.
function _pdf_file(bytes::Vector{UInt8})
    tail = String(bytes[max(1, length(bytes) - 2047):end])
    m = match(r"startxref\s+(\d+)\s+%%EOF\s*$", tail)
    isnothing(m) && return nothing
    xref = parse(Int, m[1]) + 1
    checkbounds(Bool, bytes, xref:xref+3) && bytes[xref:xref+3] == b"xref" || return nothing
    start_of_trailer = findfirst(b"trailer", @view bytes[xref:end])
    isnothing(start_of_trailer) && return nothing
    trailer_start = xref + first(start_of_trailer) - 1
    start_of_mark = findfirst(b"startxref", @view bytes[trailer_start:end])
    isnothing(start_of_mark) && return nothing
    tokens = split(String(bytes[xref+4:trailer_start-1]))
    length(tokens) >= 2 && tokens[1] == "0" || return nothing
    count = parse(Int, tokens[2])
    length(tokens) == 2 + 3count || return nothing
    offsets = Pair{Int,Int}[]
    for number in 1:count-1
        at = 3 + 3number
        tokens[at+2] == "n" && tokens[at+1] == "00000" || return nothing
        push!(offsets, number => parse(Int, tokens[at]) + 1)
    end
    sort!(offsets; by=last)
    ranges = Dict{Int,UnitRange{Int}}()
    for (i, (number, offset)) in enumerate(offsets)
        stop = i == length(offsets) ? xref - 1 : last(offsets[i+1]) - 1
        ranges[number] = offset:stop
    end
    return _PdfFile(bytes, ranges, xref, trailer_start:trailer_start+first(start_of_mark)-2)
end

_pdf_object_text(file::_PdfFile, number) = String(file.bytes[file.ranges[number]])

# An object's dictionary and where its stream's bytes are, within the object.
function _pdf_stream_span(text::AbstractString)
    m = match(r">>\s*stream\r?\n", text)
    isnothing(m) && return nothing
    head = String(codeunits(text)[1:m.offset+1])
    length_match = match(r"/Length\s+(\d+)", head)
    isnothing(length_match) && return nothing
    start = m.offset + ncodeunits(m.match)
    return (; head, data=start:start+parse(Int, length_match[1])-1)
end

# A stream's decoded bytes, or `nothing` for a filter this repair does not read.
function _pdf_stream_data(file::_PdfFile, number)
    text = _pdf_object_text(file, number)
    span = _pdf_stream_span(text)
    isnothing(span) && return nothing
    raw = Vector{UInt8}(codeunits(text)[span.data])
    occursin("/Filter", span.head) || return raw
    occursin(r"/Filter\s*/FlateDecode\b", span.head) && !occursin("/DecodeParms", span.head) || return nothing
    return transcode(CodecZlib.ZlibDecompressor, raw)
end

# The object with its stream replaced by `data`, deflated, and `/Length` to match.
function _pdf_object_with_stream(file::_PdfFile, number, data::Vector{UInt8})
    text = _pdf_object_text(file, number)
    span = _pdf_stream_span(text)
    units = codeunits(text)
    deflated = transcode(CodecZlib.ZlibCompressor, data)
    before = replace(String(units[1:first(span.data)-1]), r"/Length\s+\d+" => "/Length $(length(deflated))"; count=1)
    return vcat(Vector{UInt8}(codeunits(before)), deflated, Vector{UInt8}(units[last(span.data)+1:end]))
end

# The file with these objects replaced, its table written anew.
function _pdf_rebuilt(file::_PdfFile, replaced::Dict{Int,Vector{UInt8}})
    numbers = sort!(collect(keys(file.ranges)); by=number -> first(file.ranges[number]))
    out = IOBuffer()
    write(out, @view file.bytes[1:first(file.ranges[first(numbers)])-1])
    offsets = Dict{Int,Int}()
    for number in numbers
        offsets[number] = position(out)
        new = get(replaced, number, nothing)
        isnothing(new) ? write(out, @view file.bytes[file.ranges[number]]) : write(out, new)
    end
    xref = position(out)
    count = length(numbers) + 1
    write(out, "xref\n0 $count\n0000000000 65535 f \n")
    for number in 1:count-1
        write(out, lpad(offsets[number], 10, '0'), " 00000 n \n")
    end
    write(out, @view file.bytes[file.trailer])
    write(out, "startxref\n$xref\n%%EOF\n")
    return take!(out)
end

# --- The ToUnicode tables ---

_pdf_utf16be_hex(text::AbstractString) = uppercase(join(string(unit; base=16, pad=4) for unit in transcode(UInt16, String(text))))

function _pdf_utf16be_text(bytes::AbstractVector{UInt8})
    isodd(length(bytes)) && return nothing
    units = [UInt16(bytes[i]) << 8 | bytes[i+1] for i in 1:2:length(bytes)-1]
    return transcode(String, units)
end

const _PDF_BFCHAR_BLOCK = r"beginbfchar(.*?)endbfchar"s
const _PDF_BFCHAR_ENTRY = r"<([0-9A-Fa-f]+)>(\s*)<([0-9A-Fa-f]*)>"

# Glyph code => text, or `nothing` for a table that is not plain bfchar entries.
function _pdf_to_unicode(cmap::AbstractString)
    occursin("beginbfrange", cmap) && return nothing
    table = Dict{UInt16,String}()
    for block in eachmatch(_PDF_BFCHAR_BLOCK, cmap), entry in eachmatch(_PDF_BFCHAR_ENTRY, block[1])
        text = _pdf_utf16be_text(hex2bytes(isodd(ncodeunits(entry[3])) ? "0" * entry[3] : entry[3]))
        isnothing(text) && return nothing
        table[parse(UInt16, entry[1]; base=16)] = text
    end
    return table
end

function _pdf_to_unicode_with(cmap::AbstractString, changes::Dict{UInt16,String})
    replace(cmap, _PDF_BFCHAR_BLOCK => function (block)
        replace(block, _PDF_BFCHAR_ENTRY => function (entry)
            m = match(_PDF_BFCHAR_ENTRY, entry)
            text = get(changes, parse(UInt16, m[1]; base=16), nothing)
            isnothing(text) ? entry : "<$(m[1])>$(m[2])<$(_pdf_utf16be_hex(text))>"
        end)
    end)
end

# --- The content streams ---

struct _PdfSpan
    start::Int   # the span's opening operator, operands first
    stop::Int
    text::Union{Nothing,String}  # its ActualText
end

# One Tj or TJ operator: its bytes, and its strings and numbers in order. A number
# is the range of its bytes in the stream.
struct _PdfShow
    start::Int
    stop::Int
    elements::Vector{Union{UnitRange{Int},Vector{UInt8}}}
end

struct _PdfGlyph
    font::Int     # the font's object number, 0 for a font this repair does not read
    code::UInt16
    span::Int     # the innermost ActualText span around it, 0 if none
    show::Int     # its operator
    element::Int  # its string among the operator's elements
    index::Int    # its place in that string, counted in glyphs
end

_pdf_is_space(c::UInt8) = c in (0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20)
_pdf_is_delimiter(c::UInt8) = c in b"()<>[]{}/%"

const _PDF_STRING_ESCAPES = Dict(UInt8('n') => 0x0a, UInt8('r') => 0x0d, UInt8('t') => 0x09, UInt8('b') => 0x08, UInt8('f') => 0x0c)

# A literal string starting at `i`: its bytes and the position after it.
function _pdf_literal_string(b::Vector{UInt8}, i::Int)
    out = UInt8[]
    depth = 1
    i += 1
    while i <= length(b)
        c = b[i]
        if c == UInt8('\\')
            i += 1
            i > length(b) && break
            e = b[i]
            if UInt8('0') <= e <= UInt8('7')
                value = 0
                digits = 0
                while i <= length(b) && digits < 3 && UInt8('0') <= b[i] <= UInt8('7')
                    value = 8value + Int(b[i] - UInt8('0'))
                    digits += 1
                    i += 1
                end
                push!(out, UInt8(value & 0xff))
                continue
            elseif e == UInt8('\r')
                i + 1 <= length(b) && b[i+1] == UInt8('\n') && (i += 1)
            elseif e != UInt8('\n')
                push!(out, get(_PDF_STRING_ESCAPES, e, e))
            end
        elseif c == UInt8('(')
            depth += 1
            push!(out, c)
        elseif c == UInt8(')')
            depth -= 1
            depth == 0 && return out, i + 1
            push!(out, c)
        else
            push!(out, c)
        end
        i += 1
    end
    return nothing, i
end

# A hexadecimal string starting at `i`: its bytes and the position after it.
function _pdf_hex_string(b::Vector{UInt8}, i::Int)
    close = findnext(==(UInt8('>')), b, i)
    isnothing(close) && return nothing, length(b) + 1
    digits = filter(!_pdf_is_space, b[i+1:close-1])
    all(c -> UInt8('0') <= c <= UInt8('9') || UInt8('a') <= c | 0x20 <= UInt8('f'), digits) || return nothing, close + 1
    isodd(length(digits)) && push!(digits, UInt8('0'))
    return hex2bytes(digits), close + 1
end

function _pdf_actual_text(bytes::Vector{UInt8})
    length(bytes) >= 2 && bytes[1] == 0xfe && bytes[2] == 0xff && return _pdf_utf16be_text(@view bytes[3:end])
    length(bytes) >= 3 && bytes[1:3] == [0xef, 0xbb, 0xbf] && return String(bytes[4:end])
    return String([Char(c) for c in bytes])  # the ASCII range of PDFDocEncoding is all Typst writes this way
end

# The glyphs a content stream shows, in order, with its operators and its
# marked-content spans, or `nothing` for a stream this repair cannot follow.
function _pdf_scan_content(b::Vector{UInt8}, fonts::Dict{String,Int})
    glyphs = _PdfGlyph[]
    shows = _PdfShow[]
    spans = _PdfSpan[]
    open_spans = Int[]
    elements = Union{UnitRange{Int},Vector{UInt8}}[]
    name = ""        # the last name operand
    font = 0
    operands_start = 0
    pending_text = nothing   # the ActualText of the dictionary being read
    expect_text = false
    i = 1
    n = length(b)
    begin_operand!(at) = operands_start == 0 && (operands_start = at)
    while i <= n
        c = b[i]
        if _pdf_is_space(c)
            i += 1
        elseif c == UInt8('%')
            while i <= n && b[i] != 0x0a && b[i] != 0x0d
                i += 1
            end
        elseif c == UInt8('/')
            begin_operand!(i)
            j = i + 1
            while j <= n && !_pdf_is_space(b[j]) && !_pdf_is_delimiter(b[j])
                j += 1
            end
            word = String(b[i+1:j-1])
            expect_text = word == "ActualText"
            expect_text || (name = word)
            i = j
        elseif c == UInt8('(') || (c == UInt8('<') && !(i < n && b[i+1] == UInt8('<')))
            begin_operand!(i)
            bytes, i = c == UInt8('(') ? _pdf_literal_string(b, i) : _pdf_hex_string(b, i)
            isnothing(bytes) && return nothing
            if expect_text
                pending_text = _pdf_actual_text(bytes)
                expect_text = false
            else
                push!(elements, bytes)
            end
        elseif c == UInt8('<') || c == UInt8('>')
            begin_operand!(i)
            i += 2
        elseif c == UInt8('[') || c == UInt8(']') || c == UInt8('{') || c == UInt8('}')
            begin_operand!(i)
            i += 1
        elseif c == UInt8(')')
            return nothing
        elseif UInt8('0') <= c <= UInt8('9') || c == UInt8('+') || c == UInt8('-') || c == UInt8('.')
            begin_operand!(i)
            j = i
            while j <= n && !_pdf_is_space(b[j]) && !_pdf_is_delimiter(b[j])
                j += 1
            end
            push!(elements, i:j-1)
            i = j
        else
            j = i
            while j <= n && !_pdf_is_space(b[j]) && !_pdf_is_delimiter(b[j])
                j += 1
            end
            operator = String(b[i:j-1])
            if operator == "Tf"
                font = get(fonts, name, 0)
            elseif operator == "Tj" || operator == "TJ"
                span = 0
                for s in Iterators.reverse(open_spans)
                    isnothing(spans[s].text) && continue
                    span = s
                    break
                end
                push!(shows, _PdfShow(operands_start, j - 1, copy(elements)))
                for (e, element) in enumerate(elements)
                    element isa UnitRange && continue
                    if font == 0 || isodd(length(element))
                        push!(glyphs, _PdfGlyph(0, 0x0000, span, length(shows), e, 0))
                    else
                        for k in 1:length(element)÷2
                            code = UInt16(element[2k-1]) << 8 | element[2k]
                            push!(glyphs, _PdfGlyph(font, code, span, length(shows), e, k))
                        end
                    end
                end
            elseif operator == "'" || operator == "\"" || operator == "BI"
                return nothing  # Typst writes none of these; its layout here is not known
            elseif operator == "BDC" || operator == "BMC"
                push!(spans, _PdfSpan(operands_start == 0 ? i : operands_start, j - 1, pending_text))
                push!(open_spans, length(spans))
            elseif operator == "EMC"
                isempty(open_spans) && return nothing
                pop!(open_spans)
            end
            empty!(elements)
            operands_start = 0
            pending_text = nothing
            expect_text = false
            i = j
        end
    end
    isempty(open_spans) || return nothing
    return (; glyphs, shows, spans)
end

_pdf_actual_text_operator(text::AbstractString) =
    isempty(text) ? "/Span<</ActualText()>>BDC" : "/Span<</ActualText<FEFF$(_pdf_utf16be_hex(text))>>>BDC"

# The operator as several TJ, each glyph in `texts` alone in a span of that text.
# TJ moves the pen by each glyph and number in turn, so this draws the same.
function _pdf_show_split(data::Vector{UInt8}, show::_PdfShow, texts::Dict{Tuple{Int,Int},String})
    out = IOBuffer()
    array = IOBuffer()
    function flush_array!()
        position(array) == 0 && return
        write(out, '[', take!(array), "]TJ ")
    end
    for (e, element) in enumerate(show.elements)
        if element isa UnitRange
            write(array, @view(data[element]), ' ')
        else
            for k in 1:length(element)÷2
                hex = bytes2hex(@view element[2k-1:2k])
                text = get(texts, (e, k), nothing)
                if isnothing(text)
                    write(array, '<', hex, '>')
                else
                    flush_array!()
                    write(out, _pdf_actual_text_operator(text), " [<", hex, ">]TJ EMC ")
                end
            end
        end
    end
    flush_array!()
    return take!(out)
end

# --- Which objects hold text ---

function _pdf_font_names(file::_PdfFile, dictionary::AbstractString)
    m = match(r"/Resources\s+(\d+)\s+0\s+R", dictionary)
    resources = isnothing(m) ? dictionary : _pdf_object_text(file, parse(Int, m[1]))
    fonts = match(r"/Font\s*<<(.*?)>>"s, resources)
    if isnothing(fonts)
        ref = match(r"/Font\s+(\d+)\s+0\s+R", resources)
        isnothing(ref) && return Dict{String,Int}()
        table = _pdf_object_text(file, parse(Int, ref[1]))
    else
        table = fonts[1]
    end
    return Dict{String,Int}(String(e[1]) => parse(Int, e[2]) for e in eachmatch(r"/([^\s/<>\[\]()]+)\s+(\d+)\s+0\s+R", table))
end

# Every content stream: (object number, the fonts its names stand for).
function _pdf_content_streams(file::_PdfFile)
    found = Pair{Int,Dict{String,Int}}[]
    for number in sort!(collect(keys(file.ranges)))
        text = _pdf_object_text(file, number)
        stream = _pdf_stream_span(text)
        if !isnothing(stream)
            # A form or a tiling pattern: a stream with resources of its own.
            occursin("/Resources", stream.head) && push!(found, number => _pdf_font_names(file, stream.head))
        elseif occursin(r"/Type\s*/Page\b", text)
            single = match(r"/Contents\s+(\d+)\s+0\s+R", text)
            several = match(r"/Contents\s*\[([^\]]*)\]", text)
            references = !isnothing(single) ? [single[1]] :
                         !isnothing(several) ? [e[1] for e in eachmatch(r"(\d+)\s+0\s+R", several[1])] : SubString{String}[]
            names = _pdf_font_names(file, text)
            for reference in references
                push!(found, parse(Int, reference) => names)
            end
        end
    end
    return found
end

# The ToUnicode table of each Type 0 font: font object => (table object, table).
function _pdf_fonts(file::_PdfFile, streams)
    fonts = Dict{Int,@NamedTuple{object::Int,table::Dict{UInt16,String}}}()
    for font in unique(number for (_, names) in streams for number in values(names))
        haskey(file.ranges, font) || continue
        text = _pdf_object_text(file, font)
        occursin(r"/Subtype\s*/Type0\b", text) || continue
        m = match(r"/ToUnicode\s+(\d+)\s+0\s+R", text)
        isnothing(m) && continue
        object = parse(Int, m[1])
        data = _pdf_stream_data(file, object)
        isnothing(data) && continue
        table = _pdf_to_unicode(String(data))
        isnothing(table) || (fonts[font] = (; object, table))
    end
    return fonts
end

# --- The repair ---

"""
    _pdf_text_layer_repaired(bytes) -> Union{Nothing,Vector{UInt8}}

The PDF `bytes` with every letter that carries combining marks reading once in
its text layer, or `nothing` when it needs no change or this repair cannot read
it. See the note at the top of this file. A cluster with more glyphs than code
points stays as it is, since it cannot be told from two clusters in a row, and
`@warn` names it.
"""
function _pdf_text_layer_repaired(bytes::Vector{UInt8})
    unreadable() = @warn "pdf_report: could not read the structure of the PDF Quarto wrote, so a letter with a " *
        "combining mark may read twice in its text layer (typst/typst#8767). Check it with `pdftotext`."
    file = _pdf_file(bytes)
    isnothing(file) && (unreadable(); return nothing)
    streams = _pdf_content_streams(file)
    fonts = _pdf_fonts(file, streams)
    scans = Pair{Int,Any}[]
    for (number, names) in streams
        haskey(file.ranges, number) || continue
        data = _pdf_stream_data(file, number)
        isnothing(data) && (unreadable(); return nothing)
        readable = Dict{String,Int}(name => font for (name, font) in names if haskey(fonts, font))
        scan = _pdf_scan_content(data, readable)
        isnothing(scan) && (unreadable(); return nothing)
        push!(scans, number => (; data, scan...))
    end

    glyph_text(scan, g) = g.font == 0 ? nothing :
        g.span != 0 ? scan.spans[g.span].text : get(fonts[g.font].table, g.code, nothing)

    # Consecutive glyphs with one text are its clusters; the first glyph's return
    # starts the next one, so "R̂R̂" is two clusters of two glyphs.
    clusters = @NamedTuple{stream::Int,text::String,codepoints::Vector{Char},glyphs::UnitRange{Int}}[]
    for (at, (_, scan)) in enumerate(scans)
        glyphs = scan.glyphs
        i = 1
        while i <= length(glyphs)
            text = glyph_text(scan, glyphs[i])
            codepoints = isnothing(text) ? nothing : _pdf_cluster_codepoints(text)
            if isnothing(codepoints)
                i += 1
                continue
            end
            j = i
            while j < length(glyphs) && glyph_text(scan, glyphs[j+1]) == text
                j += 1
            end
            start = i
            for k in i+1:j+1
                if k == j + 1 || (glyphs[k].font, glyphs[k].code) == (glyphs[i].font, glyphs[i].code)
                    push!(clusters, (; stream=at, text, codepoints, glyphs=start:k-1))
                    start = k
                end
            end
            i = j + 1
        end
    end

    # A glyph's own code point: the last glyph takes the code points left over.
    own_text(c, index) = index < length(c.glyphs) ? string(c.codepoints[index]) : join(c.codepoints[index:end])
    glyph_key(c, index) = let g = scans[c.stream].second.glyphs[c.glyphs[index]]
        (g.font, g.code)
    end
    wants = Dict{Tuple{Int,UInt16},Set{String}}()
    whole = Set{Tuple{Int,UInt16}}()   # a glyph that draws a whole cluster
    separate = eltype(clusters)[]      # clusters read once per glyph
    named = eltype(clusters)[]         # clusters whose glyphs get their own code points
    left = Set{String}()
    for c in clusters
        scan = scans[c.stream].second
        if length(c.glyphs) == 1
            push!(whole, glyph_key(c, 1))
            continue
        end
        spans = unique(scan.glyphs[g].span for g in c.glyphs)
        once = length(spans) == 1 && only(spans) != 0  # one span around them all
        if length(c.glyphs) > length(c.codepoints)
            once || push!(left, c.text)
            continue
        end
        once || push!(separate, c)
        if !_pdf_is_rtl(first(c.codepoints))
            push!(named, c)
            for index in eachindex(c.glyphs)
                push!(get!(Set{String}, wants, glyph_key(c, index)), own_text(c, index))
            end
        end
    end
    isempty(left) || @warn "pdf_report: these letters still read twice in the PDF's text layer, because the font " *
        "draws them with more glyphs than they have code points (typst/typst#8767): $(join(sort!(collect(left)), ", "))"
    isempty(separate) && return nothing

    # A glyph keeps the table's entry when it draws a whole cluster elsewhere,
    # reads something else already, or would have to read two things. The spans
    # below still make its cluster read once.
    function settled(key)
        key in whole && return false
        length(wants[key]) == 1 || return false
        current = get(fonts[first(key)].table, last(key), nothing)
        isnothing(current) && return false
        return current == only(wants[key]) || !isnothing(_pdf_cluster_codepoints(current))
    end
    changes = Dict{Int,Dict{UInt16,String}}()
    for (key, texts) in wants
        settled(key) || continue
        fonts[first(key)].table[last(key)] == only(texts) && continue
        get!(Dict{UInt16,String}, changes, first(key))[last(key)] = only(texts)
    end
    replaced = Dict{Int,Vector{UInt8}}()
    for (font, change) in changes
        object = fonts[font].object
        cmap = String(_pdf_stream_data(file, object))
        replaced[object] = _pdf_object_with_stream(file, object, Vector{UInt8}(codeunits(_pdf_to_unicode_with(cmap, change))))
    end

    # The spans: the first glyph reads the cluster, every other glyph nothing.
    wrapped = Dict{Int,Dict{Int,Dict{Tuple{Int,Int},String}}}()  # stream => show => (element, index) => text
    emptied = Dict{Int,Set{Int}}()                               # stream => spans
    for c in separate
        scan = scans[c.stream].second
        first_span = scan.glyphs[first(c.glyphs)].span
        for (position, g) in enumerate(c.glyphs)
            glyph = scan.glyphs[g]
            if glyph.span != 0
                position == 1 || glyph.span == first_span || push!(get!(Set{Int}, emptied, c.stream), glyph.span)
            else
                shows = get!(Dict{Int,Dict{Tuple{Int,Int},String}}, wrapped, c.stream)
                get!(Dict{Tuple{Int,Int},String}, shows, glyph.show)[(glyph.element, glyph.index)] =
                    position == 1 ? c.text : ""
            end
        end
    end
    for at in union(keys(wrapped), keys(emptied))
        number, scan = scans[at]
        edits = Pair{UnitRange{Int},Vector{UInt8}}[]
        for (show, texts) in get(wrapped, at, Dict{Int,Dict{Tuple{Int,Int},String}}())
            operator = scan.shows[show]
            push!(edits, operator.start:operator.stop => _pdf_show_split(scan.data, operator, texts))
        end
        for s in get(emptied, at, Set{Int}())
            span = scan.spans[s]
            push!(edits, span.start:span.stop => Vector{UInt8}(codeunits(_pdf_actual_text_operator(""))))
        end
        sort!(edits; by=edit -> first(first(edit)))
        out = IOBuffer()
        from = 1
        for (range, new) in edits
            write(out, @view scan.data[from:first(range)-1])
            write(out, new)
            from = last(range) + 1
        end
        write(out, @view scan.data[from:end])
        replaced[number] = _pdf_object_with_stream(file, number, take!(out))
    end
    return _pdf_rebuilt(file, replaced)
end

function _pdf_repair_text_layer!(path::AbstractString)
    repaired = _pdf_text_layer_repaired(read(path))
    isnothing(repaired) || write(path, repaired)
    return path
end
