defmodule Badge.Page.Led do
  @moduledoc """
  Picks what the LED ring shows: an effect, then its colours and options.

  The first row is the effect; below it come only the options that effect
  uses (see `Badge.LedEffect.options/1`), plus a hue row when the palette is
  a single hue. Up and down pick a row, left and right change it.

  `handle_key/2` only edits the setting; `tick/1` hands it to
  `Badge.Pixels`, and only when it changed, which keeps key handling pure and
  testable off the board.
  """

  use Badge.Page

  alias Badge.LedEffect
  alias Badge.Nav
  alias Badge.Pixels
  alias Badge.Theme

  @effects LedEffect.effects()
  @palettes LedEffect.palettes()

  @label_x 8
  @value_x 112
  @first_y 36
  @row_h 20
  @help_y 210

  @swatch_x 8
  @swatch_y 168
  @swatch_w 304
  @swatch_h 28

  @impl true
  def title, do: "LED"

  @impl true
  def icon, do: :circle

  @impl true
  def init, do: %{setting: LedEffect.default(), cursor: 0, pushed: nil, loaded: false}

  @impl true
  def handle_key({:move, :down}, state) do
    {:ok, %{state | cursor: min(state.cursor + 1, length(rows(state.setting)) - 1)}}
  end

  def handle_key({:move, :up}, state) do
    {:ok, %{state | cursor: max(state.cursor - 1, 0)}}
  end

  def handle_key({:move, :right}, state), do: {:ok, change(state, 1)}
  def handle_key({:move, :left}, state), do: {:ok, change(state, -1)}
  def handle_key(_event, _state), do: :ignore

  # Adopts what the ring is already showing, so opening the page cannot
  # overwrite a saved setting with this page's starting one.
  @impl true
  def tick(%{loaded: false} = state) do
    setting = Pixels.setting()
    %{state | setting: setting, pushed: setting, loaded: true}
  end

  def tick(%{setting: setting, pushed: setting} = state), do: state

  def tick(state) do
    Pixels.set(state.setting)
    %{state | pushed: state.setting}
  end

  @doc "The rows a setting shows: the effect, then the options it uses."
  @spec rows(map) :: [atom]
  def rows(setting) do
    options = LedEffect.options(setting.effect)

    case setting.palette == :hue and :lists.member(:palette, options) do
      true -> [:effect | with_hue(options)]
      false -> [:effect | options]
    end
  end

  defp with_hue([:palette | rest]), do: [:palette, :hue | rest]
  defp with_hue([option | rest]), do: [option | with_hue(rest)]

  defp change(state, delta) do
    row = :lists.nth(state.cursor + 1, rows(state.setting))
    setting = adjust(state.setting, row, delta)

    # A new effect can have fewer rows than the one before.
    cursor = min(state.cursor, length(rows(setting)) - 1)

    %{state | setting: setting, cursor: cursor}
  end

  defp adjust(setting, :effect, delta),
    do: %{setting | effect: cycle(@effects, setting.effect, delta)}

  defp adjust(setting, :palette, delta),
    do: %{setting | palette: cycle(@palettes, setting.palette, delta)}

  defp adjust(setting, :direction, _delta),
    do: %{setting | direction: if(setting.direction == :cw, do: :ccw, else: :cw)}

  defp adjust(setting, :hue, delta),
    do: %{setting | hue: rem(setting.hue + delta * 15 + 360, 360)}

  defp adjust(setting, :speed, delta), do: step(setting, :speed, delta, 1, 10)
  defp adjust(setting, :brightness, delta), do: step(setting, :brightness, delta * 5, 5, 100)
  defp adjust(setting, key, delta), do: step(setting, key, delta * 10, 0, 100)

  defp step(setting, key, delta, low, high) do
    Map.put(setting, key, max(low, min(high, Map.fetch!(setting, key) + delta)))
  end

  defp cycle(list, current, delta) do
    count = length(list)
    :lists.nth(rem(index_of(list, current, 0) + delta + count, count) + 1, list)
  end

  defp index_of([], _item, _position), do: 0
  defp index_of([item | _rest], item, position), do: position
  defp index_of([_other | rest], item, position), do: index_of(rest, item, position + 1)

  @impl true
  def render(state) do
    rows = rows(state.setting)

    lines =
      for {row, i} <- :lists.zip(rows, :lists.seq(0, length(rows) - 1)) do
        y = @first_y + i * @row_h
        colour = if i == state.cursor, do: Theme.select(), else: Theme.fg()

        [
          {:text, @label_x, y, :default16px, Theme.dim(), Theme.bg(), label(row)},
          {:text, @value_x, y, :default16px, colour, Theme.bg(), value(state.setting, row)}
        ]
      end

    :lists.append(lines) ++
      Nav.hint([{"up/down", "choose"}, {"left/right", "change"}], @help_y, Theme.dim()) ++
      swatch(LedEffect.colours(state.setting))
  end

  defp label(:effect), do: "effect"
  defp label(:palette), do: "colours"
  defp label(:hue), do: "hue"
  defp label(:speed), do: "speed"
  defp label(:brightness), do: "brightness"
  defp label(:spread), do: "spread"
  defp label(:direction), do: "direction"
  defp label(:trail), do: "trail"
  defp label(:density), do: "density"

  defp value(setting, :effect), do: :erlang.atom_to_binary(setting.effect)
  defp value(setting, :palette), do: :erlang.atom_to_binary(setting.palette)
  defp value(setting, :hue), do: :erlang.integer_to_binary(setting.hue)
  defp value(setting, :speed), do: :erlang.integer_to_binary(setting.speed) <> "/10"
  defp value(%{direction: :cw}, :direction), do: "clockwise"
  defp value(_setting, :direction), do: "anticlockwise"
  defp value(setting, key), do: :erlang.integer_to_binary(Map.fetch!(setting, key)) <> "%"

  # One block per colour, across the full swatch width.
  defp swatch([]), do: [{:rect, @swatch_x, @swatch_y, @swatch_w, @swatch_h, Theme.dim()}]

  defp swatch(colours) do
    count = length(colours)
    w = div(@swatch_w, count)

    for {colour, i} <- :lists.zip(colours, :lists.seq(0, count - 1)) do
      last = i == count - 1

      {:rect, @swatch_x + i * w, @swatch_y, if(last, do: @swatch_w - i * w, else: w), @swatch_h,
       colour}
    end
  end
end
