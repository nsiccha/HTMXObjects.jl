@testmodule GalleryFixture begin
    using HTMXObjects
    export fixture_gallery, custom_gallery

    # Two tagged sections, an untagged card in the first, an untagged section.
    function fixture_gallery()
        dir = mktempdir()
        files = [
            "odl/a.jl" => "# title: Alpha\n# tags: bayes, stan\n\n1\n",
            "odl/b.jl" => "# title: Beta\n# tags: stan web\n\n2\n",
            "odl/c.jl" => "# title: Gamma\n# tags: bayes\n\n3\n",
            "odl/d.jl" => "# title: Delta\n\n4\n",
            "odl/_section.md" => "# ODL showcases\n",
            "pkgs/e.jl" => "# title: Epsilon\n# tags: julia\n\n5\n",
            "pkgs/f.jl" => "# title: Phi\n# tags: julia, web\n\n6\n",
            "zplain/g.jl" => "# title: Plain\n\n7\n",
        ]
        for (rel, body) in files
            mkpath(dirname(joinpath(dir, rel)))
            write(joinpath(dir, rel), body)
        end
        Gallery(dir)
    end

    # A custom card renderer that keeps only the attributes the controller
    # reads for tags (no data-search-text, so search falls back to the text).
    function custom_gallery()
        dir = mktempdir()
        mkpath(joinpath(dir, "custom"))
        for (id, tags) in (("red1", "red"), ("blue1", "blue"), ("both1", "red blue"))
            write(joinpath(dir, "custom", "$id.jl"), "# tags: $tags\n\n$(repr(id))\n")
        end
        g = Gallery(dir)
        render = it -> h.article(; id=it.id, data_id=it.id, data_section=it.section,
                                   data_tags=join(it.tags, " "))(h.h4(it.title), h.p("custom card"))
        g, render
    end
end

@testitem "gallery_grid tag_filters renders one chip row per tagged section" setup=[GalleryFixture] tags=[:unit] begin
    using HTMXObjects
    g = fixture_gallery()
    html(x) = repr("text/html", x)
    plain = html(gallery_grid(g.items; section_titles=g.section_titles))
    # (The controller script names the chip selectors, so match markup.)
    @test !occursin("<div data-role=\"tag-filters\"", plain)
    @test !occursin("data-tag-match=", plain)

    page = html(gallery_grid(g.items; section_titles=g.section_titles, tag_filters=true))
    # Distinct tags of the section's items, first appearance first.
    @test occursin("<h3>ODL showcases</h3><div data-role=\"tag-filters\" data-tag-match=\"all\">" *
        "<button type=\"button\" data-tag=\"bayes\" aria-pressed=\"false\">bayes</button>" *
        "<button type=\"button\" data-tag=\"stan\" aria-pressed=\"false\">stan</button>" *
        "<button type=\"button\" data-tag=\"web\" aria-pressed=\"false\">web</button></div>" *
        "<article id=\"a\"", page)
    @test occursin("<h3>pkgs</h3><div data-role=\"tag-filters\"", page)
    # A section without tags gets no chips.
    @test occursin("<h3>zplain</h3><article id=\"g\"", page)
    @test count("<div data-role=\"tag-filters\"", page) == 2

    anymatch = html(gallery_grid(g.items; tag_filters=true, tag_match=:any))
    @test count("data-tag-match=\"any\"", anymatch) == 2
    # refused: tag_match names the chip semantics; an unknown value has none
    # and must not fall back to one silently (dev §4.5).
    @test_throws ArgumentError gallery_grid(g.items; tag_filters=true, tag_match=:none)

    # Chips alone still get the root and the controller, without an empty toolbar.
    chips_only = html(gallery_grid(g.items; tag_filters=true, search=false, pagination=false))
    @test startswith(chips_only, "<div class=\"htmxo-gallery-root\"><div class=\"htmxo-gallery\">")
    @test !occursin("<div class=\"htmxo-gallery-toolbar\"", chips_only)
    @test occursin("<script>", chips_only)
    # controls=false keeps the bare gallery; its chips need the app's own root.
    bare = html(gallery_grid(g.items; tag_filters=true, controls=false))
    @test startswith(bare, "<div class=\"htmxo-gallery\">")
    @test occursin("<div data-role=\"tag-filters\"", bare)
    @test !occursin("<script", bare)
end

@testitem "gallery_grid controls and chips stay out of Markdown" setup=[GalleryFixture] tags=[:unit] begin
    using HTMXObjects
    g = fixture_gallery()
    md(x) = repr(MIME"text/markdown"(), x)
    full = md(gallery_grid(g.items; section_titles=g.section_titles, tag_filters=true))
    @test full == md(gallery_grid(g.items; section_titles=g.section_titles, controls=false))
    @test !occursin("Page size", full)
    @test !occursin("No items match", full)
    @test !occursin("bayes", full)
    @test occursin("### ODL showcases", full)
    @test occursin("[Alpha](#a)", full)
end

@testitem "gallery tag chips stay live in a static export" setup=[GalleryFixture] tags=[:unit] begin
    using HTMXObjects
    g = fixture_gallery()
    page = htmx(gallery_grid(g.items; section_titles=g.section_titles, tag_filters=true);
                pico_version=nothing, hyperscript_version=nothing)
    live = repr("text/html", page)
    group = match(r"<h3>ODL showcases</h3><div data-role=\"tag-filters\".*?</div>"s, live).match
    for controls in (:disable, :remove)
        exported = repr("text/html", static_transform(page, StaticExport(; controls)))
        @test occursin(group, exported)
        @test occursin("chipGroups", exported)
    end
