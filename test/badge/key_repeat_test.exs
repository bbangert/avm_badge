defmodule Badge.KeyRepeatTest do
  use ExUnit.Case, async: true

  alias Badge.KeyRepeat

  @delay 500
  @interval 33

  describe "fresh state" do
    test "is idle" do
      assert {:idle, _state} = KeyRepeat.due(KeyRepeat.new(), 0, @interval)
    end
  end

  describe "due/3 before the delay elapses" do
    test "does not fire" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)

      # Delay is 500 ms = 500_000 us, due at 1_500_000. One us short.
      assert {:idle, _state} = KeyRepeat.due(state, 1_499_999, @interval)
    end
  end

  describe "due/3 past the delay" do
    test "fires with the captured event" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)

      assert {:fire, {:char, ?a}, _state} = KeyRepeat.due(state, 1_500_000, @interval)
    end
  end

  describe "after firing" do
    test "the next fire waits interval, not delay" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)
      {:fire, _event, state} = KeyRepeat.due(state, 1_500_000, @interval)

      # interval is 33 ms = 33_000 us, so next due is 1_533_000.
      assert {:idle, _state} = KeyRepeat.due(state, 1_532_999, @interval)
      assert {:fire, {:char, ?a}, _state} = KeyRepeat.due(state, 1_533_000, @interval)
    end
  end

  describe "several consecutive fires" do
    test "are spaced by interval" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)

      {:fire, _event, state} = KeyRepeat.due(state, 1_500_000, @interval)
      {:fire, _event, state} = KeyRepeat.due(state, 1_533_000, @interval)
      {:fire, _event, state} = KeyRepeat.due(state, 1_566_000, @interval)
      assert {:idle, _state} = KeyRepeat.due(state, 1_598_999, @interval)
      assert {:fire, _event, _state} = KeyRepeat.due(state, 1_599_000, @interval)
    end
  end

  describe "due/3 called late" do
    test "re-arms from the actual fire time, not the previously scheduled due time" do
      # Armed at t=0 with a 500 ms delay, so due at 500_000. The caller does
      # not check in until 700_000 -- 200 ms late, as happens routinely with
      # a ~9.8 ms scan against a 33 ms interval.
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 0, @delay)
      {:fire, _event, state} = KeyRepeat.due(state, 700_000, @interval)

      # A due_us-based re-arm (500_000 + 33_000) would be due at 533_000 and
      # would already have fired by 700_000. The correct, now_us-based re-arm
      # is due at 700_000 + 33_000 = 733_000.
      assert {:idle, _state} = KeyRepeat.due(state, 732_999, @interval)
      assert {:fire, {:char, ?a}, _state} = KeyRepeat.due(state, 733_000, @interval)
    end

    test "fires exactly once even when several intervals have elapsed, with no catch-up" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 0, @delay)

      # Due at 500_000; checked in at 800_000, nine intervals (33_000 each)
      # late. Only one fire is produced, not nine.
      assert {:fire, {:char, ?a}, state} = KeyRepeat.due(state, 800_000, @interval)

      # The next fire is not due until interval after this call, i.e.
      # 800_000 + 33_000 = 833_000 -- not immediately, and not rebased on
      # the original due time.
      assert {:idle, _state} = KeyRepeat.due(state, 832_999, @interval)
      assert {:fire, {:char, ?a}, _state} = KeyRepeat.due(state, 833_000, @interval)
    end
  end

  describe "release/2" do
    test "with the label absent disarms; a subsequent due/2 does not fire" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)
      state = KeyRepeat.release(state, [])

      assert {:idle, _state} = KeyRepeat.due(state, 1_500_000, @interval)
    end

    test "with the label still present leaves it armed" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)
      state = KeyRepeat.release(state, [~c"A"])

      assert {:fire, {:char, ?a}, _state} = KeyRepeat.due(state, 1_500_000, @interval)
    end

    test "on a disarmed state is a no-op" do
      state = KeyRepeat.release(KeyRepeat.new(), [~c"A"])

      assert {:idle, _state} = KeyRepeat.due(state, 1_500_000, @interval)
    end
  end

  describe "arm/5" do
    test "arming a second label replaces the first" do
      state = KeyRepeat.arm(KeyRepeat.new(), ~c"A", {:char, ?a}, 1_000_000, @delay)
      state = KeyRepeat.arm(state, ~c"B", {:char, ?b}, 1_000_100, @delay)

      # Only "B" is held; if "A" were still armed this would disarm.
      state = KeyRepeat.release(state, [~c"B"])

      assert {:fire, {:char, ?b}, _state} = KeyRepeat.due(state, 1_500_100, @interval)
    end
  end
end
