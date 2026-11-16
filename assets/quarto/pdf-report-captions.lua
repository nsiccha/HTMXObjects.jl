-- Quarto makes a figure of a fenced div only when its id starts with `fig-`
-- (a table with `tbl-`), so any other captioned figure, an id-less one in
-- particular, was a plain div: its picture and its caption were two blocks a
-- page break could separate, and the caption was not tagged as one. In a report
-- HTMXObjects writes `<!-- htmxo:caption -->` in such a figure just before its
-- caption (HTMX.jl writes the caption after every other child), and
-- `pdf_report` runs this filter on it:
--
-- * a figure of pictures alone becomes a Typst figure with what follows the
--   marker as its caption. A figure does not break across pages, so its
--   pictures and caption move to the next page together, and one taller than
--   a page has its pictures scaled down to fit (`pdf-report-figures.typ`);
-- * a figure holding a table becomes a table figure, its caption above it,
--   which breaks across pages like a captioned table (`pdf-report-tables.typ`);
-- * any other figure (prose, code, nested figures) stays the div it was, since
--   Typst would center its text and keep a long body from breaking.
--
-- Typst numbers none of them: a `numbered` document's captions carry their
-- numbers as text, and the page numbers no other figure. The div keeps its id,
-- which a link to the figure targets.
if not FORMAT:match('typst') then return {} end

local MARK = '<!-- htmxo:caption -->'

local function is_mark(block)
  return block.t == 'RawBlock' and block.format:match('^html') and block.text == MARK
end

-- The number of images `inlines` are, apart from spaces, line breaks and the
-- empty spans HTMX.jl writes as an image's anchor, or nil when they hold
-- anything else.
local function images(inlines)
  local n = 0
  for _, el in ipairs(inlines) do
    if el.t == 'Image' then
      n = n + 1
    elseif not (el.t == 'Space' or el.t == 'SoftBreak' or el.t == 'LineBreak' or
                (el.t == 'Span' and #el.content == 0)) then
      return nil
    end
  end
  return n
end

-- The number of pictures `blocks` hold when they hold nothing else, or nil.
local function pictures(blocks)
  local n = 0
  for _, block in ipairs(blocks) do
    if block.t == 'Para' or block.t == 'Plain' then
      local inner = images(block.content)
      if not inner then return nil end
      n = n + inner
    elseif block.t == 'Div' then
      local inner = pictures(block.content)
      if not inner then return nil end
      n = n + inner
    elseif block.t ~= 'RawBlock' then
      return nil
    end
  end
  return n
end

local function has_table(blocks)
  local found = false
  pandoc.Div(blocks):walk({ Table = function() found = true end })
  return found
end

local function figure(kind, position, caption, body)
  local blocks = pandoc.Blocks({ pandoc.RawBlock('typst',
    '#figure(kind: ' .. kind .. ', numbering: none, caption: figure.caption(position: ' .. position .. ')[') })
  blocks:extend(caption)
  blocks:insert(pandoc.RawBlock('typst', '])['))
  blocks:extend(body)
  blocks:insert(pandoc.RawBlock('typst', ']'))
  return blocks
end

function Div(el)
  local at
  for i, block in ipairs(el.content) do
    if is_mark(block) then at = i break end
  end
  if not at then return nil end
  local body = pandoc.Blocks({ table.unpack(el.content, 1, at - 1) })
  local caption = pandoc.Blocks({ table.unpack(el.content, at + 1) })
  -- A caption of one paragraph is written as Quarto writes a figure's, as text
  -- in the caption rather than a paragraph in it.
  if #caption == 1 and caption[1].t == 'Para' then caption[1] = pandoc.Plain(caption[1].content) end
  el.content:remove(at)
  if #caption > 0 then
    if has_table(body) then
      el.content = figure('table', 'top', caption, body)
    elseif (pictures(body) or 0) > 0 then
      el.content = figure('image', 'bottom', caption, body)
    end
  end
  return el
end
