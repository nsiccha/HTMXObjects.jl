-- Pandoc's Typst writer turns the typographic quotes “ ” ‘ ’ in text into
-- straight ones, for Typst to quote again by the document language. A German
-- „…“ keeps its „ but loses its “, which Typst then opens anew: „…„. And
-- ‚…‘ reads ‚…’. `pdf_report` runs this filter last: it hands those four
-- characters to Typst as raw text, so every quote reads as written. Straight
-- quotes in the Markdown stay Pandoc's quotes, which Typst quotes by `lang`.
if not FORMAT:match('typst') then return {} end

local AS_WRITTEN = { [0x201C] = true, [0x201D] = true, [0x2018] = true, [0x2019] = true }

function Str(el)
  local text, out, start = el.text, nil, 1
  for p, c in utf8.codes(text) do
    if AS_WRITTEN[c] then
      out = out or {}
      if p > start then table.insert(out, pandoc.Str(text:sub(start, p - 1))) end
      local q = utf8.char(c)
      table.insert(out, pandoc.RawInline('typst', q))
      start = p + #q
    end
  end
  if not out then return nil end
  if start <= #text then table.insert(out, pandoc.Str(text:sub(start))) end
  return out
end
