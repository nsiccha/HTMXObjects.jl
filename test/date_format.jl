using TestItemRunner

# `format_date` writes a day in a table's language, the date counterpart of
# `format_number` (snag formatting-a-dat-6e544028, design decision 1y3u6pj:
# `:short` writes the abbreviated month, the words live in `TableTexts`, no
# browser twin yet).

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
