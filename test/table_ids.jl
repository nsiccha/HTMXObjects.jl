@testitem "tables omit implicit DOM ids" setup=[HTMXOTestImports] tags=[:unit, :semantic] begin
    first = (; Item=["Name"], Result=["alpha"])
    second = (; Item=["Name"], Result=["beta"])
    page = repr("text/html", h.div(SemanticTable(first), SemanticTable(second), SemanticTable(first)))
    @test count("<tbody", page) == 3
    @test contains(page, "alpha") && contains(page, "beta")
    @test !occursin(r"\bid=", page)

    rows = [h.tr(h.td("alpha"))]
    for node in (render_table(first), sortable_table(["Name"], rows),
                 render_table(first; caption=CaptionSpec(; title="Facts")),
                 sortable_table(["Name"], rows; caption=CaptionSpec(; title="Facts")))
        html = repr("text/html", node)
        @test contains(html, "<tbody")
        @test !occursin(r"\bid=", html)
    end
    @test contains(repr("text/html", render_table(first)), "table.csv")

    for id in ("facts", "tbl-facts")
        html = repr("text/html", render_table(first; id, caption=CaptionSpec(; title="Facts")))
        ids = [m.captures[1] for m in eachmatch(r"\bid=\"([^\"]+)\"", html)]
        @test length(ids) == 2
        @test length(unique(ids)) == 2
        @test contains(html, "<tbody id=\"$id\"")
        @test contains(html, "$id.csv")
    end
    html = repr("text/html", render_table(first; download_filename="facts.csv"))
    @test contains(html, "facts.csv")
end

@testitem "unaddressed tables keep sorting and CSV local" setup=[HTMXOTestImports] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "") != "1"
        @test_skip true
    else
        chrome = Sys.which("google-chrome")
        isnothing(chrome) && (chrome = Sys.which("chromium"))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")

        facts = (; Item=["Name"], Result=["alpha"])
        driver = h.script(Raw(raw"""
            window.addEventListener('load', async function() {
                const ids = Array.from(document.querySelectorAll('[id]')).map(e => e.id);
                document.body.dataset.idControl = String(ids.includes('control') && ids.includes('tbl-facts'));
                document.body.dataset.uniqueIds = String(new Set(ids).size === ids.length);
                const tables = document.querySelectorAll('table');
                const left = tables[3], right = tables[4];
                const scores = table => Array.from(table.tBodies[0].rows).map(r => r.cells[1].textContent).join(',');
                left.tHead.rows[0].cells[1].click();
                document.body.dataset.leftSort = String(scores(left) === '1,2' && scores(right) === '4,3');
                right.tHead.rows[0].cells[1].click();
                document.body.dataset.rightSort = String(scores(left) === '1,2' && scores(right) === '3,4');
                const blobs = [], names = [];
                URL.createObjectURL = blob => { blobs.push(blob); return 'blob:test'; };
                URL.revokeObjectURL = () => {};
                HTMLAnchorElement.prototype.click = function() { names.push(this.download); };
                left.closest('figure').querySelector('button').click();
                right.closest('figure').querySelector('button').click();
                const csv = await Promise.all(blobs.map(blob => blob.text()));
                document.body.dataset.csvLocal = String(csv[0] === 'Name,Score\na,1\nb,2' && csv[1] === 'Name,Score\nc,3\nd,4');
                document.body.dataset.csvNames = String(names.join(',') === 'table.csv,right.csv');
                document.body.dataset.done = '1';
            });
            """))
        page = "<!DOCTYPE html>" * repr("text/html", h.html(
            h.head(sortable_table_js(), download_table_js()),
            h.body(h.p("Address control"; id="control"),
                SemanticTable(facts), SemanticTable((; Item=["Name"], Result=["beta"])), SemanticTable(facts),
                render_table((; Name=["b", "a"], Score=[2, 1]); caption=CaptionSpec(; title="Left")),
                render_table((; Name=["d", "c"], Score=[4, 3]); caption=CaptionSpec(; title="Right"), download_filename="right.csv"),
                render_table(facts; id="tbl-facts", caption=CaptionSpec(; title="Addressed")), driver)))
        dom = mktempdir() do directory
            fixture = joinpath(directory, "tables.html")
            write(fixture, page)
            profile = joinpath(directory, "profile")
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --virtual-time-budget=2000 --dump-dom --user-data-dir=$profile file://$fixture`
            read(pipeline(cmd; stderr=devnull), String)
        end
        @test contains(dom, "data-done=\"1\"")
        for marker in ("id-control", "unique-ids", "left-sort", "right-sort", "csv-local", "csv-names")
            @test contains(dom, "data-$marker=\"true\"")
        end
    end
end
