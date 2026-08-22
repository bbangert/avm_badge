defmodule Badge.ZoneTest do
  use ExUnit.Case, async: true

  alias Badge.Zone

  # Host-only helper: turns a UTC calendar time into an epoch second.
  defp utc(y, m, d, h, mi, s) do
    :calendar.datetime_to_gregorian_seconds({{y, m, d}, {h, mi, s}}) - 62_167_219_200
  end

  describe "zones the badge does not know" do
    test "have no offset rather than a wrong one" do
      assert Zone.offset_minutes("America/New_York", utc(2026, 10, 5, 12, 0, 0)) == nil
      assert Zone.offset_minutes("Australia/Sydney", utc(2026, 10, 5, 12, 0, 0)) == nil
    end

    test "a missing or malformed name is not a zone either" do
      assert Zone.offset_minutes(nil, utc(2026, 10, 5, 12, 0, 0)) == nil
      assert Zone.offset_minutes("", utc(2026, 10, 5, 12, 0, 0)) == nil
      assert Zone.offset_minutes("Europe/Nowhere", utc(2026, 10, 5, 12, 0, 0)) == nil
    end

    test "the covered zones are named, so what is missing is visible" do
      assert "Europe/Stockholm" in Zone.known()
      assert "Europe/Luxembourg" in Zone.known()
    end
  end

  describe "the event in Varberg" do
    test "early October is still summer time, an hour ahead of standard" do
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 10, 5, 12, 0, 0)) == 120
    end

    test "Luxembourg keeps the same clock as Sweden" do
      moment = utc(2026, 10, 5, 12, 0, 0)

      assert Zone.offset_minutes("Europe/Luxembourg", moment) ==
               Zone.offset_minutes("Europe/Stockholm", moment)
    end
  end

  describe "the European summer time rule" do
    test "winter is one hour east of UTC" do
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 1, 15, 12, 0, 0)) == 60
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 11, 15, 12, 0, 0)) == 60
    end

    test "summer is two" do
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 6, 15, 12, 0, 0)) == 120
    end

    test "it starts at 01:00 UTC on the last Sunday in March" do
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 3, 29, 0, 59, 59)) == 60
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 3, 29, 1, 0, 0)) == 120
    end

    test "it ends at 01:00 UTC on the last Sunday in October" do
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 10, 25, 0, 59, 59)) == 120
      assert Zone.offset_minutes("Europe/Stockholm", utc(2026, 10, 25, 1, 0, 0)) == 60
    end

    test "the boundary follows the calendar, not a fixed date" do
      # 2027 switches on 28 March and 31 October; 2028 on 26 March and 29 October.
      assert Zone.offset_minutes("Europe/Stockholm", utc(2027, 3, 28, 1, 0, 0)) == 120
      assert Zone.offset_minutes("Europe/Stockholm", utc(2027, 10, 31, 0, 59, 59)) == 120
      assert Zone.offset_minutes("Europe/Stockholm", utc(2027, 10, 31, 1, 0, 0)) == 60
      assert Zone.offset_minutes("Europe/Stockholm", utc(2028, 3, 26, 1, 0, 0)) == 120
      assert Zone.offset_minutes("Europe/Stockholm", utc(2028, 10, 29, 1, 0, 0)) == 60
    end
  end

  describe "UTC itself" do
    test "is known and never shifts" do
      assert Zone.offset_minutes("UTC", utc(2026, 1, 15, 12, 0, 0)) == 0
      assert Zone.offset_minutes("UTC", utc(2026, 6, 15, 12, 0, 0)) == 0
    end
  end
end
