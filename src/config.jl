using JSON3
using StonksTerminal.Types
using StonksTerminal: collect_user_input

export Config, config_read, config_write

APP_NAME = "stonks"

function get_app_path()::String
  return joinpath(get(ENV, "XDG_DATA_HOME", joinpath(homedir(), ".local/share")), APP_NAME)
end

function get_config_path()::String
  return get(ENV, "STONKS_CONFIG_PATH", joinpath(get_app_path(), "config.json"))
end

function get_data_path()::String
  return get(ENV, "STONKS_DATA_PATH", joinpath(get_app_path(), "data"))
end

function config()
  config_path = get_config_path()
  !isdir(dirname(config_path)) && mkpath(dirname(config_path))
  if !isfile(config_path)
    return config_init()
  end
  @info("Configuration file already exists. Override? y/n;")
  if lowercase(strip(readline())) == "y"
    config_init()
  end
end

@kwdef mutable struct StoreConfig
  dir::Union{String, Nothing} = nothing
  format::FileFormat
end

@kwdef mutable struct Config
  data::StoreConfig
  watchlist::Set{String}
  portfolios::Dict{String, PortfolioInfo}
  currencies::Set{Currency}
end

function config_read(path::Union{String, Nothing}=nothing)::Config
  cfg_path = isnothing(path) ? get_config_path() : path
  cfg = JSON3.read(read(cfg_path, String), Config)
  if isnothing(cfg.data.dir)
    cfg.data.dir = get_data_path()
  end

  return cfg
end

function config_write(cfg::Config, path::Union{String, Nothing}=nothing)
  cfg_path = isnothing(path) ? get_config_path() : path
  open(cfg_path, "w") do io
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
    data=StoreConfig(; dir=get_data_path(), format=arrow),
    watchlist=wl,
    portfolios=portfolios,
    currencies=currencies,
  )

  config_write(cfg)
  @info("Configuration succesfully written to $(get_config_path()) \n")
end
