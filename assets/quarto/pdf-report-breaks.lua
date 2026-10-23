-- A pipe table row is one line, so a line break in a table cell can only be
-- written as inline HTML: HTMX.jl and `SemanticTable` write it as `<br>`, and
-- so do hand-written tables. Pandoc reads `<br>` as raw HTML, and its Typst
-- writer drops raw HTML, so `27.268<br>25.501–28.966` printed
-- `27.26825.501–28.966`. `pdf_report` runs this filter: it reads each `<br>`,
-- in a table cell or anywhere else, as the line break it is.
if not FORMAT:match('typst') then return {} end

function RawInline(el)
  if el.format:match('^html') and el.text:lower():match('^<br%s*/?>$') then
    return pandoc.LineBreak()
  end
end
