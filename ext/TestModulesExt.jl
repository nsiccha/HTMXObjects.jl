module TestModulesExt

using Test
using TestModules
import HTMXObjects: h, htmx, wants_markdown, markdown_response, to_response
import HTMXObjects: test_list, test_run!, test_run_all!, test_run_failed!, test_run_missing!, test_run_batch!, test_clear_cache!

# Sentinel for errors caught during test execution
struct TestError
    exception::Any
    backtrace::Any
end

# Lightweight result loaded from disk (quacks like a TestSet for format_test_status)
struct PersistedResult
    n_passed::Int
    anynonpass::Bool
    total::Int
    results::Vector{Any}  # empty — no detailed results after restart
end

# Duration tracking (separate from the test module's cache to avoid interface changes)
_durations() = _dur
_dur = Dict{Tuple{UInt, Symbol}, Float64}()  # (objectid(mod), test_name) => seconds

# --- Disk persistence ---

function _cache_path(tests_mod)
    dir = joinpath(first(DEPOT_PATH), "test_cache")
    mkpath(dir)
    joinpath(dir, string(nameof(tests_mod)) * ".tsv")
end

function _persist_result!(tests_mod, name::Symbol)
    c = TestModules.cached(tests_mod, name)
    isnothing(c) && return
    ts, result = c
    dur = get(_durations(), (objectid(tests_mod), name), 0.0)
    status, n_passed, total = if result isa TestError
        ("error", 0, 0)
    elseif result isa PersistedResult
        (result.anynonpass ? "fail" : "pass", result.n_passed, result.total)
    else
        np = result.n_passed
        tot = np + count(r -> !(r isa Test.Pass), result.results)
        (result.anynonpass ? "fail" : "pass", np, tot)
    end
    # Read existing entries, update/add this one, write back
    entries = _read_cache_file(tests_mod)
    entries[name] = (ts, status, n_passed, total, dur)
    _write_cache_file(tests_mod, entries)
end

function _read_cache_file(tests_mod)
    path = _cache_path(tests_mod)
    entries = Dict{Symbol, Tuple{Float64, String, Int, Int, Float64}}()
    isfile(path) || return entries
    for line in eachline(path)
        parts = split(line, '\t')
        length(parts) >= 5 || continue
        name = Symbol(parts[1])
        ts = tryparse(Float64, parts[2])
        status = String(parts[3])
        np = tryparse(Int, parts[4])
        tot = tryparse(Int, parts[5])
        dur = length(parts) >= 6 ? tryparse(Float64, parts[6]) : 0.0
        (isnothing(ts) || isnothing(np) || isnothing(tot)) && continue
        entries[name] = (ts, status, np, tot, something(dur, 0.0))
    end
    entries
end

function _write_cache_file(tests_mod, entries)
    path = _cache_path(tests_mod)
    open(path, "w") do io
        for (name, (ts, status, np, tot, dur)) in sort!(collect(entries); by=first∘last, rev=true)
            println(io, name, '\t', ts, '\t', status, '\t', np, '\t', tot, '\t', dur)
        end
    end
end

function _load_persisted!(tests_mod)
    # Only load if the in-memory cache is empty
    isempty(TestModules.cache(tests_mod)) || return
    entries = _read_cache_file(tests_mod)
    for (name, (ts, status, np, tot, dur)) in entries
        anynonpass = status != "pass"
        TestModules.cache(tests_mod)[name] = (ts, PersistedResult(np, anynonpass, tot, []))
        _durations()[(objectid(tests_mod), name)] = dur
    end
end

function _clear_persisted!(tests_mod)
    path = _cache_path(tests_mod)
    isfile(path) && rm(path)
end

# --- Safe test execution (wraps the test module's run_test!) ---

function _safe_run!(tests_mod, name::Symbol)
    t0 = time()
    try
        TestModules.run_test!(tests_mod, name)
    catch e
        # Store the error in the cache so it's visible in the UI
        TestModules.cache(tests_mod)[name] = (time(), TestError(e, catch_backtrace()))
        nothing
    end
    _durations()[(objectid(tests_mod), name)] = time() - t0
    _persist_result!(tests_mod, name)
end

