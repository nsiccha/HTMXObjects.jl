# Common behavior belongs on an ancestor; generated operations keep their own
# mounted URLs, successful inputs, accessible buttons, and result addresses.
module SharedSettings

using HTMXObjects

const TABLE_SETTINGS = (
    hx_swap="innerHTML",
    hx_vals="{\"view\":\"compact\",\"columns\":\"" *
            join(("column$(i)" for i in 1:32), ',') * "\"}",
    hx_on__before_request="this.closest('.shared-settings-table').querySelector('output').textContent = 'Working';",
    hx_on__after_request="this.closest('.shared-settings-table').querySelector('output').textContent = event.detail.successful ? 'Ready' : 'Request failed';",
    hx_on_click="const row = event.target.closest('tr'); if (row && event.target.closest('button')) this.closest('.shared-settings-table').dataset.lastRow = row.dataset.row;",
)

@htmx struct Row
    number::Int
    @param (; session_key, view) = __parent__
    @options mode = (:short, :long)
    mode::Symbol
    @options choice = mode === :short ? (:a, :b) : (:c, :d)
    @get read(; choice::Symbol=:a) = h.p("read:$(number):$(session_key):$(view):$(mode):$(choice)")
    @post write(; note::String="hello") = h.p("write:$(number):$(session_key):$(view):$(note)")
end

@htmx struct App
    @param session_key::String="demo"
    @param view::String="compact"
    @include rows(row::Int) = Row(row, :short)
    __page__(content) = htmx(h.main(content))
    @get index() = table_surface(__self__)
    @get eager() = table_surface(__self__; load_operations=true)
    @get detail(; row::Int) = operation_surface(rows(row))
end

operation_surface(row) = semantic_app(row;
    submit=entry -> h.span("Run ", h.strong(entry.title)),
    submit_attrs=entry -> (; title="Run $(entry.title)", aria_label="Run $(entry.title)"),
    render_operation=entry -> h.div(entry.form, entry.result))

function table_row(app, number; load_operations=false)
    h.tr(
        h.td("Row $(number)"),
        h.td(
            h.button(load_operations ? "Reload operations" : "Load operations"; type="button",
                hx_get=query_url(app / "detail"; row=number, session_key=app.session_key),
                hx_target="next .row-operations"),
            h.div(load_operations ? operation_surface(app.rows(number)) : "";
                class="row-operations")),
        data_row=number)
end

function table_surface(app; indices=1:400, load_operations=false)
    h.div(
        h.table(h.thead(h.tr(h.th("Row"), h.th("Operations"))),
                h.tbody((table_row(app, number; load_operations) for number in indices)...)),
        h.output("Ready"; aria_live="polite");
        class="shared-settings-table", TABLE_SETTINGS...)
end

function main(; port=8080)
    route!(App())
    serve(; port)
end

end # module SharedSettings

if abspath(PROGRAM_FILE) == @__FILE__
    SharedSettings.main()
end
