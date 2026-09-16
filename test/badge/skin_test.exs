defmodule Badge.SkinTest do
  use ExUnit.Case, async: true

  alias Badge.Skin
  alias Badge.Skin.Dark
  alias Badge.Skin.Win95
  alias Badge.Theme

  @status %{battery: :battery_100, wifi: :wifi, clock: "12:34"}

  defp palette(skin) do
    [
      skin.bg(),
      skin.fg(),
      skin.muted(),
      skin.dim(),
      skin.accent(),
      skin.ok(),
      skin.warn(),
      skin.alert(),
      skin.select(),
      skin.role(:staff),
      skin.role(:presenter),
      skin.role(:attendee)
    ]
  end

  describe "the list" do
    test "starts with the default" do
      assert hd(Skin.all()) == Skin.default()
    end

    test "every skin has a distinct name" do
      names = for skin <- Skin.all(), do: skin.name()

      assert length(names) == length(:lists.usort(names))
    end

    test "shift stops at both ends rather than wrapping" do
      assert Skin.shift(Dark, -1) == Dark
      assert Skin.shift(Dark, 1) == Win95
      assert Skin.shift(Win95, 1) == Win95
      assert Skin.shift(Win95, -1) == Dark
    end
  end

  describe "the active skin" do
    test "is the default until one is activated" do
      assert Skin.current() == Dark
      assert Theme.fg() == Dark.fg()
    end

    test "changes what the theme answers" do
      Skin.activate(Win95)

      assert Skin.current() == Win95
      assert Theme.bg() == Win95.bg()
      assert Theme.select() == Win95.select()
      assert Theme.rule(0, 10, 100) == Win95.rule(0, 10, 100)
    end
  end

  describe "storage" do
    test "decodes a name back to its skin" do
      for skin <- Skin.all() do
        assert Skin.decode(skin.name()) == skin
      end
    end

    test "falls back to the default for nothing or nonsense" do
      assert Skin.decode(nil) == Skin.default()
      assert Skin.decode("Aqua") == Skin.default()
    end
  end

  for skin <- [Dark, Win95] do
    describe "#{inspect(skin)}" do
      @skin skin

      test "every colour fits in 24 bits" do
        for colour <- palette(@skin) do
          assert colour >= 0x000000
          assert colour <= 0xFFFFFF
        end
      end

      test "colours are distinct" do
        colours = palette(@skin)

        assert length(colours) == length(:lists.usort(colours))
      end

      test "chrome ends with a full-panel background in its own colour" do
        assert :lists.last(@skin.chrome("Badge", @status)) ==
                 {:rect, 0, 0, Theme.width(), Theme.height(), @skin.bg()}
      end

      test "chrome carries the title, the clock and both icons" do
        items = @skin.chrome("Badge", @status)
        bodies = for {:text, _x, _y, _f, _fg, _bg, body} <- items, do: body
        icons = for {:image, _x, _y, _bg, _image} <- items, do: :icon

        assert "Badge" in bodies
        assert "12:34" in bodies
        assert length(icons) == 2
      end

      test "chrome icons are drawn in a baked tint" do
        for {:image, _x, _y, _bg, {:rgba8888, _w, _h, binary}} <- @skin.chrome("Badge", @status) do
          assert is_binary(binary)
        end
      end

      test "glyph colour is one the icons are baked in" do
        assert @skin.glyph() in Badge.Icons.tints()
      end

      test "chrome stays inside the title bar" do
        items = :lists.droplast(@skin.chrome("Badge", @status))

        for item <- items do
          bottom =
            case item do
              {:rect, _x, y, _w, h, _c} -> y + h
              {:text, _x, y, _f, _fg, _bg, _b} -> y + 16
              {:image, _x, y, _bg, {:rgba8888, _w, h, _d}} -> y + h
            end

          assert bottom <= Theme.content_top()
        end
      end

      test "a rule is one or more single-row rects spanning the width asked for" do
        items = @skin.rule(8, 100, 200)

        assert length(items) >= 1

        for {:rect, x, _y, w, h, _c} <- items do
          assert x == 8
          assert w == 200
          assert h == 1
        end
      end
    end
  end
end
