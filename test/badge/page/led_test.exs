defmodule Badge.Page.LedTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Led
  alias Badge.Theme

  defp press(state, dir) do
    {:ok, next} = Led.handle_key({:move, dir}, state)
    next
  end

  defp press(state, _dir, 0), do: state
  defp press(state, dir, n), do: press(press(state, dir), dir, n - 1)

  defp texts(state), do: for({:text, _x, _y, _f, _fg, _bg, body} <- Led.render(state), do: body)

  defp swatch(state) do
    [colour | _rest] = for {:rect, _x, _y, 304, 60, colour} <- Led.render(state), do: colour

    colour
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Led.title() == "LED"
      assert Led.icon() == :circle
    end
  end

  describe "mode cycling" do
    test "starts on rainbow" do
      assert Led.mode(Led.init()) == :rainbow
    end

    test "down walks the mode list" do
      state = Led.init()

      assert Led.mode(press(state, :down)) == :dusk
      assert Led.mode(press(state, :down, 2)) == {:solid, 0}
      assert Led.mode(press(state, :down, 3)) == :white
      assert Led.mode(press(state, :down, 4)) == :off
    end

    test "down wraps back to the start" do
      assert Led.mode(press(Led.init(), :down, 5)) == :rainbow
    end

    test "up wraps backwards" do
      assert Led.mode(press(Led.init(), :up)) == :off
    end

    test "up and down are inverses" do
      state = press(Led.init(), :down)

      assert press(state, :up) == Led.init()
    end
  end

  describe "hue stepping" do
    test "right advances the hue" do
      assert Led.mode(press(press(Led.init(), :down, 2), :right)) == {:solid, 15}
    end

    test "hue wraps at 360" do
      assert Led.mode(press(press(Led.init(), :down, 2), :right, 24)) == {:solid, 0}
    end

    test "left wraps below zero" do
      assert Led.mode(press(press(Led.init(), :down, 2), :left)) == {:solid, 345}
    end

    test "hue survives a mode change" do
      state = press(press(press(Led.init(), :down, 2), :right, 4), :down)

      assert Led.mode(press(state, :down, 4)) == {:solid, 60}
    end
  end

  describe "handle_key/2" do
    test "is pure — no process is needed to press a key" do
      assert {:ok, _state} = Led.handle_key({:move, :down}, Led.init())
    end

    test "typing does nothing here" do
      assert Led.handle_key({:char, ?a}, Led.init()) == :ignore
      assert Led.handle_key({:edit, :newline}, Led.init()) == :ignore
    end
  end

  describe "render/1" do
    test "names the current mode" do
      assert "rainbow" in texts(Led.init())
      assert "dusk" in texts(press(Led.init(), :down))
      assert "solid" in texts(press(Led.init(), :down, 2))
      assert "white" in texts(press(Led.init(), :down, 3))
      assert "off" in texts(press(Led.init(), :down, 4))
    end

    test "the swatch follows the hue" do
      red = swatch(press(Led.init(), :down, 2))
      other = swatch(press(press(Led.init(), :down, 2), :right, 8))

      assert red != other
    end

    test "off draws a black swatch" do
      assert swatch(press(Led.init(), :down, 4)) == Theme.bg()
    end

    test "every item sits inside the content area" do
      for item <- Led.render(Led.init()) do
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
      refute Enum.any?(Led.render(Led.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end

  describe "white" do
    defp adopted(state), do: %{state | loaded: true}

    test "is one of the modes you can page to" do
      names = for mode <- Badge.LedMode.modes(), do: Badge.LedMode.name(mode)

      assert "white" in names
    end

    test "is reachable from rainbow and reads as white" do
      state = adopted(%{Led.init() | index: 3})

      assert Led.mode(state) == :white
    end

    test "its swatch is white, not the accent colour" do
      state = adopted(%{Led.init() | index: 3})

      [{:rect, _x, _y, _w, _h, colour}] =
        for {:rect, _x, _y, w, _h, _c} = item <- Led.render(state), w > 100, do: item

      assert colour == Theme.fg()
    end

    test "paging wraps through every mode and back" do
      seen =
        for step <- 0..(length(Badge.LedMode.modes()) - 1) do
          Led.mode(adopted(%{Led.init() | index: step}))
        end

      assert length(seen) == length(Badge.LedMode.modes())
      assert :white in seen
      assert :off in seen
    end
  end

  describe "adopting the live mode" do
    test "a page that has not loaded yet pushes nothing" do
      refute Led.init().loaded
      assert Led.init().pushed == nil
    end

    test "once loaded, a real change is still pushed" do
      state = %{Led.init() | loaded: true, index: 4, pushed: :rainbow}

      assert Led.mode(state) == :off
      refute Led.mode(state) == state.pushed
    end
  end
end
