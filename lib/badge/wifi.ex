defmodule Badge.Wifi do
  @moduledoc """
  Owns the wifi radio and the SNTP clock sync.

  Credentials come from NVS, provisioned by `tools/provision_wifi.py`. With
  none present the radio never starts and the rest of the badge is
  unaffected.

  AtomVM stops reconnecting on its own once a `disconnected` callback is
  supplied, so retrying with backoff is done here.
  """

  use GenServer

  alias Badge.Clock
  alias Badge.Network
  alias Badge.Nvs

  @compile {:no_warn_undefined, :network}

  @sntp_host "pool.ntp.org"

  @first_backoff 1_000
  @max_backoff 30_000

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Radio state, whether the clock has synced, and the provisioned UTC offset."
  @spec status() :: %{radio: atom, synced: boolean, offset: integer}
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Starts a scan for nearby networks; results arrive asynchronously."
  @spec scan() :: :ok
  def scan do
    GenServer.cast(__MODULE__, :scan)
  end

  @doc "Joins a network, saving the credentials only once it works."
  @spec connect(binary, binary) :: :ok
  def connect(ssid, psk) do
    GenServer.cast(__MODULE__, {:connect, ssid, psk})
  end

  @doc "Networks seen by the last completed scan, strongest first."
  @spec networks() :: [map]
  def networks do
    GenServer.call(__MODULE__, :networks)
  end

  @doc "Title bar icon for a radio state."
  @spec icon(atom) :: atom
  def icon(:connected), do: :wifi
  def icon(_radio), do: :wifi_slash

  @impl true
  def init(:ok) do
    state = %{
      radio: :disabled,
      synced: false,
      offset: Clock.offset_minutes(Nvs.get(:utc_offset_m)),
      backoff: @first_backoff,
      started: false,
      scanning: false,
      networks: [],
      scan_id: 0,
      pending: nil
    }

    {:ok, state, {:continue, :start_radio}}
  end

  # Starts the radio after init/1 returns, not during it.
  @impl true
  def handle_continue(:start_radio, state) do
    case credentials() do
      nil ->
        :io.format(~c"Wifi: no credentials in NVS, radio stays off~n")

        {:noreply, state}

      {ssid, _psk} ->
        :io.format(~c"Wifi: connecting to ~s~n", [ssid])
        started = ensure_started(state)
        :network.sta_connect()

        {:noreply, %{started | radio: :connecting}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      radio: state.radio,
      synced: state.synced,
      offset: state.offset,
      scanning: state.scanning,
      scan_id: state.scan_id
    }

    {:reply, status, state}
  end

  def handle_call(:networks, _from, state) do
    {:reply, state.networks, state}
  end

  @impl true
  def handle_cast(:scan, %{scanning: true} = state), do: {:noreply, state}

  def handle_cast(:scan, state) do
    started = ensure_started(state)

    case :network.wifi_scan() do
      :ok ->
        {:noreply, %{started | scanning: true}}

      {:error, reason} ->
        :io.format(~c"Wifi: scan refused, ~p~n", [reason])

        {:noreply, started}
    end
  end

  def handle_cast({:connect, ssid, psk}, state) do
    :io.format(~c"Wifi: joining ~s~n", [ssid])
    started = ensure_started(state)
    :network.sta_connect(ssid: ssid, psk: psk)

    {:noreply, %{started | radio: :connecting, pending: {ssid, psk}}}
  end

  @impl true
  def handle_info(:connected, state) do
    :io.format(~c"Wifi: associated~n")

    {:noreply, %{state | radio: :connected, backoff: @first_backoff}}
  end

  def handle_info({:got_ip, info}, state) do
    :io.format(~c"Wifi: got ip ~p~n", [info])

    {:noreply, %{save(state) | radio: :connected}}
  end

  def handle_info({:scan_results, {_count, found}}, state) do
    networks = Network.usable(found)
    :io.format(~c"Wifi: scan found ~p networks~n", [length(networks)])

    {:noreply, %{state | scanning: false, networks: networks, scan_id: state.scan_id + 1}}
  end

  def handle_info({:scan_results, {:error, reason}}, state) do
    :io.format(~c"Wifi: scan failed, ~p~n", [reason])

    {:noreply, %{state | scanning: false, scan_id: state.scan_id + 1}}
  end

  def handle_info(:disconnected, state) do
    :io.format(~c"Wifi: dropped, retrying in ~pms~n", [state.backoff])
    retry_after(state.backoff)

    {:noreply, %{state | radio: :connecting}}
  end

  def handle_info(:retry, state) do
    :network.sta_connect()

    {:noreply, %{state | backoff: min(state.backoff * 2, @max_backoff)}}
  end

  def handle_info({:synchronized, _timeval}, state) do
    :io.format(~c"Wifi: clock synced~n")

    {:noreply, %{state | synced: true}}
  end

  # Credentials are only stored once they are known to work.
  defp save(%{pending: nil} = state), do: state

  defp save(%{pending: {ssid, psk}} = state) do
    Nvs.put(:wifi_ssid, ssid)
    Nvs.put(:wifi_psk, psk)
    :io.format(~c"Wifi: saved ~s~n", [ssid])

    %{state | pending: nil}
  end

  defp credentials do
    case {Nvs.get(:wifi_ssid), Nvs.get(:wifi_psk)} do
      {nil, _psk} -> nil
      {_ssid, nil} -> nil
      {ssid, psk} -> {ssid, psk}
    end
  end

  defp ensure_started(%{started: true} = state), do: state

  # Managed mode brings the driver up without associating, so scanning works
  # before any credentials exist.
  defp ensure_started(state) do
    wifi = self()

    sta =
      [
        :managed,
        {:scan_done, wifi},
        {:connected, fn -> send(wifi, :connected) end},
        {:got_ip, fn info -> send(wifi, {:got_ip, info}) end},
        {:disconnected, fn -> send(wifi, :disconnected) end}
      ] ++ configured_credentials()

    :network.start(
      sta: sta,
      sntp: [
        host: @sntp_host,
        synchronized: fn timeval -> send(wifi, {:synchronized, timeval}) end
      ]
    )

    %{state | started: true}
  end

  defp configured_credentials do
    case credentials() do
      nil -> []
      {ssid, psk} -> [{:ssid, ssid}, {:psk, psk}]
    end
  end

  # Sleeps in a linked process rather than using Process.send_after/3.
  defp retry_after(delay) do
    wifi = self()

    spawn_link(fn ->
      Process.sleep(delay)
      send(wifi, :retry)
    end)
  end
end
