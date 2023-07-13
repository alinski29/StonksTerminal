using Dates

@enum Currency USD EUR RON CAD GBP CHF
@enum TransferType Deposit Withdrawal
@enum TradeType Buy Sell

parse_list(input::String)::Vector{String} = split(input, ",") |> x -> map(strip, x) |> unique
parse_string(input::String)::String = strip(input)
print_enum_values(::Type)::String = join([string(x) for x in instances(Currency)], ", ")

enum_from_string(in::String, T::Type)::T = Dict(string(x) => x for x in instances(T))[in]

abstract type Operation end

@kwdef struct Transfer <: Operation
  date::Date
  type::TransferType
  currency::Currency
  proceeds::Float64
  exchange_rate::Union{Float64,Nothing}
  function Transfer(date::Date, type::TransferType, currency::Currency, proceeds, exchange_rate::Union{Float64,Nothing}=nothing)
    return new(date, type, currency, type === Deposit ? abs(proceeds) : -(abs(proceeds)), exchange_rate)
  end
end

struct Trade <: Operation
  date::Date
  type::TradeType
  symbol::String
  shares::Int64
  share_price::Float64
  commission::Float64
  currency::Currency
  proceeds::Float64
  exchange_rate::Union{Float64,Nothing}
  function Trade(
    date::Date,
    type::TradeType,
    symbol::String,
    shares::Int64,
    share_price::Float64,
    commission::Float64=0.0,
    currency::Currency=USD,
    proceeds::Float64=((type == Sell ? abs(shares) : -shares) * share_price - abs(commission)) * (isnothing(exchange_rate) ? 1.00 : exchange_rate),
    exchange_rate::Union{Float64,Nothing}=nothing
  )
    return new(date, type, symbol, shares, share_price, commission, currency, proceeds, exchange_rate)
  end
end

@kwdef struct FinancialAsset
  symbol::String
  trades::Vector{Trade}
  shares::Int64
  date_first_trade::Date
  avg_price::Float64
end

@kwdef mutable struct PortfolioInfo
  name::String
  currency::Currency
  transfers::Vector{Transfer}
  trades::Vector{Trade}
end

# a single record, but with some cummulative computations
@kwdef mutable struct StockRecord
  symbol::String
  date::Date
  close::Float64
  shares::Int64 # cummulative
  buy::Float64 # cummulative
  sell::Float64 # cummulative
end

StockRepository = Dict{Date,Dict{String,StockRecord}}

@kwdef struct PortfolioMember
  info::Union{AssetInfo,Missing}
  trades::Vector{Trade}
end

# store data for a single asset - to be used for plotting
@kwdef mutable struct AssetProfile <: AbstractStonksRecord
  symbol::String
  dates::Vector{Date}
  closes::Vector{Float64}
  trades::Vector{Trade}
  shares::Vector{Int64}
  buys::Vector{Float64}
  sells::Vector{Float64}
  info::Union{AssetInfo,Missing}
end

# similar to AssetProfile, but used for a Portfolio
@kwdef mutable struct PortfolioProfile
  name::String
  dates::Vector{Date}
  market_value::Vector{Float64}
  # trades::Vector{Trade} - to decide if should be kept here or in members or method
  cost::Vector{Float64} # - same as buys from {AssetProfile}
  realized_profit::Vector{Float64}
  unrealized_profit::Vector{Float64}
  weights::Dict{Date,Vector{Tuple{String,Float64}}}
  members::Dict{String,PortfolioMember}
end
