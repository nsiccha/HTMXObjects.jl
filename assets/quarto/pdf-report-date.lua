-- Quarto reads the front matter's `date` as a date and prints what it parsed:
-- "22.10.2026" as "Invalid Date", "05.10.2026" as 2026-05-10. `pdf_report`
-- writes a date that is not an ISO date under `htmxobjects-date-text` instead,
-- which Quarto leaves alone. Pandoc's Typst writer then writes the date as
-- markup, `date: [22. Oktober 2026]`, which Typst reads as a numbered list. So
-- `pdf_report` runs this filter: it makes that text the date, or keeps the date
-- Quarto formatted, and hands it to Typst as a string.
if not FORMAT:match('typst') then return {} end

local TEXT = 'htmxobjects-date-text'

local function typst_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

function Meta(meta)
  local date = meta[TEXT] or meta.date
  if date == nil then return nil end
  meta[TEXT] = nil
  meta.date = pandoc.MetaInlines({
    pandoc.RawInline('typst', '#' .. typst_string(pandoc.utils.stringify(date))) })
  return meta
end
