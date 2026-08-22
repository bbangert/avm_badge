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
  alias Badge.Theme

  @fg Theme.fg()
  @dim Theme.dim()
  @muted Theme.muted()
  @select Theme.select()
  @bg Theme.bg()

  @char_w 8
  @margin 8

  # What a line can hold before it runs off the panel.
  @columns div(Theme.width() - 2 * @margin, @char_w)

  @draft_y 214
  @rule_y 206
  @rows 8
  @pitch 20
  @top Theme.content_top() + 8

  # Matches the server's cap, so nothing is typed that would be cut on arrival.
  @capacity 200

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
      ] ++ empty(state)
  end

  # Oldest at the top so the newest ends up against the draft line.
  defp rows(messages, left, top, acc) do
    lines(:lists.reverse(take(messages, left, [])), top, acc)
  end

  defp lines([], _y, acc), do: :lists.reverse(acc)

  defp lines([message | rest], y, acc) do
    lines(rest, y + @pitch, [line(message, y) | acc])
  end

  defp line(message, y) do
    body = cut(Map.get(message, :from, "") <> ": " <> Map.get(message, :body, ""))

    {:text, @margin, y, :default16px, @fg, @bg, body}
  end

  defp take(_messages, 0, acc), do: :lists.reverse(acc)
  defp take([], _left, acc), do: :lists.reverse(acc)
  defp take([head | rest], left, acc), do: take(rest, left - 1, [head | acc])

  defp draft(%{draft: field} = state) do
    case Field.value(field) do
      "" -> idle(state)
      value -> prompt(cut("> " <> value <> "_"), colour(state.link))
    end
  end

  # An empty draft is the only time there is room to say the link is still coming up.
  defp idle(%{link: :joined}), do: prompt("> _", @select)
  defp idle(_state), do: prompt("connecting to the room", @muted)

  defp prompt(text, colour), do: {:text, @margin, @draft_y, :default16px, colour, @bg, text}

  defp colour(:joined), do: @select
  defp colour(_link), do: @muted

  # Only says the room is empty when there is nothing else to look at.
  defp empty(%{messages: [], link: :joined}) do
    [{:text, Readout.centre_x(@none), 120, :default16px, @dim, @bg, @none}]
  end

  defp empty(_state), do: []

  defp cut(text) when byte_size(text) > @columns, do: :binary.part(text, 0, @columns)
  defp cut(text), do: text
end
