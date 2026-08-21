defmodule Badge.Page.Name do
  @moduledoc """
  A name tag to leave on screen.

  The name is set in the editor and kept in NVS. Long names wrap onto a
  second line, and the rule sits under however many lines that takes.
  """

  use Badge.Page

  alias Badge.Field
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

  @alert Theme.alert()
  @select Theme.select()

  @row_y Theme.content_top() + 10
  @row_pitch 18
  @marker_x 0
  @label_x 8
  @value_x 88
  @value_columns div(Theme.width() - @value_x - 8, @char_w)

  @entry_label_y Theme.content_top() + 30
  @entry_value_y Theme.content_top() + 70

  @impl true
  def title, do: "Name"

  @impl true
  def icon, do: :diamond

  @impl true
  def init do
    %{
      mode: :show,
      profile: Profile.blank(),
      cursor: 0,
      field: nil,
      loaded: false,
      saved: nil
    }
  end

  # Hardware is only touched here, never from a key handler.
  @impl true
  def tick(state), do: state |> load() |> persist()

  # The saved profile arrives on the first tick, so init/0 stays pure.
  defp load(%{loaded: true} = state), do: state

  defp load(state) do
    profile = Profile.load()

    %{state | profile: profile, saved: profile, loaded: true}
  end

  # Written once the editor is closed, not on every keystroke.
  defp persist(%{mode: mode} = state) when mode != :show, do: state
  defp persist(%{profile: profile, saved: profile} = state), do: state

  defp persist(state) do
    Profile.save(state.profile)

    %{state | saved: state.profile}
  end

  @impl true
  def handle_key(event, %{mode: :typing} = state), do: typing_key(event, state)
  def handle_key(event, %{mode: :fields} = state), do: fields_key(event, state)
  def handle_key(event, state), do: show_key(event, state)

  defp show_key({:char, char}, state) when char == ?e or char == ?E do
    {:ok, %{state | mode: :fields, cursor: 0}}
  end

  defp show_key(_event, _state), do: :ignore

  # Escape leaves the editor; the router only sees it once we are back on the badge.
  defp fields_key({:nav, :home}, state), do: {:ok, %{state | mode: :show}}
  defp fields_key({:move, :up}, state), do: {:ok, move(state, -1)}
  defp fields_key({:move, :down}, state), do: {:ok, move(state, 1)}

  defp fields_key({:edit, :newline}, state) do
    key = selected(state)
    value = Map.get(state.profile, key, "")

    {:ok, %{state | mode: :typing, field: fill(value, Profile.capacity(key))}}
  end

  defp fields_key(_event, state), do: {:ok, state}

  defp typing_key({:nav, :home}, state), do: {:ok, %{state | mode: :fields, field: nil}}

  defp typing_key({:edit, :newline}, state) do
    profile = Map.put(state.profile, selected(state), Field.value(state.field))

    {:ok, %{state | mode: :fields, profile: profile, field: nil}}
  end

  defp typing_key({:char, char}, state) do
    {:ok, %{state | field: Field.insert(state.field, char)}}
  end

  defp typing_key({:edit, :backspace}, state) do
    {:ok, %{state | field: Field.backspace(state.field)}}
  end

  defp typing_key(_event, state), do: {:ok, state}

  defp move(state, delta) do
    %{state | cursor: clamp(state.cursor + delta, length(Profile.keys()) - 1)}
  end

  defp clamp(index, _last) when index < 0, do: 0
  defp clamp(index, last) when index > last, do: last
  defp clamp(index, _last), do: index

  @doc "The field the cursor is on."
  def selected(%{cursor: cursor}), do: :lists.nth(cursor + 1, Profile.keys())

  defp fill(value, capacity) do
    :lists.foldl(&Field.insert(&2, &1), Field.new(capacity), :erlang.binary_to_list(value))
  end

  @doc "How many characters of the name fit on one line."
  def columns, do: @name_columns

  @impl true
  def render(%{mode: :typing} = state) do
    key = selected(state)
    value = Field.value(state.field) <> "_"

    [
      centred(Profile.label(key), @entry_label_y, @dim),
      centred(value, @entry_value_y, @select),
      centred("Enter save   Esc cancel", @hint_y, @dim)
    ]
  end

  def render(%{mode: :fields} = state) do
    rows(Profile.keys(), 0, state, @row_y, []) ++
      [centred("up/down pick   Enter edit   Esc done", @hint_y, @dim)]
  end

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

  defp rows([], _position, _state, _y, acc), do: :lists.reverse(acc)

  defp rows([key | rest], position, state, y, acc) do
    colour = row_colour(state, position, key)
    marker = if position == state.cursor, do: ">", else: " "

    items = [
      {:text, @value_x, y, :default16px, colour, @bg, shown(Map.get(state.profile, key, ""))},
      {:text, @label_x, y, :default16px, label_colour(state, position), @bg, Profile.label(key)},
      {:text, @marker_x, y, :default16px, @select, @bg, marker}
    ]

    rows(rest, position + 1, state, y + @row_pitch, items ++ acc)
  end

  # The one field that must be filled in says so, in the colour used for problems.
  defp row_colour(state, position, key) do
    cond do
      key == Profile.required() and not Profile.complete?(state.profile) -> @alert
      position == state.cursor -> @select
      true -> @fg
    end
  end

  defp label_colour(%{cursor: position}, position), do: @select
  defp label_colour(_state, _position), do: @dim

  # Values are longer than the column, so the list shows as much as fits.
  defp shown(value) when byte_size(value) > @value_columns do
    :binary.part(value, 0, @value_columns)
  end

  defp shown(""), do: "-"
  defp shown(value), do: value

  defp centred(text, y, colour) do
    {:text, div(Theme.width() - @char_w * byte_size(text), 2), y, :default16px, colour, @bg, text}
  end

  defp hint do
    text = "E to edit"

    {:text, div(Theme.width() - @char_w * byte_size(text), 2), @hint_y, :default16px, @dim, @bg,
     text}
  end
end
