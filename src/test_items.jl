"""
    TestItemInfo

Metadata for one `@testitem` discovered without executing its body. `key` is
the canonical `relative/file.jl::display name` selector passed to the package's
`test/runtests.jl`; `id` is its URL-safe stable identifier for `TestRoutes`.
An ordinary docstring immediately before `@testitem` becomes `description`.
"""
struct TestItemInfo
    id::String
    key::String
    name::String
    file::String
    line::Int
    tags::Vector{Symbol}
    description::String
end

struct TestCatalog
    project::String
    items::Vector{TestItemInfo}
    errors::Vector{String}
end

mutable struct TestRunJob
    id::String
    selection::Vector{String}
    labels::Vector{String}
    status::Symbol
    created_at::Float64
    started_at::Union{Nothing,Float64}
    finished_at::Union{Nothing,Float64}
    exitcode::Union{Nothing,Int}
    log_path::String
    process::Any
    error::String
end

mutable struct TestRunStore
    lock::ReentrantLock
    jobs::Vector{TestRunJob}
end

const _TEST_RUN_STORES_LOCK = ReentrantLock()
const _TEST_RUN_STORES = Dict{String,TestRunStore}()
const _TEST_SCAN_SKIP_DIRS = Set((
    ".git", ".julia", ".vscode", "node_modules", "cache", "compiled",
    "coverage", "build",
))
const _TEST_JOB_LIMIT = 20
const _TEST_LOG_LIMIT = 200_000

_test_project(project) = abspath(expanduser(string(project)))

function _test_store(project)
    key = _test_project(project)
    lock(_TEST_RUN_STORES_LOCK)
    try
        get!(_TEST_RUN_STORES, key) do
            TestRunStore(ReentrantLock(), TestRunJob[])
        end
    finally
        unlock(_TEST_RUN_STORES_LOCK)
    end
end

function _stable_test_id(key::AbstractString)
    value = UInt64(0xcbf29ce484222325)
    for byte in codeunits(key)
        value = (value ⊻ UInt64(byte)) * UInt64(0x00000100000001b3)
    end
    string(value; base=16, pad=16)
end

_macro_symbol(x::Symbol) = x
_macro_symbol(x::GlobalRef) = x.name
_macro_symbol(x::QuoteNode) = _macro_symbol(x.value)
function _macro_symbol(x::Expr)
    x.head == :. || return nothing
    isempty(x.args) && return nothing
    _macro_symbol(last(x.args))
end
_macro_symbol(_) = nothing

function _is_macrocall(ex, name::Symbol)
    ex isa Expr || return false
    ex.head == :macrocall || return false
    !isempty(ex.args) && _macro_symbol(first(ex.args)) == name
end

function _testitem_tags(ex::Expr)
    tags = Symbol[]
    for arg in ex.args[4:end-1]
        arg isa Expr && arg.head == :(=) && length(arg.args) == 2 || continue
        arg.args[1] == :tags || continue
        values = arg.args[2]
        values isa Expr && values.head == :vect || continue
        for value in values.args
            value isa QuoteNode && value.value isa Symbol && push!(tags, value.value)
        end
    end
    tags
end

function _push_testitem!(items, errors, ex::Expr, project, file, description)
    length(ex.args) >= 4 || return push!(errors, "$(file): malformed @testitem")
    name = ex.args[3]
    name isa String || return push!(errors, "$(file): @testitem name must be a literal string")
    source = ex.args[2]
    line = source isa LineNumberNode ? Int(source.line) : 0
    relative = replace(relpath(file, project), '\\' => '/')
    key = relative * "::" * name
    push!(items, TestItemInfo(
        _stable_test_id(key), key, name, relative, line,
        _testitem_tags(ex), strip(string(description)),
    ))
end

function _collect_testitems!(items, errors, ex, project, file)
    ex isa Expr || return

    if ex.head in (:error, :incomplete)
        relative = replace(relpath(file, project), '\\' => '/')
        detail = isempty(ex.args) ? "invalid Julia syntax" : sprint(showerror, first(ex.args))
        push!(errors, "$relative: $detail")
        return
    end

    if _is_macrocall(ex, Symbol("@doc")) && length(ex.args) >= 4
        target = last(ex.args)
        if _is_macrocall(target, Symbol("@testitem"))
            description = ex.args[3] isa AbstractString ? ex.args[3] : ""
            _push_testitem!(items, errors, target, project, file, description)
            return
        end
    end

    if _is_macrocall(ex, Symbol("@testitem"))
        _push_testitem!(items, errors, ex, project, file, "")
        return
    end

    for arg in ex.args
        _collect_testitems!(items, errors, arg, project, file)
    end
