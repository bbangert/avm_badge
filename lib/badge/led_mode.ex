defmodule Badge.LedMode do
  @moduledoc """
  What the LED chain can show, and how it is stored.

  The list lives here rather than in `Badge.Page.Led` so the modes and their
  names cannot drift apart, and so `Badge.Pixels` can read back what was
  saved without the page being involved.

  Stored as readable text rather than a term blob: a setting that can be
  eyeballed in NVS is worth more than a few saved bytes.
  """

  @modes [:rainbow, :solid, :white, :off]
  @names [{:rainbow, "rainbow"}, {:solid, "solid"}, {:white, "white"}, {:off, "off"}]

  @default :rainbow
  @degrees 360

  @doc "Every mode, in the order the page pages through them."
  @spec modes() :: [atom]
  def modes, do: @modes

  @doc "What a mode is called, on the panel and in NVS."
  @spec name(atom | {atom, integer}) :: binary
  def name({:solid, _hue}), do: name(:solid)
  def name(mode), do: labelled(@names, mode)

  @doc "A mode as it is written to NVS."
  @spec encode(atom | {atom, integer}) :: binary
  def encode({:solid, hue}), do: name(:solid) <> ":" <> :erlang.integer_to_binary(hue)
  def encode(mode), do: name(mode)

  @doc """
  A mode read back from NVS.

  Anything absent, corrupt or out of range reads as the default: a bad byte
  in flash should leave the chain dull, not stop it starting.
  """
  @spec decode(binary | nil) :: atom | {atom, integer}
  def decode(nil), do: @default
  def decode("rainbow"), do: :rainbow
  def decode("white"), do: :white
  def decode("off"), do: :off
  def decode(<<"solid:", hue::binary>>), do: solid(digits(hue, 0, false))
  def decode(_stored), do: @default

  defp solid(hue) when is_integer(hue) and hue >= 0 and hue < @degrees, do: {:solid, hue}
  defp solid(_hue), do: @default

  defp labelled([], _mode), do: labelled(@names, @default)
  defp labelled([{mode, label} | _rest], mode), do: label
  defp labelled([_entry | rest], mode), do: labelled(rest, mode)

  # Anything that is not all digits is a corrupt value, not a small number.
  defp digits(<<>>, _acc, false), do: :error
  defp digits(<<>>, acc, true), do: acc

  defp digits(<<digit, rest::binary>>, acc, _any) when digit >= ?0 and digit <= ?9 do
    digits(rest, acc * 10 + (digit - ?0), true)
  end

  defp digits(_binary, _acc, _any), do: :error
end
