defmodule Badge.Page.TiltTest do
  use ExUnit.Case, async: true

  alias Badge.Icons
  alias Badge.Page.Tilt
  alias Badge.Theme

  defp marker(state) do
    [{:image, x, y, _bg, _img} | _rest] = Tilt.render(state)

    {x, y}
  end

  defp at(roll, pitch), do: Tilt.update(Tilt.init(), {roll, pitch})

  defp marker_size do
    {w, h} = Icons.size(:circle)
    {w, h}
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Tilt.title() == "Tilt"
      assert Tilt.icon() == :triangle
    end
  end

  describe "update/2" do
    test "level sits at the centre of the plot" do
      {w, h} = marker_size()
      {x, y} = marker(at(0, 0))

      assert x == 160 - div(w, 2)
      assert y == 120 - div(h, 2)
    end

    test "rolling moves the marker horizontally" do
      {left, _y} = marker(at(-60, 0))
      {centre, _y2} = marker(at(0, 0))
      {right, _y3} = marker(at(60, 0))

      assert left < centre
      assert centre < right
    end

    test "pitching moves the marker vertically" do
      {_x, up} = marker(at(0, -60))
      {_x2, centre} = marker(at(0, 0))
      {_x3, down} = marker(at(0, 60))

      assert up < centre
      assert centre < down
    end

    test "past the clamp the marker stops moving" do
      assert marker(at(60, 0)) == marker(at(120, 0))
      assert marker(at(-60, 0)) == marker(at(-179, 0))
      assert marker(at(0, 90)) == marker(at(0, 60))
    end

    test "position is quantised to 4px so noise does not repaint" do
      {x, y} = marker(at(37, 23))

      assert rem(x, 4) == 0
      assert rem(y, 4) == 0
    end

    test "a sub-quantum wobble does not change state" do
      assert Tilt.update(Tilt.init(), {20, 10}) == Tilt.update(Tilt.init(), {20, 11})
    end

    test "a real movement does change state" do
      refute Tilt.update(Tilt.init(), {0, 0}) == Tilt.update(Tilt.init(), {40, 0})
    end

    test "equal readings give equal state, so the router stays clean" do
      assert Tilt.update(Tilt.init(), {12, -8}) == Tilt.update(Tilt.init(), {12, -8})
    end
  end

  describe "render/1" do
    test "the marker is the first item, so it draws over the readout" do
      [first | _rest] = Tilt.render(at(0, 0))

      assert {:image, _x, _y, _bg, {:rgba8888, _w, _h, _bin}} = first
    end

    test "shows the angles as text" do
      texts = for {:text, _x, _y, _f, _fg, _bg, body} <- Tilt.render(at(30, -20)), do: body

      assert length(texts) == 1
      assert :binary.match(hd(texts), "30") != :nomatch
      assert :binary.match(hd(texts), "-20") != :nomatch
    end

    test "the marker stays on the panel at every extreme" do
      {w, h} = marker_size()

      for roll <- [-90, -60, 0, 60, 90], pitch <- [-90, -60, 0, 60, 90] do
        {x, y} = marker(at(roll, pitch))

        assert x >= 0
        assert x + w <= Theme.width()
        assert y >= Theme.content_top()
        assert y + h <= Theme.height()
      end
    end

    test "emits no background rect" do
      refute Enum.any?(Tilt.render(at(0, 0)), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
