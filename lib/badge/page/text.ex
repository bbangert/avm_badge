defmodule Badge.Page.Text do
  @moduledoc """
  Typing surface over `Badge.TextBuffer`.

  Holds the buffer that `Badge.Screen` used to own. Geometry is the content
  area below the title bar, so this page is two rows shorter than the old
  full-screen editor.
  """

  use Badge.Page

  alias Badge.TextBuffer
  alias Badge.Theme

  @fg Theme.fg()
  @bg Theme.bg()

  @margin 4
  @char_w 8
  @char_h 16

  @cols div(Theme.width() - 2 * @margin, @char_w)
  @rows div(Theme.height() - Theme.content_top() - 2 * @margin, @char_h)

  @text_x @margin
  @text_y Theme.content_top() + @margin

  @impl true
  def title, do: "Text"

  @impl true
  def icon, do: :square

  @impl true
  def init, do: TextBuffer.new(@cols, @rows)

  @impl true
  def handle_key({:char, char}, buffer), do: {:ok, TextBuffer.insert(buffer, char)}
  def handle_key({:edit, :backspace}, buffer), do: {:ok, TextBuffer.backspace(buffer)}
  def handle_key({:edit, :newline}, buffer), do: {:ok, TextBuffer.newline(buffer)}
  def handle_key({:edit, :tab}, buffer), do: {:ok, TextBuffer.tab(buffer)}
  def handle_key(_event, _buffer), do: :ignore

  @impl true
  def render(buffer) do
    [cursor_item(buffer) | text_items(buffer)]
  end

  defp cursor_item(buffer) do
    {col, row} = TextBuffer.cursor(buffer)

    # Clamped so the cursor rect never runs past the right edge.
    x = min(@text_x + col * @char_w, Theme.width() - @char_w)

    {:rect, x, @text_y + row * @char_h + @char_h - 2, @char_w, 2, @fg}
  end

  # Row index threaded by hand; empty lines are skipped rather than emitted.
  defp text_items(buffer), do: text_items(TextBuffer.lines(buffer), 0, [])

  defp text_items([], _row, acc), do: :lists.reverse(acc)

  defp text_items([<<>> | rest], row, acc), do: text_items(rest, row + 1, acc)

  defp text_items([line | rest], row, acc) do
    item = {:text, @text_x, @text_y + row * @char_h, :default16px, @fg, @bg, line}

    text_items(rest, row + 1, [item | acc])
  end
end
