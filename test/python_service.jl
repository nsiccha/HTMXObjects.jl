using TestItemRunner

# `python_service(T, dir; …)` writes a standalone FastAPI service for the JSON
# routes `openapi(T)` describes (todo `1g4u07e`, user decision `1iheds0`):
# pydantic models, one endpoint per operation, a `Backend` class with one
# method per operation, and the shipped document with a contract test.
@testmodule PythonServiceFixtures begin
    using HTMXObjects, Dates
    export PSAlarm, PSReport, PSNode, PSLevel, ps_low, ps_high, PSInner, PSApp,
           generate_service, service_python, run_python

    @enum PSLevel ps_low ps_high

    """
    One alarm of the rule.

    Raised when two neighbouring probes exceed the threshold in the same hour.
    """
    struct PSAlarm
        "Start hour (UTC)."
        start::DateTime
        probes::Vector{String}
        "Share of the rise that rain explains; a description long enough to be wrapped over more than one line of Python."
        rain_share::Union{Float64,Nothing}
    end

    "A day's report."
    struct PSReport
        day::Date
        level::PSLevel
        from::Int
        json::String
        alarms::Vector{PSAlarm}
        extra::Union{Nothing,@NamedTuple{note::String}}
        counts::Dict{String,Int}
        anything::Any
    end

    "A tree node."
    struct PSNode
        name::String
        children::Vector{PSNode}
    end

    const PS_ALARM = (start=DateTime(2026, 10, 24, 2), probes=["a", "b"], rain_share=nothing)

    @htmx struct PSInner
        """
        Alarms of one probe

        # Arguments
        - `kenn`: the probe's id
        - `k`: threshold multiple
        """
        @get alarms(kenn::String; k::Float64 = 3.0)::JSONResponse{Vector{PSAlarm}} =
            [merge(PS_ALARM, (; probes=[kenn], rain_share=k))]
        "The report of the day."
        @get index()::JSONResponse{PSReport} = (; day=Date(2026, 10, 24), level=ps_high, from=3,
            json="j", alarms=[PS_ALARM], extra=(; note="n"), counts=Dict("a" => 1),
            anything=[1, "x"])
    end

    @htmx struct PSApp
        "Status of the service."
        @get index() = MIMEResponse("application/json", "{\"ok\":true}")
        @get tree()::JSONResponse{PSNode} = PSNode("root", [PSNode("leaf", PSNode[])])
        "Save a note."
        @post note(; text::String = "", level::Int = 1)::JSONResponse{@NamedTuple{saved::Bool, level::Int}} =
            (; saved=true, level)
        @include inner = PSInner()
        @include openapi = OpenAPIRoutes(; root=PSApp, title="PS service", version="1.2.0")
        @include docs = SwaggerRoutes(; spec_url="/openapi")
    end

    generate_service(dir; kwargs...) = python_service(PSApp, dir; package="ps_service",
        copyright="2026 Test Holder", title="PS service", version="1.2.0", kwargs...)

    # A Python that has the generated service's dependencies: `HTMXO_TEST_PYTHON`
    # (an error when it lacks them, since it was chosen on purpose), else
    # `python3` when it has them, else `nothing`.
    function service_python()
        probe(py) = success(pipeline(`$py -c "import fastapi, pydantic, pytest, pycodestyle, httpx, python_multipart"`;
                                     stdout=devnull, stderr=devnull))
        chosen = get(ENV, "HTMXO_TEST_PYTHON", "")
        if !isempty(chosen)
            probe(chosen) || error("HTMXO_TEST_PYTHON=$chosen lacks fastapi, pydantic, pytest, pycodestyle, httpx or python-multipart")
            return chosen
        end
        py = Sys.which("python3")
        py !== nothing && probe(py) ? py : nothing
    end

    # Run `args` with `python` in `dir`; its output, and whether it succeeded.
    function run_python(python, dir, args...; env=Pair{String,String}[])
        out = IOBuffer()
        cmd = addenv(Cmd(`$python $args`; dir), "PYTHONPATH" => dir, "PYTHONDONTWRITEBYTECODE" => "1", env...)
        ok = success(pipeline(ignorestatus(cmd); stdout=out, stderr=out))
        (; ok, output=String(take!(out)))
    end
end

