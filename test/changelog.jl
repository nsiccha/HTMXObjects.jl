using TestItemRunner

# A landing that adds public API bumps the patch version and adds its entry
# under a new heading at the top of CHANGELOG.md (user decision 068fwg0), so a
# dependant can state that version as its [compat] floor. Two landings that
# bump at once then collide on that heading, never on a shared number.
@testitem "CHANGELOG.md's newest version is Project.toml's version" tags=[:unit] begin
    import TOML
    root = pkgdir(HTMXObjects)
    version = VersionNumber(TOML.parsefile(joinpath(root, "Project.toml"))["version"])
    changelog = read(joinpath(root, "CHANGELOG.md"), String)
    headings = [VersionNumber(m[1]) for m in eachmatch(r"^## (\d+\.\d+\.\d+)[ \t]*$"m, changelog)]
    @test !isempty(headings)
    @test first(headings) == version
    @test allunique(headings)
    @test issorted(headings; rev=true)
end
