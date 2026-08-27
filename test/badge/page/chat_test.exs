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

  defp said(n) do
    for i <- :lists.seq(1, n), do: %{from: "Ana", body: "message " <> :erlang.integer_to_binary(i)}
  end

  defp ups(state, n) do
    :lists.foldl(fn _i, acc -> press(acc, {:move, :up}) end, state, :lists.seq(1, n))
  end

  defp draft_line(state) do
    texts = texts(state)

    :lists.nth(length(texts), texts)
  end

  defp long(n), do: :erlang.list_to_binary(:lists.duplicate(n, ?x))

  defp lefts(state, n) do
    :lists.foldl(fn _i, acc -> press(acc, {:move, :left}) end, state, :lists.seq(1, n))
  end

  defp caret_at(state) do
    {at, 1} = :binary.match(draft_line(state), "_")

    at
  end

  defp counters(state) do
    for {:text, _x, 214, _f, colour, _b, body} <- Chat.render(state),
        colour == Theme.warn() or colour == Theme.alert(),
        do: {body, colour}
  end

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

    test "left arrow moves the cursor back through the draft" do
      state = typed(Chat.init(), "hi") |> press({:move, :left})

      assert Badge.Field.cursor(state.draft) == 1
    end

    test "right arrow moves it forward again" do
      state = typed(Chat.init(), "hi") |> press({:move, :left}) |> press({:move, :right})

      assert Badge.Field.cursor(state.draft) == 2
    end

    test "typing mid-draft inserts rather than appends" do
      state = typed(Chat.init(), "ac") |> press({:move, :left}) |> typed("b")

      assert Badge.Field.value(state.draft) == "abc"
    end

    test "backspace mid-draft removes the character before the cursor" do
      state = typed(Chat.init(), "abc") |> press({:move, :left}) |> press({:edit, :backspace})

      assert Badge.Field.value(state.draft) == "ac"
    end

    test "up and down are left alone, so the router keeps them" do
      assert Chat.handle_key({:move, :up}, Chat.init()) == :ignore
      assert Chat.handle_key({:move, :down}, Chat.init()) == :ignore
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

  describe "a message too long for one line" do
    test "is wrapped across lines instead of being cut" do
      long = "the quick brown fox jumps over the lazy dog and keeps on running"
      shown = texts(heard(Chat.init(), [%{from: "Gus", body: long}]))
      joined = :erlang.iolist_to_binary(shown)

      assert :binary.match(joined, "running") != :nomatch
    end

    test "every line still fits the panel" do
      long = "the quick brown fox jumps over the lazy dog and keeps on running"

      for body <- texts(heard(Chat.init(), [%{from: "Gus", body: long}])) do
        assert 8 * byte_size(body) <= Theme.width()
      end
    end

    test "a single unbroken word is dashed across lines" do
      shown = texts(heard(Chat.init(), [%{from: "A", body: :binary.copy("x", 90)}]))
      joined = :erlang.iolist_to_binary(shown)

      assert :binary.match(joined, "-") != :nomatch
    end

    test "the room never draws more lines than fit above the draft" do
      many = for n <- 1..12, do: %{from: "A", body: "message number #{n} with some length to it"}
      items = Chat.render(heard(Chat.init(), many))

      # A line can carry two items now, the name and the body, so count rows.
      ys = for {:text, _x, y, _f, _c, _b, _body} <- items, y < 206, do: y

      assert length(:lists.usort(ys)) <= 8
    end
  end

  describe "typing past the end of the line" do
    test "keeps the whole draft, showing its tail" do
      long = :binary.copy("a", 30) <> "END"
      state = typed(Chat.init(), long)

      assert Badge.Field.value(state.draft) == long

      shown = :erlang.iolist_to_binary(texts(%{state | link: :joined}))
      assert :binary.match(shown, "END") != :nomatch
    end

    test "the draft line still fits the panel" do
      state = %{typed(Chat.init(), :binary.copy("b", 120)) | link: :joined}

      for body <- texts(state) do
        assert 8 * byte_size(body) <= Theme.width()
      end
    end

    test "a short draft is shown whole, from the start" do
      state = %{typed(Chat.init(), "hi") | link: :joined}
      shown = :erlang.iolist_to_binary(texts(state))

      assert :binary.match(shown, "> hi") != :nomatch
    end
  end

  describe "who said what" do
    defp coloured(state) do
      for {:text, _x, y, _f, colour, _b, body} <- Chat.render(state), y < 206, do: {body, colour}
    end

    test "the name is a different colour from the message" do
      shown = coloured(heard(Chat.init(), [%{from: "Gus", body: "hello", mine: false}]))

      [{_name, name_colour}] = for {b, c} <- shown, :binary.match(b, "Gus") != :nomatch, do: {b, c}
      [{_body, body_colour}] = for {b, c} <- shown, :binary.match(b, "hello") != :nomatch, do: {b, c}

      refute name_colour == body_colour
    end

    test "my own name reads differently from someone else's" do
      mine = coloured(heard(Chat.init(), [%{from: "Me", body: "xyzzy", mine: true}]))
      theirs = coloured(heard(Chat.init(), [%{from: "Me", body: "xyzzy", mine: false}]))

      [{_b, mine_colour}] = for {b, c} <- mine, :binary.match(b, "Me") != :nomatch, do: {b, c}
      [{_b, their_colour}] = for {b, c} <- theirs, :binary.match(b, "Me") != :nomatch, do: {b, c}

      refute mine_colour == their_colour
      assert mine_colour == Theme.select()
    end

    test "the message itself is the same colour whoever sent it" do
      mine = coloured(heard(Chat.init(), [%{from: "Me", body: "xyzzy", mine: true}]))
      theirs = coloured(heard(Chat.init(), [%{from: "Me", body: "xyzzy", mine: false}]))

      [{_b, mine_body}] = for {b, c} <- mine, :binary.match(b, "xyzzy") != :nomatch, do: {b, c}
      [{_b, their_body}] = for {b, c} <- theirs, :binary.match(b, "xyzzy") != :nomatch, do: {b, c}

      assert mine_body == their_body
      assert mine_body == Theme.fg()
    end

    test "a wrapped line keeps the message colour, not the name colour" do
      long = "one two three four five six seven eight nine ten eleven twelve thirteen"
      shown = coloured(heard(Chat.init(), [%{from: "Me", body: long, mine: true}]))

      for {body, colour} <- shown, :binary.match(body, "Me:") == :nomatch do
        assert colour == Theme.fg()
      end
    end

    test "a message with no ownership flag still renders" do
      assert is_list(Chat.render(heard(Chat.init(), [%{from: "A", body: "b"}])))
    end

    test "a long unbroken word is dashed rather than orphaning the name line" do
      body = "kfldlsssldkfjghfklos8iqjkdjmcmcmasoaopaaaa"
      lines = for {b, _c} <- coloured(heard(Chat.init(), [%{from: "Gus", body: body, mine: false}])), do: b

      # The first line carries the name and some of the word, not the name alone.
      assert Enum.any?(lines, &(:binary.match(&1, "-") != :nomatch))
      refute Enum.any?(lines, &(&1 == "Gus:"))
    end
  end

  describe "the caret" do
    test "sits at the end while typing" do
      assert draft_line(typed(Chat.init(), "hi")) == "> hi_"
    end

    test "moves back into the draft with the cursor" do
      state = typed(Chat.init(), "abc") |> press({:move, :left})

      assert draft_line(state) == "> ab_c"
    end

    test "reaches the front of the draft" do
      state =
        typed(Chat.init(), "abc")
        |> press({:move, :left})
        |> press({:move, :left})
        |> press({:move, :left})

      assert draft_line(state) == "> _abc"
    end

    test "a long draft is windowed to the drawn width" do
      assert byte_size(draft_line(typed(Chat.init(), long(60)))) == 35
    end

    test "a windowed draft still ends at the caret" do
      assert caret_at(typed(Chat.init(), long(60))) == 34
    end

    test "the window holds still while the caret walks in from the edge" do
      state = typed(Chat.init(), long(60))

      assert caret_at(press(state, {:move, :left})) == 33
      assert caret_at(lefts(state, 10)) == 24
    end

    test "the caret stops at the middle and the text scrolls instead" do
      state = typed(Chat.init(), long(60))

      assert caret_at(lefts(state, 17)) == 17
      assert caret_at(lefts(state, 30)) == 17
    end

    test "the window reaches the front of a long draft, prompt included" do
      state = lefts(typed(Chat.init(), long(60)), 60)

      assert caret_at(state) == 2
      assert :binary.part(draft_line(state), 0, 3) == "> _"
    end

    test "moving left in a long draft keeps the caret visible" do
      assert :binary.match(draft_line(lefts(typed(Chat.init(), long(60)), 40)), "_") != :nomatch
    end
  end

  describe "the counter" do
    test "stays hidden while there is room" do
      assert Chat.counter_colour(21) == nil
    end

    test "turns yellow as the cap approaches" do
      assert Chat.counter_colour(20) == Theme.warn()
      assert Chat.counter_colour(6) == Theme.warn()
    end

    test "turns red when nearly out" do
      assert Chat.counter_colour(5) == Theme.alert()
      assert Chat.counter_colour(0) == Theme.alert()
    end

    test "is not drawn on a short draft" do
      assert counters(typed(Chat.init(), "hi")) == []
    end

    test "shows the characters left once close to the cap" do
      assert counters(typed(Chat.init(), long(100))) == [{"14", Theme.warn()}]
    end

    test "shows red at the very end" do
      assert counters(typed(Chat.init(), long(112))) == [{"2", Theme.alert()}]
    end

    test "reads zero at the cap and refuses more" do
      state = typed(Chat.init(), long(200))

      assert counters(state) == [{"0", Theme.alert()}]
      assert byte_size(Badge.Field.value(state.draft)) == 114
    end
  end

  describe "the limit" do
    test "three panel lines less the hyphens, before anyone is named" do
      assert Chat.limit_for(nil) == 111
    end

    test "leaves room for the name, colon and space" do
      assert Chat.limit_for("Gustavo") == 111 - 9
    end

    test "a long name eats further into the budget" do
      assert Chat.limit_for("Bartholomew") == 111 - 13
    end

    test "never goes negative on an absurd name" do
      assert Chat.limit_for(long(200)) == 0
    end
  end

  describe "scrolling back" do
    test "the draft is what has focus to begin with" do
      assert Chat.init().selected == nil
    end

    test "up selects the newest message" do
      state = heard(Chat.init(), said(3)) |> press({:move, :up})

      assert state.selected == 0
    end

    test "up again walks towards the oldest" do
      state = heard(Chat.init(), said(3)) |> ups(3)

      assert state.selected == 2
    end

    test "up stops at the oldest held rather than running off" do
      state = heard(Chat.init(), said(3)) |> ups(9)

      assert state.selected == 2
    end

    test "up with nothing heard is left to the router" do
      assert Chat.handle_key({:move, :up}, Chat.init()) == :ignore
    end

    test "down walks back towards the newest" do
      state = heard(Chat.init(), said(3)) |> ups(3) |> press({:move, :down})

      assert state.selected == 1
    end

    test "down from the newest returns to the draft" do
      state = heard(Chat.init(), said(3)) |> press({:move, :up}) |> press({:move, :down})

      assert state.selected == nil
    end

    test "down on the draft is left to the router" do
      assert Chat.handle_key({:move, :down}, Chat.init()) == :ignore
    end

    test "typing snaps back to the draft and lands the character" do
      state = heard(Chat.init(), said(3)) |> ups(2) |> typed("hi")

      assert state.selected == nil
      assert Badge.Field.value(state.draft) == "hi"
    end

    test "backspace snaps back to the draft" do
      state =
        heard(Chat.init(), said(3)) |> typed("hi") |> ups(2) |> press({:edit, :backspace})

      assert state.selected == nil
      assert Badge.Field.value(state.draft) == "h"
    end

    test "left and right snap back so the caret is where you look" do
      state = heard(Chat.init(), said(3)) |> typed("hi") |> ups(2) |> press({:move, :left})

      assert state.selected == nil
      assert Badge.Field.cursor(state.draft) == 1
    end

    test "escape is still left to the router while scrolled" do
      state = heard(Chat.init(), said(3)) |> ups(2)

      assert Chat.handle_key({:nav, :home}, state) == :ignore
    end
  end
end
