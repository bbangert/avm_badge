defmodule Badge.Page.NameTest do
  use ExUnit.Case, async: true

  alias Badge.Font
  alias Badge.Page.Name
  alias Badge.Profile
  alias Badge.Theme

  defp showing(overrides) do
    %{profile: Map.merge(Profile.blank(), overrides), loaded: true}
  end

  defp texts(state), do: for({:text, _x, _y, _f, _c, _b, body} <- Name.render(state), do: body)

  defp name_lines(state) do
    for {:text, _x, _y, :dogica, _c, _b, body} <- Name.render(state), do: body
  end

  defp rule_y(state) do
    [y] =
      for {:rect, _x, y, _w, _h, colour} <- Name.render(state), colour == Theme.accent(), do: y

    y
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Name.title() == "Name"
      assert Name.icon() == :diamond
    end

    test "does not trap escape" do
      assert Name.handle_key({:nav, :home}, Name.init()) == :ignore
    end
  end

  describe "the name" do
    test "a short name is one line" do
      assert name_lines(showing(%{name: "Gus"})) == ["Gus"]
    end

    test "an empty name falls back rather than showing a blank badge" do
      assert name_lines(showing(%{})) == [Profile.placeholder()]
    end

    test "a name that exactly fills the line stays on one" do
      exact = :erlang.list_to_binary(:lists.duplicate(Name.columns(), ?x))

      assert name_lines(showing(%{name: exact})) == [exact]
    end

    test "a long name breaks at the space" do
      assert name_lines(showing(%{name: "Bartholomew Cubbins"})) == ["Bartholomew", "Cubbins"]
    end

    test "a long name with no space is cut rather than running off the panel" do
      lines = name_lines(showing(%{name: "Wolfeschlegelsteinhausen"}))

      assert length(lines) == 2
      assert hd(lines) == "Wolfeschlegelstein"
    end

    test "no name line is wider than the panel" do
      for name <- ["Gus", "Alexander Hamilton", "Wolfeschlegelsteinhausenbergerdorff"] do
        for line <- name_lines(showing(%{name: name})) do
          assert 16 + Font.advance(:dogica) * byte_size(line) <= Theme.width()
        end
      end
    end

    test "the column count matches what actually fits" do
      assert Name.columns() == div(Theme.width() - 32, Font.advance(:dogica))
    end
  end

  describe "the rule" do
    test "sits under a one-line name" do
      assert rule_y(showing(%{name: "Gus"})) > Theme.content_top()
    end

    test "moves down when the name takes two lines" do
      assert rule_y(showing(%{name: "Bartholomew Cubbins"})) > rule_y(showing(%{name: "Gus"}))
    end

    test "never overlaps the last line of the name" do
      for name <- ["Gus", "Bartholomew Cubbins"] do
        state = showing(%{name: name})

        lowest =
          :lists.max(for {:text, _x, y, :dogica, _c, _b, _body} <- Name.render(state), do: y)

        assert rule_y(state) > lowest
      end
    end
  end

  describe "the details" do
    test "shows what has been filled in" do
      bodies = texts(showing(%{name: "Gus", company: "Protolux", email: "gus@example.com"}))

      assert "Protolux" in bodies
      assert "gus@example.com" in bodies
    end

    test "leaves out what has not" do
      bodies = texts(showing(%{name: "Gus"}))

      assert bodies == ["Gus", "E to edit"]
    end

    test "marks the handles so they read as handles" do
      bodies = texts(showing(%{name: "Gus", github: "gusrs", bluesky: "gus.example"}))

      assert "gh gusrs" in bodies
      assert "@gus.example" in bodies
    end

    test "gives each link its own line" do
      bodies = texts(showing(%{name: "Gus", links: "one.example two.example"}))

      assert "one.example" in bodies
      assert "two.example" in bodies
    end

    test "drops details that would collide with the hint" do
      full = %{
        name: "Bartholomew Cubbins",
        company: "A",
        email: "B",
        github: "C",
        bluesky: "D",
        links: "E F G H I J",
        note: "K"
      }

      for {:text, _x, y, _f, _c, _b, _body} <- Name.render(showing(full)) do
        assert y <= 216
      end
    end
  end

  describe "render/1" do
    test "tells you how to edit" do
      assert "E to edit" in texts(showing(%{name: "Gus"}))
    end

    test "emits no background rect" do
      refute Enum.any?(Name.render(showing(%{name: "Gus"})), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end

    test "everything sits inside the panel" do
      for item <- Name.render(showing(%{name: "Bartholomew Cubbins", company: "Protolux"})) do
        {x, y} =
          case item do
            {:rect, x, y, _w, _h, _c} -> {x, y}
            {:text, x, y, _f, _c, _b, _body} -> {x, y}
          end

        assert x >= 0
        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end
  end
end
