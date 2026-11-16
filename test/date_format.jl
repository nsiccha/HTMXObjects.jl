using TestItemRunner

# `format_date` writes a day in a table's language, the date counterpart of
# `format_number` (snag formatting-a-dat-6e544028, design decision 1y3u6pj:
# `:short` writes the abbreviated month, the words live in `TableTexts`, no
# browser twin yet: `htmxoDateText`, 0.1.146, writes days in the browser).

@testitem "format_date writes a day in English and German" tags=[:unit] begin
    using HTMXObjects
    import Dates
    de, en = table_texts(:de), table_texts()
    d = Dates.Date(2015, 10, 1)
    # The reporter's examples and the picked short style.
    @test format_date(d) == "1 October 2015" && format_date(d; texts=en, style=:long) == "1 October 2015"
    @test format_date(d; texts=de) == "1. Oktober 2015"
    @test format_date(d; style=:short) == "1 Oct 2015" && format_date(d; texts=de, style=:short) == "1. Okt. 2015"
    @test format_date(d; style=:month) == "Oct 2015" && format_date(d; texts=de, style=:month) == "Okt. 2015"
    # Every month, as browsers write it (CLDR: Intl.DateTimeFormat en-GB and
    # de-DE; English `Sep` where en-GB writes `Sept`).
    en_long = ["January", "February", "March", "April", "May", "June", "July",
               "August", "September", "October", "November", "December"]
    en_short = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    de_long = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
               "August", "September", "Oktober", "November", "Dezember"]
    de_short = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
    for m in 1:12
        day = Dates.Date(2026, m, 9)
        @test format_date(day) == "9 $(en_long[m]) 2026"
        @test format_date(day; style=:short) == "9 $(en_short[m]) 2026"
        @test format_date(day; style=:month) == "$(en_short[m]) 2026"
        @test format_date(day; texts=de) == "9. $(de_long[m]) 2026"
        @test format_date(day; texts=de, style=:short) == "9. $(de_short[m]) 2026"
        @test format_date(day; texts=de, style=:month) == "$(de_short[m]) 2026"
    end
    # The day and year are digits alone: no zero padding, no thousands mark.
    @test format_date(Dates.Date(1999, 12, 31); texts=de) == "31. Dezember 1999"
    @test format_date(Dates.Date(12345, 1, 2)) == "2 January 12345"
    # No value writes the dash `format_number` writes.
    @test format_date(missing) == "–" && format_date(nothing; texts=de, style=:month) == "–"
end

@testitem "format_date's words and layouts are table texts" tags=[:unit] begin
    using HTMXObjects
    import Dates
    d = Dates.Date(2015, 10, 1)
    @test format_date(d; texts=table_texts(; date_long="{month} {day}, {year}")) == "October 1, 2015"
    @test format_date(d; texts=table_texts(:de; date_month="{month} {year}"), style=:month) == "Oktober 2015"
    @test format_date(d; texts=table_texts(; months_short=("Jan", "Feb", "Mar", "Apr", "May", "June", "July",
        "Aug", "Sept", "Oct", "Nov", "Dec")), style=:short) == "1 Oct 2015"
    sept = table_texts(; months_short=["Jan", "Feb", "Mar", "Apr", "May", "June", "July", "Aug", "Sept", "Oct", "Nov", "Dec"])
    @test sept.months_short isa NTuple{12,String}
    @test format_date(Dates.Date(2015, 9, 1); texts=sept, style=:month) == "Sept 2015"
    # A layout takes only the date placeholders; a name list twelve names.
    @test_throws ArgumentError table_texts(; date_long="{day} {mon} {year}")
    @test_throws ArgumentError table_texts(; date_short="{shown}")
    @test_throws ArgumentError table_texts(; months=("Jan", "Feb"))
    @test_throws ArgumentError table_texts(; months="January")
    @test_throws ArgumentError table_texts(; months=12)
    # Unknown styles and values that are not a day are refused, and a
    # DateTime is never written without its time of day.
    @test_throws ArgumentError format_date(d; style=:full)
    @test_throws ArgumentError format_date(missing; style=:full)
    @test_throws ArgumentError format_date(Dates.DateTime(2015, 10, 1, 12))
    @test_throws ArgumentError format_date("2015-10-01")
    @test_throws ArgumentError format_date(Dates.Time(12))
    err = try format_date(Dates.DateTime(2015, 10, 1, 12)) catch e e end
    @test occursin("Date(x)", sprint(showerror, err))
