defmodule Badge.Page.SoonTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Soon
  alias Badge.Theme

  defp bodies, do: for({:text, _x, _y, _f, _c, _b, body} <- Soon.render(Soon.init()), do: body)

  describe "the slot that is not built yet" do
    test "announces itself for the home grid" do
      assert Soon.title() == "Soon"
      assert Soon.icon() == :cross
    end

    test "says plainly that it does nothing" do
      assert Enum.any?(bodies(), &(:binary.match(&1, "not built") != :nomatch))
    end

    test "does not trap escape" do
      assert Soon.handle_key({:nav, :home}, Soon.init()) == :ignore
    end

    test "claims no key at all" do
      for event <- [{:char, ?a}, {:move, :left}, {:move, :right}, {:edit, :newline}] do
        assert Soon.handle_key(event, Soon.init()) == :ignore
      end
    end

    test "its text fits the panel" do
      for body <- bodies() do
        assert 8 * byte_size(body) <= Theme.width()
      end
    end

    test "emits no background rect, since the router adds it" do
      refute Enum.any?(Soon.render(Soon.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
