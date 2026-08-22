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
  alias Badge.Nvs

  @compile {:no_warn_undefined, LEDC}

  @timer 0
  @channel 0

  # 10 bits is finer than the eye can see here, and keeps the frequency easy.
  @resolution 10
  @max_duty 1023
  @frequency 5_000

  @default_brightness 100
  @default_sleep :s30

  # Sleep is a backlight concern, so its options live here rather than in the page.
  @timeouts [{:s10, "10s"}, {:s30, "30s"}, {:s60, "60s"}, {:off, "off"}]

  # Perceived brightness follows roughly a square law, so a linear setting
  # feels wrong: most of the visible change crowds into the bottom of the range.
  # 100 squared, since the setting is squared before scaling.
  @gamma_divisor 10_000

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Sets brightness as a percentage, without saving it."
  @spec set(0..100) :: :ok
  def set(percent) do
    GenServer.cast(__MODULE__, {:set, percent})
  end

  @doc "Saves brightness and sleep timeout so they survive a reboot."
  @spec store(integer, atom) :: :ok
  def store(percent, sleep) do
    GenServer.cast(__MODULE__, {:store, percent, sleep})
  end

  @doc "The saved settings, as they were loaded or last stored."
  @spec settings() :: %{brightness: integer, sleep: atom}
  def settings do
    GenServer.call(__MODULE__, :settings)
  end

  @doc "Blanks the panel, leaving the saved brightness to come back to."
  @spec sleep() :: :ok
  def sleep, do: GenServer.cast(__MODULE__, :sleep)

  @doc "Restores the brightness the badge went to sleep at."
  @spec wake() :: :ok
  def wake, do: GenServer.cast(__MODULE__, :wake)

  @doc """
  How many ticks of `interval` milliseconds a timeout is worth.

  `:never` for a badge set not to sleep, so a caller cannot accidentally
  count down to it.
  """
  @spec sleep_ticks(atom, pos_integer) :: pos_integer | :never
  def sleep_ticks(:off, _interval), do: :never
  def sleep_ticks(sleep, interval), do: div(seconds(sleep) * 1000, interval)

  # The label doubles as the number of seconds, bar the trailing s.
  defp seconds(:s10), do: 10
  defp seconds(:s30), do: 30
  defp seconds(:s60), do: 60
  defp seconds(_unknown), do: seconds(@default_sleep)

  @doc "Sleep timeout options, in order, as `{name, label}`."
  def timeouts, do: @timeouts

  @doc "Brightness to use when nothing has been saved."
  def default_brightness, do: @default_brightness

  @doc "Sleep timeout to use when nothing has been saved."
  def default_sleep, do: @default_sleep

  @doc "Reads a stored brightness, falling back to the default."
  @spec decode_brightness(binary | nil) :: integer
  def decode_brightness(nil), do: @default_brightness

  def decode_brightness(stored) do
    case digits(stored, 0, false) do
      :error -> @default_brightness
      value when value < 1 or value > 100 -> @default_brightness
      value -> value
    end
  end

  @doc "Reads a stored sleep timeout, falling back to the default."
  @spec decode_sleep(binary | nil) :: atom
  def decode_sleep(nil), do: @default_sleep
  def decode_sleep(stored), do: named(@timeouts, stored)

  @doc "The label a sleep timeout is stored and shown as."
  @spec sleep_label(atom) :: binary
  def sleep_label(sleep), do: labelled(@timeouts, sleep)

  defp named([], _label), do: @default_sleep
  defp named([{name, label} | _rest], label), do: name
  defp named([_entry | rest], label), do: named(rest, label)

  defp labelled([], _name), do: sleep_label(@default_sleep)
  defp labelled([{name, label} | _rest], name), do: label
  defp labelled([_entry | rest], name), do: labelled(rest, name)

  # Anything that is not all digits is a corrupt value, not a small number.
  defp digits(<<>>, _acc, false), do: :error
  defp digits(<<>>, acc, true), do: acc

  defp digits(<<digit, rest::binary>>, acc, _any) when digit >= ?0 and digit <= ?9 do
    digits(rest, acc * 10 + (digit - ?0), true)
  end

  defp digits(_binary, _acc, _any), do: :error

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

  @impl true
  def init(:ok) do
    brightness = decode_brightness(Nvs.get(:brightness))
    sleep = decode_sleep(Nvs.get(:sleep))

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
        duty: duty(brightness),
        gpio_num: Hardware.display_backlight(),
        speed_mode: LEDC.low_speed_mode(),
        hpoint: 0,
        timer_sel: @timer
      )

    :io.format(~c"Backlight: pwm on GPIO~p at ~p%, sleep ~s~n", [
      Hardware.display_backlight(),
      brightness,
      sleep_label(sleep)
    ])

    {:ok, %{percent: brightness, sleep: sleep}}
  end

  @impl true
  def handle_call(:settings, _from, state) do
    {:reply, %{brightness: state.percent, sleep: state.sleep}, state}
  end

  @impl true
  def handle_cast({:store, percent, sleep}, state) do
    Nvs.put(:brightness, :erlang.integer_to_binary(percent))
    Nvs.put(:sleep, sleep_label(sleep))

    {:noreply, %{state | sleep: sleep}}
  end

  # Duty is driven straight, so the saved percentage survives the blanking.
  def handle_cast(:sleep, state) do
    drive(0)

    {:noreply, state}
  end

  def handle_cast(:wake, state) do
    drive(state.percent)

    {:noreply, state}
  end

  def handle_cast({:set, percent}, %{percent: percent} = state), do: {:noreply, state}

  def handle_cast({:set, percent}, state) do
    drive(percent)

    {:noreply, %{state | percent: percent}}
  end

  defp drive(percent) do
    :ok = LEDC.set_duty(LEDC.low_speed_mode(), @channel, duty(percent))
    :ok = LEDC.update_duty(LEDC.low_speed_mode(), @channel)
  end
end
