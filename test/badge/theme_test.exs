defmodule Badge.ThemeTest do
  use ExUnit.Case, async: true

  alias Badge.Theme

  describe "colours" do
    test "every colour fits in 24 bits" do
      for colour <- [Theme.bg(), Theme.fg(), Theme.dim(), Theme.accent()] do
        assert colour >= 0x000000
        assert colour <= 0xFFFFFF
      end
    end

    test "tokens are distinct" do
      colours = [Theme.bg(), Theme.fg(), Theme.dim(), Theme.accent()]

      assert length(colours) == length(:lists.usort(colours))
    end
  end

  describe "geometry" do
    test "matches the panel" do
      assert Theme.width() == 320
      assert Theme.height() == 240
    end

    test "content starts below the title bar rule" do
      assert Theme.content_top() > Theme.bar_h()
    end

    test "content area has room for at least one row of text" do
      assert Theme.height() - Theme.content_top() >= 16
    end
  end
end
