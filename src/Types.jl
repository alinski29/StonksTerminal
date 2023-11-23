module Types

using Dates
using NamedArrays
using Stonks

export Currency, USD, EUR, RON, CAD, GBP, CHF
export Trade, TradeType, Buy, Sell
export FileFormat, csv, arrow
export Transfer, TransferType, Deposit, Withdrawal
export StockRepository, PortfolioInfo, PortfolioMember, PortfolioDataset

@enum Currency USD EUR RON CAD GBP CHF
@enum TransferType Deposit Withdrawal
@enum TradeType Buy Sell
@enum FileFormat csv arrow

abstract type Operation end

@kwdef struct Transfer <: Operation
  date::Date
  type::TransferType
  currency::Currency
  proceeds::Float64
  function Transfer(
    date::Date,
    type::TransferType,
    currency::Currency,
    proceeds,
  )
    return new(
      date,
      type,
      currency,
      type === Deposit ? abs(proceeds) : -(abs(proceeds)),
    )
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
  exchange_rate::Union{Float64, Nothing}
  function Trade(
    date::Date,
    type::TradeType,
    symbol::String,
    shares::Int64,
    share_price::Float64,
    commission::Float64=0.0,
    currency::Currency=USD,
    exchange_rate::Union{Float64, Nothing}=nothing,
  )
    return new(
      date,
      type,
      symbol,
      type == Buy ? abs(shares) : -abs(shares),
      share_price,
      commission,
      currency,
      exchange_rate,
    )
  end
end

@kwdef mutable struct PortfolioInfo
  name::String
  currency::Currency
  transfers::Vector{Transfer}
  trades::Vector{Trade}
end

StockRepository = Dict{Date, Dict{String, AssetPrice}}

@kwdef struct PortfolioMember
  info::Union{AssetInfo, Missing}
  trades::Vector{Trade}
end

@kwdef mutable struct PortfolioDataset
  name::String
  members::Dict{String, PortfolioMember}
  close::NamedMatrix{Float64}
  shares_bought::NamedMatrix{Int}
  shares_bought_price::NamedMatrix{Float64}
  shares_sold::NamedMatrix{Int}
  shares_sold_price::NamedMatrix{Float64}
  avg_price::NamedMatrix{Float64}
  commissions::NamedMatrix{Float64}
  transfers::NamedMatrix{Float64}
end

end
