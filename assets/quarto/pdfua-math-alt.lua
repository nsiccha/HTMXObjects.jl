-- PDF/UA-1 requires alt text on every equation, and Pandoc's Typst writer
-- emits none, so Typst refuses the document. `pdf_report` runs this filter:
-- it wraps each equation in a scoped `set math.equation(alt: …)` that carries
-- the equation's TeX source.
if not FORMAT:match('typst') then return {} end

local function typst_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' ') .. '"'
end

function Math(el)
  local typ = pandoc.write(pandoc.Pandoc({ pandoc.Plain({ el }) }), 'typst')
  typ = typ:gsub('%s+$', '')
  return pandoc.RawInline('typst',
    '#[#set math.equation(alt: ' .. typst_string(el.text) .. ');' .. typ .. ']')
end
