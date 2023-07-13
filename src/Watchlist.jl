module Watchlist

using Comonicon
using StonksTerminal: config_read

@cast add(item::String) = watchlist(; add=item) 
@cast remove(item::String) = watchlist(; remove=item) 

function watchlist(; add::String="", remove::String="")
  cfg = config_read()

  if length(add) > 0
    toAdd = parse_list(add)
    @info("Adding $(size(toAdd)) tickers to watchlist")
    cfg.watchlist = unique(union(cfg.watchlist, toAdd))
  end

  if length(remove) > 0
    toRm = parse_list(remove)
    @info("Removing $(size(toRm)) tickers from watchlist")
    cfg.watchlist = [item for item in cfg.watchlist if !in(item, toRm)]
  end

  if length(add) > 0 || length(remove) > 0
    config_write(cfg)
  end
end

end


