defmodule Badge.IdentityTest do
  use ExUnit.Case, async: true

  alias Badge.Identity

  describe "format/1" do
    test "writes six bytes as twelve hex digits" do
      assert Identity.format(<<0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6>>) == "A1B2C3D4E5F6"
    end

    test "pads a low byte rather than dropping its zero" do
      assert Identity.format(<<0, 1, 2, 3, 4, 5>>) == "000102030405"
    end

    test "always twelve characters, whatever the bytes" do
      for byte <- 0..255 do
        assert byte_size(Identity.format(<<byte, byte, byte, byte, byte, byte>>)) == 12
      end
    end

    test "anything that is not six bytes says so rather than crashing" do
      assert Identity.format(<<1, 2, 3>>) == "unknown"
      assert Identity.format("") == "unknown"
    end
  end

  describe "known?/1" do
    test "a real id is known" do
      assert Identity.known?(<<1, 2, 3, 4, 5, 6>>)
    end

    test "the unreadable placeholder is not" do
      refute Identity.known?(<<0, 0, 0, 0, 0, 0>>)
    end

    test "the wrong length is not" do
      refute Identity.known?(<<1, 2, 3>>)
      refute Identity.known?("")
    end
  end
end
