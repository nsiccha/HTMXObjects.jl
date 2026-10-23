-- The targets of a document's links, one per line, each once, in the order
-- they first appear: the addresses `pdf_report` hands to its `url_map` before
-- the render. A Pandoc writer, run on the `.qmd` `pdf_report` renders, so it
-- reads the links of the front matter (the title's, say) as well; a link with
-- no target (`[Bayern]()`) has nothing to map.
function Writer(doc, opts)
  local targets, seen = {}, {}
  doc:walk({
    Link = function(el)
      if el.target ~= '' and not seen[el.target] then
        seen[el.target] = true
        table.insert(targets, el.target)
      end
    end,
  })
  return table.concat(targets, '\n')
end
