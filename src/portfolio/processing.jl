using Dates
using UnicodePlots
using Stonks
using Stonks: load

using Stonks: AssetPrice, AssetInfo
using StonksTerminal.Store
using StonksTerminal.Types: StockRepository, PortfolioDataset, PortfolioMemberDataset, StockRepository
using StonksTerminal: Config, config_read, config_write

get_market_value(p::AssetProfile)::Vector{Float64} = p.shares .* p.closes

get_market_value(r::StockRecord)::Float32 = r.shares * r.close

get_avg_price(p::AssetProfile)::Vector{Float64} =
  (map(abs, p.buys) .- map(abs, p.sells)) ./ p.shares

get_avg_price(r::StockRecord)::Float64 = (abs(r.buy) - abs(r.sell)) / r.shares

get_realized_profit(p::AssetProfile)::Vector{Float64} =
  get_realized_profit(p.dates, p.trades, p.buys, p.sells, p.shares)

get_info_by_name(info::Vector{AssetInfo}, name::String)::Union{AssetInfo, Missing} =
  findfirst(x -> x.symbol == name, info) |> i -> isnothing(i) ? missing : info[i]

function get_realized_profit(
  dates::Vector{Date},
  trades::Vector{Trade},
  buys::Vector{Float64},
  sells::Vector{Float64},
  shares::Vector{Int64},
)::Vector{Float64}
  sell_trades = Dict([
    t.date => (shares=abs(t.shares), share_price=abs(t.proceeds) / abs(t.shares)) for
    t in trades if t.type === Sell
  ])
  avg_price = (map(abs, buys) .- map(abs, sells)) ./ shares

  return [
    get(sell_trades, dates[i], missing) |>
    x -> !ismissing(x) ? x.shares * (x.share_price - avg_price[max(i - 1, 1)]) : 0.00 for
    (i, _) in enumerate(avg_price)
  ] |> cumsum
end

function compute_derived_fields(trades::Vector{Trade}, dates::Vector{Date})::NamedTuple
  trades_by_date = Dict([
    (
      keys.date,
      (
        shares=sum(map(x -> x.shares, vs)),
        sells=filter(x -> x.type === Sell, collect(vs)) |>
              xs -> sum(map(x -> x.proceeds - abs(x.commission), xs)),
        buys=filter(x -> x.type === Buy, collect(vs)) |>
             xs -> sum(map(x -> x.proceeds - -(abs(x.commission)), xs)),
      ),
    ) for (keys, vs) in Stonks.groupby(trades, [:date])
  ])

  get_daily_trade(dt::Date, extractor::Function, default::T) where {T <: Any} =
    get(trades_by_date, dt, missing) |> x -> !ismissing(x) ? extractor(x) : default

  return (
    shares=cumsum(map(dt -> get_daily_trade(dt, x -> x.shares, 0), dates)),
    sells=cumsum(map(dt -> get_daily_trade(dt, x -> x.sells, 0.0), dates)),
    buys=cumsum(map(dt -> get_daily_trade(dt, x -> x.buys, 0.0), dates)),
  )
end

cfg = config_read()
stores = Store.load_stores(cfg.data.dir, arrow)

function load_repository(cfg::Config)::StockRepository
  trades = vcat([p.trades for (_, p) in cfg.portfolios]...)
  symbols = union(cfg.watchlist, Set(map(x -> x.symbol, trades)))
  prices::Dict{String, Vector{AssetPrice}} = 
    Stonks.load(stores[:price], Dict("symbol" => collect(symbols))) |>
    xs -> Dict([keys.symbol => collect(vs) for (keys, vs) in Stonks.groupby(xs, [:symbol])])

  records_by_date::StockRepository = Dict()
  for symbol in symbols
    smb_prices = get(prices, symbol, nothing)
    if isnothing(smb_prices)
      continue
    end
    
    trades_smb = filter(x -> x.symbol == symbol, trades) |> trs -> sort(trs; by=x -> x.date)
    first_trade = isempty(trades_smb) ? Dates.today() - Dates.Day(365) : first(trades_smb).date
    smb_prices = filter(x -> x.date >= first_trade, smb_prices)

    for p in smb_prices
      records_by_date[p.date] = push!(get(records_by_date, p.date, Dict()), symbol => p)
    end
  end

  return records_by_date
