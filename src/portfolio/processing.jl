using Dates
using NamedArrays
using Stonks
using Stonks: load, AssetPrice, AssetInfo

using StonksTerminal: Config, config_read, config_write
using StonksTerminal: allocate_matrix, expand_matrix, ffill, fill_missing
using StonksTerminal: load_prices, load_forex, get_latest_exchange_rate, compute_return, map_dates_to_indices
using StonksTerminal.Store
using StonksTerminal.Types

function get_returns(
  p::PortfolioDataset;
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Float64}
  compute_return(p.close; from=from, to=to)
end

function get_market_value(
  p::PortfolioDataset;
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Float64}
  slice = map_dates_to_indices(p.close, from, to)
  net_shares = cumsum(p.shares_bought .- p.shares_sold; dims=1)[slice, :]

  return p.close[slice, :] .* net_shares
end

function get_realized_profit(
  p::PortfolioDataset;
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Float64}
  slice = map_dates_to_indices(p.close, from, to)
  has_sale = map(x -> Int8(x > 0), p.shares_sold[slice, :])
  price_diff = p.shares_sold_price[slice, :] .- (p.avg_price[slice, :] .* has_sale)
  net_profit = p.shares_sold[slice, :] .* price_diff

  return cumsum(net_profit; dims=1)
end

function get_capital_gains(
  p::PortfolioDataset;
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Float64}
  slice = map_dates_to_indices(p.close, from, to)
  net_shares = cumsum(p.shares_bought .- p.shares_sold; dims=1)[slice, :]

  # TODO - This needs to be computed from returns
  return net_shares .* (p.close[slice, :] .- p.avg_price[slice, :])
end

function get_weights(
  p::PortfolioDataset;
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Float64}
  market_value = get_market_value(p; from=from, to=to)
  port_daily_value = sum(market_value; dims=2)

  return market_value ./ port_daily_value |> mat -> map(x -> isnan(x) || isinf(x) ? 0.0 : x, mat)
end

function get_portfolio_members(port::PortfolioInfo)::Dict{String, PortfolioMember}
  cfg = config_read()
  trades = port.trades |> trs -> sort(trs; by=x -> x.symbol)
  symbols = unique(map(x -> x.symbol, trades))
  stores = Store.load_stores(cfg.data.dir, arrow)
  infos = Dict([(x.symbol, x) for x in Stonks.load(stores[:info])])
  return Dict([
    smb => PortfolioMember(get(infos, smb, missing), [t for t in trades if t.symbol == smb]) for
    smb in symbols
  ])
end

function get_adjusted_price(trade::Trade)::Float64
  price_comission = abs(trade.commission / trade.shares)
  price_penalty = trade.type == Buy ? abs(price_comission) : -abs(price_comission)
  return trade.share_price + price_penalty
end

