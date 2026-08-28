defmodule Badge.Page.TextTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Text
  alias Badge.TextBuffer

  defp type(state, string) do
    :lists.foldl(
      fn char, acc ->
        {:ok, next} = Text.handle_key({:char, char}, acc)
        next
      end,
      state,
      :erlang.binary_to_list(string)
    )
  end

  defp texts(items) do
    for {:text, _x, _y, _font, _fg, _bg, body} <- items, do: body
  end

  describe "identity" do
    test "announces itself for the home grid" do
      assert Text.title() == "Text"
      assert Text.icon() == :cross
    end
  end

  describe "init/0" do
    test "starts on an empty buffer sized to the content area" do
      state = Text.init()

      assert TextBuffer.cursor(state) == {0, 0}
      assert length(TextBuffer.lines(state)) == 12
    end
  end

  describe "handle_key/2" do
    test "characters reach the buffer" do
      state = type(Text.init(), "hi")

      assert TextBuffer.cursor(state) == {2, 0}
    end

    test "backspace removes the last character" do
      {:ok, state} = Text.handle_key({:edit, :backspace}, type(Text.init(), "hi"))

      assert TextBuffer.cursor(state) == {1, 0}
    end

    test "newline moves to the next row" do
      {:ok, state} = Text.handle_key({:edit, :newline}, type(Text.init(), "hi"))

      assert TextBuffer.cursor(state) == {0, 1}
    end

    test "tab advances to the next multiple of four" do
      {:ok, state} = Text.handle_key({:edit, :tab}, type(Text.init(), "h"))

      assert TextBuffer.cursor(state) == {4, 0}
    end

    test "arrows and anything else are ignored" do
      state = Text.init()

      assert Text.handle_key({:move, :up}, state) == :ignore
      assert Text.handle_key({:move, :left}, state) == :ignore
    end
  end

  describe "tick/1" do
    test "is inert, so an untouched page never redraws" do
      state = type(Text.init(), "hello")

      assert Text.tick(state) == state
    end
  end

  describe "render/1" do
    test "draws the typed line" do
      items = Text.render(type(Text.init(), "hello"))

      assert "hello" in texts(items)
    end

    test "emits no background rect, since the router supplies it" do
      items = Text.render(type(Text.init(), "hello"))

      refute Enum.any?(items, fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end

    test "the cursor is the first item, so it draws on top" do
      [first | _rest] = Text.render(Text.init())

      assert {:rect, _x, _y, 8, 2, _colour} = first
    end

    test "the cursor advances one cell per character" do
      [{:rect, x0, _y0, _w, _h, _c} | _] = Text.render(Text.init())
      [{:rect, x1, _y1, _w1, _h1, _c1} | _] = Text.render(type(Text.init(), "a"))

      assert x1 - x0 == 8
    end

    test "the cursor never runs past the right edge" do
      full = type(Text.init(), :erlang.list_to_binary(:lists.duplicate(39, ?x)))
      [{:rect, x, _y, _w, _h, _c} | _] = Text.render(full)

      assert x <= 320 - 8
    end

    test "empty lines produce no text item" do
      items = Text.render(Text.init())

      assert texts(items) == []
    end

    test "content starts below the title bar" do
      items = Text.render(type(Text.init(), "hello"))
      ys = for {:text, _x, y, _f, _fg, _bg, _body} <- items, do: y

      assert :lists.min(ys) >= Badge.Theme.content_top()
    end
  end
end
