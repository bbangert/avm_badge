defmodule Badge.Page.Chat do
  @moduledoc """
  The room, on the panel.

  Messages arrive through `Badge.Chat.Link`, which does the polling; this page
  only reads what it has heard and hands typed lines back. Newest sits nearest
  the draft line, so the eye follows the conversation downwards.

  The link is opened on the first tick and closed on the way out, because a
  session held open costs heap the badge needs for whatever else is on screen.
  """

  use Badge.Page

  alias Badge.Chat.Link
  alias Badge.Field
  alias Badge.Readout
  alias Badge.Text
  alias Badge.Theme

  @fg Theme.fg()
  @accent Theme.accent()
  @dim Theme.dim()
  @muted Theme.muted()
  @select Theme.select()
  @warn Theme.warn()
  @alert Theme.alert()
  @bg Theme.bg()

  @char_w 8
  @margin 8

  # What a line can hold before it runs off the panel.
  @columns div(Theme.width() - 2 * @margin, @char_w)

  # The counter needs the right-hand end of the draft line: two digits and a gap.
  @draft_columns @columns - 3

  # Where the caret settles once the draft is long enough to scroll.
  @caret_rest div(@draft_columns, 2)

  @draft_y 214
  @rule_y 206
  @rows 8
  @pitch 20
  @top Theme.content_top() + 8

  # Three panel lines' worth. The server's cap of 200 is the outer bound.
  @capacity 114

  # How much ragged gap a space may leave before a word is dashed instead.
  # Without it a long unbroken word pushes the sender's name onto a line of
  # its own and wastes most of the one below.
  @orphan 6

  @none "No messages yet"

  @impl true
  def title, do: "Chat"

  @impl true
  def icon, do: :cross

  # A frame is a whole panel, and messages arrive at walking pace.
  @impl true
  def refresh(_state), do: 333

  @impl true
  def init do
    %{messages: [], link: :offline, draft: Field.new(@capacity)}
  end

  # Hardware is only touched here, never from a key handler.
  @impl true
  def tick(state) do
    Link.open()
    status = Link.status()

    %{state | messages: status.messages, link: status.state}
  end

  # A page is not a process, so the session has nowhere else to be given back.
  @impl true
  def leave(_state), do: Link.close()

  @impl true
  def handle_key({:char, char}, state), do: {:ok, %{state | draft: Field.insert(state.draft, char)}}

  def handle_key({:edit, :backspace}, state) do
    {:ok, %{state | draft: Field.backspace(state.draft)}}
  end

  def handle_key({:edit, :newline}, state), do: send_draft(Field.value(state.draft), state)

  def handle_key({:move, :left}, state), do: {:ok, %{state | draft: Field.left(state.draft)}}

  def handle_key({:move, :right}, state), do: {:ok, %{state | draft: Field.right(state.draft)}}

  def handle_key(_event, _state), do: :ignore

  # Nothing to say is not a message; let the router keep the key.
  defp send_draft("", _state), do: :ignore

  defp send_draft(body, state) do
    Link.say(body)

    {:ok, %{state | draft: Field.new(@capacity)}}
  end

  @impl true
  def render(state) do
    rows(state.messages, @rows, @top, []) ++
      [
        {:rect, @margin, @rule_y, Theme.width() - 2 * @margin, 1, @dim},
        draft(state)
      ] ++ counter(state.draft) ++ empty(state)
  end

  # Oldest at the top so the newest ends up against the draft line. A message
  # can take several lines, so the newest are taken until the room runs out.
  defp rows(messages, left, top, _acc) do
    messages
    |> newest(left, [])
    |> lines(top, [])
  end

  # Walks newest first, keeping whole messages until the lines are spent.
  defp newest([], _left, acc), do: acc

  defp newest(_messages, left, acc) when left <= 0, do: acc

  defp newest([message | rest], left, acc) do
    wrapped = wrap(message)
    count = length(wrapped)

    case count > left do
      true -> acc
      false -> newest(rest, left - count, [{message, wrapped} | acc])
    end
  end

  defp wrap(message) do
    Text.wrap(prefix(message) <> Map.get(message, :body, ""), @columns, @orphan)
  end

  defp prefix(message), do: Map.get(message, :from, "") <> ": "

  defp lines([], _y, acc), do: :lists.reverse(acc)

  defp lines([{message, [first | rest_lines]} | rest], y, acc) do
    items = head_items(message, first, y) ++ tail_items(message, rest_lines, y + @pitch, [])

    lines(rest, y + @pitch * (length(rest_lines) + 1), items ++ acc)
  end

  # The name is drawn separately so it can carry its own colour.
  defp head_items(message, first, y) do
    name = prefix(message)

    case byte_size(first) > byte_size(name) and :binary.part(first, 0, byte_size(name)) == name do
      true ->
        rest = :binary.part(first, byte_size(name), byte_size(first) - byte_size(name))

        [
          {:text, @margin + @char_w * byte_size(name), y, :default16px, @fg, @bg,
           rest},
          {:text, @margin, y, :default16px, name_colour(message), @bg, name}
        ]

      false ->
        [{:text, @margin, y, :default16px, name_colour(message), @bg, first}]
    end
  end

  defp tail_items(_message, [], _y, acc), do: acc

  defp tail_items(message, [body | rest], y, acc) do
    item = {:text, @margin, y, :default16px, @fg, @bg, body}

    tail_items(message, rest, y + @pitch, [item | acc])
  end

  # Every message reads the same; only the name says who is speaking.
  defp name_colour(%{mine: true}), do: @select
  defp name_colour(_message), do: @accent

  defp draft(%{draft: field} = state) do
    case Field.value(field) do
      "" -> idle(state)
      value -> prompt(window(value, Field.cursor(field)), colour(state.link))
    end
  end

  # The caret is drawn between the two halves rather than after the value.
  defp window(value, at) do
    line =
      :binary.part(value, 0, at) <>
        "_" <> :binary.part(value, at, byte_size(value) - at)

    clip(line, 2 + at)
  end

  # An empty draft is the only time there is room to say the link is still coming up.
  defp idle(%{link: :joined}), do: prompt("> _", @select)
  defp idle(_state), do: prompt("connecting to the room", @muted)

  defp prompt(text, colour), do: {:text, @margin, @draft_y, :default16px, colour, @bg, text}

  @doc "The colour for a count of characters left, or `nil` while there is room."
  @spec counter_colour(non_neg_integer) :: integer | nil
  def counter_colour(left) when left > 20, do: nil
  def counter_colour(left) when left > 5, do: @warn
  def counter_colour(_left), do: @alert

  defp counter(field) do
    left = Field.remaining(field)

    case counter_colour(left) do
      nil -> []
      colour -> [count_item(:erlang.integer_to_binary(left), colour)]
    end
  end

  # Right-aligned, in the columns the draft leaves free.
  defp count_item(text, colour) do
    x = Theme.width() - @margin - @char_w * byte_size(text)

    {:text, x, @draft_y, :default16px, colour, @bg, text}
  end

  defp colour(:joined), do: @select
  defp colour(_link), do: @muted

  # Only says the room is empty when there is nothing else to look at.
  defp empty(%{messages: [], link: :joined}) do
    [{:text, Readout.centre_x(@none), 120, :default16px, @dim, @bg, @none}]
  end

  defp empty(_state), do: []

  # Typing runs off the left rather than the right, so the caret stays in view.
  defp clip(line, at), do: clipped("> " <> line, at)

  defp clipped(line, _at) when byte_size(line) <= @draft_columns, do: line

  # The caret walks in to the middle before the text starts moving under it.
  defp clipped(line, at) do
    start = min(max(at - @caret_rest, 0), byte_size(line) - @draft_columns)

    :binary.part(line, start, @draft_columns)
  end
end
