module Portfolio

using Dates
using PrettyTables
using UnicodePlots
using StonksTerminal.Types
using StonksTerminal: Config, config_read, config_write
using StonksTerminal: collect_user_input, parse_string

include("portfolio/processing.jl")
include("portfolio/charts.jl")

deposit(; name::Union{String, Nothing}=nothing) = transfer_funds(; type=Deposit, name=name)

withdraw(; name::Union{String, Nothing}=nothing) = transfer_funds(; type=Withdrawal, name=name)

buy(; name::Union{String, Nothing}=nothing) = add_trade(Buy, name)

sell(; name::Union{String, Nothing}=nothing) = add_trade(Sell, name)

function status(;
  name::Union{String, Nothing}=nothing,
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
  days_delta::Int=360,
)
  cfg = config_read()
  port = get_portfolio(cfg, name)
  ds = get_portfolio_dataset(cfg, port)

  print_summary_table(ds)
end

function get_portfolio(config::Config, name::Union{String, Nothing}=nothing)::PortfolioInfo
  if length(keys(config.portfolios)) <= 1
    return config.portfolios[first(keys(config.portfolios))]
  end

  names = [p.name for p in config.portfolios]
  if name === nothing
    @info("Multiple portfolios: enter the name: $(join(names, ", "))")
    get_portfolio(config, parse_string(readline()))
  elseif !(name in keys(config.portfolios))
    @info("$name is not a valid portfolio name. Choose again between: $(join(names, ", "))")
    get_portfolio(config, nothing)
  else
    return config.portfolios[name]
  end
end

function add_trade(type::TradeType, name::Union{String, Nothing}=nothing)
  cfg = config_read()
  port = get_portfolio(cfg, name)

  date = collect_user_input("Enter date in format 'yyyy-mm-dd': ", Date)
  symbol = collect_user_input("Symbol (ticker): ", String)
  shares = collect_user_input("Number of shares: ", Float64)
  share_price = collect_user_input("Share price: ", Float64)
  commission = collect_user_input("Commission: ", Float64)
  currency = collect_user_input("Currency.", Currency)
  exchange_rate = (
    if currency != port.currency
      collect_user_input("Exchange rate: ", Float64)
    else
      nothing
    end
  )

  trade_type = type === Buy ? Buy : Sell
  trade = Trade(date, trade_type, symbol, shares, share_price, commission, currency, exchange_rate)
  new_trades = sort(vcat(port.trades, [trade]); by=x -> x.date)

  cfg.portfolios[port.name].trades = new_trades

  config_write(cfg)
end

function transfer_funds(; type::Union{TransferType, Nothing}=nothing, name::Union{String, Nothing}=nothing)
  config = config_read()
  port = get_portfolio(config, name)

  date = collect_user_input("Enter date in format 'yyyy-mm-dd': ", Date)
  transfer_type = isnothing(type) ? collect_user_input("Enter transfer type: ", TransferType) : type
  currency = collect_user_input("Portfolio currency.", Currency)
  proceeds = collect_user_input("Enter the transfer value (proceeds)", Float64)

  push!(port.transfers, Transfer(date, transfer_type, currency, proceeds))
  port.transfers = sort(port.transfers; by=x -> x.date)
  config.portfolios[port.name] = port

  config_write(config)
end

end
