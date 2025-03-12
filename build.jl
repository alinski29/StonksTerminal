using Pkg
using UUIDs

suffix = first(split(string(UUIDs.uuid4()), "-"))
project_dir = pwd()
build_dir = joinpath(pwd(), "build_$suffix")
target_dir = joinpath(project_dir, "target/")

isdir(build_dir) && rm(build_dir; recursive=true)
mkdir(build_dir)

foreach(["Manifest.toml", "Project.toml"]) do file
  cp(joinpath(project_dir, file), joinpath(build_dir, file))
end

foreach(["src", "test"]) do dir
  Base.cptree(joinpath(project_dir, dir), joinpath(build_dir, dir))
end

cd(build_dir)

Pkg.activate(".")
Pkg.instantiate()
Pkg.add("PackageCompiler")

using PackageCompiler

isdir(target_dir) && rm(target_dir; recursive=true)

create_app(
  ".",
  target_dir,
  incremental=false,
  force=true,
  executables= ["stonks" => "julia_main"],
  precompile_execution_file="test/runtests.jl",
  sysimage_build_args=`-O3 --strip-metadata`
)

cd(project_dir)
rm(build_dir; recursive=true)
