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

  defp strip(state) do
    [body | _rest] = for {:text, _x, _y, _f, _fg, _bg, body} <- Info.render(state), do: body

    body
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

    test "the strip brackets the active sub-page and only that one" do
      state = Info.init()
      [first | _rest] = titles()

      assert :binary.match(strip(state), "[" <> first <> "]") != :nomatch

      for other <- tl(titles()) do
        assert :binary.match(strip(state), "[" <> other <> "]") == :nomatch
      end
    end

    test "the strip names every sub-page wherever you are" do
      for title <- titles() do
        assert :binary.match(strip(Info.init()), title) != :nomatch
      end
    end

    test "the strip follows the carousel" do
      [_first, second | _rest] = titles()

      assert :binary.match(strip(right(Info.init())), "[" <> second <> "]") != :nomatch
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

      assert hd(ys) == Theme.content_top()
      assert Enum.all?(tl(ys), fn y -> y >= Info.content_top() end)
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

    test "the strip fits the panel" do
      assert 8 * byte_size(strip(Info.init())) <= Theme.width()
    end

    test "emits no background rect, since the router supplies it" do
      refute Enum.any?(Info.render(Info.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