end

function _test_source_files(project)
    files = String[]
    for (root, dirs, names) in walkdir(project)
        filter!(dir -> !(dir in _TEST_SCAN_SKIP_DIRS), dirs)
        for name in names
            endswith(lowercase(name), ".jl") || continue
            push!(files, joinpath(root, name))
        end
    end
    sort!(files)
end

"""
    discover_test_items(project) -> TestCatalog

Discover `@testitem`s with Julia's parser, without importing the package or
executing test code. Names, tags, source locations, and adjacent docstrings are
returned. Syntax and duplicate-id errors are retained in the catalog for the
web UI instead of taking down the host application.
"""
function discover_test_items(project)
    root = _test_project(project)
    items = TestItemInfo[]
    errors = String[]
    isdir(root) || return TestCatalog(root, items, ["Test project does not exist: $root"])

    for file in _test_source_files(root)
        content = try
            read(file, String)
        catch err
            push!(errors, "$(relpath(file, root)): $(sprint(showerror, err))")
            continue
        end
        parsed = try
            Meta.parseall(content; filename=file)
        catch err
            push!(errors, "$(relpath(file, root)): $(sprint(showerror, err))")
            continue
        end
        _collect_testitems!(items, errors, parsed, root, file)
    end

    sort!(items; by=item -> (item.file, item.line, item.name))
    seen = Dict{String,TestItemInfo}()
    for item in items
        if haskey(seen, item.id)
            push!(errors, "Duplicate test identity $(item.key)")
        else
            seen[item.id] = item
        end
    end
    TestCatalog(root, items, errors)
end

_test_item(catalog::TestCatalog, id) = let i = findfirst(item -> item.id == id, catalog.items)
    isnothing(i) ? nothing : catalog.items[i]
end

function _test_log_path()
    path, io = mktemp(; cleanup=false)
    close(io)
    path
end

function _test_command(project, selection)
    args = ["--htmxo-test=" * key for key in selection]
    julia = Base.julia_cmd()
    expression = "using Pkg; Pkg.test(; test_args=ARGS)"
    command = `$julia --startup-file=no --history-file=no --project=$project -e $expression -- $args`
    addenv(command, "JULIA_LOAD_PATH" => "@:@stdlib")
end

function _set_job!(store, job; status=job.status, started_at=job.started_at,
        finished_at=job.finished_at, exitcode=job.exitcode, process=job.process,
        error=job.error)
    lock(store.lock)
    try
        job.status = status
        job.started_at = started_at
        job.finished_at = finished_at
        job.exitcode = exitcode
        job.process = process
        job.error = error
    finally
        unlock(store.lock)
    end
    job
end

function _execute_test_job!(store, project, job)
    _set_job!(store, job; status=:running, started_at=time())
    try
        open(job.log_path, "w") do io
            process = run(pipeline(ignorestatus(_test_command(project, job.selection));
                stdout=io, stderr=io); wait=false)
            _set_job!(store, job; process)
            wait(process)
            code = process.exitcode
            _set_job!(store, job;
                status=code == 0 ? :passed : :failed,
                finished_at=time(), exitcode=code, process=nothing)
        end
    catch err
        bt = catch_backtrace()
        detail = sprint(showerror, err, bt)
        try
            open(job.log_path, "a") do io
                println(io, "\nHTMXObjects test runner error:\n", detail)
            end
        catch
        end
        _set_job!(store, job; status=:error, finished_at=time(), process=nothing,
            error=detail)
    end
    nothing
end

function _delete_test_log(job)
    isempty(job.log_path) || !isfile(job.log_path) || rm(job.log_path; force=true)
end

function _trim_test_jobs!(store)
    while length(store.jobs) > _TEST_JOB_LIMIT
        _delete_test_log(pop!(store.jobs))
    end
end

function _active_test_job(store)
    findfirst(job -> job.status in (:queued, :running), store.jobs)
end

