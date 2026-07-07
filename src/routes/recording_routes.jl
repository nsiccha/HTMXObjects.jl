# --- Recording: state + mountable routes ---

@dynamicstruct struct RecordingState
    __status__ = _recording_progress_init()

    # Drive `record!` against a fresh app of `app_type`, one path at a
    # time, with a per-path phase marker so the progress tree shows
    # full per-path state (pending → running → finished) when Treebars
    # is loaded. The IP runs once per (app_type, paths, record_dir,
    # record_base) tuple thanks to `:parallel` cache; `?force=true` on
    # the route invalidates and re-runs.
    record(app_type::DataType, paths::Tuple, record_dir::String, record_base::String) = begin
        phases = [_recording_progress_phase(__status__, p) for p in paths]
        # Clean slate so stale files from a previous run don't pollute
        # the output. The recording closures rebuild everything we
        # care about.
        isdir(record_dir) && rm(record_dir; recursive=true)
        mkpath(record_dir)
        # Install recording closures once; restore live (non-recording)
        # routes via the `finally` so subsequent live requests don't
        # keep writing to disk.
        app = app_type()
        route!(app; record_dir, record_base)
        try
            router = CONTEXT[].service.router
            for (p, phase) in zip(paths, phases)
                _recording_run_phase(phase) do _
                    _drive_record_path(router, p, Pair{String,String}[])
                    _drive_record_path(router, p, ["HX-Request" => "true"])
                end
            end
        finally
            route!(app)
        end
        n_html = n_js = n_json = n_other = 0
        for (_, _, files) in walkdir(record_dir)
            for f in files
                ext = lowercase(splitext(f)[2])
                if     ext == ".html" n_html += 1
                elseif ext == ".js"   n_js   += 1
                elseif ext == ".json" n_json += 1
                else                  n_other += 1
                end
            end
        end
        (; n_paths=length(paths), n_html, n_js, n_json, n_other, record_dir)
    end
end

const RECORDING_STATE = RecordingState()

"""
    @include record_gallery = RecordingRoutes(;
        app_type=AppContext,
        paths=String["/", "/page", "/plot/foo"],
        record_dir="docs/src/public/live-app",
        record_base="/MyPkg.jl/dev/live-app",
    )

Mountable routes for the docs-build flow. Provides one route at the
mount prefix:

  GET <prefix>/         — fires the recording IP. `?force=true`
                          invalidates the cache and re-records.
                          With Treebars loaded, returns a live
                          `polling_fetchindex` progress tree until
                          done; without it, blocks until done and
                          returns the summary article.
"""
@htmx struct RecordingRoutes
    # Mountable docs-build route bundle for `record!`-driven recordings.
    app_type::DataType
    paths::Vector{String} = String["/"]
    record_dir::String
    record_base::String = ""
    label::String = "Recording"

    @get index(; force::Bool=false) = _recording_polling(
            RECORDING_STATE.record, app_type, Tuple(paths), record_dir, record_base;
            poll_url=query_url(__route__),
            label,
            force) do summary
        h.article(
            h.header(h.h2("Recording done")),
            h.p("Wrote ", h.code(string(summary.n_paths)),
                " routes (× full + HX shapes) into ", h.code(summary.record_dir), "."),
            h.ul(
                h.li(h.code(string(summary.n_html)),  "  .html"),
                h.li(h.code(string(summary.n_js)),    "  .js"),
                h.li(h.code(string(summary.n_json)),  "  .json"),
                h.li(h.code(string(summary.n_other)), "  other"),
            ),
            h.p(h.strong("Next: "),
                h.code("git add $(summary.record_dir) && git commit && git push"),
                " — CI deploys the rest."),
            h.p("Re-record (overwrites cache): ",
                h.a("?force=true"; href=query_url(__route__; force=true))),
        )
    end
end
