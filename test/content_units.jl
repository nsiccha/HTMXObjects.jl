using TestItemRunner

# Content units: one identity, layers written separately, children at any depth,
# and one reader's view of them. The user's request and refinement (ODLPlaus GO
# 1qunouy, 04.11): each self-contained paragraph or other piece of information
# has an offer text, a short and a deep explanation, in place and recursive;
# layer selection and audience are separate; a public projection holds the offer
# text alone, its bytes free of everything else.

@testmodule UnitFixtures begin
    using HTMXObjects, HTTP
    import HTMXObjects: h, to_markdown_string
    export LAYERS, UNITS, DOC, SECRETS, PRIVATE_WORDS, UnitSiteApp, UnitHeadApp, md, html, plain, secrets_in, positions,
        bundle_bytes

    const LAYERS = [SemanticUnitLayer(:offer, "Angebot"; public=true, standalone=true),
                    SemanticUnitLayer(:short, "Kurzfassung"),
                    SemanticUnitLayer(:deep, "Vertiefung")]
    # A paragraph, an equation under it, a table, a unit with nothing public, and
    # one whose deep layer is code; nested below two groups and to depth four.
    const UNITS = [
        SemanticUnit("ap1"; title="AP 1: Faktoren", public_title="AP 1", children=[
            SemanticUnit("c2"; title="Prüfung der Faktoren",
                layers=(; offer="**Prüfung:** Die Faktoren stehen in [der Tabelle](#faktoren) und [intern](#intern).",
                        short="KURZ-C2: Die Prüfung unterscheidet Aufnahme und Verwendung.",
                        deep=["TIEF-C2: Die Unsicherheit bleibt gemeinsam, \$a^2\$.", SemanticCode(:julia, "tief_c2_code = 1")]),
                references=["faktoren", "intern" => "faktoren", "c2--deep"],
                meta=SemanticStatus(:warn; label="geplant", detail="META-C2"),
                children=[SemanticUnit("formel"; title="Die Formel",
                    layers=(; offer="\$\$\\bar f = \\frac{1}{n} \\sum_i f_i\$\$", short="KURZ-FORMEL: ungewichtet.", deep="TIEF-FORMEL: Gewichte später."),
                    children=[SemanticUnit("grenzen"; title="GRENZEN-TITEL",
                        layers=(; short="KURZ-GRENZEN: gleiche Geometrie.", deep="TIEF-GRENZEN: räumliche Unterstützung."))])]),
            SemanticUnit("faktoren"; title="Tabelle der Faktoren",
                layers=(; offer=SemanticTable((Quelle=["Boden", "Deposition"], Faktor=[1.02, 0.97])),
                        short="KURZ-TABELLE: zwei Quellen.", deep="TIEF-TABELLE: simuliert, siehe [die Prüfung](#c2--deep)."),
                references=["c2"]),
            SemanticUnit("intern"; title="INTERN-TITEL",
                layers=(; short="KURZ-INTERN: Metadaten fehlen.", deep="TIEF-INTERN: ausführlich."))]),
        SemanticUnit("ap2"; title="AP 2: Muster", children=[
            SemanticUnit("rechenkern"; title="Rechenkern",
                layers=(; offer="Der Rechenkern ist dokumentiert.", deep=SemanticCode(:julia, "tief_kern_code = 2")))])]
    const DOC = SemanticUnits(UNITS; layers=LAYERS, texts=unit_texts(:de))
    # Whatever a public reader must not get, in any format.
    const SECRETS = ["KURZ-", "TIEF-", "tief_c2_code", "tief_kern_code", "META-C2", "geplant", "INTERN-TITEL", "GRENZEN-TITEL",
                     "AP 1: Faktoren", "Prüfung der Faktoren", "Die Formel", "Kurzfassung", "Vertiefung", "Lesetiefe",
                     "\"intern\"", "#intern", "c2--short", "c2--deep", "formel--short", "grenzen", "htmxo-private"]
    const PRIVATE_WORDS = SECRETS
    secrets_in(s) = filter(w -> occursin(w, s), SECRETS)
    md(x; kw...) = to_markdown_string(x; kw...)
    html(x, audience) = with_audience(() -> repr("text/html", x), audience)
    plain(x, audience) = with_audience(() -> repr("text/plain", x), audience)
    # Where each string stands in the text, for checking an order.
    positions(s, words) = [something(findfirst(w, s), 0:0).start for w in words]

    @htmx struct UnitSiteApp
        __page__(content) = htmx(h.main(content); assets=:vendor, runtime=:linked,
            pico_version=HTMXObjects._PICO_VERSION)
        @get index() = h.div(h.h1("Bericht"), unit_tree(DOC), h.a("Kurz"; href="/unit_kurz"))
        @get unit_kurz() = h.div(h.h1("Kurz"), unit_tree(DOC; layer=:short))
    end
    bundle_bytes(dir) = Dict(relpath(joinpath(d, f), dir) => read(joinpath(d, f), String)
                             for (d, _, fs) in walkdir(dir) for f in fs)
end

@testitem "a unit document refuses what would hide a gap" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    L = LAYERS
    u(id; kw...) = SemanticUnit(id; title="T", layers=(; offer="o"), kw...)
    # A layer name and an id are addresses.
    @test_throws ArgumentError SemanticUnitLayer(:all, "x")
    @test_throws ArgumentError SemanticUnitLayer("a--b", "x")
    @test_throws ArgumentError SemanticUnitLayer("A b", "x")
    @test_throws ArgumentError SemanticUnit("a--b"; title="T")
    @test_throws ArgumentError SemanticUnit("a b"; title="T")
    @test_throws ArgumentError SemanticUnits([u("a")]; layers=SemanticUnitLayer[])
    @test_throws ArgumentError SemanticUnits([u("a")]; layers=[L[1], L[1]])
    # One id, one place, even when the second is deep below another unit.
    err = try SemanticUnits([u("a"), u("b"; children=[u("a")])]; layers=L); nothing catch e; e end
    @test err isa ArgumentError && occursin("\"a\"", err.msg) && occursin("twice", err.msg)
    # A layer the document does not declare.
    err = try SemanticUnits([SemanticUnit("a"; title="T", layers=(; tief="x"))]; layers=L); nothing catch e; e end
    @test err isa ArgumentError && occursin(":tief", err.msg) && occursin(":offer", err.msg)
    # A reference that names no unit, or a layer its unit lacks, cannot hide.
    err = try SemanticUnits([u("a"; references=["fehlt"])]; layers=L); nothing catch e; e end
    @test err isa ArgumentError && occursin("\"fehlt\"", err.msg)
    @test_throws ArgumentError SemanticUnits([u("a"; references=["a" => "fehlt"])]; layers=L)
    err = try SemanticUnits([u("a"; references=["b--deep"]), u("b")]; layers=L); nothing catch e; e end
    @test err isa ArgumentError && occursin(":deep", err.msg)
    # A unit with nothing to say, and one nothing would name.
    @test_throws ArgumentError SemanticUnits([SemanticUnit("a"; title="T")]; layers=L)
    err = try SemanticUnits([SemanticUnit("a"; layers=(; short="s"))]; layers=L); nothing catch e; e end
    @test err isa ArgumentError && occursin("title", err.msg)
    # `nothing` is an absent layer, and an absent optional part needs no branch.
    @test SemanticUnits([SemanticUnit("a"; layers=(; offer="o", short=nothing))]; layers=L) isa SemanticUnits
    # Asking for what is not in the document.
    @test_throws ArgumentError unit_tree(DOC, "fehlt")
    @test_throws ArgumentError unit_tree(DOC; layer=:fehlt)
    @test_throws ArgumentError unit_reference(DOC, "fehlt")
    @test_throws ArgumentError unit_reference(DOC, "c2"; fallback="fehlt")
    @test_throws ArgumentError unit_reference(DOC, "c2"; layer=:fehlt)
    @test_throws ArgumentError unit_ids(DOC, "fehlt")
    # A bare unit in a page would write every layer to every reader: it writes
    # nothing but an error, and its plain form names only its id.
    @test_throws ArgumentError repr("text/html", UNITS[1])
    @test_throws ArgumentError repr("text/markdown", DOC)
    @test string(UNITS[1]) == "SemanticUnit(\"ap1\")"
    @test !occursin("KURZ", string(DOC)) && !occursin("KURZ", repr(UNITS[1].children[1]))
