defmodule Badge.ClockTest do
  use ExUnit.Case, async: true

  alias Badge.Clock

  describe "format/1" do
    test "zero is midnight" do
      assert Clock.format(0) == "00:00:00"
    end

    test "pads every field to two digits" do
      assert Clock.format(1) == "00:00:01"
      assert Clock.format(61) == "00:01:01"
      assert Clock.format(3661) == "01:01:01"
    end

    test "carries seconds into minutes and minutes into hours" do
      assert Clock.format(59) == "00:00:59"
      assert Clock.format(60) == "00:01:00"
      assert Clock.format(3599) == "00:59:59"
      assert Clock.format(3600) == "01:00:00"
    end

    test "wraps after a day rather than showing a 25th hour" do
      assert Clock.format(86_399) == "23:59:59"
      assert Clock.format(86_400) == "00:00:00"
      assert Clock.format(90_061) == "01:01:01"
    end

    test "a negative reading reads as zero rather than crashing" do
      assert Clock.format(-5) == "00:00:00"
    end

    test "the width is fixed, so the title bar does not jitter" do
      for seconds <- [0, 9, 59, 600, 3600, 86_399] do
        assert byte_size(Clock.format(seconds)) == 8
      end
    end
  end
end
