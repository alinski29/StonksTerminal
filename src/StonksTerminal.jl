module StonksTerminal

using Comonicon
using Stonks

include("Types.jl")
include("helpers.jl")

include("config.jl")
"""
Initialize configuration
"""

include("Store.jl")
"""
Module for interacting with the data store
"""
@cast Store

include("Watchlist.jl")
"""
Module for managing your watchlist
"""
@cast Watchlist

include("Portfolio.jl")
"""
Module for interacting with portfolio: adding transfers & trades
"""
@cast Portfolio

# StonksTerminal price "AAPL,MSFT,IBM" --interval "7d"
"""
Get stock price data
"""
@cast function price(symbols::String; interval="1d", from=missing, to=missing)
  @info("symbols: $symbols; interval: $interval: from: $from; to: $to")
end

"""
Stonks command line interface
"""
@main

end