end

function get_record_for_closest_date(
  repo::StockRepository,
  date::Date,
  symbol::String,
  retries::Int=10,
)::Union{AssetPrice, Missing}
  if retries == 0
    return missing
  end

  maybe_record = get(repo, date, Dict()) |> res -> get(res, symbol, missing)
  if !ismissing(maybe_record)
    return maybe_record
  else
    previous_weekday =
      [date - Dates.Day(i) for i in 1:5] |> ds -> filter(x -> Stonks.is_weekday(x), ds) |> first
    return get_record_for_closest_date(repo, previous_weekday, symbol, retries - 1)
  end
end

function get_record_for_closest_date(
  forex::Dict{Tuple{Date, String}, Float64},
  date::Date,
  currency::String,
  retries::Int=10,
)::Union{Float64, Missing}
  if retries == 0
    @error("Could not find a close exchange rate for: $currency between $date and $(date + Dates.Day(10))")
    return missing
  end

  maybe_record = get(forex, (date, currency), missing)
  if !ismissing(maybe_record)
    return maybe_record
  end

  closest_prev_date = [date - Dates.Day(i) for i in 1:5] |> 
    ds -> filter(x -> Stonks.is_weekday(x), ds) |> 
    first

  return get_record_for_closest_date(forex, closest_prev_date, currency, retries - 1)
end


# TODO: Should return Dict{String, Trade}
function trades_at_date(trades::Vector{Trade}, date::Date)::Dict{String, Int}
  trades_until_date = filter(t -> t.date <= date, trades)
  if length(trades_until_date) == 0
    return Dict()
  end

  return Dict([
    (keys.symbol, sum(map(x -> x.shares, collect(values)))) for
    (keys, values) in Stonks.groupby(trades_until_date, [:symbol])
  ])

end

function get_assets_at_date(
  repo::StockRepository,
  date::Date,
  trades::Vector{Trade},
)::Dict{String, AssetPrice}
  trades_until_date = filter(t -> t.date <= date, trades)

  if length(trades_until_date) == 0
    return Dict()
  end

  symbols_at_date::Vector{String} =
    [
      (keys.symbol, sum(map(x -> x.shares, collect(values)))) for
      (keys, values) in Stonks.groupby(trades_until_date, [:symbol])
    ] |> xs -> [smb for (smb, shares) in xs if shares > 0]

  maybe_assets::Dict{String, AssetPrice} = get(repo, date, Dict())
  missing_symbols =
    ismissing(maybe_assets) ? symbols_at_date : setdiff(Set(symbols_at_date), keys(maybe_assets))

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
function to_asset_profile(repo::StockRepository, port::PortfolioInfo)::Dict{String, AssetProfile}

  # TODO: Maybe pass it as an argument
  # cfg = config_read()
  dates = sort([d for (d, _) in repo])
  # symbols = union(cfg.watchlist, Set(map(x -> x.symbol, port.trades)))
  symbols = Set(map(x -> x.symbol, port.trades))
  trades = sort(port.trades; by=x -> x.symbol)
  # trades = vcat([p.trades for (_, p) in cfg.portfolios]...) |> trs -> sort(trs; by=x -> x.symbol)
  info = Stonks.load(load_stores()[:info])

  records_by_symbol::Dict{String, Vector{StockRecord}} = Dict()
  for symbol in symbols
    for date in dates
      if haskey(repo[date], symbol)
        record = repo[date][symbol]
        records_by_symbol[symbol] = push!(get(records_by_symbol, symbol, StockRecord[]), record)
      end
    end
  end

  return Dict([
    symbol => AssetProfile(;
      symbol=symbol,
      dates=map(x -> x.date, records),
      closes=map(x -> x.close, records),
      trades=filter(x -> x.symbol == symbol, trades) |> trs -> sort(trs; by=x -> x.date),
      shares=map(x -> x.shares, records),
      buys=map(x -> x.buy, records),
      sells=map(x -> x.sell, records),
      info=get_info_by_name(info, symbol),
    ) for (symbol, records) in records_by_symbol
  ])
