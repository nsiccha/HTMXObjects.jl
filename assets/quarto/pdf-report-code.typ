// Code blocks. `pdf_report` asks Quarto for Typst's own code blocks
// (`syntax-highlighting: idiomatic`), which Typst tags as one Code element
// holding a paragraph per line. Quarto's default, Skylighting, writes each
// token as an inline `raw` and each line end as `raw("\n")`, and Typst tags
// each of those as a Code element of its own: an empty one for every line and
// a whitespace-only one for every space or indent between two tokens, which
// PAC reports as "Tagged text consists of only whitespace".

// The colours are Quarto's default theme, `arrow`, which Skylighting used: each
// keeps a contrast of at least 4.5:1 on its background, as WCAG asks of text.
// Typst's own theme on Quarto's grey falls to 3.7:1 for keywords and strings.
// Bold keywords are tagged Strong, which Typst writes for a bold theme style.
// Code without a language, and inline code, keep the theme's colour for plain
// code text, as Skylighting set them; Typst leaves a token in that colour unset.
#show raw: set text(fill: rgb("#003B4F"))
#let pdf-report-code-styles = (
  // (TextMate scopes, colour, bold)
  ("comment", "#5E5E5E", false),
  ("string, constant.character", "#20794D", false),
  ("constant.character.escape", "#5E5E5E", false),
  ("constant.numeric", "#AD0000", false),
  ("constant.language, constant.other, support.constant", "#8F5902", false),
  ("keyword, storage", "#003B4F", true),
  ("keyword.operator", "#5E5E5E", false),
  ("keyword.control.import, keyword.other.import", "#00769E", false),
  ("entity.name.function, support.function, variable.function", "#4758AB", false),
  ("storage.type, support.type, entity.name.type", "#AD0000", false),
  ("support.function.macro, entity.name.macro, meta.preprocessor", "#AD0000", false),
  ("entity.other.attribute-name", "#657422", false),
  ("invalid", "#AD0000", false),
)
#set raw(theme: bytes(
  "<?xml version='1.0' encoding='UTF-8'?><plist version='1.0'><dict>"
  + "<key>name</key><string>arrow</string><key>settings</key><array>"
  + "<dict><key>settings</key><dict><key>foreground</key><string>#003B4F</string></dict></dict>"
  + pdf-report-code-styles.map(((scope, colour, bold)) => (
      "<dict><key>scope</key><string>" + scope + "</string><key>settings</key><dict>"
      + "<key>foreground</key><string>" + colour + "</string>"
      + "<key>fontStyle</key><string>" + (if bold { "bold" } else { "" }) + "</string></dict></dict>"
    )).join()
  + "</array></dict></plist>"))
#show raw.where(block: true): set block(fill: rgb("#f1f3f5"))

// Typst tags a blank line, or one of spaces only, as an empty or whitespace-only
// paragraph, which PAC reports too. Such a line is set as an empty line with no
// tag; the page is the same, and so is the text of every other line.
#show raw.where(block: true): it => {
  let lines = ()
  for (i, line) in it.lines.enumerate() {
    if i > 0 { lines.push(linebreak()) }
    if line.text.trim() != "" { lines.push(line) }
  }
  block(align(it.align, lines.join()))
}
