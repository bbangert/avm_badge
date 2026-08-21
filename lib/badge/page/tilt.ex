defmodule Badge.Page.Tilt do
  @moduledoc """
  Shows board orientation as a marker that slides toward whichever way the
  badge is tilted.

  State is the quantised marker position plus the angles behind it, so the
  page only goes dirty when something visible actually changed.
  """

  use Badge.Page

  alias Badge.Icons
  alias Badge.Sensors
  alias Badge.Theme

  @dim Theme.dim()
  @bg Theme.bg()

  @marker :circle
  @marker_size Icons.size(@marker)
  @half_w div(elem(@marker_size, 0), 2)
  @half_h div(elem(@marker_size, 1), 2)

  # Beyond this the marker stops moving.
  @range 60

  @quantum 4
  @degree_quantum 2

  # Both centres sit on a quantum boundary once the marker's half-size is taken off.
  @centre_x 160
  @centre_y 120
  @span_x 140
  @span_y 76

  @readout_y 218

  @impl true
  def title, do: "Tilt"

  @impl true
  def icon, do: :triangle

  @impl true
  def init, do: update(%{x: 0, y: 0, roll: 0, pitch: 0}, {0, 0})

  @impl true
  def tick(state), do: update(state, Sensors.orientation())

  @doc "Recomputes the marker from a roll and pitch pair in whole degrees."
  def update(state, {roll, pitch}) do
    %{
      state
      | x: quantise(@centre_x - @half_w + scale(roll, @span_x)),
        y: quantise(@centre_y - @half_h + scale(pitch, @span_y)),
        roll: coarse(roll),
        pitch: coarse(pitch)
    }
  end

  @impl true
  def render(state) do
    [Icons.item(@marker, state.x, state.y), readout(state)]
  end

  defp readout(%{roll: roll, pitch: pitch}) do
    body =
      "roll " <>
        :erlang.integer_to_binary(roll) <> "   pitch " <> :erlang.integer_to_binary(pitch)

    {:text, 4, @readout_y, :default16px, @dim, @bg, body}
  end

  defp scale(degrees, span), do: div(clamp(degrees) * span, @range)

  defp clamp(degrees) when degrees > @range, do: @range
  defp clamp(degrees) when degrees < -@range, do: -@range
  defp clamp(degrees), do: degrees

  defp quantise(value), do: div(value, @quantum) * @quantum

  defp coarse(degrees), do: div(degrees, @degree_quantum) * @degree_quantum
end