end


function convert_price(
  price::Float64,
  date::Date,
  currency::String,
  forex::Dict{Tuple{Date, String}, Float64},
)
  # exchange_rate = get(forex, (date, currency), nothing)
  exchange_rate = get_record_for_closest_date(forex, date, currency)
  if isnothing(exchange_rate)
    @warn("No exchange rate found for currency = $currency on date: $date")
    nothing
  end

  return price * exchange_rate
end

function convert_prices(
  assets::Dict{String, AssetPrice},
  date::Date,
  port::PortfolioInfo,
  info::Dict{String, AssetInfo},
  forex::Dict{Tuple{Date, String}, Float64},
)::Dict{String, AssetPrice}
  target_currency = uppercase(string(port.currency))

  price_new::Dict{String, AssetPrice} = Dict()
  for (smb, price) in assets
    trades_smb = filter(x -> x.symbol == smb, port.trades) |> trs -> sort(trs; by=x -> x.date)
    inf = get(info, smb, nothing)
    currency = (isempty(trades_smb) ? inf.currency : string(first(trades_smb).currency)) |> uppercase
    close = currency != target_currency ? convert_price(price.close, date, currency, forex) : price.close
    price_new[smb] = AssetPrice(; symbol=smb, date=date, close=close)
  end

  return price_new
end


function get_trade_summary(trades::Vector{Trade}, dates::Vector{Date}=Date[])::Dict{Tuple{String, Date}, NamedTuple}

  function compute_stuff(vs::Base.Generator)
      data = collect(vs)
      t_buys = filter(x -> x.type === Buy, data) 
      buys = sum(map(x -> x.proceeds - -(abs(x.commission)), t_buys))
      t_sells = filter(x -> x.type === Sell, data) 
      sells = sum(map(x -> x.proceeds - abs(x.commission), t_sells))
      shares=sum(map(x -> x.shares, vs))
      # share_price = abs(t.proceeds) / abs(t.shares)
      # avg_price = (abs(buys) - abs(sells)) / shares

      return (
        shares = shares, 
        buys=buys,
        sells=sells,
        # share_price = sells / shares,
        avg_price = (abs(buys) - abs(sells)) / shares
        # avg_price=avg_price
      )
  end

  trades_by_date = Dict([
    (keys.symbol, keys.date) => compute_stuff(vs) 
    for (keys, vs) in Stonks.groupby(trades, [:symbol, :date])
  ])

  # sell_trades = Dict([
  #   date => (shares=abs(t.shares), share_price=abs(t.proceeds) / abs(t.shares)) for
  #   (date, t) in trades_by_date if t.type === Sell
  # ])

  # avg_price = (map(abs, buys) .- map(abs, sells)) ./ shares

  # return [
  #   get(sell_trades, dates[i], missing) |>
  #   x -> !ismissing(x) ? x.shares * (x.share_price - avg_price[max(i - 1, 1)]) : 0.00 for
  #   (i, _) in enumerate(avg_price)
  # ] |> cumsum
  
  get_daily_trade(symbol::String, date::Date, extractor::Function, default::T) where {T <: Any} =
    get(trades_by_date, (symbol, date), missing) |> x -> !ismissing(x) ? extractor(x) : default

   all_dates = (
    if isempty(dates)
      tr_dates = unique([x.date for x in trades])
      [d for d in minimum(tr_dates):maximum(tr_dates)]
    else
      dates
    end
  )
  min_date = minimum(all_dates)
  symbols = unique(map(t -> t.symbol, trades))

  result = Dict()
  for smb in symbols
    for date in all_dates
        # rolling = (
        shares = sum(map(dt -> get_daily_trade(smb, dt, x -> x.shares, 0), min_date:date))
        sells = sum(map(dt -> get_daily_trade(smb, dt, x -> x.sells, 0), min_date:date))
        buys = sum(map(dt -> get_daily_trade(smb, dt, x -> x.buys, 0), min_date:date))
        avg_price = (abs(buys) - abs(sells)) / shares
        rolling = (shares=shares, sells=sells, buys=buys, avg_price=avg_price)
        result[(smb, date)] = rolling
    end
  end

  return result
