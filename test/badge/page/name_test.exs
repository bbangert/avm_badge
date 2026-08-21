defmodule Badge.Page.NameTest do
  use ExUnit.Case, async: true

  alias Badge.Font
  alias Badge.Page.Name
  alias Badge.Profile
  alias Badge.Theme

  defp showing(overrides) do
    %{Name.init() | profile: Map.merge(Profile.blank(), overrides), loaded: true}
  end

  defp press(state, event) do
    {:ok, next} = Name.handle_key(event, state)
    next
  end

  defp press(state, _event, 0), do: state
  defp press(state, event, n), do: press(press(state, event), event, n - 1)

  defp editing(overrides \\ %{name: "Gus"}), do: press(showing(overrides), {:char, ?e})

  defp luminance(colour) do
    r = div(colour, 0x10000)
    g = div(rem(colour, 0x10000), 0x100)
    b = rem(colour, 0x100)

    (r * 30 + g * 59 + b * 11) |> div(100)
  end

  defp type(state, text) do
    :lists.foldl(&press(&2, {:char, &1}), state, :erlang.binary_to_list(text))
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

    test "sit below the name in the hierarchy, so the name reads first" do
      state = showing(%{name: "Gus", company: "Protolux"})

      [name_colour] =
        for {:text, _x, _y, :dogica, colour, _b, _body} <- Name.render(state), do: colour

      [detail_colour] =
        for {:text, _x, _y, :default16px, colour, _b, "Protolux"} <- Name.render(state),
            do: colour

      assert name_colour == Theme.fg()
      assert detail_colour == Theme.muted()
      assert luminance(detail_colour) < luminance(name_colour)
    end

    test "are still brighter than the chrome, so they do not read as a hint" do
      assert luminance(Theme.muted()) > luminance(Theme.dim())
    end

    test "leaves out what has not" do
      bodies = texts(showing(%{name: "Gus"}))

      assert bodies == ["Gus", "E to edit"]
    end

    test "handles are shown with an icon rather than a text marker" do
      state = showing(%{name: "Gus", github: "gusrs", bluesky: "gus.example"})
      bodies = texts(state)

      assert "gusrs" in bodies
      assert "gus.example" in bodies

      icons = for {:image, _x, _y, _bg, _img} <- Name.render(state), do: :icon

      assert length(icons) == 2
    end

    test "every detail line starts at the same x, whatever its icon" do
      state = showing(%{name: "Gus", github: "gusrs", links: "a.example", company: "Protolux"})

      xs =
        for {:text, x, _y, :default16px, _c, _b, body} <- Name.render(state),
            body in ["gusrs", "a.example", "Protolux"],
            do: x

      assert length(xs) == 3
      assert length(:lists.usort(xs)) == 1
    end

    test "each link gets its own icon, not just the first" do
      state = showing(%{name: "Gus", links: "a.example b.example"})
      icons = for {:image, _x, _y, _bg, _img} <- Name.render(state), do: :icon

      assert length(icons) == 2
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
        mastodon: "D",
        bluesky: "E",
        links: "F G H I J K"
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
            {:image, x, y, _bg, _img} -> {x, y}
          end

        assert x >= 0
        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end
  end

  describe "opening the editor" do
    test "E opens it, and so does a capital E" do
      assert editing().mode == :fields
      assert press(showing(%{name: "Gus"}), {:char, ?E}).mode == :fields
    end

    test "the badge itself ignores escape, so the router still goes home" do
      assert Name.handle_key({:nav, :home}, showing(%{name: "Gus"})) == :ignore
    end

    test "other keys on the badge are left alone" do
      assert Name.handle_key({:char, ?z}, showing(%{name: "Gus"})) == :ignore
      assert Name.handle_key({:move, :up}, showing(%{name: "Gus"})) == :ignore
    end
  end

  describe "the field list" do
    test "lists every field with its label" do
      bodies = texts(editing())

      for key <- Profile.keys() do
        assert Profile.label(key) in bodies
      end
    end

    test "starts on the first field" do
      assert Name.selected(editing()) == hd(Profile.keys())
    end

    test "up and down move, and stop at the ends" do
      assert Name.selected(press(editing(), {:move, :down})) == :lists.nth(2, Profile.keys())
      assert Name.selected(press(editing(), {:move, :up})) == hd(Profile.keys())
      assert Name.selected(press(editing(), {:move, :down}, 20)) == :lists.last(Profile.keys())
    end

    test "escape leaves the editor rather than the page" do
      assert press(editing(), {:nav, :home}).mode == :show
    end

    test "an empty required field is called out in the alert colour" do
      blank = press(showing(%{}), {:char, ?e})

      colours =
        for {:text, 88, _y, _f, colour, _b, _body} <- Name.render(blank), do: colour

      assert Theme.alert() in colours
    end

    test "a filled required field is not" do
      colours = for {:text, 88, _y, _f, colour, _b, _body} <- Name.render(editing()), do: colour

      refute Theme.alert() in colours
    end

    test "an empty field shows a placeholder rather than nothing" do
      assert "-" in texts(editing())
    end

    test "a value longer than the column is cut to fit" do
      long = :erlang.list_to_binary(:lists.duplicate(40, ?x))
      state = press(showing(%{name: "Gus", links: long}), {:char, ?e})

      for {:text, 88, _y, _f, _c, _b, body} <- Name.render(state) do
        assert byte_size(body) <= 28
      end
    end
  end

  describe "typing in a field" do
    test "enter opens the highlighted field, prefilled" do
      state = press(editing(), {:edit, :newline})

      assert state.mode == :typing
      assert :binary.match(hd(texts(state)) <> Enum.join(texts(state)), "Gus") != :nomatch
    end

    test "characters and backspace edit it" do
      state = editing() |> press({:edit, :newline}) |> press({:edit, :backspace}) |> type("s")

      assert Badge.Field.value(state.field) == "Gus"
    end

    test "spaces are allowed, since names and links need them" do
      state = editing() |> press({:edit, :newline}) |> type(" Ross")

      assert Badge.Field.value(state.field) == "Gus Ross"
    end

    test "enter commits the value back to the profile" do
      state =
        editing() |> press({:edit, :newline}) |> type(" Ross") |> press({:edit, :newline})

      assert state.mode == :fields
      assert Map.get(state.profile, :name) == "Gus Ross"
    end

    test "escape cancels, leaving the value as it was" do
      state = editing() |> press({:edit, :newline}) |> type(" Ross") |> press({:nav, :home})

      assert state.mode == :fields
      assert Map.get(state.profile, :name) == "Gus"
    end

    test "the field cannot grow past its capacity" do
      long = :erlang.list_to_binary(:lists.duplicate(60, ?x))
      state = editing() |> press({:edit, :newline}) |> type(long)

      assert Badge.Field.value(state.field) |> byte_size() <= Profile.capacity(:name)
    end

    test "the entry screen names the field and says what the keys do" do
      bodies = texts(editing() |> press({:edit, :newline}))

      assert Profile.label(:name) in bodies
      assert Enum.any?(bodies, &(:binary.match(&1, "Esc cancel") != :nomatch))
    end

    test "editing a different field edits that one" do
      state =
        editing()
        |> press({:move, :down})
        |> press({:edit, :newline})
        |> type("Protolux")
        |> press({:edit, :newline})

      assert Map.get(state.profile, :company) == "Protolux"
      assert Map.get(state.profile, :name) == "Gus"
    end
  end

  describe "every editor screen" do
    test "stays inside the panel" do
      states = [editing(), press(editing(), {:edit, :newline})]

      for state <- states, {:text, x, y, _f, _c, _b, body} <- Name.render(state) do
        assert x >= 0
        assert x + 8 * byte_size(body) <= Theme.width()
        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end
  end
end
