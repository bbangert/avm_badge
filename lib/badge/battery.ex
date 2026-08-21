defmodule Badge.Battery do
  @moduledoc """
  Turns a battery voltage into a charge percentage and an icon name.

  Pure: the voltage comes from `Badge.Power`, which owns the ADC.
  """

  @mv_empty 3300
  @mv_full 4200

  # Midpoints between the five icon levels.
  @full 88
  @high 63
  @half 38
  @low 13

  @doc "Charge as a percentage of the li-ion working range."
  @spec percent(integer) :: 0..100
  def percent(mv) when mv <= @mv_empty, do: 0
  def percent(mv) when mv >= @mv_full, do: 100
  def percent(mv), do: div((mv - @mv_empty) * 100, @mv_full - @mv_empty)

  @doc "Icon name for a voltage, or the charging icon while USB is supplying power."
  @spec icon(integer, boolean) :: atom
  def icon(_mv, true), do: :battery_charging
  def icon(mv, false), do: level_icon(percent(mv))

  defp level_icon(percent) when percent >= @full, do: :battery_100
  defp level_icon(percent) when percent >= @high, do: :battery_75
  defp level_icon(percent) when percent >= @half, do: :battery_50
  defp level_icon(percent) when percent >= @low, do: :battery_25
  defp level_icon(_percent), do: :battery_0
end
