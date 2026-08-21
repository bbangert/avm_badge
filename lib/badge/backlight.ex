defmodule Badge.Backlight do
  @moduledoc """
  Dims the panel backlight with an LEDC PWM channel.

  AtomGL drives the backlight as a plain on-or-off GPIO and offers no
  runtime control, so this takes the pin over after the display is open.
  The pin is active low, so duty runs backwards: zero duty holds it low and
  the panel is at full brightness.
  """

  use GenServer

  alias Badge.Hardware

  @compile {:no_warn_undefined, LEDC}

  @timer 0
  @channel 0

  # 10 bits is finer than the eye can see here, and keeps the frequency easy.
  @resolution 10
  @max_duty 1023
  @frequency 5_000

  @default 100

  # Perceived brightness follows roughly a square law, so a linear setting
  # feels wrong: most of the visible change crowds into the bottom of the range.
  # 100 squared, since the setting is squared before scaling.
  @gamma_divisor 10_000

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Sets brightness as a percentage."
  @spec set(0..100) :: :ok
  def set(percent) do
    GenServer.cast(__MODULE__, {:set, percent})
  end

  @doc """
  PWM duty for a brightness setting.

  Squared, so equal steps on the dial look like equal steps to the eye
  rather than doing almost nothing above half. Computed straight in duty
  counts: going through a whole-number percentage first would make one
  percent the smallest step, which is ten counts and far too bright at the
  bottom of the dial.

  Inverted, because the backlight pin is active low: full brightness holds
  the pin low, which is zero duty.
  """
  @spec duty(integer) :: integer
  def duty(percent) when percent >= 100, do: 0
  def duty(percent) when percent <= 0, do: @max_duty
  def duty(percent), do: @max_duty - lit(percent)

  # One count rather than none, so the lowest setting is dim but never dark.
  defp lit(percent) do
    case div(@max_duty * percent * percent, @gamma_divisor) do
      0 -> 1
      counts -> counts
    end
  end

  @doc "Brightness the panel starts at."
  def default, do: @default

  @impl true
  def init(:ok) do
    :ok =
      LEDC.timer_config(
        duty_resolution: @resolution,
        freq_hz: @frequency,
        speed_mode: LEDC.low_speed_mode(),
        timer_num: @timer
      )

    :ok =
      LEDC.channel_config(
        channel: @channel,
        duty: duty(@default),
        gpio_num: Hardware.display_backlight(),
        speed_mode: LEDC.low_speed_mode(),
        hpoint: 0,
        timer_sel: @timer
      )

    :io.format(~c"Backlight: pwm on GPIO~p at ~p%~n", [Hardware.display_backlight(), @default])

    {:ok, %{percent: @default}}
  end

  @impl true
  def handle_cast({:set, percent}, %{percent: percent} = state), do: {:noreply, state}

  def handle_cast({:set, percent}, state) do
    :ok = LEDC.set_duty(LEDC.low_speed_mode(), @channel, duty(percent))
    :ok = LEDC.update_duty(LEDC.low_speed_mode(), @channel)

    {:noreply, %{state | percent: percent}}
  end
end
