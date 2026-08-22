defmodule Badge.Page.ChatTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Chat
  alias Badge.Theme

  defp typed(state, text) do
    :lists.foldl(&press(&2, {:char, &1}), state, :erlang.binary_to_list(text))
  end

  defp press(state, event) do
    {:ok, next} = Chat.handle_key(event, state)
    next
  end

  defp texts(state), do: for({:text, _x, _y, _f, _c, _b, body} <- Chat.render(state), do: body)

  defp heard(state, messages), do: %{state | messages: messages, link: :joined}

  describe "identity" do
    test "announces itself for the home grid" do
      assert Chat.title() == "Chat"
      assert Chat.icon() == :cross
    end

    test "repaints slowly, since a frame is a whole panel" do
      assert Chat.refresh(Chat.init()) == 333
    end
  end

  describe "typing" do
    test "characters land in the draft" do
      assert typed(Chat.init(), "hi").draft |> Badge.Field.value() == "hi"
    end

    test "backspace removes the last character" do
      state = typed(Chat.init(), "hi") |> press({:edit, :backspace})

      assert Badge.Field.value(state.draft) == "h"
    end

    test "the draft is shown while it is being typed" do
      assert Enum.any?(texts(typed(Chat.init(), "hello")), &(:binary.match(&1, "hello") != :nomatch))
    end

    test "enter clears the draft, so a line is not sent twice" do
      state = typed(Chat.init(), "hello") |> press({:edit, :newline})

      assert Badge.Field.value(state.draft) == ""
    end

    test "enter on an empty draft is ignored rather than sending nothing" do
      assert Chat.handle_key({:edit, :newline}, Chat.init()) == :ignore
    end

    test "escape is left to the router, so the page can be left" do
      assert Chat.handle_key({:nav, :home}, Chat.init()) == :ignore
    end
  end

  describe "showing the room" do
    test "an empty room says so rather than looking broken" do
      shown = texts(%{Chat.init() | link: :joined})

      assert Enum.any?(shown, &(:binary.match(&1, "No messages") != :nomatch))
    end

    test "a message is shown with who sent it" do
      shown = texts(heard(Chat.init(), [%{from: "Gus", body: "hello badges"}]))

      assert Enum.any?(shown, &(:binary.match(&1, "Gus") != :nomatch))
      assert Enum.any?(shown, &(:binary.match(&1, "hello badges") != :nomatch))
    end

    test "the newest message is nearest the draft line" do
      state = heard(Chat.init(), [%{from: "A", body: "newest"}, %{from: "B", body: "oldest"}])

      ys =
        for {:text, _x, y, _f, _c, _b, body} <- Chat.render(state),
            :binary.match(body, "est") != :nomatch,
            do: {body, y}

      newest = for {body, y} <- ys, :binary.match(body, "newest") != :nomatch, do: y
      oldest = for {body, y} <- ys, :binary.match(body, "oldest") != :nomatch, do: y

      assert hd(newest) > hd(oldest)
    end

    test "a long message is cut rather than running off the panel" do
      long = :binary.copy("a", 200)
      state = heard(Chat.init(), [%{from: "Gus", body: long}])

      for body <- texts(state) do
        assert 8 * byte_size(body) <= Theme.width()
      end
    end

    test "says when it is not connected, rather than looking empty" do
      shown = texts(%{Chat.init() | link: :offline})

      assert Enum.any?(shown, &(:binary.match(&1, "connecting") != :nomatch))
    end
  end

  describe "render/1" do
    test "emits no background rect, since the router adds it" do
      refute Enum.any?(Chat.render(Chat.init()), fn
               {:rect, 0, 0, 320, 240, _colour} -> true
               _item -> false
             end)
    end
  end
end
