-- `pdf_report` sizes a table's columns by their content and keeps a row that
-- fits on a page in one piece (`pdf-report-table` in `pdf-report-tables.typ`).
-- Typst can only build the sized table from the table Pandoc writes before it
-- shows it: a `show table` rule that builds one tags a Table inside the Table
-- it replaces, which PDF/UA-1 refuses. So this filter, run after Quarto has
-- written its table figures, hands each table to that function, together with
-- the figure and alignment Pandoc sets it in.
if not FORMAT:match('typst') then return {} end

function Table(el)
  return { pandoc.RawBlock('typst', '#pdf-report-table['), el, pandoc.RawBlock('typst', ']') }
end
