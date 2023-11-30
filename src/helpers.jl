using Dates
using NamedArrays
using Statistics

parse_string(input::String)::String = strip(input)

parse_list(input::String)::Vector{String} = split(input, ",") |> xs -> map(strip, xs) |> unique

print_enum_values(T::Type)::String = join([string(x) for x in instances(T)], ", ")

enum_from_string(in::String, T::Type)::T where {T} = first([x for x in instances(T) if string(x) == in])

function collect_user_input(msg::String, ::Type{T})::T where {T <: Enum}
  @info(msg * " Choices: " * print_enum_values(T) * "\n")
  readline() |> parse_string |> x -> enum_from_string(x, T)
end

function collect_user_input(msg::String, ::Type{Set{T}})::Set{T} where {T <: Enum}
  @info(msg * " Choices: " * print_enum_values(T) * "\n")
  readline() |> parse_list |> xs -> map(x -> enum_from_string(x, T), xs) |> Set
end

function collect_user_input(msg::String, ::Type{Vector{String}})::Vector{String}
  @info(msg)
  readline() |> parse_list
end

function collect_user_input(msg::String, ::Type{Bool})::Bool
  @info(msg * "\n")
  readline() |> parse_string |> x -> x in ["y", "1", "true"]
end

function collect_user_input(msg::String, ::Type{String})::String
  @info(msg * "\n")
  readline() |> parse_string
end

function collect_user_input(msg::String, ::Type{T})::T where {T}
  @info(msg)
  input = readline() |> parse_string
  maybe_res = tryparse(T, input)
  if isnothing(maybe_res)
    @warn("Received unexpected value, please try again. \n")
    collect_user_input(msg, T)
  end

  return maybe_res
end

function format_number(num::Number; decimals::Int=2)::String
  digits, decimals = (
    if typeof(num) <: AbstractFloat
      str = string(round(num; digits=decimals))
      splits = split(str, "."; limit=2)
      splits[1], lpad(splits[2], 2, "0")
    else
      string(num), ""
    end
  )
  digits_friendly = replace(digits, r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => ",")
  isempty(decimals) ? digits_friendly : "$digits_friendly.$decimals"
end

function parse_pretty_number(::Type{T}, num::String) where {T <: Number}
  tryparse(T, replace(num, "," => ""))
end

function map_dates_to_indices(
  mat::NamedMatrix,
  from::Union{Date, Nothing}=nothing,
  to::Union{Date, Nothing}=nothing,
)
  nrows, _     = size(mat)
  row_names, _ = names(mat)
  i_start      = !isnothing(from) ? findfirst(d -> d >= Date(from), map(Date, row_names)) : 1
  i_end        = !isnothing(to) ? findfirst(d -> d >= Date(to), map(Date, row_names)) : nrows

  return i_start:i_end
end

function ffill(v::Union{Vector{Union{T, Missing}}, Vector{T}}) where {T}
  v[accumulate(max, [i * !ismissing(v[i]) for i in eachindex(v)]; init=1)]
end

function ffill(mat::Union{NamedMatrix{T}, NamedMatrix{Union{T, Missing}}}) where {T}
  for (col, _) in mat.dicts[2]
    mat[:, col] = ffill(mat[:, col].array)
  end

  return mat
end

function fill_missing(mat::NamedMatrix{Union{T, Missing}}, default::T) where T <: Number
  res = allocate_matrix(typeof(default), mat.dicts[1].keys, mat.dicts[2].keys)
  _, m = size(res)
  for j in 1:m
    if typeof(default) <: Int
      res[:, j] .= map(x -> Int(!ismissing(x) ? x : default), mat[:, j])
    else
      res[:, j] .= map(x -> Float64(!ismissing(x) ? x : default), mat[:, j])
    end
  end
  return res
end

function expand_matrix(
  mat::Union{NamedMatrix{Union{T, Missing}}, NamedMatrix{T}},
  row_names::Vector{String},
  col_names::Vector{String},
) where {T <: Number}
  # get_type_param(::NamedMatrix{T}) where {T} = T
  new_mat = allocate_matrix(eltype(mat), row_names, col_names)
  row_names_old, col_names_old = names(mat)
  for row_name in intersect(row_names_old, row_names)
    for col_name in intersect(col_names_old, col_names)
      new_mat[row_name, col_name] = mat[row_name, col_name]
    end
  end

  return new_mat
end

function allocate_matrix(T::Type, row_names::Vector{String}, column_names::Vector{String})::NamedMatrix
  n, m = length(row_names), length(column_names)
  matrix = (
    if T <: Number
      NamedArray(zeros(T, n, m))
    else
      NamedArray(Matrix{T}(undef, n, m))
    end
  )
  setnames!(matrix, row_names, 1)
  setnames!(matrix, column_names, 2)
  setdimnames!(matrix, ["Date", "Symbol"])
  return matrix
end

function get_basic_stats(data::AbstractVector{T}) where {T <: Number}
  return (min=minimum(data), max=maximum(data), mean=mean(data), median=median(data), std=std(data))
end