end

@testitem "gallery tag chips filter cards in a real browser" setup=[GalleryFixture, ChromeDump] tags=[:unit, :browser] begin
    using HTMXObjects, HTTP, Sockets
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"))
        g = fixture_gallery()
        cg, render = custom_gallery()
        driver = h.script(Raw(raw"""
        window.addEventListener('load', function() {
            const checks = [];
            const check = (name, ok) => checks.push([name, Boolean(ok)]);
            const section = s => document.querySelector('section[data-section="' + s + '"]');
            const shown = s => Array.from(section(s).querySelectorAll(':scope > article'))
                .filter(c => c.offsetParent !== null).map(c => c.dataset.id).join(',');
            const chip = (s, t) => section(s).querySelector('[data-tag="' + t + '"]');
            const on = (s, t) => chip(s, t).getAttribute('aria-pressed') === 'true';
            const search = document.querySelector('.htmxo-gallery-toolbar input[type="search"]');
            const type = v => { search.value = v; search.dispatchEvent(new Event('input', {bubbles: true})); };
            const tagParam = () => new URLSearchParams(location.search).get('tag.odl');
            const finish = () => {
                const result = document.createElement('pre'); result.id = 'checks';
                result.textContent = checks.map(([name, ok]) => name + ':' + ok).join('\n');
                document.body.appendChild(result);
            };
            if (new URLSearchParams(location.search).has('tag.odl')) {
                // Deep link: ?tag.odl=bayes,stan restores the pressed chips.
                check('restored-pressed', on('odl', 'bayes') && on('odl', 'stan') && !on('odl', 'web'));
                check('restored-filter', shown('odl') === 'a' && shown('pkgs') === 'e,f');
                check('restored-dead-chip', chip('odl', 'web').disabled);
                return finish();
            }
            check('initial', shown('odl') === 'a,b,c,d' && shown('pkgs') === 'e,f' && shown('zplain') === 'g');
            check('no-chips-untagged', !section('zplain').querySelector('[data-role="tag-filters"]'));
            chip('odl', 'stan').click();
            check('stan-pressed', on('odl', 'stan'));
            check('stan-narrows', shown('odl') === 'a,b');
            check('other-section-untouched', shown('pkgs') === 'e,f');
            check('url-written', tagParam() === 'stan');
            check('live-chips-enabled', !chip('odl', 'bayes').disabled && !chip('odl', 'web').disabled);
            chip('odl', 'bayes').click();
            check('all-semantics', shown('odl') === 'a');
            check('dead-chip-disabled', chip('odl', 'web').disabled);
            check('pressed-stay-enabled', !chip('odl', 'stan').disabled && !chip('odl', 'bayes').disabled);
            check('url-two-tags', tagParam() === 'bayes,stan');
            chip('odl', 'bayes').click();
            check('unpress', shown('odl') === 'a,b');
            type('web');
            check('search-and-tags', shown('odl') === 'b' && shown('pkgs') === 'f');
            check('search-disables-chip', chip('odl', 'bayes').disabled);
            type('julia');
            check('empty-section-hidden', section('odl').offsetParent === null && shown('pkgs') === 'e,f');
            type('');
            check('section-back', section('odl').offsetParent !== null && shown('odl') === 'a,b');
            chip('odl', 'stan').click();
            check('cleared', shown('odl') === 'a,b,c,d' && tagParam() === null);
            // A custom card renderer and tag_match=:any.
            chip('custom', 'red').click();
            check('any-one', shown('custom') === 'both1,red1');
            chip('custom', 'blue').click();
            check('any-widens', shown('custom') === 'blue1,both1,red1');
            chip('custom', 'blue').click(); chip('custom', 'red').click();
            // Following a card's #anchor reveals it past the chips.
            chip('odl', 'web').click();
            check('web-only', shown('odl') === 'b');
            window.addEventListener('hashchange', () => setTimeout(() => {
                check('hash-reveals', shown('odl').split(',').includes('a') && !on('odl', 'web'));
                finish();
            }, 0));
            location.hash = 'a';
        });
        """))
        page = htmx(
            gallery_grid(g.items; section_titles=g.section_titles, tag_filters=true),
            gallery_grid(cg.items; card_renderer=render, tag_filters=true, tag_match=:any,
                         search=false, pagination=false),
            driver; extra_head=(htmxo_gallery_styles(),), pico_version=nothing,
            hyperscript_version=nothing, feedback=false, compose=false, overlay=false)
        # Serve the static export as plain files would be: no app behind it.
        exported = repr("text/html", static_transform(page, StaticExport(; controls=:remove)))
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2]); close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            HTTP.URI(req.target).path == "/" ?
                HTTP.Response(200, ["Content-Type" => "text/html"], exported) : HTTP.Response(404)
        end
        try
            for (query, n) in (("", 21), ("?tag.odl=bayes,stan", 3))
                dom = mktempdir() do profile
                    dump_dom(`$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=5000 --dump-dom --user-data-dir=$profile http://127.0.0.1:$port/$query`)
                end
                checks = match(r"<pre id=\"checks\">(.*?)</pre>"s, dom)
                @test !isnothing(checks)
                if !isnothing(checks)
                    for line in split(checks[1], '\n')
                        @test endswith(line, ":true")
                    end
                    @test count(==('\n'), checks[1]) + 1 == n
                end
            end
        finally
            close(server)
        end
    end
end
