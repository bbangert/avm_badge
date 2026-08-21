defmodule Badge.KeymapTest do
  use ExUnit.Case, async: true

  alias Badge.Keymap

  describe "letters" do
    test "unshifted letters are lowercase" do
      assert Keymap.decode(~c"Q", false) == {:char, ?q}
      assert Keymap.decode(~c"A", false) == {:char, ?a}
      assert Keymap.decode(~c"Z", false) == {:char, ?z}
    end

    test "shifted letters are uppercase" do
      assert Keymap.decode(~c"Q", true) == {:char, ?Q}
      assert Keymap.decode(~c"M", true) == {:char, ?M}
    end
  end

  describe "number row" do
    test "unshifted digits" do
      assert Keymap.decode(~c"1", false) == {:char, ?1}
      assert Keymap.decode(~c"0", false) == {:char, ?0}
    end

    test "shifted digits give the US symbol row" do
      assert Keymap.decode(~c"1", true) == {:char, ?!}
      assert Keymap.decode(~c"2", true) == {:char, ?@}
      assert Keymap.decode(~c"3", true) == {:char, ?#}
      assert Keymap.decode(~c"4", true) == {:char, ?$}
      assert Keymap.decode(~c"5", true) == {:char, ?%}
      assert Keymap.decode(~c"6", true) == {:char, ?^}
      assert Keymap.decode(~c"7", true) == {:char, ?&}
      assert Keymap.decode(~c"8", true) == {:char, ?*}
      assert Keymap.decode(~c"9", true) == {:char, ?(}
      assert Keymap.decode(~c"0", true) == {:char, ?)}
    end
  end

  describe "punctuation pairs" do
    test "every pair maps both ways" do
      pairs = [
        {~c"`", ?`, ?~},
        {~c"-", ?-, ?_},
        {~c"=", ?=, ?+},
        {~c"[", ?[, ?{},
        {~c"]", ?], ?}},
        {~c"\\", ?\\, ?|},
        {~c";", ?;, ?:},
        {~c"'", ?', ?"},
        {~c",", ?,, ?<},
        {~c".", ?., ?>},
        {~c"/", ?/, ??}
      ]

      for {label, unshifted, shifted} <- pairs do
        assert Keymap.decode(label, false) == {:char, unshifted}
        assert Keymap.decode(label, true) == {:char, shifted}
      end
    end
  end

  describe "space" do
    test "is an ordinary printable character in both states" do
      assert Keymap.decode(~c"Space", false) == {:char, ?\s}
      assert Keymap.decode(~c"Space", true) == {:char, ?\s}
    end
  end

  describe "edit keys" do
    test "map to edit operations regardless of shift" do
      assert Keymap.decode(~c"Bksp", false) == {:edit, :backspace}
      assert Keymap.decode(~c"Bksp", true) == {:edit, :backspace}
      assert Keymap.decode(~c"Enter", false) == {:edit, :newline}
      assert Keymap.decode(~c"Tab", false) == {:edit, :tab}
    end
  end

  describe "ignored keys" do
    test "modifiers, arrows, shape keys and unmapped intersections" do
      for label <- [
            ~c"LShift",
            ~c"RShift",
            ~c"Ctrl",
            ~c"Alt",
            ~c"AltGr",
            ~c"Fn",
            ~c"SP",
            ~c"Esc",
            ~c"Up",
            ~c"Down",
            ~c"Left",
            ~c"Right",
            ~c"Square",
            ~c"Triangle",
            ~c"Cross",
            ~c"Circle",
            ~c"Clover",
            ~c"Diamond",
            ~c"<unmapped R0C0>"
          ] do
        assert Keymap.decode(label, false) == :ignore
        assert Keymap.decode(label, true) == :ignore
      end
    end
  end
end
