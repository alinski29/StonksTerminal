module Store

using Arrow
using Comonicon
using Dates
using Stonks
using Tables

using Stonks.APIClients
using Stonks.Stores: init, apply_schema
using StonksTerminal: Config, config_read
using StonksTerminal.Types

@cast function update(; financials::Bool=false, info::Bool=false)
  config = config_read()
  client = build_client()
  stores = load_stores(config.data.dir, config.data.format)
  [update_store(store, client, config; name=string(name), financials=financials, info=info) for (name, store) in stores]
end

function load_stores(path::String, format::FileFormat)
  reader = get_reader(format)
  writer = get_writer(format)

  Dict(
    :info => FileStore{AssetInfo}(;
      path="$path/info",
      ids=[:symbol],
      format="arrow",
      reader=reader,
      writer=writer
    ),
    :price => FileStore{AssetPrice}(;
      path="$path/price",
      ids=[:symbol],
      partitions=[:symbol],
      format="arrow",
      time_column="date",
      reader=reader,
      writer=writer
    ),
    :forex => FileStore{ExchangeRate}(;
      path="$path/forex",
      ids=[:base, :target],
      partitions=[:target],
      format="arrow",
      time_column="date",
      reader=reader,
      writer=writer
    ),
    :balance_sheet => FileStore{BalanceSheet}(;
      path="$path/balance_sheet",
      ids=[:symbol],
      format="arrow",
      reader=reader,
      writer=writer
    ),
    :income_statement => FileStore{IncomeStatement}(;
      path="$path/income_statement",
      ids=[:symbol],
      format="arrow",
      reader=reader,
      writer=writer
    ),
    :cashflow_statement => FileStore{CashflowStatement}(;
      path="$path/cashflow_statement",
      ids=[:symbol],
      format="arrow",
      reader=reader,
      writer=writer
    ),
    :earnings => FileStore{Earnings}(;
      path="$path/earnings",
      ids=[:symbol],
      format="arrow",
      reader=reader,
      writer=writer
    ),
  )
end

function get_writer(format::FileFormat)::Function
  writers = Dict(
    csv => Stonks.Stores.reader_csv,
    arrow =>
      function writer(data::Vector{T}, path::String) where {T<:AbstractStonksRecord}
        Arrow.write(path, Stonks.to_table(unique(data)))
      end
  )
  return writers[format]
end

function get_reader(format::FileFormat)::Function
  readers = Dict(
    csv => Stonks.Stores.writer_csv,
    arrow =>
      function reader(path::String, ::Type{T}) where {T<:AbstractStonksRecord}
        apply_schema(collect(Tables.rows(Arrow.Table(path))), T)
      end
  )
  return readers[format]
end

function build_client()
  yc = YahooClient(ENV["YAHOOFINANCE_TOKEN"])
  # ac = AlphavantageJSONClient(ENV["ALPHAVANTAGE_TOKEN"])
  return Stonks.APIClient(Dict(
    "price" => yc.resources["price"],
    "info" => yc.resources["info"],
    "exchange" => yc.resources["exchange"],
    "income_statement" => yc.resources["income_statement"],
    "balance_sheet" => yc.resources["balance_sheet"],
    "cashflow_statement" => yc.resources["cashflow_statement"],
    "earnings" => yc.resources["earnings"],
  ))
end

get_type_param(::FileStore{T}) where {T<:AbstractStonksRecord} = T

function update_store(store::FileStore, client::APIClient, cfg::Config; name::String, financials::Bool=false, info::Bool=false)
  S = get_type_param(store)
  #@TODO: Remove hardocding here
  min_date = Date("2017-01-01")
  statement_types = [IncomeStatement, BalanceSheet, CashflowStatement, Earnings]
  is_financial_statement = any(map(T -> S === T, statement_types))
  currencies = collect(Iterators.product(cfg.currencies, cfg.currencies)) |> filter(allunique)
  tickers = (
    if (S === ExchangeRate)
      [("$(x)/$(y)", min_date) for (x, y) in currencies]
      # elseif is_financial_statement
      #   map(c -> (c, min_date), cfg.watchlist)
    else
      _tickers = [map(x -> x.symbol, v.trades) for (k, v) in cfg.portfolios] |> x -> vcat(x...) |> unique
      [(c, min_date) for c in union(cfg.watchlist, Set(_tickers))]
    end
  )
  _smb = S === ExchangeRate ? "currency pairs" : "symbols"
  if !ismissing(store.time_column) && !is_financial_statement
    @info "Updating $name datastore... with $(length(tickers)) $_smb..."
    Stonks.update(store, tickers, client)
    @info "Finisehd updating $name datastore."
  elseif is_financial_statement && !financials
    @info "Will not update store of type $S"
  elseif is_financial_statement && financials
    @info "Updating $name datastore... with $(length(tickers)) $_smb..."
    Stonks.update(store, tickers, client)
    @info "Finisehd updating $name datastore."
  elseif S === AssetInfo && info
    @info "Updating $name datastore... with $(length(tickers)) $_smb..."
    Stonks.update(store, tickers, client)
    @info "Finisehd updating $name datastore."
  else
    @info "Datastore $name has no time column. Will not update."
  end
end

end
