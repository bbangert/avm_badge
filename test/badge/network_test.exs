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

    test "OWE encrypts without a passphrase, so it must not prompt for one" do
      refute Network.secured?(ap("Cafe", -40, :owe))
    end

    test "anything else does" do
      assert Network.secured?(ap("Home", -40, :wpa2_psk))
      assert Network.secured?(ap("Work", -40, :wpa_wpa2_psk))
    end
  end

  describe "name/1" do
    test "short names come through whole" do
      assert Network.name(ap("HomeNet", -52)) == "HomeNet"
    end

    test "a long name is truncated so the columns line up" do
      name = Network.name(ap("AVeryLongNetworkNameIndeedYesReally", -52))

      assert byte_size(name) < byte_size("AVeryLongNetworkNameIndeedYesReally")
      assert :binary.match("AVeryLongNetworkNameIndeedYesReally", name) != :nomatch
    end
  end

  describe "security/1" do
    test "names the actual security rather than a generic word" do
      assert Network.security(ap("N", -50, :wpa2_psk)) == "WPA2"
      assert Network.security(ap("N", -50, :wpa3_psk)) == "WPA3"
      assert Network.security(ap("N", -50, :wpa_psk)) == "WPA"
      assert Network.security(ap("N", -50, :wep)) == "WEP"
      assert Network.security(ap("N", -50, :open)) == "open"
    end

    test "mixed modes report the stronger one" do
      assert Network.security(ap("N", -50, :wpa_wpa2_psk)) == "WPA2"
      assert Network.security(ap("N", -50, :wpa2_wpa3_psk)) == "WPA3"
    end

    test "enterprise is called out, since a passphrase will not do" do
      assert Network.security(ap("N", -50, :eap)) == "ENT"
      assert Network.security(ap("N", -50, :wpa3_enterprise)) == "ENT"
    end

    test "an unknown mode does not crash" do
      assert Network.security(ap("N", -50, :something_new)) == "?"
    end

    test "every mode AtomVM can report fits the column" do
      modes = [
        :open,
        :wep,
        :wpa_psk,
        :wpa2_psk,
        :wpa_wpa2_psk,
        :eap,
        :wpa3_psk,
        :wpa2_wpa3_psk,
        :wapi,
        :owe,
        :wpa3_enterprise_192,
        :wpa3_ext_psk,
        :wpa3_ext_psk_mixed,
        :dpp,
        :wpa_enterprise,
        :wpa3_enterprise,
        :wpa2_wpa3_enterprise
      ]

      for mode <- modes do
        assert byte_size(Network.security(ap("N", -50, mode))) <= 4
      end
    end
  end

  describe "joinable?/1" do
    test "ordinary networks are joinable with a passphrase" do
      assert Network.joinable?(ap("N", -50, :wpa2_psk))
      assert Network.joinable?(ap("N", -50, :open))
    end

    test "enterprise networks are not" do
      refute Network.joinable?(ap("N", -50, :eap))
      refute Network.joinable?(ap("N", -50, :wpa2_wpa3_enterprise))
    end
  end

  describe "level/1" do
    test "buckets signal strength, strongest first" do
      assert Network.level(ap("N", -40)) == 3
      assert Network.level(ap("N", -60)) == 2
      assert Network.level(ap("N", -70)) == 1
      assert Network.level(ap("N", -90)) == 0
    end

    test "never falls outside the four levels" do
      for rssi <- -100..0 do
        assert Network.level(ap("N", rssi)) in [0, 1, 2, 3]
      end
    end
  end
end
