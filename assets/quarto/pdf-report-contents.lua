-- A numbered document's contents list (HTMXObjects' `contents()`) is a list of
-- links in a `::: {.htmxo-contents}` block. In the PDF it becomes Typst's own
-- outline at the same place: it lists the same numbered headings, which carry
-- their numbers in their text, and adds their page numbers, which a list of
-- links cannot. `title` is the list's title and `depth` the deepest heading
-- level it lists.
--
-- Typst's outline lists every heading, and a report has headings the contents
-- list does not: an article's header, a plain `h2` in a view, repeated once per
-- state a report shows. A report's Markdown marks the headings the contents
-- list lists with the class `htmxo-contents-entry` (its sections, and a section
-- written outside the numbered document), so the outline lists those alone.
-- Every other heading stays a heading of the body and a bookmark of the PDF.
-- Markdown that marks no heading keeps Typst's outline of every heading.
local function typst_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function outline(div, labels)
  local title = div.attributes['title'] or ''
  local depth = tonumber(div.attributes['depth'] or '') or 3
  local target = ''
  if #labels > 0 then
    local parts = {}
    for i, id in ipairs(labels) do parts[i] = 'label(' .. typst_string(id) .. ')' end
    target = ', target: selector.or(' .. table.concat(parts, ', ') .. ')'
  end
  return pandoc.RawBlock('typst', string.format('#outline(title: %s, depth: %d%s)', typst_string(title), depth, target))
end

function Pandoc(doc)
  local labels, seen = {}, {}
  doc:walk({
    Header = function(header)
      local id = header.identifier
      if header.classes:includes('htmxo-contents-entry') and id ~= '' and not seen[id] then
        seen[id] = true
        labels[#labels + 1] = id
      end
    end,
  })
  return doc:walk({
    Div = function(div)
      if div.classes:includes('htmxo-contents') then return outline(div, labels) end
    end,
  })
end
