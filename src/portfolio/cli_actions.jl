
using Comonicon
using Stonks
using StonksTerminal: Config, config_read, config_write
using StonksTerminal: TransferType, TradeType, Transfer, Trade, FinancialAsset, PortfolioInfo, Currency
using StonksTerminal: collect_user_input, parse_string, print_enum_values, enum_from_string

function add_trade(type::TradeType, name::Union{String,Nothing}=nothing)
  cfg = config_read()
  port = get_portfolio(cfg, name)

  @info("Enter date in format 'yyyy-mm-dd': ")
  date = Date(parse_string(readline()))
  # date = collect_user_input("Enter date in format 'yyyy-mm-dd': ", Date)

  symbol = collect_user_input("Symbol (ticker): ", String)

  # @info("Number of shares: ")
  # shares = tryparse(Int64, parse_string(readline()))
  shares = collect_user_input("Number of shares: ", Int64)

  @info("Share price: ")
  share_price = tryparse(Float64, parse_string(readline()))
  # share_price = collect_user_input("Share price: ", Float64)

  @info("Commission: ")
  commission = tryparse(Float64, parse_string(readline()))
  # commission = collect_user_input("Commission: ", Float64)

  # @info("Currency: Choose between: $(print_enum_values(Currency))")
  # currency = enum_from_string(parse_string(readline()), Currency)
  currency = collect_user_input("Currency: ", Currency)

  exchange_rate = (
    if currency != port.currency
      @info("Exchange rate to $(port.currency): ")
      # collect_user_input("Exchange rate: ", Float64)
      tryparse(Float64, parse_string(readline()))
    else
      nothing
    end
  )

  trade_type = type === Buy ? Buy : Sell
  trade = Trade(date, trade_type, symbol, shares, share_price, commission, currency, exchange_rate)
  new_trades = sort(vcat(port.trades, [trade]), by=x -> x.date)

  cfg.portfolios[port.name].trades = new_trades

  config_write(cfg)
end

function get_portfolio(config::Config, name::Union{String,Nothing}=nothing)::PortfolioInfo
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

function transfer_funds(; type::Union{TransferType,Nothing}=nothing, name::Union{String,Nothing}=nothing)
  config = config_read()
  port = get_portfolio(config, name)

  @info("Enter date in format 'yyyy-mm-dd': ")
  date = Date(parse_string(readline()))
  @info("Enter transfer type: $(print_enum_values(TransferType))")
  transfer_type = isnothing(type) ? enum_from_string(parse_string(readline()), TransferType) : type
  @info("Portfolio currency: Choose between: $(print_enum_values(Currency))")
  currency = enum_from_string(parse_string(readline()), Currency)
  @info("Enter the transfer value (proceeds)")
  proceeds = tryparse(Float64, parse_string(readline()))

  push!(port.transfers, Transfer(date, transfer_type, currency, proceeds))
  port.transfers = sort(port.transfers, by=x -> x.date)
  config.portfolios[name] = port

  config_write(config)
end