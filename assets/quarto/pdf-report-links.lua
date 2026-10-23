-- `pdf_report`'s links, in two passes.
--
-- A PDF opens a link to a URL (`https:`, `mailto:`) or to a place in the
-- document (`#id`). The other links of a web page do not work there: a link
-- with no target (`[Bayern]()`, an `<a>` without `href`, or a bare `#`), which
-- Typst refuses, and a site address (`/region/11`, `region/11`, `?r=1`), which
-- Quarto writes relative to the PDF file, where it opens nothing. The first
-- pass links a link starting with `/` to `htmxobjects-base-url` followed by the
-- path when one is given, and writes any other such link as its text.
--
-- PAC fails a PDF whose text shows a web or mail address that is not a link
-- ("Link in text does not have a 'Link' element"). `pdf_report` reads the
-- Markdown with Pandoc's `autolink_bare_uris`, which links an address with a
-- scheme (`https://…`, `mailto:…`) and a mail address; the second pass links
-- the rest PAC reports: an address starting with `www.`, linked with
-- `https://`, and a code span that is an address and nothing else. It runs
-- after the first, so the text of a link the first pass removed is linked the
-- same way.
if not FORMAT:match('typst') then return {} end

local BASE = 'htmxobjects-base-url'
local base

local function opens(target)
  -- a one-letter "scheme" is a Windows drive: a local file a viewer may open
  return target:match('^#.') or target:match('^%a[%w+.-]*:')
end

local function link_or_text(el)
  if opens(el.target) then return nil end
  if base and el.target:match('^/') and not el.target:match('^//') then
    el.target = base .. el.target
    return el
  end
  return el.content
end

-- Characters that end a sentence or a clause rather than an address (GFM's
-- rule for its `www.` autolinks).
local TRAILING = "[%.,:;!%?%*_~'\"]"

-- `text` split into what precedes a `www.` address, the address and what follows,
-- or nil.
local function www_address(text)
  local before, rest = text:match('^(.-)(www%.[%w_-]+%.[%w_.-]*[%w_-].*)$')
  if not rest or before:match('[%w_.-]$') then return nil end
  local address, after = rest, ''
  while true do
    local last = address:sub(-1)
    local _, opened = address:gsub('%(', '')
    local _, closed = address:gsub('%)', '')
    if last:match(TRAILING) or (last == ')' and closed > opened) then
      address, after = address:sub(1, -2), last .. after
    else
      break
    end
  end
  return before, address, after
end

local function linked_str(el)
  local before, address, after = www_address(el.text)
  if not address then return nil end
  local out = {}
  if before ~= '' then table.insert(out, pandoc.Str(before)) end
  table.insert(out, pandoc.Link({ pandoc.Str(address) }, 'https://' .. address))
  if after ~= '' then table.insert(out, pandoc.Str(after)) end
  return out, false
end

-- The link target of a code span that is an address and nothing else, or nil.
local function code_target(text)
  if text:match('^%a[%w+.-]*://%S+$') or text:match('^mailto:%S+$') then return text end
  if text:match('^[%w._%%+-]+@[%w-]+%.[%w.-]+$') then return 'mailto:' .. text end
  local before, address, after = www_address(text)
  if address and before == '' and after == '' then return 'https://' .. address end
  return nil
end

local function linked_code(el)
  local target = code_target(el.text)
  if not target then return nil end
  return pandoc.Link({ el }, target), false
end

-- A link's text, and an image's description, stay as they are.
local function as_is(el)
  return el, false
end

return {
  {
    Meta = function(meta)
      base = meta[BASE] and pandoc.utils.stringify(meta[BASE]) or nil
      meta[BASE] = nil
      return meta
    end,
  },
  { Link = link_or_text },
  { traverse = 'topdown', Str = linked_str, Code = linked_code, Link = as_is, Image = as_is },
}
