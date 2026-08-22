defmodule Badge.Clock do
  @moduledoc """
  Formats a number of seconds as a clock face, and shifts UTC into local
  time.

  The badge has no RTC, so the title bar shows uptime until SNTP syncs the
  system clock; after that it shows local wall time using the offset
  `Badge.Zone` derives from the zone the badge was placed in.
  """

  @day 86_400
  @hour 3_600
  @minute 60

  # UTC-12 to UTC+14, the real span of world time zones.
  @min_offset -720
  @max_offset 840

  @doc "Formats seconds as HH:MM:SS, wrapping after a day."
  @spec format(integer) :: binary
  def format(seconds) when seconds < 0, do: format(0)

  def format(seconds) do
    within_day = rem(seconds, @day)

    pad(div(within_day, @hour)) <>
      ":" <> pad(div(rem(within_day, @hour), @minute)) <> ":" <> pad(rem(within_day, @minute))
  end

  @doc """
  Parses a provisioned UTC offset in minutes east of UTC.

  Absent, malformed or out-of-range values all give zero: a clock in the
  wrong zone beats a crash at boot.
  """
  @spec offset_minutes(binary | nil) :: integer
  def offset_minutes(nil), do: 0
  def offset_minutes(<<>>), do: 0
  def offset_minutes(<<?-, rest::binary>>), do: in_range(-digits(rest, 0))
  def offset_minutes(binary), do: in_range(digits(binary, 0))

  @doc """
  The clock face for a UTC moment.

  A badge whose zone is not known shows UTC and says so, rather than a local
  time that is quietly an hour or two wrong.
  """
  @spec face(integer, integer | nil) :: binary
  def face(utc_seconds, nil), do: format(utc_seconds) <> " UTC"
  def face(utc_seconds, offset_minutes), do: format(local_seconds(utc_seconds, offset_minutes))

  @doc "Shifts an epoch timestamp into local time."
  @spec local_seconds(integer, integer) :: integer
  def local_seconds(epoch_seconds, offset_minutes) do
    epoch_seconds + offset_minutes * @minute
  end

  defp pad(value) when value < 10, do: "0" <> :erlang.integer_to_binary(value)
  defp pad(value), do: :erlang.integer_to_binary(value)

  # Any non-digit collapses the whole value to zero, which in_range/1 passes through.
  defp digits(<<>>, acc), do: acc

  defp digits(<<digit, rest::binary>>, acc) when digit >= ?0 and digit <= ?9 do
    digits(rest, acc * 10 + (digit - ?0))
  end

  defp digits(_binary, _acc), do: 0

  defp in_range(minutes) when minutes < @min_offset, do: 0
  defp in_range(minutes) when minutes > @max_offset, do: 0
  defp in_range(minutes), do: minutes
end
