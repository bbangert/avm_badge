defmodule Badge.Page.Info.Sensors do
  @moduledoc """
  Temperature and orientation, the first of Info's sub-pages.

  The page state is the reading map itself, so `render/1` can be driven from
  a literal in tests.
  """

  use Badge.Page

  alias Badge.Page.Info
  alias Badge.Readout
  alias Badge.Sensors

  # Milli-g the accelerometer readout rounds to.
  @accel_quantum 10

  @impl true
  def title, do: "Sensors"

  @impl true
  def init, do: %{temp: :unavailable, accel: {0, 0, 0}}

  @impl true
  def tick(state), do: update(state, read())

  @doc "Adopts a fresh reading, rounding the axes that would otherwise jitter."
  def update(_state, reading), do: %{reading | accel: coarse(reading.accel)}

  @impl true
  def render(reading) do
    Readout.rows(
      [
        {"temp", temp(reading.temp)},
        {"accel", accel(reading.accel)}
      ],
      Info.content_top()
    )
  end

  defp read do
    %{temp: Sensors.temperature(), accel: Sensors.acceleration()}
  end

  defp temp(:unavailable), do: "--"
  defp temp(degrees), do: int(degrees) <> " C"

  defp accel({x, y, z}), do: int(x) <> " " <> int(y) <> " " <> int(z)

  defp int(value), do: :erlang.integer_to_binary(value)

  # The EMA jitters by a few milli-g at rest; unrounded it would dirty the page every tick.
  defp coarse({x, y, z}), do: {round_to(x), round_to(y), round_to(z)}

  defp round_to(value), do: div(value, @accel_quantum) * @accel_quantum
end
