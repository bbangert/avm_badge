defmodule Badge.Page.Info.Power do
  @moduledoc """
  Battery, USB and uptime, the second of Info's sub-pages.

  The page state is the reading map itself, so `render/1` can be driven from
  a literal in tests.
  """

  use Badge.Page

  alias Badge.Battery
  alias Badge.Page.Info
  alias Badge.Power
  alias Badge.Readout
  alias Badge.Theme

  @accent Theme.accent()
  @dim Theme.dim()

  @bar_x 8
  @bar_y 190
  @bar_w 304
  @bar_h 14

  @impl true
  def title, do: "Power"

  @impl true
  def init, do: %{battery_mv: 0, vbus_mv: 0, usb: false, uptime_s: 0}

  @impl true
  def tick(state), do: update(state, read())

  @doc "Adopts a fresh reading."
  def update(_state, reading), do: reading

  @impl true
  def render(reading) do
    rows =
      Readout.rows(
        [
          {"battery", int(reading.battery_mv) <> " mV"},
          {"charge", int(Battery.percent(reading.battery_mv)) <> "%"},
          {"vbus", int(reading.vbus_mv) <> " mV"},
          {"usb", usb(reading.usb)},
          {"uptime", int(reading.uptime_s) <> " s"}
        ],
        Info.content_top()
      )

    rows ++ bar(reading.battery_mv)
  end

  defp read do
    power = Power.status()

    %{
      battery_mv: power.battery_mv,
      vbus_mv: power.vbus_mv,
      usb: power.usb,
      uptime_s: div(:erlang.monotonic_time(:millisecond), 1000)
    }
  end

  # Fill first, frame second: the frame shows through as the unfilled remainder.
  defp bar(mv) do
    [
      {:rect, @bar_x, @bar_y, div(@bar_w * Battery.percent(mv), 100), @bar_h, @accent},
      {:rect, @bar_x, @bar_y, @bar_w, @bar_h, @dim}
    ]
  end

  defp usb(true), do: "present"
  defp usb(false), do: "absent"

  defp int(value), do: :erlang.integer_to_binary(value)
end
