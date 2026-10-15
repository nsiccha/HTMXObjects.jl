# Make the active environment able to run `Pkg.test` from a clean checkout:
#
#     julia --project=. test/provision.jl
#
# (`test/select.jl` runs this before forwarding its arguments to `Pkg.test`.)
#
# General cannot supply part of the dependency closure: HTMX and Treebars are
# unregistered, and General's DynamicObjects stops below the `[compat]` bound.
# `Manifest.toml` is gitignored, so a fresh checkout's `Pkg.test()` stops at
# instantiate with `expected package HTMX [27f3e1ef] to be registered`, and
# Julia 1.10 ignores `[sources]` altogether.
#
# This adds each such package that the manifest does not already provide,
# tracked by git URL, in one batched `Pkg.add`: the url/rev of its `[sources]`
# entry, otherwise the one in `UNREGISTERED`. Entries the manifest already has
# (a developed local checkout, say) are kept, except a git-tracked one whose
# url/rev differs from its `[sources]` entry: an earlier provision of an older
# pin, re-added so that bumping the pin reaches an existing checkout. `Pkg.add` rewrites
# `Project.toml` (Julia 1.10, for one, moves the weak/test dependency Treebars
# into `[deps]`), so the file is restored byte for byte; the manifest keeps the
# added packages, which is what `Pkg.test` instantiates from.
using Pkg

# Git sources for the packages that `[sources]` does not name.
const UNREGISTERED = Dict(
    "DynamicObjects" => Dict("url" => "https://github.com/nsiccha/DynamicObjects.jl", "rev" => "pre-inference"),
    "HTMX" => Dict("url" => "https://github.com/nsiccha/HTMX.jl", "rev" => "dev"),
)

function provision_unregistered!(project_file=Base.active_project())
    project_bytes = read(project_file)
    project = Pkg.TOML.parsefile(project_file)
    uuids = merge(get(project, "extras", Dict()), get(project, "weakdeps", Dict()), project["deps"])
    git_sources = filter(s -> haskey(s.second, "url"), get(project, "sources", Dict()))
    manifest_file = Base.project_file_manifest_path(project_file)
    manifest = manifest_file === nothing ? Dict() : Pkg.TOML.parsefile(manifest_file)
    manifest_entries = Dict(Base.UUID(entry["uuid"]) => entry for entries in values(get(manifest, "deps", Dict())) for entry in entries)
    function provided(name, source)
        entry = get(manifest_entries, Base.UUID(uuids[name]), nothing)
        entry === nothing && return false
        haskey(git_sources, name) && haskey(entry, "repo-url") || return true
        (entry["repo-url"], get(entry, "repo-rev", nothing)) == (source["url"], get(source, "rev", nothing))
    end
    specs = [
        PackageSpec(; name, uuid=Base.UUID(uuids[name]), url=source["url"], rev=get(source, "rev", nothing))
        for (name, source) in sort!(collect(merge(UNREGISTERED, git_sources)); by=first) if !provided(name, source)
    ]
    isempty(specs) && return specs
    # Precompiling against the rewritten `Project.toml` fails the extensions;
    # `Pkg.test` precompiles once the file is restored.
    restore() = read(project_file) == project_bytes || write(project_file, project_bytes)
    withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
        try
            Pkg.add(specs)
            restore()
            # Records the restored `Project.toml` in the manifest, so Julia 1.10
            # does not warn that the project changed since the last resolve.
            Pkg.resolve()
        finally
            restore()
        end
    end
    specs
end

provision_unregistered!()
