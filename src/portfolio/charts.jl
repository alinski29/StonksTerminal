using Dates

using StonksTerminal: get_basic_stats, format_number, parse_pretty_number, convert_to_monthly
using StonksTerminal.Types: PortfolioDataset
using StonksTerminal.Portfolio: get_returns
using Statistics
using UnicodePlots
using PrettyTables

function plot_portfolio(
  ds::PortfolioDataset;
  from::Union{Missing, Date}=missing,
  to::Union{Missing, Date}=missing,
)
  n, _ = size(ds.close)
  row_names, _ = names(ds.close)
  dates = map(Date, row_names)

  i_start = !ismissing(from) ? findfirst(d -> d >= from, dates) : 1
  i_end = !ismissing(to) ? findfirst(d -> d >= to, dates) : n

  net_shares = cumsum(ds.shares_bought[i_start:i_end, :] .- ds.shares_sold[i_start:i_end, :]; dims=1)
  market_value = get_market_value(ds)[i_start:i_end, :]
  cost = net_shares .* ds.avg_price[i_start:i_end, :]
  dates = dates[i_start:i_end]

  # unrealized_profit = sum(market_value .- cost; dims=2)[:, 1]
  port_cost = sum(cost; dims=2)[:, 1]
  # print(port_cost)
  port_market_value = sum(market_value; dims=2)[:, 1]

  stats = get_basic_stats(vcat(port_market_value.array, port_cost.array))
  y_min = stats.min - 0.1 * stats.std
  y_max = stats.max + 0.1 * stats.std

  lineplot(dates, port_market_value; ylim=(y_min, y_max), width=100)
end

function plot_weights(ds::PortfolioDataset)
  n, _ = size(ds.close)
  market_value = get_market_value(ds)[n, :] |> xs -> filter(x -> x > 0, xs) |> xs -> sort(xs; rev=true)
  heights = map(x -> round(x) |> Int, market_value.array)
  text = first(names(market_value))

  barplot(text, heights; xlabel="Market value")
end

function plot_returns(
  ds::PortfolioDataset;
  from::Union{Nothing, Date}=nothing,
  to::Union{Nothing, Date}=nothing,
)
  n, _ = size(ds.close)
  row_names, _ = names(ds.close)
  dates = map(Date, row_names)
  is = map_dates_to_indices(ds.close, from, to)

  returns = get_returns(ds; from=from, to=to)
  weights = get_weights(ds; from=from, to=to)
  port_returns = sum(returns .* weights; dims=2)[:, 1]

  stats = get_basic_stats(port_returns.array)
  y_min = stats.min - 0.1 * stats.std
  y_max = stats.max + 0.1 * stats.std

  plt = lineplot(dates[is], port_returns; ylim=(y_min, y_max), width=100)

  neg_data = [(r, d) for (r, d) in zip(port_returns, dates[is]) if r < 0.0]
  lineplot!(plt, map(x -> x[2], neg_data), map(x -> x[1], neg_data); color=:red)
  hline!(plt, 0; color=:white)
end

