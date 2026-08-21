defmodule Badge.Ir.Frame do
  @moduledoc """
  Wire format for the IR link, and the stream parser that recovers it.

  A frame is a two-byte preamble, a length, the sender's chip id, the
  payload, and a CRC-8:

      55 AA <len> <6 byte chip id> <payload...> <crc>

  The payload is opaque; the link does not know what is in it.

  Framing is not decoration here. The same beam carries another badge's boot
  log at 115200 baud, and a tap can start or end mid-byte, so the parser has
  to resynchronise on garbage rather than trust what it is handed. `decode/1`
  therefore takes whatever has arrived so far and returns what it could not
  use yet, so a caller can feed it a growing buffer.
  """

  import Bitwise

  @preamble_a 0x55
  @preamble_b 0xAA

  @id_bytes 6
  @max_payload 58
  @max_len @id_bytes + @max_payload

  @doc "The largest payload a frame carries."
  @spec max_payload() :: pos_integer
  def max_payload, do: @max_payload

  @doc "A frame carrying a payload from this badge, or `{:error, :too_long}`."
  @spec encode(binary, binary) :: binary | {:error, :too_long}
  def encode(_from, payload) when byte_size(payload) > @max_payload do
    {:error, :too_long}
  end

  def encode(from, payload) do
    body = <<@id_bytes + byte_size(payload)>> <> from <> payload

    <<@preamble_a, @preamble_b>> <> body <> <<crc(body)>>
  end

  @doc """
  Takes the next frame out of a buffer.

  Returns `{:ok, frame, rest}`, `{:bad, reason, rest}` for a frame that
  arrived corrupted, or `{:more, rest}` when the buffer holds no complete
  frame and should be kept for the next read.
  """
  @spec decode(binary) ::
          {:ok, %{from: binary, payload: binary}, binary}
          | {:bad, atom, binary}
          | {:more, binary}
  def decode(<<@preamble_a, @preamble_b, len, rest::binary>> = buffer)
      when len >= @id_bytes and len <= @max_len do
    case rest do
      <<payload::binary-size(len), crc, tail::binary>> ->
        verify(<<len>> <> payload, payload, crc, tail)

      _short ->
        {:more, buffer}
    end
  end

  # A length no frame of ours could have means the preamble was noise.
  def decode(<<@preamble_a, @preamble_b, _len, _rest::binary>> = buffer) do
    <<_skip, tail::binary>> = buffer

    {:bad, :length, tail}
  end

  def decode(<<@preamble_a, @preamble_b>> = buffer), do: {:more, buffer}
  def decode(<<@preamble_a>> = buffer), do: {:more, buffer}
  def decode(<<>>), do: {:more, <<>>}

  # Anything else is mid-stream noise; drop a byte and look again.
  def decode(<<_skip, tail::binary>>), do: decode(tail)

  @doc "CRC-8, polynomial 0x07, as used over the length and payload."
  @spec crc(binary) :: byte
  def crc(data), do: crc(data, 0)

  defp crc(<<>>, acc), do: acc
  defp crc(<<byte, rest::binary>>, acc), do: crc(rest, shift(bxor(acc, byte), 8))

  defp shift(acc, 0), do: acc

  defp shift(acc, n) do
    shifted =
      case band(acc, 0x80) do
        0 -> bsl(acc, 1)
        _set -> bxor(bsl(acc, 1), 0x07)
      end

    shift(band(shifted, 0xFF), n - 1)
  end

  defp verify(body, payload, crc, tail) do
    case crc(body) do
      ^crc -> {:ok, split(payload), tail}
      _other -> {:bad, :crc, tail}
    end
  end

  defp split(<<from::binary-size(@id_bytes), payload::binary>>) do
    %{from: from, payload: payload}
  end
end
