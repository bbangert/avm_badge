defmodule Badge.Page.ReplTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Repl
  alias Badge.Theme

  @input_y Theme.content_top() + 4 + Repl.visible_rows() * 16

  setup do
    state = Repl.init()
    on_exit(fn -> Repl.leave(state) end)
    %{state: state}
  end

  defp type(state, string) do
    :lists.foldl(
      fn char, acc ->
        {:ok, next} = Repl.handle_key({:char, char}, acc)
        next
      end,
      state,
      :erlang.binary_to_list(string)
    )
  end

  defp key(state, event) do
    {:ok, next} = Repl.handle_key(event, state)
    next
  end

  defp enter(state), do: key(state, {:edit, :newline})

  defp worker(state), do: Map.get(state.langs, state.lang).worker

  # Sends a line and applies the worker's answer, as Badge.UI would.
  defp evaluate(state, line) do
    state = enter(type(state, line))
    worker = worker(state)
    assert_receive {:repl, ^worker, _result} = message
    {:ok, next} = Repl.handle_info(message, state)
    next
  end

  defp texts(items), do: for({:text, _x, _y, _f, _fg, _bg, body} <- items, do: body)

  defp input_line(items) do
    [line] = for {:text, _x, @input_y, _f, _fg, _bg, body} <- items, do: body
    line
  end

  defp cursor_x(items) do
    [{:rect, x, _y, 8, 2, _c} | _rest] = items
    x
  end

  describe "identity" do
    test "takes the cross slot the Text page had" do
      assert Repl.title() == "REPL"
      assert Repl.icon() == :cross
      assert Badge.Pages.for_key(:cross) == Repl
    end
  end

  describe "init/0 and leave/1" do
    test "starts a worker per language and leave kills them", %{state: state} do
      elixir = Map.get(state.langs, :elixir).worker
      lisp = Map.get(state.langs, :lisp).worker
      refs = [Process.monitor(elixir), Process.monitor(lisp)]

      Repl.leave(state)

      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, :killed})
    end

    test "starts in Elixir", %{state: state} do
      assert input_line(Repl.render(state)) == "ex> "
    end
  end

  describe "typing" do
    test "characters go on the input line after the prompt", %{state: state} do
      assert input_line(Repl.render(type(state, "1 + 2"))) == "ex> 1 + 2"
    end

    test "backspace removes the last character", %{state: state} do
      state = state |> type("ab") |> key({:edit, :backspace})

      assert input_line(Repl.render(state)) == "ex> a"
    end

    test "left and right move the cursor", %{state: state} do
      state = type(state, "ab")
      at_end = cursor_x(Repl.render(state))
      state = key(state, {:move, :left})

      assert cursor_x(Repl.render(state)) == at_end - 8
      assert cursor_x(Repl.render(key(state, {:move, :right}))) == at_end
    end

    test "a long line scrolls so the cursor stays on screen", %{state: state} do
      items = Repl.render(type(state, :erlang.list_to_binary(:lists.duplicate(50, ?x))))

      assert byte_size(input_line(items)) == 38 - 1
      assert cursor_x(items) <= Theme.width() - 8
    end
  end

  describe "switching language" do
    test "tab moves to Lisp and back, noting it in the output", %{state: state} do
      state = key(type(state, "abc"), {:edit, :tab})
      items = Repl.render(state)

      assert input_line(items) == "> "
      assert "-- Lisp" in texts(items)
      assert input_line(Repl.render(key(state, {:edit, :tab}))) == "ex> "
    end

    test "each language keeps its own bindings", %{state: state} do
      state = state |> evaluate("x = 1") |> key({:edit, :tab}) |> evaluate("(setq x 2)")
      state = state |> key({:edit, :tab}) |> evaluate("x + 10")

      assert "11" in texts(Repl.render(state))
    end
  end

  describe "sending Elixir" do
    test "echoes the line and shows the result", %{state: state} do
      items = Repl.render(evaluate(state, "1 + 2"))

      assert "ex> 1 + 2" in texts(items)
      assert "3" in texts(items)
      assert input_line(items) == "ex> "
    end

    test "bindings persist across lines", %{state: state} do
      state = state |> evaluate("x = 5") |> evaluate("x * 2")

      assert "10" in texts(Repl.render(state))
    end

    test "an open bracket changes the prompt and completes later", %{state: state} do
      state = enter(type(state, "[1,"))

      assert input_line(Repl.render(state)) == "..> "
      assert "[1, 2]" in texts(Repl.render(evaluate(state, "2]")))
    end

    test "a busy worker shows a waiting prompt and refuses another line", %{state: state} do
      state = enter(type(state, "1 + 2"))

      assert input_line(Repl.render(state)) == "* "
      assert Repl.handle_key({:edit, :newline}, type(state, "1")) == :ignore
    end

    test "errors are shown in the alert colour", %{state: state} do
      state = evaluate(state, "nope")

      assert Enum.any?(Repl.render(state), fn
               {:text, _x, _y, _f, fg, _bg, "** (CompileError) undefined variable n"} ->
                 fg == Theme.alert()

               _item ->
                 false
             end)
    end
  end

  describe "sending Lisp" do
    test "evaluates after a switch", %{state: state} do
      state = state |> key({:edit, :tab}) |> evaluate("(+ 1 2)")
      items = Repl.render(state)

      assert "> (+ 1 2)" in texts(items)
      assert "3" in texts(items)
    end

    test "an unreadable line is reported without asking the worker", %{state: state} do
      state = enter(type(key(state, {:edit, :tab}), ")"))
      worker = worker(state)

      assert "unbalanced )" in texts(Repl.render(state))
      refute_receive {:repl, ^worker, _result}
    end
  end

  describe "handle_info/2" do
    test "answers from an unknown worker are ignored", %{state: state} do
      assert Repl.handle_info({:repl, self(), {:ok, "1"}}, state) == :ignore
    end

    test "an answer for the other language still lands", %{state: state} do
      state = key(enter(type(state, "1 + 2")), {:edit, :tab})
      worker = Map.get(state.langs, :elixir).worker
      assert_receive {:repl, ^worker, _result} = message
      {:ok, state} = Repl.handle_info(message, state)

      assert "3" in texts(Repl.render(state))
      assert Map.get(state.langs, :elixir).busy == 0
    end
  end

  describe "history" do
    test "up recalls earlier lines and down returns to an empty one", %{state: state} do
      state = state |> evaluate("1") |> evaluate("2") |> key({:move, :up})

      assert input_line(Repl.render(state)) == "ex> 2"
      state = key(state, {:move, :up})
      assert input_line(Repl.render(state)) == "ex> 1"
      assert input_line(Repl.render(key(state, {:move, :up}))) == "ex> 1"
      state = state |> key({:move, :down}) |> key({:move, :down})
      assert input_line(Repl.render(state)) == "ex> "
    end

    test "empty lines are not remembered", %{state: state} do
      state = state |> enter() |> key({:move, :up})

      assert input_line(Repl.render(state)) == "ex> "
    end
  end

  describe "tick/1" do
    test "is inert while idle", %{state: state} do
      assert Repl.tick(state) == state
    end

    test "kills a line that runs too long and starts a fresh worker", %{state: state} do
      state = enter(type(state, "Process.sleep(60000)"))
      old = worker(state)
      ref = Process.monitor(old)

      state = :lists.foldl(fn _n, acc -> Repl.tick(acc) end, state, :lists.seq(1, 51))

      assert_receive {:DOWN, ^ref, :process, ^old, :killed}
      assert worker(state) != old
      assert Map.get(state.langs, :elixir).busy == 0
      assert "timeout, bindings lost" in texts(Repl.render(state))
      Repl.leave(state)
    end
  end

  describe "render/1" do
    test "the cursor is the first item", %{state: state} do
      assert [{:rect, _x, _y, 8, 2, _c} | _rest] = Repl.render(state)
    end

    test "output wraps to the panel width and keeps only what fits" do
      long = :erlang.list_to_binary(:lists.duplicate(100, ?a))
      lines = for n <- 1..20, do: {:out, long <> :erlang.integer_to_binary(n)}

      rows = Repl.window(lines)

      assert length(rows) == Repl.visible_rows()
      assert Enum.all?(rows, fn {:out, text} -> byte_size(text) <= 38 end)
      assert :lists.last(rows) == {:out, :erlang.list_to_binary(:lists.duplicate(24, ?a)) <> "1"}
    end

    test "content starts below the title bar", %{state: state} do
      items = Repl.render(evaluate(state, "1"))
      ys = for {:text, _x, y, _f, _fg, _bg, _body} <- items, do: y

      assert :lists.min(ys) >= Theme.content_top()
    end
  end
end
