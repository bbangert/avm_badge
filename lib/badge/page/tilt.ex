defmodule Badge.Page.Tilt do
  @moduledoc """
  A spirit level.

  The marker rests at the centre when the badge lies flat and slides toward
  whichever way it is tilted from there. Nothing has to be pressed: the
  reference is gravity, read straight off the accelerometer.

  Refreshes three times a second rather than ten: a frame is a full-panel
  repaint, and orientation does not need more.
  """

  use Badge.Page

  alias Badge.Accel
  alias Badge.Icons
  alias Badge.Sensors
  alias Badge.Theme

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

  # Gravity lands on -Z with the panel upwards, so level is half a turn of roll.
  @zero_roll elem(Accel.flat(), 0)
  @zero_pitch elem(Accel.flat(), 1)

  @impl true
  def refresh(_state), do: 333

  @impl true
  def title, do: "Tilt"

  @impl true
  def init, do: %{roll: 0, pitch: 0, x: @rest_x, y: @rest_y}

  @impl true
  def tick(state), do: update(state, Sensors.orientation())

  @doc """
  Moves the marker for a roll and pitch pair in whole degrees.

  Angles are measured from `Badge.Accel.flat/0`, so a badge on a level
  surface centres the marker with nothing captured and nothing pressed.
  """
  def update(state, {roll, pitch}) do
    roll_from_zero = @roll_sign * wrap(roll - @zero_roll)
    pitch_from_zero = @pitch_sign * wrap(pitch - @zero_pitch)

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
        :erlang.integer_to_binary(roll) <> "   pitch " <> :erlang.integer_to_binary(pitch)

    {:text, 4, @readout_y, :default16px, Theme.dim(), Theme.bg(), body}
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
