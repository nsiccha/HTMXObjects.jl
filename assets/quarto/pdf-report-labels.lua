-- SemanticDisclosure (including eager tab and master-detail labels) marks
-- its bold label separately from its body, and a block of private content
-- opens with its audience label (`*not public*`). Keep either label with the
-- next block, without keeping the whole body on a page or treating bold or
-- emphasised prose as a label. Inherit paragraph spacing instead of block's
-- larger default.
-- Pandoc still renders the label's text and escapes it for Typst.
if not FORMAT:match('typst') then return {} end

local function sticky(content)
  local blocks = pandoc.Blocks({pandoc.RawBlock('typst', '#block(spacing: auto, sticky: true)[')})
  blocks:extend(content)
  blocks:insert(pandoc.RawBlock('typst', ']'))
  return blocks
end

-- The label `private` writes first in its fenced div: a paragraph that is one
-- emphasised span, in the language of the page.
local function private_label(block)
  return block.t == 'Para' and #block.content == 1 and block.content[1].t == 'Emph'
end

function Div(el)
  if el.classes:includes('htmxo-label') then
    return sticky(el.content)
  end
  if el.classes:includes('htmxo-private') and #el.content > 1 and private_label(el.content[1]) then
    local blocks = sticky({el.content[1]})
    for i = 2, #el.content do blocks:insert(el.content[i]) end
    el.content = blocks
    return el
  end
end
