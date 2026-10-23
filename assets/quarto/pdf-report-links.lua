-- PAC fails a PDF whose text shows a web or mail address that is not a link
-- ("Link in text does not have a 'Link' element"). `pdf_report` reads the
-- Markdown with Pandoc's `autolink_bare_uris`, which links an address with a
-- scheme (`https://…`, `mailto:…`) and a mail address; this filter links the
-- rest PAC reports: an address starting with `www.`, linked with `https://`,
-- and a code span that is an address and nothing else.
if not FORMAT:match('typst') then return {} end

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
  { traverse = 'topdown', Str = linked_str, Code = linked_code, Link = as_is, Image = as_is },
}
