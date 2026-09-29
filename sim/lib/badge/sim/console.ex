defmodule Badge.Sim.Console do
  @moduledoc """
  The console `Badge.Log` echoes to: passes every line on to the host's own
  console, keeps the most recent, and streams them to subscribed viewers.

  Start `Badge.Log` with `start_log/0` so its echo lands here.
  """

  use GenServer

  @keep 500

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Starts `Badge.Log` with this process as its console."
  def start_log do
    leader = Process.group_leader()
    Process.group_leader(self(), Process.whereis(__MODULE__))

    try do
      Badge.Log.start_link(:ok)
    after
      Process.group_leader(self(), leader)
    end
  end

  @doc "Sends `pid` `{:log, lines}` for every line from now on, starting with the kept ones."
  def subscribe(pid), do: GenServer.cast(__MODULE__, {:subscribe, pid})

  @impl true
  def init(:ok), do: {:ok, %{host: Process.group_leader(), lines: [], viewers: [], partial: ""}}

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    send(pid, {:log, Enum.reverse(state.lines)})
    {:noreply, %{state | viewers: [pid | state.viewers]}}
  end

  @impl true
  def handle_info({:io_request, from, ref, request}, state) do
    {reply, state} = request(request, state)
    send(from, {:io_reply, ref, reply})
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | viewers: List.delete(state.viewers, pid)}}
  end

  defp request({:put_chars, _encoding, chars}, state), do: {:ok, write(chars, state)}
  defp request({:put_chars, chars}, state), do: {:ok, write(chars, state)}

  defp request({:put_chars, _encoding, module, function, args}, state),
    do: {:ok, write(apply(module, function, args), state)}

  defp request({:requests, requests}, state) do
    Enum.reduce(requests, {:ok, state}, fn request, {_reply, acc} -> request(request, acc) end)
  end

  defp request(_other, state), do: {{:error, :request}, state}

  defp write(chars, state) do
    IO.write(state.host, chars)

    [partial | lines] =
      (state.partial <> IO.chardata_to_string(chars))
      |> String.split("\n")
      |> Enum.reverse()

    lines = Enum.reverse(lines)
    for viewer <- state.viewers, lines != [], do: send(viewer, {:log, lines})

    %{state | lines: Enum.take(Enum.reverse(lines) ++ state.lines, @keep), partial: partial}
  end
end
