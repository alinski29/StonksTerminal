using Dates
using Stonks
using Stonks: load, AssetPrice, AssetInfo
using UnicodePlots

using StonksTerminal.Store
using StonksTerminal: Config, config_read, config_write

function load_prices(
  cfg::Config,
  symbols::Vector{String};
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)::NamedMatrix{Union{Float64, Missing}}
  stores = Store.load_stores(cfg.data.dir, arrow)
  dt_from = isnothing(from) ? Date("1970-01-01") : from
  dt_to = isnothing(to) ? Dates.today() : to

  prices::Dict{String, Vector{Tuple{Date, Float64}}} =
    Stonks.load(stores[:price], Dict("symbol" => symbols)) |>
    xs -> Dict([
      keys.symbol => [(v.date, v.close) for v in vs if v.date >= dt_from && v.date <= dt_to] for
      (keys, vs) in Stonks.groupby(xs, [:symbol])
    ])

  symbols_date_min = [minimum(v -> v[1], vs) for (_, vs) in prices] |> minimum
  all_dates = [d for d in symbols_date_min:dt_to]
  row_names = map(d -> Dates.format(d, "yyyy-mm-dd"), all_dates)

  mat = allocate_matrix(Union{Float64, Missing}, row_names, symbols)
  for (symbol, vs) in prices
    for (date, close) in vs
      mat[Dates.format(date, "yyyy-mm-dd"), symbol] = close
    end
  end

  return mat
end

function load_forex(target_currency::String)::Dict{Tuple{Date, String}, Float64}
  stores = Store.load_stores(config_read().data.dir, arrow)
  # TODO: Use predicate pushdown after fixing the bug when saving currencies
  # Stonks.load(stores[:forex], Dict("target" => [target_currency])) |>
  Stonks.load(stores[:forex]) |>
  xs -> filter(x -> x.target == target_currency, xs) |> fx -> Dict(map(x -> ((x.date, x.base), x.rate), fx))
end

function get_latest_exchange_rate(forex::Dict{Tuple{Date, String}, Float64}, base::String)::Float64
  candidates = [(date, base) for ((date, symbol), _) in forex if symbol == base]
  if isempty(candidates)
    error("Could not find any keys for currency: $base")
  end
  max_forex_key = maximum(candidates)
  return forex[max_forex_key]
end

function compute_return(
  close::NamedMatrix{Float64};
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
  cummulative::Bool=true,
)::NamedMatrix{Float64}
  slice = map_dates_to_indices(close, from, to)
  row_names, col_names = names(close[slice, :])
  daily_returns = allocate_matrix(Float64, row_names, col_names)
  n, _ = size(daily_returns)
  daily_returns[1, :] .= 1.0
  daily_returns[2:n, :] =
    close[(first(slice) + 1):last(slice), :] ./ close[first(slice):(last(slice) - 1), :] |>
    mat -> map(x -> isnan(x) || isinf(x) ? 1.0 : x, mat)

  if cummulative
    return cumprod(daily_returns; dims=1) .- 1
  else
    return daily_returns .- 1
  end
end

function convert_to_monthly(data::NamedMatrix)
  raw_dates, symbols = names(data)
  date_min = Date(minimum(raw_dates))

  month_start = Dates.Month(date_min).value
  year_start = Dates.Year(date_min).value
  today = Dates.today()
  year_end = Dates.Year(today).value
  month_end = Dates.Month(today).value
  dates_indx = String[]
  month_current = month_start
  year_current = year_start

  while year_current < year_end || (year_current == year_end && month_current <= month_end)
    date_candidates = map(i -> "$year_current-$(lpad(string(month_current), 2, '0'))-0$i", 1:9)
    idx_candidate = findfirst(date -> date in raw_dates, date_candidates)

    if isnothing(idx_candidate)
    else
      date = date_candidates[idx_candidate]
      push!(dates_indx, date)
    end

    if month_current == 12
      year_current += 1
      month_current = 1
    else
      month_current += 1
    end
  end

  res = allocate_matrix(Union{Float64, Missing}, dates_indx, symbols)
  for date in dates_indx
    res[date, :] .= data[date, :]
  end

  return res
end

function compute_correlation_matrix(
  prices::NamedMatrix;
  min_obs::Int=24,
  max_obs::Int=48,
  frequency::String="monthly",
)
  data = convert_to_monthly(prices)
  returns = compute_return(fill_missing(data, 0.0))
  _, symbols = names(returns)

  corr_mat = allocate_matrix(Union{Float64, Missing}, symbols, symbols)
  for symbol in symbols
    ok_indx = findall(x -> x != 0.0, returns[:, symbol])
    idx_slice = (
      if length(ok_indx) >= max_obs
        ok_indx[(length(ok_indx) - max_obs):length(ok_indx)]
      elseif length(ok_indx) >= min_obs
        ok_indx
      else
        nothing
      end
    )
    if isnothing(idx_slice)
      corr_mat[symbol, symbol] = missing
      continue
    end

    for dest_symbol in symbols
      if symbol == dest_symbol
        corr_mat[symbol, symbol] = 1.0
      else
        corr_mat[symbol, dest_symbol] = cor(returns[idx_slice, symbol], returns[idx_slice, dest_symbol])
      end
    end
  end

  return corr_mat
end