"""
    EditorRoutes

Git-backed inline editor `@htmx` struct. Mount as an `@include` under a
parent that exposes `editor` (a `GitRepo` per-file handle from
`editor(relpath)`) and `container_id::String` (HTML id of the wrapper) as
locals. All URLs forward the parent's `@param` values via
`query_url(path, __parent__)`, so a parameterised parent
(`@param name::String` picking which file to edit) survives
edit/save/cancel/history/restore round-trips with no extra wiring.

# Routes
- `@get form` — renders the editor form via [`editor_form`](@ref).
- `@post save(; content, version)` — optimistic-concurrency write. On
  conflict, re-renders the form with a "content changed" banner.
- `@get history` — lists prior versions with per-version Restore buttons.
- `@post restore(; sha)` — reverts the file to an earlier blob.

# Optional struct fields
- `input::Symbol = :textarea` (or `:text`)
- `rows::Int = 15`
- `placeholder::String = ""`
- `label = nothing`

See the `section_routes` demo in `HTMXObjects/web/src/git_editor_demo.jl`.
"""
@htmx struct EditorRoutes
    # Locals destructured from the parent so the routes can use `editor` and
    # `container_id` directly without a parent-prefix.
    (; editor, container_id) = __parent__
    input::Symbol       = :textarea
    rows::Int           = 15
    placeholder::String = ""
    label               = nothing

    # All URLs forward the parent's `@param` values via `query_url(path, __parent__)`
    # so a parameterised parent (e.g. `@param name::String` picking a file) survives
    # the round-trip through edit/save/cancel/history/restore.

    @get form() = editor_form(;
        id          = container_id,
        post_url    = query_url(__self__ / "save", __parent__),
        cancel_url  = query_url(__parent__.__prefix__, __parent__),
        content     = editor.current_content(),
        version     = editor.current_version(),
        input, rows, placeholder, label,
    )

    @post save(; content="", version="") = begin
        status, value = editor.write!(content; version)
        status === :conflict ?
            _editor_conflict_fragment(editor, content, value, container_id,
                                       query_url(__self__ / "save", __parent__),
                                       query_url(__parent__.__prefix__, __parent__)) :
            __parent__.index(Verb{:GET}())
    end

    @get history() = h.div(; id=container_id)(
        h.h3("History"),
        h.ul([h.li(
                  h.code(v.sha[1:min(8, length(v.sha))]), " · ",
                  v.author, " · ",
                  h.small(v.message), " ",
                  h.button("Restore";
                      hx_post=query_url(__self__ / "restore", __parent__; sha=v.sha),
                      hx_target="#$container_id", hx_swap="outerHTML")
              ) for v in editor.versions()]...),
        h.button("Back"; hx_get=query_url(__parent__.__prefix__, __parent__),
                 hx_target="#$container_id", hx_swap="outerHTML"),
    )

    @post restore(; sha::String="") = begin
        content = editor.read_version(sha)
        editor.write!(content; version=editor.current_version(),
                      message="restore " * sha)
        __parent__.index(Verb{:GET}())
    end
end

function _editor_conflict_fragment(editor, submitted, current_version, container_id,
                                    save_url, cancel_url)
    current = editor.current_content()
    h.div(; id=container_id)(
        h.article(; class="htmxo-editor-conflict")(
            h.header("Content changed since you opened the editor"),
            h.p("Another save landed first. On-disk version is now ",
                h.code(current_version[1:min(8, length(current_version))]), "."),
            h.details(
                h.summary("Show current on-disk content"),
                h.pre(current),
            ),
            h.form(; hx_post=save_url, hx_target="#$container_id", hx_swap="outerHTML")(
                h.textarea(submitted; name="content", rows="15", class="htmxo-editor-input"),
                h.input(; type="hidden", name="version", value=current_version),
                h.div(; class="htmxo-editor-actions")(
                    h.button("Force save (overwrite)"; type="submit"),
                    h.button("Discard my edit";
                        type="button", class="secondary outline",
                        hx_get=cancel_url, hx_target="#$container_id", hx_swap="outerHTML"),
                ),
            ),
        ),
    )
end
