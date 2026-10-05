using TestItemRunner

@testitem "MultilineText arguments render textareas and arrive with LF line breaks" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    @htmx struct NoteOperations
        """
        Send note

        # Arguments
        - `note`: What looks wrong
        """
        @post send(; note::MultilineText) = string(nameof(typeof(note)), "|", note)
        "Draft note"
        @get draft(; body::MultilineText=MultilineText("a < b\nsecond")) = String(body)
        "Optional note"
        @get optional(; extra::MultilineText=HTMXObjects.MultilineText()) = "[$extra]"
        "Computed note"
        @get computed(; text::MultilineText=MultilineText(string("com", "puted"))) = String(text)
        "Rename"
        @post rename(; title::String) = title
    end
    @htmx struct NoteHost
        @include notes = NoteOperations()
    end

    app = NoteHost()
    html = repr("text/html", semantic_app(app))
    # The prose argument is a required textarea labelled from its `# Arguments` entry.
    @test contains(html, "What looks wrong")
    @test occursin(r"<textarea[^>]*name=\"note\"[^>]*required=\"true\"", html)
    @test !occursin(r"<input[^>]*name=\"note\"", html)
    # A default fills the textarea, escaped exactly once, and is not required.
    @test occursin(r"<textarea[^>]*name=\"body\"[^>]*>a &lt; b\nsecond</textarea>", html)
    @test !occursin(r"<textarea[^>]*name=\"body\"[^>]*required", html)
    # Defaults are reflected unevaluated: an empty constructor and a computed
    # default leave the textarea blank instead of showing their source text.
    @test occursin(r"<textarea[^>]*name=\"extra\"[^>]*></textarea>", html)
    @test occursin(r"<textarea[^>]*name=\"text\"[^>]*></textarea>", html)
    @test !contains(html, "MultilineText(")
    # An ordinary String keeps its single-line input.
    @test occursin(r"<input[^>]*name=\"title\"", html)
    @test !occursin(r"<textarea[^>]*name=\"title\"", html)

    for wire in ("a\r\nb\rc\nd", "a\nb\nc\nd")
        converted = HTMXObjects._convert_param(SubString(wire), MultilineText)
        @test converted isa MultilineText
        @test converted == "a\nb\nc\nd"
    end

    route!(app; operation_policy=:blocking)
    posted = dispatch(:POST, "/notes/send?plain=1";
        headers=["Content-Type" => "application/x-www-form-urlencoded"],
        body="note=" * HTTP.escapeuri("first line\r\nsecond <line>"))
    @test posted.status == 200
    @test String(posted.body) == "MultilineText|first line\nsecond <line>"
    defaulted = dispatch(:GET, "/notes/draft?plain=1")
    @test defaulted.status == 200
    @test String(defaulted.body) == "a < b\nsecond"
    blank = dispatch(:GET, "/notes/computed?plain=1&text=")
    @test blank.status == 200
    @test String(blank.body) == "computed"
    optional = dispatch(:GET, "/notes/optional?plain=1")
    @test optional.status == 200
    @test String(optional.body) == "[]"
    missing_note = dispatch(:POST, "/notes/send";
        headers=["Content-Type" => "application/x-www-form-urlencoded"], body="")
    @test missing_note.status == 400
end

@testitem "MultilineText fixed context renders one textarea and remakes the target" tags=[:unit, :semantic] begin
    using HTMXObjects, HTTP

    @htmx struct DraftOperations
        draft::MultilineText
        "Preview draft"
        @get preview() = string(nameof(typeof(draft)), "|", draft)
    end
    @htmx struct DraftHost
        @include drafts = DraftOperations(MultilineText("one\ntwo"))
    end

    app = DraftHost()
    html = repr("text/html", semantic_app(app))
    @test occursin(r"<textarea[^>]*name=\"draft\"[^>]*>one\ntwo</textarea>", html)
    @test !occursin(r"<input[^>]*name=\"draft\"", html)

    route!(app; operation_policy=:blocking)
    response = dispatch(:GET, "/drafts/preview?plain=1&draft=" * HTTP.escapeuri("x\r\ny"))
    @test response.status == 200
    @test String(response.body) == "MultilineText|x\ny"
    @test app.drafts.draft == "one\ntwo"
end

@testitem "MultilineText is a String-backed AbstractString" tags=[:unit] begin
    using HTMXObjects

    text = MultilineText(SubString("héllo\nwörld", 1))
    @test String(text) === text.value
    @test text == "héllo\nwörld"
    @test hash(text) == hash("héllo\nwörld")
    @test length(text) == 11
    @test collect(text) == collect("héllo\nwörld")
    @test split(text, '\n') == ["héllo", "wörld"]
    @test "[$text]" == "[héllo\nwörld]"
    @test convert(MultilineText, "x") isa MultilineText
    @test MultilineText(text) == text
    @test MultilineText() == ""
    @test HTMXObjects._openapi_type_schema(MultilineText) == (type="string",)
end
