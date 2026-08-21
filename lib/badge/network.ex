defmodule Badge.Network do
  @moduledoc """
  Turns raw scan results into a list worth showing.

  A scan reports one entry per BSSID, so a network on several channels
  appears more than once, and hidden networks appear with an empty SSID.
  Pure: `Badge.Wifi` does the scanning.
  """

  # Fits the label columns on a 320px panel at 8px per character.
  @ssid_width 16

  @doc "Strongest reading per SSID, strongest first, hidden networks dropped."
  @spec usable([map]) :: [map]
  def usable(found) do
    named = :lists.filter(fn network -> network.ssid != "" end, found)

    # Sorted before deduplicating, so the first entry for an SSID is its strongest.
    sorted = :lists.sort(fn a, b -> a.rssi >= b.rssi end, named)

    dedup(sorted, [], [])
  end

  @doc "Whether joining this network needs a passphrase."
  @spec secured?(map) :: boolean
  def secured?(%{authmode: :open}), do: false
  def secured?(_network), do: true

  @doc "One fixed-width row: name, signal and security."
  @spec label(map) :: binary
  def label(network) do
    pad(network.ssid) <> "  " <> signal(network.rssi) <> "  " <> security(network)
  end

  defp dedup([], _seen, acc), do: :lists.reverse(acc)

  defp dedup([network | rest], seen, acc) do
    case :lists.member(network.ssid, seen) do
      true -> dedup(rest, seen, acc)
      false -> dedup(rest, [network.ssid | seen], [network | acc])
    end
  end

  defp pad(ssid) when byte_size(ssid) >= @ssid_width do
    :binary.part(ssid, 0, @ssid_width)
  end

  defp pad(ssid), do: ssid <> spaces(@ssid_width - byte_size(ssid))

  defp spaces(count), do: :erlang.list_to_binary(:lists.duplicate(count, ?\s))

  # Right-aligned in four columns so the security column never shifts.
  defp signal(rssi) do
    text = :erlang.integer_to_binary(rssi)

    spaces(4 - byte_size(text)) <> text
  end

  defp security(%{authmode: :open}), do: "open"
  defp security(_network), do: "lock"
end
