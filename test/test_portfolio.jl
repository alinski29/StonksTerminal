using Dates
using Stonks
using Test

using StonksTerminal: Config, config_read, config_write
using StonksTerminal.Types
using StonksTerminal: Store
using StonksTerminal.Portfolio
using StonksTerminal: convert_to_monthly, compute_correlation_matrix, ffill, print_correlation_matrix

include("test_utils.jl")

@testset "Store" begin
  config = load_testconfig()
  port = config.portfolios["test"]
  stores = Store.load_stores(config.data.dir, csv)

  prices = fake_stock_data(366, Date(2023, 12, 31), [t.symbol for t in port.trades])
  info = test_info_data()
  save(stores[:price], prices)
  save(stores[:info], info)

  ds = Portfolio.get_portfolio_dataset(config, port)

  @testset "Portfolio dataset" begin
    @test setdiff(Set(keys(ds.members)), Set(x.symbol for x in info)) == Set()
    @test names(ds.close)[2] == [x.symbol for x in info]
  end

  @testset "Correlation matrix" begin
    monthly = convert_to_monthly(ds.close)
    mat = compute_correlation_matrix(ffill(monthly))
    @test size(mat) == (length(ds.members), length(ds.members))
    @test print_correlation_matrix(mat; empty_diagonal=false) === nothing
    @test all(map(i -> mat[i, i] == 1.0, range(1, length(ds.members))))
  end

  @testset "Portfolio summary" begin
    @test Portfolio.status(config; name=port.name) === nothing
    @test Portfolio.plot_returns(ds) !== nothing
  end

  rm(config.data.dir; recursive=true)
end