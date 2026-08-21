defmodule Badge.Page.TiltTest do
  use ExUnit.Case, async: true

  alias Badge.Icons
  alias Badge.Page.Tilt
  alias Badge.Theme

  # A badge lying flat on a desk, from the real probe in Badge.AccelTest.
  @resting {123, 4}

  defp marker(state) do
    [{:image, x, y, _bg, _img} | _rest] = Tilt.render(state)

    {x, y}
  end

  defp levelled, do: Tilt.update(Tilt.init(), {0, 0})

  defp at(roll, pitch), do: Tilt.update(levelled(), {roll, pitch})

  defp marker_size, do: Icons.size(:circle)

  describe "identity" do
    test "announces itself for the home grid" do
      assert Tilt.title() == "Tilt"
      assert Tilt.icon() == :triangle
    end

    test "repaints slowly, since a frame is a whole panel" do
      assert Tilt.refresh() == 333
    end
  end

  describe "zeroing" do
    test "the first reading becomes the zero, whatever the badge rests at" do
      assert marker(Tilt.update(Tilt.init(), @resting)) == marker(levelled())
    end

    test "a badge left untouched stays centred" do
      rested = Tilt.update(Tilt.init(), @resting)

      assert marker(Tilt.update(rested, @resting)) == marker(levelled())
    end

    test "tilting away from the captured zero moves the marker" do
      rested = Tilt.update(Tilt.init(), @resting)
      {rested_x, _y} = marker(rested)
      {tilted_x, _y2} = marker(Tilt.update(rested, {143, 4}))

      refute tilted_x == rested_x
    end

    test "Enter re-zeroes at the current orientation" do
      tilted = Tilt.update(levelled(), {30, 20})
      refute marker(tilted) == marker(levelled())

      {:ok, cleared} = Tilt.handle_key({:edit, :newline}, tilted)

      assert marker(Tilt.update(cleared, {30, 20})) == marker(levelled())
    end

    test "crossing the 180 degree seam is a small move, not a full swing" do
      rested = Tilt.update(Tilt.init(), {170, 0})
      {rested_x, _y} = marker(rested)
      {crossed_x, _y2} = marker(Tilt.update(rested, {-170, 0}))

      # -170 is 20 degrees past 170: a nudge, not a slam to the edge.
      refute crossed_x == rested_x
      assert abs(crossed_x - rested_x) < abs(elem(marker(at(45, 0)), 0) - rested_x)
    end

    test "anything other than Enter is ignored" do
      assert Tilt.handle_key({:char, ?a}, Tilt.init()) == :ignore
      assert Tilt.handle_key({:move, :up}, Tilt.init()) == :ignore
    end
  end

  describe "update/2" do
    test "level sits at the centre of the plot" do
      {w, h} = marker_size()
      {x, y} = marker(levelled())

      assert x == 160 - div(w, 2)
      assert y == 120 - div(h, 2)
    end

    test "roll moves the marker horizontally, inverted to match the panel" do
      {positive, _y} = marker(at(45, 0))
      {centre, _y2} = marker(at(0, 0))
      {negative, _y3} = marker(at(-45, 0))

      # Sensor roll increases toward the panel's left, so the mapping flips it.
      assert positive < centre
      assert centre < negative
    end

    test "the readout agrees with the direction the marker moved" do
      [body] = for {:text, _x, _y, _f, _fg, _bg, body} <- Tilt.render(at(-30, 0)), do: body
      {x, _y} = marker(at(-30, 0))

      # Marker right of centre means a positive roll on screen.
      assert x > elem(marker(at(0, 0)), 0)
      assert :binary.match(body, "roll 30") != :nomatch
    end

    test "pitching moves the marker vertically" do
      {_x, up} = marker(at(0, -45))
      {_x2, centre} = marker(at(0, 0))
      {_x3, down} = marker(at(0, 45))

      assert up < centre
      assert centre < down
    end

    test "the marker moves further the more it is tilted" do
      centre = elem(marker(at(0, 0)), 0)
      small = abs(elem(marker(at(10, 0)), 0) - centre)
      medium = abs(elem(marker(at(25, 0)), 0) - centre)
      large = abs(elem(marker(at(40, 0)), 0) - centre)

      assert small < medium
      assert medium < large
    end

    test "past the clamp the marker stops moving" do
      assert marker(at(45, 0)) == marker(at(90, 0))
      assert marker(at(-45, 0)) == marker(at(-120, 0))
      assert marker(at(0, 80)) == marker(at(0, 45))
    end

    test "position is quantised so noise does not repaint" do
      {x, y} = marker(at(37, 23))

      assert rem(x, 8) == 0
      assert rem(y, 8) == 0
    end

    test "a degree of wobble either way leaves the marker alone" do
      centre = marker(levelled())

      # Half a quantum is about 1.3 degrees, so that is the deadzone.
      for wobble <- [-1, 0, 1] do
        assert marker(at(wobble, wobble)) == centre
      end
    end

    test "a sub-quantum wobble does not change state" do
      assert Tilt.update(levelled(), {1, 0}) == Tilt.update(levelled(), {0, 0})
    end

    test "a real movement does change state" do
      refute Tilt.update(levelled(), {0, 0}) == Tilt.update(levelled(), {30, 0})
    end

    test "equal readings give equal state, so the router stays clean" do
      assert Tilt.update(levelled(), {12, -8}) == Tilt.update(levelled(), {12, -8})
    end
  end

  describe "render/1" do
    test "the marker is the first item, so it draws over the readout" do
      [first | _rest] = Tilt.render(levelled())

      assert {:image, _x, _y, _bg, {:rgba8888, _w, _h, _bin}} = first
    end

    test "shows the angles relative to the zero" do
      texts = for {:text, _x, _y, _f, _fg, _bg, body} <- Tilt.render(at(-30, -20)), do: body

      assert length(texts) == 1
      assert :binary.match(hd(texts), "30") != :nomatch
      assert :binary.match(hd(texts), "-20") != :nomatch
    end

    test "reads zero at rest, however the sensor is mounted" do
      [body] =
        for {:text, _x, _y, _f, _fg, _bg, body} <- Tilt.render(Tilt.update(Tilt.init(), @resting)),
            do: body

      assert :binary.match(body, "roll 0") != :nomatch
      assert :binary.match(body, "pitch 0") != :nomatch
    end

    test "the readout fits the panel" do
      [body] = for {:text, _x, _y, _f, _fg, _bg, body} <- Tilt.render(at(-44, -44)), do: body

      assert 4 + 8 * byte_size(body) <= Theme.width()
    end

    test "the marker stays on the panel at every extreme" do
      {w, h} = marker_size()

      for roll <- [-90, -45, 0, 45, 90], pitch <- [-90, -45, 0, 45, 90] do
        {x, y} = marker(at(roll, pitch))

        assert x >= 0
        assert x + w <= Theme.width()
        assert y >= Theme.content_top()
        assert y + h <= Theme.height()
      end
    end

    test "the marker never overlaps the readout" do
      {_w, h} = marker_size()

      for roll <- [-45, 0, 45], pitch <- [-45, 0, 45] do
        {_x, y} = marker(at(roll, pitch))

        assert y + h <= 218
      end
    end

    test "emits no background rect" do
      refute Enum.any?(Tilt.render(levelled()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
