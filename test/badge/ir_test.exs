defmodule Badge.IrTest do
  use ExUnit.Case, async: true

  alias Badge.Ir
  alias Badge.Ir.Frame
  alias Badge.Ir.Link

  # Frame bytes on the wire, at 8N1, in milliseconds.
  defp airtime_ms(frame), do: div(byte_size(frame) * 10 * 1000, Link.baud())

  describe "the airtime budget" do
    test "runs at the baud the optics actually support" do
      assert Link.baud() == 2400
    end

    test "a full-width name leaves the beam quiet most of each cycle" do
      frame = Frame.encode(<<1, 2, 3, 4, 5, 6>>, "Wolfgang Amadeus M")

      # The UI base tick is 100 ms, so this is the gap between transmissions.
      cadence_ms = Badge.Page.Name.beam_ticks() * 100

      assert airtime_ms(frame) * 2 < cadence_ms
    end
  end

  describe "the payload budget" do
    test "publishes what a frame will carry" do
      assert Ir.max_payload() == 58
    end

    test "a payload at the limit is accepted" do
      assert Ir.send(:binary.copy(<<0x41>>, Ir.max_payload())) == :ok
    end

    test "one byte over is refused rather than truncated" do
      assert Ir.send(:binary.copy(<<0x41>>, Ir.max_payload() + 1)) == {:error, :too_long}
    end

    test "an empty payload is legal" do
      assert Ir.send(<<>>) == :ok
    end
  end
end
