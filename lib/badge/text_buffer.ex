defmodule Badge.TextBuffer do
  @moduledoc """
  A fixed-geometry character grid with an append-only cursor.

  AtomVM has no `String` module — only the `String.Chars` protocol — and
  AtomGL's text primitive accepts either charlists or binaries directly.

  The current line, `cur`, accumulates as a reversed charlist for O(1)
  insertion. Completed lines in `done` are converted to binaries once, when
  a line is finished by `newline/1`. `done` is at most `rows` long.

  State is a plain map, not a struct.
  """

  @tab_width 4

  @doc "Creates an empty buffer `cols` wide and `rows` tall."
  def new(cols, rows) do
    %{cols: cols, rows: rows, done: [], cur: [], col: 0, row: 0}
  end

  @doc "Inserts one character, wrapping to the next row at the right edge."
  def insert(%{col: col, cols: cols} = buffer, char) when col >= cols do
    buffer |> newline() |> insert(char)
  end

  def insert(buffer, char) do
    %{buffer | cur: [char | buffer.cur], col: buffer.col + 1}
  end

  @doc "Ends the current line and moves to column zero of the next row."
  def newline(buffer) do
    done = buffer.done ++ [:erlang.list_to_binary(:lists.reverse(buffer.cur))]

    scroll(%{buffer | done: done, cur: [], col: 0, row: buffer.row + 1})
  end

  @doc """
  Deletes the character before the cursor.

  At column zero this moves to the end of the previous line without deleting
  anything — the next backspace then removes that line's last character. It
  never un-scrolls: lines dropped off the top are gone.
  """
  def backspace(%{cur: [_last | rest]} = buffer) do
    %{buffer | cur: rest, col: buffer.col - 1}
  end

  def backspace(%{cur: [], row: row} = buffer) when row > 0 do
    {init, last} = split_last(buffer.done)
    cur = :lists.reverse(:erlang.binary_to_list(last))

    %{buffer | done: init, cur: cur, col: length(cur), row: row - 1}
  end

  def backspace(buffer), do: buffer

  @doc "Inserts spaces up to the next multiple of four columns."
  def tab(buffer) do
    insert_spaces(buffer, @tab_width - rem(buffer.col, @tab_width))
  end

  @doc "Returns exactly `rows` lines, oldest first, padded with empty lines."
  def lines(buffer) do
    all = buffer.done ++ [:erlang.list_to_binary(:lists.reverse(buffer.cur))]

    pad(all, buffer.rows - length(all))
  end

  @doc "Returns the cursor as `{col, row}`."
  def cursor(buffer), do: {buffer.col, buffer.row}

  # Drops the oldest line and shifts up once the cursor passes the last row.
  defp scroll(%{row: row, rows: rows} = buffer) when row >= rows do
    [_oldest | rest] = buffer.done

    %{buffer | done: rest, row: row - 1}
  end

  defp scroll(buffer), do: buffer

  defp insert_spaces(buffer, 0), do: buffer

  defp insert_spaces(buffer, n) do
    buffer |> insert(?\s) |> insert_spaces(n - 1)
  end

  defp split_last(list) do
    [last | reversed_init] = :lists.reverse(list)

    {:lists.reverse(reversed_init), last}
  end

  defp pad(all, n) when n <= 0, do: all
  defp pad(all, n), do: pad(all ++ [<<>>], n - 1)
end
