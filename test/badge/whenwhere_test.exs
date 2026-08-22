defmodule Badge.WhenwhereTest do
  use ExUnit.Case, async: true

  alias Badge.Whenwhere

  # Captured verbatim from http://whenwhere.nerves-project.org on 2026-08-22.
  @body ~s({"now":"2026-08-22T13:51:47.623Z","time_zone":"Europe/Luxembourg",) <>
          ~s("latitude":"49.74980","longitude":"6.16610","country":"LU",) <>
          ~s("address":"2001:7e8:fc14:7001:f8f9:ea8a:ec1f:f130:63141"})

  describe "a real response" do
    test "yields the zone and the coordinates" do
      assert {:ok, place} = Whenwhere.parse(@body)

      assert place.zone == "Europe/Luxembourg"
      assert place.latitude == "49.74980"
      assert place.longitude == "6.16610"
      assert place.country == "LU"
    end

    test "a Swedish response places the event" do
      body = ~s({"now":"2026-10-05T09:00:00.000Z","time_zone":"Europe/Stockholm",) <>
               ~s("latitude":"57.10557","longitude":"12.25078","country":"SE"})

      assert {:ok, %{zone: "Europe/Stockholm", country: "SE"}} = Whenwhere.parse(body)
    end
  end

  describe "a response we cannot use" do
    test "no zone is not a place" do
      assert Whenwhere.parse(~s({"latitude":"1.0","longitude":"2.0"})) == :error
    end

    test "malformed json is not a place" do
      assert Whenwhere.parse("{not json") == :error
      assert Whenwhere.parse("") == :error
    end

    test "an empty body is not a place" do
      assert Whenwhere.parse("null") == :error
    end
  end

  describe "coordinates that are missing" do
    test "come back empty rather than crashing the fetch" do
      assert {:ok, place} = Whenwhere.parse(~s({"time_zone":"UTC"}))

      assert place.latitude == ""
      assert place.longitude == ""
      assert place.country == ""
    end
  end
end
