module StonksTerminal

using ArgParse
using Stonks

include("Types.jl")
include("helpers.jl")
include("charts.jl")

include("config.jl")
"""
Initialize configuration
"""

include("Store.jl")
"""
Module for interacting with the data store
"""

include("Watchlist.jl")
"""
Module for managing your watchlist
"""

include("processing.jl")

include("Portfolio.jl")
"""
Module for interacting with portfolio: adding transfers & trades
"""

# StonksTerminal price "AAPL,MSFT,IBM" --interval "7d"
"""
Get stock price data
"""
function price(symbols::String; interval="1d", from=missing, to=missing)
  @info("symbols: $symbols; interval: $interval: from: $from; to: $to")
end

function parse_command()
  s = ArgParseSettings()

  @add_arg_table s begin
    "store"
    help = "Store command"
    action = :command
    "portfolio"
    help = "Portfolio command"
    action = :command
    "watchlist"
    help = "Watchlist command"
    action = :command
  end

  @add_arg_table s["store"] begin
    "update"
    help = "a positional argument"
    action = :command
    "--financials"
    help = "Update financials"
    action = :store_true
    "--info"
    help = "Update info"
    action = :store_true
  end

  @add_arg_table s["portfolio"] begin
    "status"
    help = "Print a summary table of the portfolio"
    action = :command
    "deposit"
    help = "Deposit funds in a portfolio"
    action = :command
    "--name"
    help = "Portfolio name. Skip it if you only have one portfolio"
    arg_type = String
    required = false
  end

  @add_arg_table s["watchlist"] begin
    "add"
    help = "Add a comma separated list of tickers to the watchlist"
    # action = :command
    "remove"
    help = "Remove a comma separated list of tickers to the watchlist"
    # action = :command
    # "--tickers"
    #   help = "Comma separated list of tickers"
    #   arg_type = String
    #   required = true
  end

  return parse_args(s)
end

"""
Stonks command line interface
"""
function julia_main()::Cint
  args = parse_command()

  command = args["%COMMAND%"]

  if command == "store"
    subcommand = args[command]["%COMMAND%"]
    kwargs = Dict((Symbol(k), v) for (k, v) in args[command] if !(k in [subcommand, "%COMMAND%"]))
    if subcommand == "update"
      Store.update(; kwargs...)
    end
  elseif command == "portfolio"
    subcommand = args[command]["%COMMAND%"]
    kwargs = Dict((Symbol(k), v) for (k, v) in args[command] if !(k in [subcommand, "%COMMAND%"]))
    if subcommand == "deposit"
      Portfolio.deposit(; kwargs...)
    elseif subcommand == "withdraw"
      Portfolio.withdraw(; kwargs...)
    elseif subcommand == "buy"
      Portfolio.buy(; kwargs...)
    elseif subcommand == "sell"
      Portfolio.sell(; kwargs...)
    elseif subcommand == "status"
      Portfolio.status(; kwargs...)
    else
      @error("Don't know how to handle subcommand: $subcommand")
    end
  elseif command == "watchlist"
    # TODO This can be Nothing, handle the case
    kwargs = Dict((k, v) for (k, v) in args[command] if String(k) != String(v))
    subcommand = first(kwargs)[1]
    if subcommand == "add"
      Watchlist.add(subcommand)
    elseif subcommand == "remove"
      Watchlist.remove(kwargs[subcommand])
    end
  else
    @error("Don't know how to handle command: $command")
  end

  return 0
end

end
