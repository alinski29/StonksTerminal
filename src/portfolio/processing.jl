using Dates
using UnicodePlots
using Stonks
using Stonks: load

using StonksTerminal.Store
using StonksTerminal: Config, config_read
using StonksTerminal: TransferType, TradeType, Trade, PortfolioInfo, StockRepository, StockRecord, AssetProfile, FinancialAsset
using StonksTerminal: arrow
using StonksTerminal: TradeType, Buy, Sell

get_market_value(p::AssetProfile)::Vector{Float64} =
  p.shares .* p.closes

get_market_value(r::StockRecord)::Float32 =
  r.shares * r.close

get_avg_price(p::AssetProfile)::Vector{Float64} =
  (map(abs, p.buys) .- map(abs, p.sells)) ./ p.shares

get_avg_price(r::StockRecord)::Float64 =
  (abs(r.buy) - abs(r.sell)) / r.shares

get_realized_profit(p::AssetProfile)::Vector{Float64} =
  get_realized_profit(p.dates, p.trades, p.buys, p.sells, p.shares)

get_info_by_name(info::Vector{AssetInfo}, name::String)::Union{AssetInfo,Missing} =
  findfirst(x -> x.symbol == name, info) |> i -> isnothing(i) ? missing : info[i]

function get_realized_profit(
  dates::Vector{Date},
  trades::Vector{Trade},
  buys::Vector{Float64},
  sells::Vector{Float64},
  shares::Vector{Int64},
)::Vector{Float64}

  sell_trades = Dict([
    t.date => (shares=abs(t.shares), share_price=abs(t.proceeds) / abs(t.shares))
    for t in trades if t.type === Sell
  ])
  avg_price = (map(abs, buys) .- map(abs, sells)) ./ shares

  return [
    get(sell_trades, dates[i], missing) |> x -> !ismissing(x) ? x.shares * (x.share_price - avg_price[max(i - 1, 1)]) : 0.00
    for (i, _) in enumerate(avg_price)
  ] |> cumsum
end

function compute_derived_fields(trades::Vector{Trade}, dates::Vector{Date})::NamedTuple

  trades_by_date = Dict([
    (keys.date, (
      shares=sum(map(x -> x.shares, vs)),
      sells=filter(x -> x.type === Sell, collect(vs)) |> xs -> sum(map(x -> x.proceeds - abs(x.commission), xs)),
      buys=filter(x -> x.type === Buy, collect(vs)) |> xs -> sum(map(x -> x.proceeds - -(abs(x.commission)), xs))
    )) for (keys, vs) in Stonks.groupby(trades, [:date])
  ])

  get_daily_trade(dt::Date, extractor::Function, default::T) where {T<:Any} =
    get(trades_by_date, dt, missing) |>
    x -> !ismissing(x) ? extractor(x) : default

  return (
    shares=cumsum(map(dt -> get_daily_trade(dt, x -> x.shares, 0), dates)),
    sells=cumsum(map(dt -> get_daily_trade(dt, x -> x.sells, 0.0), dates)),
    buys=cumsum(map(dt -> get_daily_trade(dt, x -> x.buys, 0.0), dates)),
  )

end

load_stores() = Store.load_stores(cfg.data.dir, arrow)

function load_repository(cfg::Config, port::PortfolioInfo)::StockRepository

  stores = load_stores()
  symbols = Set(map(x -> x.symbol, port.trades))
  # symbols = union(cfg.watchlist, Set(map(x -> x.symbol, port.trades)))
  # trades = vcat([p.trades for (_, p) in cfg.portfolios]...) |> trs -> sort(trs; by=x -> x.symbol)
  trades = port.trades |> trs -> sort(trs; by=x -> x.symbol)
  # @info("trades: $(typeof(trades))")

  # @TODO: Think of a better logic for this
  target_currency = "USD"
  currencies = Set([uppercase(string(x)) for x in cfg.currencies])

  forex::Dict{Tuple{Date,String},Float64} =
    filter(x -> x.target == target_currency && x.target in currencies, Stonks.load(stores[:forex], Dict("target" => [target_currency]))) |>
    fx -> Dict(map(x -> ((x.date, x.base), x.rate), fx))

  records_by_date::StockRepository = Dict()
  for symbol in symbols
    trades_smb = filter(x -> x.symbol == symbol, trades) |> trs -> sort(trs; by=x -> x.date)
    first_trade = isempty(trades_smb) ? Dates.today() - Dates.Day(365) : first(trades_smb).date
    currency = isempty(trades_smb) ? target_currency : uppercase(string(first(trades_smb).currency))
    # @info("currency: $(currency); target_currency: $(target_currency)")

    dates, closes = Date[], Float64[]
    for x in Stonks.load(stores[:price], Dict("symbol" => [symbol]))
      if (currency == target_currency || haskey(forex, (x.date, currency))) && x.date >= first_trade - Dates.Day(30)
        push!(dates, x.date)
        push!(closes, x.close * (currency == target_currency ? 1.0 : forex[(x.date, currency)]))
      end
    end

    if isempty(dates)
      continue
    end

    n = length(dates)
    (shares, sells, buys) = (
      if !isempty(trades_smb)
        x = compute_derived_fields(trades_smb, dates)
        (x.shares, x.buys, x.sells)
      else

        (repeat([0], n), repeat([0.0], n), repeat([0.0], n))
      end
    )

    for (symbol, date, close, share, sell, buy) in zip(repeat([symbol], n), dates, closes, shares, sells, buys)
      records_by_date[date] = push!(get(records_by_date, date, Dict()), symbol => StockRecord(;
        symbol=symbol, date=date, close=close, shares=share, sell=sell, buy=buy
      ))
    end
  end

  return records_by_date
