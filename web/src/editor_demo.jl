@dynamicstruct struct EditorDemoData
    initial_text = "# Notes\n\nEdit me. Press Escape to cancel.\n"
end

@htmx struct EditorDemoRoutes
    (; initial_text) = __appdata__.editor_demo

    @get index() = h.div(
        h.h1("editor_form demo"),
        h.section(
            h.h2("Textarea"),
            view("textarea-view", initial_text, :textarea),
        ),
        h.section(
            h.h2("Text input"),
            view("text-view", "https://example.com/paste-here", :text),
        ),
    )

    view(id, text, kind) = h.div(; id)(
        h.pre(text),
        h.button("Edit";
            hx_get=query_url(__self__/"edit"/id; kind),
            hx_target="#$id",
            hx_swap="outerHTML"),
    )

    @get edit(id; kind::Symbol=:textarea) = editor_form(;
        id,
        post_url   = __self__/"save"/id,
        cancel_url = query_url(__self__/"cancel"/id; kind),
        content    = kind === :text ? "https://example.com/paste-here" : initial_text,
        version    = "v0",
        input      = kind,
        rows       = 8,
        placeholder = kind === :text ? "URL..." : "",
        label      = "Editing: $id",
    )

    @get cancel(id; kind::Symbol=:textarea) =
        view(id, kind === :text ? "https://example.com/paste-here" : initial_text, kind)

    @post save(id; content="", version="") =
        view(id, content, id == "text-view" ? :text : :textarea)
end
