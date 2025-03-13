using Test

@testset "StonksTerminal" begin
  include("test_config.jl")
  include("test_helpers.jl")
  include("test_portfolio.jl")
end
