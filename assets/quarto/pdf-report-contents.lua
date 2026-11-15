-- A numbered document's contents list (HTMXObjects' `contents()`) is a list of
-- links in a `::: {.htmxo-contents}` block. In the PDF it becomes Typst's own
-- outline at the same place: it lists the same numbered headings, which carry
-- their numbers in their text, and adds their page numbers, which a list of
-- links cannot. `title` is the list's title and `depth` the deepest heading
-- level it lists.
local function typst_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

function Div(div)
  if not div.classes:includes('htmxo-contents') then return nil end
  local title = div.attributes['title'] or ''
  local depth = tonumber(div.attributes['depth'] or '') or 3
  return pandoc.RawBlock('typst', string.format('#outline(title: %s, depth: %d)', typst_string(title), depth))
end