function _start_test_job(project, items)
    root = _test_project(project)
    isempty(items) && return nothing, "No tests were selected."
    store = _test_store(root)
    lock(store.lock)
    job = try
        active = _active_test_job(store)
        isnothing(active) || return nothing, "A test run is already active."
        job = TestRunJob(
            string(time_ns(); base=16),
            [item.key for item in items],
            [item.name for item in items],
            :queued, time(), nothing, nothing, nothing,
            _test_log_path(), nothing, "",
        )
        pushfirst!(store.jobs, job)
        _trim_test_jobs!(store)
        job
    finally
        unlock(store.lock)
    end
    errormonitor(@async _execute_test_job!(store, root, job))
    job, ""
end

function _test_job_snapshot(project)
    store = _test_store(project)
    lock(store.lock)
    try
        [TestRunJob(
            job.id, copy(job.selection), copy(job.labels), job.status,
            job.created_at, job.started_at, job.finished_at, job.exitcode,
            job.log_path, job.process, job.error,
        ) for job in store.jobs]
    finally
        unlock(store.lock)
    end
end

function _selected_testitems(catalog, ids)
    unique_ids = unique(string.(ids))
    items = TestItemInfo[]
    missing = String[]
    for id in unique_ids
        item = _test_item(catalog, id)
        if isnothing(item)
            push!(missing, id)
        else
            push!(items, item)
        end
    end
    items, missing
end

function _latest_item_jobs(catalog, jobs)
    latest = Dict{String,TestRunJob}()
    by_key = Dict(item.key => item.id for item in catalog.items)
    for job in jobs
        for key in job.selection
            id = get(by_key, key, nothing)
            isnothing(id) || haskey(latest, id) || (latest[id] = job)
        end
    end
    latest
end

function _read_test_log(job)
    isfile(job.log_path) || return job.error
    text = try
        read(job.log_path, String)
    catch err
        return "Unable to read test output: $(sprint(showerror, err))"
    end
    replace(text, r"\e\[[0-9;?]*[ -/]*[@-~]" => "")
end

function _test_log_preview(job)
    text = _read_test_log(job)
    length(text) <= _TEST_LOG_LIMIT && return text, false
    "Preview shows the final $(_TEST_LOG_LIMIT) characters.\n" *
        last(text, _TEST_LOG_LIMIT), true
end

_test_status_label(status) = status in (:queued, :running, :passed, :failed, :error) ?
    string(status) : "pending"

function _test_status_class(status)
    status == :passed && return "u-text-success"
    status == :failed && return "u-text-error"
    status == :error && return "u-text-warning"
    status in (:queued, :running) && return "u-text-primary"
    "u-text-muted"
end

function _test_duration(job)
    isnothing(job.started_at) && return ""
    stop = isnothing(job.finished_at) ? time() : job.finished_at
    fmt_time(max(0, stop - job.started_at))
end

function _test_description(item)
    isempty(item.description) && return h.span(; class="u-text-muted")("—")
    first_line = first(split(item.description, '\n'; limit=2))
    h.details(
        h.summary(; class="u-pointer")(first_line),
        h.div(; class="u-mt-2")(HTMX.md_to_node(item.description)),
    )
end

function _test_job_view(job; prefix="/tests")
    output, bounded = _test_log_preview(job)
    status = _test_status_label(job.status)
    h.details(; open=job.status in (:running, :failed, :error))(
        h.summary(; class="u-pointer")(
            h.span(; class=_test_status_class(job.status))(status),
            " — ", join(job.labels, ", "),
            isempty(_test_duration(job)) ? "" : " ($( _test_duration(job) ))",
        ),
        h.div(; class="u-mt-2")(
            h.p(; class="u-text-sm u-text-muted")(
                "Job ", h.code(job.id),
                isnothing(job.exitcode) ? "" : " · exit $(job.exitcode)",
            ),
            isempty(output) ? h.p(; class="u-text-muted")("Waiting for output…") :
                h.pre(; class="u-text-xs u-scroll-y u-pre-wrap")(
                    escape_html(output),
                ),
            bounded ? h.p(
                h.a("Open complete output"; href="$(prefix)/output/$(job.id)",
                    target="_blank"),
            ) : "",
        ),
    )
end

