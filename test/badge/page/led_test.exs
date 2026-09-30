defmodule Badge.Page.LedTest do
  use ExUnit.Case, async: true

  alias Badge.LedEffect
  alias Badge.Page.Led
  alias Badge.Theme

  defp loaded(setting \\ LedEffect.default()),
    do: %{Led.init() | setting: setting, pushed: setting, loaded: true}

  defp press(state, dir) do
    {:ok, next} = Led.handle_key({:move, dir}, state)
    next
  end

  defp press(state, _dir, 0), do: state
  defp press(state, dir, n), do: press(press(state, dir), dir, n - 1)

  defp texts(state), do: for({:text, _x, _y, _f, _fg, _bg, body} <- Led.render(state), do: body)

  describe "identity" do
    test "announces itself for the home grid" do
      assert Led.title() == "LED"
      assert Led.icon() == :circle
    end
  end

  describe "rows" do
    test "are the effect, then the options it uses" do
      setting = %{LedEffect.default() | effect: :chase}

      assert Led.rows(setting) == [:effect | LedEffect.options(:chase)]
    end

    test "a single-hue palette adds a hue row after the colours" do
      setting = %{LedEffect.default() | effect: :breathe, palette: :hue}

      assert [:effect, :palette, :hue | _rest] = Led.rows(setting)
    end

    test "off has only the effect row" do
      assert Led.rows(%{LedEffect.default() | effect: :off}) == [:effect]
    end
  end

  describe "keys" do
    test "right steps to the next effect, left back again" do
      state = loaded()
      [_first, second | _rest] = LedEffect.effects()

      assert press(state, :right).setting.effect == second
      assert press(press(state, :right), :left).setting.effect == :rainbow
    end

    test "effects wrap round both ways" do
      assert press(loaded(), :left).setting.effect == :lists.last(LedEffect.effects())
      assert press(loaded(), :right, length(LedEffect.effects())).setting.effect == :rainbow
    end

    test "down moves to an option and right changes it" do
      state = press(loaded(), :down)

      assert Enum.at(Led.rows(state.setting), 1) == :speed
      assert press(state, :right).setting.speed == LedEffect.default().speed + 1
    end

    test "options stop at their ends" do
      state = press(loaded(), :down)

      assert press(state, :right, 20).setting.speed == 10
      assert press(state, :left, 20).setting.speed == 1
    end

    test "the cursor stays on the rows there are" do
      state = press(loaded(), :down, 20)

      assert state.cursor == length(Led.rows(state.setting)) - 1
    end

    test "changing to an effect with fewer rows pulls the cursor in" do
      state = %{loaded(%{LedEffect.default() | effect: :twinkle}) | cursor: 0}
      moved = press(state, :right)

      assert moved.cursor <= length(Led.rows(moved.setting)) - 1
    end

    test "direction flips either way" do
      setting = %{LedEffect.default() | effect: :chase}
      row = Enum.find_index(Led.rows(setting), &(&1 == :direction))
      state = %{loaded(setting) | cursor: row}

      assert press(state, :right).setting.direction == :ccw
      assert press(press(state, :right), :left).setting.direction == :cw
    end

    test "typing does nothing here" do
      assert Led.handle_key({:char, ?a}, Led.init()) == :ignore
    end
  end

  describe "tick/1" do
    test "a page that has not loaded yet has pushed nothing" do
      refute Led.init().loaded
      assert Led.init().pushed == nil
    end

    test "an unchanged setting is not pushed again" do
      state = loaded()

      assert Led.tick(state) == state
    end
  end

  describe "render/1" do
    test "names the effect and each option" do
      body = texts(loaded(%{LedEffect.default() | effect: :chase, palette: :fire}))

      assert "chase" in body
      assert "fire" in body
      assert "clockwise" in body
    end

    test "the swatch shows each palette colour" do
      setting = %{LedEffect.default() | effect: :drift, palette: :fire}
      blocks = for {:rect, _x, 168, _w, _h, colour} <- Led.render(loaded(setting)), do: colour

      assert blocks == LedEffect.colours(:fire, 0)
    end

    test "the swatch spans the same width whatever the palette" do
      for palette <- LedEffect.palettes() do
        setting = %{LedEffect.default() | effect: :drift, palette: palette}
        widths = for {:rect, _x, 168, w, _h, _c} <- Led.render(loaded(setting)), do: w

        assert Enum.sum(widths) == 304
      end
    end

    test "every item sits inside the content area" do
      for effect <- LedEffect.effects(),
          item <- Led.render(loaded(%{LedEffect.default() | effect: effect})) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end
  end
end
