using JSON3
using Comonicon
using StonksTerminal: Currency, enum_from_string, parse_list, parse_string, print_enum_values

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

@enum FileFormat csv arrow

@kwdef mutable struct StoreConfig
  dir::String
  format::FileFormat
end

@kwdef mutable struct Config
  data::StoreConfig
  watchlist::Set{String}
  portfolios::Dict{String,PortfolioInfo}
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

  @info("Enter comma-delimited stock tickers to populate the database, e.g.: AAPL,MSFT,IBM \n")
  input = readline()
  if length(input) < 2
    log.warn("Input cannot be empty. Please try again")
    config_init()
  end
  wl = parse_list(input)

  @info("Would you like to add a portfolio: y/n ?")
  portfolios = (
    if parse_string(readline()) == "y"
      @info("Portfolio name: \n")
      name = parse_string(readline())
      @info("Portfolio currency: Choose between: $(print_enum_values(Currency))")
      currency = enum_from_string(parse_string(readline()), Currency)
      Dict(name => PortfolioInfo(; name=name, currency=currency, transfers=Transfer[], trades=Trade[], holdings=FinancialAsset[]))
    else
      Dict{String,PortfolioInfo}()
    end
  )

  cfg = Config(;
    data=StoreConfig(; dir=DATA_DIR, format=arrow),
    watchlist=wl,
    portfolios=portfolios
  )
  config_write(cfg)
  @info("Configuration succesfully written to $(CFG_PATH) \n")

end

