using Dates
using NamedArrays
using Stonks
using Stonks: load, AssetPrice, AssetInfo
using UnicodePlots

using StonksTerminal.Store
using StonksTerminal.Types
using StonksTerminal: Config, config_read, config_write
using StonksTerminal: allocate_matrix, expand_matrix, ffill, fill_missing
using StonksTerminal: map_dates_to_indices, get_record_for_closest_date

function get_return(p::PortfolioDataset; from::Union{Date, Nothing}=nothing, to::Union{Date, Nothing}=nothing)
	slice = map_dates_to_indices(p.close, from, to)
	row_names, col_names = names(p.close[slice, :])
	daily_returns = allocate_matrix(Float64, row_names, col_names)
	n, _ = size(daily_returns)
	daily_returns[1, :] .= 1.0
	daily_returns[2:n, :] =
		p.close[(first(slice) + 1):last(slice), :] ./ p.close[first(slice):(last(slice) - 1), :] |>
		mat -> map(x -> isnan(x) || isinf(x) ? 1.0 : x, mat)

	return cumprod(daily_returns; dims=1) .- 1
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
	println(slice)
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

function load_repository(cfg::Config)::StockRepository
	trades = vcat([p.trades for (_, p) in cfg.portfolios]...)
	symbols = union(cfg.watchlist, Set(map(x -> x.symbol, trades)))
	stores = Store.load_stores(config_read().data.dir, arrow)
	prices::Dict{String, Vector{AssetPrice}} =
		Stonks.load(stores[:price], Dict("symbol" => collect(symbols))) |>
		xs -> Dict([keys.symbol => collect(vs) for (keys, vs) in Stonks.groupby(xs, [:symbol])])

	repository::StockRepository = Dict()
	for symbol in symbols
		smb_prices = get(prices, symbol, nothing)
		if isnothing(smb_prices)
			continue
		end

		trades_smb = filter(x -> x.symbol == symbol, trades) |> trs -> sort(trs; by=x -> x.date)
		first_trade = isempty(trades_smb) ? Dates.today() - Dates.Day(365) : first(trades_smb).date
		smb_prices = filter(x -> x.date >= first_trade, smb_prices)

		for p in smb_prices
			repository[p.date] = push!(get(repository, p.date, Dict()), symbol => p)
		end
	end

	return repository
end

function get_forex(target_currency::String)::Dict{Tuple{Date, String}, Float64}
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

function get_adjusted_price(trade::Trade)
	price_comission = abs(trade.commission / trade.shares)
	price_penalty = trade.type == Buy ? abs(price_comission) : -abs(price_comission)
	return trade.share_price + price_penalty
end

function get_portfolio_trade_info(port::PortfolioInfo)
	trades, transfers = port.trades, port.transfers
	symbols = sort(unique(map(x -> x.symbol, trades)))
	dates = vcat(map(x -> x.date, trades), map(x -> x.date, transfers)) |> unique |> sort
	dates_raw = map(d -> Dates.format(d, "yyyy-mm-dd"), dates)

	shares_bought_mat = allocate_matrix(Int64, dates_raw, symbols) # net shares
	shares_sold_mat = allocate_matrix(Int64, dates_raw, symbols) # net shares
	shares_bought_price_mat = allocate_matrix(Float64, dates_raw, symbols) # aquisition cost?
	shares_sold_price_mat = allocate_matrix(Float64, dates_raw, symbols)
	commissions_mat = allocate_matrix(Float64, dates_raw, symbols)
	avg_price_mat = allocate_matrix(Union{Float64, Missing}, dates_raw, symbols)
	transfers_mat = allocate_matrix(Float64, dates_raw, ["CASH"])

	target_currency = uppercase(string(port.currency))
	forex = get_forex(target_currency)
	for transfer in sort(port.transfers; by=x -> x.date)
		transfer_value = transfer.type == Deposit ? abs(transfer.proceeds) : -abs(transfer.proceeds)
		if transfer.currency != port.currency
			transfer_value *= get_latest_exchange_rate(forex, uppercase(string(transfer.currency)))
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

			prev_trades = this_trades[1:(i - 1)]
			prev_shares = map(t -> t.shares, prev_trades)
			total_shares = sum(prev_shares) + trade.shares
			prev_avg_price = avg_prices[i - 1]
			new_price = get_adjusted_price(trade)
			weight = trade.shares / total_shares
			last_avg_price = prev_avg_price * (1 - weight) + new_price * weight
			push!(avg_prices, last_avg_price)
			avg_price_mat[date_raw, symbol] = last_avg_price
		end
	end

	# Forward fill avg prices
	n, m = size(avg_price_mat)
	println(typeof(avg_price_mat))
	for j in 1:m
		avg_price_mat[findall(x -> !ismissing(x) && (isnan(x) || isinf(x)), avg_price_mat[:, j]), j] .= missing
		i = findfirst(x -> !ismissing(x), avg_price_mat[:, j])
		if isnothing(i)
			continue
		end
		avg_price_mat[i:n, j] .= ffill(avg_price_mat[i:n, j].array)
	end

	shares_bought_mat = map(Int, ffill(shares_bought_mat))
	shares_bought_price_mat = map(Float64, ffill(shares_bought_price_mat))
	shares_sold_mat = map(Int, ffill(shares_sold_mat))
	shares_sold_price_mat = map(Float64, ffill(shares_sold_price_mat))
	transfers_mat = map(Float64, ffill(transfers_mat))

	return (
		shares_bought=shares_bought_mat,
		shares_bought_price=shares_bought_price_mat,
		shares_sold=shares_sold_mat,
		shares_sold_price=shares_sold_price_mat,
		avg_price=avg_price_mat,
		commissions=commissions_mat,
		transfers=transfers_mat,
	)
end

function get_portfolio_dataset(repo::StockRepository, port::PortfolioInfo)::PortfolioDataset
	trades = port.trades |> trs -> sort(trs; by=x -> x.symbol)
	symbols = unique(map(x -> x.symbol, trades))
	target_currency = uppercase(string(port.currency))
	members = get_portfolio_members(port)

	dates_trade = map(x -> x.date, trades)
	date_min = minimum(dates_trade)
	date_max = maximum([d for (d, _) in repo])
	all_dates = [d for d in date_min:date_max]
	raw_dates = map(d -> Dates.format(d, "yyyy-mm-dd"), all_dates)

	close = allocate_matrix(Union{Float64, Missing}, raw_dates, symbols)
	trade_info = get_portfolio_trade_info(port)
	# Add data about closing prices
	for (i, date) in enumerate(all_dates)
		prices_at_date = Dict([symbol => get_record_for_closest_date(repo, date, symbol) for symbol in symbols])
		for symbol in symbols
			maybe_price = get(prices_at_date, symbol, missing)
			if ismissing(maybe_price)
				continue
			end
			close[i, symbol] = maybe_price.close
		end
	end

	# Currency conversions
	forex = get_forex(target_currency)
	for symbol in symbols
		currency = uppercase(string(first(filter(t -> t.symbol == symbol, trades)).currency))
		println("symbol: $symbol; currency: $currency; target_currency: $target_currency")
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
