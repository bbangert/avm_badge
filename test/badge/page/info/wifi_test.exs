defmodule Badge.Page.Info.WifiTest do
  use ExUnit.Case, async: true

  alias Badge.Field
  alias Badge.Page.Info
  alias Badge.Page.Info.Wifi
  alias Badge.Theme

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

  defp listing(networks) do
    %{Wifi.init() | networks: networks}
  end

  defp press(state, event) do
    {:ok, next} = Wifi.handle_key(event, state)
    next
  end

  defp texts(state), do: for({:text, _x, _y, _f, _fg, _bg, body} <- Wifi.render(state), do: body)

  defp shows?(state, needle) do
    Enum.any?(texts(state), fn body -> :binary.match(body, needle) != :nomatch end)
  end

  describe "identity" do
    test "names itself for the tab strip" do
      assert Wifi.title() == "Wifi"
    end

    test "starts in list mode" do
      assert Wifi.init().mode == :list
    end
  end

  describe "escape" do
    test "is ignored in list mode, so the router still reaches home" do
      assert Wifi.handle_key({:nav, :home}, Wifi.init()) == :ignore
    end

    test "is consumed in passphrase mode and backs out to the list" do
      entered = press(listing([ap("HomeNet", -50)]), {:edit, :newline})
      assert entered.mode == :passphrase

      assert press(entered, {:nav, :home}).mode == :list
    end

    test "backing out discards what was typed" do
      entered = press(listing([ap("HomeNet", -50)]), {:edit, :newline})
      typed = press(entered, {:char, ?a})

      assert Field.length(press(typed, {:nav, :home}).field) == 0
    end
  end

  describe "arrows" do
    test "left and right are ignored in list mode, so the carousel still moves" do
      state = listing([ap("HomeNet", -50)])

      assert Wifi.handle_key({:move, :left}, state) == :ignore
      assert Wifi.handle_key({:move, :right}, state) == :ignore
    end

    test "left and right are consumed in passphrase mode, so typing stays put" do
      entered = press(listing([ap("HomeNet", -50)]), {:edit, :newline})

      assert {:ok, ^entered} = Wifi.handle_key({:move, :left}, entered)
      assert {:ok, ^entered} = Wifi.handle_key({:move, :right}, entered)
    end

    test "up and down are always consumed, so they never reach the carousel" do
      state = listing([ap("A", -50), ap("B", -60)])

      assert {:ok, _} = Wifi.handle_key({:move, :down}, state)
      assert {:ok, _} = Wifi.handle_key({:move, :up}, state)
    end
  end

  describe "cursor" do
    test "starts at the top" do
      assert listing([ap("A", -50), ap("B", -60)]).cursor == 0
    end

    test "moves down and back up" do
      state = listing([ap("A", -50), ap("B", -60)])

      assert press(state, {:move, :down}).cursor == 1
      assert press(press(state, {:move, :down}), {:move, :up}).cursor == 0
    end

    test "stops at the top rather than wrapping" do
      assert press(listing([ap("A", -50)]), {:move, :up}).cursor == 0
    end

    test "stops at the bottom rather than wrapping" do
      state = listing([ap("A", -50), ap("B", -60)])
      bottom = press(press(state, {:move, :down}), {:move, :down})

      assert bottom.cursor == 1
    end

    test "an empty list does not move" do
      assert press(listing([]), {:move, :down}).cursor == 0
    end
  end

  describe "choosing a network" do
    test "a secured network asks for a passphrase" do
      entered = press(listing([ap("HomeNet", -50)]), {:edit, :newline})

      assert entered.mode == :passphrase
      assert entered.chosen.ssid == "HomeNet"
    end

    test "an open network does not" do
      state = press(listing([ap("Cafe", -50, :open)]), {:edit, :newline})

      assert state.mode == :list
    end

    test "enter on an empty list does nothing" do
      assert press(listing([]), {:edit, :newline}).mode == :list
    end

    test "the highlighted network is the one chosen" do
      state = listing([ap("First", -50), ap("Second", -60)])
      entered = press(press(state, {:move, :down}), {:edit, :newline})

      assert entered.chosen.ssid == "Second"
    end
  end

  describe "passphrase entry" do
    setup do
      %{entered: press(listing([ap("HomeNet", -50)]), {:edit, :newline})}
    end

    test "characters accumulate", %{entered: entered} do
      typed = press(press(entered, {:char, ?a}), {:char, ?b})

      assert Field.value(typed.field) == "ab"
    end

    test "backspace removes one", %{entered: entered} do
      typed = press(press(entered, {:char, ?a}), {:edit, :backspace})

      assert Field.value(typed.field) == ""
    end

    test "the passphrase is masked on screen", %{entered: entered} do
      typed = press(press(entered, {:char, ?s}), {:char, ?x})

      assert shows?(typed, "**")
      refute shows?(typed, "sx")
    end

    test "the chosen network is named", %{entered: entered} do
      assert shows?(entered, "HomeNet")
    end
  end

  describe "render/1" do
    test "an empty list invites a scan" do
      assert shows?(listing([]), "scan")
    end

    test "lists every network it is given" do
      state = listing([ap("First", -50), ap("Second", -60)])

      assert shows?(state, "First")
      assert shows?(state, "Second")
    end

    test "marks the highlighted row" do
      state = listing([ap("First", -50), ap("Second", -60)])

      assert ">" in texts(state)
    end

    test "shows the radio state" do
      assert shows?(listing([]), "off")
    end

    test "says so when a join failed, rather than sitting on connecting" do
      state = %{
        listing([])
        | status: %{radio: :failed, ssid: "HomeNet", scanning: false, scan_id: 0}
      }

      assert shows?(state, "failed")
    end

    test "offers forgetting the saved network" do
      assert shows?(listing([]), "forget")
    end

    test "the joined network is coloured differently from the cursor" do
      networks = [ap("HomeNet", -50), ap("Other", -60)]

      joined = %{
        listing(networks)
        | cursor: 1,
          status: %{radio: :connected, ssid: "HomeNet", scanning: false, scan_id: 0}
      }

      colours =
        for {:text, 8, _y, _f, colour, _bg, body} <- Wifi.render(joined),
            :binary.match(body, "HomeNet") != :nomatch or :binary.match(body, "Other") != :nomatch,
            do: colour

      assert length(colours) == 2
      assert length(:lists.usort(colours)) == 2
    end

    test "no network is specially coloured while disconnected" do
      networks = [ap("HomeNet", -50), ap("Other", -60)]

      state = %{
        listing(networks)
        | status: %{radio: :connecting, ssid: "HomeNet", scanning: false, scan_id: 0}
      }

      colours =
        for {:text, 8, _y, _f, colour, _bg, body} <- Wifi.render(state),
            :binary.match(body, "Net") != :nomatch or :binary.match(body, "Other") != :nomatch,
            do: colour

      assert Theme.fg() in colours
    end

    test "draws below the tab strip and inside the panel" do
      state = listing([ap("First", -50), ap("Second", -60)])

      for {:text, _x, y, _f, _fg, _bg, _body} <- Wifi.render(state) do
        assert y >= Info.content_top()
        assert y < Theme.height()
      end
    end

    test "shows at most a screenful and scrolls to keep the cursor visible" do
      many = for n <- 1..20, do: ap("Net" <> :erlang.integer_to_binary(n), -40 - n)
      state = %{listing(many) | cursor: 19}

      assert shows?(state, "Net20")
      refute shows?(state, "Net1 ")
    end
  end
end
