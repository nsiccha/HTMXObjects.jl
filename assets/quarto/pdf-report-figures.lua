-- Pandoc's Typst writer, and Quarto's for its figures, set every image in a
-- box, `#box(image(…))`, and Typst puts a box in a paragraph: an image alone in
-- its paragraph, or in a figure, was tagged as a Figure inside a P. PAC warns
-- about each one ("Possibly inappropriate use of a 'Figure' structure
-- element"), since a block Figure does not belong in a paragraph. `pdf_report`
-- runs this filter after Quarto has written its images and figures: it sets an
-- image that is all of its block in a Typst block, `#block[#box(image(…))]`,
-- which prints the same and is no paragraph. An image within text stays in its
-- paragraph.
if not FORMAT:match('typst') then return {} end

-- Whether an inline is an image: Pandoc's, or the one Quarto has written.
local function is_image(el)
  return el.t == 'Image' or
    (el.t == 'RawInline' and el.format == 'typst' and el.text:match('^#box%(.-image%(') ~= nil)
end

-- The image that is all of `inlines`, or nil.
local function lone_image(inlines)
  local image
  for _, el in ipairs(inlines) do
    if is_image(el) and not image then
      image = el
    elseif el.t ~= 'Space' and el.t ~= 'SoftBreak' then
      return nil
    end
  end
  return image
end

local function unparagraphed(block)
  local image = lone_image(block.content)
  if not image then return nil end
  block.content = { pandoc.RawInline('typst', '#block['), image, pandoc.RawInline('typst', ']') }
  return block
end

Para = unparagraphed
Plain = unparagraphed