function _safe_run_all!(tests_mod)
    for name in TestModules.test_names(tests_mod)
        _safe_run!(tests_mod, name)
    end
end

function _failed_names(tests_mod)
    Symbol[name for name in TestModules.test_names(tests_mod)
        if let c = TestModules.cached(tests_mod, name)
            !isnothing(c) && (c[2] isa TestError || c[2].anynonpass)
        end
    ]
end

function _missing_names(tests_mod)
    Symbol[name for name in TestModules.test_names(tests_mod) if isnothing(TestModules.cached(tests_mod, name))]
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

function format_test_status(tests_mod, name::Symbol)
    c = TestModules.cached(tests_mod, name)
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
    if result isa PersistedResult
        status = result.anynonpass ? "fail" : "pass"
        icon = result.anynonpass ? "✗" : "✓"
        detail = "$(result.n_passed)/$(result.total)"
        return (; status, icon, age, detail, duration=dur_str, error_detail="")
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
    for name in TestModules.test_names(tests_mod)
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
    for name in TestModules.test_names(tests_mod)
        s = format_test_status(tests_mod, name)
        push!(lines, rpad(string(name), 40) * rpad(s.icon, 8) * rpad(s.detail, 15) * rpad(s.duration, 12) * s.age)
    end
    join(lines, "\n")
end

function _html_escape(s)
    replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

function tests_html_table(tests_mod; prefix="/tests")
    counts = _summary_counts(tests_mod)
    rows = map(TestModules.test_names(tests_mod)) do name
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
            h.td(h.button("Run"; hx_post="$(prefix)/run/$(name)", hx_target="#tests-container", hx_swap="innerHTML")),
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
            h.button("Run All"; hx_post="$(prefix)/run_all", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Run Missing"; hx_post="$(prefix)/run_missing", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Run Failed"; hx_post="$(prefix)/run_failed", hx_target="#tests-container", hx_swap="innerHTML", style="margin-right:0.5rem"),
            h.button("Clear Cache"; hx_post="$(prefix)/clear_cache", hx_target="#tests-container", hx_swap="innerHTML"),
            h.span(; style="margin-left:1rem;font-size:0.9em;color:#666")(summary_text),
        ),
        h.table(; role="grid")(
            h.thead(h.tr(h.th("Test"), h.th("Status"), h.th("Detail"), h.th("Duration"), h.th("Age"), h.th("Action"))),
            h.tbody(rows...),
        ),
    )
end

# --- Route handler helpers ---

function _test_result(tests_mod, md; prefix="/tests")
    md ? markdown_response(tests_plain_text(tests_mod)) : tests_html_table(tests_mod; prefix)
end

test_list(tests_mod, md; prefix="/tests") = begin
    _load_persisted!(tests_mod)
    if md
        markdown_response(tests_plain_text(tests_mod))
    else
        htmx(h.main(class="container")(
            h.h1("Tests"),
            h.p(h.a(href="/")("Back to index")),
            tests_html_table(tests_mod; prefix),
        ); pico_version="2")
    end
end

test_run!(tests_mod, name, md; prefix="/tests") = begin
    _safe_run!(tests_mod, Symbol(name))
    _test_result(tests_mod, md; prefix)
end

test_run_all!(tests_mod, md; prefix="/tests") = begin
    _safe_run_all!(tests_mod)
    _test_result(tests_mod, md; prefix)
end

test_run_failed!(tests_mod, md; prefix="/tests") = begin
    _safe_run_batch!(tests_mod, _failed_names(tests_mod))
    _test_result(tests_mod, md; prefix)
end

test_run_missing!(tests_mod, md; prefix="/tests") = begin
    _safe_run_batch!(tests_mod, _missing_names(tests_mod))
    _test_result(tests_mod, md; prefix)
end

test_run_batch!(tests_mod, names_str, md; prefix="/tests") = begin
    ns = Symbol.(filter(!isempty, split(names_str, ",")))
    _safe_run_batch!(tests_mod, ns)
    _test_result(tests_mod, md; prefix)
end

test_clear_cache!(tests_mod, md; prefix="/tests") = begin
    TestModules.clear_cache!(tests_mod)
    _clear_persisted!(tests_mod)
    _test_result(tests_mod, md; prefix)
end

end # module TestModulesExt
