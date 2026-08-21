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

  describe "average/2" do
    test "nil previous adopts the sample as-is" do
      assert Accel.average(nil, {100, 200, 300}) == {100, 200, 300}
    end

    test "moves a quarter of the way to the new sample per axis" do
      assert Accel.average({100, 200, 300}, {200, 200, 700}) == {125, 200, 400}
    end

    test "converges toward a steady input" do
      steady = {1000, -500, 250}

      averaged =
        Enum.reduce(1..20, nil, fn _, acc -> Accel.average(acc, steady) end)

      assert averaged == steady
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
