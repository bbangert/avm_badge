defmodule Badge.Page.Temp do
  @moduledoc """
  Plots the TMP103 reading over time as a bar chart.

  History starts empty on every entry and fills at one sample per second,
  so the plot spans the panel after about 76 seconds. The sampling clock is
  an argument rather than a counter in state, so ticks that add nothing
  return the state unchanged and cost no frame.
  """

  use Badge.Page

  alias Badge.Sensors
  alias Badge.Theme

  @accent Theme.accent()
  @fg Theme.fg()
  @dim Theme.dim()
  @bg Theme.bg()

  @max_samples 76

  @plot_x 8
  @plot_top 56
  @plot_bottom 200
  @bar_w 3
  @bar_pitch 4

  # Smallest span the scale will show, so a steady reading is a flat line.
  @min_span 4

  @readout_y 30
  @footer_y 206

  @impl true
  def title, do: "Temp"

  @impl true
  def icon, do: :cross

  @impl true
  def init, do: %{samples: [], last_second: nil}

  @impl true
  def tick(state), do: update(state, {second(), Sensors.temperature()})

  @doc "Appends a reading, at most one per second."
  def update(state, {_second, :unavailable}), do: state

  def update(%{last_second: second} = state, {second, _temp}), do: state

  def update(state, {second, temp}) do
    %{state | samples: push(state.samples, temp), last_second: second}
  end

  defp second, do: div(:erlang.monotonic_time(:millisecond), 1000)

  defp push(samples, temp) when length(samples) >= @max_samples do
    [_oldest | rest] = samples

    rest ++ [temp]
  end

  defp push(samples, temp), do: samples ++ [temp]

  @impl true
  def render(%{samples: []}) do
    [{:text, @plot_x, @readout_y, :dogica, @dim, @bg, "waiting"}, baseline()]
  end

  def render(%{samples: samples}) do
    low = :lists.min(samples)
    high = :lists.max(samples)
    {floor, ceiling} = span(low, high)

    [readout(:lists.last(samples)), footer(low, high, length(samples)), baseline()] ++
      bars(samples, floor, ceiling, @plot_x, [])
  end

  # Widens a narrow span symmetrically so one degree of quantisation does not fill the plot.
  defp span(low, high) do
    padding = @min_span - (high - low)

    case padding > 0 do
      true -> {low - div(padding + 1, 2), high + div(padding, 2)}
      false -> {low, high}
    end
  end

  defp bars([], _floor, _ceiling, _x, acc), do: :lists.reverse(acc)

  defp bars([temp | rest], floor, ceiling, x, acc) do
    top = @plot_bottom - div((temp - floor) * (@plot_bottom - @plot_top), ceiling - floor)
    item = {:rect, x, top, @bar_w, @plot_bottom - top + 1, @accent}

    bars(rest, floor, ceiling, x + @bar_pitch, [item | acc])
  end

  defp readout(temp) do
    {:text, @plot_x, @readout_y, :dogica, @fg, @bg, :erlang.integer_to_binary(temp) <> " C"}
  end

  defp footer(low, high, count) do
    body =
      "min " <>
        :erlang.integer_to_binary(low) <>
        "   max " <>
        :erlang.integer_to_binary(high) <>
        "   n " <> :erlang.integer_to_binary(count)

    {:text, @plot_x, @footer_y, :default16px, @dim, @bg, body}
  end

  defp baseline do
    {:rect, @plot_x, @plot_bottom, @max_samples * @bar_pitch, 1, @dim}
  end
end
