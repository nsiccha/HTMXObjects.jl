// A figure does not break across pages, so its pictures and caption move to
// the next page together. One taller than a page printed its bottom, the
// caption, over the page bottom. `pdf_report` includes this file: a figure
// taller than the page's text area has its pictures scaled down, so it fits
// with its caption. Its other content stays the size it is. When even pictures
// of no height would leave it too tall (a caption longer than a page), the whole
// figure is scaled down instead, so nothing of it runs off the page.
// `layout` gives the size of the whole text area wherever the figure sits, so
// a figure that would fit on a fresh page keeps its size and moves there.
#let pdf-report-fit(it) = layout(size => {
  let height(f) = measure({ show image: im => scale(f * 100%, reflow: true, im); it }, width: size.width).height
  let whole = height(1)
  if whole <= size.height { return it }
  // A picture's height is its scale times its size, so the figure's height is
  // linear in the scale: the rest, plus the pictures' share.
  let pictures = 2 * (whole - height(0.5))
  let f = if pictures > 0pt { (size.height - (whole - pictures)) / pictures } else { 0 }
  if f > 0 {
    show image: im => scale(f * 100%, reflow: true, im)
    it
  } else {
    scale(size.height / whole * 100%, reflow: true, it)
  }
})
#show figure.where(kind: image): pdf-report-fit
#show figure.where(kind: "quarto-float-fig"): pdf-report-fit
