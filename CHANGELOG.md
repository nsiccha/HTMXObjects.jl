# Changelog

## Unreleased

- Documentation is organized into Start, Guides, Examples and Reference.
  The landing page and guides execute their Julia examples during the build.
- The sample-browser example renders its actual response and checks the selected
  records. Public exports are grouped by task and checked for reference coverage.
- Documentation builds reject warnings and no longer depend on recorded app
  embeds. The docs workflow follows the development branch used by the package.

## 0.1.99

- `ColumnSummary` accepts interval values for summaries with bounded inputs.
  Rendering preserves the range, including signed ranges, in HTML, Markdown
  and CSV. Empty intervals and unsupported interval arithmetic are rejected.
- Numeric formatting accepts an explicit significant-digit budget for summary
  cells, with display and sorting based on the underlying value.
