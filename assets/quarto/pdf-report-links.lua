-- A PDF opens a link to a URL (`https:`, `mailto:`) or to a place in the
-- document (`#id`). The other links of a web page do not work there: a link
-- with no target (`[Bayern]()`, an `<a>` without `href`, or a bare `#`), which
-- Typst refuses, and a site address (`/region/11`, `region/11`, `?r=1`), which
-- Quarto writes relative to the PDF file, where it opens nothing. `pdf_report`
-- runs this filter: a link starting with `/` goes to `htmxobjects-base-url`
-- followed by the path when one is given, and any other such link is written
-- as its text.
local BASE = 'htmxobjects-base-url'
local base

local function opens(target)
  -- a one-letter "scheme" is a Windows drive: a local file a viewer may open
  return target:match('^#.') or target:match('^%a[%w+.-]*:')
end

return {
  {
    Meta = function(meta)
      base = meta[BASE] and pandoc.utils.stringify(meta[BASE]) or nil
      meta[BASE] = nil
      return meta
    end,
  },
  {
    Link = function(el)
      if opens(el.target) then return nil end
      if base and el.target:match('^/') and not el.target:match('^//') then
        el.target = base .. el.target
        return el
      end
      return el.content
    end,
  },
}
