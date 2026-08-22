defmodule Badge.IrTest do
  use ExUnit.Case, async: true

  alias Badge.Ir

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
