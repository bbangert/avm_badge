defmodule Badge.Update.Link do
  @moduledoc """
  Keeps a NervesHub agent alive while the Update tab is on screen.

  `open/0` and `close/0` are the page's entry and exit. The agent is not
  started until the clock has synced: a shared-secret signature is refused if
  it was made more than ninety seconds ago, and a badge boots at the epoch.

  Updates and reboots are both manual, so the agent reports an offer and stops
  there. `install/0` starts the download in its own process and `reboot/0`
  restarts once it has landed. Nothing here happens without a keypress.

  There is no automatic rollback below this: a badge that boots into broken
  firmware stays there until `revert/0` is reached.
  """

  use GenServer

  alias Badge.Identity
  alias Badge.Nvs
  alias Badge.Wifi

  @compile {:no_warn_undefined, [:esp, :nh_flash, :nh_ota, NervesHubLink]}

  @host "devices.nervescloud.com"

  @tick 1_000

  # Long enough for the frame reporting a restart to leave the socket.
  @restart_grace 500

  def start_link(:ok), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Starts the agent, once wifi and the clock allow."
  @spec open() :: :ok
  def open, do: GenServer.cast(__MODULE__, :open)

  @doc "Stops the agent and abandons any download in flight."
  @spec close() :: :ok
  def close, do: GenServer.cast(__MODULE__, :close)

  @doc "Asks the hub whether there is anything, without reconnecting."
  @spec check() :: :ok
  def check, do: GenServer.cast(__MODULE__, :check)

  @doc "Downloads the offered update into the slot this badge is not running."
  @spec install() :: :ok
  def install, do: GenServer.cast(__MODULE__, :install)

  @doc "Restarts into the slot the update was written to."
  @spec reboot() :: :ok
  def reboot, do: GenServer.cast(__MODULE__, :reboot)

  @doc "Points the boot path back at the previous slot, then restarts."
  @spec revert() :: :ok
  def revert, do: GenServer.cast(__MODULE__, :revert)

  @doc "Where the link is, and what it knows about the firmware."
  @spec status() :: %{
          state: atom,
          percent: non_neg_integer,
          offer: binary | nil,
          reason: binary | nil,
          firmware: map | nil,
          slot: binary | nil,
          target: binary | nil,
          trial: boolean
        }
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(:ok) do
    state = %{
      agent: nil,
      want: false,
      state: :off,
      percent: 0,
      offer: nil,
      payload: nil,
      reason: nil,
      firmware: nil,
      slot: nil,
      target: nil,
      trial: false,
      download: nil
    }

    start_ticker()

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      state: state.state,
      percent: state.percent,
      offer: state.offer,
      reason: state.reason,
      firmware: state.firmware,
      slot: state.slot,
      target: state.target,
      trial: state.trial
    }

    {:reply, reply, state}
  end

  @impl true
  def handle_cast(:open, %{want: true} = state), do: {:noreply, state}

  def handle_cast(:open, state) do
    {:noreply, start_agent(describe(%{state | want: true, state: :waiting}))}
  end

  def handle_cast(:close, %{want: false} = state), do: {:noreply, state}

  def handle_cast(:close, state), do: {:noreply, stop_agent(state)}

  def handle_cast(:check, %{agent: nil} = state), do: {:noreply, state}

  def handle_cast(:check, state) do
    NervesHubLink.push(state.agent, "check_update", %{})

    {:noreply, state}
  end

  def handle_cast(:install, %{payload: nil} = state), do: {:noreply, state}

  def handle_cast(:install, %{state: :downloading} = state), do: {:noreply, state}

  def handle_cast(:install, state) do
    download = :nh_ota.start_update(state.payload, self(), %{})

    {:noreply, %{state | state: :downloading, percent: 0, download: download}}
  end

  def handle_cast(:reboot, state) do
    restart()

    {:noreply, state}
  end

  def handle_cast(:revert, state) do
    case :nh_ota.revert() do
      {:ok, previous} ->
        :io.format(~c"Update: reverting to ~s~n", [previous])

        restart()

        {:noreply, state}

      {:error, reason} ->
        {:noreply, %{state | state: :failed, reason: describe_reason(reason)}}
    end
  end

  @impl true
  def handle_info(:tick, state), do: {:noreply, start_agent(state)}

  def handle_info({:nerves_hub, event}, state), do: {:noreply, hub(event, state)}

  def handle_info({:nh_ota, _pid, {:progress, percent}}, state) do
    report(state, percent)

    {:noreply, %{state | percent: percent}}
  end

  def handle_info({:nh_ota, _pid, {:ok, slot}}, state) do
    :io.format(~c"Update: written to ~s~n", [slot])

    {:noreply, %{state | state: :ready, percent: 100, target: slot, download: nil}}
  end

  def handle_info({:nh_ota, _pid, {:error, reason}}, state) do
    :io.format(~c"Update: failed ~p~n", [reason])

    report_failure(state, reason)

    {:noreply, failed(state, reason)}
  end

  def handle_info(message, state) do
    :io.format(~c"Update: unhandled ~p~n", [message])

    {:noreply, state}
  end

  # The join reply carries an offer as well, so a badge that boots with one
  # waiting sees it without a second round trip.
  defp hub({:joined, response}, state) do
    :io.format(~c"Update: joined~n")

    offered(response, %{state | state: :current, reason: nil, trial: pending?()})
  end

  defp hub({:join_error, reason}, state), do: failed(state, reason)

  defp hub({:message, "update", payload}, state), do: offered(payload, state)

  defp hub({:disconnected, _reason}, %{want: true} = state) do
    %{state | state: :connecting}
  end

  defp hub({:transport_error, reason}, state), do: failed(state, reason)

  defp hub({:firmware_committed, _slot}, state), do: %{state | trial: false}

  defp hub(_event, state), do: state

  defp offered(payload, state) when is_map(payload) do
    case Map.get(payload, "update_available", false) do
      true -> %{state | state: :offered, payload: payload, offer: version(payload)}
      _none -> state
    end
  end

  defp offered(_response, state), do: state

  # NervesHub names the version in the firmware metadata it sends with the offer.
  defp version(payload) do
    case Map.get(payload, "firmware_meta") do
      %{"version" => version} when is_binary(version) -> version
      _absent -> "an update"
    end
  end

  defp start_agent(%{want: false} = state), do: state
  defp start_agent(%{agent: agent} = state) when agent != nil, do: state

  defp start_agent(state) do
    case credentials() do
      nil -> %{state | state: :unprovisioned}
      {key, secret} -> ready(Wifi.status(), key, secret, state)
    end
  end

  defp ready(%{radio: :connected, synced: true}, key, secret, state) do
    connect(key, secret, state)
  end

  defp ready(_status, _key, _secret, state), do: %{state | state: :waiting}

  defp connect(key, secret, state) do
    identifier = Identity.format(Identity.chip_id())

    :io.format(~c"Update: connecting as ~s~n", [identifier])

    options = [
      handler: self(),
      identifier: identifier,
      shared_secret: {key, secret},
      host: host(),
      updates: :manual,
      reboot: :manual
    ]

    case NervesHubLink.start(options) do
      {:ok, agent} ->
        %{state | agent: agent, state: :connecting, reason: nil}

      {:error, reason} ->
        :io.format(~c"Update: connect failed ~p~n", [reason])

        %{state | state: :failed, reason: describe_reason(reason)}
    end
  end

  defp stop_agent(%{agent: nil} = state), do: idle(state)

  defp stop_agent(state) do
    NervesHubLink.stop(state.agent)

    idle(state)
  end

  defp idle(state) do
    %{
      state
      | agent: nil,
        want: false,
        state: :off,
        percent: 0,
        offer: nil,
        payload: nil,
        download: nil
    }
  end

  defp failed(state, reason) do
    %{state | state: :failed, reason: describe_reason(reason), download: nil}
  end

  # Nothing to report if the agent is not there to report it.
  defp report(%{agent: nil}, _percent), do: :ok
  defp report(state, percent), do: NervesHubLink.update_progress(state.agent, percent)

  defp report_failure(%{agent: nil}, _reason), do: :ok

  defp report_failure(state, reason) do
    NervesHubLink.update_failed(state.agent, describe_reason(reason))
  end

  # Read once, off the render loop: this walks and hashes the whole partition.
  defp describe(state) do
    slot = :nh_flash.boot_partition()

    case :nh_flash.read_metadata() do
      {:ok, metadata} ->
        %{state | slot: slot, trial: pending?(), firmware: firmware(metadata)}

      {:error, reason} ->
        :io.format(~c"Update: no firmware metadata ~p~n", [reason])

        %{state | slot: slot, trial: pending?()}
    end
  end

  defp firmware(metadata) do
    %{
      name: field(metadata, :name, "unknown"),
      version: field(metadata, :version, "?"),
      sha: short(field(metadata, :sha256, ""))
    }
  end

  defp field(metadata, key, default) do
    case Map.get(metadata, key) do
      value when is_binary(value) -> value
      _absent -> default
    end
  end

  defp short(<<head::binary-8, _rest::binary>>), do: head
  defp short(sha), do: sha

  defp pending? do
    case :nh_ota.pending() do
      {:ok, _slot} -> true
      _none -> false
    end
  end

  defp credentials do
    case {Nvs.get(:nh_key), Nvs.get(:nh_secret)} do
      {key, secret} when is_binary(key) and is_binary(secret) -> {key, secret}
      _absent -> nil
    end
  end

  defp host do
    case Nvs.get(:nh_host) do
      host when is_binary(host) -> host
      _absent -> @host
    end
  end

  # A restart is immediate, so the frame saying why has to be given time to go.
  defp restart do
    Process.sleep(@restart_grace)

    :esp.restart()
  end

  defp describe_reason(reason) when is_binary(reason), do: reason
  defp describe_reason(reason), do: :erlang.iolist_to_binary(:io_lib.format(~c"~p", [reason]))

  defp start_ticker do
    link = self()

    spawn_link(fn -> tick_loop(link) end)
  end

  defp tick_loop(link) do
    Process.sleep(@tick)
    send(link, :tick)
    tick_loop(link)
  end
end
