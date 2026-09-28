defmodule Badge.LedModeTest do
  use ExUnit.Case, async: true

  alias Badge.LedMode

  describe "the modes" do
    test "white sits alongside the ones that were already there" do
      assert LedMode.modes() == [:rainbow, :dusk, :solid, :white, :off]
    end

    test "every mode has a name, and no two share one" do
      names = for mode <- LedMode.modes(), do: LedMode.name(mode)

      assert names == ["rainbow", "dusk", "solid", "white", "off"]
      assert length(:lists.usort(names)) == length(names)
    end
  end

  describe "round tripping through NVS" do
    test "a static mode survives" do
      for mode <- [:rainbow, :dusk, :white, :off] do
        assert LedMode.decode(LedMode.encode(mode)) == mode
      end
    end

    test "a solid mode keeps its hue" do
      for hue <- [0, 15, 120, 359] do
        assert LedMode.decode(LedMode.encode({:solid, hue})) == {:solid, hue}
      end
    end

    test "encoding is readable, not a term blob" do
      assert LedMode.encode(:white) == "white"
      assert LedMode.encode({:solid, 120}) == "solid:120"
    end
  end

  describe "dusk" do
    test "passes through magenta, violet and cyan at full brightness" do
      assert LedMode.dusk(0, 255) == {0xE8, 0x5F, 0xAF}
      assert LedMode.dusk(120, 255) == {0x8A, 0x63, 0xE8}
      assert LedMode.dusk(240, 255) == {0x5C, 0xC8, 0xF5}
    end

    test "loops back to magenta" do
      assert LedMode.dusk(360, 255) == LedMode.dusk(0, 255)
    end

    test "blends between stops" do
      {r, _g, b} = LedMode.dusk(60, 255)

      assert r < 0xE8 and r > 0x8A
      assert b > 0xAF and b < 0xE8
    end

    test "scales to the brightness asked for" do
      for position <- 0..359 do
        {r, g, b} = LedMode.dusk(position, 40)

        assert r <= 40 and g <= 40 and b <= 40
      end
    end
  end

  describe "anything unreadable" do
    test "falls back to rainbow rather than crashing the chain" do
      for stored <- [nil, "", "nonsense", "solid", "solid:", "solid:abc", "solid:-5"] do
        assert LedMode.decode(stored) == :rainbow
      end
    end

    test "a hue outside the circle is not a solid mode" do
      assert LedMode.decode("solid:360") == :rainbow
      assert LedMode.decode("solid:9999") == :rainbow
    end
  end
end
