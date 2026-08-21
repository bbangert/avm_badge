defmodule Badge.Accel do
  @moduledoc """
  Pure maths for the SC7A20 accelerometer: decoding raw registers and
  deriving tilt orientation. No I2C, no process state.

  The SC7A20 in normal mode is 10-bit, left-justified in a signed 16-bit
  little-endian pair, +-2g full scale, so 1g = 16384 counts and
  `mg = raw * 1000 / 16384`, simplified here to `raw * 125 / 2048`.

  Note that the sensor is not mounted square to the panel: a badge lying
  flat reads roughly 123 degrees of roll, so `orientation/1` is only
  meaningful as a difference against a captured reference.
  """

  @type mg :: {integer, integer, integer}

  @doc "Decodes the 6 bytes read from OUT_X_L..OUT_Z_H (0x28..0x2D) into milli-g."
  @spec decode(binary) :: mg
  def decode(<<x::little-signed-16, y::little-signed-16, z::little-signed-16>>) do
    {to_mg(x), to_mg(y), to_mg(z)}
  end

  defp to_mg(raw), do: div(raw * 125, 2048)

  @doc "Roll and pitch in whole degrees from a milli-g sample."
  @spec orientation(mg) :: {integer, integer}
  def orientation({x, y, z}) do
    roll = round(:math.atan2(y, z) * 180 / :math.pi())
    pitch = round(:math.atan2(-x, :math.sqrt(y * y + z * z)) * 180 / :math.pi())
    {roll, pitch}
  end
end
