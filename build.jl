using Pkg
using UUIDs

suffix = first(split(string(UUIDs.uuid4()), "-"))
PROJECT_DIR = pwd()
BUILD_DIR = joinpath(pwd(), "build_$suffix")
TARGET_DIR = joinpath(PROJECT_DIR, "target/")

isdir(BUILD_DIR) && rm(BUILD_DIR; recursive=true)
mkdir(BUILD_DIR)

foreach(["Project.toml"]) do file
  cp(joinpath(PROJECT_DIR, file), joinpath(BUILD_DIR, file))
end

foreach(["src", "test"]) do dir
  Base.cptree(joinpath(PROJECT_DIR, dir), joinpath(BUILD_DIR, dir))
end

cd(BUILD_DIR)

Pkg.activate(".")
Pkg.instantiate()
Pkg.add("PackageCompiler")

using PackageCompiler

isdir(TARGET_DIR) && rm(TARGET_DIR; recursive=true)

create_app(
  ".",
  TARGET_DIR,
  incremental=false,
  force=true,
  executables= ["stonks" => "julia_main"],
  precompile_execution_file="test/runtests.jl",
  sysimage_build_args=`-O3 --strip-metadata`
)

cd(PROJECT_DIR)
rm(BUILD_DIR; recursive=true)
