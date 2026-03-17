module TestExt

using Test
import HTMXObjects: h, htmx, wants_markdown, markdown_response, to_response
import HTMXObjects: test_list, test_run!, test_run_all!, test_run_failed!, test_run_missing!, test_run_batch!, test_clear_cache!

# Sentinel for errors caught during test execution
struct TestError
    exception::Any
    backtrace::Any
end

# Duration tracking (separate from the test module's cache to avoid interface changes)
_durations() = _dur
_dur = Dict{Tuple{UInt, Symbol}, Float64}()  # (objectid(mod), test_name) => seconds

# --- Safe test execution (wraps the test module's run_test!) ---

function _safe_run!(tests_mod, name::Symbol)
    t0 = time()
    try
        tests_mod.run_test!(name)
    catch e
        # Store the error in the cache so it's visible in the UI
        tests_mod.cache()[name] = (time(), TestError(e, catch_backtrace()))
        nothing
    end
    _durations()[(objectid(tests_mod), name)] = time() - t0
end

function _safe_run_all!(tests_mod)
    for name in tests_mod.test_names()
        _safe_run!(tests_mod, name)
    end
end

function _failed_names(tests_mod)
    Symbol[name for name in tests_mod.test_names()
        if let c = tests_mod.cached(name)
            !isnothing(c) && (c[2] isa TestError || c[2].anynonpass)
        end
    ]
end

function _missing_names(tests_mod)
    Symbol[name for name in tests_mod.test_names() if isnothing(tests_mod.cached(name))]
end

function _safe_run_batch!(tests_mod, names)
    for name in names
        _safe_run!(tests_mod, name)
    end
end

# --- Shared test status formatting ---

function _format_duration(dt)
    dt < 1 ? "$(round(Int, dt * 1000))ms" :
    dt < 60 ? "$(round(dt; digits=1))s" :
    "$(round(dt / 60; digits=1))m"
end

function _count_total(result)
    # Count total tests from a DefaultTestSet
    result.n_passed + length(result.results) - result.n_passed
end

function format_test_status(tests_mod, name::Symbol)
    c = tests_mod.cached(name)
    dur = get(_durations(), (objectid(tests_mod), name), nothing)
    dur_str = isnothing(dur) ? "" : _format_duration(dur)
    isnothing(c) && return (; status="pending", icon="·", age="", detail="", duration=dur_str, error_detail="")
    ts, result = c
    age_s = round(Int, time() - ts)
    age = age_s < 60 ? "$(age_s)s ago" : age_s < 3600 ? "$(age_s ÷ 60)m ago" : "$(age_s ÷ 3600)h ago"
    if result isa TestError
        msg = sprint(showerror, result.exception)
        short = first(msg, 60)
        bt = sprint(Base.show_backtrace, result.backtrace)
        full_detail = msg * "\n" * bt
        return (; status="error", icon="!", age, detail=short, duration=dur_str, error_detail=full_detail)
    end
    np = result.n_passed
    total = np + count(r -> !(r isa Test.Pass), result.results)
    anyf = result.anynonpass
    status = anyf ? "fail" : "pass"
    icon = anyf ? "✗" : "✓"
    detail = "$(np)/$(total)"
    # Collect failure details
    error_detail = if anyf
        fails = filter(r -> !(r isa Test.Pass), result.results)
        join([sprint(show, f) for f in fails], "\n")
    else
        ""
    end
    (; status, icon, age, detail, duration=dur_str, error_detail)
end

function _summary_counts(tests_mod)
    pass = fail = error = pending = 0
    for name in tests_mod.test_names()
        s = format_test_status(tests_mod, name)
        if s.status == "pass"; pass += 1
        elseif s.status == "fail"; fail += 1
        elseif s.status == "error"; error += 1
        else pending += 1 end
    end
    (; pass, fail, error, pending, total=pass+fail+error+pending)
end

