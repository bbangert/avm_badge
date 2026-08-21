defmodule Badge.Network do
  @moduledoc """
  Turns raw scan results into a list worth showing.

  A scan reports one entry per BSSID, so a network on several channels
  appears more than once, and hidden networks appear with an empty SSID.
  Pure: `Badge.Wifi` does the scanning.
  """

  # Fits beside the signal and security columns on a 320px panel.
  @ssid_width 24

  @doc "Strongest reading per SSID, strongest first, hidden networks dropped."
  @spec usable([map]) :: [map]
  def usable(found) do
    named = :lists.filter(fn network -> network.ssid != "" end, found)

    # Sorted before deduplicating, so the first entry for an SSID is its strongest.
    sorted = :lists.sort(fn a, b -> a.rssi >= b.rssi end, named)

    dedup(sorted, [], [])
  end

  # Neither of these asks for a passphrase: OWE encrypts without one.
  @unsecured [:open, :owe]

  # These need a username and certificate, which the badge cannot collect.
  @enterprise [
    :eap,
    :wpa_enterprise,
    :wpa3_enterprise,
    :wpa2_wpa3_enterprise,
    :wpa3_enterprise_192
  ]

  @doc "Whether joining this network needs a passphrase."
  @spec secured?(map) :: boolean
  def secured?(%{authmode: authmode}), do: not :lists.member(authmode, @unsecured)

  @doc "Whether a passphrase is enough to join at all."
  @spec joinable?(map) :: boolean
  def joinable?(%{authmode: authmode}), do: not :lists.member(authmode, @enterprise)

  @doc "Short name for the network's security, at most four characters."
  @spec security(map) :: binary
  def security(%{authmode: authmode}), do: security_name(authmode)

  @doc "Signal strength as text, until the strength icons land."
  @spec signal(map) :: binary
  def signal(%{rssi: rssi}), do: :erlang.integer_to_binary(rssi)

  @doc "Signal strength bucketed into four levels, strongest first."
  @spec level(map) :: 0..3
  def level(%{rssi: rssi}) when rssi >= -55, do: 3
  def level(%{rssi: rssi}) when rssi >= -67, do: 2
  def level(%{rssi: rssi}) when rssi >= -78, do: 1
  def level(_network), do: 0

  @doc "The network name, truncated to fit its column."
  @spec name(map) :: binary
  def name(%{ssid: ssid}) when byte_size(ssid) > @ssid_width do
    :binary.part(ssid, 0, @ssid_width)
  end

  def name(%{ssid: ssid}), do: ssid

  defp dedup([], _seen, acc), do: :lists.reverse(acc)

  defp dedup([network | rest], seen, acc) do
    case :lists.member(network.ssid, seen) do
      true -> dedup(rest, seen, acc)
      false -> dedup(rest, [network.ssid | seen], [network | acc])
    end
  end

  defp security_name(:open), do: "open"
  defp security_name(:owe), do: "open"
  defp security_name(:wep), do: "WEP"
  defp security_name(:wpa_psk), do: "WPA"
  defp security_name(:wpa2_psk), do: "WPA2"
  defp security_name(:wpa_wpa2_psk), do: "WPA2"
  defp security_name(:wpa3_psk), do: "WPA3"
  defp security_name(:wpa2_wpa3_psk), do: "WPA3"
  defp security_name(:wpa3_ext_psk), do: "WPA3"
  defp security_name(:wpa3_ext_psk_mixed), do: "WPA3"
  defp security_name(:wapi), do: "WAPI"
  defp security_name(:dpp), do: "DPP"
  defp security_name(authmode), do: enterprise_or_unknown(authmode)

  defp enterprise_or_unknown(authmode) do
    case :lists.member(authmode, @enterprise) do
      true -> "ENT"
      false -> "?"
    end
  end
end