function get_portfolio_trade_info(port::PortfolioInfo, exchange_rates::Dict{Tuple{Date, String}, Float64})
  trades    = port.trades
  transfers = port.transfers
  symbols   = sort(unique(map(x -> x.symbol, trades)))
  dates     = vcat(map(x -> x.date, trades), map(x -> x.date, transfers)) |> unique |> sort
  dates_raw = map(d -> Dates.format(d, "yyyy-mm-dd"), dates)

  shares_bought_mat       = allocate_matrix(Float64, dates_raw, symbols) # net shares
  shares_sold_mat         = allocate_matrix(Float64, dates_raw, symbols) # net shares
  shares_bought_price_mat = allocate_matrix(Float64, dates_raw, symbols) # aquisition cost?
  shares_sold_price_mat   = allocate_matrix(Float64, dates_raw, symbols)
  commissions_mat         = allocate_matrix(Float64, dates_raw, symbols)
  avg_price_mat           = allocate_matrix(Union{Float64, Missing}, dates_raw, symbols)
  transfers_mat           = allocate_matrix(Float64, dates_raw, ["CASH"])

  for transfer in sort(port.transfers; by=x -> x.date)
    transfer_value = transfer.type == Deposit ? abs(transfer.proceeds) : -abs(transfer.proceeds)
    if transfer.currency != port.currency
      transfer_value *= get_latest_exchange_rate(exchange_rates, uppercase(string(transfer.currency)))
    end
    transfers_mat[Dates.format(transfer.date, "yyyy-mm-dd"), "CASH"] += transfer_value
  end

  for symbol in symbols
    this_trades = filter(x -> x.symbol == symbol, trades) |> xs -> sort(xs; by=x -> (x.date, x.type))
    if isempty(this_trades)
      continue
    end

    avg_prices = []
    for (i, trade) in enumerate(this_trades)
      date_raw = Dates.format(trade.date, "yyyy-mm-dd")
      commissions_mat[date_raw, symbol] += abs(trade.commission)

      if trade.type == Buy
        shares_bought_mat[date_raw, trade.symbol] += abs(trade.shares)
        shares_bought_price_mat[date_raw, trade.symbol] +=
          abs(trade.share_price) - abs(trade.commission / trade.shares)
      elseif trade.type == Sell
        shares_sold_mat[date_raw, trade.symbol] += abs(trade.shares)
        shares_sold_price_mat[date_raw, trade.symbol] +=
          abs(trade.share_price) - abs(trade.commission / trade.shares)
      end

      if i == 1
        last_avg_price = get_adjusted_price(trade)
        push!(avg_prices, last_avg_price)
        avg_price_mat[date_raw, symbol] = last_avg_price
        continue
      end

      if trade.type == Sell
        push!(avg_prices, avg_prices[i - 1])
        continue
      end

      prev_trades    = this_trades[1:(i - 1)]
      prev_shares    = map(t -> t.shares, prev_trades)
      total_shares   = sum(prev_shares) + trade.shares
      prev_avg_price = avg_prices[i - 1]
      new_price      = get_adjusted_price(trade)
      weight         = trade.shares / total_shares
      last_avg_price = prev_avg_price * (1 - weight) + new_price * weight

      push!(avg_prices, last_avg_price)
      avg_price_mat[date_raw, symbol] = last_avg_price
    end
  end

  # Forward fill avg prices
  n, m = size(avg_price_mat)
  for j in 1:m
    avg_price_mat[findall(x -> !ismissing(x) && (isnan(x) || isinf(x)), avg_price_mat[:, j]), j] .= missing
    i = findfirst(x -> !ismissing(x), avg_price_mat[:, j])
    if isnothing(i)
      continue
    end
    avg_price_mat[i:n, j] .= ffill(avg_price_mat[i:n, j].array)
  end

  shares_bought_mat       = map(Float64, ffill(shares_bought_mat))
  shares_bought_price_mat = map(Float64, ffill(shares_bought_price_mat))
  shares_sold_mat         = map(Float64, ffill(shares_sold_mat))
  shares_sold_price_mat   = map(Float64, ffill(shares_sold_price_mat))
  transfers_mat           = map(Float64, ffill(transfers_mat))

  return (
    shares_bought       = shares_bought_mat,
    shares_bought_price = shares_bought_price_mat,
    shares_sold         = shares_sold_mat,
    shares_sold_price   = shares_sold_price_mat,
    avg_price           = avg_price_mat,
    commissions         = commissions_mat,
    transfers           = transfers_mat,
  )
end

function get_portfolio_dataset(cfg::Config, port::PortfolioInfo)::PortfolioDataset
  trades = port.trades |> trs -> sort(trs; by=x -> x.symbol)
  symbols = unique(map(x -> x.symbol, trades))
  target_currency = uppercase(string(port.currency))
  members = get_portfolio_members(port)

  dates_trade = map(x -> x.date, trades)
  date_min = minimum(dates_trade)
  @info("Loading prices for portfolio $(port.name) from $(date_min)")
  close = load_prices(cfg, symbols; from=date_min) |> ffill
  raw_dates, _ = names(close)

  forex = load_forex(target_currency)
  trade_info = get_portfolio_trade_info(port, forex)
  # Currency conversions
  for symbol in symbols
    currency = uppercase(string(first(filter(t -> t.symbol == symbol, trades)).currency))
    if currency == target_currency
      continue
    end
    rate = get_latest_exchange_rate(forex, currency)
    close[:, symbol] .*= rate
    trade_info.shares_bought_price[:, symbol] .*= rate
    trade_info.shares_sold_price[:, symbol] .*= rate
    trade_info.avg_price[:, symbol] .*= rate
    trade_info.commissions[:, symbol] .*= rate
  end

  return PortfolioDataset(;
    name=port.name,
    members=members,
    close=fill_missing(close, 0.0),
    shares_bought=expand_matrix(trade_info.shares_bought, raw_dates, symbols),
    shares_bought_price=expand_matrix(trade_info.shares_bought_price, raw_dates, symbols),
    shares_sold=expand_matrix(trade_info.shares_sold, raw_dates, symbols),
    shares_sold_price=expand_matrix(trade_info.shares_sold_price, raw_dates, symbols),
    avg_price=expand_matrix(trade_info.avg_price, raw_dates, symbols) |> ffill |> xs -> fill_missing(xs, 0.0),
    commissions=expand_matrix(trade_info.commissions, raw_dates, symbols),
    transfers=trade_info.transfers,
  )
end