"""
    test_output(project, id; prefix="/tests")

Render the complete captured output for one validated test job. The main test
page keeps large polling fragments bounded and links here without discarding
the beginning of the log.
"""
function test_output(project, id; prefix="/tests")
    jobs = _test_job_snapshot(project)
    index = findfirst(job -> job.id == id, jobs)
    if isnothing(index)
        return h.main(; class="container")(
            h.h1("Unknown test job"),
            h.p("No captured output exists for job ", h.code(string(id)), "."),
            h.a("Back to tests"; href=prefix),
        )
    end

    job = jobs[index]
    output = _read_test_log(job)
    h.main(; class="container")(
        h.p(h.a("Back to tests"; href=prefix)),
        h.h1("Test output"),
        h.p(
            h.span(; class=_test_status_class(job.status))(_test_status_label(job.status)),
            " — ", join(job.labels, ", "),
            " · job ", h.code(job.id),
        ),
        isempty(output) ? h.p(; class="u-text-muted")("Waiting for output…") :
            h.pre(; class="u-text-xs u-scroll-y u-pre-wrap")(escape_html(output)),
    )
end

function _test_summary(catalog, latest)
    counts = Dict(:passed => 0, :failed => 0, :error => 0, :running => 0, :pending => 0)
    for item in catalog.items
        job = get(latest, item.id, nothing)
        status = isnothing(job) ? :pending : job.status == :queued ? :running : job.status
        counts[haskey(counts, status) ? status : :pending] += 1
    end
    join(("$(counts[s]) $(s)" for s in (:passed, :failed, :error, :running, :pending)
        if counts[s] > 0), ", ") * " ($(length(catalog.items)) total)"
end

"""
    test_list(project; prefix="/tests", notice="")

Render the current test catalog and isolated run history. The returned value is
an ordinary `Node`; the HTMXObjects response pipeline owns page, fragment, and
`?plain` rendering.
"""
function test_list(project; prefix="/tests", notice="")
    catalog = discover_test_items(project)
    jobs = _test_job_snapshot(catalog.project)
    latest = _latest_item_jobs(catalog, jobs)
    active = any(job -> job.status in (:queued, :running), jobs)
    tags = sort!(unique(reduce(vcat, (item.tags for item in catalog.items); init=Symbol[])); by=string)

    rows = map(catalog.items) do item
        job = get(latest, item.id, nothing)
        status = isnothing(job) ? :pending : job.status
        h.tr(
            h.td(h.input(; type="checkbox", name="names", value=item.id,
                aria_label="Select $(item.name)")),
            h.td(
                h.strong(item.name),
                h.div(; class="u-text-xs u-text-muted")("$(item.file):$(item.line)"),
            ),
            h.td(_test_description(item)),
            h.td(isempty(item.tags) ? "—" : join(("#" * string(tag) for tag in item.tags), " ")),
            h.td(
                h.span(; class=_test_status_class(status))(_test_status_label(status)),
                isnothing(job) || isempty(_test_duration(job)) ? "" : h.div(; class="u-text-xs")(_test_duration(job)),
            ),
            h.td(h.button("Run"; type="button", hx_post="$(prefix)/run/$(item.id)",
                hx_target="#tests-container", hx_swap="outerHTML")),
        )
    end

    attrs = active ? (; id="tests-container", hx_get="$(prefix)/status",
        hx_trigger="every 1s", hx_swap="outerHTML") : (; id="tests-container")

    notice_node = isempty(notice) ? nothing : h.p(; role="status")(notice)
    errors_node = isempty(catalog.errors) ? nothing : h.article(; class="u-text-warning")(
        h.strong("Catalog errors"), h.ul((h.li(error) for error in catalog.errors)...),
    )
    tags_node = isempty(tags) ? nothing : h.div(; class="u-mb-4")(
        h.span(; class="u-text-sm u-text-muted u-mr-2")("Run tag:"),
        (h.button("#$(tag)"; type="button", hx_post="$(prefix)/run_tag/$(tag)",
            hx_target="#tests-container", hx_swap="outerHTML", class="u-mr-2") for tag in tags)...,
    )
    jobs_node = isempty(jobs) ? nothing : h.section(; class="u-mt-6")(
        h.h2("Run output"), (_test_job_view(job; prefix) for job in jobs)...,
    )

    children = Any[
        h.h1("Tests"),
        notice_node,
        errors_node,
        h.form(; hx_post="$(prefix)/run_selected", hx_target="#tests-container",
            hx_swap="outerHTML")(
            h.div(; class="u-mb-4")(
                h.button("Run selected"; type="submit", class="u-mr-2"),
                h.button("Run all"; type="button", hx_post="$(prefix)/run_all",
                    hx_target="#tests-container", hx_swap="outerHTML", class="u-mr-2"),
                h.button("Run failed"; type="button", hx_post="$(prefix)/run_failed",
                    hx_target="#tests-container", hx_swap="outerHTML", class="u-mr-2"),
                h.button("Run missing"; type="button", hx_post="$(prefix)/run_missing",
                    hx_target="#tests-container", hx_swap="outerHTML", class="u-mr-2"),
                h.button("Clear results"; type="button", hx_post="$(prefix)/clear",
                    hx_target="#tests-container", hx_swap="outerHTML"),
                h.span(; class="u-ml-4 u-text-sm u-text-muted")(_test_summary(catalog, latest)),
            ),
            isnothing(tags_node) ? "" : tags_node,
            h.table(; role="grid")(
                h.thead(h.tr(h.th(""), h.th("Test"), h.th("Description"),
                    h.th("Tags"), h.th("Status"), h.th("Action"))),
                h.tbody(rows...),
            ),
        ),
        jobs_node,
    ]
    h.div(; attrs...)(filter(!isnothing, children)...)
