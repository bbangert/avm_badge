defmodule Badge.Ir.FrameTest do
  use ExUnit.Case, async: true

  alias Badge.Ir.Frame

  @id <<0x90, 0xDA, 0x72, 0x47, 0xF8, 0x04>>
  @other <<0x90, 0xDA, 0x72, 0x47, 0xF8, 0x28>>

  defp frame(id \\ @id, payload \\ "Gus"), do: Frame.encode(id, payload)

  describe "a frame on its own" do
    test "round trips the sender and the payload" do
      assert {:ok, %{from: @id, payload: "Gus"}, <<>>} = Frame.decode(frame())
    end

    test "the payload is bytes, not text" do
      payload = <<0, 1, 2, 255, 0x55, 0xAA>>

      assert {:ok, %{payload: ^payload}, <<>>} = Frame.decode(frame(@id, payload))
    end

    test "carries a payload at the published limit" do
      payload = :binary.copy(<<0x41>>, Frame.max_payload())

      assert {:ok, %{payload: ^payload}, <<>>} = Frame.decode(frame(@id, payload))
    end

    test "an empty payload is a legal frame" do
      assert {:ok, %{from: @id, payload: <<>>}, <<>>} = Frame.decode(frame(@id, <<>>))
    end

    test "the largest frame stays inside the airtime budget" do
      assert byte_size(frame(@id, :binary.copy(<<0>>, Frame.max_payload()))) <= 68
    end

    test "starts with the preamble so a receiver can find it" do
      assert <<0x55, 0xAA, _rest::binary>> = frame()
    end
  end

  describe "a payload that will not fit" do
    test "is refused rather than truncated onto the wire" do
      too_big = :binary.copy(<<0x41>>, Frame.max_payload() + 1)

      assert Frame.encode(@id, too_big) == {:error, :too_long}
    end
  end

  describe "a corrupted frame" do
    test "a flipped payload bit is caught by the crc" do
      <<head::binary-4, byte, tail::binary>> = frame()
      corrupt = head <> <<Bitwise.bxor(byte, 0x01)>> <> tail

      assert {:bad, :crc, _rest} = Frame.decode(corrupt)
    end

    test "a flipped crc bit is caught too" do
      size = byte_size(frame())
      <<head::binary-size(size - 1), crc>> = frame()

      assert {:bad, :crc, _rest} = Frame.decode(head <> <<Bitwise.bxor(crc, 0x80)>>)
    end

    test "a nonsense length is reported, and the frame behind it still arrives" do
      assert {:bad, :length, rest} = Frame.decode(<<0x55, 0xAA, 0xFF>> <> frame())
      assert {:ok, %{from: @id}, <<>>} = Frame.decode(rest)
    end
  end

  describe "a stream rather than a frame" do
    test "leading noise is skipped" do
      assert {:ok, %{from: @id}, <<>>} = Frame.decode(<<0x00, 0x13, 0x99>> <> frame())
    end

    test "another badge's boot log does not decode as a frame" do
      assert {:more, _rest} = Frame.decode("I (8317) wifi:pm start, type: 1\n")
    end

    test "two frames back to back both come out" do
      {:ok, first, rest} = Frame.decode(frame() <> frame(@other, "Pat"))

      assert first.from == @id
      assert {:ok, %{from: @other, payload: "Pat"}, <<>>} = Frame.decode(rest)
    end

    test "a half-arrived frame is kept, not discarded" do
      whole = frame()
      <<head::binary-5, _tail::binary>> = whole

      assert {:more, kept} = Frame.decode(head)

      assert {:ok, %{from: @id}, <<>>} =
               Frame.decode(kept <> :binary.part(whole, 5, byte_size(whole) - 5))
    end

    test "a truncated frame keeps its preamble so the rest can join it" do
      assert {:more, <<0x55, 0xAA>>} = Frame.decode(<<0x00, 0x55, 0xAA>>)
    end

    test "the parser always makes progress on garbage" do
      assert {:more, <<>>} = Frame.decode(:binary.copy(<<0x00>>, 64))
    end
  end
end
