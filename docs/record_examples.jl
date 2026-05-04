# Record each example app's output into docs/public/examples/<name>/.
# Uses HTMXObjects.record! to drive each route in-process — no subprocess,
# no port, no warmup. For each app and each route, writes:
#   <name>/<route>.html         full page (plain GET)
#   <name>/hx/<route>.html      body fragment (HX-Request: true)
#   <name>/md/<route>.md        markdown view (Accept: text/markdown)
#
# Run with: julia --project=docs docs/record_examples.jl
# Override the URL prefix via `RECORD_BASE_PREFIX`,
# default `/HTMXObjects.jl/dev/examples`.

using HTMXObjects

EXAMPLES_DIR = joinpath(dirname(@__DIR__), "examples")
OUTPUT_DIR   = joinpath(@__DIR__, "public", "examples")
BASE_PREFIX  = get(ENV, "RECORD_BASE_PREFIX", "/HTMXObjects.jl/dev/examples")

isdir(OUTPUT_DIR) && rm(OUTPUT_DIR; recursive=true)

# Each example file is a module exposing `App` (the @htmx struct) and
# `gallery_paths()` (the URL list to record).
for name in ("hello", "counter", "blog", "search", "tabs")
    println("Recording $name…")
    include(joinpath(EXAMPLES_DIR, "$name.jl"))
    mod = getproperty(@__MODULE__, Symbol(uppercasefirst(name)))
    record_dir  = joinpath(OUTPUT_DIR, name)
    record_base = BASE_PREFIX * "/" * name
    record!(mod.App(); record_dir, record_base, paths=mod.gallery_paths())
    println("  → $record_dir  (base=$record_base)")
end

println("\nDone! Recorded examples to $OUTPUT_DIR")