end


function ffill(v::Vector{Union{T, Missing}})::Vector{T} where {T}
  v[accumulate(max, [i*!ismissing(v[i]) for i in 1:length(v)], init=1)]
end

function get_forex(target_currency::String)::Dict{Tuple{Date, String}, Float64}
    Stonks.load(stores[:forex], Dict("target" => [target_currency])) |>
    fx -> Dict(map(x -> ((x.date, x.base), x.rate), fx))
end

function get_portfolio_dataset(repo::StockRepository, port::PortfolioInfo)::PortfolioDataset
  dates = Date[]
  costs::Vector{Union{Float64, Missing}} = Float64[]
  sells::Vector{Union{Float64, Missing}} = Float64[]
  market_values::Vector{Union{Float64, Missing}} = Float64[]
  weights::Dict{Date, Vector{Tuple{String, Float64}}} = Dict()
  # realized_profits = Float64[]
  # unrealized_profit = Float64[]

  trades = port.trades |> trs -> sort(trs; by=x -> x.symbol)
  symbols = unique(map(x -> x.symbol, trades))
  target_currency = uppercase(string(port.currency))
  infos = Dict([(x.symbol, x) for x in Stonks.load(stores[:info])])
  forex = get_forex(target_currency)
  trademap::Dict{Tuple{String, Date}, NamedTuple} = get_trade_summary(trades)

  get_trade_value(smb::String, date::Date, extractor::Function, default::T) where {T} =
    get(trademap, (smb, date), missing) |> x -> !ismissing(x) ? extractor(x) : default

  portMap = Dict()
  for date in sort(map(x -> x.date, port.trades))
    trades_until_date = filter(t -> t.date <= date, trades)
    assets::Dict{String, AssetPrice} =
      get_assets_at_date(repo, date, trades_until_date) |>
      xs -> convert_prices(xs, date, port, infos, forex)

    trades_by_smb = [ smb => get(trademap, (smb, date), missing) for (smb, _) in assets ]
    # d_cost  = sum([!ismissing(trade) ? abs(trade.buys) : 0.0 for trade in trades_by_smb])
    d_sells = sum([!ismissing(t) ? abs(t.sells) : 0.0 for (_, t) in trades_by_smb])
    d_buys = sum([!ismissing(t) ? abs(t.buys) : 0.0 for (_, t) in trades_by_smb])
    # d_avg_price = sum([!ismissing(t) ? abs(t.avg_price) : 0.0 for t in trades_by_smb])
    d_market_value = sum([(p.close * get_trade_value(smb, date, x -> x.shares, 0)) for (smb, p) in assets])

    function get_weight(smb::String, total_market_value::Float64)::Float64
      price = get(assets, smb, missing)
      ismissing(price) && return 0.0
      return (price.close * get_trade_value(smb, date, x -> x.shares, 0)) / total_market_value
    end

    weights[date] = [(smb, get_weight(smb, d_market_value)) for smb in symbols]

    portMap[date] = (market_value = d_market_value, cost=d_buys-d_sells, sells=d_sells, buys=d_buys)
  end

  all_dates = [x for x in minimum(t -> t.date, trades):maximum([k for (k, _) in repo]) if Stonks.is_weekday(x)]
  for date in all_dates
    data = get(portMap, date, nothing)
    push!(dates, date)
    
    if isnothing(data)
      push!(costs, missing)
      push!(market_values, missing)
      push!(sells, missing)
    else
      push!(costs, data.cost)
      push!(market_values, data.market_value)
      push!(sells, data.sells)
    end
  end
  
  members = Dict([ smb => 
    PortfolioMember(get(infos, smb, missing), [t for t in trades if t.symbol == smb])
    for smb in symbols
  ])

  PortfolioDataset(; 
    name=port.name, 
    dates=dates, 
    cost=ffill(costs), 
    market_value=ffill(market_values), 
    members=members, 
    weights=weights
  )
