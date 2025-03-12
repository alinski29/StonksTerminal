module Watchlist

using StonksTerminal: parse_list, config_read, config_write

function add(items::String)
  cfg = config_read()
  symbols = parse_list(items)

  if length(symbols) > 0
    @info("Adding $(size(symbols)) tickers to watchlist")
    cfg.watchlist = unique(union(cfg.watchlist, symbols))
  end

  config_write(cfg)
end

function remove(items::String)
  cfg = config_read()
  symbols = parse_list(items)

  if length(symbols) > 0
    @info("Removing $(size(symbols)) tickers from watchlist")
    cfg.watchlist = [item for item in cfg.watchlist if !in(item, symbols)]
  end

  config_write(cfg)
end

end