end

function test_run!(project, id; prefix="/tests")
    catalog = discover_test_items(project)
    item = _test_item(catalog, id)
    isnothing(item) && return test_list(project; prefix, notice="Unknown test selection: $id")
    _, notice = _start_test_job(catalog.project, [item])
    test_list(project; prefix, notice=isempty(notice) ? "Started $(item.name)." : notice)
end

function test_run_batch!(project, ids; prefix="/tests")
    catalog = discover_test_items(project)
    items, missing = _selected_testitems(catalog, ids)
    !isempty(missing) && return test_list(project; prefix,
        notice="Unknown test selection: $(join(missing, ", "))")
    _, notice = _start_test_job(catalog.project, items)
    test_list(project; prefix,
        notice=isempty(notice) ? "Started $(length(items)) selected test(s)." : notice)
end

test_run_batch!(project, ids::AbstractString; prefix="/tests") =
    test_run_batch!(project, filter(!isempty, split(ids, ',')); prefix)

function test_run_all!(project; prefix="/tests")
    catalog = discover_test_items(project)
    _, notice = _start_test_job(catalog.project, catalog.items)
    test_list(project; prefix,
        notice=isempty(notice) ? "Started all $(length(catalog.items)) test(s)." : notice)
end

function test_run_tag!(project, tag; prefix="/tests")
    catalog = discover_test_items(project)
    selected_tag = Symbol(tag)
    items = [item for item in catalog.items if selected_tag in item.tags]
    _, notice = _start_test_job(catalog.project, items)
    test_list(project; prefix,
        notice=isempty(notice) ? "Started $(length(items)) #$(selected_tag) test(s)." : notice)
end

function _rerun_keys(project, predicate; prefix)
    catalog = discover_test_items(project)
    jobs = _test_job_snapshot(catalog.project)
    latest = _latest_item_jobs(catalog, jobs)
    items = [item for item in catalog.items if predicate(get(latest, item.id, nothing))]
    _, notice = _start_test_job(catalog.project, items)
    test_list(project; prefix,
        notice=isempty(notice) ? "Started $(length(items)) test(s)." : notice)
end

test_run_failed!(project; prefix="/tests") =
    _rerun_keys(project, job -> !isnothing(job) && job.status in (:failed, :error); prefix)

test_run_missing!(project; prefix="/tests") =
    _rerun_keys(project, isnothing; prefix)

function test_clear_cache!(project; prefix="/tests")
    store = _test_store(project)
    lock(store.lock)
    notice = try
        active = _active_test_job(store)
        if isnothing(active)
            foreach(_delete_test_log, store.jobs)
            empty!(store.jobs)
            "Cleared test results."
        else
            "Cannot clear results while a test run is active."
        end
    finally
        unlock(store.lock)
    end
    test_list(project; prefix, notice)
end