end

@testitem "unit_ids names what a tree places, in document order" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    @test unit_ids(DOC) == ["ap1", "c2", "formel", "grenzen", "faktoren", "intern", "ap2", "rechenkern"]
    @test unit_ids(DOC, "c2") == ["c2", "formel", "grenzen"]
    @test unit_ids(DOC, "ap2", "formel") == ["ap2", "rechenkern", "formel", "grenzen"]
end

@testitem "a public reader gets the public layers and nothing else, in every format" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    tree = unit_tree(DOC)
    for (name, text) in (("html", html(tree, :public)), ("markdown", md(tree; audience=:public)), ("plain", plain(tree, :public)))
        @testset "$name" begin
            @test isempty(secrets_in(text))
            @test occursin("Prüfung:", text) && occursin("Der Rechenkern", text) && occursin("Deposition", text)
            # A group's heading in its public wording; content in document order.
            @test occursin("AP 1", text) && occursin("AP 2: Muster", text)
            p = positions(text, ["Prüfung:", "bar f", "Deposition", "Der Rechenkern"])
            @test all(>(0), p) && issorted(p)
        end
    end
    s = html(tree, :public)
    # Nothing to switch and nothing to open: one layer is all this reader has.
    @test !occursin("<details", s) && !occursin("<input", s) && !occursin("<fieldset", s)
    # An offer's approved wording gets nothing added: no title, no line of
    # references, no labels.
    @test !occursin("Siehe auch", s) && !occursin("Angebot", s) && !occursin("Tabelle der Faktoren", s)
    # A link in the wording to a unit this reader cannot reach keeps its words
    # and loses its address; a link to one they can reach stays.
    @test occursin("<a href=\"#faktoren\">der Tabelle</a>", s) && occursin(" und intern.", s)
    m = md(tree; audience=:public)
    @test occursin("[der Tabelle](#faktoren) und intern.", m)
    # The units' anchors reach the Markdown.
    @test occursin("## AP 1 {#ap1}", m) && occursin("::: {#c2}", m) && occursin("::: {#faktoren--offer}", m)
    # Asking a public reader for a private layer gives nothing, and no error.
    for layer in (:short, :deep)
        @test md(unit_tree(DOC; layer); audience=:public) == ""
        @test html(unit_tree(DOC; layer), :public) == ""
    end
    # A subtree with nothing public is nothing at all.
    @test md(unit_tree(DOC, "intern"); audience=:public) == ""
    @test md(unit_tree(DOC, "grenzen"); audience=:public) == ""
    # A group with nothing public below it goes whole, its heading and id too,
    # and so does a public reference to anything in it.
    quellen = SemanticUnits([
        SemanticUnit("text"; title="Text", layers=(; offer="Siehe [die Quelle](#quelle-a) und [alle](#quellen).", short="k")),
        SemanticUnit("quellen"; title="QUELLEN-TITEL", children=[
            SemanticUnit("quelle-a"; title="QUELLE-A", layers=(; short="ZITAT-KURZ", deep="ZITAT-TIEF"), meta="NOTIZ")])]; layers=LAYERS)
    for text in (md(unit_tree(quellen); audience=:public), html(unit_tree(quellen), :public), plain(unit_tree(quellen), :public))
        @test !occursin("QUELLEN-TITEL", text) && !occursin("quellen", text) && !occursin("quelle-a", text) &&
              !occursin("QUELLE-A", text) && !occursin("ZITAT", text) && !occursin("NOTIZ", text)
        @test occursin("Siehe die Quelle und alle.", replace(text, r"<[^>]*>" => ""))
    end
    @test md(unit_tree(quellen, "quellen"); audience=:public) == "" && html(unit_tree(quellen, "quellen"), :public) == ""
    @test md(unit_reference(quellen, "quelle-a"); audience=:public) == ""
    # The same group for a private reader, whole.
    @test occursin("QUELLEN-TITEL", md(unit_tree(quellen); audience=:private)) && occursin("NOTIZ", md(unit_tree(quellen); audience=:private))
    # Nothing in a public answer needs the guard against escaped private content.
    @test !occursin("<!--htmxo-private-->", s)
    # A layer is private unless it says otherwise.
    undeclared = SemanticUnits([SemanticUnit("a"; title="T", layers=(; x="GEHEIM"))]; layers=[SemanticUnitLayer(:x, "X")])
    @test md(unit_tree(undeclared); audience=:public) == ""
    @test md(unit_view_control(undeclared); audience=:public) == ""
end

@testitem "each layer reads alone, complete and in order" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    short = md(unit_tree(DOC; layer=:short); audience=:private)
    p = positions(short, ["{#ap1}", "{#c2}", "KURZ-C2", "{#formel}", "KURZ-FORMEL", "{#grenzen}",
                          "KURZ-GRENZEN", "{#faktoren}", "KURZ-TABELLE", "{#intern}", "KURZ-INTERN"])
    @test all(>(0), p) && issorted(p)
    # That layer only, and no labels or controls.
    @test !occursin("TIEF-", short) && !occursin("Prüfung:", short) && !occursin("bar f", short)
    @test !occursin("**Kurzfassung**", short) && !occursin("Unterpunkte", short)
    # A unit, and a group, without the layer are gone.
    @test !occursin("Rechenkern", short) && !occursin("AP 2", short)
    # The whole read is private, so it says so once.
    @test length(collect(eachmatch(r"\.htmxo-private", short))) == 1

    deep = md(unit_tree(DOC; layer=:deep); audience=:private)
    p = positions(deep, ["TIEF-C2", "tief_c2_code", "TIEF-FORMEL", "TIEF-GRENZEN", "TIEF-TABELLE", "TIEF-INTERN", "AP 2: Muster", "tief_kern_code"])
    @test all(>(0), p) && issorted(p)
    @test !occursin("KURZ-", deep)
    # In HTML nothing collapses and nothing asks to be opened.
    s = html(unit_tree(DOC; layer=:deep), :private)
    @test !occursin("<details", s) && !occursin("<input", s) && !occursin("htmxo-unit-link", s)

    # The public layer read alone by a private reader is what a public reader
    # gets: no marks, no title, no references.
    offer = md(unit_tree(DOC; layer=:offer); audience=:private)
    @test replace(offer, "AP 1: Faktoren" => "AP 1") == md(unit_tree(DOC; layer=:offer); audience=:public)
    @test !occursin("htmxo-private", offer) && !occursin("Siehe auch", offer)

    # Headings nest from where the tree is placed.
    nested = SemanticSection("Bericht", unit_tree(DOC; layer=:short))
    n = md(nested; audience=:private)
    @test occursin("## Bericht", n) && occursin("### AP 1: Faktoren {#ap1}", n) && occursin("#### Prüfung der Faktoren {#c2}", n)
    @test occursin("##### Die Formel {#formel}", n) && occursin("###### GRENZEN-TITEL {#grenzen}", n)
