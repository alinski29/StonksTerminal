using Dates
using Test
using StonksTerminal: Config, StoreConfig, config_write, config_read
using StonksTerminal: FileFormat, PortfolioInfo, arrow, enum_from_string
using StonksTerminal: Currency, USD, EUR
using StonksTerminal: Transfer, TransferType, Deposit, Withdrawal
using StonksTerminal: Trade, TradeType, Buy, Sell
using StonksTerminal: collect_user_input, parse_string

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

  rm(cfg_dir, recursive=true)

end