@testitem "python_service writes a FastAPI package from openapi(T)" setup=[PythonServiceFixtures] tags=[:unit] begin
    using HTMXObjects
    dir = mktempdir()
    written = generate_service(dir)
    relative = sort!([relpath(p, dir) for p in written])
    @test relative == sort!([".dockerignore", "Dockerfile", "LICENSE", "README.md", "pyproject.toml",
        joinpath("ps_service", "__init__.py"), joinpath("ps_service", "app.py"),
        joinpath("ps_service", "backend.py"), joinpath("ps_service", "models.py"),
        joinpath("ps_service", "openapi.json"), joinpath("tests", "test_contract.py")])
    read_file(path...) = read(joinpath(dir, path...), String)

    # Every Python file carries the license notice and the copyright line.
    for file in ("__init__.py", "app.py", "backend.py", "models.py")
        text = read_file("ps_service", file)
        @test startswith(text, "# SPDX-License-Identifier: GPL-3.0-or-later\n# Copyright (C) 2026 Test Holder\n")
        @test contains(text, "either version 3 of the License, or (at your option)")
    end
    @test startswith(read_file("LICENSE"), "                    GNU GENERAL PUBLIC LICENSE")
    @test contains(read_file("pyproject.toml"), "license = \"GPL-3.0-or-later\"")
    @test contains(read_file("pyproject.toml"), "\"python-multipart>=0.0.9\"")   # `note` takes a form
    # The image runs the installed package as an unprivileged user, so files
    # copied with the build host's modes (0600 under umask 077) stay readable.
    @test contains(read_file("Dockerfile"), "RUN chmod -R a+rX /tmp/service \\\n    && pip install --no-cache-dir /tmp/service")
    @test contains(read_file("Dockerfile"), "USER service\nWORKDIR /home/service\n")

    # The shipped document is the one `openapi` renders.
    @test read_file("ps_service", "openapi.json") ==
        HTMXObjects._schema_json_encode(openapi(PSApp; title="PS service", version="1.2.0")) * "\n"

    # Models: struct docstrings, field docstrings, nullable fields, enums as
    # literals, a NamedTuple type named after where it appears, wire names a
    # Python field cannot carry as aliases, and maps.
    models = read_file("ps_service", "models.py")
    @test contains(models, "class PSAlarm(BaseModel):\n    \"\"\"One alarm of the rule.\n")
    @test contains(models, "    start: datetime = Field(description=\"Start hour (UTC).\")\n")
    @test contains(models, "    rain_share: float | None = Field(\n        description=(\n")
    @test contains(models, "    level: Literal[\"ps_low\", \"ps_high\"]\n")
    @test contains(models, "    from_: int = Field(alias=\"from\")\n")
    @test contains(models, "    json_: str = Field(alias=\"json\")\n")
    @test contains(models, "    extra: PSReportExtra | None\n")
    @test contains(models, "    counts: dict[str, int]\n")
    @test contains(models, "    anything: Any\n")
    @test contains(models, "    children: list[PSNode]\n")
    @test contains(models, "class NoteResponse(BaseModel):\n    saved: bool\n    level: int\n")

    # Endpoints: the mounts' document and Swagger page are FastAPI's own, an
    # untyped route answers any JSON, parameters keep their place and
    # descriptions, and each calls its backend method.
    app = read_file("ps_service", "app.py")
    @test contains(app, "OPENAPI_URL = \"/openapi\"\nDOCS_URL = \"/docs\"\n")
    @test !contains(app, "operation_id=\"docs\"") && !contains(app, "operation_id=\"openapi\"")
    @test contains(app, "    def index() -> Any:\n        return backend.index()\n")
    @test contains(app, "        kenn: Annotated[str, Path(description=\"the probe's id\")],\n")
    @test contains(app, "        k: Annotated[float, Query(description=\"threshold multiple\")] = 3.0,\n")
    @test contains(app, "        level: Annotated[int, Form()] = 1,\n")
    @test contains(app, "    ) -> list[PSAlarm]:\n        return backend.alarms(kenn=kenn, k=k)\n")

    backend = read_file("ps_service", "backend.py")
    @test contains(backend, "ENVIRONMENT_VARIABLE = \"PS_SERVICE_BACKEND\"")
    @test contains(backend, "    def alarms(self, *, kenn: str, k: float = 3.0) -> list[PSAlarm]:\n")
    @test contains(backend, "        raise unimplemented(\"alarms\")\n")

    # No line of generated Python exceeds PEP 8's 79 characters.
    for file in ("app.py", "backend.py", "models.py")
        @test all(line -> length(line) <= 79, eachline(joinpath(dir, "ps_service", file)))
    end
    @test all(line -> length(line) <= 79, eachline(joinpath(dir, "tests", "test_contract.py")))
end

@testitem "python_service lays Python out within 79 columns" setup=[PythonServiceFixtures] tags=[:unit] begin
    using HTMXObjects
    H = HTMXObjects
    # Every field shape across name and description lengths around the
    # breaking points: one line, a broken call, a split string.
    words = ["µSv/h", "Tagesgang,", "Quantil", "(5-%)", "a", "Messstelle"]
    prose = join(words[mod1.(1:200, length(words))], " ")
    float_or_none = H._pyunion([H._pyname("float"), H._pyname("None")])
    too_long = String[]
    for name_length in 1:30, text_length in 20:140, required in (true, false), alias in (nothing, "a")
        field = H._PyField("f"^name_length, alias, float_or_none, required, first(prose, text_length))
        append!(too_long, filter(line -> length(line) > 79, H._py_field_lines(field)))
    end
    @test isempty(too_long)
    # A long docstring wraps; an unbreakable one becomes concatenated literals.
    for text in (repeat("word ", 60), "https://example.com/" * repeat("x", 120))
        @test all(line -> length(line) <= 79, H._py_docstring(text, 4))
    end
end

