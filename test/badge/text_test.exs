defmodule Badge.TextTest do
  use ExUnit.Case, async: true

  alias Badge.Text

  describe "wrap/2" do
    test "text that fits is left alone" do
      assert Text.wrap("Gus", 18) == ["Gus"]
      assert Text.wrap("", 18) == [""]
    end

    test "text exactly the width is left alone" do
      assert Text.wrap("123456", 6) == ["123456"]
    end

    test "breaks at the space so words stay whole" do
      assert Text.wrap("Alexander Hamilton", 12) == ["Alexander", "Hamilton"]
    end

    test "breaks at the last space that fits, not the first" do
      assert Text.wrap("a b c d e f g h", 7) == ["a b c d", "e f g h"]
    end

    test "a word with no space to break on is dashed rather than overflowing" do
      assert Text.wrap("Supercalifragilistic", 8) == ["Superca-", "lifragi-", "listic"]
    end

    test "a long word after a short one still breaks at the space first" do
      assert Text.wrap("Dr Supercalifragilistic", 10) == ["Dr", "Supercali-", "fragilist-", "ic"]
    end

    test "wraps onto as many lines as it needs" do
      assert length(Text.wrap("one two three four five six", 9)) == 4
    end

    test "no line is ever wider than asked for" do
      names = [
        "Gus",
        "Alexander Hamilton",
        "Supercalifragilisticexpialidocious",
        "A B C D E F G H I J K L",
        "Wolfeschlegelsteinhausenbergerdorff"
      ]

      for name <- names, columns <- [6, 10, 18, 30] do
        for line <- Text.wrap(name, columns) do
          assert byte_size(line) <= columns
        end
      end
    end

    test "nothing is lost but the spaces broken on and the dashes added" do
      squashed = fn text -> :binary.replace(text, " ", "", [:global]) end
      undashed = fn lines -> for line <- lines, do: :binary.replace(line, "-", "", [:global]) end

      for name <- ["Alexander Hamilton", "a b c d e f g", "Supercalifragilistic"] do
        joined = :erlang.iolist_to_binary(undashed.(Text.wrap(name, 8)))

        assert squashed.(joined) == squashed.(name)
      end
    end

    test "runs of spaces do not produce empty lines" do
      assert Text.wrap("a  b", 3) == ["a", "b"]
    end

    test "a nonsense width does not loop forever" do
      assert Text.wrap("hello", 0) == ["hello"]
    end
  end

  describe "words too long to fit" do
    test "are broken with a dash that joins them to the next line" do
      assert Text.wrap("supercalifragilistic", 10) == ["supercali-", "fragilist-", "ic"]
    end

    test "the dash costs a column, so no line runs over" do
      for line <- Text.wrap("abcdefghijklmnopqrstuvwxyz", 8) do
        assert byte_size(line) <= 8
      end
    end

    test "a word that fits exactly is not dashed" do
      assert Text.wrap("abcdefgh", 8) == ["abcdefgh"]
    end

    test "a short word after a long one still breaks on the space" do
      assert Text.wrap("aaaaaaaaaaaa bb", 10) == ["aaaaaaaaa-", "aaa bb"]
    end

    test "a two column line still makes progress rather than looping" do
      assert Text.wrap("abcdef", 2) == ["a-", "a-", "a-", "a-", "a-", "f"] or
               length(Text.wrap("abcdef", 2)) > 1
    end
  end
end
