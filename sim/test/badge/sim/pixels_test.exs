defmodule Badge.Sim.PixelsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Badge.LedEffect
  alias Badge.Pixels
  alias Badge.Sim.Leds

  setup do
    start_supervised!(Badge.Sim.Nvs)
    Leds.reset()
    :ok
  end

  defp start do
    capture_io(fn ->
      pid = start_supervised!({Pixels, Leds})
      :sys.get_state(pid)
    end)
  end

  test "starts the ring on the saved setting, corners in order" do
    Badge.Nvs.put(:led_mode, "chase pal=fire")
    start()

    assert {:effect, :chase, [0xFFB040 | _rest], _opts} = Leds.last(:effect)
    assert {:order, [_, _, _, _]} = Leds.last(:order)
  end

  test "a new setting is shown at once and saved once it settles" do
    start()
    setting = %{LedEffect.default() | effect: :candle}
    Pixels.set(setting)

    assert Pixels.setting() == setting
    assert {:effect, :candle, _colours, _opts} = Leds.last(:effect)

    Process.sleep(1700)
    assert Badge.Nvs.get(:led_mode) == LedEffect.encode(setting)
  end

  test "sleep darkens the ring and wake brings the setting back" do
    start()
    Pixels.sleep()
    Pixels.setting()
    assert Leds.last(:effect) == {:effect, :off, [], []}

    Pixels.wake()
    Pixels.setting()
    assert {:effect, :rainbow, _colours, _opts} = Leds.last(:effect)
  end

  test "a flash is passed on, but not while asleep" do
    start()
    Pixels.flash(120)
    Pixels.setting()
    assert {:flash, 0x00FF00, _ms} = Leds.last(:flash)

    Leds.reset()
    Pixels.sleep()
    Pixels.flash(0)
    Pixels.setting()
    assert Leds.last(:flash) == nil
  end
end
