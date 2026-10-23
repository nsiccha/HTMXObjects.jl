-- Typst reads only files inside the document's directory, and Quarto reads an
-- image path starting with `/` as relative to that directory, so an image given
-- as an absolute path, a `file:` URL or a relative path that leaves the
-- directory fails to compile. `pdf_report` runs this filter: it puts each such
-- image into Pandoc's media bag, which Quarto writes next to the document.
-- A `/path` that names a file inside the directory keeps Quarto's reading
-- (the site-root URL of an exported page).
local root = pandoc.path.directory(quarto.doc.input_file)

local function readable(path)
  local f = io.open(path, 'rb')
  if f then f:close() end
  return f ~= nil
end

-- Whether a relative path climbs out of the directory it is relative to.
local function leaves(path)
  local depth = 0
  for part in path:gmatch('[^/\\]+') do
    if part == '..' then depth = depth - 1 elseif part ~= '.' then depth = depth + 1 end
    if depth < 0 then return true end
  end
  return false
end

-- The source to fetch for an image Typst cannot read as written, or nil.
local function outside_source(src)
  if src:match('^[Ff][Ii][Ll][Ee]:') then return src end
  -- any other URL (`https:`, `data:`) Quarto fetches itself; a one-letter
  -- "scheme" is a Windows drive
  if src:match('^%a[%w+.-]+:') then return nil end
  if src:match('^[/\\]') and not src:match('^[/\\][/\\]') then
    return not readable(pandoc.path.join({ root, src:sub(2) })) and src or nil
  end
  if pandoc.path.is_absolute(src) then return src end
  return leaves(src) and pandoc.path.join({ root, src }) or nil
end

function Image(el)
  local source = outside_source(el.src)
  if not source then return nil end
  local mt, contents = pandoc.mediabag.fetch(source)
  local _, ext = pandoc.path.split_extension(pandoc.path.filename(el.src))
  local subtype = mt and mt:match('^image/(%w+)')
  if ext == '' and subtype then ext = '.' .. subtype end
  local name = 'pdf-report-' .. pandoc.utils.sha1(contents) .. ext
  pandoc.mediabag.insert(name, mt, contents)
  el.src = name
  return el
end
