defmodule Badge.Page.Tilt do
  @moduledoc """
  A spirit level.

  The marker rests at the centre when the badge is held the way it was when
  the page opened, and slides toward whichever way it is tilted from there.
  Enter re-zeroes at the current orientation.

  Refreshes three times a second rather than ten: a frame is a full-panel
  repaint, and orientation does not need more.

  Levelling against a captured reference rather than an absolute frame is
  deliberate: the accelerometer is not mounted square to the panel, so a
  badge lying flat on a desk reads roughly 123 degrees of roll and an
  absolute level would sit pegged in a corner forever.
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

  # Tilt that drives the marker to the edge.
  @range 45

  # The sensor's roll increases toward the panel's left, so it is inverted here.
  @roll_sign -1
  @pitch_sign 1

  # 8px is about 2.6 degrees at this range, so a small wobble leaves the marker alone.
  @quantum 8
  @degree_quantum 2

  # Both centres land on a quantum boundary once the marker's half-size is taken off.
  @centre_x 160
  @centre_y 120
  @span_x 140
  @span_y 76

  @rest_x div(@centre_x - @half_w + div(@quantum, 2), @quantum) * @quantum
  @rest_y div(@centre_y - @half_h + div(@quantum, 2), @quantum) * @quantum

  @readout_y 218

  @impl true
  def refresh, do: 333

  @impl true
  def title, do: "Tilt"

  @impl true
  def icon, do: :triangle

  @impl true
  def init, do: %{zero: nil, roll: 0, pitch: 0, x: @rest_x, y: @rest_y}

  @impl true
  def tick(state), do: update(state, Sensors.orientation())

  @impl true
  def handle_key({:edit, :newline}, state), do: {:ok, %{state | zero: nil}}
  def handle_key(_event, _state), do: :ignore

  @doc """
  Moves the marker for a roll and pitch pair in whole degrees.

  The first reading after entry, or after Enter, becomes the zero.
  """
  def update(%{zero: nil} = state, {roll, pitch}) do
    update(%{state | zero: {roll, pitch}}, {roll, pitch})
  end

  def update(%{zero: {roll_zero, pitch_zero}} = state, {roll, pitch}) do
    roll_from_zero = @roll_sign * wrap(roll - roll_zero)
    pitch_from_zero = @pitch_sign * wrap(pitch - pitch_zero)

    %{
      state
      | x: quantise(@centre_x - @half_w + scale(roll_from_zero, @span_x)),
        y: quantise(@centre_y - @half_h + scale(pitch_from_zero, @span_y)),
        roll: coarse(roll_from_zero),
        pitch: coarse(pitch_from_zero)
    }
  end

  @impl true
  def render(state) do
    [Icons.item(@marker, state.x, state.y), readout(state)]
  end

  defp readout(%{roll: roll, pitch: pitch}) do
    body =
      "roll " <>
        :erlang.integer_to_binary(roll) <>
        "   pitch " <> :erlang.integer_to_binary(pitch) <> "   Enter=level"

    {:text, 4, @readout_y, :default16px, @dim, @bg, body}
  end

  defp scale(degrees, span), do: div(clamp(degrees) * span, @range)

  defp clamp(degrees) when degrees > @range, do: @range
  defp clamp(degrees) when degrees < -@range, do: -@range
  defp clamp(degrees), do: degrees

  # Crossing the 180 degree seam is a small movement, not a full swing.
  defp wrap(degrees) when degrees > 180, do: degrees - 360
  defp wrap(degrees) when degrees < -180, do: degrees + 360
  defp wrap(degrees), do: degrees

  # Rounds rather than truncates, so the steps sit symmetrically either side of centre.
  defp quantise(value), do: div(value + div(@quantum, 2), @quantum) * @quantum

  defp coarse(degrees), do: div(degrees, @degree_quantum) * @degree_quantum
end
