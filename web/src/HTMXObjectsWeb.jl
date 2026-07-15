module HTMXObjectsWeb

using HTMXObjects
using HTMXObjects.DynamicObjects
using DataFrames

include("demo.jl")
include("lazy_grid.jl")
include("sortable_table.jl")
include("captions.jl")
include("posteriors.jl")
include("editor_demo.jl")
include("git_editor_demo.jl")
include("gallery_demo.jl")

@dynamicstruct struct AppData
    demo = DemoData()
    lazy_grid = LazyGridData()
    sortable_table = SortableTableData()
    captions = CaptionsData()
    posteriors = PosteriorsData()
    editor_demo = EditorDemoData()
    git_editor_demo = GitEditorDemoData()
    gallery_demo = GalleryDemoData()
end

const APPDATA = AppData()
const TEST_PROJECT = normpath(joinpath(@__DIR__, "..", ".."))

@htmx struct AppRoutes
    __appdata__ = APPDATA

    __page__(content) = htmx(h.main(class="container")(content); pico_version="2")

    @get index() = h.div(
        h.h1("HTMXObjectsWeb"),
        h.ul(
            h.li(h.a(href=__self__/"tests")("Tests")),
            h.li(h.a(href=__self__/"demo")("Feedback demo")),
            h.li(h.a(href=__self__/"lazy_grid")("Lazy grid demo")),
            h.li(h.a(href=__self__/"posteriors")("Posteriors / lazy-grid demo")),
            h.li(h.a(href=__self__/"sortable_table")("Sortable table demo")),
            h.li(h.a(href=__self__/"captions")("Captions demo")),
            h.li(h.a(href=__self__/"editor_demo")("Editor form demo")),
            h.li(h.a(href=__self__/"git_editor_demo")("Git-backed editor demo")),
            h.li(h.a(href=__self__/"gallery_demo")("Gallery primitive demo")),
            h.li(h.a(href=__self__/"schema")("App schema (JSON)")),
        ),
    )

    @include demo = DemoRoutes()
    @include lazy_grid = LazyGridRoutes()
    @include sortable_table = SortableTableRoutes()
    @include captions = CaptionsRoutes()
    @include posteriors = PosteriorsRoutes()
    @include editor_demo = EditorDemoRoutes()
    @include git_editor_demo = GitEditorDemoRoutes()
    @include gallery_demo = GalleryDemoRoutes()
    @include tests = TestRoutes(; project=TEST_PROJECT)
    @include schema = SchemaRoutes(; root=AppRoutes)
end

function __init__()
    route!(AppRoutes())
end

end # module HTMXObjectsWeb
