
parse_string(input::String)::String = strip(input)
parse_list(input::String)::Vector{String} = split(input, ",") |> xs -> map(strip, xs) |> unique
print_enum_values(T::Type)::String = join([string(x) for x in instances(T)], ", ")
enum_from_string(in::String, T::Type)::T = first([x for x in instances(T) if str(x) == in])

function collect_user_input(msg::String, ::Type{T})::T where {T<:Enum}
  @info(msg * " Choices: " * print_enum_values(T) * "\n")
  @info("::Type{T}")
  readline() |> parse_string |> x -> enum_from_string(x, T)
end

function collect_user_input(msg::String, ::Type{Set{T}})::Set{T} where {T<:Enum}
  @info(msg * " Choices: " * print_enum_values(T) * "\n")
  @info("::Type{Set{T}}")
  readline() |> parse_list |> xs -> map(x -> enum_from_string(x, T), xs) |> Set
end

function collect_user_input(msg::String, ::Type{Vector{String}})::Vector{String}
  @info("a list")
  @info(msg)
  readline() |> parse_list
end

function collect_user_input(msg::String, ::Type{T})::T where {T}
  @info(msg)
  maybe_res = tryparse(T, readline() |> parse_string)
  if isnothing(maybe_res)
    @warn("Received unexpected value, please try again. \n")
    collect_user_input(msg, T)
  end
end

function collect_user_input(msg::String, ::Type{Bool})::Bool
  @info(msg * "\n")
  parse_string(readline()) == "y"
end