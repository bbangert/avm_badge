defmodule Badge.Page.TempTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Temp
  alias Badge.Theme

  # One reading per second, starting at second zero.
  defp samples(state, temps) do
    {result, _second} =
      :lists.foldl(
        fn temp, {acc, second} -> {Temp.update(acc, {second, temp}), second + 1} end,
        {state, 0},
        temps
      )

    result
  end

  defp bars(state) do
    for {:rect, _x, _y, 3, _h, colour} <- Temp.render(state),
        colour == Theme.accent(),
        do: :bar
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Temp.title() == "Temp"
      assert Temp.icon() == :cross
    end
  end

  describe "update/2" do
    test "the first reading samples immediately" do
      assert length(bars(Temp.update(Temp.init(), {0, 22}))) == 1
    end

    test "a second reading in the same second is dropped" do
      state = Temp.update(Temp.init(), {0, 22})

      assert length(bars(Temp.update(state, {0, 23}))) == 1
    end

    test "a repeat tick inside the same second leaves state untouched" do
      state = Temp.update(Temp.init(), {0, 22})

      assert Temp.update(state, {0, 22}) == state
      assert Temp.update(state, {0, 99}) == state
    end

    test "one sample per second" do
      assert length(bars(samples(Temp.init(), [20, 21, 22, 23]))) == 4
    end

    test "an unavailable reading is skipped, not plotted" do
      assert bars(Temp.update(Temp.init(), {0, :unavailable})) == []
    end

    test "an unavailable reading leaves state untouched, so the next tick retries" do
      state = Temp.update(Temp.init(), {0, 22})

      assert Temp.update(state, {1, :unavailable}) == state
      assert length(bars(Temp.update(Temp.update(state, {1, :unavailable}), {1, 24}))) == 2
    end

    test "samples cap at the plot width, dropping the oldest" do
      assert length(bars(samples(Temp.init(), :lists.seq(1, 100)))) == 76
    end

    test "the oldest sample is the one dropped" do
      state = samples(Temp.init(), :lists.seq(1, 100))

      texts = for {:text, _x, _y, _f, _fg, _bg, body} <- Temp.render(state), do: body

      assert Enum.any?(texts, fn body -> :binary.match(body, "min 25") != :nomatch end)
    end
  end

  describe "render/1" do
    test "an empty page still draws without crashing" do
      assert is_list(Temp.render(Temp.init()))
      assert bars(Temp.init()) == []
    end

    test "shows the latest reading" do
      texts =
        for {:text, _x, _y, _f, _fg, _bg, body} <- Temp.render(samples(Temp.init(), [20, 27])),
            do: body

      assert Enum.any?(texts, fn body -> :binary.match(body, "27") != :nomatch end)
    end

    test "a flat reading does not become a full-height sawtooth" do
      state = samples(Temp.init(), [22, 22, 22, 22, 22])
      heights = for {:rect, _x, _y, 3, h, _c} <- Temp.render(state), do: h

      assert length(:lists.usort(heights)) == 1
      assert hd(heights) < 100
    end

    test "a rising reading produces rising bars" do
      state = samples(Temp.init(), [20, 25, 30])

      tops =
        for {:rect, _x, y, 3, _h, colour} <- Temp.render(state),
            colour == Theme.accent(),
            do: y

      assert tops == :lists.reverse(:lists.sort(tops))
    end

    test "every bar sits inside the plot area" do
      state = samples(Temp.init(), :lists.seq(10, 40))

      for {:rect, x, y, 3, h, colour} <- Temp.render(state), colour == Theme.accent() do
        assert x >= 8
        assert x + 3 <= Theme.width()
        assert y >= Theme.content_top()
        assert y + h <= Theme.height()
      end
    end

    test "emits no background rect" do
      refute Enum.any?(Temp.render(samples(Temp.init(), [22])), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
