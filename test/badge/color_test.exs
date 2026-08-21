defmodule Badge.ColorTest do
  use ExUnit.Case, async: true

  alias Badge.Color

  describe "hsv_to_rgb/3" do
    test "the six primary hues land on the expected sector" do
      assert Color.hsv_to_rgb(0, 255, 255) == {255, 0, 0}
      assert Color.hsv_to_rgb(120, 255, 255) == {0, 255, 0}
      assert Color.hsv_to_rgb(240, 255, 255) == {0, 0, 255}
    end

    test "zero saturation is grey at the value level" do
      assert Color.hsv_to_rgb(0, 0, 200) == {200, 200, 200}
      assert Color.hsv_to_rgb(180, 0, 200) == {200, 200, 200}
    end

    test "zero value is black at any hue" do
      assert Color.hsv_to_rgb(0, 255, 0) == {0, 0, 0}
      assert Color.hsv_to_rgb(300, 255, 0) == {0, 0, 0}
    end

    test "every hue in range returns three bytes" do
      for hue <- 0..359 do
        {r, g, b} = Color.hsv_to_rgb(hue, 255, 40)

        assert r >= 0 and r <= 255
        assert g >= 0 and g <= 255
        assert b >= 0 and b <= 255
      end
    end
  end

  describe "rgb888/1" do
    test "packs each channel into its byte" do
      assert Color.rgb888({0xFF, 0x00, 0x00}) == 0xFF0000
      assert Color.rgb888({0x00, 0xE5, 0xA0}) == 0x00E5A0
      assert Color.rgb888({0, 0, 0}) == 0x000000
      assert Color.rgb888({255, 255, 255}) == 0xFFFFFF
    end
  end
end
