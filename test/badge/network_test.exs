defmodule Badge.NetworkTest do
  use ExUnit.Case, async: true

  alias Badge.Network

  defp ap(ssid, rssi, authmode \\ :wpa2_psk) do
    %{
      ssid: ssid,
      rssi: rssi,
      authmode: authmode,
      bssid: <<0, 0, 0, 0, 0, 0>>,
      channel: 1,
      hidden: false
    }
  end

  defp ssids(found), do: for(network <- Network.usable(found), do: network.ssid)

  describe "usable/1" do
    test "an empty scan gives nothing" do
      assert Network.usable([]) == []
    end

    test "keeps a single network" do
      assert ssids([ap("HomeNet", -50)]) == ["HomeNet"]
    end

    test "sorts strongest first" do
      found = [ap("Weak", -80), ap("Strong", -40), ap("Middle", -60)]

      assert ssids(found) == ["Strong", "Middle", "Weak"]
    end

    test "collapses one network seen on several channels" do
      found = [ap("HomeNet", -70), ap("HomeNet", -45), ap("Other", -60)]

      assert ssids(found) == ["HomeNet", "Other"]
    end

    test "keeps the strongest reading of a duplicated network" do
      [home | _rest] = Network.usable([ap("HomeNet", -70), ap("HomeNet", -45)])

      assert home.rssi == -45
    end

    test "drops entries with no ssid, which cannot be joined by name" do
      assert ssids([ap("", -40), ap("Real", -60)]) == ["Real"]
    end

    test "keeps open networks and preserves the auth mode" do
      [open | _rest] = Network.usable([ap("Cafe", -40, :open)])

      assert open.authmode == :open
    end

    test "a scan of only hidden networks gives nothing" do
      assert Network.usable([ap("", -40), ap("", -50)]) == []
    end
  end

  describe "secured?/1" do
    test "open networks need no passphrase" do
      refute Network.secured?(ap("Cafe", -40, :open))
    end

    test "anything else does" do
      assert Network.secured?(ap("Home", -40, :wpa2_psk))
      assert Network.secured?(ap("Work", -40, :wpa_wpa2_psk))
    end
  end

  describe "label/1" do
    test "shows the ssid, signal and security" do
      label = Network.label(ap("HomeNet", -52))

      assert :binary.match(label, "HomeNet") != :nomatch
      assert :binary.match(label, "-52") != :nomatch
    end

    test "truncates a long ssid so the columns line up" do
      label = Network.label(ap("AVeryLongNetworkNameIndeed", -52))

      assert :binary.match(label, "AVeryLongNetworkNameIndeed") == :nomatch
      assert byte_size(label) == byte_size(Network.label(ap("Short", -52)))
    end

    test "open networks say so" do
      assert :binary.match(Network.label(ap("Cafe", -40, :open)), "open") != :nomatch
    end
  end
end