end

@testitem "every layer together: labelled, marked, and in place in a browser's markup" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    tree = unit_tree(DOC)
    m = md(tree; audience=:private, lang="de-DE")
    # Each layer under its label, in the declared order; a unit's parts together.
    p = positions(m, ["### Prüfung der Faktoren {#c2}", "**Angebot**", "Prüfung:", "**Kurzfassung**", "KURZ-C2", "**Vertiefung**", "TIEF-C2",
                      "Siehe auch", "Die Formel", "KURZ-FORMEL"])
    @test all(>(0), p) && issorted(p)
    @test occursin("::: {#c2--short}", m) && occursin("::: {#c2--deep}", m)
    # Valid strong emphasis: a closing `**` after a space would print its stars.
    @test occursin("**Siehe auch:** [Tabelle der Faktoren](#faktoren)", m)
    # What a public export leaves out says so, the public layer does not.
    @test occursin("nicht öffentlich", m)
    @test occursin(r"\*\*Kurzfassung\*\*\s+::: \{\.htmxo-private\}"s, m)
    @test !occursin(r"\*\*Angebot\*\*\s+::: \{\.htmxo-private\}"s, m)
    # The private reader's address keeps a link the public one loses.
    @test occursin("[intern](#intern)", m)
    # What only private readers see beside a unit.
    @test occursin("META-C2", m)

    s = html(tree, :private)
    # The first layer shown, the others closed under their labels with their
    # links, and each one its own address.
    @test occursin("<div class=\"htmxo-unit-layer\" id=\"c2--offer\" data-htmxo-unit-layer=\"offer\">", s)
    @test occursin("<details class=\"htmxo-unit-layer\" id=\"c2--short\" data-htmxo-unit-layer=\"short\"><summary>Kurzfassung<a href=\"#c2--short\"", s)
    @test occursin("<details class=\"htmxo-unit-layer\" id=\"c2--deep\"", s)
    # Children of a content unit sit closed; a group's are shown.
    @test occursin("<details class=\"htmxo-unit-children\"><summary>Unterpunkte (1)</summary>", s)
    @test occursin("<div class=\"htmxo-unit htmxo-unit-group\" data-htmxo-unit=\"ap1\">", s)
    # A unit with nothing public is marked as a whole, and once.
    block = s[findfirst("data-htmxo-unit=\"intern\"", s).start:end]
    @test occursin("INTERN-TITEL", block)
    # The layer switch: every layer, the choice of all, keys through radios.
    @test occursin("data-htmxo-unit-view=\"layer\"", s) && occursin("<legend>Lesetiefe</legend>", s)
    @test occursin("value=\"all\" checked=\"true\"", s) && occursin("value=\"short\"", s)
    @test length(collect(eachmatch(r"data-htmxo-unit-view", s))) == 1
    # It is a browser's alone.
    @test !occursin("Lesetiefe", m) && !occursin("Alle Ebenen", m) && !occursin("Unterpunkte", m)
    @test !occursin("Link zu dieser Stelle", m) && !occursin("Alle Ebenen", plain(tree, :private))
    # `control=false` leaves the switch to a page placing it once itself.
    @test !occursin("<fieldset", html(unit_tree(DOC; control=false), :private))
    @test occursin("data-htmxo-unit-view=\"ebene\"", html(unit_view_control(DOC; param="ebene"), :private))
    # `open=` decides, either way.
    L = LAYERS
    d = SemanticUnits([SemanticUnit("g"; title="G", open=false, children=[SemanticUnit("a"; title="A", open=true, layers=(; offer="o"),
        children=[SemanticUnit("b"; layers=(; offer="p"))])])]; layers=L)
    o = html(unit_tree(d), :private)
    @test occursin("<details class=\"htmxo-unit-children\"><summary>Subpoints (1)</summary><div class=\"htmxo-unit htmxo-unit-content\" id=\"a\" data-htmxo-unit=\"a\">", o)
    @test occursin("<div class=\"htmxo-unit-children\"><div class=\"htmxo-unit htmxo-unit-content\" id=\"b\"", o)
    # Another word for the words.
    @test unit_texts(:de; children="Mehr ({count})").children == "Mehr ({count})"
    @test_throws ArgumentError unit_texts(:de; references="Mehr {count}")
    @test_throws ArgumentError unit_texts(:fr)
    # A `title` a public reader must not read has public wording of its own.
    @test occursin("AP 1: Faktoren", s) && !occursin("AP 1: Faktoren", html(tree, :public))
end

@testitem "a layer can say what another says: once together, whole alone" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    # A generated table that short and deep explanations hang under, and a citation
    # the short layer repeats while the deep layer adds a note (ODLPlaus K5, 77 units).
    d = SemanticUnits([
        SemanticUnit("tabelle"; title="Tabelle K5", layers=(; offer=SemanticTable((Posten=["ROHZEILE"],)), short=:offer, deep=:offer),
            open=true, children=[SemanticUnit("erkl"; title="Erklärung", layers=(; short="KURZ-ERKL", deep="TIEF-ERKL"))]),
        SemanticUnit("quelle"; title="Quelle A", layers=(; offer="ZITAT", short=:offer, deep=["ZITAT", "NOTIZ"])),
        SemanticUnit("zeiger"; title="Zeiger", layers=(; short="[Tabelle](#tabelle--short)", deep="[Quelle](#quelle--deep)"), references=["tabelle--short"])]; layers=LAYERS)
    count_of(s, w) = length(collect(eachmatch(Regex(w), s)))
    # Together: once, and for a reader with one layer no label at all.
    m = md(unit_tree(d); audience=:private)
    @test count_of(m, "ROHZEILE") == 1 && count_of(m, "ZITAT") == 2
    @test occursin("**Angebot · Kurzfassung**", m) && occursin("**Vertiefung**", m)
    # All three share the table: one panel, one place, nothing to label.
    @test !occursin("Angebot · Kurzfassung · Vertiefung", m)
    h = html(unit_tree(d), :private)
    @test count_of(h, "ROHZEILE") == 1 && !occursin("id=\"tabelle--short\"", h)
    @test occursin("id=\"tabelle--offer\" data-htmxo-unit-layer=\"offer short deep\"", h)
    @test occursin("id=\"quelle--offer\" data-htmxo-unit-layer=\"offer short\"", h)
    # A panel shared with a public layer is not marked as private; the deep layer is.
    @test !occursin("id=\"tabelle--offer\" data-htmxo-unit-layer=\"offer short deep\"><div class=\"htmxo-private", h)
    # Alone: complete in each layer, with no mark on a table a public layer has too
    # beyond the one a private read carries.
    for (layer, words) in ((:offer, ["ROHZEILE", "ZITAT"]), (:short, ["ROHZEILE", "KURZ-ERKL", "ZITAT"]), (:deep, ["ROHZEILE", "TIEF-ERKL", "ZITAT", "NOTIZ"]))
        alone = md(unit_tree(d; layer); audience=:private)
        @test all(w -> occursin(w, alone), words)
        @test count_of(alone, "ROHZEILE") == 1
        layer === :offer || @test occursin("::: {#tabelle--$layer}", alone)
    end
    # A public reader: the public layer, and no other layer's name in the file.
    p = html(unit_tree(d), :public)
    @test occursin("data-htmxo-unit-layer=\"offer\"", p) && !occursin("short", p) && !occursin("deep", p)
    @test count_of(p, "ROHZEILE") == 1 && !occursin("NOTIZ", p) && !occursin("KURZ-ERKL", p)
    # A link to a sharing layer lands on the panel among all layers, on its own in one.
    @test occursin("[Tabelle](#tabelle--offer)", m) && occursin("#tabelle--short", md(unit_tree(d; layer=:short); audience=:private))
    @test occursin("Tabelle K5 (Angebot)", m)
    @test occursin("#tabelle--offer", html(unit_reference(d, "tabelle--short"), :private))
    @test occursin("#tabelle--short", html(unit_reference(d, "tabelle--short"; layer=:short), :private))
    # Naming nothing, or a layer that itself only names another, cannot hide.
    @test_throws ArgumentError SemanticUnits([SemanticUnit("a"; title="A", layers=(; short=:offer))]; layers=LAYERS)
    @test_throws ArgumentError SemanticUnits([SemanticUnit("a"; title="A", layers=(; offer=:short, short=:offer))]; layers=LAYERS)
    @test_throws ArgumentError SemanticUnits([SemanticUnit("a"; title="A", layers=(; offer="o", short=:offer, deep=:short))]; layers=LAYERS)
