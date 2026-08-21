defmodule Badge.Page.InfoTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Info
  alias Badge.Theme

  defp right(state) do
    {:ok, next} = Info.handle_key({:move, :right}, state)
    next
  end

  defp left(state) do
    {:ok, next} = Info.handle_key({:move, :left}, state)
    next
  end

  defp tabs(state) do
    for {:text, _x, y, _f, colour, _bg, body} <- Info.render(state),
        y == Theme.content_top(),
        body != " | ",
        do: {body, colour}
  end

  defp active(state) do
    [title] = for {title, colour} <- tabs(state), colour == Theme.select(), do: title

    title
  end

  defp titles, do: for(module <- Info.subpages(), do: module.title())

  describe "identity" do
    test "announces itself for the home grid" do
      assert Info.title() == "Info"
      assert Info.icon() == :circle
    end

    test "repaints slowly, since a frame is a whole panel" do
      assert Info.refresh() == 333
    end
  end

  describe "carousel" do
    test "starts on the first sub-page" do
      assert Info.init().index == 0
    end

    test "right steps forward" do
      assert right(Info.init()).index == 1
    end

    test "left from the first wraps to the last" do
      assert left(Info.init()).index == length(Info.subpages()) - 1
    end

    test "right from the last wraps to the first" do
      last = :lists.foldl(fn _i, acc -> right(acc) end, Info.init(), Info.subpages())

      assert last.index == 0
    end

    test "left and right are inverses" do
      assert left(right(Info.init())) == Info.init()
    end

    test "exactly one tab is highlighted, and it is the active one" do
      [first | _rest] = titles()

      assert active(Info.init()) == first
    end

    test "every other tab is dim" do
      dim = for {title, colour} <- tabs(Info.init()), colour == Theme.dim(), do: title

      assert dim == tl(titles())
    end

    test "the strip names every sub-page wherever you are" do
      assert for({title, _colour} <- tabs(Info.init()), do: title) == titles()
    end

    test "the highlight follows the carousel" do
      [_first, second | _rest] = titles()

      assert active(right(Info.init())) == second
    end

    test "the highlight wraps with the carousel" do
      assert active(left(Info.init())) == :lists.last(titles())
    end
  end

  describe "key routing" do
    test "escape is not trapped, so the router can still go home" do
      assert Info.handle_key({:nav, :home}, Info.init()) == :ignore
    end

    test "a key no sub-page wants is ignored rather than swallowed" do
      assert Info.handle_key({:char, ?z}, Info.init()) == :ignore
    end

    test "arrows the sub-pages ignore move the carousel" do
      refute right(Info.init()).index == Info.init().index
    end

    test "up and down are left for sub-pages and do not move the carousel" do
      assert Info.handle_key({:move, :up}, Info.init()) == :ignore
      assert Info.handle_key({:move, :down}, Info.init()) == :ignore
    end
  end

  describe "sub-page state" do
    test "one state per sub-page" do
      assert length(Info.init().states) == length(Info.subpages())
    end

    test "survives sliding away and back" do
      state = Info.init()
      touched = %{state | states: [:touched | tl(state.states)]}

      assert hd(left(right(touched)).states) == :touched
    end

    test "moving the carousel leaves every sub-page's state alone" do
      state = Info.init()

      assert right(state).states == state.states
      assert left(state).states == state.states
    end

    # tick/1 delegates to the active sub-page, which reads hardware. That one
    # line is the untestable seam; what it writes back is covered above.
  end

  describe "render/1" do
    test "draws the strip above everything a sub-page draws" do
      ys = for {:text, _x, y, _f, _fg, _bg, _body} <- Info.render(Info.init()), do: y
      {strip, content} = :lists.partition(fn y -> y == Theme.content_top() end, ys)

      # The strip is several items now: a tab each, and a separator between.
      assert length(strip) == 2 * length(Info.subpages()) - 1
      assert content != []
      assert Enum.all?(content, fn y -> y >= Info.content_top() end)
    end

    test "the strip clears the sub-page content area" do
      assert Info.content_top() > Theme.content_top()
    end

    test "every item sits inside the content area" do
      for item <- Info.render(Info.init()) do
        y =
          case item do
            {:rect, _x, y, _w, _h, _c} -> y
            {:text, _x, y, _f, _fg, _bg, _b} -> y
          end

        assert y >= Theme.content_top()
        assert y < Theme.height()
      end
    end

    test "the strip fits the panel and does not overlap itself" do
      placed =
        for {:text, x, y, _f, _c, _bg, body} <- Info.render(Info.init()),
            y == Theme.content_top(),
            do: {x, x + 8 * byte_size(body)}

      assert Enum.all?(placed, fn {left, right} -> left >= 0 and right <= Theme.width() end)

      sorted = :lists.sort(placed)
      pairs = :lists.zip(sorted, tl(sorted) ++ [{Theme.width(), Theme.width()}])

      assert Enum.all?(pairs, fn {{_l, right}, {next_left, _r}} -> right <= next_left end)
    end

    test "emits no background rect, since the router supplies it" do
      refute Enum.any?(Info.render(Info.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
