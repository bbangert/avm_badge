defmodule Badge.LedModeTest do
  use ExUnit.Case, async: true

  alias Badge.LedMode

  describe "the modes" do
    test "white sits alongside the ones that were already there" do
      assert LedMode.modes() == [:rainbow, :solid, :white, :off]
    end

    test "every mode has a name, and no two share one" do
      names = for mode <- LedMode.modes(), do: LedMode.name(mode)

      assert names == ["rainbow", "solid", "white", "off"]
      assert length(:lists.usort(names)) == length(names)
    end
  end

  describe "round tripping through NVS" do
    test "a static mode survives" do
      for mode <- [:rainbow, :white, :off] do
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