@testitem "python_service writes the license it is given and refuses bad arguments" setup=[PythonServiceFixtures] tags=[:unit] begin
    using HTMXObjects
    mit = mktempdir()
    generate_service(mit; license="MIT")
    @test startswith(read(joinpath(mit, "LICENSE"), String), "MIT License\n\nCopyright (c) 2026 Test Holder\n")
    @test contains(read(joinpath(mit, "ps_service", "app.py"), String), "# Licensed under the MIT License; see LICENSE.")
    only_v3 = mktempdir()
    generate_service(only_v3; license="GPL-3.0-only")
    header = read(joinpath(only_v3, "ps_service", "models.py"), String)
    @test contains(header, "# Software Foundation, version 3 of the License.\n")
    @test !contains(header, "any later version")

    @test_throws ArgumentError generate_service(mktempdir(); license="Apache-2.0")
    @test_throws ArgumentError python_service(PSApp, mktempdir(); package="PS-Service", copyright="2026 X")
    @test_throws ArgumentError python_service(PSApp, mktempdir(); package="import", copyright="2026 X")
    @test_throws ArgumentError python_service(PSApp, mktempdir(); package="ps", copyright=" ")
end

@testitem "a generated service passes pycodestyle and its contract test, and answers as the Julia routes do" setup=[PythonServiceFixtures] tags=[:unit] begin
    using HTMXObjects
    python = service_python()
    if python === nothing
        @test_skip "no Python with fastapi, pydantic, pytest, pycodestyle, httpx and python-multipart (set HTMXO_TEST_PYTHON)"
    else
        dir = mktempdir()
        generate_service(dir)
        style = run_python(python, dir, "-m", "pycodestyle", "ps_service", "tests")
        @test style.ok
        style.ok || println(style.output)
        contract = run_python(python, dir, "-m", "pytest", "-q", "-p", "no:cacheprovider", "tests")
        @test contract.ok
        contract.ok || println(contract.output)

        # The Julia routes' answers, which the Python service must give too
        # with a backend that computes the same values.
        route!(PSApp())
        requests = [
            ("GET", "/", ""), ("GET", "/tree", ""), ("GET", "/inner", ""),
            ("GET", "/inner/alarms/p1?k=2.5", ""), ("POST", "/note", "level=2&text=hi"),
        ]
        answers = Dict{String,String}()
        for (method, target, body) in requests
            headers = isempty(body) ? Pair{String,String}[] :
                ["Content-Type" => "application/x-www-form-urlencoded"]
            req = HTTP.Request(method, target, headers, Vector{UInt8}(body))
            response = first(HTTP.Handlers.gethandler(HTMXObjects.ROUTER, req))(req)
            @test response.status == 200
            answers[method * " " * target] = String(response.body)
        end
        write(joinpath(dir, "julia_answers.json"), HTMXObjects._schema_json_encode(answers))
        write(joinpath(dir, "fixture_backend.py"), """
            from ps_service.backend import Backend, CallerFault

            ALARM = {"start": "2026-10-24T02:00:00", "probes": ["a", "b"],
                     "rain_share": None}


            class FixtureBackend(Backend):
                def index(self):
                    return {"ok": True}

                def tree(self):
                    return {"name": "root",
                            "children": [{"name": "leaf", "children": []}]}

                def inner(self):
                    return {"day": "2026-10-24", "level": "ps_high", "from": 3,
                            "json": "j", "alarms": [ALARM],
                            "extra": {"note": "n"}, "counts": {"a": 1},
                            "anything": [1, "x"]}

                def alarms(self, *, kenn, k=3.0):
                    if kenn == "missing":
                        raise CallerFault(404, "no probe " + kenn)
                    return [{**ALARM, "probes": [kenn], "rain_share": k}]

                def note(self, *, level=1, text=""):
                    return {"saved": True, "level": level}
            """)
        write(joinpath(dir, "parity.py"), """
            import json
            import sys

            from fastapi.testclient import TestClient

            from ps_service.app import create_app
            from ps_service.backend import Backend

            failures = []
            client = TestClient(create_app())   # PS_SERVICE_BACKEND names it
            with open("julia_answers.json") as f:
                answers = json.load(f)
            for request, body in answers.items():
                method, target = request.split(" ", 1)
                if method == "POST":
                    form = dict(p.split("=") for p in "level=2&text=hi".split("&"))
                    response = client.post(target, data=form)
                else:
                    response = client.get(target)
                if response.status_code != 200 or response.json() != json.loads(body):
                    failures.append((request, response.status_code, response.text, body))

            missing = client.get("/inner/alarms/missing")
            if (missing.status_code, missing.json()) != (404, {"detail": "no probe missing"}):
                failures.append(("CallerFault", missing.status_code, missing.text))
            unconfigured = TestClient(create_app(Backend())).get("/tree")
            if unconfigured.status_code != 501 or "implement tree" not in unconfigured.json()["detail"]:
                failures.append(("501", unconfigured.status_code, unconfigured.text))

            for failure in failures:
                print(failure)
            sys.exit(1 if failures else 0)
            """)
        parity = run_python(python, dir, "parity.py";
                            env=["PS_SERVICE_BACKEND" => "fixture_backend:FixtureBackend"])
        @test parity.ok
        parity.ok || println(parity.output)
    end
end
