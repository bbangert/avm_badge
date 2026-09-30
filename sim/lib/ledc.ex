defmodule LEDC do
  @moduledoc false

  # The only channel on the badge is the backlight, which is active low.
  @full_duty 1024

  @doc "The panel's brightness from the last duty set, from 0 (dark) to 1."
  def level, do: :persistent_term.get({__MODULE__, :level}, 1.0)

  def low_speed_mode, do: :low_speed
  def timer_config(_options), do: :ok
  def channel_config(options), do: set_duty(:low_speed, 0, Keyword.fetch!(options, :duty))

  def set_duty(_speed_mode, _channel, duty) do
    level = :math.sqrt(max(@full_duty - duty, 0) / @full_duty)
    :persistent_term.put({__MODULE__, :level}, level)
    Badge.Sim.Display.backlight(level)
  end

  def update_duty(_speed_mode, _channel), do: :ok
end
