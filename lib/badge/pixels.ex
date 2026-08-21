defmodule Badge.Pixels do
  @moduledoc """
  Drives the SK6812 / WS2812 chain using the SPI peripheral as a waveform
  generator.

  These LEDs read a self-clocked NRZ bitstream: each bit is a fixed-width
  pulse whose high time carries the value (short = 0, long = 1). A frame is
  latched by holding the line low past the chip's reset threshold. Each LED
  bit is expanded to four SPI bits (`0b1000` for 0, `0b1100` for 1), so each
  colour byte becomes four SPI bytes and each pixel costs twelve.

  The animation runs on a timer rather than a sleep loop so it shares the
  scheduler with the keyboard scan and display updates.
  """

  use GenServer

  import Bitwise

  alias Badge.Color
  alias Badge.Hardware

  @device :pixels

  # Expansion table, indexed by a pair of LED bits: 0b1000 / 0b1100 per bit.
  @nibble_pairs {0x88, 0x8C, 0xC8, 0xCC}

  # Idle bytes to hold the line low long enough to latch a frame.
  @latch :binary.copy(<<0>>, 40)

  @brightness 40

  @tick 20
  @hue_step 3

  # Long enough to catch the eye across a table, short enough not to linger.
  @flash_ticks div(600, @tick)

  def start_link(spi) do
    GenServer.start_link(__MODULE__, spi, name: __MODULE__)
  end

  @doc """
  Sets what the chain displays.

  `:rainbow` animates; `{:solid, hue}` and `:off` are static and are only
  written to the chain once.
  """
  def set_mode(mode) do
    GenServer.cast(__MODULE__, {:mode, mode})
  end

  @doc """
  Shows a colour briefly, then goes back to whatever was set before.

  The countdown rides the animation tick that is already running, so a flash
  costs no timer and cannot outlive the chain going quiet.
  """
  @spec flash(non_neg_integer) :: :ok
  def flash(hue) do
    GenServer.cast(__MODULE__, {:flash, hue, @flash_ticks})
  end

  @impl true
  def init(spi) do
    :io.format(~c"Pixels: ~p LEDs on GPIO ~p at ~p Hz~n", [
      Hardware.pixel_count(),
      Hardware.pixel_data(),
      Hardware.pixel_clock_hz()
    ])

    {:ok, %{spi: spi, phase: 0, mode: :rainbow, last: nil, flash: nil}, {:continue, :self_test}}
  end

  # Runs the self-test after init/1 returns, not during it.
  @impl true
  def handle_continue(:self_test, %{spi: spi} = state) do
    self_test(spi)
    send(self(), :tick)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mode, mode}, state) do
    {:noreply, %{state | mode: mode}}
  end

  def handle_cast({:flash, hue, ticks}, state) do
    {:noreply, %{state | flash: {hue, ticks}}}
  end

  @impl true
  def handle_info(:tick, state) do
    next = paint(state)

    # Sleeps rather than using Process.send_after/3.
    Process.sleep(@tick)
    send(self(), :tick)

    {:noreply, next}
  end

  # A flash outranks the mode until its ticks run out, then the mode resumes
  # on its own because `last` no longer matches.
  defp paint(%{flash: {_hue, 0}} = state), do: paint(%{state | flash: nil})

  defp paint(%{flash: {hue, left}} = state) do
    lit = hold(state, Color.hsv_to_rgb(hue, 255, @brightness))

    %{lit | flash: {hue, left - 1}}
  end

  defp paint(%{mode: :rainbow, spi: spi, phase: phase} = state) do
    frame(spi, phase)

    %{state | phase: rem(phase + @hue_step, 360), last: nil}
  end

  defp paint(%{mode: {:solid, hue}} = state) do
    hold(state, Color.hsv_to_rgb(hue, 255, @brightness))
  end

  defp paint(%{mode: :off} = state), do: hold(state, {0, 0, 0})

  # A static mode would otherwise rewrite the chain fifty times a second.
  defp hold(%{last: colour} = state, colour), do: state

  defp hold(%{spi: spi} = state, colour) do
    fill(spi, colour)

    %{state | last: colour}
  end

  # Solid colours, in order, make byte-order and wiring faults visible.
  defp self_test(spi) do
    Enum.each(
      [
        {~c"red", {@brightness, 0, 0}},
        {~c"green", {0, @brightness, 0}},
        {~c"blue", {0, 0, @brightness}},
        {~c"white", {@brightness, @brightness, @brightness}}
      ],
      fn {name, colour} ->
        :io.format(~c"Pixels: all ~s~n", [name])
        fill(spi, colour)
        Process.sleep(700)
      end
    )

    fill(spi, {0, 0, 0})
    Process.sleep(300)
  end

  defp frame(spi, phase) do
    count = Hardware.pixel_count()

    for(
      i <- 0..(count - 1),
      do: Color.hsv_to_rgb(rem(phase + i * div(360, count), 360), 255, @brightness)
    )
    |> then(&show(spi, &1))
  end

  defp show(spi, pixels) do
    frame =
      pixels
      |> Enum.map(&encode_pixel/1)
      |> Enum.reduce(<<>>, fn bytes, acc -> acc <> bytes end)

    :ok = :spi.write(spi, @device, %{write_data: frame <> @latch})
  end

  defp fill(spi, colour) do
    show(spi, List.duplicate(colour, Hardware.pixel_count()))
  end

  # SK6812 and WS2812 both take green first.
  defp encode_pixel({r, g, b}) do
    encode_byte(g) <> encode_byte(r) <> encode_byte(b)
  end

  defp encode_byte(byte) do
    <<expand(byte >>> 6), expand(byte >>> 4), expand(byte >>> 2), expand(byte)>>
  end

  defp expand(bits), do: elem(@nibble_pairs, bits &&& 0x03)
end