end

function get_record_for_closest_date(repo::StockRepository, date::Date, symbol::String, retries::Int=10)::Union{StockRecord,Missing}
  if retries == 0
    return missing
  end

  maybe_record = get(repo, date, Dict()) |> res -> get(res, symbol, missing)
  if !ismissing(maybe_record)
    return maybe_record
  else
    previous_weekday = [date - Dates.Day(i) for i in 1:5] |> ds -> filter(x -> Stonks.is_weekday(x), ds) |> first
    return get_record_for_closest_date(repo, previous_weekday, symbol, retries - 1)
  end
end

function get_assets_at_date(repo::StockRepository, date::Date, trades::Vector{Trade})::Dict{String,StockRecord}

  trades_until_date = filter(t -> t.date <= date, trades)

  if length(trades_until_date) == 0
    return Dict()
  end

  symbols_at_date::Vector{String} = [
    (keys.symbol, sum(map(x -> x.shares, collect(values))))
    for (keys, values) in Stonks.groupby(trades_until_date, [:symbol])
  ] |> xs -> [smb for (smb, shares) in xs if shares > 0]

  maybe_assets::Dict{String,StockRecord} = get(repo, date, Dict())
  missing_symbols = ismissing(maybe_assets) ? symbols_at_date : setdiff(Set(symbols_at_date), keys(maybe_assets))

  if isempty(missing_symbols)
    return maybe_assets
  end

  for symbol in missing_symbols
    maybe_record = get_record_for_closest_date(repo, date, symbol, 10)
    if !ismissing(maybe_record)
      maybe_record.date = date
      maybe_assets[symbol] = maybe_record
    else
      @warn("Could not find any fresh record for $(symbol) at date: $(date)")
    end
  end

  return maybe_assets
end

# TODO: Better compute it from price + asset_ifno
function to_asset_profile(repo::StockRepository, port::PortfolioInfo)::Dict{String,AssetProfile}

  # TODO: Maybe pass it as an argument
  # cfg = config_read()
  dates = sort([d for (d, _) in repo])
  # symbols = union(cfg.watchlist, Set(map(x -> x.symbol, port.trades)))
  symbols = Set(map(x -> x.symbol, port.trades))
  trades = sort(port.trades; by=x -> x.symbol)
  # trades = vcat([p.trades for (_, p) in cfg.portfolios]...) |> trs -> sort(trs; by=x -> x.symbol)
  info = Stonks.load(load_stores()[:info])

  records_by_symbol::Dict{String,Vector{StockRecord}} = Dict()
  for symbol in symbols
    for date in dates
      if haskey(repo[date], symbol)
        record = repo[date][symbol]
        records_by_symbol[symbol] = push!(get(records_by_symbol, symbol, StockRecord[]), record)
      end
    end
  end

  return Dict([symbol => AssetProfile(;
    symbol=symbol,
    dates=map(x -> x.date, records),
    closes=map(x -> x.close, records),
    trades=filter(x -> x.symbol == symbol, trades) |> trs -> sort(trs; by=x -> x.date),
    shares=map(x -> x.shares, records),
    buys=map(x -> x.buy, records),
    sells=map(x -> x.sell, records),
    info=get_info_by_name(info, symbol)
  ) for (symbol, records) in records_by_symbol])

end

function to_porfolio_profile(repo::StockRepository, port::PortfolioInfo)::PortfolioProfile

  info = Stonks.load(load_stores()[:info])
  dates = Date[]
  costs = Float64[]
  market_value = Float64[]
  sells = Float64[]
  shares = Int64[]
  weights::Dict{Date,Vector{Tuple{String,Float64}}} = Dict()

  repo_dates = sort([d for (d, _) in repo])
  for date in repo_dates
    assets = get_assets_at_date(repo, date, port.trades)
    market_value_at_date = sum([get_market_value(rec) for (_, rec) in assets])
    push!(dates, date)
    push!(costs, sum([abs(rec.buy) for (_, rec) in assets]))
    push!(sells, sum([abs(rec.sell) for (_, rec) in assets]))
    push!(shares, sum([abs(rec.shares) for (_, rec) in assets]))
    push!(market_value, market_value_at_date)
    weights[date] = [
      (smb, (market_value_at_date > 0 ? rec.close * rec.shares / market_value_at_date : 0)) for (smb, rec) in assets
    ]
  end

  realized_profit = get_realized_profit(dates, port.trades, costs, sells, shares)
  unrealized_profit = market_value .- realized_profit
  members = Dict([
    smb => PortfolioMember(;
      info=get_info_by_name(info, smb),
      trades=filter(t -> t.symbol == smb, port.trades) |> xs -> sort(xs, by=x -> x.date)
    )
    for (smb, _) in get_assets_at_date(repo, last(repo_dates), port.trades)
  ])

  return PortfolioProfile(;
    name=port.name,
    dates=dates,
    market_value=market_value,
    cost=costs,
    realized_profit=realized_profit,
    unrealized_profit=unrealized_profit,
    weights=weights,
    members=members
  )
end

# TODO: Check if we need this
function compute_portfolio_holdings(trades::Vector{Trade})::Vector{FinancialAsset}
  groups = Stonks.groupby(trades, [:symbol])
  weights = [map(x -> x.shares, vs) / sum(map(x -> x.shares, vs)) for (_, vs) in groups]
  [FinancialAsset(;
    symbol=keys.symbol,
    trades=collect(values),
    shares=sum(map(x -> x.shares, values)),
    date_first_trade=minimum(map(x -> x.date, values)),
    avg_price=sum(map(x -> x.share_price, values) * first(weights[i]))
  ) for (i, (keys, values)) in enumerate(groups)]
end