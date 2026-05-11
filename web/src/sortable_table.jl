@dynamicstruct struct SortableTableData
    df = DataFrame(
        name = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank"],
        score = [95, 87, 92, 78, 88, 100],
        time_ms = [12.4, 8.1, missing, 9.9, 11.2, 7.3],
        note = [nothing, "fast", "slow", nothing, "retry", "best"],
        payload = Any[42, "n/a", 3.14, missing, :ok, nothing],
        status = ["pass", "pass", "pass", "fail", "pass", "pass"],
    )
end

@htmx struct SortableTableRoutes
    (; sortable_table) = __appdata__
    (; df) = sortable_table

    @get index() = h.div(
        h.h1("Sortable Table Demo"),
        h.p("Click any column header to sort. Numeric columns sort numerically; string columns use locale compare. Includes ",
            h.code("missing"), ", ", h.code("nothing"),
            ", a single-type string column, and a mixed-type ", h.code("Any"), " column."),
        render_table(df),
        sortable_table_js(),
    )
end
