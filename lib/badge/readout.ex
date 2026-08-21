defmodule Badge.Readout do
  @moduledoc """
  Label and value rows, the shared shape of the status sub-pages.

  Positions are threaded by hand rather than with `Enum.with_index/1`, which
  AtomVM does not have.
  """

  alias Badge.Theme

  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @label_x 8
  @value_x 120
  @pitch 18

  @doc "Vertical gap between rows."
  def pitch, do: @pitch

  @doc "Display items for a list of `{label, value}` pairs, first row at `top`."
  @spec rows([{binary, binary}], integer) :: [tuple]
  def rows(pairs, top), do: rows(pairs, top, [])

  defp rows([], _y, acc), do: :lists.reverse(acc)

  defp rows([{label, value} | rest], y, acc) do
    label_item = {:text, @label_x, y, :default16px, @dim, @bg, label}
    value_item = {:text, @value_x, y, :default16px, @fg, @bg, value}

    rows(rest, y + @pitch, [value_item, label_item | acc])
  end
end
