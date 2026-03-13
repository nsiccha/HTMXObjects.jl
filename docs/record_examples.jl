# Record each example app's HTML output into docs/public/examples/<name>/
# so VitePress can serve them as static pages.
#
# Run with: julia --project docs/record_examples.jl

using HTMXObjects

EXAMPLES_DIR = joinpath(dirname(@__DIR__), "examples")
OUTPUT_DIR   = joinpath(@__DIR__, "public", "examples")

# Clean previous recordings
isdir(OUTPUT_DIR) && rm(OUTPUT_DIR; recursive=true)

# Each example: (name, routes_to_visit)
EXAMPLES = [
    ("hello",   String[]),
    ("counter", ["/increment/0", "/increment/1", "/increment/2"]),
    ("blog",    ["/post/1", "/post/2", "/post/3"]),
    ("search",  String[]),
    ("tabs",    ["/tab/home", "/tab/about", "/tab/contact"]),
]

PORT = 18765

for (name, routes) in EXAMPLES
    println("Recording $name...")
    record_dir = joinpath(OUTPUT_DIR, name)
    file = joinpath(EXAMPLES_DIR, "$name.jl")

    # Launch example as a subprocess with record_dir via ARGS
    proc = open(`julia --project $(dirname(EXAMPLES_DIR)) -e """
        push!(ARGS, "record", "$record_dir", "$PORT")
        include("$file")
    """`, "r")

    # Wait for server to start
    sleep(4)

    # Hit index + extra routes
    base = "http://127.0.0.1:$PORT"
    try
        HTTP.get(base; retry=false, readtimeout=5)
        for route in routes
            HTTP.get(base * route; retry=false, readtimeout=5)
        end
    catch e
        @warn "Error recording $name" exception=e
    end

    # Kill the subprocess
    kill(proc)
    wait(proc)

    println("  → $record_dir")
end

println("\nDone! Recorded examples to $OUTPUT_DIR")
