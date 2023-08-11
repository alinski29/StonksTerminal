using Dates
using Test

using StonksTerminal.Types
using StonksTerminal: Config, config_read, config_write

include("test_utils.jl")

@testset "Configuration" begin
  cfg_dir = "/tmp/StonksTerminal"
  cfg_path = "$cfg_dir/config.json"
  cfg_test = load_testconfig()
  mkpath(cfg_dir)

  @testset "save" begin
    config_write(cfg_test, cfg_path)
    fs = stat(cfg_path)

    @test fs.size > 0
  end

  @testset "read" begin
    cfg = config_read(cfg_path)

    @test isa(cfg, Config)
    @test cfg.watchlist == cfg_test.watchlist
    @test cfg.currencies == cfg_test.currencies
  end

  rm(cfg_dir; recursive=true)
end
