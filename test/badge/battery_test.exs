defmodule Badge.BatteryTest do
  use ExUnit.Case, async: true

  alias Badge.Battery
  alias Badge.Icons

  describe "percent/1" do
    test "clamps at both rails" do
      assert Battery.percent(3000) == 0
      assert Battery.percent(3300) == 0
      assert Battery.percent(4200) == 100
      assert Battery.percent(4500) == 100
    end

    test "is monotonic across the working range" do
      assert Battery.percent(3500) < Battery.percent(3800)
      assert Battery.percent(3800) < Battery.percent(4100)
    end

    test "the midpoint is about half" do
      assert_in_delta Battery.percent(3750), 50, 2
    end
  end

  describe "icon/2" do
    test "usb power shows charging whatever the voltage" do
      assert Battery.icon(3300, true) == :battery_charging
      assert Battery.icon(4200, true) == :battery_charging
    end

    test "each level maps to its own icon" do
      assert Battery.icon(4200, false) == :battery_100
      assert Battery.icon(3980, false) == :battery_75
      assert Battery.icon(3750, false) == :battery_50
      assert Battery.icon(3520, false) == :battery_25
      assert Battery.icon(3300, false) == :battery_0
    end

    test "the icon only ever drops as the voltage falls" do
      order = [:battery_0, :battery_25, :battery_50, :battery_75, :battery_100]

      indices =
        for mv <- [3300, 3400, 3500, 3600, 3700, 3800, 3900, 4000, 4100, 4200] do
          icon = Battery.icon(mv, false)

          length(:lists.takewhile(fn name -> name != icon end, order))
        end

      assert indices == :lists.sort(indices)
    end

    test "every icon it can return actually exists" do
      names = Icons.names()

      for mv <- [3200, 3400, 3600, 3800, 4000, 4300], usb <- [true, false] do
        assert Battery.icon(mv, usb) in names
      end
    end

    test "the status icons are all the same size, so the bar lines up" do
      sizes =
        for name <- [:battery_0, :battery_25, :battery_50, :battery_75, :battery_100,
                     :battery_charging, :wifi, :wifi_slash],
            do: Icons.size(name)

      assert :lists.usort(sizes) == [{16, 16}]
    end
  end
end
