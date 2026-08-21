defmodule Badge.AccelTest do
  use ExUnit.Case, async: true

  alias Badge.Accel

  describe "decode/1" do
    test "converts raw counts to milli-g" do
      bytes = <<-1120::little-signed-16, 13936::little-signed-16, -9184::little-signed-16>>
      assert Accel.decode(bytes) == {-68, 850, -560}
    end

    test "a stationary reading has unit magnitude" do
      # Real probe reading of a badge sitting flat on a desk.
      bytes = <<-1120::little-signed-16, 13936::little-signed-16, -9184::little-signed-16>>
      {x, y, z} = Accel.decode(bytes)
      magnitude = :math.sqrt(x * x + y * y + z * z)

      assert_in_delta magnitude, 1000, 30
    end
  end

  describe "orientation/1" do
    test "flat, z up, gives zero roll and pitch" do
      assert Accel.orientation({0, 0, 1000}) == {0, 0}
    end

    test "rolled 90 degrees onto its side" do
      assert Accel.orientation({0, 1000, 0}) == {90, 0}
    end

    test "pitched 90 degrees nose down" do
      assert Accel.orientation({1000, 0, 0}) == {0, -90}
    end
  end
end