end

@testitem "a Markdown table sits in the scroll container every table has" tags=[:unit] begin
    using HTMXObjects
    s = repr("text/html", SemanticProse("| a |\n| --- |\n| 1 |"))
    @test occursin("<div class=\"table-wrap\"><table>", s) && occursin("</table></div>", s)
    # Its Markdown is the Markdown it was.
    @test repr("text/markdown", SemanticProse("| a |\n| --- |\n| 1 |")) == "| a |\n| --- |\n| 1 |"
end

@testitem "a heading or a prefix goes with what it is for" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    # A bibliography cited only by private layers, and a unit with a public layer.
    d = SemanticUnits([
        SemanticUnit("text"; title="Text", layers=(; offer="OFFENER-TEXT", short="k")),
        SemanticUnit("quelle"; title="Quelle", layers=(; short="ZITAT-KURZ", deep="ZITAT-TIEF")),
        SemanticUnit("nur-tief"; title="Nur tief", layers=(; deep="T"))]; layers=LAYERS)
    calls = Ref(0)
    heading(c) = (calls[] += 1; SemanticSection("Im Projekt", c))
    # A reader with something gets it, and `wrap` sees one node.
    seen = Ref{Any}(nothing)
    unit_tree(d, "quelle"; control=false, wrap=c -> (seen[] = c; c))
    @test !(seen[] isa AbstractVector)
    private_md = md(unit_tree(d, "quelle"; control=false, wrap=heading); audience=:private)
    @test occursin("## Im Projekt", private_md) && occursin("ZITAT-KURZ", private_md)
    # A public reader has nothing: no heading in any format.
    t = unit_tree(d, "quelle"; control=false, wrap=heading)
    @test md(t; audience=:public) == "" && html(t, :public) == "" && plain(t, :public) == ""
    # Called for the one branch that has anything.
    calls[] = 0
    unit_tree(d, "quelle"; control=false, wrap=heading)
    @test calls[] == 1
    calls[] = 0
    unit_tree(d, "text"; control=false, wrap=heading)
    @test calls[] == 2
    # One layer: the unit that has it keeps the heading, the one that lacks it does not.
    @test occursin("Im Projekt", md(unit_tree(d, "quelle"; control=false, layer=:deep, wrap=heading); audience=:private))
    @test md(unit_tree(d, "nur-tief"; control=false, layer=:short, wrap=heading); audience=:private) == ""
    # A public reader of a public unit gets it, marked for the layer switch.
    pub = html(unit_tree(d, "text"; control=false, wrap=heading), :public)
    @test occursin("Im Projekt", pub) && occursin("OFFENER-TEXT", pub) && occursin("data-htmxo-unit-wrap", pub)
    # Without `wrap` nothing changes.
    @test !occursin("data-htmxo-unit-wrap", html(unit_tree(d, "text"; control=false), :public))
    # A heading with other content keeps it, by being a section with that content.
    demo = SemanticSection("Mit Demo", SemanticProse("DEMO"), unit_tree(d, "quelle"; control=false))
    @test occursin("## Mit Demo", md(demo; audience=:public)) && occursin("DEMO", md(demo; audience=:public)) && !occursin("ZITAT", md(demo; audience=:public))

    # A line of references: the prefix goes with the last link.
    prefix(c) = h.p("Siehe: ", c)
    all_public = unit_references(d, ["text", "quelle", "text"]; wrap=prefix)
    pub_md = md(all_public; audience=:public)
    @test occursin("Siehe:", pub_md) && occursin("[Text](#text)", pub_md) && !occursin("Quelle", pub_md)
    # An address once, and every link for a private reader, by the separator.
    @test occursin("[Text](#text) · [Quelle](#quelle)", md(unit_references(d, ["text", "quelle", "text"]; separator=" · "); audience=:private))
    # None left: no links and no prefix, for the reader or the layer.
    none = unit_references(d, ["quelle", "nur-tief"]; wrap=prefix)
    @test md(none; audience=:public) == "" && html(none, :public) == "" && occursin("Siehe:", md(none; audience=:private))
    @test md(unit_references(d, ["nur-tief"]; layer=:short, wrap=prefix); audience=:private) == ""
    # A fallback for who cannot reach the target.
    fb = md(unit_references(d, ["quelle" => "text"]; wrap=prefix); audience=:public)
    @test occursin("[Text](#text)", fb) && !occursin("#quelle", fb)
    @test_throws ArgumentError unit_references(d, ["fehlt"])
    @test_throws ArgumentError unit_references(d, ["text" => "fehlt"])
    @test_throws ArgumentError unit_references(d, ["text"]; layer=:fehlt)
end

@testitem "a title with Markdown's marks is its text, and keeps its anchor" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    import HTMXObjects: h
    # As HTML shows them. An unmatched `*` runs Pandoc's emphasis over the line's
    # `{#id}`, which became text, and Typst refused every link to it (ODLPlaus,
    # `Luftkerma, H*(10) und Geräteanzeige`, 77 units on 42bb0b7).
    m(x) = repr("text/markdown", x)
    @test m(SemanticSection("H*(10) a"; anchor="x")) == "## H\\*(10) a {#x}"
    @test m(SemanticCard("H*(10)"; anchor="y")) == "### H\\*(10) {#y}"
    @test m(SemanticLink("H*(10)", "#x")) == "[H\\*(10)](#x)"
    @test startswith(m(SemanticDisclosure("H*(10)", "z")), "::: {.htmxo-label}\n**H\\*(10)**\n:::")
    # A `_` at a word's edge opens emphasis too; inside a word it means nothing.
    @test m(SemanticSection("_rand und snake_case_"; anchor="x")) == "## \\_rand und snake_case\\_ {#x}"
    # What is written as code stays code.
    @test m(SemanticLink("a*b", "#x"; code=true)) == "[`a*b`](#x)"
    # Without either mark the bytes are what they were.
    @test m(SemanticSection("Titel – mit [Klammern] & Zeichen"; anchor="x")) == "## Titel – mit [Klammern] & Zeichen {#x}"
    # HTML writes the text as it is.
    @test occursin("<h2>H*(10) a</h2>", repr("text/html", SemanticSection("H*(10) a")))
end

