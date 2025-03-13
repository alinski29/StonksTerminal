using Dates
using Test

using StonksTerminal.Types
using StonksTerminal: Config, StoreConfig
using StonksTerminal: enum_from_stringa

using Stonks:
  UpdatableSymbol,
  AssetPrice,
  ExchangeRate,
  is_weekday,
  last_sunday,
  last_workday,
  build_fx_pair

function load_testconfig()
  transfers = [
    Transfer(Date("2023-01-01"), Deposit, USD, 500.00),
    Transfer(Date("2023-02-01"), Deposit, USD, 450.00),
    Transfer(Date("2023-03-01"), Deposit, USD, 550.00),
    Transfer(Date("2023-04-01"), Withdrawal, USD, 200.00),
  ]

  trades = [
    Trade(Date("2023-01-02"), Buy, "AAPL", 4.0, 85.0, 1.00, USD, 1.00),
    Trade(Date("2023-01-02"), Buy, "MSFT", 8.0, 98.0, 1.00, USD, 1.00),
    Trade(Date("2023-01-30"), Buy, "AAPL", 3.0, 105.0, 1.00, USD, 1.00),
  ]

  portfolios = Dict("test" => PortfolioInfo(; name="test", currency=USD, transfers=transfers, trades=trades))

  return Config(;
    data=StoreConfig(; dir="/tmp/StonksTerminal/data", format=csv),
    watchlist=Set(["AAPL", "AMZN", "MSFT", "MCD", "GE"]),
    portfolios=portfolios,
    currencies=Set([USD, EUR]),
  )
end

function fake_stock_data(days=30, ref_date=today(), symbols=["AAPL", "IBM", "TSLA"])::Vector{AssetPrice}
  dates = filter(x -> is_weekday(x), [ref_date - Day(i) for i in reverse(0:(days - 1))])
  n = length(dates)
  map(s -> (symbol = repeat([s], n), date=dates, close=[100 + (rand(-8:10) * 0.1) for i in 1:n]), symbols) |>
    xs -> map(x -> [AssetPrice(; symbol = x.symbol[i], date = x.date[i], close = x.close[i]) for i in 1:n], xs) |>
    xs -> vcat(xs...)  
end 


function fake_price_data(
  days=30, ref_date=today(), symbols=["AAPL", "IBM", "TSLA"]
)::Vector{AssetPrice}
  dates = 
    [ref_date - Day(i) for i in reverse(0:(days - 1))] |>
    xs -> filter(x -> is_weekday(x), xs)
  data = AssetPrice[]
  for symbol in symbols
    append!(
      data, map(d -> AssetPrice(; symbol=symbol, date=d, close=100 + rand() * 10), dates)
    )
  end
  return data
end

function fake_exchange_data(
  days=30, ref_date=today(), symbols=["EUR/USD", "USD/CAD", "USD/JPY"]
)::Vector{ExchangeRate}
  dates = 
    [ref_date - Day(i) for i in reverse(0:(days - 1))] |>
    xs -> filter(x -> is_weekday(x), xs)
  data = ExchangeRate[]
  for symbol in symbols
    base, target = build_fx_pair(symbol)
    append!(
      data,
      map(
        d -> ExchangeRate(; base=base, target=target, date=d, rate=1 + rand() * 10), dates
      ),
    )
  end
  return data
end

function test_info_data()
  return [
    AssetInfo(;
      symbol="AAPL",
      currency="USD",
      name="Apple Inc.",
      type="EQUITY",
      exchange="NMS",
      country="United States",
      industry="Consumer Electronics",
      sector="Technology",
      timezone="America/New_York",
      employees=100000,
    ),
    AssetInfo(;
      symbol="MSFT",
      currency="USD",
      name="Microsoft Corporation",
      type="EQUITY",
      country="United States",
      industry="Software—Infrastructure",
      sector="Technology",
      timezone="America/New_York",
      employees=181000,
    ),
  ]
end