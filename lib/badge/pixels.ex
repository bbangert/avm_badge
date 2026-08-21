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

  alias Badge.Hardware

  @device :pixels

  # Expansion table, indexed by a pair of LED bits: 0b1000 / 0b1100 per bit.
  @nibble_pairs {0x88, 0x8C, 0xC8, 0xCC}

  # Idle bytes to hold the line low long enough to latch a frame.
  @latch :binary.copy(<<0>>, 40)

  @brightness 40

  @tick 20
  @hue_step 3

  def start_link(spi) do
    GenServer.start_link(__MODULE__, spi, name: __MODULE__)
  end

  @impl true
  def init(spi) do
    :io.format(~c"Pixels: ~p LEDs on GPIO ~p at ~p Hz~n", [
      Hardware.pixel_count(),
      Hardware.pixel_data(),
      Hardware.pixel_clock_hz()
    ])

    {:ok, %{spi: spi, phase: 0}, {:continue, :self_test}}
  end

  # Runs the self-test after init/1 returns, not during it.
  @impl true
  def handle_continue(:self_test, %{spi: spi} = state) do
    self_test(spi)
    send(self(), :tick)

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, %{spi: spi, phase: phase} = state) do
    frame(spi, phase)

    # Sleeps rather than using Process.send_after/3.
    Process.sleep(@tick)
    send(self(), :tick)

    {:noreply, %{state | phase: rem(phase + @hue_step, 360)}}
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
      do: hsv_to_rgb(rem(phase + i * div(360, count), 360), 255, @brightness)
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

  # Integer HSV: hue 0..359, saturation and value 0..255.
  defp hsv_to_rgb(h, s, v) do
    sector = div(h, 60)
    offset = div(rem(h, 60) * 255, 60)

    p = div(v * (255 - s), 255)
    q = div(v * (255 - div(s * offset, 255)), 255)
    t = div(v * (255 - div(s * (255 - offset), 255)), 255)

    sector_rgb(sector, v, p, q, t)
  end

  defp sector_rgb(0, v, p, _q, t), do: {v, t, p}
  defp sector_rgb(1, v, p, q, _t), do: {q, v, p}
  defp sector_rgb(2, v, p, _q, t), do: {p, v, t}
  defp sector_rgb(3, v, p, q, _t), do: {p, q, v}
  defp sector_rgb(4, v, p, _q, t), do: {t, p, v}
  defp sector_rgb(_, v, p, q, _t), do: {v, p, q}
end
