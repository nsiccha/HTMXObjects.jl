// Quarto's Typst template justifies the whole document, and Typst hyphenates
// text exactly when it is justified, so a narrow table cell came out stretched
// with wide gaps and split words ("Medi-an"). `pdf_report` includes this file:
// table cells are set ragged-right, and a word is hyphenated only when it is
// wider than its column, where it would otherwise print over the next cell.
// Typst has no setting for that, so each word of a cell is measured. Code is
// never hyphenated, and neither is text set with `hyphenate: false`.

// The width a cell's text can take: the cell's width less its left and right
// inset, which Typst resolves to `ratio + length` or a dictionary of sides.
#let pdf-report-cell-room(cell, width) = {
  let side(v) = v.ratio * width + v.length
  let inset = cell.inset
  if type(inset) == dictionary { width - side(inset.left) - side(inset.right) } else { width - 2 * side(inset) }
}

#show table: set par(justify: false)
#show table.cell: cell => layout(size => {
  let room = pdf-report-cell-room(cell, size.width)
  show regex("\p{L}+"): word => context {
    if text.hyphenate != false and measure(word).width > room.to-absolute() { text(hyphenate: true, word) } else { word }
  }
  show raw: set text(hyphenate: false)
  cell
})
