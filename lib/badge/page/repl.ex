defmodule Badge.Page.Repl do
  @moduledoc """
  A prompt for `Badge.Alisp` and `Badge.Elixir`.

  The last row is the input line; what came before scrolls up above it,
  newest at the bottom. Enter sends the line, Tab switches language, up and
  down walk the lines sent before, left and right move within the line.
  Each language keeps its own worker, so bindings survive a switch. A line
  that has not answered after a few seconds is killed, and its bindings
  with it.
  """

  use Badge.Page

  alias Badge.Alisp
  alias Badge.Field
  alias Badge.Theme

  @fg Theme.fg()
  @bg Theme.bg()
  @muted Theme.muted()
  @alert Theme.alert()

  @x 8
  @top Theme.content_top() + 4
  @pitch 16
  @char_w 8
  @columns div(Theme.width() - 2 * @x, @char_w)
  @rows div(Theme.height() - @top, @pitch)
  @scrollback @rows - 1
  @input_y @top + @scrollback * @pitch

  @keep 40
  @capacity 120
  @history 20
  @timeout_ticks 50

  @langs [:elixir, :lisp]

  @impl true
  def title, do: "REPL"

  @impl true
  def icon, do: :cross

  @impl true
  def init do
    %{
      lang: :elixir,
      langs: %{elixir: fresh(:elixir), lisp: fresh(:lisp)},
      lines: [],
      field: Field.new(@capacity),
      history: [],
      recall: 0
    }
  end

  @impl true
  def leave(state) do
    :lists.foreach(fn lang -> mod(lang).stop(current(state, lang).worker) end, @langs)
  end

  @impl true
  def handle_key({:char, char}, state), do: {:ok, edit(state, Field.insert(state.field, char))}
  def handle_key({:edit, :backspace}, state), do: {:ok, edit(state, Field.backspace(state.field))}
  def handle_key({:move, :left}, state), do: {:ok, edit(state, Field.left(state.field))}
  def handle_key({:move, :right}, state), do: {:ok, edit(state, Field.right(state.field))}
  def handle_key({:move, :up}, state), do: {:ok, recall(state, state.recall + 1)}
  def handle_key({:move, :down}, state), do: {:ok, recall(state, state.recall - 1)}
  def handle_key({:edit, :tab}, state), do: {:ok, switch(state)}

  def handle_key({:edit, :newline}, state) do
    case current(state).busy do
      0 -> {:ok, submit(state)}
      _busy -> :ignore
    end
  end

  def handle_key(_event, _state), do: :ignore

  @impl true
  def handle_info({:repl, worker, result}, state) do
    case owner(state, worker) do
      nil -> :ignore
      lang -> {:ok, answered(state, lang, result)}
    end
  end

  def handle_info(_message, _state), do: :ignore

  @impl true
  def tick(state) do
    case current(state) do
      %{busy: 0} -> state
      %{busy: busy} when busy > @timeout_ticks -> timed_out(state)
      %{busy: busy} = lang -> put_current(state, %{lang | busy: busy + 1})
    end
  end

  @impl true
  def render(state) do
    [cursor(state), input(state) | output(state)]
  end

  @doc "The visible rows of output, oldest first, as `{kind, text}`."
  def window(lines), do: window(lines, @scrollback, [])

  @doc "How many rows of output fit above the input line."
  def visible_rows, do: @scrollback

  defp mod(:lisp), do: Alisp
  defp mod(:elixir), do: Badge.Elixir

  defp label(:lisp), do: "Lisp"
  defp label(:elixir), do: "Elixir"

  defp fresh(lang), do: %{session: mod(lang).new(), worker: mod(lang).start(self()), busy: 0}

  defp current(state), do: current(state, state.lang)
  defp current(state, lang), do: Map.get(state.langs, lang)

  defp put_current(state, lang_state) do
    %{state | langs: Map.put(state.langs, state.lang, lang_state)}
  end

  defp owner(state, worker) do
    :lists.foldl(
      fn lang, found -> if current(state, lang).worker == worker, do: lang, else: found end,
      nil,
      @langs
    )
  end

  defp edit(state, field), do: %{state | field: field}

  defp switch(state) do
    lang = other(state.lang)
    %{push(state, :in, "-- " <> label(lang)) | lang: lang, field: Field.new(@capacity), recall: 0}
  end

  defp other(:lisp), do: :elixir
  defp other(:elixir), do: :lisp

  defp submit(state) do
    line = Field.value(state.field)
    state = push(state, :in, prompt(state) <> line)
    history = remember(state.history, line)
    state = %{state | field: Field.new(@capacity), history: history, recall: 0}
    %{session: session, worker: worker} = lang = current(state)

    case mod(state.lang).feed(session, line) do
      {:pending, session} ->
        put_current(state, %{lang | session: session})

      {:error, session, text} ->
        put_current(push(state, :err, text), %{lang | session: session})

      {:eval, session, form} ->
        mod(state.lang).eval(worker, form)
        put_current(state, %{lang | session: session, busy: 1})
    end
  end

  defp answered(state, lang, {:ok, text}), do: settle(push(state, :out, text), lang)
  defp answered(state, lang, {:error, text}), do: settle(push(state, :err, text), lang)

  defp settle(state, lang) do
    lang_state = current(state, lang)
    %{state | langs: Map.put(state.langs, lang, %{lang_state | busy: 0})}
  end

  defp timed_out(state) do
    mod(state.lang).stop(current(state).worker)
    put_current(push(state, :err, "timeout, bindings lost"), fresh(state.lang))
  end

  defp remember(history, <<>>), do: history
  defp remember(history, line), do: :lists.sublist([line | history], @history)

  defp recall(state, index) when index < 0, do: state
  defp recall(state, index) when index > length(state.history), do: state
  defp recall(state, 0), do: %{state | field: Field.new(@capacity), recall: 0}

  defp recall(state, index) do
    chars = :erlang.binary_to_list(:lists.nth(index, state.history))
    field = :lists.foldl(&Field.insert(&2, &1), Field.new(@capacity), chars)

    %{state | field: field, recall: index}
  end

  defp push(state, kind, text) do
    %{state | lines: :lists.sublist([{kind, text} | state.lines], @keep)}
  end

  defp prompt(state) do
    %{session: session, busy: busy} = current(state)

    cond do
      busy > 0 -> "* "
      mod(state.lang).pending?(session) -> more(state.lang)
      true -> ready(state.lang)
    end
  end

  defp ready(:lisp), do: "> "
  defp ready(:elixir), do: "ex> "
  defp more(:lisp), do: ".. "
  defp more(:elixir), do: "..> "

  defp input(state) do
    {shown, _start} = visible(state)

    {:text, @x, @input_y, :default16px, @fg, @bg, prompt(state) <> shown}
  end

  defp cursor(state) do
    {_shown, start} = visible(state)
    column = byte_size(prompt(state)) + Field.cursor(state.field) - start

    {:rect, @x + column * @char_w, @input_y + @pitch - 2, @char_w, 2, @fg}
  end

  # The stretch of the line that fits after the prompt, keeping the cursor in view.
  defp visible(state) do
    value = Field.value(state.field)
    width = @columns - byte_size(prompt(state))
    start = max(Field.cursor(state.field) - width + 1, 0)
    length = min(width, byte_size(value) - start)

    {:binary.part(value, start, length), start}
  end

  defp output(state), do: items(window(state.lines), @top, [])

  defp items([], _y, acc), do: :lists.reverse(acc)

  defp items([{kind, text} | rest], y, acc) do
    items(rest, y + @pitch, [{:text, @x, y, :default16px, colour(kind), @bg, text} | acc])
  end

  defp colour(:in), do: @muted
  defp colour(:out), do: @fg
  defp colour(:err), do: @alert

  # Newest first in, oldest first out; only as many lines are wrapped as fit.
  defp window([], _need, acc), do: acc
  defp window(_lines, need, acc) when need <= 0, do: acc

  defp window([{kind, text} | rest], need, acc) do
    rows = chunks(text, kind, [])
    extra = length(rows) - need
    rows = if extra > 0, do: :lists.nthtail(extra, rows), else: rows

    window(rest, need - length(rows), rows ++ acc)
  end

  defp chunks(text, kind, acc) when byte_size(text) <= @columns do
    :lists.reverse([{kind, text} | acc])
  end

  defp chunks(<<head::binary-size(@columns), rest::binary>>, kind, acc) do
    chunks(rest, kind, [{kind, head} | acc])
  end
end