@testitem "a reference is a link, and only to what its reader can reach" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects
    link(r, a) = html(r, a)
    href(s) = (m = match(r"href=\"([^\"]*)\"", s); isnothing(m) ? nothing : m[1])
    text(s) = (m = match(r">([^<]*)</a>", s); isnothing(m) ? nothing : m[1])

    # Target, reader and view decide it. A unit in the view is its id.
    r = unit_reference(DOC, "c2")
    @test href(link(r, :public)) == "#c2" && href(link(r, :private)) == "#c2"
    @test text(link(r, :private)) == "Prüfung der Faktoren"
    # A layer is its own address where it shows, named with its label.
    r = unit_reference(DOC, "c2--short")
    @test href(link(r, :private)) == "#c2--short" && text(link(r, :private)) == "Prüfung der Faktoren (Kurzfassung)"
    # Where it does not show, the link comes down to the unit.
    @test href(link(r, :public)) == "#c2" && text(link(r, :public)) == "Prüfung der Faktoren"
    r = unit_reference(DOC, "c2--short"; layer=:offer)
    @test href(link(r, :private)) == "#c2"
    r = unit_reference(DOC, "c2--short"; layer=:short)
    @test href(link(r, :private)) == "#c2--short"
    # `layer` is the view: a unit it lacks has no target, a group whose
    # descendants have it does.
    @test href(link(unit_reference(DOC, "rechenkern"; layer=:short), :private)) === nothing
    @test href(link(unit_reference(DOC, "ap1"; layer=:short), :private)) == "#ap1"
    @test href(link(unit_reference(DOC, "ap2"; layer=:short), :private)) === nothing
    # A unit with nothing public: no address, no title, or its fallback.
    r = unit_reference(DOC, "intern")
    @test link(r, :public) == "" && href(link(r, :private)) == "#intern"
    r = unit_reference(DOC, "intern"; fallback="faktoren")
    @test href(link(r, :public)) == "#faktoren" && href(link(r, :private)) == "#intern"
    @test isempty(secrets_in(link(r, :public)))
    # A label is the caller's words.
    @test text(link(unit_reference(DOC, "c2"; label="dort"), :public)) == "dort"
    # A group's title follows its reader.
    @test text(link(unit_reference(DOC, "ap1"), :public)) == "AP 1" && text(link(unit_reference(DOC, "ap1"), :private)) == "AP 1: Faktoren"
    # All Markdown a PDF can resolve, and nothing for a reader without a target.
    @test md(unit_reference(DOC, "c2--deep"); audience=:private) == "[Prüfung der Faktoren (Vertiefung)](#c2--deep)"
    @test md(unit_reference(DOC, "intern"); audience=:public) == ""

    # A unit's own references follow the same rule.
    m = md(unit_tree(DOC); audience=:private)
    @test occursin("[Tabelle der Faktoren](#faktoren), [INTERN-TITEL](#intern), [Prüfung der Faktoren (Vertiefung)](#c2--deep)", m)
    # In a view without the target a reference goes, and one that came down to
    # the unit itself or a repeat of another says nothing.
    n = md(unit_tree(DOC; layer=:short); audience=:private)
    @test occursin("**Siehe auch:** [Tabelle der Faktoren](#faktoren), [INTERN-TITEL](#intern)", n)
    @test !occursin("c2--deep", n)
    # A fallback for a reader who cannot reach the target, on a public layer
    # that takes references.
    L = [SemanticUnitLayer(:o, "O"; public=true), SemanticUnitLayer(:p, "P")]
    d = SemanticUnits([SemanticUnit("a"; title="A", layers=(; o="o"), references=["b" => "c", "b", "c"]),
                       SemanticUnit("b"; title="B", layers=(; p="p")),
                       SemanticUnit("c"; title="C", layers=(; o="o"))]; layers=L)
    pub = md(unit_tree(d); audience=:public)
    @test length(collect(eachmatch(r"\[C\]\(#c\)", pub))) == 1 && !occursin("#b", pub) && !occursin("[B]", pub)
    # A link inside a deep layer's wording to a layer the view has not.
    alone = md(unit_tree(DOC; layer=:deep); audience=:private)
    @test occursin("siehe [die Prüfung](#c2--deep)", alone)
    short_only = SemanticUnits([SemanticUnit("x"; title="X", layers=(; short="[zur Tiefe](#y--deep)")),
                                SemanticUnit("y"; title="Y", layers=(; deep="d"))]; layers=LAYERS)
    t = md(unit_tree(short_only; layer=:short); audience=:private)
    @test occursin("zur Tiefe", t) && !occursin("#y", t)
    # A link to something that is no unit is the author's.
    other = SemanticUnits([SemanticUnit("x"; title="X", layers=(; offer="[oben](#seitenanfang)"))]; layers=LAYERS)
    @test occursin("[oben](#seitenanfang)", md(unit_tree(other); audience=:public))
end

@testitem "units keep their content's own rendering and their place in a route's answer" setup=[UnitFixtures] tags=[:unit] begin
    using HTMXObjects, HTTP
    import HTMXObjects: h
    route!(UnitSiteApp())
    body(r) = String(r.body)
    pub = dispatch(:GET, "/"; audience=:public)
    @test pub.status == 200 && isempty(secrets_in(body(pub)))
    # A table is a table and a formula a formula, for every reader.
    @test occursin("htmxo-semantic-table", body(pub)) && occursin("data-htmxo-math", body(pub))
    full = dispatch(:GET, "/"; audience=:private)
    @test occursin("language-julia", body(full)) && occursin("KURZ-C2", body(full))
    # `?plain` is the reader's whole view.
    plain_pub = body(dispatch(:GET, "/?plain"; audience=:public))
    @test isempty(secrets_in(plain_pub)) && occursin("Prüfung:", plain_pub) && !occursin("<details", plain_pub)
    plain_all = body(dispatch(:GET, "/?plain"; audience=:private))
    @test occursin("**Kurzfassung**", plain_all) && occursin("KURZ-C2", plain_all)
    @test !occursin("<input", plain_all) && !occursin("Alle Ebenen", plain_all)
    # One layer as a route of its own.
    @test occursin("KURZ-C2", body(dispatch(:GET, "/unit_kurz?plain"; audience=:private)))
    @test isempty(secrets_in(body(dispatch(:GET, "/unit_kurz?plain"; audience=:public))))
    # The runtime rides every page, and a page without units carries it inert.
    @test occursin("unit_script.js", body(full)) && occursin("unit_styles.css", body(full))
end