function tests_plain_text(tests_mod)
    counts = _summary_counts(tests_mod)
    lines = String[]
    push!(lines, "Summary: $(counts.pass) pass, $(counts.fail) fail, $(counts.error) error, $(counts.pending) pending ($(counts.total) total)")
    push!(lines, "")
    push!(lines, rpad("Test", 40) * rpad("Status", 8) * rpad("Detail", 15) * rpad("Duration", 12) * "Age")
    push!(lines, "-"^85)
    for name in tests_mod.test_names()
        s = format_test_status(tests_mod, name)
        push!(lines, rpad(string(name), 40) * rpad(s.icon, 8) * rpad(s.detail, 15) * rpad(s.duration, 12) * s.age)
    end
    join(lines, "\n")
end

function _html_escape(s)
    replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

function tests_html_table(tests_mod)
    counts = _summary_counts(tests_mod)
    rows = map(tests_mod.test_names()) do name
        s = format_test_status(tests_mod, name)
        color = s.status == "pass" ? "green" : s.status == "fail" ? "red" : s.status == "error" ? "orange" : "gray"
        detail_cell = if !isempty(s.error_detail)
            h.td(
                h.details(
                    h.summary(; style=s.status == "error" ? "font-size:0.8em;color:orange;cursor:pointer" : "cursor:pointer")(s.detail),
                    h.pre(; style="font-size:0.75em;max-height:300px;overflow:auto;white-space:pre-wrap;margin-top:0.5em")(_html_escape(s.error_detail)),
                ),
            )
        else
            h.td(s.detail)
        end
        h.tr(
            h.td(string(name)),
            h.td(s.icon; style="color:$color;font-weight:bold"),
            detail_cell,
            h.td(s.duration),
            h.td(s.age),
            h.td(h.button("Run"; hx_post="/tests_run/$(name)", hx_target="#tests-container", hx_swap="innerHTML")),
        )
    end

    summary_parts = String[]
    counts.pass > 0 && push!(summary_parts, "$(counts.pass) pass")
    counts.fail > 0 && push!(summary_parts, "$(counts.fail) fail")
    counts.error > 0 && push!(summary_parts, "$(counts.error) error")
    counts.pending > 0 && push!(summary_parts, "$(counts.pending) pending")
    summary_text = join(summary_parts, ", ") * " ($(counts.total) total)"

    h.div(; id="tests-container")(
        h.div(; style="margin-bottom:1rem")(
            h.button("Run All"; hx_post="/tests_run_all", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Run Missing"; hx_post="/tests_run_missing", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Run Failed"; hx_post="/tests_run_failed", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Clear Cache"; hx_post="/tests_clear_cache", hx_target="#tests-container", hx_swap="innerHTML"),
            h.span(; style="margin-left:1rem;font-size:0.9em;color:#666")(summary_text),
        ),
        h.table(; role="grid")(
            h.thead(h.tr(h.th("Test"), h.th("Status"), h.th("Detail"), h.th("Duration"), h.th("Age"), h.th("Action"))),
            h.tbody(rows...),
        ),
    )
end

# --- Route handler helpers ---

function _test_result(tests_mod, md)
    md ? markdown_response(tests_plain_text(tests_mod)) : tests_html_table(tests_mod)
end

test_list(tests_mod, md) = if md
    markdown_response(tests_plain_text(tests_mod))
else
    htmx(h.main(class="container")(
        h.h1("Tests"),
        h.p(h.a(href="/")("Back to index")),
        tests_html_table(tests_mod),
    ); pico_version="2")
end

test_run!(tests_mod, name, md) = begin
    _safe_run!(tests_mod, Symbol(name))
    _test_result(tests_mod, md)
end

test_run_all!(tests_mod, md) = begin
    _safe_run_all!(tests_mod)
    _test_result(tests_mod, md)
end

test_run_failed!(tests_mod, md) = begin
    _safe_run_batch!(tests_mod, _failed_names(tests_mod))
    _test_result(tests_mod, md)
end

test_run_missing!(tests_mod, md) = begin
    _safe_run_batch!(tests_mod, _missing_names(tests_mod))
    _test_result(tests_mod, md)
end

test_run_batch!(tests_mod, names_str, md) = begin
    ns = Symbol.(filter(!isempty, split(names_str, ",")))
    _safe_run_batch!(tests_mod, ns)
    _test_result(tests_mod, md)
end

test_clear_cache!(tests_mod, md) = begin
    tests_mod.clear_cache!()
    _test_result(tests_mod, md)
end

end # module TestExt