end

@testitem "a table's HTML does not carry the date texts" tags=[:unit] begin
    using HTMXObjects
    import JSON
    de = table_texts(:de)
    # The browser reads every table text but the dates, in field order.
    browser = [n for n in fieldnames(TableTexts) if !(n in (:months, :months_short, :date_long, :date_short, :date_month))]
    @test collect(Symbol.(keys(JSON.parse(HTMXObjects._table_texts_json(de))))) == browser
    @test HTMXObjects._table_texts_json(de) == JSON.json(NamedTuple{Tuple(browser)}(Tuple(getfield(de, n) for n in browser)))
    html(x) = repr("text/html", x)
    rows = (name=["a", "b"], n=[1.5, 2.25])
    # A German table carries its texts, with no month names in them.
    german = html(render_table(rows; texts=de, searchable=true))
    @test occursin("data-htmxo-texts", german) && !occursin("Oktober", german) && !occursin("date_long", german)
    # An English table, and one whose texts differ only in the dates, carry none.
    @test !occursin("data-htmxo-texts", html(render_table(rows; searchable=true)))
    american = table_texts(; date_long="{month} {day}, {year}")
    @test html(render_table(rows; texts=american, searchable=true)) == html(render_table(rows; searchable=true))
    # Nor does the runtime's English default.
    @test !occursin("October", HTMXObjects._md_runtime_js()) && occursin("htmxoTableTextsDefault", HTMXObjects._md_runtime_js())
end

@testitem "render_table writes a ColumnSpec(date) column as days" tags=[:unit] begin
    using HTMXObjects
    import Dates
    html(x) = repr("text/html", x)
    ms(d) = Dates.value(Dates.DateTime(d)) - Dates.UNIXEPOCH
    # A Date, the milliseconds of an instant, and no day (missing, NaN, beyond JavaScript's dates).
    rows = (; day = [Dates.Date(2015, 10, 1), Dates.Date(2016, 2, 29), missing],
              at = [Float64(ms(Dates.Date(2015, 10, 1))) + 3_600_000, NaN, 8.64e15 + 1])
    columns = [:day => ColumnSpec("Tag"; date = :long), :at => ColumnSpec("Zeit"; date = :short)]
    t = html(render_table(rows; columns, texts = table_texts(:de)))
    @test [m[1] for m in eachmatch(r"<td[^>]*>([^<]*)</td>", t)] ==
          ["1. Oktober 2015", "1. Okt. 2015", "29. Februar 2016", "–", "–", "–"]
    # Each sorts by its value and exports its ISO day; no day is an empty number cell.
    @test occursin("<td data-sort-value=\"1443657600000\" data-htmxo-number=\"2015-10-01\">1. Oktober 2015</td>", t)
    @test occursin("<td data-sort-value=\"1.4436612e12\" data-htmxo-number=\"2015-10-01\">1. Okt. 2015</td>", t)
    @test count("<td data-htmxo-number=\"\">–</td>", t) == 3
    # Both columns are right-aligned like number columns, and the table carries no month names.
    @test count(r"<th[^>]*data-htmxo-align=\"right\"", t) == 2 && !occursin("Oktober\"", t) && !occursin("months", t)
    @test [m[1] for m in eachmatch(r"<td[^>]*>([^<]*)</td>", html(render_table((; d = [Dates.Date(2015, 10, 1)]))))] == ["2015-10-01"]
    # Refused: an unknown style, days with digits, a DateTime or text in a day column, days in a table of built cells.
    @test_throws ArgumentError ColumnSpec("Day"; date = :weekday)
    e = try; ColumnSpec("Day"; date = :long, sigdigits = 2); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("takes no `digits`, `sigdigits` or `percent`", e.msg)
    @test_throws ArgumentError render_table((; d = [Dates.DateTime(2015, 10, 1)]); columns = [:d => ColumnSpec("D"; date = :long)])
    @test_throws ArgumentError render_table((; d = ["2015-10-01"]); columns = [:d => ColumnSpec("D"; date = :long)])
    e = try; sortable_table([ColumnSpec("Day"; date = :long)], []); nothing; catch err; err; end
    @test e isa ArgumentError && occursin("format_date", e.msg)
end