function print_summary_table(ds::PortfolioDataset)
  n, _ = size(ds.close)
  raw_dates, symbols = names(ds.close)

  returns =
    convert_to_monthly(ds.close) |>
    ffill |>
    xs -> fill_missing(xs, 0.0) |> xs -> compute_return(xs; cummulative=false) |> xs -> xs[2:size(xs)[1], :]

  weights =
    get_weights(ds) |>
    ffill |>
    convert_to_monthly |>
    xs -> fill_missing(xs, 0.0) |> xs -> xs[2:size(xs)[1], :]

  # TODO: Consider only when shares were held
  monthly_returns = sum(returns; dims=1) / size(returns)[1] |> xs -> xs[1, :]
  monthly_std = map(name -> std(returns[:, name]), names(returns)[2])

  net_shares = cumsum(ds.shares_bought .- ds.shares_sold; dims=1)[n, :]
  realized_profit = get_realized_profit(ds)[n, :]
  expense = ds.avg_price[n, :] .* net_shares
  max_date = maximum(raw_dates)
  idx_trsf = findall(x -> x <= max_date, names(ds.transfers)[1])
  cash = sum(ds.transfers[idx_trsf, "CASH"]) + sum(realized_profit) - sum(expense)
  close_price = ds.close[n, :]
  avg_price = ds.avg_price[n, :]
  mkt_value = ds.close[n, :] .* net_shares
  profit = mkt_value .- expense
  port_return = profit ./ expense
  weight = mkt_value ./ sum(mkt_value)
  commissions = cumsum(ds.commissions; dims=1)[n, :]

  idx = eachindex(net_shares)
  colnames = [
    "shares",
    "close",
    "average",
    "value",
    "expense",
    "weight",
    "return",
    "return_monthly",
    "stdev_monthly",
    "unrealized",
    "realized",
    "commissions",
  ]
  mat = allocate_matrix(Float64, vcat(symbols[idx], ["CASH", "TOTAL"]), colnames)
  mat[1:length(idx), :] = NamedArray(
    reduce(
      hcat,
      [
        net_shares,
        close_price,
        avg_price,
        mkt_value,
        expense,
        weight,
        port_return,
        monthly_returns,
        monthly_std,
        profit,
        realized_profit,
        commissions,
      ],
    ),
  )[
    idx,
    :,
  ]

  data = NamedArray(hcat(NamedArray(names(mat)[1]), mat))
  setnames!(data, vcat("symbol", colnames), 2)

  row_order =
    enumerate(data[:, "value"]) |>
    collect |>
    xs -> sort(xs; by=x -> x[2], rev=true) |> xs -> map(x -> x[1], xs)

  # FILL CASH row
  n, _ = size(data)
  data[n - 1, ["value", "expense"]] .= cash

  # Fill TOTAL row
  for col in ["value", "expense", "weight", "unrealized", "realized", "commissions"]
    data[n, col] = sum(data[1:(n - 1), col])
  end

  # Fill monthly return & stdev TOTAL rows
  data[n, "return_monthly"] = sum(returns .* weights; dims=2) |> mean
  data[n, "stdev_monthly"] = sum(monthly_std .* weight, dims=2) |> mean

  # Recompute weights to include cash
  data[1:(n - 1), "weight"] .= data[1:(n - 1), "value"] ./ sum(data[1:(n - 1), "value"])

  # Pretty table formatting
  data[n, "return"] = (data[n, "value"] / data[n, "expense"]) - 1
  data[:, "close"] .= map(format_number, data[:, "close"])
  data[:, "average"] .= map(format_number, data[:, "average"])
  data[:, "shares"] .= map(x -> format_number(Float64(x)), data[:, "shares"])
  data[:, "value"] .= map(x -> format_number(Int(round(x))), data[:, "value"])
  data[:, "expense"] .= map(x -> format_number(Int(round(x))), data[:, "expense"])
  data[:, "unrealized"] .= map(x -> format_number(Int(round(x))), data[:, "unrealized"])
  data[:, "realized"] .= map(x -> format_number(Int(round(x))), data[:, "realized"])
  data[:, "return"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "return"])
  data[:, "return_monthly"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "return_monthly"])
  data[:, "stdev_monthly"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "stdev_monthly"])
  data[:, "weight"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "weight"])
  data[:, "commissions"] .= map(x -> format_number(-abs(x)), data[:, "commissions"])
  data[(n - 1):n, ["shares", "close", "average"]] .= ""

  #data[findfirst(x -> x == 0, data[:, "shares"])]

  header = (
    map(x -> split(x, "_")[1], vcat("symbol", colnames)),
    [
      "",
      "",
      "price \$",
      "price \$",
      "market \$",
      "\$",
      "%, total",
      "%, total",
      "%, monthly",
      "%, monthly",
      "profit \$",
      "profit \$",
      "\$",
    ],
  )

  # Highlight profits with green, losses with red and total column
  idx_color_unrlzd = findall(x -> x in ["unrealized", "return"], header[1])
  idx_color_rlzd = findall(x -> x in ["realized"], header[1])
  hl_green_unrlzd = Highlighter(
    (data, i, j) -> j in idx_color_unrlzd && parse_pretty_number(Float64, data[i, "unrealized"]) > 0.0,
    crayon"green",
  )
  hl_red_unrlzd = Highlighter(
    (data, i, j) -> j in idx_color_unrlzd && parse_pretty_number(Float64, data[i, "unrealized"]) < 0.0,
    crayon"red",
  )

  hl_green_rlzd = Highlighter(
    (data, i, j) -> j in idx_color_rlzd && parse_pretty_number(Float64, data[i, "realized"]) > 0.0,
    crayon"green",
  )
  hl_red_rlzd = Highlighter(
    (data, i, j) -> j in idx_color_rlzd && parse_pretty_number(Float64, data[i, "realized"]) < 0.0,
    crayon"red",
  )

  hl_total_rlzd_green = Highlighter(
    (data, i, j) ->
      j in idx_color_rlzd &&
        data[i, "symbol"] == "TOTAL" &&
        parse_pretty_number(Float64, data[i, "realized"]) > 0.0,
    crayon"green bold underline bg:dark_gray",
  )
  hl_total_rlzd_red = Highlighter(
    (data, i, j) ->
      j in idx_color_rlzd &&
        data[i, "symbol"] == "TOTAL" &&
        parse_pretty_number(Float64, data[i, "realized"]) < 0.0,
    crayon"red bold underline bg:dark_gray",
  )
  hl_total_unrlzd_green = Highlighter(
    (data, i, j) ->
      j in idx_color_unrlzd &&
        data[i, "symbol"] == "TOTAL" &&
        parse_pretty_number(Float64, data[i, "unrealized"]) > 0.0,
    crayon"green bold underline bg:dark_gray",
  )
  hl_total_unrlzd_red = Highlighter(
    (data, i, j) ->
      j in idx_color_unrlzd &&
        data[i, "symbol"] == "TOTAL" &&
        parse_pretty_number(Float64, data[i, "unrealized"]) < 0.0,
    crayon"red bold underline bg:dark_gray",
  )
  hl_total = Highlighter(
    (data, i, j) -> !(j in union(idx_color_rlzd, idx_color_unrlzd)) && data[i, "symbol"] == "TOTAL",
    crayon"bold underline bg:dark_gray",
  )

  pretty_table(
    data[row_order, :];
    header=header,
    highlighters=(
      hl_total,
      hl_total_rlzd_green,
      hl_total_rlzd_red,
      hl_total_unrlzd_green,
      hl_total_unrlzd_red,
      hl_green_unrlzd,
      hl_red_unrlzd,
      hl_green_rlzd,
      hl_red_rlzd,
    ),
    tf=tf_unicode_rounded,
  )
end
