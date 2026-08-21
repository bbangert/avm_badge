defmodule Badge.Page.Info do
  @moduledoc """
  Board status: battery, USB, temperature, orientation and uptime.

  The page state is the reading map itself, so `render/1` can be driven
  from a literal in tests.
  """

  use Badge.Page

  alias Badge.Power
  alias Badge.Sensors
  alias Badge.Theme

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @label_x 8
  @value_x 120
  @top 34
  @pitch 18

  @bar_x 8
  @bar_y 190
  @bar_w 304
  @bar_h 14

  # Li-ion working range for the percentage bar.
  @mv_empty 3300
  @mv_full 4200

  # Milli-g the accelerometer readout rounds to.
  @accel_quantum 10

  @row_ys for i <- 0..5, do: @top + i * @pitch

  # Nothing here moves fast enough to be worth a full repaint ten times a second.
  @impl true
  def refresh, do: 333

  @impl true
  def title, do: "Info"

  @impl true
  def icon, do: :circle

  @impl true
  def init do
    %{battery_mv: 0, vbus_mv: 0, usb: false, temp: :unavailable, accel: {0, 0, 0}, uptime_s: 0}
  end

  @impl true
  def tick(state), do: update(state, read())

  @doc "Adopts a fresh reading map, rounding the axes that would otherwise jitter."
  def update(_state, reading), do: %{reading | accel: coarse(reading.accel)}

  @doc "Battery charge as a percentage of the li-ion working range."
  def percent(mv) when mv <= @mv_empty, do: 0
  def percent(mv) when mv >= @mv_full, do: 100
  def percent(mv), do: div((mv - @mv_empty) * 100, @mv_full - @mv_empty)

  @impl true
  def render(reading) do
    row_items(rows(reading), @row_ys, []) ++ battery_bar(reading.battery_mv)
  end

  defp read do
    %{
      battery_mv: Power.battery_mv(),
      vbus_mv: Power.vbus_mv(),
      usb: Power.usb_present?(),
      temp: Sensors.temperature(),
      accel: Sensors.acceleration(),
      uptime_s: div(:erlang.monotonic_time(:millisecond), 1000)
    }
  end

  defp rows(reading) do
    [
      {"battery", int(reading.battery_mv) <> " mV   " <> int(percent(reading.battery_mv)) <> "%"},
      {"vbus", int(reading.vbus_mv) <> " mV"},
      {"usb", usb(reading.usb)},
      {"temp", temp(reading.temp)},
      {"accel", accel(reading.accel)},
      {"uptime", int(reading.uptime_s) <> " s"}
    ]
  end

  # Labels and row positions threaded together, since Enum.with_index/1 is absent on AtomVM.
  defp row_items([], [], acc), do: :lists.reverse(acc)

  defp row_items([{label, value} | rest], [y | ys], acc) do
    label_item = {:text, @label_x, y, :default16px, @dim, @bg, label}
    value_item = {:text, @value_x, y, :default16px, @fg, @bg, value}

    row_items(rest, ys, [value_item, label_item | acc])
  end

  # Fill first, frame second: the frame shows through as the unfilled remainder.
  defp battery_bar(mv) do
    [
      {:rect, @bar_x, @bar_y, div(@bar_w * percent(mv), 100), @bar_h, @accent},
      {:rect, @bar_x, @bar_y, @bar_w, @bar_h, @dim}
    ]
  end

  defp usb(true), do: "present"
  defp usb(false), do: "absent"

  defp temp(:unavailable), do: "--"
  defp temp(degrees), do: int(degrees) <> " C"

  defp accel({x, y, z}), do: int(x) <> " " <> int(y) <> " " <> int(z)

  defp int(value), do: :erlang.integer_to_binary(value)

  # The EMA jitters by a few milli-g at rest; unrounded it would dirty the page every tick.
  defp coarse({x, y, z}), do: {round_to(x), round_to(y), round_to(z)}

  defp round_to(value), do: div(value, @accel_quantum) * @accel_quantum
end
