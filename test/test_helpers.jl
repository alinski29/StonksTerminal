using Dates
using NamedArrays
using Test

using StonksTerminal: format_number, parse_pretty_number, allocate_matrix, expand_matrix, ffill, fill_missing

@testset "Utilities" begin

  @testset "format_number" begin
    @test format_number(1000) == "1,000"
    @test format_number(3.14159) == "3.14"
    @test format_number(-12345.6789) == "-12,345.68"
    @test format_number(0) == "0"
    @test format_number(999999999999999) == "999,999,999,999,999"
    @test format_number(42.0) == "42.00"
    @test format_number(4.999) == "5.00"
    @test format_number(4.001) == "4.00"
  end

  @testset "parse_pretty_number" begin
    @test parse_pretty_number(Float64, "1,000") == 1000
    @test parse_pretty_number(Float64, "3.14") == 3.14
    @test parse_pretty_number(Float64, "-12,345.68") == -12345.68
    @test parse_pretty_number(Float64, "0") == 0
    @test parse_pretty_number(Float64, "999,999,999,999,999") == 999999999999999
    @test parse_pretty_number(Float64, "42.00") == 42.0
    @test parse_pretty_number(Float64, "5.00") == 5.0
  end

  @testset "allocate_matrix" begin
    mat = allocate_matrix(Int64, ["r1", "r2", "r3"], ["c1", "c2", "c3"])
    @test size(mat) == (3, 3)
    @test names(mat) == [["r1", "r2", "r3"], ["c1", "c2", "c3"]]
    @test typeof(mat) <: NamedMatrix{Int64}
    @test all(map(x -> x == 0, mat))

    mat = allocate_matrix(Union{Int, Missing}, ["r1", "r2", "r3"], ["c1", "c2"])
    @test size(mat) == (3, 2)
    @test names(mat) == [["r1", "r2", "r3"], ["c1", "c2"]]
    @test typeof(mat) <: NamedMatrix{Union{Missing, Int}}
    @test all(map(ismissing, mat))
  end

  @testset "expand matrix" begin 
    mat_large = allocate_matrix(Int64, ["r1", "r2", "r3", "r4"], ["c1", "c2"])
    mat_short = allocate_matrix(Int64, ["r1", "r3"], ["c1", "c2"])
    mat_short[:,:] .= 1

    row_names, col_names = names(mat_large)
    mat_expanded = expand_matrix(mat_short, row_names, col_names)
    @test names(mat_expanded) == [row_names, col_names]
    @test size(mat_expanded) == size(mat_large)

    @test mat_expanded["r1", "c1"] == 1
    @test mat_expanded["r1", "c2"] == 1
    @test mat_expanded["r3", "c1"] == 1
    @test mat_expanded["r3", "c2"] == 1
  end

  @testset "ffill" begin 
    mat = allocate_matrix(Union{Int, Missing}, ["r1", "r2", "r3"], ["c1", "c2"])
    mat["r1", "c1"] .= 1
    mat["r2", "c2"] .= 1

    mat_ffill = ffill(mat)
    @test all(x -> x == 1, mat_ffill[:, "c1"])
    @test mat_ffill["r1", "c2"] === missing
    @test mat_ffill[["r2", "r3"], "c2"].array == [1, 1]

    mat = allocate_matrix(Int64, ["r1", "r2", "r3"], ["c1", "c2"])
    mat["r1", "c1"] .= 1
    mat["r2", "c2"] .= 1

    mat_ffill = ffill(mat)
    @test mat_ffill[:, "c1"].array == [1, 0, 0]
    @test mat_ffill[:, "c2"].array == [0, 1, 0]
  end

  @testset "fill_missing" begin
    mat = allocate_matrix(Union{Int, Missing}, ["r1", "r2", "r3"], ["c1", "c2"]) |> 
      xs -> fill_missing(xs, 42)
    @test all(x -> x == 42, mat)
  end

end