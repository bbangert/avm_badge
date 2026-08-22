defmodule Badge.Text do
  @moduledoc """
  Wrapping for fixed-width text.

  Pure, and hand-rolled: AtomVM has no `String` module at runtime, so
  binaries are walked a byte at a time.
  """

  @doc """
  Breaks `text` into lines of at most `columns` characters.

  Breaks at the last space that fits, so words stay whole. A word longer
  than a line has nowhere to break, so it is split and a dash joins it to
  the line below. The dash costs a column, so the break comes one character
  early.
  """
  @spec wrap(binary, pos_integer) :: [binary]
  def wrap(text, columns) when columns < 1, do: [text]
  def wrap(<<>>, _columns), do: [""]
  def wrap(text, columns), do: wrap(text, columns, [])

  defp wrap(text, columns, acc) when byte_size(text) <= columns do
    :lists.reverse([text | acc])
  end

  defp wrap(text, columns, acc) do
    case break_at(text, columns) do
      0 -> wrap(rest(text, kept(columns)), columns, [dashed(text, columns) | acc])
      at -> wrap(rest(text, at + 1), columns, [trim(:binary.part(text, 0, at)) | acc])
    end
  end

  # No space to break on, so the word is split and dashed onto the next line.
  defp dashed(text, columns), do: :binary.part(text, 0, kept(columns)) <> "-"

  # One column goes to the dash, but a single column line would never advance.
  defp kept(1), do: 1
  defp kept(columns), do: columns - 1

  # The last space at or before the column limit, or 0 when there is none.
  defp break_at(text, columns), do: break_at(text, columns, 0, 0)

  defp break_at(_text, columns, position, last) when position > columns, do: last

  defp break_at(text, columns, position, last) do
    case :binary.at(text, position) do
      ?\s -> break_at(text, columns, position + 1, position)
      _other -> break_at(text, columns, position + 1, last)
    end
  end

  defp rest(text, from), do: :binary.part(text, from, byte_size(text) - from)

  # A run of spaces leaves them on the end of the line, which would shift centred text.
  defp trim(<<>>), do: <<>>

  defp trim(line) do
    case :binary.at(line, byte_size(line) - 1) do
      ?\s -> trim(:binary.part(line, 0, byte_size(line) - 1))
      _other -> line
    end
  end
end
