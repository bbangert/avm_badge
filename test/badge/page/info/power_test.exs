defmodule Badge.Page.Info.PowerTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Info
  alias Badge.Page.Info.Power
  alias Badge.Theme

  defp reading(overrides) do
    Map.merge(%{battery_mv: 3900, vbus_mv: 0, usb: false, uptime_s: 42}, overrides)
  end

  defp texts(state), do: for({:text, _x, _y, _f, _fg, _bg, body} <- Power.render(state), do: body)

  defp shows?(state, needle) do
    Enum.any?(texts(state), fn body -> :binary.match(body, needle) != :nomatch end)
  end

  defp fill(state) do
    [width | _rest] =
      for {:rect, _x, _y, w, _h, colour} <- Power.render(state), colour == Theme.accent(), do: w

    width
  end

  describe "identity" do
    test "names itself for the tab strip" do
      assert Power.title() == "Power"
    end

    test "does not trap escape" do
      assert Power.handle_key({:nav, :home}, Power.init()) == :ignore
    end

    test "leaves the arrows to the carousel" do
      assert Power.handle_key({:move, :left}, Power.init()) == :ignore
      assert Power.handle_key({:move, :right}, Power.init()) == :ignore
    end
  end

  describe "render/1" do
    test "renders from a literal reading with no hardware" do
      state = Power.update(Power.init(), reading(%{}))

      assert shows?(state, "3900")
      assert shows?(state, "42")
    end

    test "reports usb presence both ways" do
      absent = Power.update(Power.init(), reading(%{usb: false}))
      present = Power.update(Power.init(), reading(%{usb: true, vbus_mv: 5050}))

      refute texts(absent) == texts(present)
      assert shows?(present, "5050")
    end

    test "shows the charge percentage" do
      assert shows?(Power.update(Power.init(), reading(%{battery_mv: 4200})), "100%")
      assert shows?(Power.update(Power.init(), reading(%{battery_mv: 3300})), "0%")
    end

    test "the bar fill tracks the percentage" do
      assert fill(Power.update(Power.init(), reading(%{battery_mv: 3300}))) == 0
      assert fill(Power.update(Power.init(), reading(%{battery_mv: 4200}))) == 304
    end

    test "the bar fill is listed before its frame, so it draws on top" do
      state = Power.update(Power.init(), reading(%{}))
      rects = for {:rect, _x, _y, _w, _h, colour} <- Power.render(state), do: colour

      assert rects == [Theme.accent(), Theme.dim()]
    end

    test "init renders before any reading arrives" do
      assert is_list(Power.render(Power.init()))
    end

    test "draws below the tab strip and inside the panel" do
      state = Power.update(Power.init(), reading(%{}))

      for item <- Power.render(state) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Info.content_top()
        assert y < Theme.height()
      end
    end
  end
end