end

function get_portfolio_member_dataset(repo::StockRepository, port::PortfolioInfo, symbol::String)::PortfolioMemberDataset
  dates = Date[]
  closes::Vector{Union{Float64, Missing}} = Float64[]
  shares::Vector{Union{Float64, Missing}} = Int64[]
  costs::Vector{Union{Float64, Missing}} = Float64[]
  sells::Vector{Union{Float64, Missing}} = Float64[]
  market_values::Vector{Union{Float64, Missing}} = Float64[]
  avg_prices::Vector{Union{Float64, Missing}} = Float64[]

  trades = filter(t -> t.symbol == symbol, port.trades) |> trs -> sort(trs; by=x -> x.symbol)
  min_date = minimum(t -> t.date, trades)
  max_date = maximum([k for (k, _) in repo])
  all_dates = [x for x in min_date:max_date if Stonks.is_weekday(x)]
  target_currency = uppercase(string(port.currency))

  info = Stonks.load(stores[:info]) |> xs -> filter(x -> x.symbol==symbol, xs) |> xs -> isempty(xs) ? missing : first(xs)
  forex = get_forex(target_currency)
  trademap::Dict{Tuple{String, Date}, NamedTuple} = get_trade_summary(trades)

  get_trade_value(smb::String, date::Date, extractor::Function, default::T) where {T} =
    get(trademap, (smb, date), missing) |> x -> !ismissing(x) ? extractor(x) : default
  
  status_sparse = Dict()
  for date in unique(map(t -> t.date, trades)) 
    trades_until_date = filter(t -> t.date <= date, trades)
    currency = string(first(trades_until_date).currency) |> uppercase
    price = (
      if currency != target_currency
        price_original = get_record_for_closest_date(repo, date, symbol)
        new_close = convert_price(price_original, date, currency, forex)
        AssetPrice(; symbol=symbol, date=date, close=new_close)
      else
        get_record_for_closest_date(repo, date, symbol)
      end
    )
    trades_by_date = get(trademap, (symbol, date), missing)
    res = (
      close = price.close,
      shares = trades_by_date.shares,
      market_value = trades_by_date.shares * price.close,
      avg_price = trades_by_date.avg_price,
      sells = trades_by_date.sells,
      buys = trades_by_date.buys,
    )
    status_sparse[date] = res
  end

  for date in all_dates
    push!(dates, date)
    
    data = get(status_sparse, date, nothing)
    if isnothing(data)
      push!(closes, missing)
      push!(shares, missing)
      push!(costs, missing)
      push!(sells, missing)
      push!(market_values, missing)
    else
      push!(closes, data.close)
      push!(shares, data.shares)
      push!(costs, data.buys - data.sells)
      push!(sells, data.sells)
      push!(market_values, data.market_value)
      push!(avg_prices, data.avg_price)
    end
  end

  PortfolioMemberDataset(; 
    symbol=symbol,
    dates=dates,
    closes=ffill(closes),
    trades=trades,
    shares=ffill(shares),
    costs=ffill(costs),
    sells=ffill(sells),
    info=info
  )

end

# TODO: Check if we need this
function compute_portfolio_holdings(trades::Vector{Trade})::Vector{FinancialAsset}
  groups = Stonks.groupby(trades, [:symbol])
  weights = [map(x -> x.shares, vs) / sum(map(x -> x.shares, vs)) for (_, vs) in groups]
  [
    FinancialAsset(;
      symbol=keys.symbol,
      trades=collect(values),
      shares=sum(map(x -> x.shares, values)),
      date_first_trade=minimum(map(x -> x.date, values)),
      avg_price=sum(map(x -> x.share_price, values) * first(weights[i])),
    ) for (i, (keys, values)) in enumerate(groups)
  ]
end