@testitem "export_site: a public bundle is free of private bytes, a private one needs no server" setup=[HTMXOTestImports, UnitFixtures] tags=[:unit] begin
    using Treebars
    route!(UnitSiteApp())
    vendorfiles()
    pub = joinpath(mktempdir(), "pub")
    export_site(pub; pages=["/"])
    bytes = bundle_bytes(pub)
    @test haskey(bytes, "index.html") && occursin("Der Rechenkern", bytes["index.html"])
    # Every file, the runtime and fragments included, not just the page. The
    # runtime names the layer switch's machinery, never a word of the content.
    for (file, text) in bytes
        endswith(file, ".js") || endswith(file, ".css") || @test isempty(secrets_in(text))
        for word in ("KURZ-", "TIEF-", "tief_c2_code", "META-C2", "INTERN-TITEL", "GRENZEN-TITEL", "Kurzfassung", "c2--short")
            @test !occursin(word, text)
        end
    end
    full = joinpath(mktempdir(), "full")
    export_site(full; pages=["/"], audience=:private)
    bytes = bundle_bytes(full)
    @test occursin("KURZ-C2", bytes["index.html"]) && occursin("TIEF-GRENZEN", bytes["index.html"])
    # One file holds every layer and asks nothing of a server: no address to
    # fetch for opening a layer, and the runtime carried along.
    @test !occursin(r"<details[^>]*hx-get", bytes["index.html"]) && any(endswith("unit_script.js"), keys(bytes))
    @test occursin("data-htmxo-unit-view", bytes["index.html"])
    @test occursin("KURZ-C2", bytes["unit_kurz.html"]) && !occursin("TIEF-C2", bytes["unit_kurz.html"])
    # In-page links stay in the page.
    @test occursin("href=\"#c2--short\"", bytes["index.html"])
    # Inline runtime: the export of a value holds the runtime in its own file.
    page = HTMXObjects.htmx(HTMXObjects.h.main(unit_tree(DOC)); assets=:vendor, runtime=:linked)
    inline = repr("text/html", static_transform(page, StaticExport(; audience=:private)))
    @test occursin("window.htmxoUnits", inline) && occursin("KURZ-C2", inline)
    public_inline = repr("text/html", static_transform(page, StaticExport()))
    @test occursin("window.htmxoUnits", public_inline) && !occursin("KURZ-C2", public_inline) && !occursin("c2--short", public_inline)
end

@testitem "pdf_report: public, one layer and every layer, each with its links" tags=[:quarto] setup=[UnitFixtures] begin
    if get(ENV, "HTMXO_QUARTO_TESTS", "") != "1" || isnothing(Sys.which("pdftotext"))
        @test_skip "Quarto and pdftotext (poppler-utils) write and read the text layer"
    else
        using HTMXObjects
        mktempdir() do dir
            build(x, name; kw...) = (path = joinpath(dir, name); @test pdf_report(x, path; title="Bericht", lang="de-DE", kw...) == path; path)
            text(path) = read(`pdftotext -enc UTF-8 $path -`, String)
            # Typst refuses a link to a label the document lacks, so every one of
            # these building is a check of the anchors and of what references keep.
            pub = text(build(unit_tree(DOC), "public.pdf"))
            @test occursin("Prüfung:", pub) && occursin("Deposition", pub) && occursin("Rechenkern ist", pub)
            for word in ("KURZ-", "TIEF-", "tief_c2_code", "META-C2", "INTERN-TITEL", "GRENZEN-TITEL", "Kurzfassung", "Vertiefung", "Siehe auch")
                @test !occursin(word, pub)
            end
            short = text(build(unit_tree(DOC; layer=:short), "short.pdf"; audience=:private))
            @test occursin("KURZ-C2", short) && occursin("KURZ-GRENZEN", short) && !occursin("TIEF-", short) && !occursin("Prüfung:", short)
            @test issorted(positions(short, ["KURZ-C2", "KURZ-FORMEL", "KURZ-GRENZEN", "KURZ-TABELLE", "KURZ-INTERN"]))
            deep = text(build(unit_tree(DOC; layer=:deep), "deep.pdf"; audience=:private))
            @test occursin("TIEF-C2", deep) && occursin("tief_kern_code", deep) && !occursin("KURZ-", deep)
            both = text(build(unit_tree(DOC), "all.pdf"; audience=:private))
            @test occursin("Kurzfassung", both) && occursin("KURZ-INTERN", both) && occursin("nicht öffentlich", both)
            # A title Pandoc would read as emphasis keeps its anchor: a link to it
            # resolves, in a view and in the document as a whole.
            marks = SemanticUnits([
                SemanticUnit("ziel"; title="Luftkerma, H*(10) und Anzeige", layers=(; deep="TIEF-ZIEL")),
                SemanticUnit("leser"; title="Leser", layers=(; deep="Siehe [dort](#ziel)."), references=["ziel"])]; layers=LAYERS)
            read_marks = text(build(unit_tree(marks; layer=:deep), "marks.pdf"; audience=:private))
            @test occursin("H*(10)", read_marks) && occursin("TIEF-ZIEL", read_marks) && !occursin("{#", read_marks)
            # An offer of its own, for a private reader too, has no mark.
            offer = text(build(unit_tree(DOC; layer=:offer), "offer.pdf"; audience=:private))
            @test !occursin("nicht öffentlich", offer) && occursin("Rechenkern ist", offer)
        end
    end
end

