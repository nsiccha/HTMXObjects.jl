@dynamicstruct struct GitEditorDemoData
    repo = GitRepo(joinpath(tempdir(), "htmxo-git-editor-demo"))
    notes = repo.editor("notes.md";
        default_content="# Notes\n\nEdit me, save, try to edit in a second tab — conflict should be caught.\n")
end

@htmx struct GitEditorDemoRoutes
    (; repo, notes) = __appdata__.git_editor_demo
    editor       = notes
    container_id = "git-editor-notes"

    @include editor_routes = EditorRoutes(; rows=10)

    @post append_line(; line::String="") = begin
        status, sha = notes.update!(c -> c * line * "\n";
                                     message="append " * line)
        h.p("$(status): $(sha[1:min(8, length(sha))])")
    end

    @get index() = h.div(; id=container_id)(
        h.h2("Git-backed editor — notes.md"),
        h.p("Repo: ", h.code(repo.path)),
        h.p("Current blob: ",
            h.code(let v = notes.current_version()
                isempty(v) ? "(unborn)" : v[1:min(8, length(v))]
            end)),
        h.pre(notes.current_content()),
        h.div(
            h.button("Edit";
                hx_get=editor_routes / "form",
                hx_target="#$container_id", hx_swap="outerHTML"),
            " ",
            h.button("History";
                hx_get=editor_routes / "history",
                hx_target="#$container_id", hx_swap="outerHTML"),
        ),
        h.hr(),
        h.p("Parameterised sub-editor (pass ", h.code("?name=…"),
            " to pick a section):"),
        h.ul(
            h.li(h.a("intro"; href=query_url(__self__/"section_routes"; name="intro"))),
            h.li(h.a("methods"; href=query_url(__self__/"section_routes"; name="methods"))),
            h.li(h.a("results"; href=query_url(__self__/"section_routes"; name="results"))),
        ),
    )

    # Parameterised child: per-section editor picked by `?name=`. Exercises
    # that `EditorRoutes` forwards the parent's `@param` values through
    # edit/save/cancel/history/restore round-trips.
    @include section_routes = begin
        # `repo` is auto-forwarded from the parent's `(; repo, notes) =
        # __appdata__.git_editor_demo` destructure — re-declaring it
        # here would emit a second `compute_property(…, ::Val{:repo})`
        # method and trip the "overwritten at …" warning.
        @param name::String = "intro"
        editor       = repo.editor("sections/$name.md";
                           default_content="# $name\n\nSection content.\n")
        container_id = "section-" * replace(name, r"[^A-Za-z0-9_-]" => "_")

        @include editor_routes = EditorRoutes(; rows=8, label=name)

        @get index() = h.section(; id=container_id)(
            h.h3("Section: ", h.code(name)),
            h.pre(editor.current_content()),
            h.button("Edit"; hx_get=query_url(editor_routes/"form", __self__),
                             hx_target="#$container_id", hx_swap="outerHTML"),
            " ",
            h.button("History"; hx_get=query_url(editor_routes/"history", __self__),
                                hx_target="#$container_id", hx_swap="outerHTML"),
        )
    end
end
