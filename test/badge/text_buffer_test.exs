defmodule Badge.TextBufferTest do
  use ExUnit.Case, async: true

  alias Badge.TextBuffer

  defp type(buffer, chars) do
    Enum.reduce(chars, buffer, fn c, acc -> TextBuffer.insert(acc, c) end)
  end

  describe "new/2" do
    test "starts empty with the cursor at the origin" do
      buffer = TextBuffer.new(5, 3)
      assert TextBuffer.cursor(buffer) == {0, 0}
      assert TextBuffer.lines(buffer) == ["", "", ""]
    end
  end

  describe "insert/2" do
    test "appends characters to the current line" do
      buffer = TextBuffer.new(5, 3) |> type(~c"abc")
      assert TextBuffer.lines(buffer) == ["abc", "", ""]
      assert TextBuffer.cursor(buffer) == {3, 0}
    end

    test "wraps to the next row at the right edge" do
      buffer = TextBuffer.new(5, 3) |> type(~c"abcdef")
      assert TextBuffer.lines(buffer) == ["abcde", "f", ""]
      assert TextBuffer.cursor(buffer) == {1, 1}
    end
  end

  describe "newline/1" do
    test "moves to column zero of the next row" do
      buffer = TextBuffer.new(5, 3) |> type(~c"ab") |> TextBuffer.newline() |> type(~c"c")
      assert TextBuffer.lines(buffer) == ["ab", "c", ""]
      assert TextBuffer.cursor(buffer) == {1, 1}
    end
  end

  describe "scrolling" do
    test "drops the oldest line when advancing past the last row" do
      buffer =
        TextBuffer.new(5, 3)
        |> type(~c"one")
        |> TextBuffer.newline()
        |> type(~c"two")
        |> TextBuffer.newline()
        |> type(~c"three")
        |> TextBuffer.newline()
        |> type(~c"four")

      assert TextBuffer.lines(buffer) == ["two", "three", "four"]
      assert TextBuffer.cursor(buffer) == {4, 2}
    end

    test "wrapping also scrolls once the grid is full" do
      buffer = TextBuffer.new(2, 2) |> type(~c"abcdef")
      assert TextBuffer.lines(buffer) == ["cd", "ef"]
      assert TextBuffer.cursor(buffer) == {2, 1}
    end
  end

  describe "backspace/1" do
    test "deletes the previous character mid-line" do
      buffer = TextBuffer.new(5, 3) |> type(~c"abc") |> TextBuffer.backspace()
      assert TextBuffer.lines(buffer) == ["ab", "", ""]
      assert TextBuffer.cursor(buffer) == {2, 0}
    end

    test "at column zero moves to the end of the previous line without deleting" do
      buffer =
        TextBuffer.new(5, 3)
        |> type(~c"ab")
        |> TextBuffer.newline()
        |> TextBuffer.backspace()

      assert TextBuffer.lines(buffer) == ["ab", "", ""]
      assert TextBuffer.cursor(buffer) == {2, 0}
    end

    test "a second backspace then deletes that line's last character" do
      buffer =
        TextBuffer.new(5, 3)
        |> type(~c"ab")
        |> TextBuffer.newline()
        |> TextBuffer.backspace()
        |> TextBuffer.backspace()

      assert TextBuffer.lines(buffer) == ["a", "", ""]
      assert TextBuffer.cursor(buffer) == {1, 0}
    end

    test "is a no-op at the very start of the buffer" do
      buffer = TextBuffer.new(5, 3) |> TextBuffer.backspace()
      assert TextBuffer.cursor(buffer) == {0, 0}
      assert TextBuffer.lines(buffer) == ["", "", ""]
    end

    test "never un-scrolls a line dropped by an earlier scroll" do
      buffer =
        TextBuffer.new(5, 3)
        |> type(~c"one")
        |> TextBuffer.newline()
        |> type(~c"two")
        |> TextBuffer.newline()
        |> type(~c"three")
        |> TextBuffer.newline()
        |> type(~c"four")

      # "one" has already scrolled off the top; the buffer holds "two",
      # "three", "four".
      assert TextBuffer.lines(buffer) == ["two", "three", "four"]

      buffer =
        Enum.reduce(1..20, buffer, fn _, acc -> TextBuffer.backspace(acc) end)

      refute Enum.any?(TextBuffer.lines(buffer), &(&1 == "one"))
      assert TextBuffer.lines(buffer) == ["", "", ""]
      assert TextBuffer.cursor(buffer) == {0, 0}
    end
  end

  describe "tab/1" do
    test "advances to the next multiple of four" do
      buffer = TextBuffer.new(20, 3) |> TextBuffer.tab()
      assert TextBuffer.cursor(buffer) == {4, 0}
      assert TextBuffer.lines(buffer) == ["    ", "", ""]
    end

    test "advances only to the next stop when already partway" do
      buffer = TextBuffer.new(20, 3) |> type(~c"ab") |> TextBuffer.tab()
      assert TextBuffer.cursor(buffer) == {4, 0}
      assert TextBuffer.lines(buffer) == ["ab  ", "", ""]
    end

    test "wraps like any other insertion" do
      buffer = TextBuffer.new(5, 3) |> type(~c"abcd") |> TextBuffer.tab()
      assert TextBuffer.lines(buffer) == ["abcd ", "   ", ""]
      assert TextBuffer.cursor(buffer) == {3, 1}
    end
  end

  describe "lines/1" do
    test "always returns exactly `rows` entries" do
      buffer = TextBuffer.new(5, 3)
      assert length(TextBuffer.lines(buffer)) == 3
      assert length(TextBuffer.lines(type(buffer, ~c"ab"))) == 3
    end
  end
end
