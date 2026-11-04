-- PDF/UA-1 requires alt text on every equation, and Pandoc's Typst writer
-- emits none, so Typst refuses the document. `pdf_report` runs this filter:
-- it wraps each equation in a scoped `set math.equation(alt: …)` that carries
-- the equation's TeX source.
if not FORMAT:match('typst') then return {} end

local function typst_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' ') .. '"'
end

-- A ```math fence is display math in the browser (`render_markdown`); Pandoc
-- reads it as code. It runs first, so the formula gets its alt text below.
local function math_fence(el)
  if el.classes:includes('math') then
    return pandoc.Para({ pandoc.Math('DisplayMath', el.text) })
  end
end

-- Pandoc's Typst writer rounds a space it has no Typst name for down to whole
-- ems: `\!` (-1/6 em) becomes `#h(-1em)`, which overprints what stands before
-- it, and `\;` (5/18 em) becomes `#h(0em)`. So the two reach the writer as text
-- it cannot round, which is replaced in its output.
local NEG_THIN, THICK = 'HTMXOPDFNEGTHIN', 'HTMXOPDFTHICK'

local function marked_spaces(tex)
  -- A pair of backslashes is a line break, so only an odd run starts a command.
  return (tex:gsub('(\\+)([!;])', function(run, command)
    if #run % 2 == 0 then return nil end
    return run:sub(2) .. '\\text{' .. (command == '!' and NEG_THIN or THICK) .. '}'
  end))
end

local function typst_math(el)
  local function write(tex)
    local doc = pandoc.Pandoc({ pandoc.Plain({ pandoc.Math(el.mathtype, tex) }) })
    return (pandoc.write(doc, 'typst'):gsub('%s+$', ''))
  end
  local typ = write(marked_spaces(el.text))
  -- A formula the writer cannot convert comes back as its source: keep that clean.
  if typ:find(NEG_THIN .. '}', 1, true) or typ:find(THICK .. '}', 1, true) then
    return write(el.text)
  end
  return (typ:gsub('upright%("' .. NEG_THIN .. '"%)', '#h(-1em/6)'):gsub('upright%("' .. THICK .. '"%)', 'thick'))
end

local function equation_alt(el)
  return pandoc.RawInline('typst',
    '#[#set math.equation(alt: ' .. typst_string(el.text) .. ');' .. typst_math(el) .. ']')
end

return { { CodeBlock = math_fence }, { Math = equation_alt } }
