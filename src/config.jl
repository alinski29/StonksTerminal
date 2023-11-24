using Comonicon
using JSON3
using StonksTerminal.Types
using StonksTerminal: collect_user_input

export Config, config_read, config_write

DIR_NAME = "stonks-terminal"
APP_DIR = (
  if !ismissing(get(ENV, "XDG_DATA_HOME", missing))
    joinpath(ENV["XDG_DATA_HOME"], DIR_NAME)
  elseif isdir(joinpath(homedir(), ".local/share"))
    joinpath(homedir(), ".local/share", DIR_NAME)
  else
    joinpath(homedir(), ".$(DIR_NAME)")
  end
)
DATA_DIR = joinpath(APP_DIR, "data")
CFG_PATH = joinpath(APP_DIR, "config.json")

@cast function config()
  !isdir(APP_DIR) && mkpath(APP_DIR)
  if !isfile(CFG_PATH)
    return config_init()
  end
  @info("Configuration file already exists. Override? y/n;")
  if lowercase(strip(readline())) == "y"
    config_init()
  end
end

@kwdef mutable struct StoreConfig
  dir::String
  format::FileFormat
end

@kwdef mutable struct Config
  data::StoreConfig
  watchlist::Set{String}
  portfolios::Dict{String, PortfolioInfo}
  currencies::Set{Currency}
end

function config_read(path::String=CFG_PATH)::Config
  JSON3.read(read(path, String), Config)
end

function config_write(cfg::Config, path::String=CFG_PATH)
  open(path, "w") do io
    JSON3.pretty(io, cfg)
  end
end

function config_init()
  @info("Initializing config file \n")

  wl = collect_user_input(
    "Enter comma-delimited stock tickers to populate the database, e.g.: AAPL,MSFT,IBM",
    Vector{String},
  )

  currencies = collect_user_input(
    "Enter comman-delimited currencies you want to use. If empty, it will default to USD",
    Set{Currency},
  )

  portfolios = (
    if collect_user_input("Would you like to add a portfolio: y/n ?", Bool)
      name = collect_user_input("Portfolio name", String)
      currency = collect_user_input("Portfolio currency", Currency)
      Dict(name => PortfolioInfo(; name=name, currency=currency, transfers=Transfer[], trades=Trade[]))
    else
      Dict{String, PortfolioInfo}()
    end
  )

  cfg = Config(;
    data=StoreConfig(; dir=DATA_DIR, format=arrow),
    watchlist=wl,
    portfolios=portfolios,
    currencies=currencies,
  )

  config_write(cfg)
  @info("Configuration succesfully written to $(CFG_PATH) \n")
end
