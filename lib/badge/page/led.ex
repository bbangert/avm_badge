defmodule Badge.Page.Led do
  @moduledoc """
  Picks what the NeoPixel chain shows.

  `handle_key/2` only moves the selection; the cast to `Badge.Pixels`
  happens in `tick/1`, and only when the selected mode actually changed.
  That keeps key handling pure and testable off the board.
  """

  use Badge.Page

  alias Badge.Color
  alias Badge.Pixels
  alias Badge.Theme

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @modes [:rainbow, :solid, :off]
  @mode_count length(@modes)
  @names ["rainbow", "solid", "off"]

  @hue_step 15

  @label_x 8
  @value_x 96
  @mode_y 40
  @hue_y 64
  @help_y 210

  @swatch_x 8
  @swatch_y 110
  @swatch_w 304
  @swatch_h 60

  @impl true
  def title, do: "LED"

  @impl true
  def icon, do: :clover

  @impl true
  def init, do: %{index: 0, hue: 0, pushed: nil}

  @impl true
  def handle_key({:move, :down}, state) do
    {:ok, %{state | index: rem(state.index + 1, @mode_count)}}
  end

  def handle_key({:move, :up}, state) do
    {:ok, %{state | index: rem(state.index + @mode_count - 1, @mode_count)}}
  end

  def handle_key({:move, :right}, state) do
    {:ok, %{state | hue: rem(state.hue + @hue_step, 360)}}
  end

  def handle_key({:move, :left}, state) do
    {:ok, %{state | hue: rem(state.hue + 360 - @hue_step, 360)}}
  end

  def handle_key(_event, _state), do: :ignore

  @impl true
  def tick(%{pushed: pushed} = state) do
    case mode(state) do
      ^pushed ->
        state

      current ->
        Pixels.set_mode(current)

        %{state | pushed: current}
    end
  end

  @doc "The chain mode the current selection means."
  def mode(%{index: index, hue: hue}) do
    case :lists.nth(index + 1, @modes) do
      :solid -> {:solid, hue}
      other -> other
    end
  end

  @impl true
  def render(state) do
    [
      {:text, @label_x, @mode_y, :default16px, @dim, @bg, "mode"},
      {:text, @value_x, @mode_y, :default16px, @fg, @bg, name(state)},
      {:text, @label_x, @hue_y, :default16px, @dim, @bg, "hue"},
      {:text, @value_x, @hue_y, :default16px, @fg, @bg, :erlang.integer_to_binary(state.hue)},
      {:text, @label_x, @help_y, :default16px, @dim, @bg, "up/down mode   left/right hue"},
      swatch(state)
    ]
  end

  defp name(%{index: index}), do: :lists.nth(index + 1, @names)

  defp swatch(state) do
    {:rect, @swatch_x, @swatch_y, @swatch_w, @swatch_h, swatch_colour(mode(state))}
  end

  defp swatch_colour(:off), do: @bg
  defp swatch_colour(:rainbow), do: @accent
  defp swatch_colour({:solid, hue}), do: Color.rgb888(Color.hsv_to_rgb(hue, 255, 255))
end
