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
  // Identifiers have no language hyphenation points. An empty inline box
  // permits a break after an underscore run without adding a character to
  // the PDF's text (a zero-width space would survive copy/paste).
  show regex("_+"): it => it + box(width: 0pt)
  cell
})

// Column widths as a browser gives an HTML table (CSS automatic table layout):
// a column is at least as wide as its longest word (the text between spaces, or
// up to an underscore run, where the cell rule above allows a break; a number
// interval such as `25.501–28.966` is one word), and the room left goes to
// the columns whose text would otherwise wrap, in proportion to how much longer
// their text is than their longest word. Pandoc gives a table `auto` columns,
// or, when a row is longer than 72 characters, equal shares read from HTMX's
// equal `---` separators (14.29 % each of 7 columns), which squeezed a long label
// into a narrow column beside mostly empty number columns. Typst's own `auto`
// columns share the room equally among the wide ones, so a one-word header got
// as much as a long label. A table that fits keeps its natural widths, and
// widths an author gave (unequal shares) are kept.
//
// A row stays on one page when it fits on a fresh page below the repeated
// header and footer; a taller row still breaks, so no text runs past the page.
//
// `pdf-report-tables.lua` hands each table to `pdf-report-table` before Typst
// shows it: a `show table` rule that built the sized table would tag a Table
// inside the Table it replaces, which PDF/UA-1 refuses. A table with spanning or
// placed cells, its own insets or a label is shown as it is.
#let pdf-report-length(v, width) = if v == none or v == auto { 0pt } else if type(v) == relative { v.ratio * width + v.length } else if type(v) == ratio { v * width } else { v }
#let pdf-report-margin(key) = {
  let margin = page.margin
  let v = if type(margin) == dictionary { margin.at(key, default: margin.at("y", default: margin.at("rest", default: auto))) } else { margin }
  if v == auto { 2.5 / 21 * calc.min(page.width, page.height) } else { pdf-report-length(v, page.height) }
}
// Widths that fit `width` when even the longest words do not: as Typst shares
// out `auto` columns, a column narrower than an equal share of the room left
// keeps its width, and the wider ones share that room equally.
#let pdf-report-fair-shares(widths, width) = {
  let kept = widths.map(_ => false)
  let share = width / widths.len()
  let changed = true
  while changed {
    changed = false
    let open = kept.filter(k => not k).len()
    if open == 0 { break }
    share = (width - widths.zip(kept).filter(((_, k)) => k).map(((w, _)) => w).sum(default: 0pt)) / open
    for (j, w) in widths.enumerate() {
      if not kept.at(j) and w <= share { kept.at(j) = true; changed = true }
    }
  }
  widths.zip(kept).map(((w, k)) => if k { w } else { share })
}
#let pdf-report-sized-table(it) = {
  let columns = it.at("columns", default: none)
  if type(columns) == int { columns = (auto,) * columns }
  if type(columns) != array or columns.len() == 0 or it.has("label") { return it }
  let share(c) = type(c) == ratio or (type(c) == relative and c.length == 0pt)
  let content-sized = columns.all(c => c == auto) or columns.all(c => share(c) and c == columns.first())
  if not content-sized and not columns.all(c => type(c) in (ratio, relative, length)) { return it }
  let n = columns.len()
  // the cells in grid order, each with whether it is a body cell
  let cells = ()
  for child in it.children {
    let kind = child.func()
    if kind == table.header or kind == table.footer {
      for c in child.children {
        if c.func() == table.cell { cells.push((c, false)) } else if c.func() in (table.hline, table.vline) { } else { cells.push((table.cell(c), false)) }
      }
    } else if kind == table.cell { cells.push((child, true)) } else if kind in (table.hline, table.vline) { } else { cells.push((table.cell(child), true)) }
  }
  for (c, _) in cells {
    let f = c.fields()
    if f.at("colspan", default: 1) != 1 or f.at("rowspan", default: 1) != 1 or f.at("x", default: auto) != auto or f.at("y", default: auto) != auto or "inset" in f { return it }
  }
  layout(size => {
    let inset = table.inset
    if type(inset) not in (relative, length, ratio, dictionary) { return it }
    let side(key) = if type(inset) == dictionary { inset.at(key, default: inset.at("rest", default: 0pt)) } else { inset }
    let gutter = table.column-gutter
    let gap = if type(gutter) in (relative, length, ratio) { pdf-report-length(gutter, size.width) * (n - 1) } else if gutter in ((), auto, none) { 0pt } else { return it }
    let width = size.width - gap
    let ix = pdf-report-length(side("left"), width) + pdf-report-length(side("right"), width)
    let iy = pdf-report-length(side("top"), width) + pdf-report-length(side("bottom"), width)
    let widths = none
    let used = columns.map(c => pdf-report-length(c, width))
    if content-sized {
      // each column's longest word and its widest unbroken line
      let least = (0pt,) * n
      let most = (0pt,) * n
      for (i, (c, _)) in cells.enumerate() {
        let k = calc.rem(i, n)
        most.at(k) = calc.max(most.at(k), measure(c.body).width + ix)
        least.at(k) = calc.max(least.at(k), measure({
          show regex("\s+"): linebreak()
          show regex("_+"): it => it + linebreak()
          c.body
        }).width + ix)
      }
      let (low, high) = (least.sum(), most.sum())
      used = most
      if high > width {
        widths = if low >= width { pdf-report-fair-shares(least, width) } else {
          least.zip(most).map(((a, b)) => a + (b - a) * ((width - low) / (high - low)))
        }
        used = widths
      } else if columns.any(c => c != auto) { widths = (auto,) * n }
    }
    // each row's height at those widths, and the room a fresh page has for a row
    let heights = ()
    for (i, (c, _)) in cells.enumerate() {
      let h = measure(block(width: used.at(calc.rem(i, n)) - ix, { set par(justify: false); c.body })).height + iy
      let r = calc.quo(i, n)
      if heights.len() <= r { heights.push(h) } else { heights.at(r) = calc.max(heights.at(r), h) }
    }
    let repeated = cells.enumerate().filter(((i, (_, body))) => not body and calc.rem(i, n) == 0).map(((i, _)) => heights.at(calc.quo(i, n))).sum(default: 0pt)
    let room = if type(page.height) == length {
      page.height - pdf-report-margin("top") - pdf-report-margin("bottom") - repeated - 2em.to-absolute()
    } else { none }
    let i = 0
    let children = ()
    for child in it.children {
      let kind = child.func()
      if kind == table.header or kind == table.footer {
        i += child.children.filter(c => c.func() not in (table.hline, table.vline)).len()
        children.push(child)
      } else if kind in (table.hline, table.vline) { children.push(child) } else {
        let cell = if kind == table.cell { child } else { table.cell(child) }
        if room != none and heights.at(calc.quo(i, n)) <= room {
          let f = cell.fields()
          let body = f.remove("body")
          children.push(table.cell(..f, breakable: false, body))
        } else { children.push(cell) }
        i += 1
      }
    }
    let f = it.fields()
    let _ = f.remove("children")
    if widths != none { f.columns = widths }
    table(..f, ..children)
  })
}
// Each table in `body`, in the figure and alignment Pandoc sets it in, sized.
#let pdf-report-table(body) = {
  let kind = body.func()
  if body.has("label") { body }
  else if kind == table { pdf-report-sized-table(body) }
  else if kind == align { align(body.alignment, pdf-report-table(body.body)) }
  else if kind == figure {
    let f = body.fields()
    let inner = f.remove("body")
    figure(..f, pdf-report-table(inner))
  }
  else if kind == [].func() { body.children.map(pdf-report-table).join() }
  else { body }
}

// A captioned table is a figure (`quarto-float-tbl`, or Typst's `table` kind),
// and a figure does not break across pages: a table taller than a page printed
// its last rows over the page bottom. Breakable, it continues on the next page
// like an uncaptioned table, its header row repeated; a caption above a table
// moves along with the first rows rather than stay alone at a page bottom.
#show figure.where(kind: "quarto-float-tbl"): set block(breakable: true)
#show figure.where(kind: table): set block(breakable: true)
#show figure.caption.where(position: top): it => block(sticky: true, it)
