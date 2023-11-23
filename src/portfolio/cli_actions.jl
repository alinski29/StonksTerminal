using Comonicon
using Stonks
using StonksTerminal.Types
using StonksTerminal: Config, config_read, config_write
using StonksTerminal: collect_user_input, parse_string, print_enum_values, enum_from_string, format_number, parse_pretty_number

# include("../utils.jl")

function add_trade(type::TradeType, name::Union{String, Nothing}=nothing)
  cfg = config_read()
  port = get_portfolio(cfg, name)

  date = collect_user_input("Enter date in format 'yyyy-mm-dd': ", Date)
  symbol = collect_user_input("Symbol (ticker): ", String)
  shares = collect_user_input("Number of shares: ", Int64)
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

function transfer_funds(;
  type::Union{TransferType, Nothing}=nothing,
  name::Union{String, Nothing}=nothing,
)
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

function print_summary_table(ds::PortfolioDataset)
	n, _ = size(ds.close)
	raw_dates, symbols = names(ds.close)

	net_shares = cumsum(ds.shares_bought .- ds.shares_sold; dims=1)[n, :]
	realized_profit = get_realized_profit(ds)[n, :]
	expense = ds.avg_price[n, :] .* net_shares
	max_date = maximum(raw_dates)
	idx_trsf = findall(x -> x <= max_date, names(ds.transfers)[1])
	# idx_tr
	cash = sum(ds.transfers[idx_trsf, "CASH"]) + sum(realized_profit) - sum(expense)
	close_price = ds.close[n, :]
	avg_price = ds.avg_price[n, :]
	mkt_value = ds.close[n, :] .* net_shares
	profit = mkt_value .- expense
	port_return = profit ./ expense
	weight = mkt_value ./ sum(mkt_value)
	commissions = cumsum(ds.commissions; dims=1)[n, :]
	# currency = map(s -> ds.members[s].info.currency, col_names)
	# stock_exchange = map(s -> ds.members[s].info.exchange, col_names)
	# date_first_trade = map(s -> ds.members[s].trades |> xs -> map(x -> x.date, xs) |> minimum,  col_names)

	# idx = findall(x -> x > 0, net_shares)
	idx = eachindex(net_shares)
	colnames = ["shares", "close", "average", "value", "expense", "weight", "return", "unrealized", "realized", "commissions"]
	mat = allocate_matrix(Float64, vcat(symbols[idx], ["CASH", "TOTAL"]), colnames)
	mat[1:length(idx), :] = NamedArray(
		reduce(
			hcat,
			[net_shares, close_price, avg_price, mkt_value, expense, weight, port_return, profit, realized_profit, commissions],
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
	data[n-1, ["value", "expense"]] .= cash

	# Fill TOTAL row
	for col in ["value", "expense", "weight", "unrealized", "realized", "commissions"]
		data[n, col] = sum(data[1:(n - 1), col])
	end

	# data[""]
	# Recompute data to include cash
	data[1:n-1, "weight"] .= data[1:(n-1), "value"] ./ sum(data[1:(n - 1), "value"]) 
	
	data[n, "return"] = (data[n, "value"] / data[n, "expense"]) - 1
	data[:, "close"] .= map(format_number, data[:, "close"])
	data[:, "average"] .= map(format_number, data[:, "average"])
	data[:, "shares"] .= map(x -> format_number(Int(x)), data[:, "shares"])
	data[:, "value"] .= map(x -> format_number(Int(round(x))), data[:, "value"])
	data[:, "expense"] .= map(x -> format_number(Int(round(x))), data[:, "expense"])
	data[:, "unrealized"] .= map(x -> format_number(Int(round(x))), data[:, "unrealized"])
	data[:, "realized"] .= map(x -> format_number(Int(round(x))), data[:, "realized"])
	data[:, "return"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "return"])
	data[:, "weight"] .= map(x -> "$(round(x * 100, digits=2)) %", data[:, "weight"])
	data[:, "commissions"] .= map(x -> format_number(- abs(x)), data[:, "commissions"])
	data[n-1:n, ["shares", "close", "average"]] .= ""

	header = (
		vcat("symbol", colnames),
		["", "", "price \$", "price \$", "market \$", "\$", "%", "%", "profit \$", "profit \$", "\$"],
	)
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
