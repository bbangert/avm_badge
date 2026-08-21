defmodule Badge.Page.InfoTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Info
  alias Badge.Theme

  defp reading(overrides) do
    base = %{
      battery_mv: 3900,
      vbus_mv: 0,
      usb: false,
      temp: 24,
      accel: {0, 0, 1000},
      uptime_s: 42
    }

    Map.merge(base, overrides)
  end

  defp texts(state) do
    for {:text, _x, _y, _f, _fg, _bg, body} <- Info.render(state), do: body
  end

  defp shows?(state, needle) do
    Enum.any?(texts(state), fn body -> :binary.match(body, needle) != :nomatch end)
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Info.title() == "Info"
      assert Info.icon() == :circle
    end
  end

  describe "percent/1" do
    test "clamps at both rails" do
      assert Info.percent(3000) == 0
      assert Info.percent(3300) == 0
      assert Info.percent(4200) == 100
      assert Info.percent(4500) == 100
    end

    test "is monotonic across the working range" do
      assert Info.percent(3500) < Info.percent(3800)
      assert Info.percent(3800) < Info.percent(4100)
    end

    test "the midpoint is about half" do
      assert_in_delta Info.percent(3750), 50, 2
    end
  end

  describe "render/1" do
    test "renders from a literal reading with no hardware" do
      state = Info.update(Info.init(), reading(%{}))

      assert shows?(state, "3900")
      assert shows?(state, "24")
      assert shows?(state, "42")
    end

    test "reports usb presence both ways" do
      absent = Info.update(Info.init(), reading(%{usb: false}))
      present = Info.update(Info.init(), reading(%{usb: true, vbus_mv: 5050}))

      refute texts(absent) == texts(present)
      assert shows?(present, "5050")
    end

    test "an unavailable temperature does not crash" do
      state = Info.update(Info.init(), reading(%{temp: :unavailable}))

      assert is_list(Info.render(state))
    end

    test "shows all three accelerometer axes" do
      state = Info.update(Info.init(), reading(%{accel: {-68, 850, -560}}))

      assert shows?(state, "-60")
      assert shows?(state, "850")
      assert shows?(state, "-560")
    end

    test "the accelerometer readout is rounded, so sensor noise does not repaint" do
      steady = Info.update(Info.init(), reading(%{accel: {-68, 850, -560}}))
      jittered = Info.update(Info.init(), reading(%{accel: {-61, 856, -566}}))

      assert steady == jittered
    end

    test "the battery bar fill tracks the percentage" do
      fill = fn state ->
        [width | _rest] =
          for {:rect, _x, _y, w, _h, colour} <- Info.render(state),
              colour == Theme.accent(),
              do: w

        width
      end

      assert fill.(Info.update(Info.init(), reading(%{battery_mv: 3300}))) == 0
      assert fill.(Info.update(Info.init(), reading(%{battery_mv: 4200}))) == 304
    end

    test "the bar fill is listed before its frame, so it draws on top" do
      state = Info.update(Info.init(), reading(%{battery_mv: 3900}))
      rects = for {:rect, _x, _y, _w, _h, colour} <- Info.render(state), do: colour

      assert rects == [Theme.accent(), Theme.dim()]
    end

    test "init renders before any reading arrives" do
      assert is_list(Info.render(Info.init()))
    end

    test "every item sits inside the content area" do
      state = Info.update(Info.init(), reading(%{}))

      for item <- Info.render(state) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end

    test "emits no background rect" do
      state = Info.update(Info.init(), reading(%{}))

      refute Enum.any?(Info.render(state), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
