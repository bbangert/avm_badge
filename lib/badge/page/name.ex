defmodule Badge.Page.Name do
  @moduledoc """
  A name tag to leave on screen.

  The name is set in the editor and kept in NVS. Long names wrap onto a
  second line, and the rule sits under however many lines that takes.
  """

  use Badge.Page

  alias Badge.Font
  alias Badge.Profile
  alias Badge.Text
  alias Badge.Theme

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @margin 16

  # dogica is fixed width, so its text can be measured and wrapped exactly.
  @name_font :dogica
  @name_w Font.advance(@name_font)

  @name_w != nil ||
    raise "#{@name_font} is proportional; the name cannot be wrapped without glyph widths"

  @name_columns div(Theme.width() - 2 * @margin, @name_w)
  @name_pitch 22

  @char_w 8

  @name_y Theme.content_top() + 10
  @rule_h 2
  @rule_w 200

  @detail_pitch 18
  @hint_y 216

  @impl true
  def title, do: "Name"

  @impl true
  def icon, do: :diamond

  @impl true
  def init, do: %{profile: Profile.blank(), loaded: false}

  # The saved profile arrives on the first tick, so init/0 stays pure.
  @impl true
  def tick(%{loaded: true} = state), do: state
  def tick(state), do: %{state | profile: Profile.load(), loaded: true}

  @doc "How many characters of the name fit on one line."
  def columns, do: @name_columns

  @impl true
  def render(%{profile: profile}) do
    lines = Text.wrap(Profile.display_name(profile), @name_columns)
    rule_y = @name_y + length(lines) * @name_pitch + 6

    name_items(lines, @name_y, []) ++
      [{:rect, @margin, rule_y, @rule_w, @rule_h, @accent}] ++
      detail_items(Profile.lines(profile), rule_y + 14, []) ++
      [hint()]
  end

  defp name_items([], _y, acc), do: :lists.reverse(acc)

  defp name_items([line | rest], y, acc) do
    item = {:text, @margin, y, @name_font, @fg, @bg, line}

    name_items(rest, y + @name_pitch, [item | acc])
  end

  # Anything that will not fit above the hint is dropped rather than overlapping it.
  defp detail_items([], _y, acc), do: :lists.reverse(acc)

  defp detail_items(_lines, y, acc) when y + @detail_pitch > @hint_y, do: :lists.reverse(acc)

  defp detail_items([line | rest], y, acc) do
    item = {:text, @margin, y, :default16px, @fg, @bg, line}

    detail_items(rest, y + @detail_pitch, [item | acc])
  end

  defp hint do
    text = "E to edit"

    {:text, div(Theme.width() - @char_w * byte_size(text), 2), @hint_y, :default16px, @dim, @bg,
     text}
  end
end
