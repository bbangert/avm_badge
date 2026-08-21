defmodule Badge.Identity do
  @moduledoc """
  This badge's own chip identifier.

  The factory-programmed MAC in efuse is unique per chip and survives a
  reflash, so it is what other badges key this one by.
  """

  @compile {:no_warn_undefined, :esp}

  @unknown <<0, 0, 0, 0, 0, 0>>

  @doc "The six-byte chip id, or six zeroes if it cannot be read."
  @spec chip_id() :: binary
  def chip_id do
    case :esp.get_default_mac() do
      {:ok, mac} -> mac
      _other -> @unknown
    end
  end

  @doc "A chip id written out as hex, for showing on screen."
  @spec format(binary) :: binary
  def format(<<a, b, c, d, e, f>>) do
    hex(a) <> hex(b) <> hex(c) <> hex(d) <> hex(e) <> hex(f)
  end

  def format(_other), do: "unknown"

  @doc "Whether an id is a real one rather than the unreadable placeholder."
  @spec known?(binary) :: boolean
  def known?(@unknown), do: false
  def known?(<<_::binary-6>>), do: true
  def known?(_other), do: false

  defp hex(byte), do: <<digit(div(byte, 16)), digit(rem(byte, 16))>>

  defp digit(value) when value < 10, do: ?0 + value
  defp digit(value), do: ?A + value - 10
end
