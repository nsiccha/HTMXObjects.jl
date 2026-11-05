-- SemanticDisclosure (including eager tab and master-detail labels) marks
-- its bold label separately from its body. Keep that label with the next
-- block, without keeping the whole body on a page or treating bold prose as
-- a label. Pandoc still renders the label's text and escapes it for Typst.
if not FORMAT:match('typst') then return {} end

function Div(el)
  if el.classes:includes('htmxo-label') then
    local blocks = pandoc.Blocks({pandoc.RawBlock('typst', '#block(sticky: true)[')})
    blocks:extend(el.content)
    blocks:insert(pandoc.RawBlock('typst', ']'))
    return blocks
  end
end
