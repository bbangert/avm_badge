defmodule Badge.Page.HomeTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Home
  alias Badge.Pages
  alias Badge.Theme

  defp assigned, do: for({_key, module} <- Pages.all(), module != nil, do: module)

  defp icons(items) do
    for {:scaled_cropped_image, _x, _y, _w, _h, _bg, _sx, _sy, _xs, _ys, _o, _img} <- items,
        do: :icon
  end

  defp texts(items) do
    for {:text, _x, _y, _font, _fg, _bg, body} <- items, do: body
  end

  describe "identity" do
    test "has a title for the bar" do
      assert Home.title() == "Badge"
    end
  end

  describe "render/1" do
    test "one icon per assigned page" do
      items = Home.render(Home.init())

      assert length(icons(items)) == length(assigned())
    end

    test "one label per assigned page, and it is the page's own title" do
      items = Home.render(Home.init())

      for module <- assigned() do
        assert module.title() in texts(items)
      end
    end

    test "draws the dividing rules" do
      rules =
        for {:rect, _x, _y, _w, _h, colour} <- Home.render(Home.init()),
            colour == Theme.dim(),
            do: :rule

      assert length(rules) == 3
    end

    test "emits no background rect, since the router supplies it" do
      refute Enum.any?(Home.render(Home.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end

    test "every item sits inside the content area" do
      for item <- Home.render(Home.init()) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
            {:scaled_cropped_image, _x, y, _w, _h, _bg, _sx, _sy, _xs, _ys, _o, _i} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end

    test "every item sits inside the panel horizontally" do
      for item <- Home.render(Home.init()) do
        {x, w} =
          case item do
            {:rect, x, _y, w, _h, _c} -> {x, w}
            {:text, x, _y, _f, _fg, _bg, body} -> {x, byte_size(body) * 8}
            {:scaled_cropped_image, x, _y, w, _h, _bg, _sx, _sy, _xs, _ys, _o, _i} -> {x, w}
          end

        assert x >= 0
        assert x + w <= Theme.width()
      end
    end
  end

  describe "inertness" do
    test "ignores every key, since navigation is the router's job" do
      assert Home.handle_key({:char, ?a}, :ok) == :ignore
      assert Home.handle_key({:move, :up}, :ok) == :ignore
    end

    test "never goes dirty on its own" do
      assert Home.tick(:ok) == :ok
    end
  end
end
