using Dates
using NamedArrays
using PrettyTables
using Statistics

using StonksTerminal: format_number

function print_correlation_matrix(mat::NamedMatrix; empty_diagonal::Bool=false)
  row_names, _ = names(mat)
  mat_display = map(format_number, mat)

  # fill lower diagonal of mat_display with missing
  if empty_diagonal
    n = size(mat_display, 1)
    for i in 2:n
      for j in 1:(i - 1)
        mat_display[i, j] = ""
      end
    end
  end

  mat_display = hcat(row_names, mat_display)
  header = vcat("Symbol", row_names)

  hl_symbol_col = Highlighter((data, i, j) -> j == 1, crayon"bold")
  hl_diagonal = Highlighter((data, i, j) -> i == j - 1, crayon"bold bg:dark_gray")
  hl_red = Highlighter(
    (data, i, j) ->
      j > 1 && data[i, j] != "" && parse_pretty_number(Float64, data[i, j]) > 0.70 && data[i, j] != "1.0",
    crayon"red",
  )

  pretty_table(mat_display; header=header, highlighters=(hl_symbol_col, hl_diagonal, hl_red))
end
