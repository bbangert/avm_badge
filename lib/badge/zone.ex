defmodule Badge.Zone do
  @moduledoc """
  Minutes east of UTC for the few time zones the badge knows.

  `whenwhere.nerves-project.org` reports an IANA zone name and no offset, and
  a whole zone database will not fit: a large compile-time literal breaks
  AtomVM's literals table. So the zones the badge is used in are listed here
  and everything else reads UTC.

  The European rule is arithmetic rather than a stored table. Summer time runs
  from 01:00 UTC on the last Sunday in March to 01:00 UTC on the last Sunday
  in October, which stays right without anything to update each year.
  """

  @day 86_400
  @hour 3_600

  # {zone, standard minutes east of UTC, summer time rule}
  @zones [
    {"Europe/Stockholm", 60, :eu},
    {"Europe/Luxembourg", 60, :eu},
    {"UTC", 0, :none},
    {"Etc/UTC", 0, :none}
  ]

  @summer 60

  @doc "The zones this badge can place."
  @spec known() :: [binary]
  def known, do: for({zone, _standard, _rule} <- @zones, do: zone)

  @doc """
  Minutes east of UTC for a zone at a moment, or nil for a zone that is not
  in `known/0`.
  """
  @spec offset_minutes(binary | nil, integer) :: integer | nil
  def offset_minutes(zone, utc_seconds) do
    case :lists.keyfind(zone, 1, @zones) do
      {_zone, standard, rule} -> standard + summer(rule, utc_seconds)
      false -> nil
    end
  end

  defp summer(:none, _utc_seconds), do: 0

  defp summer(:eu, utc_seconds) do
    year = year_of(utc_seconds)

    inside(utc_seconds >= changes_at(year, 3) and utc_seconds < changes_at(year, 10))
  end

  defp inside(true), do: @summer
  defp inside(false), do: 0

  # 01:00 UTC on the last Sunday of a 31 day month.
  defp changes_at(year, month) do
    last = days_from_civil(year, month, 31)

    (last - weekday(last)) * @day + @hour
  end

  # 1970-01-01 was a Thursday, and Sunday is 0 here.
  defp weekday(days), do: rem(days + 4, 7)

  # Howard Hinnant's civil_from_days, kept to the year it lands in.
  defp year_of(utc_seconds) do
    z = div(utc_seconds, @day) + 719_468
    era = div(z, 146_097)
    doe = z - era * 146_097
    yoe = div(doe - div(doe, 1460) + div(doe, 36_524) - div(doe, 146_096), 365)
    doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))

    yoe + era * 400 + carry(month_of(div(5 * doy + 2, 153)))
  end

  defp month_of(mp) when mp < 10, do: mp + 3
  defp month_of(mp), do: mp - 9

  defp carry(month) when month <= 2, do: 1
  defp carry(_month), do: 0

  # Howard Hinnant's days_from_civil.
  defp days_from_civil(year, month, day) do
    y = year - carry(month)
    era = div(y, 400)
    yoe = y - era * 400
    doy = div(153 * (month + shift(month)) + 2, 5) + day - 1
    doe = yoe * 365 + div(yoe, 4) - div(yoe, 100) + doy

    era * 146_097 + doe - 719_468
  end

  defp shift(month) when month > 2, do: -3
  defp shift(_month), do: 9
end
