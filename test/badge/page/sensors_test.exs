defmodule Badge.Page.SensorsTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Sensors
  alias Badge.Page.Temp
  alias Badge.Page.Tilt
  alias Badge.Theme

  defp right(state) do
    {:ok, next} = Sensors.handle_key({:move, :right}, state)
    next
  end

  defp left(state) do
    {:ok, next} = Sensors.handle_key({:move, :left}, state)
    next
  end

  defp dots(state) do
    for {:rect, x, y, w, h, colour} <- Sensors.render(state),
        w == 6 and h == 6,
        do: {x, y, colour}
  end

  defp lit(state), do: for({_x, _y, colour} <- dots(state), colour == Theme.fg(), do: colour)

  describe "identity" do
    test "announces itself for the home grid" do
      assert Sensors.title() == "Sensors"
      assert Sensors.icon() == :clover
    end

    test "carries both sensor pages, tilt first" do
      assert Sensors.subpages() == [Tilt, Temp]
    end

    test "takes its frame rate from the sub-page on screen" do
      state = Sensors.init()

      assert Sensors.refresh(state) == Tilt.refresh(Tilt.init())
      assert Sensors.refresh(right(state)) == Temp.refresh(Temp.init())
    end
  end

  describe "carousel" do
    test "starts on the first sub-page" do
      assert Sensors.init().index == 0
    end

    test "right and left step between them" do
      state = Sensors.init()

      assert right(state).index == 1
      assert left(right(state)).index == 0
    end

    test "wraps in both directions" do
      state = Sensors.init()

      assert right(right(state)).index == 0
      assert left(state).index == 1
    end

    test "moving leaves every sub-page's state alone" do
      state = Sensors.init()

      assert right(state).states == state.states
      assert left(state).states == state.states
    end

    test "one state per sub-page" do
      assert length(Sensors.init().states) == length(Sensors.subpages())
    end

    test "sub-page state survives sliding away and back" do
      state = Sensors.init()
      touched = %{state | states: [:touched | tl(state.states)]}

      assert hd(left(right(touched)).states) == :touched
    end
  end

  describe "key routing" do
    test "a key neither sub-page wants is ignored rather than swallowed" do
      assert Sensors.handle_key({:char, ?z}, Sensors.init()) == :ignore
    end

    test "escape is not trapped, so the router can go home" do
      assert Sensors.handle_key({:nav, :home}, Sensors.init()) == :ignore
    end

    test "enter is free now that tilt levels itself" do
      assert Sensors.handle_key({:edit, :newline}, Sensors.init()) == :ignore
    end
  end

  describe "render/1" do
    test "shows the active sub-page's own items" do
      state = Sensors.init()

      assert Sensors.render(state) -- dots_items(state) == Tilt.render(Tilt.init())
    end

    defp dots_items(state) do
      for {:rect, _x, _y, w, h, _c} = item <- Sensors.render(state), w == 6 and h == 6, do: item
    end

    test "one dot per sub-page, exactly one of them lit" do
      for state <- [Sensors.init(), right(Sensors.init())] do
        assert length(dots(state)) == length(Sensors.subpages())
        assert length(lit(state)) == 1
      end
    end

    test "the lit dot follows the carousel" do
      state = Sensors.init()
      [{first_x, _y, _c}] = for {x, y, c} <- dots(state), c == Theme.fg(), do: {x, y, c}
      [{second_x, _y2, _c2}] = for {x, y, c} <- dots(right(state)), c == Theme.fg(), do: {x, y, c}

      assert first_x < second_x
    end

    test "the dots sit below everything either sub-page draws" do
      for state <- [Sensors.init(), right(Sensors.init())] do
        content =
          for item <- Sensors.render(state),
              item not in dots_items(state),
              do: bottom(item)

        assert :lists.max(content) <= 234
      end
    end

    test "the dots stay on the panel" do
      for {x, y, _c} <- dots(Sensors.init()) do
        assert x >= 0
        assert x + 6 <= Theme.width()
        assert y + 6 <= Theme.height()
      end
    end

    defp bottom({:text, _x, y, _f, _fg, _bg, _body}), do: y + 16
    defp bottom({:rect, _x, y, _w, h, _c}), do: y + h
    defp bottom({:image, _x, y, _bg, {:rgba8888, _w, h, _bin}}), do: y + h

    test "emits no background rect, since the router adds it" do
      refute Enum.any?(Sensors.render(Sensors.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
