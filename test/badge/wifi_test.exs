defmodule Badge.WifiTest do
  use ExUnit.Case, async: true

  alias Badge.Icons
  alias Badge.Wifi

  describe "icon/1" do
    test "only a live association shows a connected radio" do
      assert Wifi.icon(:connected) == :wifi
    end

    test "everything else shows disconnected" do
      assert Wifi.icon(:connecting) == :wifi_slash
      assert Wifi.icon(:disabled) == :wifi_slash
    end

    test "an unexpected state degrades to disconnected rather than crashing" do
      assert Wifi.icon(:nonesuch) == :wifi_slash
    end

    test "every icon it can return actually exists" do
      names = Icons.names()

      for radio <- [:connected, :connecting, :disabled, :nonesuch] do
        assert Wifi.icon(radio) in names
      end
    end
  end
end
