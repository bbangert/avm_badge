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

    test "a word with no space to break on is cut rather than overflowing" do
      assert Text.wrap("Supercalifragilistic", 8) == ["Supercal", "ifragili", "stic"]
    end

    test "a long word after a short one still breaks at the space first" do
      assert Text.wrap("Dr Supercalifragilistic", 10) == ["Dr", "Supercalif", "ragilistic"]
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

    test "nothing is lost but the spaces broken on" do
      squashed = fn text -> :binary.replace(text, " ", "", [:global]) end

      for name <- ["Alexander Hamilton", "a b c d e f g", "Supercalifragilistic"] do
        joined = :erlang.iolist_to_binary(Text.wrap(name, 8))

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
end
