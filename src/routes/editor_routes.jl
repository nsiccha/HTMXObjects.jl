"""
    EditorRoutes

Git-backed inline editor `@htmx` struct. Mount as an `@include` under a
parent that exposes `editor` (a per-file handle, normally
`GitRepo(path).editor(relpath)`) and `container_id::String` (HTML id of the
wrapper) as locals. All URLs forward the parent's `@param` values via
`query_url(path, __parent__)`, so a parameterised parent
(`@param name::String` picking which file to edit) survives
edit/save/cancel/history/restore round-trips with no extra wiring.

# The `editor` local

`editor` is supplied by the mounting app, and every route computes with it.
It must expose these five properties — `GitRepo(path).editor(relpath)` is
the built-in implementation, but any object with the same surface works:

| Property | Returns |
|---|---|
| `current_content()` | current file content, `String` |
| `current_version()` | current blob sha, `String` (`""` for an unborn file) |
| `versions()` | iterable of revisions, each with `sha`, `author`, `message` — empty when nothing is committed yet |
| `read_version(sha)` | that revision's content, `String` |
| `write!(content; version, message)` | `(:ok, commit_sha)`, or `(:conflict, current_blob_sha)` when `version` is stale |

"this editor exists but has no recorded history yet" is `versions()`
returning an **empty collection** — not a placeholder value. Mounting with
a value that lacks these properties raises an error naming the route and
the missing ones, rather than failing inside the route body.

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
# `editor` comes from the MOUNTING APP, so a value that is not a per-file handle
# only surfaces once a route computes with it — as a `MethodError` raised deep
# inside `collect`/destructuring that names neither the property that was wrong
# nor what it needed (measured: a placeholder value reached `history` and
# reported `no method matching length(::StubExpr)` four frames down). These
# guards check the property surface at the point of use and name both. They
# inspect `hasproperty` only and never wrap the calls, so a genuine failure
# inside a real handle still propagates untouched.
const _EDITOR_API = (:current_content, :current_version, :versions, :read_version, :write!)

_editor_props(names) = join(("`$p`" for p in names), ", ")

function _check_editor(editor, route::Symbol, needed)
    absent = Symbol[p for p in needed if !hasproperty(editor, p)]
    isempty(absent) && return editor
    error("EditorRoutes.$route: `editor` must be a per-file handle as returned by " *
          "`GitRepo(path).editor(relpath)`, exposing " * _editor_props(_EDITOR_API) *
          "; got $(typeof(editor)) with no " * _editor_props(absent) *
          ". Fix the `editor` local the parent passes to `@include … = EditorRoutes(…)`.")
end

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

    @get form() = begin
        _check_editor(editor, :form, (:current_content, :current_version))
        editor_form(;
            id          = container_id,
            post_url    = query_url(__self__ / "save", __parent__),
            cancel_url  = query_url(__parent__.__prefix__, __parent__),
            content     = editor.current_content(),
            version     = editor.current_version(),
            input, rows, placeholder, label,
        )
    end

    @post save(; content="", version="") = begin
        _check_editor(editor, :save, (:write!, :current_content))
        status, value = editor.write!(content; version)
        status === :conflict ?
            _editor_conflict_fragment(editor, content, value, container_id,
                                       query_url(__self__ / "save", __parent__),
                                       query_url(__parent__.__prefix__, __parent__)) :
            __parent__.index(Verb{:GET}())
    end

    @get history() = begin
        _check_editor(editor, :history, (:versions,))
        revisions = editor.versions()
        # A handle whose `versions()` returns a non-iterable would otherwise blow
        # up inside the comprehension's `collect`, naming neither `versions` nor
        # the requirement. An editor with no recorded history yet returns empty.
        applicable(iterate, revisions) || error(
            "EditorRoutes.history: `editor.versions()` must return an iterable of " *
            "revisions (each with `sha`, `author`, `message`), or an empty " *
            "collection when nothing is committed yet; got $(typeof(revisions)).")
        h.div(; id=container_id)(
            h.h3("History"),
            h.ul([h.li(
                      h.code(v.sha[1:min(8, length(v.sha))]), " · ",
                      v.author, " · ",
                      h.small(v.message), " ",
                      h.button("Restore";
                          hx_post=query_url(__self__ / "restore", __parent__; sha=v.sha),
                          hx_target="#$container_id", hx_swap="outerHTML")
                  ) for v in revisions]...),
            h.button("Back"; hx_get=query_url(__parent__.__prefix__, __parent__),
                     hx_target="#$container_id", hx_swap="outerHTML"),
        )
    end

    @post restore(; sha::String="") = begin
        _check_editor(editor, :restore, (:read_version, :current_version, :write!))
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
