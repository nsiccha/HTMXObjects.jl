# Gallery primitive demo — exercises HTMXObjects' file-based Gallery /
# GalleryItem against a fixture directory. Doubles as the live-app
# verification path for `record!` and `Gallery` (no Julia subprocess
# needed: hit these routes via curl).

@dynamicstruct struct GalleryDemoData
    fixture_dir = joinpath(@__DIR__, "test_fixtures", "gallery_demo")
    gallery = Gallery(fixture_dir)
end

@htmx struct GalleryDemoRoutes
    (; gallery) = __appdata__.gallery_demo

    @get index() = h.div(
        h.h1("Gallery primitive demo"),
        h.p(
            "Walks ", h.code("web/src/test_fixtures/gallery_demo/"),
            " and renders one card per ", h.code(".jl"), " file. ",
            "Curl ", h.code("/gallery_demo?plain"),
            " for the markdown view (each item's metadata + body).",
        ),
        h.p(
            "Routes: ",
            h.a("/items"; href=__self__/"items"), " — list as a table; ",
            h.a("/item/scatter"; href=__self__/"item/scatter"), " — single item; ",
            h.a("/record_test"; href=__self__/"record_test"), " — drive ", h.code("record!"), "; ",
            h.a("/recorded"; href=__self__/"recorded"), " — stat /tmp/htmxo-gallery-demo-record/.",
        ),
        h.p(
            h.strong("See also: "),
            h.a("AoV gallery"; href="http://localhost:8092"),
            " (100+ items at ", h.code(":8092"), "), ",
            h.a("BRM gallery"; href="http://localhost:8121/pipeline/gallery"),
            " (PPC cards, lazy-loaded). Both built on the same ",
            h.code("HTMXObjects.Gallery"),
            " primitive demonstrated here.",
        ),
        gallery_grid(gallery.items; section_titles=gallery.section_titles),
    )

    @get items() = render_table(DataFrame(
        section     = [it.section     for it in gallery.items],
        id          = [it.id          for it in gallery.items],
        title       = [it.title       for it in gallery.items],
        description = [it.description for it in gallery.items],
    ))

    @get item(id) = let it = find_item(gallery, id)
        isnothing(it) ?
            h.article("No item with id $(id) (have: $(join([i.id for i in gallery.items], ", ")))") :
            h.article(
                h.header(h.h2(it.title)),
                isempty(it.description) ? h.span() : h.p(it.description),
                h.pre(h.code(it.code_string)),
                h.footer(
                    h.small("section: $(it.section); path: $(it.path)"),
                ),
            )
    end

    # Collect all relative file paths under `dir`, sorted.
    dir_files(dir) = sort!(
        [relpath(joinpath(root, f), dir)
         for (root, _, fs) in walkdir(dir) for f in fs]
    )

    # Drive `record!` against a tiny in-process app and surface the
    # produced filesystem tree. Lets us verify the recorder + the
    # markdown shape without spawning a subprocess.
    @get record_test() = let
        out_dir = joinpath(tempdir(), "htmxo-gallery-demo-record")
        isdir(out_dir) && rm(out_dir; recursive=true)
        # Use the GalleryDemoRoutes itself as the recordee: it already has
        # routes that pass `?plain` cleanly through to_markdown_string.
        # Construct a fresh registered app and record the index + a few
        # items.
        paths = ["/items", ["/item/$(it.id)" for it in gallery.items]...]
        # Ad-hoc: mount a copy of THIS struct under /gd and record it.
        # (record! re-registers via route!, so it'd clobber our running
        # routes if we reused __self__. Use a separate mounted prefix.)
        record!(GalleryDemoRoutes(; __appdata__=__appdata__);
                record_dir=out_dir,
                record_base="/gallery_demo_recordings",
                paths)
        h.div(
            h.h2("record! produced:"),
            h.p(h.code(out_dir)),
            h.ul([h.li(h.code(f)) for f in dir_files(out_dir)]...),
        )
    end

    @get recorded() = let
        # Browseable listing of the last record_test output.
        out_dir = joinpath(tempdir(), "htmxo-gallery-demo-record")
        isdir(out_dir) || return h.p("No recordings yet — hit /gallery_demo/record_test first.")
        h.div(
            h.h2("Recordings under $out_dir"),
            h.ul([h.li(h.code(f)) for f in dir_files(out_dir)]...),
        )
    end
end
