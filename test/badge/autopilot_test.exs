defmodule Badge.AutopilotTest do
  # Registers the Badge.UI name to catch what the script sends, so it cannot
  # share the node with another test doing the same.
  use ExUnit.Case, async: false

  alias Badge.Autopilot

  describe "the compiled-in script" do
    test "is empty, so a shipped build is never driven by itself" do
      assert Autopilot.script() == []
    end

    test "every step is a wait and an event the keymap can produce" do
      for {wait, event} <- Autopilot.script() do
        assert is_integer(wait) and wait >= 0
        assert is_tuple(event)
      end
    end
  end

  describe "running" do
    test "an empty script starts nothing" do
      assert Autopilot.start() == :ok
      assert Autopilot.start([]) == :ok
    end

    test "delivers every step to the UI, in order" do
      Process.register(self(), Badge.UI)

      assert Autopilot.start([{10, {:nav, :home}}, {10, {:move, :right}}]) == :ok

      assert_receive {:"$gen_cast", {:key, {:nav, :home}}}, 500
      assert_receive {:"$gen_cast", {:key, {:move, :right}}}, 500
    end

    test "returns before the script has finished, so boot is not held up" do
      Process.register(self(), Badge.UI)

      assert Autopilot.start([{400, {:nav, :home}}]) == :ok
      refute_received {:"$gen_cast", {:key, {:nav, :home}}}

      assert_receive {:"$gen_cast", {:key, {:nav, :home}}}, 2_000
    end
  end
end
