using Dates
using StonksTerminal: Config, StoreConfig, config_write, config_read
using StonksTerminal: FileFormat, arrow, PortfolioInfo, enum_from_string
using StonksTerminal: Currency, USD, EUR
using StonksTerminal: Transfer, TransferType, Deposit, Withdrawal
using StonksTerminal: Trade, TradeType, Buy, Sell

function load_testconfig()
  transfers = [
    Transfer(Date("2023-01-01"), Deposit, USD, 100.00),
    Transfer(Date("2023-02-01"), Deposit, USD, 150.00),
    Transfer(Date("2023-03-01"), Deposit, USD, 250.00),
    Transfer(Date("2023-04-01"), Withdrawal, USD, 200.00),
  ]

  trades = [
    Trade(Date("2023-01-02"), Buy, "AAPL", 3, 20.0, 1.00, USD, 1.00),
    Trade(Date("2023-01-02"), Buy, "MSFT", 8, 4.00, 1.00, USD, 1.00),
    Trade(Date("2023-01-30"), Buy, "AAPL", 1, 22.0, 1.00, USD, 1.00),
  ]

  portfolios = Dict("test" => PortfolioInfo(;
    name="test",
    currency=USD,
    transfers=transfers,
    trades=trades
  ))

  return Config(;
    data=StoreConfig(; dir="/tmp/StonksTerminal/data", format=arrow),
    watchlist=Set(["AAPL", "AMZN", "MSFT", "MCD", "GE"]),
    portfolios=portfolios,
    currencies=Set([USD, EUR])
  )
end