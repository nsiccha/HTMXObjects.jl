# Record each example app's HTML output into docs/public/examples/<name>/
# so VitePress can serve them as static pages. Each route is hit twice
# per app: once plain (records under <name>/<route>.html as the full
# page) and once with `HX-Request: true` (records under
# <name>/hx/<route>.html as a body fragment). All `hx-get` URLs in
# either shape are rewritten by `static_transform` to point into the
# `hx/` subtree under `record_base`, so the recordings work both as a
# standalone-host entry (full page) and as VitePress-embed targets
# (fragments).
#
# Run with: julia --project docs/record_examples.jl
# Override the URL prefix the recordings will be served under via
# `RECORD_BASE_PREFIX`, defaults to `/HTMXObjects.jl/dev/examples`.

using HTMXObjects

EXAMPLES_DIR = joinpath(dirname(@__DIR__), "examples")
OUTPUT_DIR   = joinpath(@__DIR__, "public", "examples")

# Clean previous recordings
isdir(OUTPUT_DIR) && rm(OUTPUT_DIR; recursive=true)

# Each example: (name, routes_to_visit). The index ("/") is always hit;
# `routes` lists additional sub-routes that should be recorded.
EXAMPLES = [
    ("hello",   String[]),
    ("counter", ["/increment/0", "/increment/1", "/increment/2"]),
    ("blog",    ["/post/1", "/post/2", "/post/3"]),
    ("search",  String[]),
    ("tabs",    ["/tab/home", "/tab/about", "/tab/contact"]),
]

PORT = 18765
BASE_PREFIX = get(ENV, "RECORD_BASE_PREFIX", "/HTMXObjects.jl/dev/examples")

for (name, routes) in EXAMPLES
    println("Recording $name...")
    record_dir  = joinpath(OUTPUT_DIR, name)
    record_base = BASE_PREFIX * "/" * name
    file        = joinpath(EXAMPLES_DIR, "$name.jl")

    # Launch example as a subprocess with record_dir + record_base via ARGS
    proc = open(`julia --project $(dirname(EXAMPLES_DIR)) -e """
        push!(ARGS, "record", "$record_dir", "$PORT", "$record_base")
        include("$file")
    """`, "r")

    # Wait for server to start
    sleep(4)

    # Hit each route twice: plain (full page recording) and with
    # `HX-Request: true` (fragment recording).
    base = "http://127.0.0.1:$PORT"
    hx_headers = ["HX-Request" => "true"]
    try
        HTTP.get(base; retry=false, readtimeout=5)
        HTTP.get(base; retry=false, readtimeout=5, headers=hx_headers)
        for route in routes
            HTTP.get(base * route; retry=false, readtimeout=5)
            HTTP.get(base * route; retry=false, readtimeout=5, headers=hx_headers)
        end
    catch e
        @warn "Error recording $name" exception=e
    end

    # Kill the subprocess
    kill(proc)
    wait(proc)

    println("  → $record_dir  (base=$record_base)")
end

println("\nDone! Recorded examples to $OUTPUT_DIR")
