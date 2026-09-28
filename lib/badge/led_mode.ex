defmodule Badge.LedMode do
  @moduledoc """
  What the LED chain can show, and how it is stored.

  The list lives here rather than in `Badge.Page.Led` so the modes and their
  names cannot drift apart, and so `Badge.Pixels` can read back what was
  saved without the page being involved.

  Stored as readable text rather than a term blob: a setting that can be
  eyeballed in NVS is worth more than a few saved bytes.
  """

  @modes [:rainbow, :dusk, :solid, :white, :off]
  @names [
    {:rainbow, "rainbow"},
    {:dusk, "dusk"},
    {:solid, "solid"},
    {:white, "white"},
    {:off, "off"}
  ]

  @default :rainbow
  @degrees 360

  # Neon Dusk's horizon: magenta, violet, cyan, a third of the loop apart.
  @dusk {{0xE8, 0x5F, 0xAF}, {0x8A, 0x63, 0xE8}, {0x5C, 0xC8, 0xF5}}
  @dusk_span div(@degrees, 3)

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
  def decode("dusk"), do: :dusk
  def decode("white"), do: :white
  def decode("off"), do: :off
  def decode(<<"solid:", hue::binary>>), do: solid(digits(hue, 0, false))
  def decode(_stored), do: @default

  @doc """
  The dusk mode's colour at `position` around its 0..359 loop, as an
  `{r, g, b}` triple scaled so the brightest channel of a stop is at most `v`.
  """
  @spec dusk(non_neg_integer, 0..255) :: {byte, byte, byte}
  def dusk(position, v) do
    step = rem(position, @degrees)
    stop = div(step, @dusk_span)
    from = elem(@dusk, stop)
    to = elem(@dusk, rem(stop + 1, 3))

    scale(blend(from, to, rem(step, @dusk_span), @dusk_span), v)
  end

  defp blend({r1, g1, b1}, {r2, g2, b2}, num, den) do
    {r1 + div((r2 - r1) * num, den), g1 + div((g2 - g1) * num, den),
     b1 + div((b2 - b1) * num, den)}
  end

  defp scale({r, g, b}, v), do: {div(r * v, 255), div(g * v, 255), div(b * v, 255)}

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
