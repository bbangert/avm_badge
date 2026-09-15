defmodule Badge.Page.LispTest do
  use ExUnit.Case, async: true

  alias Badge.Page.Lisp
  alias Badge.Theme

  @input_y Theme.content_top() + 4 + Lisp.visible_rows() * 16

  setup do
    state = Lisp.init()
    on_exit(fn -> Lisp.leave(state) end)
    %{state: state}
  end

  defp type(state, string) do
    :lists.foldl(
      fn char, acc ->
        {:ok, next} = Lisp.handle_key({:char, char}, acc)
        next
      end,
      state,
      :erlang.binary_to_list(string)
    )
  end

  defp enter(state) do
    {:ok, next} = Lisp.handle_key({:edit, :newline}, state)
    next
  end

  # Sends a line and applies the worker's answer, as Badge.UI would.
  defp evaluate(state, line) do
    state = enter(type(state, line))
    worker = state.worker
    assert_receive {:alisp, ^worker, _result} = message
    {:ok, next} = Lisp.handle_info(message, state)
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
      assert Lisp.title() == "Lisp"
      assert Lisp.icon() == :cross
      assert Badge.Pages.for_key(:cross) == Lisp
    end
  end

  describe "init/0 and leave/1" do
    test "starts a worker and leave kills it", %{state: state} do
      ref = Process.monitor(state.worker)

      assert Process.alive?(state.worker)
      Lisp.leave(state)
      assert_receive {:DOWN, ^ref, :process, _pid, :killed}
    end
  end

  describe "typing" do
    test "characters go on the input line with a prompt", %{state: state} do
      items = Lisp.render(type(state, "(+ 1 2)"))

      assert input_line(items) == "> (+ 1 2)"
    end

    test "backspace removes the last character", %{state: state} do
      {:ok, state} = Lisp.handle_key({:edit, :backspace}, type(state, "ab"))

      assert input_line(Lisp.render(state)) == "> a"
    end

    test "left and right move the cursor", %{state: state} do
      state = type(state, "ab")
      at_end = cursor_x(Lisp.render(state))
      {:ok, state} = Lisp.handle_key({:move, :left}, state)

      assert cursor_x(Lisp.render(state)) == at_end - 8
      {:ok, state} = Lisp.handle_key({:move, :right}, state)
      assert cursor_x(Lisp.render(state)) == at_end
    end

    test "a long line scrolls so the cursor stays on screen", %{state: state} do
      state = type(state, :erlang.list_to_binary(:lists.duplicate(50, ?x)))
      items = Lisp.render(state)

      assert byte_size(input_line(items)) == 37
      assert cursor_x(items) <= Theme.width() - 8
    end

    test "tab is ignored", %{state: state} do
      assert Lisp.handle_key({:edit, :tab}, state) == :ignore
    end
  end

  describe "sending a form" do
    test "echoes the line and shows the result", %{state: state} do
      state = evaluate(state, "(+ 1 2)")
      items = Lisp.render(state)

      assert "> (+ 1 2)" in texts(items)
      assert "3" in texts(items)
      assert input_line(items) == "> "
    end

    test "variables persist across forms", %{state: state} do
      state = state |> evaluate("(setq x 5)") |> evaluate("(* x 2)")

      assert "10" in texts(Lisp.render(state))
    end

    test "an unfinished form changes the prompt and completes later", %{state: state} do
      state = enter(type(state, "(list 1"))

      assert input_line(Lisp.render(state)) == ".. "
      state = evaluate(state, "2)")
      assert "(1 2)" in texts(Lisp.render(state))
    end

    test "a busy worker shows a waiting prompt and refuses another line", %{state: state} do
      state = enter(type(state, "(+ 1 2)"))

      assert input_line(Lisp.render(state)) == "* "
      assert Lisp.handle_key({:edit, :newline}, type(state, "1")) == :ignore
    end

    test "errors are shown in the alert colour", %{state: state} do
      state = evaluate(state, "nope")

      assert Enum.any?(Lisp.render(state), fn
               {:text, _x, _y, _f, fg, _bg, "(tuple throw (tuple unbound nope))"} ->
                 fg == Theme.alert()

               _item ->
                 false
             end)
    end

    test "an unreadable line is reported without asking the worker", %{state: state} do
      state = enter(type(state, ")"))
      worker = state.worker

      assert "unbalanced )" in texts(Lisp.render(state))
      refute_receive {:alisp, ^worker, _result}
    end

    test "answers from a previous worker are ignored", %{state: state} do
      assert Lisp.handle_info({:alisp, self(), {:ok, "1"}}, state) == :ignore
    end
  end

  describe "history" do
    test "up recalls earlier lines and down returns to an empty one", %{state: state} do
      state = state |> evaluate("1") |> evaluate("2")
      {:ok, state} = Lisp.handle_key({:move, :up}, state)

      assert input_line(Lisp.render(state)) == "> 2"
      {:ok, state} = Lisp.handle_key({:move, :up}, state)
      assert input_line(Lisp.render(state)) == "> 1"
      {:ok, state} = Lisp.handle_key({:move, :up}, state)
      assert input_line(Lisp.render(state)) == "> 1"
      {:ok, state} = Lisp.handle_key({:move, :down}, state)
      {:ok, state} = Lisp.handle_key({:move, :down}, state)
      assert input_line(Lisp.render(state)) == "> "
    end

    test "empty lines are not remembered", %{state: state} do
      {:ok, state} = Lisp.handle_key({:move, :up}, enter(state))

      assert input_line(Lisp.render(state)) == "> "
    end
  end

  describe "tick/1" do
    test "is inert while idle", %{state: state} do
      assert Lisp.tick(state) == state
    end

    test "kills a form that runs too long and starts a fresh worker", %{state: state} do
      state = enter(type(state, "(do ((i 0 i)) ((= i 1) i))"))
      old = state.worker
      ref = Process.monitor(old)

      state = :lists.foldl(fn _n, acc -> Lisp.tick(acc) end, state, :lists.seq(1, 51))

      assert_receive {:DOWN, ^ref, :process, ^old, :killed}
      assert state.worker != old
      assert state.busy == 0
      assert "timeout, variables lost" in texts(Lisp.render(state))
      Lisp.leave(state)
    end
  end

  describe "render/1" do
    test "the cursor is the first item", %{state: state} do
      assert [{:rect, _x, _y, 8, 2, _c} | _rest] = Lisp.render(state)
    end

    test "output wraps to the panel width and keeps only what fits", %{state: state} do
      long = :erlang.list_to_binary(:lists.duplicate(100, ?a))
      lines = for n <- 1..20, do: {:out, long <> :erlang.integer_to_binary(n)}

      rows = Lisp.window(lines)

      assert length(rows) == Lisp.visible_rows()
      assert Enum.all?(rows, fn {:out, text} -> byte_size(text) <= 38 end)
      assert :lists.last(rows) == {:out, :erlang.list_to_binary(:lists.duplicate(24, ?a)) <> "1"}
    end

    test "content starts below the title bar", %{state: state} do
      items = Lisp.render(evaluate(state, "1"))
      ys = for {:text, _x, y, _f, _fg, _bg, _body} <- items, do: y

      assert :lists.min(ys) >= Theme.content_top()
    end
  end
end
