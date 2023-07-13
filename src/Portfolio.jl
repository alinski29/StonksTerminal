module Portfolio

include("portfolio/cli_actions.jl")
include("portfolio/processing.jl")

@cast deposit(; name::Union{String,Nothing}=nothing) = transfer_funds(; type=Deposit, name=name)
@cast withdraw(; name::Union{String,Nothing}=nothing) = transfer_funds(; type=Withdrawal, name=name)
@cast buy(; name::Union{String,Nothing}=nothing) = add_trade(Buy, name)
@cast sell(; name::Union{String,Nothing}=nothing) = add_trade(Sell, name)
@cast function status(; name::Union{String,Nothing}=nothing)
  cfg = config_read()
  port = get_portfolio(cfg, name)
  holdings = compute_portfolio_holdings(port.trades)
  foreach(println, holdings)
end

end
