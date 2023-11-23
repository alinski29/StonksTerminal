module Portfolio

using UnicodePlots
using Dates
using PrettyTables
using StonksTerminal.Types: Deposit, Withdrawal, Buy, Sell
using StonksTerminal.Types

include("portfolio/cli_actions.jl")
include("portfolio/processing.jl")

@cast deposit(; name::Union{String, Nothing}=nothing) = transfer_funds(; type=Deposit, name=name)

@cast withdraw(; name::Union{String, Nothing}=nothing) = transfer_funds(; type=Withdrawal, name=name)

@cast buy(; name::Union{String, Nothing}=nothing) = add_trade(Buy, name)

@cast sell(; name::Union{String, Nothing}=nothing) = add_trade(Sell, name)

@cast function status(; 
  name::Union{String, Nothing}=nothing,
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
  days_delta::Int=360
)
	cfg = config_read()
	port = get_portfolio(cfg, name)
	repo = load_repository(cfg)
	ds = get_portfolio_dataset(repo, port)

	print_summary_table(ds)
end

end
