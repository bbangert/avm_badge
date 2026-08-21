defmodule Badge.Page.NameTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Name
  alias Badge.Theme

  defp texts do
    for {:text, _x, _y, _f, _fg, _bg, body} <- Name.render(:ok), do: body
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Name.title() == "Name"
      assert Name.icon() == :diamond
    end
  end

  describe "render/1" do
    test "shows the name and the tagline" do
      assert Name.name() in texts()
      assert Name.tagline() in texts()
    end

    test "the name uses the largest available font" do
      fonts =
        for {:text, _x, _y, font, _fg, _bg, body} <- Name.render(:ok),
            body == Name.name(),
            do: font

      assert fonts == [:dogica]
    end

    test "the tagline is centred, which only default16px permits" do
      [{x, font}] =
        for {:text, x, _y, font, _fg, _bg, body} <- Name.render(:ok),
            body == Name.tagline(),
            do: {x, font}

      assert font == :default16px
      assert x == div(Theme.width() - 8 * byte_size(Name.tagline()), 2)
    end

    test "draws an accent rule" do
      rules =
        for {:rect, _x, _y, _w, _h, colour} <- Name.render(:ok),
            colour == Theme.accent(),
            do: :rule

      assert length(rules) == 1
    end

    test "is inert" do
      assert Name.tick(:ok) == :ok
      assert Name.handle_key({:char, ?a}, :ok) == :ignore
    end

    test "every item sits inside the content area" do
      for item <- Name.render(:ok) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end

    test "the tagline fits the panel" do
      assert 8 * byte_size(Name.tagline()) <= Theme.width()
    end

    test "emits no background rect" do
      refute Enum.any?(Name.render(:ok), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