@testitem "units in a browser: direct links, keyboard, layers, history, static" setup=[HTMXOTestImports, TabsetBrowser, UnitFixtures] tags=[:browser] begin
    if get(ENV, "HTMXO_BROWSER_TESTS", "0") != "1"
        @test_skip false
    else
        using Sockets, Treebars
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), Some(nothing))
        isnothing(chrome) && error("HTMXO_BROWSER_TESTS=1 requires google-chrome or chromium")
        route!(UnitSiteApp())
        vendorfiles()
        shell(x; kw...) = htmx(h.main(; id="main")(h.h1("Bericht"), x, h.div(; style="height: 3000px")); assets=:vendor,
            feedback=false, compose=false, thread=false, treebars_assets=false, preload_version=nothing,
            pico_version=HTMXObjects._PICO_VERSION, kw...)
        rendered(x, audience) = with_audience(() -> repr("text/html", x), audience)
        side(p) = SemanticUnits([SemanticUnit("$p-eins"; title="$p eins", layers=(; offer="$p o", short="$p k", deep="$p t"))]; layers=LAYERS)
        later_doc = SemanticUnits([SemanticUnit("spaeter"; title="Später", layers=(; offer="o", deep="spät tief"))]; layers=LAYERS)
        pages = Dict(
            "/" => rendered(shell(unit_tree(DOC)), :private),
            "/public" => rendered(shell(unit_tree(DOC)), :public),
            "/export" => repr("text/html", static_transform(htmx(h.main(unit_tree(DOC)); assets=:vendor, runtime=:linked,
                pico_version=HTMXObjects._PICO_VERSION), StaticExport(; audience=:private))),
            "/frag" => rendered(shell(h.div(; id="spaet", hx_get="/fragment", hx_trigger="load")), :private),
            "/shared" => rendered(shell(unit_tree(SemanticUnits([SemanticUnit("geteilt"; title="Geteilt", layers=(; offer="ROH", short=:offer, deep=:offer),
                children=[SemanticUnit("kind"; title="Kind", layers=(; short="k", deep="t"))])]; layers=LAYERS))), :private),
            "/wide" => rendered(shell(h.div(; style="width: 400px")(unit_tree(SemanticUnits([SemanticUnit("breit"; title="Breit",
                layers=(; offer="o", short="| " * join(("Spalte$i" for i in 1:30), " | ") * " |\n|" * " --- |"^30 * "\n| " * join(("x$i" for i in 1:30), " | ") * " |"))]; layers=LAYERS)))), :private),
            "/wrapped" => (w = SemanticUnits([SemanticUnit("anderes"; title="Anderes", layers=(; offer="o", short="k")),
                                              SemanticUnit("nur-tief"; title="Nur tief", layers=(; deep="t"))]; layers=LAYERS);
                rendered(shell(h.div(unit_view_control(w), unit_tree(w, "anderes"; control=false),
                    unit_tree(w, "nur-tief"; control=false, wrap=c -> SemanticSection("Im Projekt", c)))), :private)),
            "/scopes" => rendered(shell(h.div(
                h.div(; data_htmxo_unit_scope="")(unit_view_control(side("a"); param="erste"), unit_tree(side("a"); control=false)),
                h.div(; data_htmxo_unit_scope="")(unit_view_control(side("b"); param="zweite"), unit_tree(side("b"); control=false)))), :private))
        fragment = rendered(unit_tree(later_doc; control=false), :private)
        bundle = joinpath(mktempdir(), "bundle")
        export_site(bundle; pages=["/"], audience=:private)
        socket = listen(Sockets.localhost, 0)
        port = Int(getsockname(socket)[2])
        close(socket)
        server = HTTP.serve!("127.0.0.1", port; verbose=false) do req
            path = HTTP.URI(req.target).path
            haskey(pages, path) && return HTTP.Response(200, ["Content-Type" => "text/html"], pages[path])
            path == "/favicon.ico" && return HTTP.Response(204)
            path == "/fragment" && return HTTP.Response(200, ["Content-Type" => "text/html"], fragment)
            # The bundle, as any static server has it: files and no application.
            if startswith(path, "/bundle/")
                file = joinpath(bundle, path[9:end])
                isfile(file) || return HTTP.Response(404)
                type = endswith(file, ".js") ? "text/javascript" : endswith(file, ".css") ? "text/css" : "text/html"
                return HTTP.Response(200, ["Content-Type" => type], read(file))
            end
            startswith(path, "/vendor/") && return dispatch(:GET, req.target; headers=collect(req.headers))
            HTTP.Response(404)
        end
        base = "http://127.0.0.1:$port"
        mktempdir() do profile
            cmd = `$chrome --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage --hide-scrollbars --window-size=1200,900 --remote-debugging-port=0 '--remote-allow-origins=*' --user-data-dir=$profile about:blank`
            process = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=false)
            try
                active = joinpath(profile, "DevToolsActivePort")
                @test timedwait(() -> isfile(active) && countlines(active) >= 2, 30; pollint=0.05) === :ok
                debug_port = strip(first(readlines(active)))
                targets = String(HTTP.get("http://127.0.0.1:$debug_port/json/list").body)
                target = match(r"\"webSocketDebuggerUrl\"\s*:\s*\"(ws://[^\"]*/page/[^\"]*)\"", targets)[1]
                HTTP.WebSockets.open(target; suppress_close_error=true) do ws
                    b = Browser(ws, Ref(0))
                    load(url) = begin
                        TabsetBrowser.call(b, "Page.navigate", "{\"url\":\"$url\"}")
                        sleep(0.1)
                        wait_for(b, "document.readyState === 'complete' && window.htmxoUnits")
                    end
                    opened(id) = evaluate(b, "String(document.getElementById('$id').open)")
                    seen(id) = evaluate(b, "(el => String(el.getClientRects().length > 0 && getComputedStyle(el).visibility === 'visible' && el.offsetHeight > 0))(document.getElementById('$id'))")
                    closed_around(id) = evaluate(b, "(() => { let n = 0; for (let d = document.getElementById('$id').parentElement; d; d = d.parentElement) if (d.tagName === 'DETAILS' && !d.open) n++; return String(n); })()")
                    in_view(id) = evaluate(b, "(r => String(r.top >= -1 && r.top < innerHeight))(document.getElementById('$id').getBoundingClientRect())")
                    address() = evaluate(b, "location.pathname + location.search + location.hash")
                    wait_seen(id) = wait_for(b, "(el => el && el.getClientRects().length > 0)(document.getElementById('$id'))")

                    for (name, page) in (("live", "$base/"), ("linked bundle", "$base/bundle/index.html"), ("inline export", "$base/export"))
                        @testset "$name" begin
                            # The first layer is what a reader starts with.
                            @test load(page)
                            @test seen("c2--offer") == "true" && opened("c2--short") == "false" && opened("c2--deep") == "false"
                            @test closed_around("formel") == "1"
                            # A direct link to a layer four levels down opens the chain, and lands.
                            @test load("$page#grenzen--deep")
                            @test wait_seen("grenzen--deep")
                            @test closed_around("grenzen--deep") == "0"
                            @test opened("grenzen--deep") == "true"
                            @test opened("grenzen--short") == "false"
                            @test wait_for(b, "(r => r.top >= -1 && r.top < innerHeight)(document.getElementById('grenzen--deep').getBoundingClientRect())")
                            # A reload keeps it.
                            TabsetBrowser.call(b, "Page.reload")
                            sleep(0.2)
                            @test wait_for(b, "document.readyState === 'complete' && window.htmxoUnits")
                            @test wait_seen("grenzen--deep")
                            @test closed_around("grenzen--deep") == "0"
                            # In-page links, then Back and Forward through them.
                            @test load(page)
                            evaluate(b, "document.querySelector('a[href=\"#faktoren\"]').click(); ''")
                            @test wait_for(b, "location.hash === '#faktoren'")
                            @test wait_seen("faktoren")
                            evaluate(b, "location.hash = '#formel--deep'; ''")
                            @test wait_for(b, "document.getElementById('formel--deep').getClientRects().length > 0")
                            @test closed_around("formel--deep") == "0"
                            evaluate(b, "document.querySelector('#c2 details.htmxo-unit-children').open = false; ''")
                            evaluate(b, "history.back(); ''")
                            @test wait_for(b, "location.hash === '#faktoren'")
                            evaluate(b, "history.forward(); ''")
                            @test wait_for(b, "location.hash === '#formel--deep'")
                            # Forward to a target the reader closed since opens it again.
                            @test wait_for(b, "document.querySelector('#c2 details.htmxo-unit-children').open")
                        end
                    end

                    # Keyboard: a real key on a summary opens in place and writes the
                    # address; closing writes the unit's.
                    @test load("$base/")
                    evaluate(b, "document.querySelector('#c2--short > summary').focus(); ''")
                    press(b, "Enter")
                    @test wait_for(b, "document.getElementById('c2--short').open")
                    @test address() == "/#c2--short"
                    press(b, " ")
                    @test wait_for(b, "!document.getElementById('c2--short').open")
                    @test address() == "/#c2"
                    # The address names what is open, and a reload has it.
                    press(b, "Enter")
                    @test wait_for(b, "document.getElementById('c2--short').open")
                    TabsetBrowser.call(b, "Page.reload")
                    sleep(0.2)
                    @test wait_for(b, "document.readyState === 'complete' && window.htmxoUnits")
                    @test wait_for(b, "document.getElementById('c2--short').open")
                    # Tab reaches a closed layer, then the link beside its label.
                    @test load("$base/")
                    evaluate(b, "document.querySelector('#c2--short > summary').focus(); ''")
                    press(b, "Tab")
                    @test evaluate(b, "document.activeElement.getAttribute('href')") == "#c2--short"

                    # The layer switch: the arrow keys choose; one layer alone, and all back.
                    @test load("$base/")
                    evaluate(b, "document.querySelector('[data-htmxo-unit-view] input[value=all]').focus(); ''")
                    press(b, "ArrowRight")
                    press(b, "ArrowRight")
                    @test wait_for(b, "window.htmxoUnits.view() === 'short'")
                    @test address() == "/?layer=short"
                    @test seen("c2--short") == "true" && seen("grenzen--short") == "true" && seen("intern--short") == "true"
                    @test seen("c2--offer") == "false" && seen("c2--deep") == "false"
                    @test seen("rechenkern") == "false" && seen("ap2") == "false"
                    TabsetBrowser.call(b, "Page.reload")
                    sleep(0.2)
                    @test wait_for(b, "document.readyState === 'complete' && window.htmxoUnits && window.htmxoUnits.view() === 'short'")
                    @test seen("grenzen--short") == "true" && evaluate(b, "document.querySelector('[data-htmxo-unit-view] input:checked').value") == "short"
                    # A link to what the chosen layer hides leaves that layer.
                    evaluate(b, "location.hash = '#c2--deep'; ''")
                    @test wait_for(b, "window.htmxoUnits.view() === null")
                    @test evaluate(b, "location.search") == "" && closed_around("c2--deep") == "0"
                    # Choosing all again closes only what the view opened.
                    @test load("$base/?layer=deep")
                    @test wait_for(b, "window.htmxoUnits.view() === 'deep'")
                    evaluate(b, "document.querySelector('[data-htmxo-unit-view] input[value=all]').click(); ''")
                    @test wait_for(b, "window.htmxoUnits.view() === null")
                    @test opened("c2--deep") == "false" && seen("c2--offer") == "true" && seen("rechenkern") == "true"
                    @test evaluate(b, "location.search") == ""
                    # An unknown layer in an address is the default view.
                    @test load("$base/?layer=nichts")
                    @test evaluate(b, "String(window.htmxoUnits.view())") == "null" && seen("c2--offer") == "true"

                    # Two documents side by side, each with a scope and a parameter
                    # of its own: choosing in one leaves the other, and a reload has both.
                    @test load("$base/scopes")
                    second = "document.querySelector('[data-htmxo-unit-view=zweite]')"
                    evaluate(b, "$second.querySelector('input[value=short]').click(); ''")
                    @test wait_for(b, "window.htmxoUnits.view(document.getElementById('b-eins')) === 'short'")
                    @test address() == "/scopes?zweite=short"
                    @test evaluate(b, "String(window.htmxoUnits.view(document.getElementById('a-eins')))") == "null"
                    @test seen("b-eins--short") == "true" && seen("b-eins--offer") == "false"
                    @test seen("a-eins--offer") == "true" && opened("a-eins--short") == "false"
                    @test evaluate(b, "document.querySelector('[data-htmxo-unit-view=erste] input:checked').value") == "all"
                    @test load("$base/scopes?zweite=short&erste=deep")
                    @test wait_for(b, "window.htmxoUnits.view(document.getElementById('a-eins')) === 'deep'")
                    @test seen("a-eins--deep") == "true" && seen("b-eins--short") == "true" && seen("a-eins--offer") == "false"
                    # A link to what one scope's layer hides clears that scope only.
                    evaluate(b, "location.hash = '#a-eins--offer'; ''")
                    @test wait_for(b, "window.htmxoUnits.view(document.getElementById('a-eins')) === null")
                    @test address() == "/scopes?zweite=short#a-eins--offer"
                    @test evaluate(b, "window.htmxoUnits.view(document.getElementById('b-eins'))") == "short"

                    # A panel several layers share: the layer view keeps it, and a link
                    # to a layer sharing it, which has no element of its own, lands there.
                    @test load("$base/shared?layer=short")
                    @test wait_for(b, "window.htmxoUnits.view() === 'short'")
                    @test seen("geteilt--offer") == "true"
                    @test load("$base/shared#geteilt--deep")
                    @test wait_for(b, "document.getElementById('geteilt--offer').getClientRects().length > 0")
                    @test closed_around("geteilt--offer") == "0" && closed_around("kind") == "1"
                    @test load("$base/shared#kind--deep")
                    @test wait_for(b, "document.getElementById('kind--deep').open")

                    # A wide Markdown table scrolls in its own box, inside a closed-off
                    # layer's border and the page; its text is all still there.
                    @test load("$base/wide#breit--short")
                    @test wait_for(b, "document.getElementById('breit--short').open")
                    @test evaluate(b, "(d => String(d.scrollWidth <= d.clientWidth))(document.getElementById('breit--short'))") == "true"
                    @test evaluate(b, "String(document.documentElement.scrollWidth <= innerWidth)") == "true"
                    @test evaluate(b, "(w => String(w.classList.contains('table-wrap') && w.scrollWidth > w.clientWidth))(document.querySelector('#breit--short table').parentElement)") == "true"

                    # A heading only for units with the deep layer: there among all
                    # layers, gone under a layer they lack, through a reload, and back.
                    @test load("$base/wrapped")
                    @test evaluate(b, "String(!!document.querySelector('[data-htmxo-unit-wrap] h2'))") == "true"
                    @test seen("nur-tief") == "true"
                    wrap_shown() = evaluate(b, "(w => String(w.getClientRects().length > 0))(document.querySelector('[data-htmxo-unit-wrap]'))")
                    @test wrap_shown() == "true"
                    evaluate(b, "document.querySelector('[data-htmxo-unit-view] input[value=short]').click(); ''")
                    @test wait_for(b, "window.htmxoUnits.view() === 'short'")
                    @test wrap_shown() == "false" && seen("anderes--short") == "true"
                    TabsetBrowser.call(b, "Page.reload")
                    sleep(0.2)
                    @test wait_for(b, "document.readyState === 'complete' && window.htmxoUnits && window.htmxoUnits.view() === 'short'")
                    @test wrap_shown() == "false"
                    evaluate(b, "document.querySelector('[data-htmxo-unit-view] input[value=deep]').click(); ''")
                    @test wait_for(b, "window.htmxoUnits.view() === 'deep'")
                    @test wrap_shown() == "true"
                    evaluate(b, "document.querySelector('[data-htmxo-unit-view] input[value=all]').click(); ''")
                    @test wait_for(b, "window.htmxoUnits.view() === null")
                    @test wrap_shown() == "true"

                    # The events a page uses to make way: before the lookup on the
                    # document, then on the target before anything opens.
                    @test load("$base/")
                    evaluate(b, """(() => {
                        window.seen = [];
                        const held = document.querySelector('[data-htmxo-unit=intern]');
                        const place = held.parentElement, after = held.nextSibling;
                        held.remove();
                        document.addEventListener('htmxo:unit-before-reveal', e => {
                            window.seen.push('before:' + e.detail.id + ':' + e.detail.layer + ':' + !!document.getElementById('intern--deep'));
                            if (e.detail.id === 'intern') place.insertBefore(held, after);
                        });
                        document.addEventListener('htmxo:unit-reveal', e => {
                            window.seen.push('reveal:' + e.detail.id + ':' + e.detail.layer + ':' + e.target.id + ':' + e.target.open);
                        });
                        return '';
                    })()""")
                    evaluate(b, "location.hash = '#intern--deep'; ''")
                    @test wait_for(b, "window.seen.length >= 2")
                    @test evaluate(b, "window.seen.join(',')") == "before:intern:deep:false,reveal:intern:deep:intern--deep:false"
                    @test wait_for(b, "document.getElementById('intern--deep').open")
                    @test evaluate(b, "typeof window.htmxoUnits.reveal") == "function"

                    # A swap that brings the address's target opens it.
                    @test load("$base/frag#spaeter--deep")
                    @test wait_for(b, "document.getElementById('spaeter--deep') && document.getElementById('spaeter--deep').open")

                    # A public page has nothing to open or switch and runs inert.
                    @test load("$base/public")
                    @test evaluate(b, "String(document.querySelectorAll('details, fieldset').length)") == "0"
                    @test seen("c2--offer") == "true"
                    @test load("$base/public#intern--deep")
                    @test evaluate(b, "String(document.getElementById('intern--deep'))") == "null"
                end
            finally
                kill(process)
                close(server)
            end
        end
    end
end
